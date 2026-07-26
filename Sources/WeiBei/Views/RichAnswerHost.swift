import AppKit
import SwiftUI
import WeiBeiCore

import AppKit
import SwiftUI
import WeiBeiCore

struct RichAnswerHost: View {
    let presentation: RichAnswerPresentation
    var onOpenEvidence: (RichAnswerEvidence) -> Void
    var onOpenAsset: (String) -> Void
    var assetPreview: (String) -> NSImage?
    var onAction: (String) -> Void
    @State private var focusPresented = false
    @State private var focusedSceneID: String?
    @State private var selectedSceneID: String?
    @State private var readySceneIDs: Set<String> = []
    @State private var hostContentSize: CGSize = .zero

    /// Verification markers stay deferred until the host has a real layout size
    /// and every rich scene renderer has reported ready.
    private func rendererIsReady(_ updatedSceneIDs: Set<String>) -> Bool {
        let sceneIDs = Set(presentation.scenes.map(\.id))
        let everySceneReady = presentation.scenes.isEmpty
            || updatedSceneIDs.isSuperset(of: sceneIDs)
        let hostHasMeasuredSize = hostContentSize.width > 1 && hostContentSize.height > 1
        // Web runtime readiness already requires a real viewport and measured content
        // height, so it remains trustworthy when a lazy ScrollView reports a zero host height.
        let everySceneHasMeasuredWebRuntime = !presentation.scenes.isEmpty
            && presentation.scenes.allSatisfy(\.usesWebRuntime)
        return everySceneReady && (hostHasMeasuredSize || everySceneHasMeasuredWebRuntime)
    }

    init(
        presentation: RichAnswerPresentation,
        onOpenEvidence: @escaping (RichAnswerEvidence) -> Void = { _ in },
        onOpenAsset: @escaping (String) -> Void = { _ in },
        assetPreview: @escaping (String) -> NSImage? = { _ in nil },
        onAction: @escaping (String) -> Void = { _ in }
    ) {
        self.presentation = presentation
        self.onOpenEvidence = onOpenEvidence
        self.onOpenAsset = onOpenAsset
        self.assetPreview = assetPreview
        self.onAction = onAction
    }

