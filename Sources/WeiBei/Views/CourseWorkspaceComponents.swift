import AppKit
import Foundation
import SwiftUI
import WeiBeiCore

enum CourseProjectEntryIntent: Equatable {
    case create
    case adopt
}

struct CourseProjectEntryPresentation: Identifiable, Equatable {
    let id = UUID()
    let intent: CourseProjectEntryIntent
}

struct CourseProjectEntrySheet: View {
    @EnvironmentObject private var store: WorkspaceStore
    let cancel: () -> Void
    let openCourse: (UUID) -> Void

    @State private var intent: CourseProjectEntryIntent
    @State private var title = ""
    @State private var selectedFolder: URL?
    @State private var configuredLibraryThisTime = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var rebindProposal: CourseProjectRebindProposal?
    @FocusState private var titleFocused: Bool

    init(
        initialIntent: CourseProjectEntryIntent = .create,
        cancel: @escaping () -> Void,
        openCourse: @escaping (UUID) -> Void
    ) {
        _intent = State(initialValue: initialIntent)
        self.cancel = cancel
        self.openCourse = openCourse
    }

    private var needsLibrary: Bool {
        intent == .create
            && store.courseLibraryRootURL == nil
            && !configuredLibraryThisTime
    }

    private var libraryNeedsReauthorization: Bool {
        needsLibrary && store.courseLibraryRootPath != nil
    }

