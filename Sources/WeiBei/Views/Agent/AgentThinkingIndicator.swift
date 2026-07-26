import AppKit
import PDFKit
import SwiftUI
import WeiBeiCore

struct AgentThinkingIndicator: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cachedText = ""
    @State private var cachedTextWidth: CGFloat = 1
    @State private var motionEpoch = Date()

    private static let statusFontSize: CGFloat = 12
    /// Clear gap from line-box edge → stroke centerline (all four sides).
    private static let orbitPadding: CGFloat = 5.5
    private static let lineWidth: CGFloat = 1.25
    /// Line box height matches the font’s typographic bounds so top/bottom pad stay equal.
    private static var textLineHeight: CGFloat {
        let font = NSFont.systemFont(ofSize: statusFontSize, weight: .medium)
        return max(1, ceil(font.ascender - font.descender))
    }
    /// Outer view size = line box + equal pad on both sides + half stroke outside the path.
    private static var pathOuterInset: CGFloat { orbitPadding + lineWidth / 2 }
    private static var pathHeight: CGFloat { textLineHeight + pathOuterInset * 2 }

    private var statusText: String {
        store.agentActivityText ?? store.ui("正在读取上下文", "Reading context")
    }

    var body: some View {
        let text = cachedText.isEmpty ? statusText : cachedText
        let textWidth = max(1, cachedTextWidth)
        let orbitWidth = textWidth + Self.pathOuterInset * 2
        let pathHeight = Self.pathHeight

        Group {
            if reduceMotion {
                Text(text)
                    .font(.system(size: Self.statusFontSize, weight: .medium))
                    .foregroundStyle(WeiBeiTheme.ink.opacity(0.93))
                    .lineLimit(1)
                    .frame(width: textWidth, height: Self.textLineHeight, alignment: .leading)
                    .padding(Self.pathOuterInset)
            } else {
                // AppKit host: fixed intrinsic size; ticks only repaint the NSView.
                AgentThinkingOrbitHost(
                    text: text,
                    textWidth: textWidth,
                    orbitWidth: orbitWidth,
                    pathHeight: pathHeight,
                    orbitPadding: Self.orbitPadding,
                    textLineHeight: Self.textLineHeight,
                    lineWidth: Self.lineWidth,
                    motionEpoch: motionEpoch,
                    appearanceMode: store.appearanceMode
                )
                .frame(width: orbitWidth, height: pathHeight, alignment: .leading)
                .allowsHitTesting(false)
            }
        }
        .frame(width: orbitWidth, height: pathHeight, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: true, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .onAppear {
            refreshCache(for: statusText)
            motionEpoch = Date()
        }
        .onChange(of: statusText) { _, newText in
            // Interrupt mid-orbit immediately; restart first bottom proofreading pass.
            refreshCache(for: newText)
            motionEpoch = Date()
        }
    }

    private func refreshCache(for text: String) {
        cachedText = text
        cachedTextWidth = Self.measuredWidth(for: text)
    }

    private static func measuredWidth(for text: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: statusFontSize, weight: .medium)
        let size = (text as NSString).size(withAttributes: [.font: font])
        return max(1, ceil(size.width))
    }
}

/// Bridges V3 orbit motion into AppKit so SwiftUI layout never sees per-frame updates.
struct AgentThinkingOrbitHost: NSViewRepresentable {
    let text: String
    let textWidth: CGFloat
    let orbitWidth: CGFloat
    let pathHeight: CGFloat
    let orbitPadding: CGFloat
    let textLineHeight: CGFloat
    let lineWidth: CGFloat
    let motionEpoch: Date
    let appearanceMode: WeiBeiAppearanceMode

