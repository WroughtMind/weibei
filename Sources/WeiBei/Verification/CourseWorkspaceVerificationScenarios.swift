import AppKit
import Foundation
import SwiftUI
import WeiBeiCore

/// Course-library and course-workspace verification scenarios.
extension WorkspaceStore {
    /**
     * Builds course fixtures and drives overview, workflow, and index-navigation scenarios.
     *
     * @param scenario - Registered course verification scenario name
     */
    func runCourseWorkspaceVerification(_ scenario: String) async {
        let fixtureDirectory = storageURL.deletingLastPathComponent()
            .appendingPathComponent("CourseWorkspaceFixtures", isDirectory: true)
        try? FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)

        func fixtureURL(_ name: String, extension fileExtension: String) -> URL {
            fixtureDirectory.appendingPathComponent(name).appendingPathExtension(fileExtension)
        }

        let materialAURL = fixtureURL("利率基础", extension: "html")
        let materialBURL = fixtureURL("货币政策", extension: "md")
        let materialCURL = fixtureURL("复习问题", extension: "txt")
        let noteAURL = fixtureURL("利率研究笔记", extension: "md")
        let noteBURL = fixtureURL("政策工具笔记", extension: "md")
        let noteCURL = fixtureURL("期末复习笔记", extension: "md")
        try? "<h1>利率基础</h1><p>名义利率与实际利率。</p>".write(to: materialAURL, atomically: true, encoding: .utf8)
        try? "# 货币政策\n\n公开市场操作与政策利率。\n".write(to: materialBURL, atomically: true, encoding: .utf8)
        try? "复习：比较名义利率与实际利率。\n".write(to: materialCURL, atomically: true, encoding: .utf8)
        try? "# 利率研究笔记\n\n## 核心要点\n".write(to: noteAURL, atomically: true, encoding: .utf8)
        try? "# 政策工具笔记\n\n## 摘录\n".write(to: noteBURL, atomically: true, encoding: .utf8)
        try? "# 期末复习笔记\n\n## 待追问\n".write(to: noteCURL, atomically: true, encoding: .utf8)

        let selectionBeforeFolderImport = selectedItemID
        let folderImportDraft = makeCourseFolderImportDraft(
            rootURLs: [fixtureDirectory],
            supportedFiles: Self.supportedCourseFiles(at: fixtureDirectory)
        )
        importCourseFolder(folderImportDraft, notePaths: folderImportDraft.notePaths)
        let importedFolderItems = importedItems.filter {
            $0.url?.deletingLastPathComponent().standardizedFileURL.path == fixtureDirectory.standardizedFileURL.path
        }
        let importedFolderRoles = Dictionary(uniqueKeysWithValues: importedFolderItems.map {
            ($0.subtitle, $0.isNotebookNote)
        })
        let folderItemCountPassed = importedFolderItems.count == 6
        let folderMaterialDefaultPassed = (importedFolderRoles[materialBURL.lastPathComponent] ?? true) == false
        let folderNoteDefaultsPassed = [noteAURL, noteBURL, noteCURL].allSatisfy { url in
            (importedFolderRoles[url.lastPathComponent] ?? false) == true
        }
        let folderCountSummaryPassed = folderImportDraft.automaticMaterialCount
            + folderImportDraft.markdownFiles.count
            - folderImportDraft.notePaths.count == 3
        let initialFolderClassificationPassed = folderItemCountPassed
            && folderMaterialDefaultPassed
            && folderNoteDefaultsPassed
            && folderCountSummaryPassed
        _ = importFiles(
            [materialBURL],
            selectsFirstImportedItem: false,
            markdownAsNotes: true,
            markdownOnly: true,
            reclassifiesExistingMarkdown: true
        )
        let correctedExistingFileToNote = importedItems.first(where: { $0.urlPath == materialBURL.path })?.isNotebookNote == true
        _ = importFiles(
            [materialBURL],
            selectsFirstImportedItem: false,
            reclassifiesExistingMarkdown: true
        )
        let correctedExistingFileBackToMaterial = importedItems.first(where: { $0.urlPath == materialBURL.path })?.isNotebookNote == false
        let importClassificationPassed = initialFolderClassificationPassed
            && correctedExistingFileToNote
            && correctedExistingFileBackToMaterial
            && selectedItemID == selectionBeforeFolderImport
        let importSelectionPreserved = selectedItemID == selectionBeforeFolderImport

