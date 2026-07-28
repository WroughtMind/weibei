import mermaid from "mermaid";

export type EditorTheme = "paper" | "inkstone" | "xuan" | "stele";

/**
 * Normalizes the host theme to one of the editor's supported palettes.
 *
 * @param theme - Host-provided theme identifier
 * @returns Supported editor theme
 */
export const normalizeTheme = (theme: string | undefined): EditorTheme => {
  if (
    theme === "xuan" ||
    theme === "inkstone" ||
    theme === "stele" ||
    theme === "paper"
  )
    return theme;
  return "paper";
};
let currentTheme = normalizeTheme("paper");

/**
 * Builds Mermaid colors for the active editor theme.
 *
 * @returns Mermaid theme variables
 */
export const mermaidThemeVariables = (): Record<string, string> => {
  switch (currentTheme) {
    case "inkstone":
      return {
        background: "#151515",
        primaryColor: "#1c1c1c",
        primaryTextColor: "#d7cbb0",
        primaryBorderColor: "#3a3328",
        lineColor: "#8b5e3c",
        secondaryColor: "#222222",
        tertiaryColor: "#171717",
        fontFamily: '-apple-system, BlinkMacSystemFont, "Songti SC", serif',
      };
    case "stele":
      return {
        background: "#1e2228",
        primaryColor: "#252a32",
        primaryTextColor: "#d2d6dc",
        primaryBorderColor: "#3a414c",
        lineColor: "#8a7a5c",
        secondaryColor: "#2a3038",
        tertiaryColor: "#1a1e24",
        fontFamily: '-apple-system, BlinkMacSystemFont, "Songti SC", serif',
      };
    case "xuan":
      return {
        background: "#f7f4ef",
        primaryColor: "#fcfbf8",
        primaryTextColor: "#25231f",
        primaryBorderColor: "#d8d2c6",
        lineColor: "#6e634f",
        secondaryColor: "#ebe6dc",
        tertiaryColor: "#f7f4ef",
        fontFamily: '-apple-system, BlinkMacSystemFont, "Songti SC", serif',
      };
    default:
      return {
        background: "#fbf5e8",
        primaryColor: "#f6eddc",
        primaryTextColor: "#2e261f",
        primaryBorderColor: "#cbb79b",
        lineColor: "#7a6250",
        secondaryColor: "#efe4d2",
        tertiaryColor: "#f8f0e1",
        fontFamily: '-apple-system, BlinkMacSystemFont, "Songti SC", serif',
      };
  }
};

const initializeMermaid = () => {
  mermaid.initialize({
    startOnLoad: false,
    securityLevel: "strict",
    theme: "base",
    themeVariables: mermaidThemeVariables(),
  });
};

/**
 * Applies a theme to the editor document and Mermaid renderer.
 *
 * @param theme - Requested editor theme
 */
export const applyTheme = (theme: string | undefined): void => {
  currentTheme = normalizeTheme(theme);
  document.documentElement.dataset.weibeiTheme = currentTheme;
  if (document.body) document.body.dataset.weibeiTheme = currentTheme;
  initializeMermaid();
};

/**
 * Returns the active editor theme.
 *
 * @returns Active theme
 */
export function getCurrentTheme(): EditorTheme {
  return currentTheme;
}
