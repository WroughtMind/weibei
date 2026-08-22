import Foundation
import SwiftUI
import UniformTypeIdentifiers
import WeiBeiCore

/// A quiet course landing page: resume reading first, then browse recent course content.
struct CourseHubView: View {
    @EnvironmentObject private var store: WorkspaceStore
    let search: String
    @Binding var selectedMaterialID: String?
    @Binding var selectedNoteID: String?
    @Binding var selectedSessionID: UUID?
    let isCompact: Bool
    let openRelations: () -> Void
    let openRecords: () -> Void
    let importMaterials: () -> Void
    let importNotes: () -> Void
    let createNote: () -> Void

    @State private var showsAllContent = false
    @State private var searchResults: [GlobalSearchHit] = []
    @State private var isSearching = false
    @State private var searchAvailability: CourseDocumentIndexAvailability = .ready
    @State private var searchRetryToken = 0
    @State private var isMaterialDropTargeted = false
    @State private var isNoteDropTargeted = false
    @State private var courseEntryPresentation: CourseProjectEntryPresentation?

    private var courseID: UUID? { store.courseWorkspaceCourseID }

    private var materials: [StudyItem] {
        guard let courseID else { return [] }
        return store.courseMaterials(in: courseID)
    }

    private var notes: [StudyItem] {
        guard let courseID else { return [] }
        return store.courseNotes(in: courseID)
    }

