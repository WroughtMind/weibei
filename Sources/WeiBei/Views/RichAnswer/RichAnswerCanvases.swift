import AppKit
import SwiftUI
import WeiBeiCore

struct RelationMapCanvas: View {
    let scene: RichAnswerScene
    @Binding var focusedRelationID: String?

    var body: some View {
        GeometryReader { geometry in
            let positions = nodePositions(in: geometry.size)
            ZStack {
                RelationMapEdges(
                    relations: scene.relations,
                    positions: positions,
                    focusedRelationID: focusedRelationID
                )

                ForEach(visibleObjects, id: \.id) { object in
                    if let point = positions[object.id] {
                        RelationMapNode(
                            object: object,
                            focused: isFocused(object)
                        ) {
                            focusedRelationID = relationID(touching: object.id)
                        }
                        .position(point)
                    }
                }
            }
        }
    }

    private var visibleObjects: [RichAnswerObject] {
        let referencedIDs = Set(scene.relations.flatMap { [$0.sourceID, $0.targetID] })
        return Array(scene.objects.filter { referencedIDs.contains($0.id) }.prefix(9))
    }

    private func isFocused(_ object: RichAnswerObject) -> Bool {
        guard let focusedRelationID,
              let relation = scene.relations.first(where: { $0.id == focusedRelationID }) else {
            return true
        }
        return relation.sourceID == object.id || relation.targetID == object.id
    }

    private func relationID(touching objectID: String) -> String? {
        scene.relations.first {
            $0.sourceID == objectID || $0.targetID == objectID
        }?.id
    }

    private func nodePositions(in size: CGSize) -> [String: CGPoint] {
        let sourceIDs = Set(scene.relations.map(\.sourceID))
        let targetIDs = Set(scene.relations.map(\.targetID))
        var left = visibleObjects.filter { sourceIDs.contains($0.id) && !targetIDs.contains($0.id) }
        var middle = visibleObjects.filter { sourceIDs.contains($0.id) && targetIDs.contains($0.id) }
        var right = visibleObjects.filter { targetIDs.contains($0.id) && !sourceIDs.contains($0.id) }
        let assigned = Set((left + middle + right).map(\.id))
        middle.append(contentsOf: visibleObjects.filter { !assigned.contains($0.id) })
        if left.isEmpty, !middle.isEmpty {
            left.append(middle.removeFirst())
        }
        if right.isEmpty, !middle.isEmpty {
            right.append(middle.removeLast())
        }

        var result: [String: CGPoint] = [:]
        add(left, x: size.width * 0.16, size: size, to: &result)
        add(middle, x: size.width * 0.50, size: size, to: &result)
        add(right, x: size.width * 0.84, size: size, to: &result)
        return result
    }

    private func add(
        _ objects: [RichAnswerObject],
        x: CGFloat,
        size: CGSize,
        to result: inout [String: CGPoint]
    ) {
        guard !objects.isEmpty else { return }
        let spacing = size.height / CGFloat(objects.count + 1)
        for (index, object) in objects.enumerated() {
            result[object.id] = CGPoint(x: x, y: spacing * CGFloat(index + 1))
        }
    }
}

struct RelationMapEdges: View {
    let relations: [RichAnswerRelation]
    let positions: [String: CGPoint]
    let focusedRelationID: String?

    var body: some View {
        Canvas { context, _ in
            for relation in relations {
                draw(relation, in: &context)
            }
        }
    }

    private func draw(_ relation: RichAnswerRelation, in context: inout GraphicsContext) {
        guard let source = positions[relation.sourceID],
              let target = positions[relation.targetID] else { return }
        let focused = focusedRelationID == nil || focusedRelationID == relation.id
        let color = relationColor(relation.kind)
        var path = Path()
        path.move(to: source)
        path.addLine(to: target)
        context.stroke(
            path,
            with: .color(color.opacity(focused ? 0.72 : 0.16)),
            style: StrokeStyle(
                lineWidth: focused ? 1.8 : 1,
                dash: relation.kind == .refutes ? [5, 4] : []
            )
        )
        context.fill(
            Path(ellipseIn: CGRect(x: target.x - 3, y: target.y - 3, width: 6, height: 6)),
            with: .color(color.opacity(focused ? 0.88 : 0.20))
        )
    }
}

