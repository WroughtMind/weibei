import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import type {
  AppSnapshot,
  DocumentPayload,
  PaneRole,
  Preferences,
  SaveNoteResult,
  SelectionContext,
  WeiBeiDesktopAPI,
} from "../shared/contracts";
import { ExclusiveOperationGate, LatestOperationGate } from "../shared/latest-operation-gate";
import {
  activateOpenedItem,
  applyAgentEvent,
  applyAgentRequestEvent,
  hydratedNoteSaveTarget,
  isTerminalAgentEvent,
  noteHydrationDisposition,
  noteRecoveryFlushAction,
  replaceAgentMessageText,
  replaceSnapshotPreferences,
  replaceSnapshotProvider,
  saveRequestForProtectedNoteDraft,
  sameHydratedNoteTarget,
  shouldAcceptOpenedItemResult,
  snapshotKeepsHydratedEditor,
  type HydratedNoteTarget,
  type ProtectedNoteDraft,
  type TerminalAgentEvent,
} from "./app-state";
import { CourseSpace } from "./components/CourseSpace";
import { EmptyLauncher } from "./components/EmptyLauncher";
import { LibraryDrawer } from "./components/LibraryDrawer";
import { NamePromptSheet } from "./components/NamePromptSheet";
import { SettingsSheet } from "./components/SettingsSheet";
import { SearchPalette } from "./components/SearchPalette";
import { TopBar } from "./components/TopBar";
import { ThreePaneWorkspace } from "./components/ThreePaneWorkspace";
import type { CanonicalNoteEditorHandle } from "./components/panes/CanonicalNoteEditor";
import { PostCommitReleaseQueue } from "./note-snapshot-flush";
import { NoteRecoveryWriteEpochGate } from "./note-recovery-write-epoch";
import { AgentStreamDisplayPump } from "./stream-display-pump";
import { ProtectedWindowUnloadGuard } from "./protected-window-unload";

type Overlay = "course" | "search" | "settings" | null;
type ItemOpenTarget = "reader" | "notes" | "auto";
type SnapshotCommitValue = AppSnapshot | null | ((current: AppSnapshot) => AppSnapshot);
type NoteProtectionResult =
  | { ok: false }
  | { ok: true; note: ProtectedNoteDraft | null; release(): void };
type NamePrompt =
  | { kind: "course"; closeLibrary: boolean }
  | { kind: "note"; closeLibrary: boolean; courseId: string };

const defaultPreferences: Preferences = {
  theme: "paper",
  language: "zh-Hans",
  textScale: 1,
  glassIntensity: 1,
  reduceMotion: false,
  paneOrder: ["reader", "agent", "notes"],
  visiblePanes: ["reader", "agent", "notes"],
  paneWidths: { reader: 1, agent: 1, notes: 1 },
};

const fallbackSnapshot: AppSnapshot = {
  courses: [],
  activeCourse: null,
  preferences: defaultPreferences,
  provider: {
    providerId: "openai",
    model: "gpt-5.4",
    baseUrl: "https://api.openai.com/v1",
    hasCredential: false,
  },
  libraryRootPath: "",
  platform: "windows",
  appVersion: "1.0.0",
};

