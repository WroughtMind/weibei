import type {
  AgentEvent,
  AppSnapshot,
  NoteRecoverySaveInput,
  NoteRecoveryTarget,
  Preferences,
  ProviderPublicConfig,
  SaveNoteRequest,
  StudyItem,
  StudySession,
} from "../shared/contracts";
import type { NoteEditorSnapshot } from "./note-snapshot-flush";

export type TerminalAgentEvent = Extract<
  AgentEvent,
  { type: "completed" | "failed" | "cancelled" }
>;

export interface HydratedNoteTarget {
  libraryRootPath: string;
  courseId: string;
  itemId: string;
  editorGeneration: number;
}

export interface ProtectedNoteDraft {
  target: HydratedNoteTarget;
  markdown: string;
  baselineDigest: string | null;
}

export type NoteRecoveryFlushAction =
  | { kind: "clear"; target: NoteRecoveryTarget }
  | {
      kind: "save";
      request: NoteRecoverySaveInput;
    };

export function isTerminalAgentEvent(event: AgentEvent): event is TerminalAgentEvent {
  return event.type === "completed" || event.type === "failed" || event.type === "cancelled";
}

export function applyAgentRequestEvent(
  current: Record<string, string>,
  event: AgentEvent,
): Record<string, string> {
  if (event.type === "started") {
    return { ...current, [event.sessionId]: event.requestId };
  }
  if (!isTerminalAgentEvent(event) || current[event.sessionId] !== event.requestId) {
    return current;
  }
  const next = { ...current };
  delete next[event.sessionId];
  return next;
}

/** Mirror the active item change which `openItem` has already persisted in main. */
export function activateOpenedItem(
  snapshot: AppSnapshot,
  courseId: string,
  item: StudyItem,
): AppSnapshot {
  const course = snapshot.activeCourse;
  if (!course || course.id !== courseId) return snapshot;
  return {
    ...snapshot,
    activeCourse: item.isNotebookNote
      ? { ...course, activeNoteId: item.id }
      : { ...course, activeItemId: item.id },
  };
}

/** Async item content may be shown only while its originating course is still active. */
export function shouldAcceptOpenedItemResult(
  snapshot: AppSnapshot | null,
  courseId: string,
  isLatest: boolean,
): boolean {
  return isLatest && snapshot?.activeCourse?.id === courseId;
}

/** Patch only persisted preferences onto the state current at completion. */
export function replaceSnapshotPreferences(
  current: AppSnapshot,
  preferences: Preferences,
): AppSnapshot {
  return { ...current, preferences };
}

/** Patch only provider metadata onto the state current at completion. */
export function replaceSnapshotProvider(
  current: AppSnapshot,
  provider: ProviderPublicConfig,
): AppSnapshot {
  return { ...current, provider };
}

/** A save is valid only for the exact course/note pair which finished hydration. */
export function hydratedNoteSaveTarget(
  snapshot: AppSnapshot | null,
  target: HydratedNoteTarget | null,
): HydratedNoteTarget | null {
  const course = snapshot?.activeCourse;
  if (!course || !target
      || snapshot.libraryRootPath !== target.libraryRootPath
      || course.id !== target.courseId
      || course.activeNoteId !== target.itemId
      || !course.items.some((item) => item.id === target.itemId && item.isNotebookNote)) {
    return null;
  }
  return target;
}

export function sameHydratedNoteTarget(
  left: HydratedNoteTarget | null,
  right: HydratedNoteTarget | null,
): boolean {
  return Boolean(left && right
    && left.libraryRootPath === right.libraryRootPath
    && left.courseId === right.courseId
    && left.itemId === right.itemId
    && left.editorGeneration === right.editorGeneration);
}

export type NoteHydrationDisposition = "bootstrap" | "reuse" | "conflict";

/** Decide a watcher refresh without ever replacing an unpersisted live draft. */
export function noteHydrationDisposition(
  target: HydratedNoteTarget | null,
  libraryRootPath: string,
  courseId: string,
  itemId: string,
  liveMarkdown: string,
  priorDiskMarkdown: string,
  hydratedMarkdown: string,
): NoteHydrationDisposition {
  const sameTarget = Boolean(target
    && target.libraryRootPath === libraryRootPath
    && target.courseId === courseId
    && target.itemId === itemId);
  if (sameTarget && liveMarkdown !== priorDiskMarkdown) return "conflict";
  if (sameTarget && liveMarkdown === hydratedMarkdown) return "reuse";
  return "bootstrap";
}

