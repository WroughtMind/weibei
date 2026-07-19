#!/usr/bin/env swift

import AppKit
import Foundation

enum GateStatus: String {
    case pass
    case warn
    case fail
}

struct GateError: Error, CustomStringConvertible {
    let description: String
}

struct Arguments {
    var overviewPath: String?
    var beforePath: String?
    var afterPath: String?
    var overviewAckPath: String?
    var beforeAckPath: String?
    var afterAckPath: String?
    var axBeforePath: String?
    var axAfterPath: String?
    var outputPath: String?
    var singlePath: String?
    var singleAckPath: String?
    var requireReaderPane = false
    var requireAgentPane = false
}

struct PixelImage {
    let path: String
    let width: Int
    let height: Int
    let pixels: [UInt8]
}

struct ImageMetrics {
    let meanLuma: Double
    let standardDeviation: Double
    let dynamicRange: Double
    let opaqueFraction: Double
    let edgeFraction: Double
    let changedFraction: Double?
    let meanDifference: Double?
}

struct RectRecord {
    let role: String
    let identifier: String
    let title: String
    let desc: String
    let value: String
    let frame: CGRect
}

struct PaneFrames {
    let reader: CGRect
    let agent: CGRect
}

struct VerifiedCaptureAck {
    let stage: String
    let path: String
    let capturePath: String
    let sha256: String
    let bytes: Int64
    let startPaneFrames: PaneFrames?
    let endPaneFrames: PaneFrames?
}

struct CheckResult {
    let id: String
    let status: GateStatus
    let score: Int
    let summary: String
    let metrics: [String: Any]
}

let minimumReadablePaneWidth: CGFloat = 240
let paneWidthJumpFailThreshold: CGFloat = 48
let paneWidthJumpWarnThreshold: CGFloat = 20
let contentOverflowWarnTolerance: CGFloat = 10
let contentOverflowFailTolerance: CGFloat = 28
let canvasReadableWidthFailThreshold: CGFloat = 320
let canvasReadableWidthWarnThreshold: CGFloat = 380
let canvasSceneShareFailThreshold: CGFloat = 0.56
let canvasSceneShareWarnThreshold: CGFloat = 0.66

func parseArguments() throws -> Arguments {
    var arguments = Arguments()
    let rawArguments = Array(CommandLine.arguments.dropFirst())
    var argumentIndex = 0
    while argumentIndex < rawArguments.count {
        let key = rawArguments[argumentIndex]
        guard key.hasPrefix("--") else {
            throw GateError(description: "Unexpected positional argument: \(key)")
        }
        guard argumentIndex + 1 < rawArguments.count else {
            throw GateError(description: "Missing value for \(key)")
        }
        let value = rawArguments[argumentIndex + 1]
        switch key {
        case "--overview":
            arguments.overviewPath = value
        case "--before":
            arguments.beforePath = value
        case "--after":
            arguments.afterPath = value
        case "--overview-ack":
            arguments.overviewAckPath = value
        case "--before-ack":
            arguments.beforeAckPath = value
        case "--after-ack":
            arguments.afterAckPath = value
        case "--ax-before":
            arguments.axBeforePath = value
        case "--ax-after":
            arguments.axAfterPath = value
        case "--output":
            arguments.outputPath = value
        case "--single":
            arguments.singlePath = value
        case "--single-ack":
            arguments.singleAckPath = value
        case "--require-reader-pane":
            arguments.requireReaderPane = value == "true" || value == "1"
        case "--require-agent-pane":
            arguments.requireAgentPane = value == "true" || value == "1"
        default:
            throw GateError(description: "Unknown option: \(key)")
        }
        argumentIndex += 2
    }

    guard arguments.outputPath != nil else {
        throw GateError(description: "usage: rich-answer-visual-gate.swift --before before.png --after after.png --ax-before ax-before.txt --ax-after ax-after.txt --output quality.json [--single single.png]")
    }
    if arguments.singlePath == nil {
        guard arguments.beforePath != nil,
              arguments.afterPath != nil,
              arguments.axBeforePath != nil,
              arguments.axAfterPath != nil else {
            throw GateError(description: "Missing rich-interaction inputs. Provide --before, --after, --ax-before, --ax-after, and --output, or provide --single with --output.")
        }
    }
    return arguments
}

func loadImage(path: String) throws -> PixelImage {
    let imageURL = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: imageURL.path) else {
        throw GateError(description: "PNG does not exist: \(path)")
    }
    guard let sourceImage = NSImage(contentsOf: imageURL) else {
        throw GateError(description: "Could not load PNG: \(path)")
    }
    var proposedRect = CGRect(origin: .zero, size: sourceImage.size)
    guard let cgImage = sourceImage.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
        throw GateError(description: "Could not decode PNG as CGImage: \(path)")
    }
    let width = cgImage.width
    let height = cgImage.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw GateError(description: "Could not allocate bitmap context for \(path)")
    }
    context.interpolationQuality = .none
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    return PixelImage(path: path, width: width, height: height, pixels: pixels)
}

func clamp(_ value: Int, lowerBound: Int, upperBound: Int) -> Int {
    min(max(value, lowerBound), upperBound)
}

func luma(red: UInt8, green: UInt8, blue: UInt8) -> Double {
    0.2126 * Double(red) + 0.7152 * Double(green) + 0.0722 * Double(blue)
}

func pixelOffset(image: PixelImage, pixelX: Int, pixelY: Int) -> Int {
    (pixelY * image.width + pixelX) * 4
}

