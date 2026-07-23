# Third-party notices

WeiBei includes and builds upon third-party open-source software. Those
components remain under their original licenses; the project's AGPL license
does not replace them.

## Pi coding agent

WeiBei downloads and packages a pinned standalone Pi coding agent runtime.
Version, source commit, artifact digests, MIT license, and notices are recorded
under [`Vendor/PiRuntime/`](Vendor/PiRuntime/).

## JavaScript components

The Milkdown editor and rich-answer runtime use packages including Milkdown,
KaTeX, Mermaid, PrismJS, React, ECharts, zrender, Vite, TypeScript, Zod, and
their transitive dependencies.

Exact package versions and declared licenses are recorded in:

- [`package-lock.json`](package-lock.json)
- [`Prototypes/RichAnswerWebRuntime/package-lock.json`](Prototypes/RichAnswerWebRuntime/package-lock.json)

Generated JavaScript bundles retain embedded copyright and license notices.
Rebuilds must preserve those notices.

## Reference assets

Image and text reference sources, rights bases, and required credits are
documented in:

- [`Attachments/RichAnswerVerificationAssets/ATTRIBUTION.md`](Attachments/RichAnswerVerificationAssets/ATTRIBUTION.md)
- [`Attachments/RichAnswerVerificationAssets/manifest.json`](Attachments/RichAnswerVerificationAssets/manifest.json)
- [`Sources/WeiBei/Resources/RichAnswerVerificationAssets/ATTRIBUTION.md`](Sources/WeiBei/Resources/RichAnswerVerificationAssets/ATTRIBUTION.md)
- [`Sources/WeiBei/Resources/Inspiration/SOURCES.md`](Sources/WeiBei/Resources/Inspiration/SOURCES.md)

Redistributors must review and preserve the terms that apply to each asset.
