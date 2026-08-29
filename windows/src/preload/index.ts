import { contextBridge, ipcRenderer } from "electron";
import {
  AgentEventSchema,
  AppSnapshotSchema,
  DocumentPayloadSchema,
  NoteRecoveryRecordSchema,
  PreferencesSchema,
  ProviderPublicConfigSchema,
  SaveNoteResultSchema,
  SearchResultSchema,
  StudySessionSchema,
  type WeiBeiDesktopAPI,
} from "../shared/contracts";
import { IPC } from "../shared/ipc";

const api: WeiBeiDesktopAPI = {
  bootstrap: async () => AppSnapshotSchema.parse(await ipcRenderer.invoke(IPC.bootstrap)),
  chooseLibraryRoot: async () => nullableSnapshot(await ipcRenderer.invoke(IPC.chooseLibraryRoot)),
  createCourse: async (title) => AppSnapshotSchema.parse(await ipcRenderer.invoke(IPC.createCourse, title)),
  adoptCourseFolder: async () => nullableSnapshot(await ipcRenderer.invoke(IPC.adoptCourseFolder)),
  selectCourse: async (courseId) => AppSnapshotSchema.parse(await ipcRenderer.invoke(IPC.selectCourse, courseId)),
  importItems: async (courseId) => AppSnapshotSchema.parse(await ipcRenderer.invoke(IPC.importItems, courseId)),
  createNote: async (courseId, title) => AppSnapshotSchema.parse(await ipcRenderer.invoke(IPC.createNote, courseId, title)),
  openItem: async (courseId, itemId) => DocumentPayloadSchema.parse(await ipcRenderer.invoke(IPC.openItem, courseId, itemId)),
  saveNote: async (request) => SaveNoteResultSchema.parse(await ipcRenderer.invoke(IPC.saveNote, request)),
  loadNoteRecovery: async (itemId) => {
    const value: unknown = await ipcRenderer.invoke(IPC.loadNoteRecovery, itemId);
    return value === null ? null : NoteRecoveryRecordSchema.parse(value);
  },
  saveNoteRecovery: async (input) => NoteRecoveryRecordSchema.parse(await ipcRenderer.invoke(IPC.saveNoteRecovery, input)),
  clearNoteRecovery: async (itemId) => { await ipcRenderer.invoke(IPC.clearNoteRecovery, itemId); },
  updatePreferences: async (patch) => PreferencesSchema.parse(await ipcRenderer.invoke(IPC.updatePreferences, patch)),
  search: async (request) => SearchResultSchema.array().parse(await ipcRenderer.invoke(IPC.search, request)),
  createSession: async (courseId) => StudySessionSchema.parse(await ipcRenderer.invoke(IPC.createSession, courseId)),
  selectSession: async (courseId, sessionId) => AppSnapshotSchema.parse(await ipcRenderer.invoke(IPC.selectSession, courseId, sessionId)),
  saveProvider: async (config) => ProviderPublicConfigSchema.parse(await ipcRenderer.invoke(IPC.saveProvider, config)),
  startAgent: async (request) => ipcRenderer.invoke(IPC.startAgent, request) as Promise<{ requestId: string }>,
  cancelAgent: async (requestId) => { await ipcRenderer.invoke(IPC.cancelAgent, requestId); },
  applyNoteProposal: async (courseId, sessionId, messageId, actionId) => AppSnapshotSchema.parse(await ipcRenderer.invoke(IPC.applyNoteProposal, courseId, sessionId, messageId, actionId)),
  revealItem: async (courseId, itemId) => { await ipcRenderer.invoke(IPC.revealItem, courseId, itemId); },
  onAgentEvent(listener) {
    const wrapped = (_event: Electron.IpcRendererEvent, value: unknown) => listener(AgentEventSchema.parse(value));
    ipcRenderer.on(IPC.agentEvent, wrapped);
    return () => ipcRenderer.removeListener(IPC.agentEvent, wrapped);
  },
  onLibraryChanged(listener) {
    const wrapped = (_event: Electron.IpcRendererEvent, value: unknown) => listener(AppSnapshotSchema.parse(value));
    ipcRenderer.on(IPC.libraryChanged, wrapped);
    return () => ipcRenderer.removeListener(IPC.libraryChanged, wrapped);
  },
  window: {
    minimize: async () => { await ipcRenderer.invoke(IPC.windowMinimize); },
    toggleMaximize: async () => Boolean(await ipcRenderer.invoke(IPC.windowToggleMaximize)),
    close: async () => { await ipcRenderer.invoke(IPC.windowClose); },
    isMaximized: async () => Boolean(await ipcRenderer.invoke(IPC.windowIsMaximized)),
  },
};

contextBridge.exposeInMainWorld("weibei", Object.freeze(api));

function nullableSnapshot(value: unknown) {
  return value === null ? null : AppSnapshotSchema.parse(value);
}
