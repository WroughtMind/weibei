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
    static let normalWidth: CGFloat = 28
    static let railOnlyWidth: CGFloat = 88
    static let railOnlyThreshold: CGFloat = 150
    static let snapThreshold: CGFloat = 160
    static let readableWidth: CGFloat = 240
    static let defaultReadableWidth: CGFloat = 420
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
            railColumn(height: geometry.size.height)
        }
        .frame(width: railWidth)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(label))
        .animation(WeiBeiMotion.panel, value: isRailOnly)
        .animation(WeiBeiMotion.hover, value: previewID)
        .onChange(of: items.map(\.id)) { _, ids in
            guard let previewID, !ids.contains(previewID) else { return }
            closePreview(immediately: true)
        }
        .onDisappear {
            previewOpenWork?.cancel()
            previewCloseWork?.cancel()
            if previewID != nil {
                onHover(nil)
            }
        }
    }

    private var railWidth: CGFloat {
        isRailOnly ? ContentRailMetrics.railOnlyWidth : ContentRailMetrics.normalWidth
    }

    private var previewWidth: CGFloat {
        336
    }

    private func railColumn(height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            railBackground

            Rectangle()
                .fill(WeiBeiTheme.hairline.opacity(isRailOnly ? 0.54 : 0.30))
                .frame(width: 1)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .allowsHitTesting(false)

            if items.isEmpty {
                emptyOriginMark
                    .position(
                        x: railWidth / 2,
                        y: railY(position: 0, height: height)
                    )
            } else {
                let hitHeight = railHitHeight(for: height)
                ForEach(items) { item in
                    railButton(for: item, hitHeight: hitHeight, acceptsPointer: hitHeight >= 4)
                        .position(
                            x: railWidth / 2,
                            y: railY(position: item.position, height: height)
                        )
                }

                if hitHeight < 4 {
                    denseRailPointerSurface(height: height)
                }
            }
        }
        .frame(width: railWidth, height: height)
    }

    private var railBackground: some View {
        Rectangle()
            .fill(
                isRailOnly
                    ? WeiBeiTheme.paperRaised.opacity(appearanceMode == .inkstone ? 0.18 : 0.24)
                    : Color.clear
            )
    }

    private var emptyOriginMark: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(WeiBeiTheme.hairline.opacity(0.44))
                .frame(width: isRailOnly ? 18 : 8, height: 1.5)
            Spacer(minLength: 0)
        }
            .padding(.horizontal, tickHorizontalInset)
            .frame(width: railWidth, height: 24)
            .accessibilityLabel(Text("\(label)：暂无可导航内容"))
    }

    private func railButton(for item: ContentRailItem, hitHeight: CGFloat, acceptsPointer: Bool) -> some View {
        let active = item.id == activeID

        return Button {
            activate(item)
        } label: {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(tickColor(itemID: item.id, active: active))
                    .frame(
                        width: tickLength(level: item.level, active: active),
                        height: active ? 2.5 : 1.5
                    )
                Spacer(minLength: 0)
            }
                .padding(.horizontal, tickHorizontalInset)
                .frame(width: railWidth, height: hitHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(label)：\(item.title)"))
        .accessibilityValue(Text(active ? "当前位置" : item.metadata))
        .help(item.title)
        .allowsHitTesting(acceptsPointer)
        .popover(
            isPresented: previewBinding(for: item),
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .leading
        ) {
            previewCard(for: item)
                .frame(width: previewWidth)
                .padding(4)
        }
        .onHover { hovering in
            if hovering {
                beginHover(item)
            } else {
                endHover(item)
            }
        }
        .animation(WeiBeiMotion.micro, value: activeID)
        .animation(WeiBeiMotion.hover, value: hoveredID)
    }

    private func denseRailPointerSurface(height: CGFloat) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    if let item = nearestItem(to: location.y, height: height) {
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
            .frame(width: railWidth, height: height)
            .accessibilityHidden(true)
    }

    private var tickHorizontalInset: CGFloat {
        isRailOnly ? 16 : 4
    }

    private func tickLength(level: Int, active: Bool) -> CGFloat {
        if active {
            return isRailOnly ? 56 : 20
        }
        let base: CGFloat = isRailOnly ? 34 : 14
        let minimum: CGFloat = isRailOnly ? 10 : 6
        return max(minimum, base - CGFloat(min(level, 4)) * (isRailOnly ? 6 : 2))
    }

    private func tickColor(itemID: String, active: Bool) -> Color {
        if active {
            return appearanceMode == .inkstone ? WeiBeiTheme.onCinnabar : WeiBeiTheme.cinnabar
        }
        if hoveredID == itemID {
            return WeiBeiTheme.secondaryInk.opacity(0.72)
        }
        return WeiBeiTheme.hairline.opacity(0.86)
    }

    private func railY(position: CGFloat, height: CGFloat) -> CGFloat {
        let top = max(topInset, 0) + 12
        let bottom = max(bottomInset, 0) + 12
        let available = max(height - top - bottom, 0)
        return min(max(top + min(max(position, 0), 1) * available, 12), max(height - 12, 12))
    }

    private func railHitHeight(for height: CGFloat) -> CGFloat {
        guard !items.isEmpty else { return 24 }
        let available = max(height - max(topInset, 0) - max(bottomInset, 0) - 24, 1)
        return min(24, available / CGFloat(items.count))
    }

    private func nearestItem(to y: CGFloat, height: CGFloat) -> ContentRailItem? {
        guard !items.isEmpty else { return nil }
        let top = max(topInset, 0) + 12
        let bottom = max(bottomInset, 0) + 12
        let available = max(height - top - bottom, 1)
        let position = min(max((y - top) / available, 0), 1)
        return items.min { abs($0.position - position) < abs($1.position - position) }
    }

    private func previewCard(for item: ContentRailItem) -> some View {
        Button {
            activate(item)
        } label: {
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
            .frame(width: previewWidth, alignment: .leading)
            .background(WeiBeiTheme.paperRaised)
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(WeiBeiTheme.hairline.opacity(0.82), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .shadow(color: WeiBeiTheme.ink.opacity(appearanceMode == .inkstone ? 0.22 : 0.08), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(item.title)，点击打开"))
        .onHover { hovering in
            if hovering {
                holdPreview(item)
            } else {
                endHover(item)
            }
        }
    }

    private func previewBinding(for item: ContentRailItem) -> Binding<Bool> {
        Binding(
            get: { previewID == item.id },
            set: { presented in
                guard !presented, previewID == item.id else { return }
                closePreview(immediately: true)
            }
        )
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

    private func holdPreview(_ item: ContentRailItem) {
        previewCloseWork?.cancel()
        hoveredID = item.id
        if previewID != item.id {
            withAnimation(WeiBeiMotion.hover) {
                previewID = item.id
            }
        }
        onHover(item)
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