    private var cleanedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(heading)
                    .font(WeiBeiTypography.brandFont(
                        language: store.interfaceLanguage,
                        size: 21,
                        weight: .semibold
                    ))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if needsLibrary {
                libraryPicker
            } else if intent == .adopt {
                adoptionPicker
            } else {
                courseTitleField
                if let libraryPath = store.courseLibraryRootURL?.path {
                    pathLine(
                        label: store.ui("魏碑资料库", "WeiBei Library"),
                        path: libraryPath
                    )
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11.5))
                    .foregroundStyle(WeiBeiTheme.cinnabar)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(Text(store.ui(
                        "错误：\(errorMessage)",
                        "Error: \(errorMessage)"
                    )))
            }

            actionBar
        }
        .padding(22)
        .frame(width: 460)
        .background(WeiBeiTheme.paper)
        .foregroundStyle(WeiBeiTheme.ink)
        .interactiveDismissDisabled(isWorking)
        .onAppear(perform: updateFocus)
        .onChange(of: intent) { _, _ in updateFocus() }
        .onChange(of: selectedFolder) { _, _ in updateFocus() }
    }

    private var heading: String {
        if rebindProposal != nil {
            return store.ui(
                "重新绑定这门课程？",
                "Reconnect This Course?"
            )
        }
        if needsLibrary {
            return libraryNeedsReauthorization
                ? store.ui("重新授权魏碑资料库", "Reconnect WeiBei Library")
                : store.ui("选择魏碑资料库", "Choose WeiBei Library")
        }
        switch intent {
        case .create:
            return store.ui("新建课程", "Create Course")
        case .adopt:
            return store.ui("纳入已有课程文件夹", "Add Existing Course Folder")
        }
    }

    private var detail: String {
        if let rebindProposal {
            switch rebindProposal.impact {
            case .unchanged:
                return store.ui(
                    "魏碑认出了同一门课程，原文件夹当前无法访问。确认后只把课程连接到所选文件夹；课程 ID、对话、学习记忆、关系和阅读位置都会保留。",
                    "WeiBei recognized the same course, and its original folder is unavailable. Confirm to reconnect it while preserving its identity and learning state."
                )
            case .useNewerCandidate:
                return store.ui(
                    "魏碑认出了同一门课程，所选文件夹带有更新的课程状态。确认后会采用其中更新的对话、学习记忆、关系和阅读位置。",
                    "WeiBei recognized the same course with newer portable state. Confirm to use the newer chats, memory, links, and reading position from this folder."
                )
            }
        }
        if needsLibrary {
            if libraryNeedsReauthorization {
                return store.ui(
                    "魏碑记得原资料库，但当前无法访问。请重新选择同一资料库；为避免课程误绑到别处，选择不同文件夹会被拒绝。",
                    "WeiBei remembers the library but cannot access it. Re-select the same library; a different folder will be rejected to protect course identity."
                )
            }
            return store.ui(
                "先选择一个本地文件夹作为魏碑资料库。之后每门新课程都会在其中拥有自己的真实文件夹。",
                "Choose a local WeiBei Library. Each new course will get its own real folder inside it."
            )
        }
        switch intent {
        case .create:
            return store.ui(
                "魏碑会为这门课创建文稿、笔记和本地课程状态，课程 Agent 只在这个项目范围内工作。",
                "WeiBei will create materials, notes, and local course state for this course."
            )
        case .adopt:
            return store.ui(
                "原地登记一个已有文件夹为课程；不会复制、移动或重排其中的可见内容。",
                "Register an existing folder in place without copying, moving, or rearranging its visible contents."
            )
        }
    }

    private var libraryPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            if libraryNeedsReauthorization {
                if let path = store.courseLibraryRootPath {
                    pathLine(
                        label: store.ui("原魏碑资料库", "Original WeiBei Library"),
                        path: path
                    )
                }
                Label(
                    store.courseLibraryUnavailableReason
                        ?? store.ui("当前无法访问这个资料库。", "This library is currently unavailable."),
                    systemImage: "exclamationmark.triangle"
                )
                .font(.system(size: 12))
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Label(
                    store.ui("建议选择或新建一个名为“魏碑”的总文件夹。", "Choose or create a top-level WeiBei folder."),
                    systemImage: "folder"
                )
                .font(.system(size: 12))
                .foregroundStyle(WeiBeiTheme.secondaryInk)
            }

            Button(
                libraryNeedsReauthorization
                    ? store.ui("重新选择同一资料库…", "Re-select the Same Library…")
                    : store.ui("选择魏碑资料库…", "Choose WeiBei Library…"),
                action: chooseLibrary
            )
                .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
                .keyboardShortcut(.defaultAction)
                .disabled(isWorking)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WeiBeiTheme.paperRaised.opacity(0.34), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var adoptionPicker: some View {
        if let rebindProposal {
            pathLine(
                label: store.ui(
                    "新的课程文件夹",
                    "New course folder"
                ),
                path: rebindProposal.candidateRoot.path
            )
            Label(
                store.ui(
                    "只有确认后才会改绑；取消不会修改课程或文件夹。",
                    "Nothing changes until you confirm. Cancel leaves the course and folder untouched."
                ),
                systemImage: "arrow.triangle.2.circlepath"
            )
            .font(.system(size: 12))
            .foregroundStyle(WeiBeiTheme.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
        } else if let selectedFolder {
            pathLine(
                label: store.ui("课程文件夹", "Course folder"),
                path: selectedFolder.path
            )
            courseTitleField
        } else {
            Button(store.ui("选择课程文件夹…", "Choose Course Folder…"), action: chooseAdoptionFolder)
                .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
                .keyboardShortcut(.defaultAction)
                .disabled(isWorking)
        }
    }

    private var courseTitleField: some View {
        TextField(store.ui("课程名", "Course title"), text: $title)
            .textFieldStyle(.plain)
            .focused($titleFocused)
            .font(.system(size: 13))
            .foregroundColor(WeiBeiTheme.ink)
            .weibeiInputSurface(active: titleFocused, height: 32)
            .onSubmit(submitCurrentIntent)
            .disabled(isWorking)
            .accessibilityLabel(Text(store.ui("课程名称", "Course title")))
    }

    private func pathLine(label: String, path: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.tertiaryInk)
            Text(path)
                .font(.system(size: 11.5))
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .lineLimit(2)
                .truncationMode(.middle)
                .help(path)
                .accessibilityLabel(Text("\(label)：\(path)"))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WeiBeiTheme.paperRaised.opacity(0.30), in: RoundedRectangle(cornerRadius: 9))
    }

    @ViewBuilder
    private var actionBar: some View {
        HStack(spacing: 8) {
            if rebindProposal != nil {
                Button(store.ui("重新选择", "Choose Again")) {
                    rebindProposal = nil
                    selectedFolder = nil
                    errorMessage = nil
                }
                .buttonStyle(WeiBeiTextActionButtonStyle())
                .disabled(isWorking)
            } else if needsLibrary || intent == .create {
                Button(store.ui("纳入已有文件夹", "Add Existing Folder")) {
                    intent = .adopt
                    selectedFolder = nil
                    title = ""
                    errorMessage = nil
                    rebindProposal = nil
                }
                .buttonStyle(WeiBeiTextActionButtonStyle())
                .disabled(isWorking)
            } else {
                Button(store.ui("返回新建课程", "Back to Create")) {
                    intent = .create
                    selectedFolder = nil
                    title = ""
                    errorMessage = nil
                    rebindProposal = nil
                }
                .buttonStyle(WeiBeiTextActionButtonStyle())
                .disabled(isWorking)
            }

            Spacer()

            if isWorking {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(Text(store.ui("正在处理课程", "Working on course")))
            }

            Button(store.ui("取消", "Cancel"), action: cancel)
                .buttonStyle(WeiBeiTextActionButtonStyle())
                .keyboardShortcut(.cancelAction)
                .disabled(isWorking)

            if rebindProposal != nil {
                Button(
                    store.ui(
                        "确认重新绑定",
                        "Confirm Reconnect"
                    ),
                    action: confirmRebind
                )
                .buttonStyle(
                    WeiBeiTextActionButtonStyle(active: true)
                )
                .keyboardShortcut(.defaultAction)
                .disabled(isWorking)
            } else if !needsLibrary, intent == .create {
                Button(store.ui("创建", "Create"), action: createCourse)
                    .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(cleanedTitle.isEmpty || isWorking)
            } else if intent == .adopt, selectedFolder != nil {
                Button(store.ui("重新选择", "Choose Again"), action: chooseAdoptionFolder)
                    .buttonStyle(WeiBeiTextActionButtonStyle())
                    .disabled(isWorking)
                Button(store.ui("纳入课程", "Add Course"), action: adoptCourse)
                    .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(cleanedTitle.isEmpty || isWorking)
            }
        }
    }

    private func chooseLibrary() {
        let panel = NSOpenPanel()
        panel.title = libraryNeedsReauthorization
            ? store.ui("重新选择同一魏碑资料库", "Re-select the Same WeiBei Library")
            : store.ui("选择魏碑资料库", "Choose WeiBei Library")
        panel.message = libraryNeedsReauthorization
            ? store.ui(
                "请选择原来的魏碑资料库。若选择不同文件夹，魏碑会拒绝改绑。",
                "Choose the original WeiBei Library. WeiBei will reject a different folder."
            )
            : store.ui(
                "选择或新建一个总文件夹；每门课程会在其中建立独立项目目录。",
                "Choose or create a parent folder for independent course projects."
            )
        panel.prompt = libraryNeedsReauthorization
            ? store.ui("重新授权", "Reconnect")
            : store.ui("设为魏碑资料库", "Use as WeiBei Library")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform {
            try await store.configureCourseLibraryAsync(at: url)
            configuredLibraryThisTime = true
            updateFocus()
        }
    }

    private func chooseAdoptionFolder() {
        let panel = NSOpenPanel()
        panel.title = store.ui("选择课程文件夹", "Choose Course Folder")
        panel.message = store.ui(
            "魏碑会原地纳入这个文件夹，不移动其中的可见内容。",
            "WeiBei will register this folder in place without moving visible contents."
        )
        panel.prompt = store.ui("选择", "Choose")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        intent = .adopt
        selectedFolder = url.standardizedFileURL
        title = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        errorMessage = nil
        rebindProposal = nil
    }

    private func submitCurrentIntent() {
        if rebindProposal != nil {
            confirmRebind()
            return
        }
        guard !cleanedTitle.isEmpty else { return }
        switch intent {
        case .create:
            guard !needsLibrary else { return }
            createCourse()
        case .adopt:
            guard selectedFolder != nil else { return }
            adoptCourse()
        }
    }

    private func createCourse() {
        perform {
            let courseID = try await store.createCourseInLibraryAsync(
                title: cleanedTitle
            )
            openCourse(courseID)
        }
    }

    private func adoptCourse() {
        guard let selectedFolder else { return }
        perform {
            let outcome = try await store.adoptCourseFolderOrProposeRebindAsync(
                at: selectedFolder,
                title: cleanedTitle
            )
            switch outcome {
            case .opened(let courseID):
                openCourse(courseID)
            case .requiresRebind(let proposal):
                rebindProposal = proposal
                title = proposal.courseTitle
            }
        }
    }

    private func confirmRebind() {
        guard let rebindProposal else { return }
        perform {
            let courseID = try await store.confirmCourseProjectRebindAsync(
                rebindProposal
            )
            self.rebindProposal = nil
            openCourse(courseID)
        }
    }

    private func perform(
        _ action: @escaping @MainActor () async throws -> Void
    ) {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        Task { @MainActor in
            await Task.yield()
            do {
                try await action()
            } catch {
                errorMessage = error.localizedDescription
                announceError(error.localizedDescription)
            }
            isWorking = false
        }
    }

    private func announceError(_ message: String) {
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: store.ui("错误：\(message)", "Error: \(message)"),
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }

    private func updateFocus() {
        titleFocused = !needsLibrary
            && (intent == .create || selectedFolder != nil)
    }
}

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
