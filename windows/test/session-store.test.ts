import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import {
  mkdir,
  mkdtemp,
  readFile,
  readdir,
  rm,
  writeFile,
} from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import type { AgentMessage } from "../src/shared/contracts";
import { StudySessionStore } from "../src/main/services/session-store";
import {
  decodePersistedWorkspace,
  parseSwiftJSON,
  stringifySwiftJSON,
  swiftReferenceSecondsFromDate,
  type SwiftJSONObject,
} from "../src/main/services/swift-codec";

test("session bodies use lowercase external files and workspace metadata carries no body", async () => {
  await withWorkspace(async (directory) => {
    const courseID = randomUUID();
    const store = await StudySessionStore.open(directory);
    const session = await store.create(courseID);
    const user = agentMessage("user", "魏碑与隶书的关系是什么？");
    const assistant = agentMessage("assistant", "SESSION_BODY_ONLY_北朝刻石", {
      sources: [{
        id: randomUUID(),
        itemId: "imported:source",
        courseId: courseID,
        kind: "material",
        title: "龙门二十品",
        label: "[1]",
        excerpt: "方笔与隶意",
        pageIndex: 2,
        sectionTitle: "结体",
        sectionLocationId: "section-3",
      }],
      actions: [{
        id: randomUUID(),
        state: "pending",
        targetItemId: "imported:note",
        sourceItemId: "imported:source",
        proposedMarkdown: "## 方笔\n",
        evidence: ["方笔与隶意"],
        baselineContentDigest: "abc123",
      }],
    });
    await store.appendMessages(session.id, [user, assistant]);

    const sessionNames = await readdir(path.join(directory, "Sessions"));
    assert.deepEqual(sessionNames, [`${session.id.toLowerCase()}.json`]);
    const payload = await readSwiftObject(sessionFile(directory, session.id));
    assert.equal(payload.schemaVersion, 1);
    assert.equal(payload.sessionID, session.id);
    const messages = objectArray(payload.messages);
    assert.equal(messages.length, 2);
    assert.equal(messages[1].text, assistant.text);
    assert.deepEqual(messages[1].contentBlocks, [{ text: { _0: assistant.text } }]);
    assert.equal(objectArray(messages[1].sources)[0].sectionLocationID, "section-3");
    assert.equal(objectArray(messages[1].actions)[0].proposedMarkdown, "## 方笔\n");

    const workspaceBytes = await readFile(path.join(directory, "workspace.json"));
    const workspace = decodePersistedWorkspace(workspaceBytes);
    const metadata = objectArray(workspace.studySessions)[0];
    assert.equal(metadata.id, session.id);
    assert.equal(metadata.messageCount, 2);
    assert.deepEqual(metadata.messages, []);
    assert.equal(workspaceBytes.includes(Buffer.from("SESSION_BODY_ONLY_北朝刻石")), false);
  });
});

test("restart interrupts generating replies, restores retry question, and preserves raw extensions", async () => {
  await withWorkspace(async (directory) => {
    const courseID = randomUUID();
    const first = await StudySessionStore.open(directory);
    const session = await first.create(courseID);
    const question = "中断后应该恢复哪一个问题？";
    const user = agentMessage("user", question);
    const assistant = agentMessage("assistant", "半段答案", {
      completionState: "generating",
      retryQuestion: null,
    });
    await first.appendMessages(session.id, [user, assistant]);

    const filePath = sessionFile(directory, session.id);
    const payload = await readSwiftObject(filePath);
    payload.futurePayloadCounter = 9_007_199_254_740_993n;
    const rawAssistant = objectArray(payload.messages)[1];
    rawAssistant.futureMessageField = { retain: true };
    rawAssistant.contentBlocks = [
      { text: { _0: "半段答案" } },
      { visualization: { _0: { id: "chart", specJSON: "{}", futureBlock: 7 } } },
    ];
    await writeFile(filePath, stringifySwiftJSON(payload, { sortKeys: true }), "utf8");

    const reopened = await StudySessionStore.open(directory);
    const recovered = await reopened.get(session.id);
    assert.ok(recovered);
    const recoveredAssistant = recovered.messages.find((message) => message.id === assistant.id);
    assert.ok(recoveredAssistant);
    assert.equal(recoveredAssistant.completionState, "interrupted");
    assert.equal(recoveredAssistant.failureKind, "cancelled");
    assert.equal(recoveredAssistant.retryQuestion, question);

    const roundTripped = await readSwiftObject(filePath);
    assert.equal(roundTripped.futurePayloadCounter, 9_007_199_254_740_993n);
    const storedAssistant = objectArray(roundTripped.messages)[1];
    assert.deepEqual(storedAssistant.futureMessageField, { retain: true });
    assert.deepEqual(storedAssistant.contentBlocks, rawAssistant.contentBlocks);
    assert.equal(storedAssistant.completionState, "interrupted");
    assert.equal(storedAssistant.failureKind, "cancelled");
    assert.equal(storedAssistant.retryQuestion, question);
  });
});

