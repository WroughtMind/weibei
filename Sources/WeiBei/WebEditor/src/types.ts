import type { Editor } from "@milkdown/kit/core";

/**
 * JSON-compatible payload sent from the editor to its native WebKit host.
 */
export type BridgePayload = Record<string, unknown>;

/**
 * Native WebKit message handler exposed to JavaScript.
 */
export interface WebKitMessageHandler {
  postMessage(message: BridgePayload): void;
}

/**
 * Message handlers installed by the native WebKit host.
 */
export type WebKitMessageHandlers = Record<
  string,
  WebKitMessageHandler | undefined
>;

/**
 * Stable message bridge used by editor features.
 */
export interface EditorBridge {
  post(name: string, body?: BridgePayload): void;
  setDocumentID(next: string): void;
  getDocumentID(): string;
  hasHandler(name: string): boolean;
}

/**
 * Text range expressed as ProseMirror document offsets.
 */
export interface EditorRange {
  from: number;
  to: number;
}

/**
 * Localized editor label formatter.
 */
export type EditorLabel = (
  key: string,
  values?: Record<string, unknown>,
) => string;

/**
 * Callback that exposes the active Milkdown editor once initialization completes.
 */
export type GetEditor = () => Editor | undefined;

/**
 * Callback that reports a failure to the native host or the editor fallback UI.
 */
export type ShowFailure = (error: unknown) => void;

declare global {
  interface Window {
    webkit?: {
      messageHandlers?: WebKitMessageHandlers;
    };
    WeiBeiCompactPreviewHeight?: number;
    WeiBeiCompactPreviewMeasuredAt?: number;
    WeiBeiEditor?: unknown;
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
