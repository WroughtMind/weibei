# Third-party notices (embedded Agent runtime)

WeiBei embeds a **Node.js** runtime and the official **Pi coding agent** npm package
for RPC mode. It does **not** embed the Bun-compiled single-file `pi` binary.

## Pi coding agent

- Package: `@earendil-works/pi-coding-agent@0.82.1`
- Source: https://github.com/earendil-works/pi
- Pinned commit: `b4f293684bba718d59cc1157679bcf6157b3a7f5`
- License: MIT
- Copyright: 2025 Mario Zechner

Pi's runtime dependency licenses are declared in the locked install graph for this
exact version (see the package's published lock / the generated
`agent/package-lock.json` inside the prepared runtime). WeiBei keeps only the
production install needed to run `dist/cli.js` in `--mode rpc`.

## Node.js

- Distribution: official Node.js binary from https://nodejs.org
- Pinned version: see `manifest.json` → `node.version` (currently 22.19.0)
- License: Node.js is released under the MIT License; it bundles additional
  third-party components under their own terms. Full texts ship with the
  official Node tarball (`LICENSE` and related notices) and are retained under
  `PiRuntime/node/` when the runtime is prepared.

## What this package deliberately avoids

The previous Bun `build --compile` single-file `pi` statically linked components
such as JavaScriptCore / WebKit (LGPL-2) via Bun. WeiBei no longer redistributes
that Bun-compiled artifact. Redistribution review for installers should focus on
**Node + npm production dependencies**, not Bun static-link object materials.

## WeiBei-authored code

WeiBei application source remains under the MIT License at the repository root.
