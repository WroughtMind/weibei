import { readFile, readdir } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { build } from "../../../node_modules/esbuild/lib/main.js";
import ts from "typescript";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const extensionPath = resolve(
  repositoryRoot,
  "Sources",
  "WeiBeiCore",
  "AgentResources",
  "extension.ts",
);
const source = await readFile(extensionPath, "utf8");
const domainDirectory = resolve(
  repositoryRoot,
  "Sources",
  "WeiBeiCore",
  "AgentResources",
  "domains",
);
const catalogSource = await readFile(resolve(
  domainDirectory,
  "rich-answer-schema.ts",
), "utf8");
const envelopeStart = catalogSource.indexOf("const richAnswerEnvelopeSchema");
const envelopeSection = catalogSource.slice(envelopeStart, envelopeStart + 500);
const entryLineCount = source.split(/\r?\n/u).length;

if (
  envelopeStart < 0 ||
  !envelopeSection.includes("schemaVersion: Type.Literal(2)") ||
  envelopeSection.includes("schemaVersion: Type.Literal(1)")
) {
  throw new Error("Pi extension Rich Answer Envelope must accept schemaVersion 2 only");
}
if (entryLineCount > 2_500) {
  throw new Error(`Pi extension entry must stay below 2,500 lines; found ${entryLineCount}`);
}

const domainFiles = (await readdir(domainDirectory))
  .filter((name) => name.endsWith(".ts"))
  .map((name) => resolve(domainDirectory, name));
for (const domainFile of domainFiles) {
  const domainSource = await readFile(domainFile, "utf8");
  const domainLineCount = domainSource.split(/\r?\n/u).length;
  if (domainLineCount > 1_200) {
    throw new Error(`Pi extension domain must stay below 1,200 lines: ${domainFile} has ${domainLineCount}`);
  }
}
const [agentContractsSource, pythonArtifactSource] = await Promise.all([
  readFile(resolve(domainDirectory, "agent-contracts.ts"), "utf8"),
  readFile(resolve(domainDirectory, "python-artifact.ts"), "utf8"),
]);
if (
  !agentContractsSource.includes('new URL(`../${skill.relativePath}`, import.meta.url)') ||
  !pythonArtifactSource.includes('new URL("../python/rich_answer_worker.py", import.meta.url)')
) {
  throw new Error("Pi extension moved-resource URLs must resolve from the domains directory");
}
const program = ts.createProgram({
  rootNames: [extensionPath, ...domainFiles],
  options: {
    target: ts.ScriptTarget.ES2022,
    module: ts.ModuleKind.ESNext,
    moduleResolution: ts.ModuleResolutionKind.Bundler,
    noEmit: true,
    strict: true,
    skipLibCheck: true,
    typeRoots: [
      resolve(repositoryRoot, "Prototypes", "RichAnswerWebRuntime", "node_modules", "@types"),
      resolve(repositoryRoot, "node_modules", "@types"),
    ],
  },
});
const structuralDiagnosticCodes = new Set([2304, 2305, 2307, 2448, 2459, 2724]);
const diagnostics = ts.getPreEmitDiagnostics(program).filter((diagnostic) => {
  if (!structuralDiagnosticCodes.has(diagnostic.code)) return false;
  if (diagnostic.code !== 2307) return true;
  const message = ts.flattenDiagnosticMessageText(diagnostic.messageText, "\n");
  return !message.includes("@earendil-works/pi-");
});
if (diagnostics.length > 0) {
  const host = {
    getCanonicalFileName: (fileName) => fileName,
    getCurrentDirectory: () => repositoryRoot,
    getNewLine: () => "\n",
  };
  throw new Error(`Pi extension typecheck failed:\n${ts.formatDiagnosticsWithColorAndContext(diagnostics, host)}`);
}

await build({
  entryPoints: [extensionPath],
  bundle: true,
  platform: "node",
  format: "esm",
  write: false,
  external: [
    "@earendil-works/pi-coding-agent",
    "@earendil-works/pi-ai",
  ],
});

process.stdout.write("Pi extension domain modules bundle and Rich Answer Envelope is v2-only\n");
