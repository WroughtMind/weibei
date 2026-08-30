import { randomUUID } from "node:crypto";
import path from "node:path";
import { dialog, shell, type BrowserWindow } from "electron";
import {
  AppSnapshotSchema,
  PreferencesSchema,
  ProviderPublicConfigSchema,
  SaveNoteResultSchema,
  type AppSnapshot,
  type AgentStartRequest,
  type Citation,
  type NoteRecoveryRecord,
  type NoteRecoverySaveInput,
  type NoteRecoveryTarget,
  type Preferences,
  type ProviderPublicConfig,
  type SaveNoteRequest,
  type SaveNoteResult,
  type SearchRequest,
  type SearchResult,
  type StudySession,
} from "../shared/contracts";
import { AgentRuntime } from "./services/agent-runtime";
import { makeAgentUtilityProcessSpawner } from "./agent-worker/electron-process";
import { formatAgentContext } from "./agent-worker/context";
import { AppStateStore } from "./services/app-state";
import { CourseLibrary } from "./services/course-library";
import type { CredentialVault } from "./services/credential-vault";
import type { DocumentGrantService } from "./services/document-grants";
import { NoteWriteGate } from "./services/note-write-gate";
import { NoteRecoveryStore } from "./services/note-recovery-store";
import {
  consumeLegacyProviderCredentialOnUpgrade,
  deleteLegacyUnboundProviderCredential,
  hasEndpointBoundProviderCredential,
  normalizeProviderEndpoint,
  providerCredentialID,
} from "./services/provider-client";
import { StudySessionStore } from "./services/session-store";
import { extractSearchDocument } from "./services/document-indexer";
import { SearchIndexClient } from "./search-index-worker/client";
import { makeSearchIndexUtilityProcessSpawner } from "./search-index-worker/electron-process";
import { COURSE_SEARCH_INDEX_FILE_NAME } from "./services/search-index-schema";
import { LatestOperationGate } from "../shared/latest-operation-gate";
import { LatestSerialOperationGate } from "../shared/latest-serial-operation-gate";
import { SnapshotPublicationGate } from "./snapshot-publication-gate";
import chokidar, { type FSWatcher } from "chokidar";

export interface WeiBeiControllerOptions {
  window: BrowserWindow;
  appVersion: string;
  userDataPath: string;
  localDataPath: string;
  defaultLibraryRootPath: string;
  rendererScope: string;
  grants: DocumentGrantService;
  vault: CredentialVault;
}

export class WeiBeiController {
  readonly state: AppStateStore;
  readonly sessions: StudySessionStore;
  readonly noteGate: NoteWriteGate;
  readonly noteRecovery: NoteRecoveryStore;
  readonly agent: AgentRuntime;
  readonly searchIndex: SearchIndexClient;
  private library: CourseLibrary;
  private libraryWatcher: FSWatcher | null = null;
  private libraryChangeTimer: NodeJS.Timeout | null = null;
  private readonly openItemGate = new LatestOperationGate();
  private readonly libraryNavigationGate = new LatestSerialOperationGate();
  private readonly snapshotPublicationGate = new SnapshotPublicationGate();
  private readonly stopAgentPublicationInvalidation: () => void;
  private readonly libraryChangeListeners = new Set<(snapshot: AppSnapshot) => void>();

  private constructor(
    private readonly options: WeiBeiControllerOptions,
    state: AppStateStore,
    sessions: StudySessionStore,
    searchIndex: SearchIndexClient,
  ) {
    this.state = state;
    this.sessions = sessions;
    this.noteGate = new NoteWriteGate({ backupRootPath: path.join(options.localDataPath, "NoteBackups") });
    this.noteRecovery = new NoteRecoveryStore({ userDataPath: options.userDataPath });
    this.searchIndex = searchIndex;
    this.library = this.makeLibrary(state.snapshot().libraryRootPath);
    this.agent = new AgentRuntime({
      sessions,
      vault: options.vault,
      provider: () => this.state.snapshot().provider,
      ledgerRoot: path.join(options.userDataPath, "NativeAgent", "Ledgers"),
      spawnWorker: makeAgentUtilityProcessSpawner(),
    });
    // AgentRuntime owns the session-file writes for a turn. Subscribe before
    // IPC forwarding is registered so a persisted start/terminal event always
    // invalidates an older watcher snapshot first.
    this.stopAgentPublicationInvalidation = this.agent.onEvent((event) => {
      if (event.type === "started"
          || event.type === "completed"
          || event.type === "failed"
          || event.type === "cancelled") {
        this.snapshotPublicationGate.invalidate();
      }
    });
  }

