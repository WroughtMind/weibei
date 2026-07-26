import AppKit
import SwiftUI
import WeiBeiCore

struct ProcessStateSceneView: View {
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
        .padding(.vertical, 10)
        .task(id: isPlaying) {
            guard isPlaying else { return }
            while !Task.isCancelled, isPlaying {
                do {
                    try await Task.sleep(nanoseconds: 850_000_000)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                if activeIndex + 1 < processObjects.count {
                    activeIndex += 1
                } else {
                    isPlaying = false
                }
            }
        }
        .onRichAnswerVerificationStage { stage in
            guard stage == .after else { return }
            let before = verificationState
            advanceVerificationInteraction()
            writeDeepComponentVerificationReceipt(
                scene: scene,
                target: [
                    "id": activeStepID ?? "",
                    "control": "process-step",
                    "label": activeStepLabel,
                ],
                kind: "step",
                before: before,
                after: verificationState
            )
        }
    }

    private var processBand: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(processObjects.enumerated()), id: \.element.id) { index, object in
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
                        if index < processObjects.count - 1 {
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
        let object = processObjects.indices.contains(activeIndex) ? processObjects[activeIndex] : processObjects.first
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
                    Text("\(min(activeIndex + 1, max(processObjects.count, 1))) / \(max(processObjects.count, 1))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                    Button("下一步") {
                        isPlaying = false
                        activeIndex = min(max(processObjects.count - 1, 0), activeIndex + 1)
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

    private var activeStepID: String? {
        processObjects.indices.contains(activeIndex) ? processObjects[activeIndex].id : processObjects.first?.id
    }

    private var activeStepLabel: String {
        activeStepID.flatMap { id in processObjects.first(where: { $0.id == id })?.label } ?? ""
    }

    private var verificationState: [String: Any] {
        [
            "activeIndex": activeIndex,
            "activeStepID": activeStepID ?? NSNull(),
            "isPlaying": isPlaying,
        ]
    }

    private var processObjects: [RichAnswerObject] {
        let operationTargets = Set(scene.operations.filter {
            $0.kind == .step || $0.kind == .playPause || $0.kind == .select
        }.flatMap(\.targetIDs))
        let candidates = scene.objects.filter {
            operationTargets.isEmpty
                ? ($0.kind == .step || $0.kind == .state)
                : operationTargets.contains($0.id)
        }
        let base = candidates.isEmpty ? scene.objects : candidates
        let baseIDs = Set(base.map(\.id))
        let transitions = scene.relations.filter {
            ($0.kind == .precedes || $0.kind == .transforms)
                && baseIDs.contains($0.sourceID)
                && baseIDs.contains($0.targetID)
        }
        guard !transitions.isEmpty else { return base }

        let targetIDs = Set(transitions.map(\.targetID))
        guard var currentID = base.first(where: { !targetIDs.contains($0.id) })?.id else { return base }
        var ordered: [RichAnswerObject] = []
        var visited: Set<String> = []
        while !visited.contains(currentID), let object = base.first(where: { $0.id == currentID }) {
            ordered.append(object)
            visited.insert(currentID)
            guard let nextID = transitions.first(where: { $0.sourceID == currentID })?.targetID else { break }
            currentID = nextID
        }
        ordered.append(contentsOf: base.filter { !visited.contains($0.id) })
        return ordered
    }

    private func advanceVerificationInteraction() {
        isPlaying = false
        activeIndex = min(max(processObjects.count - 1, 0), activeIndex + 1)
    }
}

struct RelationEvidenceSceneView: View {
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
            RelationMapCanvas(scene: scene, focusedRelationID: $focusedRelationID)
                .frame(height: 244)
                .visualCanvasSurface()
            focusedRelationDetail
            if showsAllEvidence || scene.relations.isEmpty {
                EvidenceStrip(evidence: focusedEvidence, onOpenEvidence: onOpenEvidence)
            }
            UnsupportedOperationNotice(
                scene: scene,
                handledOperationIDs: operationIDs(in: scene, matching: [.select, .reveal, .reset])
            )
        }
        .padding(.vertical, 10)
        .onRichAnswerVerificationStage { stage in
            guard stage == .after else { return }
            let before = verificationState
            advanceVerificationInteraction()
            writeDeepComponentVerificationReceipt(
                scene: scene,
                target: [
                    "id": focusedRelationID ?? "",
                    "control": "relation-focus",
                    "label": focusedRelation.map { "\(objectLabel($0.sourceID)) → \(objectLabel($0.targetID))" } ?? "",
                ],
                kind: "select",
                before: before,
                after: verificationState
            )
        }
    }

    @ViewBuilder
    private var focusedRelationDetail: some View {
        if let relation = focusedRelation {
            HStack(alignment: .top, spacing: 8) {
                Text(relation.kind.label)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(relationColor(relation.kind))
                Text("\(objectLabel(relation.sourceID)) → \(objectLabel(relation.targetID))")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.ink)
                if let label = relation.label, !label.isEmpty {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 9)
            .background(WeiBeiTheme.paperInset.opacity(0.22), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }

    private var focusedRelation: RichAnswerRelation? {
        focusedRelationID.flatMap { id in scene.relations.first(where: { $0.id == id }) }
    }

    private var focusedEvidence: [RichAnswerEvidence] {
        let ids = focusedRelation.map { Set($0.evidenceIDs) } ?? Set(scene.evidenceIDs)
        return ids.compactMap { evidenceByID[$0] }
    }

    private var resetOperation: RichAnswerOperation? {
        scene.operations.first { $0.kind == .reset }
    }

    private var verificationState: [String: Any] {
        [
            "focusedRelationID": focusedRelationID ?? NSNull(),
            "showsAllEvidence": showsAllEvidence,
            "focusedEvidenceIDs": focusedEvidence.map(\.id),
        ]
    }

    private func objectLabel(_ objectID: String) -> String {
        scene.objects.first(where: { $0.id == objectID })?.label ?? objectID
    }

    private func advanceVerificationInteraction() {
        if let currentID = focusedRelationID,
           let currentIndex = scene.relations.firstIndex(where: { $0.id == currentID }),
           currentIndex + 1 < scene.relations.count {
            focusedRelationID = scene.relations[currentIndex + 1].id
        } else {
            focusedRelationID = scene.relations.first?.id
        }
        showsAllEvidence = true
    }
}

