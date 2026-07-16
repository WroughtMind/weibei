import SwiftUI
import WeiBeiCore

struct RichAnswerHost: View {
    let presentation: RichAnswerPresentation
    var onOpenEvidence: (RichAnswerEvidence) -> Void
    var onOpenAsset: (String) -> Void
    @State private var focusPresented = false

    init(
        presentation: RichAnswerPresentation,
        onOpenEvidence: @escaping (RichAnswerEvidence) -> Void = { _ in },
        onOpenAsset: @escaping (String) -> Void = { _ in }
    ) {
        self.presentation = presentation
        self.onOpenEvidence = onOpenEvidence
        self.onOpenAsset = onOpenAsset
    }

    var body: some View {
        Group {
            if presentation.mode == .rich, !presentation.scenes.isEmpty {
                if preferredSurface == .focus {
                    focusLauncher
                } else {
                    presentationContent(maxWidth: preferredSurface == .inline ? 620 : 760)
                }
            }
        }
        .sheet(isPresented: $focusPresented) {
            ZStack {
                WeiBeiTheme.paper.ignoresSafeArea()
                ScrollView {
                    presentationContent(maxWidth: 980)
                        .padding(.horizontal, 34)
                        .padding(.vertical, 28)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .frame(minWidth: 860, minHeight: 640)
        }
    }

    private func presentationContent(maxWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: preferredSurface == .inline ? 10 : 14) {
            RichAnswerHeader(presentation: presentation)
            ForEach(presentation.scenes, id: \.id) { scene in
                RichAnswerSceneHost(
                    scene: scene,
                    evidenceByID: evidenceByID,
                    onOpenEvidence: onOpenEvidence,
                    onOpenAsset: onOpenAsset
                )
                .id(scene.id)
            }
            RichAnswerEvidenceLedger(
                evidence: ledgerEvidence,
                onOpenEvidence: onOpenEvidence
            )
        }
        .padding(.vertical, preferredSurface == .inline ? 4 : 8)
        .frame(maxWidth: maxWidth, alignment: .leading)
    }

    private var focusLauncher: some View {
        VStack(alignment: .leading, spacing: 10) {
            RichAnswerHeader(presentation: presentation)
            Text("这个场景需要更大的观察与操作空间。")
                .font(.caption)
                .foregroundStyle(WeiBeiTheme.secondaryInk)
            Button("打开聚焦实验面") {
                focusPresented = true
            }
            .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
        }
        .padding(.vertical, 8)
        .frame(maxWidth: 620, alignment: .leading)
    }

    private var preferredSurface: RichAnswerSurface {
        presentation.expressionPlan?.preferredSurface ?? .inline
    }

    private var evidenceByID: [String: RichAnswerEvidence] {
        Dictionary(uniqueKeysWithValues: presentation.evidenceLedger.map { ($0.id, $0) })
    }

    private var ledgerEvidence: [RichAnswerEvidence] {
        guard presentation.scenes.count == 1 else { return presentation.evidenceLedger }
        let inlineEvidenceIDs = Set(presentation.scenes[0].evidenceIDs)
        return presentation.evidenceLedger.filter { !inlineEvidenceIDs.contains($0.id) }
    }
}

private struct RichAnswerHeader: View {
    let presentation: RichAnswerPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text("富回答")
                    .font(WeiBeiTypography.englishBrandFont(size: 10.5, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.82))
                Text(surfaceLabel)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                Spacer(minLength: 0)
                evidenceStatePill
            }

            if let summary = presentation.expressionPlan?.summary, !summary.isEmpty {
                Text(summary)
                    .font(.system(size: 12.5))
                    .lineSpacing(3)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !presentation.diagnostics.isEmpty {
                Text("部分内容已按当前材料自动简化；正文结论仍可直接阅读。")
                    .font(.caption)
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
            }
        }
        .padding(.leading, 13)
        .overlay(alignment: .leading) {
            Capsule()
                .fill(WeiBeiTheme.cinnabar.opacity(0.52))
                .frame(width: 2, height: 32)
        }
    }

    private var surfaceLabel: String {
        guard let preferredSurface = presentation.expressionPlan?.preferredSurface else {
            return "知识场景"
        }
        switch preferredSurface {
        case .inline:
            return "正文内研读"
        case .expanded:
            return "展开研习面"
        case .focus:
            return "聚焦实验面"
        }
    }

    private var evidenceStatePill: some View {
        Text(evidenceStateLabel)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(evidenceStateColor)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(WeiBeiTheme.paperInset.opacity(0.24), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(WeiBeiTheme.hairline.opacity(0.48), lineWidth: 1)
            }
    }

    private var evidenceStateLabel: String {
        switch presentation.evidenceState {
        case .complete:
            return "证据完整"
        case .partial:
            return "证据部分可用"
        case .missing:
            return "证据缺口"
        }
    }

    private var evidenceStateColor: Color {
        switch presentation.evidenceState {
        case .complete:
            return WeiBeiTheme.moss
        case .partial:
            return WeiBeiTheme.link
        case .missing:
            return WeiBeiTheme.cinnabar
        }
    }
}

