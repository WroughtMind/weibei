import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import ts from "typescript";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const packageRoot = resolve(scriptDirectory, "..");
const repositoryRoot = resolve(packageRoot, "../..");
const agentResourcesRoot = join(
  repositoryRoot,
  "Sources/WeiBeiCore/AgentResources",
);
const extensionPath = join(agentResourcesRoot, "extension.ts");
const stubsPath = join(scriptDirectory, "agent-contract-stubs.d.ts");

const program = ts.createProgram(
  [extensionPath, stubsPath],
  {
    allowSyntheticDefaultImports: true,
    lib: ["lib.es2022.d.ts", "lib.dom.d.ts"],
    module: ts.ModuleKind.ESNext,
    moduleResolution: ts.ModuleResolutionKind.Bundler,
    noEmit: true,
    noImplicitAny: false,
    skipLibCheck: true,
    strict: false,
    target: ts.ScriptTarget.ES2022,
  },
);
const typeErrors = ts
  .getPreEmitDiagnostics(program)
  .filter((diagnostic) => diagnostic.category === ts.DiagnosticCategory.Error);
assert.equal(
  typeErrors.length,
  0,
  ts.formatDiagnosticsWithColorAndContext(typeErrors, {
    getCanonicalFileName: (name) => name,
    getCurrentDirectory: () => repositoryRoot,
    getNewLine: () => "\n",
  }),
);

const extensionSource = await readFile(extensionPath, "utf8");
const transpiled = ts.transpileModule(extensionSource, {
  compilerOptions: {
    module: ts.ModuleKind.ESNext,
    target: ts.ScriptTarget.ES2022,
  },
  fileName: extensionPath,
  reportDiagnostics: true,
});
const transpileErrors = (transpiled.diagnostics ?? []).filter(
  (diagnostic) => diagnostic.category === ts.DiagnosticCategory.Error,
);
assert.equal(transpileErrors.length, 0, "Agent extension must transpile cleanly");

process.stdout.write("Agent extension contract passed\n");
