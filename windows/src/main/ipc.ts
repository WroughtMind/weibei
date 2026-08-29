import { ipcMain, type BrowserWindow } from "electron";
import { z } from "zod";
import {
  AgentStartRequestSchema,
  NoteRecoveryRecordSchema,
  PreferencesSchema,
  SaveNoteRequestSchema,
  SearchRequestSchema,
} from "../shared/contracts";
import { IPC } from "../shared/ipc";
import type { WeiBeiController } from "./controller";

const UUID = z.string().uuid();
const nonemptyTitle = z.string().trim().min(1).max(120);
const itemID = z.string().min(1).max(256);
const noteRecoveryInput = NoteRecoveryRecordSchema.pick({
  itemId: true,
  markdown: true,
  baselineDigest: true,
});

export function registerIPC(controller: WeiBeiController, window: BrowserWindow): () => void {
  const handles = <T extends (...args: never[]) => unknown>(channel: string, operation: T) => {
    ipcMain.handle(channel, async (event, ...args: unknown[]) => {
      if (event.sender !== window.webContents || event.senderFrame !== window.webContents.mainFrame) {
        throw new Error("ipc-capability-denied");
      }
      return operation(...(args as Parameters<T>));
    });
  };

  handles(IPC.bootstrap, () => controller.bootstrap());
  handles(IPC.chooseLibraryRoot, () => controller.chooseLibraryRoot());
  handles(IPC.createCourse, (title: unknown) => controller.createCourse(nonemptyTitle.parse(title)));
  handles(IPC.adoptCourseFolder, () => controller.adoptCourseFolder());
  handles(IPC.selectCourse, (courseID: unknown) => controller.selectCourse(UUID.parse(courseID)));
  handles(IPC.importItems, (courseID: unknown) => controller.importItems(UUID.parse(courseID)));
  handles(IPC.createNote, (courseID: unknown, title: unknown) => controller.createNote(UUID.parse(courseID), nonemptyTitle.parse(title)));
  handles(IPC.openItem, (courseID: unknown, rawItemID: unknown) => controller.openItem(UUID.parse(courseID), itemID.parse(rawItemID)));
  handles(IPC.saveNote, (request: unknown) => controller.saveNote(SaveNoteRequestSchema.parse(request)));
  handles(IPC.loadNoteRecovery, (rawItemID: unknown) => controller.loadNoteRecovery(itemID.parse(rawItemID)));
  handles(IPC.saveNoteRecovery, (input: unknown) => controller.saveNoteRecovery(noteRecoveryInput.parse(input)));
  handles(IPC.clearNoteRecovery, (rawItemID: unknown) => controller.clearNoteRecovery(itemID.parse(rawItemID)));
  handles(IPC.updatePreferences, (patch: unknown) => controller.updatePreferences(PreferencesSchema.partial().parse(patch)));
  handles(IPC.search, (request: unknown) => controller.search(SearchRequestSchema.parse(request)));
  handles(IPC.createSession, (courseID: unknown) => controller.createSession(UUID.parse(courseID)));
  handles(IPC.selectSession, (courseID: unknown, sessionID: unknown) => controller.selectSession(UUID.parse(courseID), UUID.parse(sessionID)));
  handles(IPC.saveProvider, (config: unknown) => controller.saveProvider(z.object({
    providerId: z.string().trim().min(1).max(80),
    model: z.string().trim().min(1).max(200),
    baseUrl: z.string().url().max(2_048),
    apiKey: z.string().min(1).max(1024 * 1024).optional(),
  }).parse(config)));
  handles(IPC.startAgent, (request: unknown) => controller.startAgent(AgentStartRequestSchema.parse(request)));
  handles(IPC.cancelAgent, (requestID: unknown) => controller.agent.cancel(UUID.parse(requestID)));
  handles(IPC.applyNoteProposal, (...values: unknown[]) => {
    const [courseID, sessionID, messageID, actionID] = z.tuple([UUID, UUID, UUID, UUID]).parse(values);
    return controller.applyNoteProposal(courseID, sessionID, messageID, actionID);
  });
  handles(IPC.revealItem, (courseID: unknown, rawItemID: unknown) => controller.revealItem(UUID.parse(courseID), itemID.parse(rawItemID)));
  handles(IPC.windowMinimize, () => window.minimize());
  handles(IPC.windowToggleMaximize, () => { if (window.isMaximized()) window.unmaximize(); else window.maximize(); return window.isMaximized(); });
  handles(IPC.windowClose, () => window.close());
  handles(IPC.windowIsMaximized, () => window.isMaximized());

  const stopEvents = controller.agent.onEvent((event) => {
    if (!window.isDestroyed()) window.webContents.send(IPC.agentEvent, event);
  });
  const stopLibraryEvents = controller.onLibraryChanged((snapshot) => {
    if (!window.isDestroyed()) window.webContents.send(IPC.libraryChanged, snapshot);
  });
  return () => {
    stopEvents();
    stopLibraryEvents();
    void controller.agent.dispose();
    for (const channel of Object.values(IPC)) {
      if (channel !== IPC.agentEvent) ipcMain.removeHandler(channel);
    }
  };
}
