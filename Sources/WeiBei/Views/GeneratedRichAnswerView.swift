import AppKit
import SwiftUI
import WeiBeiCore

struct GeneratedRichAnswerSceneView: View {
    let scene: RichAnswerScene
    let composition: RichAnswerUIComposition
    let evidenceByID: [String: RichAnswerEvidence]
    var onOpenEvidence: (RichAnswerEvidence) -> Void
    var onOpenAsset: (String) -> Void
    var assetPreview: (String) -> NSImage?
    @State private var runtime: GeneratedRichAnswerRuntime

    init(
        scene: RichAnswerScene,
        composition: RichAnswerUIComposition,
        evidenceByID: [String: RichAnswerEvidence],
        onOpenEvidence: @escaping (RichAnswerEvidence) -> Void,
        onOpenAsset: @escaping (String) -> Void,
        assetPreview: @escaping (String) -> NSImage?
    ) {
        self.scene = scene
        self.composition = composition
        self.evidenceByID = evidenceByID
        self.onOpenEvidence = onOpenEvidence
        self.onOpenAsset = onOpenAsset
        self.assetPreview = assetPreview
        _runtime = State(initialValue: GeneratedRichAnswerRuntime(composition: composition))
    }

    var body: some View {
        GeneratedRichAnswerNodeView(
            nodeID: composition.rootID,
            composition: composition,
            evidenceByID: evidenceByID,
            runtime: $runtime,
            onOpenEvidence: onOpenEvidence,
            onOpenAsset: onOpenAsset,
            assetPreview: assetPreview
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(scene.title)
        .accessibilityIdentifier("rich-answer-scene-\(scene.id)")
    }
}

private struct GeneratedRichAnswerRuntime: Equatable {
    var values: [String: Double]
    var selectedID: String?

    init(composition: RichAnswerUIComposition) {
        values = Dictionary(uniqueKeysWithValues: composition.bindings.map { ($0.id, $0.initialValue) })
    }

    mutating func reset(_ composition: RichAnswerUIComposition) {
        values = Dictionary(uniqueKeysWithValues: composition.bindings.map { ($0.id, $0.initialValue) })
        selectedID = nil
    }

}

private struct GeneratedRichAnswerNodeView: View {
    let nodeID: String
    let composition: RichAnswerUIComposition
    let evidenceByID: [String: RichAnswerEvidence]
    @Binding var runtime: GeneratedRichAnswerRuntime
    var onOpenEvidence: (RichAnswerEvidence) -> Void
    var onOpenAsset: (String) -> Void
    var assetPreview: (String) -> NSImage?

