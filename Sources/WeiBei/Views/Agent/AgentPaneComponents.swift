import AppKit
import PDFKit
import SwiftUI
import WeiBeiCore

struct AgentPaneWidthKey: PreferenceKey {
    /// 0 = unmeasured. Must NOT default to 960: reduce used to max with 960 and
    /// multi-pane strips (e.g. 360pt) were forever treated as full-window wide,
    /// so messages/input centered off-canvas and "didn't adapt".
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 1 {
            value = next
        }
    }
}

struct AgentStarterChip: View {
    var title: String
    var systemImage: String
    var help: String
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .font(.system(size: 11.5, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 8)
                .frame(height: 26)
        }
        .buttonStyle(.plain)
        .foregroundStyle(hovering ? WeiBeiTheme.ink : WeiBeiTheme.secondaryInk)
        .background(WeiBeiTheme.paperInset.opacity(hovering ? 0.18 : 0.0))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(hovering ? WeiBeiTheme.hairline.opacity(0.56) : WeiBeiTheme.hairline.opacity(0.0), lineWidth: 1)
        }
        .offset(y: hovering ? -1 : 0)
        .accessibilityLabel(Text(help))
        .help(help)
        .onHover { value in
            withAnimation(WeiBeiMotion.hover) {
                hovering = value
            }
        }
    }
}

struct AgentSelectionAttachmentPill: View {
    @EnvironmentObject private var store: WorkspaceStore
    @State private var pillHovering = false
    @State private var popoverHovering = false
    @State private var closeToken = UUID()

    var body: some View {
        if store.hasSelectionAttachments {
            HStack(spacing: 4) {
                // Popover anchor is only the label — keep the clear button outside so the first
                // click is not eaten by hover-popover dismissal.
                HStack(spacing: 6) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 11, weight: .medium))
                    Text(store.ui("\(store.selectionAttachments.count) 个已选文本片段", "\(store.selectionAttachments.count) selected text fragments"))
                        .font(.system(size: 12, weight: .medium))
                }
                .contentShape(Rectangle())
                .onHover { value in
                    setPillHovering(value)
                }
                .popover(isPresented: popoverPresented, arrowEdge: .bottom) { popoverContent }

                Button(action: clearAllAttachments) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(WeiBeiIconButtonStyle(size: 18))
                .accessibilityLabel(Text(store.ui("清空已选文本片段", "Clear selected text fragments")))
                .help(store.ui("清空已选文本片段", "Clear selected text fragments"))
            }
            .foregroundStyle(pillHovering ? WeiBeiTheme.ink : WeiBeiTheme.secondaryInk)
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .frame(height: 28)
            .background(WeiBeiTheme.paperRaised.opacity(pillHovering ? 0.72 : 0.54))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(WeiBeiTheme.hairline.opacity(pillHovering ? 0.68 : 0.38), lineWidth: 1)
            }
            .accessibilityLabel(Text(store.ui("\(store.selectionAttachments.count) 个已选文本片段", "\(store.selectionAttachments.count) selected text fragments")))
            .help(store.ui("悬停查看选区", "Hover to preview selections"))
        }
    }

    private func clearAllAttachments() {
        closeToken = UUID()
        pillHovering = false
        popoverHovering = false
        store.clearSelectionAttachments()
    }

    private var popoverPresented: Binding<Bool> {
        Binding(
            get: { pillHovering || popoverHovering },
            set: { presented in
                if !presented {
                    pillHovering = false
                    popoverHovering = false
                }
            }
        )
    }

    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(store.ui("\(store.selectionAttachments.count) 个已选文本片段", "\(store.selectionAttachments.count) selected text fragments"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.ink)
                Spacer()
                Text(store.ui("发问时会作为上下文", "Used as context when asking"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
                Button(store.ui("清空", "Clear")) {
                    clearAllAttachments()
                }
                .buttonStyle(WeiBeiTextActionButtonStyle())
                .help(store.ui("清空全部选区片段", "Clear all selected fragments"))
            }

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 9) {
                    ForEach(Array(store.selectionAttachments.enumerated()), id: \.element.id) { index, selection in
                        selectionAttachmentRow(index: index, selection: selection)
                    }
                }
            }
            .frame(maxHeight: 260)
        }
        .padding(12)
        .frame(width: 360, alignment: .leading)
        .background(WeiBeiTheme.paperRaised)
        .onHover { value in
            setPopoverHovering(value)
        }
    }

    private func selectionAttachmentRow(index: Int, selection: SelectionContext) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(store.ui("片段 \(index + 1)", "Fragment \(index + 1)"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.ink)
                Text(selection.ownerTitle)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                Spacer(minLength: 8)
                Button {
                    let shouldClose = store.selectionAttachments.count <= 1
                    closeToken = UUID()
                    store.removeSelectionAttachment(id: selection.id)
                    if shouldClose {
                        pillHovering = false
                        popoverHovering = false
                    }
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(WeiBeiIconButtonStyle(size: 20))
                .accessibilityLabel(Text(store.ui("移除片段 \(index + 1)", "Remove fragment \(index + 1)")))
                .help(store.ui("移除这个选区片段", "Remove this selected fragment"))
            }

            Text(selection.text)
                .font(.system(size: 12))
                .lineSpacing(3)
                .lineLimit(5)
                .foregroundStyle(WeiBeiTheme.ink)
                .allowsHitTesting(false)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 1)
        }
        .padding(9)
        .background(WeiBeiTheme.paperInset.opacity(0.32))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(WeiBeiTheme.hairline.opacity(0.36), lineWidth: 1)
        }
    }

    private func setPillHovering(_ value: Bool) {
        if value {
            closeToken = UUID()
            withAnimation(WeiBeiMotion.hover) {
                pillHovering = true
            }
        } else {
            schedulePopoverClose()
        }
    }

    private func setPopoverHovering(_ value: Bool) {
        if value {
            closeToken = UUID()
            popoverHovering = true
        } else {
            popoverHovering = false
            schedulePopoverClose()
        }
    }

    private func schedulePopoverClose() {
        let token = UUID()
        closeToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            guard closeToken == token, !popoverHovering else { return }
            withAnimation(WeiBeiMotion.hover) {
                pillHovering = false
                popoverHovering = false
            }
        }
    }
}