    func makeNSView(context: Context) -> AgentThinkingOrbitNSView {
        let view = AgentThinkingOrbitNSView()
        view.wantsLayer = true
        view.apply(
            text: text,
            textWidth: textWidth,
            orbitWidth: orbitWidth,
            pathHeight: pathHeight,
            orbitPadding: orbitPadding,
            textLineHeight: textLineHeight,
            lineWidth: lineWidth,
            motionEpoch: motionEpoch,
            appearanceMode: appearanceMode
        )
        return view
    }

    func updateNSView(_ nsView: AgentThinkingOrbitNSView, context: Context) {
        nsView.apply(
            text: text,
            textWidth: textWidth,
            orbitWidth: orbitWidth,
            pathHeight: pathHeight,
            orbitPadding: orbitPadding,
            textLineHeight: textLineHeight,
            lineWidth: lineWidth,
            motionEpoch: motionEpoch,
            appearanceMode: appearanceMode
        )
    }
}

/// Fixed-size AppKit painter for 「行文进行中 V3」: reveal + first-pass underline + TextOrbitSegment.
/// Text sits in a line box; orbit stroke centerline keeps equal `orbitPadding` on all four sides.
final class AgentThinkingOrbitNSView: NSView {
    private static let statusFontSize: CGFloat = 12
    private static let segmentLength: CGFloat = 10
    private static let firstPassDuration: TimeInterval = 0.88
    private static let orbitDuration: TimeInterval = 2.25

