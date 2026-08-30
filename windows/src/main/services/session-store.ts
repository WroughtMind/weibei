import { randomUUID } from "node:crypto";
import { lstat, mkdir, readFile, readdir, realpath } from "node:fs/promises";
import path from "node:path";
import type { AgentMessage, StudySession } from "../../shared/contracts";
import {
  assertVerifiedDirectoryIdentity,
  atomicCreateVerified,
  atomicReplaceVerified,
  recoverAtomicReplace,
  type VerifiedDirectoryIdentity,
} from "./file-utils";
import {
  dateFromSwiftReferenceSeconds,
  parseSwiftJSON,
  stringifySwiftJSON,
  swiftReferenceSecondsFromDate,
  type PersistedWorkspaceRecord,
  type SwiftJSONObject,
  type SwiftJSONValue,
} from "./swift-codec";
import { WorkspacePersistence } from "./workspace-persistence";

type SessionPayloadInspection =
  | { status: "valid"; payload: SwiftJSONObject; contents: string }
  | { status: "missing"; payload: null; contents: null }
  | { status: "invalid"; payload: null; contents: null };

export interface LegacySessionMigrationContext {
  itemIDs: readonly string[];
  noteItemIDs: readonly string[];
  materialItemIDs: readonly string[];
  memoryIDs: readonly string[];
  relations: ReadonlyArray<{
    id: string;
    noteItemID: string;
    sourceItemID: string;
  }>;
}

interface SessionDirectoryIdentity {
  workspacePath: string;
  workspaceDev: bigint;
  workspaceIno: bigint;
  sessionsPath: string;
  sessionsDev: bigint;
  sessionsIno: bigint;
}

export class StudySessionStore {
  private readonly workspaceDirectory: string;
  private readonly sessionsDirectory: string;
  private persistence: WorkspacePersistence;
  private workspace: PersistedWorkspaceRecord = { importedItems: [], notesByItemID: {} };
  private queue: Promise<void> = Promise.resolve();
  private directoryIdentity: SessionDirectoryIdentity | null = null;

  private constructor(workspaceDirectory: string) {
    this.workspaceDirectory = path.resolve(workspaceDirectory);
    this.sessionsDirectory = path.join(this.workspaceDirectory, "Sessions");
    this.persistence = new WorkspacePersistence(this.workspaceDirectory);
  }

  static async open(workspaceDirectory: string): Promise<StudySessionStore> {
    const store = new StudySessionStore(workspaceDirectory);
    await store.initializeDirectoryIdentity();
    store.persistence = new WorkspacePersistence({
      workspaceDirectory: store.workspaceDirectory,
      expectedParent: store.workspaceIOIdentity(),
    });
    const loaded = await store.persistence.load();
    store.workspace = loaded.snapshot ?? { importedItems: [], notesByItemID: {} };
    if (loaded.needsPrimaryRewrite || !loaded.snapshot) {
      await store.assertDirectoryIdentity();
      await store.persistence.save(store.workspace);
    }
    await store.recoverInterruptedSessionTransactions();
    await store.interruptOrphanedGeneratingMessages();
    return store;
  }

  async listForCourse(courseID: string): Promise<StudySession[]> {
    return this.runExclusive(async () => {
      const sessions = readableSessionRecords(this.workspace)
        .filter((raw) => sessionCourseIDs(raw).some((value) =>
          sameUUID(value, courseID)));
      const result: StudySession[] = [];
      for (const raw of sessions) {
        try {
          result.push(await this.hydrateSession(raw));
        } catch {
          // One damaged session file never blocks the rest or app launch.
        }
      }
      return result.sort((left, right) => right.updatedAt.localeCompare(left.updatedAt));
    });
  }

  async get(sessionID: string): Promise<StudySession | null> {
    return this.runExclusive(async () => {
      const raw = readableSessionRecords(this.workspace)
        .find((entry) => sameUUID(entry.id, sessionID));
      if (!raw) return null;
      try { return await this.hydrateSession(raw); } catch { return null; }
    });
  }

  async create(courseID: string): Promise<StudySession> {
    return this.runExclusive(async () => {
      const existingSessions = sessionRecordsFailingOnDuplicateIDs(this.workspace);
      const now = new Date();
      const session: StudySession = {
        id: randomUUID(),
        title: "新 Chat",
        courseId: courseID,
        itemId: null,
        messages: [],
        createdAt: now.toISOString(),
        updatedAt: now.toISOString(),
      };
      const raw: SwiftJSONObject = {
        id: session.id,
        title: session.title,
        titleSetByUser: false,
        messages: [],
        summary: "",
        relatedCourseIDs: [courseID],
        focusItemIDs: [],
        flow: { phase: "orient", pinnedByUser: false, suggestedNext: [] },
        createdAt: swiftReferenceSecondsFromDate(now),
        updatedAt: swiftReferenceSecondsFromDate(now),
        messageCount: 0,
      };
      await this.persistSessionMessages(
        session.id,
        [],
        null,
        { status: "missing", payload: null, contents: null },
      );
      await this.commitWorkspace({
        ...this.workspace,
        studySessions: [...existingSessions, raw],
      });
      return session;
    });
  }

  /**
   * Externalize Chat bodies embedded by portable course schema v1 before the
   * course is rewritten as v2. Histories merge only when either raw message
   * sequence is a complete prefix of the other; the longer append-only body
   * wins, while a deletion, damaged body, or fork holds the v1 course.
   */
  async migrateLegacyCourseSessions(
    courseID: string,
    legacySessions: readonly SwiftJSONObject[],
    context?: LegacySessionMigrationContext,
  ): Promise<void> {
    requiredUUID(courseID);
    return this.runExclusive(async () => {
      if (legacySessions.length === 0) return;

      const existingRecords = sessionRecordsFailingOnDuplicateIDs(this.workspace);
      // Migration can let the caller retire the only portable v1 copy. Ensure
      // every destination record remains Swift-decodable before writing any
      // external body, including records unrelated to this migration batch.
      for (const existing of existingRecords) {
        validateLegacySessionMetadata(existing);
        validatedMessageArray(existing.messages, true);
        messageCountValue(existing.messageCount);
      }
      const values: SwiftJSONValue[] = [...existingRecords];
      const indexes = new Map<string, number>();
      for (const [index, raw] of existingRecords.entries()) {
        indexes.set(normalizedIdentifier(requiredUUID(raw.id)), index);
      }

      const preparedLegacy: Array<{
        legacy: SwiftJSONObject;
        sessionID: string;
        key: string;
        messages: SwiftJSONValue[];
        declaredMessageCount: bigint;
      }> = [];
      const migrated = new Set<string>();
      for (const legacyValue of legacySessions) {
        const rawLegacy = asObject(legacyValue);
        const sessionID = requiredUUID(rawLegacy.id);
        const key = normalizedIdentifier(sessionID);
        if (migrated.has(key)) throw new Error("duplicate-legacy-session-id");
        migrated.add(key);
        const rawMessages = validatedMessageArray(rawLegacy.messages, true);
        validateLegacySessionMetadata(rawLegacy);
        const { legacy, messages } = validatedLegacySessionForCourse(
          rawLegacy,
          rawMessages,
          courseID,
          context,
        );
        preparedLegacy.push({
          legacy,
          sessionID,
          key,
          messages,
          declaredMessageCount: messageCountValue(legacy.messageCount),
        });
      }

      const plans: Array<{
        sessionID: string;
        existingIndex: number | undefined;
        messages: SwiftJSONValue[];
        metadata: SwiftJSONObject;
        existingPayload: SwiftJSONObject | null;
        payloadBaseline: Exclude<SessionPayloadInspection, { status: "invalid" }>;
      }> = [];
      for (const prepared of preparedLegacy) {
        const {
          legacy,
          sessionID,
          key,
          messages: legacyMessages,
          declaredMessageCount: legacyDeclaredMessageCount,
        } = prepared;
        const existingIndex = indexes.get(key);
        const existing = existingIndex === undefined
          ? null
          : asObject(values[existingIndex]);
        if (existing) validateLegacySessionMetadata(existing);
        // Inspect even when metadata is absent: a previous attempt can leave a
        // durably written body before workspace.json commits. Only an exact
        // append-only prefix may merge; a missing, damaged, or forked body must
        // hold the v1 course rather than discard either version.
        const inspected = await this.inspectSessionPayload(sessionID);
        if (inspected.status === "invalid") {
          throw new Error("existing-session-payload-invalid");
        }

        const embeddedExistingMessages = existing && !inspected.payload
          ? validatedMessageArray(existing.messages, true)
          : [];
        const existingMessages = inspected.payload
          ? validatedMessageArray(inspected.payload.messages, false)
          : embeddedExistingMessages;
        const existingDeclaredMessageCount = existing
          ? messageCountValue(existing.messageCount)
          : 0n;
        if (
          existing
          && BigInt(existingMessages.length) < existingDeclaredMessageCount
        ) {
          throw new Error("existing-session-payload-missing");
        }
        const messages = mergeAppendOnlyMessages(existingMessages, legacyMessages);
        if (BigInt(messages.length) < legacyDeclaredMessageCount) {
          throw new Error("legacy-session-body-missing");
        }
        const metadata: SwiftJSONObject = {
          ...mergedSessionMetadata(existing, legacy),
          relatedCourseIDs: mergedCourseIDs(
            existing,
            legacy,
            courseID,
          ),
          messages: [],
          messageCount: messages.length,
        };

        plans.push({
          sessionID,
          existingIndex,
          messages,
          metadata,
          existingPayload: inspected.payload,
          payloadBaseline: inspected,
        });
      }

      for (const plan of plans) {
        await this.persistSessionMessages(
          plan.sessionID,
          plan.messages,
          plan.existingPayload,
          plan.payloadBaseline,
        );
        if (plan.existingIndex === undefined) {
          values.push(plan.metadata);
        } else {
          values[plan.existingIndex] = plan.metadata;
        }
      }

      const nextWorkspace: PersistedWorkspaceRecord = {
        ...this.workspace,
        studySessions: values,
      };
      await this.commitWorkspace(nextWorkspace);
    });
  }

