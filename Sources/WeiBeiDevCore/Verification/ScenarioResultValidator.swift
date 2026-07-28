import Foundation

/// 验证应用场景写入隔离工作区的行为结果。
public protocol VerificationScenarioResultValidating: Sendable {
    /// 等待场景结果出现，并根据场景契约判断成功或失败。
    func validate(
        scenario: VerificationScenario,
        artifacts: VerificationScenarioArtifacts
    ) throws
}

/// 使用文件与 JSON 行为产物验证旧脚本覆盖的场景。
public struct FileVerificationScenarioResultValidator: VerificationScenarioResultValidating {
    private let waiter: any VerificationWaiting
    private let pollingIntervalSeconds: TimeInterval

    /// 创建场景结果验证器。
    public init(
        waiter: any VerificationWaiting = SystemVerificationWaiter(),
        pollingIntervalSeconds: TimeInterval = 0.2
    ) {
        self.waiter = waiter
        self.pollingIntervalSeconds = pollingIntervalSeconds
    }

    /// 根据注册表中的类型化契约轮询结果。
    public func validate(
        scenario: VerificationScenario,
        artifacts: VerificationScenarioArtifacts
    ) throws {
        if scenario.resultContract == .visualOnly {
            return
        }
        let attempts = max(1, Int(ceil(scenario.timeoutSeconds / pollingIntervalSeconds)))
        for attempt in 0..<attempts {
            if resultIsValid(scenario: scenario, workspaceURL: artifacts.workspaceURL) {
                return
            }
            if conclusiveFailureExists(scenario: scenario, workspaceURL: artifacts.workspaceURL) {
                break
            }
            if attempt + 1 < attempts {
                waiter.wait(seconds: pollingIntervalSeconds)
            }
        }
        throw VerificationError(
            code: "scenario_assertion_failed",
            message: "Scenario \(scenario.id.rawValue) did not produce the expected behavior artifacts."
        )
    }

    /// Dispatches a scenario to its declared filesystem result contract.
    private func resultIsValid(scenario: VerificationScenario, workspaceURL: URL) -> Bool {
        switch scenario.resultContract {
        case .offlineLearning:
            return validateOfflineLearning(workspaceURL: workspaceURL)
        case .emptyWorkspace:
            return validateEmptyWorkspace(scenarioID: scenario.id, workspaceURL: workspaceURL)
        case .linkedSources:
            return validateLinkedSources(workspaceURL: workspaceURL)
        case .courseWorkspaceOverview:
            return validateCourseOverview(workspaceURL: workspaceURL)
        case .courseWorkspaceWorkflow:
            return validateCourseWorkflow(workspaceURL: workspaceURL)
        case .paneToggleContinuity:
            return textReportPassed(workspaceURL.appendingPathComponent("pane-toggle-continuity-report.txt"))
                && validatePaneSummary(workspaceURL: workspaceURL, minimumTransitions: 480)
        case .paneLayoutStability:
            return validatePaneLayout(workspaceURL: workspaceURL)
        case .paneReorderWidth:
            return textReportPassed(workspaceURL.appendingPathComponent("pane-reorder-width-report.txt"))
                && validatePaneSummary(workspaceURL: workspaceURL, minimumTransitions: 4)
        case .readerScrollPersistence:
            return textReportPassed(workspaceURL.appendingPathComponent("reader-scroll-persistence-report.txt"))
        case .piLearning:
            return validatePILearning(workspaceURL: workspaceURL)
        case .piCourseMemory:
            return validatePICourseMemory(workspaceURL: workspaceURL)
        case .visualOnly:
            return true
        }
    }

    /// Stops polling early when a text report has already declared failure.
    private func conclusiveFailureExists(scenario: VerificationScenario, workspaceURL: URL) -> Bool {
        let reportName: String?
        switch scenario.resultContract {
        case .paneToggleContinuity:
            reportName = "pane-toggle-continuity-report.txt"
        case .paneLayoutStability:
            reportName = "pane-layout-stability-report.txt"
        case .paneReorderWidth:
            reportName = "pane-reorder-width-report.txt"
        case .readerScrollPersistence:
            reportName = "reader-scroll-persistence-report.txt"
        default:
            reportName = nil
        }
        guard let reportName,
              let report = try? String(
                  contentsOf: workspaceURL.appendingPathComponent(reportName),
                  encoding: .utf8
              ) else {
            return false
        }
        return !report.split(whereSeparator: \.isNewline).contains("result=pass")
    }

