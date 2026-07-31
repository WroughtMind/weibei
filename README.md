<!-- WEIBEI_VISUAL:hero:START -->
![WeiBei / 魏碑](./Docs/brand/readme-hero-1983x793.png)
<!-- WEIBEI_VISUAL:hero:END -->

# WeiBei / 魏碑

WeiBei is a source-grounded macOS study workspace for reading course materials, asking questions, and writing notes without breaking context.

It is submitted to the **Education** track of OpenAI Build Week 2026.

WeiBei's source code is open source under the MIT License. Its custom English
fonts are open under the SIL Open Font License 1.1. Brand assets, project media,
and third-party reference material have separate terms; see
[Licensing](#licensing).

## Why I built it

During final-exam revision, I was reading PDFs and HTML pages in a browser, asking questions in a separate AI chat, and writing Markdown notes in another app. Each tool worked on its own, but the learning flow broke whenever I switched windows and reconstructed the context.

I built WeiBei so the material, the question, its evidence, and the resulting note can stay connected in one workspace.

<!-- WEIBEI_VISUAL:workspace:START -->
<p align="center">
  <img src="./Docs/release-evidence/app-offline-learning-flow.png" alt="WeiBei reading, Agent conversation, and note workspace" width="1200">
</p>
<!-- WEIBEI_VISUAL:workspace:END -->

## What it does

- Imports individual files or course folders containing PDF, HTML, Markdown, and plain text.
- Keeps the reader, Agent conversation, and Milkdown note editor in one native macOS window.
- Searches the current course locally and returns citations that can jump to the exact file, PDF page, HTML section, or note.
- Opens a persistent question thread from a selected passage. The passage keeps a visible cinnabar underline that can reopen the related conversation later.
- Links notes and source materials through real many-to-many course relationships.
- Saves meaningful learning-memory updates automatically, while formal note and relationship writes still require a light confirmation card.
- Can render source-bound interactive explanations through a constrained generative UI protocol. Plain text remains the default and the fallback.

## OpenAI Build Week scope

WeiBei existed as an early prototype before the submission period. The last repository checkpoint before the July 13, 2026 9:00 AM Pacific start is [`366892c1`](https://github.com/weibei-app/weibei/commit/366892c1). It already supported the basic native read, ask, and write workflow, course-aware retrieval, local notes, study memory, and a three-pane workspace.

The Build Week work is the range from `366892c1` to the merged `main` submission commit [`c05ca69b`](https://github.com/weibei-app/weibei/commit/c05ca69b). This range contains 59 commits. The main additions were:

- A course hub and a material-to-note relationship workbench.
- A host-validated, evidence-linked rich-answer protocol with readable text fallback.
- Selection-based question threads and persistent marks across PDF, HTML, Markdown, and notes.
- Explicit citation labels and verified jumps back to files, PDF pages, and HTML sections.
- Agent provider profiles, OpenAI Codex OAuth support, clearer failure states, cancellation, and retry.
- Persistent study-session grouping, performance work, final chat math rendering, and pane interaction fixes.

<!-- WEIBEI_VISUAL:course-relations:START -->
<p align="center">
  <img src="./Docs/release-evidence/app-course-workspace-overview-flow.png" alt="WeiBei course material and note relationship view" width="1200">
</p>
<!-- WEIBEI_VISUAL:course-relations:END -->

This separation is intentional. The submission should be evaluated on the work added during Build Week, not on the earlier prototype as a whole.

## How I used Codex and GPT-5.6

I used Codex as my primary AI engineering collaborator. Across the Build Week work, Codex helped inspect the existing codebase, plan bounded changes, implement and refactor Swift code, write self-checks, trace failures, compare real app behavior with the intended design, and prepare release evidence.

GPT-5.6 was used inside Codex for selected architecture, implementation, debugging, and review work. It contributed to the source-grounded Agent design, the course relationship workbench, the rich-answer protocol, and the selection-linked question flow. Other coding models also helped on smaller exploration and review tasks.

I remained responsible for the original problem, product architecture, UX direction, acceptance criteria, hands-on testing, and every final shipping decision. I also rejected generated directions when they added complexity without improving the study flow.

This describes the development process. Inside the product, Pi is the Agent orchestration layer and the user chooses a configured model provider. GPT-5.6 is not hard-coded as WeiBei's runtime default.

## How it is built

WeiBei is a native Swift 5.9 application for macOS 14 and later.

- SwiftUI provides the application interface, with AppKit hosting the long-lived reader, Agent, and note panes.
- PDFKit reads PDFs, WebKit renders HTML and the Milkdown editor, and Vision handles OCR for scanned pages.
- SQLite FTS5 stores the local course index and search results.
- A pinned Pi 0.82.1 runtime provides the Agent loop.
- WeiBei owns the material context, citations, learning memory, note write-back, and interface rendering.

The Agent does not receive unrestricted file, terminal, or network access. Each request gets a bounded and revisioned snapshot of the current material, selection, note, course search results, and learning state. The Swift host validates citations, source jumps, learning updates, note proposals, and generative UI payloads before displaying or applying them.

For long or scanned PDFs, WeiBei extracts text in a resource-bounded helper process, indexes available text locally, and uses Vision OCR only when a page has no native text. Partial and incomplete indexing states remain visible instead of being presented as complete reads.

## Requirements

- macOS 14 or later
- Xcode Command Line Tools with Swift 5.9 support
- Internet access on the first build to download and verify the pinned Pi runtime
- A configured supported model provider for live Agent responses
- Node.js only when rebuilding the Milkdown web editor source

## Build and run

```bash
git clone https://github.com/weibei-app/weibei.git
cd weibei
./script/build_and_run.sh
```

The script builds and opens `dist/魏碑.app`.

## Suggested judge test

No private course data is included. Use a small folder containing a PDF, HTML page, Markdown file, or plain-text document that you are allowed to test with.

1. Launch WeiBei and import the folder as a course.
2. Open a material and create or select a related note.
3. Open Agent settings and configure an available provider, or use OpenAI Codex OAuth if it is available to the testing account.
4. Select a passage in the reader and ask a question from the selection surface.
5. Inspect the answer's citation labels and click one to return to the source location.
6. Return to the marked passage and reopen its persistent question thread.
7. Open the course relationship view and inspect or change the links between notes and materials.
8. Ask for a note update and confirm that WeiBei presents a proposal instead of silently changing the note.

## Checks

```bash
./script/build_and_run.sh check
./script/build_and_run.sh --verify
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

- WeiBei currently supports macOS 14 and later. Windows and web versions are future work.
- Course files and indexes are local-first, but live model responses may require a network connection.
- Learning memory is written automatically into the Chat's global or course scope and shown with a light end-of-answer notice. Formal notes and relationships still use a confirmation card.
- Large or difficult source files may be reported as partially indexed or incomplete.
- The repository version is `0.1.0` and remains a pre-release candidate, not a signed and notarized 1.0 release.

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