func sampleMetrics(image: PixelImage, rect: CGRect? = nil, comparedWith otherImage: PixelImage? = nil) -> ImageMetrics {
    let targetRect = rect ?? CGRect(x: 0, y: 0, width: image.width, height: image.height)
    let minPixelX = clamp(Int(targetRect.minX.rounded(.down)), lowerBound: 0, upperBound: max(0, image.width - 1))
    let minPixelY = clamp(Int(targetRect.minY.rounded(.down)), lowerBound: 0, upperBound: max(0, image.height - 1))
    let maxPixelX = clamp(Int(targetRect.maxX.rounded(.up)), lowerBound: minPixelX + 1, upperBound: image.width)
    let maxPixelY = clamp(Int(targetRect.maxY.rounded(.up)), lowerBound: minPixelY + 1, upperBound: image.height)
    let sampledWidth = max(1, maxPixelX - minPixelX)
    let sampledHeight = max(1, maxPixelY - minPixelY)
    let stepX = max(1, sampledWidth / 220)
    let stepY = max(1, sampledHeight / 160)

    var sampleCount = 0
    var opaqueCount = 0
    var lumaValues: [Double] = []
    var edgeCount = 0
    var changedCount = 0
    var differenceTotal = 0.0
    var differenceCount = 0

    for pixelY in stride(from: minPixelY, to: maxPixelY, by: stepY) {
        for pixelX in stride(from: minPixelX, to: maxPixelX, by: stepX) {
            let offset = pixelOffset(image: image, pixelX: pixelX, pixelY: pixelY)
            let red = image.pixels[offset]
            let green = image.pixels[offset + 1]
            let blue = image.pixels[offset + 2]
            let alpha = image.pixels[offset + 3]
            let currentLuma = luma(red: red, green: green, blue: blue)
            lumaValues.append(currentLuma)
            sampleCount += 1
            if alpha > 12 {
                opaqueCount += 1
            }
            let neighborX = min(pixelX + stepX, maxPixelX - 1)
            let neighborY = min(pixelY + stepY, maxPixelY - 1)
            let rightOffset = pixelOffset(image: image, pixelX: neighborX, pixelY: pixelY)
            let downOffset = pixelOffset(image: image, pixelX: pixelX, pixelY: neighborY)
            let rightLuma = luma(red: image.pixels[rightOffset], green: image.pixels[rightOffset + 1], blue: image.pixels[rightOffset + 2])
            let downLuma = luma(red: image.pixels[downOffset], green: image.pixels[downOffset + 1], blue: image.pixels[downOffset + 2])
            if abs(currentLuma - rightLuma) > 8 || abs(currentLuma - downLuma) > 8 {
                edgeCount += 1
            }

            if let otherImage {
                let otherPixelX = clamp(Int(Double(pixelX) / Double(image.width) * Double(otherImage.width)), lowerBound: 0, upperBound: otherImage.width - 1)
                let otherPixelY = clamp(Int(Double(pixelY) / Double(image.height) * Double(otherImage.height)), lowerBound: 0, upperBound: otherImage.height - 1)
                let otherOffset = pixelOffset(image: otherImage, pixelX: otherPixelX, pixelY: otherPixelY)
                let redDelta = abs(Int(red) - Int(otherImage.pixels[otherOffset]))
                let greenDelta = abs(Int(green) - Int(otherImage.pixels[otherOffset + 1]))
                let blueDelta = abs(Int(blue) - Int(otherImage.pixels[otherOffset + 2]))
                let averageDelta = Double(redDelta + greenDelta + blueDelta) / 3.0
                differenceTotal += averageDelta
                differenceCount += 1
                if averageDelta > 10 {
                    changedCount += 1
                }
            }
        }
    }

    let mean = lumaValues.reduce(0.0, +) / Double(max(1, lumaValues.count))
    let variance = lumaValues.reduce(0.0) { partial, value in
        partial + pow(value - mean, 2)
    } / Double(max(1, lumaValues.count))
    let minLuma = lumaValues.min() ?? 0
    let maxLuma = lumaValues.max() ?? 0
    return ImageMetrics(
        meanLuma: mean,
        standardDeviation: sqrt(variance),
        dynamicRange: maxLuma - minLuma,
        opaqueFraction: Double(opaqueCount) / Double(max(1, sampleCount)),
        edgeFraction: Double(edgeCount) / Double(max(1, sampleCount)),
        changedFraction: differenceCount > 0 ? Double(changedCount) / Double(differenceCount) : nil,
        meanDifference: differenceCount > 0 ? differenceTotal / Double(differenceCount) : nil
    )
}

func roundValue(_ value: Double, places: Int = 4) -> Double {
    let scale = pow(10.0, Double(places))
    return (value * scale).rounded() / scale
}

func normalizedPath(_ path: String) -> String {
    URL(fileURLWithPath: path).standardizedFileURL.path
}

func dictionaryValue(_ object: [String: Any], path: [String]) -> [String: Any]? {
    var current: Any = object
    for key in path {
        guard let dictionary = current as? [String: Any],
              let value = dictionary[key] else {
            return nil
        }
        current = value
    }
    return current as? [String: Any]
}

func stringValue(_ object: [String: Any], path: [String]) -> String? {
    var current: Any = object
    for key in path {
        guard let dictionary = current as? [String: Any],
              let value = dictionary[key] else {
            return nil
        }
        current = value
    }
    return current as? String
}

func boolValue(_ object: [String: Any], path: [String]) -> Bool? {
    var current: Any = object
    for key in path {
        guard let dictionary = current as? [String: Any],
              let value = dictionary[key] else {
            return nil
        }
        current = value
    }
    return current as? Bool
}

