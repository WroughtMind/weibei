import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import {
  mkdir,
  mkdtemp,
  readFile,
  readdir,
  rename,
  rm,
  symlink,
  writeFile,
} from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import type { AgentMessage } from "../src/shared/contracts";
import { sha256 } from "../src/main/services/file-utils";
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

test("open restores a session baseline displaced by an interrupted CAS", async () => {
  await withWorkspace(async (directory) => {
    const courseID = randomUUID();
    const first = await StudySessionStore.open(directory);
    const session = await first.create(courseID);
    await first.appendMessages(session.id, [agentMessage("user", "崩溃前正文")]);
    const payloadPath = sessionFile(directory, session.id);
    const baseline = await readFile(payloadPath);
    const next = Buffer.from("next-generation", "utf8");
    const transactionDirectory = path.join(
      path.dirname(payloadPath),
      `.${path.basename(payloadPath)}.weibei-transaction-${randomUUID()}`,
    );
    await mkdir(transactionDirectory);
    await Promise.all([
      writeFile(path.join(transactionDirectory, "next"), next),
      writeFile(
        path.join(transactionDirectory, "transaction.json"),
        JSON.stringify({
          schemaVersion: 1,
          targetFileName: path.basename(payloadPath),
          expectedDigest: sha256(baseline),
          nextDigest: sha256(next),
        }),
        "utf8",
      ),
    ]);
    await rename(payloadPath, path.join(transactionDirectory, "previous"));

    const reopened = await StudySessionStore.open(directory);
    assert.deepEqual(await readFile(payloadPath), baseline);
    assert.deepEqual(
      (await reopened.get(session.id))?.messages.map((message) => message.text),
      ["崩溃前正文"],
    );
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

test("append and update preserve missing, corrupt, and mismatched external bodies", async () => {
  await withWorkspace(async (directory) => {
    const store = await StudySessionStore.open(directory);
    const courseID = randomUUID();
    for (const damage of ["missing", "corrupt", "identity-mismatch"] as const) {
      const session = await store.create(courseID);
      const original = agentMessage("user", `原始正文-${damage}`);
      await store.appendMessages(session.id, [original]);
      const payloadPath = sessionFile(directory, session.id);
      let damagedBytes: Buffer | null = null;
      if (damage === "missing") {
        await rm(payloadPath);
      } else if (damage === "corrupt") {
        damagedBytes = Buffer.from("{", "utf8");
        await writeFile(payloadPath, damagedBytes);
      } else {
        const payload = await readSwiftObject(payloadPath);
        payload.sessionID = randomUUID();
        damagedBytes = Buffer.from(
          stringifySwiftJSON(payload, { sortKeys: true }),
          "utf8",
        );
        await writeFile(payloadPath, damagedBytes);
      }
      const workspaceBefore = await readFile(path.join(directory, "workspace.json"));
      const expected = damage === "missing"
        ? /session-payload-missing/
        : /session-payload-invalid/;

      await assert.rejects(
        store.appendMessages(session.id, [agentMessage("assistant", "不得覆盖")]),
        expected,
      );
      await assert.rejects(
        store.updateMessage(session.id, { ...original, text: "不得覆盖更新" }),
        expected,
      );
      assert.deepEqual(
        await readFile(path.join(directory, "workspace.json")),
        workspaceBefore,
      );
      if (damagedBytes) {
        assert.deepEqual(await readFile(payloadPath), damagedBytes);
      } else {
        await assert.rejects(readFile(payloadPath), isNodeErrorCode("ENOENT"));
      }
    }
  });
});

test("append and update externalize a complete embedded legacy body", async () => {
  await withWorkspace(async (directory) => {
    const courseID = randomUUID();
    const first = await StudySessionStore.open(directory);
    const session = await first.create(courseID);
    const original = agentMessage("user", "合法 embedded 正文");
    await first.appendMessages(session.id, [original]);
    const payloadPath = sessionFile(directory, session.id);
    const payload = await readSwiftObject(payloadPath);
    const workspacePath = path.join(directory, "workspace.json");
    const workspace = decodePersistedWorkspace(await readFile(workspacePath));
    const metadata = objectArray(workspace.studySessions)[0];
    metadata.messages = payload.messages;
    metadata.messageCount = objectArray(payload.messages).length;
    await writeFile(
      workspacePath,
      stringifySwiftJSON(workspace, { trailingNewline: true }),
      "utf8",
    );
    await rm(payloadPath);

    const reopened = await StudySessionStore.open(directory);
    await reopened.updateMessage(session.id, {
      ...original,
      text: "embedded 更新后仍保留",
    });
    await reopened.appendMessages(session.id, [
      agentMessage("assistant", "embedded 后续追加"),
    ]);
    assert.deepEqual(
      (await reopened.get(session.id))?.messages.map((message) => message.text),
      ["embedded 更新后仍保留", "embedded 后续追加"],
    );
    assert.equal(objectArray((await readSwiftObject(payloadPath)).messages).length, 2);
  });
});

test("duplicate session UUID spellings are isolated from reads and block mutations", async () => {
  await withWorkspace(async (directory) => {
    const courseID = randomUUID();
    const sessionID = randomUUID();
    const createdAt = swiftReferenceSecondsFromDate(
      new Date("2025-02-03T04:05:06.000Z"),
    );
    const firstMessage: SwiftJSONObject = {
      id: randomUUID(),
      role: "user",
      text: "FIRST_EMBEDDED",
      createdAt,
    };
    const secondMessage: SwiftJSONObject = {
      id: randomUUID(),
      role: "user",
      text: "SECOND_EMBEDDED",
      createdAt,
    };
    const metadata = (id: string, message: SwiftJSONObject): SwiftJSONObject => ({
      id,
      title: "重复 UUID",
      messages: [message],
      relatedCourseIDs: [courseID],
      createdAt,
      updatedAt: createdAt,
      messageCount: 1,
    });
    const workspacePath = path.join(directory, "workspace.json");
    await writeFile(
      workspacePath,
      stringifySwiftJSON({
        importedItems: [],
        notesByItemID: {},
        studySessions: [
          metadata(sessionID.toLowerCase(), firstMessage),
          metadata(sessionID.toUpperCase(), secondMessage),
        ],
      }, { trailingNewline: true }),
      "utf8",
    );
    const store = await StudySessionStore.open(directory);
    const before = await readFile(workspacePath);

    assert.deepEqual(await store.listForCourse(courseID), []);
    assert.equal(await store.get(sessionID), null);
    await assert.rejects(
      store.appendMessages(sessionID.toUpperCase(), [agentMessage("assistant", "NEW")]),
      /duplicate-session-id/,
    );
    await assert.rejects(
      store.updateMessage(sessionID, { ...agentMessage("user", "UPDATE"), id: firstMessage.id as string }),
      /duplicate-session-id/,
    );
    await assert.rejects(store.create(courseID), /duplicate-session-id/);
    await assert.rejects(
      store.migrateLegacyCourseSessions(courseID, [
        metadata(randomUUID(), {
          ...firstMessage,
          id: randomUUID(),
        }),
      ]),
      /duplicate-session-id/,
    );
    assert.deepEqual(await readFile(workspacePath), before);
    await assert.rejects(
      readFile(sessionFile(directory, sessionID)),
      isNodeErrorCode("ENOENT"),
    );
    const persisted = decodePersistedWorkspace(await readFile(workspacePath));
    assert.deepEqual(
      objectArray(persisted.studySessions).map((entry) =>
        objectArray(entry.messages).map((message) => message.text)),
      [["FIRST_EMBEDDED"], ["SECOND_EMBEDDED"]],
    );
  });
});

test("read surfaces isolate malformed metadata while mutations preserve its evidence", async () => {
  await withWorkspace(async (directory) => {
    const courseID = randomUUID();
    const sessionID = randomUUID();
    const createdAt = swiftReferenceSecondsFromDate(
      new Date("2025-02-03T04:05:06.000Z"),
    );
    const valid: SwiftJSONObject = {
      id: sessionID,
      title: "仍可读取",
      messages: [{
        id: randomUUID(),
        role: "user",
        text: "HEALTHY_EMBEDDED",
        createdAt,
      }],
      relatedCourseIDs: [courseID],
      createdAt,
      updatedAt: createdAt,
      messageCount: 1,
    };
    const workspacePath = path.join(directory, "workspace.json");
    await writeFile(
      workspacePath,
      stringifySwiftJSON({
        importedItems: [],
        notesByItemID: {},
        studySessions: [42, valid],
      }, { trailingNewline: true }),
      "utf8",
    );
    const store = await StudySessionStore.open(directory);
    const before = await readFile(workspacePath);

    assert.deepEqual(
      (await store.listForCourse(courseID)).map((value) => value.id),
      [sessionID],
    );
    assert.equal((await store.get(sessionID))?.messages[0]?.text, "HEALTHY_EMBEDDED");
    await assert.rejects(store.create(courseID), /invalid-workspace-session/);
    await assert.rejects(
      store.appendMessages(sessionID, [agentMessage("assistant", "MUST_NOT_WRITE")]),
      /invalid-workspace-session/,
    );
    assert.deepEqual(await readFile(workspacePath), before);
    await assert.rejects(
      readFile(sessionFile(directory, sessionID)),
      isNodeErrorCode("ENOENT"),
    );
  });
});

test("legacy migration preflights every existing workspace session", async () => {
  await withWorkspace(async (directory) => {
    const workspacePath = path.join(directory, "workspace.json");
    await writeFile(
      workspacePath,
      stringifySwiftJSON({
        importedItems: [],
        notesByItemID: {},
        studySessions: [null],
      }, { trailingNewline: true }),
      "utf8",
    );
    const store = await StudySessionStore.open(directory);
    const courseID = randomUUID();
    const sessionID = randomUUID();
    const createdAt = swiftReferenceSecondsFromDate(
      new Date("2025-02-03T04:05:06.000Z"),
    );
    const before = await readFile(workspacePath);
    await assert.rejects(
      store.migrateLegacyCourseSessions(courseID, [{
        id: sessionID,
        title: "不得写入损坏 workspace",
        messages: [{
          id: randomUUID(),
          role: "user",
          text: "保留 v1",
          createdAt,
        }],
        relatedCourseIDs: [courseID],
        createdAt,
        updatedAt: createdAt,
        messageCount: 1,
      }]),
      /invalid-workspace-session/,
    );
    assert.deepEqual(await readFile(workspacePath), before);
    await assert.rejects(
      readFile(sessionFile(directory, sessionID)),
      isNodeErrorCode("ENOENT"),
    );
  });
});

test("legacy migration preflights unrelated Swift session metadata before body writes", async () => {
  await withWorkspace(async (directory) => {
    const courseID = randomUUID();
    const unrelatedID = randomUUID();
    const migratingID = randomUUID();
    const createdAt = swiftReferenceSecondsFromDate(
      new Date("2025-02-03T04:05:06.000Z"),
    );
    const workspacePath = path.join(directory, "workspace.json");
    await writeFile(
      workspacePath,
      stringifySwiftJSON({
        importedItems: [],
        notesByItemID: {},
        studySessions: [{
          id: unrelatedID,
          title: 42,
          messages: [],
          relatedCourseIDs: [courseID],
          createdAt,
          updatedAt: createdAt,
          messageCount: 0,
        }],
      }, { trailingNewline: true }),
      "utf8",
    );
    const store = await StudySessionStore.open(directory);
    const before = await readFile(workspacePath);
    await assert.rejects(
      store.migrateLegacyCourseSessions(courseID, [{
        id: migratingID,
        title: "不得外置",
        messages: [{
          id: randomUUID(),
          role: "user",
          text: "V1 必须保留",
          createdAt,
        }],
        relatedCourseIDs: [courseID],
        createdAt,
        updatedAt: createdAt,
        messageCount: 1,
      }]),
      /legacy-session-metadata-invalid/,
    );
    assert.deepEqual(await readFile(workspacePath), before);
    await assert.rejects(
      readFile(sessionFile(directory, migratingID)),
      isNodeErrorCode("ENOENT"),
    );
  });
});

test("course session lookup matches UUID spelling case-insensitively", async () => {
  await withWorkspace(async (directory) => {
    const courseID = randomUUID().toLowerCase();
    const store = await StudySessionStore.open(directory);
    const session = await store.create(courseID);
    assert.deepEqual(
      (await store.listForCourse(courseID.toUpperCase())).map((value) => value.id),
      [session.id],
    );
  });
});

test("legacy migration accepts only strict append-only Chat extensions", async () => {
  await withWorkspace(async (directory) => {
    const store = await StudySessionStore.open(directory);
    const courseID = randomUUID();
    const session = await store.create(courseID);
    const createdAt = swiftReferenceSecondsFromDate(
      new Date("2025-02-03T04:05:06.000Z"),
    );
    const first: SwiftJSONObject = {
      id: randomUUID(),
      role: "user",
      text: "共同前缀",
      createdAt,
    };
    const second: SwiftJSONObject = {
      id: randomUUID(),
      role: "assistant",
      text: "课程端追加",
      createdAt,
    };
    const legacy = (messages: SwiftJSONObject[]): SwiftJSONObject => ({
      id: session.id,
      title: "追加迁移",
      messages,
      relatedCourseIDs: [courseID],
      createdAt,
      updatedAt: createdAt,
      messageCount: messages.length,
    });

    await store.migrateLegacyCourseSessions(courseID, [legacy([first])]);
    await store.migrateLegacyCourseSessions(courseID, [legacy([first, second])]);
    // The shorter v1 copy remains a valid prefix of the longer global body.
    await store.migrateLegacyCourseSessions(courseID, [legacy([first])]);
    assert.deepEqual(
      (await store.get(session.id))?.messages.map((message) => message.text),
      ["共同前缀", "课程端追加"],
    );

    const payloadPath = sessionFile(directory, session.id);
    const beforeFork = await readFile(payloadPath);
    await assert.rejects(
      store.migrateLegacyCourseSessions(courseID, [legacy([
        first,
        { ...second, text: "分叉回答" },
      ])]),
      /existing-session-body-conflict/,
    );
    assert.deepEqual(await readFile(payloadPath), beforeFork);

    // Metadata still declares two messages, so losing the external body must
    // hold migration even though the old course retains a shorter copy.
    await rm(payloadPath);
    await assert.rejects(
      store.migrateLegacyCourseSessions(courseID, [legacy([first])]),
      /existing-session-payload-missing/,
    );
  });
});

test("legacy migration holds the course when an existing or declared body is missing", async () => {
  await withWorkspace(async (directory) => {
    const store = await StudySessionStore.open(directory);
    const courseID = randomUUID();
    const createdAt = swiftReferenceSecondsFromDate(
      new Date("2025-02-03T04:05:06.000Z"),
    );
    const sessionID = randomUUID();
    const legacy: SwiftJSONObject = {
      id: sessionID,
      title: "有效旧 Chat",
      messages: [{
        id: randomUUID(),
        role: "user",
        text: "有效的课程内历史",
        createdAt,
      }],
      relatedCourseIDs: [courseID],
      createdAt,
      updatedAt: createdAt,
      messageCount: 1,
    };
    await writeFile(
      sessionFile(directory, sessionID),
      stringifySwiftJSON({
        schemaVersion: 1,
        sessionID,
        messages: [null],
      }, { sortKeys: true }),
      "utf8",
    );

    await assert.rejects(
      store.migrateLegacyCourseSessions(courseID, [legacy]),
      /existing-session-payload-invalid/,
    );
    assert.deepEqual(
      (await readSwiftObject(sessionFile(directory, sessionID))).messages,
      [null],
    );

    const missingBodySession: SwiftJSONObject = {
      ...legacy,
      id: randomUUID(),
      messages: [],
      messageCount: 1,
    };
    await assert.rejects(
      store.migrateLegacyCourseSessions(courseID, [missingBodySession]),
      /legacy-session-body-missing/,
    );
    const workspace = decodePersistedWorkspace(
      await readFile(path.join(directory, "workspace.json")),
    );
    assert.deepEqual(workspace.studySessions ?? [], []);
  });
});

test("legacy migration CAS rejects a payload changed after its final inspection", async () => {
  await withWorkspace(async (directory) => {
    const store = await StudySessionStore.open(directory);
    const courseID = randomUUID();
    const session = await store.create(courseID);
    await store.appendMessages(session.id, [agentMessage("user", "BASELINE")]);
    const payloadPath = sessionFile(directory, session.id);
    const baselinePayload = await readSwiftObject(payloadPath);
    const baselineMessages = objectArray(baselinePayload.messages);
    const createdAt = swiftReferenceSecondsFromDate(
      new Date("2025-02-03T04:05:06.000Z"),
    );
    const legacy: SwiftJSONObject = {
      id: session.id,
      title: "并发迁移",
      messages: [
        baselineMessages[0],
        {
          id: randomUUID(),
          role: "assistant",
          text: "LEGACY_APPEND",
          createdAt,
        },
      ],
      relatedCourseIDs: [courseID],
      createdAt,
      updatedAt: createdAt,
      messageCount: 2,
    };
    const forkPayload: SwiftJSONObject = {
      ...baselinePayload,
      messages: [{ ...baselineMessages[0], text: "EXTERNAL_FORK" }],
    };
    const forkBytes = stringifySwiftJSON(forkPayload, { sortKeys: true });
    const originalInspect = Reflect.get(
      store,
      "inspectSessionPayload",
    ) as (sessionID: string) => Promise<unknown>;
    let inspections = 0;
    Reflect.set(store, "inspectSessionPayload", async (sessionID: string) => {
      const result = await originalInspect.call(store, sessionID);
      inspections += 1;
      if (
        inspections === 2
        && sessionID.toLowerCase() === session.id.toLowerCase()
      ) {
        await writeFile(payloadPath, forkBytes, "utf8");
      }
      return result;
    });
    const workspaceBefore = await readFile(path.join(directory, "workspace.json"));

    await assert.rejects(
      store.migrateLegacyCourseSessions(courseID, [legacy]),
      /write-conflict/,
    );
    assert.equal(inspections, 2);
    assert.equal(await readFile(payloadPath, "utf8"), forkBytes);
    assert.deepEqual(
      await readFile(path.join(directory, "workspace.json")),
      workspaceBefore,
    );

  });
});

test("append preserves an externally edited workspace and reloads the winner", async () => {
  await withWorkspace(async (directory) => {
    const courseID = randomUUID();
    const store = await StudySessionStore.open(directory);
    const session = await store.create(courseID);
    await store.appendMessages(session.id, [agentMessage("user", "BASELINE")]);
    const workspacePath = path.join(directory, "workspace.json");
    const external = {
      ...decodePersistedWorkspace(await readFile(workspacePath)),
      futureExternalEdit: { winner: "EXTERNAL" },
    };
    const externalBytes = Buffer.from(
      stringifySwiftJSON(external, { trailingNewline: true }),
      "utf8",
    );
    await writeFile(workspacePath, externalBytes);

    await assert.rejects(
      store.appendMessages(session.id, [agentMessage("assistant", "BODY_FIRST")]),
      /write-conflict/,
    );
    assert.deepEqual(await readFile(workspacePath), externalBytes);
    assert.deepEqual(
      objectArray((await readSwiftObject(sessionFile(directory, session.id))).messages)
        .map((message) => message.text),
      ["BASELINE", "BODY_FIRST"],
    );

    // The failed commit reloads the external winner, so a later independent
    // mutation can succeed without erasing its forward field.
    await store.create(courseID);
    const afterRetry = decodePersistedWorkspace(await readFile(workspacePath));
    assert.deepEqual(afterRetry.futureExternalEdit, { winner: "EXTERNAL" });
  });
});

test("legacy migration preserves an externally edited workspace and retries safely", async () => {
  await withWorkspace(async (directory) => {
    const courseID = randomUUID();
    const sessionID = randomUUID();
    const store = await StudySessionStore.open(directory);
    const workspacePath = path.join(directory, "workspace.json");
    const external = {
      ...decodePersistedWorkspace(await readFile(workspacePath)),
      futureExternalEdit: "COURSE_FILE_WINNER",
    };
    const externalBytes = Buffer.from(
      stringifySwiftJSON(external, { trailingNewline: true }),
      "utf8",
    );
    await writeFile(workspacePath, externalBytes);
    const createdAt = swiftReferenceSecondsFromDate(
      new Date("2025-02-03T04:05:06.000Z"),
    );
    const legacy: SwiftJSONObject = {
      id: sessionID,
      title: "外部编辑期间迁移",
      messages: [{
        id: randomUUID(),
        role: "user",
        text: "V1_EVIDENCE",
        createdAt,
      }],
      relatedCourseIDs: [courseID],
      createdAt,
      updatedAt: createdAt,
      messageCount: 1,
    };

    await assert.rejects(
      store.migrateLegacyCourseSessions(courseID, [legacy]),
      /write-conflict/,
    );
    assert.deepEqual(await readFile(workspacePath), externalBytes);
    assert.equal(
      objectArray((await readSwiftObject(sessionFile(directory, sessionID))).messages)[0].text,
      "V1_EVIDENCE",
    );

    await store.migrateLegacyCourseSessions(courseID, [legacy]);
    const persisted = decodePersistedWorkspace(await readFile(workspacePath));
    assert.equal(persisted.futureExternalEdit, "COURSE_FILE_WINNER");
    assert.equal(objectArray(persisted.studySessions).length, 1);
  });
});

test("legacy migration validates course ownership, references, and Swift metadata", async () => {
  await withWorkspace(async (directory) => {
    const store = await StudySessionStore.open(directory);
    const courseID = randomUUID();
    const otherCourseID = randomUUID();
    const createdAt = swiftReferenceSecondsFromDate(
      new Date("2025-02-03T04:05:06.000Z"),
    );
    const session = (overrides: SwiftJSONObject = {}): SwiftJSONObject => ({
      id: randomUUID(),
      title: "归属校验",
      messages: [{
        id: randomUUID(),
        role: "user",
        text: "不能串课程",
        createdAt,
      }],
      relatedCourseIDs: [courseID],
      createdAt,
      updatedAt: createdAt,
      messageCount: 1,
      ...overrides,
    });
    const invalidCases: Array<[SwiftJSONObject, RegExp]> = [
      [session({ relatedCourseIDs: [otherCourseID] }), /legacy-session-course-mismatch/],
      [session({ relatedCourseIDs: [] }), /legacy-session-course-mismatch/],
      [session({ title: 42 }), /legacy-session-metadata-invalid/],
      [session({ focusItemIDs: ["foreign:item"] }), /legacy-session-reference-unverifiable/],
      [session({
        messages: [{
          id: randomUUID(),
          role: "user",
          text: "跨课程来源",
          sources: [{
            id: randomUUID(),
            courseID: otherCourseID,
            kind: "selection",
            title: "跨课程来源",
            label: "[1]",
            excerpt: "不得迁移",
          }],
          createdAt,
        }],
      }), /legacy-session-reference-mismatch/],
      [session({
        messages: [{
          id: randomUUID(),
          role: "user",
          text: "错误 origin",
          origin: { requestID: randomUUID(), courseID, chatID: randomUUID() },
          createdAt,
        }],
      }), /legacy-session-reference-mismatch/],
    ];
    const workspaceBefore = await readFile(path.join(directory, "workspace.json"));
    for (const [value, expected] of invalidCases) {
      await assert.rejects(
        store.migrateLegacyCourseSessions(courseID, [value]),
        expected,
      );
      await assert.rejects(
        readFile(sessionFile(directory, value.id as string)),
        isNodeErrorCode("ENOENT"),
      );
    }
    assert.deepEqual(
      await readFile(path.join(directory, "workspace.json")),
      workspaceBefore,
    );
    const precedence = session({
      courseID: otherCourseID,
      scopeNeedsReview: true,
    });
    await store.migrateLegacyCourseSessions(courseID, [precedence]);
    const persisted = decodePersistedWorkspace(
      await readFile(path.join(directory, "workspace.json")),
    );
    assert.deepEqual(
      objectArray(persisted.studySessions)[0].relatedCourseIDs,
      [courseID],
    );
    assert.deepEqual(await store.listForCourse(otherCourseID), []);
  });
});

test("legacy migration rejects invalid matched destination metadata before body writes", async () => {
  await withWorkspace(async (directory) => {
    const courseID = randomUUID();
    const sessionID = randomUUID();
    const createdAt = swiftReferenceSecondsFromDate(
      new Date("2025-02-03T04:05:06.000Z"),
    );
    const message: SwiftJSONObject = {
      id: randomUUID(),
      role: "user",
      text: "唯一可读正文",
      createdAt,
    };
    const workspacePath = path.join(directory, "workspace.json");
    await writeFile(
      workspacePath,
      stringifySwiftJSON({
        importedItems: [],
        notesByItemID: {},
        studySessions: [{
          id: sessionID,
          title: 42,
          messages: [message],
          relatedCourseIDs: [courseID],
          createdAt,
          updatedAt: createdAt,
          messageCount: 1,
        }],
      }, { trailingNewline: true }),
      "utf8",
    );
    const store = await StudySessionStore.open(directory);
    const before = await readFile(workspacePath);
    await assert.rejects(
      store.migrateLegacyCourseSessions(courseID, [{
        id: sessionID,
        title: "合法 v1 标题",
        messages: [message],
        relatedCourseIDs: [courseID],
        createdAt,
        updatedAt: createdAt,
        messageCount: 1,
      }]),
      /legacy-session-metadata-invalid/,
    );
    assert.deepEqual(await readFile(workspacePath), before);
    await assert.rejects(
      readFile(sessionFile(directory, sessionID)),
      isNodeErrorCode("ENOENT"),
    );
  });
});

test("legacy migration context preserves valid rich portable references exactly", async () => {
  await withWorkspace(async (directory) => {
    const store = await StudySessionStore.open(directory);
    const courseID = randomUUID();
    const sessionID = randomUUID();
    const noteItemID = "note:portable";
    const materialItemID = "material:portable";
    const memoryID = randomUUID();
    const relationID = randomUUID();
    const createdAt = swiftReferenceSecondsFromDate(
      new Date("2025-02-03T04:05:06.000Z"),
    );
    const message: SwiftJSONObject = {
      id: randomUUID(),
      role: "assistant",
      text: "完整保留课程内引用",
      toolTrace: [],
      sources: [{
        id: randomUUID(),
        itemID: materialItemID,
        courseID,
        kind: "material",
        title: "课程材料",
        label: "[1]",
        excerpt: "完整保留",
        futureSourceField: { keep: true },
      }],
      actions: [{
        id: randomUUID(),
        kind: "createRelation",
        state: "executed",
        targetItemID: noteItemID,
        sourceItemID: materialItemID,
        createdRelationID: relationID,
        evidence: ["完整保留"],
        createdAt,
        updatedAt: createdAt,
        futureActionField: 9_007_199_254_740_995n,
      }],
      memoryUpdate: {
        memoryIDs: [memoryID],
        summary: "保留课程 memory",
      },
      origin: {
        requestID: randomUUID(),
        courseID,
        chatID: sessionID,
        futureOriginField: "keep",
      },
      createdAt,
      futureMessageField: { exact: true },
    };
    const legacy: SwiftJSONObject = {
      id: sessionID,
      title: "引用保留",
      messages: [message],
      relatedCourseIDs: [courseID],
      focusItemIDs: [noteItemID],
      materialItemID,
      createdAt,
      updatedAt: createdAt,
      messageCount: 1,
      futureSessionField: { exact: true },
    };

    await store.migrateLegacyCourseSessions(courseID, [legacy], {
      itemIDs: [noteItemID, materialItemID],
      noteItemIDs: [noteItemID],
      materialItemIDs: [materialItemID],
      memoryIDs: [memoryID],
      relations: [{
        id: relationID,
        noteItemID,
        sourceItemID: materialItemID,
      }],
    });
    const workspace = decodePersistedWorkspace(
      await readFile(path.join(directory, "workspace.json")),
    );
    const metadata = objectArray(workspace.studySessions)[0];
    assert.deepEqual(metadata.focusItemIDs, [noteItemID]);
    assert.equal(metadata.materialItemID, materialItemID);
    assert.deepEqual(metadata.futureSessionField, { exact: true });
    const persistedMessage = objectArray(
      (await readSwiftObject(sessionFile(directory, sessionID))).messages,
    )[0];
    assert.deepEqual(persistedMessage, message);
  });
});

test("legacy migration rejects Swift decodeLossy rich-field failures without writes", async () => {
  await withWorkspace(async (directory) => {
    const store = await StudySessionStore.open(directory);
    const courseID = randomUUID();
    const createdAt = swiftReferenceSecondsFromDate(
      new Date("2025-02-03T04:05:06.000Z"),
    );
    const source = (overrides: SwiftJSONObject = {}): SwiftJSONObject => ({
      id: randomUUID(),
      courseID,
      kind: "selection",
      title: "来源",
      label: "[1]",
      excerpt: "原始证据",
      ...overrides,
    });
    const action = (overrides: SwiftJSONObject = {}): SwiftJSONObject => ({
      id: randomUUID(),
      kind: "writeNote",
      state: "pending",
      evidence: [],
      createdAt,
      updatedAt: createdAt,
      ...overrides,
    });
    const legacy = (messageOverrides: SwiftJSONObject): SwiftJSONObject => ({
      id: randomUUID(),
      title: "富字段损坏必须 hold",
      messages: [{
        id: randomUUID(),
        role: "assistant",
        text: "保留在 v1",
        createdAt,
        ...messageOverrides,
      }],
      relatedCourseIDs: [courseID],
      createdAt,
      updatedAt: createdAt,
      messageCount: 1,
    });
    const invalid = [
      legacy({ source: 7 }),
      legacy({ backend: "future-backend" }),
      legacy({ completionState: "future-state" }),
      legacy({ failureKind: "future-failure" }),
      legacy({ retryQuestion: 7 }),
      legacy({ contentBlocks: [{ text: { _0: 7 } }] }),
      legacy({ sources: [source({ title: 7 })] }),
      legacy({ sources: [source({ pageIndex: "one" })] }),
      legacy({ actions: [action({ evidence: "not-an-array" })] }),
      legacy({ memoryUpdate: { memoryIDs: [], summary: 7 } }),
      legacy({ profileUpdate: { entryIDs: [], summary: "摘要", texts: 7 } }),
      legacy({ origin: { chatID: randomUUID(), courseID } }),
    ];
    const workspacePath = path.join(directory, "workspace.json");
    const before = await readFile(workspacePath);
    for (const value of invalid) {
      await assert.rejects(
        store.migrateLegacyCourseSessions(courseID, [value]),
        /legacy-session-message-invalid/,
      );
      await assert.rejects(
        readFile(sessionFile(directory, value.id as string)),
        isNodeErrorCode("ENOENT"),
      );
    }
    assert.deepEqual(await readFile(workspacePath), before);
  });
});

test("legacy migration context rejects every invalid project reference transactionally", async () => {
  await withWorkspace(async (directory) => {
    const store = await StudySessionStore.open(directory);
    const courseID = randomUUID();
    const otherCourseID = randomUUID();
    const noteItemID = "note:portable";
    const materialItemID = "material:portable";
    const memoryID = randomUUID();
    const relationID = randomUUID();
    const createdAt = swiftReferenceSecondsFromDate(
      new Date("2025-02-03T04:05:06.000Z"),
    );
    const context = {
      itemIDs: [noteItemID, materialItemID],
      noteItemIDs: [noteItemID],
      materialItemIDs: [materialItemID],
      memoryIDs: [memoryID],
      relations: [{ id: relationID, noteItemID, sourceItemID: materialItemID }],
    };
    const source = (overrides: SwiftJSONObject = {}): SwiftJSONObject => ({
      id: randomUUID(),
      kind: "material",
      title: "课程材料",
      label: "[1]",
      excerpt: "引用校验",
      ...overrides,
    });
    const action = (overrides: SwiftJSONObject = {}): SwiftJSONObject => ({
      id: randomUUID(),
      kind: "writeNote",
      state: "pending",
      evidence: ["引用校验"],
      createdAt,
      updatedAt: createdAt,
      ...overrides,
    });
    const session = (
      sessionID: string,
      sessionOverrides: SwiftJSONObject = {},
      messageOverrides: SwiftJSONObject = {},
    ): SwiftJSONObject => ({
      id: sessionID,
      title: "非法引用必须 hold",
      messages: [{
        id: randomUUID(),
        role: "user",
        text: "原始证据不能被清理",
        createdAt,
        ...messageOverrides,
      }],
      relatedCourseIDs: [courseID],
      focusItemIDs: [],
      createdAt,
      updatedAt: createdAt,
      messageCount: 1,
      ...sessionOverrides,
    });
    const invalidSessions = [
      session(randomUUID(), { focusItemIDs: ["foreign:item"] }),
      session(randomUUID(), { materialItemID: "foreign:item" }),
      session(randomUUID(), {}, { toolTrace: ["must-not-drop"] }),
      session(randomUUID(), {}, {
        sources: [source({ itemID: "foreign:item", courseID })],
      }),
      session(randomUUID(), {}, {
        sources: [source({ itemID: materialItemID, courseID: otherCourseID })],
      }),
      session(randomUUID(), {}, {
        actions: [action({ targetItemID: materialItemID })],
      }),
      session(randomUUID(), {}, {
        actions: [action({
          kind: "createRelation",
          targetItemID: noteItemID,
          sourceItemID: materialItemID,
          createdRelationID: randomUUID(),
        })],
      }),
      session(randomUUID(), {}, {
        memoryUpdate: { memoryIDs: [randomUUID()], summary: "非法 memory" },
      }),
      session(randomUUID(), {}, {
        origin: { requestID: randomUUID(), courseID, chatID: randomUUID() },
      }),
    ];
    const workspaceBefore = await readFile(path.join(directory, "workspace.json"));
    for (const legacy of invalidSessions) {
      await assert.rejects(
        store.migrateLegacyCourseSessions(courseID, [legacy], context),
        /legacy-session-reference-mismatch/,
      );
      await assert.rejects(
        readFile(sessionFile(directory, legacy.id as string)),
        isNodeErrorCode("ENOENT"),
      );
    }
    assert.deepEqual(
      await readFile(path.join(directory, "workspace.json")),
      workspaceBefore,
    );
  });
});

test("legacy migration preserves legacy-only metadata and rejects unknown-field forks", async () => {
  await withWorkspace(async (directory) => {
    const store = await StudySessionStore.open(directory);
    const courseID = randomUUID();
    const session = await store.create(courseID);
    const createdAt = swiftReferenceSecondsFromDate(
      new Date("2025-02-03T04:05:06.000Z"),
    );
    const message: SwiftJSONObject = {
      id: randomUUID(),
      role: "user",
      text: "保留 forward metadata",
      createdAt,
    };
    const legacy = (futureValue: string): SwiftJSONObject => ({
      id: session.id,
      title: "旧标题",
      messages: [message],
      relatedCourseIDs: [courseID],
      createdAt,
      updatedAt: createdAt,
      messageCount: 1,
      futureSessionField: { mustKeep: futureValue },
    });

    await store.migrateLegacyCourseSessions(courseID, [legacy("LEGACY_ONLY")]);
    const workspace = decodePersistedWorkspace(
      await readFile(path.join(directory, "workspace.json")),
    );
    assert.deepEqual(
      objectArray(workspace.studySessions)[0].futureSessionField,
      { mustKeep: "LEGACY_ONLY" },
    );
    const payloadPath = sessionFile(directory, session.id);
    const payloadBefore = await readFile(payloadPath);
    await assert.rejects(
      store.migrateLegacyCourseSessions(courseID, [legacy("FORK")]),
      /existing-session-metadata-conflict/,
    );
    assert.deepEqual(await readFile(payloadPath), payloadBefore);
  });
});

test("open rejects a preexisting Sessions symlink without writing its target", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "weibei-session-root-"));
  const outside = await mkdtemp(path.join(os.tmpdir(), "weibei-session-outside-"));
  try {
    await symlink(
      outside,
      path.join(directory, "Sessions"),
      process.platform === "win32" ? "junction" : "dir",
    );
    await assert.rejects(
      StudySessionStore.open(directory),
      /unsafe-sessions-directory/,
    );
    assert.deepEqual(await readdir(outside), []);
  } finally {
    await rm(directory, { recursive: true, force: true });
    await rm(outside, { recursive: true, force: true });
  }
});

test("create and append reject a replaced Sessions directory without outside writes", async () => {
  const outside = await mkdtemp(path.join(os.tmpdir(), "weibei-session-outside-"));
  try {
    await withWorkspace(async (directory) => {
      const courseID = randomUUID();
      const store = await StudySessionStore.open(directory);
      const session = await store.create(courseID);
      const sessionsPath = path.join(directory, "Sessions");
      await rename(sessionsPath, path.join(directory, "Sessions-original"));
      await symlink(
        outside,
        sessionsPath,
        process.platform === "win32" ? "junction" : "dir",
      );

      await assert.rejects(store.create(courseID), /sessions-directory-conflict/);
      await assert.rejects(
        store.appendMessages(session.id, [agentMessage("user", "OUTSIDE_WRITE")]),
        /sessions-directory-conflict/,
      );
      assert.deepEqual(await readdir(outside), []);
    });
  } finally {
    await rm(outside, { recursive: true, force: true });
  }
});

test("identity-bound session placement rejects a Sessions swap after payload inspection", async () => {
  const createOutside = await mkdtemp(path.join(os.tmpdir(), "weibei-session-stage-"));
  const appendOutside = await mkdtemp(path.join(os.tmpdir(), "weibei-session-stage-"));
  try {
    await withWorkspace(async (directory) => {
      const store = await StudySessionStore.open(directory);
      const originalInspect = Reflect.get(
        store,
        "inspectSessionPayload",
      ) as (sessionID: string) => Promise<unknown>;
      let swapped = false;
      Reflect.set(store, "inspectSessionPayload", async (sessionID: string) => {
        const result = await originalInspect.call(store, sessionID);
        if (!swapped) {
          swapped = true;
          await rename(
            path.join(directory, "Sessions"),
            path.join(directory, "Sessions-original"),
          );
          await symlink(
            createOutside,
            path.join(directory, "Sessions"),
            process.platform === "win32" ? "junction" : "dir",
          );
        }
        return result;
      });
      await assert.rejects(store.create(randomUUID()), /directory-identity-conflict/);
      assert.equal(swapped, true);
      assert.deepEqual(await readdir(createOutside), []);
    });

    await withWorkspace(async (directory) => {
      const courseID = randomUUID();
      const store = await StudySessionStore.open(directory);
      const session = await store.create(courseID);
      await store.appendMessages(session.id, [agentMessage("user", "BASELINE")]);
      const payloadName = `${session.id.toLowerCase()}.json`;
      const outsidePayload = path.join(appendOutside, payloadName);
      const baseline = await readFile(sessionFile(directory, session.id));
      await writeFile(outsidePayload, baseline);
      const originalInspect = Reflect.get(
        store,
        "inspectSessionPayload",
      ) as (sessionID: string) => Promise<unknown>;
      let inspections = 0;
      Reflect.set(store, "inspectSessionPayload", async (sessionID: string) => {
        const result = await originalInspect.call(store, sessionID);
        inspections += 1;
        if (inspections === 2) {
          await rename(
            path.join(directory, "Sessions"),
            path.join(directory, "Sessions-original"),
          );
          await symlink(
            appendOutside,
            path.join(directory, "Sessions"),
            process.platform === "win32" ? "junction" : "dir",
          );
        }
        return result;
      });
      await assert.rejects(
        store.appendMessages(session.id, [agentMessage("assistant", "MUST_NOT_ESCAPE")]),
        /directory-identity-conflict/,
      );
      assert.equal(inspections, 2);
      assert.deepEqual(await readFile(outsidePayload), baseline);
    });
  } finally {
    await rm(createOutside, { recursive: true, force: true });
    await rm(appendOutside, { recursive: true, force: true });
  }
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

function isNodeErrorCode(code: string): (error: unknown) => boolean {
  return (error: unknown): boolean =>
    error instanceof Error
    && "code" in error
    && error.code === code;
}
