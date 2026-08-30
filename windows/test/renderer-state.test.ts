import assert from "node:assert/strict";
import test from "node:test";
import {
  AgentEventSchema,
  type AgentEvent,
  type AgentMessage,
  type AppSnapshot,
  type StudyItem,
  type StudySession,
} from "../src/shared/contracts";
import {
  activateOpenedItem,
  applyAgentEvent,
  applyAgentRequestEvent,
  hydratedNoteSaveTarget,
  isTerminalAgentEvent,
  noteHydrationDisposition,
  noteRecoveryFlushAction,
  replaceSnapshotPreferences,
  replaceSnapshotProvider,
  saveRequestForProtectedNoteDraft,
  sameHydratedNoteTarget,
  shouldAcceptOpenedItemResult,
  snapshotKeepsHydratedEditor,
} from "../src/renderer/app-state";

const courseID = "11111111-1111-4111-8111-111111111111";
const sessionAID = "22222222-2222-4222-8222-222222222222";
const sessionBID = "33333333-3333-4333-8333-333333333333";
const requestID = "44444444-4444-4444-8444-444444444444";
const messageAID = "55555555-5555-4555-8555-555555555555";
const messageBID = "66666666-6666-4666-8666-666666666666";
const libraryRootPath = "C:\\Library";

test("opening a note mirrors activeNoteId and only its completed hydration can be saved", () => {
  const original = snapshot();
  const opened = activateOpenedItem(original, courseID, noteB);

  assert.equal(opened.activeCourse?.activeNoteId, noteB.id);
  assert.equal(opened.activeCourse?.activeItemId, material.id);
  assert.equal(hydratedNoteSaveTarget(opened, {
    libraryRootPath,
    courseId: courseID,
    itemId: noteA.id,
    editorGeneration: 1,
  }), null, "the previous note must not remain a save target while the new note hydrates");
  assert.deepEqual(hydratedNoteSaveTarget(opened, {
    libraryRootPath,
    courseId: courseID,
    itemId: noteB.id,
    editorGeneration: 2,
  }), { libraryRootPath, courseId: courseID, itemId: noteB.id, editorGeneration: 2 });
  assert.equal(sameHydratedNoteTarget(
    { libraryRootPath, courseId: courseID, itemId: noteA.id, editorGeneration: 1 },
    { libraryRootPath, courseId: courseID, itemId: noteA.id, editorGeneration: 2 },
  ), false, "an old save response must not mutate a newly hydrated generation of the same note");
  const clonedLibraryRoot = "C:\\ClonedLibrary";
  assert.equal(hydratedNoteSaveTarget({
    ...opened,
    libraryRootPath: clonedLibraryRoot,
  }, {
    libraryRootPath,
    courseId: courseID,
    itemId: noteB.id,
    editorGeneration: 2,
  }), null, "the same course and item IDs in another library are a different note target");
  assert.equal(noteHydrationDisposition(
    { libraryRootPath, courseId: courseID, itemId: noteB.id, editorGeneration: 2 },
    clonedLibraryRoot,
    courseID,
    noteB.id,
    "draft from original library",
    "same disk bytes",
    "same disk bytes",
  ), "bootstrap");
  assert.equal(noteHydrationDisposition(
    { libraryRootPath, courseId: courseID, itemId: noteB.id, editorGeneration: 2 },
    libraryRootPath,
    courseID,
    noteB.id,
    "already in the iframe",
    "already in the iframe",
    "already in the iframe",
  ), "reuse", "a watcher refresh of the saved bytes must not remount the editor and lose its caret");
  assert.equal(noteHydrationDisposition(
    { libraryRootPath, courseId: courseID, itemId: noteA.id, editorGeneration: 1 },
    libraryRootPath,
    courseID,
    noteB.id,
    "old note",
    "old note",
    "new note",
  ), "bootstrap", "a different note still requires a fresh editor bootstrap");
});

test("a watcher refresh preserves a live draft before delayed recovery reaches disk", () => {
  const liveDraft = "旧磁盘内容 + 用户刚输入、尚未经过 700ms recovery";
  assert.equal(noteHydrationDisposition(
    { libraryRootPath, courseId: courseID, itemId: noteA.id, editorGeneration: 4 },
    libraryRootPath,
    courseID,
    noteA.id,
    liveDraft,
    "旧磁盘内容",
    "约 360ms 后观察到的外部磁盘修改",
  ), "conflict", "the live iframe draft must never be replaced by the watcher payload");
});