    private var sessions: [StudySession] {
        guard let courseID else { return [] }
        return store.sessionsTouchingCourse(courseID)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var learningHighlights: CourseHomeLearningHighlights? {
        guard let courseID else { return nil }
        return CourseHomeLearningHighlights(
            courseID: courseID,
            learningMemoryEntries: store.orderedLearningMemoryEntries(
                in: .course(courseID)
            ),
            studySessions: sessions
        )
    }

    private var cleanedSearch: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchTaskID: CourseHomeSearchTaskID {
        CourseHomeSearchTaskID(
            courseID: courseID,
            query: cleanedSearch,
            retryToken: searchRetryToken
        )
    }

    private var continueReading: (item: StudyItem, location: StudyLocation?)? {
        guard let courseID else { return nil }
        if let location = store.courseResumePoint(for: courseID)?.materialLocation,
           let item = materials.first(where: { $0.id == location.itemID }) {
            return (item, location)
        }
        guard let item = materials.max(by: {
            contentDate(for: $0, courseID: courseID)
                < contentDate(for: $1, courseID: courseID)
        }) else {
            return nil
        }
        return (item, nil)
    }

    private var continueConversation: StudySession? {
        guard let courseID,
              let chatID = store.courseResumePoint(for: courseID)?.chatID else {
            return nil
        }
        return sessions.first { session in
            session.id == chatID
                && session.relatedCourseIDs.contains(courseID)
                && !session.messages.isEmpty
        }
    }

    private var recentEntries: [CourseHomeEntry] {
        guard let courseID else { return [] }

        let materialEntries = materials.map { item in
            let date = contentDate(for: item, courseID: courseID)
            return CourseHomeEntry(
                id: "material:\(item.id)",
                kind: .material(item),
                title: store.displayTitle(for: item),
                detail: contentDetail(
                    label: item.kind.label(language: store.interfaceLanguage),
                    date: date
                ),
                date: date
            )
        }

        let noteEntries = notes.map { item in
            let date = contentDate(for: item, courseID: courseID)
            return CourseHomeEntry(
                id: "note:\(item.id)",
                kind: .note(item),
                title: store.displayTitle(for: item),
                detail: contentDetail(
                    label: store.ui("课程笔记", "Course note"),
                    date: date
                ),
                date: date
            )
        }

        let chatEntries = sessions.map { session in
            CourseHomeEntry(
                id: "chat:\(session.id.uuidString)",
                kind: .chat(session),
                title: session.title,
                detail: store.ui(
                    "\(session.messages.count) 条消息 · \(courseRelativeDate(session.updatedAt, language: store.interfaceLanguage))",
                    "\(session.messages.count) messages · \(courseRelativeDate(session.updatedAt, language: store.interfaceLanguage))"
                ),
                date: session.updatedAt
            )
        }

        return (materialEntries + noteEntries + chatEntries)
            .sorted {
                if $0.date == $1.date { return $0.id < $1.id }
                return $0.date > $1.date
            }
    }

    private var visibleRecentEntries: ArraySlice<CourseHomeEntry> {
        recentEntries.prefix(showsAllContent ? recentEntries.count : 3)
    }

    var body: some View {
        Group {
            if courseID == nil {
                coursePickerEmptyState
            } else {
                courseHome
            }
        }
        .task(id: searchTaskID) {
            await refreshSearch(for: searchTaskID)
        }
        .onAppear(perform: ensureMaterialSelection)
        .onAppear {
            guard WeiBeiPerf.isEnabled else { return }
            DispatchQueue.main.async {
                store.finishCourseHomePerformanceNavigation()
            }
        }
        .onChange(of: courseID) { _, _ in
            showsAllContent = false
            selectedMaterialID = materials.first?.id
            selectedNoteID = nil
            selectedSessionID = nil
        }
        .onChange(of: materials.map(\.id)) { _, ids in
            if selectedMaterialID == nil
                || selectedMaterialID.map({ !ids.contains($0) }) == true {
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
                        .weiBeiBrandFont(language: store.interfaceLanguage, size: 22, weight: .semibold)
                    Text(store.ui(
                        "进入课程后，可以继续阅读并打开这门课里的文稿、笔记与对话。",
                        "Open a course to resume reading and browse its materials, notes, and chats."
                    ))
                    .weiBeiText(12.5)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                }

                if store.courses.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(store.ui("还没有课程", "No courses yet"))
                            .weiBeiText(14, weight: .semibold)
                        Text(store.ui(
                            "每门课程都有自己的本地项目文件夹，可以容纳多份文稿与笔记。",
                            "Each course has a local project folder for multiple materials and notes."
                        ))
                        .weiBeiText(12)
                        .foregroundStyle(WeiBeiTheme.secondaryInk)

                        courseCreationActions
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        WeiBeiTheme.paperRaised.opacity(0.34),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                } else {
                    VStack(spacing: 0) {
                        ForEach(store.courses) { course in
                            Button {
                                store.openCourseSpace(course.id)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "book.closed")
                                        .weiBeiText(14, weight: .medium)
                                        .foregroundStyle(
                                            courseWorkspaceAccent(colorIndex: course.colorIndex)
                                        )
                                        .frame(width: 22)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(course.title)
                                            .font(courseTitleDisplayFont(
                                                course.title,
                                                size: 14,
                                                weight: .semibold
                                            ))
                                            .foregroundStyle(WeiBeiTheme.ink)
                                            .lineLimit(1)
                                        Text(courseContentCount(for: course.id))
                                            .weiBeiText(11)
                                            .foregroundStyle(WeiBeiTheme.secondaryInk)
                                    }

                                    Spacer(minLength: 8)

                                    Image(systemName: "chevron.right")
                                        .weiBeiText(10, weight: .semibold)
                                        .foregroundStyle(WeiBeiTheme.tertiaryInk)
                                }
                                .padding(.horizontal, 14)
                                .frame(height: 56)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if course.id != store.courses.last?.id {
                                CourseHairline().padding(.leading, 48)
                            }
                        }
                    }
                    .background(
                        WeiBeiTheme.paperRaised.opacity(0.28),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(WeiBeiTheme.hairline.opacity(0.55), lineWidth: 1)
                    }

                    courseCreationActions
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

    private var courseCreationActions: some View {
        HStack(spacing: 10) {
            Button(store.ui("新建课程", "Create course")) {
                courseEntryPresentation = CourseProjectEntryPresentation(intent: .create)
            }
            .buttonStyle(WeiBeiTextActionButtonStyle(active: store.courses.isEmpty))
        }
    }

    // MARK: - Course home

    private var courseHome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: isCompact ? 28 : 34) {
                if let courseID,
                   let reason = store.courseRootUnavailableReason(for: courseID) {
                    unavailableCourseRootBanner(reason: reason)
                }

                continueReadingSection
                courseContentSection
            }
            .frame(maxWidth: isCompact ? .infinity : 1_000, alignment: .leading)
            .padding(.horizontal, isCompact ? 24 : 44)
            .padding(.top, isCompact ? 28 : 42)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WeiBeiTheme.paper)
        .onDrop(of: [.fileURL], isTargeted: $isMaterialDropTargeted) { providers in
            handleDrop(providers, asNotes: false)
        }
    }

    @ViewBuilder
    private var continueReadingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(store.ui("继续上次", "Continue where you left off"))
                .weiBeiBrandFont(language: store.interfaceLanguage, size: 21, weight: .semibold)
                .foregroundStyle(WeiBeiTheme.ink)

            if let courseID, let reading = continueReading {
                let available = store.courseMaterialIsAvailable(reading.item.id)
                CourseHubContinueCard(
                    icon: reading.item.kind.systemImage,
                    title: store.displayTitle(for: reading.item),
                    detail: continueReadingDetail(
                        item: reading.item,
                        location: reading.location,
                        available: available
                    ),
                    actionTitle: available
                        ? (reading.location == nil
                            ? store.ui("打开文稿", "Open material")
                            : store.ui("继续阅读", "Continue reading"))
                        : store.ui("找回文稿…", "Find material…"),
                    secondaryActionTitle: continueConversation.map { _ in
                        store.ui("继续对话", "Continue Chat")
                    },
                    secondaryAction: continueConversation.map { _ in
                        {
                            _ = store.resumeCourseConversation(courseID)
                        }
                    }
                ) {
                    selectedMaterialID = reading.item.id
                    if available {
                        if reading.location == nil
                            || !store.resumeCourseReading(courseID) {
                            _ = store.openCourseMaterial(reading.item.id, in: courseID)
                        }
                    } else {
                        store.revealCourseFolder(
                            containing: reading.item.id,
                            in: courseID
                        )
                    }
                }
            } else if let courseID, let conversation = continueConversation {
                CourseHubContinueCard(
                    icon: "bubble.left.and.text.bubble.right",
                    title: conversation.title,
                    detail: store.ui(
                        "\(conversation.messages.count) 条消息 · \(courseRelativeDate(conversation.updatedAt, language: store.interfaceLanguage))",
                        "\(conversation.messages.count) messages · \(courseRelativeDate(conversation.updatedAt, language: store.interfaceLanguage))"
                    ),
                    actionTitle: store.ui("继续对话", "Continue Chat")
                ) {
                    _ = store.resumeCourseConversation(courseID)
                }
            } else {
                CourseHubStartReadingRow(
                    isDropTargeted: isMaterialDropTargeted,
                    importMaterials: importMaterials,
                    title: store.ui(
                        "还没有可继续阅读的文稿",
                        "No material to continue yet"
                    ),
                    detail: store.ui(
                        "把 PDF、HTML、Markdown 或文本加入这门课。",
                        "Add PDF, HTML, Markdown, or text to this course."
                    ),
                    actionTitle: store.ui("导入文稿", "Import materials")
                )
            }
        }
    }

    private var courseContentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(cleanedSearch.isEmpty
                     ? store.ui("最近内容", "Recent content")
                     : store.ui("搜索结果", "Search results"))
                    .weiBeiBrandFont(language: store.interfaceLanguage, size: 18, weight: .semibold)
                    .foregroundStyle(WeiBeiTheme.ink)

                if !cleanedSearch.isEmpty, !isSearching {
                    Text(store.ui(
                        "\(searchResults.count) 项",
                        "\(searchResults.count) results"
                    ))
                    .weiBeiText(11)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                }

                Spacer(minLength: 0)
            }
            .padding(.bottom, 12)

            CourseHairline()

            if cleanedSearch.isEmpty {
                recentContent
            } else {
                searchContent
            }

            if cleanedSearch.isEmpty {
                CourseHairline()
                courseLearningOverview
            }

            CourseHairline()

            courseContentFooter
        }
    }

    private var courseLearningOverview: some View {
        let summary = learningHighlights?.summary
        let nextStepText = learningHighlights?.nextStepText
        let nextStepSessionID = learningHighlights?.nextStepSessionID
        let nextStepAction: (() -> Void)? = {
            guard let courseID, let nextStepSessionID else { return nil }
            return {
                selectedSessionID = nextStepSessionID
                store.continueCourseSession(
                    nextStepSessionID,
                    expectedCourseID: courseID,
                    expectedScopeNeedsReview: false
                )
            }
        }()

        return VStack(spacing: 0) {
            CourseHubMemoryLine(
                icon: "bookmark",
                title: store.ui("学习小结", "Learning summary"),
                text: summary?.text ?? store.ui(
                    "产生实质学习变化后生成",
                    "Generated after meaningful learning progress"
                ),
                isPlaceholder: summary == nil,
                accessibilityIdentifier: "course-home-learning-summary",
                action: summary == nil ? nil : openRecords
            )

            CourseHairline().padding(.leading, 42)

            CourseHubMemoryLine(
                icon: "flag",
                title: store.ui("下一步", "Next step"),
                text: nextStepText ?? store.ui(
                    "尚无学习建议",
                    "No learning suggestion yet"
                ),
                isPlaceholder: nextStepText == nil,
                accessibilityIdentifier: "course-home-next-step",
                action: nextStepAction
            )
        }
    }

    @ViewBuilder
    private var recentContent: some View {
        if recentEntries.isEmpty {
            courseContentEmptyState
        } else {
            VStack(spacing: 0) {
                ForEach(visibleRecentEntries) { entry in
                    CourseHubContentRow(
                        icon: entry.kind.icon,
                        title: entry.title,
                        detail: entry.detail,
                        selected: entry.isSelected(
                            materialID: selectedMaterialID,
                            noteID: selectedNoteID,
                            sessionID: selectedSessionID
                        ),
                        action: { open(entry) }
                    )

                    if entry.id != visibleRecentEntries.last?.id {
                        CourseHairline().padding(.leading, 42)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        if isSearching {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(store.ui("正在搜索课程内容…", "Searching course content…"))
                    .weiBeiText(12)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
            }
            .frame(minHeight: 62)
        } else {
            VStack(spacing: 0) {
                if searchAvailability != .ready {
                    HStack(spacing: 10) {
                        Text(searchAvailability == .indexing
                             ? store.ui(
                                "课程资料仍在建立搜索索引，结果可能尚未完整。",
                                "Course materials are still being indexed, so results may be incomplete."
                             )
                             : store.ui(
                                "部分课程资料无法读取或建立搜索索引，请检查课程文件夹后重试。",
                                "Some course materials could not be read or indexed. Check the course folder and retry."
                             ))
                            .weiBeiText(12.5)
                            .foregroundStyle(WeiBeiTheme.secondaryInk)

                        Spacer(minLength: 8)

                        Button(store.ui("重试", "Retry")) {
                            searchRetryToken += 1
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle())
                    }
                    .frame(minHeight: 62)

                    if !searchResults.isEmpty {
                        CourseHairline()
                    }
                } else if searchResults.isEmpty {
                    Text(store.ui(
                        "没有找到与“\(cleanedSearch)”相关的内容，已搜索全部课程。",
                        "Nothing matched “\(cleanedSearch)” — all courses were searched."
                    ))
                    .weiBeiText(12.5)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                }

                ForEach(searchResults) { hit in
                    CourseHubContentRow(
                        icon: searchResultIcon(hit.result),
                        title: hit.result.title,
                        detail: hit.result.detail,
                        snippet: hit.result.matchedText,
                        courseBadge: hit.isCurrentCourse ? nil : hit.courseTitle,
                        selected: searchResultIsSelected(hit.result),
                        action: { open(hit) }
                    )

                    if hit.id != searchResults.last?.id {
                        CourseHairline().padding(.leading, 42)
                    }
                }
            }
        }
    }

    private var courseContentEmptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(store.ui(
                "这门课还没有文稿、笔记或对话。",
                "This course has no materials, notes, or chats yet."
            ))
            .weiBeiText(12.5)
            .foregroundStyle(WeiBeiTheme.secondaryInk)

            importAndCreateActions
        }
        .padding(.vertical, 18)
    }

    @ViewBuilder
    private var courseContentFooter: some View {
        if cleanedSearch.isEmpty, recentEntries.count > 3 {
            Button {
                withAnimation(WeiBeiMotion.panel) {
                    showsAllContent.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Text(showsAllContent
                         ? store.ui("收起全部内容", "Show less")
                         : store.ui(
                            "查看全部文稿、笔记与对话记录",
                            "View all materials, notes, and chats"
                         ))
                    Image(systemName: showsAllContent ? "chevron.up" : "chevron.down")
                        .weiBeiText(9, weight: .semibold)
                }
                .weiBeiText(12.5, weight: .medium)
                .foregroundStyle(WeiBeiTheme.cinnabar)
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else if cleanedSearch.isEmpty {
            importAndCreateActions
                .padding(.top, 14)
        }
    }

    private var importAndCreateActions: some View {
        HStack(spacing: 10) {
            Button(store.ui("导入文稿", "Import materials"), action: importMaterials)
                .buttonStyle(WeiBeiTextActionButtonStyle(active: materials.isEmpty))

            Button(store.ui("导入笔记", "Import notes"), action: importNotes)
                .buttonStyle(WeiBeiTextActionButtonStyle())
                .onDrop(of: [.fileURL], isTargeted: $isNoteDropTargeted) { providers in
                    handleDrop(providers, asNotes: true)
                }

            Button(store.ui("新建笔记", "New note"), action: createNote)
                .buttonStyle(WeiBeiTextActionButtonStyle())

            Spacer(minLength: 0)
        }
    }

    private func unavailableCourseRootBanner(reason: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "folder.badge.questionmark")
                .weiBeiText(15, weight: .medium)
                .foregroundStyle(WeiBeiTheme.cinnabar)

            VStack(alignment: .leading, spacing: 3) {
                Text(store.ui(
                    "课程文件夹暂时不可用",
                    "Course folder unavailable"
                ))
                .weiBeiText(12.5, weight: .semibold)
                Text(reason)
                    .weiBeiText(11)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button(store.ui("重新选择资料库…", "Re-select Library…")) {
                courseEntryPresentation = CourseProjectEntryPresentation(intent: .create)
            }
            .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
        }
        .padding(14)
        .background(
            WeiBeiTheme.cinnabarSoft.opacity(0.22),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }

    // MARK: - Actions and async search

    private func refreshSearch(for request: CourseHomeSearchTaskID) async {
        searchResults = []
        isSearching = false
        searchAvailability = .ready
        guard let courseID = request.courseID, !request.query.isEmpty else {
            return
        }

        let span = WeiBeiPerf.begin("course.search_to_next_main_queue_proxy")
        isSearching = true
        let outcome = await store.searchAllCourses(
            currentCourseID: courseID,
            query: request.query
        )
        guard !Task.isCancelled,
              request == searchTaskID,
              store.courseWorkspaceCourseID == courseID else {
            WeiBeiPerf.end(span, extra: "outcome=superseded scope=global")
            return
        }
        searchResults = outcome.hits
        searchAvailability = outcome.availability
        isSearching = false
        guard let span else { return }
        await withCheckedContinuation {
            (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async {
                WeiBeiPerf.end(
                    span,
                    extra:
                        "outcome=completed endpoint=next_main_queue_proxy input=manual_ui scope=global results=\(outcome.hits.count)"
                )
                continuation.resume()
            }
        }
    }

    private func open(_ entry: CourseHomeEntry) {
        guard let courseID else { return }
        switch entry.kind {
        case .material(let item):
            selectedMaterialID = item.id
            _ = store.openCourseMaterial(item.id, in: courseID)
        case .note(let item):
            selectedNoteID = item.id
            store.openCourseNote(item.id, in: courseID)
        case .chat(let session):
            selectedSessionID = session.id
            store.continueCourseSession(
                session.id,
                expectedCourseID: courseID,
                expectedScopeNeedsReview: false
            )
        }
    }

    private func open(_ hit: GlobalSearchHit) {
        switch hit.result.kind {
        case .material:
            guard let itemID = hit.result.itemID, let courseID = hit.courseID else { return }
            selectedMaterialID = itemID
            _ = store.openCourseMaterial(itemID, in: courseID)
        case .note:
            guard let itemID = hit.result.itemID, let courseID = hit.courseID else { return }
            selectedNoteID = itemID
            store.openCourseNote(itemID, in: courseID)
        case .chat:
            guard let sessionID = hit.result.sessionID else { return }
            selectedSessionID = sessionID
            store.continueCourseSession(
                sessionID,
                expectedCourseID: hit.courseID,
                expectedScopeNeedsReview: false
            )
        }
    }

    private func handleDrop(_ providers: [NSItemProvider], asNotes: Bool) -> Bool {
        guard let courseID else { return false }
        var urls: [URL] = []
        let urlsLock = NSLock()
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            provider.loadItem(
                forTypeIdentifier: UTType.fileURL.identifier,
                options: nil
            ) { item, _ in
                defer { group.leave() }
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = item as? URL
                }
                guard let url else { return }
                urlsLock.lock()
                urls.append(url)
                urlsLock.unlock()
            }
        }

        group.notify(queue: .main) {
            guard !urls.isEmpty,
                  store.courseWorkspaceCourseID == courseID else {
                return
            }
            store.importCourseFilesFromURLs(
                urls,
                asNotes: asNotes,
                courseID: courseID
            ) { imported in
                if asNotes {
                    selectedNoteID = selectedNoteID
                        ?? imported.first(where: \.isNotebookNote)?.id
                } else {
                    selectedMaterialID = selectedMaterialID
                        ?? imported.first(where: \.isCourseMaterial)?.id
                }
            }
        }
        return true
    }

    // MARK: - Display helpers

    private func ensureMaterialSelection() {
        if selectedMaterialID == nil {
            selectedMaterialID = materials.first?.id
        }
    }

    private func courseContentCount(for courseID: UUID) -> String {
        let materialCount = store.courseMaterials(in: courseID).count
        let noteCount = store.courseNotes(in: courseID).count
        let sessionCount = store.sessionsTouchingCourse(courseID).count
        return store.ui(
            "文稿 \(materialCount) · 笔记 \(noteCount) · 对话 \(sessionCount)",
            "\(materialCount) materials · \(noteCount) notes · \(sessionCount) chats"
        )
    }

    private func continueReadingDetail(
        item: StudyItem,
        location: StudyLocation?,
        available: Bool
    ) -> String {
        guard available else {
            return store.ui(
                "文稿暂不可用 · 原阅读位置仍已保留",
                "Material unavailable · Your reading position is preserved"
            )
        }
        guard let location else {
            return item.kind.label(language: store.interfaceLanguage)
        }
        return "\(courseLocationLabel(location, store: store)) · \(courseRelativeDate(location.lastStudiedAt, language: store.interfaceLanguage))"
    }

    private func contentDate(for item: StudyItem, courseID: UUID) -> Date {
        if let location = store.studyLocation(for: item.id, in: courseID) {
            return location.lastStudiedAt
        }
        if let point = store.courseResumePoint(for: courseID) {
            if point.noteItemID == item.id {
                return point.savedAt
            }
        }
        guard let nanoseconds = item.fileModificationTimeNanoseconds,
              nanoseconds > 0 else {
            return .distantPast
        }
        return Date(timeIntervalSince1970: Double(nanoseconds) / 1_000_000_000)
    }

    private func contentDetail(label: String, date: Date) -> String {
        guard date != .distantPast else { return label }
        return "\(label) · \(courseRelativeDate(date, language: store.interfaceLanguage))"
    }

    private func searchResultIcon(_ result: CourseHomeSearchResult) -> String {
        switch result.kind {
        case .material:
            guard let itemID = result.itemID,
                  let item = materials.first(where: { $0.id == itemID }) else {
                return "doc.text"
            }
            return item.kind.systemImage
        case .note:
            return "note.text"
        case .chat:
            return "bubble.left.and.text.bubble.right"
        }
    }

    private func searchResultIsSelected(_ result: CourseHomeSearchResult) -> Bool {
        switch result.kind {
        case .material:
            return result.itemID == selectedMaterialID
        case .note:
            return result.itemID == selectedNoteID
        case .chat:
            return result.sessionID == selectedSessionID
        }
    }
}

private struct CourseHomeSearchTaskID: Equatable {
    let courseID: UUID?
    let query: String
    let retryToken: Int
}

private struct CourseHomeEntry: Identifiable {
    enum Kind {
        case material(StudyItem)
        case note(StudyItem)
        case chat(StudySession)

        var icon: String {
            switch self {
            case .material(let item):
                return item.kind.systemImage
            case .note:
                return "note.text"
            case .chat:
                return "bubble.left.and.text.bubble.right"
            }
        }
    }

    let id: String
    let kind: Kind
    let title: String
    let detail: String
    let date: Date

    func isSelected(
        materialID: String?,
        noteID: String?,
        sessionID: UUID?
    ) -> Bool {
        switch kind {
        case .material(let item):
            return item.id == materialID
        case .note(let item):
            return item.id == noteID
        case .chat(let session):
            return session.id == sessionID
        }
    }
}

private struct CourseHubContinueCard: View {
    let icon: String
    let title: String
    let detail: String
    let actionTitle: String
    var secondaryActionTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil
    let action: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: icon)
                .weiBeiText(24, weight: .regular)
                .foregroundStyle(WeiBeiTheme.cinnabar)
                .frame(width: 46)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .weiBeiText(17, weight: .semibold)
                    .foregroundStyle(WeiBeiTheme.ink)
                    .lineLimit(1)
                Text(detail)
                    .weiBeiText(11.5)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .lineLimit(2)
            }

            Spacer(minLength: 18)

            HStack(spacing: 10) {
                Button(actionTitle, action: action)
                    .buttonStyle(CourseHubContinueActionButtonStyle(primary: true))
                    .fixedSize()

                if let secondaryActionTitle, let secondaryAction {
                    Button(secondaryActionTitle, action: secondaryAction)
                        .buttonStyle(CourseHubContinueActionButtonStyle(primary: false))
                        .fixedSize()
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .background(
            WeiBeiTheme.paperRaised.opacity(0.36),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(WeiBeiTheme.cinnabar.opacity(0.12), lineWidth: 1)
        }
    }
}