  static async open(options: WeiBeiControllerOptions): Promise<WeiBeiController> {
    const [state, sessions] = await Promise.all([
      AppStateStore.open({ userDataPath: options.userDataPath, defaultLibraryRootPath: options.defaultLibraryRootPath }),
      StudySessionStore.open(path.join(options.userDataPath, "Workspace")),
    ]);
    const storedProvider = state.snapshot().provider;
    const hasCredential = await consumeLegacyProviderCredentialOnUpgrade(
      options.vault,
      storedProvider.providerId,
      storedProvider.baseUrl,
    );
    if (storedProvider.hasCredential !== hasCredential) {
      await state.updateProvider({ ...storedProvider, hasCredential });
    }
    const searchIndex = await SearchIndexClient.open({
      dbPath: path.join(options.localDataPath, "CourseIndex", COURSE_SEARCH_INDEX_FILE_NAME),
      spawnWorker: makeSearchIndexUtilityProcessSpawner(),
    });
    const controller = new WeiBeiController(options, state, sessions, searchIndex);
    try {
      await controller.library.ensureLayout();
      await controller.startLibraryWatcher();
      return controller;
    } catch (error) {
      await controller.close();
      throw error;
    }
  }

  async close(): Promise<void> {
    if (this.libraryChangeTimer) clearTimeout(this.libraryChangeTimer);
    this.libraryChangeTimer = null;
    await this.libraryWatcher?.close().catch(() => undefined);
    this.libraryWatcher = null;
    this.stopAgentPublicationInvalidation();
    await Promise.allSettled([this.searchIndex.close(), this.agent.dispose()]);
  }

  onLibraryChanged(listener: (snapshot: AppSnapshot) => void): () => void {
    this.libraryChangeListeners.add(listener);
    return () => this.libraryChangeListeners.delete(listener);
  }

  async bootstrap(): Promise<AppSnapshot> { return this.snapshot(); }

  async chooseLibraryRoot(): Promise<AppSnapshot | null> {
    return this.runSnapshotMutation(async () => {
      const result = await dialog.showOpenDialog(this.options.window, {
        title: "选择魏碑资料库",
        buttonLabel: "使用这个文件夹",
        properties: ["openDirectory", "createDirectory"],
      });
      if (result.canceled || result.filePaths.length !== 1) return null;
      const ticket = this.libraryNavigationGate.begin();
      return this.libraryNavigationGate.run(async () => {
        if (!this.libraryNavigationGate.isLatest(ticket)) return null;
        const next = this.makeLibrary(result.filePaths[0]);
        await next.ensureLayout();
        if (!this.libraryNavigationGate.isLatest(ticket)) return null;
        await this.stopLibraryWatcher();
        this.library = next;
        try {
          await this.state.setLibraryRoot(next.rootPath);
        } finally {
          await this.startLibraryWatcher();
        }
        if (!this.libraryNavigationGate.isLatest(ticket)) return null;
        const snapshot = await this.snapshotUnlocked();
        return this.libraryNavigationGate.isLatest(ticket) ? snapshot : null;
      });
    });
  }

  async createCourse(title: string): Promise<AppSnapshot> {
    return this.runSnapshotMutation(() => this.libraryNavigationGate.run(async () => {
      const summary = await this.library.createCourse(title);
      await this.state.setActiveCourse(summary.id);
      return this.snapshotUnlocked();
    }));
  }