func doubleValue(_ object: [String: Any], path: [String]) -> Double? {
    var current: Any = object
    for key in path {
        guard let dictionary = current as? [String: Any],
              let value = dictionary[key] else {
            return nil
        }
        current = value
    }
    if let number = current as? NSNumber {
        return number.doubleValue
    }
    return current as? Double
}

func stringArrayValue(_ object: [String: Any], path: [String]) -> [String]? {
    var current: Any = object
    for key in path {
        guard let dictionary = current as? [String: Any],
              let value = dictionary[key] else {
            return nil
        }
        current = value
    }
    return current as? [String]
}

func fileByteCount(path: String) throws -> Int64 {
    let attributes = try FileManager.default.attributesOfItem(atPath: path)
    guard let size = attributes[.size] as? NSNumber else {
        throw GateError(description: "Could not read byte size for \(path)")
    }
    return size.int64Value
}

func fileSHA256(path: String) throws -> String {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
    process.arguments = ["-a", "256", path]
    process.standardOutput = pipe
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw GateError(description: "Could not hash PNG: \(path)")
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8),
          let digest = output.split(separator: " ").first,
          digest.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil else {
        throw GateError(description: "Invalid SHA256 output for \(path)")
    }
    return String(digest)
}

func rectFromAck(_ object: [String: Any], path: [String]) -> CGRect? {
    guard let frame = dictionaryValue(object, path: path),
          let x = doubleValue(frame, path: ["x"]),
          let y = doubleValue(frame, path: ["y"]),
          let width = doubleValue(frame, path: ["width"]),
          let height = doubleValue(frame, path: ["height"]),
          width > 0,
          height > 0 else {
        return nil
    }
    return CGRect(x: x, y: y, width: width, height: height)
}

func paneFramesFromAck(_ object: [String: Any], phase: String) -> PaneFrames? {
    guard let reader = rectFromAck(object, path: ["captureWorkspaceState", phase, "paneFrames", "reader"]),
          let agent = rectFromAck(object, path: ["captureWorkspaceState", phase, "paneFrames", "agent"]) else {
        return nil
    }
    return PaneFrames(reader: reader, agent: agent)
}

func stablePaneFramesFromAck(_ object: [String: Any]) throws -> (start: PaneFrames, end: PaneFrames)? {
    guard dictionaryValue(object, path: ["captureWorkspaceState"]) != nil else {
        return nil
    }
    guard boolValue(object, path: ["captureWorkspaceState", "stable"]) == true,
          boolValue(object, path: ["captureWorkspaceState", "start", "showReader"]) == true,
          boolValue(object, path: ["captureWorkspaceState", "start", "showAgent"]) == true,
          boolValue(object, path: ["captureWorkspaceState", "end", "showReader"]) == true,
          boolValue(object, path: ["captureWorkspaceState", "end", "showAgent"]) == true,
          stringArrayValue(object, path: ["captureWorkspaceState", "start", "visiblePanes"])?.contains("reader") == true,
          stringArrayValue(object, path: ["captureWorkspaceState", "start", "visiblePanes"])?.contains("agent") == true,
          stringArrayValue(object, path: ["captureWorkspaceState", "end", "visiblePanes"])?.contains("reader") == true,
          stringArrayValue(object, path: ["captureWorkspaceState", "end", "visiblePanes"])?.contains("agent") == true,
          let start = paneFramesFromAck(object, phase: "start"),
          let end = paneFramesFromAck(object, phase: "end") else {
        throw GateError(description: "Capture acknowledgement did not prove stable reader/agent pane frames")
    }
    return (start, end)
}

func loadVerifiedCaptureAck(path: String?, expectedStage: String, expectedImagePath: String?) throws -> VerifiedCaptureAck? {
    guard let path else { return nil }
    guard let expectedImagePath else {
        throw GateError(description: "Capture acknowledgement \(path) has no matching PNG input")
    }
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw GateError(description: "Capture acknowledgement is not a JSON object: \(path)")
    }
    let expectedPath = normalizedPath(expectedImagePath)
    guard stringValue(object, path: ["status"]) == "succeeded" else {
        throw GateError(description: "Capture acknowledgement is not succeeded: \(path)")
    }
    guard stringValue(object, path: ["stage"]) == expectedStage else {
        throw GateError(description: "Capture acknowledgement stage mismatch for \(path)")
    }
    for jsonPath in [["requestCapturePath"], ["capturePath"], ["actualPNG", "path"]] {
        guard let capturedPath = stringValue(object, path: jsonPath),
              normalizedPath(capturedPath) == expectedPath else {
            throw GateError(description: "Capture acknowledgement path mismatch for \(path)")
        }
    }
    guard let ackSHA256 = stringValue(object, path: ["actualPNG", "sha256"]),
          ackSHA256.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil,
          let ackBytes = doubleValue(object, path: ["actualPNG", "bytes"]),
          ackBytes > 0 else {
        throw GateError(description: "Capture acknowledgement missing valid PNG hash/bytes: \(path)")
    }
    if let prefixedHash = stringValue(object, path: ["actualPNG", "hash"]),
       prefixedHash != "sha256:\(ackSHA256)" {
        throw GateError(description: "Capture acknowledgement prefixed hash mismatch for \(path)")
    }
    let actualBytes = try fileByteCount(path: expectedImagePath)
    let actualSHA256 = try fileSHA256(path: expectedImagePath)
    guard Int64(ackBytes) == actualBytes,
          ackSHA256 == actualSHA256 else {
        throw GateError(description: "Capture acknowledgement does not match PNG bytes/hash for \(path)")
    }
    let paneFrames = try stablePaneFramesFromAck(object)
    return VerifiedCaptureAck(
        stage: expectedStage,
        path: path,
        capturePath: expectedImagePath,
        sha256: ackSHA256,
        bytes: actualBytes,
        startPaneFrames: paneFrames?.start,
        endPaneFrames: paneFrames?.end
    )
}

