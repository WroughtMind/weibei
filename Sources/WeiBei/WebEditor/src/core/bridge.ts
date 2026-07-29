import type {
  EditorBridge,
  EditorBridgeMessageMap,
  EditorBridgeMessageName,
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
    post<Name extends EditorBridgeMessageName>(
      name: Name,
      body: EditorBridgeMessageMap[Name],
    ) {
      handlers?.[name]?.postMessage({ ...body, documentID: currentDocumentID });
    },
    setDocumentID(next: string) {
      currentDocumentID = next || "";
    },
    getDocumentID() {
      return currentDocumentID;
    },
    hasHandler(name: EditorBridgeMessageName) {
      return Boolean(handlers?.[name]);
    },
  };
}
