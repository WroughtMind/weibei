# Windows visual parity QA

- Source visual truth: `DesignReferences/weibei-reference-13-visual-system.png` (1586 × 992 px), supported by references 01, 06, 09, 12 and 17.
- Implementation evidence: packaged Windows Electron captures at 1240 × 760 CSS px, device scale factor 1, from workflow run #1710 at `2cda0cd518b42650826539e4fa4c92a9ab196c58`.
- Evidence set: empty state, course drawer, three-pane workspace, paper settings and final glass-slate settings. The diagnostics artifact is `WeiBei-Windows-52f31c1a55c63a6c279e83128dcf9bb92ee30316-diagnostics` (artifact 9723054015, SHA-256 `fbab92fe51ec052ca5de263e69b7ff5081f96e6f3cb1e252125cc66d86db04dd`).
- Runtime result: all three packaged Playwright UI scenes passed on `windows-2025`.

## Findings

- No P0 rendering defect is visible in the five captures: Chinese fonts load, controls stay inside their surfaces, panes and dividers align, and no content leaks outside the window or modal.
- Paper, cinnabar, reading type, one-pixel dividers and the three equal workspace roles preserve the intended visual language.
- The available three-pane capture is an empty course. It does not reproduce the reference's active document, grounded Agent answer and active Markdown note, so a same-state pixel comparison is not yet valid.
- The Windows layout omits the reference's persistent library rail and several document, Agent-context and Markdown toolbar controls. Pane proportions and top chrome also differ materially from the macOS references.
- No source reference shows the same settings dialog. Its paper and glass-slate captures can establish internal consistency, but not one-to-one parity. Secondary copy in glass-slate is visibly lower contrast than the night reference.
- Platform chrome is intentionally Windows-specific; it must be judged by semantic role and optical dimensions rather than macOS traffic-light pixels.

## Comparison history

- Pass 1: source images inspected; implementation capture unavailable, so no visual pass was claimed.
- Pass 2: five real Windows captures inspected. Packaged UI behavior passed 3/3 and no P0 rendering defect was found. Exact visual parity remains blocked by state and structural differences.

## Remaining gate

1. Capture an active document, grounded Agent response and active note at the same normalized viewport as reference 13.
2. Reconcile the library rail, pane proportions, missing toolbars/context controls and glass-slate secondary-text contrast.
3. Repeat the same-state comparison before making a pixel-level parity claim.

final result: packaged Windows UI pass; pixel parity blocked
