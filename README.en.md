<p align="right"><a href="README.md">中文</a> · English</p>

<!-- WEIBEI_VISUAL:hero:START -->
<p align="center">
  <img src="./Docs/brand/readme-hero-1983x793.png" alt="WeiBei / 魏碑: reading, notes, and questions on the same page" width="100%">
</p>
<!-- WEIBEI_VISUAL:hero:END -->

<h1 align="center">Read, ask, and keep notes in one window</h1>

<p align="center">WeiBei is a native macOS workspace for reading and notes. Keep your material locally, and connect AI when you need it.</p>

<p align="center">
  <a href="https://wroughtmind.github.io/weibei/">Website</a> ·
  <a href="#get-started">Get started</a> ·
  <a href="#contribute">Contribute</a> ·
  <a href="https://github.com/WroughtMind/weibei/issues">Report an issue</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-35332F?style=flat-square" alt="macOS 14 or later">
  <img src="https://img.shields.io/badge/Swift-5.9-A44735?style=flat-square" alt="Swift 5.9">
  <a href="LICENSE"><img src="https://img.shields.io/badge/code-MIT-35332F?style=flat-square" alt="Source code under the MIT License"></a>
  <br>
  <sub>In development, no official installer yet · Apple silicon and Intel · Build from source</sub>
</p>

<!-- WEIBEI_VISUAL:workspace:START -->
<p align="center">
  <img src="./website/assets/第二幕-真实三窗截图-去黑边.webp" alt="WeiBei's three-pane workspace: an article on the left, a conversation in the middle, and notes on the right" width="100%">
  <br>
  <sub>Open the reader, chat, and notes side by side or as separate panes.</sub>
</p>
<!-- WEIBEI_VISUAL:workspace:END -->

## Features

| Task | In WeiBei |
|:---|:---|
| **Read** | Import a folder as a course, read PDF, HTML, Markdown, and plain text, and search your course material. |
| **Ask** | Select text to ask a question. Click citations to view the source, or click an underlined passage to reopen its conversation. |
| **Write** | Edit Markdown with images, formulas, and code blocks. AI changes appear as proposals and are saved after you approve them. |
| **Revisit** | View the material linked to a note and use learning memory to look up previous progress and questions. |

> Reading at length, taking excerpts, and writing notes by hand are meaningful in themselves, even without AI.

<p align="center">
  <img src="./website/assets/第三幕-真实截图-宣纸-论文选区浮窗.webp" alt="A paper and notes open side by side, with a floating panel for asking about or keeping selected text" width="100%">
  <br>
  <sub>Select text to open a floating panel for questions or excerpts.</sub>
</p>

## Themes

Choose Paper, Xuan, Inkstone, or Stele, or one of four frosted-glass themes: Clear Glass, Dark Glass, Mist Glass, and Slate Glass. Open reading, chat, or writing on its own, and adjust text size across the app with <kbd>⌘</kbd> + <kbd>+</kbd> / <kbd>−</kbd>.

<table>
  <tr>
    <td width="50%" align="center">
      <a href="./website/assets/第三幕-真实截图-纸面-沉浸对话.webp"><img src="./website/assets/第三幕-真实截图-纸面-沉浸对话.webp" alt="Paper theme with a warm background in the chat pane" width="100%"></a>
      <br><sub><b>Paper</b> · Chat</sub>
    </td>
    <td width="50%" align="center">
      <a href="./website/assets/第三幕-真实截图-墨石-沉浸对话.webp"><img src="./website/assets/第三幕-真实截图-墨石-沉浸对话.webp" alt="Inkstone theme with a dark background in the chat pane" width="100%"></a>
      <br><sub><b>Inkstone</b> · Chat</sub>
    </td>
  </tr>
  <tr>
    <td width="50%" align="center">
      <a href="./website/assets/第三幕-真实截图-晴璃-沉浸阅读.webp"><img src="./website/assets/第三幕-真实截图-晴璃-沉浸阅读.webp" alt="Clear Glass theme with a light frosted background in the reader" width="100%"></a>
      <br><sub><b>Clear Glass</b> · Reading</sub>
    </td>
    <td width="50%" align="center">
      <a href="./website/assets/第三幕-真实截图-夜璃-沉浸阅读.webp"><img src="./website/assets/第三幕-真实截图-夜璃-沉浸阅读.webp" alt="Dark Glass theme with a dark frosted background in the reader" width="100%"></a>
      <br><sub><b>Dark Glass</b> · Reading</sub>
    </td>
  </tr>
</table>

<p align="center"><sub>Four themes in the app. Click an image to enlarge it. The materials shown are for demonstration and are not bundled with WeiBei.</sub></p>

## Local storage and AI permissions

| Topic | How it works |
|:---|:---|
| Storage | Courses, notes, full-text indexes, and learning memory are stored locally. Reading local files and writing notes require no model. |
| Network | Online models receive the relevant excerpts needed for your request. Remote images and web content in documents also use the network. |
| Approval | Formal notes and source relationships use proposals you review and accept. Learning memory is recorded automatically, with a notice of what was saved. |
| Access | AI reads through WeiBei's scoped tools, with no terminal or unrestricted file-system access. |

