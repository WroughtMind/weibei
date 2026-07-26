import AppKit
import SwiftUI
import WeiBeiCore

struct TextAlignmentSceneView: View {
    let scene: RichAnswerScene
    let evidenceByID: [String: RichAnswerEvidence]
    var onOpenEvidence: (RichAnswerEvidence) -> Void
    @State private var selectedObjectID: String?
    @State private var revealsNotes = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SceneTitle(scene: scene, eyebrow: "文本 / 对齐")
                Spacer(minLength: 8)
                if let resetOperation {
                    Button(resetOperation.label) {
                        selectedObjectID = nil
                        revealsNotes = false
                    }
                    .buttonStyle(WeiBeiTextActionButtonStyle())
                }
            }
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
                handledOperationIDs: operationIDs(in: scene, matching: [.select, .reveal, .reset])
            )
        }
        .sceneSurface(fill: WeiBeiTheme.paperRaised.opacity(0.12))
        .onRichAnswerVerificationStage { stage in
            guard stage == .after else { return }
            let before = verificationState
            advanceVerificationInteraction()
            writeDeepComponentVerificationReceipt(
                scene: scene,
                target: [
                    "id": selectedObjectID ?? "",
                    "control": "text-selection",
                    "label": selectedObjectID.map(objectLabel) ?? "",
                ],
                kind: "select",
                before: before,
                after: verificationState
            )
        }
    }

    private var textColumn: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(selectableObjects.prefix(8)), id: \.id) { object in
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
            Text(selectedObjectID == nil ? "选择原文查看对应边注" : "当前段落的关系与依据")
                .font(.caption)
                .foregroundStyle(WeiBeiTheme.tertiaryInk)
            ForEach(Array(visibleRelations.prefix(revealsNotes ? 6 : 3)), id: \.id) { relation in
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
            EvidenceStrip(evidence: visibleEvidence, onOpenEvidence: onOpenEvidence)
        }
    }

    private var selectableObjects: [RichAnswerObject] {
        let targetIDs = Set(scene.operations.filter { $0.kind == .select }.flatMap(\.targetIDs))
        guard !targetIDs.isEmpty else { return scene.objects }
        return scene.objects.filter { targetIDs.contains($0.id) }
    }

    private var visibleRelations: [RichAnswerRelation] {
        guard let selectedObjectID else { return scene.relations }
        return scene.relations.filter {
            $0.sourceID == selectedObjectID || $0.targetID == selectedObjectID
        }
    }

    private var visibleEvidence: [RichAnswerEvidence] {
        let objectEvidence = selectedObjectID.flatMap { id in
            scene.objects.first(where: { $0.id == id })?.evidenceIDs
        } ?? []
        let evidenceIDs = Set(objectEvidence + visibleRelations.flatMap(\.evidenceIDs))
        let resolvedIDs = evidenceIDs.isEmpty ? Set(scene.evidenceIDs) : evidenceIDs
        return resolvedIDs.compactMap { evidenceByID[$0] }
    }

    private var resetOperation: RichAnswerOperation? {
        scene.operations.first { $0.kind == .reset }
    }

    private var verificationState: [String: Any] {
        [
            "selectedObjectID": selectedObjectID ?? NSNull(),
            "revealsNotes": revealsNotes,
            "visibleRelationIDs": visibleRelations.map(\.id),
        ]
    }

    private func advanceVerificationInteraction() {
        if let currentID = selectedObjectID,
           let currentIndex = selectableObjects.firstIndex(where: { $0.id == currentID }),
           currentIndex + 1 < selectableObjects.count {
            selectedObjectID = selectableObjects[currentIndex + 1].id
        } else {
            selectedObjectID = selectableObjects.first?.id
        }
        revealsNotes = true
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

struct QuantityCoordinateSceneView: View {
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
                .visualCanvasSurface()
            probeControl
            UnsupportedOperationNotice(
                scene: scene,
                handledOperationIDs: handledOperationIDs
            )
        }
        .sceneSurface(fill: Color.clear, horizontalPadding: 0)
        .onRichAnswerVerificationStage { stage in
            guard stage == .after else { return }
            let before = verificationState
            advanceVerificationInteraction()
            writeDeepComponentVerificationReceipt(
                scene: scene,
                target: verificationTarget,
                kind: primaryAdjustment != nil ? "adjust" : "probe",
                before: before,
                after: verificationState
            )
        }
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

    private var verificationState: [String: Any] {
        [
            "adjustmentValues": adjustmentValues,
            "fallbackProbeValue": fallbackProbeValue,
            "selectedObjectID": selectedObjectID ?? NSNull(),
            "chartProbeValue": chartProbeValue ?? NSNull(),
        ]
    }

    private var verificationTarget: [String: Any] {
        if let operation = primaryAdjustment, let parameter = operation.parameter {
            return [
                "id": operation.id,
                "control": "adjustment",
                "label": operation.label,
                "parameterID": parameter.id,
            ]
        }
        return [
            "id": scene.operations.first(where: { $0.kind == .probe })?.id ?? "fallback-probe",
            "control": "probe",
            "label": "观察位置",
        ]
    }

    private func advanceVerificationInteraction() {
        if let operation = primaryAdjustment, let parameter = operation.parameter {
            adjustmentValues[operation.id] = RichAnswerVerificationBridge.nextVerificationValue(
                current: adjustmentValue(for: operation, parameter: parameter),
                minimum: parameter.minimum,
                maximum: parameter.maximum,
                step: parameter.step
            )
        } else if scene.operations.contains(where: { $0.kind == .probe }) {
            fallbackProbeValue = fallbackProbeValue < 0.66 ? 0.74 : 0.32
        }
        selectedObjectID = selectedObjectID ?? scene.objects.first(where: { $0.coordinate != nil })?.id
    }
}
