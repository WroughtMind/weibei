# WeiBei embedded Pi runtime (Bun standalone)

WeiBei owns the runtime boundary. The app package contains a **pinned upstream
standalone `pi` binary** (Bun `build --compile`) and starts only that copy. It
never searches the user’s PATH, Node, NVM, Bun, or a global Pi install.

## Pins

`manifest.json` locks:

- Pi version and source commit  
- macOS archive names and SHA-256 digests  

`script/prepare_pi_runtime.sh` downloads the matching archive, verifies the
digest, copies MIT + third-party notices + **`BUN_LICENSE.md`**, ad-hoc signs
`bin/pi`, and writes `binary.sha256`.

## Notices

- `LICENSE` — Pi MIT  
- `BUN_LICENSE.md` — Bun 1.3.14 license (LGPL static-link disclosures + relink notes)  
- `THIRD_PARTY_NOTICES.md` — product-facing redistribution narrative  

Release DMGs built with `script/build_release_dmg.sh` require  
`WEIBEI_PI_REDISTRIBUTION_REVIEWED=1` after a human has reviewed these files.

## WeiBei-specific behavior

- Swift owns material, selection, notes, cancellation, fallback, write-back  
- `AgentResources/extension.ts` owns allowlisted tools  
- Pi runs in `--mode rpc` without unrestricted built-in tools  

See also: `Docs/audit/2026-07-31-Pi-Bun再分发结论修订.md`.