    private var statusText = ""
    private var textWidth: CGFloat = 1
    private var orbitWidth: CGFloat = 1
    private var pathHeight: CGFloat = 26
    private var orbitPadding: CGFloat = 5.5
    private var textLineHeight: CGFloat = 15
    private var lineWidth: CGFloat = 1.25
    private var motionEpoch = Date()
    private var appearanceMode: WeiBeiAppearanceMode = .paper
    private var displayLink: CADisplayLink?

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: orbitWidth, height: pathHeight)
    }

    deinit {
        stopDisplayLink()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            startDisplayLink()
        } else {
            stopDisplayLink()
        }
    }

    func apply(
        text: String,
        textWidth: CGFloat,
        orbitWidth: CGFloat,
        pathHeight: CGFloat,
        orbitPadding: CGFloat,
        textLineHeight: CGFloat,
        lineWidth: CGFloat,
        motionEpoch: Date,
        appearanceMode: WeiBeiAppearanceMode
    ) {
        let sizeChanged = abs(self.orbitWidth - orbitWidth) > 0.5
            || abs(self.pathHeight - pathHeight) > 0.5
        statusText = text
        self.textWidth = max(1, textWidth)
        self.orbitWidth = max(1, orbitWidth)
        self.pathHeight = max(1, pathHeight)
        self.orbitPadding = max(1, orbitPadding)
        self.textLineHeight = max(1, textLineHeight)
        self.lineWidth = max(0.5, lineWidth)
        self.motionEpoch = motionEpoch
        self.appearanceMode = appearanceMode
        if sizeChanged {
            invalidateIntrinsicContentSize()
        }
        // Paint only — do not call setNeedsLayout / invalidate parent SwiftUI layout.
        needsDisplay = true
        if window != nil {
            startDisplayLink()
        }
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let link = displayLink(target: self, selector: #selector(handleDisplayTick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 30, preferred: 30)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func handleDisplayTick() {
        // Local repaint only. Never touch SwiftUI state from here.
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let bounds = CGRect(x: 0, y: 0, width: orbitWidth, height: pathHeight)
        context.clear(bounds)

        let elapsed = max(0, Date().timeIntervalSince(motionEpoch))
        let reveal = TextOrbitSegment.revealProgress(at: elapsed)
        let firstPass = elapsed < Self.firstPassDuration
        let cursorProgress = firstPass ? reveal : 1
        let cursorOpacity = firstPass
            ? TextOrbitSegment.smootherStep(TextOrbitSegment.clamp(reveal / 0.14))
                * (1 - TextOrbitSegment.smootherStep(TextOrbitSegment.clamp((elapsed - 0.82) / 0.16)))
            : 0
        let orbitOpacity = firstPass
            ? TextOrbitSegment.smootherStep(TextOrbitSegment.clamp((elapsed - 0.82) / 0.18))
            : 1
        let orbitProgress = TextOrbitSegment.orbitProgress(at: elapsed)

        let ink = WeiBeiNativePalette.ink(for: appearanceMode).withAlphaComponent(0.93)
        let dim = WeiBeiNativePalette.tertiaryInk(for: appearanceMode).withAlphaComponent(0.70)
        let cinnabar = WeiBeiNativePalette.cinnabar(for: appearanceMode).withAlphaComponent(0.82)

        let font = NSFont.systemFont(ofSize: Self.statusFontSize, weight: .medium)
        // Line box inset so every side has the same gap to the stroke centerline.
        // view edge → stroke center = lineWidth/2
        // stroke center → line box edge = orbitPadding
        let contentOrigin = orbitPadding + lineWidth / 2
        let textRect = CGRect(
            x: contentOrigin,
            y: contentOrigin,
            width: textWidth,
            height: textLineHeight
        )
        // draw(in:) top-aligns in the flipped line box. Line-box height == ascender−descender,
        // so ink fills the box and all four sides keep the same gap to the stroke centerline.
        // Do not add capHeight/descender fudge — that broke equal top/bottom padding.
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byClipping
        let dimAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: dim,
            .paragraphStyle: paragraph
        ]
        (statusText as NSString).draw(in: textRect, withAttributes: dimAttributes)

        if reveal > 0.001 {
            context.saveGState()
            context.clip(
                to: CGRect(
                    x: textRect.minX,
                    y: 0,
                    width: textWidth * CGFloat(reveal),
                    height: pathHeight
                )
            )
            let inkAttributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: ink,
                .paragraphStyle: paragraph
            ]
            (statusText as NSString).draw(in: textRect, withAttributes: inkAttributes)
            context.restoreGState()
        }

        // First-pass proofread line: center of the bottom equal-padding band.
        if cursorOpacity > 0.01 {
            let bottomBandCenterY = textRect.maxY + orbitPadding / 2
            let x = textRect.minX + max(0, (textWidth - Self.segmentLength) * CGFloat(cursorProgress))
            let y = bottomBandCenterY - lineWidth / 2
            let segment = CGRect(x: x, y: y, width: Self.segmentLength, height: lineWidth)
            context.saveGState()
            context.setAlpha(CGFloat(cursorOpacity))
            context.setFillColor(cinnabar.cgColor)
            let path = CGPath(
                roundedRect: segment,
                cornerWidth: lineWidth / 2,
                cornerHeight: lineWidth / 2,
                transform: nil
            )
            context.addPath(path)
            context.fillPath()
            context.restoreGState()
        }

        // Orbit stroke centerline: equal orbitPadding from the line box on all four sides.
        if orbitOpacity > 0.01 {
            context.saveGState()
            context.setAlpha(CGFloat(orbitOpacity))
            TextOrbitSegment.stroke(
                progress: orbitProgress,
                width: orbitWidth,
                height: pathHeight,
                segmentLength: Self.segmentLength,
                lineWidth: lineWidth,
                color: cinnabar,
                in: context
            )
            context.restoreGState()
        }
    }
}

/// Short cinnabar segment orbiting a measured text box (V3 path geometry).
/// Pure geometry/paint helper — not a SwiftUI View — so it cannot thrash ScrollView layout.
enum TextOrbitSegment {
    static let firstPassDuration: TimeInterval = 0.88
    static let orbitDuration: TimeInterval = 2.25

    static func revealProgress(at elapsed: TimeInterval) -> Double {
        let raw = clamp((elapsed - 0.10) / 0.78)
        return 1 - pow(1 - raw, 3.2)
    }