    @ViewBuilder
    var body: some View {
        if let node {
            switch node.role {
            case .vstack:
                VStack(alignment: horizontalAlignment(for: node.alignment), spacing: spacing(for: node.spacing)) {
                    childViews(node)
                }
            case .hstack:
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: spacing(for: node.spacing)) {
                        childViews(node)
                    }
                    .frame(minWidth: hstackMinimumInlineWidth(for: node), alignment: .leading)
                    VStack(alignment: horizontalAlignment(for: node.alignment), spacing: spacing(for: node.spacing)) {
                        childViews(node)
                    }
                }
            case .zstack:
                ZStack(alignment: zAlignment(for: node.alignment)) {
                    childViews(node)
                }
            case .grid:
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: spacing(for: node.spacing), alignment: .topLeading),
                        count: max(2, min(3, node.columns ?? 2))
                    ),
                    alignment: .leading,
                    spacing: spacing(for: node.spacing)
                ) {
                    childViews(node)
                }
            case .panel:
                VStack(alignment: horizontalAlignment(for: node.alignment), spacing: spacing(for: node.spacing)) {
                    childViews(node)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(WeiBeiTheme.paperInset.opacity(0.16))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(WeiBeiTheme.hairline.opacity(0.44))
                        .frame(height: 1)
                }
            case .canvas:
                GeneratedRichAnswerCanvas(
                    canvasNode: node,
                    composition: composition,
                    runtime: $runtime,
                    onOpenAsset: onOpenAsset,
                    assetPreview: assetPreview
                )
                .frame(minWidth: canvasMinimumInlineWidth(for: node), maxWidth: .infinity, alignment: .leading)
            case .text:
                GeneratedRichAnswerText(node: node)
            case .metric:
                GeneratedRichAnswerMetric(node: node, composition: composition, runtime: runtime)
            case .sequence:
                GeneratedRichAnswerSequence(node: node, composition: composition, runtime: $runtime)
            case .slider, .toggle, .scrubber, .select, .reset, .probe:
                GeneratedRichAnswerControl(node: node, composition: composition, runtime: $runtime)
            case .evidence:
                GeneratedRichAnswerEvidence(
                    node: node,
                    evidenceByID: evidenceByID,
                    onOpenEvidence: onOpenEvidence
                )
            case .divider:
                Rectangle()
                    .fill(WeiBeiTheme.hairline.opacity(0.48))
                    .frame(height: 1)
            case .axis, .line, .path, .point, .area, .shape, .bar, .dotMatrix, .vector, .region, .image, .label:
                EmptyView()
            }
        }
    }

    private var node: RichAnswerUINode? {
        composition.nodes.first(where: { $0.id == nodeID })
    }

    @ViewBuilder
    private func childViews(_ node: RichAnswerUINode) -> some View {
        ForEach(deduplicatedChildIDs(for: node), id: \.self) { childID in
            GeneratedRichAnswerNodeView(
                nodeID: childID,
                composition: composition,
                evidenceByID: evidenceByID,
                runtime: $runtime,
                onOpenEvidence: onOpenEvidence,
                onOpenAsset: onOpenAsset,
                assetPreview: assetPreview
            )
        }
    }

    private func deduplicatedChildIDs(for node: RichAnswerUINode) -> [String] {
        var seenSourceLabels: Set<String> = []
        return node.children.filter { childID in
            guard let child = composition.nodes.first(where: { $0.id == childID }),
                  child.role == .evidence else {
                return true
            }
            let sourceLabels = child.evidenceIDs.compactMap { evidenceByID[$0]?.sourceLabel }
            guard !sourceLabels.isEmpty else { return true }
            let introducesSource = sourceLabels.contains { !seenSourceLabels.contains($0) }
            seenSourceLabels.formUnion(sourceLabels)
            return introducesSource
        }
    }

    private func canvasMinimumInlineWidth(for node: RichAnswerUINode) -> CGFloat {
        guard node.role == .canvas else { return 0 }
        let children = node.children.compactMap { childID in
            composition.nodes.first(where: { $0.id == childID })
        }
        let hasComplexMarks = children.contains { child in
            [.axis, .line, .path, .area, .vector, .region, .label].contains(child.role)
        } || node.xAxis != nil || node.yAxis != nil
        let baseWidth: CGFloat
        switch node.size {
        case .compact:
            baseWidth = 260
        case .regular:
            baseWidth = 320
        case .large:
            baseWidth = hasComplexMarks ? 380 : 340
        }
        return hasComplexMarks ? baseWidth : min(baseWidth, 320)
    }

    private func hstackMinimumInlineWidth(for node: RichAnswerUINode) -> CGFloat {
        guard node.role == .hstack else { return 0 }
        let children = node.children.compactMap { childID in
            composition.nodes.first(where: { $0.id == childID })
        }
        guard children.contains(where: { $0.role == .canvas }) else { return 0 }
        let canvasWidth = children
            .filter { $0.role == .canvas }
            .map(canvasMinimumInlineWidth(for:))
            .reduce(CGFloat.zero, +)
        let nonCanvasCount = children.filter { $0.role != .canvas }.count
        let sidecarWidth = CGFloat(nonCanvasCount) * 220
        let gaps = CGFloat(max(0, children.count - 1)) * spacing(for: node.spacing)
        return canvasWidth + sidecarWidth + gaps
    }
}

private struct GeneratedRichAnswerText: View {
    let node: RichAnswerUINode

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let label = node.label, !label.isEmpty {
                Text(label)
                    .font(labelFont)
                    .foregroundStyle(generatedToneColor(node.tone))
            }
            if let text = node.text, !text.isEmpty {
                Text(text)
                    .font(textFont)
                    .lineSpacing(3)
                    .foregroundStyle(node.emphasis == .quiet ? WeiBeiTheme.secondaryInk : WeiBeiTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: generatedFrameAlignment(node.alignment))
    }

    private var labelFont: Font {
        switch node.emphasis {
        case .quiet:
            return .system(size: 10.5, weight: .semibold)
        case .regular:
            return .system(size: 12.5, weight: .semibold)
        case .strong:
            return .system(size: 16, weight: .semibold)
        }
    }

    private var textFont: Font {
        node.emphasis == .strong ? .system(size: 14, weight: .medium) : .system(size: 12.5)
    }
}

private struct GeneratedRichAnswerMetric: View {
    let node: RichAnswerUINode
    let composition: RichAnswerUIComposition
    let runtime: GeneratedRichAnswerRuntime

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let label = node.label {
                Text(label)
                    .weiBeiText(10.5, weight: .medium)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
            }
            Text(displayValue)
                .weiBeiText(node.emphasis == .strong ? 22 : 18, weight: .semibold, design: .monospaced)
                .foregroundStyle(generatedToneColor(node.tone))
            if let text = node.text, !text.isEmpty {
                Text(text)
                    .weiBeiText(9.5)
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: generatedFrameAlignment(node.alignment))
    }

    private var displayValue: String {
        guard let datasetID = node.datasetID,
              let dataset = composition.datasets.first(where: { $0.id == datasetID }),
              !dataset.rows.isEmpty else {
            return "—"
        }
        let value: Double
        if let bindingID = node.bindingID,
           let binding = composition.bindings.first(where: { $0.id == bindingID }) {
            if generatedBindingIsDiscrete(binding, in: composition),
               let row = generatedActiveRows(
                   in: dataset,
                   binding: binding,
                   runtimeValue: runtime.values[bindingID]
               ).first {
                value = row.result ?? row.y
            } else {
                value = interpolatedY(
                    in: dataset,
                    at: runtime.values[bindingID] ?? binding.initialValue
                )
            }
        } else {
            value = dataset.rows.first?.result ?? dataset.rows.first?.value ?? dataset.rows.first?.y ?? 0
        }
        let formatted = abs(value.rounded() - value) < 0.0001
            ? String(format: "%.0f", value)
            : String(format: "%.2f", value)
        return generatedMeaningfulUnit(node.unit).map { "\(formatted) \($0)" } ?? formatted
    }
}