private struct RichAnswerSceneHost: View {
    let scene: RichAnswerScene
    let evidenceByID: [String: RichAnswerEvidence]
    var onOpenEvidence: (RichAnswerEvidence) -> Void
    var onOpenAsset: (String) -> Void

    var body: some View {
        switch scene.family {
        case .textAndAlignment:
            TextAlignmentSceneView(scene: scene, evidenceByID: evidenceByID, onOpenEvidence: onOpenEvidence)
        case .quantityAndCoordinates:
            QuantityCoordinateSceneView(scene: scene, evidenceByID: evidenceByID, onOpenEvidence: onOpenEvidence)
        case .processAndState:
            ProcessStateSceneView(scene: scene, evidenceByID: evidenceByID, onOpenEvidence: onOpenEvidence)
        case .relationAndEvidence:
            RelationEvidenceSceneView(scene: scene, evidenceByID: evidenceByID, onOpenEvidence: onOpenEvidence)
        case .timeAndSpace:
            TimeSpaceSceneView(scene: scene, evidenceByID: evidenceByID, onOpenEvidence: onOpenEvidence)
        case .imageAndOverlay:
            ImageOverlaySceneView(scene: scene, evidenceByID: evidenceByID, onOpenEvidence: onOpenEvidence, onOpenAsset: onOpenAsset)
        case .comparisonAndEvaluation:
            ComparisonEvaluationSceneView(scene: scene, evidenceByID: evidenceByID, onOpenEvidence: onOpenEvidence)
        case .calculationAndConstraints:
            CalculationConstraintSceneView(scene: scene, evidenceByID: evidenceByID, onOpenEvidence: onOpenEvidence)
        }
    }
}

private struct TextAlignmentSceneView: View {
    let scene: RichAnswerScene
    let evidenceByID: [String: RichAnswerEvidence]
    var onOpenEvidence: (RichAnswerEvidence) -> Void
    @State private var selectedObjectID: String?
    @State private var revealsNotes = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SceneTitle(scene: scene, eyebrow: "文本 / 对齐")
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    textColumn
                    relationMargin.frame(width: 210, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 10) {
                    textColumn
                    relationMargin
                }
            }
            UnsupportedOperationNotice(
                scene: scene,
                handledOperationIDs: operationIDs(in: scene, matching: [.select, .reveal])
            )
        }
        .sceneInkBand(color: WeiBeiTheme.cinnabar.opacity(0.42), fill: WeiBeiTheme.paperRaised.opacity(0.20))
    }

    private var textColumn: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(scene.objects.prefix(8)), id: \.id) { object in
                Button {
                    selectedObjectID = object.id
                    revealsNotes = true
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(object.label)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(selectedObjectID == object.id ? WeiBeiTheme.cinnabar : WeiBeiTheme.ink)
                        if let text = object.text, !text.isEmpty {
                            Text(text)
                                .font(.system(size: 13.5))
                                .lineSpacing(4)
                                .foregroundStyle(WeiBeiTheme.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(selectedObjectID == object.id ? WeiBeiTheme.cinnabarSoft.opacity(0.52) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var relationMargin: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(revealsNotes ? "边注已展开" : "点原文展开边注")
                .font(.caption)
                .foregroundStyle(WeiBeiTheme.tertiaryInk)
            ForEach(Array(scene.relations.prefix(revealsNotes ? 6 : 3)), id: \.id) { relation in
                Text(relationLabel(relation))
                    .font(.caption)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .padding(.leading, 8)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(relationColor(relation.kind).opacity(0.62))
                            .frame(width: 2)
                    }
            }
            EvidenceStrip(evidence: sceneEvidence, onOpenEvidence: onOpenEvidence)
        }
    }

    private var sceneEvidence: [RichAnswerEvidence] {
        scene.evidenceIDs.compactMap { evidenceByID[$0] }
    }

    private func relationLabel(_ relation: RichAnswerRelation) -> String {
        let source = objectLabel(relation.sourceID)
        let target = objectLabel(relation.targetID)
        return "\(source) \(relation.kind.label) \(target)"
    }

    private func objectLabel(_ objectID: String) -> String {
        scene.objects.first(where: { $0.id == objectID })?.label ?? objectID
    }
}

private struct QuantityCoordinateSceneView: View {
    let scene: RichAnswerScene
    let evidenceByID: [String: RichAnswerEvidence]
    var onOpenEvidence: (RichAnswerEvidence) -> Void
    @State private var selectedObjectID: String?
    @State private var fallbackProbeValue = 0.5
    @State private var adjustmentValues: [String: Double] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SceneTitle(scene: scene, eyebrow: "数量 / 坐标")
            CoordinateCanvas(
                scene: scene,
                selectedObjectID: $selectedObjectID,
                probeValue: chartProbeValue,
                probeLabel: chartProbeLabel
            )
                .frame(height: 174)
                .background(WeiBeiTheme.paperInset.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(WeiBeiTheme.hairline.opacity(0.48), lineWidth: 1)
                }
            probeControl
            UnsupportedOperationNotice(
                scene: scene,
                handledOperationIDs: handledOperationIDs
            )
            EvidenceStrip(evidence: sceneEvidence, onOpenEvidence: onOpenEvidence)
        }
        .sceneInkBand(color: WeiBeiTheme.link.opacity(0.40), fill: Color.clear)
    }

    @ViewBuilder
    private var probeControl: some View {
        if let operation = primaryAdjustment, let parameter = operation.parameter {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(operation.label)
                        .font(.caption)
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                    Spacer(minLength: 8)
                    Text(parameterText(parameter, value: adjustmentValue(for: operation, parameter: parameter)))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(WeiBeiTheme.ink)
                    if let resetOperation {
                        Button(resetOperation.label) {
                            resetInteraction()
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle())
                    }
                }
                Slider(
                    value: adjustmentBinding(for: operation, parameter: parameter),
                    in: parameter.minimum...parameter.maximum,
                    step: max(parameter.step, 0.0001)
                )
                .tint(WeiBeiTheme.cinnabar)
                Text("拖动参数，图中的朱砂探针会同步移动。")
                    .font(.caption2)
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
            }
        } else if scene.operations.contains(where: { $0.kind == .probe }) {
            HStack(spacing: 10) {
                Text("观察位置")
                    .font(.caption)
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
                Slider(value: $fallbackProbeValue, in: 0...1)
                    .tint(WeiBeiTheme.cinnabar)
                Text(String(format: "%.0f%%", fallbackProbeValue * 100))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
            }
        }
    }

    private var sceneEvidence: [RichAnswerEvidence] {
        scene.evidenceIDs.compactMap { evidenceByID[$0] }
    }

    private var primaryAdjustment: RichAnswerOperation? {
        scene.operations.first { $0.kind == .adjust && $0.parameter != nil }
    }

    private var resetOperation: RichAnswerOperation? {
        scene.operations.first { $0.kind == .reset }
    }

    private var handledOperationIDs: Set<String> {
        var ids = operationIDs(in: scene, matching: [.probe, .select, .reset])
        if let primaryAdjustment {
            ids.insert(primaryAdjustment.id)
        }
        return ids
    }

    private var chartProbeValue: Double? {
        guard let operation = primaryAdjustment, let parameter = operation.parameter else {
            return scene.operations.contains(where: { $0.kind == .probe }) ? fallbackProbeValue : nil
        }
        let span = parameter.maximum - parameter.minimum
        guard span > 0 else { return 0.5 }
        let normalizedValue = (adjustmentValue(for: operation, parameter: parameter) - parameter.minimum) / span
        return min(1, max(0, normalizedValue))
    }

    private var chartProbeLabel: String? {
        guard let operation = primaryAdjustment, let parameter = operation.parameter else { return nil }
        return parameterText(parameter, value: adjustmentValue(for: operation, parameter: parameter))
    }

    private func adjustmentValue(for operation: RichAnswerOperation, parameter: RichAnswerParameter) -> Double {
        adjustmentValues[operation.id] ?? parameter.initialValue
    }

    private func adjustmentBinding(for operation: RichAnswerOperation, parameter: RichAnswerParameter) -> Binding<Double> {
        Binding(
            get: { adjustmentValue(for: operation, parameter: parameter) },
            set: { adjustmentValues[operation.id] = $0 }
        )
    }

    private func resetInteraction() {
        adjustmentValues.removeAll()
        fallbackProbeValue = 0.5
        selectedObjectID = nil
    }
}