  async adoptCourseFolder(): Promise<AppSnapshot | null> {
    return this.runSnapshotMutation(async () => {
      const result = await dialog.showOpenDialog(this.options.window, {
        title: "收录现有课程文件夹",
        buttonLabel: "收录课程",
        properties: ["openDirectory"],
      });
      if (result.canceled || result.filePaths.length !== 1) return null;
      const selected = path.resolve(result.filePaths[0]);
      const ticket = this.libraryNavigationGate.begin();
      return this.libraryNavigationGate.run(async () => {
        if (!this.libraryNavigationGate.isLatest(ticket)) return null;
        const parentLibrary = this.makeLibrary(path.dirname(selected));
        const courses = await parentLibrary.listCourses();
        if (!this.libraryNavigationGate.isLatest(ticket)) return null;
        const matching = courses.find((course) => path.resolve(course.rootPath) === selected);
        if (!matching) throw new Error("所选文件夹不是可验证的魏碑课程（缺少 .weibei/course.json 或 portable state）。");
        const changesLibrary = path.resolve(parentLibrary.rootPath) !== path.resolve(this.library.rootPath);
        await (changesLibrary ? parentLibrary : this.library)
          .ensureLegacySessionsExternalized(matching.id);
        if (!this.libraryNavigationGate.isLatest(ticket)) return null;
        if (changesLibrary) {
          await this.stopLibraryWatcher();
          this.library = parentLibrary;
          try {
            await this.state.setLibraryRoot(parentLibrary.rootPath);
          } finally {
            await this.startLibraryWatcher();
          }
        }
        if (!this.libraryNavigationGate.isLatest(ticket)) return null;
        await this.state.setActiveCourse(matching.id);
        if (!this.libraryNavigationGate.isLatest(ticket)) return null;
        const snapshot = await this.snapshotUnlocked();
        return this.libraryNavigationGate.isLatest(ticket) ? snapshot : null;
      });
    });
  }

  async selectCourse(courseID: string): Promise<AppSnapshot> {
    return this.runSnapshotMutation(async () => {
      const ticket = this.libraryNavigationGate.begin();
      const selected = await this.libraryNavigationGate.run(async () => {
        if (!this.libraryNavigationGate.isLatest(ticket)) return null;
        await this.library.ensureLegacySessionsExternalized(courseID);
        if (!this.libraryNavigationGate.isLatest(ticket)) return null;
        await this.state.setActiveCourse(courseID);
        if (!this.libraryNavigationGate.isLatest(ticket)) return null;
        const snapshot = await this.snapshotUnlocked();
        return this.libraryNavigationGate.isLatest(ticket) ? snapshot : null;
      });
      return selected ?? this.snapshot();
    });
  }

  async importItems(courseID: string): Promise<AppSnapshot> {
    return this.runSnapshotMutation(async () => {
      const selected = await dialog.showOpenDialog(this.options.window, {
        title: "导入课程文稿",
        buttonLabel: "导入",
        properties: ["openFile", "multiSelections"],
        filters: [{ name: "支持的文稿", extensions: ["pdf", "html", "htm", "md", "markdown", "txt", "text"] }],
      });
      if (selected.canceled || selected.filePaths.length === 0) return this.snapshot();
      return this.libraryNavigationGate.run(async () => {
        const items = await this.library.importFiles(courseID, selected.filePaths);
        if (items[0]) await this.state.setActiveItem(courseID, items[0].id);
        return this.snapshotUnlocked();
      });
    });
  }

  async createNote(courseID: string, title: string): Promise<AppSnapshot> {
    return this.runSnapshotMutation(() => this.libraryNavigationGate.run(async () => {
      const note = await this.library.createNote(courseID, title);
      await this.state.setActiveNote(courseID, note.id);
      return this.snapshotUnlocked();
    }));
  }

