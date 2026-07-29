import type { Editor } from "@milkdown/kit/core";
export type { EditorLabel } from "./core/i18n.js";

/** Selection bounds in editor viewport coordinates. */
export interface SelectionRectangle {
  x: number;
  y: number;
  width: number;
  height: number;
}

/**
 * Native messages emitted by the editor and their payload contracts.
 */
export interface EditorBridgeMessageMap {
  activeHeadingChanged: { index: number | null };
  askAgentWithSelection: {
    text: string;
    rect: SelectionRectangle | null;
  };
  contentHeightChanged: { height: number };
  editorReady: { markdown: string };
  imageAttachmentRequested: {
    id: string;
    name: string;
    mime: string;
    dataURL: string;
  };
  imagePickerRequested: { id: string };
  markdownChanged: { markdown: string };
  selectionChanged: {
    text: string;
    rect: SelectionRectangle | null;
  };
  sourceReferenceActivated: { reference: string };
  wikiLinkActivated: { title: string };
}

export type EditorBridgeMessageName = keyof EditorBridgeMessageMap;

/**
 * Native WebKit message handler exposed to JavaScript.
 */
export interface WebKitMessageHandler {
  postMessage(
    message: EditorBridgeMessageMap[EditorBridgeMessageName] & {
      documentID: string;
    },
  ): void;
}

/**
 * Message handlers installed by the native WebKit host.
 */
export type WebKitMessageHandlers = Partial<Record<
  EditorBridgeMessageName,
  WebKitMessageHandler | undefined
>>;

export interface EditorHostWindow extends Window {
  webkit?: {
    messageHandlers?: WebKitMessageHandlers;
  };
}

/**
 * Stable message bridge used by editor features.
 */
export interface EditorBridge {
  post<Name extends EditorBridgeMessageName>(
    name: Name,
    body: EditorBridgeMessageMap[Name],
  ): void;
  setDocumentID(next: string): void;
  getDocumentID(): string;
  hasHandler(name: EditorBridgeMessageName): boolean;
}

/**
 * Text range expressed as ProseMirror document offsets.
 */
export interface EditorRange {
  from: number;
  to: number;
}

/**
 * Callback that exposes the active Milkdown editor once initialization completes.
 */
export type GetEditor = () => Editor | undefined;

/**
 * Callback that reports a failure to the native host or the editor fallback UI.
 */
export type ShowFailure = (error: unknown) => void;

/** Observable slash-menu state returned to native self-checks. */
export interface SlashCheckState {
  show: boolean;
  commands: string[];
  groups: string[];
  icons: number;
  descriptions: number;
  activeDescendant: string;
  announcement: string;
  error: string;
  tableOpen: boolean;
  rows: number;
  columns: number;
}

/**
 * Stable JavaScript API called by the native WKWebView host.
 */
export interface EditorPublicAPI {
  getMarkdown(): string;
  setMarkdown(markdown: string): void;
  replaceSelection(markdown: string): void | undefined;
  applyAgentPatch(markdown: string): void | undefined;
  askAgentWithSelection(): void;
  insertMarkdownImage(markdown: string): void | undefined;
  insertMarkdown(markdown: string): void | undefined;
  resolveAttachment(id: string, src: string, alt: string): void;
  rejectAttachment(id: string, message?: string): void;
  discardAttachment(id: string): boolean;
  resolveImagePicker(id: string, src: string, alt: string): boolean;
  cancelImagePicker(id: string): boolean;
  discardImagePicker(id: string): boolean;
  rejectImagePicker(id: string, message?: string): boolean;
  setEditable(next: boolean): void;
  setDocumentID(next: string): void;
  setMarkdownBaseURL(next: string): void;
  setTheme(next: string): void;
  setInterfaceLanguage(next: string): void;
  scrollToHeading(rawIndex: unknown): boolean;
  selectFirstTextForCheck?(needle: string): boolean;
  placeCursorAtTextForCheck?(needle: string, offset?: number): boolean;
  selectedTextForCheck?(): string;
  typeTextForCheck?(text: string): boolean;
  pressKeyForCheck?(
    key: string,
    options?: {
      shiftKey?: boolean;
      altKey?: boolean;
      metaKey?: boolean;
      ctrlKey?: boolean;
    },
  ): boolean;
  openSlashMenuForCheck?(): boolean;
  slashStateForCheck?(): SlashCheckState;
  openSlashTableForCheck?(): boolean;
  setSlashTableSizeForCheck?(rows: number, columns: number): boolean;
  executeSlashCommandForCheck?(commandID: string): boolean;
  pendingImagePickerIDsForCheck?(): string[];
  undoForCheck?(): boolean;
}

declare global {
  interface Window {
    WeiBeiCompactPreviewHeight?: number;
    WeiBeiCompactPreviewMeasuredAt?: number;
    WeiBeiEditor?: EditorPublicAPI;
    WeiBeiEditorBootFailed?: (error: unknown) => void;
    initialMarkdown?: string;
    weiBeiDocumentID?: string;
    weiBeiEditorCheckMode?: boolean;
    weiBeiInterfaceLanguage?: string;
    weiBeiLocalImageScheme?: string;
    weiBeiMarkdownBaseURL?: string;
    weiBeiMarkdownCompactPreview?: boolean;
    weiBeiMarkdownEditable?: boolean;
    weiBeiSuppressSelectionReport?: boolean;
    weiBeiTheme?: string;
  }
}

export {};