private struct ProcessStateSceneView: View {
    let scene: RichAnswerScene
    let evidenceByID: [String: RichAnswerEvidence]
    var onOpenEvidence: (RichAnswerEvidence) -> Void
    @State private var activeIndex = 0
    @State private var isPlaying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SceneTitle(scene: scene, eyebrow: "过程 / 状态")
                Spacer(minLength: 10)
                if let playOperation {
                    Button(isPlaying ? "暂停" : playOperation.label) {
                        isPlaying.toggle()
                    }
                    .buttonStyle(WeiBeiTextActionButtonStyle(active: isPlaying))
                }
            }
            processBand
            activeStepDetail
            processControls
            UnsupportedOperationNotice(
                scene: scene,
                handledOperationIDs: operationIDs(in: scene, matching: [.select, .step, .playPause, .reset])
            )
            EvidenceStrip(evidence: sceneEvidence, onOpenEvidence: onOpenEvidence)
        }
        .sceneUnderline(color: WeiBeiTheme.moss.opacity(0.52))
        .task(id: isPlaying) {
            guard isPlaying else { return }
            while !Task.isCancelled, isPlaying {
                do {
                    try await Task.sleep(nanoseconds: 850_000_000)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                if activeIndex + 1 < scene.objects.count {
                    activeIndex += 1
                } else {
                    isPlaying = false
                }
            }
        }
    }

    private var processBand: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(scene.objects.enumerated()), id: \.element.id) { index, object in
                    Button {
                        activeIndex = index
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(index + 1)")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(index == activeIndex ? WeiBeiTheme.onCinnabar : WeiBeiTheme.secondaryInk)
                                .frame(width: 22, height: 22)
                                .background(index == activeIndex ? WeiBeiTheme.cinnabar : WeiBeiTheme.paperInset.opacity(0.34), in: Circle())
                            Text(object.label)
                                .font(.caption)
                                .foregroundStyle(WeiBeiTheme.ink)
                                .lineLimit(2)
                                .frame(width: 96, alignment: .leading)
                        }
                        .padding(.trailing, 12)
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .topTrailing) {
                        if index < scene.objects.count - 1 {
                            Rectangle()
                                .fill(WeiBeiTheme.hairline.opacity(0.62))
                                .frame(width: 20, height: 1)
                                .offset(x: 4, y: 11)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var activeStepDetail: some View {
        let object = scene.objects.indices.contains(activeIndex) ? scene.objects[activeIndex] : scene.objects.first
        return VStack(alignment: .leading, spacing: 4) {
            Text(object?.label ?? "未选择步骤")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.ink)
            Text(object?.text ?? "这里仅切换本地步骤观察状态，不推断新的过程结果。")
                .font(.caption)
                .lineSpacing(3)
                .foregroundStyle(WeiBeiTheme.secondaryInk)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(WeiBeiTheme.paperRaised.opacity(0.34), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var processControls: some View {
        if stepOperation != nil || resetOperation != nil {
            HStack(spacing: 6) {
                if stepOperation != nil {
                    Button("上一步") {
                        isPlaying = false
                        activeIndex = max(0, activeIndex - 1)
                    }
                    .buttonStyle(WeiBeiTextActionButtonStyle())
                    Text("\(min(activeIndex + 1, max(scene.objects.count, 1))) / \(max(scene.objects.count, 1))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                    Button("下一步") {
                        isPlaying = false
                        activeIndex = min(max(scene.objects.count - 1, 0), activeIndex + 1)
                    }
                    .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
                }
                if let resetOperation {
                    Button(resetOperation.label) {
                        isPlaying = false
                        activeIndex = 0
                    }
                    .buttonStyle(WeiBeiTextActionButtonStyle())
                }
            }
        }
    }

    private var playOperation: RichAnswerOperation? {
        scene.operations.first { $0.kind == .playPause }
    }

    private var stepOperation: RichAnswerOperation? {
        scene.operations.first { $0.kind == .step }
    }

    private var resetOperation: RichAnswerOperation? {
        scene.operations.first { $0.kind == .reset }
    }

    private var sceneEvidence: [RichAnswerEvidence] {
        scene.evidenceIDs.compactMap { evidenceByID[$0] }
    }
}

private struct RelationEvidenceSceneView: View {
    let scene: RichAnswerScene
    let evidenceByID: [String: RichAnswerEvidence]
    var onOpenEvidence: (RichAnswerEvidence) -> Void
    @State private var focusedRelationID: String?
    @State private var showsAllEvidence = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SceneTitle(scene: scene, eyebrow: "关系 / 证据")
                Spacer(minLength: 10)
                Button(showsAllEvidence ? "收起来源" : "展开来源") {
                    showsAllEvidence.toggle()
                }
                .buttonStyle(WeiBeiTextActionButtonStyle(active: showsAllEvidence))
                if let resetOperation {
                    Button(resetOperation.label) {
                        focusedRelationID = nil
                        showsAllEvidence = false
                    }
                    .buttonStyle(WeiBeiTextActionButtonStyle())
                }
            }
            relationRows
            if showsAllEvidence || scene.relations.isEmpty {
                EvidenceStrip(evidence: sceneEvidence, onOpenEvidence: onOpenEvidence)
            }
            UnsupportedOperationNotice(
                scene: scene,
                handledOperationIDs: operationIDs(in: scene, matching: [.select, .reveal, .reset])
            )
        }
        .padding(.vertical, 10)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(WeiBeiTheme.hairline.opacity(0.72))
                .frame(width: 1)
        }
    }

    private var relationRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(scene.relations.prefix(10)), id: \.id) { relation in
                Button {
                    focusedRelationID = relation.id
                    showsAllEvidence = true
                } label: {
                    HStack(alignment: .top, spacing: 9) {
                        Text(relation.kind.label)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(relationColor(relation.kind))
                            .frame(width: 52, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(objectLabel(relation.sourceID)) → \(objectLabel(relation.targetID))")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(WeiBeiTheme.ink)
                            if let label = relation.label, !label.isEmpty {
                                Text(label)
                                    .font(.caption)
                                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 9)
                    .background(focusedRelationID == relation.id ? WeiBeiTheme.paperInset.opacity(0.34) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 10)
    }

    private var sceneEvidence: [RichAnswerEvidence] {
        scene.evidenceIDs.compactMap { evidenceByID[$0] }
    }

    private var resetOperation: RichAnswerOperation? {
        scene.operations.first { $0.kind == .reset }
    }

    private func objectLabel(_ objectID: String) -> String {
        scene.objects.first(where: { $0.id == objectID })?.label ?? objectID
    }
}

private struct TimeSpaceSceneView: View {
    let scene: RichAnswerScene
    let evidenceByID: [String: RichAnswerEvidence]
    var onOpenEvidence: (RichAnswerEvidence) -> Void
    @State private var scrubPosition = 0.0
    @State private var activeLayerIDs: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SceneTitle(scene: scene, eyebrow: "时间 / 空间")
                Spacer(minLength: 10)
                if let resetOperation {
                    Button(resetOperation.label) {
                        scrubPosition = 0
                        activeLayerIDs.removeAll()
                    }
                    .buttonStyle(WeiBeiTextActionButtonStyle())
                }
            }
            TimelineCanvas(scene: scene, scrubPosition: scrubPosition, activeLayerIDs: activeLayerIDs)
                .frame(height: 142)
                .background(WeiBeiTheme.paperRaised.opacity(0.25))
            if scene.operations.contains(where: { $0.kind == .scrub }) {
                HStack(spacing: 10) {
                    Text("时间尺")
                        .font(.caption)
                        .foregroundStyle(WeiBeiTheme.tertiaryInk)
                    Slider(value: $scrubPosition, in: 0...1)
                        .tint(WeiBeiTheme.link)
                }
            }
            if !toggleFrames.isEmpty {
                layerControls
            }
            UnsupportedOperationNotice(
                scene: scene,
                handledOperationIDs: handledOperationIDs
            )
            EvidenceStrip(evidence: sceneEvidence, onOpenEvidence: onOpenEvidence)
        }
        .sceneInkBand(color: WeiBeiTheme.link.opacity(0.45), fill: WeiBeiTheme.paperRaised.opacity(0.12))
    }

    private var layerControls: some View {
        FlowLayout(spacing: 6) {
            ForEach(toggleFrames, id: \.id) { frame in
                Button {
                    if activeLayerIDs.contains(frame.id) {
                        activeLayerIDs.remove(frame.id)
                    } else {
                        activeLayerIDs.insert(frame.id)
                    }
                } label: {
                    Label(frame.title, systemImage: activeLayerIDs.contains(frame.id) ? "checkmark.circle.fill" : "circle")
                        .font(.caption)
                        .foregroundStyle(activeLayerIDs.contains(frame.id) ? WeiBeiTheme.link : WeiBeiTheme.secondaryInk)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var toggleFrames: [RichAnswerFrame] {
        let targetIDs = Set(toggleOperations.flatMap(\.targetIDs))
        return Array(scene.frames.lazy.filter { targetIDs.contains($0.id) }.prefix(6))
    }

    private var toggleOperations: [RichAnswerOperation] {
        scene.operations.filter { $0.kind == .toggle }
    }

    private var handledOperationIDs: Set<String> {
        let visibleFrameIDs = Set(toggleFrames.map(\.id))
        let handledToggleIDs = toggleOperations.lazy.filter {
            !$0.targetIDs.isEmpty && $0.targetIDs.allSatisfy(visibleFrameIDs.contains)
        }.map(\.id)
        return operationIDs(in: scene, matching: [.scrub, .reset])
            .union(handledToggleIDs)
    }

    private var sceneEvidence: [RichAnswerEvidence] {
        scene.evidenceIDs.compactMap { evidenceByID[$0] }
    }

    private var resetOperation: RichAnswerOperation? {
        scene.operations.first { $0.kind == .reset }
    }
}

private struct ImageOverlaySceneView: View {
    let scene: RichAnswerScene
    let evidenceByID: [String: RichAnswerEvidence]
    var onOpenEvidence: (RichAnswerEvidence) -> Void
    var onOpenAsset: (String) -> Void
    @State private var selectedRegionID: String?
    @State private var showsOverlay = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SceneTitle(scene: scene, eyebrow: "图像 / 叠层")
                Spacer(minLength: 10)
                if scene.operations.contains(where: { $0.kind == .toggle }) {
                    Button(showsOverlay ? "隐藏叠层" : "显示叠层") {
                        showsOverlay.toggle()
                    }
                    .buttonStyle(WeiBeiTextActionButtonStyle(active: showsOverlay))
                }
            }
            imageFallbackStage
            assetButtons
            UnsupportedOperationNotice(
                scene: scene,
                handledOperationIDs: operationIDs(in: scene, matching: [.select, .toggle])
            )
            EvidenceStrip(evidence: sceneEvidence, onOpenEvidence: onOpenEvidence)
        }
        .sceneUnderline(color: WeiBeiTheme.cinnabar.opacity(0.44))
    }

    private var imageFallbackStage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(WeiBeiTheme.codePaper.opacity(0.72))
            VStack(spacing: 5) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 26))
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
                Text("原图暂不嵌入回答")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                Text("先查看叠层位置，也可以打开原始素材对照。")
                    .font(.caption)
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
            }
            if showsOverlay {
                ImageRegionOverlay(scene: scene, selectedRegionID: $selectedRegionID)
                    .padding(12)
            }
        }
        .frame(height: 188)
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(WeiBeiTheme.hairline.opacity(0.54), lineWidth: 1)
        }
    }

    private var assetButtons: some View {
        FlowLayout(spacing: 6) {
            ForEach(assetIDs, id: \.self) { assetID in
                Button {
                    onOpenAsset(assetID)
                } label: {
                    Text("打开原始素材")
                        .font(.caption)
                        .lineLimit(1)
                }
                .buttonStyle(WeiBeiTextActionButtonStyle())
                .help(assetID)
            }
        }
    }

    private var assetIDs: [String] {
        Array(Set(scene.objects.compactMap(\.assetID) + scene.frames.compactMap(\.assetID) + sceneEvidence.flatMap(\.assetIDs))).sorted()
    }

    private var sceneEvidence: [RichAnswerEvidence] {
        scene.evidenceIDs.compactMap { evidenceByID[$0] }
    }
}