  async appendMessages(sessionID: string, messages: readonly AgentMessage[]): Promise<StudySession> {
    return this.runExclusive(async () => {
      const records = sessionRecordsFailingOnDuplicateIDs(this.workspace);
      const index = records.findIndex((entry) => sameUUID(entry.id, sessionID));
      if (index < 0) throw new Error("session-not-found");
      const inspected = await this.inspectSessionPayloadForMutation(
        sessionID,
        records[index],
      );
      const payload = inspected.payload;
      const current = await this.hydrateSession(records[index], payload);
      const rawMessages = [
        ...rawMessagesForSession(records[index], payload),
        ...messages.map(messageToRaw),
      ];
      const updated: StudySession = {
        ...current,
        messages: [...current.messages, ...messages],
        updatedAt: new Date().toISOString(),
      };
      if (current.messages.filter((message) => message.role === "user").length === 0) {
        const firstQuestion = messages.find((message) => message.role === "user")?.text.trim();
        if (firstQuestion) updated.title = sessionTitle(firstQuestion);
      }
      records[index] = updateSessionMetadata(records[index], updated, rawMessages.length);
      // Swift commit order: external session body before workspace metadata.
      await this.persistSessionMessages(sessionID, rawMessages, payload, inspected);
      await this.commitWorkspace({ ...this.workspace, studySessions: records });
      return updated;
    });
  }

  async updateMessage(sessionID: string, message: AgentMessage): Promise<StudySession> {
    return this.runExclusive(async () => {
      const records = sessionRecordsFailingOnDuplicateIDs(this.workspace);
      const index = records.findIndex((entry) => sameUUID(entry.id, sessionID));
      if (index < 0) throw new Error("session-not-found");
      const inspected = await this.inspectSessionPayloadForMutation(
        sessionID,
        records[index],
      );
      const payload = inspected.payload;
      const current = await this.hydrateSession(records[index], payload);
      const messageIndex = current.messages.findIndex((entry) => sameUUID(entry.id, message.id));
      if (messageIndex < 0) throw new Error("message-not-found");
      const messages = [...current.messages];
      messages[messageIndex] = message;
      const rawMessages = rawMessagesForSession(records[index], payload);
      const rawMessageIndex = rawMessages.findIndex((entry) => {
        try { return sameUUID(asObject(entry).id, message.id); } catch { return false; }
      });
      if (rawMessageIndex < 0) throw new Error("message-not-found");
      rawMessages[rawMessageIndex] = mergeMessageRaw(asObject(rawMessages[rawMessageIndex]), message);
      const updated = { ...current, messages, updatedAt: new Date().toISOString() };
      records[index] = updateSessionMetadata(records[index], updated, rawMessages.length);
      await this.persistSessionMessages(sessionID, rawMessages, payload, inspected);
      await this.commitWorkspace({ ...this.workspace, studySessions: records });
      return updated;
    });
  }

  private async hydrateSession(
    raw: SwiftJSONObject,
    loadedPayload?: SwiftJSONObject | null,
  ): Promise<StudySession> {
    const id = requiredUUID(raw.id);
    let messages: AgentMessage[] = [];
    const payload = loadedPayload === undefined
      ? await this.readSessionPayload(id)
      : loadedPayload;
    messages = rawMessagesForSession(raw, payload).flatMap((entry) => {
      try { return [messageFromRaw(asObject(entry))]; } catch { return []; }
    });
    const related = sessionCourseIDs(raw);
    const focus = stringArray(raw.focusItemIDs);
    return {
      id,
      title: typeof raw.title === "string" ? raw.title : "Chat",
      courseId: related.length === 1 && isUUID(related[0]) ? related[0] : null,
      itemId: typeof raw.materialItemID === "string" ? raw.materialItemID : focus[0] ?? null,
      messages,
      createdAt: dateFromRaw(raw.createdAt).toISOString(),
      updatedAt: dateFromRaw(raw.updatedAt ?? raw.createdAt).toISOString(),
    };
  }

  private async readSessionPayload(sessionID: string): Promise<SwiftJSONObject | null> {
    try {
      await this.assertDirectoryIdentity();
      await recoverAtomicReplace(
        this.sessionPath(sessionID),
        this.sessionsIOIdentity(),
      );
      await this.assertDirectoryIdentity();
      const contents = await readFile(this.sessionPath(sessionID), "utf8");
      await this.assertDirectoryIdentity();
      const payload = asObject(parseSwiftJSON(contents));
      if (!sameUUID(payload.sessionID, sessionID) || !Array.isArray(payload.messages)) {
        throw new Error("session-identity-mismatch");
      }
      return payload;
    } catch {
      return null;
    }
  }

  private async inspectSessionPayload(sessionID: string): Promise<
    SessionPayloadInspection
  > {
    // A replaced directory is a boundary violation, not a damaged payload.
    // Keep it outside the payload parser's isolation catch so mutations report
    // and preserve the security conflict directly.
    await this.assertDirectoryIdentity();
    try {
      await recoverAtomicReplace(
        this.sessionPath(sessionID),
        this.sessionsIOIdentity(),
      );
      await this.assertDirectoryIdentity();
      const contents = await readFile(this.sessionPath(sessionID), "utf8");
      await this.assertDirectoryIdentity();
      const payload = asObject(parseSwiftJSON(contents));
      if (!sameUUID(payload.sessionID, sessionID)) {
        return { status: "invalid", payload: null, contents: null };
      }
      validatedMessageArray(payload.messages, false);
      return { status: "valid", payload, contents };
    } catch (error) {
      if (isNodeError(error) && error.code === "ENOENT") {
        return { status: "missing", payload: null, contents: null };
      }
      return { status: "invalid", payload: null, contents: null };
    }
  }

  private async inspectSessionPayloadForMutation(
    sessionID: string,
    metadata: SwiftJSONObject,
  ): Promise<Exclude<SessionPayloadInspection, { status: "invalid" }>> {
    const inspected = await this.inspectSessionPayload(sessionID);
    if (inspected.status === "invalid") {
      throw new Error("session-payload-invalid");
    }
    const messages = inspected.status === "valid"
      ? validatedMessageArray(inspected.payload.messages, false)
      : validatedMessageArray(metadata.messages, true);
    if (BigInt(messages.length) < messageCountValue(metadata.messageCount)) {
      throw new Error("session-payload-missing");
    }
    return inspected;
  }

