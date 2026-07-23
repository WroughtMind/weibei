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
    var actionReceiptPath: String?
    var caseID: String?
    var caseKind: String?
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

struct VerifiedActionReceipt {
    let path: String
    let source: String
    let kind: String
    let sceneID: String
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
        case "--action-receipt":
            arguments.actionReceiptPath = value
        case "--case-id":
            arguments.caseID = value
        case "--case-kind":
            arguments.caseKind = value
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

func loadVerifiedActionReceipt(
    path: String?,
    expectedCaseID: String?,
    expectedCaseKind: String?
) throws -> VerifiedActionReceipt? {
    guard let path else { return nil }
    let receiptURL = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: receiptURL.path) else {
        throw GateError(description: "Interaction receipt does not exist: \(path)")
    }
    let data = try Data(contentsOf: receiptURL)
    guard let receipt = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          (receipt["schemaVersion"] as? NSNumber)?.intValue == 1,
          receipt["stage"] as? String == "after",
          receipt["changed"] as? Bool == true,
          let source = receipt["source"] as? String,
          !source.isEmpty,
          let kind = receipt["kind"] as? String,
          !kind.isEmpty,
          let scene = receipt["scene"] as? [String: Any],
          let sceneID = scene["id"] as? String,
          !sceneID.isEmpty,
          let receiptCase = receipt["case"] as? [String: Any],
          let before = receipt["before"],
          let after = receipt["after"],
          JSONSerialization.isValidJSONObject(["value": before]),
          JSONSerialization.isValidJSONObject(["value": after]),
          try JSONSerialization.data(withJSONObject: ["value": before], options: [.sortedKeys])
            != JSONSerialization.data(withJSONObject: ["value": after], options: [.sortedKeys]) else {
        throw GateError(description: "Interaction receipt is invalid or unchanged: \(path)")
    }
    if let expectedCaseID, !expectedCaseID.isEmpty,
       receiptCase["id"] as? String != expectedCaseID {
        throw GateError(description: "Interaction receipt case id does not match: \(path)")
    }
    if let expectedCaseKind, !expectedCaseKind.isEmpty,
       receiptCase["kind"] as? String != expectedCaseKind {
        throw GateError(description: "Interaction receipt case kind does not match: \(path)")
    }
    return VerifiedActionReceipt(path: path, source: source, kind: kind, sceneID: sceneID)
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

func recordsAppendingPaneFrames(_ records: [RectRecord], with ack: VerifiedCaptureAck?) -> [RectRecord] {
    guard let frames = ack?.endPaneFrames else { return records }
    var merged = records
    let existing = paneRecords(records: records)
    if existing.reader == nil {
        merged.append(paneRecord(identifier: "stable-document-slot-reader", stage: ack?.stage ?? "", frame: frames.reader))
    }
    if existing.agent == nil {
        merged.append(paneRecord(identifier: "stable-document-slot-agent", stage: ack?.stage ?? "", frame: frames.agent))
    }
    return merged
}

func usesAcknowledgementPaneFallback(records: [RectRecord], ack: VerifiedCaptureAck?) -> Bool {
    guard ack?.endPaneFrames != nil else { return false }
    let panes = paneRecords(records: records)
    return panes.reader == nil || panes.agent == nil
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
    let pattern = #"(?m)^(?:[A-Za-z][A-Za-z0-9]* )?role=([^\n]*?) id=([^\n]*?) title=([^\n]*?) desc=([^\n]*?) value=((?:(?!\n(?:[A-Za-z][A-Za-z0-9]* )?role=)[\s\S])*?) frame=(-?\d+),(-?\d+),(-?\d+),(-?\d+)"#
    let expression = try NSRegularExpression(
        pattern: pattern,
        options: [.anchorsMatchLines]
    )
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

func paneIsHiddenByVisibleAction(toggle: RectRecord, visibleActionLabels: [String]) -> Bool {
    let description = toggle.desc.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return visibleActionLabels.contains { description.contains($0.lowercased()) }
}

func frameObject(_ frame: CGRect) -> [String: Any] {
    [
        "x": roundValue(frame.minX),
        "y": roundValue(frame.minY),
        "width": roundValue(frame.width),
        "height": roundValue(frame.height),
        "area": roundValue(frame.width * frame.height),
    ]
}

func structuredFailure(stage: String, category: String, reason: String, details: [String: Any] = [:]) -> [String: Any] {
    var object: [String: Any] = [
        "stage": stage,
        "category": category,
        "reason": reason,
    ]
    for (key, value) in details {
        object[key] = value
    }
    return object
}

func checkSourceGroundedRichInteractionEvidence(
    beforeRecords: [RectRecord],
    afterRecords: [RectRecord]
) -> CheckResult {
    var failures: [[String: Any]] = []
    var stageMetrics: [[String: Any]] = []

    for stage in [("before", beforeRecords), ("after", afterRecords)] {
        let records = stage.1
        let panes = paneRecords(records: records)
        let usesApplicationAcknowledgement = [panes.reader, panes.agent]
            .compactMap { $0 }
            .contains { $0.role == "AppCapturePane" }
        var paneMetrics: [[String: Any]] = []

        if records.isEmpty {
            failures.append(structuredFailure(
                stage: stage.0,
                category: "ax-empty",
                reason: "\(stage.0) AX 快照为空，不能把富回答真实显示判为通过"
            ))
        }

        for pane in [("reader", panes.reader), ("agent", panes.agent)] {
            if let record = pane.1 {
                paneMetrics.append([
                    "pane": pane.0,
                    "identifier": record.identifier,
                    "frame": frameObject(record.frame),
                ])
            } else {
                failures.append(structuredFailure(
                    stage: stage.0,
                    category: "pane-missing",
                    reason: "\(stage.0) 缺少 \(pane.0) 正面积窗格",
                    details: ["pane": pane.0]
                ))
            }
        }

        if let readerToggle = paneToggleRecord(records: records, identifier: "doc.text"),
           paneIsHiddenByVisibleAction(toggle: readerToggle, visibleActionLabels: ["显示文稿", "show document"]) {
            failures.append(structuredFailure(
                stage: stage.0,
                category: "reader-hidden",
                reason: "\(stage.0) reader 开关显示“显示文稿/Show document”，说明 reader 已隐藏",
                details: [
                    "pane": "reader",
                    "toggleIdentifier": readerToggle.identifier,
                    "toggleDescription": readerToggle.desc,
                    "toggleFrame": frameObject(readerToggle.frame),
                ]
            ))
        }

        stageMetrics.append([
            "stage": stage.0,
            "recordCount": records.count,
            "paneEvidenceSource": usesApplicationAcknowledgement ? "application-ack" : "accessibility",
            "panes": paneMetrics,
            "readerToggleDescription": paneToggleRecord(records: records, identifier: "doc.text")?.desc ?? "",
        ])
    }

    let status: GateStatus = failures.isEmpty ? .pass : .fail
    return CheckResult(
        id: "source-grounded-rich-interaction-evidence",
        status: status,
        score: status == .pass ? 20 : 0,
        summary: failures.first?["reason"] as? String ?? "source-grounded 富回答 before/after AX、reader 与 agent 窗格证据完整",
        metrics: [
            "mode": "rich-interaction",
            "evidencePolicy": "accessibility-first-with-verified-application-ack-fallback",
            "failures": failures,
            "stages": stageMetrics,
        ]
    )
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
            let applicationAcknowledgementOnly = !stage.1.isEmpty
                && stage.1.allSatisfy { $0.role == "AppCapturePane" }
            let acknowledgedPane = paneRecords(records: stage.1)
            let acknowledgedRecord = requirement.name == "reader"
                ? acknowledgedPane.reader
                : acknowledgedPane.agent
            guard let toggle = paneToggleRecord(records: stage.1, identifier: requirement.identifier) else {
                if applicationAcknowledgementOnly,
                   let acknowledgedRecord,
                   acknowledgedRecord.role == "AppCapturePane" {
                    observations.append([
                        "stage": stage.0,
                        "pane": requirement.name,
                        "toggleIdentifier": requirement.identifier,
                        "toggleDescription": "",
                        "visible": true,
                        "evidencePresent": true,
                        "evidenceSource": "application-ack",
                    ])
                    continue
                }
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

func checkInteractionChanged(
    beforeImage: PixelImage?,
    afterImage: PixelImage?,
    beforeRecords: [RectRecord],
    afterRecords: [RectRecord],
    actionReceipt: VerifiedActionReceipt?,
    isSingleMode: Bool = false
) -> CheckResult {
    if isSingleMode {
        return CheckResult(
            id: "interaction-changed",
            status: .pass,
            score: 20,
            summary: "单张证据为降级场景，不要求前后交互变化",
            metrics: [
                "mode": "single",
                "interactionChangeRequired": false,
            ]
        )
    }
    guard let beforeImage, let afterImage else {
        return CheckResult(id: "interaction-changed", status: .warn, score: 10, summary: "single 模式未检查交互前后变化", metrics: ["mode": "single"])
    }
    let metrics = sampleMetrics(image: afterImage, comparedWith: beforeImage)
    let changedKeys = changedControlKeys(beforeRecords: beforeRecords, afterRecords: afterRecords)
    let changedFraction = metrics.changedFraction ?? 0
    let meanDifference = metrics.meanDifference ?? 0
    let imageChanged = changedFraction >= 0.0015 || meanDifference >= 0.35
    let axChanged = !changedKeys.isEmpty
    let receiptChanged = actionReceipt != nil
    let status: GateStatus
    let summary: String
    let score: Int
    if imageChanged || axChanged || receiptChanged {
        status = imageChanged || receiptChanged ? .pass : .warn
        if imageChanged {
            summary = "交互前后截图有可见变化"
        } else if receiptChanged {
            summary = "应用交互回执已证明控件状态真实变化；截图和 AX 变化较小，保留作诊断"
        } else {
            summary = "AX 控件值已变化，但截图变化很小，可能需要复核捕获链路"
        }
        score = imageChanged || receiptChanged ? 20 : 13
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
            "applicationReceiptChanged": receiptChanged,
            "applicationReceipt": actionReceipt.map {
                [
                    "path": $0.path,
                    "source": $0.source,
                    "kind": $0.kind,
                    "sceneID": $0.sceneID,
                ]
            } as Any,
        ]
    )
}

func checkPaneWidths(beforeRecords: [RectRecord], afterRecords: [RectRecord], usedAckFallback: Bool, isSingleMode: Bool = false) -> CheckResult {
    if isSingleMode {
        return CheckResult(
            id: "pane-width-stability",
            status: .pass,
            score: 20,
            summary: "单张证据为降级/纯文本场景，不要求双栏宽度稳定性",
            metrics: [
                "mode": "single",
                "requirePaneWidthStability": false,
            ]
        )
    }
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

func normalizedAXValue(_ text: String) -> String {
    let filtered = String(text.unicodeScalars.filter { scalar in
        !CharacterSet.whitespacesAndNewlines.contains(scalar)
            && !CharacterSet.punctuationCharacters.contains(scalar)
            && !CharacterSet.symbols.contains(scalar)
    })
    return filtered.lowercased()
}

func isReadableRichAnswerValue(_ value: String) -> Bool {
    let normalized = normalizedAXValue(value).trimmingCharacters(in: .whitespacesAndNewlines)
    if normalized.isEmpty {
        return false
    }
    if ["结论", "conclusion", "总结", "summary", "none", "n/a", "na", "null", "nil", "empty", "暂无", "待补充", "无", "未设置"].contains(normalized) {
        return false
    }
    if normalized.count < 4 {
        return false
    }
    return true
}

func isSingleModeTextRole(_ role: String) -> Bool {
    let readableRoles: Set<String> = ["AXText", "AXStaticText", "AXTextField", "AXList", "AXListItem"]
    return readableRoles.contains(role) || role.hasPrefix("AXList")
}

func isPlaceholderText(_ text: String) -> Bool {
    let normalized = normalizedAXValue(text).trimmingCharacters(in: .whitespacesAndNewlines)
    if normalized.isEmpty || normalized.count < 2 {
        return true
    }
    if ["结论", "conclusion", "总结", "summary", "none", "n/a", "na", "null", "nil", "empty", "暂无", "待补充", "无", "未设置", "请输入", "请输入问题", "输入问题", "请提问", "placeholder", "占位", "待补齐"].contains(normalized) {
        return true
    }
    return false
}

func isSingleModeIgnoredTextRecord(_ record: RectRecord) -> Bool {
    let lowerIdentifier = record.identifier.lowercased()
    let lowerTitle = record.title.lowercased()
    let lowerDescription = record.desc.lowercased()
    let haystacks = [lowerIdentifier, lowerTitle, lowerDescription]
    let ignoredTokens: [String] = [
        "doc.text",
        "bubble.left.and.text.bubble.right",
        "button",
        "textfield",
        "text-field",
        "chat-input",
        "chat_input",
        "text input",
        "input",
        "prompt",
        "search",
        "history",
        "历史记录",
        "输入框",
        "请输入",
        "请提问",
        "placeholder",
        "占位",
    ]
    return ignoredTokens.contains { token in
        haystacks.contains(where: { $0.contains(token) })
    }
}

func isReadableSingleModeTextRecord(_ record: RectRecord) -> Bool {
    if !isSingleModeTextRole(record.role) {
        return false
    }
    if isPlaceholderText(record.value) {
        return false
    }
    if isSingleModeIgnoredTextRecord(record) {
        return false
    }
    return record.frame.width > 0 && record.frame.height > 0
}

func isFrameInside(_ inner: CGRect, in outer: CGRect) -> Bool {
    return outer.minX <= inner.minX
        && outer.maxX >= inner.maxX
        && outer.minY <= inner.minY
        && outer.maxY >= inner.maxY
}

func frameOverlaps(_ inner: CGRect, in outer: CGRect) -> Bool {
    return inner.minX < outer.maxX
        && inner.maxX > outer.minX
        && inner.minY < outer.maxY
        && inner.maxY > outer.minY
}

func singleModeAnswerContainers(records: [RectRecord], agentPane: CGRect) -> [CGRect] {
    records.compactMap { record in
        guard record.role == "AXWebArea",
              record.frame.width > 0,
              record.frame.height > 0,
              frameOverlaps(record.frame, in: agentPane) else {
            return nil
        }
        return record.frame
    }
}

func singleModeReadableTextRecords(
    records: [RectRecord],
    agentPane: CGRect,
    answerContainers: [CGRect]
) -> [RectRecord] {
    return records.filter { record in
        isReadableSingleModeTextRecord(record)
            && frameOverlaps(record.frame, in: agentPane)
            && answerContainers.contains { frameOverlaps(record.frame, in: $0) }
    }
}

func countReadableSingleModeTextRecords(
    records: [RectRecord],
    agentPane: CGRect,
    answerContainers: [CGRect]
) -> Int {
    records.filter { record in
        isReadableSingleModeTextRecord(record)
            && isFrameInside(record.frame, in: agentPane)
            && answerContainers.contains { isFrameInside(record.frame, in: $0) }
    }.count
}

func checkContentOverflow(records: [RectRecord], usedAckFallback: Bool, isSingleMode: Bool = false) -> CheckResult {
    let panes = paneRecords(records: records)
    guard let agentPaneRecord = panes.agent else {
        return CheckResult(
            id: "content-overflow",
            status: isSingleMode ? .fail : .warn,
            score: isSingleMode ? 0 : 11,
            summary: "\(isSingleMode ? "single 模式" : "当前") 缺少 Agent 窗格 frame，无法判断内容越界",
            metrics: [
                "mode": isSingleMode ? "single" : "rich",
                "recordCount": records.count,
                "agentPanePresent": false,
            ]
        )
    }
    let agentPaneFrame = agentPaneRecord.frame
    let richRecords = richContentRecords(records: records)
    let answerContainers = isSingleMode
        ? singleModeAnswerContainers(records: records, agentPane: agentPaneFrame)
        : []
    if isSingleMode {
        let readableTextCount = countReadableSingleModeTextRecords(
            records: records,
            agentPane: agentPaneFrame,
            answerContainers: answerContainers
        )
        if answerContainers.isEmpty || readableTextCount == 0 {
            return CheckResult(
                id: "content-overflow",
                status: .fail,
                score: 0,
                summary: answerContainers.isEmpty
                    ? "single 模式未检测到 Agent 回复容器"
                    : "single 模式未检测到回复容器内的可读正文",
                metrics: [
                    "mode": "single",
                    "recordCount": records.count,
                    "agentPane": [
                        "x": roundValue(agentPaneFrame.minX),
                        "y": roundValue(agentPaneFrame.minY),
                        "width": roundValue(agentPaneFrame.width),
                        "height": roundValue(agentPaneFrame.height),
                    ],
                    "answerContainerCount": answerContainers.count,
                    "readableTextRecordCount": readableTextCount,
                ]
            )
        }
    } else if richRecords.isEmpty {
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

    let checkedRecords = isSingleMode
        ? singleModeReadableTextRecords(
            records: records,
            agentPane: agentPaneFrame,
            answerContainers: answerContainers
        )
        : richRecords
    var failures: [[String: Any]] = []
    var warnings: [[String: Any]] = []
    for record in checkedRecords {
        let leftOverflow = max(0.0, agentPaneFrame.minX - record.frame.minX)
        let rightOverflow = max(0.0, record.frame.maxX - agentPaneFrame.maxX)
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
        if horizontalOverflow >= contentOverflowFailTolerance || record.frame.width > agentPaneFrame.width + 40 {
            failures.append(recordObject)
        } else if horizontalOverflow >= contentOverflowWarnTolerance || record.frame.width > agentPaneFrame.width + 18 {
            warnings.append(recordObject)
        }
    }

    let status: GateStatus = failures.isEmpty ? (warnings.isEmpty ? .pass : .warn) : .fail
    return CheckResult(
        id: "content-overflow",
        status: status,
        score: status == .fail ? 0 : (status == .warn ? 13 : 20),
        summary: failures.first.map { isSingleMode
            ? "单张证据正文内容明显横向越界：\($0["id"] ?? "")"
            : "发现富回答内容明显横向越界：\($0["id"] ?? "")"
        }
            ?? warnings.first.map { isSingleMode
                ? "单张证据正文内容接近横向边界：\($0["id"] ?? "")"
                : "发现富回答内容接近横向边界：\($0["id"] ?? "")"
            }
            ?? (isSingleMode ? "单张证据正文内容在窗格内" : "富回答内容没有明显横向越界"),
        metrics: [
            "agentPane": [
                "x": roundValue(agentPaneFrame.minX),
                "y": roundValue(agentPaneFrame.minY),
                "width": roundValue(agentPaneFrame.width),
                "height": roundValue(agentPaneFrame.height),
            ],
            "recordCount": checkedRecords.count,
            "answerContainerCount": answerContainers.count,
            "failures": failures,
            "warnings": warnings,
            "warnTolerance": Int(contentOverflowWarnTolerance),
            "failTolerance": Int(contentOverflowFailTolerance),
            "mode": isSingleMode ? "single" : "rich",
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
    let actionReceipt = try loadVerifiedActionReceipt(
        path: arguments.actionReceiptPath,
        expectedCaseID: arguments.caseID,
        expectedCaseKind: arguments.caseKind
    )
    let rawBeforeRecords = try parseAX(path: arguments.axBeforePath)
    let rawAfterRecords = try parseAX(path: arguments.axAfterPath)
    let beforeRecords = recordsAppendingPaneFrames(rawBeforeRecords, with: singleImage == nil ? beforeAck : singleAck)
    let afterRecords: [RectRecord] = {
        if singleImage != nil {
            return beforeRecords
        }
        return recordsAppendingPaneFrames(rawAfterRecords, with: afterAck)
    }()
    let representativeAck = singleImage == nil ? afterAck : singleAck
    let representativeRecords = recordsAppendingPaneFrames(singleImage == nil ? afterRecords : beforeRecords, with: representativeAck)
    let usedAckFallback = singleImage == nil
        ? (usesAcknowledgementPaneFallback(records: rawBeforeRecords, ack: beforeAck)
            || usesAcknowledgementPaneFallback(records: rawAfterRecords, ack: afterAck))
        : usesAcknowledgementPaneFallback(records: rawBeforeRecords, ack: singleAck)
    let sourceBeforeRecords = rawBeforeRecords.isEmpty ? beforeRecords : rawBeforeRecords
    let sourceAfterRecords = rawAfterRecords.isEmpty ? afterRecords : rawAfterRecords

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
    let isSingleMode = (singleImage != nil)
    if singleImage == nil {
        checks.append(checkSourceGroundedRichInteractionEvidence(
            beforeRecords: sourceBeforeRecords,
            afterRecords: sourceAfterRecords
        ))
    }
    checks.append(checkVisibleContent(images: checkedImages, axRecords: representativeRecords))
    checks.append(checkInteractionChanged(
        beforeImage: beforeImage,
        afterImage: afterImage,
        beforeRecords: beforeRecords,
        afterRecords: afterRecords,
        actionReceipt: actionReceipt,
        isSingleMode: isSingleMode
    ))
    checks.append(checkRequiredPaneVisibility(
        beforeRecords: beforeRecords,
        afterRecords: afterRecords,
        requireReaderPane: arguments.requireReaderPane,
        requireAgentPane: arguments.requireAgentPane
    ))
    checks.append(checkPaneWidths(
        beforeRecords: beforeRecords,
        afterRecords: afterRecords,
        usedAckFallback: usedAckFallback,
        isSingleMode: isSingleMode
    ))
    checks.append(checkContentOverflow(
        records: representativeRecords,
        usedAckFallback: usedAckFallback,
        isSingleMode: isSingleMode
    ))
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
            "actionReceipt": actionReceipt.map {
                [
                    "path": $0.path,
                    "source": $0.source,
                    "kind": $0.kind,
                    "sceneID": $0.sceneID,
                ]
            } as Any,
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
