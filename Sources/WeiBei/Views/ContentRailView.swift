import AppKit
import Foundation
import SwiftUI

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
    static let normalWidth: CGFloat = 40
    static let railOnlyWidth: CGFloat = 88
    static let railOnlyThreshold: CGFloat = 150
    static let snapThreshold: CGFloat = 160
    static let readableWidth: CGFloat = 240
    static let defaultReadableWidth: CGFloat = 420
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
    let topInset: CGFloat
    let bottomInset: CGFloat
    let onActivate: (ContentRailItem) -> Void
    let onHover: (ContentRailItem?) -> Void

    @State private var hoveredID: String?
    @State private var previewID: String?
    @State private var previewOpenWork: DispatchWorkItem?
    @State private var previewCloseWork: DispatchWorkItem?
    @FocusState private var focusedItemID: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        label: String,
        items: [ContentRailItem],
        activeID: String? = nil,
        appearanceMode: WeiBeiAppearanceMode,
        isRailOnly: Bool = false,
        topInset: CGFloat = 0,
        bottomInset: CGFloat = 0,
        onActivate: @escaping (ContentRailItem) -> Void,
        onHover: @escaping (ContentRailItem?) -> Void = { _ in }
    ) {
        self.label = label
        self.items = items
        self.activeID = activeID
        self.appearanceMode = appearanceMode
        self.isRailOnly = isRailOnly
        self.topInset = topInset
        self.bottomInset = bottomInset
        self.onActivate = onActivate
        self.onHover = onHover
    }

    var body: some View {
        GeometryReader { geometry in
            let height = compactHeight(in: geometry.size.height)
            ZStack(alignment: .topLeading) {
                compactRail(height: height)
                    .position(
                        x: compactWidth / 2,
                        y: compactCenterY(in: geometry.size.height)
                    )

                if let previewID,
                   let previewIndex = items.firstIndex(where: { $0.id == previewID }),
                   let width = previewWidth(in: geometry.size.width) {
                    previewCard(for: items[previewIndex], width: width)
                        .position(
                            x: previewLeadingX + width / 2,
                            y: previewY(
                                index: previewIndex,
                                railHeight: height,
                                totalHeight: geometry.size.height
                            )
                        )
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .leading)))
                        .zIndex(20)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(label))
        .animation(WeiBeiMotion.panel, value: isRailOnly)
        .animation(WeiBeiMotion.hover, value: previewID)
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
            previewOpenWork?.cancel()
            previewCloseWork?.cancel()
            if previewID != nil {
                onHover(nil)
            }
        }
    }

    private var compactWidth: CGFloat {
        isRailOnly ? 42 : 40
    }

    private var tickLeadingInset: CGFloat {
        isRailOnly ? 4 : 3
    }

    private var previewLeadingX: CGFloat {
        tickLeadingInset + ContentRailWaveMetrics.peakLength + 8
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
        let desiredHeight = max(20, 14 + CGFloat(max(items.count - 1, 0)) * 8)
        return min(desiredHeight, min(160, available))
    }

    private func compactCenterY(in totalHeight: CGFloat) -> CGFloat {
        let top = max(topInset, 0) + 10
        let bottom = max(bottomInset, 0) + 10
        let available = max(totalHeight - top - bottom, 0)
        return min(max(top + available / 2, 0), max(totalHeight, 0))
    }

    private func previewWidth(in totalWidth: CGFloat) -> CGFloat? {
        guard !isRailOnly else { return nil }
        let available = totalWidth - previewLeadingX - 8
        guard available >= 220 else { return nil }
        return min(360, available)
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
                        schedulePreviewClose()
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
        return WeiBeiTheme.secondaryInk.opacity(appearanceMode == .inkstone ? 0.78 : 0.58)
    }

    private func railSpacing(count: Int, height: CGFloat) -> CGFloat {
        guard count > 1 else { return 0 }
        let verticalInset = min(7, height / 2)
        let available = max(height - verticalInset * 2, 0)
        return min(8, available / CGFloat(count - 1))
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
        HStack(alignment: .top, spacing: item.previewImage == nil ? 0 : 12) {
            if let image = item.previewImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 88, height: 112)
                    .clipped()
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(label)
                    .font(.system(size: 9.5, weight: .semibold, design: .serif))
                    .tracking(0.7)
                    .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.78))
                    .lineLimit(1)

                Text(item.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.ink)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !item.excerpt.isEmpty {
                    Text(item.excerpt)
                        .font(.system(size: 12.5))
                        .lineSpacing(3)
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                        .lineLimit(item.previewImage == nil ? 4 : 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !item.metadata.isEmpty {
                    Text(item.metadata)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
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
        .shadow(color: WeiBeiTheme.ink.opacity(appearanceMode == .inkstone ? 0.22 : 0.08), radius: 8, y: 4)
        .accessibilityHidden(true)
    }

    private func beginHover(_ item: ContentRailItem) {
        previewCloseWork?.cancel()
        previewOpenWork?.cancel()
        hoveredID = item.id

        guard previewID != item.id else {
            onHover(item)
            return
        }

        let work = DispatchWorkItem {
            guard hoveredID == item.id else { return }
            withAnimation(WeiBeiMotion.hover) {
                previewID = item.id
            }
            onHover(item)
        }
        previewOpenWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10, execute: work)
    }

    private func endHover(_ item: ContentRailItem) {
        if hoveredID == item.id {
            hoveredID = nil
        }
        schedulePreviewClose()
    }

    private func schedulePreviewClose() {
        previewCloseWork?.cancel()
        let work = DispatchWorkItem {
            guard hoveredID == nil else { return }
            closePreview(immediately: false)
        }
        previewCloseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func closePreview(immediately: Bool) {
        previewOpenWork?.cancel()
        previewCloseWork?.cancel()
        hoveredID = nil
        if immediately {
            previewID = nil
        } else {
            withAnimation(WeiBeiMotion.hover) {
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