        let materialA = StudyItem(id: "course-material-a", title: "利率基础", subtitle: materialAURL.lastPathComponent, kind: .html, urlPath: materialAURL.path, isSample: false)
        let materialB = StudyItem(id: "course-material-b", title: "货币政策", subtitle: materialBURL.lastPathComponent, kind: .markdown, urlPath: materialBURL.path, isSample: false)
        let materialC = StudyItem(id: "course-material-c", title: "复习问题", subtitle: materialCURL.lastPathComponent, kind: .text, urlPath: materialCURL.path, isSample: false)
        let noteA = StudyItem(id: "course-note-a", title: "利率研究笔记", subtitle: noteAURL.lastPathComponent, kind: .markdown, urlPath: noteAURL.path, isSample: false, isNotebookNote: true)
        let noteB = StudyItem(id: "course-note-b", title: "政策工具笔记", subtitle: noteBURL.lastPathComponent, kind: .markdown, urlPath: noteBURL.path, isSample: false, isNotebookNote: true)
        let noteC = StudyItem(id: "course-note-c", title: "期末复习笔记", subtitle: noteCURL.lastPathComponent, kind: .markdown, urlPath: noteCURL.path, isSample: false, isNotebookNote: true)

        importedItems = [materialA, materialB, materialC, noteA, noteB, noteC]
        notesByItemID = [
            noteA.id: "# 利率研究笔记\n\n## 核心要点\n",
            noteB.id: "# 政策工具笔记\n\n## 摘录\n",
            noteC.id: "# 期末复习笔记\n\n## 待追问\n",
        ]
        selectedItemID = materialA.id
        activeNotebookItemID = noteA.id
        noteText = notesByItemID[noteA.id] ?? ""
        noteSourceLinks = [
            NoteSourceLink(noteItemID: noteA.id, sourceItemID: materialA.id),
            NoteSourceLink(noteItemID: noteA.id, sourceItemID: materialB.id),
            NoteSourceLink(noteItemID: noteB.id, sourceItemID: materialB.id),
        ]
        let courseA = Course(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: "货币金融学",
            colorIndex: 0
        )
        let courseB = Course(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            title: "经济思想史",
            colorIndex: 1
        )
        courses = [courseA, courseB]
        var verificationMemberships = CourseItemMemberships()
        verificationMemberships.assign(
            itemIDs: Set([materialA.id, materialB.id, noteA.id, noteB.id]),
            to: courseA.id
        )
        verificationMemberships.assign(
            itemIDs: Set([materialB.id, materialC.id, noteB.id, noteC.id]),
            to: courseB.id
        )
        courseItemMemberships = verificationMemberships.values
        activeCourseID = courseA.id
        studyLocationsByItemID = [
            materialA.id: StudyLocation(
                itemID: materialA.id,
                itemTitle: materialA.title,
                locationID: "html-heading-1",
                locationTitle: "名义利率与实际利率",
                lastStudiedAt: Date().addingTimeInterval(-1_800),
                visitCount: 3
            )
        ]
        let activeSession = StudySession(
            title: "利率为什么会变化",
            messages: [
                AgentMessage(role: .user, text: "名义利率和实际利率有什么区别？", source: materialA.title, backend: .pi),
                AgentMessage(role: .assistant, text: "实际利率会扣除通货膨胀的影响。", source: materialA.title, backend: .pi),
            ],
            summary: "比较名义利率与实际利率，并联系货币政策工具。",
            focusItemIDs: [materialA.id, materialB.id, noteA.id],
            flow: StudyFlowState(phase: .note, suggestedNext: ["把利率公式整理到复习笔记", "用一道例题检验区别"]),
            updatedAt: Date().addingTimeInterval(-900)
        )
        let emptySession = StudySession(title: "新学习会话")
        studySessions = [activeSession, emptySession]
        activeStudySessionID = activeSession.id
        messages = activeSession.messages
        learningMemoryEntries = [
            LearningMemoryEntry(
                kind: .confusion,
                text: "仍不确定通货膨胀预期如何传导到名义利率。",
                evidence: "用户在当前会话中明确提出",
                origin: .userStatement,
                sessionID: activeSession.id
            ),
            LearningMemoryEntry(
                kind: .nextStep,
                text: "完成名义利率与实际利率的对照例题。",
                evidence: "当前会话建议",
                origin: .agentInference,
                sessionID: activeSession.id
            ),
        ]
        layout = .documentAgentNotes
        showLibrary = false
        showReader = true
        showAgent = true
        showNotes = true
        agentSurface = .hidden
        courseDocumentSearchIndex.synchronize(allItems)
        save()

