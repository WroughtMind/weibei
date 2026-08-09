# Third-party notices

WeiBei includes and builds upon third-party open-source software. Those
components remain under their original licenses; the project's MIT License
does not replace them.

## Pi coding agent (Bun-compiled standalone)

WeiBei embeds a pinned upstream **standalone Pi** binary built with Bun
`build --compile`. Pi application source is MIT; Bun’s license and LGPL
static-link disclosures ship in the package. See
[`Vendor/PiRuntime/`](Vendor/PiRuntime/) (`THIRD_PARTY_NOTICES.md`,
`BUN_LICENSE.md`, `manifest.json`).

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

## Website fonts

The marketing website includes Noto Sans CJK and Noto Serif CJK web fonts.
They remain licensed under the SIL Open Font License 1.1. The copyright notice
and complete license text are preserved in
[`website/assets/fonts/OFL-Noto-CJK.txt`](website/assets/fonts/OFL-Noto-CJK.txt).

## Reference assets

Image and text reference sources, rights bases, and required credits are
documented in:

- [`Attachments/RichAnswerVerificationAssets/ATTRIBUTION.md`](Attachments/RichAnswerVerificationAssets/ATTRIBUTION.md)
- [`Attachments/RichAnswerVerificationAssets/manifest.json`](Attachments/RichAnswerVerificationAssets/manifest.json)
- [`Sources/WeiBei/Resources/RichAnswerVerificationAssets/ATTRIBUTION.md`](Sources/WeiBei/Resources/RichAnswerVerificationAssets/ATTRIBUTION.md)
- [`Sources/WeiBei/Resources/Inspiration/SOURCES.md`](Sources/WeiBei/Resources/Inspiration/SOURCES.md)

Redistributors must review and preserve the terms that apply to each asset.