test("a pre-navigation snapshot saves recovery only to its exact hydrated note", () => {
  const current = snapshot();
  const target = { libraryRootPath, courseId: courseID, itemId: noteA.id, editorGeneration: 4 };
  const editorSnapshot = {
    requestID: "flush-2",
    documentID: noteA.id,
    documentGeneration: 4,
    revision: 2,
    markdown: "input typed less than 700ms before navigation",
  };
  assert.deepEqual(noteRecoveryFlushAction(
    current,
    target,
    editorSnapshot,
    "old disk",
    "a".repeat(64),
  ), {
    kind: "save",
    request: {
      libraryRootPath,
      courseId: courseID,
      itemId: noteA.id,
      markdown: editorSnapshot.markdown,
      baselineDigest: "a".repeat(64),
    },
  });

  const switchedNote = activateOpenedItem(current, courseID, noteB);
  assert.equal(noteRecoveryFlushAction(
    switchedNote,
    target,
    editorSnapshot,
    "old disk",
    "a".repeat(64),
  ), null, "a late note A snapshot must never be stored as note B recovery");

  const otherCourseID = "88888888-8888-4888-8888-888888888888";
  const switchedCourse = {
    ...current,
    activeCourse: current.activeCourse && { ...current.activeCourse, id: otherCourseID },
  };
  assert.equal(noteRecoveryFlushAction(
    switchedCourse,
    target,
    editorSnapshot,
    "old disk",
    "a".repeat(64),
  ), null, "even the same item ID in another course must not receive the old recovery");
  assert.equal(noteRecoveryFlushAction(
    current,
    target,
    { ...editorSnapshot, documentGeneration: 3 },
    "old disk",
    "a".repeat(64),
  ), null, "a prior iframe generation must be rejected");

  const protectedDraft = {
    target,
    markdown: editorSnapshot.markdown,
    baselineDigest: "a".repeat(64),
  };
  assert.deepEqual(saveRequestForProtectedNoteDraft(current, target, protectedDraft), {
    courseId: courseID,
    itemId: noteA.id,
    markdown: editorSnapshot.markdown,
    baselineDigest: "a".repeat(64),
  });
  assert.equal(saveRequestForProtectedNoteDraft(
    switchedNote,
    { libraryRootPath, courseId: courseID, itemId: noteB.id, editorGeneration: 5 },
    protectedDraft,
  ), null, "a saved A target can never be combined with B's later live markdown");

  assert.deepEqual(noteRecoveryFlushAction(
    current,
    target,
    { ...editorSnapshot, markdown: "old disk" },
    "old disk",
    "a".repeat(64),
  ), {
    kind: "clear",
    target: { libraryRootPath, courseId: courseID, itemId: noteA.id },
  });
});

test("snapshot changes which can remount the editor require a recovery flush", () => {
  const current = snapshot();
  const target = { libraryRootPath, courseId: courseID, itemId: noteA.id, editorGeneration: 4 };
  assert.equal(snapshotKeepsHydratedEditor(current, current, target), true);
  const changedDigest = {
    ...current,
    activeCourse: current.activeCourse && {
      ...current.activeCourse,
      items: current.activeCourse.items.map((item) => item.id === noteA.id
        ? { ...item, contentDigest: "b".repeat(64) }
        : item),
    },
  };
  assert.equal(snapshotKeepsHydratedEditor(current, changedDigest, target), false);
  assert.equal(snapshotKeepsHydratedEditor(current, {
    ...current,
    preferences: { ...current.preferences, visiblePanes: [] },
  }, target), false, "hiding the last pane unmounts the editor and must flush first");
});

test("an openItem response cannot enter the reader after its course was switched away", () => {
  const original = snapshot();
  assert.equal(shouldAcceptOpenedItemResult(original, courseID, true), true);
  assert.equal(
    shouldAcceptOpenedItemResult({ ...original, activeCourse: null }, courseID, true),
    false,
    "a latest response from the previous course is still stale for the current workspace",
  );
  assert.equal(
    shouldAcceptOpenedItemResult(original, courseID, false),
    false,
    "an older response in the same course must also be ignored",
  );
});

test("late preferences and provider completions patch the current snapshot only", () => {
  const staleAtRequestStart = snapshot();
  const completedMessage = assistantMessage(messageAID, "terminal text", "completed");
  const afterNavigationAndTerminal = applyAgentEvent(
    activateOpenedItem(staleAtRequestStart, courseID, noteB),
    {
      type: "completed",
      requestId: requestID,
      sessionId: sessionAID,
      message: completedMessage,
    },
  );
  const savedPreferences = {
    ...staleAtRequestStart.preferences,
    theme: "inkstone" as const,
  };
  const afterPreferences = replaceSnapshotPreferences(
    afterNavigationAndTerminal,
    savedPreferences,
  );
  assert.equal(afterPreferences.activeCourse?.activeNoteId, noteB.id);
  assert.deepEqual(messageIn(afterPreferences, sessionAID, messageAID), completedMessage);
  assert.equal(afterPreferences.preferences.theme, "inkstone");

  const savedProvider = {
    providerId: "anthropic",
    model: "claude-test",
    baseUrl: "https://api.anthropic.com",
    hasCredential: true,
  };
  const afterProvider = replaceSnapshotProvider(afterPreferences, savedProvider);
  assert.equal(afterProvider.activeCourse?.activeNoteId, noteB.id);
  assert.deepEqual(messageIn(afterProvider, sessionAID, messageAID), completedMessage);
  assert.deepEqual(afterProvider.preferences, savedPreferences);
  assert.deepEqual(afterProvider.provider, savedProvider);
});