  private async persistSessionMessages(
    sessionID: string,
    messages: readonly SwiftJSONValue[],
    existingPayload: SwiftJSONObject | null,
    expectedPayload: Exclude<SessionPayloadInspection, { status: "invalid" }>,
  ): Promise<void> {
    await this.assertDirectoryIdentity();
    if (expectedPayload) {
      const current = await this.inspectSessionPayload(sessionID);
      if (!sameSessionPayloadBaseline(expectedPayload, current)) {
        throw new Error("session-payload-changed");
      }
    }
    const payload: SwiftJSONObject = {
      ...(existingPayload ?? { schemaVersion: 1, sessionID }),
      messages: [...messages],
    };
    const serialized = stringifySwiftJSON(payload, { sortKeys: true });
    if (expectedPayload.status === "missing") {
      await atomicCreateVerified(
        this.sessionPath(sessionID),
        serialized,
        this.sessionsIOIdentity(),
      );
    } else {
      await atomicReplaceVerified(
        this.sessionPath(sessionID),
        expectedPayload.contents,
        serialized,
        this.sessionsIOIdentity(),
      );
    }
    await this.assertDirectoryIdentity();
    const verifiedContents = await readFile(this.sessionPath(sessionID), "utf8");
    await this.assertDirectoryIdentity();
    const verified = asObject(parseSwiftJSON(verifiedContents));
    if (!sameUUID(verified.sessionID, sessionID) || !Array.isArray(verified.messages) || verified.messages.length !== messages.length) {
      throw new Error("session-write-verification-failed");
    }
  }

  private sessionPath(sessionID: string): string {
    return path.join(this.sessionsDirectory, `${requiredUUID(sessionID).toLocaleLowerCase("en-US")}.json`);
  }

  private async initializeDirectoryIdentity(): Promise<void> {
    await mkdir(this.workspaceDirectory, { recursive: true });
    try {
      await mkdir(this.sessionsDirectory, { recursive: false, mode: 0o700 });
    } catch (error) {
      if (!isNodeError(error) || error.code !== "EEXIST") throw error;
    }
    const [workspaceInfo, sessionsInfo, workspacePath, sessionsPath] = await Promise.all([
      lstat(this.workspaceDirectory, { bigint: true }),
      lstat(this.sessionsDirectory, { bigint: true }),
      realpath(this.workspaceDirectory),
      realpath(this.sessionsDirectory),
    ]);
    if (
      !workspaceInfo.isDirectory()
      || workspaceInfo.isSymbolicLink()
      || !sessionsInfo.isDirectory()
      || sessionsInfo.isSymbolicLink()
      || !sameFilesystemPath(path.dirname(sessionsPath), workspacePath)
    ) {
      throw new Error("unsafe-sessions-directory");
    }
    this.directoryIdentity = {
      workspacePath,
      workspaceDev: workspaceInfo.dev,
      workspaceIno: workspaceInfo.ino,
      sessionsPath,
      sessionsDev: sessionsInfo.dev,
      sessionsIno: sessionsInfo.ino,
    };
    await this.assertDirectoryIdentity();
  }

  private async assertDirectoryIdentity(): Promise<void> {
    const expected = this.directoryIdentity;
    if (!expected) throw new Error("unsafe-sessions-directory");
    try {
      await Promise.all([
        assertVerifiedDirectoryIdentity(this.workspaceIOIdentity()),
        assertVerifiedDirectoryIdentity(this.sessionsIOIdentity()),
      ]);
    } catch {
      throw new Error("sessions-directory-conflict");
    }
    const [workspaceInfo, sessionsInfo, workspacePath, sessionsPath] = await Promise.all([
      lstat(this.workspaceDirectory, { bigint: true }),
      lstat(this.sessionsDirectory, { bigint: true }),
      realpath(this.workspaceDirectory),
      realpath(this.sessionsDirectory),
    ]);
    if (
      !workspaceInfo.isDirectory()
      || workspaceInfo.isSymbolicLink()
      || workspaceInfo.dev !== expected.workspaceDev
      || workspaceInfo.ino !== expected.workspaceIno
      || !sessionsInfo.isDirectory()
      || sessionsInfo.isSymbolicLink()
      || sessionsInfo.dev !== expected.sessionsDev
      || sessionsInfo.ino !== expected.sessionsIno
      || !sameFilesystemPath(workspacePath, expected.workspacePath)
      || !sameFilesystemPath(sessionsPath, expected.sessionsPath)
      || !sameFilesystemPath(path.dirname(sessionsPath), workspacePath)
    ) {
      throw new Error("sessions-directory-conflict");
    }
  }

  private workspaceIOIdentity(): VerifiedDirectoryIdentity {
    const identity = this.directoryIdentity;
    if (!identity) throw new Error("unsafe-sessions-directory");
    return {
      absolutePath: identity.workspacePath,
      dev: identity.workspaceDev,
      ino: identity.workspaceIno,
    };
  }

  private sessionsIOIdentity(): VerifiedDirectoryIdentity {
    const identity = this.directoryIdentity;
    if (!identity) throw new Error("unsafe-sessions-directory");
    return {
      absolutePath: identity.sessionsPath,
      dev: identity.sessionsDev,
      ino: identity.sessionsIno,
    };
  }

  private async recoverInterruptedSessionTransactions(): Promise<void> {
    await this.assertDirectoryIdentity();
    if (!Array.isArray(this.workspace.studySessions)) return;
    const recovered = new Set<string>();
    for (const value of this.workspace.studySessions) {
      let id: string;
      try {
        id = requiredUUID(asObject(value).id);
      } catch {
        // Public reads/mutations validate the record; recovery can still
        // restore every other independently identifiable session at launch.
        continue;
      }
      const key = normalizedIdentifier(id);
      if (recovered.has(key)) continue;
      recovered.add(key);
      await recoverAtomicReplace(
        this.sessionPath(id),
        this.sessionsIOIdentity(),
      );
    }
  }

  private async commitWorkspace(nextWorkspace: PersistedWorkspaceRecord): Promise<void> {
    try {
      await this.assertDirectoryIdentity();
      await this.persistence.save(nextWorkspace);
      this.workspace = nextWorkspace;
    } catch (error) {
      try {
        await this.assertDirectoryIdentity();
        const reloaded = await this.persistence.load();
        if (reloaded.snapshot) this.workspace = reloaded.snapshot;
      } catch {
        // The operation still fails closed. Keep the previous in-memory copy
        // when even the external winner cannot be loaded safely.
      }
      throw error;
    }
  }

  private async interruptOrphanedGeneratingMessages(): Promise<void> {
    // Scan independently so one corrupt JSON file is isolated by omission.
    await this.assertDirectoryIdentity();
    let names: string[] = [];
    try {
      names = await readdir(this.sessionsDirectory);
      await this.assertDirectoryIdentity();
    } catch { return; }
    for (const name of names.filter((value) => /^[0-9a-f-]{36}\.json$/i.test(value))) {
      try {
        const filePath = path.join(this.sessionsDirectory, name);
        await this.assertDirectoryIdentity();
        const contents = await readFile(filePath, "utf8");
        await this.assertDirectoryIdentity();
        const payload = asObject(parseSwiftJSON(contents));
        const fileSessionID = name.slice(0, -".json".length);
        if (!sameUUID(payload.sessionID, fileSessionID) || !Array.isArray(payload.messages)) continue;
        let changed = false;
        const next = payload.messages.map((entry, index, allMessages) => {
          const raw = asObject(entry);
          if (raw.completionState !== "generating") return raw;
          changed = true;
          const retryQuestion = typeof raw.retryQuestion === "string"
            ? raw.retryQuestion
            : precedingUserQuestion(allMessages, index);
          return {
            ...raw,
            completionState: "interrupted",
            failureKind: "cancelled",
            ...(retryQuestion === null ? {} : { retryQuestion }),
          } as SwiftJSONObject;
        });
        if (changed) {
          await this.assertDirectoryIdentity();
          await atomicReplaceVerified(
            filePath,
            contents,
            stringifySwiftJSON({ ...payload, messages: next }, { sortKeys: true }),
            this.sessionsIOIdentity(),
          );
        }
      } catch { /* preserve corrupt evidence and continue */ }
    }
  }

