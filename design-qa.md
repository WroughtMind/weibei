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
### 2026-07-11：收起轨道缩至真实休眠尺寸

- 休眠轨道从 40pt 缩至 28pt，磁吸区同步收窄为最后 10pt，减少对阅读面积的占用。
- 点击轨道节点时，恢复宽度限制在 300–380pt；没有可用历史宽度时使用 340pt，避免恢复成过宽或过窄面板。
- 历史宽度只在舒适区内原样恢复，超出区间时取最近边界；内容、选区与滚动位置仍沿用原有状态。

### 2026-07-11：收起轨道改为末端吸附并保留简介

- 分栏不再在 190pt 自动收起；用户拖到 53pt 以上时保留其实际宽度。
- 仅最后 12pt（40–52pt）作为可感知的磁吸区，松手后收成 40pt 轨道。
- 40pt 收起态悬浮仍显示 280pt 简介浮层；浮层越过分栏边界但不改宽、不抢焦点，点击沿用原有“恢复并跳转”行为。
- 新增 `content-rail-dormant-preview` 隔离验收场景，真实截图确认轨道、简介与相邻分栏无裁切或挤压。

---

# 原文问答浮层 Design QA

- 目标视觉：`/Users/changfenhuang/.codex/generated_images/019fd849-59a6-73f0-b4b9-16cfaa45d5a3/exec-e4166657-5bce-4871-ac02-87c466432bf3.png`
- 空态真窗口：`/private/tmp/weibei-selection-float-empty-final.png`
- 回答态真窗口：`/private/tmp/weibei-selection-float-answer-final.png`
- 完整原文弹层：`/private/tmp/weibei-selection-float-preview-ax.png`
- 视口：1440 × 900pt；浅色外观；隔离工作区；候选 App 未抢前台

## 对照结论

- 展开宽度固定为 380pt，不再允许拖成横向大窗；空态不挂载回答区，只保留一行原文、固定/关闭和无边框输入。
- 用户界面不再出现“选区对话”“选区”“已固定”“跳到对话”和空状态说明，也移除了输入区上方分割线与右下缩放柄。
- 原文默认单行省略；通过同一可访问按钮打开完整可选择文本。固定按钮在真 App 中完成一次开关，辅助功能标签从“取消固定”正确变为“固定在当前位置”。
- 空态与回答态的顶部指针保持同一位置；回答只向下展开，正文无重叠、无裁切，达到上限后内部滚动。
- 真窗口验收所用临时数据未进入提交，最终分支没有给正式 App 新增验收后门。

## Findings

- P0 / P1 / P2：本任务稳态界面无遗留。
- 跨任务记录：App 自带的 250ms 首帧截图早于富 Markdown 测高完成，曾捕获到暂态重叠；3 秒稳定态截图正常。流式/Markdown 状态切换由并行任务 #142 负责，#141 未改其状态机。

final result: passed
