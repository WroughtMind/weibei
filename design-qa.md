# Windows visual parity QA

- Source visual truth: `DesignReferences/weibei-reference-13-visual-system.png` (1586 × 992 px), supported by references 01, 06, 09, 12 and 17.
- Implementation evidence: packaged Windows Electron captures at 1240 × 760 CSS px, device scale factor 1, from the already-completed [workflow run 33287171636](https://github.com/WroughtMind/weibei/actions/runs/33287171636) at PR synthetic merge ref `1e12dd6b`.
- Evidence set: empty state, course drawer, three-pane workspace, paper settings and final glass-slate settings. All five captures were manually inspected from the short-lived [acceptance artifact 9725016917](https://github.com/WroughtMind/weibei/actions/runs/33287171636/artifacts/9725016917).
- Runtime result: the prior `windows-2025` run was green, including all three packaged Playwright UI scenes, NSIS install / same-version overwrite / uninstall and Portable checks.
- Candidate identity: Portable SHA-256 `ddc2b86c554ddda4d9e3f57669d7c8050eec75777d88da8a667df6fa6cd9000e`; Setup SHA-256 `e8a11d37deae4e187c55c494300bb07f67135d61c813b5f687aff8a5508c6d7e`.
- Evidence scope: these results belong only to that prior synthetic merge ref. They do not pre-approve later code changes or establish the merge readiness of the current head. The workflow retains the acceptance artifact for one day, so its link expires; the recorded hashes only preserve historical candidate identity.

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

## Merge boundary

- This prior evidence supports only the visual/runtime portion of the Windows core shell at synthetic merge ref `1e12dd6b`; the current head still requires its own code, data-safety and packaged Windows CI before merge.
- The confirmed Agent → note proposal / user approval / safe-write loop is not complete.
- Full relationship and learning-memory management, automatic updates, the OAuth provider catalog and scanned-PDF OCR are not complete.
- The workflow artifact is a short-lived CI acceptance candidate. It is not a formally signed or release-authorized Windows release, and no release claim should be derived from these hashes.

## Remaining gate

1. Capture an active document, grounded Agent response and active note at the same normalized viewport as reference 13.
2. Reconcile the library rail, pane proportions, missing toolbars/context controls and glass-slate secondary-text contrast.
3. Repeat the same-state comparison before making a pixel-level parity claim.

final result: prior packaged Windows core UI pass; exact pixel parity and full feature parity blocked; CI artifact is not a formal signed release
