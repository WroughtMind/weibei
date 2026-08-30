import "@fontsource-variable/noto-sans-sc";
import "@fontsource-variable/noto-serif-sc";
import React from "react";
import { createRoot } from "react-dom/client";
import { App } from "./App";
import "./styles/tokens.css";
import "./styles/app.css";

const container = document.getElementById("root");
if (!container) throw new Error("Missing #root renderer mount");

createRoot(container).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