        if scenario == "course-index-navigation-flow" {
            let unassignedURL = fixtureURL("跨课程阅读清单", extension: "txt")
            try? "待归类：金融史、政策工具与复习问题。\n".write(to: unassignedURL, atomically: true, encoding: .utf8)
            importedItems.append(
                StudyItem(
                    id: "course-material-unassigned",
                    title: "跨课程阅读清单",
                    subtitle: unassignedURL.lastPathComponent,
                    kind: .text,
                    urlPath: unassignedURL.path,
                    isSample: false
                )
            )
            activeCourseID = nil
            showLibrary = true
            courseWorkspacePresented = false
            courseDocumentSearchIndex.synchronize(allItems)
            save()
            recordVerificationStage("completed")
            return
        }

        let noteCountBeforeInvalidCreation = courseNotebookItems.count
        let invalidNoteID = createCourseNotebookNote(title: "   ")
        let invalidNoteCreationPassed = invalidNoteID == nil
            && courseNotebookItems.count == noteCountBeforeInvalidCreation
            && noteFileError?.isEmpty == false
        noteFileError = nil

        let initialSummary = courseWorkspaceSummary
        let initialRelations = NoteSourceRelations(links: noteSourceLinks)
        if scenario == "course-workspace-overview-flow" {
            let requestedPage = Self.environmentValue("WEIBEI_VERIFY_COURSE_PAGE")
            if requestedPage == "notes" {
                presentCourseWorkspace(.notes, selecting: noteA.id)
            } else if requestedPage == "materials" || requestedPage == "relations-large" {
                if requestedPage == "relations-large" {
                    activeCourseID = nil
                }
                presentCourseWorkspace(.materials, selecting: materialB.id)
            } else if requestedPage == "sessions" {
                presentCourseWorkspace(.sessions, selecting: activeSession.id.uuidString)
            } else {
                presentCourseWorkspace(.relations)
            }
            writeCourseWorkspaceVerificationReport(
                name: "course-workspace-overview-report.json",
                payload: [
                    "result": initialSummary.materialCount == 3
                        && initialSummary.noteCount == 3
                        && initialSummary.explicitLinkCount == 3
                        && initialSummary.readingPositionCount == 1
                        && initialSummary.unlinkedMaterialCount == 1
                        && initialSummary.unlinkedNoteCount == 1
                        && initialSummary.studySessionCount == 1
                        && initialSummary.unresolvedConfusionCount == 1
                        && importClassificationPassed ? "pass" : "fail",
                    "importClassificationPassed": importClassificationPassed,
                    "invalidNoteCreationPassed": invalidNoteCreationPassed,
                    "initialFolderClassificationPassed": initialFolderClassificationPassed,
                    "correctedExistingFileToNote": correctedExistingFileToNote,
                    "correctedExistingFileBackToMaterial": correctedExistingFileBackToMaterial,
                    "importSelectionPreserved": importSelectionPreserved,
                    "importedFolderItemCount": importedFolderItems.count,
                    "importedFolderRoles": importedFolderRoles,
                    "folderMaterialDefaultPassed": folderMaterialDefaultPassed,
                    "folderNoteDefaultsPassed": folderNoteDefaultsPassed,
                    "folderCountSummaryPassed": folderCountSummaryPassed,
                    "materialCount": initialSummary.materialCount,
                    "noteCount": initialSummary.noteCount,
                    "explicitLinkCount": initialSummary.explicitLinkCount,
                    "readingPositionCount": initialSummary.readingPositionCount,
                    "unlinkedMaterialIDs": courseMaterialsWithoutNoteLinks.map(\.id).sorted(),
                    "unlinkedNoteIDs": courseNotesWithoutSourceLinks.map(\.id).sorted(),
                    "studySessionCount": initialSummary.studySessionCount,
                    "unresolvedConfusionCount": initialSummary.unresolvedConfusionCount,
                    "currentMaterialID": selectedItemID ?? "",
                    "currentNoteID": activeNotebookItemID ?? "",
                    "courseWorkspacePresented": courseWorkspacePresented,
                ]
            )
            if requestedPage == "relations-large" {
                let courseC = Course(
                    id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                    title: "金融史专题",
                    colorIndex: 2
                )
                let courseD = Course(
                    id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                    title: "计量练习",
                    colorIndex: 3
                )
                courses.append(contentsOf: [courseC, courseD])

                var expandedMemberships = CourseItemMemberships(values: courseItemMemberships)
                var expandedRelations = NoteSourceRelations(links: noteSourceLinks)
                for index in 1...7 {
                    let materialURL = fixtureURL("扩展资料 \(index)", extension: "txt")
                    let noteURL = fixtureURL("扩展笔记 \(index)", extension: "md")
                    try? "第 \(index) 份课程材料，包含利率、政策与历史线索。\n".write(to: materialURL, atomically: true, encoding: .utf8)
                    try? "# 扩展笔记 \(index)\n\n## 课程线索\n".write(to: noteURL, atomically: true, encoding: .utf8)
                    let material = StudyItem(
                        id: "course-large-material-\(index)",
                        title: ["债券定价", "通胀预期", "央行沟通", "危机史料", "政策冲击", "回归练习", "期末框架"][index - 1],
                        subtitle: materialURL.lastPathComponent,
                        kind: .text,
                        urlPath: materialURL.path,
                        isSample: false
                    )
                    let note = StudyItem(
                        id: "course-large-note-\(index)",
                        title: ["期限结构札记", "费雪效应", "政策信号", "危机比较", "识别假设", "模型结果", "总复习图谱"][index - 1],
                        subtitle: noteURL.lastPathComponent,
                        kind: .markdown,
                        urlPath: noteURL.path,
                        isSample: false,
                        isNotebookNote: true
                    )
                    importedItems.append(contentsOf: [material, note])
                    notesByItemID[note.id] = "# \(note.title)\n\n## 课程线索\n"
                    let primaryCourseID = index <= 3 ? courseC.id : courseD.id
                    expandedMemberships.assign(itemIDs: Set([material.id, note.id]), to: primaryCourseID)
                    if index == 3 || index == 4 {
                        expandedMemberships.assign(itemIDs: Set([material.id, note.id]), to: courseB.id)
                    }
                    let nextNoteID = "course-large-note-\(index == 7 ? 1 : index + 1)"
                    expandedRelations.replaceNotes(
                        for: material.id,
                        noteItemIDs: Set([note.id, nextNoteID])
                    )
                }
                courseItemMemberships = expandedMemberships.values
                noteSourceLinks = expandedRelations.links
                activeCourseID = nil
                courseDocumentSearchIndex.synchronize(allItems)
                save()
            }
            recordVerificationStage("completed")
            return
        }