/** Bind a flushed iframe snapshot to the exact still-active hydrated note. */
export function noteRecoveryFlushAction(
  snapshot: AppSnapshot | null,
  target: HydratedNoteTarget | null,
  editorSnapshot: NoteEditorSnapshot,
  diskMarkdown: string,
  baselineDigest: string | null,
): NoteRecoveryFlushAction | null {
  const activeTarget = hydratedNoteSaveTarget(snapshot, target);
  if (!activeTarget
      || editorSnapshot.documentID !== activeTarget.itemId
      || editorSnapshot.documentGeneration !== activeTarget.editorGeneration) {
    return null;
  }
  if (editorSnapshot.markdown === diskMarkdown) {
    return {
      kind: "clear",
      target: {
        libraryRootPath: activeTarget.libraryRootPath,
        courseId: activeTarget.courseId,
        itemId: activeTarget.itemId,
      },
    };
  }
  return {
    kind: "save",
    request: {
      libraryRootPath: activeTarget.libraryRootPath,
      courseId: activeTarget.courseId,
      itemId: activeTarget.itemId,
      markdown: editorSnapshot.markdown,
      baselineDigest,
    },
  };
}

/** Build disk-save arguments solely from the immutable, exact flush result. */
export function saveRequestForProtectedNoteDraft(
  snapshot: AppSnapshot | null,
  currentTarget: HydratedNoteTarget | null,
  draft: ProtectedNoteDraft,
): SaveNoteRequest | null {
  const activeTarget = hydratedNoteSaveTarget(snapshot, currentTarget);
  if (!activeTarget || !sameHydratedNoteTarget(activeTarget, draft.target)) return null;
  return {
    courseId: draft.target.courseId,
    itemId: draft.target.itemId,
    markdown: draft.markdown,
    baselineDigest: draft.baselineDigest,
  };
}

export function snapshotKeepsHydratedEditor(
  currentSnapshot: AppSnapshot | null,
  nextSnapshot: AppSnapshot,
  target: HydratedNoteTarget | null,
): boolean {
  const currentTarget = hydratedNoteSaveTarget(currentSnapshot, target);
  const nextTarget = hydratedNoteSaveTarget(nextSnapshot, target);
  if (!currentTarget || !nextTarget || nextSnapshot.preferences.visiblePanes.length === 0) {
    return false;
  }
  const currentItem = currentSnapshot?.activeCourse?.items.find(
    (item) => item.id === currentTarget.itemId,
  );
  const nextItem = nextSnapshot.activeCourse?.items.find(
    (item) => item.id === nextTarget.itemId,
  );
  return Boolean(currentItem && nextItem
    && currentItem.contentRevision === nextItem.contentRevision
    && currentItem.contentDigest === nextItem.contentDigest);
}

export function applyAgentEvent(snapshot: AppSnapshot, event: AgentEvent): AppSnapshot {
  const course = snapshot.activeCourse;
  if (!course) return snapshot;
  const sessions = course.sessions.map((session): StudySession => {
    if (session.id !== event.sessionId) return session;
    if (event.type === "started") {
      return { ...session, messages: [...session.messages, event.userMessage, event.assistantMessage] };
    }
    const messageId = isTerminalAgentEvent(event) ? event.message.id : event.messageId;
    return {
      ...session,
      messages: session.messages.map((message) => {
        if (message.id !== messageId) return message;
        if (event.type === "delta") return { ...message, text: event.text };
        return event.message;
      }),
    };
  });
  return { ...snapshot, activeCourse: { ...course, sessions } };
}

export function replaceAgentMessageText(
  snapshot: AppSnapshot,
  messageId: string,
  text: string,
): AppSnapshot {
  const course = snapshot.activeCourse;
  if (!course) return snapshot;
  return {
    ...snapshot,
    activeCourse: {
      ...course,
      sessions: course.sessions.map((session) => ({
        ...session,
        messages: session.messages.map((message) =>
          message.id === messageId ? { ...message, text } : message),
      })),
    },
  };
}
