import Foundation
import SwiftUI
import UniformTypeIdentifiers
import WeiBeiCore

/// Course hub: continue-learning launcher with materials, conversations, and notes.
/// Selecting a material still highlights linked conversations/notes (read-only; editing stays on 关系台).
struct CourseHubView: View {
    @EnvironmentObject private var store: WorkspaceStore
    let search: String
    @Binding var selectedMaterialID: String?
    @Binding var selectedNoteID: String?
    @Binding var selectedSessionID: UUID?
    let isCompact: Bool
    let openRelations: () -> Void
    let importMaterials: () -> Void
    let importNotes: () -> Void
    let createNote: () -> Void

    @State private var isMaterialDropTargeted = false
    @State private var isNoteDropTargeted = false
    @State private var courseEntryPresentation: CourseProjectEntryPresentation?

    private var courseID: UUID? { store.activeCourseID }

    private var materials: [StudyItem] {
        guard let courseID else { return [] }
        return filteredItems(store.courseMaterials(in: courseID))
    }

    private var notes: [StudyItem] {
        guard let courseID else { return [] }
        return filteredItems(store.courseNotes(in: courseID))
    }

    private var sessions: [StudySession] {
        guard let courseID else { return [] }
        let base = store.sessionsTouchingCourse(courseID)
            .sorted { $0.updatedAt > $1.updatedAt }
        let cleaned = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return base }
        return base.filter { session in
            session.title.localizedCaseInsensitiveContains(cleaned)
                || session.summary.localizedCaseInsensitiveContains(cleaned)
                || session.messages.contains { $0.text.localizedCaseInsensitiveContains(cleaned) }
        }
    }

    private var linkedNoteIDs: Set<String> {
        guard let selectedMaterialID else { return [] }
        return Set(store.linkedNoteIDs(for: selectedMaterialID))
    }

    private var linkedSessionIDs: Set<UUID> {
        guard let selectedMaterialID, let courseID else { return [] }
        return Set(store.sessionsTouchingMaterial(selectedMaterialID, in: courseID).map(\.id))
    }

    private var latestReading: (StudyItem, StudyLocation)? {
        materials
            .compactMap { item in store.studyLocation(for: item.id).map { (item, $0) } }
            .sorted { $0.1.lastStudiedAt > $1.1.lastStudiedAt }
            .first
    }

    private var latestSession: StudySession? {
        sessions.first
    }

    var body: some View {
        Group {
            if courseID == nil {
                coursePickerEmptyState
            } else {
                courseLauncherBody
            }
        }
        .onAppear(perform: ensureMaterialSelection)
        .onChange(of: courseID) { _, _ in
            selectedMaterialID = materials.first?.id
            selectedNoteID = nil
            selectedSessionID = nil
        }
        .onChange(of: materials.map(\.id)) { _, ids in
            if selectedMaterialID == nil || selectedMaterialID.map({ !ids.contains($0) }) == true {
                selectedMaterialID = ids.first
            }
        }
        .sheet(item: $courseEntryPresentation) { presentation in
            CourseProjectEntrySheet(
                initialIntent: presentation.intent,
                cancel: { courseEntryPresentation = nil },
                openCourse: { courseID in
                    courseEntryPresentation = nil
                    store.openCourseSpace(courseID)
                }
            )
            .environmentObject(store)
        }
    }

    // MARK: - No course selected

    private var coursePickerEmptyState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.ui("选择一门课程", "Choose a course"))
                        .font(WeiBeiTypography.brandFont(language: store.interfaceLanguage, size: 22, weight: .semibold))
                    Text(store.ui(
                        "进入后可继续上次阅读或对话，并浏览本课文稿与记录。",
                        "Continue reading or chat, and browse this course’s materials and records."
                    ))
                    .font(.system(size: 12.5))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                }

                if store.courses.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(store.ui("还没有课程", "No courses yet"))
                            .font(.system(size: 14, weight: .semibold))
                        Text(store.ui(
                            "每门课程都有自己的本地项目文件夹，里面可以放多份文稿与笔记。",
                            "Each course has a local project folder for its materials and notes."
                        ))
                        .font(.system(size: 12))
                        .foregroundStyle(WeiBeiTheme.secondaryInk)

                        HStack(spacing: 10) {
                            Button(store.ui("新建课程", "Create course")) {
                                courseEntryPresentation = CourseProjectEntryPresentation(intent: .create)
                            }
                            .buttonStyle(WeiBeiTextActionButtonStyle(active: true))

                            Button(store.ui("纳入已有文件夹", "Add existing folder")) {
                                courseEntryPresentation = CourseProjectEntryPresentation(intent: .adopt)
                            }
                            .buttonStyle(WeiBeiTextActionButtonStyle())
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(WeiBeiTheme.paperRaised.opacity(0.34), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    VStack(spacing: 0) {
                        ForEach(store.courses) { course in
                            let materialCount = store.courseMaterials(in: course.id).count
                            let noteCount = store.courseNotes(in: course.id).count
                            let sessionCount = store.sessionsTouchingCourse(course.id).count
                            Button {
                                store.activateCourse(course.id)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "book.closed")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(courseWorkspaceAccent(colorIndex: course.colorIndex))
                                        .frame(width: 22)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(course.title)
                                            .font(courseTitleDisplayFont(course.title, size: 14, weight: .semibold))
                                            .foregroundStyle(WeiBeiTheme.ink)
                                            .lineLimit(1)
                                        Text(store.ui(
                                            "文稿 \(materialCount) · 笔记 \(noteCount) · 对话 \(sessionCount)",
                                            "\(materialCount) materials · \(noteCount) notes · \(sessionCount) chats"
                                        ))
                                        .font(.system(size: 11))
                                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                                    }

                                    Spacer(minLength: 8)

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(WeiBeiTheme.tertiaryInk)
                                }
                                .padding(.horizontal, 14)
                                .frame(height: 56)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if course.id != store.courses.last?.id {
                                CourseHairline()
                                    .padding(.leading, 48)
                            }
                        }
                    }
                    .background(WeiBeiTheme.paperRaised.opacity(0.28), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(WeiBeiTheme.hairline.opacity(0.55), lineWidth: 1)
                    )

                    HStack(spacing: 10) {
                        Button(store.ui("新建课程", "Create course")) {
                            courseEntryPresentation = CourseProjectEntryPresentation(intent: .create)
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle())

                        Button(store.ui("纳入已有文件夹", "Add existing folder")) {
                            courseEntryPresentation = CourseProjectEntryPresentation(intent: .adopt)
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle())

                        // Keep menu label for header parity / self-check; top bar still has 选择课程.
                        Text(store.ui("也可使用顶栏选择课程", "Or pick a course from the title bar"))
                            .font(.system(size: 11))
                            .foregroundStyle(WeiBeiTheme.tertiaryInk)
                    }
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WeiBeiTheme.paper)
    }

    // MARK: - Course selected: continue + lists

    private var courseLauncherBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                courseSummaryHeader
                if let courseID,
                   let reason = store.courseRootUnavailableReason(
                    for: courseID
                   ) {
                    unavailableCourseRootBanner(reason: reason)
                }
                continueSection
                materialsSection
                sessionsSection
                notesSection
                secondaryActions
            }
            .frame(maxWidth: isCompact ? .infinity : 720, alignment: .leading)
            .padding(.horizontal, isCompact ? 20 : 36)
            .padding(.top, 28)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WeiBeiTheme.paper)
        .onDrop(of: [.fileURL], isTargeted: $isMaterialDropTargeted) { providers in
            handleDrop(providers, asNotes: false)
        }
    }

    private func unavailableCourseRootBanner(reason: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(WeiBeiTheme.cinnabar)

            VStack(alignment: .leading, spacing: 3) {
                Text(store.ui(
                    "课程文件夹暂时不可用",
                    "Course folder unavailable"
                ))
                .font(.system(size: 12.5, weight: .semibold))
                Text(reason)
                    .font(.system(size: 11))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button(store.ui(
                "重新连接…",
                "Reconnect…"
            )) {
                courseEntryPresentation = CourseProjectEntryPresentation(
                    intent: .adopt
                )
            }
            .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
        }
        .padding(14)
        .background(
            WeiBeiTheme.cinnabarSoft.opacity(0.22),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }

    private var courseSummaryHeader: some View {
        let courseTitle = store.courses.first(where: { $0.id == courseID })?.title
            ?? store.ui("选择课程", "Select course")
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(courseTitle)
                .font(courseTitleDisplayFont(courseTitle, size: 15, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.ink)
                .lineLimit(1)
            Text(store.ui(
                "文稿 \(materials.count) · 对话记录 \(sessions.count) · 笔记 \(notes.count)",
                "\(materials.count) materials · \(sessions.count) conversations · \(notes.count) notes"
            ))
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(WeiBeiTheme.secondaryInk)
            Spacer(minLength: 0)
        }
        .frame(height: 44, alignment: .center)
    }

    @ViewBuilder
    private var continueSection: some View {
        let reading = latestReading
        let session = latestSession

        if reading != nil || session != nil || materials.count == 1 {
            VStack(alignment: .leading, spacing: 12) {
                Text(store.ui("继续", "Continue"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)

                VStack(alignment: .leading, spacing: 0) {
                    if let reading {
                        let isAvailable = store.courseMaterialIsAvailable(
                            reading.0.id
                        )
                        CourseHubContinueRow(
                            icon: reading.0.kind.systemImage,
                            title: store.displayTitle(for: reading.0),
                            detail: isAvailable
                                ? "\(courseLocationLabel(reading.1, store: store)) · \(courseRelativeDate(reading.1.lastStudiedAt, language: store.interfaceLanguage))"
                                : store.ui(
                                    "文稿暂不可用 · 原学习位置已保留",
                                    "Material unavailable · Reading position preserved"
                                ),
                            actionTitle: isAvailable
                                ? store.ui("继续阅读", "Continue reading")
                                : store.ui("找回文稿…", "Find Material…")
                        ) {
                            selectedMaterialID = reading.0.id
                            if isAvailable {
                                store.openCourseMaterial(reading.0.id)
                            } else {
                                store.revealCourseFolder(
                                    containing: reading.0.id
                                )
                            }
                        }
                    } else if materials.count == 1, let only = materials.first {
                        let isAvailable = store.courseMaterialIsAvailable(
                            only.id
                        )
                        CourseHubContinueRow(
                            icon: only.kind.systemImage,
                            title: store.displayTitle(for: only),
                            detail: isAvailable
                                ? only.kind.label(language: store.interfaceLanguage)
                                : store.ui(
                                    "文稿暂不可用 · 请放回课程文件夹",
                                    "Material unavailable · Put it back in the course folder"
                                ),
                            actionTitle: isAvailable
                                ? store.ui("打开文稿", "Open material")
                                : store.ui("找回文稿…", "Find Material…")
                        ) {
                            selectedMaterialID = only.id
                            if isAvailable {
                                store.openCourseMaterial(only.id)
                            } else {
                                store.revealCourseFolder(containing: only.id)
                            }
                        }
                    }

                    if reading != nil && session != nil {
                        CourseHairline()
                            .padding(.leading, 44)
                    }

                    if let session {
                        CourseHubContinueRow(
                            icon: "bubble.left.and.text.bubble.right",
                            title: session.title,
                            detail: store.ui(
                                "\(session.messages.count) 条消息 · \(courseRelativeDate(session.updatedAt, language: store.interfaceLanguage))",
                                "\(session.messages.count) messages · \(courseRelativeDate(session.updatedAt, language: store.interfaceLanguage))"
                            ),
                            actionTitle: store.ui("继续对话", "Continue chat")
                        ) {
                            selectedSessionID = session.id
                            store.continueCourseSession(
                                session.id,
                                expectedCourseID: courseID,
                                expectedScopeNeedsReview: false
                            )
                        }
                    }
                }
                .background(WeiBeiTheme.paperRaised.opacity(0.36), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(WeiBeiTheme.cinnabar.opacity(0.14), lineWidth: 1)
                )
            }
        } else if materials.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(store.ui("开始学习", "Get started"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)

                VStack(alignment: .leading, spacing: 10) {
                    Text(store.ui("这门课还没有文稿", "This course has no materials yet"))
                        .font(.system(size: 13.5, weight: .semibold))
                    Text(store.ui(
                        "导入 PDF、HTML 或 Markdown，作为本课骨架。",
                        "Import PDF, HTML, or Markdown to build this course."
                    ))
                    .font(.system(size: 12))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)

                    HStack(spacing: 8) {
                        Button(store.ui("导入文稿", "Import materials"), action: importMaterials)
                            .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    isMaterialDropTargeted
                        ? WeiBeiTheme.cinnabarSoft.opacity(0.42)
                        : WeiBeiTheme.paperRaised.opacity(0.36),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }
        }
    }

    private var materialsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            hubSectionHeader(
                title: store.ui("文稿", "Materials"),
                count: store.ui("\(materials.count) 份", "\(materials.count)")
            )

            if materials.isEmpty {
                Text(store.ui("还没有文稿。可拖入文件，或使用下方导入。", "No materials yet. Drop files here or import below."))
                    .font(.system(size: 12))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(materials) { item in
                        let isAvailable = store.courseMaterialIsAvailable(
                            item.id
                        )
                        CourseHubListRow(
                            icon: item.kind.systemImage,
                            title: store.displayTitle(for: item),
                            detail: isAvailable
                                ? item.kind.label(language: store.interfaceLanguage)
                                : store.ui(
                                    "暂不可用 · 文件已不在课程目录",
                                    "Unavailable · File is no longer in the course folder"
                                ),
                            selected: item.id == selectedMaterialID,
                            prominence: .normal,
                            statusTitle: isAvailable
                                ? nil
                                : store.ui("找回…", "Find…")
                        ) {
                            if !isAvailable {
                                selectedMaterialID = item.id
                                store.revealCourseFolder(containing: item.id)
                            } else if selectedMaterialID == item.id {
                                store.openCourseMaterial(item.id)
                            } else {
                                selectedMaterialID = item.id
                            }
                        }
                        .contextMenu {
                            if isAvailable {
                                Button(store.ui("打开文稿", "Open material")) {
                                    selectedMaterialID = item.id
                                    store.openCourseMaterial(item.id)
                                }
                            } else {
                                Button(store.ui(
                                    "在访达中打开课程文件夹",
                                    "Show Course Folder in Finder"
                                )) {
                                    store.revealCourseFolder(
                                        containing: item.id
                                    )
                                }
                            }
                        }
                        if item.id != materials.last?.id {
                            CourseHairline().padding(.leading, 40)
                        }
                    }
                }
                .background(WeiBeiTheme.paperRaised.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            hubSectionHeader(
                title: store.ui("对话记录", "Conversations"),
                count: store.ui("\(sessions.count) 段", "\(sessions.count)")
            )

            if sessions.isEmpty {
                Text(store.ui("还没有对话。在对话里问本课文稿后，记录会出现在这里。", "No conversations yet. Ask about course materials in chat."))
                    .font(.system(size: 12))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(sessions.prefix(8)) { session in
                        let linked = selectedMaterialID != nil && linkedSessionIDs.contains(session.id)
                        let dimmed = selectedMaterialID != nil && !linkedSessionIDs.contains(session.id)
                        CourseHubListRow(
                            icon: "bubble.left.and.text.bubble.right",
                            title: session.title,
                            detail: store.ui(
                                "\(session.messages.count) 条 · \(courseRelativeDate(session.updatedAt, language: store.interfaceLanguage))",
                                "\(session.messages.count) msgs · \(courseRelativeDate(session.updatedAt, language: store.interfaceLanguage))"
                            ),
                            selected: session.id == selectedSessionID,
                            prominence: linked ? .linked : (dimmed ? .dimmed : .normal)
                        ) {
                            selectedSessionID = session.id
                            store.continueCourseSession(
                                session.id,
                                expectedCourseID: courseID,
                                expectedScopeNeedsReview: false
                            )
                        }
                        if session.id != sessions.prefix(8).last?.id {
                            CourseHairline().padding(.leading, 40)
                        }
                    }
                }
                .background(WeiBeiTheme.paperRaised.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                if sessions.count > 8 {
                    Text(store.ui("更多对话见「学习记录」", "More conversations are under Learning Records"))
                        .font(.system(size: 11))
                        .foregroundStyle(WeiBeiTheme.tertiaryInk)
                }
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            hubSectionHeader(
                title: store.ui("笔记", "Notes"),
                count: store.ui("\(notes.count) 份", "\(notes.count)")
            )

            if notes.isEmpty {
                HStack(spacing: 10) {
                    Text(store.ui("还没有笔记", "No notes yet"))
                        .font(.system(size: 12.5))
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                    Spacer(minLength: 0)
                    Button(store.ui("导入笔记", "Import notes"), action: importNotes)
                        .buttonStyle(WeiBeiTextActionButtonStyle())
                    Button(store.ui("新建笔记", "New note"), action: createNote)
                        .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
                }
                .padding(.horizontal, 12)
                .frame(height: 44, alignment: .center)
                .background(
                    isNoteDropTargeted
                        ? WeiBeiTheme.cinnabarSoft.opacity(0.42)
                        : WeiBeiTheme.paperRaised.opacity(0.22),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .onDrop(of: [.fileURL], isTargeted: $isNoteDropTargeted) { providers in
                    handleDrop(providers, asNotes: true)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(notes) { item in
                        let linked = selectedMaterialID != nil && linkedNoteIDs.contains(item.id)
                        let dimmed = selectedMaterialID != nil && !linkedNoteIDs.contains(item.id)
                        CourseHubListRow(
                            icon: "note.text",
                            title: store.displayTitle(for: item),
                            detail: linked
                                ? store.ui("与当前文稿关联", "Linked to selected material")
                                : store.ui("课程笔记", "Course note"),
                            selected: item.id == selectedNoteID,
                            prominence: linked ? .linked : (dimmed ? .dimmed : .normal)
                        ) {
                            selectedNoteID = item.id
                            store.openCourseNote(item.id)
                        }
                        if item.id != notes.last?.id {
                            CourseHairline().padding(.leading, 40)
                        }
                    }
                }
                .background(WeiBeiTheme.paperRaised.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onDrop(of: [.fileURL], isTargeted: $isNoteDropTargeted) { providers in
                    handleDrop(providers, asNotes: true)
                }

                HStack(spacing: 8) {
                    Button(store.ui("导入笔记", "Import notes"), action: importNotes)
                        .buttonStyle(WeiBeiTextActionButtonStyle())
                    Button(store.ui("新建笔记", "New note"), action: createNote)
                        .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var secondaryActions: some View {
        HStack(spacing: 8) {
            Button(store.ui("导入文稿", "Import materials"), action: importMaterials)
                .buttonStyle(WeiBeiTextActionButtonStyle(active: materials.isEmpty))
            Button(store.ui("管理关系", "Relations"), action: openRelations)
                .buttonStyle(WeiBeiTextActionButtonStyle())
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    private func hubSectionHeader(title: String, count: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(WeiBeiTypography.brandFont(language: store.interfaceLanguage, size: 14, weight: .semibold))
            Text(count)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(WeiBeiTheme.secondaryInk)
            Spacer(minLength: 0)
        }
        .frame(height: 44, alignment: .center)
    }

    // MARK: - Helpers

    private func ensureMaterialSelection() {
        if selectedMaterialID == nil {
            selectedMaterialID = materials.first?.id
        }
    }

    private func filteredItems(_ items: [StudyItem]) -> [StudyItem] {
        let cleaned = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return items }
        return items.filter {
            store.displayTitle(for: $0).localizedCaseInsensitiveContains(cleaned)
                || $0.subtitle.localizedCaseInsensitiveContains(cleaned)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider], asNotes: Bool) -> Bool {
        var urls: [URL] = []
        let urlsLock = NSLock()
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urlsLock.lock()
                    urls.append(url)
                    urlsLock.unlock()
                } else if let url = item as? URL {
                    urlsLock.lock()
                    urls.append(url)
                    urlsLock.unlock()
                }
            }
        }
        group.notify(queue: .main) {
            guard !urls.isEmpty else { return }
            store.importCourseFilesFromURLs(urls, asNotes: asNotes) { imported in
                if asNotes {
                    if selectedNoteID == nil {
                        selectedNoteID = imported.first(where: \.isNotebookNote)?.id
                    }
                } else if selectedMaterialID == nil {
                    selectedMaterialID = imported.first(where: { !$0.isNotebookNote })?.id
                }
            }
        }
        return true
    }
}

// MARK: - Rows

private struct CourseHubContinueRow: View {
    let icon: String
    let title: String
    let detail: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.88))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.ink)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            Button(actionTitle, action: action)
                .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct CourseHubListRow: View {
    let icon: String
    let title: String
    let detail: String
    let selected: Bool
    var prominence: CourseHubRowProminence = .normal
    var statusTitle: String? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: selected || prominence == .linked ? .semibold : .medium))
                        .foregroundStyle(WeiBeiTheme.ink.opacity(prominence == .dimmed ? 0.55 : 1))
                        .lineLimit(1)
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(WeiBeiTheme.secondaryInk.opacity(prominence == .dimmed ? 0.7 : 1))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if let statusTitle {
                    Text(statusTitle)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(WeiBeiTheme.cinnabar)
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
            .background(rowBackground)
            .overlay(alignment: .leading) {
                if selected || prominence == .linked {
                    Capsule()
                        .fill(prominence == .linked && !selected
                              ? WeiBeiTheme.cinnabar.opacity(0.55)
                              : WeiBeiTheme.secondaryInk.opacity(0.42))
                        .frame(width: 2, height: 22)
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