  private async runExclusive<T>(operation: () => Promise<T>): Promise<T> {
    const result = this.queue.then(operation, operation);
    this.queue = result.then(() => undefined, () => undefined);
    return result;
  }
}

function sessionRecordsFailingOnDuplicateIDs(
  workspace: PersistedWorkspaceRecord,
): SwiftJSONObject[] {
  const raw = workspace.studySessions;
  if (raw === undefined || raw === null) return [];
  if (!Array.isArray(raw)) throw new Error("invalid-workspace-sessions");
  const records: SwiftJSONObject[] = [];
  const ids = new Set<string>();
  for (const value of raw) {
    let record: SwiftJSONObject;
    let id: string;
    try {
      record = asObject(value);
      id = requiredUUID(record.id);
    } catch {
      throw new Error("invalid-workspace-session");
    }
    const key = normalizedIdentifier(id);
    if (ids.has(key)) throw new Error("duplicate-session-id");
    ids.add(key);
    records.push(record);
  }
  return records;
}
function readableSessionRecords(
  workspace: PersistedWorkspaceRecord,
): SwiftJSONObject[] {
  if (!Array.isArray(workspace.studySessions)) return [];
  const candidates: Array<{ key: string; record: SwiftJSONObject }> = [];
  const counts = new Map<string, number>();
  for (const value of workspace.studySessions) {
    try {
      const record = asObject(value);
      const key = normalizedIdentifier(requiredUUID(record.id));
      candidates.push({ key, record });
      counts.set(key, (counts.get(key) ?? 0) + 1);
    } catch {
      // Read-only surfaces isolate malformed unrelated metadata. Mutations use
      // the strict validator above and refuse to rewrite any such workspace.
    }
  }
  return candidates
    .filter(({ key }) => counts.get(key) === 1)
    .map(({ record }) => record);
}
function rawMessagesForSession(
  metadata: SwiftJSONObject,
  payload: SwiftJSONObject | null,
): SwiftJSONValue[] {
  const raw = payload?.messages ?? metadata.messages;
  return Array.isArray(raw) ? [...raw] : [];
}
function updateSessionMetadata(
  raw: SwiftJSONObject,
  session: StudySession,
  messageCount = session.messages.length,
): SwiftJSONObject {
  return {
    ...raw,
    title: session.title,
    messages: [],
    updatedAt: swiftReferenceSecondsFromDate(new Date(session.updatedAt)),
    messageCount,
  };
}
function messageFromRaw(raw: SwiftJSONObject): AgentMessage {
  const sources: AgentMessage["sources"] = Array.isArray(raw.sources) ? raw.sources.flatMap((entry, index): AgentMessage["sources"] => {
    try {
      const source = asObject(entry);
      return [{
        id: typeof source.id === "string" && isUUID(source.id) ? source.id : deterministicUUID(`${raw.id}:source:${index}`),
        itemId: typeof source.itemID === "string" ? source.itemID : null,
        courseId: typeof source.courseID === "string" && isUUID(source.courseID) ? source.courseID : null,
        kind: source.kind === "note" || source.kind === "selection" ? source.kind : "material",
        title: typeof source.title === "string" ? source.title : "来源",
        label: typeof source.label === "string" ? source.label : String(index + 1),
        excerpt: typeof source.excerpt === "string" ? source.excerpt : "",
        pageIndex: nonnegativeSafeInteger(source.pageIndex),
        sectionTitle: typeof source.sectionTitle === "string" ? source.sectionTitle : null,
        sectionLocationId: typeof source.sectionLocationID === "string" ? source.sectionLocationID : null,
      }];
    } catch { return []; }
  }) : [];
  const actions: AgentMessage["actions"] = Array.isArray(raw.actions) ? raw.actions.flatMap((entry): AgentMessage["actions"] => {
    try {
      const action = asObject(entry);
      return [{
        id: requiredUUID(action.id),
        state: action.state === "executed" || action.state === "cancelled" || action.state === "failed"
          ? action.state
          : "pending",
        targetItemId: typeof action.targetItemID === "string" ? action.targetItemID : null,
        sourceItemId: typeof action.sourceItemID === "string" ? action.sourceItemID : null,
        proposedMarkdown: typeof action.proposedMarkdown === "string" ? action.proposedMarkdown : "",
        evidence: stringArray(action.evidence),
        baselineContentDigest: typeof action.baselineContentDigest === "string" ? action.baselineContentDigest : null,
      }];
    } catch { return []; }
  }) : [];
  return {
    id: requiredUUID(raw.id),
    role: raw.role === "user" ? "user" : "assistant",
    text: typeof raw.text === "string" ? raw.text : "",
    completionState: raw.completionState === "generating" || raw.completionState === "interrupted" ? raw.completionState : "completed",
    sources,
    actions,
    failureKind: typeof raw.failureKind === "string" ? raw.failureKind : null,
    retryQuestion: typeof raw.retryQuestion === "string" ? raw.retryQuestion : null,
    createdAt: dateFromRaw(raw.createdAt).toISOString(),
  };
}
function messageToRaw(message: AgentMessage): SwiftJSONObject {
  const createdAt = swiftReferenceSecondsFromDate(new Date(message.createdAt));
  return {
    id: message.id,
    role: message.role,
    text: message.text,
    contentBlocks: message.text ? [{ text: { _0: message.text } }] : [],
    source: null,
    completionState: message.completionState,
    sources: message.sources.map(citationToRaw),
    actions: message.actions.map((action) => noteProposalToRaw(action, createdAt)),
    memoryUpdate: null,
    profileUpdate: null,
    origin: null,
    failureKind: message.failureKind,
    retryQuestion: message.retryQuestion,
    toolTrace: [],
    createdAt,
  };
}
function mergeMessageRaw(raw: SwiftJSONObject, message: AgentMessage): SwiftJSONObject {
  const current = messageFromRaw(raw);
  const next = { ...raw };
  if (current.role !== message.role) next.role = message.role;
  if (current.text !== message.text) next.text = message.text;
  if (current.completionState !== message.completionState) next.completionState = message.completionState;
  if (current.failureKind !== message.failureKind) next.failureKind = message.failureKind;
  if (current.retryQuestion !== message.retryQuestion) next.retryQuestion = message.retryQuestion;
  if (current.createdAt !== normalizedISOString(message.createdAt)) {
    next.createdAt = swiftReferenceSecondsFromDate(new Date(message.createdAt));
  }
  if (!contractValuesEqual(current.sources, message.sources)) {
    next.sources = mergeCitations(raw.sources, message.sources);
  }
  if (!contractValuesEqual(current.actions, message.actions)) {
    next.actions = mergeNoteProposals(raw.actions, message.actions, next.createdAt ?? raw.createdAt);
  }
  return next;
}
function citationToRaw(source: AgentMessage["sources"][number]): SwiftJSONObject {
  return {
    id: source.id,
    itemID: source.itemId,
    courseID: source.courseId,
    kind: source.kind,
    title: source.title,
    label: source.label,
    excerpt: source.excerpt,
    pageIndex: source.pageIndex,
    sectionTitle: source.sectionTitle,
    sectionLocationID: source.sectionLocationId,
  };
}
function noteProposalToRaw(
  action: AgentMessage["actions"][number],
  fallbackDate: SwiftJSONValue | undefined,
): SwiftJSONObject {
  const date = typeof fallbackDate === "number" || typeof fallbackDate === "bigint"
    ? fallbackDate
    : swiftReferenceSecondsFromDate(new Date());
  return {
    id: action.id,
    kind: "writeNote",
    state: action.state,
    targetItemID: action.targetItemId,
    sourceItemID: action.sourceItemId,
    proposedMarkdown: action.proposedMarkdown,
    evidence: [...action.evidence],
    contextRevision: null,
    baselineContentDigest: action.baselineContentDigest,
    resultContentDigest: null,
    createdRelationID: null,
    failureMessage: null,
    createdAt: date,
    updatedAt: date,
  };
}
function mergeCitations(
  existing: SwiftJSONValue | undefined,
  sources: AgentMessage["sources"],
): SwiftJSONObject[] {
  const byID = objectsByStringID(existing);
  return sources.map((source) => ({
    ...(byID.get(normalizedIdentifier(source.id)) ?? {}),
    ...citationToRaw(source),
  }));
}
function mergeNoteProposals(
  existing: SwiftJSONValue | undefined,
  actions: AgentMessage["actions"],
  fallbackDate: SwiftJSONValue | undefined,
): SwiftJSONObject[] {
  const byID = objectsByStringID(existing);
  return actions.map((action) => ({
    ...(byID.get(normalizedIdentifier(action.id)) ?? {}),
    ...noteProposalToRaw(action, fallbackDate),
  }));
}
function objectsByStringID(value: SwiftJSONValue | undefined): Map<string, SwiftJSONObject> {
  const result = new Map<string, SwiftJSONObject>();
  if (!Array.isArray(value)) return result;
  for (const entry of value) {
    try {
      const raw = asObject(entry);
      if (typeof raw.id === "string") result.set(normalizedIdentifier(raw.id), raw);
    } catch { /* a malformed attachment remains untouched unless its array is explicitly replaced */ }
  }
  return result;
}
function precedingUserQuestion(messages: SwiftJSONValue[], beforeIndex: number): string | null {
  for (let index = beforeIndex - 1; index >= 0; index -= 1) {
    try {
      const raw = asObject(messages[index]);
      if (raw.role === "user" && typeof raw.text === "string") return raw.text;
    } catch { /* isolate a malformed earlier message */ }
  }
  return null;
}
function dateFromRaw(value: unknown): Date {
  if (typeof value === "number" || typeof value === "bigint") return dateFromSwiftReferenceSeconds(value);
  if (typeof value === "string") { const date = new Date(value); if (Number.isFinite(date.getTime())) return date; }
  return new Date(0);
}
function normalizedISOString(value: string): string {
  const date = new Date(value);
  return Number.isFinite(date.getTime()) ? date.toISOString() : value;
}
function contractValuesEqual(left: unknown, right: unknown): boolean {
  return JSON.stringify(left) === JSON.stringify(right);
}
function nonnegativeSafeInteger(value: unknown): number | null {
  const numeric = typeof value === "bigint" ? Number(value) : value;
  return typeof numeric === "number" && Number.isSafeInteger(numeric) && numeric >= 0 ? numeric : null;
}
function asObject(value: unknown): SwiftJSONObject { if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("expected-object"); return value as SwiftJSONObject; }
function stringArray(value: SwiftJSONValue | undefined): string[] { return Array.isArray(value) ? value.filter((entry): entry is string => typeof entry === "string") : []; }
function sessionCourseIDs(raw: SwiftJSONObject): string[] {
  // StudySession's Swift decoder gives the current relatedCourseIDs field
  // complete precedence over the legacy singular courseID, including when the
  // current field is explicitly empty.
  if (raw.relatedCourseIDs !== undefined && raw.relatedCourseIDs !== null) {
    return stringArray(raw.relatedCourseIDs);
  }
  return typeof raw.courseID === "string" ? [raw.courseID] : [];
}
function sameSessionPayloadBaseline(
  expected: Exclude<SessionPayloadInspection, { status: "invalid" }>,
  current: SessionPayloadInspection,
): boolean {
  if (expected.status !== current.status) return false;
  return expected.status === "missing"
    || (current.status === "valid" && expected.contents === current.contents);
}
function validatedMessageArray(
  value: SwiftJSONValue | undefined,
  allowMissing: boolean,
): SwiftJSONValue[] {
  if ((value === undefined || value === null) && allowMissing) return [];
  if (!Array.isArray(value)) throw new Error("invalid-session-messages");
  const messageIDs = new Set<string>();
  for (const entry of value) {
    const message = asObject(entry);
    const id = normalizedIdentifier(requiredUUID(message.id));
    if (messageIDs.has(id)) throw new Error("duplicate-message-id");
    messageIDs.add(id);
    if (message.role !== "user" && message.role !== "assistant") {
      throw new Error("invalid-message-role");
    }
    if (typeof message.text !== "string") throw new Error("invalid-message-text");
    if (typeof message.createdAt !== "number" && typeof message.createdAt !== "bigint") {
      throw new Error("invalid-message-date");
    }
    dateFromSwiftReferenceSeconds(message.createdAt);
  }
  return [...value];
}
function validateLegacySessionMetadata(legacy: SwiftJSONObject): void {
  if (typeof legacy.title !== "string") {
    throw new Error("legacy-session-metadata-invalid");
  }
  for (const value of [legacy.titleSetByUser]) {
    if (value !== undefined && value !== null && typeof value !== "boolean") {
      throw new Error("legacy-session-metadata-invalid");
    }
  }
  if (
    legacy.summary !== undefined
    && legacy.summary !== null
    && typeof legacy.summary !== "string"
  ) {
    throw new Error("legacy-session-metadata-invalid");
  }
  if (legacy.relatedCourseIDs !== undefined && legacy.relatedCourseIDs !== null) {
    if (
      !Array.isArray(legacy.relatedCourseIDs)
      || legacy.relatedCourseIDs.some((value) =>
        typeof value !== "string" || !isUUID(value))
    ) {
      throw new Error("legacy-session-metadata-invalid");
    }
  }
  if (
    legacy.courseID !== undefined
    && legacy.courseID !== null
    && (typeof legacy.courseID !== "string" || !isUUID(legacy.courseID))
  ) {
    throw new Error("legacy-session-metadata-invalid");
  }
  if (legacy.focusItemIDs !== undefined && legacy.focusItemIDs !== null) {
    if (
      !Array.isArray(legacy.focusItemIDs)
      || legacy.focusItemIDs.some((value) => typeof value !== "string")
    ) {
      throw new Error("legacy-session-metadata-invalid");
    }
  }
  if (
    legacy.materialItemID !== undefined
    && legacy.materialItemID !== null
    && typeof legacy.materialItemID !== "string"
  ) {
    throw new Error("legacy-session-metadata-invalid");
  }
  if (legacy.flow !== undefined && legacy.flow !== null) {
    const flow = asObject(legacy.flow);
    if (
      ![
        "orient",
        "explore",
        "closeRead",
        "note",
        "recall",
        "consolidate",
        "plan",
      ].includes(String(flow.phase))
      || typeof flow.pinnedByUser !== "boolean"
      || !Array.isArray(flow.suggestedNext)
      || flow.suggestedNext.some((value) => typeof value !== "string")
    ) {
      throw new Error("legacy-session-metadata-invalid");
    }
  }
  for (const value of [legacy.createdAt, legacy.updatedAt]) {
    if (value === undefined || value === null) continue;
    if (typeof value !== "number" && typeof value !== "bigint") {
      throw new Error("legacy-session-metadata-invalid");
    }
    try {
      dateFromSwiftReferenceSeconds(value);
    } catch {
      throw new Error("legacy-session-metadata-invalid");
    }
  }
}
function validateLegacyMessageCodableShape(message: SwiftJSONObject): void {
  validateOptionalLegacyString(message.source);
  validateOptionalLegacyEnum(message.backend, ["openAI", "offline", "native"]);
  validateOptionalLegacyEnum(
    message.completionState,
    ["generating", "completed", "interrupted"],
  );
  validateLegacyContentBlocks(message.contentBlocks);

  if (message.sources !== undefined && message.sources !== null) {
    if (!Array.isArray(message.sources)) legacyMessageInvalid();
    for (const value of message.sources) {
      validateLegacySourceCodableShape(requiredLegacyObject(value));
    }
  }
  if (message.actions !== undefined && message.actions !== null) {
    if (!Array.isArray(message.actions)) legacyMessageInvalid();
    for (const value of message.actions) {
      validateLegacyActionCodableShape(requiredLegacyObject(value));
    }
  }
  if (message.memoryUpdate !== undefined && message.memoryUpdate !== null) {
    const update = requiredLegacyObject(message.memoryUpdate);
    validateLegacyUUIDArray(update.memoryIDs);
    requireLegacyString(update.summary);
    if (update.texts !== undefined && update.texts !== null) {
      validateLegacyStringArray(update.texts);
    }
  }
  if (message.profileUpdate !== undefined && message.profileUpdate !== null) {
    const update = requiredLegacyObject(message.profileUpdate);
    validateLegacyUUIDArray(update.entryIDs);
    requireLegacyString(update.summary);
    validateLegacyStringArray(update.texts);
  }
  if (message.origin !== undefined && message.origin !== null) {
    const origin = requiredLegacyObject(message.origin);
    requireLegacyUUID(origin.requestID);
    requireLegacyUUID(origin.chatID);
    validateOptionalLegacyUUID(origin.courseID);
  }
  validateOptionalLegacyEnum(message.failureKind, [
    "offline",
    "unauthorized",
    "rateLimited",
    "serverError",
    "timedOut",
    "cancelled",
    "generic",
  ]);
  validateOptionalLegacyString(message.retryQuestion);
  if (message.toolTrace !== undefined && message.toolTrace !== null) {
    validateLegacyStringArray(message.toolTrace);
  }
}
function validateLegacySourceCodableShape(source: SwiftJSONObject): void {
  requireLegacyUUID(source.id);
  requireLegacyEnum(source.kind, ["material", "note", "selection"]);
  requireLegacyString(source.title);
  requireLegacyString(source.label);
  requireLegacyString(source.excerpt);
  validateOptionalLegacyString(source.itemID);
  validateOptionalLegacyUUID(source.courseID);
  validateOptionalLegacyString(source.sectionTitle);
  validateOptionalLegacyString(source.sectionLocationID);
  for (const value of [
    source.pageIndex,
    source.sectionOrdinal,
    source.courseItemOrdinal,
  ]) {
    if (value !== undefined && value !== null && !isSwiftInt(value)) {
      legacyMessageInvalid();
    }
  }
}
function validateLegacyActionCodableShape(action: SwiftJSONObject): void {
  requireLegacyUUID(action.id);
  requireLegacyEnum(action.kind, ["writeNote", "createRelation"]);
  requireLegacyEnum(action.state, ["pending", "executed", "cancelled", "failed"]);
  validateLegacyStringArray(action.evidence);
  validateLegacySwiftDate(action.createdAt);
  validateLegacySwiftDate(action.updatedAt);
  for (const value of [
    action.targetItemID,
    action.sourceItemID,
    action.proposedMarkdown,
    action.contextRevision,
    action.baselineContentDigest,
    action.resultContentDigest,
    action.failureMessage,
  ]) {
    validateOptionalLegacyString(value);
  }
  validateOptionalLegacyUUID(action.createdRelationID);
}
function validateLegacyContentBlocks(value: SwiftJSONValue | undefined): void {
  if (value === undefined || value === null) return;
  const blocks = Array.isArray(value) ? value : [value];
  for (const blockValue of blocks) {
    const block = requiredLegacyObject(blockValue);
    if (Object.prototype.hasOwnProperty.call(block, "text")) {
      const wrapper = requiredLegacyObject(block.text);
      requireLegacyString(wrapper._0);
      continue;
    }
    if (!Object.prototype.hasOwnProperty.call(block, "visualization")) {
      legacyMessageInvalid();
    }
    const wrapper = requiredLegacyObject(block.visualization);
    const visualization = requiredLegacyObject(wrapper._0);
    requireLegacyString(visualization.id);
    requireLegacyString(visualization.specJSON);
    validateOptionalLegacyString(visualization.stateJSON);
  }
}
function validateOptionalLegacyString(value: SwiftJSONValue | undefined): void {
  if (value !== undefined && value !== null && typeof value !== "string") {
    legacyMessageInvalid();
  }
}
function validateOptionalLegacyUUID(value: SwiftJSONValue | undefined): void {
  if (value !== undefined && value !== null) requireLegacyUUID(value);
}
function validateOptionalLegacyEnum(
  value: SwiftJSONValue | undefined,
  allowed: readonly string[],
): void {
  if (value !== undefined && value !== null) requireLegacyEnum(value, allowed);
}
function requireLegacyString(value: SwiftJSONValue | undefined): string {
  if (typeof value !== "string") legacyMessageInvalid();
  return value;
}
function requireLegacyUUID(value: SwiftJSONValue | undefined): string {
  const result = requireLegacyString(value);
  if (!isUUID(result)) legacyMessageInvalid();
  return result;
}
function requireLegacyEnum(
  value: SwiftJSONValue | undefined,
  allowed: readonly string[],
): string {
  const result = requireLegacyString(value);
  if (!allowed.includes(result)) legacyMessageInvalid();
  return result;
}
function requiredLegacyObject(value: unknown): SwiftJSONObject {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    legacyMessageInvalid();
  }
  return value as SwiftJSONObject;
}
function validateLegacyStringArray(value: SwiftJSONValue | undefined): void {
  if (!Array.isArray(value) || value.some((entry) => typeof entry !== "string")) {
    legacyMessageInvalid();
  }
}
function validateLegacyUUIDArray(value: SwiftJSONValue | undefined): void {
  if (
    !Array.isArray(value)
    || value.some((entry) => typeof entry !== "string" || !isUUID(entry))
  ) {
    legacyMessageInvalid();
  }
}
function validateLegacySwiftDate(value: SwiftJSONValue | undefined): void {
  if (typeof value !== "number" && typeof value !== "bigint") {
    legacyMessageInvalid();
  }
  try {
    dateFromSwiftReferenceSeconds(value);
  } catch {
    legacyMessageInvalid();
  }
}
function isSwiftInt(value: SwiftJSONValue): boolean {
  if (typeof value === "number") return Number.isSafeInteger(value);
  return typeof value === "bigint"
    && value >= -9_223_372_036_854_775_808n
    && value <= 9_223_372_036_854_775_807n;
}
function legacyMessageInvalid(): never {
  throw new Error("legacy-session-message-invalid");
}
function validatedLegacySessionForCourse(
  legacy: SwiftJSONObject,
  messages: readonly SwiftJSONValue[],
  currentCourseID: string,
  context: LegacySessionMigrationContext | undefined,
): { legacy: SwiftJSONObject; messages: SwiftJSONValue[] } {
  validateLegacySessionCourseAffiliation(legacy, currentCourseID);
  for (const value of messages) {
    validateLegacyMessageCodableShape(asObject(value));
  }
  if (!context) {
    validateLegacySessionReferencesWithoutContext(
      legacy,
      messages,
      currentCourseID,
    );
    return { legacy: { ...legacy }, messages: [...messages] };
  }

  const allowed = normalizedLegacyMigrationContext(context);
  if (
    Array.isArray(legacy.focusItemIDs)
    && legacy.focusItemIDs.some((value) =>
      typeof value !== "string" || !allowed.itemIDs.has(value))
  ) {
    throw new Error("legacy-session-reference-mismatch");
  }
  if (
    legacy.materialItemID !== undefined
    && legacy.materialItemID !== null
    && (
      typeof legacy.materialItemID !== "string"
      || !allowed.materialItemIDs.has(legacy.materialItemID)
    )
  ) {
    throw new Error("legacy-session-reference-mismatch");
  }
  for (const value of messages) {
    validateLegacyMessageReferences(
      asObject(value),
      requiredUUID(legacy.id),
      currentCourseID,
      allowed,
    );
  }
  // Validation must never normalize the migration input: once the course's v1
  // copy is cleared, every forward field and raw portable reference has only
  // this externalized copy left.
  return { legacy: { ...legacy }, messages: [...messages] };
}
function validateLegacySessionCourseAffiliation(
  legacy: SwiftJSONObject,
  currentCourseID: string,
): void {
  if (legacy.relatedCourseIDs !== undefined && legacy.relatedCourseIDs !== null) {
    if (!Array.isArray(legacy.relatedCourseIDs)) {
      throw new Error("legacy-session-course-invalid");
    }
    const related = new Set<string>();
    for (const value of legacy.relatedCourseIDs) {
      if (typeof value !== "string" || !isUUID(value)) {
        throw new Error("legacy-session-course-invalid");
      }
      related.add(normalizedIdentifier(value));
    }
    if (
      related.size !== 1
      || !related.has(normalizedIdentifier(currentCourseID))
    ) {
      throw new Error("legacy-session-course-mismatch");
    }
  } else {
    if (legacy.courseID === undefined || legacy.courseID === null) {
      throw new Error("legacy-session-course-missing");
    }
    if (typeof legacy.courseID !== "string" || !isUUID(legacy.courseID)) {
      throw new Error("legacy-session-course-invalid");
    }
    if (!sameUUID(legacy.courseID, currentCourseID)) {
      throw new Error("legacy-session-course-mismatch");
    }
  }
  // scopeNeedsReview remains a raw forward-compatibility field. The current
  // Swift StudySession decoder intentionally ignores it, so it cannot be used
  // as course-affiliation evidence here either.
}
function validateLegacySessionReferencesWithoutContext(
  legacy: SwiftJSONObject,
  messages: readonly SwiftJSONValue[],
  currentCourseID: string,
): void {
  if (
    Array.isArray(legacy.focusItemIDs)
    && legacy.focusItemIDs.length > 0
  ) {
    throw new Error("legacy-session-reference-unverifiable");
  }
  if (legacy.materialItemID !== undefined && legacy.materialItemID !== null) {
    throw new Error("legacy-session-reference-unverifiable");
  }

  for (const value of messages) {
    const message = asObject(value);
    if (message.toolTrace !== undefined && message.toolTrace !== null) {
      if (!Array.isArray(message.toolTrace)) {
        throw new Error("legacy-session-reference-invalid");
      }
      if (message.toolTrace.length > 0) {
        throw new Error("legacy-session-reference-mismatch");
      }
    }
    if (message.sources !== undefined && message.sources !== null) {
      if (!Array.isArray(message.sources)) {
        throw new Error("legacy-session-reference-invalid");
      }
      for (const sourceValue of message.sources) {
        const source = asObject(sourceValue);
        validateLegacyCourseReference(source.courseID, currentCourseID);
        if (source.itemID !== undefined && source.itemID !== null) {
          throw new Error("legacy-session-reference-unverifiable");
        }
      }
    }
    if (message.actions !== undefined && message.actions !== null) {
      if (!Array.isArray(message.actions)) {
        throw new Error("legacy-session-reference-invalid");
      }
      for (const actionValue of message.actions) {
        const action = asObject(actionValue);
        for (const reference of [
          action.targetItemID,
          action.sourceItemID,
          action.createdRelationID,
        ]) {
          if (reference !== undefined && reference !== null) {
            throw new Error("legacy-session-reference-unverifiable");
          }
        }
      }
    }
    if (message.memoryUpdate !== undefined && message.memoryUpdate !== null) {
      const memoryUpdate = asObject(message.memoryUpdate);
      if (!Array.isArray(memoryUpdate.memoryIDs)) {
        throw new Error("legacy-session-reference-invalid");
      }
      if (memoryUpdate.memoryIDs.length > 0) {
        throw new Error("legacy-session-reference-unverifiable");
      }
    }
    if (message.origin !== undefined && message.origin !== null) {
      const origin = asObject(message.origin);
      if (
        !sameUUID(origin.courseID, currentCourseID)
        || !sameUUID(origin.chatID, legacy.id)
      ) {
        throw new Error("legacy-session-reference-mismatch");
      }
    }
  }
}
interface NormalizedLegacyMigrationContext {
  itemIDs: ReadonlySet<string>;
  noteItemIDs: ReadonlySet<string>;
  materialItemIDs: ReadonlySet<string>;
  memoryIDs: ReadonlySet<string>;
  relations: ReadonlyMap<string, {
    noteItemID: string;
    sourceItemID: string;
  }>;
}
function normalizedLegacyMigrationContext(
  context: LegacySessionMigrationContext,
): NormalizedLegacyMigrationContext {
  const itemIDs = validatedStringSet(context.itemIDs);
  const noteItemIDs = validatedStringSet(context.noteItemIDs);
  const materialItemIDs = validatedStringSet(context.materialItemIDs);
  if (
    [...noteItemIDs].some((value) => !itemIDs.has(value))
    || [...materialItemIDs].some((value) => !itemIDs.has(value))
  ) {
    throw new Error("legacy-session-context-invalid");
  }
  const memoryIDs = new Set<string>();
  for (const value of context.memoryIDs) {
    if (typeof value !== "string" || !isUUID(value)) {
      throw new Error("legacy-session-context-invalid");
    }
    memoryIDs.add(normalizedIdentifier(value));
  }
  const relations = new Map<string, {
    noteItemID: string;
    sourceItemID: string;
  }>();
  for (const relation of context.relations) {
    if (
      !relation
      || typeof relation !== "object"
      || typeof relation.id !== "string"
      || !isUUID(relation.id)
      || typeof relation.noteItemID !== "string"
      || typeof relation.sourceItemID !== "string"
      || !noteItemIDs.has(relation.noteItemID)
      || !materialItemIDs.has(relation.sourceItemID)
    ) {
      throw new Error("legacy-session-context-invalid");
    }
    const key = normalizedIdentifier(relation.id);
    const existing = relations.get(key);
    if (
      existing
      && (
        existing.noteItemID !== relation.noteItemID
        || existing.sourceItemID !== relation.sourceItemID
      )
    ) {
      throw new Error("legacy-session-context-invalid");
    }
    relations.set(key, {
      noteItemID: relation.noteItemID,
      sourceItemID: relation.sourceItemID,
    });
  }
  return { itemIDs, noteItemIDs, materialItemIDs, memoryIDs, relations };
}
function validatedStringSet(values: readonly string[]): ReadonlySet<string> {
  if (!Array.isArray(values)) throw new Error("legacy-session-context-invalid");
  const result = new Set<string>();
  for (const value of values) {
    if (typeof value !== "string" || value.length === 0) {
      throw new Error("legacy-session-context-invalid");
    }
    result.add(value);
  }
  return result;
}
function validateLegacyMessageReferences(
  message: SwiftJSONObject,
  sessionID: string,
  currentCourseID: string,
  allowed: NormalizedLegacyMigrationContext,
): void {
  if (message.toolTrace !== undefined && message.toolTrace !== null) {
    if (
      !Array.isArray(message.toolTrace)
      || message.toolTrace.some((value) => typeof value !== "string")
    ) {
      throw new Error("legacy-session-reference-invalid");
    }
    if (message.toolTrace.length > 0) {
      throw new Error("legacy-session-reference-mismatch");
    }
  }
  if (message.sources !== undefined && message.sources !== null) {
    if (!Array.isArray(message.sources)) {
      throw new Error("legacy-session-reference-invalid");
    }
    for (const value of message.sources) {
      validateLegacySourceReference(
        asObject(value),
        currentCourseID,
        allowed,
      );
    }
  }
  if (message.actions !== undefined && message.actions !== null) {
    if (!Array.isArray(message.actions)) {
      throw new Error("legacy-session-reference-invalid");
    }
    for (const value of message.actions) {
      validateLegacyActionReference(asObject(value), allowed);
    }
  }
  if (message.memoryUpdate !== undefined && message.memoryUpdate !== null) {
    const memoryUpdate = asObject(message.memoryUpdate);
    if (!Array.isArray(memoryUpdate.memoryIDs)) {
      throw new Error("legacy-session-reference-invalid");
    }
    for (const value of memoryUpdate.memoryIDs) {
      if (typeof value !== "string" || !isUUID(value)) {
        throw new Error("legacy-session-reference-invalid");
      }
      if (!allowed.memoryIDs.has(normalizedIdentifier(value))) {
        throw new Error("legacy-session-reference-mismatch");
      }
    }
  }
  if (message.origin !== undefined && message.origin !== null) {
    const origin = asObject(message.origin);
    if (
      typeof origin.courseID !== "string"
      || !isUUID(origin.courseID)
      || typeof origin.chatID !== "string"
      || !isUUID(origin.chatID)
    ) {
      throw new Error("legacy-session-reference-invalid");
    }
    if (
      !sameUUID(origin.courseID, currentCourseID)
      || !sameUUID(origin.chatID, sessionID)
    ) {
      throw new Error("legacy-session-reference-mismatch");
    }
  }
}
function validateLegacySourceReference(
  source: SwiftJSONObject,
  currentCourseID: string,
  allowed: NormalizedLegacyMigrationContext,
): void {
  validateLegacyCourseReference(source.courseID, currentCourseID);
  if (![
    "material",
    "note",
    "selection",
  ].includes(String(source.kind))) {
    throw new Error("legacy-session-reference-invalid");
  }
  if (source.itemID === undefined || source.itemID === null) return;
  if (typeof source.itemID !== "string") {
    throw new Error("legacy-session-reference-invalid");
  }
  if (!allowed.itemIDs.has(source.itemID)) {
    throw new Error("legacy-session-reference-mismatch");
  }
  if (
    (source.kind === "material" && !allowed.materialItemIDs.has(source.itemID))
    || (source.kind === "note" && !allowed.noteItemIDs.has(source.itemID))
  ) {
    throw new Error("legacy-session-reference-mismatch");
  }
}
function validateLegacyActionReference(
  action: SwiftJSONObject,
  allowed: NormalizedLegacyMigrationContext,
): void {
  const target = action.targetItemID;
  const source = action.sourceItemID;
  if (
    (target !== undefined && target !== null && typeof target !== "string")
    || (source !== undefined && source !== null && typeof source !== "string")
  ) throw new Error("legacy-session-reference-invalid");
  if (
    (typeof target === "string" && !allowed.itemIDs.has(target))
    || (typeof source === "string" && !allowed.itemIDs.has(source))
  ) throw new Error("legacy-session-reference-mismatch");
  if (action.kind === "writeNote") {
    if (
      (typeof target === "string" && !allowed.noteItemIDs.has(target))
      || (action.createdRelationID !== undefined && action.createdRelationID !== null)
    ) {
      throw new Error("legacy-session-reference-mismatch");
    }
    return;
  }
  if (action.kind !== "createRelation") {
    throw new Error("legacy-session-reference-invalid");
  }
  if (
    typeof target === "string"
    && !allowed.noteItemIDs.has(target)
  ) throw new Error("legacy-session-reference-mismatch");
  if (
    typeof source === "string"
    && !allowed.materialItemIDs.has(source)
  ) throw new Error("legacy-session-reference-mismatch");
  if (action.createdRelationID === undefined || action.createdRelationID === null) {
    return;
  }
  if (
    typeof action.createdRelationID !== "string"
    || !isUUID(action.createdRelationID)
  ) throw new Error("legacy-session-reference-invalid");
  if (typeof target !== "string" || typeof source !== "string") {
    throw new Error("legacy-session-reference-mismatch");
  }
  const relation = allowed.relations.get(normalizedIdentifier(action.createdRelationID));
  if (relation?.noteItemID !== target || relation.sourceItemID !== source) {
    throw new Error("legacy-session-reference-mismatch");
  }
}
function validateLegacyCourseReference(
  value: SwiftJSONValue | undefined,
  currentCourseID: string,
): void {
  if (value === undefined || value === null) return;
  if (typeof value !== "string" || !isUUID(value)) {
    throw new Error("legacy-session-reference-invalid");
  }
  if (!sameUUID(value, currentCourseID)) {
    throw new Error("legacy-session-reference-mismatch");
  }
}
function mergeAppendOnlyMessages(
  existing: SwiftJSONValue[],
  legacy: SwiftJSONValue[],
): SwiftJSONValue[] {
  if (isSwiftArrayPrefix(existing, legacy)) return legacy;
  if (isSwiftArrayPrefix(legacy, existing)) return existing;
  throw new Error("existing-session-body-conflict");
}
function isSwiftArrayPrefix(
  prefix: readonly SwiftJSONValue[],
  value: readonly SwiftJSONValue[],
): boolean {
  return prefix.length <= value.length && prefix.every((entry, index) =>
    stringifySwiftJSON(entry, { sortKeys: true })
      === stringifySwiftJSON(value[index], { sortKeys: true }));
}
function messageCountValue(value: SwiftJSONValue | undefined): bigint {
  if (value === undefined || value === null) return 0n;
  if (typeof value === "bigint") {
    if (value < 0n || value > 9_223_372_036_854_775_807n) {
      throw new Error("invalid-message-count");
    }
    return value;
  }
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0) {
    throw new Error("invalid-message-count");
  }
  return BigInt(value);
}
const KNOWN_SESSION_METADATA_KEYS = new Set([
  "id",
  "title",
  "titleSetByUser",
  "messages",
  "summary",
  "relatedCourseIDs",
  "courseID",
  "scopeNeedsReview",
  "focusItemIDs",
  "materialItemID",
  "flow",
  "createdAt",
  "updatedAt",
  "messageCount",
]);
function mergedSessionMetadata(
  existing: SwiftJSONObject | null,
  legacy: SwiftJSONObject,
): SwiftJSONObject {
  if (!existing) return { ...legacy };
  for (const [key, legacyValue] of Object.entries(legacy)) {
    if (KNOWN_SESSION_METADATA_KEYS.has(key) || legacyValue === undefined) continue;
    const existingValue = existing[key];
    if (
      existingValue !== undefined
      && stringifySwiftJSON(existingValue, { sortKeys: true })
        !== stringifySwiftJSON(legacyValue, { sortKeys: true })
    ) {
      throw new Error("existing-session-metadata-conflict");
    }
  }
  // Existing user-visible state wins, while forward fields present only in the
  // portable v1 copy survive its later removal from the course state.
  return { ...legacy, ...existing };
}
function mergedCourseIDs(
  existing: SwiftJSONObject | null,
  legacy: SwiftJSONObject,
  currentCourseID: string,
): string[] {
  const byID = new Map<string, string>();
  for (const raw of [existing, legacy]) {
    if (!raw) continue;
    if (Array.isArray(raw.relatedCourseIDs)) {
      for (const value of stringArray(raw.relatedCourseIDs)) {
        if (isUUID(value)) byID.set(normalizedIdentifier(value), value);
      }
    } else if (typeof raw.courseID === "string" && isUUID(raw.courseID)) {
      byID.set(normalizedIdentifier(raw.courseID), raw.courseID);
    }
  }
  // Keep the spelling used by the portable course so listForCourse's current
  // compatibility lookup succeeds even for uppercase UUIDs from Swift files.
  byID.set(normalizedIdentifier(currentCourseID), currentCourseID);
  return [...byID.entries()]
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([, value]) => value);
}
function requiredUUID(value: unknown): string { if (typeof value !== "string" || !isUUID(value)) throw new Error("invalid-uuid"); return value; }
function isUUID(value: string): boolean { return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value); }
function sameUUID(left: unknown, right: unknown): boolean {
  return typeof left === "string"
    && typeof right === "string"
    && isUUID(left)
    && isUUID(right)
    && left.toLocaleLowerCase("en-US") === right.toLocaleLowerCase("en-US");
}
function normalizedIdentifier(value: string): string {
  return isUUID(value) ? value.toLocaleLowerCase("en-US") : value;
}
function isNodeError(error: unknown): error is NodeJS.ErrnoException {
  return error instanceof Error && "code" in error;
}
function sameFilesystemPath(left: string, right: string): boolean {
  return path.resolve(left).toLocaleLowerCase("en-US")
    === path.resolve(right).toLocaleLowerCase("en-US");
}
function sessionTitle(question: string): string { const compact = question.replace(/\s+/g, " ").trim(); return compact.length > 24 ? `${compact.slice(0, 23)}…` : compact; }
function deterministicUUID(seed: string): string {
  const bytes = Buffer.from(seed).toString("hex").padEnd(32, "0").slice(0, 32).split("");
  bytes[12] = "4"; bytes[16] = "8";
  const hex = bytes.join("");
  return `${hex.slice(0,8)}-${hex.slice(8,12)}-${hex.slice(12,16)}-${hex.slice(16,20)}-${hex.slice(20)}`;
}
