import { z } from "zod";

export const themeModes = [
  "paper",
  "xuan",
  "inkstone",
  "stele",
  "glassLight",
  "glassDark",
  "glassMist",
  "glassSlate",
] as const;
export const ThemeModeSchema = z.enum(themeModes);
export type ThemeMode = z.infer<typeof ThemeModeSchema>;

export const InterfaceLanguageSchema = z.enum(["zh-Hans", "en"]);
export type InterfaceLanguage = z.infer<typeof InterfaceLanguageSchema>;

export const PaneRoleSchema = z.enum(["reader", "agent", "notes"]);
export type PaneRole = z.infer<typeof PaneRoleSchema>;

export const StudyItemKindSchema = z.enum(["html", "pdf", "markdown", "text"]);
export type StudyItemKind = z.infer<typeof StudyItemKindSchema>;

export const PreferencesSchema = z.object({
  theme: ThemeModeSchema.default("paper"),
  language: InterfaceLanguageSchema.default("zh-Hans"),
  textScale: z.number().min(0.9).max(1.6).default(1),
  glassIntensity: z.number().min(0).max(1).default(1),
  reduceMotion: z.boolean().default(false),
  paneOrder: z.array(PaneRoleSchema).length(3).default(["reader", "agent", "notes"]),
  visiblePanes: z.array(PaneRoleSchema).min(1).default(["reader", "agent", "notes"]),
  paneWidths: z.record(PaneRoleSchema, z.number().positive()).default({
    reader: 1,
    agent: 1,
    notes: 1,
  }),
});
export type Preferences = z.infer<typeof PreferencesSchema>;

export const CourseSummarySchema = z.object({
  id: z.string().uuid(),
  title: z.string().min(1),
  colorIndex: z.number().int().nonnegative(),
  rootPath: z.string(),
  createdAt: z.string(),
  updatedAt: z.string(),
  itemCount: z.number().int().nonnegative(),
});
export type CourseSummary = z.infer<typeof CourseSummarySchema>;

export const StudyItemSchema = z.object({
  id: z.string().min(1),
  title: z.string().min(1),
  subtitle: z.string(),
  kind: StudyItemKindSchema,
  isNotebookNote: z.boolean(),
  appearsInMaterials: z.boolean(),
  relativePath: z.string(),
  contentRevision: z.number().int().nonnegative(),
  contentDigest: z.string().nullable(),
  unavailable: z.boolean().default(false),
});
export type StudyItem = z.infer<typeof StudyItemSchema>;

export const CitationSchema = z.object({
  id: z.string().uuid(),
  itemId: z.string().nullable(),
  courseId: z.string().uuid().nullable(),
  kind: z.enum(["material", "note", "selection"]),
  title: z.string(),
  label: z.string(),
  excerpt: z.string(),
  pageIndex: z.number().int().nonnegative().nullable(),
  sectionTitle: z.string().nullable(),
  sectionLocationId: z.string().nullable(),
});
export type Citation = z.infer<typeof CitationSchema>;

export const NoteProposalSchema = z.object({
  id: z.string().uuid(),
  state: z.enum(["pending", "executed", "cancelled", "failed"]),
  targetItemId: z.string().nullable(),
  sourceItemId: z.string().nullable(),
  proposedMarkdown: z.string(),
  evidence: z.array(z.string()),
  baselineContentDigest: z.string().nullable(),
});
export type NoteProposal = z.infer<typeof NoteProposalSchema>;

export const AgentMessageSchema = z.object({
  id: z.string().uuid(),
  role: z.enum(["user", "assistant"]),
  text: z.string(),
  completionState: z.enum(["generating", "completed", "interrupted"]),
  sources: z.array(CitationSchema),
  actions: z.array(NoteProposalSchema),
  failureKind: z.string().nullable(),
  retryQuestion: z.string().nullable(),
  createdAt: z.string(),
});
export type AgentMessage = z.infer<typeof AgentMessageSchema>;

