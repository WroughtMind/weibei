import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { fileURLToPath, URL } from "node:url";
import react from "@vitejs/plugin-react";
import { defineConfig, type Plugin } from "vite";

const canonicalEditorHTML = fileURLToPath(
  new URL("../Sources/WeiBei/Resources/Editor/index.html", import.meta.url),
);

const windowsEditorHostHTML = (canonicalHTML: string) => {
  const startMarker = "  <script>\n    var weiBeiEntry = document.createElement('script');";
  const endMarker = "    document.body.appendChild(weiBeiEntry);\n  </script>";
  const start = canonicalHTML.indexOf(startMarker);
  const endStart = canonicalHTML.indexOf(endMarker, start);
  if (start < 0 || endStart < 0) {
    throw new Error("Canonical Editor/index.html entry loader marker changed");
  }
  const end = endStart + endMarker.length;
  const hostHTML = `${canonicalHTML.slice(0, start)}  <script type="module" src="/src/renderer/editor/frame-bridge.ts"></script>${canonicalHTML.slice(end)}`;
  const scriptHashes = [...hostHTML.matchAll(/<script>([\s\S]*?)<\/script>/g)]
    .map((match) => `'sha256-${createHash("sha256").update(match[1]).digest("base64")}'`);
  if (scriptHashes.length === 0) {
    throw new Error("Windows editor host has no canonical inline scripts to authorize");
  }
  const csp = [
    "default-src 'none'",
    `script-src 'self' ${scriptHashes.join(" ")}`,
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' data: blob: weibeiimage:",
    "font-src 'self' data:",
    "connect-src 'none'",
    "worker-src 'self' blob:",
    "object-src 'none'",
    "media-src 'none'",
    "form-action 'none'",
    "base-uri 'self'",
  ].join("; ");
  return hostHTML
    .replace("<head>", `<head>\n  <meta http-equiv="Content-Security-Policy" content="${csp}">`);
};

const windowsEditorDevelopmentHost = (): Plugin => ({
  name: "weibei-windows-editor-development-host",
  configureServer(server) {
    server.middlewares.use("/Editor/windows-host.html", (_request, response, next) => {
      void readFile(canonicalEditorHTML, "utf8")
        .then((html) => {
          response.statusCode = 200;
          response.setHeader("Content-Type", "text/html; charset=utf-8");
          response.setHeader("Cache-Control", "no-store");
          response.end(windowsEditorHostHTML(html));
        })
        .catch(next);
    });
  },
});

export default defineConfig({
  root: fileURLToPath(new URL(".", import.meta.url)),
  base: "./",
  publicDir: fileURLToPath(
    new URL("../Sources/WeiBei/Resources", import.meta.url),
  ),
  plugins: [windowsEditorDevelopmentHost(), react()],
  resolve: {
    alias: {
      "@": fileURLToPath(new URL("./src", import.meta.url)),
    },
  },
  build: {
    outDir: "dist/renderer",
    emptyOutDir: true,
    sourcemap: false,
  },
});
