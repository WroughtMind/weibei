import { z } from "zod/v4";

const optionalJson = z.json().optional();
const jsonArray = z.array(z.json()).optional();

export const repairEvidenceSchema = z
  .object({ manifestPath: z.string().optional() })
  .catchall(z.json());

export const caseSnapshotSchema = z
  .object({
    caseID: optionalJson,
    id: optionalJson,
    caseId: optionalJson,
    caseKind: optionalJson,
    question: optionalJson,
    subject: optionalJson,
    materialTitle: optionalJson,
    materialKind: optionalJson,
    materialText: optionalJson,
    selectionTitle: optionalJson,
    selectionText: optionalJson,
    expectedCapabilityFamilies: jsonArray,
    userBenefitCriteria: jsonArray,
    rejectedOrDegradedBehaviors: jsonArray,
  })
  .catchall(z.json());

export const shapeDecisionSchema = z
  .object({
    caseKind: optionalJson,
    preferredShape: optionalJson,
    expectedShape: optionalJson,
    actualShape: optionalJson,
    preferredSurface: optionalJson,
    directManipulation: optionalJson,
    t1SceneCount: optionalJson,
    t2SceneCount: optionalJson,
    narrativeCharacterCount: optionalJson,
  })
  .catchall(z.json());

export const t1ProgramSchema = z
  .object({
    sceneID: optionalJson,
    family: optionalJson,
    version: optionalJson,
    maxHeight: optionalJson,
    capabilities: jsonArray,
    directManipulation: optionalJson,
    componentNames: jsonArray,
  })
  .catchall(z.json());

export const t2CompositionSchema = z
  .object({
    sceneID: optionalJson,
    family: optionalJson,
    rootID: optionalJson,
    roles: jsonArray,
    nodeCount: optionalJson,
    datasetCount: optionalJson,
    dataRowCount: optionalJson,
    bindingCount: optionalJson,
  })
  .catchall(z.json());

export const expressionPlanSchema = z
  .object({
    expressionPlan: optionalJson,
    t1Programs: z.array(t1ProgramSchema).optional(),
    t2Compositions: z.array(t2CompositionSchema).optional(),
  })
  .catchall(z.json());

export const sourceBindingSchema = z
  .object({
    textSourceLabels: jsonArray,
    evidenceLedgerLabels: jsonArray,
    sceneEvidenceIDs: jsonArray,
    evidenceState: optionalJson,
    hasExpectedSource: optionalJson,
  })
  .catchall(z.json());

export const repairSchema = z
  .object({
    failureReason: optionalJson,
    previousRunID: optionalJson,
    previousStatus: optionalJson,
    repairNote: optionalJson,
    isRetest: optionalJson,
  })
  .catchall(z.json());

export const protocolSchema = z
  .object({
    status: optionalJson,
    validationKind: optionalJson,
    passedChecks: jsonArray,
    issues: jsonArray,
    protocolDiagnostics: jsonArray,
    toolTrace: jsonArray,
  })
  .catchall(z.json());

export const replyDocumentSchema = z
  .object({
    backend: optionalJson,
    text: optionalJson,
    toolTrace: jsonArray,
    richAnswer: optionalJson,
  })
  .catchall(z.json());

export const requestDocumentSchema = z
  .object({
    caseSnapshot: caseSnapshotSchema.optional(),
    shapeDecision: shapeDecisionSchema.optional(),
    expressionPlan: expressionPlanSchema.optional(),
    sourceBinding: sourceBindingSchema.optional(),
    repairAndRetest: repairSchema.optional(),
    question: optionalJson,
    prompt: optionalJson,
    subject: optionalJson,
    materialTitle: optionalJson,
    materialKind: optionalJson,
    materialText: optionalJson,
    selectionTitle: optionalJson,
    selectionText: optionalJson,
    workflow: optionalJson,
    resolvedWorkflow: optionalJson,
    materialIsTruncated: optionalJson,
    contextRevision: optionalJson,
  })
  .catchall(z.json());

export const recordDocumentSchema = z
  .object({
    runID: optionalJson,
    caseID: optionalJson,
    repetition: optionalJson,
    round: optionalJson,
    sequence: optionalJson,
    subject: optionalJson,
    status: optionalJson,
    state: optionalJson,
    elapsedSeconds: optionalJson,
    duration: optionalJson,
    failureReason: optionalJson,
    question: optionalJson,
    caseKind: optionalJson,
    caseSnapshot: caseSnapshotSchema.optional(),
    shapeDecision: shapeDecisionSchema.optional(),
    expressionPlan: expressionPlanSchema.optional(),
    sourceBinding: sourceBindingSchema.optional(),
    repairAndRetest: repairSchema.optional(),
    toolAndProtocolValidation: protocolSchema.optional(),
    modelRawReply: replyDocumentSchema.optional(),
  })
  .catchall(z.json());