struct RelationMapNode: View {
    let object: RichAnswerObject
    let focused: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(object.label)
                .font(.system(size: 11.5, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(focused ? WeiBeiTheme.ink : WeiBeiTheme.secondaryInk)
                .lineLimit(3)
                .padding(.horizontal, 8)
                .frame(width: 122)
                .frame(minHeight: 44)
                .background(
                    focused ? WeiBeiTheme.paperRaised.opacity(0.94) : WeiBeiTheme.paperInset.opacity(0.38),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(
                            focused ? WeiBeiTheme.hairline.opacity(0.72) : WeiBeiTheme.hairline.opacity(0.34),
                            lineWidth: 1
                        )
                }
        }
        .buttonStyle(.plain)
    }
}

struct CoordinateCanvas: View {
    let scene: RichAnswerScene
    @Binding var selectedObjectID: String?
    let probeValue: Double?
    let probeLabel: String?

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let drawingRect = drawingRect(in: size)
                var axisPath = Path()
                axisPath.move(to: CGPoint(x: drawingRect.minX, y: drawingRect.maxY))
                axisPath.addLine(to: CGPoint(x: drawingRect.maxX, y: drawingRect.maxY))
                axisPath.move(to: CGPoint(x: drawingRect.minX, y: drawingRect.maxY))
                axisPath.addLine(to: CGPoint(x: drawingRect.minX, y: drawingRect.minY))
                context.stroke(axisPath, with: .color(WeiBeiTheme.hairline.opacity(0.92)), lineWidth: 1)
                drawTicks(context: &context, drawingRect: drawingRect)

                var tracePath = Path()
                for (index, plottedObject) in plottedObjects.enumerated() {
                    let object = plottedObject.object
                    let point = plottedObject.point
                    let canvasPoint = CGPoint(
                        x: drawingRect.minX + drawingRect.width * point.x,
                        y: drawingRect.maxY - drawingRect.height * point.y
                    )
                    if index == 0 {
                        tracePath.move(to: canvasPoint)
                    } else {
                        tracePath.addLine(to: canvasPoint)
                    }
                    let radius: CGFloat = selectedObjectID == object.id ? 5 : 3.5
                    context.fill(
                        Path(ellipseIn: CGRect(x: canvasPoint.x - radius, y: canvasPoint.y - radius, width: radius * 2, height: radius * 2)),
                        with: .color(selectedObjectID == object.id ? WeiBeiTheme.cinnabar : WeiBeiTheme.secondaryInk.opacity(0.66))
                    )
                }
                context.stroke(tracePath, with: .color(WeiBeiTheme.secondaryInk.opacity(0.62)), lineWidth: 1.4)

                if let probeValue {
                    let probeX = drawingRect.minX + drawingRect.width * probeValue
                    var probePath = Path()
                    probePath.move(to: CGPoint(x: probeX, y: drawingRect.minY))
                    probePath.addLine(to: CGPoint(x: probeX, y: drawingRect.maxY))
                    context.stroke(probePath, with: .color(WeiBeiTheme.cinnabar.opacity(0.42)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    if let probePoint = interpolatedPoint(at: probeValue, in: drawingRect) {
                        context.fill(
                            Path(ellipseIn: CGRect(x: probePoint.x - 4.5, y: probePoint.y - 4.5, width: 9, height: 9)),
                            with: .color(WeiBeiTheme.cinnabar)
                        )
                    }

                    if let probeLabel {
                        let labelX = min(drawingRect.maxX - 24, max(drawingRect.minX + 24, probeX))
                        context.draw(
                            Text(probeLabel)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(WeiBeiTheme.cinnabar),
                            at: CGPoint(x: labelX, y: drawingRect.minY + 2),
                            anchor: .top
                        )
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture().onEnded { value in
                    let rect = drawingRect(in: geometry.size)
                    selectedObjectID = nearestObjectID(to: value.location, drawingRect: rect)
                }
            )
        }
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 10) {
                ForEach(scene.frames.prefix(2), id: \.id) { frame in
                    Text(frameAxisLabel(frame))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(WeiBeiTheme.tertiaryInk)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 7)
        }
    }

    private func drawingRect(in size: CGSize) -> CGRect {
        CGRect(
            x: 34,
            y: 16,
            width: max(10, size.width - 52),
            height: max(10, size.height - 42)
        )
    }