Choose your model: built-in profiles include OpenAI, Anthropic, Google, DeepSeek, Kimi, and OpenRouter. Subscription sign-in, local llama.cpp, and custom OpenAI-compatible endpoints are also supported. Read the [privacy notice](PRIVACY.md) for the full data flow.

## Get started

For now, build from source. You need **macOS 14 or later** and **Xcode Command Line Tools with Swift 5.9 or later**. The first build needs a network connection to fetch dependencies.

```bash
git clone https://github.com/WroughtMind/weibei.git
cd weibei
./script/build_and_run.sh
```

The script builds and opens WeiBei. Full checks, packaging, and web-editor rebuilds also require **Node.js 22 or later** and `npm ci` from the repository root.

1. Import a folder of your own material as a course.
2. Open a document, write notes alongside it, and try full-text search.
3. When you want AI, connect a model in Settings. Select text to ask a question, follow a citation back to the source, or review a note proposal.

Large files and scans may be reported as partially indexed. There is no release scheduled; the next official version will be **0.0.1**. See the [release status](Docs/releases/README.md).

## Contribute

WeiBei began in the Education track of OpenAI Build Week 2026 and has been developed since. See the [contribution guide](CONTRIBUTING.md) to get involved and the [security policy](SECURITY.md) to report security issues.

<details>
<summary><strong>Build commands and checks</strong></summary>

The root `Makefile` is a thin entry point that forwards to the underlying build scripts (run `make help` for the same list):

| Target | What it runs |
|---|---|
| `make build` | `swift build` |
| `make run` | `./script/build_and_run.sh` |
| `make check` | `./script/build_and_run.sh check` |
| `make package` | `./script/build_and_run.sh package` |
| `make verify` | `./script/build_and_run.sh verify` (package, launch, and confirm a live process) |
| `make editor-build` | `npm run build:editor` |
| `make genui-math-check` | `npx tsx script/check-genui-math.ts` |
| `make perf-p95` | `./script/perf_p95.sh $(LOG) $(METRIC)` (usage: `make perf-p95 LOG=<perf-log> METRIC=<metric-name>`) |
| `make release` | `./script/build_release_dmg.sh` (build the current architecture's unnotarized release DMG) |
| `make clean` | `swift package clean && rm -rf dist` (keeps `node_modules` and user data) |

Node tooling: run `npm ci` at the repository root to install dependencies from the single `package-lock.json`. TypeScript tools under `script/` and `DesignSystem/scripts/` run with `tsx`; `npm run typecheck:tools` checks their types.

Apple silicon and Intel packages are built natively on the matching Mac. See the [dual-architecture release guide](Docs/releases/dual-architecture.md) for assets and verification requirements.

### Checks

Requires Node.js 22 or later:

```bash
npm ci
./script/build_and_run.sh check
```

Individual checks are also available:

```bash
swift build
swift run WeiBeiSelfCheck
swift run WeiBeiWebEditorCheck
swift run WeiBeiNativeCheck --authentication-status
```

Live-provider checks require valid local credentials and are never silently replaced with mock answers.

</details>

<details>
<summary><strong>Architecture</strong></summary>

SwiftUI handles the interface, with AppKit hosting persistent reader, chat, and note panes. PDFKit reads PDFs, WebKit renders HTML and the Milkdown editor, Vision handles OCR for scanned pages, and SQLite FTS5 provides local full-text indexes. Math uses KaTeX, and diagrams use Mermaid.

A Swift-native Agent runtime handles the tool loop, provider connections, credentials, and session ledger. WeiBei validates citations, memory updates, note proposals, and rich answers before display or writing. Interactive `visualize` fragments run in a sandbox without network or local-file access. Long PDFs and scans use a resource-bounded helper process for text extraction, with OCR only on pages that have no native text.

</details>

<details>
<summary><strong>Further reading</strong></summary>

- [Build Week record](Docs/build-week.md): OpenAI Build Week 2026 submission record and judge walkthrough
- [Note editor guide](Docs/note-slash-commands.md): note editor slash commands, image insertion, and code block behavior
- [Course library and storage](Docs/course-library-architecture.md): course library and storage architecture
- [Native Agent implementation](Docs/plans/2026-08-22-native-agent-runtime-实验计划.md): validation and rollout notes for the Swift-native Agent runtime
- [Generative UI design](Docs/生成式界面基础与Visualize借鉴.md): generative UI foundations and the `visualize` decision

</details>

## Licensing

- WeiBei-authored source code and developer documentation: [MIT License](LICENSE).
- `WeiBeiStele` and `WeiBeiSteleMono` fonts: [SIL Open Font License 1.1](Sources/WeiBei/Resources/Fonts/OFL.txt). Modified fonts must use different names unless the project grants written permission to retain the reserved names.
- The WeiBei / 魏碑 names, logos, visual identity, screenshots, and release media are not licensed under MIT or OFL. Third-party software and reference assets retain their original terms.
- Read [the licensing guide](LICENSING.md) before redistributing a fork or packaged app. Contributions follow [the contribution guide](CONTRIBUTING.md); security issues follow [the security policy](SECURITY.md).
