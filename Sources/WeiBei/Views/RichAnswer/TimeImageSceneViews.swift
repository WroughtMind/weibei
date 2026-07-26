import AppKit
import SwiftUI
import WeiBeiCore

struct TimeSpaceSceneView: View {
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

struct ImageOverlaySceneView: View {
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

