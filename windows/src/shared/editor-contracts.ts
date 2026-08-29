import {
  editorCommandTypes,
  editorProtocolVersion,
  type EditorCommand as CanonicalEditorCommand,
} from "../../../Sources/WeiBei/WebEditor/src/bridge/protocol";

export { editorCommandTypes, editorProtocolVersion };

/**
 * Cross-platform contract for the canonical Milkdown WebEditor.
 *
 * Transport messages are Windows/Electron-specific. The nested editor command
 * remains protocol v2 so the macOS and Windows hosts share document identity,
 * revision, and idempotency semantics.
 */

export const editorHostTransportVersion = 1 as const;

export type EditorCommandType = (typeof editorCommandTypes)[number];

export type EditorTheme =
  | "paper"
  | "xuan"
  | "inkstone"
  | "stele"
  | "glassLight"
  | "glassDark"
  | "glassMist"
  | "glassSlate";

export type EditorInterfaceLanguage = "zh-Hans" | "en";

export interface EditorCommandPayloads {
  loadDocument: { markdown: string; initialRevision?: number };
  requestSnapshot: Record<string, never>;
  setTheme: { theme: EditorTheme };
  setLanguage: { language: EditorInterfaceLanguage };
  setEditable: { editable: boolean };
  focus: Record<string, never>;
  scrollToHeading: { index: number };
  applyMarkdownFragment: { markdown: string };
  replaceSelection: { markdown: string };
  executeSelectionCommand: { action: string; value?: unknown };
  insertStructuredBlock: { markdown: string };
  restoreCheckpoint: { markdown: string; revision?: number };
}

type EditorCommandBase<Type extends EditorCommandType> = Omit<
  CanonicalEditorCommand,
  "type" | "payload" | "requestID"
> & {
  type: Type;
  payload: EditorCommandPayloads[Type];
};

export type EditorCommand = {
  [Type in EditorCommandType]: EditorCommandBase<Type> &
    (Type extends "requestSnapshot"
      ? { requestID: string }
      : { requestID?: string });
}[EditorCommandType];

export interface EditorHostBootstrap {
  markdown: string;
  documentID: string;
  documentGeneration: number;
  /** Chooses editor-entry.js (true) or viewer-entry.js (false) for this frame. */
  editable: boolean;
  markdownBaseURL: string;
  localImageScheme: string;
  theme: EditorTheme;
  interfaceLanguage: EditorInterfaceLanguage;
  compactPreview: boolean;
  wideTypography: boolean;
  reduceMotion: boolean;
  textScale: number;
}

export type EditorHostBootstrapInput = Pick<
  EditorHostBootstrap,
  "markdown" | "documentID" | "editable"
> &
  Partial<Omit<EditorHostBootstrap, "markdown" | "documentID" | "editable">>;

export const editorBridgeMessageNames = [
  "editorReady",
  "dirtyChanged",
  "snapshotReady",
  "commandApplied",
  "commandRejected",
  "outlineChanged",
  "selectionChanged",
  "askAgentWithSelection",
  "linkEditorRequested",
  "wikiLinkActivated",
  "sourceReferenceActivated",
  "externalLinkActivated",
  "editorFailure",
  "imageAttachmentRequested",
  "imagePickerRequested",
  "contentHeightChanged",
  "finalizedStreaming",
  "activeHeadingChanged",
  "compactPreviewWheel",
  "selectionAskMark",
  "remarkMark",
  "streamDebug",
] as const;

export type EditorBridgeMessageName =
  (typeof editorBridgeMessageNames)[number];

export interface EditorEventSession {
  protocolVersion: typeof editorProtocolVersion;
  documentID: string;
  documentGeneration: number;
  revision: number;
}

export interface EditorSelectionRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface EditorOutlineItem {
  id: string;
  index: number;
  level: number;
  title: string;
  position: number;
}

