import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

struct SampleDef {
    let groupID: String
    let role: String
    let id: String
    let label: String
    let centerX: Int
    let centerY: Int
    let size: Int
    let note: String
}

struct SampleResult {
    let def: SampleDef
    let medianRGB: (Int, Int, Int)
    let linearRGB: (Double, Double, Double)
    let relativeLuminance: Double
}

struct ContrastPair {
    let id: String
    let title: String
    let foregroundRole: String
    let backgroundRole: String
    let thresholdNormal: Double
    let thresholdLarge: Double
    let conclusion: String
}

let defaultImagePath = "/private/tmp/weibei-rich-reply-replay-rerun-20260718-142954/after.png"
let defaultOutputDirectory = "Attachments/RichAnswerVerificationAssets/color-contrast"
let imagePath = CommandLine.arguments.dropFirst().first ?? defaultImagePath
let outputDirectoryPath = CommandLine.arguments.dropFirst(2).first ?? defaultOutputDirectory
let expectedSHA256 = "c1c79970691385ff614f7c5a9eacedc21a094ba409bf242bb7c62d0716f06e1e"
let expectedWidth = 2_616
let expectedHeight = 1_656

let samples: [SampleDef] = [
    SampleDef(groupID: "metric-value-black-on-paper", role: "foregroundRaw11", id: "metric-raw-2-top", label: "大号数值 2.22 的 2 顶部笔画 11×11", centerX: 1439, centerY: 444, size: 11, note: "可读数值主体；11×11 混入抗锯齿和纸色。"),
    SampleDef(groupID: "metric-value-black-on-paper", role: "foregroundRaw11", id: "metric-raw-second-2", label: "大号数值 2.22 的第二个 2 顶部笔画 11×11", centerX: 1484, centerY: 444, size: 11, note: "可读数值主体；11×11 中位数仍保留暗笔画。"),
    SampleDef(groupID: "metric-value-black-on-paper", role: "foregroundRaw11", id: "metric-raw-s", label: "大号数值单位 s 笔画 11×11", centerX: 1552, centerY: 448, size: 11, note: "单位字母笔画边缘；比数字更受抗锯齿影响。"),
    SampleDef(groupID: "metric-value-black-on-paper", role: "foregroundGlyphInterior", id: "metric-glyph-2-left", label: "大号数值 2.22 深色字形内部", centerX: 1439, centerY: 440, size: 5, note: "因 11×11 混入纸色，用 5×5 glyph interior 记录真实前景。"),
    SampleDef(groupID: "metric-value-black-on-paper", role: "foregroundGlyphInterior", id: "metric-glyph-2-mid", label: "大号数值 2.22 第二个 2 深色字形内部", centerX: 1484, centerY: 440, size: 5, note: "因 11×11 混入纸色，用 5×5 glyph interior 记录真实前景。"),
    SampleDef(groupID: "metric-value-black-on-paper", role: "foregroundGlyphInterior", id: "metric-glyph-2-right", label: "大号数值 2.22 第三个 2 深色字形内部", centerX: 1506, centerY: 440, size: 5, note: "因 11×11 混入纸色，用 5×5 glyph interior 记录真实前景。"),
    SampleDef(groupID: "metric-value-black-on-paper", role: "background11", id: "metric-bg-above", label: "大号数值上方纸色背景 11×11", centerX: 1425, centerY: 416, size: 11, note: "数值标签附近无字背景。"),
    SampleDef(groupID: "metric-value-black-on-paper", role: "background11", id: "metric-bg-between", label: "大号数字间纸色背景 11×11", centerX: 1458, centerY: 453, size: 11, note: "数字内部间隙附近背景。"),
    SampleDef(groupID: "metric-value-black-on-paper", role: "background11", id: "metric-bg-right", label: "大号数值右侧纸色背景 11×11", centerX: 1610, centerY: 443, size: 11, note: "数值右侧背景。"),
    SampleDef(groupID: "metric-value-black-on-paper", role: "boundary11", id: "metric-boundary-left-edge", label: "大号数字左边缘邻近边界 11×11", centerX: 1431, centerY: 444, size: 11, note: "文字边缘邻近区域；中位数可能被背景主导。"),
    SampleDef(groupID: "metric-value-black-on-paper", role: "boundary11", id: "metric-boundary-aa", label: "大号数字抗锯齿邻近边界 11×11", centerX: 1448, centerY: 442, size: 11, note: "抗锯齿边缘邻近区域。"),
    SampleDef(groupID: "metric-value-black-on-paper", role: "boundary11", id: "metric-boundary-s-edge", label: "单位 s 边缘邻近边界 11×11", centerX: 1552, centerY: 448, size: 11, note: "单位字母边缘区域。"),

    SampleDef(groupID: "orange-heading-on-paper", role: "foregroundRaw11", id: "orange-raw-left", label: "橙色小标题适用范围左侧 11×11", centerX: 1450, centerY: 990, size: 11, note: "橙色标题笔画附近；11×11 被纸色明显稀释。"),
    SampleDef(groupID: "orange-heading-on-paper", role: "foregroundRaw11", id: "orange-raw-scope", label: "橙色小标题范围字 11×11", centerX: 1510, centerY: 991, size: 11, note: "橙色标题较实笔画区域。"),
    SampleDef(groupID: "orange-heading-on-paper", role: "foregroundRaw11", id: "orange-raw-edge", label: "橙色小标题边缘 11×11", centerX: 1432, centerY: 990, size: 11, note: "标题左边缘；11×11 被纸色主导。"),
    SampleDef(groupID: "orange-heading-on-paper", role: "foregroundGlyphInterior", id: "orange-glyph-left", label: "橙色小标题字形内部 1", centerX: 1432, centerY: 982, size: 3, note: "3×3 glyph interior，用于避免 11×11 被背景吞掉。"),
    SampleDef(groupID: "orange-heading-on-paper", role: "foregroundGlyphInterior", id: "orange-glyph-mid", label: "橙色小标题字形内部 2", centerX: 1486, centerY: 982, size: 3, note: "3×3 glyph interior。"),
    SampleDef(groupID: "orange-heading-on-paper", role: "foregroundGlyphInterior", id: "orange-glyph-right", label: "橙色小标题字形内部 3", centerX: 1495, centerY: 982, size: 3, note: "3×3 glyph interior。"),
    SampleDef(groupID: "orange-heading-on-paper", role: "background11", id: "orange-bg-above", label: "橙色小标题上方纸色背景 11×11", centerX: 1448, centerY: 958, size: 11, note: "标题上方背景。"),
    SampleDef(groupID: "orange-heading-on-paper", role: "background11", id: "orange-bg-right", label: "橙色小标题右侧纸色背景 11×11", centerX: 1560, centerY: 990, size: 11, note: "标题右侧背景。"),
    SampleDef(groupID: "orange-heading-on-paper", role: "background11", id: "orange-bg-below", label: "橙色小标题下方纸色背景 11×11", centerX: 1450, centerY: 1018, size: 11, note: "标题下方背景。"),
    SampleDef(groupID: "orange-heading-on-paper", role: "boundary11", id: "orange-boundary-top", label: "橙色小标题上边缘邻近边界 11×11", centerX: 1454, centerY: 980, size: 11, note: "标题边缘区域；中位数可能被纸色主导。"),
    SampleDef(groupID: "orange-heading-on-paper", role: "boundary11", id: "orange-boundary-left", label: "橙色小标题左边缘邻近边界 11×11", centerX: 1432, centerY: 990, size: 11, note: "标题左边缘区域。"),
    SampleDef(groupID: "orange-heading-on-paper", role: "boundary11", id: "orange-boundary-right", label: "橙色小标题右边缘邻近边界 11×11", centerX: 1523, centerY: 982, size: 11, note: "标题右边缘区域。"),

    SampleDef(groupID: "input-placeholder-low-contrast", role: "foregroundRaw11", id: "placeholder-raw-left", label: "输入框占位文字问字 11×11", centerX: 1416, centerY: 1481, size: 11, note: "占位文字太细，11×11 中位数会接近背景。"),
    SampleDef(groupID: "input-placeholder-low-contrast", role: "foregroundRaw11", id: "placeholder-raw-mid", label: "输入框占位文字课程字 11×11", centerX: 1508, centerY: 1477, size: 11, note: "占位文字太细，11×11 中位数会接近背景。"),
    SampleDef(groupID: "input-placeholder-low-contrast", role: "foregroundRaw11", id: "placeholder-raw-right", label: "输入框占位文字材料字 11×11", centerX: 1558, centerY: 1481, size: 11, note: "占位文字太细，11×11 中位数会接近背景。"),
    SampleDef(groupID: "input-placeholder-low-contrast", role: "foregroundGlyphInterior", id: "placeholder-glyph-left", label: "输入框占位文字字形内部 1", centerX: 1416, centerY: 1481, size: 3, note: "11×11 被背景吞掉，改用 3×3 glyph interior。"),
    SampleDef(groupID: "input-placeholder-low-contrast", role: "foregroundGlyphInterior", id: "placeholder-glyph-mid", label: "输入框占位文字字形内部 2", centerX: 1508, centerY: 1477, size: 3, note: "11×11 被背景吞掉，改用 3×3 glyph interior。"),
    SampleDef(groupID: "input-placeholder-low-contrast", role: "foregroundGlyphInterior", id: "placeholder-glyph-right", label: "输入框占位文字字形内部 3", centerX: 1558, centerY: 1481, size: 3, note: "11×11 被背景吞掉，改用 3×3 glyph interior。"),
    SampleDef(groupID: "input-placeholder-low-contrast", role: "background11", id: "placeholder-bg-left", label: "输入框内部底色背景 11×11", centerX: 1450, centerY: 1460, size: 11, note: "输入框内部无字底色。"),
    SampleDef(groupID: "input-placeholder-low-contrast", role: "background11", id: "placeholder-bg-mid", label: "输入框内部底色背景 11×11", centerX: 1650, centerY: 1460, size: 11, note: "输入框内部无字底色。"),
    SampleDef(groupID: "input-placeholder-low-contrast", role: "background11", id: "placeholder-bg-right", label: "输入框内部底色背景 11×11", centerX: 1830, centerY: 1446, size: 11, note: "输入框内部无字底色。"),
    SampleDef(groupID: "input-placeholder-low-contrast", role: "boundary11", id: "placeholder-boundary-top-left", label: "输入框上边框邻近边界 11×11", centerX: 1395, centerY: 1427, size: 11, note: "输入框上边框很细，11×11 中位数可能被背景主导。"),
    SampleDef(groupID: "input-placeholder-low-contrast", role: "boundary11", id: "placeholder-boundary-top-mid", label: "输入框上边框邻近边界 11×11", centerX: 1500, centerY: 1427, size: 11, note: "输入框上边框很细。"),
    SampleDef(groupID: "input-placeholder-low-contrast", role: "boundary11", id: "placeholder-boundary-top-right", label: "输入框上边框邻近边界 11×11", centerX: 1700, centerY: 1427, size: 11, note: "输入框上边框很细。"),
]