  async openItem(courseID: string, itemID: string) {
    const ticket = this.openItemGate.begin();
    return this.runSnapshotMutation(() => this.libraryNavigationGate.run(async () => {
      const opened = await this.library.openItem(courseID, itemID);
      if (this.openItemGate.isLatest(ticket)) {
        if (opened.payload.item.isNotebookNote) await this.state.setActiveNote(courseID, itemID);
        else await this.state.setActiveItem(courseID, itemID);
      }
      const grant = opened.payload.mediaType === "application/pdf"
        ? await this.options.grants.issue({ rootPath: this.library.rootPath, filePath: opened.absolutePath, scope: this.options.rendererScope, mediaType: opened.payload.mediaType })
        : null;
      return { ...opened.payload, documentGrantUrl: grant?.url ?? null };
    }));
  }

  async saveNote(request: SaveNoteRequest): Promise<SaveNoteResult> {
    return this.runSnapshotMutation(() => this.libraryNavigationGate.run(async () => {
      const filePath = await this.library.resolveItemPath(request.courseId, request.itemId);
      const result = await this.noteGate.write({ itemId: request.itemId, filePath, markdown: request.markdown, baselineDigest: request.baselineDigest });
      if (result.status === "saved" && result.digest) {
        await this.noteRecovery.clear({
          libraryRootPath: this.library.rootPath,
          courseId: request.courseId,
          itemId: request.itemId,
        }).catch(() => undefined);
        await this.indexItem(request.courseId, request.itemId, result.digest).catch(() => undefined);
      }
      return SaveNoteResultSchema.parse(result);
    }));
  }

  async loadNoteRecovery(target: NoteRecoveryTarget): Promise<NoteRecoveryRecord | null> {
    return this.libraryNavigationGate.run(
      () => this.noteRecovery.load(this.noteRecoveryScope(target)),
    );
  }

  async saveNoteRecovery(input: NoteRecoverySaveInput): Promise<NoteRecoveryRecord> {
    return this.libraryNavigationGate.run(
      () => this.noteRecovery.save({ ...input, ...this.noteRecoveryScope(input) }),
    );
  }

  async clearNoteRecovery(target: NoteRecoveryTarget): Promise<void> {
    await this.libraryNavigationGate.run(
      () => this.noteRecovery.clear(this.noteRecoveryScope(target)),
    );
  }

  async updatePreferences(patch: Partial<Preferences>): Promise<Preferences> {
    const sanitized = PreferencesSchema.partial().parse(patch);
    return this.runSnapshotMutation(() => this.libraryNavigationGate.run(
      () => this.state.updatePreferences(sanitized),
    ));
  }

  async search(request: SearchRequest): Promise<SearchResult[]> {
    const detail = await this.library.detail(request.courseId);
    for (const item of detail.items) {
      if (!item.contentDigest) continue;
      const coverage = await this.searchIndex.coverage(item.id);
      if (coverage?.signature === item.contentDigest) continue;
      await this.indexItem(request.courseId, item.id, item.contentDigest).catch(() => undefined);
    }
    const itemByID = new Map(detail.items.map((item) => [item.id, item]));
    const hits = await this.searchIndex.search(request.query, {
      itemIds: detail.items.map((item) => item.id),
      limit: request.limit,
    });
    return hits.flatMap((hit): SearchResult[] => {
      const item = itemByID.get(hit.itemId);
      if (!item) return [];
      return [{
        itemId: item.id,
        title: item.title,
        kind: item.kind,
        excerpt: hit.excerpt,
        rank: hit.rank,
      }];
    });
  }

  async createSession(courseID: string): Promise<StudySession> {
    return this.runSnapshotMutation(() => this.libraryNavigationGate.run(async () => {
      const session = await this.sessions.create(courseID);
      await this.state.setActiveSession(courseID, session.id);
      return session;
    }));
  }

  async selectSession(courseID: string, sessionID: string): Promise<AppSnapshot> {
    return this.runSnapshotMutation(() => this.libraryNavigationGate.run(async () => {
      await this.state.setActiveSession(courseID, sessionID);
      return this.snapshotUnlocked();
    }));
  }

  async startAgent(request: AgentStartRequest): Promise<{ requestId: string }> {
    return this.runSnapshotMutation(() => this.libraryNavigationGate.run(async () => {
      const session = await this.sessions.get(request.sessionId);
      if (!session || session.courseId !== request.courseId) throw new Error("agent-session-course-mismatch");
      const retrieval = await this.buildAgentContext(request);
      return this.agent.start(request, retrieval.context, retrieval.sources);
    }));
  }

