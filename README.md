<!-- WEIBEI_VISUAL:hero:START -->
![WeiBei / 魏碑](./Docs/brand/readme-hero-1983x793.png)
<!-- WEIBEI_VISUAL:hero:END -->

# WeiBei / 魏碑

WeiBei is a source-grounded study workspace for macOS. Reading, asking questions, and writing notes happen in one native window, so the learning flow never has to be rebuilt across apps — every answer cites the material it came from, and every note stays connected to its sources.

WeiBei began as a submission to the **Education** track of OpenAI Build Week 2026 and has been developed continuously since. The submission record — scope, commit range, and the original judge walkthrough — is preserved in [Docs/build-week.md](Docs/build-week.md).

WeiBei's source code is open source under the MIT License. Its custom English
fonts are open under the SIL Open Font License 1.1. Brand assets, project media,
and third-party reference material have separate terms; see
[Licensing](#licensing).

## Why WeiBei

During final-exam revision, I was reading PDFs and HTML pages in a browser, asking questions in a separate AI chat, and writing Markdown notes in another app. Each tool worked on its own, but the learning flow broke whenever I switched windows and reconstructed the context.

I built WeiBei so the material, the question, its evidence, and the resulting note can stay connected in one workspace.

<!-- WEIBEI_VISUAL:workspace:START -->
<p align="center">
  <img src="./Docs/release-evidence/app-offline-learning-flow.png" alt="WeiBei reading, Agent conversation, and note workspace" width="1200">
</p>
<!-- WEIBEI_VISUAL:workspace:END -->

## What WeiBei does

- Imports individual files or course folders containing PDF, HTML, Markdown, and plain text, and indexes them locally.
- Keeps the reader, the Agent conversation, and the WYSIWYG Milkdown note editor in one native macOS window, with panes that stay legible during cold starts and long streaming answers.
- Searches the current course locally (SQLite FTS5) and returns citations that jump to the exact file, PDF page, HTML section, or note.
- Opens a persistent question thread from a selected passage. The passage keeps a visible cinnabar underline that can reopen the related conversation later.
- Renders rich answers with plain Markdown as the default: KaTeX math and Mermaid diagrams inline, and interactive `visualize` fragments only inside a host-validated sandbox that cannot reach the network or local files. Every rich form has a readable text fallback.
- Writes notes through a live editor with slash commands, image insertion, and code blocks; formal note writes arrive as a reviewable proposal instead of silent edits.
- Links notes and source materials through real many-to-many course relationships, managed in a relationship workbench.
- Saves meaningful learning-memory updates automatically with a light end-of-answer notice, while formal note and relationship writes still require a confirmation card.
- Stays comfortable for long sessions: eight themes (paper, xuan, inkstone, stele, and four Liquid Glass variants), app-wide text scaling with keyboard shortcuts, and a daily calligraphy line (灵感句) drawn from the stele tradition.

<!-- WEIBEI_VISUAL:course-relations:START -->
<p align="center">
  <img src="./Docs/release-evidence/app-course-workspace-overview-flow.png" alt="WeiBei course material and note relationship view" width="1200">
</p>
<!-- WEIBEI_VISUAL:course-relations:END -->

## Download

[WeiBei 1.0.0 for macOS (Apple silicon)](https://github.com/weibei-app/weibei/releases/download/v1.0.0/WeiBei-1.0.0-macOS-arm64.dmg) — see [Releases](https://github.com/weibei-app/weibei/releases) for all assets and SHA-256 checksums.

- Requires macOS 14 or later. The packaged build targets Apple silicon; on other Macs, build from source below.
- The community build is ad-hoc signed and not Apple-notarized, so Gatekeeper blocks the first launch. Allow it for this app only: right-click `魏碑.app` in Applications and choose **Open**, then confirm **Open** in the dialog (or use System Settings → Privacy & Security → **Open Anyway**). Do not disable Gatekeeper globally.
- A Homebrew cask is planned; until the tap is published, use the DMG or build from source.

You choose the model provider in Agent settings — bring an OpenAI-compatible provider, or sign in with OpenAI Codex OAuth where available. No provider is hard-coded.

## Build from source

Requirements:

- macOS 14 or later
- Xcode Command Line Tools with Swift 5.9 support
- Internet access on the first build to download and verify the pinned Pi runtime
- A configured supported model provider for live Agent responses
- Node.js only when rebuilding the Milkdown web editor source

```bash
git clone https://github.com/weibei-app/weibei.git
cd weibei
./script/build_and_run.sh
```

The script builds and opens `dist/魏碑.app`.

## How it is built

WeiBei is a native Swift 5.9 application for macOS 14 and later.

- SwiftUI provides the application interface, with AppKit hosting the long-lived reader, Agent, and note panes.
- PDFKit reads PDFs, WebKit renders HTML and the Milkdown editor, and Vision handles OCR for scanned pages.
- SQLite FTS5 stores the local course index and search results.
- A pinned Pi 0.82.1 runtime provides the Agent loop.
- WeiBei owns the material context, citations, learning memory, note write-back, and interface rendering.

The Agent does not receive unrestricted file, terminal, or network access. Each request gets a bounded and revisioned snapshot of the current material, selection, note, course search results, and learning state. The Swift host validates citations, source jumps, learning updates, note proposals, and rich-answer payloads before displaying or applying them. Interactive `visualize` fragments run in a sandboxed web runtime with no network or local file access, and anything with real side effects requires explicit user confirmation.

For long or scanned PDFs, WeiBei extracts text in a resource-bounded helper process, indexes available text locally, and uses Vision OCR only when a page has no native text. Partial and incomplete indexing states remain visible instead of being presented as complete reads.

## Development and tooling

The root `Makefile` is a thin entry point that forwards to the underlying build scripts (run `make help` for the same list):

| Target | What it runs |
|---|---|
| `make build` | `swift build` |
| `make run` | `./script/build_and_run.sh` |
| `make check` | `./script/build_and_run.sh check` |
| `make package` | `./script/build_and_run.sh package` |
| `make editor-build` | `npm run build:editor` |
| `make rich-answer-build` | `npm -w Prototypes/RichAnswerWebRuntime run build:embed` |
| `make genui-math-check` | `npx tsx script/check-genui-math.ts` |
| `make perf-p95` | `./script/perf_p95.sh $(LOG) $(METRIC)` (usage: `make perf-p95 LOG=<perf-log> METRIC=<metric-name>`) |
| `make pi-prepare` | `./script/prepare_pi_runtime.sh` |
| `make release-community` | `./script/build_release_dmg.sh --community` |
| `make release-notarized` | `./script/build_release_dmg.sh --notarized` |
| `make clean` | `swift package clean && rm -rf dist` (keeps `node_modules`, `.build/pi-runtime` — the clean target moves `pi-runtime` aside and back around `swift package clean`, which would otherwise delete it — and user data) |

Node tooling: the repository has a **single root lockfile** (`package-lock.json`) covering the `Prototypes/RichAnswerWebRuntime` workspace, and exactly one `npm ci` installs everything. Tool scripts under `script/`, `DesignSystem/scripts/` and the prototype `scripts/` are TypeScript run with `tsx` (e.g. `npx tsx script/check-genui-math.ts`); `npm run typecheck:tools` type-checks them.

## Documentation

- [Docs/build-week.md](Docs/build-week.md) — OpenAI Build Week 2026 submission record and judge walkthrough
- [Docs/note-slash-commands.md](Docs/note-slash-commands.md) — note editor slash commands, image insertion, and code block behavior
- [Docs/course-library-architecture.md](Docs/course-library-architecture.md) — course library and storage architecture
- [Docs/pi-unified-runtime.md](Docs/pi-unified-runtime.md) — the pinned Pi agent runtime
- [Docs/生成式界面基础与Visualize借鉴.md](Docs/生成式界面基础与Visualize借鉴.md) — generative UI foundations and the `visualize` decision
- [Docs/releases/v1.0.0.md](Docs/releases/v1.0.0.md) — v1.0.0 release notes and evidence

## Checks

```bash
./script/build_and_run.sh check
```

Individual checks are also available:

```bash
swift build
swift run WeiBeiSelfCheck
swift run WeiBeiWebEditorCheck
PI_RUNTIME="$(./script/prepare_pi_runtime.sh)"
WEIBEI_PI_EXECUTABLE="$PI_RUNTIME/bin/pi" swift run WeiBeiPiCheck
```

Live-provider checks require valid local credentials and are not silently replaced with mock answers.

## Current limits

- WeiBei currently supports macOS 14 and later, on Apple silicon for packaged builds. Windows and web versions are future work.
- Course files and indexes are local-first, but live model responses require a network connection.
- Learning memory is written automatically into the Chat's global or course scope and shown with a light end-of-answer notice. Formal notes and relationships still use a confirmation card.
- Large or difficult source files may be reported as partially indexed or incomplete.
- The community build is ad-hoc signed and is not Apple-notarized.

## Licensing

WeiBei-authored source code and developer documentation are licensed under the
[MIT License](LICENSE).

`WeiBeiStele` and `WeiBeiSteleMono` are licensed under the
[SIL Open Font License 1.1](Sources/WeiBei/Resources/Fonts/OFL.txt). Modified
fonts must use different names unless the project gives written permission to
retain the reserved font names.

The WeiBei / 魏碑 names, logos, visual identity, project screenshots, and
release media are not licensed under MIT or OFL. Third-party software and
reference assets retain their original terms. Read
[`LICENSING.md`](LICENSING.md) before redistributing a fork or packaged app.

Contributions are welcome under [`CONTRIBUTING.md`](CONTRIBUTING.md). Security
issues should follow [`SECURITY.md`](SECURITY.md).

## Technology

Swift, SwiftUI, AppKit, PDFKit, WebKit, Vision OCR, SQLite FTS5, Milkdown, KaTeX, Mermaid, Pi, OpenAI Codex OAuth
