import AppKit
import SwiftUI
import WeiBeiCore

extension GeneratedRichAnswerCanvas {
    func drawLabels(
        _ node: RichAnswerUINode,
        context: inout GraphicsContext,
        rect: CGRect,
        sharedOccupiedFrames: inout [CGRect]
    ) {
        guard let dataset = dataset(for: node) else { return }
        let occupiedFrames = labelObstacles(excluding: node.id, in: rect) + sharedOccupiedFrames
        if let bindingID = node.bindingID,
           let binding = binding(for: bindingID),
           let currentRow = interpolatedRow(in: dataset, binding: binding) {
            let point = canvasPoint(currentRow.x, currentRow.y, in: rect)
            let label = measuredCanvasLabel(
                id: currentRow.id,
                text: currentRow.label ?? formattedBindingValue(binding),
                point: point,
                node: node,
                selected: true,
                required: true,
                priority: 100,
                in: rect
            )
            let placements = placeCanvasLabels([label], in: rect, occupiedFrames: occupiedFrames)
            drawPlacedLabels(placements, context: &context)
            sharedOccupiedFrames.append(contentsOf: placements.map { $0.frame.insetBy(dx: -2, dy: -2) })
            return
        }
        let labelledRows = dataset.rows.filter { $0.label?.isEmpty == false }
        let horizontalRows = labelledRows.sorted { $0.x < $1.x }
        let endpointIDs = Set([horizontalRows.first?.id, horizontalRows.last?.id].compactMap(\.self))
        let activeID = activeRow(in: dataset, bindingID: node.bindingID)?.id
        let labels = labelledRows.map { row in
            let selected = runtime.selectedID == row.id || activeID == row.id
            let endpoint = endpointIDs.contains(row.id)
            return measuredCanvasLabel(
                id: row.id,
                text: row.label ?? "",
                point: canvasPoint(row.x, row.y, in: rect),
                node: node,
                selected: selected,
                required: selected || node.emphasis == .strong,
                priority: selected ? 100 : (node.emphasis == .strong ? 86 : (endpoint ? 62 : 40)),
                in: rect
            )
        }
        let placements = placeCanvasLabels(labels, in: rect, occupiedFrames: occupiedFrames)
        drawPlacedLabels(placements, context: &context)
        sharedOccupiedFrames.append(contentsOf: placements.map { $0.frame.insetBy(dx: -2, dy: -2) })
    }

    func drawPlacedLabels(_ placements: [GeneratedCanvasLabelPlacement], context: inout GraphicsContext) {
        for placement in placements {
            let label = placement.label
            context.draw(
                Text(label.text)
                    .font(.system(size: 9, weight: label.required ? .semibold : .medium))
                    .foregroundStyle(label.selected ? WeiBeiTheme.cinnabar : generatedToneColor(label.tone)),
                at: placement.drawPoint,
                anchor: placement.anchor.unitPoint
            )
        }
    }

    func measuredCanvasLabel(
        id: String,
        text: String,
        point: CGPoint,
        node: RichAnswerUINode,
        selected: Bool,
        required: Bool,
        priority: Int,
        in rect: CGRect
    ) -> GeneratedCanvasLabel {
        let maxWidth = min(132, max(42, rect.width * 0.42))
        let displayText = trimmedCanvasLabel(text, maxWidth: maxWidth)
        return GeneratedCanvasLabel(
            id: id,
            text: displayText,
            point: point,
            size: measuredCanvasLabelSize(displayText, maxWidth: maxWidth, required: required),
            tone: node.tone,
            selected: selected,
            required: required,
            priority: priority
        )
    }

    func placeCanvasLabels(
        _ labels: [GeneratedCanvasLabel],
        in rect: CGRect,
        occupiedFrames: [CGRect]
    ) -> [GeneratedCanvasLabelPlacement] {
        let allowedRect = rect.insetBy(dx: 3, dy: 3)
        let sortedLabels = labels.sorted {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            if $0.size.width != $1.size.width { return $0.size.width < $1.size.width }
            return $0.id < $1.id
        }
        let densityLimit = canvasLabelDensityLimit(for: sortedLabels, in: rect)
        var placements: [GeneratedCanvasLabelPlacement] = []
        var placedFrames = occupiedFrames
        var flexibleCount = 0
        for label in sortedLabels {
            if !label.required, flexibleCount >= densityLimit { continue }
            guard let placement = bestCanvasLabelPlacement(label, allowedRect: allowedRect, occupiedFrames: placedFrames) else { continue }
            if !label.required, placement.score > 86 { continue }
            placements.append(placement)
            placedFrames.append(placement.frame.insetBy(dx: -2, dy: -2))
            if !label.required {
                flexibleCount += 1
            }
        }
        return placements
    }

