import type {
  BridgePayload,
  EditorBridge,
  WebKitMessageHandlers,
} from "../types.js";

/**
 * Creates the native WebKit message bridge for the active document.
 *
 * @param handlers - WebKit message handlers
 * @param initialDocumentID - Initial document identity
 * @returns Stable bridge bound to the active document
 */
export function createBridge(
  handlers: WebKitMessageHandlers | undefined,
  initialDocumentID = "",
): EditorBridge {
  let currentDocumentID = initialDocumentID || "";

  return {
    post(name: string, body: BridgePayload = {}) {
      handlers?.[name]?.postMessage({ ...body, documentID: currentDocumentID });
    },
    setDocumentID(next: string) {
      currentDocumentID = next || "";
    },
    getDocumentID() {
      return currentDocumentID;
    },
    hasHandler(name: string) {
      return Boolean(handlers?.[name]);
    },
  };
}
