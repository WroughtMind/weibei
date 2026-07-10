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
    @State private var isPointerInside = false
    @State private var pointerY: CGFloat?
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
            compactRail(height: height)
                .position(
                    x: railWidth / 2,
                    y: compactCenterY(in: geometry.size.height)
                )
        }
        .frame(width: railWidth)
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
            if ids.isEmpty {
                pointerY = nil
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

    private var railWidth: CGFloat {
        isRailOnly ? ContentRailMetrics.railOnlyWidth : ContentRailMetrics.normalWidth
    }

    private var previewWidth: CGFloat {
        336
    }

    private var compactWidth: CGFloat {
        isRailOnly ? 42 : 40
    }

    private var resolvedActiveID: String? {
        activeID ?? items.first?.id
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
                ForEach(items) { item in
                    railButton(
                        for: item,
                        railHeight: height,
                        hitHeight: hitHeight,
                        acceptsPointer: hitHeight >= 4
                    )
                    .position(
                        x: compactWidth / 2,
                        y: railY(position: item.position, height: height)
                    )
                }

                if hitHeight < 4 {
                    denseRailPointerSurface(height: height)
                }
            }
        }
        .frame(width: compactWidth, height: height)
        .contentShape(Rectangle())
        .onExitCommand {
            focusedItemID = nil
            isPointerInside = false
            pointerY = nil
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                isPointerInside = true
                updatePointerY(location.y, height: height)
            case .ended:
                isPointerInside = false
                restoreFocusedPointer(height: height)
            }
        }
        .onChange(of: focusedItemID) { _, _ in
            guard !isPointerInside else { return }
            restoreFocusedPointer(height: height)
        }
    }

    private var emptyOriginMark: some View {
        Rectangle()
            .fill(WeiBeiTheme.hairline.opacity(0.64))
            .frame(width: 8, height: 1.5)
            .frame(width: compactWidth, height: 34)
            .accessibilityLabel(Text(label))
    }

    private func compactHeight(in totalHeight: CGFloat) -> CGFloat {
        let top = max(topInset, 0) + 10
        let bottom = max(bottomInset, 0) + 10
        let available = max(totalHeight - top - bottom, 34)
        guard items.count > 1 else { return min(items.isEmpty ? 34 : 50, available) }

        let countDrivenHeight = 72 + CGFloat(min(max(items.count - 2, 0), 14)) * 6.3
        return min(max(72, countDrivenHeight), min(160, available))
    }

    private func compactCenterY(in totalHeight: CGFloat) -> CGFloat {
        let top = max(topInset, 0) + 10
        let bottom = max(bottomInset, 0) + 10
        let available = max(totalHeight - top - bottom, 0)
        return min(max(top + available / 2, 17), max(totalHeight - 17, 17))
    }

    private func updatePointerY(_ y: CGFloat, height: CGFloat) {
        let value = min(max(y, 0), height)
        guard pointerY == nil || abs((pointerY ?? value) - value) > 0.5 else { return }
        withAnimation(waveMotion) {
            pointerY = value
        }
    }

    private func restoreFocusedPointer(height: CGFloat) {
        let focusedItem = focusedItemID.flatMap { id in
            items.first(where: { $0.id == id })
        }
        withAnimation(waveMotion) {
            pointerY = focusedItem.map { railY(position: $0.position, height: height) }
        }
    }

    private func railButton(
        for item: ContentRailItem,
        railHeight: CGFloat,
        hitHeight: CGFloat,
        acceptsPointer: Bool
    ) -> some View {
        let active = item.id == resolvedActiveID

        return Button {
            activate(item)
        } label: {
            Rectangle()
                .fill(tickColor(itemID: item.id, active: active))
                .frame(
                    width: tickLength(for: item, active: active, railHeight: railHeight),
                    height: active ? 2 : 1.5
                )
                .opacity(tickOpacity(for: item, active: active, railHeight: railHeight))
                .frame(width: compactWidth, height: hitHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focusedItemID, equals: item.id)
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
            guard acceptsPointer else { return }
            if hovering {
                beginHover(item)
            } else {
                endHover(item)
            }
        }
        .animation(WeiBeiMotion.micro, value: activeID)
        .animation(WeiBeiMotion.hover, value: hoveredID)
        .animation(waveMotion, value: pointerY)
    }

    private func denseRailPointerSurface(height: CGFloat) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    isPointerInside = true
                    updatePointerY(location.y, height: height)
                    if let item = nearestItem(to: location.y, height: height),
                       hoveredID != item.id {
                        beginHover(item)
                    }
                case .ended:
                    isPointerInside = false
                    restoreFocusedPointer(height: height)
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

    private func tickLength(for item: ContentRailItem, active: Bool, railHeight: CGFloat) -> CGFloat {
        let normal: CGFloat = active ? 8 : (item.level == 0 ? 7 : 6)
        guard let pointerY else { return normal }

        let distance = abs(railY(position: item.position, height: railHeight) - pointerY)
        let influenceRadius: CGFloat = 48
        guard distance < influenceRadius else { return normal }
        let linear = 1 - distance / influenceRadius
        let influence = linear * linear * (3 - 2 * linear)
        return normal + (34 - normal) * influence
    }

    private func tickOpacity(for item: ContentRailItem, active: Bool, railHeight: CGFloat) -> Double {
        let normal: Double = active ? 1 : 0.64
        guard let pointerY else { return normal }

        let distance = abs(railY(position: item.position, height: railHeight) - pointerY)
        let influenceRadius: CGFloat = 48
        guard distance < influenceRadius else { return normal }
        let linear = 1 - distance / influenceRadius
        let influence = Double(linear * linear * (3 - 2 * linear))
        return normal + (1 - normal) * influence
    }

    private func tickColor(itemID: String, active: Bool) -> Color {
        if active {
            return appearanceMode == .inkstone ? WeiBeiTheme.onCinnabar : WeiBeiTheme.cinnabar
        }
        if hoveredID == itemID {
            return WeiBeiTheme.ink.opacity(0.92)
        }
        return WeiBeiTheme.hairline.opacity(0.92)
    }

    private func railY(position: CGFloat, height: CGFloat) -> CGFloat {
        let available = max(height - 14, 0)
        return min(max(7 + min(max(position, 0), 1) * available, 7), max(height - 7, 7))
    }

    private func railHitHeight(for height: CGFloat) -> CGFloat {
        guard !items.isEmpty else { return 20 }
        let available = max(height - 14, 1)
        return min(20, available / CGFloat(items.count))
    }

    private func nearestItem(to y: CGFloat, height: CGFloat) -> ContentRailItem? {
        guard !items.isEmpty else { return nil }
        let available = max(height - 14, 1)
        let position = min(max((y - 7) / available, 0), 1)
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