    func bestCanvasLabelPlacement(
        _ label: GeneratedCanvasLabel,
        allowedRect: CGRect,
        occupiedFrames: [CGRect]
    ) -> GeneratedCanvasLabelPlacement? {
        let placements = GeneratedCanvasLabelAnchor.allCases.map { anchor -> GeneratedCanvasLabelPlacement in
            let rawPoint = CGPoint(x: label.point.x + anchor.offset.width, y: label.point.y + anchor.offset.height)
            let rawFrame = anchor.frame(for: rawPoint, size: label.size)
            let constrainedFrame = constrainCanvasLabelFrame(rawFrame, to: allowedRect)
            let shift = distance(CGPoint(x: rawFrame.midX, y: rawFrame.midY), CGPoint(x: constrainedFrame.midX, y: constrainedFrame.midY))
            let ownMarker = CGRect(x: label.point.x - 5, y: label.point.y - 5, width: 10, height: 10)
            let overlap = occupiedFrames.reduce(CGFloat.zero) { partial, frame in
                partial + intersectionArea(constrainedFrame, frame)
            } + intersectionArea(constrainedFrame, ownMarker) * 1.8
            let score = overlap * 3.2 + shift * 1.6 + anchor.bias
            return GeneratedCanvasLabelPlacement(
                label: label,
                anchor: anchor,
                drawPoint: anchor.drawPoint(for: constrainedFrame),
                frame: constrainedFrame,
                score: score
            )
        }
        return placements.min { $0.score < $1.score }
    }

    func labelObstacles(excluding excludedID: String, in rect: CGRect) -> [CGRect] {
        var frames: [CGRect] = []
        for node in markNodes where node.id != excludedID && isVisible(node) {
            switch node.role {
            case .point, .dotMatrix, .label:
                guard let dataset = dataset(for: node) else { continue }
                for row in dataset.rows {
                    let point = canvasPoint(row.x, row.y, in: rect)
                    frames.append(CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10))
                }
            case .shape:
                frames.append(contentsOf: shapeInstances(for: node, rect: rect).map { $0.rect.insetBy(dx: -2, dy: -2) })
            case .bar:
                frames.append(contentsOf: barInstances(for: node, rect: rect).map { $0.rect.insetBy(dx: -1, dy: -1) })
            case .region:
                guard let region = node.region else { continue }
                let regionRect = CGRect(
                    x: rect.minX + rect.width * region.x,
                    y: rect.minY + rect.height * region.y,
                    width: rect.width * region.width,
                    height: rect.height * region.height
                )
                if let label = node.label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
                    let maxWidth = max(20, regionRect.width - 10)
                    let displayLabel = trimmedCanvasLabel(label, maxWidth: maxWidth)
                    let labelSize = measuredCanvasLabelSize(displayLabel, maxWidth: maxWidth, required: true)
                    frames.append(CGRect(
                        x: regionRect.minX + 5,
                        y: regionRect.minY + 4,
                        width: labelSize.width,
                        height: labelSize.height
                    ).insetBy(dx: -2, dy: -2))
                }
            case .vector:
                guard let dataset = dataset(for: node) else { continue }
                let rows = node.bindingID.flatMap { activeRow(in: dataset, bindingID: $0) }.map { [$0] } ?? dataset.rows
                for row in rows {
                    guard let x2 = row.x2, let y2 = row.y2 else { continue }
                    let start = canvasPoint(row.x, row.y, in: rect)
                    let end = canvasPoint(x2, y2, in: rect)
                    frames.append(CGRect(x: start.x - 4, y: start.y - 4, width: 8, height: 8))
                    frames.append(CGRect(x: end.x - 5, y: end.y - 5, width: 10, height: 10))
                }
            default:
                continue
            }
        }
        return frames
    }

    func canvasLabelDensityLimit(for labels: [GeneratedCanvasLabel], in rect: CGRect) -> Int {
        let flexibleCount = labels.filter { !$0.required }.count
        guard flexibleCount > 0 else { return 0 }
        let widthSlots = max(2, Int(rect.width / 68))
        let areaSlots = max(2, Int((rect.width * rect.height) / 5_400))
        let generousLimit = max(widthSlots, areaSlots)
        if rect.width < 320 || labels.count > generousLimit + 3 {
            return max(2, min(flexibleCount, generousLimit))
        }
        return flexibleCount
    }

}

struct GeneratedCanvasLabel {
    let id: String
    let text: String
    let point: CGPoint
    let size: CGSize
    let tone: RichAnswerUITone
    let selected: Bool
    let required: Bool
    let priority: Int
}

struct GeneratedCanvasLabelPlacement {
    let label: GeneratedCanvasLabel
    let anchor: GeneratedCanvasLabelAnchor
    let drawPoint: CGPoint
    let frame: CGRect
    let score: CGFloat
}

enum GeneratedCanvasLabelAnchor: CaseIterable {
    case upperRight
    case lowerRight
    case upperLeft
    case lowerLeft
    case upperCenter
    case lowerCenter
    case right
    case left

