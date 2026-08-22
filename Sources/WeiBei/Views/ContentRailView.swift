import AppKit
import Foundation
import SwiftUI
import WeiBeiCore

struct ContentRailItem: Identifiable {
    let id: String
    let position: CGFloat
    let level: Int
    let title: String
    let excerpt: String
    let metadata: String
    let previewImage: NSImage?

    init(
        id: String,
        position: CGFloat,
        level: Int = 0,
        title: String,
        excerpt: String = "",
        metadata: String = "",
        previewImage: NSImage? = nil
    ) {
        self.id = id
        self.position = min(max(position, 0), 1)
        self.level = max(level, 0)
        self.title = title
        self.excerpt = excerpt
        self.metadata = metadata
        self.previewImage = previewImage
    }
}

enum ContentRailMetrics {
    /// Overlay hit area. Readable panes must not reserve this width in their layout.
    static let normalWidth: CGFloat = ContentRailPolicy.dormantWidth
    static let railOnlyWidth: CGFloat = normalWidth
    static let railOnlyThreshold = ContentRailPolicy.railOnlyThreshold
    static let snapThreshold = ContentRailPolicy.snapThreshold
    static let readableWidth = ContentRailPolicy.readableWidth
    static let defaultReadableWidth = ContentRailPolicy.defaultReadableWidth

    /// Vertical budget for the tick strip. The old 160pt cap crushed long
    /// documents into near-zero gaps; the strip now stretches up to this
    /// before gaps start shrinking.
    static let maxRailHeight: CGFloat = 420
    /// Gap between adjacent ticks while the strip still fits maxRailHeight.
    static let tickSpacing: CGFloat = 11

    static func isRailOnly(availableWidth: CGFloat, allowed: Bool) -> Bool {
        ContentRailPolicy.presentation(
            availableWidth: availableWidth,
            allowsRailOnly: allowed
        ) == .railOnly
    }
}

enum ContentRailWaveMetrics {
    static let peakLength: CGFloat = 28
    static let influences: [CGFloat] = [1, 0.70, 0.41, 0.20]

    static func length(normal: CGFloat, stepDistance: Int) -> CGFloat {
        guard influences.indices.contains(stepDistance) else { return normal }
        return normal + (peakLength - normal) * influences[stepDistance]
    }
}

struct ContentRailView: View {
    let label: String
    let items: [ContentRailItem]
    let activeID: String?
    let appearanceMode: WeiBeiAppearanceMode
    let isRailOnly: Bool
    let availableWidth: CGFloat?
    let topInset: CGFloat
    let bottomInset: CGFloat
    let onActivate: (ContentRailItem) -> Void
    let onHover: (ContentRailItem?) -> Void
    /// Needed by the cross-pane floating preview host, whose root has no store
    /// in its environment.
    let motionPreference: WeiBeiMotionPreference

    @State private var hoveredID: String?
    @State private var previewID: String?
    @FocusState private var focusedItemID: String?

    @Environment(\.weibeiReduceMotion) private var reduceMotion

    init(
        label: String,
        items: [ContentRailItem],
        activeID: String? = nil,
        appearanceMode: WeiBeiAppearanceMode,
        isRailOnly: Bool = false,
        availableWidth: CGFloat? = nil,
        topInset: CGFloat = 0,
        bottomInset: CGFloat = 0,
        onActivate: @escaping (ContentRailItem) -> Void,
        onHover: @escaping (ContentRailItem?) -> Void = { _ in },
        motionPreference: WeiBeiMotionPreference = .system
    ) {
        self.label = label
        self.items = items
        self.activeID = activeID
        self.appearanceMode = appearanceMode
        self.isRailOnly = isRailOnly
        self.availableWidth = availableWidth
        self.topInset = topInset
        self.bottomInset = bottomInset
        self.onActivate = onActivate
        self.onHover = onHover
        self.motionPreference = motionPreference
    }

