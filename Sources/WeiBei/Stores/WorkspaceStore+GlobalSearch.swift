import Foundation
import WeiBeiCore

// MARK: - 课程首页搜索 + 跨课程全局搜索
//
// searchCourseHome 的实现自 WorkspaceStore.swift 原样迁来(共享内核),
// 并以同一套匹配/评分逻辑扩展出全局搜索:一次 FTS 查询覆盖所有课程,
// 当前课程命中排在最前,跨课程命中带来源课程标注。

/// 全局搜索命中:原始结果 + 来源课程。courseID 为 nil 表示未关联课程的全局对话。
struct GlobalSearchHit: Identifiable, Sendable {
    let courseID: UUID?
    let courseTitle: String
    let isCurrentCourse: Bool
    let result: CourseHomeSearchResult

    var id: String { "\(courseID?.uuidString ?? "none")/\(result.id)" }
}

struct GlobalSearchOutcome: Sendable {
    let hits: [GlobalSearchHit]
    let availability: CourseDocumentIndexAvailability
}

extension WorkspaceStore {

    /// 课程内搜索——行为与迁移前完全一致。
    func searchCourseHome(
        courseID: UUID,
        query rawQuery: String,
        resultLimit: Int = 50
    ) async -> CourseHomeSearchOutcome {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty,
              courses.contains(where: { $0.id == courseID }) else {
            return CourseHomeSearchOutcome(results: [], availability: .ready)
        }
        let itemInputs = courseItems(in: courseID).map { item in
            CourseSearchItemInput(
                item: item,
                title: displayTitle(for: item),
                detail: displaySubtitle(for: item),
                memoryText: item.isNotebookNote
                    ? (item.id == activeNotebookItemID
                        ? noteText
                        : notesByItemID[item.id] ?? loadedCourseNoteTextByItemID[item.id])
                    : nil
            )
        }
        ensureStudySessionMessagesLoaded(touchingCourse: courseID)
        let sessions = sessionsTouchingCourse(courseID)
        let search = await runCourseSearchKernel(
            itemInputs: itemInputs,
            sessions: sessions,
            query: query,
            chatDetail: ui("%d 条消息", "%d messages"),
            resultLimit: resultLimit
        )
        guard !Task.isCancelled else {
            return CourseHomeSearchOutcome(results: [], availability: .ready)
        }
        lastCourseHomeSearchRanOnMainThread = search.ranOnMainThread
        return CourseHomeSearchOutcome(
            results: search.results,
            availability: search.availability
        )
    }