private struct CourseHubContinueActionButtonStyle: ButtonStyle {
    let primary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .weiBeiText(13, weight: .semibold)
            .foregroundStyle(primary ? WeiBeiTheme.onCinnabar : WeiBeiTheme.cinnabar)
            .padding(.horizontal, 20)
            .frame(minWidth: 132, minHeight: 42)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        primary
                            ? WeiBeiTheme.cinnabar.opacity(
                                configuration.isPressed ? 0.82 : 0.94
                            )
                            : WeiBeiTheme.paperRaised.opacity(
                                configuration.isPressed ? 0.74 : 0.42
                            )
                    )
            )
            .overlay {
                if !primary {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(WeiBeiTheme.cinnabar.opacity(0.72), lineWidth: 1)
                }
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(WeiBeiMotion.press, value: configuration.isPressed)
    }
}

private struct CourseHubStartReadingRow: View {
    let isDropTargeted: Bool
    let importMaterials: () -> Void
    let title: String
    let detail: String
    let actionTitle: String

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: "doc.badge.plus")
                .weiBeiText(22, weight: .regular)
                .foregroundStyle(WeiBeiTheme.cinnabar)
                .frame(width: 46)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .weiBeiText(15, weight: .semibold)
                    .foregroundStyle(WeiBeiTheme.ink)
                Text(detail)
                    .weiBeiText(11.5)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
            }

            Spacer(minLength: 18)

            Button(actionTitle, action: importMaterials)
                .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .background(
            isDropTargeted
                ? WeiBeiTheme.cinnabarSoft.opacity(0.42)
                : WeiBeiTheme.paperRaised.opacity(0.32),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }
}

