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
    {
      name: "weibei-generated-whitespace",
      apply: "build",
      enforce: "post",
      /**
       * 移除依赖内嵌模板字符串产生的行尾空白，保持跟踪生成物可审查。
       */
      generateBundle(_options, bundle) {
        for (const output of Object.values(bundle)) {
          if (output.type === "chunk") {
            output.code = output.code.replace(/[ \t]+$/gmu, "");
          } else if (typeof output.source === "string") {
            output.source = output.source.replace(/[ \t]+$/gmu, "");
          }
        }
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
