import AppKit
import SwiftUI
import WeiBeiCore

extension GeneratedRichAnswerCanvas {
    func drawProbe(context: inout GraphicsContext, rect: CGRect, includeGuide: Bool, includeLabel: Bool) {
        guard let control = compositionIndex.nodes.first(where: { $0.role == .probe && $0.bindingID != nil }),
              let bindingID = control.bindingID,
              let binding = binding(for: bindingID),
              let mark = markNodes.first(where: {
                  $0.bindingID == bindingID
                      && $0.datasetID != nil
                      && [.line, .path, .point, .bar].contains($0.role)
              }),
              let dataset = dataset(for: mark),
              let row = interpolatedRow(in: dataset, binding: binding) else { return }
        let point = canvasPoint(row.x, row.y, in: rect)
        if includeGuide {
            var probe = Path()
            probe.move(to: CGPoint(x: point.x, y: rect.minY))
            probe.addLine(to: CGPoint(x: point.x, y: rect.maxY))
            context.stroke(probe, with: .color(WeiBeiTheme.cinnabar.opacity(0.42)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            context.fill(
                Path(ellipseIn: CGRect(x: point.x - 4.5, y: point.y - 4.5, width: 9, height: 9)),
                with: .color(WeiBeiTheme.cinnabar)
            )
        }
        guard includeLabel else { return }
        let label = measuredCanvasLabel(
            id: "\(row.id)-probe-label",
            text: row.label ?? formattedBindingValue(binding),
            point: point,
            node: mark,
            selected: true,
            required: true,
            priority: 110,
            in: rect
        )
        drawPlacedLabels(placeCanvasLabels([label], in: rect, occupiedFrames: labelObstacles(excluding: mark.id, in: rect)), context: &context)
    }

    func select(at location: CGPoint, size: CGSize) {
        let projection = GeneratedCanvasProjection(canvasSize: size)
        let rect = projection.rect
        if let regionNode = markNodes.first(where: { node in
            guard node.role == .region, let region = node.region else { return false }
            let regionRect = CGRect(
                x: rect.minX + rect.width * region.x,
                y: rect.minY + rect.height * region.y,
                width: rect.width * region.width,
                height: rect.height * region.height
            )
            return regionRect.contains(location)
        }) {
            runtime.selectedID = regionNode.id
            return
        }
        for node in markNodes where node.role == .shape {
            if let instance = GeneratedCanvasHitTesting.firstInstance(at: location, in: shapeInstances(for: node, rect: rect), padding: 5) {
                runtime.selectedID = instance.id
                return
            }
        }
        for node in markNodes where node.role == .bar {
            if let instance = GeneratedCanvasHitTesting.firstInstance(at: location, in: barInstances(for: node, rect: rect), padding: 4) {
                runtime.selectedID = instance.id
                return
            }
        }
        let rows = markNodes
            .filter { $0.role == .point || $0.role == .dotMatrix || $0.role == .label }
            .compactMap { dataset(for: $0) }
            .flatMap(\.rows)
        runtime.selectedID = GeneratedCanvasHitTesting.nearestRowID(at: location, rows: rows, projection: projection, radius: 24)
    }

    func shapeInstances(for node: RichAnswerUINode, rect: CGRect) -> [GeneratedCanvasMarkInstance] {
        guard let region = node.region else { return [] }
        let width = max(8, rect.width * region.width)
        let height = max(8, rect.height * region.height)
        if let dataset = dataset(for: node) {
            if let bindingID = node.bindingID,
               let binding = binding(for: bindingID),
               generatedBindingIsDiscrete(binding, in: composition) {
                return activeRows(in: dataset, bindingID: bindingID).map { row in
                    let point = canvasPoint(row.x, row.y, in: rect)
                    return GeneratedCanvasMarkInstance(
                        id: row.id,
                        rect: CGRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height),
                        label: row.label ?? node.label
                    )
                }
            }
            if let bindingID = node.bindingID,
               let point = interpolatedPoint(in: dataset, bindingID: bindingID, rect: rect),
               let row = activeRow(in: dataset, bindingID: bindingID) {
                return [GeneratedCanvasMarkInstance(
                    id: row.id,
                    rect: CGRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height),
                    label: row.label ?? node.label
                )]
            }
            return dataset.rows.map { row in
                let point = canvasPoint(row.x, row.y, in: rect)
                return GeneratedCanvasMarkInstance(
                    id: row.id,
                    rect: CGRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height),
                    label: row.label ?? node.label
                )
            }
        }
        return [GeneratedCanvasMarkInstance(
            id: node.id,
            rect: CGRect(
                x: rect.minX + rect.width * region.x,
                y: rect.minY + rect.height * region.y,
                width: width,
                height: height
            ),
            label: node.label
        )]
    }

    func barInstances(for node: RichAnswerUINode, rect: CGRect) -> [GeneratedCanvasMarkInstance] {
        guard let dataset = dataset(for: node) else { return [] }
        let rows: [RichAnswerUIDataRow]
        if let bindingID = node.bindingID,
           let binding = binding(for: bindingID),
           generatedBindingIsDiscrete(binding, in: composition) {
            rows = activeRows(in: dataset, bindingID: bindingID)
        } else {
            rows = dataset.rows
        }
        let sortedX = rows.map(\.x).sorted()
        let minimumCoordinateGap = zip(sortedX, sortedX.dropFirst())
            .map { $1 - $0 }
            .filter { $0 > 0.000_001 }
            .min()
        let countBasedWidth = rect.width / CGFloat(max(1, rows.count)) * 0.58
        let coordinateBasedWidth = minimumCoordinateGap.map { rect.width * CGFloat($0) * 0.72 } ?? 46
        let width = max(5, min(46, min(countBasedWidth, coordinateBasedWidth)))
        return rows.map { row in
            let height = max(2, rect.height * row.y)
            let centerX = rect.minX + rect.width * row.x
            return GeneratedCanvasMarkInstance(
                id: row.id,
                rect: CGRect(x: centerX - width / 2, y: rect.maxY - height, width: width, height: height),
                label: row.label
            )
        }
    }

    func interpolatedPoint(
        in dataset: RichAnswerUIDataset,
        bindingID: String,
        rect: CGRect
    ) -> CGPoint? {
        guard let binding = compositionIndex.binding(id: bindingID) else { return nil }
        if generatedBindingIsDiscrete(binding, in: composition),
           let row = activeRows(in: dataset, bindingID: bindingID).first {
            return canvasPoint(row.x, row.y, in: rect)
        }
        let rows = dataset.rows.sorted { ($0.value ?? $0.x) < ($1.value ?? $1.x) }
        guard let first = rows.first else { return nil }
        let value = runtime.values[bindingID] ?? binding.initialValue
        if value <= (first.value ?? first.x) {
            return canvasPoint(first.x, first.y, in: rect)
        }
        guard let last = rows.last else { return canvasPoint(first.x, first.y, in: rect) }
        if value >= (last.value ?? last.x) {
            return canvasPoint(last.x, last.y, in: rect)
        }
        for index in rows.indices.dropLast() {
            let start = rows[index]
            let end = rows[index + 1]
            let startValue = start.value ?? start.x
            let endValue = end.value ?? end.x
            guard startValue <= value, value <= endValue else { continue }
            let progress = (value - startValue) / max(0.000_001, endValue - startValue)
            return canvasPoint(
                start.x + (end.x - start.x) * progress,
                start.y + (end.y - start.y) * progress,
                in: rect
            )
        }
        return canvasPoint(first.x, first.y, in: rect)
    }

    func interpolatedRow(in dataset: RichAnswerUIDataset, binding: RichAnswerUIBinding) -> RichAnswerUIDataRow? {
        if generatedBindingIsDiscrete(binding, in: composition),
           let row = activeRows(in: dataset, bindingID: binding.id).first {
            return boundRow(from: row, binding: binding)
        }
        let rows = dataset.rows.sorted { rowBindingValue($0, binding: binding) < rowBindingValue($1, binding: binding) }
        guard let first = rows.first else { return nil }
        let value = boundValue(for: binding)
        if value <= rowBindingValue(first, binding: binding) {
            return boundRow(from: first, binding: binding)
        }
        guard let last = rows.last else { return boundRow(from: first, binding: binding) }
        if value >= rowBindingValue(last, binding: binding) {
            return boundRow(from: last, binding: binding)
        }
        for index in rows.indices.dropLast() {
            let start = rows[index]
            let end = rows[index + 1]
            let startValue = rowBindingValue(start, binding: binding)
            let endValue = rowBindingValue(end, binding: binding)
            guard startValue <= value, value <= endValue else { continue }
            let progress = (value - startValue) / max(0.000_001, endValue - startValue)
            return RichAnswerUIDataRow(
                id: "\(start.id)-\(end.id)-bound-\(binding.id)",
                x: start.x + (end.x - start.x) * progress,
                y: start.y + (end.y - start.y) * progress,
                x2: interpolatedOptional(start.x2, end.x2, progress: progress),
                y2: interpolatedOptional(start.y2, end.y2, progress: progress),
                value: value,
                result: interpolatedOptional(start.result ?? start.y, end.result ?? end.y, progress: progress),
                label: formattedBindingValue(binding),
                evidenceIDs: start.evidenceIDs + end.evidenceIDs
            )
        }
        return boundRow(from: first, binding: binding)
    }

    func boundRow(from row: RichAnswerUIDataRow, binding: RichAnswerUIBinding) -> RichAnswerUIDataRow {
        RichAnswerUIDataRow(
            id: "\(row.id)-bound-\(binding.id)",
            x: row.x,
            y: row.y,
            x2: row.x2,
            y2: row.y2,
            value: boundValue(for: binding),
            result: row.result,
            label: formattedBindingValue(binding),
            evidenceIDs: row.evidenceIDs
        )
    }

    func binding(for bindingID: String) -> RichAnswerUIBinding? {
        compositionIndex.binding(id: bindingID)
    }

    func boundValue(for binding: RichAnswerUIBinding) -> Double {
        min(binding.maximum, max(binding.minimum, runtime.values[binding.id] ?? binding.initialValue))
    }

    func rowBindingValue(_ row: RichAnswerUIDataRow, binding: RichAnswerUIBinding) -> Double {
        row.value ?? binding.minimum + row.x * (binding.maximum - binding.minimum)
    }

    func formattedBindingValue(_ binding: RichAnswerUIBinding) -> String {
        let value = boundValue(for: binding)
        let precision = binding.step < 1 ? 1 : 0
        let formatted = String(format: "%.\(precision)f", value)
        return binding.unit.map { "\(binding.label)=\(formatted) \($0)" } ?? "\(binding.label)=\(formatted)"
    }

    func interpolatedOptional(_ start: Double?, _ end: Double?, progress: Double) -> Double? {
        guard let start, let end else { return nil }
        return start + (end - start) * progress
    }

    func interpolatedOptional(_ start: Double, _ end: Double, progress: Double) -> Double {
        start + (end - start) * progress
    }

    func dataset(for node: RichAnswerUINode) -> RichAnswerUIDataset? {
        guard let datasetID = node.datasetID else { return nil }
        return compositionIndex.dataset(id: datasetID)
    }

    func activeRow(in dataset: RichAnswerUIDataset, bindingID: String?) -> RichAnswerUIDataRow? {
        guard let bindingID,
              let binding = compositionIndex.binding(id: bindingID) else { return nil }
        let value = runtime.values[bindingID] ?? binding.initialValue
        return dataset.rows.min {
            abs(($0.value ?? binding.minimum + $0.x * (binding.maximum - binding.minimum)) - value)
                < abs(($1.value ?? binding.minimum + $1.x * (binding.maximum - binding.minimum)) - value)
        }
    }

    func activeRows(in dataset: RichAnswerUIDataset, bindingID: String) -> [RichAnswerUIDataRow] {
        guard let binding = binding(for: bindingID) else { return [] }
        return generatedActiveRows(
            in: dataset,
            binding: binding,
            runtimeValue: runtime.values[bindingID]
        )
    }

    func continuousActiveRowID(in dataset: RichAnswerUIDataset, bindingID: String?) -> String? {
        guard let bindingID,
              let binding = binding(for: bindingID),
              !generatedBindingIsDiscrete(binding, in: composition) else { return nil }
        return activeRow(in: dataset, bindingID: bindingID)?.id
    }

    func isVisible(_ node: RichAnswerUINode) -> Bool {
        guard let bindingID = node.bindingID,
              node.role == .image || node.role == .region else { return true }
        return (runtime.values[bindingID] ?? 1) >= 0.5
    }

    func imageScale(_ node: RichAnswerUINode) -> CGFloat {
        guard let bindingID = node.bindingID else { return 1 }
        return CGFloat(max(0.7, min(2, runtime.values[bindingID] ?? 1)))
    }
}

