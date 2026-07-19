import { GenerativeWorkbench } from "./generative/generative-workbench";
import { LegacyGallery } from "./legacy-gallery";

export function App() {
  const legacy = new URLSearchParams(window.location.search).get("legacy") === "1";
  return legacy ? <LegacyGallery /> : <GenerativeWorkbench />;
}