  async saveProvider(config: { providerId: string; model: string; baseUrl: string; apiKey?: string }): Promise<ProviderPublicConfig> {
    return this.runSnapshotMutation(() => this.libraryNavigationGate.run(async () => {
      const baseURL = normalizeProviderEndpoint(config.baseUrl).toString().replace(/\/$/u, "");
      const providerID = config.providerId.trim();
      const model = config.model.trim();
      if (!providerID || !model) throw new Error("供应商和模型不能为空。");
      const credentialID = providerCredentialID(providerID, baseURL);
      if (config.apiKey !== undefined) await this.options.vault.setSecret(credentialID, config.apiKey);
      await deleteLegacyUnboundProviderCredential(this.options.vault, providerID);
      const hasCredential = await hasEndpointBoundProviderCredential(
        this.options.vault,
        providerID,
        baseURL,
      );
      const provider = ProviderPublicConfigSchema.parse({
        providerId: providerID,
        model,
        baseUrl: baseURL,
        hasCredential,
      });
      return this.state.updateProvider(provider);
    }));
  }

  async revealItem(courseID: string, itemID: string): Promise<void> {
    await shell.showItemInFolder(await this.library.resolveItemPath(courseID, itemID));
  }

  async applyNoteProposal(
    _courseID?: string,
    _sessionID?: string,
    _messageID?: string,
    _actionID?: string,
  ): Promise<AppSnapshot> {
    // Proposals are only executable when a persisted action contains an exact
    // note baseline; the initial provider loop does not fabricate write actions.
    throw new Error("这条回答没有可验证的笔记写入建议。");
  }

  private async runSnapshotMutation<T>(operation: () => Promise<T>): Promise<T> {
    const finishMutation = this.snapshotPublicationGate.beginMutation();
    try {
      return await operation();
    } finally {
      finishMutation();
    }
  }

  private noteRecoveryScope(target: NoteRecoveryTarget) {
    if (!sameLibraryRootPath(target.libraryRootPath, this.library.rootPath)) {
      throw new Error("stale-note-recovery-library");
    }
    return {
      libraryRootPath: this.library.rootPath,
      courseId: target.courseId,
      itemId: target.itemId,
    };
  }

  private snapshot(): Promise<AppSnapshot> {
    return this.libraryNavigationGate.run(() => this.snapshotUnlocked());
  }

  private async snapshotUnlocked(): Promise<AppSnapshot> {
    for (;;) {
      const generation = this.snapshotPublicationGate.captureGeneration();
      const snapshot = await this.buildSnapshotUnlocked();
      if (this.snapshotPublicationGate.isGenerationCurrent(generation)) return snapshot;
      // Agent terminal persistence is not owned by controller navigation. If
      // it completed while sessions were being read, rebuild in this same
      // serial section so the explicit IPC response cannot erase the event.
    }
  }

  private async buildSnapshotUnlocked(): Promise<AppSnapshot> {
    const local = this.state.snapshot();
    const courses = await this.library.listCourses();
    const activeID = courses.some((course) => course.id === local.activeCourseId) ? local.activeCourseId : courses[0]?.id ?? null;
    if (activeID !== local.activeCourseId) await this.state.setActiveCourse(activeID);
    if (activeID) await this.library.ensureLegacySessionsExternalized(activeID);
    const activeCourse = activeID
      ? await this.library.detail(activeID, {
          activeItemId: local.activeItemsByCourse[activeID] ?? null,
          activeNoteId: local.activeNotesByCourse[activeID] ?? null,
          activeSessionId: local.activeSessionsByCourse[activeID] ?? null,
        })
      : null;
    return AppSnapshotSchema.parse({
      courses,
      activeCourse,
      preferences: local.preferences,
      provider: local.provider,
      libraryRootPath: local.libraryRootPath,
      platform: "windows",
      appVersion: this.options.appVersion,
    });
  }

