# WeiBei embedded Pi runtime

WeiBei owns the runtime boundary. The app package contains a pinned standalone Pi
executable and starts only that copy. It never searches the user's PATH, Node,
NVM, Bun, or global Pi installation.

`manifest.json` is the source of truth for the Pi version, source commit, release
artifacts, and archive digests. `swift run WeiBeiDevTool prepare pi-runtime`
downloads the matching macOS artifact, verifies SHA-256 before extraction, and
keeps only the files needed by WeiBei RPC mode.

WeiBei-specific behavior is deliberately outside the upstream CLI surface:

- Swift owns current material, selection, notes, cancellation, fallback, and write-back.
- `AgentResources/extension.ts` owns the two allowlisted tools and guard hooks.
- `AgentResources/skills/` owns the three study workflows.
- Pi runs without built-in tools, sessions, global extensions, or global skills.

To maintain a deeper Pi fork, publish a standalone artifact from the fork, update
the repository, commit, version, filenames, and digests in `manifest.json`, then
run the same self-contained package and live-evaluation checks. The Swift/RPC
contract does not need to change unless the fork intentionally changes protocol.