    /// Confirms only the note-ready offline suggestion was persisted.
    private func validateOfflineLearning(workspaceURL: URL) -> Bool {
        guard let workspace = jsonObject(
            at: workspaceURL.appendingPathComponent("workspace.json")
        ) else {
            return false
        }
        let noteText: String
        if let notes = workspace["notesByItemID"] as? [String: String] {
            noteText = notes.values.joined(separator: "\n")
        } else {
            noteText = string(workspace["notes"]) ?? ""
        }
        return noteText.contains("## 整理建议")
            && noteText.contains("把可确认依据写入笔记")
            && !noteText.contains("## 离线草稿")
            && !noteText.contains("## 可确认")
    }

    /// Confirms each empty-workspace entry opens exactly the requested pane.
    private func validateEmptyWorkspace(scenarioID: VerificationScenarioID, workspaceURL: URL) -> Bool {
        guard let object = jsonObject(at: workspaceURL.appendingPathComponent("workspace.json")) else {
            return false
        }
        let expected: (reader: Bool, agent: Bool, notes: Bool, inspiration: Bool)
        switch scenarioID {
        case .emptyWorkspaceOpenDoc:
            expected = (true, false, false, true)
        case .emptyWorkspaceOpenChat:
            expected = (false, true, false, true)
        case .emptyWorkspaceOpenNotes:
            expected = (false, false, true, true)
        case .emptyWorkspaceInspirationOff:
            expected = (false, false, false, false)
        default:
            return false
        }
        guard bool(object["showReader"]) == expected.reader,
              bool(object["showAgent"]) == expected.agent,
              bool(object["showNotes"]) == expected.notes,
              bool(object["showDailyInspiration"]) == expected.inspiration else {
            return false
        }
        if [.emptyWorkspaceOpenDoc, .emptyWorkspaceOpenChat, .emptyWorkspaceOpenNotes].contains(scenarioID) {
            return text(at: workspaceURL.appendingPathComponent("workspace.json"))?
                .contains("Empty workspace entry state marker") == true
        }
        return true
    }

    /// Confirms linked sources retain stable imported notebook identity.
    private func validateLinkedSources(workspaceURL: URL) -> Bool {
        guard let workspace = text(at: workspaceURL.appendingPathComponent("workspace.json")) else {
            return false
        }
        return workspace.contains("\"noteSourceLinks\"")
            && workspace.contains("\"sourceItemID\":\"sample-html\"")
            && workspace.contains("\"sourceItemID\":\"sample-pdf\"")
            && workspace.contains("\"selectedItemID\":\"sample-pdf\"")
            && workspace.contains("\"showLibrary\":false")
            && workspace.contains("\"activeNotebookItemID\":\"imported:")
            && !workspace.contains("\"activeNotebookItemID\":\"file:")
    }

    /// Validates the course overview's counts, links, and navigation state.
    private func validateCourseOverview(workspaceURL: URL) -> Bool {
        guard let report = jsonObject(
            at: workspaceURL.appendingPathComponent("course-workspace-overview-report.json")
        ) else {
            return false
        }
        return string(report["result"]) == "pass"
            && integer(report["materialCount"]) == 3
            && integer(report["noteCount"]) == 3
            && integer(report["explicitLinkCount"]) == 3
            && integer(report["readingPositionCount"]) == 1
            && integer(report["studySessionCount"]) == 1
            && integer(report["unresolvedConfusionCount"]) == 1
            && bool(report["importClassificationPassed"]) == true
            && bool(report["invalidNoteCreationPassed"]) == true
            && bool(report["folderCountSummaryPassed"]) == true
            && strings(report["unlinkedMaterialIDs"]) == ["course-material-c"]
            && strings(report["unlinkedNoteIDs"]) == ["course-note-c"]
            && bool(report["courseWorkspacePresented"]) == true
    }

    /// Validates the complete course workspace interaction and persistence report.
    private func validateCourseWorkflow(workspaceURL: URL) -> Bool {
        guard let report = jsonObject(
            at: workspaceURL.appendingPathComponent("course-workspace-workflow-report.json")
        ) else {
            return false
        }
        return string(report["result"]) == "pass"
            && bool(report["continuityPassed"]) == true
            && bool(report["importClassificationPassed"]) == true
            && bool(report["invalidNoteCreationPassed"]) == true
            && bool(report["folderCountSummaryPassed"]) == true
            && bool(report["materialNavigationPassed"]) == true
            && bool(report["noteNavigationPassed"]) == true
            && bool(report["persistencePassed"]) == true
            && string(report["finalMaterialID"]) == "course-material-c"
            && string(report["finalNoteID"]) == "course-note-c"
            && strings(report["noteA_sources"]) == ["course-material-a"]
            && strings(report["noteC_sources"])?.sorted() == ["course-material-b", "course-material-c"]
            && strings(report["materialB_notes"])?.sorted() == ["course-note-b", "course-note-c"]
            && integer(report["paneMakeCount"]) == 0
            && integer(report["paneDismantleCount"]) == 0
    }