  private makeLibrary(rootPath: string) {
    return new CourseLibrary({
      rootPath,
      sessionsForCourse: (id) => this.sessions.listForCourse(id),
      migrateLegacySessions: (id, sessions, context) =>
        this.sessions.migrateLegacyCourseSessions(id, sessions, context),
    });
  }

  private async startLibraryWatcher(): Promise<void> {
    await this.stopLibraryWatcher();
    this.libraryWatcher = chokidar.watch(this.library.rootPath, {
      ignoreInitial: true,
      awaitWriteFinish: { stabilityThreshold: 180, pollInterval: 50 },
      ignorePermissionErrors: true,
    });
    const markChanged = () => {
      if (this.libraryChangeTimer) clearTimeout(this.libraryChangeTimer);
      this.libraryChangeTimer = setTimeout(() => {
        this.libraryChangeTimer = null;
        void this.publishLibrarySnapshot();
      }, 180);
    };
    this.libraryWatcher.on("add", markChanged);
    this.libraryWatcher.on("change", markChanged);
    this.libraryWatcher.on("unlink", markChanged);
    this.libraryWatcher.on("addDir", markChanged);
    this.libraryWatcher.on("unlinkDir", markChanged);
  }

  private async stopLibraryWatcher(): Promise<void> {
    if (this.libraryChangeTimer) clearTimeout(this.libraryChangeTimer);
    this.libraryChangeTimer = null;
    const watcher = this.libraryWatcher;
    this.libraryWatcher = null;
    await watcher?.close().catch(() => undefined);
  }

  private async publishLibrarySnapshot(): Promise<void> {
    try {
      while (this.libraryChangeListeners.size > 0) {
        const publicationGeneration = await this.snapshotPublicationGate.captureWhenIdle();
        const navigationTicket = this.libraryNavigationGate.capture();
        const next = await this.libraryNavigationGate.run(() => this.snapshotUnlocked());
        if (!this.snapshotPublicationGate.isCurrent(publicationGeneration)
            || !this.libraryNavigationGate.isLatest(navigationTicket)) {
          // A mutation began after the read was authorized. Wait until all
          // active mutations finish, then rebuild instead of publishing stale
          // local selections, sessions, preferences, or provider state.
          continue;
        }
        for (const listener of this.libraryChangeListeners) listener(next);
        return;
      }
    } catch {
      // A transient external write is picked up by the next filesystem event.
    }
  }

  private async buildAgentContext(request: AgentStartRequest): Promise<{ context: string; sources: Citation[] }> {
    const detail = await this.library.detail(request.courseId);
    const itemByID = new Map(detail.items.map((item) => [item.id, item]));
    const selection = request.selection && itemByID.has(request.selection.itemId)
      ? request.selection.text.slice(0, 8_000)
      : null;
    const hits = await this.search({
      courseId: request.courseId,
      query: request.question,
      limit: 10,
    }).catch(() => []);
    const sources = hits.map((hit, index): Citation => ({
      id: randomUUID(),
      itemId: hit.itemId,
      courseId: request.courseId,
      kind: itemByID.get(hit.itemId)?.isNotebookNote ? "note" : "material",
      title: hit.title,
      label: String(index + 1),
      excerpt: hit.excerpt,
      pageIndex: null,
      sectionTitle: null,
      sectionLocationId: null,
    }));
    return { context: formatAgentContext({ selection, hits }), sources };
  }

  private async indexItem(courseID: string, itemID: string, signature: string): Promise<void> {
    const opened = await this.library.openItem(courseID, itemID);
    const extracted = await extractSearchDocument({
      itemId: itemID,
      signature,
      kind: opened.payload.item.kind,
      filePath: opened.absolutePath,
    });
    await this.searchIndex.upsertTextChunks(extracted);
  }
}

function sameLibraryRootPath(left: string, right: string): boolean {
  const normalize = (value: string) => {
    const resolved = path.resolve(value).normalize("NFC");
    return process.platform === "win32"
      ? resolved.toLocaleLowerCase("en-US")
      : resolved;
  };
  return normalize(left) === normalize(right);
}
