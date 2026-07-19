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
    private var rendererIsReady: Bool {
        hostContentSize.width > 1
            && hostContentSize.height > 1
            && (presentation.scenes.isEmpty
                || readySceneIDs.isSuperset(of: Set(presentation.scenes.map(\.id))))
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
            if !presentation.diagnostics.isEmpty {
                Text("部分内容因证据或宿主能力不足已自动收敛，正文结论仍然保留。")
                    .font(.caption)
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
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
        if scenes.allSatisfy({ $0.program != nil }) {
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
            minWidth: scene.program == nil ? nil : 0,
            maxWidth: scene.program == nil ? nil : maxWidth,
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
            $0.program != nil || $0.ui != nil || !$0.operations.isEmpty
        }?.id ?? presentation.scenes.first?.id
    }

    private var preferredContentWidth: CGFloat {
        if selectedScene?.program != nil || selectedScene?.ui != nil {
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
        if scene.program != nil || scene.ui != nil {
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
        let effectiveReadyIDs = rendererIsReady ? updatedSceneIDs : Set<String>()
        RichAnswerVerificationMarker.update(
            mode: presentation.mode,
            sceneIDs: presentation.scenes.map(\.id),
            readySceneIDs: effectiveReadyIDs
        )
    }
}

private struct RichAnswerHostSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

private enum RichAnswerVerificationMarker {
    static func update(
        mode: RichAnswerPresentationMode,
        sceneIDs: [String],
        readySceneIDs: Set<String>
    ) {
        guard isVerificationRichAnswerRun else { return }
        guard mode == .rich,
              !sceneIDs.isEmpty,
              readySceneIDs.isSuperset(of: Set(sceneIDs)) else {
            holdPrematureVerificationMarkerIfNeeded()
            return
        }
        writeRendererReadyMarkerIfPossible(mode: mode, sceneIDs: sceneIDs)
    }

    private static var isVerificationRichAnswerRun: Bool {
        let environment = ProcessInfo.processInfo.environment
        guard environment["WEIBEI_SUPPRESS_ACTIVATION"] == "1" else { return false }
        if environment["WEIBEI_VERIFY_RICH_ANSWER_REPLAY"]?.isEmpty == false { return true }
        guard let scenario = environment["WEIBEI_VERIFY_SCENARIO"] else { return false }
        return RichAnswerVerificationFixture.supports(scenario)
    }

    private static func writeRendererReadyMarkerIfPossible(
        mode: RichAnswerPresentationMode,
        sceneIDs: [String]
    ) {
        guard let workspaceDirectory = ProcessInfo.processInfo.environment["WEIBEI_WORKSPACE_DIR"],
              !workspaceDirectory.isEmpty else { return }
        let baseURL = URL(fileURLWithPath: workspaceDirectory, isDirectory: true)
        restoreDeferredVerificationMarkerIfNeeded(in: baseURL)
        let markerURL = baseURL.appendingPathComponent("rich-answer-renderer-ready.txt")
        guard !FileManager.default.fileExists(atPath: markerURL.path) else { return }
        let summary = [
            "ready=renderer",
            "mode=\(mode.rawValue)",
            "scenes=\(sceneIDs.count)",
            "ids=\(sceneIDs.joined(separator: ","))",
        ].joined(separator: "\n") + "\n"
        try? summary.write(
            to: markerURL,
            atomically: true,
            encoding: .utf8
        )
        let stateURL = baseURL.appendingPathComponent("verification-state.txt")
        let previous = (try? String(contentsOf: stateURL, encoding: .utf8)) ?? ""
        try? "\(previous)rich-answer-renderer-ready\n".write(to: stateURL, atomically: true, encoding: .utf8)
    }

    private static func holdPrematureVerificationMarkerIfNeeded() {
        guard let workspaceDirectory = ProcessInfo.processInfo.environment["WEIBEI_WORKSPACE_DIR"],
              !workspaceDirectory.isEmpty else { return }
        let baseURL = URL(fileURLWithPath: workspaceDirectory, isDirectory: true)
        let markerURL = verificationMarkerURL(in: baseURL)
        guard FileManager.default.fileExists(atPath: markerURL.path),
              !FileManager.default.fileExists(atPath: baseURL.appendingPathComponent("rich-answer-renderer-ready.txt").path) else { return }
        let pendingURL = deferredVerificationMarkerURL(in: baseURL)
        if !FileManager.default.fileExists(atPath: pendingURL.path),
           let marker = try? Data(contentsOf: markerURL) {
            try? marker.write(to: pendingURL, options: .atomic)
        }
        try? FileManager.default.removeItem(at: markerURL)
    }

    private static func restoreDeferredVerificationMarkerIfNeeded(in baseURL: URL) {
        let markerURL = verificationMarkerURL(in: baseURL)
        guard !FileManager.default.fileExists(atPath: markerURL.path) else { return }
        let pendingURL = deferredVerificationMarkerURL(in: baseURL)
        guard let marker = try? Data(contentsOf: pendingURL) else { return }
        try? marker.write(to: markerURL, options: .atomic)
        try? FileManager.default.removeItem(at: pendingURL)
    }

    private static func verificationMarkerURL(in baseURL: URL) -> URL {
        let environment = ProcessInfo.processInfo.environment
        let isReplay = environment["WEIBEI_VERIFY_RICH_ANSWER_REPLAY"]?.isEmpty == false
        return baseURL.appendingPathComponent(isReplay ? "rich-answer-replay-verified.txt" : "rich-answer-verified.txt")
    }

    private static func deferredVerificationMarkerURL(in baseURL: URL) -> URL {
        baseURL.appendingPathComponent("rich-answer-deferred-verified.txt")
    }
}

private struct RichAnswerSceneHost: View {
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

private func writeDeepComponentVerificationReceipt(
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

private struct TextAlignmentSceneView: View {
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

private struct RelationMapCanvas: View {
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

private struct RelationMapEdges: View {
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

private struct RelationMapNode: View {
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
            sceneCanvas
                .frame(height: 142)
                .visualCanvasSurface()
            if scene.operations.contains(where: { $0.kind == .scrub }) {
                HStack(spacing: 10) {
                    Text("时间尺")
                        .font(.caption)
                        .foregroundStyle(WeiBeiTheme.tertiaryInk)
                    Slider(value: $scrubPosition, in: 0...1)
                        .tint(WeiBeiTheme.cinnabar)
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
        .sceneSurface(fill: WeiBeiTheme.paperRaised.opacity(0.08))
        .onRichAnswerVerificationStage { stage in
            guard stage == .after else { return }
            let before = verificationState
            advanceVerificationInteraction()
            writeDeepComponentVerificationReceipt(
                scene: scene,
                target: verificationTarget,
                kind: scene.operations.contains(where: { $0.kind == .scrub }) ? "scrub" : "toggle",
                before: before,
                after: verificationState
            )
        }
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
                        .foregroundStyle(activeLayerIDs.contains(frame.id) ? WeiBeiTheme.cinnabar : WeiBeiTheme.secondaryInk)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var sceneCanvas: some View {
        if scene.frames.contains(where: { $0.kind == .space }) {
            SpatialMapCanvas(scene: scene, scrubPosition: scrubPosition, activeLayerIDs: activeLayerIDs)
        } else {
            TimelineCanvas(scene: scene, scrubPosition: scrubPosition, activeLayerIDs: activeLayerIDs)
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

    private var verificationState: [String: Any] {
        [
            "scrubPosition": scrubPosition,
            "activeLayerIDs": activeLayerIDs,
        ]
    }

    private var verificationTarget: [String: Any] {
        if let scrub = scene.operations.first(where: { $0.kind == .scrub }) {
            return [
                "id": scrub.id,
                "control": "scrub",
                "label": scrub.label,
            ]
        }
        return [
            "id": toggleFrames.first?.id ?? "",
            "control": "layer-toggle",
            "label": toggleFrames.first?.title ?? "",
        ]
    }

    private func advanceVerificationInteraction() {
        if scene.operations.contains(where: { $0.kind == .scrub }) {
            scrubPosition = scrubPosition < 0.66 ? 0.72 : 0.28
        }
        if let firstFrameID = toggleFrames.first?.id {
            if activeLayerIDs.contains(firstFrameID), toggleFrames.count > 1 {
                activeLayerIDs.insert(toggleFrames[1].id)
            } else {
                activeLayerIDs.insert(firstFrameID)
            }
        }
    }
}

private struct ImageOverlaySceneView: View {
    let scene: RichAnswerScene
    let evidenceByID: [String: RichAnswerEvidence]
    var onOpenEvidence: (RichAnswerEvidence) -> Void
    var onOpenAsset: (String) -> Void
    var assetPreview: (String) -> NSImage?
    @State private var selectedRegionID: String?
    @State private var showsOverlay = true
    @State private var zoomScale = 1.0

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
            imageStage
            if hasZoomOperation, previewImage != nil {
                HStack(spacing: 10) {
                    Text("缩放")
                        .font(.caption)
                        .foregroundStyle(WeiBeiTheme.tertiaryInk)
                    Slider(value: $zoomScale, in: 1...2.4, step: 0.1)
                        .tint(WeiBeiTheme.cinnabar)
                    Text(String(format: "%.1f×", zoomScale))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                    Button("复位") {
                        zoomScale = 1
                        selectedRegionID = nil
                    }
                    .buttonStyle(WeiBeiTextActionButtonStyle())
                }
            }
            assetButtons
            UnsupportedOperationNotice(
                scene: scene,
                handledOperationIDs: handledOperationIDs
            )
            EvidenceStrip(evidence: sceneEvidence, onOpenEvidence: onOpenEvidence)
        }
        .padding(.vertical, 10)
        .onRichAnswerVerificationStage { stage in
            guard stage == .after else { return }
            let before = verificationState
            advanceVerificationInteraction()
            writeDeepComponentVerificationReceipt(
                scene: scene,
                target: [
                    "id": selectedRegionID ?? scene.objects.first(where: { $0.bounds != nil })?.id ?? "",
                    "control": hasZoomOperation ? "image-zoom" : "image-overlay",
                    "label": "图像叠层",
                ],
                kind: hasZoomOperation ? "zoom" : "toggle",
                before: before,
                after: verificationState
            )
        }
    }

    @ViewBuilder
    private var imageStage: some View {
        if let image = previewImage {
            GeometryReader { geometry in
                let fittedSize = aspectFitSize(content: image.size, container: geometry.size)
                ZStack {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                    if showsOverlay {
                        ImageRegionOverlay(scene: scene, selectedRegionID: $selectedRegionID)
                    }
                }
                .frame(width: fittedSize.width, height: fittedSize.height)
                .scaleEffect(zoomScale)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
            .frame(height: 286)
            .visualCanvasSurface()
            .clipped()
        } else {
            VStack(spacing: 5) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 24))
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
                Text("当前素材无法在回答中预览")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                Text("保留区域说明，并可打开原始素材核对。")
                    .font(.caption)
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
            }
            .frame(maxWidth: .infinity, minHeight: 170)
            .visualCanvasSurface()
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

    private var previewImage: NSImage? {
        assetIDs.lazy.compactMap(assetPreview).first
    }

    private var hasZoomOperation: Bool {
        scene.operations.contains { $0.kind == .zoom }
    }

    private var handledOperationIDs: Set<String> {
        var kinds: Set<RichAnswerOperationKind> = [.select, .toggle]
        if previewImage != nil {
            kinds.insert(.zoom)
        }
        return operationIDs(in: scene, matching: kinds)
    }

    private var sceneEvidence: [RichAnswerEvidence] {
        scene.evidenceIDs.compactMap { evidenceByID[$0] }
    }

    private var verificationState: [String: Any] {
        [
            "selectedRegionID": selectedRegionID ?? NSNull(),
            "showsOverlay": showsOverlay,
            "zoomScale": zoomScale,
            "hasPreviewImage": previewImage != nil,
        ]
    }

    private func advanceVerificationInteraction() {
        showsOverlay = true
        selectedRegionID = selectedRegionID ?? scene.objects.first(where: { $0.bounds != nil })?.id
        if hasZoomOperation {
            zoomScale = zoomScale < 1.3 ? 1.5 : 1.1
        }
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
        Text(scene.title)
            .font(.system(size: 15.5, weight: .semibold))
            .foregroundStyle(WeiBeiTheme.ink)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct CoordinateCanvas: View {
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

private struct TimelineCanvas: View {
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

private struct SpatialMapCanvas: View {
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

private struct ImageRegionOverlay: View {
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

private struct EvidenceStrip: View {
    let evidence: [RichAnswerEvidence]
    var onOpenEvidence: (RichAnswerEvidence) -> Void

    var body: some View {
        if !evidence.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(displayEvidence, id: \.id) { item in
                    EvidenceChip(evidence: item, onOpenEvidence: onOpenEvidence)
                }
            }
        }
    }

    private var displayEvidence: [RichAnswerEvidence] {
        var seenLabels: Set<String> = []
        return evidence.filter { seenLabels.insert($0.sourceLabel).inserted }
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
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8.5, weight: .semibold))
                Text(evidence.sourceLabel)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
                ForEach(Array(evidence.tags).sorted().prefix(2), id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 9.5))
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                }
                if evidence.isTruncated {
                    Text("截断")
                        .font(.system(size: 9.5))
                        .foregroundStyle(WeiBeiTheme.cinnabar)
                }
            }
            .foregroundStyle(WeiBeiTheme.secondaryInk)
            .padding(.horizontal, 2)
            .frame(height: 21)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(WeiBeiTheme.hairline.opacity(0.48))
                    .frame(height: 1)
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
    func sceneSurface(fill: Color, horizontalPadding: CGFloat = 10) -> some View {
        self
            .padding(.vertical, 9)
            .padding(.horizontal, horizontalPadding)
            .background(fill)
    }

    func visualCanvasSurface() -> some View {
        self
            .background(WeiBeiTheme.paperInset.opacity(0.11))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(WeiBeiTheme.hairline.opacity(0.42), lineWidth: 1)
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

private func axisTickText(_ value: Double, unit: String?) -> String {
    let formatted = abs(value.rounded() - value) < 0.001
        ? String(format: "%.0f", value)
        : String(format: "%.1f", value)
    return unit.map { "\(formatted)\($0)" } ?? formatted
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
    case .refutes, .contrasts, .constrains:
        return WeiBeiTheme.cinnabar
    case .supports, .aligns, .contains, .causes, .dependsOn, .transforms, .precedes:
        return WeiBeiTheme.secondaryInk
    }
}

private func aspectFitSize(content: NSSize, container: CGSize) -> CGSize {
    guard content.width > 0, content.height > 0, container.width > 0, container.height > 0 else {
        return .zero
    }
    let scale = min(container.width / content.width, container.height / content.height)
    return CGSize(width: content.width * scale, height: content.height * scale)
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