private struct GeneratedRichAnswerSequence: View {
    let node: RichAnswerUINode
    let composition: RichAnswerUIComposition
    @Binding var runtime: GeneratedRichAnswerRuntime

    var body: some View {
        if let dataset, !dataset.rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if let label = node.label, !label.isEmpty {
                    Text(label)
                        .weiBeiText(10.5, weight: .semibold)
                        .foregroundStyle(generatedToneColor(node.tone))
                }
                ViewThatFits(in: .horizontal) {
                    horizontalRows(dataset.rows)
                    verticalRows(dataset.rows)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var dataset: RichAnswerUIDataset? {
        guard let datasetID = node.datasetID else { return nil }
        return composition.datasets.first(where: { $0.id == datasetID })
    }

    private func horizontalRows(_ rows: [RichAnswerUIDataRow]) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                Button {
                    select(row)
                } label: {
                    VStack(spacing: 6) {
                        HStack(spacing: 0) {
                            Rectangle()
                                .fill(WeiBeiTheme.hairline.opacity(index == 0 ? 0 : 0.55))
                                .frame(height: 1)
                            marker(index: index, row: row)
                            Rectangle()
                                .fill(WeiBeiTheme.hairline.opacity(index == rows.count - 1 ? 0 : 0.55))
                                .frame(height: 1)
                        }
                        .frame(height: 18)
                        Text(row.label ?? "")
                            .weiBeiText(10.5, weight: isActive(row) ? .semibold : .regular)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(isActive(row) ? WeiBeiTheme.cinnabar : WeiBeiTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(minWidth: 84, maxWidth: 132, alignment: .top)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(sequenceAccessibilityLabel(row))
                .accessibilityIdentifier("rich-answer-sequence-\(node.id)-\(row.id)")
            }
        }
        .frame(minWidth: CGFloat(rows.count) * 150, alignment: .topLeading)
        .padding(.vertical, 2)
    }

    private func verticalRows(_ rows: [RichAnswerUIDataRow]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                Button {
                    select(row)
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        marker(index: index, row: row)
                            .padding(.top, 1)
                        Text(row.label ?? "")
                            .weiBeiText(12, weight: isActive(row) ? .semibold : .regular)
                            .foregroundStyle(isActive(row) ? WeiBeiTheme.cinnabar : WeiBeiTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(sequenceAccessibilityLabel(row))
                .accessibilityIdentifier("rich-answer-sequence-\(node.id)-\(row.id)")
            }
        }
    }

    private func sequenceAccessibilityLabel(_ row: RichAnswerUIDataRow) -> String {
        let sequenceLabel = node.label ?? "富回答序列"
        let rowLabel = row.label ?? row.id
        return "\(sequenceLabel)：\(rowLabel)"
    }

    private func marker(index: Int, row: RichAnswerUIDataRow) -> some View {
        let active = isActive(row)
        return ZStack {
            Circle()
                .fill(active ? WeiBeiTheme.cinnabar : WeiBeiTheme.paperInset.opacity(0.32))
                .overlay {
                    Circle()
                        .stroke(active ? WeiBeiTheme.cinnabar : WeiBeiTheme.hairline.opacity(0.74), lineWidth: 1)
                }
            Text("\(index + 1)")
                .weiBeiText(9.5, weight: .semibold, design: .monospaced)
                .foregroundStyle(active ? WeiBeiTheme.onCinnabar : WeiBeiTheme.secondaryInk)
        }
        .frame(width: 18, height: 18)
        .shadow(color: active ? WeiBeiTheme.cinnabar.opacity(0.16) : .clear, radius: 4, y: 1)
    }

    private func select(_ row: RichAnswerUIDataRow) {
        runtime.selectedID = row.id
        guard let bindingID = node.bindingID,
              let binding = composition.bindings.first(where: { $0.id == bindingID }) else { return }
        let inferredValue = row.value ?? binding.minimum + row.x * (binding.maximum - binding.minimum)
        runtime.values[bindingID] = min(binding.maximum, max(binding.minimum, inferredValue))
    }

    private func isActive(_ row: RichAnswerUIDataRow) -> Bool {
        if runtime.selectedID == row.id { return true }
        guard let bindingID = node.bindingID,
              let binding = composition.bindings.first(where: { $0.id == bindingID }),
              let dataset else { return false }
        let value = runtime.values[bindingID] ?? binding.initialValue
        return dataset.rows.min {
            abs(($0.value ?? binding.minimum + $0.x * (binding.maximum - binding.minimum)) - value)
                < abs(($1.value ?? binding.minimum + $1.x * (binding.maximum - binding.minimum)) - value)
        }?.id == row.id
    }
}

private struct GeneratedRichAnswerControl: View {
    let node: RichAnswerUINode
    let composition: RichAnswerUIComposition
    @Binding var runtime: GeneratedRichAnswerRuntime

    @ViewBuilder
    var body: some View {
        switch node.role {
        case .slider, .scrubber, .probe:
            if let binding {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(node.label ?? binding.label)
                            .weiBeiText(10.5, weight: .medium)
                            .foregroundStyle(WeiBeiTheme.secondaryInk)
                        Spacer(minLength: 8)
                        Text(formattedValue(binding))
                            .weiBeiText(12, weight: .medium, design: .monospaced)
                            .foregroundStyle(WeiBeiTheme.ink)
                    }
                    Slider(
                        value: valueBinding(binding),
                        in: binding.minimum...binding.maximum,
                        step: binding.step
                    )
                    .controlSize(.small)
                    .accessibilityLabel(node.label ?? binding.label)
                    .accessibilityValue(formattedValue(binding))
                    .accessibilityIdentifier("rich-answer-control-\(node.id)-\(binding.id)")
                }
            }
        case .toggle:
            if let binding {
                Toggle(
                    node.label ?? binding.label,
                    isOn: Binding(
                        get: { (runtime.values[binding.id] ?? binding.initialValue) >= 0.5 },
                        set: { runtime.values[binding.id] = $0 ? 1 : 0 }
                    )
                )
                .toggleStyle(.switch)
                .controlSize(.small)
                .weiBeiText(12, weight: .medium)
                .accessibilityIdentifier("rich-answer-control-\(node.id)-\(binding.id)")
            }
        case .select:
            HStack(spacing: 6) {
                Image(systemName: "cursorarrow.click")
                    .weiBeiText(10.5, weight: .semibold)
                Text(node.label ?? "点选图中元素")
                    .weiBeiText(10.5, weight: .medium)
            }
            .foregroundStyle(WeiBeiTheme.secondaryInk)
            .accessibilityLabel(node.label ?? "点选图中元素")
            .accessibilityIdentifier("rich-answer-control-\(node.id)-select")
        case .reset:
            Button(node.label ?? "恢复初值") {
                runtime.reset(composition)
            }
            .buttonStyle(WeiBeiTextActionButtonStyle())
            .accessibilityIdentifier("rich-answer-control-\(node.id)-reset")
        default:
            EmptyView()
        }
    }

