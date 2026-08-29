import { mkdir, readFile } from "node:fs/promises";
import path from "node:path";
import type { Preferences, ProviderPublicConfig } from "../../shared/contracts";
import { PreferencesSchema, ProviderPublicConfigSchema } from "../../shared/contracts";
import { atomicWriteVerified } from "./file-utils";

export interface StoredState {
  schemaVersion: 1;
  libraryRootPath: string;
  activeCourseId: string | null;
  activeItemsByCourse: Record<string, string>;
  activeNotesByCourse: Record<string, string>;
  activeSessionsByCourse: Record<string, string>;
  preferences: Preferences;
  provider: ProviderPublicConfig;
}

const defaultProvider: ProviderPublicConfig = {
  providerId: "openai",
  model: "gpt-5.4",
  baseUrl: "https://api.openai.com/v1",
  hasCredential: false,
};

export class AppStateStore {
  private readonly statePath: string;
  private state: StoredState;
  private writeQueue: Promise<void> = Promise.resolve();

  private constructor(statePath: string, state: StoredState) {
    this.statePath = statePath;
    this.state = state;
  }

  static async open(options: {
    userDataPath: string;
    defaultLibraryRootPath: string;
  }): Promise<AppStateStore> {
    await mkdir(options.userDataPath, { recursive: true });
    const statePath = path.join(options.userDataPath, "windows-state.json");
    let raw: unknown;
    try {
      raw = JSON.parse(await readFile(statePath, "utf8"));
    } catch {
      raw = null;
    }
    const record = raw && typeof raw === "object" ? (raw as Record<string, unknown>) : {};
    const state: StoredState = {
      schemaVersion: 1,
      libraryRootPath:
        typeof record.libraryRootPath === "string" && record.libraryRootPath
          ? record.libraryRootPath
          : options.defaultLibraryRootPath,
      activeCourseId:
        typeof record.activeCourseId === "string" ? record.activeCourseId : null,
      activeItemsByCourse: stringRecord(record.activeItemsByCourse),
      activeNotesByCourse: stringRecord(record.activeNotesByCourse),
      activeSessionsByCourse: stringRecord(record.activeSessionsByCourse),
      preferences: PreferencesSchema.parse(record.preferences ?? {}),
      provider: ProviderPublicConfigSchema.parse(record.provider ?? defaultProvider),
    };
    const store = new AppStateStore(statePath, state);
    await store.persist();
    return store;
  }

  snapshot(): Readonly<StoredState> {
    return structuredClone(this.state);
  }

  async setLibraryRoot(libraryRootPath: string): Promise<void> {
    this.state.libraryRootPath = libraryRootPath;
    this.state.activeCourseId = null;
    await this.persist();
  }

  async setActiveCourse(courseId: string | null): Promise<void> {
    this.state.activeCourseId = courseId;
    await this.persist();
  }

  async setActiveItem(courseId: string, itemId: string): Promise<void> {
    this.state.activeItemsByCourse[courseId] = itemId;
    await this.persist();
  }

  async setActiveNote(courseId: string, itemId: string): Promise<void> {
    this.state.activeNotesByCourse[courseId] = itemId;
    await this.persist();
  }

  async setActiveSession(courseId: string, sessionId: string): Promise<void> {
    this.state.activeSessionsByCourse[courseId] = sessionId;
    await this.persist();
  }

  async updatePreferences(patch: Partial<Preferences>): Promise<Preferences> {
    this.state.preferences = PreferencesSchema.parse({
      ...this.state.preferences,
      ...patch,
    });
    await this.persist();
    return structuredClone(this.state.preferences);
  }

  async updateProvider(provider: ProviderPublicConfig): Promise<ProviderPublicConfig> {
    this.state.provider = ProviderPublicConfigSchema.parse(provider);
    await this.persist();
    return structuredClone(this.state.provider);
  }

  private async persist(): Promise<void> {
    const payload = JSON.stringify(this.state, null, 2) + "\n";
    this.writeQueue = this.writeQueue.then(async () => {
      await atomicWriteVerified(this.statePath, payload);
    });
    await this.writeQueue;
  }
}

function stringRecord(value: unknown): Record<string, string> {
  if (!value || typeof value !== "object") return {};
  return Object.fromEntries(
    Object.entries(value).filter(
      (entry): entry is [string, string] => typeof entry[1] === "string",
    ),
  );
}
