# Windows visual parity QA

- Source visual truth: `DesignReferences/weibei-reference-13-visual-system.png` (1586 × 992 px), supported by references 01, 02, 05, 14 and 17.
- Intended implementation evidence: packaged Windows Electron capture at 1240 × 760 CSS px, device scale factor 1.
- State: paper theme, three-pane workspace, active document, active Agent session and active Markdown note.
- Implementation screenshot: unavailable in the current Linux workspace.
- Density normalization: pending a 1240 × 760 Windows capture; source crops will be resized to the same comparison frame before judging.

## Findings

- Browser-rendered implementation evidence is unavailable. The Work Mode cloud browser rejected the local preview URL, and the local container cannot launch Chromium/Electron because its process-socket sandbox is restricted.
- Therefore fonts/typography, spacing/layout rhythm, colors/tokens, image quality, copy, focused regions, primary interactions and console errors cannot yet be compared from a combined reference/implementation image.
- The packaged Windows Playwright run is configured to capture the required 1240 × 760 evidence for empty, drawer, three-pane and settings states. That Windows run is the next comparison gate.

## Comparison history

- Pass 1: source images opened and inspected; implementation capture blocked before a valid same-state comparison could be produced. No visual pass is claimed from source code or build output alone.

## Implementation checklist

1. Run the packaged Electron Playwright smoke on `windows-2025`.
2. Open its 1240 × 760 evidence beside the matching reference crop.
3. Fix any P0/P1/P2 typography, spacing, token, icon or content differences and recapture.

final result: blocked