export const StudySessionSchema = z.object({
  id: z.string().uuid(),
  title: z.string(),
  courseId: z.string().uuid().nullable(),
  itemId: z.string().nullable(),
  messages: z.array(AgentMessageSchema),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type StudySession = z.infer<typeof StudySessionSchema>;

export const SelectionContextSchema = z.object({
  itemId: z.string(),
  text: z.string().min(1),
  pageIndex: z.number().int().nonnegative().nullable(),
  sectionTitle: z.string().nullable(),
  sectionLocationId: z.string().nullable(),
});
export type SelectionContext = z.infer<typeof SelectionContextSchema>;

export const ProviderPublicConfigSchema = z.object({
  providerId: z.string(),
  model: z.string(),
  baseUrl: z.string().url(),
  hasCredential: z.boolean(),
});
export type ProviderPublicConfig = z.infer<typeof ProviderPublicConfigSchema>;

export const CourseDetailSchema = CourseSummarySchema.extend({
  items: z.array(StudyItemSchema),
  sessions: z.array(StudySessionSchema),
  activeItemId: z.string().nullable(),
  activeNoteId: z.string().nullable(),
  activeSessionId: z.string().uuid().nullable(),
});
export type CourseDetail = z.infer<typeof CourseDetailSchema>;

export const AppSnapshotSchema = z.object({
  courses: z.array(CourseSummarySchema),
  activeCourse: CourseDetailSchema.nullable(),
  preferences: PreferencesSchema,
  provider: ProviderPublicConfigSchema,
  libraryRootPath: z.string(),
  platform: z.literal("windows"),
  appVersion: z.string(),
});
export type AppSnapshot = z.infer<typeof AppSnapshotSchema>;

export const DocumentPayloadSchema = z.object({
  item: StudyItemSchema,
  mediaType: z.enum(["text/markdown", "text/plain", "text/html", "application/pdf"]),
  content: z.string().nullable(),
  documentGrantUrl: z.string().nullable(),
  digest: z.string(),
});
export type DocumentPayload = z.infer<typeof DocumentPayloadSchema>;

export const SearchRequestSchema = z.object({
  courseId: z.string().uuid(),
  query: z.string().trim().min(1).max(500),
  limit: z.number().int().min(1).max(100).default(30),
});
export type SearchRequest = z.infer<typeof SearchRequestSchema>;

export const SearchResultSchema = z.object({
  itemId: z.string(),
  title: z.string(),
  kind: StudyItemKindSchema,
  excerpt: z.string(),
  rank: z.number(),
});
export type SearchResult = z.infer<typeof SearchResultSchema>;

export const SaveNoteRequestSchema = z.object({
  courseId: z.string().uuid(),
  itemId: z.string(),
  markdown: z.string(),
  baselineDigest: z.string().nullable(),
});
export type SaveNoteRequest = z.infer<typeof SaveNoteRequestSchema>;

export const SaveNoteResultSchema = z.object({
  status: z.enum(["saved", "conflict", "unavailable"]),
  digest: z.string().nullable(),
  diskMarkdown: z.string().nullable(),
  backupPath: z.string().nullable(),
});
export type SaveNoteResult = z.infer<typeof SaveNoteResultSchema>;

export const NoteRecoveryRecordSchema = z.object({
  schemaVersion: z.literal(1),
  itemId: z.string().min(1).max(256),
  markdown: z.string(),
  baselineDigest: z.string().regex(/^[a-f0-9]{64}$/u).nullable(),
  savedAt: z.string(),
});
export type NoteRecoveryRecord = z.infer<typeof NoteRecoveryRecordSchema>;

export const AgentStartRequestSchema = z.object({
  courseId: z.string().uuid(),
  sessionId: z.string().uuid(),
  question: z.string().trim().min(1).max(32_000),
  selection: SelectionContextSchema.nullable(),
});
export type AgentStartRequest = z.infer<typeof AgentStartRequestSchema>;

export const AgentEventSchema = z.discriminatedUnion("type", [
  z.object({
    type: z.literal("started"),
    requestId: z.string().uuid(),
    sessionId: z.string().uuid(),
    userMessage: AgentMessageSchema,
    assistantMessage: AgentMessageSchema,
  }),
  z.object({
    type: z.literal("delta"),
    requestId: z.string().uuid(),
    messageId: z.string().uuid(),
    text: z.string(),
  }),
  z.object({
    type: z.literal("completed"),
    requestId: z.string().uuid(),
    message: AgentMessageSchema,
  }),
  z.object({
    type: z.literal("failed"),
    requestId: z.string().uuid(),
    messageId: z.string().uuid(),
    failureKind: z.string(),
  }),
  z.object({
    type: z.literal("cancelled"),
    requestId: z.string().uuid(),
    message: AgentMessageSchema,
  }),
]);
export type AgentEvent = z.infer<typeof AgentEventSchema>;

export interface WeiBeiDesktopAPI {
  bootstrap(): Promise<AppSnapshot>;
  chooseLibraryRoot(): Promise<AppSnapshot | null>;
  createCourse(title: string): Promise<AppSnapshot>;
  adoptCourseFolder(): Promise<AppSnapshot | null>;
  selectCourse(courseId: string): Promise<AppSnapshot>;
  importItems(courseId: string): Promise<AppSnapshot>;
  createNote(courseId: string, title: string): Promise<AppSnapshot>;
  openItem(courseId: string, itemId: string): Promise<DocumentPayload>;
  saveNote(request: SaveNoteRequest): Promise<SaveNoteResult>;
  loadNoteRecovery(itemId: string): Promise<NoteRecoveryRecord | null>;
  saveNoteRecovery(input: Pick<NoteRecoveryRecord, "itemId" | "markdown" | "baselineDigest">): Promise<NoteRecoveryRecord>;
  clearNoteRecovery(itemId: string): Promise<void>;
  updatePreferences(patch: Partial<Preferences>): Promise<Preferences>;
  search(request: SearchRequest): Promise<SearchResult[]>;
  createSession(courseId: string): Promise<StudySession>;
  selectSession(courseId: string, sessionId: string): Promise<AppSnapshot>;
  saveProvider(config: {
    providerId: string;
    model: string;
    baseUrl: string;
    apiKey?: string;
  }): Promise<ProviderPublicConfig>;
  startAgent(request: AgentStartRequest): Promise<{ requestId: string }>;
  cancelAgent(requestId: string): Promise<void>;
  applyNoteProposal(courseId: string, sessionId: string, messageId: string, actionId: string): Promise<AppSnapshot>;
  revealItem(courseId: string, itemId: string): Promise<void>;
  onAgentEvent(listener: (event: AgentEvent) => void): () => void;
  onLibraryChanged(listener: (snapshot: AppSnapshot) => void): () => void;
  window: {
    minimize(): Promise<void>;
    toggleMaximize(): Promise<boolean>;
    close(): Promise<void>;
    isMaximized(): Promise<boolean>;
  };
}
