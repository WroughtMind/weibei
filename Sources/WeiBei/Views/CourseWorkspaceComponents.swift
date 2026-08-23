import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import WeiBeiCore

enum CourseProjectEntryIntent: Equatable {
    case create
    case adopt
}

struct CourseProjectEntryPresentation: Identifiable, Equatable {
    let id = UUID()
    let intent: CourseProjectEntryIntent
}

struct CourseManagementPresentation: Identifiable, Equatable {
    let courseID: UUID
    var id: UUID { courseID }
}

struct CourseManagementSheet: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    let courseID: UUID

    @State private var trashConfirmationPresented = false
    @State private var unregisterConfirmationPresented = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var course: Course? {
        store.course(withID: courseID)
    }

    private var rootURL: URL? {
        store.courseRootURL(for: courseID)
    }

    private var rootUnavailableReason: String? {
        store.courseRootUnavailableReason(for: courseID)
    }

    private var canUseCourseFolder: Bool {
        rootURL != nil
            && rootUnavailableReason == nil
            && !isWorking
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(store.ui("课程设置", "Course Settings"))
                    .weiBeiBrandFont(language: store.interfaceLanguage, size: 22, weight: .semibold)
                if let course {
                    Text(course.title)
                        .weiBeiText(12, weight: .medium)
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                }
            }

            if let rootURL {
                VStack(alignment: .leading, spacing: 7) {
                    Text(store.ui("课程文件夹", "Course Folder"))
                        .weiBeiText(12, weight: .semibold)
                        .foregroundStyle(WeiBeiTheme.tertiaryInk)
                    Text(rootURL.path)
                        .weiBeiText(12, design: .monospaced)
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                        .textSelection(.enabled)
                        .lineLimit(3)
                        .truncationMode(.middle)
                        .help(rootURL.path)
                    Button(
                        store.ui(
                            "在 Finder 中显示",
                            "Show in Finder"
                        )
                    ) {
                        store.revealCourseRoot(courseID)
                    }
                    .buttonStyle(WeiBeiTextActionButtonStyle())
                    .disabled(!canUseCourseFolder)
                }
            }
            if let rootUnavailableReason {
                Label(
                    rootUnavailableReason,
                    systemImage: "folder.badge.questionmark"
                )
                .weiBeiText(12)
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            } else if rootURL == nil {
                Label(
                    store.ui(
                        "课程文件夹当前不可用。",
                        "The course folder is unavailable."
                    ),
                    systemImage: "folder.badge.questionmark"
                )
                .weiBeiText(12)
                .foregroundStyle(WeiBeiTheme.secondaryInk)
            }

            Divider()

            VStack(alignment: .leading, spacing: 9) {
                Text(store.ui("危险操作", "Danger Zone"))
                    .weiBeiText(12, weight: .semibold)
                    .foregroundStyle(WeiBeiTheme.cinnabar)
                if UnavailableCourseUnregister.shouldOfferUnregister(
                    rootURL: rootURL,
                    unavailableReason: rootUnavailableReason
                ) {
                    Text(store.ui(
                        UnavailableCourseUnregister.confirmationMessage(chinese: true),
                        UnavailableCourseUnregister.confirmationMessage(chinese: false)
                    ))
                    .weiBeiText(12)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)

                    Button(
                        store.ui("只从魏碑移除…", "Remove from WeiBei Only…"),
                        role: .destructive
                    ) {
                        unregisterConfirmationPresented = true
                    }
                    .disabled(isWorking)
                } else {
                    Text(store.ui(
                        "这会把整个真实课程文件夹及其中内容移到 macOS 废纸篓。只有移动成功后，课程才会从魏碑移除。",
                        "This moves the entire real course folder to the macOS Trash. WeiBei removes the course only after the move succeeds."
                    ))
                    .weiBeiText(12)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)

                    Button(
                        store.ui(
                            "将课程文件夹移到废纸篓…",
                            "Move Course Folder to Trash…"
                        ),
                        role: .destructive
                    ) {
                        trashConfirmationPresented = true
                    }
                    .disabled(!canUseCourseFolder)
                }
            }

            if isWorking {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(store.ui(
                        "正在安全移动课程文件夹…",
                        "Moving the course folder safely…"
                    ))
                    .weiBeiText(12)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                }
                .accessibilityElement(children: .combine)
            }

            if let errorMessage {
                Label(
                    errorMessage,
                    systemImage: "exclamationmark.triangle"
                )
                .weiBeiText(12)
                .foregroundStyle(WeiBeiTheme.cinnabar)
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button(store.ui("完成", "Done")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isWorking)
            }
        }
        .padding(22)
        .frame(width: 460)
        .background(WeiBeiTheme.paper)
        .foregroundStyle(WeiBeiTheme.ink)
        .interactiveDismissDisabled(isWorking)
        .confirmationDialog(
            store.ui(
                "将真实课程文件夹移到废纸篓？",
                "Move the real course folder to Trash?"
            ),
            isPresented: $trashConfirmationPresented,
            titleVisibility: .visible,
            presenting: rootURL
        ) { _ in
            Button(
                store.ui("移到废纸篓", "Move to Trash"),
                role: .destructive
            ) {
                moveToTrash()
            }
            .disabled(!canUseCourseFolder)
            Button(
                store.ui("取消", "Cancel"),
                role: .cancel
            ) {}
        } message: { rootURL in
            Text(store.ui(
                "将移动整个文件夹：\n\(rootURL.path)\n\n执行前魏碑会再次核验课程身份和路径。",
                "The entire folder will be moved:\n\(rootURL.path)\n\nWeiBei will verify its identity and path again before moving it."
            ))
        }
        .confirmationDialog(
            store.ui(
                UnavailableCourseUnregister.confirmationTitle(chinese: true),
                UnavailableCourseUnregister.confirmationTitle(chinese: false)
            ),
            isPresented: $unregisterConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(
                store.ui("只从魏碑移除", "Remove from WeiBei Only"),
                role: .destructive
            ) {
                unregisterFromWeiBei()
            }
            .disabled(isWorking)
            Button(
                store.ui("取消", "Cancel"),
                role: .cancel
            ) {}
        } message: {
            Text(store.ui(
                UnavailableCourseUnregister.confirmationMessage(chinese: true),
                UnavailableCourseUnregister.confirmationMessage(chinese: false)
            ))
        }
    }

    private func moveToTrash() {
        guard canUseCourseFolder else { return }
        isWorking = true
        errorMessage = nil
        Task { @MainActor in
            do {
                _ = try await store.moveCourseFolderToTrash(
                    courseID
                )
                dismiss()
            } catch {
                store.recordCourseLibraryUIFailure(
                    error,
                    operation: "move_course_to_trash",
                    path: store.courseRootURL(for: courseID)
                )
                errorMessage = store.ui(
                    "没有确认移动完成。请先检查课程列表和废纸篓；如果课程仍在魏碑，确认资料库可访问后再重试。",
                    "The move was not confirmed. Check the course list and Trash first. If the course is still in WeiBei, make sure the library is accessible before trying again."
                )
                isWorking = false
            }
        }
    }

    private func unregisterFromWeiBei() {
        isWorking = true
        errorMessage = nil
        Task { @MainActor in
            do {
                try await store.removeCourseFromWeiBei(courseID)
                dismiss()
            } catch {
                store.recordCourseLibraryUIFailure(
                    error,
                    operation: "unregister_course",
                    path: store.courseRootURL(for: courseID)
                )
                errorMessage = store.ui(
                    "没有从魏碑移除这门课程；课程登记和文件夹内容保持不变。请稍后重试。",
                    "The course was not removed from WeiBei. Its registration and folder contents remain unchanged. Try again later."
                )
                isWorking = false
            }
        }
    }
}

