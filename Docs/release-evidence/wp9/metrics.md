# WP9 V3 loading motion — measurements

## Text width (NSFont.system 12pt medium)

| text | textW | orbitW (=text+4.25*2) | L/R pad |
|---|---:|---:|---:|
| 正在读取上下文 | 84 | 92.5 | 4.25 |
| 正在核对材料与笔记 | 108 | 116.5 | 4.25 |
| 正在组织回答 | 72 | 80.5 | 4.25 |
| Reading context | 94 | 102.5 | 4.25 |
| Checking material and notes | 166 | 174.5 | 4.25 |
| Preparing a note proposal | 150 | 158.5 | 4.25 |

Orbit path inset 0.75, corner radius 3, path height 22.
Horizontal padding 4.25 each side → V3 acceptance ≈ 5–6px L/R at 1x (retina 2x doubles pixel counts).
Vertical: baseline -0.625 + path height 22 vs text cap height yields ~6–7pt top/bottom spacing.

Widths are measured live at runtime via `NSString.size(withAttributes:)` — not hardcoded per status.
