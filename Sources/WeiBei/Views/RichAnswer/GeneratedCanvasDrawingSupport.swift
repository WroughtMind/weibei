import AppKit
import SwiftUI
import WeiBeiCore

func generatedShapePath(_ shape: RichAnswerUIShape, in rect: CGRect) -> Path {
    switch shape {
    case .rectangle:
        return Path(rect)
    case .roundedRectangle:
        return Path(roundedRect: rect, cornerRadius: min(9, min(rect.width, rect.height) * 0.22))
    case .circle:
        let diameter = min(rect.width, rect.height)
        return Path(ellipseIn: CGRect(
            x: rect.midX - diameter / 2,
            y: rect.midY - diameter / 2,
            width: diameter,
            height: diameter
        ))
    case .ellipse:
        return Path(ellipseIn: rect)
    case .triangle:
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    case .diamond:
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    case .capsule:
        return Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) / 2)
    }
}


func drawArrowHead(context: inout GraphicsContext, start: CGPoint, end: CGPoint, color: Color) {
    let angle = atan2(end.y - start.y, end.x - start.x)
    let length: CGFloat = 8
    let spread: CGFloat = .pi / 7
    let left = CGPoint(x: end.x - length * cos(angle - spread), y: end.y - length * sin(angle - spread))
    let right = CGPoint(x: end.x - length * cos(angle + spread), y: end.y - length * sin(angle + spread))
    var head = Path()
    head.move(to: left)
    head.addLine(to: end)
    head.addLine(to: right)
    context.stroke(head, with: .color(color.opacity(0.84)), lineWidth: 1.5)
}

func axisValue(_ value: Double, unit: String?) -> String {
    let formatted = abs(value.rounded() - value) < 0.0001
        ? String(format: "%.0f", value)
        : String(format: "%.1f", value)
    return unit.map { "\(formatted)\($0)" } ?? formatted
}

func generatedToneColor(_ tone: RichAnswerUITone) -> Color {
    switch tone {
    case .ink:
        return WeiBeiTheme.ink
    case .muted:
        return WeiBeiTheme.secondaryInk
    case .accent:
        return WeiBeiTheme.cinnabar
    case .warning:
        return WeiBeiTheme.cinnabar.opacity(0.82)
    case .positive:
        return WeiBeiTheme.moss
    case .gridline:
        return WeiBeiTheme.hairline
    }
}

func spacing(for spacing: RichAnswerUISpacing) -> CGFloat {
    switch spacing {
    case .tight:
        return 6
    case .regular:
        return 10
    case .loose:
        return 16
    }
}

func horizontalAlignment(for alignment: RichAnswerUIAlignment) -> HorizontalAlignment {
    switch alignment {
    case .leading:
        return .leading
    case .center:
        return .center
    case .trailing:
        return .trailing
    }
}

func zAlignment(for alignment: RichAnswerUIAlignment) -> Alignment {
    switch alignment {
    case .leading:
        return .topLeading
    case .center:
        return .center
    case .trailing:
        return .topTrailing
    }
}

func generatedFrameAlignment(_ alignment: RichAnswerUIAlignment) -> Alignment {
    switch alignment {
    case .leading:
        return .leading
    case .center:
        return .center
    case .trailing:
        return .trailing
    }
}