    private func drawTicks(context: inout GraphicsContext, drawingRect: CGRect) {
        guard let frame = scene.frames.first else { return }
        for index in 0...4 {
            let progress = CGFloat(index) / 4
            let x = drawingRect.minX + drawingRect.width * progress
            let y = drawingRect.maxY - drawingRect.height * progress
            if let xAxis = frame.xAxis {
                let value = xAxis.minimum + (xAxis.maximum - xAxis.minimum) * Double(progress)
                context.draw(
                    Text(axisTickText(value, unit: xAxis.unit))
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundStyle(WeiBeiTheme.tertiaryInk),
                    at: CGPoint(x: x, y: drawingRect.maxY + 8),
                    anchor: .top
                )
            }
            if let yAxis = frame.yAxis {
                let value = yAxis.minimum + (yAxis.maximum - yAxis.minimum) * Double(progress)
                context.draw(
                    Text(axisTickText(value, unit: yAxis.unit))
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundStyle(WeiBeiTheme.tertiaryInk),
                    at: CGPoint(x: drawingRect.minX - 5, y: y),
                    anchor: .trailing
                )
            }
        }
    }

    private func nearestObjectID(to location: CGPoint, drawingRect: CGRect) -> String? {
        plottedObjects.min { left, right in
            distance(from: location, to: canvasPoint(left.point, in: drawingRect))
                < distance(from: location, to: canvasPoint(right.point, in: drawingRect))
        }.flatMap { entry in
            distance(from: location, to: canvasPoint(entry.point, in: drawingRect)) <= 24 ? entry.object.id : nil
        }
    }

    private func canvasPoint(_ point: CGPoint, in drawingRect: CGRect) -> CGPoint {
        CGPoint(
            x: drawingRect.minX + drawingRect.width * point.x,
            y: drawingRect.maxY - drawingRect.height * point.y
        )
    }

    private func distance(from start: CGPoint, to end: CGPoint) -> CGFloat {
        hypot(start.x - end.x, start.y - end.y)
    }

    private func normalizedPoint(for object: RichAnswerObject, index: Int, count: Int) -> CGPoint {
        if let coordinate = object.coordinate {
            return CGPoint(x: clamp01(coordinate.x), y: clamp01(coordinate.y))
        }
        let divisor = max(1, count - 1)
        let normalizedX = Double(index) / Double(divisor)
        let normalizedY = object.number.map { clamp01(($0.truncatingRemainder(dividingBy: 100)) / 100) } ?? (0.28 + 0.44 * normalizedX)
        return CGPoint(x: normalizedX, y: normalizedY)
    }

    private func interpolatedPoint(at probeValue: Double, in drawingRect: CGRect) -> CGPoint? {
        let points = plottedObjects.map { $0.point }
        guard let firstPoint = points.first else { return nil }

        let normalizedX = clamp01(probeValue)
        let normalizedY: CGFloat
        if normalizedX <= firstPoint.x {
            normalizedY = firstPoint.y
        } else if let lastPoint = points.last, normalizedX >= lastPoint.x {
            normalizedY = lastPoint.y
        } else if let segmentIndex = points.indices.dropLast().first(where: {
            points[$0].x <= normalizedX && normalizedX <= points[$0 + 1].x
        }) {
            let start = points[segmentIndex]
            let end = points[segmentIndex + 1]
            let span = max(0.0001, end.x - start.x)
            let progress = (normalizedX - start.x) / span
            normalizedY = start.y + (end.y - start.y) * progress
        } else {
            normalizedY = firstPoint.y
        }

        return CGPoint(
            x: drawingRect.minX + drawingRect.width * normalizedX,
            y: drawingRect.maxY - drawingRect.height * normalizedY
        )
    }

    private var plottedObjects: [(object: RichAnswerObject, point: CGPoint)] {
        scene.objects.enumerated()
            .map { entry in
                (
                    object: entry.element,
                    point: normalizedPoint(for: entry.element, index: entry.offset, count: scene.objects.count)
                )
            }
            .sorted { $0.point.x < $1.point.x }
    }
}

struct TimelineCanvas: View {
    let scene: RichAnswerScene
    let scrubPosition: Double
    let activeLayerIDs: Set<String>