private struct ComparisonEvaluationSceneView: View {
    let scene: RichAnswerScene
    let evidenceByID: [String: RichAnswerEvidence]
    var onOpenEvidence: (RichAnswerEvidence) -> Void
    @State private var selectedObjectID: String?
    @State private var comparesFirstPair = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SceneTitle(scene: scene, eyebrow: "比较 / 评价")
                Spacer(minLength: 10)
                if let compareOperation {
                    Button(comparesFirstPair ? "取消对照" : compareOperation.label) {
                        comparesFirstPair.toggle()
                    }
                    .buttonStyle(WeiBeiTextActionButtonStyle(active: comparesFirstPair))
                }
                if let resetOperation {
                    Button(resetOperation.label) {
                        selectedObjectID = nil
                        comparesFirstPair = false
                    }
                    .buttonStyle(WeiBeiTextActionButtonStyle())
                }
            }
            comparisonGrid
            UnsupportedOperationNotice(
                scene: scene,
                handledOperationIDs: operationIDs(in: scene, matching: [.select, .compare, .reset])
            )
            EvidenceStrip(evidence: sceneEvidence, onOpenEvidence: onOpenEvidence)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WeiBeiTheme.hairline.opacity(0.72))
                .frame(height: 1)
        }
    }

    private var comparisonGrid: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(scene.objects.prefix(8)), id: \.id) { object in
                Button {
                    selectedObjectID = object.id
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Text(object.label)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(selectedObjectID == object.id ? WeiBeiTheme.cinnabar : WeiBeiTheme.ink)
                            .frame(width: 128, alignment: .leading)
                        Text(object.text ?? objectValueText(object))
                            .font(.caption)
                            .lineSpacing(3)
                            .foregroundStyle(WeiBeiTheme.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 8)
                    .background(rowFill(for: object))
                }
                .buttonStyle(.plain)
                Divider().overlay(WeiBeiTheme.hairline.opacity(0.42))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(WeiBeiTheme.hairline.opacity(0.46), lineWidth: 1)
        }
    }

    private var sceneEvidence: [RichAnswerEvidence] {
        scene.evidenceIDs.compactMap { evidenceByID[$0] }
    }

    private var compareOperation: RichAnswerOperation? {
        scene.operations.first { $0.kind == .compare }
    }

    private var resetOperation: RichAnswerOperation? {
        scene.operations.first { $0.kind == .reset }
    }

    private func rowFill(for object: RichAnswerObject) -> Color {
        if selectedObjectID == object.id {
            return WeiBeiTheme.cinnabarSoft.opacity(0.48)
        }
        if comparesFirstPair, scene.objects.prefix(2).contains(where: { $0.id == object.id }) {
            return WeiBeiTheme.paperInset.opacity(0.24)
        }
        return Color.clear
    }
}