    private var binding: RichAnswerUIBinding? {
        guard let bindingID = node.bindingID else { return nil }
        return composition.bindings.first(where: { $0.id == bindingID })
    }

    private func valueBinding(_ binding: RichAnswerUIBinding) -> Binding<Double> {
        Binding(
            get: { runtime.values[binding.id] ?? binding.initialValue },
            set: { runtime.values[binding.id] = $0 }
        )
    }

    private func formattedValue(_ binding: RichAnswerUIBinding) -> String {
        let value = runtime.values[binding.id] ?? binding.initialValue
        let precision = binding.step < 1 ? 1 : 0
        let formatted = String(format: "%.*f", precision, value)
        return binding.unit.map { "\(formatted) \($0)" } ?? formatted
    }
}

private struct GeneratedRichAnswerEvidence: View {
    let node: RichAnswerUINode
    let evidenceByID: [String: RichAnswerEvidence]
    var onOpenEvidence: (RichAnswerEvidence) -> Void

    var body: some View {
        let evidence = deduplicatedEvidence
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                evidenceButtons(evidence)
            }
            VStack(alignment: .leading, spacing: 5) {
                evidenceButtons(evidence)
            }
        }
    }

    private var deduplicatedEvidence: [RichAnswerEvidence] {
        var seenSourceLabels: Set<String> = []
        return node.evidenceIDs.compactMap { evidenceByID[$0] }.filter { item in
            seenSourceLabels.insert(item.sourceLabel).inserted
        }
    }

    @ViewBuilder
    private func evidenceButtons(_ evidence: [RichAnswerEvidence]) -> some View {
        ForEach(evidence, id: \.id) { item in
            Button {
                onOpenEvidence(item)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.right")
                        .weiBeiText(9.5, weight: .semibold)
                    Text(item.sourceLabel)
                        .weiBeiText(10.5, weight: .medium)
                        .lineLimit(1)
                }
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .padding(.vertical, 3)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(WeiBeiTheme.hairline.opacity(0.48))
                        .frame(height: 1)
                }
            }
            .buttonStyle(.plain)
            .help(item.excerpt)
            .accessibilityLabel("查看来源：\(item.sourceLabel)")
            .accessibilityIdentifier("rich-answer-evidence-\(node.id)-\(item.id)")
        }
    }
}

