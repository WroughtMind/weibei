import Foundation
import SwiftUI
import WeiBeiCore

struct CourseRelationDetailHeader: View {
    @EnvironmentObject private var store: WorkspaceStore
    let mark: String
    let title: String
    let detail: String
    let manageTitle: String?
    let manage: (() -> Void)?
    let openTitle: String
    let open: () -> Void

    init(
        mark: String,
        title: String,
        detail: String,
        manageTitle: String? = nil,
        manage: (() -> Void)? = nil,
        openTitle: String,
        open: @escaping () -> Void
    ) {
        self.mark = mark
        self.title = title
        self.detail = detail
        self.manageTitle = manageTitle
        self.manage = manage
        self.openTitle = openTitle
        self.open = open
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(mark.uppercased())
                    .font(WeiBeiTypography.englishBrandFont(size: 9, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.76))
                Text(title)
                    .font(WeiBeiTypography.brandFont(language: store.interfaceLanguage, size: 20, weight: .semibold))
                    .lineLimit(2)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
            }

            Spacer()

            HStack(spacing: 8) {
                if let manageTitle, let manage {
                    Button(manageTitle, action: manage)
                        .buttonStyle(WeiBeiTextActionButtonStyle())
                }
                Button(openTitle, action: open)
                    .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
            }
        }
        .padding(.horizontal, 24)
        .frame(minHeight: 88)
        .background(WeiBeiTheme.paperRaised.opacity(0.28))
    }
}

struct CourseLinkedItemRow: View {
    @EnvironmentObject private var store: WorkspaceStore
    let item: StudyItem
    let detail: String

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: item.kind.systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(store.displayTitle(for: item))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WeiBeiTheme.ink)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .lineLimit(1)
            }
            Spacer()
            Text(store.ui("已关联", "Linked"))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(WeiBeiTheme.cinnabar)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 48)
        .accessibilityElement(children: .combine)
    }
}

enum CourseHubRowProminence {
    case normal
    case linked
    case dimmed
}

struct CourseWorkspaceRow: View {
    let icon: String
    let title: String
    let detail: String
    let status: String
    let selected: Bool
    var prominence: CourseHubRowProminence = .normal
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: selected || prominence == .linked ? .semibold : .medium))
                        .foregroundStyle(WeiBeiTheme.ink.opacity(prominence == .dimmed ? 0.55 : 1))
                        .lineLimit(1)
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(WeiBeiTheme.secondaryInk.opacity(prominence == .dimmed ? 0.7 : 1))
                        .lineLimit(1)
                }

                Spacer(minLength: 10)

                if !status.isEmpty {
                    Text(status)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(selected || prominence == .linked ? WeiBeiTheme.cinnabar : WeiBeiTheme.secondaryInk)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 58)
            .contentShape(Rectangle())
            .background(rowBackground)
            .overlay(alignment: .leading) {
                if selected || prominence == .linked {
                    Capsule()
                        .fill(prominence == .linked && !selected
                              ? WeiBeiTheme.cinnabar.opacity(0.55)
                              : WeiBeiTheme.secondaryInk.opacity(0.42))
                        .frame(width: 2, height: 24)
                        .padding(.leading, 3)
                }
            }
            .opacity(prominence == .dimmed ? 0.72 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(WeiBeiMotion.hover, value: hovering)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var iconColor: Color {
        if selected || prominence == .linked { return WeiBeiTheme.cinnabar }
        if prominence == .dimmed { return WeiBeiTheme.tertiaryInk }
        return WeiBeiTheme.secondaryInk
    }

    private var rowBackground: Color {
        if selected { return WeiBeiTheme.paperInset.opacity(0.38) }
        if prominence == .linked { return WeiBeiTheme.cinnabarSoft.opacity(0.28) }
        if hovering { return WeiBeiTheme.paperInset.opacity(0.18) }
        return .clear
    }
}

struct RelationSelectionRow: View {
    @EnvironmentObject private var store: WorkspaceStore
    let item: StudyItem
    let checked: Bool
    let detail: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(checked ? WeiBeiTheme.cinnabar : WeiBeiTheme.tertiaryInk)
                    .frame(width: 20)
                Image(systemName: item.kind.systemImage)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.displayTitle(for: item))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(WeiBeiTheme.ink)
                        .lineLimit(1)
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                        .lineLimit(1)
                }
                Spacer()
                Text(item.isNotebookNote
                     ? store.ui("笔记", "Note")
                     : item.kind.label(language: store.interfaceLanguage))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
            .background(hovering ? WeiBeiTheme.paperInset.opacity(0.18) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityValue(Text(checked ? store.ui("已关联", "Linked") : store.ui("未关联", "Not linked")))
    }
}

struct CourseDetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.secondaryInk)
            content
        }
    }
}

struct CourseContextLine: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .frame(width: 18)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .frame(width: 76, alignment: .leading)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(WeiBeiTheme.ink)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(WeiBeiTheme.paperRaised.opacity(0.30))
    }
}

struct CourseActionRow: View {
    let icon: String
    let title: String
    let detail: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WeiBeiTheme.ink)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .lineLimit(2)
            }
            Spacer()
            Button(actionTitle, action: action)
                .buttonStyle(WeiBeiTextActionButtonStyle())
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 50)
        .background(WeiBeiTheme.paperRaised.opacity(0.24))
    }
}

