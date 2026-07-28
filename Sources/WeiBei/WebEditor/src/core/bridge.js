/**
 * Creates the native WebKit message bridge for the active document.
 *
 * @param {object | undefined} handlers - WebKit message handlers
 * @param {string} initialDocumentID - Initial document identity
 * @returns {{ post: (name: string, body?: object) => void, setDocumentID: (next: string) => void, getDocumentID: () => string, hasHandler: (name: string) => boolean }}
 */
export function createBridge(handlers, initialDocumentID = '') {
  let currentDocumentID = initialDocumentID || '';

  return {
    post(name, body = {}) {
      handlers?.[name]?.postMessage({ ...body, documentID: currentDocumentID });
    },
    setDocumentID(next) {
      currentDocumentID = next || '';
    },
    getDocumentID() {
      return currentDocumentID;
    },
    hasHandler(name) {
      return Boolean(handlers?.[name]);
    },
  };
}