func paneRecord(identifier: String, stage: String, frame: CGRect) -> RectRecord {
    RectRecord(
        role: "AppCapturePane",
        identifier: identifier,
        title: "application-owned capture pane",
        desc: "verified capture acknowledgement \(stage)",
        value: stage,
        frame: frame
    )
}

func recordsReplacingPaneFrames(_ records: [RectRecord], with ack: VerifiedCaptureAck?) -> [RectRecord] {
    guard let frames = ack?.endPaneFrames else { return records }
    let paneIdentifiers = Set(["stable-document-slot-reader", "persistent-pane-reader", "stable-document-slot-agent", "persistent-pane-agent"])
    var merged = records.filter { !paneIdentifiers.contains($0.identifier) }
    merged.append(paneRecord(identifier: "stable-document-slot-reader", stage: ack?.stage ?? "", frame: frames.reader))
    merged.append(paneRecord(identifier: "stable-document-slot-agent", stage: ack?.stage ?? "", frame: frames.agent))
    return merged
}

func ackSummary(_ ack: VerifiedCaptureAck?) -> [String: Any] {
    guard let ack else { return ["present": false] }
    return [
        "present": true,
        "stage": ack.stage,
        "path": ack.path,
        "capturePath": ack.capturePath,
        "sha256": ack.sha256,
        "bytes": ack.bytes,
        "stablePaneFrames": ack.endPaneFrames != nil,
    ]
}

func parseAX(path: String?) throws -> [RectRecord] {
    guard let path else { return [] }
    let text = try String(contentsOfFile: path, encoding: .utf8)
    let pattern = #"role=(.*?) id=(.*?) title=(.*?) desc=(.*?) value=(.*?) frame=(-?\d+),(-?\d+),(-?\d+),(-?\d+)"#
    let expression = try NSRegularExpression(pattern: pattern)
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return expression.matches(in: text, range: range).compactMap { match in
        guard match.numberOfRanges == 10 else { return nil }
        func capture(_ index: Int) -> String {
            guard let captureRange = Range(match.range(at: index), in: text) else { return "" }
            return String(text[captureRange])
        }
        guard let frameX = Double(capture(6)),
              let frameY = Double(capture(7)),
              let frameWidth = Double(capture(8)),
              let frameHeight = Double(capture(9)) else {
            return nil
        }
        return RectRecord(
            role: capture(1),
            identifier: capture(2),
            title: capture(3),
            desc: capture(4),
            value: capture(5),
            frame: CGRect(x: frameX, y: frameY, width: frameWidth, height: frameHeight)
        )
    }
}

func firstRecord(records: [RectRecord], identifiers: [String]) -> RectRecord? {
    records.first { record in identifiers.contains(record.identifier) }
}

func largestRecord(records: [RectRecord], identifiers: [String]) -> RectRecord? {
    records
        .filter { identifiers.contains($0.identifier) && $0.frame.width > 0 && $0.frame.height > 0 }
        .max { lhs, rhs in
            lhs.frame.width * lhs.frame.height < rhs.frame.width * rhs.frame.height
        }
}

func windowRecord(records: [RectRecord]) -> RectRecord? {
    records.first { $0.role == "AXWindow" } ?? records.first
}

func paneRecords(records: [RectRecord]) -> (reader: RectRecord?, agent: RectRecord?) {
    let reader = largestRecord(records: records, identifiers: ["stable-document-slot-reader", "persistent-pane-reader"])
    let agent = largestRecord(records: records, identifiers: ["stable-document-slot-agent", "persistent-pane-agent"])
    return (reader, agent)
}

func paneToggleRecord(records: [RectRecord], identifier: String) -> RectRecord? {
    firstRecord(records: records, identifiers: [identifier])
}

func paneIsVisible(toggle: RectRecord, hiddenActionLabels: [String]) -> Bool {
    let description = toggle.desc.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return hiddenActionLabels.contains { description.contains($0.lowercased()) }
}

func checkRequiredPaneVisibility(
    beforeRecords: [RectRecord],
    afterRecords: [RectRecord],
    requireReaderPane: Bool,
    requireAgentPane: Bool
) -> CheckResult {
    let requirements: [(name: String, required: Bool, identifier: String, visibleActionLabels: [String])] = [
        ("reader", requireReaderPane, "doc.text", ["隐藏文稿", "hide document"]),
        ("agent", requireAgentPane, "bubble.left.and.text.bubble.right", ["隐藏对话", "hide chat"]),
    ]
    var failures: [String] = []
    var observations: [[String: Any]] = []

    for requirement in requirements where requirement.required {
        for stage in [("before", beforeRecords), ("after", afterRecords)] {
            guard let toggle = paneToggleRecord(records: stage.1, identifier: requirement.identifier) else {
                failures.append("\(stage.0) 缺少 \(requirement.name) 窗格开关证据，无法证明窗格仍然可见")
                observations.append([
                    "stage": stage.0,
                    "pane": requirement.name,
                    "toggleIdentifier": requirement.identifier,
                    "toggleDescription": "",
                    "visible": false,
                    "evidencePresent": false,
                ])
                continue
            }
            let visible = paneIsVisible(toggle: toggle, hiddenActionLabels: requirement.visibleActionLabels)
            if !visible {
                failures.append("\(stage.0) 的 \(requirement.name) 窗格已被关闭")
            }
            observations.append([
                "stage": stage.0,
                "pane": requirement.name,
                "toggleIdentifier": requirement.identifier,
                "toggleDescription": toggle.desc,
                "visible": visible,
                "evidencePresent": true,
            ])
        }
    }

    let status: GateStatus = failures.isEmpty ? .pass : .fail
    return CheckResult(
        id: "required-pane-visibility",
        status: status,
        score: status == .pass ? 20 : 0,
        summary: failures.first ?? "富回答验收所需的资料与对话窗格持续可见",
        metrics: [
            "requiredReaderPane": requireReaderPane,
            "requiredAgentPane": requireAgentPane,
            "observations": observations,
            "failures": failures,
        ]
    )
}

