import AppKit
import Foundation
import SwiftUI
import WeiBeiCore

/// Hosts deterministic visual and workflow verification scenarios outside production state storage.
extension WorkspaceStore {
    /// Recognizes the requested verification scenario and dispatches its deterministic fixture setup.
    func runWorkspaceVerificationScenarioIfNeeded() async {
        guard !didRunVerificationScenario else { return }
        guard Self.environmentValue("WEIBEI_SUPPRESS_ACTIVATION") == "1" else { return }
        let richAnswerReplayPath = Self.environmentValue("WEIBEI_VERIFY_RICH_ANSWER_REPLAY")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !richAnswerReplayPath.isEmpty {
            didRunVerificationScenario = true
            recordVerificationStage("recognized:rich-answer-replay")
            configureRichAnswerReplayVerification(path: richAnswerReplayPath)
            return
        }
        let scenario = Self.environmentValue("WEIBEI_VERIFY_SCENARIO")
        let emptyWorkspaceScenarios: Set<String> = [
            "empty-workspace-light-wide",
            "empty-workspace-light-narrow",
            "empty-workspace-dark-wide",
            "empty-workspace-dark-narrow",
            "empty-workspace-calligraphy-light",
            "empty-workspace-calligraphy-dark",
            "empty-workspace-inspiration-off",
            "empty-workspace-open-doc",
            "empty-workspace-open-chat",
            "empty-workspace-open-notes",
        ]
        guard scenario == "offline-learning-flow"
            || scenario == "pi-learning-flow"
            || scenario == "pi-course-memory-flow"
            || RichAnswerVerificationFixture.supports(scenario)
            || scenario == "immersive-conversation-flow"
            || scenario == "notebook-creation-flow"
            || scenario == "pure-writing-flow"
            || scenario == "linked-sources-flow"
            || scenario == "pane-layout-stability-flow"
            || scenario == "content-rail-dormant-preview"
            || scenario == "content-rail-activation-preview"
            || scenario == "pane-toggle-continuity-flow"
            || scenario == "pane-reorder-width-flow"
            || scenario == "reader-scroll-persistence-flow"
            || scenario == "course-workspace-overview-flow"
            || scenario == "course-workspace-workflow-flow"
            || scenario == "course-index-navigation-flow"
            || scenario == "loading-indicator-samples"
            || emptyWorkspaceScenarios.contains(scenario) else { return }
        didRunVerificationScenario = true
        recordVerificationStage("recognized:\(scenario)")
        if emptyWorkspaceScenarios.contains(scenario) {
            configureEmptyWorkspaceVerificationScenario(scenario)
            return
        }
        if scenario == "loading-indicator-samples" {
            // Shows product V3 「行文进行中」thinking indicator in the agent stream.
            let appearanceRaw = Self.environmentValue("WEIBEI_VERIFY_APPEARANCE").lowercased()
            if appearanceRaw == "ink" || appearanceRaw == "inkstone" || appearanceRaw == "dark" {
                appearanceMode = .inkstone
            } else {
                appearanceMode = .paper
            }
            let languageRaw = Self.environmentValue("WEIBEI_VERIFY_LANGUAGE").lowercased()
            if languageRaw == "en" || languageRaw == "english" {
                interfaceLanguage = .english
            } else {
                interfaceLanguage = .chinese
            }
            layout = .immersiveConversation
            showLibrary = false
            showReader = false
            showAgent = true
            showNotes = false
            agentSurface = .hidden
            isAskingAgent = true
            agentActivityText = ui("正在读取上下文", "Reading context")
            agentStreamingText = ""
            messages = []
            showLoadingIndicatorSamples = false
            recordVerificationStage("loading-samples")
            recordVerificationStage("completed")
            return
        }
        if scenario == "content-rail-dormant-preview" || scenario == "content-rail-activation-preview" {
            layout = .documentAgentNotes
            showLibrary = false
            showReader = true
            showAgent = true
            showNotes = true
            agentSurface = .hidden
            select(itemID: "sample-html")
            updateNote(ui("# 收起轨道验收\n\n悬浮简介必须越过收起边界显示。\n", "# Dormant rail check\n\nThe hover preview must cross the dormant pane boundary.\n"))
            save()
            return
        }
        if RichAnswerVerificationFixture.supports(scenario) {
            configureRichAnswerPreviewVerification(scenario: scenario)
            return
        }
        if scenario == "course-workspace-overview-flow"
            || scenario == "course-workspace-workflow-flow"
            || scenario == "course-index-navigation-flow" {
            await runCourseWorkspaceVerification(scenario)
            return
        }
        if scenario == "pane-toggle-continuity-flow" {
            await runPaneToggleContinuityVerification()
            return
        }
        if scenario == "pane-layout-stability-flow" {
            await runPaneLayoutStabilityVerification()
            return
        }
        if scenario == "pane-reorder-width-flow" {
            await runPaneReorderWidthVerification()
            return
        }
        if scenario == "reader-scroll-persistence-flow" {
            await runReaderScrollPersistenceVerification()
            return
        }
        layout = scenario == "immersive-conversation-flow" ? .immersiveConversation : .documentAgentNotes
        if scenario == "notebook-creation-flow" {
            layout = .immersiveWriting
        }
        if scenario == "pure-writing-flow" || scenario == "linked-sources-flow" {
            layout = .immersiveWriting
        }
        showLibrary = scenario != "immersive-conversation-flow"
        showReader = true
        showAgent = true
        showNotes = true
        agentSurface = .hidden
        select(itemID: "sample-html")
        if scenario == "pure-writing-flow" || scenario == "linked-sources-flow" {
            createNotebookNote(
                seed: .currentMaterial(sampleItems[0]),
                title: ui("多资料研究笔记", "Multi-source research note")
            )
            setLinkedSourceIDsForActiveNote(["sample-html", "sample-pdf"])
            select(itemID: "sample-pdf")
            showLibrary = false
            linkedSourcesPresented = scenario == "linked-sources-flow"
            if scenario == "linked-sources-flow" {
                noteRenderMode = .source
            }
            save()
            return
        }
        if scenario == "pi-learning-flow" || scenario == "pi-course-memory-flow" {
            await waitForReaderContextToSettle()
        }
        if scenario == "notebook-creation-flow" {
            promptCreateBlankNotebookNote()
            return
        }
        if scenario == "pi-course-memory-flow" {
            updateReaderLocationTitle(ui("实际利率", "Real interest rates"))
            updateNote(ui("# 课程学习记录\n\n", "# Course study record\n\n"))
            recordVerificationStage("course-memory-context-prepared")
            agentDraft = ui(
                "我上次学到哪？课程里哪份其他资料也提到利率，为什么相关？我还不懂名义利率和实际利率的区别，请记住这个困惑，并给出可点击来源。",
                "Where did I stop last time? Which other course material discusses interest rates, and why is it related? I still do not understand nominal versus real rates. Remember that confusion and give me a clickable source."
            )
            await askAgentAndWait()
            let answer = messages.last?.text ?? ""
            let recordedConfusion = latestAgentLearningUpdate?.entries.contains { $0.kind == .confusion } == true
            let hasJumpReference = answer.contains(ui("来源：", "Source:"))
            let previousItemID = selectedItemID
            let previousLearningUpdate = latestAgentLearningUpdate
            let openedJumpReference = openSourceReference(answer)
            if openedJumpReference, let previousItemID {
                select(itemID: previousItemID)
                latestAgentLearningUpdate = previousLearningUpdate
                lastAgentReplyContextRevision = agentContextRevision
            }
            recordVerificationStage("course-memory-reply:\(messages.last?.backend?.rawValue ?? "none")")
            recordVerificationStage("course-memory-update:\(recordedConfusion)")
            recordVerificationStage("course-memory-jump:\(hasJumpReference && openedJumpReference)")
            if messages.last?.backend == .pi,
               recordedConfusion,
               hasJumpReference,
               openedJumpReference {
                let markerURL = storageURL.deletingLastPathComponent().appendingPathComponent("pi-course-memory-verified.txt")
                try? "PI backend completed course memory and wayfinding\n".write(to: markerURL, atomically: true, encoding: .utf8)
            }
            recordVerificationStage("completed")
            return
        }
        let verificationNoteSeed = ui("# 视觉验收笔记\n\n", "# Visual verification note\n\n")
        updateNote(verificationNoteSeed)
        updateSelection(
            ui("利率是资金使用价格的表达。", "An interest rate is the price paid for using funds."),
            source: .document,
            ownerTitle: currentSourceReferenceTitle
        )
        recordVerificationStage("context-prepared")
        agentDraft = ui("解释选区，并整理成可以写入笔记的要点。", "Explain the selection and turn it into note-ready points.")
        await askAgentAndWait()
        recordVerificationStage("reply:\(messages.last?.backend?.rawValue ?? "none")")
        if messages.last?.backend == nil, let message = messages.last?.text {
            recordVerificationStage("failure:\(String(message.prefix(500)))")
        }
        applyLastAgentAnswerToNote()
        if scenario == "pi-learning-flow" {
            try? await Task.sleep(nanoseconds: 700_000_000)
            if messages.last?.backend == .pi, noteText.count > verificationNoteSeed.count {
                let markerURL = storageURL.deletingLastPathComponent().appendingPathComponent("pi-agent-verified.txt")
                try? "PI backend completed the packaged learning flow and persisted its note proposal\n"
                    .write(to: markerURL, atomically: true, encoding: .utf8)
            }
        }
        recordVerificationStage("completed")
    }