private struct CalculationConstraintSceneView: View {
    let scene: RichAnswerScene
    let evidenceByID: [String: RichAnswerEvidence]
    var onOpenEvidence: (RichAnswerEvidence) -> Void
    @State private var currentValues: [String: Double] = [:]
    @State private var didReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SceneTitle(scene: scene, eyebrow: "计算 / 约束")
                Spacer(minLength: 10)
                if let resetOperation {
                    Button(resetOperation.label) {
                        currentValues.removeAll()
                        didReset.toggle()
                    }
                    .buttonStyle(WeiBeiTextActionButtonStyle(active: didReset))
                }
            }
            formulaColumn
            parameterControls
            Text("本地控件只调整输入展示，不在宿主里补算未知公式；真实结果必须来自已校验场景。")
                .font(.caption)
                .foregroundStyle(WeiBeiTheme.tertiaryInk)
            UnsupportedOperationNotice(
                scene: scene,
                handledOperationIDs: operationIDs(in: scene, matching: [.adjust, .reset])
            )
            EvidenceStrip(evidence: sceneEvidence, onOpenEvidence: onOpenEvidence)
        }
        .sceneInkBand(color: WeiBeiTheme.moss.opacity(0.48), fill: WeiBeiTheme.codePaper.opacity(0.20))
    }

    private var formulaColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(scene.objects.filter { $0.kind == .formula || $0.kind == .constraint || $0.kind == .quantity }.prefix(8)), id: \.id) { object in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(object.kind.shortLabel)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(WeiBeiTheme.cinnabar)
                    Text(object.text ?? objectValueText(object))
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(WeiBeiTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .background(WeiBeiTheme.paperRaised.opacity(0.30), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var parameterControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(scene.operations.filter { $0.kind == .adjust }.compactMap(\.parameter), id: \.id) { parameter in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(parameter.label)
                            .font(.caption)
                            .foregroundStyle(WeiBeiTheme.secondaryInk)
                        Spacer(minLength: 8)
                        Text(parameterText(parameter, value: value(for: parameter)))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(WeiBeiTheme.tertiaryInk)
                    }
                    Slider(
                        value: binding(for: parameter),
                        in: parameter.minimum...parameter.maximum,
                        step: max(parameter.step, 0.0001)
                    )
                    .tint(WeiBeiTheme.moss)
                }
            }
        }
    }

    private var sceneEvidence: [RichAnswerEvidence] {
        scene.evidenceIDs.compactMap { evidenceByID[$0] }
    }

    private var resetOperation: RichAnswerOperation? {
        scene.operations.first { $0.kind == .reset }
    }

    private func value(for parameter: RichAnswerParameter) -> Double {
        currentValues[parameter.id] ?? parameter.initialValue
    }

    private func binding(for parameter: RichAnswerParameter) -> Binding<Double> {
        Binding(
            get: { value(for: parameter) },
            set: { currentValues[parameter.id] = $0 }
        )
    }
}

