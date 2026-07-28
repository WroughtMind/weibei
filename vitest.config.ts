import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "node",
    include: [
      "TypeScriptTests/**/*.test.ts",
      "Prototypes/RichAnswerWebRuntime/tests/**/*.test.ts",
    ],
  },
});