        func verifyCourseOverlayContinuity(itemID: String) async -> (passed: Bool, makeCount: Int, dismantleCount: Int) {
            select(itemID: itemID)
            try? await Task.sleep(nanoseconds: 900_000_000)
            let baselineLayout = layout
            let baselineMaterialID = selectedItemID
            let baselineNoteID = activeNotebookItemID
            let baselineNoteText = noteText
            let baselineMessages = messages
            let baselineOrder = threePaneOrder
            let baselineLocation = selectedItemID.flatMap { studyLocationsByItemID[$0] }
            PaneToggleContinuityVerifier.beginMeasurement()
            presentCourseWorkspace(.relations)
            try? await Task.sleep(nanoseconds: 500_000_000)
            dismissCourseWorkspace()
            try? await Task.sleep(nanoseconds: 500_000_000)
            let makeCount = PaneToggleContinuityVerifier.webReaderMakeCount
                + PaneToggleContinuityVerifier.pdfReaderMakeCount
                + PaneToggleContinuityVerifier.noteEditorMakeCount
            let dismantleCount = PaneToggleContinuityVerifier.webReaderDismantleCount
                + PaneToggleContinuityVerifier.pdfReaderDismantleCount
                + PaneToggleContinuityVerifier.noteEditorDismantleCount
            let passed = layout == baselineLayout
                && selectedItemID == baselineMaterialID
                && activeNotebookItemID == baselineNoteID
                && noteText == baselineNoteText
                && messages == baselineMessages
                && threePaneOrder == baselineOrder
                && selectedItemID.flatMap { studyLocationsByItemID[$0] } == baselineLocation
                && makeCount == 0
                && dismantleCount == 0
            PaneToggleContinuityVerifier.endMeasurement()
            return (passed, makeCount, dismantleCount)
        }

        let htmlContinuity = await verifyCourseOverlayContinuity(itemID: materialA.id)
        let pdfContinuity = await verifyCourseOverlayContinuity(itemID: "sample-pdf")
        let continuityPassed = htmlContinuity.passed && pdfContinuity.passed
        let paneMakeCount = htmlContinuity.makeCount + pdfContinuity.makeCount
        let paneDismantleCount = htmlContinuity.dismantleCount + pdfContinuity.dismantleCount
        select(itemID: materialA.id)

        setLinkedSourceIDs([materialA.id], for: noteA.id)
        setLinkedSourceIDs([materialB.id, materialC.id], for: noteC.id)
        let editedRelations = NoteSourceRelations(links: noteSourceLinks)

