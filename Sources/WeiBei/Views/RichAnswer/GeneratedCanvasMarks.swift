import AppKit
import SwiftUI
import WeiBeiCore

extension GeneratedRichAnswerCanvas {
    func drawShapes(
        _ node: RichAnswerUINode,
        context: inout GraphicsContext,
        rect: CGRect,
        includeLabels: Bool
    ) {
        guard let shape = node.shape else { return }
        for instance in shapeInstances(for: node, rect: rect) {
            let selected = runtime.selectedID == instance.id || runtime.selectedID == node.id
            let path = generatedShapePath(shape, in: instance.rect)
            drawFilledMark(path, node: node, selected: selected, defaultFill: .soft, context: &context)
            if includeLabels {
                drawShapeLabel(instance: instance, node: node, selected: selected, context: &context)
            }
        }
    }

    func drawShapeLabels(_ node: RichAnswerUINode, context: inout GraphicsContext, rect: CGRect) {
        guard node.shape != nil else { return }
        for instance in shapeInstances(for: node, rect: rect) {
            let selected = runtime.selectedID == instance.id || runtime.selectedID == node.id
            drawShapeLabel(instance: instance, node: node, selected: selected, context: &context)
        }
    }

    func drawShapeLabel(
        instance: GeneratedCanvasMarkInstance,
        node: RichAnswerUINode,
        selected: Bool,
        context: inout GraphicsContext
    ) {
        guard let label = instance.label, !label.isEmpty else { return }
        let maxWidth = max(14, instance.rect.width - 7)
        guard selected || node.emphasis == .strong || maxWidth >= 22 else { return }
        let displayLabel = trimmedCanvasLabel(label, maxWidth: maxWidth)
        context.draw(
            Text(displayLabel)
                .font(.system(size: node.size == .compact ? 8.2 : 9.2, weight: .semibold))
                .foregroundStyle(node.fill == .solid ? WeiBeiTheme.onCinnabar : generatedToneColor(node.tone)),
            at: CGPoint(x: instance.rect.midX, y: instance.rect.midY),
            anchor: .center
        )
    }

    func drawBars(
        _ node: RichAnswerUINode,
        context: inout GraphicsContext,
        rect: CGRect,
        includeLabels: Bool
    ) {
        guard let dataset = dataset(for: node) else { return }
        let activeID = continuousActiveRowID(in: dataset, bindingID: node.bindingID)
        for instance in barInstances(for: node, rect: rect) {
            let selected = runtime.selectedID == instance.id || activeID == instance.id
            let path = Path(roundedRect: instance.rect, cornerRadius: min(5, instance.rect.width * 0.18))
            drawFilledMark(path, node: node, selected: selected, defaultFill: .solid, context: &context)
            if includeLabels {
                drawBarLabel(instance: instance, node: node, selected: selected, rect: rect, context: &context)
            }
        }
    }

    func drawBarLabels(_ node: RichAnswerUINode, context: inout GraphicsContext, rect: CGRect) {
        guard let dataset = dataset(for: node) else { return }
        let activeID = continuousActiveRowID(in: dataset, bindingID: node.bindingID)
        let instances = barInstances(for: node, rect: rect).sorted { $0.rect.midX < $1.rect.midX }
        let minimumSeparation = max(38, min(64, rect.width / CGFloat(max(4, instances.count + 1))))
        var groups: [[GeneratedCanvasMarkInstance]] = []
        for instance in instances {
            if let last = groups.last?.last,
               instance.rect.midX - last.rect.midX < minimumSeparation {
                groups[groups.count - 1].append(instance)
            } else {
                groups.append([instance])
            }
        }
        for group in groups {
            guard let first = group.first, let last = group.last else { continue }
            let selected = group.contains { runtime.selectedID == $0.id || activeID == $0.id }
            if group.count == 1 {
                drawBarLabel(instance: first, node: node, selected: selected, rect: rect, context: &context)
                continue
            }
            let cluster = GeneratedCanvasMarkInstance(
                id: "\(first.id)-\(last.id)-label-cluster",
                rect: CGRect(
                    x: first.rect.minX,
                    y: min(first.rect.minY, last.rect.minY),
                    width: max(1, last.rect.maxX - first.rect.minX),
                    height: max(first.rect.height, last.rect.height)
                ),
                label: generatedBarRangeLabel(first.label, last.label)
            )
            drawBarLabel(instance: cluster, node: node, selected: selected, rect: rect, context: &context)
        }
    }

