import React from "react";
import { createRoot } from "react-dom/client";

import { LegacyGallery } from "./legacy-gallery";
import "../app.css";

createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <LegacyGallery />
  </React.StrictMode>,
);