func imageRect(for axFrame: CGRect, windowFrame: CGRect, image: PixelImage) -> CGRect {
    let scaleX = CGFloat(image.width) / max(windowFrame.width, 1)
    let scaleY = CGFloat(image.height) / max(windowFrame.height, 1)
    return CGRect(
        x: (axFrame.minX - windowFrame.minX) * scaleX,
        y: (axFrame.minY - windowFrame.minY) * scaleY,
        width: axFrame.width * scaleX,
        height: axFrame.height * scaleY
    )
}

func imageIsVisible(_ metrics: ImageMetrics) -> Bool {
    metrics.opaqueFraction > 0.98
        && (metrics.standardDeviation >= 2.2 || metrics.dynamicRange >= 18 || metrics.edgeFraction >= 0.006)
}

func checkVisibleContent(images: [(label: String, image: PixelImage)], axRecords: [RectRecord]) -> CheckResult {
    var failures: [String] = []
    var warnings: [String] = []
    var imageObjects: [[String: Any]] = []

    for imageEntry in images {
        let metrics = sampleMetrics(image: imageEntry.image)
        let visible = imageIsVisible(metrics)
        if !visible {
            failures.append("\(imageEntry.label) 截图接近空白或没有可见内容")
        }
        imageObjects.append([
            "label": imageEntry.label,
            "path": imageEntry.image.path,
            "width": imageEntry.image.width,
            "height": imageEntry.image.height,
            "meanLuma": roundValue(metrics.meanLuma),
            "standardDeviation": roundValue(metrics.standardDeviation),
            "dynamicRange": roundValue(metrics.dynamicRange),
            "opaqueFraction": roundValue(metrics.opaqueFraction),
            "edgeFraction": roundValue(metrics.edgeFraction),
            "visible": visible,
        ])
    }

    if let window = windowRecord(records: axRecords) {
        let panes = paneRecords(records: axRecords)
        for imageEntry in images {
            for paneEntry in [("reader", panes.reader), ("agent", panes.agent)] {
                guard let pane = paneEntry.1, pane.frame.width >= 180, pane.frame.height >= 180 else { continue }
                let paneRect = imageRect(for: pane.frame, windowFrame: window.frame, image: imageEntry.image).insetBy(dx: 10, dy: 10)
                let metrics = sampleMetrics(image: imageEntry.image, rect: paneRect)
                if !imageIsVisible(metrics) {
                    warnings.append("\(imageEntry.label) 的 \(paneEntry.0) 窗格可见内容偏少，可能是背景截图残帧或空白窗格")
                }
            }
        }
    }

    let status: GateStatus = failures.isEmpty ? (warnings.isEmpty ? .pass : .warn) : .fail
    let score = status == .fail ? 0 : (status == .warn ? 13 : 20)
    return CheckResult(
        id: "visible-content",
        status: status,
        score: score,
        summary: (failures + warnings).first ?? "截图和主要窗格都有可见内容",
        metrics: [
            "images": imageObjects,
            "failures": failures,
            "warnings": warnings,
        ]
    )
}

func richControlValues(records: [RectRecord]) -> [String: String] {
    var values: [String: String] = [:]
    for record in records where record.identifier.hasPrefix("rich-answer-control-") || record.role == "AXSlider" || record.role == "AXValueIndicator" {
        let key = record.identifier.isEmpty ? "\(record.role)@\(Int(record.frame.minX)),\(Int(record.frame.minY))" : record.identifier
        values[key] = record.value
    }
    return values
}

func changedControlKeys(beforeRecords: [RectRecord], afterRecords: [RectRecord]) -> [String] {
    let beforeValues = richControlValues(records: beforeRecords)
    let afterValues = richControlValues(records: afterRecords)
    return beforeValues.keys.sorted().filter { key in
        guard let beforeValue = beforeValues[key], let afterValue = afterValues[key] else { return false }
        return beforeValue != afterValue
    }
}