export interface EditorBridgeEventBodies {
  editorReady: EditorEventSession;
  dirtyChanged: EditorEventSession & { dirty: boolean };
  snapshotReady: EditorEventSession & {
    requestID: string;
    markdown: string;
  };
  commandApplied: EditorEventSession & { commandID: string };
  commandRejected: EditorEventSession & {
    commandID: string;
    reason: string;
  };
  outlineChanged: EditorEventSession & { items: EditorOutlineItem[] };
  selectionChanged: EditorEventSession & {
    text: string;
    rect: EditorSelectionRect | null;
    activeMarks?: string[];
    blockType?: string;
    canConvertToMath?: boolean;
    linkTarget?: string;
  };
  askAgentWithSelection: Record<string, unknown>;
  linkEditorRequested: EditorEventSession;
  wikiLinkActivated: EditorEventSession & { title: string };
  sourceReferenceActivated: EditorEventSession & { reference: string };
  externalLinkActivated: { url: string };
  /** Boot failures occur before a complete editor session exists. */
  editorFailure: {
    documentID: string;
    message: string;
    protocolVersion?: typeof editorProtocolVersion;
    documentGeneration?: number;
    revision?: number;
  };
  imageAttachmentRequested: EditorEventSession & {
    id: string;
    name: string;
    mime: string;
    dataURL: string;
  };
  imagePickerRequested: EditorEventSession & { id: string };
  contentHeightChanged: EditorEventSession & { height: number };
  finalizedStreaming: EditorEventSession & { height: number };
  activeHeadingChanged: EditorEventSession & { index: number | null };
  compactPreviewWheel: { documentID: string; deltaY: number };
  selectionAskMark: EditorEventSession & { threadId: string; text: string };
  remarkMark: EditorEventSession & { recordId: string; text: string };
  streamDebug: EditorEventSession & Record<string, unknown>;
}

export type EditorBridgeEvent<
  Name extends EditorBridgeMessageName = EditorBridgeMessageName,
> = {
  [CurrentName in Name]: {
    kind: "event";
    transportVersion: typeof editorHostTransportVersion;
    instanceId: string;
    name: CurrentName;
    body: EditorBridgeEventBodies[CurrentName];
  };
}[Name];

export interface EditorSelectionMark {
  id: string;
  text: string;
}

export type EditorRuntimeCall =
  | { method: "setMarkdown"; args: [markdown: string] }
  | { method: "updateStreamingMarkdown"; args: [markdown: string] }
  | { method: "appendStreamingMarkdown"; args: [suffix: string] }
  | { method: "finishStreamingMarkdown"; args: [markdown: string] }
  | { method: "setDocumentID"; args: [documentID: string] }
  | { method: "setTheme"; args: [theme: EditorTheme] }
  | {
      method: "setInterfaceLanguage";
      args: [language: EditorInterfaceLanguage];
    }
  | { method: "setReduceMotion"; args: [reduceMotion: boolean] }
  | { method: "setTextScale"; args: [textScale: number] }
  | { method: "focus"; args: [] }
  | { method: "scrollToHeading"; args: [index: number] }
  | {
      method: "setSelectionAskMarks";
      args: [marks: EditorSelectionMark[]];
    }
  | {
      method: "setSelectionRemarkMarks";
      args: [marks: EditorSelectionMark[]];
    }
  | { method: "setMarkdownBaseURL"; args: [url: string] }
  | {
      method: "resolveAttachment";
      args: [id: string, src: string, alt: string];
    }
  | { method: "rejectAttachment"; args: [id: string, message: string] }
  | {
      method: "resolveImagePicker";
      args: [id: string, src: string, alt: string];
    }
  | { method: "cancelImagePicker"; args: [id: string] }
  | { method: "discardImagePicker"; args: [id: string] }
  | { method: "rejectImagePicker"; args: [id: string, message: string] };

export const editorRuntimeMethods = [
  "setMarkdown",
  "updateStreamingMarkdown",
  "appendStreamingMarkdown",
  "finishStreamingMarkdown",
  "setDocumentID",
  "setTheme",
  "setInterfaceLanguage",
  "setReduceMotion",
  "setTextScale",
  "focus",
  "scrollToHeading",
  "setSelectionAskMarks",
  "setSelectionRemarkMarks",
  "setMarkdownBaseURL",
  "resolveAttachment",
  "rejectAttachment",
  "resolveImagePicker",
  "cancelImagePicker",
  "discardImagePicker",
  "rejectImagePicker",
] as const satisfies readonly EditorRuntimeCall["method"][];

export type EditorFrameRequest =
  | {
      kind: "command";
      transportVersion: typeof editorHostTransportVersion;
      instanceId: string;
      command: EditorCommand;
    }
  | {
      kind: "call";
      transportVersion: typeof editorHostTransportVersion;
      instanceId: string;
      call: EditorRuntimeCall;
    }
  | {
      kind: "dispose";
      transportVersion: typeof editorHostTransportVersion;
      instanceId: string;
    };

export interface EditorFrameReadyMessage {
  kind: "weibei-editor-frame-ready";
  transportVersion: typeof editorHostTransportVersion;
  instanceId: string;
  frameNonce: string;
}

export interface EditorHostInitMessage {
  kind: "weibei-editor-host-init";
  transportVersion: typeof editorHostTransportVersion;
  instanceId: string;
  frameNonce: string;
  bootstrap: EditorHostBootstrap;
}
