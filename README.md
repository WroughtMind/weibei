<!-- WEIBEI_VISUAL:hero:START -->
![WeiBei / 魏碑](./Docs/brand/readme-hero-1983x793.png)
<!-- WEIBEI_VISUAL:hero:END -->

# WeiBei / 魏碑

**One native macOS window for the whole study flow: the material you are reading, the questions you ask about it, and the notes you keep from it — all connected back to their sources.**

[![Release](https://img.shields.io/github/v/release/weibei-app/weibei)](https://github.com/weibei-app/weibei/releases)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
![Swift](https://img.shields.io/badge/Swift-5.9-F05138)

WeiBei was born in the **Education** track of OpenAI Build Week 2026 and has been developed as an ongoing product since; the submission record lives in [Docs/build-week.md](Docs/build-week.md). Source code is MIT-licensed, its custom fonts are OFL-licensed, and brand assets have separate terms — see [Licensing](#licensing).

## The problem

A revision evening usually looks like this: a PDF and an HTML lecture open in a browser, an AI chat in another window, a notes app in a third. Every jump between them breaks the context you had just built. Answers drift away from the pages they came from; notes forget which question produced them; "where did I read that?" becomes the evening's refrain.

WeiBei keeps the material, the question, its evidence, and the resulting note as one connected object in a single window. I built it during my own final-exam revision, when the window-juggling finally became unbearable.

## One window, one flow: read → ask → keep

<!-- WEIBEI_VISUAL:workspace:START -->
<p align="center">
  <img src="./Docs/release-evidence/app-offline-learning-flow.png" alt="WeiBei reading, Agent conversation, and note workspace" width="1200">
</p>
<!-- WEIBEI_VISUAL:workspace:END -->

**Read.** Import a folder as a course — PDF, HTML, Markdown, and plain text all work. Everything is indexed and searchable locally, and opens in a native reader that jumps straight to a PDF page or an HTML section.

**Ask.** Select a passage and ask from the selection. Answers arrive with citation labels; click one to jump back to the exact file, page, or section it came from. The passage keeps a cinnabar underline that reopens its question thread whenever you return to it — the conversation stays attached to the text it was about. Math renders in KaTeX, diagrams in Mermaid, and interactive `visualize` fragments run in a sandbox — with readable plain text always underneath.

**Keep.** Notes live in a WYSIWYG editor with slash commands, images, and code blocks. When the Agent has something worth saving, it proposes a note update as a card you review and accept — nothing silently rewrites your notes. Meaningful learning moments are remembered automatically, with a light notice so you always know what was stored. And every note links to its sources as real many-to-many relationships, managed on the relationship bench:

<!-- WEIBEI_VISUAL:course-relations:START -->
<p align="center">
  <img src="./Docs/release-evidence/app-course-workspace-overview-flow.png" alt="WeiBei course material and note relationship view" width="1200">
</p>
<!-- WEIBEI_VISUAL:course-relations:END -->

## Why not just a browser, an AI chat, and a notes app?

| | Chat window + notes app | WeiBei |
|---|---|---|
| Your material | re-pasted or attached in pieces | imported, indexed, in the same window |
| Answers | may sound right, sources unclear | answers cite the course files behind them; one click back to the page |
| A week later | scroll a long chat history to reconstruct why | the underlined passage reopens its exact thread |
| Notes | you retype the useful parts by hand | proposals you review and accept — never silent edits |
| Your data | split across services | a local-first library on your Mac |

## Private by structure

- Your library and full-text index stay on your Mac.
- The Agent runs on a closed set of host-mediated tools — course search and reading, note and relationship proposals, learning memory. It gets no shell and no open file system; each request sees a bounded snapshot of the current material, selection, note, and search results. The only web pages it reads are HTTPS URLs you yourself provided in that same turn, and the Swift host validates citations, source jumps, memory writes, note proposals, and rich-answer payloads before anything is displayed or applied.
- Web pages, course materials, notes, and tool results are treated strictly as data, never as instructions — a page telling the Agent to do something can't change its behavior. Search queries carry only the public topic of your question, never your course text, notes, or local paths.
- Interactive `visualize` fragments run sandboxed, with no network and no local file access; anything with real side effects asks for your confirmation first.
- You choose the model provider: dozens of built-in profiles (OpenAI, Anthropic, Google, DeepSeek, Kimi, OpenRouter, and more), OAuth subscriptions such as OpenAI Codex, a local llama.cpp, or any OpenAI-compatible endpoint. No provider is hard-coded.

## Get WeiBei

**[Download WeiBei 1.0.0](https://github.com/weibei-app/weibei/releases/download/v1.0.0/WeiBei-1.0.0-macOS-arm64.dmg)** — macOS 14 or later, Apple silicon. SHA-256 checksums are published alongside in [Releases](https://github.com/weibei-app/weibei/releases).

The community build is ad-hoc signed and not Apple-notarized, so Gatekeeper blocks the very first launch. Allow it for this app only: right-click `魏碑.app` in Applications, choose **Open**, then confirm **Open** (or System Settings → Privacy & Security → **Open Anyway**). Don't disable Gatekeeper globally. WeiBei checks for new versions from Settings, so you don't need to watch the Releases page yourself.

**Five minutes to your first cited answer:**

1. Launch WeiBei and import a folder of your own material as a course — PDF, HTML, Markdown, and plain text all work. (No sample data ships in the app; nothing is bundled that you didn't bring.)
2. In Agent settings, connect a provider — pick a built-in profile, sign in with an OAuth subscription, or point at an OpenAI-compatible endpoint.
3. Select a passage in the reader and ask a question from the selection.
4. Click a citation label to jump back to the source.
5. Ask the Agent to save something to your notes, then review the proposal card before it is applied.

A Homebrew cask is planned; until the tap is published, use the DMG or build from source.

## Made for long nights

WeiBei is named after the stele inscription style, and it leans into that: paper, xuan, inkstone, and stele themes alongside four frosted-glass variants; app-wide text scaling with keyboard shortcuts (⌘+ / ⌘−) when 3 a.m. eyes need bigger type; quiet skeleton states instead of blank flashes while long documents and cold chats load; and a daily calligraphy line (灵感句) from the stele tradition, shown as a quiet background watermark — every one of the 50 lines carries its source and rights basis in a ledger you can open in Settings.

## For developers

Everything from here down is for people building WeiBei itself.

### Build from source

Requirements: macOS 14+, Xcode Command Line Tools with Swift 5.9, internet on first build to download and verify the pinned Pi runtime, a configured model provider for live Agent responses, and Node.js only when rebuilding the Milkdown web editor.

```bash
git clone https://github.com/weibei-app/weibei.git
cd weibei
./script/build_and_run.sh
```

The script builds and opens `dist/魏碑.app`.

### How it is built

WeiBei is a native Swift 5.9 application: SwiftUI for the interface, AppKit hosting the long-lived reader, Agent, and note panes. PDFKit reads PDFs, WebKit renders HTML and the Milkdown editor, Vision handles OCR for scanned pages, and SQLite FTS5 stores the local course index. A pinned Pi 0.82.1 runtime provides the Agent loop; WeiBei itself owns the material context, citations, learning memory, note write-back, and interface rendering.

Each Agent request receives a bounded, revisioned snapshot of the working context — no open file system, no shell, and web reading limited to HTTPS URLs the user explicitly provided. The host validates citations, source jumps, learning updates, note proposals, and rich-answer payloads before display or application; `visualize` fragments execute in a sandboxed web runtime with no network or local file access. For long or scanned PDFs, text extraction runs in a resource-bounded helper process, with Vision OCR only where a page has no native text, and partial or incomplete indexing is reported honestly rather than passed off as complete.

### Tooling

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

### Checks

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

### Documentation

- [Docs/build-week.md](Docs/build-week.md) — OpenAI Build Week 2026 submission record and judge walkthrough
- [Docs/note-slash-commands.md](Docs/note-slash-commands.md) — note editor slash commands, image insertion, and code block behavior
- [Docs/course-library-architecture.md](Docs/course-library-architecture.md) — course library and storage architecture
- [Docs/pi-unified-runtime.md](Docs/pi-unified-runtime.md) — the pinned Pi agent runtime
- [Docs/生成式界面基础与Visualize借鉴.md](Docs/生成式界面基础与Visualize借鉴.md) — generative UI foundations and the `visualize` decision
- [Docs/releases/v1.0.0.md](Docs/releases/v1.0.0.md) — v1.0.0 release notes and evidence

## Current limits

- macOS 14 or later; packaged builds target Apple silicon. Windows and web versions are future work.
- Course files and indexes are local-first, but live model responses require a network connection.
- Learning memory is written automatically into the Chat's global or course scope, shown with a light end-of-answer notice. Formal notes and relationships still use a confirmation card.
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