    /// Checks pane trace ownership and transition invariants.
    private func validatePaneSummary(workspaceURL: URL, minimumTransitions: Int) -> Bool {
        guard let summary = jsonObject(
            at: workspaceURL.appendingPathComponent("pane-trace/summary.json")
        ) else {
            return false
        }
        return (integer(summary["transitions"]) ?? -1) >= minimumTransitions
            && integer(summary["ownershipFailures"]) == 0
            && integer(summary["blankVisibleFailures"]) == 0
            && integer(summary["identityFailures"]) == 0
            && (summary["roleIdentities"] as? [Any])?.count == 3
    }

    /// Validates long-running pane layout identity across every transition.
    private func validatePaneLayout(workspaceURL: URL) -> Bool {
        guard textReportPassed(workspaceURL.appendingPathComponent("pane-layout-stability-report.txt")) else {
            return false
        }
        let traceDirectory = workspaceURL.appendingPathComponent("pane-trace")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: traceDirectory,
            includingPropertiesForKeys: nil
        ).filter({ $0.lastPathComponent.hasPrefix("container-") && $0.pathExtension == "json" }),
              files.count >= 120 else {
            return false
        }
        let traces = files.compactMap(jsonObject(at:))
        guard traces.count == files.count,
              Set(traces.compactMap { string($0["recorderID"]) }).count == 1,
              Set(traces.compactMap { string($0["transition"]) }).count >= 8,
              traces.allSatisfy({
                  bool($0["stableOwnership"]) == true && bool($0["noBlankVisibleSlots"]) == true
              }) else {
            return false
        }
        let grouped = Dictionary(grouping: traces) { string($0["transition"]) ?? "" }
        guard grouped.values.allSatisfy({ $0.count >= 15 }) else {
            return false
        }
        return ["reader", "agent", "notes"].allSatisfy { role in
            roleIdentityIsStable(role, traces: traces)
        }
    }

    /// Ensures a pane role retains the same host and content identities.
    private func roleIdentityIsStable(_ role: String, traces: [[String: Any]]) -> Bool {
        let roleEntries = traces.flatMap { trace -> [[String: Any]] in
            (trace["roles"] as? [[String: Any]])?.filter { string($0["role"]) == role } ?? []
        }
        guard !roleEntries.isEmpty else {
            return false
        }
        return ["hostID", "parentID", "contentHostID", "contentParentID"].allSatisfy { key in
            Set(roleEntries.compactMap { string($0[key]) }).count == 1
        }
    }

    /// Confirms the in-app PI learning marker and persisted answer.
    private func validatePILearning(workspaceURL: URL) -> Bool {
        guard nonEmptyFile(at: workspaceURL.appendingPathComponent("pi-agent-verified.txt")),
              let workspace = text(at: workspaceURL.appendingPathComponent("workspace.json")) else {
            return false
        }
        return workspace.contains("视觉验收笔记")
            && workspace.contains("利率")
            && !workspace.contains("## 离线草稿")
    }

    /// Confirms PI course memory, location, and session state were persisted.
    private func validatePICourseMemory(workspaceURL: URL) -> Bool {
        guard nonEmptyFile(at: workspaceURL.appendingPathComponent("pi-course-memory-verified.txt")),
              let workspace = text(at: workspaceURL.appendingPathComponent("workspace.json")) else {
            return false
        }
        return [
            "\"learningMemoryEntries\"",
            "\"studyLocationsByItemID\"",
            "\"studySessions\"",
            "\"confusion\"",
            "\"userStatement\"",
            "\"pi\""
        ].allSatisfy(workspace.contains)
    }

    /// Reports whether a line-oriented verifier report declares success.
    private func textReportPassed(_ url: URL) -> Bool {
        text(at: url)?.split(whereSeparator: \.isNewline).contains("result=pass") == true
    }

    /// Reads an optional UTF-8 verification artifact.
    private func text(at url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    /// Reports whether a regular verification artifact contains bytes.
    private func nonEmptyFile(at url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return false
        }
        return size.int64Value > 0
    }

    /// Decodes a JSON artifact as a string-keyed object.
    private func jsonObject(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    /// Extracts a string from dynamically decoded JSON.
    private func string(_ value: Any?) -> String? {
        value as? String
    }

    /// Extracts a string array from dynamically decoded JSON.
    private func strings(_ value: Any?) -> [String]? {
        value as? [String]
    }

    /// Extracts an integer while accepting JSON NSNumber values.
    private func integer(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    /// Extracts a boolean while accepting JSON NSNumber values.
    private func bool(_ value: Any?) -> Bool? {
        (value as? NSNumber)?.boolValue
    }
}
