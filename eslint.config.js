import tseslint from "typescript-eslint";

export default tseslint.config(
  {
    ignores: [
      ".build/**",
      "dist/**",
      "node_modules/**",
      "Prototypes/RichAnswerWebRuntime/dist/**",
      "Sources/WeiBei/Resources/**",
      "website/main.js",
    ],
  },
  ...tseslint.configs.recommended,
  {
    files: ["**/*.ts", "**/*.tsx"],
    rules: {
      "@typescript-eslint/ban-ts-comment": "error",
      "@typescript-eslint/no-explicit-any": "error",
      "@typescript-eslint/no-unused-expressions": "off",
      "@typescript-eslint/no-unused-vars": "off",
      "@typescript-eslint/no-this-alias": "off",
      "no-fallthrough": "error",
      "prefer-const": "off",
    },
  },
);
