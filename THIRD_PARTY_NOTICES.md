# Third-party notices

WeiBei includes and builds upon third-party open-source software. Those
components remain under their original licenses; the project's MIT License
does not replace them.

## JavaScript components

The Milkdown editor and rich-answer runtime use packages including Milkdown,
KaTeX, Mermaid, PrismJS, React, ECharts, zrender, Vite, TypeScript, Zod, and
their transitive dependencies.

Exact package versions and declared licenses are recorded in:

- [`package-lock.json`](package-lock.json)
- [`Prototypes/RichAnswerWebRuntime/package-lock.json`](Prototypes/RichAnswerWebRuntime/package-lock.json)

Generated JavaScript bundles retain embedded copyright and license notices.
Rebuilds must preserve those notices.

The safe mathematical expression evaluator used by the inline generative UI
is adapted from `dsh-external/dsh-genui`, copyright 2026 dsh-external, under
the MIT License.

## Native Markdown and mathematics

Assistant answers use WeiBei's fixed fork of Microsoft's
`SwiftStreamingMarkdown`, revision
`e3b6e952a7121e95aecb5370c90459b5c800fdf1`, copyright Microsoft Corporation,
under the MIT License.

Native formula rendering uses `SwiftMath`, revision
`c7830ce1ee79de0c57e4eac1ed3405b1ec790898`, copyright Computer Inspirations,
under the MIT License.

Their exact direct and transitive Swift package revisions are recorded in
[`Package.resolved`](Package.resolved). Redistributions must preserve the
license texts and notices bundled by those packages.

## Website fonts

The marketing website includes Noto Sans CJK and Noto Serif CJK web fonts.
They remain licensed under the SIL Open Font License 1.1. The copyright notice
and complete license text are preserved in
[`website/assets/fonts/OFL-Noto-CJK.txt`](website/assets/fonts/OFL-Noto-CJK.txt).

## Reference assets

Image and text reference sources, rights bases, and required credits are
documented in:

- [`Sources/WeiBei/Resources/Inspiration/SOURCES.md`](Sources/WeiBei/Resources/Inspiration/SOURCES.md)

Redistributors must review and preserve the terms that apply to each asset.