    var body: some View {
        Group {
            if presentation.mode == .rich, !presentation.scenes.isEmpty {
                if preferredSurface == .focus {
                    focusLauncher
                } else {
                    presentationContent(
                        maxWidth: preferredSurface == .inline ? nil : preferredContentWidth,
                        expandsOverflow: false
                    )
                }
            }
        }
        .sheet(isPresented: $focusPresented) {
            ZStack {
                WeiBeiTheme.paper.ignoresSafeArea()
                ScrollView {
                    presentationContent(maxWidth: 920, expandsOverflow: true)
                        .padding(.horizontal, 34)
                        .padding(.vertical, 28)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .frame(minWidth: 860, minHeight: 640)
        }
        .background {
            GeometryReader { geometry in
                Color.clear
                    .preference(key: RichAnswerHostSizeKey.self, value: geometry.size)
            }
        }
        .onPreferenceChange(RichAnswerHostSizeKey.self) { size in
            hostContentSize = size
            updateVerificationMarker(readySceneIDs)
        }
        .onAppear {
            updateVerificationMarker(readySceneIDs)
        }
        .onChange(of: readySceneIDs) { _, updatedSceneIDs in
            updateVerificationMarker(updatedSceneIDs)
        }
        .onRichAnswerVerificationStage { stage in
            guard stage == .overview || stage == .before || stage == .after else { return }
            selectedSceneID = selectedSceneID ?? firstVerificationSceneID
        }
    }

    private func presentationContent(maxWidth: CGFloat?, expandsOverflow: Bool) -> some View {
        let scenes = displayedScenes(expandsOverflow: expandsOverflow)
        let resolvedMaxWidth = maxWidth ?? .infinity
        return VStack(alignment: .leading, spacing: preferredSurface == .inline ? 10 : 14) {
            if rendersInlineFlow(scenes) {
                inlineFlowContent(
                    scenes: scenes,
                    maxWidth: resolvedMaxWidth,
                    expandsOverflow: expandsOverflow
                )
            } else {
                if scenes.count > 1 {
                    scenePicker
                }
                if let selectedScene = selectedScene(in: scenes) {
                    sceneContent(
                        selectedScene,
                        maxWidth: resolvedMaxWidth,
                        expandsOverflow: expandsOverflow
                    )
                }
            }
            RichAnswerEvidenceLedger(
                evidence: ledgerEvidence,
                onOpenEvidence: onOpenEvidence
            )
        }
        .padding(.vertical, preferredSurface == .inline ? 2 : 8)
        .frame(maxWidth: resolvedMaxWidth, alignment: .leading)
    }

    @ViewBuilder
    private func inlineFlowContent(
        scenes: [RichAnswerScene],
        maxWidth: CGFloat,
        expandsOverflow: Bool
    ) -> some View {
        if rendersInlineWebRuntimeGroup(scenes) {
            RichAnswerWebRuntimeView(
                scenes: scenes,
                evidenceByID: evidenceByID,
                expandsOverflow: expandsOverflow,
                onRequestExpansion: {
                    focusedSceneID = scenes.count == 1 ? scenes.first?.id : nil
                    focusPresented = true
                },
                onOpenEvidence: onOpenEvidence,
                onAction: onAction,
                assetPreview: assetPreview,
                onRuntimeReady: {
                    readySceneIDs.formUnion(scenes.map(\.id))
                }
            )
            .id(scenes.map(\.id).joined(separator: "|"))
            .frame(minWidth: 0, maxWidth: maxWidth, alignment: .leading)
        } else {
            ForEach(scenes, id: \.id) { scene in
                sceneContent(
                    scene,
                    maxWidth: maxWidth,
                    expandsOverflow: expandsOverflow
                )
            }
        }
    }

    private func rendersInlineWebRuntimeGroup(_ scenes: [RichAnswerScene]) -> Bool {
        guard scenes.allSatisfy(\.usesWebRuntime) else { return false }
        return scenes.allSatisfy(\.hasProgram) || scenes.allSatisfy(\.hasRenderPlan)
    }

    private func sceneContent(
        _ scene: RichAnswerScene,
        maxWidth: CGFloat,
        expandsOverflow: Bool
    ) -> some View {
        RichAnswerSceneHost(
            scene: scene,
            evidenceByID: evidenceByID,
            expandsOverflow: expandsOverflow,
            onRequestExpansion: {
                focusedSceneID = scene.id
                focusPresented = true
            },
            onOpenEvidence: onOpenEvidence,
            onOpenAsset: onOpenAsset,
            assetPreview: assetPreview,
            onAction: onAction,
            onSceneReady: {
                readySceneIDs.insert(scene.id)
            }
        )
        .id(scene.id)
        .frame(
            minWidth: scene.usesWebRuntime ? 0 : nil,
            maxWidth: scene.usesWebRuntime ? maxWidth : nil,
            alignment: .leading
        )
    }

    private var focusLauncher: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let selectedScene {
                SceneTitle(scene: selectedScene, eyebrow: "需要更大操作空间")
            }
            Button("打开实验面") {
                focusedSceneID = selectedScene?.id
                focusPresented = true
            }
            .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
        }
        .padding(.vertical, 8)
        .frame(maxWidth: 620, alignment: .leading)
    }

    private var preferredSurface: RichAnswerSurface {
        selectedScene?.placement ?? presentation.expressionPlan?.preferredSurface ?? .inline
    }

    private func rendersInlineFlow(_ scenes: [RichAnswerScene]) -> Bool {
        presentation.expressionPlan?.preferredSurface == .inline
            && scenes.allSatisfy { $0.placement == .inline }
    }

    private func displayedScenes(expandsOverflow: Bool) -> [RichAnswerScene] {
        guard expandsOverflow,
              let focusedSceneID,
              let focusedScene = presentation.scenes.first(where: { $0.id == focusedSceneID }) else {
            return presentation.scenes
        }
        return [focusedScene]
    }