func checkInteractionChanged(beforeImage: PixelImage?, afterImage: PixelImage?, beforeRecords: [RectRecord], afterRecords: [RectRecord]) -> CheckResult {
    guard let beforeImage, let afterImage else {
        return CheckResult(id: "interaction-changed", status: .warn, score: 10, summary: "single 模式未检查交互前后变化", metrics: ["mode": "single"])
    }
    let metrics = sampleMetrics(image: afterImage, comparedWith: beforeImage)
    let changedKeys = changedControlKeys(beforeRecords: beforeRecords, afterRecords: afterRecords)
    let changedFraction = metrics.changedFraction ?? 0
    let meanDifference = metrics.meanDifference ?? 0
    let imageChanged = changedFraction >= 0.0015 || meanDifference >= 0.35
    let axChanged = !changedKeys.isEmpty
    let status: GateStatus
    let summary: String
    let score: Int
    if imageChanged || axChanged {
        status = imageChanged ? .pass : .warn
        summary = imageChanged ? "交互前后截图有可见变化" : "AX 控件值已变化，但截图变化很小，可能需要复核捕获链路"
        score = imageChanged ? 20 : 13
    } else {
        status = .fail
        summary = "交互前后截图和 AX 控件值都没有明显变化"
        score = 0
    }
    return CheckResult(
        id: "interaction-changed",
        status: status,
        score: score,
        summary: summary,
        metrics: [
            "changedFraction": roundValue(changedFraction),
            "meanDifference": roundValue(meanDifference),
            "changedControlKeys": changedKeys,
            "imageChanged": imageChanged,
            "axChanged": axChanged,
        ]
    )
}

func checkPaneWidths(beforeRecords: [RectRecord], afterRecords: [RectRecord], usedAckFallback: Bool) -> CheckResult {
    let beforePanes = paneRecords(records: beforeRecords)
    let afterPanes = paneRecords(records: afterRecords)
    var failures: [String] = []
    var warnings: [String] = []
    var paneMetrics: [[String: Any]] = []

    for paneEntry in [("reader", beforePanes.reader, afterPanes.reader), ("agent", beforePanes.agent, afterPanes.agent)] {
        guard let beforePane = paneEntry.1, let afterPane = paneEntry.2 else {
            warnings.append("缺少 \(paneEntry.0) 窗格 AX frame，无法判断宽度稳定性")
            continue
        }
        let widthDelta = abs(afterPane.frame.width - beforePane.frame.width)
        let minimumWidth = min(beforePane.frame.width, afterPane.frame.width)
        if minimumWidth < minimumReadablePaneWidth {
            failures.append("\(paneEntry.0) 窗格宽度 \(Int(minimumWidth))px，已压到不可读")
        }
        if widthDelta >= paneWidthJumpFailThreshold {
            failures.append("\(paneEntry.0) 窗格交互前后跳变 \(Int(widthDelta))px")
        } else if widthDelta >= paneWidthJumpWarnThreshold {
            warnings.append("\(paneEntry.0) 窗格交互前后变化 \(Int(widthDelta))px，需要复核")
        }
        paneMetrics.append([
            "pane": paneEntry.0,
            "beforeWidth": roundValue(beforePane.frame.width),
            "afterWidth": roundValue(afterPane.frame.width),
            "widthDelta": roundValue(widthDelta),
            "minimumWidth": roundValue(minimumWidth),
        ])
    }

    let status: GateStatus = failures.isEmpty ? (warnings.isEmpty ? .pass : .warn) : .fail
    return CheckResult(
        id: "pane-width-stability",
        status: status,
        score: status == .fail ? 0 : (status == .warn ? 13 : 20),
        summary: (failures + warnings).first ?? "读文窗格和 Agent 窗格宽度稳定且可读",
        metrics: [
            "panes": paneMetrics,
            "failures": failures,
            "warnings": warnings,
            "minimumReadablePaneWidth": Int(minimumReadablePaneWidth),
            "paneFrameSource": usedAckFallback ? "application-ack" : "accessibility",
        ]
    )
}

func richContentRecords(records: [RectRecord]) -> [RectRecord] {
    records.filter { record in
        record.identifier.hasPrefix("rich-answer-")
            && record.frame.width > 0
            && record.frame.height > 0
    }
}

func checkContentOverflow(records: [RectRecord], usedAckFallback: Bool) -> CheckResult {
    let panes = paneRecords(records: records)
    guard let agentPane = panes.agent else {
        return CheckResult(id: "content-overflow", status: .warn, score: 11, summary: "缺少 Agent 窗格 frame，无法判断内容越界", metrics: ["recordCount": records.count])
    }
    let richRecords = richContentRecords(records: records)
    if richRecords.isEmpty {
        if usedAckFallback {
            return CheckResult(
                id: "content-overflow",
                status: .pass,
                score: 16,
                summary: "AX 未暴露富回答 frame，已用应用回执确认 Agent 窗格边界",
                metrics: [
                    "recordCount": records.count,
                    "contentFrameSource": "unavailable",
                    "paneFrameSource": "application-ack",
                    "fallbackLimit": "pane-boundary-only",
                    "requiresHumanReview": true,
                ]
            )
        }
        return CheckResult(id: "content-overflow", status: .warn, score: 13, summary: "未发现 rich-answer AX 元素，无法判断富回答内容越界", metrics: ["recordCount": records.count])
    }

    var failures: [[String: Any]] = []
    var warnings: [[String: Any]] = []
    for record in richRecords {
        let leftOverflow = max(0, agentPane.frame.minX - record.frame.minX)
        let rightOverflow = max(0, record.frame.maxX - agentPane.frame.maxX)
        let horizontalOverflow = max(leftOverflow, rightOverflow)
        let recordObject: [String: Any] = [
            "id": record.identifier,
            "role": record.role,
            "frame": [
                "x": roundValue(record.frame.minX),
                "y": roundValue(record.frame.minY),
                "width": roundValue(record.frame.width),
                "height": roundValue(record.frame.height),
            ],
            "horizontalOverflow": roundValue(horizontalOverflow),
        ]
        if horizontalOverflow >= contentOverflowFailTolerance || record.frame.width > agentPane.frame.width + 40 {
            failures.append(recordObject)
        } else if horizontalOverflow >= contentOverflowWarnTolerance || record.frame.width > agentPane.frame.width + 18 {
            warnings.append(recordObject)
        }
    }

    let status: GateStatus = failures.isEmpty ? (warnings.isEmpty ? .pass : .warn) : .fail
    return CheckResult(
        id: "content-overflow",
        status: status,
        score: status == .fail ? 0 : (status == .warn ? 13 : 20),
        summary: failures.first.map { "发现富回答内容明显横向越界：\($0["id"] ?? "")" }
            ?? warnings.first.map { "发现富回答内容接近横向边界：\($0["id"] ?? "")" }
            ?? "富回答内容没有明显横向越界",
        metrics: [
            "agentPane": [
                "x": roundValue(agentPane.frame.minX),
                "y": roundValue(agentPane.frame.minY),
                "width": roundValue(agentPane.frame.width),
                "height": roundValue(agentPane.frame.height),
            ],
            "richRecordCount": richRecords.count,
            "failures": failures,
            "warnings": warnings,
            "warnTolerance": Int(contentOverflowWarnTolerance),
            "failTolerance": Int(contentOverflowFailTolerance),
            "paneFrameSource": usedAckFallback ? "application-ack" : "accessibility",
        ]
    )
}

