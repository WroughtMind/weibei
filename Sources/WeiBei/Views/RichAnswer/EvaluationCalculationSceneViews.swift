import AppKit
import SwiftUI
import WeiBeiCore

struct ComparisonEvaluationSceneView: View {
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
            if comparesFirstPair {
                comparisonRelationNotes
            }
            UnsupportedOperationNotice(
                scene: scene,
                handledOperationIDs: handledOperationIDs
            )
            EvidenceStrip(evidence: sceneEvidence, onOpenEvidence: onOpenEvidence)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WeiBeiTheme.hairline.opacity(0.72))
                .frame(height: 1)
        }
        .onRichAnswerVerificationStage { stage in
            guard stage == .after else { return }
            let before = verificationState
            advanceVerificationInteraction()
            writeDeepComponentVerificationReceipt(
                scene: scene,
                target: [
                    "id": selectedObjectID ?? "",
                    "control": "comparison",
                    "label": selectedObjectID.map(objectLabel) ?? "",
                ],
                kind: compareOperation != nil ? "compare" : "select",
                before: before,
                after: verificationState
            )
        }
    }

    private var comparisonGrid: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 0) {
                comparisonColumns
            }
            VStack(alignment: .leading, spacing: 0) {
                comparisonColumns
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(WeiBeiTheme.hairline.opacity(0.46), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var comparisonColumns: some View {
        ForEach(comparisonObjects, id: \.id) { object in
            VStack(alignment: .leading, spacing: 7) {
                Button {
                    selectedObjectID = object.id
                } label: {
                    Text(object.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selectedObjectID == object.id ? WeiBeiTheme.cinnabar : WeiBeiTheme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                Text(object.text ?? objectValueText(object))
                    .font(.caption)
                    .lineSpacing(3)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                EvidenceStrip(
                    evidence: object.evidenceIDs.compactMap { evidenceByID[$0] },
                    onOpenEvidence: onOpenEvidence
                )
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .background(columnFill(for: object))
            if object.id != comparisonObjects.last?.id {
                Divider().overlay(WeiBeiTheme.hairline.opacity(0.44))
            }
        }
    }

    private var comparisonRelationNotes: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(comparisonRelations, id: \.id) { relation in
                Text("\(relation.kind.label)：\(relation.label ?? "\(objectLabel(relation.sourceID)) 与 \(objectLabel(relation.targetID))")")
                    .font(.caption)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
            }
        }
        .padding(.leading, 2)
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

    private var comparisonObjects: [RichAnswerObject] {
        let targetIDs = Set(compareOperation?.targetIDs ?? [])
        let targeted = scene.objects.filter { targetIDs.contains($0.id) }
        return Array((targeted.count >= 2 ? targeted : scene.objects).prefix(3))
    }

    private var comparisonRelations: [RichAnswerRelation] {
        let ids = Set(comparisonObjects.map(\.id))
        return scene.relations.filter { ids.contains($0.sourceID) && ids.contains($0.targetID) }
    }

    private var handledOperationIDs: Set<String> {
        var ids = operationIDs(in: scene, matching: [.select, .reset])
        if let compareOperation,
           compareOperation.targetIDs.count >= 2,
           compareOperation.targetIDs.allSatisfy({ id in comparisonObjects.contains(where: { $0.id == id }) }) {
            ids.insert(compareOperation.id)
        }
        return ids
    }

    private var verificationState: [String: Any] {
        [
            "selectedObjectID": selectedObjectID ?? NSNull(),
            "comparesFirstPair": comparesFirstPair,
            "comparisonObjectIDs": comparisonObjects.map(\.id),
        ]
    }

    private func objectLabel(_ id: String) -> String {
        scene.objects.first(where: { $0.id == id })?.label ?? id
    }

    private func columnFill(for object: RichAnswerObject) -> Color {
        if selectedObjectID == object.id {
            return WeiBeiTheme.cinnabarSoft.opacity(0.48)
        }
        if comparesFirstPair, comparisonObjects.contains(where: { $0.id == object.id }) {
            return WeiBeiTheme.paperInset.opacity(0.24)
        }
        return Color.clear
    }

    private func advanceVerificationInteraction() {
        comparesFirstPair = compareOperation != nil
        if let currentID = selectedObjectID,
           let currentIndex = comparisonObjects.firstIndex(where: { $0.id == currentID }),
           currentIndex + 1 < comparisonObjects.count {
            selectedObjectID = comparisonObjects[currentIndex + 1].id
        } else {
            selectedObjectID = comparisonObjects.first?.id
        }
    }
}

struct CalculationConstraintSceneView: View {
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
            resultPanel
            parameterControls
            if calculableOperations.isEmpty {
                Text("当前场景没有可验证的结果采样，因此只展示公式与约束，不提供假计算。")
                    .font(.caption)
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
            }
            UnsupportedOperationNotice(
                scene: scene,
                handledOperationIDs: handledOperationIDs
            )
            EvidenceStrip(evidence: sceneEvidence, onOpenEvidence: onOpenEvidence)
        }
        .sceneSurface(fill: WeiBeiTheme.codePaper.opacity(0.16))
        .onRichAnswerVerificationStage { stage in
            guard stage == .after else { return }
            let before = verificationState
            advanceVerificationInteraction()
            writeDeepComponentVerificationReceipt(
                scene: scene,
                target: verificationTarget,
                kind: calculableOperations.first?.kind.rawValue ?? "reset",
                before: before,
                after: verificationState
            )
        }
    }

    private var formulaColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(scene.objects.filter { $0.kind == .formula || $0.kind == .constraint || $0.kind == .quantity }.prefix(8)), id: \.id) { object in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(calculationRoleLabel(object.kind))
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
            ForEach(calculableOperations, id: \.id) { operation in
                if let parameter = operation.parameter {
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
                    .tint(WeiBeiTheme.cinnabar)
                }
                }
            }
        }
    }

    private var resultPanel: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(calculableOperations, id: \.id) { operation in
                if let parameter = operation.parameter,
                   let result = sampledResult(for: operation, parameter: parameter) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                resultValue(
                                    label: parameter.label,
                                    value: parameterText(parameter, value: value(for: parameter))
                                )
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
                                resultValue(label: operation.label, value: resultText(result, for: operation))
                            }
                        }
                        Spacer(minLength: 0)
                        Text("确定性结果")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(WeiBeiTheme.cinnabar)
                    }
                }
            }
        }
        .padding(.vertical, calculableOperations.isEmpty ? 0 : 9)
        .padding(.horizontal, calculableOperations.isEmpty ? 0 : 10)
        .background(
            calculableOperations.isEmpty ? Color.clear : WeiBeiTheme.cinnabarSoft.opacity(0.20),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    private var sceneEvidence: [RichAnswerEvidence] {
        scene.evidenceIDs.compactMap { evidenceByID[$0] }
    }

    private var resetOperation: RichAnswerOperation? {
        scene.operations.first { $0.kind == .reset }
    }

    private var calculableOperations: [RichAnswerOperation] {
        scene.operations.filter { operation in
            guard operation.kind == .adjust, operation.parameter != nil else { return false }
            return sampledObjects(for: operation).count >= 2
        }
    }

    private var handledOperationIDs: Set<String> {
        var ids = Set(calculableOperations.map(\.id))
        if resetOperation != nil {
            ids.formUnion(operationIDs(in: scene, matching: [.reset]))
        }
        return ids
    }

    private func sampledObjects(for operation: RichAnswerOperation) -> [RichAnswerObject] {
        let targetIDs = Set(operation.targetIDs)
        return scene.objects.filter {
            targetIDs.contains($0.id) && $0.coordinate != nil && $0.number != nil
        }.sorted { ($0.coordinate?.x ?? 0) < ($1.coordinate?.x ?? 0) }
    }

    private func sampledResult(for operation: RichAnswerOperation, parameter: RichAnswerParameter) -> Double? {
        let samples = sampledObjects(for: operation)
        guard let first = samples.first, let firstNumber = first.number else { return nil }
        let span = parameter.maximum - parameter.minimum
        let normalizedInput = span > 0 ? (value(for: parameter) - parameter.minimum) / span : 0
        if normalizedInput <= (first.coordinate?.x ?? 0) { return firstNumber }
        if let last = samples.last,
           let lastX = last.coordinate?.x,
           let lastNumber = last.number,
           normalizedInput >= lastX {
            return lastNumber
        }
        for index in samples.indices.dropLast() {
            guard let startX = samples[index].coordinate?.x,
                  let endX = samples[index + 1].coordinate?.x,
                  let startValue = samples[index].number,
                  let endValue = samples[index + 1].number,
                  startX <= normalizedInput,
                  normalizedInput <= endX else { continue }
            let progress = (normalizedInput - startX) / max(0.0001, endX - startX)
            return startValue + (endValue - startValue) * progress
        }
        return firstNumber
    }

    private func resultText(_ result: Double, for operation: RichAnswerOperation) -> String {
        let unit = sampledObjects(for: operation).compactMap(\.unit).first
        let formatted = String(format: "%.2f", result)
            .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
        return unit.map { "\(formatted) \($0)" } ?? formatted
    }

    private func calculationRoleLabel(_ kind: RichAnswerObjectKind) -> String {
        switch kind {
        case .formula:
            return "公式"
        case .constraint:
            return "约束"
        case .quantity:
            return "常量"
        default:
            return kind.shortLabel
        }
    }

    private func resultValue(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(WeiBeiTheme.secondaryInk)
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundStyle(WeiBeiTheme.ink)
        }
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

    private var verificationState: [String: Any] {
        [
            "currentValues": currentValues,
            "didReset": didReset,
        ]
    }

    private var verificationTarget: [String: Any] {
        guard let operation = calculableOperations.first, let parameter = operation.parameter else {
            return [
                "id": resetOperation?.id ?? "calculation-reset",
                "control": "reset",
                "label": resetOperation?.label ?? "切换计算状态",
            ]
        }
        return [
            "id": operation.id,
            "control": "calculation-parameter",
            "label": operation.label,
            "parameterID": parameter.id,
        ]
    }

    private func advanceVerificationInteraction() {
        guard let parameter = calculableOperations.first?.parameter else {
            didReset.toggle()
            return
        }
        currentValues[parameter.id] = RichAnswerVerificationBridge.nextVerificationValue(
            current: value(for: parameter),
            minimum: parameter.minimum,
            maximum: parameter.maximum,
            step: parameter.step
        )
    }
}

