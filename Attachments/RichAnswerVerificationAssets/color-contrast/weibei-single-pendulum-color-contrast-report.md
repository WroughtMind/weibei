# learning-art-color-contrast-overlay 像素采样报告

- 源图：`<temporary-directory>/weibei-rich-reply-replay-rerun-20260718-142954/after.png`
- 坐标原点：左上角，单位为 PNG 像素。
- 尺寸：2616×1656
- SHA-256：`c1c79970691385ff614f7c5a9eacedc21a094ba409bf242bb7c62d0716f06e1e`
- 方法：CoreGraphics/ImageIO 读取 PNG；每个窗口取 RGB 中位数；sRGB 线性化后计算相对亮度和对比度。
- 抗锯齿说明：11×11 文字窗口已完整记录；当文字过细导致中位数被背景吞掉时，报告另列明确 glyph interior 小窗，不制造理想色值。

## 对比结论

| 组 | 前景 RGB | 背景 RGB | 前景 L | 背景 L | 对比度 | 普通正文 AA | 大号文字 AA | 专业结论 |
| --- | --- | --- | ---: | ---: | ---: | --- | --- | --- |
| 明显可读：近似周期数值 2.22 s | 39,32,26 | 247,238,221 | 0.0154 | 0.8614 | 13.94:1 | 通过 | 通过 | 黑色大号数值对纸色背景有充分余量，可作为学生观察反馈的主读数。 |
| 边缘状态：橙色小标题“适用范围” | 181,90,71 | 247,238,221 | 0.1759 | 0.8614 | 4.03:1 | 未通过 | 通过 | 橙色标题在大号/加粗标题上可读，但不适合降级成小正文或说明文字。 |
| 低对比状态：输入框占位文字 | 188,182,171 | 249,242,226 | 0.4709 | 0.8913 | 1.81:1 | 未通过 | 未通过 | 占位文字对输入框底色对比度不足，富回答应把它标为需要增强的可用性风险点。 |

## 采样窗口