let pairs: [ContrastPair] = [
    ContrastPair(id: "metric-value-black-on-paper", title: "明显可读：近似周期数值 2.22 s", foregroundRole: "foregroundGlyphInterior", backgroundRole: "background11", thresholdNormal: 4.5, thresholdLarge: 3.0, conclusion: "黑色大号数值对纸色背景有充分余量，可作为学生观察反馈的主读数。"),
    ContrastPair(id: "orange-heading-on-paper", title: "边缘状态：橙色小标题“适用范围”", foregroundRole: "foregroundGlyphInterior", backgroundRole: "background11", thresholdNormal: 4.5, thresholdLarge: 3.0, conclusion: "橙色标题在大号/加粗标题上可读，但不适合降级成小正文或说明文字。"),
    ContrastPair(id: "input-placeholder-low-contrast", title: "低对比状态：输入框占位文字", foregroundRole: "foregroundGlyphInterior", backgroundRole: "background11", thresholdNormal: 4.5, thresholdLarge: 3.0, conclusion: "占位文字对输入框底色对比度不足，富回答应把它标为需要增强的可用性风险点。"),
]

func median(_ values: [Int]) -> Int {
    let sorted = values.sorted()
    return sorted[sorted.count / 2]
}

func linearized(_ value: Int) -> Double {
    let component = Double(value) / 255.0
    if component <= 0.04045 {
        return component / 12.92
    }
    return pow((component + 0.055) / 1.055, 2.4)
}