private struct CourseHubContentRow: View {
    let icon: String
    let title: String
    let detail: String
    var snippet: String? = nil
    var courseBadge: String? = nil
    let selected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .weiBeiText(14, weight: .medium)
                    .foregroundStyle(selected
                                     ? WeiBeiTheme.cinnabar
                                     : WeiBeiTheme.secondaryInk)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .weiBeiText(13.5, weight: selected ? .semibold : .medium)
                        .foregroundStyle(WeiBeiTheme.ink)
                        .lineLimit(1)

                    Text(detail)
                        .weiBeiText(10.5)
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                        .lineLimit(1)

                    if let snippet,
                       !snippet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(snippet)
                            .weiBeiText(11)
                            .foregroundStyle(WeiBeiTheme.tertiaryInk)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 10)

                if let courseBadge {
                    Text(courseBadge)
                        .weiBeiText(10)
                        .foregroundStyle(WeiBeiTheme.tertiaryInk)
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            WeiBeiTheme.paperInset.opacity(0.4),
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                        )
                }

                Image(systemName: "chevron.right")
                    .weiBeiText(9.5, weight: .semibold)
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, snippet == nil ? 12 : 10)
            .frame(minHeight: snippet == nil ? 58 : 72)
            .contentShape(Rectangle())
            .background(
                selected
                    ? WeiBeiTheme.paperInset.opacity(0.34)
                    : (hovering ? WeiBeiTheme.paperInset.opacity(0.16) : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(WeiBeiMotion.hover, value: hovering)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct CourseHubMemoryLine: View {
    let icon: String
    let title: String
    let text: String
    let isPlaceholder: Bool
    let accessibilityIdentifier: String
    let action: (() -> Void)?

    @State private var hovering = false

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    content
                }
                .buttonStyle(.plain)
                .onHover { hovering = $0 }
                .animation(WeiBeiMotion.hover, value: hovering)
            } else {
                content
            }
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var content: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .weiBeiText(15, weight: .regular)
                .foregroundStyle(WeiBeiTheme.cinnabar)
                .frame(width: 24)

            Text(title)
                .weiBeiText(13.5, weight: .semibold)
                .foregroundStyle(WeiBeiTheme.ink)
                .frame(width: 104, alignment: .leading)

            Text(text)
                .weiBeiText(11.5)
                .foregroundStyle(
                    isPlaceholder
                        ? WeiBeiTheme.tertiaryInk
                        : WeiBeiTheme.secondaryInk
                )
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if action != nil {
                Image(systemName: "chevron.right")
                    .weiBeiText(9.5, weight: .semibold)
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 62)
        .contentShape(Rectangle())
        .background(hovering ? WeiBeiTheme.paperInset.opacity(0.16) : .clear)
        .accessibilityElement(children: .combine)
    }
}