    static func orbitProgress(at elapsed: TimeInterval) -> Double {
        guard elapsed >= firstPassDuration else { return 0 }
        let t = (elapsed - firstPassDuration) / orbitDuration
        let remainder = t.truncatingRemainder(dividingBy: 1)
        return remainder >= 0 ? remainder : remainder + 1
    }

    static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    static func smootherStep(_ value: Double) -> Double {
        let x = clamp(value)
        return x * x * x * (x * (x * 6 - 15) + 10)
    }

    static func stroke(
        progress: Double,
        width: CGFloat,
        height: CGFloat,
        segmentLength: CGFloat,
        lineWidth: CGFloat,
        color: NSColor,
        in context: CGContext
    ) {
        let normalized = CGFloat(((progress.truncatingRemainder(dividingBy: 1)) + 1).truncatingRemainder(dividingBy: 1))
        let perimeter = TextOrbitPath.estimatedPerimeter(width: width, height: height, lineWidth: lineWidth)
        let fraction = min(0.08, segmentLength / max(1, perimeter))
        let end = normalized + fraction
        let fullPath = TextOrbitPath.cgPath(width: width, height: height, lineWidth: lineWidth)

        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        if end <= 1 {
            strokeTrimmed(fullPath, from: normalized, to: end, in: context)
        } else {
            strokeTrimmed(fullPath, from: normalized, to: 1, in: context)
            strokeTrimmed(fullPath, from: 0, to: end - 1, in: context)
        }
    }

    private static func strokeTrimmed(_ path: CGPath, from start: CGFloat, to end: CGFloat, in context: CGContext) {
        guard end > start else { return }
        let trimmed = path.trimmedPath(from: start, to: end)
        context.addPath(trimmed)
        context.strokePath()
    }
}

/// V3 orbit geometry: rounded rectangle starting bottom-right, clockwise.
/// Path centerline sits `lineWidth/2` inside the view so the stroke is fully visible
/// and the clear gap to the text line box is equal on all four sides.
enum TextOrbitPath {
    /// Matches AgentThinkingOrbitNSView lineWidth default; stroke() passes the live width via inset.
    static let defaultLineWidth: CGFloat = 1.25

    static func estimatedPerimeter(width: CGFloat, height: CGFloat, lineWidth: CGFloat = defaultLineWidth) -> CGFloat {
        let inset = lineWidth / 2
        let radius: CGFloat = 3
        let w = max(1, width - inset * 2)
        let h = max(1, height - inset * 2)
        return max(1, 2 * (w + h) - 8 * radius + 2 * .pi * radius)
    }

    static func cgPath(width: CGFloat, height: CGFloat, lineWidth: CGFloat = defaultLineWidth) -> CGPath {
        // Stroke centerline inset = half line width → equal visual margins when text box
        // is placed at (pad + lineWidth/2) with the same pad on every side.
        let inset = lineWidth / 2
        let radius: CGFloat = 3
        let minX = inset
        let maxX = width - inset
        let minY = inset
        let maxY = height - inset

        let path = CGMutablePath()
        path.move(to: CGPoint(x: maxX - radius, y: maxY))
        path.addQuadCurve(to: CGPoint(x: maxX, y: maxY - radius), control: CGPoint(x: maxX, y: maxY))
        path.addLine(to: CGPoint(x: maxX, y: minY + radius))
        path.addQuadCurve(to: CGPoint(x: maxX - radius, y: minY), control: CGPoint(x: maxX, y: minY))
        path.addLine(to: CGPoint(x: minX + radius, y: minY))
        path.addQuadCurve(to: CGPoint(x: minX, y: minY + radius), control: CGPoint(x: minX, y: minY))
        path.addLine(to: CGPoint(x: minX, y: maxY - radius))
        path.addQuadCurve(to: CGPoint(x: minX + radius, y: maxY), control: CGPoint(x: minX, y: maxY))
        path.addLine(to: CGPoint(x: maxX - radius, y: maxY))
        path.closeSubpath()
        return path
    }
}

