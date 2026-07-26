import AppKit
import SwiftUI
import WeiBeiCore

struct UnsupportedOperationNotice: View {
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

struct SceneTitle: View {
    let scene: RichAnswerScene
    let eyebrow: String

    var body: some View {
        Text(scene.title)
            .font(.system(size: 15.5, weight: .semibold))
            .foregroundStyle(WeiBeiTheme.ink)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct FlowLayout<Content: View>: View {
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

extension View {
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

func objectValueText(_ object: RichAnswerObject) -> String {
    if let number = object.number {
        let formatted = String(format: "%.3g", number)
        return object.unit.map { "\(formatted) \($0)" } ?? formatted
    }
    return object.label
}

func parameterText(_ parameter: RichAnswerParameter, value: Double) -> String {
    let formatted = String(format: "%.3g", value)
    return parameter.unit.map { "\(formatted) \($0)" } ?? formatted
}

func axisTickText(_ value: Double, unit: String?) -> String {
    let formatted = abs(value.rounded() - value) < 0.001
        ? String(format: "%.0f", value)
        : String(format: "%.1f", value)
    return unit.map { "\(formatted)\($0)" } ?? formatted
}

func operationIDs(
    in scene: RichAnswerScene,
    matching kinds: Set<RichAnswerOperationKind>
) -> Set<String> {
    Set(scene.operations.lazy.filter { kinds.contains($0.kind) }.map(\.id))
}

func frameAxisLabel(_ frame: RichAnswerFrame) -> String {
    let xAxis = frame.xAxis.map { $0.label } ?? "x"
    let yAxis = frame.yAxis.map { $0.label } ?? "y"
    return "\(frame.title)：\(xAxis) / \(yAxis)"
}

func relationColor(_ kind: RichAnswerRelationKind) -> Color {
    switch kind {
    case .refutes, .contrasts, .constrains:
        return WeiBeiTheme.cinnabar
    case .supports, .aligns, .contains, .causes, .dependsOn, .transforms, .precedes:
        return WeiBeiTheme.secondaryInk
    }
}

func aspectFitSize(content: NSSize, container: CGSize) -> CGSize {
    guard content.width > 0, content.height > 0, container.width > 0, container.height > 0 else {
        return .zero
    }
    let scale = min(container.width / content.width, container.height / content.height)
    return CGSize(width: content.width * scale, height: content.height * scale)
}

func clamp01(_ value: Double) -> CGFloat {
    CGFloat(min(1, max(0, value)))
}

extension RichAnswerRelationKind {
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

extension RichAnswerObjectKind {
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