    func drawBarLabel(
        instance: GeneratedCanvasMarkInstance,
        node: RichAnswerUINode,
        selected: Bool,
        rect: CGRect,
        context: inout GraphicsContext
    ) {
        guard let label = instance.label, !label.isEmpty else { return }
        let maxWidth = max(18, min(74, rect.width / 6))
        let displayLabel = trimmedCanvasLabel(label, maxWidth: maxWidth)
        let labelSize = measuredCanvasLabelSize(displayLabel, maxWidth: maxWidth, required: selected)
        let labelCenterX = min(
            rect.maxX - labelSize.width / 2,
            max(rect.minX + labelSize.width / 2, instance.rect.midX)
        )
        context.draw(
            Text(displayLabel)
                .font(.system(size: 8.3, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? WeiBeiTheme.cinnabar : WeiBeiTheme.tertiaryInk),
            at: CGPoint(x: labelCenterX, y: rect.maxY + 7),
            anchor: .top
        )
    }

    func drawDotMatrix(_ node: RichAnswerUINode, context: inout GraphicsContext, rect: CGRect) {
        guard let dataset = dataset(for: node) else { return }
        let activeID = activeRow(in: dataset, bindingID: node.bindingID)?.id
        let radius: CGFloat
        switch node.size {
        case .compact:
            radius = 3.8
        case .regular:
            radius = 5.4
        case .large:
            radius = 7.2
        }
        for row in dataset.rows {
            let point = canvasPoint(row.x, row.y, in: rect)
            let selected = runtime.selectedID == row.id || activeID == row.id
            let path = Path(ellipseIn: CGRect(
                x: point.x - radius,
                y: point.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            drawFilledMark(path, node: node, selected: selected, defaultFill: .solid, context: &context)
        }
    }

    func drawFilledMark(
        _ path: Path,
        node: RichAnswerUINode,
        selected: Bool,
        defaultFill: RichAnswerUIFill,
        context: inout GraphicsContext
    ) {
        let color = generatedToneColor(node.tone)
        let fillColor = selected ? WeiBeiTheme.cinnabar : color
        switch node.fill ?? defaultFill {
        case .outline:
            break
        case .soft:
            context.fill(path, with: .color(fillColor.opacity(selected ? 0.24 : 0.13)))
        case .solid:
            context.fill(path, with: .color(fillColor.opacity(selected ? 0.96 : 0.78)))
        }
        context.stroke(
            path,
            with: .color(selected ? WeiBeiTheme.cinnabar : color.opacity(node.fill == .solid ? 0.94 : 0.68)),
            lineWidth: selected ? 2.2 : (node.emphasis == .strong ? 1.8 : 1.2)
        )
    }

    func drawVectors(_ node: RichAnswerUINode, context: inout GraphicsContext, rect: CGRect) {
        guard let dataset = dataset(for: node) else { return }
        let rows = node.bindingID.flatMap { activeRow(in: dataset, bindingID: $0) }.map { [$0] } ?? dataset.rows
        for row in rows {
            guard let x2 = row.x2, let y2 = row.y2 else { continue }
            let start = canvasPoint(row.x, row.y, in: rect)
            let end = canvasPoint(x2, y2, in: rect)
            let color = generatedToneColor(node.tone)
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(path, with: .color(color.opacity(0.84)), lineWidth: node.emphasis == .strong ? 2.2 : 1.5)
            drawArrowHead(context: &context, start: start, end: end, color: color)
        }
    }

    func drawRegion(
        _ node: RichAnswerUINode,
        context: inout GraphicsContext,
        rect: CGRect,
        includeLabel: Bool
    ) {
        guard let region = node.region else { return }
        let regionRect = CGRect(
            x: rect.minX + rect.width * region.x,
            y: rect.minY + rect.height * region.y,
            width: rect.width * region.width,
            height: rect.height * region.height
        )
        let selected = runtime.selectedID == node.id
        context.fill(
            Path(roundedRect: regionRect, cornerRadius: 4),
            with: .color(generatedToneColor(node.tone).opacity(selected ? 0.18 : 0.08))
        )
        context.stroke(
            Path(roundedRect: regionRect, cornerRadius: 4),
            with: .color(selected ? WeiBeiTheme.cinnabar : generatedToneColor(node.tone).opacity(0.66)),
            style: StrokeStyle(lineWidth: selected ? 1.8 : 1, dash: selected ? [] : [5, 4])
        )
        if includeLabel, let label = node.label {
            let maxWidth = max(20, regionRect.width - 10)
            guard selected || node.emphasis == .strong || maxWidth >= 36 else { return }
            let displayLabel = trimmedCanvasLabel(label, maxWidth: maxWidth)
            context.draw(
                Text(displayLabel)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(selected ? WeiBeiTheme.cinnabar : generatedToneColor(node.tone)),
                at: CGPoint(x: regionRect.minX + 5, y: regionRect.minY + 4),
                anchor: .topLeading
            )
        }
    }

}
