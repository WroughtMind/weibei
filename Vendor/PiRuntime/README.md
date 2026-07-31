# WeiBei embedded Pi runtime (Node path)

WeiBei owns the runtime boundary. The app package embeds:

1. A pinned **official Node.js** binary (`node/bin/node`)
2. A production install of **`@earendil-works/pi-coding-agent`** (`agent/`)
3. A thin launcher **`bin/pi`** that runs `node …/dist/cli.js`

The app never searches the user's PATH, NVM, Bun, or a global Pi install.

`manifest.json` is the source of truth for:

- Pi npm package version and source commit
- Node version and official tarball digests
- `runtimeKind: "node"` (Bun single-file artifacts are not used)

`script/prepare_pi_runtime.sh` downloads Node, verifies SHA-256, installs the
npm package with `--omit=dev`, writes the launcher, ad-hoc signs the Node
binary, and records integrity files:

- `binary.sha256` — digest of `node/bin/node`
- `artifact.sha256` — Node tarball digest + generated `package-lock.json` digest

## Why Node instead of Bun compile

Upstream standalone `pi` macOS builds are produced with `bun build --compile`,
which statically links Bun components (including LGPL-licensed JavaScriptCore).
WeiBei ships the official **npm/JS** form under Node so installers do not
redistribute that Bun-compiled binary.

## WeiBei-specific behavior

Still outside the upstream CLI surface:

- Swift owns material, selection, notes, cancellation, fallback, and write-back
- `AgentResources/extension.ts` owns allowlisted course / memory / note / rich-answer tools
- Pi runs with `--mode rpc` and without unrestricted built-in tools

## Maintainers

To bump Pi or Node:

1. Update `Vendor/PiRuntime/manifest.json` (versions + Node digests from nodejs.org `SHASUMS256.txt`)
2. Refresh `THIRD_PARTY_NOTICES.md` if the redistribution story changes
3. Delete `.build/pi-runtime` and run `./script/prepare_pi_runtime.sh`
4. Run package + `WeiBeiPiCheck` / self-check
