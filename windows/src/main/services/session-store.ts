import { randomUUID } from "node:crypto";
import { mkdir, readFile, readdir } from "node:fs/promises";
import path from "node:path";
import type { AgentMessage, StudySession } from "../../shared/contracts";
import { atomicWriteVerified } from "./file-utils";
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

export class StudySessionStore {
  private readonly workspaceDirectory: string;
  private readonly sessionsDirectory: string;
  private readonly persistence: WorkspacePersistence;
  private workspace: PersistedWorkspaceRecord = { importedItems: [], notesByItemID: {} };
  private queue: Promise<void> = Promise.resolve();

  private constructor(workspaceDirectory: string) {
    this.workspaceDirectory = path.resolve(workspaceDirectory);
    this.sessionsDirectory = path.join(this.workspaceDirectory, "Sessions");
    this.persistence = new WorkspacePersistence(this.workspaceDirectory);
  }

  static async open(workspaceDirectory: string): Promise<StudySessionStore> {
    const store = new StudySessionStore(workspaceDirectory);
    await mkdir(store.sessionsDirectory, { recursive: true });
    const loaded = await store.persistence.load();
    store.workspace = loaded.snapshot ?? { importedItems: [], notesByItemID: {} };
    if (loaded.needsPrimaryRewrite || !loaded.snapshot) await store.persistence.save(store.workspace);
    await store.interruptOrphanedGeneratingMessages();
    return store;
  }

  async listForCourse(courseID: string): Promise<StudySession[]> {
    return this.runExclusive(async () => {
      const sessions = sessionRecords(this.workspace)
        .filter((raw) => stringArray(raw.relatedCourseIDs).includes(courseID) || raw.courseID === courseID);
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
      const raw = sessionRecords(this.workspace).find((entry) => sameUUID(entry.id, sessionID));
      if (!raw) return null;
      try { return await this.hydrateSession(raw); } catch { return null; }
    });
  }

  async create(courseID: string): Promise<StudySession> {
    return this.runExclusive(async () => {
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
      setSessionRecords(this.workspace, [...sessionRecords(this.workspace), raw]);
      await this.persistSessionMessages(session.id, []);
      await this.persistence.save(this.workspace);
      return session;
    });
  }

  async appendMessages(sessionID: string, messages: readonly AgentMessage[]): Promise<StudySession> {
    return this.runExclusive(async () => {
      const records = sessionRecords(this.workspace);
      const index = records.findIndex((entry) => sameUUID(entry.id, sessionID));
      if (index < 0) throw new Error("session-not-found");
      const payload = await this.readSessionPayload(sessionID);
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
      setSessionRecords(this.workspace, records);
      // Swift commit order: external session body before workspace metadata.
      await this.persistSessionMessages(sessionID, rawMessages, payload);
      await this.persistence.save(this.workspace);
      return updated;
    });
  }

  async updateMessage(sessionID: string, message: AgentMessage): Promise<StudySession> {
    return this.runExclusive(async () => {
      const records = sessionRecords(this.workspace);
      const index = records.findIndex((entry) => sameUUID(entry.id, sessionID));
      if (index < 0) throw new Error("session-not-found");
      const payload = await this.readSessionPayload(sessionID);
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
      setSessionRecords(this.workspace, records);
      await this.persistSessionMessages(sessionID, rawMessages, payload);
      await this.persistence.save(this.workspace);
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
    const related = stringArray(raw.relatedCourseIDs);
    const focus = stringArray(raw.focusItemIDs);
    return {
      id,
      title: typeof raw.title === "string" ? raw.title : "Chat",
      courseId: related.length === 1 && isUUID(related[0]) ? related[0] : (typeof raw.courseID === "string" && isUUID(raw.courseID) ? raw.courseID : null),
      itemId: typeof raw.materialItemID === "string" ? raw.materialItemID : focus[0] ?? null,
      messages,
      createdAt: dateFromRaw(raw.createdAt).toISOString(),
      updatedAt: dateFromRaw(raw.updatedAt ?? raw.createdAt).toISOString(),
    };
  }

  private async readSessionPayload(sessionID: string): Promise<SwiftJSONObject | null> {
    try {
      const payload = asObject(parseSwiftJSON(await readFile(this.sessionPath(sessionID), "utf8")));
      if (!sameUUID(payload.sessionID, sessionID) || !Array.isArray(payload.messages)) {
        throw new Error("session-identity-mismatch");
      }
      return payload;
    } catch {
      return null;
    }
  }

  private async persistSessionMessages(
    sessionID: string,
    messages: readonly SwiftJSONValue[],
    existingPayload: SwiftJSONObject | null = null,
  ): Promise<void> {
    await mkdir(this.sessionsDirectory, { recursive: true });
    const payload: SwiftJSONObject = {
      ...(existingPayload ?? { schemaVersion: 1, sessionID }),
      messages: [...messages],
    };
    await atomicWriteVerified(this.sessionPath(sessionID), stringifySwiftJSON(payload, { sortKeys: true }));
    const verified = asObject(parseSwiftJSON(await readFile(this.sessionPath(sessionID), "utf8")));
    if (!sameUUID(verified.sessionID, sessionID) || !Array.isArray(verified.messages) || verified.messages.length !== messages.length) {
      throw new Error("session-write-verification-failed");
    }
  }

  private sessionPath(sessionID: string): string {
    return path.join(this.sessionsDirectory, `${requiredUUID(sessionID).toLocaleLowerCase("en-US")}.json`);
  }

  private async interruptOrphanedGeneratingMessages(): Promise<void> {
    // Scan independently so one corrupt JSON file is isolated by omission.
    let names: string[] = [];
    try { names = await readdir(this.sessionsDirectory); } catch { return; }
    for (const name of names.filter((value) => /^[0-9a-f-]{36}\.json$/i.test(value))) {
      try {
        const filePath = path.join(this.sessionsDirectory, name);
        const payload = asObject(parseSwiftJSON(await readFile(filePath, "utf8")));
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
        if (changed) await atomicWriteVerified(filePath, stringifySwiftJSON({ ...payload, messages: next }, { sortKeys: true }));
      } catch { /* preserve corrupt evidence and continue */ }
    }
  }

  private async runExclusive<T>(operation: () => Promise<T>): Promise<T> {
    const result = this.queue.then(operation, operation);
    this.queue = result.then(() => undefined, () => undefined);
    return result;
  }
}

function sessionRecords(workspace: PersistedWorkspaceRecord): SwiftJSONObject[] {
  const raw = workspace.studySessions;
  if (raw === undefined || raw === null) return [];
  if (!Array.isArray(raw)) return [];
  return raw.flatMap((entry) => {
    try { return [asObject(entry)]; } catch { return []; }
  });
}
function setSessionRecords(workspace: PersistedWorkspaceRecord, sessions: SwiftJSONObject[]) {
  workspace.studySessions = sessions;
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
function sessionTitle(question: string): string { const compact = question.replace(/\s+/g, " ").trim(); return compact.length > 24 ? `${compact.slice(0, 23)}…` : compact; }
function deterministicUUID(seed: string): string {
  const bytes = Buffer.from(seed).toString("hex").padEnd(32, "0").slice(0, 32).split("");
  bytes[12] = "4"; bytes[16] = "8";
  const hex = bytes.join("");
  return `${hex.slice(0,8)}-${hex.slice(8,12)}-${hex.slice(12,16)}-${hex.slice(16,20)}-${hex.slice(20)}`;
}
