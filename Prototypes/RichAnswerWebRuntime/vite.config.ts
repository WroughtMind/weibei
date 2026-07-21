import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  base: "./",
  plugins: [
    react(),
    {
      name: "weibei-local-webview-script",
      apply: "build",
      enforce: "post",
      transformIndexHtml(html) {
        return html
          .replace('<script type="module" crossorigin', '<script defer')
          .replace('<link rel="stylesheet" crossorigin', '<link rel="stylesheet"');
      },
    },
  ],
  build: {
    assetsDir: "",
    rollupOptions: {
      output: {
        entryFileNames: "rich-answer-runtime.js",
        assetFileNames: "rich-answer-runtime[extname]",
      },
    },
  },
});