struct GeneratedCanvasMarkInstance {
    let id: String
    let rect: CGRect
    let label: String?
}


func generatedBindingIsDiscrete(
    _ binding: RichAnswerUIBinding,
    in composition: RichAnswerUIComposition
) -> Bool {
    composition.nodes.contains { node in
        node.bindingID == binding.id && [.toggle, .sequence].contains(node.role)
    }
}

func generatedActiveRows(
    in dataset: RichAnswerUIDataset,
    binding: RichAnswerUIBinding,
    runtimeValue: Double?
) -> [RichAnswerUIDataRow] {
    guard !dataset.rows.isEmpty else { return [] }
    let currentValue = min(
        binding.maximum,
        max(binding.minimum, runtimeValue ?? binding.initialValue)
    )
    func rowValue(_ row: RichAnswerUIDataRow) -> Double {
        row.value ?? binding.minimum + row.x * (binding.maximum - binding.minimum)
    }
    guard let nearestValue = dataset.rows.min(by: {
        abs(rowValue($0) - currentValue) < abs(rowValue($1) - currentValue)
    }).map(rowValue) else { return [] }
    let tolerance = max(0.000_001, abs(binding.step) * 0.000_001)
    return dataset.rows.filter { abs(rowValue($0) - nearestValue) <= tolerance }
}

