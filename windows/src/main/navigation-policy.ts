export type MainWindowNavigationPolicy =
  | { mode: "development"; rendererURL: string }
  | { mode: "packaged"; rendererEntryURL: string };

/** Keeps the preload-backed main frame on the renderer source selected at startup. */
export function isAllowedMainWindowNavigation(
  target: string,
  policy: MainWindowNavigationPolicy,
): boolean {
  let destination: URL;
  try {
    destination = new URL(target);
  } catch {
    return false;
  }

  if (policy.mode === "development") {
    let renderer: URL;
    try {
      renderer = new URL(policy.rendererURL);
    } catch {
      return false;
    }
    if (renderer.protocol !== "http:" && renderer.protocol !== "https:") return false;
    return destination.protocol === renderer.protocol && destination.origin === renderer.origin;
  }

  let entry: URL;
  try {
    entry = new URL(policy.rendererEntryURL);
  } catch {
    return false;
  }
  if (entry.protocol !== "file:" || destination.protocol !== "file:") return false;
  destination.search = "";
  destination.hash = "";
  entry.search = "";
  entry.hash = "";
  return destination.href === entry.href;
}