    /// 跨课程全局搜索:所有课程的资料/笔记/对话一次查完;
    /// 当前课程命中排在最前,其余按内核排序跟随,默认返回 100 条。
    func searchAllCourses(
        currentCourseID: UUID?,
        query rawQuery: String,
        resultLimit: Int = 100
    ) async -> GlobalSearchOutcome {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return GlobalSearchOutcome(hits: [], availability: .ready)
        }
        ensureAllStudySessionMessagesLoaded()
        let courseTitleByID = Dictionary(
            uniqueKeysWithValues: courses.map { ($0.id, $0.title) }
        )
        var courseIDByItemID: [String: UUID] = [:]
        var itemInputs: [CourseSearchItemInput] = []
        for course in courses {
            for item in courseItems(in: course.id) {
                courseIDByItemID[item.id] = course.id
                itemInputs.append(
                    CourseSearchItemInput(
                        item: item,
                        title: displayTitle(for: item),
                        detail: displaySubtitle(for: item),
                        memoryText: item.isNotebookNote
                            ? (item.id == activeNotebookItemID
                                ? noteText
                                : notesByItemID[item.id] ?? loadedCourseNoteTextByItemID[item.id])
                            : nil
                    )
                )
            }
        }
        let sessionByID = Dictionary(
            uniqueKeysWithValues: orderedStudySessions.map { ($0.id, $0) }
        )
        let sessions = orderedStudySessions.filter(\.hasChatHistory)
        let search = await runCourseSearchKernel(
            itemInputs: itemInputs,
            sessions: sessions,
            query: query,
            chatDetail: ui("%d 条消息", "%d messages"),
            resultLimit: resultLimit
        )
        guard !Task.isCancelled else {
            return GlobalSearchOutcome(hits: [], availability: .ready)
        }
        lastCourseHomeSearchRanOnMainThread = search.ranOnMainThread
        let unaffiliatedLabel = ui("未关联课程", "No course")
        let hits = search.results.enumerated().compactMap { pair -> (index: Int, hit: GlobalSearchHit)? in
            let result = pair.element
            switch result.kind {
            case .material, .note:
                guard let itemID = result.itemID,
                      let courseID = courseIDByItemID[itemID] else { return nil }
                return (pair.offset, GlobalSearchHit(
                    courseID: courseID,
                    courseTitle: courseTitleByID[courseID] ?? unaffiliatedLabel,
                    isCurrentCourse: courseID == currentCourseID,
                    result: result
                ))
            case .chat:
                guard let sessionID = result.sessionID,
                      let session = sessionByID[sessionID] else { return nil }
                let courseID = session.relatedCourseIDs.first {
                    courseTitleByID[$0] != nil
                }
                return (pair.offset, GlobalSearchHit(
                    courseID: courseID,
                    courseTitle: courseID.flatMap { courseTitleByID[$0] } ?? unaffiliatedLabel,
                    isCurrentCourse: courseID == currentCourseID,
                    result: result
                ))
            }
        }
        // sort 不是稳定排序:携带内核序号,同组内保持原有相对顺序。
        let ordered = hits
            .sorted {
                if $0.hit.isCurrentCourse != $1.hit.isCurrentCourse {
                    return $0.hit.isCurrentCourse
                }
                return $0.index < $1.index
            }
            .prefix(resultLimit)
            .map(\.hit)
        return GlobalSearchOutcome(hits: ordered, availability: search.availability)
    }

    // MARK: - 共享内核(自 WorkspaceStore.searchCourseHome 原样迁移)

    private struct CourseSearchItemInput {
        let item: StudyItem
        let title: String
        let detail: String
        let memoryText: String?
    }

    private struct CourseSearchKernelOutcome {
        let results: [CourseHomeSearchResult]
        let availability: CourseDocumentIndexAvailability
        let ranOnMainThread: Bool
    }

    private func runCourseSearchKernel(
        itemInputs: [CourseSearchItemInput],
        sessions: [StudySession],
        query: String,
        chatDetail: String,
        resultLimit: Int = 50
    ) async -> CourseSearchKernelOutcome {
        let searchIndex = courseDocumentSearchIndex
        let searchTask = Task.detached(priority: .userInitiated) {
            let ranOnMainThread = pthread_main_np() != 0
            let indexedItems = itemInputs.compactMap {
                $0.memoryText == nil ? $0.item : nil
            }
            let indexed = searchIndex.lookup(
                items: indexedItems,
                query: query,
                maximumCharactersPerItem: 1_200
            )
            let availability: CourseDocumentIndexAvailability
            if indexedItems.contains(where: {
                indexed[$0.id]?.availability == .unavailable
                    || indexed[$0.id] == nil
            }) {
                availability = .unavailable
            } else if indexedItems.contains(where: {
                indexed[$0.id]?.availability == .indexing
            }) {
                availability = .indexing
            } else {
                availability = .ready
            }
            func snippet(_ text: String?) -> String? {
                guard let text else { return nil }
                let compact = text
                    .split(whereSeparator: \.isWhitespace)
                    .joined(separator: " ")
                guard !compact.isEmpty else { return nil }
                return String(compact.prefix(150))
            }

            var scored: [(score: Int, result: CourseHomeSearchResult)] = []
            for input in itemInputs {
                guard !Task.isCancelled else {
                    return CourseSearchKernelOutcome(
                        results: [CourseHomeSearchResult](),
                        availability: CourseDocumentIndexAvailability.ready,
                        ranOnMainThread: ranOnMainThread
                    )
                }
                let titleMatches = input.title.localizedCaseInsensitiveContains(query)
                let detailMatches = input.detail.localizedCaseInsensitiveContains(query)
                let bodyMatch: String?
                if let memoryText = input.memoryText {
                    bodyMatch = memoryText.localizedCaseInsensitiveContains(query)
                        ? snippet(memoryText)
                        : nil
                } else {
                    bodyMatch = snippet(indexed[input.item.id]?.text)
                }
                guard titleMatches || detailMatches || bodyMatch != nil else { continue }
                let kind: CourseHomeSearchResultKind = input.item.isNotebookNote
                    ? .note
                    : .material
                scored.append((
                    titleMatches ? 0 : (detailMatches ? 1 : 2),
                    CourseHomeSearchResult(
                        id: "\(kind.rawValue):\(input.item.id)",
                        kind: kind,
                        itemID: input.item.id,
                        sessionID: nil,
                        title: input.title,
                        detail: input.detail,
                        matchedText: bodyMatch
                    )
                ))
            }

            for session in sessions {
                guard !Task.isCancelled else {
                    return CourseSearchKernelOutcome(
                        results: [CourseHomeSearchResult](),
                        availability: CourseDocumentIndexAvailability.ready,
                        ranOnMainThread: ranOnMainThread
                    )
                }
                let titleMatches = session.title.localizedCaseInsensitiveContains(query)
                let summaryMatches = session.summary.localizedCaseInsensitiveContains(query)
                let matchingMessage = session.messages.first {
                    $0.text.localizedCaseInsensitiveContains(query)
                }?.text
                guard titleMatches || summaryMatches || matchingMessage != nil else { continue }
                let summary = session.summary.trimmingCharacters(in: .whitespacesAndNewlines)
                scored.append((
                    titleMatches ? 0 : (summaryMatches ? 1 : 2),
                    CourseHomeSearchResult(
                        id: "chat:\(session.id.uuidString)",
                        kind: .chat,
                        itemID: nil,
                        sessionID: session.id,
                        title: session.title,
                        detail: summary.isEmpty
                            ? String(format: chatDetail, session.displayedMessageCount)
                            : String(summary.prefix(150)),
                        matchedText: snippet(matchingMessage)
                    )
                ))
            }
            return CourseSearchKernelOutcome(
                results: scored
                .sorted {
                    $0.score == $1.score
                        ? $0.result.title.localizedStandardCompare($1.result.title)
                            == .orderedAscending
                        : $0.score < $1.score
                }
                .prefix(resultLimit)
                .map(\.result),
                availability: availability,
                ranOnMainThread: ranOnMainThread
            )
        }
        let search = await withTaskCancellationHandler {
            await searchTask.value
        } onCancel: {
            searchTask.cancel()
        }
        return search
    }
}