func richCanvasRecords(records: [RectRecord]) -> [RectRecord] {
    records.filter { record in
        record.identifier.hasPrefix("rich-answer-canvas-")
            && record.frame.width > 0
            && record.frame.height > 0
    }
}

func richSceneRecords(records: [RectRecord]) -> [RectRecord] {
    records.filter { record in
        record.identifier.hasPrefix("rich-answer-scene-")
            && record.frame.width > 0
            && record.frame.height > 0
    }
}

func enclosingScene(for canvas: RectRecord, scenes: [RectRecord]) -> RectRecord? {
    let center = CGPoint(x: canvas.frame.midX, y: canvas.frame.midY)
    return scenes
        .filter { $0.frame.insetBy(dx: -2, dy: -2).contains(center) && $0.frame.width >= canvas.frame.width }
        .sorted { lhs, rhs in
            (lhs.frame.width * lhs.frame.height) < (rhs.frame.width * rhs.frame.height)
        }
        .first
}

func checkInlineCanvasReadability(records: [RectRecord]) -> CheckResult {
    let canvases = richCanvasRecords(records: records)
    guard !canvases.isEmpty else {
        return CheckResult(
            id: "inline-canvas-readability",
            status: .pass,
            score: 20,
            summary: "未发现内联画布，跳过画布宽度检查",
            metrics: ["canvasCount": 0]
        )
    }

    let scenes = richSceneRecords(records: records)
    let panes = paneRecords(records: records)
    var failures: [[String: Any]] = []
    var warnings: [[String: Any]] = []
    var canvasMetrics: [[String: Any]] = []

    for canvas in canvases {
        let scene = enclosingScene(for: canvas, scenes: scenes)
        let container = scene ?? panes.agent
        let containerWidth = container?.frame.width ?? 0
        let widthShare = containerWidth > 0 ? canvas.frame.width / containerWidth : 1
        let canvasObject: [String: Any] = [
            "id": canvas.identifier,
            "role": canvas.role,
            "width": roundValue(canvas.frame.width),
            "height": roundValue(canvas.frame.height),
            "containerID": container?.identifier ?? "",
            "containerWidth": roundValue(containerWidth),
            "widthShare": roundValue(widthShare),
            "absoluteFailThreshold": Int(canvasReadableWidthFailThreshold),
            "absoluteWarnThreshold": Int(canvasReadableWidthWarnThreshold),
            "shareFailThreshold": roundValue(canvasSceneShareFailThreshold),
            "shareWarnThreshold": roundValue(canvasSceneShareWarnThreshold),
        ]

        let absoluteFail = canvas.frame.width < canvasReadableWidthFailThreshold
        let shareFail = containerWidth > 0 && widthShare < canvasSceneShareFailThreshold
        let absoluteWarn = canvas.frame.width < canvasReadableWidthWarnThreshold
        let shareWarn = containerWidth > 0 && widthShare < canvasSceneShareWarnThreshold

        if absoluteFail || shareFail {
            failures.append(canvasObject.merging([
                "reason": absoluteFail
                    ? "canvas width \(Int(canvas.frame.width))pt below readable floor"
                    : "canvas uses only \(Int((widthShare * 100).rounded()))% of inline scene/container width",
            ]) { current, _ in current })
        } else if absoluteWarn || shareWarn {
            warnings.append(canvasObject.merging([
                "reason": absoluteWarn
                    ? "canvas width \(Int(canvas.frame.width))pt close to readable floor"
                    : "canvas uses only \(Int((widthShare * 100).rounded()))% of inline scene/container width",
            ]) { current, _ in current })
        }
        canvasMetrics.append(canvasObject)
    }

    let status: GateStatus = failures.isEmpty ? (warnings.isEmpty ? .pass : .warn) : .fail
    return CheckResult(
        id: "inline-canvas-readability",
        status: status,
        score: status == .fail ? 0 : (status == .warn ? 13 : 20),
        summary: failures.first.map { "内联画布被压到不可读：\($0["id"] ?? "")" }
            ?? warnings.first.map { "内联画布偏窄，需要人工复核：\($0["id"] ?? "")" }
            ?? "内联画布宽度和场景占比达到基础可读线",
        metrics: [
            "canvases": canvasMetrics,
            "failures": failures,
            "warnings": warnings,
        ]
    )
}

