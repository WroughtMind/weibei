# Third-party notices

WeiBei includes and builds upon third-party open-source software. Those
components remain under their original licenses; the project's MIT License
does not replace them.

## JavaScript components

The editor and document viewer use Milkdown, KaTeX, Mermaid, PrismJS,
remark-math, and their transitive dependencies. Build tools include esbuild,
TypeScript, tsx, and appdmg.

Exact package versions and declared licenses are recorded in:

- [`package-lock.json`](package-lock.json)

Generated JavaScript bundles retain embedded copyright and license notices.
Rebuilds must preserve those notices.

The safe mathematical expression evaluator used by the inline generative UI
is adapted from `dsh-external/dsh-genui`, copyright 2026 dsh-external, under
the MIT License.

## Fonts

The website uses the project's WeiBeiStele font at `website/assets/WeiBeiStele.ttf`.
Its SIL Open Font License 1.1 and Reserved Font Names are recorded in
[`DesignSystem/assets/fonts/OFL.txt`](DesignSystem/assets/fonts/OFL.txt).
System font fallbacks named in CSS are not bundled web fonts.

## Reference assets

Image and text reference sources, rights bases, and required credits are
documented in:

- [`Sources/WeiBei/Resources/Inspiration/SOURCES.md`](Sources/WeiBei/Resources/Inspiration/SOURCES.md)

Redistributors must review and preserve the terms that apply to each asset.