    private func selectedScene(in scenes: [RichAnswerScene]) -> RichAnswerScene? {
        if let selectedSceneID,
           let scene = scenes.first(where: { $0.id == selectedSceneID }) {
            return scene
        }
        return scenes.first
    }

    private var selectedScene: RichAnswerScene? {
        if let selectedSceneID,
           let scene = presentation.scenes.first(where: { $0.id == selectedSceneID }) {
            return scene
        }
        return presentation.scenes.first
    }

    private var firstVerificationSceneID: String? {
        presentation.scenes.first {
            $0.usesWebRuntime || $0.ui != nil || !$0.operations.isEmpty
        }?.id ?? presentation.scenes.first?.id
    }

    private var preferredContentWidth: CGFloat {
        if selectedScene?.usesWebRuntime == true || selectedScene?.ui != nil {
            return preferredSurface == .inline ? 620 : 708
        }
        guard let family = selectedScene?.family else { return 588 }
        let familyWidth: CGFloat
        switch family {
        case .textAndAlignment, .relationAndEvidence, .calculationAndConstraints:
            familyWidth = 596
        case .processAndState:
            familyWidth = 654
        case .quantityAndCoordinates, .timeAndSpace, .imageAndOverlay, .comparisonAndEvaluation:
            familyWidth = 708
        }
        return preferredSurface == .inline ? min(familyWidth, 620) : familyWidth
    }

    private var scenePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(presentation.scenes, id: \.id) { scene in
                    let isSelected = selectedScene?.id == scene.id
                    Button {
                        selectedSceneID = scene.id
                    } label: {
                        Text(scenePickerLabel(scene))
                            .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? WeiBeiTheme.cinnabar : WeiBeiTheme.secondaryInk)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 7)
                            .overlay(alignment: .bottom) {
                                Rectangle()
                                    .fill(isSelected ? WeiBeiTheme.cinnabar : Color.clear)
                                    .frame(height: 1.5)
                            }
                    }
                    .buttonStyle(.plain)
                    .help(scene.title)
                }
            }
        }
    }

    private func scenePickerLabel(_ scene: RichAnswerScene) -> String {
        if scene.usesWebRuntime || scene.ui != nil {
            return scene.title
        }
        switch scene.family {
        case .textAndAlignment:
            return "原文对齐"
        case .quantityAndCoordinates:
            return "坐标实验"
        case .processAndState:
            return "过程步进"
        case .relationAndEvidence:
            return "关系图"
        case .timeAndSpace:
            return scene.frames.contains(where: { $0.kind == .space }) ? "空间路径" : "时间线"
        case .imageAndOverlay:
            return "图像叠层"
        case .comparisonAndEvaluation:
            return "并排比较"
        case .calculationAndConstraints:
            return "计算台"
        }
    }

    private var evidenceByID: [String: RichAnswerEvidence] {
        Dictionary(uniqueKeysWithValues: presentation.evidenceLedger.map { ($0.id, $0) })
    }

    private var ledgerEvidence: [RichAnswerEvidence] {
        let usedEvidenceIDs = Set(presentation.scenes.flatMap { scene in
            scene.evidenceIDs
                + scene.objects.flatMap(\.evidenceIDs)
                + scene.relations.flatMap(\.evidenceIDs)
                + scene.frames.flatMap(\.evidenceIDs)
        })
        return presentation.evidenceLedger.filter { !usedEvidenceIDs.contains($0.id) }
    }

    private func updateVerificationMarker(_ updatedSceneIDs: Set<String>) {
        // Defer ready markers until rendererIsReady (host size + every scene ready).
        let effectiveReadyIDs = rendererIsReady(updatedSceneIDs) ? updatedSceneIDs : Set<String>()
        RichAnswerVerificationMarker.update(
            mode: presentation.mode,
            sceneIDs: presentation.scenes.map(\.id),
            readySceneIDs: effectiveReadyIDs
        )
    }
}
struct RichAnswerHostSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

extension RichAnswerScene {
    var usesWebRuntime: Bool {
        program != nil || renderPlan != nil
    }

    var hasProgram: Bool {
        program != nil
    }