struct CourseAttentionRow: View {
    let title: String
    let count: Int
    let detail: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text("\(count)")
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(count == 0 ? WeiBeiTheme.tertiaryInk : WeiBeiTheme.cinnabar)
                    .frame(width: 34, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(WeiBeiTheme.ink)
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
            .background(hovering ? WeiBeiTheme.paperInset.opacity(0.18) : WeiBeiTheme.paperRaised.opacity(0.22))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct CourseEmptyState: View {
    let title: String
    let detail: String
    let systemImage: String
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.58))
                .frame(width: 28, height: 28, alignment: .center)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.ink)
                .lineLimit(1)
            Text(detail)
                .font(.system(size: 11.5))
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .lineLimit(2)
                .frame(minHeight: 32, alignment: alignment == .leading ? .topLeading : .top)
                .multilineTextAlignment(alignment == .leading ? .leading : .center)
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
        .padding(.vertical, 8)
    }
}

/// Hub column empty slot: top-aligned icon/title/detail so three columns share one baseline.
struct CourseHubColumnEmptyState: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.72))
                .frame(width: 28, height: 28, alignment: .center)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.ink)
                .lineLimit(1)
            Text(detail)
                .font(.system(size: 11.5))
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .lineLimit(2)
                .frame(height: 34, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

func courseTitleDisplayFont(_ title: String, size: CGFloat, weight: Font.Weight = .semibold) -> Font {
    if courseTitlePrefersEnglishBrandFont(title) {
        return WeiBeiTypography.englishBrandFont(size: size, weight: weight)
    }
    return WeiBeiTypography.brandFont(language: .chinese, size: size, weight: weight)
}

func courseTitlePrefersEnglishBrandFont(_ title: String) -> Bool {
    let scalars = title.unicodeScalars.filter { CharacterSet.letters.contains($0) }
    guard !scalars.isEmpty else { return false }
    let cjkCount = scalars.filter(isCJKLetter).count
    if cjkCount > 0 { return false }
    return scalars.contains { $0.isASCII }
}

private func isCJKLetter(_ scalar: UnicodeScalar) -> Bool {
    let value = scalar.value
    return (0x3400...0x4DBF).contains(value)
        || (0x4E00...0x9FFF).contains(value)
        || (0xF900...0xFAFF).contains(value)
        || (0x3040...0x30FF).contains(value)
        || (0xAC00...0xD7AF).contains(value)
}

struct CourseHairline: View {
    var axis: Axis = .horizontal

    var body: some View {
        Rectangle()
            .fill(WeiBeiTheme.hairline.opacity(0.62))
            .frame(
                width: axis == .vertical ? 1 : nil,
                height: axis == .horizontal ? 1 : nil
            )
            .frame(
                maxWidth: axis == .vertical ? 1 : .infinity,
                maxHeight: axis == .horizontal ? 1 : .infinity
            )
    }
}

func relationFooter(
    countTitle: String,
    statusTitle: String,
    errorTitle: String?,
    retryTitle: String,
    retry: @escaping () -> Void
) -> some View {
    HStack {
        Text(countTitle)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(WeiBeiTheme.cinnabar)
        Spacer()
        if let errorTitle {
            Text(errorTitle)
                .font(.system(size: 10.5))
                .foregroundStyle(WeiBeiTheme.cinnabar)
                .lineLimit(1)
            Button(retryTitle, action: retry)
                .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
        } else {
            Text(statusTitle)
                .font(.system(size: 10.5))
                .foregroundStyle(WeiBeiTheme.secondaryInk)
        }
    }
    .padding(.horizontal, 18)
    .frame(height: 46)
    .background(WeiBeiTheme.paperRaised.opacity(0.36))
}

func toggled(_ itemID: String, in values: Set<String>) -> Set<String> {
    var result = values
    if result.contains(itemID) {
        result.remove(itemID)
    } else {
        result.insert(itemID)
    }
    return result
}

@MainActor
func courseFolderLabel(_ item: StudyItem, store: WorkspaceStore) -> String {
    guard let url = item.url else {
        return item.isSample ? store.ui("内置示例", "Built-in sample") : store.displaySubtitle(for: item)
    }
    let folder = url.deletingLastPathComponent().lastPathComponent
    return folder.isEmpty ? url.deletingLastPathComponent().path : folder
}

@MainActor
func courseLocationLabel(_ location: StudyLocation, store: WorkspaceStore) -> String {
    if let title = location.locationTitle, !title.isEmpty {
        return title
    }
    if let page = location.pageIndex {
        return store.ui("第 \(page + 1) 页", "Page \(page + 1)")
    }
    return store.ui("已有阅读位置", "Reading position saved")
}

func courseWorkspaceAccent(colorIndex: Int) -> Color {
    switch ((colorIndex % 4) + 4) % 4 {
    case 0:
        return WeiBeiTheme.cinnabar
    case 1:
        return WeiBeiTheme.moss
    case 2:
        return WeiBeiTheme.link
    default:
        return WeiBeiTheme.secondaryInk
    }
}

func courseRelativeDate(_ date: Date, language: WeiBeiInterfaceLanguage) -> String {
    if abs(date.timeIntervalSinceNow) < 60 {
        return language.text("刚刚", "Now")
    }
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = Locale(identifier: language == .chinese ? "zh-Hans" : "en")
    formatter.unitsStyle = .short
    return formatter.localizedString(for: date, relativeTo: Date())
}

func courseMaterialMark(_ kind: StudyItemKind) -> String {
    switch kind {
    case .html: "HTML"
    case .pdf: "PDF"
    case .markdown: "MARKDOWN"
    case .text: "TEXT"
    }
}

@MainActor
func coursePhaseLabel(_ phase: StudyPhase, store: WorkspaceStore) -> String {
    switch phase {
    case .orient:
        store.ui("定位", "Orient")
    case .explore:
        store.ui("探索", "Explore")
    case .closeRead:
        store.ui("细读", "Close read")
    case .note:
        store.ui("记笔记", "Note")
    case .recall:
        store.ui("回忆", "Recall")
    case .consolidate:
        store.ui("巩固", "Consolidate")
    case .plan:
        store.ui("计划", "Plan")
    }
}