    private func configureRichAnswerPreviewVerification(scenario: String) {
        let presentation = RichAnswerVerificationFixture.presentation(for: scenario)
        let verifiesInlinePane = scenario == RichAnswerVerificationFixture.inlineExtendedOpenUIProgramScenario
        layout = verifiesInlinePane ? .documentAgentNotes : .immersiveConversation
        showLibrary = false
        showReader = verifiesInlinePane
        showAgent = true
        showNotes = false
        agentSurface = .hidden
        select(itemID: "sample-html")
        messages = []
        appendAgentMessage(
            AgentMessage(
                role: .user,
                text: RichAnswerVerificationFixture.question(for: scenario),
                source: "货币金融学课程 HTML"
            )
        )
        appendAgentMessage(
            AgentMessage(
                role: .assistant,
                text: presentation.narrative,
                source: "货币金融学课程 HTML",
                backend: .pi,
                richAnswer: presentation
            )
        )
        let familySummary = presentation.scenes.map(\.family.rawValue).joined(separator: ",")
        let verificationSummary = [
            "scenario=\(scenario)",
            "mode=\(presentation.mode.rawValue)",
            "scenes=\(presentation.scenes.count)",
            "families=\(familySummary)",
            "diagnostics=\(presentation.diagnostics.count)",
        ].joined(separator: "\n") + "\n"
        let markerURL = storageURL.deletingLastPathComponent()
            .appendingPathComponent("rich-answer-verified.txt")
        try? verificationSummary.write(to: markerURL, atomically: true, encoding: .utf8)
        recordVerificationStage("rich-answer:\(presentation.mode.rawValue):\(presentation.scenes.count):\(presentation.diagnostics.count)")
        focus(.agent)
        recordVerificationStage("completed")
    }