    var hasRenderPlan: Bool {
        renderPlan != nil
    }
}

struct RichAnswerSceneHost: View {
    let scene: RichAnswerScene
    let evidenceByID: [String: RichAnswerEvidence]
    let expandsOverflow: Bool
    var onRequestExpansion: () -> Void
    var onOpenEvidence: (RichAnswerEvidence) -> Void
    var onOpenAsset: (String) -> Void
    var assetPreview: (String) -> NSImage?
    var onAction: (String) -> Void
    var onSceneReady: () -> Void

    var body: some View {
        if let program = scene.program {
            RichAnswerWebRuntimeView(
                scene: scene,
                program: program,
                evidenceByID: evidenceByID,
                expandsOverflow: expandsOverflow,
                onRequestExpansion: onRequestExpansion,
                onOpenEvidence: onOpenEvidence,
                onAction: onAction,
                assetPreview: assetPreview,
                onRuntimeReady: onSceneReady
            )
        } else if let renderPlan = scene.renderPlan {
            RichAnswerWebRuntimeView(
                scene: scene,
                renderPlan: renderPlan,
                evidenceByID: evidenceByID,
                expandsOverflow: expandsOverflow,
                onRequestExpansion: onRequestExpansion,
                onOpenEvidence: onOpenEvidence,
                onAction: onAction,
                assetPreview: assetPreview,
                onRuntimeReady: onSceneReady
            )
        } else if let composition = scene.ui {
            GeneratedRichAnswerSceneView(
                scene: scene,
                composition: composition,
                evidenceByID: evidenceByID,
                onOpenEvidence: onOpenEvidence,
                onOpenAsset: onOpenAsset,
                assetPreview: assetPreview,
                onSceneReady: onSceneReady
            )
        } else {
            switch scene.family {
            case .textAndAlignment:
                TextAlignmentSceneView(scene: scene, evidenceByID: evidenceByID, onOpenEvidence: onOpenEvidence)
                    .onAppear(perform: onSceneReady)
            case .quantityAndCoordinates:
                QuantityCoordinateSceneView(scene: scene, evidenceByID: evidenceByID, onOpenEvidence: onOpenEvidence)
                    .onAppear(perform: onSceneReady)
            case .processAndState:
                ProcessStateSceneView(scene: scene, evidenceByID: evidenceByID, onOpenEvidence: onOpenEvidence)
                    .onAppear(perform: onSceneReady)
            case .relationAndEvidence:
                RelationEvidenceSceneView(scene: scene, evidenceByID: evidenceByID, onOpenEvidence: onOpenEvidence)
                    .onAppear(perform: onSceneReady)
            case .timeAndSpace:
                TimeSpaceSceneView(scene: scene, evidenceByID: evidenceByID, onOpenEvidence: onOpenEvidence)
                    .onAppear(perform: onSceneReady)
            case .imageAndOverlay:
                ImageOverlaySceneView(
                    scene: scene,
                    evidenceByID: evidenceByID,
                    onOpenEvidence: onOpenEvidence,
                    onOpenAsset: onOpenAsset,
                    assetPreview: assetPreview
                )
                .onAppear(perform: onSceneReady)
            case .comparisonAndEvaluation:
                ComparisonEvaluationSceneView(scene: scene, evidenceByID: evidenceByID, onOpenEvidence: onOpenEvidence)
                    .onAppear(perform: onSceneReady)
            case .calculationAndConstraints:
                CalculationConstraintSceneView(scene: scene, evidenceByID: evidenceByID, onOpenEvidence: onOpenEvidence)
                    .onAppear(perform: onSceneReady)
            }
        }
    }
}

func writeDeepComponentVerificationReceipt(
    scene: RichAnswerScene,
    target: [String: Any],
    kind: String,
    before: [String: Any],
    after: [String: Any]
) {
    RichAnswerVerificationBridge.writeInteractionReceipt(
        sceneID: scene.id,
        sceneTitle: scene.title,
        target: target,
        kind: kind,
        before: before,
        after: after,
        changed: RichAnswerVerificationBridge.changed(before, after),
        source: "deep-component"
    )
}