extension CGPath {
    /// Approximate trim for a closed path by walking the flattened polyline.
    func trimmedPath(from start: CGFloat, to end: CGFloat) -> CGPath {
        let points = flattenedPoints()
        guard points.count >= 2 else { return self }

        var lengths: [CGFloat] = [0]
        var total: CGFloat = 0
        for index in 1..<points.count {
            total += hypot(points[index].x - points[index - 1].x, points[index].y - points[index - 1].y)
            lengths.append(total)
        }
        guard total > 0 else { return self }

        let startDistance = max(0, min(1, start)) * total
        let endDistance = max(0, min(1, end)) * total
        guard endDistance > startDistance else { return CGMutablePath() }

        let result = CGMutablePath()
        var started = false
        for index in 1..<points.count {
            let segmentStart = lengths[index - 1]
            let segmentEnd = lengths[index]
            if segmentEnd < startDistance { continue }
            if segmentStart > endDistance { break }

            let fromT = segmentEnd == segmentStart
                ? 0
                : max(0, (startDistance - segmentStart) / (segmentEnd - segmentStart))
            let toT = segmentEnd == segmentStart
                ? 1
                : min(1, (endDistance - segmentStart) / (segmentEnd - segmentStart))
            let p0 = points[index - 1]
            let p1 = points[index]
            let fromPoint = CGPoint(
                x: p0.x + (p1.x - p0.x) * fromT,
                y: p0.y + (p1.y - p0.y) * fromT
            )
            let toPoint = CGPoint(
                x: p0.x + (p1.x - p0.x) * toT,
                y: p0.y + (p1.y - p0.y) * toT
            )
            if !started {
                result.move(to: fromPoint)
                started = true
            }
            result.addLine(to: toPoint)
        }
        return result
    }

    func flattenedPoints() -> [CGPoint] {
        var points: [CGPoint] = []
        applyWithBlock { elementPointer in
            Self.appendFlattened(element: elementPointer.pointee, into: &points)
        }
        return points
    }

    private static func appendFlattened(element: CGPathElement, into points: inout [CGPoint]) {
        switch element.type {
        case .moveToPoint:
            points.append(element.points[0])
        case .addLineToPoint:
            points.append(element.points[0])
        case .addQuadCurveToPoint:
            appendQuad(
                from: points.last ?? element.points[1],
                control: element.points[0],
                to: element.points[1],
                into: &points
            )
        case .addCurveToPoint:
            appendCubic(
                from: points.last ?? element.points[2],
                c1: element.points[0],
                c2: element.points[1],
                to: element.points[2],
                into: &points
            )
        case .closeSubpath:
            if let first = points.first {
                points.append(first)
            }
        @unknown default:
            break
        }
    }

    private static func appendQuad(
        from start: CGPoint,
        control: CGPoint,
        to end: CGPoint,
        into points: inout [CGPoint]
    ) {
        for step in 1...8 {
            let t = CGFloat(step) / 8
            let mt = 1 - t
            let x = mt * mt * start.x + 2 * mt * t * control.x + t * t * end.x
            let y = mt * mt * start.y + 2 * mt * t * control.y + t * t * end.y
            points.append(CGPoint(x: x, y: y))
        }
    }

    private static func appendCubic(
        from start: CGPoint,
        c1: CGPoint,
        c2: CGPoint,
        to end: CGPoint,
        into points: inout [CGPoint]
    ) {
        for step in 1...8 {
            let t = CGFloat(step) / 8
            let mt = 1 - t
            let x = mt * mt * mt * start.x
                + 3 * mt * mt * t * c1.x
                + 3 * mt * t * t * c2.x
                + t * t * t * end.x
            let y = mt * mt * mt * start.y
                + 3 * mt * mt * t * c1.y
                + 3 * mt * t * t * c2.y
                + t * t * t * end.y
            points.append(CGPoint(x: x, y: y))
        }
    }
}