    var body: some View {
        GeometryReader { geometry in
            let height = compactHeight(in: geometry.size.height)
            let previewIndex = previewID.flatMap { id in items.firstIndex(where: { $0.id == id }) }
            let previewItem = previewIndex.map { items[$0] }
            let previewAnchorY = previewIndex.map {
                previewY(index: $0, railHeight: height, totalHeight: geometry.size.height)
            } ?? compactCenterY(in: geometry.size.height)
            ZStack(alignment: .topLeading) {
                compactRail(height: height)
                    .position(
                        x: compactWidth / 2,
                        y: compactCenterY(in: geometry.size.height)
                    )

                ContentRailFloatingPreviewBridge(
                    label: label,
                    item: isRailOnly ? previewItem : nil,
                    appearanceMode: appearanceMode,
                    width: ContentRailPolicy.dormantPreviewWidth,
                    reduceMotion: reduceMotion,
                    motionPreference: motionPreference
                )
                .frame(width: 1, height: 1)
                .position(x: floatingPreviewAnchorX, y: previewAnchorY)
                .allowsHitTesting(false)

                if !isRailOnly, let item = previewItem {
                    if let width = previewWidth(in: availableWidth ?? geometry.size.width) {
                        previewCard(for: item, width: width)
                            .position(x: previewLeadingX + width / 2, y: previewAnchorY)
                            .allowsHitTesting(false)
                            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .leading)))
                            .zIndex(20)
                    }
                }
            }
        }
        .frame(width: railWidth)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(label))
        .animation(WeiBeiMotion.panel, value: isRailOnly)
        // Animate presence only (nil ↔ item). Moving across ticks swaps content
        // instantly; appear/disappear get the single 150ms fade.
        .animation(reduceMotion ? nil : WeiBeiMotion.railPreview, value: previewID != nil)
        .onChange(of: items.map { $0.id }) { _, ids in
            let staleHover = hoveredID.map { !ids.contains($0) } ?? false
            let stalePreview = previewID.map { !ids.contains($0) } ?? false
            if staleHover || stalePreview {
                closePreview(immediately: true)
            }
            if let focusedItemID, !ids.contains(focusedItemID) {
                self.focusedItemID = nil
            }
        }
        .onDisappear {
            if previewID != nil {
                onHover(nil)
            }
        }
    }

    private var compactWidth: CGFloat {
        ContentRailMetrics.normalWidth
    }

    private var railWidth: CGFloat {
        isRailOnly ? ContentRailMetrics.railOnlyWidth : ContentRailMetrics.normalWidth
    }

    private var tickLeadingInset: CGFloat {
        3
    }

    private var previewLeadingX: CGFloat {
        tickLeadingInset + ContentRailWaveMetrics.peakLength + 8
    }

    private var floatingPreviewAnchorX: CGFloat {
        max(1, compactWidth - 1)
    }

    private var resolvedActiveID: String? {
        activeID ?? items.first?.id
    }

    private var emphasizedID: String? {
        hoveredID ?? focusedItemID
    }

    private var highlightedID: String? {
        emphasizedID ?? resolvedActiveID
    }

    private var waveMotion: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.10)
    }

    private func compactRail(height: CGFloat) -> some View {
        ZStack {
            if items.isEmpty {
                emptyOriginMark
            } else {
                let hitHeight = railHitHeight(for: height)
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    railButton(
                        for: item,
                        index: index,
                        hitHeight: hitHeight
                    )
                    .position(
                        x: compactWidth / 2,
                        y: railY(index: index, count: items.count, height: height)
                    )
                }

                railPointerSurface(height: height)
                    .zIndex(10)

            }
        }
        .frame(width: compactWidth, height: height)
        .contentShape(Rectangle())
        .onExitCommand {
            focusedItemID = nil
        }
    }

    private var emptyOriginMark: some View {
        Rectangle()
            .fill(WeiBeiTheme.hairline.opacity(0.64))
            .frame(width: 8, height: 1.5)
            .frame(width: compactWidth - tickLeadingInset, height: 20, alignment: .leading)
            .padding(.leading, tickLeadingInset)
            .accessibilityLabel(Text(label))
    }

    private func compactHeight(in totalHeight: CGFloat) -> CGFloat {
        let top = max(topInset, 0) + 10
        let bottom = max(bottomInset, 0) + 10
        let available = max(totalHeight - top - bottom, 1)
        let desiredHeight = max(
            20,
            14 + CGFloat(max(items.count - 1, 0)) * ContentRailMetrics.tickSpacing
        )
        return min(desiredHeight, min(ContentRailMetrics.maxRailHeight, available))
    }

    private func compactCenterY(in totalHeight: CGFloat) -> CGFloat {
        let top = max(topInset, 0) + 10
        let bottom = max(bottomInset, 0) + 10
        let available = max(totalHeight - top - bottom, 0)
        return min(max(top + available / 2, 0), max(totalHeight, 0))
    }

    private func previewWidth(in totalWidth: CGFloat) -> CGFloat? {
        ContentRailPolicy.previewWidth(
            totalWidth: totalWidth,
            previewLeadingX: previewLeadingX,
            isRailOnly: false
        )
    }

    private func previewY(index: Int, railHeight: CGFloat, totalHeight: CGFloat) -> CGFloat {
        let localY = railY(index: index, count: items.count, height: railHeight)
        let proposedY = compactCenterY(in: totalHeight) - railHeight / 2 + localY
        let halfPreviewHeight: CGFloat = 74
        guard totalHeight > halfPreviewHeight * 2 else { return totalHeight / 2 }
        return min(max(proposedY, halfPreviewHeight), totalHeight - halfPreviewHeight)
    }

    private func railButton(
        for item: ContentRailItem,
        index: Int,
        hitHeight: CGFloat
    ) -> some View {
        let active = item.id == resolvedActiveID

        return Button {
            activate(item)
        } label: {
            Rectangle()
                .fill(tickColor(for: item, active: active))
                .frame(
                    width: tickLength(for: item, index: index, active: active),
                    height: active ? 2 : 1.5
                )
                .frame(width: compactWidth - tickLeadingInset, height: hitHeight, alignment: .leading)
                .padding(.leading, tickLeadingInset)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focusedItemID, equals: item.id)
        .accessibilityLabel(Text("\(label)：\(item.title)"))
        .accessibilityValue(Text(active ? "当前位置" : item.metadata))
        .help(item.title)
        .animation(WeiBeiMotion.micro, value: activeID)
        .animation(waveMotion, value: emphasizedID)
    }

    private func railPointerSurface(height: CGFloat) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    if let item = nearestItem(to: location.y, height: height),
                       hoveredID != item.id {
                        beginHover(item)
                    }
                case .ended:
                    if let hoveredID,
                       let item = items.first(where: { $0.id == hoveredID }) {
                        endHover(item)
                    } else {
                        closePreview(immediately: false)
                    }
                }
            }
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        guard let item = nearestItem(to: value.location.y, height: height) else { return }
                        activate(item)
                    }
            )
            .frame(width: compactWidth, height: height)
            .accessibilityHidden(true)
    }

    private func tickLength(for item: ContentRailItem, index: Int, active: Bool) -> CGFloat {
        let normal: CGFloat = active ? 8 : (item.level == 0 ? 7 : 6)
        guard let emphasizedID,
              let emphasizedIndex = items.firstIndex(where: { $0.id == emphasizedID }) else {
            return normal
        }
        return ContentRailWaveMetrics.length(
            normal: normal,
            stepDistance: abs(index - emphasizedIndex)
        )
    }

    private func tickColor(for item: ContentRailItem, active: Bool) -> Color {
        if item.id == highlightedID {
            return WeiBeiTheme.cinnabar
        }
        return WeiBeiTheme.secondaryInk.opacity(appearanceMode.isDark ? 0.78 : 0.58)
    }

    private func railSpacing(count: Int, height: CGFloat) -> CGFloat {
        guard count > 1 else { return 0 }
        let verticalInset = min(7, height / 2)
        let available = max(height - verticalInset * 2, 0)
        return min(ContentRailMetrics.tickSpacing, available / CGFloat(count - 1))
    }

    private func railY(index: Int, count: Int, height: CGFloat) -> CGFloat {
        guard count > 1 else { return height / 2 }
        let spacing = railSpacing(count: count, height: height)
        let span = spacing * CGFloat(count - 1)
        let firstY = (height - span) / 2
        return firstY + CGFloat(min(max(index, 0), count - 1)) * spacing
    }

    private func railHitHeight(for height: CGFloat) -> CGFloat {
        guard !items.isEmpty else { return 20 }
        guard items.count > 1 else { return min(20, height) }
        return min(20, max(railSpacing(count: items.count, height: height), 1))
    }

    private func nearestItem(to y: CGFloat, height: CGFloat) -> ContentRailItem? {
        guard !items.isEmpty else { return nil }
        guard items.count > 1 else { return items[0] }
        let spacing = railSpacing(count: items.count, height: height)
        guard spacing > 0 else { return items[0] }
        let firstY = railY(index: 0, count: items.count, height: height)
        let rawIndex = ((y - firstY) / spacing).rounded()
        let index = min(max(Int(rawIndex), 0), items.count - 1)
        return items[index]
    }

    private func previewCard(for item: ContentRailItem, width: CGFloat) -> some View {
        ContentRailPreviewCard(
            label: label,
            item: item,
            appearanceMode: appearanceMode,
            width: width
        )
    }

    private func beginHover(_ item: ContentRailItem) {
        hoveredID = item.id

        guard previewID != item.id else {
            onHover(item)
            return
        }

        withAnimation(reduceMotion ? nil : WeiBeiMotion.railPreview) {
            previewID = item.id
        }
        onHover(item)
    }

    private func endHover(_ item: ContentRailItem) {
        if hoveredID == item.id {
            hoveredID = nil
        }
        closePreview(immediately: false)
    }

    private func closePreview(immediately: Bool) {
        hoveredID = nil
        if immediately {
            previewID = nil
        } else {
            withAnimation(reduceMotion ? nil : WeiBeiMotion.railPreview) {
                previewID = nil
            }
        }
        onHover(nil)
    }

    private func activate(_ item: ContentRailItem) {
        closePreview(immediately: true)
        onActivate(item)
    }
}