test("a terminal event updates its owning session even after the user switches chats", () => {
  const current = snapshot();
  assert.equal(current.activeCourse?.activeSessionId, sessionBID);
  const completedMessage = assistantMessage(messageAID, "A 的完整回答", "completed");
  const event: AgentEvent = {
    type: "completed",
    requestId: requestID,
    sessionId: sessionAID,
    message: completedMessage,
  };

  const parsed = AgentEventSchema.parse(event);
  assert.equal(parsed.sessionId, sessionAID);
  const next = applyAgentEvent(current, parsed);
  assert.deepEqual(messageIn(next, sessionAID, messageAID), completedMessage);
  assert.equal(messageIn(next, sessionBID, messageBID)?.text, "B 正在生成");
  const requestBID = "77777777-7777-4777-8777-777777777777";
  assert.deepEqual(applyAgentRequestEvent({
    [sessionAID]: requestID,
    [sessionBID]: requestBID,
  }, parsed), {
    [sessionBID]: requestBID,
  }, "finishing A must not make B's stop button target disappear");
});

test("a failed event is terminal and lands the authoritative persisted partial text", () => {
  const current = snapshot();
  const failedMessage = {
    ...assistantMessage(messageAID, "已经收到但尚未显示的尾部", "interrupted"),
    failureKind: "provider-timeout",
  };
  const event: AgentEvent = {
    type: "failed",
    requestId: requestID,
    sessionId: sessionAID,
    messageId: messageAID,
    failureKind: "provider-timeout",
    message: failedMessage,
  };

  const parsed = AgentEventSchema.parse(event);
  assert.equal(isTerminalAgentEvent(parsed), true);
  assert.equal(parsed.sessionId, sessionAID);
  const next = applyAgentEvent(current, parsed);
  assert.deepEqual(messageIn(next, sessionAID, messageAID), failedMessage);
});

function snapshot(): AppSnapshot {
  const sessions: StudySession[] = [
    session(sessionAID, assistantMessage(messageAID, "已显示前缀", "generating")),
    session(sessionBID, assistantMessage(messageBID, "B 正在生成", "generating")),
  ];
  return {
    courses: [{
      id: courseID,
      title: "测试课程",
      colorIndex: 0,
      rootPath: "C:\\Library\\Course",
      createdAt: "2026-08-30T00:00:00.000Z",
      updatedAt: "2026-08-30T00:00:00.000Z",
      itemCount: 3,
    }],
    activeCourse: {
      id: courseID,
      title: "测试课程",
      colorIndex: 0,
      rootPath: "C:\\Library\\Course",
      createdAt: "2026-08-30T00:00:00.000Z",
      updatedAt: "2026-08-30T00:00:00.000Z",
      itemCount: 3,
      items: [material, noteA, noteB],
      sessions,
      activeItemId: material.id,
      activeNoteId: noteA.id,
      activeSessionId: sessionBID,
    },
    preferences: {
      theme: "paper",
      language: "zh-Hans",
      textScale: 1,
      glassIntensity: 1,
      reduceMotion: false,
      paneOrder: ["reader", "agent", "notes"],
      visiblePanes: ["reader", "agent", "notes"],
      paneWidths: { reader: 1, agent: 1, notes: 1 },
    },
    provider: {
      providerId: "openai",
      model: "gpt-5.4",
      baseUrl: "https://api.openai.com/v1",
      hasCredential: true,
    },
    libraryRootPath,
    platform: "windows",
    appVersion: "1.0.0",
  };
}

function session(id: string, message: AgentMessage): StudySession {
  return {
    id,
    title: id === sessionAID ? "Chat A" : "Chat B",
    courseId: courseID,
    itemId: null,
    messages: [message],
    createdAt: "2026-08-30T00:00:00.000Z",
    updatedAt: "2026-08-30T00:00:00.000Z",
  };
}

function assistantMessage(
  id: string,
  text: string,
  completionState: AgentMessage["completionState"],
): AgentMessage {
  return {
    id,
    role: "assistant",
    text,
    completionState,
    sources: [],
    actions: [],
    failureKind: null,
    retryQuestion: "继续",
    createdAt: "2026-08-30T00:00:00.000Z",
  };
}

function messageIn(value: AppSnapshot, sessionId: string, messageId: string) {
  return value.activeCourse?.sessions
    .find((candidate) => candidate.id === sessionId)?.messages
    .find((message) => message.id === messageId);
}

const material: StudyItem = {
  id: "material:one",
  title: "文稿",
  subtitle: "",
  kind: "markdown",
  isNotebookNote: false,
  appearsInMaterials: true,
  relativePath: "文稿/one.md",
  contentRevision: 1,
  contentDigest: "a".repeat(64),
  unavailable: false,
};

const noteA: StudyItem = {
  ...material,
  id: "note:a",
  title: "笔记 A",
  isNotebookNote: true,
  appearsInMaterials: false,
  relativePath: "笔记/a.md",
};

const noteB: StudyItem = {
  ...noteA,
  id: "note:b",
  title: "笔记 B",
  relativePath: "笔记/b.md",
};