    private func configureRichAnswerReplayVerification(path: String) {
        let baseURL = storageURL.deletingLastPathComponent()
        do {
            let artifactURL = RichAnswerReplayArtifact.url(fromEnvironmentValue: path, relativeTo: baseURL)
            let artifact = try RichAnswerReplayArtifact.load(from: artifactURL)
            let materialItem = try installRichAnswerReplayMaterial(artifact, baseURL: baseURL)
            layout = .documentAgentNotes
            showLibrary = false
            showReader = true
            showAgent = true
            showNotes = false
            agentSurface = .hidden
            select(itemID: materialItem.id)
            messages = []
            latestAgentNoteProposal = nil
            latestAgentLearningUpdate = nil
            agentStreamingText = ""
            agentActivityText = "真实回放：\(artifact.status)"
            appendAgentMessage(
                AgentMessage(
                    role: .user,
                    text: artifact.question,
                    source: materialItem.title
                )
            )
            appendAgentMessage(
                AgentMessage(
                    role: .assistant,
                    text: artifact.visibleAssistantText,
                    source: materialItem.title,
                    backend: artifact.backend,
                    richAnswer: artifact.presentationForDisplay
                )
            )
            let verificationSummary = [
                "artifact=\(artifact.artifactURL.path)",
                "case=\(artifact.caseID)",
                "status=\(artifact.status)",
                "backend=\(artifact.backend?.rawValue ?? "none")",
                "materialItemID=\(artifact.materialItemID)",
                "materialKind=\(artifact.materialKind)",
                "verificationAssetID=\(artifact.verificationAssetID ?? "none")",
                "sourceFingerprint=\(artifact.sourceFingerprint ?? "none")",
                "verificationAssetFingerprint=\(artifact.verificationAssetFingerprint ?? "none")",
                "richAnswer=\(artifact.richAnswer?.mode.rawValue ?? "none")",
                "scenes=\(artifact.richAnswer?.scenes.count ?? 0)",
                "tools=\(artifact.toolTrace.joined(separator: ","))",
            ].joined(separator: "\n") + "\n"
            try verificationSummary.write(
                to: baseURL.appendingPathComponent("rich-answer-replay-verified.txt"),
                atomically: true,
                encoding: .utf8
            )
            recordVerificationStage("rich-answer-replay:\(artifact.status):\(artifact.richAnswer?.mode.rawValue ?? "none"):\(artifact.richAnswer?.scenes.count ?? 0)")
        } catch {
            configureRichAnswerReplayFailure(path: path, error: error, baseURL: baseURL)
        }
        recordVerificationStage("completed")
    }