| 组 | 角色 | ID | 中心坐标 | 窗口 | RGB 中位数 | 相对亮度 | 说明 |
| --- | --- | --- | --- | ---: | --- | ---: | --- |
| metric-value-black-on-paper | foregroundRaw11 | metric-raw-2-top | (1439, 444) | 11×11 | 123,115,105 | 0.1749 | 可读数值主体；11×11 混入抗锯齿和纸色。 |
| metric-value-black-on-paper | foregroundRaw11 | metric-raw-second-2 | (1484, 444) | 11×11 | 97,90,81 | 0.1045 | 可读数值主体；11×11 中位数仍保留暗笔画。 |
| metric-value-black-on-paper | foregroundRaw11 | metric-raw-s | (1552, 448) | 11×11 | 136,129,118 | 0.2224 | 单位字母笔画边缘；比数字更受抗锯齿影响。 |
| metric-value-black-on-paper | foregroundGlyphInterior | metric-glyph-2-left | (1439, 440) | 5×5 | 39,32,26 | 0.0154 | 因 11×11 混入纸色，用 5×5 glyph interior 记录真实前景。 |
| metric-value-black-on-paper | foregroundGlyphInterior | metric-glyph-2-mid | (1484, 440) | 5×5 | 39,32,26 | 0.0154 | 因 11×11 混入纸色，用 5×5 glyph interior 记录真实前景。 |
| metric-value-black-on-paper | foregroundGlyphInterior | metric-glyph-2-right | (1506, 440) | 5×5 | 39,32,26 | 0.0154 | 因 11×11 混入纸色，用 5×5 glyph interior 记录真实前景。 |
| metric-value-black-on-paper | background11 | metric-bg-above | (1425, 416) | 11×11 | 247,238,221 | 0.8614 | 数值标签附近无字背景。 |
| metric-value-black-on-paper | background11 | metric-bg-between | (1458, 453) | 11×11 | 247,238,221 | 0.8614 | 数字内部间隙附近背景。 |
| metric-value-black-on-paper | background11 | metric-bg-right | (1610, 443) | 11×11 | 247,238,221 | 0.8614 | 数值右侧背景。 |
| metric-value-black-on-paper | boundary11 | metric-boundary-left-edge | (1431, 444) | 11×11 | 247,238,221 | 0.8614 | 文字边缘邻近区域；中位数可能被背景主导。 |
| metric-value-black-on-paper | boundary11 | metric-boundary-aa | (1448, 442) | 11×11 | 247,238,221 | 0.8614 | 抗锯齿边缘邻近区域。 |
| metric-value-black-on-paper | boundary11 | metric-boundary-s-edge | (1552, 448) | 11×11 | 136,129,118 | 0.2224 | 单位字母边缘区域。 |
| orange-heading-on-paper | foregroundRaw11 | orange-raw-left | (1450, 990) | 11×11 | 247,238,221 | 0.8614 | 橙色标题笔画附近；11×11 被纸色明显稀释。 |
| orange-heading-on-paper | foregroundRaw11 | orange-raw-scope | (1510, 991) | 11×11 | 181,90,71 | 0.1759 | 橙色标题较实笔画区域。 |
| orange-heading-on-paper | foregroundRaw11 | orange-raw-edge | (1432, 990) | 11×11 | 247,238,221 | 0.8614 | 标题左边缘；11×11 被纸色主导。 |
| orange-heading-on-paper | foregroundGlyphInterior | orange-glyph-left | (1432, 982) | 3×3 | 186,103,83 | 0.2076 | 3×3 glyph interior，用于避免 11×11 被背景吞掉。 |
| orange-heading-on-paper | foregroundGlyphInterior | orange-glyph-mid | (1486, 982) | 3×3 | 181,90,71 | 0.1759 | 3×3 glyph interior。 |
| orange-heading-on-paper | foregroundGlyphInterior | orange-glyph-right | (1495, 982) | 3×3 | 181,90,71 | 0.1759 | 3×3 glyph interior。 |
| orange-heading-on-paper | background11 | orange-bg-above | (1448, 958) | 11×11 | 247,238,221 | 0.8614 | 标题上方背景。 |
| orange-heading-on-paper | background11 | orange-bg-right | (1560, 990) | 11×11 | 247,238,221 | 0.8614 | 标题右侧背景。 |
| orange-heading-on-paper | background11 | orange-bg-below | (1450, 1018) | 11×11 | 247,238,221 | 0.8614 | 标题下方背景。 |
| orange-heading-on-paper | boundary11 | orange-boundary-top | (1454, 980) | 11×11 | 247,238,221 | 0.8614 | 标题边缘区域；中位数可能被纸色主导。 |
| orange-heading-on-paper | boundary11 | orange-boundary-left | (1432, 990) | 11×11 | 247,238,221 | 0.8614 | 标题左边缘区域。 |
| orange-heading-on-paper | boundary11 | orange-boundary-right | (1523, 982) | 11×11 | 247,238,221 | 0.8614 | 标题右边缘区域。 |
| input-placeholder-low-contrast | foregroundRaw11 | placeholder-raw-left | (1416, 1481) | 11×11 | 248,241,225 | 0.8830 | 占位文字太细，11×11 中位数会接近背景。 |
| input-placeholder-low-contrast | foregroundRaw11 | placeholder-raw-mid | (1508, 1477) | 11×11 | 188,182,171 | 0.4709 | 占位文字太细，11×11 中位数会接近背景。 |
| input-placeholder-low-contrast | foregroundRaw11 | placeholder-raw-right | (1558, 1481) | 11×11 | 218,212,198 | 0.6607 | 占位文字太细，11×11 中位数会接近背景。 |
| input-placeholder-low-contrast | foregroundGlyphInterior | placeholder-glyph-left | (1416, 1481) | 3×3 | 188,182,171 | 0.4709 | 11×11 被背景吞掉，改用 3×3 glyph interior。 |
| input-placeholder-low-contrast | foregroundGlyphInterior | placeholder-glyph-mid | (1508, 1477) | 3×3 | 188,182,171 | 0.4709 | 11×11 被背景吞掉，改用 3×3 glyph interior。 |
| input-placeholder-low-contrast | foregroundGlyphInterior | placeholder-glyph-right | (1558, 1481) | 3×3 | 188,182,171 | 0.4709 | 11×11 被背景吞掉，改用 3×3 glyph interior。 |
| input-placeholder-low-contrast | background11 | placeholder-bg-left | (1450, 1460) | 11×11 | 249,242,226 | 0.8913 | 输入框内部无字底色。 |
| input-placeholder-low-contrast | background11 | placeholder-bg-mid | (1650, 1460) | 11×11 | 249,242,226 | 0.8913 | 输入框内部无字底色。 |
| input-placeholder-low-contrast | background11 | placeholder-bg-right | (1830, 1446) | 11×11 | 249,242,226 | 0.8913 | 输入框内部无字底色。 |
| input-placeholder-low-contrast | boundary11 | placeholder-boundary-top-left | (1395, 1427) | 11×11 | 247,238,221 | 0.8614 | 输入框上边框很细，11×11 中位数可能被背景主导。 |
| input-placeholder-low-contrast | boundary11 | placeholder-boundary-top-mid | (1500, 1427) | 11×11 | 247,238,221 | 0.8614 | 输入框上边框很细。 |
| input-placeholder-low-contrast | boundary11 | placeholder-boundary-top-right | (1700, 1427) | 11×11 | 247,238,221 | 0.8614 | 输入框上边框很细。 |
