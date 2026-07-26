import AppKit
import SwiftUI
import WeiBeiCore

extension GeneratedRichAnswerCanvas {
    func drawAxes(context: inout GraphicsContext, rect: CGRect) {
        for index in 0...4 {
            let progress = CGFloat(index) / 4
            var grid = Path()
            grid.move(to: CGPoint(x: rect.minX + rect.width * progress, y: rect.minY))
            grid.addLine(to: CGPoint(x: rect.minX + rect.width * progress, y: rect.maxY))
            grid.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * progress))
            grid.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * progress))
            context.stroke(grid, with: .color(WeiBeiTheme.hairline.opacity(index == 0 || index == 4 ? 0.48 : 0.20)), lineWidth: 1)
        }
        if let xAxis = canvasNode.xAxis {
            context.draw(
                Text("\(axisValue(xAxis.minimum, unit: xAxis.unit))   \(xAxis.label)   \(axisValue(xAxis.maximum, unit: xAxis.unit))")
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(WeiBeiTheme.tertiaryInk),
                at: CGPoint(x: rect.midX, y: rect.maxY + 10),
                anchor: .top
            )
        }
        if let yAxis = canvasNode.yAxis {
            context.draw(
                Text(axisValue(yAxis.maximum, unit: yAxis.unit))
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(WeiBeiTheme.tertiaryInk),
                at: CGPoint(x: rect.minX - 5, y: rect.minY),
                anchor: .trailing
            )
            context.draw(
                Text(axisValue(yAxis.minimum, unit: yAxis.unit))
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(WeiBeiTheme.tertiaryInk),
                at: CGPoint(x: rect.minX - 5, y: rect.maxY),
                anchor: .trailing
            )
        }
    }

    func drawPath(_ node: RichAnswerUINode, context: inout GraphicsContext, rect: CGRect) {
        guard let dataset = dataset(for: node) else { return }
        let style = node.emphasis == .quiet
            ? StrokeStyle(lineWidth: 1, dash: [4, 4])
            : StrokeStyle(lineWidth: node.emphasis == .strong ? 2.2 : 1.5)
        if let bindingID = node.bindingID,
           let binding = binding(for: bindingID),
           generatedBindingIsDiscrete(binding, in: composition) {
            let rows = activeRows(in: dataset, bindingID: bindingID).sorted { $0.x < $1.x }
            guard !rows.isEmpty else { return }
            context.stroke(
                path(for: rows, in: rect),
                with: .color(generatedToneColor(node.tone).opacity(node.emphasis == .quiet ? 0.48 : 0.78)),
                style: style
            )
            return
        }
        let rows = dataset.rows.sorted { $0.x < $1.x }
        let wholePath = path(for: rows, in: rect)
        if let bindingID = node.bindingID,
           let binding = binding(for: bindingID),
           let currentRow = interpolatedRow(in: dataset, binding: binding),
           let partialPath = pathThroughCurrentValue(rows: rows, currentRow: currentRow, binding: binding, in: rect) {
            context.stroke(wholePath, with: .color(generatedToneColor(node.tone).opacity(0.28)), style: style)
            context.stroke(partialPath, with: .color(generatedToneColor(node.tone).opacity(0.86)), style: style)
            return
        }
        context.stroke(wholePath, with: .color(generatedToneColor(node.tone).opacity(node.emphasis == .quiet ? 0.48 : 0.78)), style: style)
    }

    func path(for rows: [RichAnswerUIDataRow], in rect: CGRect) -> Path {
        var path = Path()
        for (index, row) in rows.enumerated() {
            let point = canvasPoint(row.x, row.y, in: rect)
            if let x2 = row.x2, let y2 = row.y2 {
                path.move(to: point)
                path.addLine(to: canvasPoint(x2, y2, in: rect))
            } else if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }

    func pathThroughCurrentValue(
        rows: [RichAnswerUIDataRow],
        currentRow: RichAnswerUIDataRow,
        binding: RichAnswerUIBinding,
        in rect: CGRect
    ) -> Path? {
        let currentValue = boundValue(for: binding)
        let sortedRows = rows.sorted { rowBindingValue($0, binding: binding) < rowBindingValue($1, binding: binding) }
        guard let first = sortedRows.first else { return nil }
        var partialRows = sortedRows.filter { rowBindingValue($0, binding: binding) < currentValue }
        if partialRows.isEmpty {
            partialRows = [first]
        }
        partialRows.append(currentRow)
        return path(for: partialRows, in: rect)
    }

    func drawPoints(_ node: RichAnswerUINode, context: inout GraphicsContext, rect: CGRect) {
        guard let dataset = dataset(for: node) else { return }
        if let bindingID = node.bindingID,
           let binding = binding(for: bindingID),
           generatedBindingIsDiscrete(binding, in: composition) {
            for row in activeRows(in: dataset, bindingID: bindingID) {
                let point = canvasPoint(row.x, row.y, in: rect)
                let selected = runtime.selectedID == row.id
                let radius: CGFloat = selected ? 5.2 : 3.4
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
                    with: .color(selected ? WeiBeiTheme.cinnabar : generatedToneColor(node.tone).opacity(0.72))
                )
            }
            return
        }
        if let bindingID = node.bindingID,
           let binding = binding(for: bindingID),
           let currentRow = interpolatedRow(in: dataset, binding: binding) {
            for row in dataset.rows {
                let point = canvasPoint(row.x, row.y, in: rect)
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x - 3.1, y: point.y - 3.1, width: 6.2, height: 6.2)),
                    with: .color(generatedToneColor(node.tone).opacity(0.54))
                )
            }
            let point = canvasPoint(currentRow.x, currentRow.y, in: rect)
            context.fill(
                Path(ellipseIn: CGRect(x: point.x - 5.2, y: point.y - 5.2, width: 10.4, height: 10.4)),
                with: .color(WeiBeiTheme.cinnabar)
            )
            context.stroke(
                Path(ellipseIn: CGRect(x: point.x - 7.2, y: point.y - 7.2, width: 14.4, height: 14.4)),
                with: .color(WeiBeiTheme.cinnabar.opacity(0.28)),
                lineWidth: 2
            )
            return
        }
        let activeID = activeRow(in: dataset, bindingID: node.bindingID)?.id
        for row in dataset.rows {
            let point = canvasPoint(row.x, row.y, in: rect)
            let isActive = runtime.selectedID == row.id || activeID == row.id
            let radius: CGFloat = isActive ? 5.2 : 3.4
            context.fill(
                Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
                with: .color(isActive ? WeiBeiTheme.cinnabar : generatedToneColor(node.tone).opacity(0.72))
            )
        }
    }

    func drawArea(_ node: RichAnswerUINode, context: inout GraphicsContext, rect: CGRect) {
        guard let dataset = dataset(for: node) else { return }
        let rows: [RichAnswerUIDataRow]
        if let bindingID = node.bindingID,
           let binding = binding(for: bindingID),
           generatedBindingIsDiscrete(binding, in: composition) {
            rows = activeRows(in: dataset, bindingID: bindingID).sorted { $0.x < $1.x }
        } else {
            rows = dataset.rows.sorted { $0.x < $1.x }
        }
        guard rows.count >= 3 else { return }
        var path = Path()
        path.move(to: canvasPoint(rows[0].x, rows[0].y, in: rect))
        for row in rows.dropFirst() {
            path.addLine(to: canvasPoint(row.x, row.y, in: rect))
        }
        path.closeSubpath()
        context.fill(path, with: .color(generatedToneColor(node.tone).opacity(0.12)))
        context.stroke(path, with: .color(generatedToneColor(node.tone).opacity(0.58)), lineWidth: 1.2)
    }

}
