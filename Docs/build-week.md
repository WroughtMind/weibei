# OpenAI Build Week 2026 submission record

Status: Build Week has concluded. This page preserves the submission-era record
(scope, AI-use disclosure, and the judge walkthrough) as submitted with the
`main` commit [`c05ca69b`](https://github.com/weibei-app/weibei/commit/c05ca69b).
WeiBei has been developed continuously since; the [README](../README.md)
describes the current product.

## Scope

WeiBei existed as an early prototype before the submission period. The last repository checkpoint before the July 13, 2026 9:00 AM Pacific start is [`366892c1`](https://github.com/weibei-app/weibei/commit/366892c1). It already supported the basic native read, ask, and write workflow, course-aware retrieval, local notes, study memory, and a three-pane workspace.

The Build Week work is the range from `366892c1` to the merged `main` submission commit [`c05ca69b`](https://github.com/weibei-app/weibei/commit/c05ca69b). This range contains 59 commits. The main additions were:

- A course hub and a material-to-note relationship workbench.
- A host-validated, evidence-linked rich-answer protocol with readable text fallback.
- Selection-based question threads and persistent marks across PDF, HTML, Markdown, and notes.
- Explicit citation labels and verified jumps back to files, PDF pages, and HTML sections.
- Agent provider profiles, OpenAI Codex OAuth support, clearer failure states, cancellation, and retry.
- Persistent study-session grouping, performance work, final chat math rendering, and pane interaction fixes.

This separation is intentional. The submission should be evaluated on the work added during Build Week, not on the earlier prototype as a whole.

## How Codex and GPT-5.6 were used

Codex was the primary AI engineering collaborator. Across the Build Week work, Codex helped inspect the existing codebase, plan bounded changes, implement and refactor Swift code, write self-checks, trace failures, compare real app behavior with the intended design, and prepare release evidence.

GPT-5.6 was used inside Codex for selected architecture, implementation, debugging, and review work. It contributed to the source-grounded Agent design, the course relationship workbench, the rich-answer protocol, and the selection-linked question flow. Other coding models also helped on smaller exploration and review tasks.

The author remained responsible for the original problem, product architecture, UX direction, acceptance criteria, hands-on testing, and every final shipping decision, and rejected generated directions that added complexity without improving the study flow.

This describes the development process. At submission time, Pi was the Agent orchestration layer; WeiBei now uses its Swift-native Agent runtime. The user still chooses a configured model provider, and GPT-5.6 is not hard-coded as the runtime default.

## Judge walkthrough

No private course data is included. Use a small folder containing a PDF, HTML page, Markdown file, or plain-text document that you are allowed to test with.

1. Launch WeiBei and import the folder as a course.
2. Open a material and create or select a related note.
3. Open Agent settings and configure an available provider, or use OpenAI Codex OAuth if it is available to the testing account.
4. Select a passage in the reader and ask a question from the selection surface.
5. Inspect the answer's citation labels and click one to return to the source location.
6. Return to the marked passage and reopen its persistent question thread.
7. Open the course relationship view and inspect or change the links between notes and materials.
8. Ask for a note update and confirm that WeiBei presents a proposal instead of silently changing the note.