func luminance(_ linear: (Double, Double, Double)) -> Double {
    0.2126 * linear.0 + 0.7152 * linear.1 + 0.0722 * linear.2
}

func rounded(_ value: Double, places: Int = 4) -> Double {
    let scale = pow(10.0, Double(places))
    return (value * scale).rounded() / scale
}

func contrastRatio(_ lhs: Double, _ rhs: Double) -> Double {
    let lighter = max(lhs, rhs)
    let darker = min(lhs, rhs)
    return (lighter + 0.05) / (darker + 0.05)
}

let imageURL = URL(fileURLWithPath: imagePath)
let imageData = try Data(contentsOf: imageURL)
let digest = SHA256.hash(data: imageData).map { String(format: "%02x", $0) }.joined()
guard digest == expectedSHA256 else {
    fatalError("Unexpected SHA-256 for \(imagePath): \(digest)")
}
guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fatalError("Unable to load PNG with CoreGraphics/ImageIO: \(imagePath)")
}
guard image.width == expectedWidth, image.height == expectedHeight else {
    fatalError("Unexpected PNG size \(image.width)×\(image.height)")
}

var bitmap = [UInt8](repeating: 0, count: image.width * image.height * 4)
guard let context = CGContext(
    data: &bitmap,
    width: image.width,
    height: image.height,
    bitsPerComponent: 8,
    bytesPerRow: image.width * 4,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fatalError("Unable to create bitmap context")
}
context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

