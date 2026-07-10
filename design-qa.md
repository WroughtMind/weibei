# Content Rail Design QA

- Source visual truth: `/var/folders/yp/wx87z0l97wj89_yj8nw7_ptm0000gn/T/codex-clipboard-f9bffc1d-eecd-440f-9c92-ed91b8df9cc3.png`
- Light implementation screenshot: `/private/tmp/weibei-wave-qa-351.png`
- Dark implementation screenshot: `/private/tmp/weibei-wave-dark-qa-352.png`
- Focused comparison: `/private/tmp/weibei-content-rail-comparison-final.png`
- Viewport: 2560 x 1640 app capture; focused comparison normalized to 536 x 310 per side
- State: second rail item hovered, preview visible, dark appearance

## Full-view comparison evidence

The rail remains a floating overlay and does not reserve document width. The preview opens to the right of the wave, stays inside the pane, and leaves the reading surface usable. Light and dark captures show no overflow or clipping.

## Focused comparison evidence

The reference rail measures 13, 22, 31, 44, 57, 44, 31, 22, 13 pixels around its peak. The implemented four-item sample measures 44, 56, 43, 30 pixels for the available distances, within one pixel of the corresponding reference values. Both use a fixed left edge and rightward growth.

## Required fidelity surfaces

- Fonts and typography: existing WeiBei typography is preserved; the change does not alter type.
- Spacing and layout rhythm: peak reduced from 34 to 28 points; neighbors follow 0.70, 0.41, and 0.20 distance weights; preview begins eight points after the peak and gains up to 24 points of width.
- Colors and visual tokens: hovered tick uses semantic cinnabar in both appearances; unselected ticks retain the existing mode-aware gray.
- Image quality and asset fidelity: no image assets were added or modified.
- Copy and content: preview continues to use real document title, excerpt, metadata, and page or section count.

## Comparison history

1. P1: the previous peak measured 69 pixels and every neighbor stayed at 15 pixels. Fixed by reducing the peak and adding four-step distance weights.
2. P1: the first dark capture used the pale on-cinnabar foreground for the hovered tick. Fixed by using cinnabar itself in both appearances. The final dark capture shows the selected rail in red.

## Findings

No actionable P0, P1, or P2 differences remain. The preview-to-peak gap is six pixels tighter than the reference, an intentional P3 trade-off that gives the preview more usable width.

## Implementation checklist

- Run Swift build and both project checks.
- Confirm one-click navigation remains unchanged.
- Package and open a non-activating isolated preview.

final result: passed