export const indexEntrySchema = z
  .object({
    runID: optionalJson,
    repetition: optionalJson,
    round: optionalJson,
    roundIndex: optionalJson,
    sequence: optionalJson,
    caseID: optionalJson,
    case_id: optionalJson,
    caseKind: optionalJson,
    status: optionalJson,
    question: optionalJson,
    subject: optionalJson,
    materialText: optionalJson,
    selectionTitle: optionalJson,
    selectionText: optionalJson,
    elapsedSeconds: optionalJson,
    failureReason: optionalJson,
    recordPath: z.string().optional(),
    record_file: z.string().optional(),
    recordJson: z.string().optional(),
    record: z.string().optional(),
    recordPathRelative: z.string().optional(),
    requestPath: z.string().optional(),
    request_file: z.string().optional(),
    requestJson: z.string().optional(),
    request: z.string().optional(),
    replyPath: z.string().optional(),
    reply_file: z.string().optional(),
    replyJson: z.string().optional(),
    reply: z.string().optional(),
    validationPath: z.string().optional(),
    validation_file: z.string().optional(),
    validationJson: z.string().optional(),
    validation: z.string().optional(),
    caseDir: z.string().optional(),
    caseSnapshot: caseSnapshotSchema.optional(),
    screenshots: z.record(z.string(), optionalJson).optional(),
    repairEvidence: repairEvidenceSchema.optional(),
    screenshotManifest: z.string().optional(),
    originalScreenshotStatus: optionalJson,
    screenshotStatus: optionalJson,
    qualityStatus: optionalJson,
  })
  .catchall(z.json());

export const indexDocumentSchema = z
  .object({ records: z.array(indexEntrySchema).optional() })
  .catchall(z.json());

export const runDocumentSchema = z
  .object({
    createdAt: optionalJson,
    runID: optionalJson,
    rootPath: optionalJson,
    retestOfRunID: optionalJson,
    repairNote: optionalJson,
    continueAfterFailure: optionalJson,
    requestedIDs: jsonArray,
    filters: jsonArray,
  })
  .catchall(z.json());

export const captureManifestSchema = z
  .object({
    status: optionalJson,
    captureStatus: optionalJson,
    qualityGate: z
      .object({
        status: optionalJson,
        inputs: z
          .record(
            z.string(),
            z
              .object({
                present: z.boolean().optional(),
                stablePaneFrames: z.boolean().optional(),
              })
              .catchall(z.json()),
          )
          .optional(),
        checks: z
          .array(
            z
              .object({
                id: z.string().optional(),
                status: optionalJson,
              })
              .catchall(z.json()),
          )
          .optional(),
      })
      .catchall(z.json())
      .optional(),
  })
  .catchall(z.json());

export type JsonValue = z.infer<ReturnType<typeof z.json>>;
export type IndexEntry = z.infer<typeof indexEntrySchema>;
export type IndexDocument = z.infer<typeof indexDocumentSchema>;
export type RecordDocument = z.infer<typeof recordDocumentSchema>;
export type RequestDocument = z.infer<typeof requestDocumentSchema>;
export type ReplyDocument = z.infer<typeof replyDocumentSchema>;
export type ProtocolDocument = z.infer<typeof protocolSchema>;
export type RunDocument = z.infer<typeof runDocumentSchema>;
export type RepairEvidence = z.infer<typeof repairEvidenceSchema>;

/**
 * Parses evidence JSON once at the untrusted file boundary.
 *
 * @param raw - JSON source text
 * @param sourcePath - Source path included in diagnostics
 * @param schema - Schema for the evidence document kind
 * @returns Validated evidence data
 */
export function parseEvidenceJson<T>(
  raw: string,
  sourcePath: string,
  schema: z.ZodType<T>,
): T {
  let decoded: unknown;
  try {
    decoded = JSON.parse(raw);
  } catch (error: unknown) {
    const detail = error instanceof Error ? error.message : String(error);
    throw new Error(`JSON 语法无效（${sourcePath}）：${detail}`);
  }
  const result = schema.safeParse(decoded);
  if (!result.success) {
    throw new Error(
      `JSON 数据结构无效（${sourcePath}）：${z.prettifyError(result.error)}`,
    );
  }
  return result.data;
}

/**
 * Converts an evidence value to non-empty display text.
 */
export function evidenceText(value: unknown, fallback = "缺失"): string {
  if (value === null || value === undefined) return fallback;
  if (typeof value === "string") return value.trim() || fallback;
  return String(value);
}

/**
 * Converts an evidence value to a finite number.
 */
export function evidenceNumber(value: unknown): number | null {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

/**
 * Converts a nullable evidence flag to Chinese display text.
 */
export function evidenceBooleanText(value: unknown): string {
  if (value === null || value === undefined) return "缺失";
  return value ? "是" : "否";
}

/**
 * Returns the first evidence value that contains meaningful data.
 */
export function firstEvidenceValue<T>(
  ...values: Array<T | null | undefined>
): T | undefined {
  for (const value of values) {
    if (value === null || value === undefined) continue;
    if (typeof value === "string" && !value.trim()) continue;
    if (Array.isArray(value) && value.length === 0) continue;
    if (
      typeof value === "object" &&
      !Array.isArray(value) &&
      Object.keys(value).length === 0
    ) {
      continue;
    }
    return value;
  }
  return undefined;
}