func pixelRGB(x: Int, y: Int) -> (Int, Int, Int) {
    let index = (y * image.width + x) * 4
    return (Int(bitmap[index]), Int(bitmap[index + 1]), Int(bitmap[index + 2]))
}

func sample(_ def: SampleDef) -> SampleResult {
    let radius = def.size / 2
    precondition(def.centerX - radius >= 0 && def.centerY - radius >= 0)
    precondition(def.centerX + radius < image.width && def.centerY + radius < image.height)
    var red: [Int] = []
    var green: [Int] = []
    var blue: [Int] = []
    for y in (def.centerY - radius)...(def.centerY + radius) {
        for x in (def.centerX - radius)...(def.centerX + radius) {
            let rgb = pixelRGB(x: x, y: y)
            red.append(rgb.0)
            green.append(rgb.1)
            blue.append(rgb.2)
        }
    }
    let medianRGB = (median(red), median(green), median(blue))
    let linearRGB = (linearized(medianRGB.0), linearized(medianRGB.1), linearized(medianRGB.2))
    return SampleResult(def: def, medianRGB: medianRGB, linearRGB: linearRGB, relativeLuminance: luminance(linearRGB))
}

let results = samples.map(sample)
let resultsByGroup = Dictionary(grouping: results, by: { $0.def.groupID })

func representativeColor(groupID: String, role: String) -> (rgb: (Int, Int, Int), luminance: Double) {
    let groupResults = (resultsByGroup[groupID] ?? []).filter { $0.def.role == role }
    guard !groupResults.isEmpty else {
        fatalError("Missing role \(role) in group \(groupID)")
    }
    let red = median(groupResults.map { $0.medianRGB.0 })
    let green = median(groupResults.map { $0.medianRGB.1 })
    let blue = median(groupResults.map { $0.medianRGB.2 })
    let linear = (linearized(red), linearized(green), linearized(blue))
    return ((red, green, blue), luminance(linear))
}

let contrastObjects: [[String: Any]] = pairs.map { pair in
    let foreground = representativeColor(groupID: pair.id, role: pair.foregroundRole)
    let background = representativeColor(groupID: pair.id, role: pair.backgroundRole)
    let ratio = contrastRatio(foreground.luminance, background.luminance)
    return [
        "id": pair.id,
        "title": pair.title,
        "foregroundRole": pair.foregroundRole,
        "backgroundRole": pair.backgroundRole,
        "foregroundMedianRGB": ["r": foreground.rgb.0, "g": foreground.rgb.1, "b": foreground.rgb.2],
        "backgroundMedianRGB": ["r": background.rgb.0, "g": background.rgb.1, "b": background.rgb.2],
        "foregroundRelativeLuminance": rounded(foreground.luminance),
        "backgroundRelativeLuminance": rounded(background.luminance),
        "contrastRatio": rounded(ratio, places: 2),
        "passesNormalTextAA": ratio >= pair.thresholdNormal,
        "passesLargeTextAA": ratio >= pair.thresholdLarge,
        "thresholdNormalTextAA": pair.thresholdNormal,
        "thresholdLargeTextAA": pair.thresholdLarge,
        "conclusion": pair.conclusion,
    ]
}

let sampleObjects: [[String: Any]] = results.map { result in
    [
        "groupID": result.def.groupID,
        "role": result.def.role,
        "id": result.def.id,
        "label": result.def.label,
        "center": ["x": result.def.centerX, "y": result.def.centerY],
        "windowSize": result.def.size,
        "origin": "top-left",
        "medianRGB": ["r": result.medianRGB.0, "g": result.medianRGB.1, "b": result.medianRGB.2],
        "linearRGB": ["r": rounded(result.linearRGB.0), "g": rounded(result.linearRGB.1), "b": rounded(result.linearRGB.2)],
        "relativeLuminance": rounded(result.relativeLuminance),
        "note": result.def.note,
    ]
}