func aggregate(checks: [CheckResult]) -> (status: GateStatus, score: Int) {
    let status: GateStatus
    if checks.contains(where: { $0.status == .fail }) {
        status = .fail
    } else if checks.contains(where: { $0.status == .warn }) {
        status = .warn
    } else {
        status = .pass
    }
    let score = checks.reduce(0) { partial, check in partial + check.score }
    if status == .fail {
        return (status, min(69, score))
    }
    if status == .warn {
        return (status, min(89, score))
    }
    return (status, min(100, score))
}

func checkObject(_ check: CheckResult) -> [String: Any] {
    [
        "id": check.id,
        "status": check.status.rawValue,
        "score": check.score,
        "summary": check.summary,
        "metrics": check.metrics,
    ]
}

func writeJSON(_ object: [String: Any], outputPath: String) throws {
    let outputURL = URL(fileURLWithPath: outputPath)
    try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: outputURL)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

func run() throws {
    let arguments = try parseArguments()
    let overviewImage = try arguments.overviewPath.map(loadImage)
    let beforeImage = try arguments.beforePath.map(loadImage)
    let afterImage = try arguments.afterPath.map(loadImage)
    let singleImage = try arguments.singlePath.map(loadImage)
    let overviewAck = try loadVerifiedCaptureAck(path: arguments.overviewAckPath, expectedStage: "overview", expectedImagePath: arguments.overviewPath)
    let beforeAck = try loadVerifiedCaptureAck(path: arguments.beforeAckPath, expectedStage: "before", expectedImagePath: arguments.beforePath)
    let afterAck = try loadVerifiedCaptureAck(path: arguments.afterAckPath, expectedStage: "after", expectedImagePath: arguments.afterPath)
    let singleAck = try loadVerifiedCaptureAck(path: arguments.singleAckPath, expectedStage: "single", expectedImagePath: arguments.singlePath)
    let beforeRecords = recordsReplacingPaneFrames(try parseAX(path: arguments.axBeforePath), with: singleImage == nil ? beforeAck : singleAck)
    let afterRecords = recordsReplacingPaneFrames(try parseAX(path: arguments.axAfterPath), with: afterAck)
    let representativeAck = singleImage == nil ? afterAck : singleAck
    let representativeRecords = recordsReplacingPaneFrames(singleImage == nil ? afterRecords : beforeRecords, with: representativeAck)
    let usedAckFallback = singleImage == nil
        ? (beforeAck?.endPaneFrames != nil || afterAck?.endPaneFrames != nil)
        : (singleAck?.endPaneFrames != nil)

    var checkedImages: [(label: String, image: PixelImage)] = []
    if let overviewImage {
        checkedImages.append(("overview", overviewImage))
    }
    if let beforeImage {
        checkedImages.append(("before", beforeImage))
    }
    if let afterImage {
        checkedImages.append(("after", afterImage))
    }
    if let singleImage {
        checkedImages.append(("single", singleImage))
    }

    var checks: [CheckResult] = []
    checks.append(checkVisibleContent(images: checkedImages, axRecords: representativeRecords))
    checks.append(checkInteractionChanged(beforeImage: beforeImage, afterImage: afterImage, beforeRecords: beforeRecords, afterRecords: afterRecords))
    checks.append(checkRequiredPaneVisibility(
        beforeRecords: beforeRecords,
        afterRecords: afterRecords,
        requireReaderPane: arguments.requireReaderPane,
        requireAgentPane: arguments.requireAgentPane
    ))
    checks.append(checkPaneWidths(beforeRecords: beforeRecords, afterRecords: afterRecords, usedAckFallback: usedAckFallback))
    checks.append(checkContentOverflow(records: representativeRecords, usedAckFallback: usedAckFallback))
    checks.append(checkInlineCanvasReadability(records: representativeRecords))

    let summary = aggregate(checks: checks)
    let output: [String: Any] = [
        "scope": "technical-layout-safety",
        "requiresHumanReview": true,
        "notChecked": [
            "审美统一",
            "学习有效性",
            "Canvas 内部文字碰撞",
        ],
        "status": summary.status.rawValue,
        "score": summary.score,
        "checks": checks.map(checkObject),
        "inputs": [
            "overview": arguments.overviewPath as Any,
            "before": arguments.beforePath as Any,
            "after": arguments.afterPath as Any,
            "overviewAck": ackSummary(overviewAck),
            "beforeAck": ackSummary(beforeAck),
            "afterAck": ackSummary(afterAck),
            "axBefore": arguments.axBeforePath as Any,
            "axAfter": arguments.axAfterPath as Any,
            "single": arguments.singlePath as Any,
            "singleAck": ackSummary(singleAck),
        ],
    ]
    try writeJSON(output, outputPath: arguments.outputPath!)
}

do {
    try run()
} catch {
    let output: [String: Any] = [
        "scope": "technical-layout-safety",
        "requiresHumanReview": true,
        "notChecked": [
            "审美统一",
            "学习有效性",
            "Canvas 内部文字碰撞",
        ],
        "status": GateStatus.fail.rawValue,
        "score": 0,
        "checks": [[
            "id": "visual-gate-runtime",
            "status": GateStatus.fail.rawValue,
            "score": 0,
            "summary": "\(error)",
            "metrics": [:],
        ]],
    ]
    if let outputIndex = CommandLine.arguments.firstIndex(of: "--output"),
       outputIndex + 1 < CommandLine.arguments.count {
        try? writeJSON(output, outputPath: CommandLine.arguments[outputIndex + 1])
    } else {
        let data = try? JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
        if let data {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }
    exit(1)
}