test("one corrupt session file does not block launch or another session", async () => {
  await withWorkspace(async (directory) => {
    const courseID = randomUUID();
    const first = await StudySessionStore.open(directory);
    const damaged = await first.create(courseID);
    const healthy = await first.create(courseID);
    await first.appendMessages(damaged.id, [agentMessage("user", "损坏会话正文")]);
    await first.appendMessages(healthy.id, [agentMessage("user", "健康会话正文")]);
    const damagedPath = sessionFile(directory, damaged.id);
    await writeFile(damagedPath, "{", "utf8");

    const reopened = await StudySessionStore.open(directory);
    const sessions = await reopened.listForCourse(courseID);
    assert.equal(sessions.length, 2);
    assert.deepEqual(
      sessions.find((session) => session.id === healthy.id)?.messages.map((message) => message.text),
      ["健康会话正文"],
    );
    assert.deepEqual(
      sessions.find((session) => session.id === damaged.id)?.messages,
      [],
    );
    assert.equal(await readFile(damagedPath, "utf8"), "{");
  });
});

test("append and update merge a Mac-style payload without losing rich or unknown data", async () => {
  await withWorkspace(async (directory) => {
    const courseID = randomUUID();
    const first = await StudySessionStore.open(directory);
    const session = await first.create(courseID);
    const fixed = new Date("2025-02-03T04:05:06.000Z");
    const userID = randomUUID().toUpperCase();
    const sourceID = randomUUID().toUpperCase();
    const actionID = randomUUID().toUpperCase();
    const untouchedID = randomUUID().toUpperCase();
    const source: SwiftJSONObject = {
      id: sourceID,
      itemID: "imported:碑帖",
      courseID: courseID.toUpperCase(),
      kind: "material",
      title: "郑文公碑",
      label: "[1]",
      excerpt: "雄强茂密",
      pageIndex: 4,
      sectionTitle: "用笔",
      sectionLocationID: "section-5",
      sectionOrdinal: 5,
      futureCitationField: 9_007_199_254_740_995n,
    };
    const action: SwiftJSONObject = {
      id: actionID,
      kind: "writeNote",
      state: "pending",
      targetItemID: "imported:笔记",
      sourceItemID: "imported:碑帖",
      proposedMarkdown: "## 雄强茂密\n",
      evidence: ["雄强茂密"],
      contextRevision: "future-context",
      baselineContentDigest: "digest-before",
      resultContentDigest: null,
      createdRelationID: null,
      failureMessage: null,
      createdAt: swiftReferenceSecondsFromDate(fixed),
      updatedAt: swiftReferenceSecondsFromDate(fixed),
      futureActionField: { raw: "keep-action" },
    };
    const richBlocks = [
      { text: { _0: "原始问题" } },
      { futureBlock: { _0: { payload: "keep-block" } } },
    ];
    const originalUser: SwiftJSONObject = {
      id: userID,
      role: "user",
      text: "原始问题",
      contentBlocks: richBlocks,
      source: "legacy-source",
      backend: "native",
      completionState: "completed",
      sources: [source],
      actions: [action],
      memoryUpdate: { memoryIDs: [randomUUID()], summary: "keep-memory", future: true },
      profileUpdate: { entryIDs: [randomUUID()], summary: "keep-profile", texts: [] },
      origin: { requestID: randomUUID(), chatID: randomUUID(), courseID },
      failureKind: null,
      retryQuestion: null,
      toolTrace: ["course-search"],
      createdAt: swiftReferenceSecondsFromDate(fixed),
      futureMessageRevision: 9_007_199_254_740_997n,
    };
    const untouched: SwiftJSONObject = {
      id: untouchedID,
      role: "assistant",
      text: "旁路消息",
      contentBlocks: [{ text: { _0: "旁路消息" } }],
      sources: [],
      actions: [],
      createdAt: swiftReferenceSecondsFromDate(fixed),
      futureUntouched: { exact: true },
    };
    const fixturePayload: SwiftJSONObject = {
      schemaVersion: 1,
      sessionID: session.id.toUpperCase(),
      messages: [originalUser, untouched],
      futurePayloadRevision: 9_007_199_254_740_999n,
      futurePayloadField: { raw: "keep-payload" },
    };
    const filePath = sessionFile(directory, session.id);
    await writeFile(filePath, stringifySwiftJSON(fixturePayload, { sortKeys: true }), "utf8");

    const reopened = await StudySessionStore.open(directory);
    const loaded = await reopened.get(session.id);
    assert.ok(loaded);
    assert.equal(loaded.messages[0].sources.length, 1);
    assert.equal(loaded.messages[0].actions.length, 1);

    const appendedMessage = agentMessage("assistant", "Windows 新增回答");
    const appended = await reopened.appendMessages(session.id, [appendedMessage]);
    let persisted = await readSwiftObject(filePath);
    assert.equal(persisted.sessionID, session.id.toUpperCase());
    assert.equal(persisted.futurePayloadRevision, 9_007_199_254_740_999n);
    assert.deepEqual(persisted.futurePayloadField, { raw: "keep-payload" });
    let rawMessages = objectArray(persisted.messages);
    assert.deepEqual(rawMessages[0], originalUser);
    assert.deepEqual(rawMessages[1], untouched);
    assert.equal(rawMessages[2].text, appendedMessage.text);

    const updatedUser: AgentMessage = {
      ...appended.messages.find((message) => message.id === userID)!,
      text: "只更新这一段文本",
      completionState: "interrupted",
      failureKind: "cancelled",
    };
    await reopened.updateMessage(session.id, updatedUser);
    persisted = await readSwiftObject(filePath);
    rawMessages = objectArray(persisted.messages);
    const updatedRaw = rawMessages[0];
    assert.equal(updatedRaw.text, "只更新这一段文本");
    assert.equal(updatedRaw.completionState, "interrupted");
    assert.equal(updatedRaw.failureKind, "cancelled");
    assert.deepEqual(updatedRaw.contentBlocks, richBlocks);
    assert.deepEqual(updatedRaw.sources, [source]);
    assert.deepEqual(updatedRaw.actions, [action]);
    assert.deepEqual(updatedRaw.memoryUpdate, originalUser.memoryUpdate);
    assert.deepEqual(updatedRaw.profileUpdate, originalUser.profileUpdate);
    assert.deepEqual(updatedRaw.origin, originalUser.origin);
    assert.deepEqual(updatedRaw.toolTrace, originalUser.toolTrace);
    assert.equal(updatedRaw.createdAt, originalUser.createdAt);
    assert.equal(updatedRaw.futureMessageRevision, 9_007_199_254_740_997n);
    assert.deepEqual(rawMessages[1], untouched);
    assert.equal(persisted.futurePayloadRevision, 9_007_199_254_740_999n);

    const workspace = decodePersistedWorkspace(await readFile(path.join(directory, "workspace.json")));
    const metadata = objectArray(workspace.studySessions)[0];
    assert.deepEqual(metadata.messages, []);
    assert.equal(metadata.messageCount, 3);
  });
});