func generatedMeaningfulUnit(_ rawUnit: String?) -> String? {
    guard let unit = rawUnit?.trimmingCharacters(in: .whitespacesAndNewlines),
          !unit.isEmpty else { return nil }
    let placeholderUnits: Set<String> = ["值", "数值", "value", "values"]
    return placeholderUnits.contains(unit.lowercased()) ? nil : unit
}

func interpolatedY(in dataset: RichAnswerUIDataset, at value: Double) -> Double {
    let rows = dataset.rows.sorted { ($0.value ?? $0.x) < ($1.value ?? $1.x) }
    guard let first = rows.first else { return 0 }
    if value <= (first.value ?? first.x) { return first.result ?? first.y }
    guard let last = rows.last else { return first.y }
    if value >= (last.value ?? last.x) { return last.result ?? last.y }
    for index in rows.indices.dropLast() {
        let start = rows[index]
        let end = rows[index + 1]
        let startValue = start.value ?? start.x
        let endValue = end.value ?? end.x
        if startValue <= value, value <= endValue {
            let span = max(0.000_001, endValue - startValue)
            let progress = (value - startValue) / span
            let startResult = start.result ?? start.y
            let endResult = end.result ?? end.y
            return startResult + (endResult - startResult) * progress
        }
    }
    return first.result ?? first.y
}

func canvasPoint(_ x: Double, _ y: Double, in rect: CGRect) -> CGPoint {
    GeneratedCanvasProjection(rect: rect).point(x: x, y: y)
}

func distance(_ left: CGPoint, _ right: CGPoint) -> CGFloat {
    hypot(left.x - right.x, left.y - right.y)
}