    var unitPoint: UnitPoint {
        switch self {
        case .upperRight:
            return .bottomLeading
        case .lowerRight:
            return .topLeading
        case .upperLeft:
            return .bottomTrailing
        case .lowerLeft:
            return .topTrailing
        case .upperCenter:
            return .bottom
        case .lowerCenter:
            return .top
        case .right:
            return .leading
        case .left:
            return .trailing
        }
    }

    var offset: CGSize {
        switch self {
        case .upperRight:
            return CGSize(width: 7, height: -6)
        case .lowerRight:
            return CGSize(width: 7, height: 6)
        case .upperLeft:
            return CGSize(width: -7, height: -6)
        case .lowerLeft:
            return CGSize(width: -7, height: 6)
        case .upperCenter:
            return CGSize(width: 0, height: -9)
        case .lowerCenter:
            return CGSize(width: 0, height: 9)
        case .right:
            return CGSize(width: 9, height: 0)
        case .left:
            return CGSize(width: -9, height: 0)
        }
    }

    var bias: CGFloat {
        switch self {
        case .upperRight:
            return 0
        case .lowerRight:
            return 3
        case .upperLeft:
            return 5
        case .lowerLeft:
            return 6
        case .upperCenter:
            return 8
        case .lowerCenter:
            return 9
        case .right:
            return 10
        case .left:
            return 11
        }
    }

    func frame(for point: CGPoint, size: CGSize) -> CGRect {
        switch self {
        case .upperRight:
            return CGRect(x: point.x, y: point.y - size.height, width: size.width, height: size.height)
        case .lowerRight:
            return CGRect(origin: point, size: size)
        case .upperLeft:
            return CGRect(x: point.x - size.width, y: point.y - size.height, width: size.width, height: size.height)
        case .lowerLeft:
            return CGRect(x: point.x - size.width, y: point.y, width: size.width, height: size.height)
        case .upperCenter:
            return CGRect(x: point.x - size.width / 2, y: point.y - size.height, width: size.width, height: size.height)
        case .lowerCenter:
            return CGRect(x: point.x - size.width / 2, y: point.y, width: size.width, height: size.height)
        case .right:
            return CGRect(x: point.x, y: point.y - size.height / 2, width: size.width, height: size.height)
        case .left:
            return CGRect(x: point.x - size.width, y: point.y - size.height / 2, width: size.width, height: size.height)
        }
    }

    func drawPoint(for frame: CGRect) -> CGPoint {
        switch self {
        case .upperRight:
            return CGPoint(x: frame.minX, y: frame.maxY)
        case .lowerRight:
            return CGPoint(x: frame.minX, y: frame.minY)
        case .upperLeft:
            return CGPoint(x: frame.maxX, y: frame.maxY)
        case .lowerLeft:
            return CGPoint(x: frame.maxX, y: frame.minY)
        case .upperCenter:
            return CGPoint(x: frame.midX, y: frame.maxY)
        case .lowerCenter:
            return CGPoint(x: frame.midX, y: frame.minY)
        case .right:
            return CGPoint(x: frame.minX, y: frame.midY)
        case .left:
            return CGPoint(x: frame.maxX, y: frame.midY)
        }
    }
}

func measuredCanvasLabelSize(_ text: String, maxWidth: CGFloat, required: Bool) -> CGSize {
    let font = NSFont.systemFont(ofSize: 9, weight: required ? .semibold : .medium)
    let size = (text as NSString).size(withAttributes: [.font: font])
    return CGSize(width: min(maxWidth, ceil(size.width)), height: ceil(size.height) + 1)
}

func trimmedCanvasLabel(_ text: String, maxWidth: CGFloat) -> String {
    let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let maxCharacters = max(4, Int(maxWidth / 7.2))
    guard cleanText.count > maxCharacters else { return cleanText }
    for separator in ["：", "（", "(", "；", ";"] {
        guard let range = cleanText.range(of: separator) else { continue }
        let semanticPrefix = cleanText[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        if semanticPrefix.count >= 4, semanticPrefix.count <= maxCharacters {
            return semanticPrefix
        }
    }
    return String(cleanText.prefix(max(1, maxCharacters - 1))) + "…"
}

func generatedBarRangeLabel(_ firstLabel: String?, _ lastLabel: String?) -> String? {
    guard let firstLabel = firstLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
          !firstLabel.isEmpty else { return lastLabel }
    guard let lastLabel = lastLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
          !lastLabel.isEmpty else { return firstLabel }
    func prefix(_ label: String) -> String {
        for separator in ["：", ":"] {
            if let range = label.range(of: separator) {
                return String(label[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return label
    }
    let first = prefix(firstLabel)
    let last = prefix(lastLabel)
    guard first != last else { return first }
    return "\(first)–\(last)"
}

func constrainCanvasLabelFrame(_ frame: CGRect, to allowedRect: CGRect) -> CGRect {
    GeneratedCanvasLayout.constrain(frame, to: allowedRect)
}

func intersectionArea(_ first: CGRect, _ second: CGRect) -> CGFloat {
    GeneratedCanvasLayout.intersectionArea(first, second)
}