export function App() {
  const [snapshot, setSnapshot] = useState<AppSnapshot | null>(null);
  const [document, setDocument] = useState<DocumentPayload | null>(null);
  const [noteDraft, setNoteDraft] = useState("");
  const [noteBaseline, setNoteBaseline] = useState<string | null>(null);
  const [noteDiskMarkdown, setNoteDiskMarkdown] = useState("");
  const [noteLoadedTarget, setNoteLoadedTarget] = useState<HydratedNoteTarget | null>(null);
  const [noteStatus, setNoteStatus] = useState<SaveNoteResult["status"] | null>(null);
  const [noteConflict, setNoteConflict] = useState<SaveNoteResult | null>(null);
  const [selection, setSelection] = useState<SelectionContext | null>(null);
  const [libraryOpen, setLibraryOpen] = useState(false);
  const [overlay, setOverlay] = useState<Overlay>(null);
  const [namePrompt, setNamePrompt] = useState<NamePrompt | null>(null);
  const [loading, setLoading] = useState(true);
  const [failure, setFailure] = useState<string | null>(null);
  const [recoveryRetryGeneration, setRecoveryRetryGeneration] = useState(0);
  const [agentRequestIdsBySession, setAgentRequestIdsBySession] = useState<Record<string, string>>({});
  const streamPumps = useRef(new Map<string, AgentStreamDisplayPump>());
  const finalStreamEvents = useRef(new Map<string, TerminalAgentEvent>());
  const noteHydrationSequence = useRef(0);
  const noteEditorGeneration = useRef(0);
  const noteBaselineRef = useRef<string | null>(null);
  const noteDraftRef = useRef("");
  const noteDiskMarkdownRef = useRef("");
  const noteLoadedTargetRef = useRef<HydratedNoteTarget | null>(null);
  const noteEditorRef = useRef<CanonicalNoteEditorHandle | null>(null);
  const snapshotRef = useRef<AppSnapshot | null>(null);
  const openItemGate = useRef(new LatestOperationGate());
  const snapshotCommitGate = useRef(new LatestOperationGate());
  const snapshotMutationGate = useRef(new ExclusiveOperationGate());
  const pendingHydrationReleases = useRef<Array<() => void>>([]);
  const postCommitReleases = useRef(new PostCommitReleaseQueue());
  const recoveryWriteEpoch = useRef(new NoteRecoveryWriteEpochGate());
  noteBaselineRef.current = noteBaseline;
  noteDraftRef.current = noteDraft;
  noteDiskMarkdownRef.current = noteDiskMarkdown;
  noteLoadedTargetRef.current = noteLoadedTarget;
  snapshotRef.current = snapshot;

  const api = window.weiBei;
  const preferences = snapshot?.preferences ?? defaultPreferences;
  const activeLibraryRootPath = snapshot?.libraryRootPath ?? "";
  const activeCourse = snapshot?.activeCourse ?? null;
  const activeMaterial = activeCourse?.items.find((item) => item.id === activeCourse.activeItemId) ?? null;
  const activeNote = activeCourse?.items.find((item) => item.id === activeCourse.activeNoteId && item.isNotebookNote) ?? null;
  const activeHydratedNoteTarget = hydratedNoteSaveTarget(snapshot, noteLoadedTarget);
  const activeMaterialIdentity = activeMaterial
    ? `${activeLibraryRootPath}:${activeCourse?.id}:${activeMaterial.id}:${activeMaterial.contentRevision}:${activeMaterial.contentDigest ?? ""}`
    : "";
  const activeNoteIdentity = activeNote
    ? `${activeLibraryRootPath}:${activeCourse?.id}:${activeNote.id}:${activeNote.contentRevision}:${activeNote.contentDigest ?? ""}`
    : "";
  const recoveryWriteTicket = useMemo(
    () => recoveryWriteEpoch.current.capture(),
    [
      activeHydratedNoteTarget?.libraryRootPath,
      activeHydratedNoteTarget?.courseId,
      activeHydratedNoteTarget?.itemId,
      activeHydratedNoteTarget?.editorGeneration,
      noteBaseline,
      noteDiskMarkdown,
      noteDraft,
      recoveryRetryGeneration,
    ],
  );

  const flushCurrentNoteRecovery = useCallback(async (): Promise<NoteProtectionResult> => {
    const editor = noteEditorRef.current;
    const target = hydratedNoteSaveTarget(snapshotRef.current, noteLoadedTargetRef.current);
    if (!api || !editor || !target) return { ok: true, note: null, release: () => undefined };
    let editorFlush: ReturnType<CanonicalNoteEditorHandle["beginSnapshotFlush"]> | null = null;
    let invalidatedDelayedRecovery = false;
    try {
      editorFlush = editor.beginSnapshotFlush();
      recoveryWriteEpoch.current.invalidate();
      invalidatedDelayedRecovery = true;
      const editorSnapshot = await withTimeout(
        editorFlush.snapshot,
        3_000,
        "等待笔记编辑器快照超时",
      );
      const baselineDigest = noteBaselineRef.current;
      const action = noteRecoveryFlushAction(
        snapshotRef.current,
        noteLoadedTargetRef.current,
        editorSnapshot,
        noteDiskMarkdownRef.current,
        baselineDigest,
      );
      if (!action) throw new Error("笔记已切换，旧编辑器快照未写入其他笔记");
      if (action.kind === "save") {
        await api.saveNoteRecovery(action.request);
      } else {
        await api.clearNoteRecovery(action.target);
      }
      const activeTarget = hydratedNoteSaveTarget(snapshotRef.current, noteLoadedTargetRef.current);
      if (!activeTarget
          || activeTarget.itemId !== editorSnapshot.documentID
          || activeTarget.editorGeneration !== editorSnapshot.documentGeneration) {
        throw new Error("笔记已切换，草稿保护结果已失效");
      }
      return {
        ok: true,
        note: {
          target: { ...activeTarget },
          markdown: editorSnapshot.markdown,
          baselineDigest,
        },
        release: editorFlush.release,
      };
    } catch (error) {
      editorFlush?.release();
      if (invalidatedDelayedRecovery) {
        setRecoveryRetryGeneration((generation) => generation + 1);
      }
      setFailure(`切换前未能保护当前笔记草稿：${messageFor(error)}`);
      return { ok: false };
    }
  }, [api]);

  const releaseHydrationTransitions = useCallback(() => {
    for (const release of pendingHydrationReleases.current.splice(0)) release();
  }, []);

  useLayoutEffect(() => {
    postCommitReleases.current.drain();
  });

  const protectionMatchesCurrentNote = useCallback((
    protection: Extract<NoteProtectionResult, { ok: true }>,
  ): boolean => {
    const currentTarget = hydratedNoteSaveTarget(snapshotRef.current, noteLoadedTargetRef.current);
    if (!currentTarget) return protection.note === null;
    if (!noteEditorRef.current) return protection.note === null;
    return Boolean(protection.note
      && sameHydratedNoteTarget(protection.note.target, currentTarget));
  }, []);

  const commitSnapshot = useCallback(async (
    input: SnapshotCommitValue,
    existingProtection?: Extract<NoteProtectionResult, { ok: true }>,
  ): Promise<boolean> => {
    if (input === null) {
      existingProtection?.release();
      return false;
    }
    const ticket = snapshotCommitGate.current.begin();
    let target = noteLoadedTargetRef.current;
    let protection: Extract<NoteProtectionResult, { ok: true }> | null = existingProtection ?? null;
    for (;;) {
      if (!snapshotCommitGate.current.isLatest(ticket)) {
        protection?.release();
        return false;
      }
      const current = snapshotRef.current;
      const value = typeof input === "function"
        ? current && input(current)
        : input;
      if (!value) {
        protection?.release();
        return false;
      }
      if (snapshotKeepsHydratedEditor(current, value, target)) {
        protection?.release();
        protection = null;
      } else if (!protection || !protectionMatchesCurrentNote(protection)) {
        protection?.release();
        const nextProtection = await flushCurrentNoteRecovery();
        if (!nextProtection.ok) return false;
        protection = nextProtection;
        target = noteLoadedTargetRef.current;
        continue;
      }
      if (protection) {
        const sameNoteWillHydrate = value.preferences.visiblePanes.length > 0
          && hydratedNoteSaveTarget(value, target) !== null;
        if (sameNoteWillHydrate) pendingHydrationReleases.current.push(protection.release);
        else postCommitReleases.current.enqueue(protection.release);
      }
      snapshotRef.current = value;
      if (typeof input === "function") {
        setSnapshot((committedCurrent) => {
          if (!committedCurrent) return committedCurrent;
          const committedValue = input(committedCurrent);
          snapshotRef.current = committedValue;
          return committedValue;
        });
      } else {
        setSnapshot(value);
      }
      setFailure(null);
      return true;
    }
  }, [flushCurrentNoteRecovery, protectionMatchesCurrentNote]);

  const mutateSnapshot = useCallback((mutation: (current: AppSnapshot) => AppSnapshot) => {
    const current = snapshotRef.current;
    if (current) snapshotRef.current = mutation(current);
    setSnapshot((committedCurrent) => committedCurrent && mutation(committedCurrent));
  }, []);

  useEffect(() => {
    let active = true;
    void (async () => {
      try {
        const value = api ? await api.bootstrap() : fallbackSnapshot;
        if (active) setSnapshot(value);
      } catch (error) {
        if (active) {
          setSnapshot(fallbackSnapshot);
          setFailure(messageFor(error));
        }
      } finally {
        if (active) setLoading(false);
      }
    })();
    return () => {
      active = false;
    };
  }, [api]);

  useEffect(() => {
    if (!api) return;
    return api.onLibraryChanged((value) => {
      void commitSnapshot(value);
    });
  }, [api, commitSnapshot]);

  useEffect(() => {
    const guard = new ProtectedWindowUnloadGuard({
      hasEditorToProtect: () => Boolean(noteEditorRef.current
        && hydratedNoteSaveTarget(snapshotRef.current, noteLoadedTargetRef.current)),
      flushRecovery: async () => {
        const protection = await flushCurrentNoteRecovery();
        return protection.ok
          ? { ok: true, release: protection.release }
          : { ok: false, release: () => undefined };
      },
      closeWindow: () => window.close(),
      scheduleCloseFallback: (callback) => { window.setTimeout(callback, 250); },
    });
    const handleBeforeUnload = (event: BeforeUnloadEvent) => guard.handle(event);
    window.addEventListener("beforeunload", handleBeforeUnload);
    return () => window.removeEventListener("beforeunload", handleBeforeUnload);
  }, [flushCurrentNoteRecovery]);

  useEffect(() => { setSelection(null); }, [activeCourse?.id]);

  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      if ((event.ctrlKey || event.metaKey) && event.key.toLocaleLowerCase("en-US") === "k") {
        event.preventDefault();
        if (activeCourse) setOverlay("search");
      }
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [activeCourse]);

  useEffect(() => {
    if (!api || !activeCourse) {
      releaseHydrationTransitions();
      setDocument(null);
      noteDraftRef.current = "";
      setNoteDraft("");
      noteBaselineRef.current = null;
      setNoteBaseline(null);
      noteDiskMarkdownRef.current = "";
      setNoteDiskMarkdown("");
      noteLoadedTargetRef.current = null;
      setNoteLoadedTarget(null);
      setNoteStatus(null);
      setNoteConflict(null);
      return;
    }
    let live = true;
    if (activeMaterial) {
      void api.openItem(activeCourse.id, activeMaterial.id).then((payload) => {
        if (live) setDocument(payload);
      }, (error: unknown) => {
        if (live) setFailure(messageFor(error));
      });
    } else {
      setDocument(null);
    }
    if (activeNote) {
      const sequence = ++noteHydrationSequence.current;
      void api.openItem(activeCourse.id, activeNote.id).then(async (payload) => {
        const hydrated = await hydrateNoteDraft(
          api,
          activeLibraryRootPath,
          activeCourse.id,
          payload,
        );
        if (!live) return;
        if (sequence !== noteHydrationSequence.current) return;
        const disposition = noteHydrationDisposition(
          noteLoadedTargetRef.current,
          activeLibraryRootPath,
          activeCourse.id,
          activeNote.id,
          noteDraftRef.current,
          noteDiskMarkdownRef.current,
          hydrated.markdown,
        );
        noteDiskMarkdownRef.current = hydrated.diskMarkdown;
        setNoteDiskMarkdown(hydrated.diskMarkdown);
        if (disposition === "conflict") {
          setNoteStatus("conflict");
          setNoteConflict({
            status: "conflict",
            digest: payload.digest,
            diskMarkdown: hydrated.diskMarkdown,
            backupPath: null,
          });
          releaseHydrationTransitions();
          return;
        }
        if (disposition === "bootstrap") {
          for (const release of pendingHydrationReleases.current.splice(0)) {
            postCommitReleases.current.enqueue(release);
          }
        }
        noteDraftRef.current = hydrated.markdown;
        if (disposition === "bootstrap") setNoteDraft(hydrated.markdown);
        noteBaselineRef.current = hydrated.baselineDigest;
        setNoteBaseline(hydrated.baselineDigest);
        if (disposition === "bootstrap") {
          const target: HydratedNoteTarget = {
            libraryRootPath: activeLibraryRootPath,
            courseId: activeCourse.id,
            itemId: activeNote.id,
            editorGeneration: ++noteEditorGeneration.current,
          };
          noteLoadedTargetRef.current = target;
          setNoteLoadedTarget(target);
          setNoteStatus(null);
        }
        setNoteConflict(null);
        if (disposition === "reuse") releaseHydrationTransitions();
      }, (error: unknown) => {
        if (live) {
          releaseHydrationTransitions();
          setFailure(messageFor(error));
        }
      });
    } else {
      releaseHydrationTransitions();
      noteHydrationSequence.current += 1;
      noteDraftRef.current = "";
      setNoteDraft("");
      noteBaselineRef.current = null;
      setNoteBaseline(null);
      noteDiskMarkdownRef.current = "";
      setNoteDiskMarkdown("");
      noteLoadedTargetRef.current = null;
      setNoteLoadedTarget(null);
      setNoteStatus(null);
      setNoteConflict(null);
    }
    return () => { live = false; };
    // The digest/revision identities deliberately reload externally changed
    // active files without tying hydration to unrelated chat/session updates.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [api, activeCourse?.id, activeMaterialIdentity, activeNoteIdentity]);

  useEffect(() => {
    const target = activeHydratedNoteTarget;
    if (!api || !target) return;
    if (noteDraft === noteDiskMarkdown) {
      void recoveryWriteEpoch.current.runIfCurrent(recoveryWriteTicket, async () => {
        await api.clearNoteRecovery({
          libraryRootPath: target.libraryRootPath,
          courseId: target.courseId,
          itemId: target.itemId,
        });
      }).catch(() => undefined);
      return;
    }
    const timer = window.setTimeout(() => {
      void recoveryWriteEpoch.current.runIfCurrent(recoveryWriteTicket, async () => {
        await api.saveNoteRecovery({
          libraryRootPath: target.libraryRootPath,
          courseId: target.courseId,
          itemId: target.itemId,
          markdown: noteDraft,
          baselineDigest: noteBaseline,
        });
      }).catch(() => undefined);
    }, 700);
    return () => window.clearTimeout(timer);
  }, [activeHydratedNoteTarget, api, noteBaseline, noteDiskMarkdown, noteDraft, recoveryWriteTicket]);

  useEffect(() => {
    if (!api) return;
    return api.onAgentEvent((event) => {
      setAgentRequestIdsBySession((current) => applyAgentRequestEvent(current, event));
      if (event.type === "delta") {
        let pump = streamPumps.current.get(event.messageId);
        if (!pump) {
          pump = makeStreamPump(event.messageId);
          streamPumps.current.set(event.messageId, pump);
        }
        if (preferences.reduceMotion) {
          pump.replaceImmediately(event.text);
        } else {
          pump.enqueue(event.text);
        }
        return;
      }
      if (isTerminalAgentEvent(event)) {
        let pump = streamPumps.current.get(event.message.id);
        if (!pump) {
          pump = makeStreamPump(event.message.id);
          streamPumps.current.set(event.message.id, pump);
        }
        if (preferences.reduceMotion) {
          pump.replaceImmediately(event.message.text);
          mutateSnapshot((current) => applyAgentEvent(current, event));
          pump.cancel();
          streamPumps.current.delete(event.message.id);
        } else {
          finalStreamEvents.current.set(event.message.id, event);
          pump.finalize(event.message.text);
        }
        return;
      }
      mutateSnapshot((current) => applyAgentEvent(current, event));
    });
    function makeStreamPump(messageId: string) {
      let visible = "";
      return new AgentStreamDisplayPump({
        locale: preferences.language === "zh-Hans" ? "zh-Hans" : "en",
        hooks: {
          append(chunk) {
            visible += chunk;
            mutateSnapshot((current) => replaceAgentMessageText(current, messageId, visible));
          },
          replace(text) {
            visible = text;
            mutateSnapshot((current) => replaceAgentMessageText(current, messageId, text));
          },
          settled() {
            const finalEvent = finalStreamEvents.current.get(messageId);
            if (finalEvent) mutateSnapshot((current) => applyAgentEvent(current, finalEvent));
            finalStreamEvents.current.delete(messageId);
            streamPumps.current.delete(messageId);
          },
        },
      });
    }
  }, [api, mutateSnapshot, preferences.language, preferences.reduceMotion]);

  useEffect(() => () => {
    for (const pump of streamPumps.current.values()) pump.cancel();
    streamPumps.current.clear();
    finalStreamEvents.current.clear();
  }, []);

  const rootStyle = useMemo(
    () =>
      ({
        "--wb-text-scale": String(preferences.textScale),
        "--wb-glass-intensity": String(preferences.glassIntensity),
      }) as React.CSSProperties,
    [preferences.glassIntensity, preferences.textScale],
  );

  const replaceSnapshot = useCallback((value: AppSnapshot | null) => {
    void commitSnapshot(value);
  }, [commitSnapshot]);

  const runProtectedSnapshotMutation = useCallback(async (
    operation: () => Promise<AppSnapshot | null>,
  ): Promise<boolean> => {
    const releaseOperation = snapshotMutationGate.current.tryBegin();
    if (!releaseOperation) return false;
    let protection: NoteProtectionResult | null = null;
    try {
      protection = await flushCurrentNoteRecovery();
      if (!protection.ok) return false;
      const value = await operation();
      return await commitSnapshot(value, protection);
    } catch (error) {
      if (protection?.ok) protection.release();
      throw error;
    } finally {
      releaseOperation();
    }
  }, [commitSnapshot, flushCurrentNoteRecovery]);

  const confirmNamePrompt = useCallback(async (value: string) => {
    if (!api || !namePrompt) return;
    const request = namePrompt;
    try {
      const committed = await runProtectedSnapshotMutation(() => request.kind === "course"
        ? api.createCourse(value)
        : api.createNote(request.courseId, value));
      if (!committed) return;
      setNamePrompt(null);
      if (request.closeLibrary) setLibraryOpen(false);
    } catch (error) {
      setFailure(messageFor(error));
    }
  }, [api, namePrompt, runProtectedSnapshotMutation]);

  const updatePreferences = useCallback(
    async (patch: Partial<Preferences>) => {
      const current = snapshotRef.current;
      if (!current) return;
      const candidate = { ...current.preferences, ...patch };
      const needsProtection = !snapshotKeepsHydratedEditor(
        current,
        replaceSnapshotPreferences(current, candidate),
        noteLoadedTargetRef.current,
      );
      const protection = needsProtection ? await flushCurrentNoteRecovery() : null;
      if (protection && !protection.ok) return;
      try {
        const saved = api ? await api.updatePreferences(patch) : candidate;
        await commitSnapshot(
          (latest) => replaceSnapshotPreferences(latest, saved),
          protection?.ok ? protection : undefined,
        );
      } catch (error) {
        if (protection?.ok) protection.release();
        setFailure(messageFor(error));
      }
    },
    [api, commitSnapshot, flushCurrentNoteRecovery],
  );

  const openItem = useCallback(
    async (courseId: string, itemId: string, target: ItemOpenTarget = "auto") => {
      if (!api) return;
      const ticket = openItemGate.current.begin();
      let protection = await flushCurrentNoteRecovery();
      if (!protection.ok) return;
      let releaseTransferred = false;
      try {
        if (!openItemGate.current.isLatest(ticket)) return;
        const payload = await api.openItem(courseId, itemId);
        if (!shouldAcceptOpenedItemResult(
          snapshotRef.current,
          courseId,
          openItemGate.current.isLatest(ticket),
        )) return;
        if (!protectionMatchesCurrentNote(protection)) {
          protection.release();
          protection = await flushCurrentNoteRecovery();
          if (!protection.ok
              || !openItemGate.current.isLatest(ticket)
              || !protectionMatchesCurrentNote(protection)) return;
        }
        const current = snapshotRef.current;
        if (!current) return;
        const next = activateOpenedItem(current, courseId, payload.item);
        if (!snapshotKeepsHydratedEditor(current, next, noteLoadedTargetRef.current)) {
          postCommitReleases.current.enqueue(protection.release);
          releaseTransferred = true;
        }
        snapshotRef.current = next;
        setSnapshot(next);
        setSelection((current) => current?.itemId === itemId ? current : null);
        const noteOnly = target === "notes"
          || (target === "auto" && payload.item.isNotebookNote && !payload.item.appearsInMaterials);
        if (!noteOnly) setDocument(payload);
      } catch (error) {
        if (!shouldAcceptOpenedItemResult(
          snapshotRef.current,
          courseId,
          openItemGate.current.isLatest(ticket),
        )) return;
        setFailure(messageFor(error));
      } finally {
        if (protection.ok && !releaseTransferred) protection.release();
      }
    },
    [api, flushCurrentNoteRecovery, protectionMatchesCurrentNote],
  );

  const persistNote = useCallback(async (draft: ProtectedNoteDraft) => {
    if (!api) return;
    const request = saveRequestForProtectedNoteDraft(
      snapshotRef.current,
      noteLoadedTargetRef.current,
      draft,
    );
    if (!request) return;
    const { target, markdown } = draft;
    try {
      const result = await api.saveNote(request);
      if (!sameHydratedNoteTarget(noteLoadedTargetRef.current, target)) return;
      setNoteStatus(result.status);
      if (result.status === "saved") {
        noteBaselineRef.current = result.digest;
        setNoteBaseline(result.digest);
        noteDiskMarkdownRef.current = markdown;
        setNoteDiskMarkdown(markdown);
        setNoteConflict(null);
      }
      if (result.status === "conflict") {
        setNoteConflict(result);
        setFailure(result.diskMarkdown === null
          ? "磁盘上的笔记已被移除。草稿仍保留，魏碑没有重新创建文件。"
          : "笔记已被外部修改。草稿仍保留，魏碑没有覆盖磁盘内容。");
      }
    } catch (error) {
      if (!sameHydratedNoteTarget(noteLoadedTargetRef.current, target)) return;
      setNoteStatus("unavailable");
      setFailure(messageFor(error));
    }
  }, [api]);

  const saveNote = useCallback(() => {
    void (async () => {
      const protection = await flushCurrentNoteRecovery();
      if (!protection.ok) return;
      try {
        if (protection.note) await persistNote(protection.note);
      } finally {
        protection.release();
      }
    })();
  }, [flushCurrentNoteRecovery, persistNote]);

  const overwriteDiskNote = useCallback(() => {
    if (!noteConflict) return;
    void (async () => {
      const protection = await flushCurrentNoteRecovery();
      if (!protection.ok) return;
      try {
        if (protection.note) {
          await persistNote({ ...protection.note, baselineDigest: noteConflict.digest });
        }
      } finally {
        protection.release();
      }
    })();
  }, [flushCurrentNoteRecovery, noteConflict, persistNote]);

  if (loading || !snapshot) {
    return (
      <main className="app-shell loading-shell" data-theme="paper">
        <span className="seal-spinner" aria-label="正在打开魏碑">魏</span>
      </main>
    );
  }

  const empty = preferences.visiblePanes.length === 0 || !snapshot.activeCourse;
  const selectedSessionId = activeCourse?.sessions.find(
    (session) => session.id === activeCourse.activeSessionId,
  )?.id ?? activeCourse?.sessions[0]?.id ?? null;

  return (
    <main
      className={`app-shell theme-${preferences.theme}`}
      data-theme={preferences.theme}
      data-reduce-motion={preferences.reduceMotion ? "true" : "false"}
      style={rootStyle}
    >
      <TopBar
        snapshot={snapshot}
        persistState={activeHydratedNoteTarget && noteConflict ? "conflict" : activeHydratedNoteTarget && noteDraft !== noteDiskMarkdown ? "unsaved" : "saved"}
        onToggleLibrary={() => setLibraryOpen((value) => !value)}
        onTogglePane={(pane) => {
          const visible = preferences.visiblePanes.includes(pane);
          const next = visible
            ? preferences.visiblePanes.filter((candidate) => candidate !== pane)
            : [...preferences.visiblePanes, pane];
          void updatePreferences({ visiblePanes: next });
        }}
        onCourseSpace={() => setOverlay("course")}
        onSearch={() => setOverlay("search")}
        onSettings={() => setOverlay("settings")}
        onToggleTheme={() =>
          void updatePreferences({
            theme: isDarkTheme(preferences.theme) ? "paper" : "inkstone",
          })
        }
      />

      <section className="workspace-stage">
        {empty ? (
          <EmptyLauncher
            language={preferences.language}
            hasCourses={snapshot.courses.length > 0}
            onLibrary={() => setLibraryOpen(true)}
            onCreateCourse={() => setNamePrompt({ kind: "course", closeLibrary: false })}
            onAdopt={() => {
              if (api) void runProtectedSnapshotMutation(() => api.adoptCourseFolder());
            }}
          />
        ) : (
          <ThreePaneWorkspace
            snapshot={snapshot}
            document={document}
            noteDraft={noteDraft}
            noteEditorGeneration={activeHydratedNoteTarget?.editorGeneration ?? null}
            noteEditorRef={noteEditorRef}
            noteStatus={activeHydratedNoteTarget ? noteStatus : null}
            noteConflict={activeHydratedNoteTarget ? noteConflict : null}
            selection={selection}
            activeAgentRequestId={selectedSessionId ? agentRequestIdsBySession[selectedSessionId] ?? null : null}
            onDraftChange={(value, itemId, documentGeneration) => {
              const target = noteLoadedTargetRef.current;
              if (!target
                  || target.itemId !== itemId
                  || target.editorGeneration !== documentGeneration) return;
              noteDraftRef.current = value;
              setNoteDraft(value);
              if (noteStatus === "saved") setNoteStatus(null);
            }}
            onSelection={setSelection}
            onSaveNote={saveNote}
            onOverwriteDiskNote={overwriteDiskNote}
            onOpenItem={openItem}
            onSnapshot={replaceSnapshot}
            onPreferences={updatePreferences}
            onSearch={() => setOverlay("search")}
            onFailure={setFailure}
          />
        )}
      </section>

      <LibraryDrawer
        open={libraryOpen}
        snapshot={snapshot}
        onClose={() => setLibraryOpen(false)}
        onSelectCourse={async (courseId) => {
          if (!api) return;
          if (!(await runProtectedSnapshotMutation(() => api.selectCourse(courseId)))) return;
          setLibraryOpen(false);
          setDocument(null);
        }}
        onCreateCourse={() => setNamePrompt({ kind: "course", closeLibrary: true })}
        onImport={async () => {
          if (!api || !snapshot.activeCourse) return;
          const courseId = snapshot.activeCourse.id;
          await runProtectedSnapshotMutation(() => api.importItems(courseId));
        }}
        onCreateNote={() => {
          if (api && snapshot.activeCourse) {
            setNamePrompt({ kind: "note", closeLibrary: false, courseId: snapshot.activeCourse.id });
          }
        }}
      />

      {overlay === "course" && (
        <CourseSpace
          snapshot={snapshot}
          onClose={() => setOverlay(null)}
          onSnapshot={replaceSnapshot}
          onOpenItem={async (courseId, itemId) => {
            await openItem(courseId, itemId, "auto");
            setOverlay(null);
          }}
        />
      )}

      {overlay === "settings" && (
        <SettingsSheet
          snapshot={snapshot}
          onClose={() => setOverlay(null)}
          onPreferences={updatePreferences}
          onProvider={(provider) => {
            void commitSnapshot((current) => replaceSnapshotProvider(current, provider));
          }}
        />
      )}

      {overlay === "search" && (
        <SearchPalette
          snapshot={snapshot}
          onClose={() => setOverlay(null)}
          onOpenItem={(itemId) => { void openItem(snapshot.activeCourse!.id, itemId, "auto"); }}
        />
      )}

      {namePrompt && (
        <NamePromptSheet
          title={namePrompt.kind === "course" ? "新建课程" : "新建笔记"}
          initialValue={namePrompt.kind === "course" ? "新课程" : "无题笔记"}
          onCancel={() => setNamePrompt(null)}
          onConfirm={confirmNamePrompt}
        />
      )}

      {failure && (
        <button className="status-banner" onClick={() => setFailure(null)}>
          <span>{failure}</span><span aria-hidden="true">×</span>
        </button>
      )}
    </main>
  );
}

async function hydrateNoteDraft(
  api: WeiBeiDesktopAPI,
  libraryRootPath: string,
  courseId: string,
  payload: DocumentPayload,
) {
  const diskMarkdown = payload.content ?? "";
  const recovery = await api.loadNoteRecovery({
    libraryRootPath,
    courseId,
    itemId: payload.item.id,
  }).catch(() => null);
  if (recovery && recovery.markdown !== diskMarkdown) {
    return {
      markdown: recovery.markdown,
      baselineDigest: recovery.baselineDigest,
      diskMarkdown,
    };
  }
  return {
    markdown: diskMarkdown,
    baselineDigest: payload.digest,
    diskMarkdown,
  };
}

function isDarkTheme(theme: Preferences["theme"]): boolean {
  return theme === "inkstone" || theme === "stele" || theme === "glassDark" || theme === "glassSlate";
}

function messageFor(error: unknown): string {
  return error instanceof Error ? error.message : "操作未完成，请稍后重试。";
}

function withTimeout<T>(promise: Promise<T>, timeoutMilliseconds: number, message: string): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const timer = window.setTimeout(() => reject(new Error(message)), timeoutMilliseconds);
    void promise.then(
      (value) => {
        window.clearTimeout(timer);
        resolve(value);
      },
      (error: unknown) => {
        window.clearTimeout(timer);
        reject(error);
      },
    );
  });
}