private struct UnsupportedOperationNotice: View {
    let scene: RichAnswerScene
    let handledOperationIDs: Set<String>

    var body: some View {
        if !unsupportedOperations.isEmpty {
            Text("当前宿主尚未开放：\(unsupportedOperations.map(\.label).joined(separator: "、"))。已保留正文与静态场景，不提供假操作。")
                .font(.caption2)
                .foregroundStyle(WeiBeiTheme.tertiaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var unsupportedOperations: [RichAnswerOperation] {
        scene.operations.filter { !handledOperationIDs.contains($0.id) }
    }
}

private struct SceneTitle: View {
    let scene: RichAnswerScene
    let eyebrow: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(eyebrow)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.tertiaryInk)
            Text(scene.title)
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct CoordinateCanvas: View {
    let scene: RichAnswerScene
    @Binding var selectedObjectID: String?
    let probeValue: Double?
    let probeLabel: String?

    var body: some View {
        Canvas { context, size in
            let inset: CGFloat = 24
            let drawingRect = CGRect(
                x: inset,
                y: 16,
                width: max(10, size.width - inset - 18),
                height: max(10, size.height - 40)
            )
            var axisPath = Path()
            axisPath.move(to: CGPoint(x: drawingRect.minX, y: drawingRect.maxY))
            axisPath.addLine(to: CGPoint(x: drawingRect.maxX, y: drawingRect.maxY))
            axisPath.move(to: CGPoint(x: drawingRect.minX, y: drawingRect.maxY))
            axisPath.addLine(to: CGPoint(x: drawingRect.minX, y: drawingRect.minY))
            context.stroke(axisPath, with: .color(WeiBeiTheme.hairline.opacity(0.92)), lineWidth: 1)

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
                    with: .color(selectedObjectID == object.id ? WeiBeiTheme.cinnabar : WeiBeiTheme.link)
                )
            }
            context.stroke(tracePath, with: .color(WeiBeiTheme.link.opacity(0.72)), lineWidth: 1.4)

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
        .contentShape(Rectangle())
        .onTapGesture {
            selectedObjectID = scene.objects.first?.id
        }
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

private struct TimelineCanvas: View {
    let scene: RichAnswerScene
    let scrubPosition: Double
    let activeLayerIDs: Set<String>

    var body: some View {
        Canvas { context, size in
            let centerY = size.height * 0.54
            let startX: CGFloat = 18
            let endX = max(startX + 20, size.width - 18)
            var linePath = Path()
            linePath.move(to: CGPoint(x: startX, y: centerY))
            linePath.addLine(to: CGPoint(x: endX, y: centerY))
            context.stroke(linePath, with: .color(WeiBeiTheme.hairline.opacity(0.92)), lineWidth: 1)

            for (index, object) in scene.objects.prefix(12).enumerated() {
                let divisor = max(1, min(scene.objects.count, 12) - 1)
                let objectX = startX + (endX - startX) * CGFloat(index) / CGFloat(divisor)
                let isLayerActive = object.frameID.map { activeLayerIDs.contains($0) } ?? activeLayerIDs.isEmpty
                let color = isLayerActive ? WeiBeiTheme.link : WeiBeiTheme.tertiaryInk.opacity(0.45)
                context.fill(
                    Path(ellipseIn: CGRect(x: objectX - 4, y: centerY - 4, width: 8, height: 8)),
                    with: .color(color)
                )
            }

            let scrubX = startX + (endX - startX) * CGFloat(scrubPosition)
            var scrubPath = Path()
            scrubPath.move(to: CGPoint(x: scrubX, y: 18))
            scrubPath.addLine(to: CGPoint(x: scrubX, y: size.height - 18))
            context.stroke(scrubPath, with: .color(WeiBeiTheme.cinnabar.opacity(0.50)), lineWidth: 1.2)
        }
        .overlay(alignment: .topLeading) {
            Text(scene.objects.first?.label ?? "时间线")
                .font(.caption)
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .padding(9)
        }
    }
}

private struct ImageRegionOverlay: View {
    let scene: RichAnswerScene
    @Binding var selectedRegionID: String?

    var body: some View {
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
                context.stroke(
                    Path(roundedRect: rect, cornerRadius: 6),
                    with: .color(selected ? WeiBeiTheme.cinnabar : WeiBeiTheme.moss.opacity(0.82)),
                    style: StrokeStyle(lineWidth: selected ? 2 : 1.2, dash: selected ? [] : [5, 4])
                )
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedRegionID = scene.objects.first(where: { $0.bounds != nil })?.id
        }
    }
}

private struct EvidenceStrip: View {
    let evidence: [RichAnswerEvidence]
    var onOpenEvidence: (RichAnswerEvidence) -> Void

    var body: some View {
        if !evidence.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(evidence, id: \.id) { item in
                    EvidenceChip(evidence: item, onOpenEvidence: onOpenEvidence)
                }
            }
        }
    }
}

private struct RichAnswerEvidenceLedger: View {
    let evidence: [RichAnswerEvidence]
    var onOpenEvidence: (RichAnswerEvidence) -> Void

