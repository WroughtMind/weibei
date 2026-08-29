import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type {
  AgentEvent,
  AppSnapshot,
  DocumentPayload,
  PaneRole,
  Preferences,
  SaveNoteResult,
  SelectionContext,
  StudySession,
  WeiBeiDesktopAPI,
} from "../shared/contracts";
import { CourseSpace } from "./components/CourseSpace";
import { EmptyLauncher } from "./components/EmptyLauncher";
import { LibraryDrawer } from "./components/LibraryDrawer";
import { SettingsSheet } from "./components/SettingsSheet";
import { SearchPalette } from "./components/SearchPalette";
import { TopBar } from "./components/TopBar";
import { ThreePaneWorkspace } from "./components/ThreePaneWorkspace";
import { AgentStreamDisplayPump } from "./stream-display-pump";

type Overlay = "course" | "search" | "settings" | null;
type ItemOpenTarget = "reader" | "notes" | "auto";

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
  const [noteLoadedItemId, setNoteLoadedItemId] = useState<string | null>(null);
  const [noteStatus, setNoteStatus] = useState<SaveNoteResult["status"] | null>(null);
  const [noteConflict, setNoteConflict] = useState<SaveNoteResult | null>(null);
  const [selection, setSelection] = useState<SelectionContext | null>(null);
  const [libraryOpen, setLibraryOpen] = useState(false);
  const [overlay, setOverlay] = useState<Overlay>(null);
  const [loading, setLoading] = useState(true);
  const [failure, setFailure] = useState<string | null>(null);
  const streamPumps = useRef(new Map<string, AgentStreamDisplayPump>());
  const finalStreamEvents = useRef(new Map<string, Extract<AgentEvent, { type: "completed" | "cancelled" }>>());
  const noteHydrationSequence = useRef(0);

  const api = window.weiBei;
  const preferences = snapshot?.preferences ?? defaultPreferences;
  const activeCourse = snapshot?.activeCourse ?? null;
  const activeMaterial = activeCourse?.items.find((item) => item.id === activeCourse.activeItemId) ?? null;
  const activeNote = activeCourse?.items.find((item) => item.id === activeCourse.activeNoteId && item.isNotebookNote) ?? null;
  const activeMaterialIdentity = activeMaterial
    ? `${activeCourse?.id}:${activeMaterial.id}:${activeMaterial.contentRevision}:${activeMaterial.contentDigest ?? ""}`
    : "";
  const activeNoteIdentity = activeNote
    ? `${activeCourse?.id}:${activeNote.id}:${activeNote.contentRevision}:${activeNote.contentDigest ?? ""}`
    : "";

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
      setSnapshot(value);
      setFailure(null);
    });
  }, [api]);

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
      setDocument(null);
      setNoteDraft("");
      setNoteBaseline(null);
      setNoteDiskMarkdown("");
      setNoteLoadedItemId(null);
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
        const hydrated = await hydrateNoteDraft(api, payload);
        if (!live) return;
        if (sequence !== noteHydrationSequence.current) return;
        setNoteDraft(hydrated.markdown);
        setNoteBaseline(hydrated.baselineDigest);
        setNoteDiskMarkdown(hydrated.diskMarkdown);
        setNoteLoadedItemId(activeNote.id);
        setNoteStatus(null);
        setNoteConflict(null);
      }, (error: unknown) => {
        if (live) setFailure(messageFor(error));
      });
    } else {
      noteHydrationSequence.current += 1;
      setNoteDraft("");
      setNoteBaseline(null);
      setNoteDiskMarkdown("");
      setNoteLoadedItemId(null);
      setNoteStatus(null);
      setNoteConflict(null);
    }
    return () => { live = false; };
    // The digest/revision identities deliberately reload externally changed
    // active files without tying hydration to unrelated chat/session updates.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [api, activeCourse?.id, activeMaterialIdentity, activeNoteIdentity]);

  useEffect(() => {
    if (!api || !activeNote || noteLoadedItemId !== activeNote.id) return;
    if (noteDraft === noteDiskMarkdown) {
      void api.clearNoteRecovery(activeNote.id).catch(() => undefined);
      return;
    }
    const timer = window.setTimeout(() => {
      void api.saveNoteRecovery({
        itemId: activeNote.id,
        markdown: noteDraft,
        baselineDigest: noteBaseline,
      }).catch(() => undefined);
    }, 700);
    return () => window.clearTimeout(timer);
  }, [activeNote, api, noteBaseline, noteDiskMarkdown, noteDraft, noteLoadedItemId]);

  useEffect(() => {
    if (!api) return;
    return api.onAgentEvent((event) => {
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
      if (event.type === "completed" || event.type === "cancelled") {
        let pump = streamPumps.current.get(event.message.id);
        if (!pump) {
          pump = makeStreamPump(event.message.id);
          streamPumps.current.set(event.message.id, pump);
        }
        if (preferences.reduceMotion) {
          pump.replaceImmediately(event.message.text);
          setSnapshot((current) => current && applyAgentEvent(current, event));
          pump.cancel();
          streamPumps.current.delete(event.message.id);
        } else {
          finalStreamEvents.current.set(event.message.id, event);
          pump.finalize(event.message.text);
        }
        return;
      }
      if (event.type === "failed") {
        streamPumps.current.get(event.messageId)?.cancel();
        streamPumps.current.delete(event.messageId);
      }
      setSnapshot((current) => current && applyAgentEvent(current, event));
    });
    function makeStreamPump(messageId: string) {
      let visible = "";
      return new AgentStreamDisplayPump({
        locale: preferences.language === "zh-Hans" ? "zh-Hans" : "en",
        hooks: {
          append(chunk) {
            visible += chunk;
            setSnapshot((current) => current && replaceAgentMessageText(current, messageId, visible));
          },
          replace(text) {
            visible = text;
            setSnapshot((current) => current && replaceAgentMessageText(current, messageId, text));
          },
          settled() {
            const finalEvent = finalStreamEvents.current.get(messageId);
            if (finalEvent) setSnapshot((current) => current && applyAgentEvent(current, finalEvent));
            finalStreamEvents.current.delete(messageId);
            streamPumps.current.delete(messageId);
          },
        },
      });
    }
  }, [api, preferences.language, preferences.reduceMotion]);

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
    if (!value) return;
    setSnapshot(value);
    setFailure(null);
  }, []);

  const updatePreferences = useCallback(
    async (patch: Partial<Preferences>) => {
      if (!snapshot) return;
      const optimistic = { ...snapshot.preferences, ...patch };
      setSnapshot({ ...snapshot, preferences: optimistic });
      try {
        const saved = api ? await api.updatePreferences(patch) : optimistic;
        setSnapshot((current) => current && { ...current, preferences: saved });
      } catch (error) {
        setSnapshot((current) =>
          current ? { ...current, preferences: snapshot.preferences } : current,
        );
        setFailure(messageFor(error));
      }
    },
    [api, snapshot],
  );

  const openItem = useCallback(
    async (courseId: string, itemId: string, target: ItemOpenTarget = "auto") => {
      if (!api) return;
      try {
        const payload = await api.openItem(courseId, itemId);
        setSelection((current) => current?.itemId === itemId ? current : null);
        if (payload.item.isNotebookNote) {
          const sequence = ++noteHydrationSequence.current;
          const hydrated = await hydrateNoteDraft(api, payload);
          if (sequence !== noteHydrationSequence.current) return;
          setNoteDraft(hydrated.markdown);
          setNoteBaseline(hydrated.baselineDigest);
          setNoteDiskMarkdown(hydrated.diskMarkdown);
          setNoteLoadedItemId(payload.item.id);
          setNoteStatus(null);
          setNoteConflict(null);
        }
        const noteOnly = target === "notes"
          || (target === "auto" && payload.item.isNotebookNote && !payload.item.appearsInMaterials);
        if (!noteOnly) setDocument(payload);
      } catch (error) {
        setFailure(messageFor(error));
      }
    },
    [api],
  );

  const persistNote = useCallback(async (baselineDigest: string | null) => {
    const course = snapshot?.activeCourse;
    const note = course?.items.find((item) => item.id === course.activeNoteId);
    if (!api || !course || !note) return;
    try {
      const result = await api.saveNote({
        courseId: course.id,
        itemId: note.id,
        markdown: noteDraft,
        baselineDigest,
      });
      setNoteStatus(result.status);
      if (result.status === "saved") {
        setNoteBaseline(result.digest);
        setNoteDiskMarkdown(noteDraft);
        setNoteConflict(null);
      }
      if (result.status === "conflict") {
        setNoteConflict(result);
        setFailure(result.diskMarkdown === null
          ? "磁盘上的笔记已被移除。草稿仍保留，魏碑没有重新创建文件。"
          : "笔记已被外部修改。草稿仍保留，魏碑没有覆盖磁盘内容。");
      }
    } catch (error) {
      setNoteStatus("unavailable");
      setFailure(messageFor(error));
    }
  }, [api, noteDraft, snapshot]);

  const saveNote = useCallback(() => persistNote(noteBaseline), [noteBaseline, persistNote]);

  const useDiskNote = useCallback(() => {
    if (!activeNote || !noteConflict || noteConflict.diskMarkdown === null) return;
    setNoteDraft(noteConflict.diskMarkdown);
    setNoteDiskMarkdown(noteConflict.diskMarkdown);
    setNoteBaseline(noteConflict.digest);
    setNoteStatus("saved");
    setNoteConflict(null);
    void api?.clearNoteRecovery(activeNote.id).catch(() => undefined);
  }, [activeNote, api, noteConflict]);

  const overwriteDiskNote = useCallback(() => {
    if (!noteConflict) return;
    void persistNote(noteConflict.digest);
  }, [noteConflict, persistNote]);

  if (loading || !snapshot) {
    return (
      <main className="app-shell loading-shell" data-theme="paper">
        <span className="seal-spinner" aria-label="正在打开魏碑">魏</span>
      </main>
    );
  }

  const empty = preferences.visiblePanes.length === 0 || !snapshot.activeCourse;

  return (
    <main
      className={`app-shell theme-${preferences.theme}`}
      data-theme={preferences.theme}
      data-reduce-motion={preferences.reduceMotion ? "true" : "false"}
      style={rootStyle}
    >
      <TopBar
        snapshot={snapshot}
        persistState={noteConflict ? "conflict" : noteLoadedItemId && noteDraft !== noteDiskMarkdown ? "unsaved" : "saved"}
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
            onCreateCourse={async () => {
              const title = window.prompt("课程名称", "新课程")?.trim();
              if (!title || !api) return;
              replaceSnapshot(await api.createCourse(title));
            }}
            onAdopt={async () => replaceSnapshot(api ? await api.adoptCourseFolder() : null)}
          />
        ) : (
          <ThreePaneWorkspace
            snapshot={snapshot}
            document={document}
            noteDraft={noteDraft}
            noteStatus={noteStatus}
            noteConflict={noteConflict}
            selection={selection}
            onDraftChange={(value) => {
              setNoteDraft(value);
              if (noteStatus === "saved") setNoteStatus(null);
            }}
            onSelection={setSelection}
            onSaveNote={saveNote}
            onUseDiskNote={useDiskNote}
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
          replaceSnapshot(await api.selectCourse(courseId));
          setLibraryOpen(false);
          setDocument(null);
        }}
        onCreateCourse={async () => {
          const title = window.prompt("课程名称", "新课程")?.trim();
          if (!title || !api) return;
          replaceSnapshot(await api.createCourse(title));
          setLibraryOpen(false);
        }}
        onImport={async () => {
          if (!api || !snapshot.activeCourse) return;
          replaceSnapshot(await api.importItems(snapshot.activeCourse.id));
        }}
        onCreateNote={async () => {
          if (!api || !snapshot.activeCourse) return;
          const title = window.prompt("笔记名称", "无题笔记")?.trim();
          if (!title) return;
          replaceSnapshot(await api.createNote(snapshot.activeCourse.id, title));
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
          onSnapshot={replaceSnapshot}
        />
      )}

      {overlay === "search" && (
        <SearchPalette
          snapshot={snapshot}
          onClose={() => setOverlay(null)}
          onOpenItem={(itemId) => { void openItem(snapshot.activeCourse!.id, itemId, "auto"); }}
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

async function hydrateNoteDraft(api: WeiBeiDesktopAPI, payload: DocumentPayload) {
  const diskMarkdown = payload.content ?? "";
  const recovery = await api.loadNoteRecovery(payload.item.id).catch(() => null);
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

function applyAgentEvent(snapshot: AppSnapshot, event: AgentEvent): AppSnapshot {
  const course = snapshot.activeCourse;
  if (!course) return snapshot;
  const sessions = course.sessions.map((session): StudySession => {
    if (session.id !== ("sessionId" in event ? event.sessionId : course.activeSessionId)) return session;
    if (event.type === "started") {
      return { ...session, messages: [...session.messages, event.userMessage, event.assistantMessage] };
    }
    const messageId = event.type === "completed" || event.type === "cancelled"
      ? event.message.id
      : event.messageId;
    return {
      ...session,
      messages: session.messages.map((message) => {
        if (message.id !== messageId) return message;
        if (event.type === "delta") return { ...message, text: event.text };
        if (event.type === "completed" || event.type === "cancelled") return event.message;
        if (event.type === "failed") {
          return { ...message, completionState: "interrupted", failureKind: event.failureKind };
        }
        return message;
      }),
    };
  });
  return { ...snapshot, activeCourse: { ...course, sessions } };
}

function replaceAgentMessageText(snapshot: AppSnapshot, messageId: string, text: string): AppSnapshot {
  const course = snapshot.activeCourse;
  if (!course) return snapshot;
  return {
    ...snapshot,
    activeCourse: {
      ...course,
      sessions: course.sessions.map((session) => ({
        ...session,
        messages: session.messages.map((message) => message.id === messageId ? { ...message, text } : message),
      })),
    },
  };
}