private struct GeneratedRichAnswerCanvas: View {
    let canvasNode: RichAnswerUINode
    let composition: RichAnswerUIComposition
    @Binding var runtime: GeneratedRichAnswerRuntime
    var onOpenAsset: (String) -> Void
    var assetPreview: (String) -> NSImage?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let imageNode, let assetID = imageNode.assetID, let preview = assetPreview(assetID) {
                    Image(nsImage: preview)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(imageScale(imageNode))
                        .onTapGesture(count: 2) {
                            onOpenAsset(assetID)
                        }
                }
                Canvas { context, size in
                    drawCanvas(context: &context, size: size)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture().onEnded { value in
                    select(at: value.location, size: geometry.size)
                }
            )
        }
        .frame(height: canvasHeight)
        .background(WeiBeiTheme.paperInset.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(WeiBeiTheme.hairline.opacity(0.42), lineWidth: 1)
        }
        .accessibilityLabel(canvasAccessibilityLabel)
        .accessibilityIdentifier("rich-answer-canvas-\(canvasNode.id)")
    }

    private var markNodes: [RichAnswerUINode] {
        canvasNode.children.compactMap { childID in
            composition.nodes.first(where: { $0.id == childID })
        }
    }

    private var imageNode: RichAnswerUINode? {
        markNodes.first(where: { $0.role == .image && isVisible($0) })
    }

    private var canvasHeight: CGFloat {
        switch canvasNode.size {
        case .compact:
            return 168
        case .regular:
            return 232
        case .large:
            return 306
        }
    }

    private var canvasAccessibilityLabel: String {
        canvasNode.label ?? canvasNode.xAxis?.label ?? canvasNode.yAxis?.label ?? "富回答交互画布"
    }

    private func drawCanvas(context: inout GraphicsContext, size: CGSize) {
        let drawingRect = CGRect(x: 32, y: 18, width: max(20, size.width - 52), height: max(20, size.height - 42))
        let visibleNodes = markNodes.filter { isVisible($0) }
        if markNodes.contains(where: { $0.role == .axis }) || canvasNode.xAxis != nil || canvasNode.yAxis != nil {
            drawAxes(context: &context, rect: drawingRect)
        }
        for node in visibleNodes {
            switch node.role {
            case .area:
                drawArea(node, context: &context, rect: drawingRect)
            case .region:
                drawRegion(node, context: &context, rect: drawingRect, includeLabel: false)
            default:
                break
            }
        }
        for node in visibleNodes {
            switch node.role {
            case .line, .path:
                drawPath(node, context: &context, rect: drawingRect)
            case .vector:
                drawVectors(node, context: &context, rect: drawingRect)
            default:
                break
            }
        }
        for node in visibleNodes {
            switch node.role {
            case .shape:
                drawShapes(node, context: &context, rect: drawingRect, includeLabels: false)
            case .bar:
                drawBars(node, context: &context, rect: drawingRect, includeLabels: false)
            case .point:
                drawPoints(node, context: &context, rect: drawingRect)
            case .dotMatrix:
                drawDotMatrix(node, context: &context, rect: drawingRect)
            default:
                break
            }
        }
        drawProbe(context: &context, rect: drawingRect, includeGuide: true, includeLabel: false)
        for node in visibleNodes {
            switch node.role {
            case .shape:
                drawShapeLabels(node, context: &context, rect: drawingRect)
            case .bar:
                drawBarLabels(node, context: &context, rect: drawingRect)
            case .region:
                drawRegion(node, context: &context, rect: drawingRect, includeLabel: true)
            default:
                break
            }
        }
        var sharedLabelFrames: [CGRect] = []
        let labelNodes = visibleNodes
            .filter { $0.role == .label }
            .sorted {
                if $0.emphasis != $1.emphasis { return $0.emphasis == .strong }
                return $0.id < $1.id
            }
        for node in labelNodes {
            drawLabels(
                node,
                context: &context,
                rect: drawingRect,
                sharedOccupiedFrames: &sharedLabelFrames
            )
        }
        drawProbe(context: &context, rect: drawingRect, includeGuide: false, includeLabel: true)
    }

    private func drawAxes(context: inout GraphicsContext, rect: CGRect) {
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
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(WeiBeiTheme.tertiaryInk),
                at: CGPoint(x: rect.midX, y: rect.maxY + 10),
                anchor: .top
            )
        }
        if let yAxis = canvasNode.yAxis {
            context.draw(
                Text(axisValue(yAxis.maximum, unit: yAxis.unit))
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(WeiBeiTheme.tertiaryInk),
                at: CGPoint(x: rect.minX - 5, y: rect.minY),
                anchor: .trailing
            )
            context.draw(
                Text(axisValue(yAxis.minimum, unit: yAxis.unit))
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(WeiBeiTheme.tertiaryInk),
                at: CGPoint(x: rect.minX - 5, y: rect.maxY),
                anchor: .trailing
            )
        }
    }

    private func drawPath(_ node: RichAnswerUINode, context: inout GraphicsContext, rect: CGRect) {
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

    private func path(for rows: [RichAnswerUIDataRow], in rect: CGRect) -> Path {
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

    private func pathThroughCurrentValue(
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

    private func drawPoints(_ node: RichAnswerUINode, context: inout GraphicsContext, rect: CGRect) {
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

    private func drawArea(_ node: RichAnswerUINode, context: inout GraphicsContext, rect: CGRect) {
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

    private func drawShapes(
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

    private func drawShapeLabels(_ node: RichAnswerUINode, context: inout GraphicsContext, rect: CGRect) {
        guard node.shape != nil else { return }
        for instance in shapeInstances(for: node, rect: rect) {
            let selected = runtime.selectedID == instance.id || runtime.selectedID == node.id
            drawShapeLabel(instance: instance, node: node, selected: selected, context: &context)
        }
    }

    private func drawShapeLabel(
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
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(node.fill == .solid ? WeiBeiTheme.onCinnabar : generatedToneColor(node.tone)),
            at: CGPoint(x: instance.rect.midX, y: instance.rect.midY),
            anchor: .center
        )
    }

    private func drawBars(
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

    private func drawBarLabels(_ node: RichAnswerUINode, context: inout GraphicsContext, rect: CGRect) {
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

    private func drawBarLabel(
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
                .font(.system(size: 9.5, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? WeiBeiTheme.cinnabar : WeiBeiTheme.tertiaryInk),
            at: CGPoint(x: labelCenterX, y: rect.maxY + 7),
            anchor: .top
        )
    }

    private func drawDotMatrix(_ node: RichAnswerUINode, context: inout GraphicsContext, rect: CGRect) {
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

    private func drawFilledMark(
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

    private func drawVectors(_ node: RichAnswerUINode, context: inout GraphicsContext, rect: CGRect) {
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

    private func drawRegion(
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

    private func drawLabels(
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

    private func drawPlacedLabels(_ placements: [GeneratedCanvasLabelPlacement], context: inout GraphicsContext) {
        for placement in placements {
            let label = placement.label
            context.draw(
                Text(label.text)
                    .font(.system(size: 9.5, weight: label.required ? .semibold : .medium))
                    .foregroundStyle(label.selected ? WeiBeiTheme.cinnabar : generatedToneColor(label.tone)),
                at: placement.drawPoint,
                anchor: placement.anchor.unitPoint
            )
        }
    }

    private func measuredCanvasLabel(
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

    private func placeCanvasLabels(
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

    private func bestCanvasLabelPlacement(
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

    private func labelObstacles(excluding excludedID: String, in rect: CGRect) -> [CGRect] {
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

    private func canvasLabelDensityLimit(for labels: [GeneratedCanvasLabel], in rect: CGRect) -> Int {
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

    private func drawProbe(context: inout GraphicsContext, rect: CGRect, includeGuide: Bool, includeLabel: Bool) {
        guard let control = composition.nodes.first(where: { $0.role == .probe && $0.bindingID != nil }),
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

    private func select(at location: CGPoint, size: CGSize) {
        let rect = CGRect(x: 32, y: 18, width: max(20, size.width - 52), height: max(20, size.height - 42))
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
            if let instance = shapeInstances(for: node, rect: rect).first(where: { $0.rect.insetBy(dx: -5, dy: -5).contains(location) }) {
                runtime.selectedID = instance.id
                return
            }
        }
        for node in markNodes where node.role == .bar {
            if let instance = barInstances(for: node, rect: rect).first(where: { $0.rect.insetBy(dx: -4, dy: -4).contains(location) }) {
                runtime.selectedID = instance.id
                return
            }
        }
        let rows = markNodes
            .filter { $0.role == .point || $0.role == .dotMatrix || $0.role == .label }
            .compactMap { dataset(for: $0) }
            .flatMap(\.rows)
        runtime.selectedID = rows.min { left, right in
            distance(location, canvasPoint(left.x, left.y, in: rect))
                < distance(location, canvasPoint(right.x, right.y, in: rect))
        }.flatMap { row in
            distance(location, canvasPoint(row.x, row.y, in: rect)) <= 24 ? row.id : nil
        }
    }

    private func shapeInstances(for node: RichAnswerUINode, rect: CGRect) -> [GeneratedCanvasMarkInstance] {
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

    private func barInstances(for node: RichAnswerUINode, rect: CGRect) -> [GeneratedCanvasMarkInstance] {
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

    private func interpolatedPoint(
        in dataset: RichAnswerUIDataset,
        bindingID: String,
        rect: CGRect
    ) -> CGPoint? {
        guard let binding = composition.bindings.first(where: { $0.id == bindingID }) else { return nil }
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

    private func interpolatedRow(in dataset: RichAnswerUIDataset, binding: RichAnswerUIBinding) -> RichAnswerUIDataRow? {
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

    private func boundRow(from row: RichAnswerUIDataRow, binding: RichAnswerUIBinding) -> RichAnswerUIDataRow {
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

    private func binding(for bindingID: String) -> RichAnswerUIBinding? {
        composition.bindings.first(where: { $0.id == bindingID })
    }

    private func boundValue(for binding: RichAnswerUIBinding) -> Double {
        min(binding.maximum, max(binding.minimum, runtime.values[binding.id] ?? binding.initialValue))
    }

    private func rowBindingValue(_ row: RichAnswerUIDataRow, binding: RichAnswerUIBinding) -> Double {
        row.value ?? binding.minimum + row.x * (binding.maximum - binding.minimum)
    }

    private func formattedBindingValue(_ binding: RichAnswerUIBinding) -> String {
        let value = boundValue(for: binding)
        let precision = binding.step < 1 ? 1 : 0
        let formatted = String(format: "%.\(precision)f", value)
        return binding.unit.map { "\(binding.label)=\(formatted) \($0)" } ?? "\(binding.label)=\(formatted)"
    }

    private func interpolatedOptional(_ start: Double?, _ end: Double?, progress: Double) -> Double? {
        guard let start, let end else { return nil }
        return start + (end - start) * progress
    }

    private func interpolatedOptional(_ start: Double, _ end: Double, progress: Double) -> Double {
        start + (end - start) * progress
    }

    private func dataset(for node: RichAnswerUINode) -> RichAnswerUIDataset? {
        guard let datasetID = node.datasetID else { return nil }
        return composition.datasets.first(where: { $0.id == datasetID })
    }

    private func activeRow(in dataset: RichAnswerUIDataset, bindingID: String?) -> RichAnswerUIDataRow? {
        guard let bindingID,
              let binding = composition.bindings.first(where: { $0.id == bindingID }) else { return nil }
        let value = runtime.values[bindingID] ?? binding.initialValue
        return dataset.rows.min {
            abs(($0.value ?? binding.minimum + $0.x * (binding.maximum - binding.minimum)) - value)
                < abs(($1.value ?? binding.minimum + $1.x * (binding.maximum - binding.minimum)) - value)
        }
    }

    private func activeRows(in dataset: RichAnswerUIDataset, bindingID: String) -> [RichAnswerUIDataRow] {
        guard let binding = binding(for: bindingID) else { return [] }
        return generatedActiveRows(
            in: dataset,
            binding: binding,
            runtimeValue: runtime.values[bindingID]
        )
    }

    private func continuousActiveRowID(in dataset: RichAnswerUIDataset, bindingID: String?) -> String? {
        guard let bindingID,
              let binding = binding(for: bindingID),
              !generatedBindingIsDiscrete(binding, in: composition) else { return nil }
        return activeRow(in: dataset, bindingID: bindingID)?.id
    }

    private func isVisible(_ node: RichAnswerUINode) -> Bool {
        guard let bindingID = node.bindingID,
              node.role == .image || node.role == .region else { return true }
        return (runtime.values[bindingID] ?? 1) >= 0.5
    }

    private func imageScale(_ node: RichAnswerUINode) -> CGFloat {
        guard let bindingID = node.bindingID else { return 1 }
        return CGFloat(max(0.7, min(2, runtime.values[bindingID] ?? 1)))
    }
}

private struct GeneratedCanvasMarkInstance {
    let id: String
    let rect: CGRect
    let label: String?
}

private struct GeneratedCanvasLabel {
    let id: String
    let text: String
    let point: CGPoint
    let size: CGSize
    let tone: RichAnswerUITone
    let selected: Bool
    let required: Bool
    let priority: Int
}

private struct GeneratedCanvasLabelPlacement {
    let label: GeneratedCanvasLabel
    let anchor: GeneratedCanvasLabelAnchor
    let drawPoint: CGPoint
    let frame: CGRect
    let score: CGFloat
}

private enum GeneratedCanvasLabelAnchor: CaseIterable {
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

private func measuredCanvasLabelSize(_ text: String, maxWidth: CGFloat, required: Bool) -> CGSize {
    let font = NSFont.systemFont(ofSize: 9, weight: required ? .semibold : .medium)
    let size = (text as NSString).size(withAttributes: [.font: font])
    return CGSize(width: min(maxWidth, ceil(size.width)), height: ceil(size.height) + 1)
}

private func trimmedCanvasLabel(_ text: String, maxWidth: CGFloat) -> String {
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

private func generatedBarRangeLabel(_ firstLabel: String?, _ lastLabel: String?) -> String? {
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

private func constrainCanvasLabelFrame(_ frame: CGRect, to allowedRect: CGRect) -> CGRect {
    var constrained = frame
    if constrained.minX < allowedRect.minX {
        constrained.origin.x += allowedRect.minX - constrained.minX
    }
    if constrained.maxX > allowedRect.maxX {
        constrained.origin.x -= constrained.maxX - allowedRect.maxX
    }
    if constrained.minY < allowedRect.minY {
        constrained.origin.y += allowedRect.minY - constrained.minY
    }
    if constrained.maxY > allowedRect.maxY {
        constrained.origin.y -= constrained.maxY - allowedRect.maxY
    }
    return constrained
}

private func intersectionArea(_ first: CGRect, _ second: CGRect) -> CGFloat {
    let intersection = first.intersection(second)
    guard !intersection.isNull else { return 0 }
    return intersection.width * intersection.height
}

private func generatedShapePath(_ shape: RichAnswerUIShape, in rect: CGRect) -> Path {
    switch shape {
    case .rectangle:
        return Path(rect)
    case .roundedRectangle:
        return Path(roundedRect: rect, cornerRadius: min(9, min(rect.width, rect.height) * 0.22))
    case .circle:
        let diameter = min(rect.width, rect.height)
        return Path(ellipseIn: CGRect(
            x: rect.midX - diameter / 2,
            y: rect.midY - diameter / 2,
            width: diameter,
            height: diameter
        ))
    case .ellipse:
        return Path(ellipseIn: rect)
    case .triangle:
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    case .diamond:
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    case .capsule:
        return Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) / 2)
    }
}

private func generatedBindingIsDiscrete(
    _ binding: RichAnswerUIBinding,
    in composition: RichAnswerUIComposition
) -> Bool {
    composition.nodes.contains { node in
        node.bindingID == binding.id && [.toggle, .sequence].contains(node.role)
    }
}

private func generatedActiveRows(
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

private func generatedMeaningfulUnit(_ rawUnit: String?) -> String? {
    guard let unit = rawUnit?.trimmingCharacters(in: .whitespacesAndNewlines),
          !unit.isEmpty else { return nil }
    let placeholderUnits: Set<String> = ["值", "数值", "value", "values"]
    return placeholderUnits.contains(unit.lowercased()) ? nil : unit
}

private func interpolatedY(in dataset: RichAnswerUIDataset, at value: Double) -> Double {
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

private func canvasPoint(_ x: Double, _ y: Double, in rect: CGRect) -> CGPoint {
    CGPoint(x: rect.minX + rect.width * x, y: rect.maxY - rect.height * y)
}

private func distance(_ left: CGPoint, _ right: CGPoint) -> CGFloat {
    hypot(left.x - right.x, left.y - right.y)
}

private func drawArrowHead(context: inout GraphicsContext, start: CGPoint, end: CGPoint, color: Color) {
    let angle = atan2(end.y - start.y, end.x - start.x)
    let length: CGFloat = 8
    let spread: CGFloat = .pi / 7
    let left = CGPoint(x: end.x - length * cos(angle - spread), y: end.y - length * sin(angle - spread))
    let right = CGPoint(x: end.x - length * cos(angle + spread), y: end.y - length * sin(angle + spread))
    var head = Path()
    head.move(to: left)
    head.addLine(to: end)
    head.addLine(to: right)
    context.stroke(head, with: .color(color.opacity(0.84)), lineWidth: 1.5)
}

private func axisValue(_ value: Double, unit: String?) -> String {
    let formatted = abs(value.rounded() - value) < 0.0001
        ? String(format: "%.0f", value)
        : String(format: "%.1f", value)
    return unit.map { "\(formatted)\($0)" } ?? formatted
}

private func generatedToneColor(_ tone: RichAnswerUITone) -> Color {
    switch tone {
    case .ink:
        return WeiBeiTheme.ink
    case .muted:
        return WeiBeiTheme.secondaryInk
    case .accent:
        return WeiBeiTheme.cinnabar
    case .warning:
        return WeiBeiTheme.cinnabar.opacity(0.82)
    case .positive:
        return WeiBeiTheme.moss
    case .gridline:
        return WeiBeiTheme.hairline
    }
}

private func spacing(for spacing: RichAnswerUISpacing) -> CGFloat {
    switch spacing {
    case .tight:
        return 6
    case .regular:
        return 10
    case .loose:
        return 16
    }
}

private func horizontalAlignment(for alignment: RichAnswerUIAlignment) -> HorizontalAlignment {
    switch alignment {
    case .leading:
        return .leading
    case .center:
        return .center
    case .trailing:
        return .trailing
    }
}

private func zAlignment(for alignment: RichAnswerUIAlignment) -> Alignment {
    switch alignment {
    case .leading:
        return .topLeading
    case .center:
        return .center
    case .trailing:
        return .topTrailing
    }
}

private func generatedFrameAlignment(_ alignment: RichAnswerUIAlignment) -> Alignment {
    switch alignment {
    case .leading:
        return .leading
    case .center:
        return .center
    case .trailing:
        return .trailing
    }
}