    var body: some View {
        if !evidence.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text("来源索引")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
                EvidenceStrip(evidence: evidence, onOpenEvidence: onOpenEvidence)
            }
            .padding(.top, 2)
        }
    }
}

private struct EvidenceChip: View {
    let evidence: RichAnswerEvidence
    var onOpenEvidence: (RichAnswerEvidence) -> Void

    var body: some View {
        Button {
            onOpenEvidence(evidence)
        } label: {
            HStack(spacing: 5) {
                Text(evidence.sourceLabel)
                    .font(.system(size: 10.5, weight: .semibold))
                    .lineLimit(1)
                ForEach(Array(evidence.tags).sorted().prefix(2), id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 9.5))
                        .foregroundStyle(WeiBeiTheme.link)
                }
                if evidence.isTruncated {
                    Text("截断")
                        .font(.system(size: 9.5))
                        .foregroundStyle(WeiBeiTheme.cinnabar)
                }
            }
            .foregroundStyle(WeiBeiTheme.secondaryInk)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(WeiBeiTheme.paperInset.opacity(0.22), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(WeiBeiTheme.hairline.opacity(0.44), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .help(evidence.excerpt)
    }
}

private struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: spacing) {
                content
            }
            VStack(alignment: .leading, spacing: spacing) {
                content
            }
        }
    }
}