    var body: some View {
        Canvas { context, size in
            let centerY = size.height * 0.54
            let startX: CGFloat = 24
            let endX = max(startX + 20, size.width - 24)
            var linePath = Path()
            linePath.move(to: CGPoint(x: startX, y: centerY))
            linePath.addLine(to: CGPoint(x: endX, y: centerY))
            context.stroke(linePath, with: .color(WeiBeiTheme.hairline.opacity(0.92)), lineWidth: 1)

            for (index, entry) in timelineObjects.enumerated() {
                let objectX = startX + (endX - startX) * entry.position
                let isVisible = layerIsVisible(for: entry.object)
                let isReached = entry.position <= CGFloat(scrubPosition) + 0.001
                let color = isVisible
                    ? (isReached ? WeiBeiTheme.cinnabar.opacity(0.82) : WeiBeiTheme.secondaryInk.opacity(0.48))
                    : WeiBeiTheme.tertiaryInk.opacity(0.16)
                context.fill(
                    Path(ellipseIn: CGRect(x: objectX - 4, y: centerY - 4, width: 8, height: 8)),
                    with: .color(color)
                )
                if let label = context.resolveSymbol(id: entry.object.id) {
                    context.draw(
                        label,
                        at: CGPoint(x: objectX, y: centerY + (index.isMultiple(of: 2) ? -14 : 14)),
                        anchor: index.isMultiple(of: 2) ? .bottom : .top
                    )
                }
            }

            let scrubX = startX + (endX - startX) * CGFloat(scrubPosition)
            var scrubPath = Path()
            scrubPath.move(to: CGPoint(x: scrubX, y: 12))
            scrubPath.addLine(to: CGPoint(x: scrubX, y: size.height - 12))
            context.stroke(scrubPath, with: .color(WeiBeiTheme.cinnabar.opacity(0.58)), lineWidth: 1.2)
        } symbols: {
            ForEach(timelineObjects.map(\.object), id: \.id) { object in
                Text(object.label)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(layerIsVisible(for: object) ? WeiBeiTheme.secondaryInk : WeiBeiTheme.tertiaryInk.opacity(0.30))
                    .lineLimit(2)
                    .frame(width: 92)
                    .tag(object.id)
            }
        }
    }

    private var timelineObjects: [(object: RichAnswerObject, position: CGFloat)] {
        let objects = Array(scene.objects.filter { $0.kind == .event || $0.kind == .state }.prefix(10))
        let base = objects.isEmpty ? Array(scene.objects.prefix(10)) : objects
        let divisor = max(1, base.count - 1)
        return base.enumerated().map { index, object in
            (object, object.coordinate.map { clamp01($0.x) } ?? CGFloat(index) / CGFloat(divisor))
        }.sorted { $0.position < $1.position }
    }

    private func layerIsVisible(for object: RichAnswerObject) -> Bool {
        activeLayerIDs.isEmpty || object.frameID == nil || activeLayerIDs.contains(object.frameID ?? "")
    }
}

struct SpatialMapCanvas: View {
    let scene: RichAnswerScene
    let scrubPosition: Double
    let activeLayerIDs: Set<String>

