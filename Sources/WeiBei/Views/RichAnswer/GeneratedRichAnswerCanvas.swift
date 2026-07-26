import AppKit
import SwiftUI
import WeiBeiCore

import AppKit
import SwiftUI
import WeiBeiCore

struct GeneratedRichAnswerCanvas: View {
    let canvasNode: RichAnswerUINode
    let composition: RichAnswerUIComposition
    let compositionIndex: GeneratedRichAnswerCompositionIndex
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
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(WeiBeiTheme.hairline.opacity(0.42), lineWidth: 1)
        }
        .accessibilityLabel(canvasAccessibilityLabel)
        .accessibilityIdentifier("rich-answer-canvas-\(canvasNode.id)")
    }

    var markNodes: [RichAnswerUINode] {
        canvasNode.children.compactMap(compositionIndex.node(id:))
    }

    var imageNode: RichAnswerUINode? {
        markNodes.first(where: { $0.role == .image && isVisible($0) })
    }

    var canvasHeight: CGFloat {
        GeneratedCanvasLayout.height(for: canvasNode.size)
    }

    var canvasAccessibilityLabel: String {
        canvasNode.label ?? canvasNode.xAxis?.label ?? canvasNode.yAxis?.label ?? "富回答交互画布"
    }

    func drawCanvas(context: inout GraphicsContext, size: CGSize) {
        let drawingRect = GeneratedCanvasProjection(canvasSize: size).rect
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

}