struct CourseProjectEntrySheet: View {
    @EnvironmentObject private var store: WorkspaceStore
    let cancel: () -> Void
    let openCourse: (UUID) -> Void

    @State private var intent: CourseProjectEntryIntent
    @State private var title = ""
    @State private var selectedFolder: URL?
    @State private var selectedImportURLs: [URL] = []
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
                    .weiBeiBrandFont(language: store.interfaceLanguage, size: 22, weight: .semibold)
                Text(detail)
                    .weiBeiText(12)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if needsLibrary {
                libraryPicker
            } else {
                courseTitleField
                if let libraryPath = store.courseLibraryRootURL?.path {
                    pathLine(
                        label: store.ui("魏碑资料库", "WeiBei Library"),
                        path: libraryPath
                    )
                }
                if intent == .create {
                    importPicker
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .weiBeiText(12)
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
            case .keepsLocalState:
                return store.ui(
                    "候选文件夹包含与本机不同的课程进度；确认后以本机进度为准，候选中的差异会以冲突备份保留。",
                    "The candidate folder has different course progress than this Mac. Confirm to keep local progress; differing files from the candidate will be kept as conflict backups."
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
                "魏碑会为这门课创建文稿、笔记和本地课程状态。Chat 始终是全局的，进入这门课只会把它设为当前学习现场。",
                "WeiBei will create materials, notes, and local course state. Chats remain global; entering this course only makes it the current study context."
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
                    store.ui(
                        "原资料库当前无法访问，课程记录仍保留。请重新选择同一资料库以恢复访问。",
                        "The original library is currently unavailable, but course records are preserved. Re-select the same library to restore access."
                    ),
                    systemImage: "exclamationmark.triangle"
                )
                .weiBeiText(12)
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Label(
                    store.ui("建议选择或新建一个名为“魏碑”的总文件夹。", "Choose or create a top-level WeiBei folder."),
                    systemImage: "folder"
                )
                .weiBeiText(12)
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
        .weibeiEtchedBackground(
            fill: WeiBeiTheme.paperRaised.opacity(0.34),
            stroke: WeiBeiTheme.hairline.opacity(0.3),
            cornerRadius: 12
        )
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
            .weiBeiText(12)
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
            .weiBeiText(13)
            .foregroundColor(WeiBeiTheme.ink)
            .weibeiInputSurface(active: titleFocused, height: 32)
            .onSubmit(submitCurrentIntent)
            .disabled(isWorking)
            .accessibilityLabel(Text(store.ui("课程名称", "Course title")))
    }

    private var importPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(
                selectedImportURLs.isEmpty
                    ? store.ui("同时选择现有文稿或文件夹…", "Choose Existing Files or Folder…")
                    : store.ui("重新选择导入内容…", "Choose Different Content…"),
                action: chooseImportContent
            )
            .buttonStyle(WeiBeiTextActionButtonStyle(active: selectedImportURLs.isEmpty))
            .disabled(isWorking)

            if !selectedImportURLs.isEmpty {
                Text(store.ui(
                    "已选择 \(selectedImportURLs.count) 项；课程创建后会直接导入。Markdown 会同时出现在文稿与笔记中。",
                    "Selected \(selectedImportURLs.count) item(s). Markdown will appear in both Materials and Notes."
                ))
                .weiBeiText(12)
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .weibeiEtchedBackground(
            fill: WeiBeiTheme.paperRaised.opacity(0.30),
            stroke: WeiBeiTheme.hairline.opacity(0.28),
            cornerRadius: 12
        )
    }

    private func pathLine(label: String, path: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .weiBeiText(10.5, weight: .semibold)
                .foregroundStyle(WeiBeiTheme.tertiaryInk)
            Text(path)
                .weiBeiText(12)
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .lineLimit(2)
                .truncationMode(.middle)
                .help(path)
                .accessibilityLabel(Text("\(label)：\(path)"))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .weibeiEtchedBackground(
            fill: WeiBeiTheme.paperRaised.opacity(0.30),
            stroke: WeiBeiTheme.hairline.opacity(0.28),
            cornerRadius: 12
        )
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
            } else if !needsLibrary {
                Button(
                    selectedImportURLs.isEmpty
                        ? store.ui("创建课程", "Create Course")
                        : store.ui("创建并导入", "Create and Import"),
                    action: createCourse
                )
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
        perform(
            failureMessage: libraryNeedsReauthorization
                ? store.ui(
                    "没有重新连接资料库，原课程记录仍保留。请重新选择原来的同一资料库。",
                    "The library was not reconnected, and existing course records are preserved. Re-select the same original library."
                )
                : store.ui(
                    "资料库没有更改，原课程记录和文件未被移动。请选择可访问的本地文件夹后重试。",
                    "The library was not changed. Existing course records and files were not moved. Choose an accessible local folder and try again."
                ),
            operation: "course_entry_configure_library",
            path: url
        ) {
            try await store.confirmAndConfigureCourseLibrary(at: url)
            if store.courseLibraryRootURL != nil {
                configuredLibraryThisTime = true
                updateFocus()
            }
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

    private func chooseImportContent() {
        let panel = NSOpenPanel()
        panel.title = store.ui("选择课程内容", "Choose Course Content")
        panel.message = store.ui(
            "可以选择多个文件或一个文件夹。Markdown 会作为同一个文件同时用于阅读和笔记。",
            "Choose files or a folder. Markdown stays one file and appears in both reading and notes."
        )
        panel.prompt = store.ui("选择", "Choose")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            .pdf,
            .html,
            .plainText,
            UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "markdown") ?? .plainText,
        ]
        guard panel.runModal() == .OK else { return }
        selectedImportURLs = panel.urls
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
        perform(
            failureMessage: store.ui(
                "课程没有创建完成，魏碑未确认登记；已有课程记录不受影响。请确认资料库可写后重试。",
                "The course was not created or registered. Existing course records are unaffected. Make sure the library is writable and try again."
            ),
            operation: "create_course",
            path: store.courseLibraryRootURL
        ) {
            let courseID = try await store.createCourseInLibraryAsync(
                title: cleanedTitle
            )
            if selectedImportURLs.isEmpty {
                openCourse(courseID)
            } else {
                store.importCourseFilesFromURLs(
                    selectedImportURLs,
                    courseID: courseID
                ) { _ in
                    openCourse(courseID)
                }
            }
        }
    }

    private func adoptCourse() {
        guard let selectedFolder else { return }
        perform(
            failureMessage: store.ui(
                "课程文件夹没有确认纳入魏碑；所选文件夹仍由你保留。请确认文件夹可访问后重试。",
                "The course folder was not confirmed as added to WeiBei. You still retain the selected folder. Make sure it is accessible and try again."
            ),
            operation: "adopt_course_folder",
            path: selectedFolder
        ) {
            let outcome = try await store.adoptCourseFolderOrProposeRebindAsync(
                at: selectedFolder,
                title: cleanedTitle
            )
            switch outcome {
            case .opened(let courseID):
                openCourse(courseID)
            case .requiresRebind(let proposal):
                // S6-5：无歧义（原根失联、状态 digest 相等）时单步自动确认；
                // H2：keepsLocalState / useNewerCandidate 弹一次确认。
                if proposal.impact == .unchanged {
                    let courseID = try await store.confirmCourseProjectRebindAsync(
                        proposal
                    )
                    openCourse(courseID)
                } else {
                    rebindProposal = proposal
                    title = proposal.courseTitle
                }
            }
        }
    }

    private func confirmRebind() {
        guard let rebindProposal else { return }
        perform(
            failureMessage: store.ui(
                "课程没有确认重新连接，原课程记录仍保留。请确认所选文件夹可访问后重试。",
                "The course was not confirmed as reconnected, and its original record remains. Make sure the selected folder is accessible and try again."
            ),
            operation: "rebind_course_folder"
        ) {
            let courseID = try await store.confirmCourseProjectRebindAsync(
                rebindProposal
            )
            self.rebindProposal = nil
            openCourse(courseID)
        }
    }

    private func perform(
        failureMessage: String,
        operation: String,
        path: URL? = nil,
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
                store.recordCourseLibraryUIFailure(
                    error,
                    operation: operation,
                    path: path
                )
                errorMessage = failureMessage
                announceError(failureMessage)
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
                    .weiBeiText(13, weight: .medium)
                    .foregroundStyle(iconColor)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .weiBeiText(13, weight: selected || prominence == .linked ? .semibold : .medium)
                        .foregroundStyle(WeiBeiTheme.ink.opacity(prominence == .dimmed ? 0.55 : 1))
                        .lineLimit(1)
                    Text(detail)
                        .weiBeiText(10.5)
                        .foregroundStyle(WeiBeiTheme.secondaryInk.opacity(prominence == .dimmed ? 0.7 : 1))
                        .lineLimit(1)
                }

                Spacer(minLength: 10)

                if !status.isEmpty {
                    Text(status)
                        .weiBeiText(10.5, weight: .medium)
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
                    .weiBeiText(15, weight: .medium)
                    .foregroundStyle(checked ? WeiBeiTheme.cinnabar : WeiBeiTheme.tertiaryInk)
                    .frame(width: 20)
                Image(systemName: item.kind.systemImage)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.displayTitle(for: item))
                        .weiBeiText(13, weight: .medium)
                        .foregroundStyle(WeiBeiTheme.ink)
                        .lineLimit(1)
                    Text(detail)
                        .weiBeiText(10.5)
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                        .lineLimit(1)
                }
                Spacer()
                Text(item.isNotebookNote
                     ? store.ui("笔记", "Note")
                     : item.kind.label(language: store.interfaceLanguage))
                    .weiBeiText(10.5, weight: .medium)
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

struct CourseEmptyState: View {
    let title: String
    let detail: String
    let systemImage: String
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 8) {
            Image(systemName: systemImage)
                .weiBeiText(18, weight: .regular)
                .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.58))
                .frame(width: 28, height: 28, alignment: .center)
            Text(title)
                .weiBeiText(13, weight: .semibold)
                .foregroundStyle(WeiBeiTheme.ink)
                .lineLimit(1)
            Text(detail)
                .weiBeiText(12)
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .lineLimit(2)
                .frame(minHeight: 32, alignment: alignment == .leading ? .topLeading : .top)
                .multilineTextAlignment(alignment == .leading ? .leading : .center)
        }
        .frame(
            maxWidth: alignment == .center ? 360 : .infinity,
            alignment: Alignment(horizontal: alignment, vertical: .center)
        )
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
        .padding(.vertical, 8)
    }
}

/// Hub column empty slot: top-aligned icon/title/detail so three columns share one baseline.
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
            .weiBeiText(12, weight: .semibold)
            .foregroundStyle(WeiBeiTheme.cinnabar)
        Spacer()
        if let errorTitle {
            Text(errorTitle)
                .weiBeiText(10.5)
                .foregroundStyle(WeiBeiTheme.cinnabar)
                .lineLimit(1)
            Button(retryTitle, action: retry)
                .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
        } else {
            Text(statusTitle)
                .weiBeiText(10.5)
                .foregroundStyle(WeiBeiTheme.secondaryInk)
        }
    }
    .padding(.horizontal, 18)
    .frame(height: 46)
    .weibeiEtchedBackground(
    fill: WeiBeiTheme.paperRaised.opacity(0.36),
    stroke: WeiBeiTheme.hairline.opacity(0.3),
    cornerRadius: 8
)
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
        return store.displaySubtitle(for: item)
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