let reportObject: [String: Any] = [
    "caseID": "learning-art-color-contrast-overlay",
    "image": [
        "sourcePath": imagePath,
        "width": image.width,
        "height": image.height,
        "sha256": digest,
        "coordinateOrigin": "top-left",
        "samplingMethod": "CoreGraphics/ImageIO PNG decode; RGB median per window; sRGB linearization; WCAG relative luminance.",
    ],
    "samples": sampleObjects,
    "contrastPairs": contrastObjects,
    "antiAliasingDisclosure": "For large black text, 11×11 samples are recorded and glyph-interior 5×5 samples are used for the representative foreground. For the input placeholder and orange heading, 11×11 text samples can be swallowed by paper/background; 3×3 glyph-interior samples are therefore recorded explicitly and used for the representative foreground.",
]

let outputDirectory = URL(fileURLWithPath: outputDirectoryPath, isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let jsonURL = outputDirectory.appendingPathComponent("weibei-single-pendulum-color-contrast-samples.json")
let jsonData = try JSONSerialization.data(withJSONObject: reportObject, options: [.prettyPrinted, .sortedKeys])
try jsonData.write(to: jsonURL)

let csvURL = outputDirectory.appendingPathComponent("weibei-single-pendulum-color-contrast-samples.csv")
var csv = "group_id,role,id,label,origin,center_x,center_y,window_size,median_r,median_g,median_b,linear_r,linear_g,linear_b,relative_luminance,note\n"
for result in results {
    let values = [
        result.def.groupID,
        result.def.role,
        result.def.id,
        result.def.label,
        "top-left",
        String(result.def.centerX),
        String(result.def.centerY),
        String(result.def.size),
        String(result.medianRGB.0),
        String(result.medianRGB.1),
        String(result.medianRGB.2),
        String(format: "%.4f", result.linearRGB.0),
        String(format: "%.4f", result.linearRGB.1),
        String(format: "%.4f", result.linearRGB.2),
        String(format: "%.4f", result.relativeLuminance),
        result.def.note,
    ]
    csv += values.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: ",") + "\n"
}
try csv.write(to: csvURL, atomically: true, encoding: .utf8)

let markdownURL = outputDirectory.appendingPathComponent("weibei-single-pendulum-color-contrast-report.md")
var markdown = """
# learning-art-color-contrast-overlay 像素采样报告

- 源图：`\(imagePath)`
- 坐标原点：左上角，单位为 PNG 像素。
- 尺寸：\(image.width)×\(image.height)
- SHA-256：`\(digest)`
- 方法：CoreGraphics/ImageIO 读取 PNG；每个窗口取 RGB 中位数；sRGB 线性化后计算相对亮度和对比度。
- 抗锯齿说明：11×11 文字窗口已完整记录；当文字过细导致中位数被背景吞掉时，报告另列明确 glyph interior 小窗，不制造理想色值。

## 对比结论

| 组 | 前景 RGB | 背景 RGB | 前景 L | 背景 L | 对比度 | 普通正文 AA | 大号文字 AA | 专业结论 |
| --- | --- | --- | ---: | ---: | ---: | --- | --- | --- |
""" + "\n"
for object in contrastObjects {
    let fg = object["foregroundMedianRGB"] as! [String: Int]
    let bg = object["backgroundMedianRGB"] as! [String: Int]
    markdown += "| \(object["title"]!) | \(fg["r"]!),\(fg["g"]!),\(fg["b"]!) | \(bg["r"]!),\(bg["g"]!),\(bg["b"]!) | \(String(format: "%.4f", object["foregroundRelativeLuminance"] as! Double)) | \(String(format: "%.4f", object["backgroundRelativeLuminance"] as! Double)) | \(String(format: "%.2f", object["contrastRatio"] as! Double)):1 | \((object["passesNormalTextAA"] as! Bool) ? "通过" : "未通过") | \((object["passesLargeTextAA"] as! Bool) ? "通过" : "未通过") | \(object["conclusion"]!) |\n"
}

markdown += """

## 采样窗口

| 组 | 角色 | ID | 中心坐标 | 窗口 | RGB 中位数 | 相对亮度 | 说明 |
| --- | --- | --- | --- | ---: | --- | ---: | --- |
""" + "\n"
for result in results {
    markdown += "| \(result.def.groupID) | \(result.def.role) | \(result.def.id) | (\(result.def.centerX), \(result.def.centerY)) | \(result.def.size)×\(result.def.size) | \(result.medianRGB.0),\(result.medianRGB.1),\(result.medianRGB.2) | \(String(format: "%.4f", result.relativeLuminance)) | \(result.def.note) |\n"
}
try markdown.write(to: markdownURL, atomically: true, encoding: .utf8)

print("wrote \(jsonURL.path)")
print("wrote \(csvURL.path)")
print("wrote \(markdownURL.path)")
