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
import { normalizeProviderEndpoint, providerCredentialID } from "./services/provider-client";
import { StudySessionStore } from "./services/session-store";
import { extractSearchDocument } from "./services/document-indexer";
import { SearchIndexClient } from "./search-index-worker/client";
import { makeSearchIndexUtilityProcessSpawner } from "./search-index-worker/electron-process";
import { COURSE_SEARCH_INDEX_FILE_NAME } from "./services/search-index-schema";
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
  }

  static async open(options: WeiBeiControllerOptions): Promise<WeiBeiController> {
    const [state, sessions] = await Promise.all([
      AppStateStore.open({ userDataPath: options.userDataPath, defaultLibraryRootPath: options.defaultLibraryRootPath }),
      StudySessionStore.open(path.join(options.userDataPath, "Workspace")),
    ]);
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
    await Promise.allSettled([this.searchIndex.close(), this.agent.dispose()]);
  }

  onLibraryChanged(listener: (snapshot: AppSnapshot) => void): () => void {
    this.libraryChangeListeners.add(listener);
    return () => this.libraryChangeListeners.delete(listener);
  }

  async bootstrap(): Promise<AppSnapshot> { return this.snapshot(); }

  async chooseLibraryRoot(): Promise<AppSnapshot | null> {
    const result = await dialog.showOpenDialog(this.options.window, {
      title: "选择魏碑资料库",
      buttonLabel: "使用这个文件夹",
      properties: ["openDirectory", "createDirectory"],
    });
    if (result.canceled || result.filePaths.length !== 1) return null;
    const next = new CourseLibrary({ rootPath: result.filePaths[0], sessionsForCourse: (id) => this.sessions.listForCourse(id) });
    await next.ensureLayout();
    await this.stopLibraryWatcher();
    await this.state.setLibraryRoot(next.rootPath);
    this.library = next;
    await this.startLibraryWatcher();
    return this.snapshot();
  }

  async createCourse(title: string): Promise<AppSnapshot> {
    const summary = await this.library.createCourse(title);
    await this.state.setActiveCourse(summary.id);
    return this.snapshot();
  }

  async adoptCourseFolder(): Promise<AppSnapshot | null> {
    const result = await dialog.showOpenDialog(this.options.window, {
      title: "收录现有课程文件夹",
      buttonLabel: "收录课程",
      properties: ["openDirectory"],
    });
    if (result.canceled || result.filePaths.length !== 1) return null;
    const selected = path.resolve(result.filePaths[0]);
    const parentLibrary = new CourseLibrary({ rootPath: path.dirname(selected), sessionsForCourse: (id) => this.sessions.listForCourse(id) });
    const matching = (await parentLibrary.listCourses()).find((course) => path.resolve(course.rootPath) === selected);
    if (!matching) throw new Error("所选文件夹不是可验证的魏碑课程（缺少 .weibei/course.json 或 portable state）。");
    if (path.resolve(parentLibrary.rootPath) !== path.resolve(this.library.rootPath)) {
      await this.stopLibraryWatcher();
      await this.state.setLibraryRoot(parentLibrary.rootPath);
      this.library = parentLibrary;
      await this.startLibraryWatcher();
    }
    await this.state.setActiveCourse(matching.id);
    return this.snapshot();
  }

  async selectCourse(courseID: string): Promise<AppSnapshot> { await this.state.setActiveCourse(courseID); return this.snapshot(); }

  async importItems(courseID: string): Promise<AppSnapshot> {
    const selected = await dialog.showOpenDialog(this.options.window, {
      title: "导入课程文稿",
      buttonLabel: "导入",
      properties: ["openFile", "multiSelections"],
      filters: [{ name: "支持的文稿", extensions: ["pdf", "html", "htm", "md", "markdown", "txt", "text"] }],
    });
    if (selected.canceled || selected.filePaths.length === 0) return this.snapshot();
    const items = await this.library.importFiles(courseID, selected.filePaths);
    if (items[0]) await this.state.setActiveItem(courseID, items[0].id);
    return this.snapshot();
  }

  async createNote(courseID: string, title: string): Promise<AppSnapshot> {
    const note = await this.library.createNote(courseID, title);
    await this.state.setActiveNote(courseID, note.id);
    return this.snapshot();
  }

  async openItem(courseID: string, itemID: string) {
    const opened = await this.library.openItem(courseID, itemID);
    if (opened.payload.item.isNotebookNote) await this.state.setActiveNote(courseID, itemID);
    else await this.state.setActiveItem(courseID, itemID);
    const grant = opened.payload.mediaType === "application/pdf"
      ? await this.options.grants.issue({ rootPath: this.library.rootPath, filePath: opened.absolutePath, scope: this.options.rendererScope, mediaType: opened.payload.mediaType })
      : null;
    return { ...opened.payload, documentGrantUrl: grant?.url ?? null };
  }

  async saveNote(request: SaveNoteRequest): Promise<SaveNoteResult> {
    const filePath = await this.library.resolveItemPath(request.courseId, request.itemId);
    const result = await this.noteGate.write({ itemId: request.itemId, filePath, markdown: request.markdown, baselineDigest: request.baselineDigest });
    if (result.status === "saved" && result.digest) {
      await this.noteRecovery.clear(request.itemId).catch(() => undefined);
      await this.indexItem(request.courseId, request.itemId, result.digest).catch(() => undefined);
    }
    return SaveNoteResultSchema.parse(result);
  }

  async loadNoteRecovery(itemID: string): Promise<NoteRecoveryRecord | null> {
    return this.noteRecovery.load(itemID);
  }

  async saveNoteRecovery(
    input: Pick<NoteRecoveryRecord, "itemId" | "markdown" | "baselineDigest">,
  ): Promise<NoteRecoveryRecord> {
    return this.noteRecovery.save(input);
  }

  async clearNoteRecovery(itemID: string): Promise<void> {
    await this.noteRecovery.clear(itemID);
  }

  async updatePreferences(patch: Partial<Preferences>): Promise<Preferences> {
    const sanitized = PreferencesSchema.partial().parse(patch);
    return this.state.updatePreferences(sanitized);
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
    const session = await this.sessions.create(courseID);
    await this.state.setActiveSession(courseID, session.id);
    return session;
  }

  async selectSession(courseID: string, sessionID: string): Promise<AppSnapshot> {
    await this.state.setActiveSession(courseID, sessionID);
    return this.snapshot();
  }

  async startAgent(request: AgentStartRequest): Promise<{ requestId: string }> {
    const session = await this.sessions.get(request.sessionId);
    if (!session || session.courseId !== request.courseId) throw new Error("agent-session-course-mismatch");
    const retrieval = await this.buildAgentContext(request);
    return this.agent.start(request, retrieval.context, retrieval.sources);
  }

  async saveProvider(config: { providerId: string; model: string; baseUrl: string; apiKey?: string }): Promise<ProviderPublicConfig> {
    const baseURL = normalizeProviderEndpoint(config.baseUrl).toString().replace(/\/$/u, "");
    const providerID = config.providerId.trim();
    const model = config.model.trim();
    if (!providerID || !model) throw new Error("供应商和模型不能为空。");
    const credentialID = providerCredentialID(providerID, baseURL);
    if (config.apiKey !== undefined) await this.options.vault.setSecret(credentialID, config.apiKey);
    const provider = ProviderPublicConfigSchema.parse({
      providerId: providerID,
      model,
      baseUrl: baseURL,
      hasCredential: await this.options.vault.hasSecret(credentialID),
    });
    return this.state.updateProvider(provider);
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

  private async snapshot(): Promise<AppSnapshot> {
    const local = this.state.snapshot();
    const courses = await this.library.listCourses();
    const activeID = courses.some((course) => course.id === local.activeCourseId) ? local.activeCourseId : courses[0]?.id ?? null;
    if (activeID !== local.activeCourseId) await this.state.setActiveCourse(activeID);
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
    return new CourseLibrary({ rootPath, sessionsForCourse: (id) => this.sessions.listForCourse(id) });
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
      const next = await this.snapshot();
      for (const listener of this.libraryChangeListeners) listener(next);
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
