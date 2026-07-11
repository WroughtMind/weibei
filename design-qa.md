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
3. P1: the full-width transparent rail overlay exposed background window dragging at pane borders in non-fullscreen windows. Fixed by restoring the rail's 40-point hit surface while passing pane width as layout data only. `/private/tmp/weibei-divider-qa-401.png` confirms the overflow preview still renders with the narrow hit surface.
4. P1: the pane previously snapped to an 88-point rail-only shell even though the dormant rail itself is 40 points, and widths between the rail threshold and the old 220-point preview minimum could suppress the preview entirely. The rail-only state now equals the 40-point dormant surface, widths below 190 points resolve to that state, compact text previews fit from 190 points, and hover opens immediately instead of racing a delayed work item.

## Findings

No actionable P0, P1, or P2 differences remain. The preview-to-peak gap is six pixels tighter than the reference, an intentional P3 trade-off that gives the preview more usable width.

## Implementation checklist

- Run Swift build and both project checks.
- Confirm one-click navigation remains unchanged.
- Package and open a non-activating isolated preview.

final result: passed

---

# Empty Workspace Design QA: Inspiration Disabled

- Reference: `/var/folders/yp/wx87z0l97wj89_yj8nw7_ptm0000gn/T/codex-clipboard-a2fc8532-c763-4611-aeef-eb42bcab300d.png`
- Implementation capture: `/var/folders/yp/wx87z0l97wj89_yj8nw7_ptm0000gn/T/weibei-visual-verify-empty-workspace-inspiration-off.png`
- Side-by-side comparison: `/private/tmp/weibei-empty-off-reference-comparison.png`
- Comparison viewport: 1180 x 760 points, 2360 x 1520 pixels
- State: light appearance, all work panes closed, daily inspiration disabled

## Comparison

- The greeting and `DOC | CHAT | NOTES` form one centered cluster.
- The cluster's horizontal center, greeting baseline, entry baseline, and vertical gap match the reference at the same viewport.
- Disabling inspiration removes the entire lower inspiration surface instead of reserving an invisible slot.
- Existing WeiBei hairlines and hover affordances remain; no new visual language or asset was introduced.
- The three work entries remain interactive and continue to use the existing pane toggles.

## Findings

- P0: none
- P1: none
- P2: none
- P3: the runtime greeting differs from the reference because it follows the actual time of day; this is expected behavior.

final result: passed
### 2026-07-11：收起轨道改为末端吸附并保留简介

- 分栏不再在 190pt 自动收起；用户拖到 53pt 以上时保留其实际宽度。
- 仅最后 12pt（40–52pt）作为可感知的磁吸区，松手后收成 40pt 轨道。
- 40pt 收起态悬浮仍显示 280pt 简介浮层；浮层越过分栏边界但不改宽、不抢焦点，点击沿用原有“恢复并跳转”行为。
- 新增 `content-rail-dormant-preview` 隔离验收场景，真实截图确认轨道、简介与相邻分栏无裁切或挤压。