    var body: some View {
        Canvas { context, size in
            let inset: CGFloat = 18
            let rect = CGRect(x: inset, y: inset, width: max(10, size.width - inset * 2), height: max(10, size.height - inset * 2))
            for tick in 1..<4 {
                let progress = CGFloat(tick) / 4
                var grid = Path()
                grid.move(to: CGPoint(x: rect.minX + rect.width * progress, y: rect.minY))
                grid.addLine(to: CGPoint(x: rect.minX + rect.width * progress, y: rect.maxY))
                grid.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * progress))
                grid.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * progress))
                context.stroke(grid, with: .color(WeiBeiTheme.hairline.opacity(0.22)), lineWidth: 1)
            }

            let positions = objectPositions(in: rect)
            for relation in scene.relations {
                guard let source = positions[relation.sourceID], let target = positions[relation.targetID] else { continue }
                var path = Path()
                path.move(to: source)
                path.addLine(to: target)
                context.stroke(path, with: .color(relationColor(relation.kind).opacity(0.48)), lineWidth: 1.3)
            }

            for (index, object) in visibleObjects.enumerated() {
                guard let point = positions[object.id] else { continue }
                let isVisible = layerIsVisible(for: object)
                let isCurrent = abs(Double(index) / Double(max(visibleObjects.count - 1, 1)) - scrubPosition) < 0.16
                let radius: CGFloat = isCurrent ? 5.5 : 3.8
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
                    with: .color(isVisible ? (isCurrent ? WeiBeiTheme.cinnabar : WeiBeiTheme.secondaryInk.opacity(0.64)) : WeiBeiTheme.tertiaryInk.opacity(0.18))
                )
                if let label = context.resolveSymbol(id: object.id) {
                    context.draw(label, at: CGPoint(x: point.x + 7, y: point.y - 6), anchor: .bottomLeading)
                }
            }
        } symbols: {
            ForEach(visibleObjects, id: \.id) { object in
                Text(object.label)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(layerIsVisible(for: object) ? WeiBeiTheme.secondaryInk : WeiBeiTheme.tertiaryInk.opacity(0.30))
                    .lineLimit(2)
                    .frame(width: 96, alignment: .leading)
                    .tag(object.id)
            }
        }
    }

    private var visibleObjects: [RichAnswerObject] {
        Array(scene.objects.prefix(10))
    }

    private func objectPositions(in rect: CGRect) -> [String: CGPoint] {
        let columns = max(1, Int(ceil(sqrt(Double(visibleObjects.count)))))
        return Dictionary(uniqueKeysWithValues: visibleObjects.enumerated().map { index, object in
            let fallbackX = Double(index % columns) / Double(max(columns - 1, 1))
            let fallbackY = Double(index / columns) / Double(max(columns - 1, 1))
            let x = object.coordinate.map { clamp01($0.x) } ?? CGFloat(fallbackX)
            let y = object.coordinate.map { clamp01($0.y) } ?? CGFloat(fallbackY)
            return (
                object.id,
                CGPoint(x: rect.minX + rect.width * x, y: rect.maxY - rect.height * y)
            )
        })
    }

    private func layerIsVisible(for object: RichAnswerObject) -> Bool {
        activeLayerIDs.isEmpty || object.frameID == nil || activeLayerIDs.contains(object.frameID ?? "")
    }
}

struct ImageRegionOverlay: View {
    let scene: RichAnswerScene
    @Binding var selectedRegionID: String?

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                for object in scene.objects {
                    guard let bounds = object.bounds else { continue }
                    let rect = CGRect(
                        x: size.width * clamp01(bounds.x),
                        y: size.height * clamp01(bounds.y),
                        width: size.width * clamp01(bounds.width),
                        height: size.height * clamp01(bounds.height)
                    )
                    let selected = selectedRegionID == object.id
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: 5),
                        with: .color(selected ? WeiBeiTheme.cinnabarSoft.opacity(0.24) : WeiBeiTheme.paperRaised.opacity(0.18))
                    )
                    context.stroke(
                        Path(roundedRect: rect, cornerRadius: 5),
                        with: .color(selected ? WeiBeiTheme.cinnabar : WeiBeiTheme.secondaryInk.opacity(0.72)),
                        style: StrokeStyle(lineWidth: selected ? 2 : 1.2, dash: selected ? [] : [5, 4])
                    )
                    if let label = context.resolveSymbol(id: object.id) {
                        context.draw(label, at: CGPoint(x: rect.minX + 5, y: rect.minY + 5), anchor: .topLeading)
                    }
                }
            } symbols: {
                ForEach(scene.objects.filter { $0.bounds != nil }, id: \.id) { object in
                    Text(object.label)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(selectedRegionID == object.id ? WeiBeiTheme.cinnabar : WeiBeiTheme.secondaryInk)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(WeiBeiTheme.paper.opacity(0.86), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .tag(object.id)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture().onEnded { value in
                    let width = max(geometry.size.width, 1)
                    let height = max(geometry.size.height, 1)
                    let x = value.location.x / width
                    let y = value.location.y / height
                    selectedRegionID = scene.objects.first { object in
                        guard let bounds = object.bounds else { return false }
                        return x >= bounds.x
                            && x <= bounds.x + bounds.width
                            && y >= bounds.y
                            && y <= bounds.y + bounds.height
                    }?.id
                }
            )
        }
    }
}