async function withWorkspace(operation: (directory: string) => Promise<void>): Promise<void> {
  const directory = await mkdtemp(path.join(os.tmpdir(), "weibei-session-store-"));
  await mkdir(path.join(directory, "Sessions"), { recursive: true });
  try {
    await operation(directory);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}

function agentMessage(
  role: AgentMessage["role"],
  text: string,
  overrides: Partial<AgentMessage> = {},
): AgentMessage {
  return {
    id: randomUUID(),
    role,
    text,
    completionState: "completed",
    sources: [],
    actions: [],
    failureKind: null,
    retryQuestion: null,
    createdAt: new Date("2025-02-03T04:05:06.000Z").toISOString(),
    ...overrides,
  };
}

function sessionFile(directory: string, sessionID: string): string {
  return path.join(directory, "Sessions", `${sessionID.toLowerCase()}.json`);
}

async function readSwiftObject(filePath: string): Promise<SwiftJSONObject> {
  return objectValue(parseSwiftJSON(await readFile(filePath, "utf8")));
}

function objectValue(value: unknown): SwiftJSONObject {
  assert.ok(value && typeof value === "object" && !Array.isArray(value));
  return value as SwiftJSONObject;
}

function objectArray(value: unknown): SwiftJSONObject[] {
  assert.ok(Array.isArray(value));
  return value.map(objectValue);
}
