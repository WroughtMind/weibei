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
    var onSceneReady: () -> Void
    @State private var runtime: GeneratedRichAnswerRuntime

    init(
        scene: RichAnswerScene,
        composition: RichAnswerUIComposition,
        evidenceByID: [String: RichAnswerEvidence],
        onOpenEvidence: @escaping (RichAnswerEvidence) -> Void,
        onOpenAsset: @escaping (String) -> Void,
        assetPreview: @escaping (String) -> NSImage?,
        onSceneReady: @escaping () -> Void = {}
    ) {
        self.scene = scene
        self.composition = composition
        self.evidenceByID = evidenceByID
        self.onOpenEvidence = onOpenEvidence
        self.onOpenAsset = onOpenAsset
        self.assetPreview = assetPreview
        self.onSceneReady = onSceneReady
        _runtime = State(initialValue: GeneratedRichAnswerRuntime(composition: composition))
    }

    var body: some View {
        let compositionIndex = GeneratedRichAnswerCompositionIndex(composition: composition)
        GeneratedRichAnswerNodeView(
            nodeID: composition.rootID,
            composition: composition,
            compositionIndex: compositionIndex,
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
        .onAppear(perform: onSceneReady)
        .onRichAnswerVerificationStage { stage in
            guard stage == .after else { return }
            let before = runtime.verificationStateSnapshot()
            let advance = runtime.advanceVerificationInteraction(composition)
            let after = runtime.verificationStateSnapshot()
            RichAnswerVerificationBridge.writeInteractionReceipt(
                sceneID: scene.id,
                sceneTitle: scene.title,
                target: advance.target,
                kind: advance.kind,
                before: before,
                after: after,
                changed: RichAnswerVerificationBridge.changed(before, after),
                source: "generated-ui"
            )
        }
    }
}

struct GeneratedVerificationAdvanceResult {
    var target: [String: Any]
    var kind: String
}

struct GeneratedRichAnswerRuntime: Equatable {
    var values: [String: Double]
    var selectedID: String?

    init(composition: RichAnswerUIComposition) {
        values = Dictionary(uniqueKeysWithValues: composition.bindings.map { ($0.id, $0.initialValue) })
    }

    mutating func reset(_ composition: RichAnswerUIComposition) {
        values = Dictionary(uniqueKeysWithValues: composition.bindings.map { ($0.id, $0.initialValue) })
        selectedID = nil
    }

    func verificationStateSnapshot() -> [String: Any] {
        [
            "values": Dictionary(uniqueKeysWithValues: values.map { ($0.key, $0.value) }),
            "selectedID": selectedID ?? NSNull(),
        ]
    }

    mutating func advanceVerificationInteraction(_ composition: RichAnswerUIComposition) -> GeneratedVerificationAdvanceResult {
        var target: [String: Any] = [:]
        var kind = "generated-ui"
        if let binding = composition.bindings.first {
            let beforeValue = values[binding.id] ?? binding.initialValue
            let afterValue = RichAnswerVerificationBridge.nextVerificationValue(
                current: beforeValue,
                minimum: binding.minimum,
                maximum: binding.maximum,
                step: binding.step
            )
            values[binding.id] = afterValue
            target = [
                "id": binding.id,
                "label": binding.label,
                "control": "binding",
                "beforeValue": beforeValue,
                "afterValue": afterValue,
            ]
            kind = "binding"
        }
        if selectedID == nil,
           let selectableID = firstSelectableID(in: composition) {
            selectedID = selectableID
            if target.isEmpty {
                target = [
                    "id": selectableID,
                    "control": "selectable-node",
                ]
                kind = "select"
            }
        }
        if target.isEmpty {
            target = [
                "id": composition.rootID,
                "control": "composition-root",
            ]
        }
        return GeneratedVerificationAdvanceResult(target: target, kind: kind)
    }

    private func firstSelectableID(in composition: RichAnswerUIComposition) -> String? {
        if let rowID = composition.datasets.first(where: { !$0.rows.isEmpty })?.rows.first?.id {
            return rowID
        }
        return composition.nodes.first {
            [.region, .shape, .bar, .point, .dotMatrix, .label, .sequence].contains($0.role)
        }?.id
    }
}

struct GeneratedRichAnswerNodeView: View {
    let nodeID: String
    let composition: RichAnswerUIComposition
    let compositionIndex: GeneratedRichAnswerCompositionIndex
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
                    compositionIndex: compositionIndex,
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
        compositionIndex.node(id: nodeID)
    }

    @ViewBuilder
    private func childViews(_ node: RichAnswerUINode) -> some View {
        ForEach(deduplicatedChildIDs(for: node), id: \.self) { childID in
            GeneratedRichAnswerNodeView(
                nodeID: childID,
                composition: composition,
                compositionIndex: compositionIndex,
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
            guard let child = compositionIndex.node(id: childID),
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
            compositionIndex.node(id: childID)
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
            compositionIndex.node(id: childID)
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

struct GeneratedRichAnswerText: View {
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

struct GeneratedRichAnswerMetric: View {
    let node: RichAnswerUINode
    let composition: RichAnswerUIComposition
    let runtime: GeneratedRichAnswerRuntime

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let label = node.label {
                Text(label)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
            }
            Text(displayValue)
                .font(.system(size: node.emphasis == .strong ? 22 : 18, weight: .semibold, design: .monospaced))
                .foregroundStyle(generatedToneColor(node.tone))
            if let text = node.text, !text.isEmpty {
                Text(text)
                    .font(.caption2)
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

struct GeneratedRichAnswerSequence: View {
    let node: RichAnswerUINode
    let composition: RichAnswerUIComposition
    @Binding var runtime: GeneratedRichAnswerRuntime

    var body: some View {
        if let dataset, !dataset.rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if let label = node.label, !label.isEmpty {
                    Text(label)
                        .font(.system(size: 10.5, weight: .semibold))
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
                            .font(.system(size: 10.5, weight: isActive(row) ? .semibold : .regular))
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
                            .font(.system(size: 11, weight: isActive(row) ? .semibold : .regular))
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
                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
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

struct GeneratedRichAnswerControl: View {
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
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(WeiBeiTheme.secondaryInk)
                        Spacer(minLength: 8)
                        Text(formattedValue(binding))
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
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
                .font(.system(size: 11.5, weight: .medium))
                .accessibilityIdentifier("rich-answer-control-\(node.id)-\(binding.id)")
            }
        case .select:
            HStack(spacing: 6) {
                Image(systemName: "cursorarrow.click")
                    .font(.system(size: 10, weight: .semibold))
                Text(node.label ?? "点选图中元素")
                    .font(.system(size: 10.5, weight: .medium))
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

struct GeneratedRichAnswerEvidence: View {
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
                        .font(.system(size: 8.5, weight: .semibold))
                    Text(item.sourceLabel)
                        .font(.system(size: 10.5, weight: .medium))
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