private extension View {
    func sceneInkBand(color: Color, fill: Color) -> some View {
        self
            .padding(.vertical, 11)
            .padding(.leading, 13)
            .padding(.trailing, 10)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(color)
                    .frame(width: 2)
                    .padding(.vertical, 10)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(WeiBeiTheme.hairline.opacity(0.34), lineWidth: 1)
            }
    }

    func sceneUnderline(color: Color) -> some View {
        self
            .padding(.vertical, 10)
            .padding(.horizontal, 2)
            .overlay(alignment: .bottomLeading) {
                Rectangle()
                    .fill(color)
                    .frame(width: 96, height: 1.5)
            }
    }

    func operationControlSurface() -> some View {
        self
            .padding(.vertical, 5)
            .padding(.horizontal, 7)
            .background(WeiBeiTheme.paperRaised.opacity(0.38), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(WeiBeiTheme.hairline.opacity(0.32), lineWidth: 1)
            }
    }
}

private func objectValueText(_ object: RichAnswerObject) -> String {
    if let number = object.number {
        let formatted = String(format: "%.3g", number)
        return object.unit.map { "\(formatted) \($0)" } ?? formatted
    }
    return object.label
}

private func parameterText(_ parameter: RichAnswerParameter, value: Double) -> String {
    let formatted = String(format: "%.3g", value)
    return parameter.unit.map { "\(formatted) \($0)" } ?? formatted
}

private func operationIDs(
    in scene: RichAnswerScene,
    matching kinds: Set<RichAnswerOperationKind>
) -> Set<String> {
    Set(scene.operations.lazy.filter { kinds.contains($0.kind) }.map(\.id))
}

private func frameAxisLabel(_ frame: RichAnswerFrame) -> String {
    let xAxis = frame.xAxis.map { $0.label } ?? "x"
    let yAxis = frame.yAxis.map { $0.label } ?? "y"
    return "\(frame.title)：\(xAxis) / \(yAxis)"
}

private func relationColor(_ kind: RichAnswerRelationKind) -> Color {
    switch kind {
    case .supports, .aligns, .contains:
        return WeiBeiTheme.moss
    case .refutes, .contrasts, .constrains:
        return WeiBeiTheme.cinnabar
    case .causes, .dependsOn, .transforms:
        return WeiBeiTheme.link
    case .precedes:
        return WeiBeiTheme.tertiaryInk
    }
}

private func clamp01(_ value: Double) -> CGFloat {
    CGFloat(min(1, max(0, value)))
}

private extension RichAnswerRelationKind {
    var label: String {
        switch self {
        case .supports:
            return "支持"
        case .refutes:
            return "反驳"
        case .causes:
            return "导致"
        case .precedes:
            return "先于"
        case .aligns:
            return "对齐"
        case .contains:
            return "包含"
        case .transforms:
            return "转化"
        case .dependsOn:
            return "依赖"
        case .contrasts:
            return "对照"
        case .constrains:
            return "约束"
        }
    }
}

private extension RichAnswerObjectKind {
    var shortLabel: String {
        switch self {
        case .text:
            return "TXT"
        case .quantity:
            return "QTY"
        case .formula:
            return "FML"
        case .event:
            return "EVT"
        case .region:
            return "RGN"
        case .state:
            return "STA"
        case .claim:
            return "CLM"
        case .image:
            return "IMG"
        case .dataPoint:
            return "DAT"
        case .step:
            return "STP"
        case .constraint:
            return "CST"
        case .option:
            return "OPT"
        }
    }
}