    private func installRichAnswerReplayMaterial(
        _ artifact: RichAnswerReplayArtifact,
        baseURL: URL
    ) throws -> StudyItem {
        let directory = baseURL.appendingPathComponent("RichAnswerReplay", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let materialURL = try richAnswerReplayMaterialURL(for: artifact, directory: directory)
        let item = StudyItem(
            id: artifact.materialItemID,
            title: artifact.materialTitle,
            subtitle: "真实富回答回放材料 · \(artifact.materialKind)",
            kind: richAnswerReplayStudyItemKind(for: artifact.materialKind),
            urlPath: materialURL.path,
            isSample: false
        )
        importedItems.removeAll {
            $0.id == item.id
                || $0.id == "rich-answer-replay-material"
                || $0.urlPath == materialURL.path
        }
        importedItems.append(item)
        courseDocumentSearchIndex.synchronize(allItems)
        save()
        return item
    }

    private func richAnswerReplayMaterialURL(
        for artifact: RichAnswerReplayArtifact,
        directory: URL
    ) throws -> URL {
        let normalizedKind = artifact.materialKind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isImageMaterial = normalizedKind == "image"
        let verificationAssetID = artifact.verificationAssetID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let assetID = verificationAssetID, !assetID.isEmpty {
            guard isImageMaterial else {
                throw RichAnswerReplayMaterialInstallError.unexpectedVerificationAssetID(
                    assetID,
                    artifact.materialKind
                )
            }
            try RichAnswerVerificationAssets.validateBundledResources()
            guard let url = RichAnswerVerificationAssets.url(for: assetID) else {
                throw RichAnswerReplayMaterialInstallError.missingBundledVerificationAsset(assetID)
            }
            return url
        }
        if isImageMaterial {
            throw RichAnswerReplayMaterialInstallError.missingVerificationAssetID(artifact.materialItemID)
        }
        if artifact.referencesCurrentMaterialAsset {
            throw RichAnswerReplayMaterialInstallError.missingReferencedAsset(artifact.materialItemID)
        }

        if normalizedKind == "html" {
            let escapedTitle = artifact.materialTitle
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            let paragraphs = artifact.materialBody
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .map {
                    $0.replacingOccurrences(of: "&", with: "&amp;")
                        .replacingOccurrences(of: "<", with: "&lt;")
                        .replacingOccurrences(of: ">", with: "&gt;")
                }
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map { "<p>\($0)</p>" }
                .joined(separator: "\n")
            let escapedBody = paragraphs.isEmpty
                ? "<p>当前材料没有可显示的正文。</p>"
                : paragraphs
            let materialURL = directory.appendingPathComponent("material.html")
            let document = """
            <!doctype html>
            <html lang="zh-CN">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <style>
                html, body { margin: 0; background: transparent; }
                main { box-sizing: border-box; max-width: 760px; margin: 0 auto; padding: 34px 38px 64px; }
                h1 { margin: 0 0 24px; font-family: "Songti SC", "STSong", serif; font-size: 28px; line-height: 1.35; font-weight: 600; }
                p { margin: 0 0 14px; font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", sans-serif; font-size: 16px; line-height: 1.82; }
              </style>
            </head>
            <body><main data-weibei-paper-surface><h1>\(escapedTitle)</h1>\(escapedBody)</main></body>
            </html>
            """
            try document.write(to: materialURL, atomically: true, encoding: .utf8)
            return materialURL
        }

        let body = """
        \(artifact.materialTitle)

        \(artifact.materialBody)
        """
        let materialURL = directory.appendingPathComponent("material.txt")
        try body.write(to: materialURL, atomically: true, encoding: .utf8)
        return materialURL
    }

    private func richAnswerReplayStudyItemKind(for materialKind: String) -> StudyItemKind {
        switch materialKind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "image":
            .html
        case "html":
            .html
        case "pdf":
            .pdf
        case "markdown", "md":
            .markdown
        default:
            .text
        }
    }

