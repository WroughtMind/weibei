# Third-party notices (embedded Agent runtime)

WeiBei embeds a **standalone Pi coding agent** binary produced by the upstream
project with **Bun `build --compile`**. WeiBei application source remains MIT
(see the repository root `LICENSE`). This notice describes third-party material
**inside the packaged runtime**, not a claim that the entire app bundle is
“MIT-only”.

## Pi coding agent

- Project: Pi coding agent  
- Version: **0.82.1** (see `manifest.json` → `piVersion`)  
- Source repository: https://github.com/earendil-works/pi  
- Pinned commit: `b4f293684bba718d59cc1157679bcf6157b3a7f5`  
- License: **MIT** (full text: `LICENSE` in this directory)  
- Copyright: 2025 Mario Zechner  

Upstream also publishes the JS package `@earendil-works/pi-coding-agent` and
install lockfiles for the same release. Anyone may obtain Pi source, inspect it,
and rebuild.

## How this binary is built

The macOS `bin/pi` shipped here is the upstream **single-file executable** for
the pinned release (archive names and SHA-256 digests are locked in
`manifest.json`). Upstream builds it with Bun’s documented production path
`bun build --compile` (see Bun’s “Single-file executable” documentation).

WeiBei does **not** use Bun’s `--bytecode` option for this embed.

## Bun runtime inside the compiled binary

The standalone executable is produced with **Bun 1.3.14** tooling. Bun itself is
MIT-licensed. Bun **statically links** additional libraries, including:

- JavaScriptCore / WebKit / WebCore — **LGPL-2**  
- tinycc — **LGPL v2.1**  
- and other libraries listed in Bun’s license file  

The complete Bun license text for the pinned tag is shipped next to this file as
**`BUN_LICENSE.md`** (source:
https://raw.githubusercontent.com/oven-sh/bun/bun-v1.3.14/LICENSE.md ).

Bun’s license states that for LGPL static linking, recipients must be able to
modify the LGPL library and relink. Bun documents a rebuild path for Bun with a
modified JavaScriptCore (patched WebKit at https://github.com/oven-sh/webkit ,
then `make jsc` and `zig build` as described in `BUN_LICENSE.md`).

### Relink / rebuild narrative for this product

Because **Pi application source is MIT and public**, and **Bun source plus
relink instructions are public**, a recipient who wants to modify an LGPL
component and produce an equivalent agent binary can, in principle:

1. Obtain Bun source and follow `BUN_LICENSE.md` to rebuild Bun with a modified
   JavaScriptCore (or other LGPL component as applicable);  
2. Obtain Pi source at the pinned commit (or a chosen revision);  
3. Rebuild a standalone `pi` with `bun build --compile` using that toolchain;  
4. Substitute the resulting binary for the copy embedded in WeiBei (subject to
   WeiBei’s own MIT terms for host code).

WeiBei therefore ships:

- the pinned `pi` binary and its integrity digests;  
- Pi’s MIT license;  
- Bun’s full license text and static-link disclosures;  
- LGPL-2.0 and LGPL-2.1 full texts plus `RELINK.md`;
- a separately downloadable, fingerprint-locked relink bundle containing the
  exact Pi, Bun, WebKit, and TinyCC source materials used by this runtime.

The relink bundle is generated once per runtime/toolchain baseline and reused
across ordinary WeiBei releases. Every release verifies its fingerprint and
SHA-256 before packaging.

## What WeiBei source covers

- WeiBei-authored Swift/app code: MIT (repository root).  
- WeiBei-authored Agent resources (prompts, extension, skills): as in-tree.  
- Brand, fonts (OFL), and other carve-outs: see `LICENSING.md`.

## Release process note

Packaging a community or notarized DMG via `script/build_release_dmg.sh`
requires both `WEIBEI_PI_REDISTRIBUTION_REVIEWED=1` and a verified bundle path
in `WEIBEI_PI_RELINK_BUNDLE`. These are engineering release gates, not a legal
opinion or third-party certification.