private struct ContentRailPreviewCard: View {
    let label: String
    let item: ContentRailItem
    let appearanceMode: WeiBeiAppearanceMode
    let width: CGFloat

    var body: some View {
        let showsPreviewImage = item.previewImage != nil && width >= ContentRailPolicy.previewImageMinimumWidth

        HStack(alignment: .top, spacing: showsPreviewImage ? 12 : 0) {
            if showsPreviewImage, let image = item.previewImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 88, height: 112)
                    .clipped()
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(label)
                    .weiBeiText(9.5, weight: .semibold, design: .serif)
                    .tracking(0.7)
                    .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.78))
                    .lineLimit(1)

                Text(item.title)
                    .weiBeiText(13.5, weight: .semibold)
                    .foregroundStyle(WeiBeiTheme.ink)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !item.excerpt.isEmpty {
                    Text(item.excerpt)
                        .weiBeiText(12.5)
                        .lineSpacing(3)
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                        .lineLimit(showsPreviewImage ? 3 : 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !item.metadata.isEmpty {
                    Text(item.metadata)
                        .weiBeiText(10.5, weight: .medium, design: .monospaced)
                        .foregroundStyle(WeiBeiTheme.tertiaryInk)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(width: width, alignment: .leading)
        .background(WeiBeiTheme.paperRaised)
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(WeiBeiTheme.hairline.opacity(0.82), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .shadow(color: WeiBeiTheme.ink.opacity(appearanceMode.isDark ? 0.22 : 0.08), radius: 8, y: 4)
        .accessibilityHidden(true)
    }
}

/// The dormant pane is only 40pt wide, so its preview cannot live inside that pane's
/// clipped host. This bridge places the same SwiftUI card in the existing window root.
private struct ContentRailFloatingPreviewBridge: NSViewRepresentable {
    let label: String
    let item: ContentRailItem?
    let appearanceMode: WeiBeiAppearanceMode
    let width: CGFloat
    let reduceMotion: Bool
    let motionPreference: WeiBeiMotionPreference

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ anchorView: NSView, context: Context) {
        guard let item else {
            context.coordinator.dismiss(reduceMotion: reduceMotion)
            return
        }
        context.coordinator.update(
            anchorView: anchorView,
            label: label,
            item: item,
            appearanceMode: appearanceMode,
            width: width,
            reduceMotion: reduceMotion,
            motionPreference: motionPreference
        )
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.dismiss(reduceMotion: true)
    }

    final class Coordinator {
        private var hostingView: ContentRailPassthroughHostingView?
        private weak var containerView: NSView?
        private var updateGeneration = 0
        /// Bumped by every show and every dismiss so a stale fade-out completion
        /// can never remove a preview that a newer hover re-opened.
        private var dismissGeneration = 0

        func update(
            anchorView: NSView,
            label: String,
            item: ContentRailItem,
            appearanceMode: WeiBeiAppearanceMode,
            width: CGFloat,
            reduceMotion: Bool,
            motionPreference: WeiBeiMotionPreference
        ) {
            updateGeneration += 1
            dismissGeneration += 1
            let generation = updateGeneration
            DispatchQueue.main.async { [weak self, weak anchorView] in
                guard let self, let anchorView, generation == self.updateGeneration,
                      let contentView = anchorView.window?.contentView,
                      let container = contentView.superview else { return }

                let card = AnyView(
                    ContentRailPreviewCard(
                        label: label,
                        item: item,
                        appearanceMode: appearanceMode,
                        width: width
                    )
                    .preferredColorScheme(appearanceMode.colorScheme)
                    .weiBeiMotionScoped(preference: motionPreference)
                )
                let hosting: ContentRailPassthroughHostingView
                if let existing = self.hostingView {
                    existing.rootView = card
                    hosting = existing
                } else {
                    hosting = ContentRailPassthroughHostingView(rootView: card)
                    hosting.wantsLayer = true
                    hosting.layer?.backgroundColor = NSColor.clear.cgColor
                    hosting.layer?.zPosition = 1_000
                    self.hostingView = hosting
                }

                var isNewHosting = false
                if hosting.superview !== container {
                    hosting.removeFromSuperview()
                    hosting.alphaValue = reduceMotion ? 1 : 0
                    container.addSubview(hosting, positioned: .above, relativeTo: contentView)
                    self.containerView = container
                    isNewHosting = true
                } else {
                    // Cancel any fade-out still in flight: the preview is live again.
                    hosting.layer?.removeAllAnimations()
                    hosting.alphaValue = 1
                }

                hosting.frame.size = NSSize(width: width, height: max(132, hosting.fittingSize.height))
                let anchorCenter = anchorView.convert(
                    NSPoint(x: anchorView.bounds.midX, y: anchorView.bounds.midY),
                    to: container
                )
                let inset: CGFloat = 8
                let proposedX = anchorCenter.x + 4
                let maximumX = max(inset, container.bounds.maxX - hosting.frame.width - inset)
                let x = min(max(proposedX, inset), maximumX)
                let proposedY = anchorCenter.y - hosting.frame.height / 2
                let maximumY = max(inset, container.bounds.maxY - hosting.frame.height - inset)
                let y = min(max(proposedY, inset), maximumY)
                hosting.frame.origin = NSPoint(x: x, y: y)

                if isNewHosting && !reduceMotion {
                    NSAnimationContext.runAnimationGroup({ context in
                        context.duration = 0.15
                        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                        hosting.animator().alphaValue = 1
                    })
                }
            }
        }

        func dismiss(reduceMotion: Bool) {
            updateGeneration += 1
            dismissGeneration += 1
            let generation = dismissGeneration
            guard let hosting = hostingView else {
                containerView = nil
                return
            }
            let removeHosting = { [weak self, weak hosting] in
                guard let self, let hosting,
                      self.dismissGeneration == generation,
                      self.hostingView === hosting else { return }
                hosting.removeFromSuperview()
                self.hostingView = nil
                self.containerView = nil
            }
            guard !reduceMotion else {
                removeHosting()
                return
            }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                hosting.animator().alphaValue = 0
            }, completionHandler: removeHosting)
        }
    }
}

private final class ContentRailPassthroughHostingView: NSHostingView<AnyView> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }
}