    private func configureRichAnswerReplayFailure(path: String, error: Error, baseURL: URL) {
        layout = .immersiveConversation
        showLibrary = false
        showReader = false
        showAgent = true
        showNotes = false
        agentSurface = .hidden
        messages = []
        latestAgentNoteProposal = nil
        latestAgentLearningUpdate = nil
        agentStreamingText = ""
        agentActivityText = "真实回放失败"
        let question = "回放富回答留档：\(path)"
        let answer = """
        富回答真实回放失败，已显式显示错误，避免空白误判。

        路径：\(path)
        错误：\(error.localizedDescription)
        """
        appendAgentMessage(AgentMessage(role: .user, text: question, source: "富回答回放"))
        appendAgentMessage(AgentMessage(role: .assistant, text: answer, source: "富回答回放"))
        try? answer.write(
            to: baseURL.appendingPathComponent("rich-answer-replay-error.txt"),
            atomically: true,
            encoding: .utf8
        )
        recordVerificationStage("rich-answer-replay-failure:\(error.localizedDescription)")
    }

    private enum RichAnswerReplayMaterialInstallError: LocalizedError {
        case missingVerificationAssetID(String)
        case missingBundledVerificationAsset(String)
        case missingReferencedAsset(String)
        case unexpectedVerificationAssetID(String, String)

        var errorDescription: String? {
            switch self {
            case let .missingVerificationAssetID(materialItemID):
                return "富回答图片回放缺少 verificationAssetID，材料 \(materialItemID) 不显示空 Canvas。"
            case let .missingBundledVerificationAsset(assetID):
                return "富回答图片回放找不到已校验的打包图片资源：\(assetID)。"
            case let .missingReferencedAsset(assetID):
                return "富回答回放引用了材料资产 \(assetID)，但没有可解析的真实图片资源。"
            case let .unexpectedVerificationAssetID(assetID, materialKind):
                return "富回答回放记录了图片资源 \(assetID)，但材料类型是 \(materialKind)，已停止安装。"
            }
        }
    }

    /**
     * Appends a durable stage marker consumed by the external verification harness.
     *
     * @param stage - Stable machine-readable stage description
     */
    func recordVerificationStage(_ stage: String) {
        guard Self.environmentValue("WEIBEI_SUPPRESS_ACTIVATION") == "1" else { return }
        let url = storageURL.deletingLastPathComponent().appendingPathComponent("verification-state.txt")
        let previous = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try? "\(previous)\(stage)\n".write(to: url, atomically: true, encoding: .utf8)
    }

    private func configureEmptyWorkspaceVerificationScenario(_ scenario: String) {
        layout = .documentAgentNotes
        showLibrary = false
        agentSurface = .hidden
        appearanceMode = scenario.contains("dark") ? .inkstone : .paper
        showDailyInspiration = scenario != "empty-workspace-inspiration-off"

        if scenario.hasPrefix("empty-workspace-open-") {
            select(itemID: "sample-html")
            updateNote("# Empty workspace entry state marker\n\nPane toggles must preserve this note.\n")
        }

        showReader = false
        showAgent = false
        showNotes = false

        switch scenario {
        case "empty-workspace-open-doc":
            toggleReader()
        case "empty-workspace-open-chat":
            toggleAgent()
        case "empty-workspace-open-notes":
            toggleNotes()
        default:
            save()
        }
    }

}