        presentCourseWorkspace(.materials, selecting: materialC.id)
        openCourseMaterial(materialC.id)
        let materialNavigationPassed = selectedItemID == materialC.id
            && activeNotebookItemID == noteA.id
            && !editedRelations.isLinked(noteItemID: noteA.id, sourceItemID: materialC.id)

        presentCourseWorkspace(.notes, selecting: noteC.id)
        openCourseNote(noteC.id)
        let noteNavigationPassed = selectedItemID == materialC.id
            && activeNotebookItemID == noteC.id

        flushPendingNotePersistence()
        save()
        let diskData = try? Data(contentsOf: storageURL)
        let diskSnapshot = diskData.flatMap { try? JSONDecoder().decode(PersistedWorkspace.self, from: $0) }
        let diskRelations = NoteSourceRelations(links: diskSnapshot?.noteSourceLinks ?? [])
        let diskSummary = diskSnapshot.map {
            CourseWorkspaceSummary(
                importedItems: $0.importedItems,
                noteSourceLinks: $0.noteSourceLinks ?? [],
                studyLocationsByItemID: $0.studyLocationsByItemID ?? [:],
                studySessions: $0.studySessions ?? [],
                learningMemoryEntries: $0.learningMemoryEntries ?? []
            )
        }
        let persistencePassed = diskRelations.sourceIDs(for: noteA.id) == [materialA.id]
            && Set(diskRelations.sourceIDs(for: noteC.id)) == Set([materialB.id, materialC.id])
            && Set(diskRelations.noteIDs(for: materialB.id)) == Set([noteB.id, noteC.id])
            && Set(diskSnapshot?.courses?.map(\.id) ?? []) == Set([courseA.id, courseB.id])
            && diskSnapshot?.activeCourseID == courseB.id
            && diskSnapshot?.courseItemMemberships?.count == courseItemMemberships.count
            && diskSummary?.explicitLinkCount == 4
            && diskSummary?.unlinkedMaterialCount == 0
            && diskSummary?.unlinkedNoteCount == 0

        let resultPassed = initialRelations.links.count == 3
            && importClassificationPassed
            && invalidNoteCreationPassed
            && continuityPassed
            && materialNavigationPassed
            && noteNavigationPassed
            && persistencePassed
        writeCourseWorkspaceVerificationReport(
            name: "course-workspace-workflow-report.json",
            payload: [
                "result": resultPassed ? "pass" : "fail",
                "continuityPassed": continuityPassed,
                "importClassificationPassed": importClassificationPassed,
                "invalidNoteCreationPassed": invalidNoteCreationPassed,
                "initialFolderClassificationPassed": initialFolderClassificationPassed,
                "correctedExistingFileToNote": correctedExistingFileToNote,
                "correctedExistingFileBackToMaterial": correctedExistingFileBackToMaterial,
                "importSelectionPreserved": importSelectionPreserved,
                "importedFolderItemCount": importedFolderItems.count,
                "importedFolderRoles": importedFolderRoles,
                "folderMaterialDefaultPassed": folderMaterialDefaultPassed,
                "folderNoteDefaultsPassed": folderNoteDefaultsPassed,
                "folderCountSummaryPassed": folderCountSummaryPassed,
                "materialNavigationPassed": materialNavigationPassed,
                "noteNavigationPassed": noteNavigationPassed,
                "persistencePassed": persistencePassed,
                "finalMaterialID": selectedItemID ?? "",
                "finalNoteID": activeNotebookItemID ?? "",
                "noteA_sources": diskRelations.sourceIDs(for: noteA.id),
                "noteC_sources": diskRelations.sourceIDs(for: noteC.id),
                "materialB_notes": diskRelations.noteIDs(for: materialB.id),
                "paneMakeCount": paneMakeCount,
                "paneDismantleCount": paneDismantleCount,
            ]
        )
        recordVerificationStage("completed")
    }

    private func writeCourseWorkspaceVerificationReport(name: String, payload: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else { return }
        let url = storageURL.deletingLastPathComponent().appendingPathComponent(name)
        try? data.write(to: url, options: .atomic)
    }

    /// Waits until reader location state is stable across consecutive samples.
    func waitForReaderContextToSettle() async {
        var previousTitle = readerLocationTitle
        var previousPage = readerPageIndex
        var stableChecks = 0
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 150_000_000)
            if readerLocationTitle == previousTitle, readerPageIndex == previousPage {
                stableChecks += 1
                if stableChecks >= 3 { return }
            } else {
                previousTitle = readerLocationTitle
                previousPage = readerPageIndex
                stableChecks = 0
            }
        }
    }

}
