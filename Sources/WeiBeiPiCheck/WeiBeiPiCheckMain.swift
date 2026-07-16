import Darwin
import Foundation
import WeiBeiCore

@main
struct WeiBeiPiCheckMain {
    static func main() async {
        if CommandLine.arguments.contains("--rich-answer-protocol") {
            do {
                try runRichAnswerProtocolSelfCheck()
                print("rich-answer-protocol-check passed")
            } catch {
                fputs("rich-answer-protocol-check failed: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
            return
        }

        let environment = ProcessInfo.processInfo.environment
        let liveCheckSetting = environment["WEIBEI_PI_LIVE_CHECK"] ?? "auto"
        let runsEvaluation = environment["WEIBEI_PI_EVAL"] == "1"
        let runsRichAnswerCheck = environment["WEIBEI_PI_RICH_ANSWER_CHECK"] == "1"
        let explicitPath = environment["WEIBEI_PI_EXECUTABLE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let executableURL = explicitPath.isEmpty
            ? PiExecutableLocator.locate()
            : URL(fileURLWithPath: explicitPath)
        let containingAppPath = environment["WEIBEI_PI_APP_BUNDLE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let containingAppURL = containingAppPath.isEmpty ? nil : URL(fileURLWithPath: containingAppPath)

        guard let executableURL else {
            fputs("pi-check failed: embedded PI runtime not found\n", stderr)
            exit(1)
        }

        let runtimeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("weibei-pi-check-\(UUID().uuidString)", isDirectory: true)
        let runtime = PiAgentRuntime(executableURL: executableURL, runtimeDirectory: runtimeRoot)

        do {
            let manifest = try PiBundledRuntime.validate(
                executableURL: executableURL,
                containingAppURL: containingAppURL
            )
            let launchedPath = try await runtime.healthCheck()
            let isolatedConfig = runtimeRoot.appendingPathComponent("PiConfig", isDirectory: true)
            guard FileManager.default.fileExists(atPath: isolatedConfig.path) else {
                throw PiCheckError.missingIsolatedConfiguration
            }
            print("pi-check ready: PI \(manifest.piVersion) at \(launchedPath)")

            let isolatedAuth = isolatedConfig.appendingPathComponent("auth.json")
            let hasConfiguredAuth = ((try? isolatedAuth.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 2
            let runsLiveCheck = runsEvaluation
                || liveCheckSetting == "1"
                || (liveCheckSetting != "0" && hasConfiguredAuth)
            if runsLiveCheck {
                try await checkNoteMaking(runtime)
            }
            if runsRichAnswerCheck || runsEvaluation {
                try await checkRichAnswer(runtime)
            }
            if runsEvaluation {
                try await checkStudyCompanion(runtime)
                try await checkCourseWayfinding(runtime)
                try await checkCloseReading(runtime)
                try await checkRecallPractice(runtime)
                print("pi-eval passed: study-companion, course-wayfinding, close-reading, rich-answer, note-making, recall-practice")
            }
            try verifyNoPersistedTurnState(runtimeRoot)

            await runtime.shutdown()
            try? FileManager.default.removeItem(at: runtimeRoot)
        } catch {
            await runtime.shutdown()
            try? FileManager.default.removeItem(at: runtimeRoot)
            fputs("pi-check failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func checkNoteMaking(_ runtime: PiAgentRuntime) async throws {
        let reply = try await runtime.respond(
            to: request(
                workflow: .noteMaking,
                question: "请把当前选区整理成一个带来源的 Markdown 核心要点，并提交待确认的笔记建议。",
                revision: "pi-check-note"
            )
        )
        guard reply.backend == .pi,
              !reply.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let proposal = reply.noteProposal,
              proposal.contextRevision == "pi-check-note",
              !proposal.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !proposal.evidence.isEmpty else {
            throw PiCheckError.invalidLiveReply
        }
        print("pi-live-check passed: proposal=\(proposal.markdown.count) chars evidence=\(proposal.evidence.count)")
    }

    private static func checkCloseReading(_ runtime: PiAgentRuntime) async throws {
        let reply = try await runtime.respond(
            to: request(
                workflow: .closeReading,
                question: "只根据当前内容解释为什么利率可称为资金价格，并标明来源。",
                revision: "pi-check-reading"
            )
        )
        guard reply.backend == .pi,
              reply.noteProposal == nil,
              reply.text.contains("资金"),
              containsSourceLabel(reply.text) else {
            throw PiCheckError.invalidEvaluation("close-reading")
        }
    }

    private static func checkRichAnswer(_ runtime: PiAgentRuntime) async throws {
        let reply = try await runtime.respond(
            to: request(
                workflow: .closeReading,
                question: "请基于当前材料，用可调的富回答展示名义利率、通胀率和实际利率的近似关系；固定名义利率为 5%，让我调节通胀率。正文仍要简洁引用来源，不要输出场景 JSON。",
                revision: "pi-check-rich-answer"
            )
        )
        guard reply.backend == .pi,
              reply.noteProposal == nil,
              containsSourceLabel(reply.text),
              let presentation = reply.richAnswer,
              presentation.mode == .rich,
              presentation.scenes.contains(where: {
                  $0.family == .quantityAndCoordinates || $0.family == .calculationAndConstraints
              }),
              presentation.scenes.contains(where: { !$0.operations.isEmpty }) else {
            let presentation = reply.richAnswer
            let families = presentation?.scenes.map(\.family.rawValue).joined(separator: ",") ?? "none"
            let operationCount = presentation?.scenes.reduce(0) { $0 + $1.operations.count } ?? 0
            let diagnostics = presentation?.diagnostics.map(\.code.rawValue).joined(separator: ",") ?? "none"
            throw PiCheckError.invalidEvaluation(
                "rich-answer backend=\(reply.backend.rawValue) source=\(containsSourceLabel(reply.text)) "
                    + "presentation=\(presentation != nil) mode=\(presentation?.mode.rawValue ?? "none") "
                    + "families=\(families) operations=\(operationCount) diagnostics=\(diagnostics)"
            )
        }
        print("pi-rich-answer passed: scenes=\(presentation.scenes.count) diagnostics=\(presentation.diagnostics.count)")
    }

    private static func checkStudyCompanion(_ runtime: PiAgentRuntime) async throws {
        let reply = try await runtime.respond(
            to: request(
                workflow: .studyCompanion,
                question: "我上次学到哪了？请告诉我位置和下一步。",
                revision: "pi-check-companion"
            )
        )
        guard reply.backend == .pi,
              reply.text.contains("期限结构") || reply.text.contains("第 12 页") || reply.text.contains("第12页"),
              reply.text.contains("[学习记录：上次位置]") else {
            throw PiCheckError.invalidEvaluation("study-companion")
        }
    }

    private static func checkCourseWayfinding(_ runtime: PiAgentRuntime) async throws {
        let reply = try await runtime.respond(
            to: request(
                workflow: .courseWayfinding,
                question: "利率和通货膨胀在课程里有哪份相关材料？说明关联，并原样给出工具返回的最精确 PDF 页码跳转。",
                revision: "pi-check-wayfinding"
            )
        )
        guard reply.backend == .pi,
              reply.text.contains("通货膨胀补充材料"),
              reply.text.contains("来源：通货膨胀补充材料，第 4 页"),
              containsSourceLabel(reply.text) else {
            throw PiCheckError.invalidEvaluation("course-wayfinding")
        }
    }

    private static func checkRecallPractice(_ runtime: PiAgentRuntime) async throws {
        let reply = try await runtime.respond(
            to: request(
                workflow: .recallPractice,
                question: "只根据当前内容出 2 道复习题，并给出带来源的答案。",
                revision: "pi-check-recall"
            )
        )
        guard reply.backend == .pi,
              reply.noteProposal == nil,
              reply.text.contains("？") || reply.text.contains("?"),
              containsSourceLabel(reply.text) else {
            throw PiCheckError.invalidEvaluation("recall-practice")
        }
    }

    private static func request(
        workflow: StudyAgentWorkflow,
        question: String,
        revision: String
    ) -> StudyAgentRequest {
        StudyAgentRequest(
            purpose: .conversation,
            workflow: workflow,
            question: question,
            materialTitle: "利率课程",
            materialText: "利率是资金使用价格的表达。名义利率以货币单位表示，实际利率扣除了通货膨胀后的购买力变化。在课程的近似计算中：实际利率 = 名义利率 - 通货膨胀率。",
            noteTitle: "课堂笔记",
            noteText: "# 利率\n\n## 待整理",
            selectionTitle: "利率定义",
            selectionText: "利率是资金使用价格的表达。",
            courseContext: StudyAgentCourseContext(
                title: "货币金融学",
                items: [
                    StudyAgentCourseItem(
                        id: "material-rates",
                        title: "利率课程",
                        subtitle: "利率讲义",
                        kind: "html",
                        role: "material",
                        isCurrentMaterial: true,
                        linkedItemIDs: ["note-rates"],
                        headings: ["利率的含义", "名义利率与实际利率"],
                        searchText: "利率是资金使用价格的表达。实际利率会扣除通货膨胀对购买力的影响。在课程的近似计算中：实际利率 = 名义利率 - 通货膨胀率。"
                    ),
                    StudyAgentCourseItem(
                        id: "material-inflation",
                        title: "通货膨胀补充材料",
                        subtitle: "PDF 第 4 章",
                        kind: "pdf",
                        role: "material",
                        headings: ["第 4 页", "购买力与实际利率"],
                        searchText: "通货膨胀会改变货币购买力，区分名义利率与实际利率时需要考虑通货膨胀。"
                    ),
                    StudyAgentCourseItem(
                        id: "note-rates",
                        title: "利率笔记",
                        subtitle: "Markdown",
                        kind: "markdown",
                        role: "note",
                        isCurrentNote: true,
                        linkedItemIDs: ["material-rates"],
                        headings: ["核心要点"],
                        searchText: "名义利率与实际利率的区别还需要复习。"
                    ),
                ],
                relations: [
                    StudyAgentCourseRelation(noteItemID: "note-rates", sourceItemID: "material-rates"),
                ]
            ),
            learningContext: StudyAgentLearningContext(
                memoryRevision: 3,
                lastLocation: StudyLocation(
                    itemID: "material-rates",
                    itemTitle: "利率课程",
                    locationTitle: "期限结构",
                    pageIndex: 11
                ),
                memories: [
                    LearningMemoryEntry(
                        kind: .confusion,
                        text: "还不能稳定区分名义利率与实际利率",
                        evidence: "[用户：本轮] 用户上次明确说这个区别还没掌握",
                        origin: .userStatement
                    ),
                ],
                session: StudyAgentSessionSnapshot(
                    id: "pi-check-session",
                    title: "利率复习",
                    summary: "上次学到期限结构，实际利率与通货膨胀的关系还需要复习。",
                    phase: StudyPhase.recall.rawValue,
                    focusItemIDs: ["material-rates", "note-rates"],
                    turnCount: 6
                )
            ),
            language: .chinese,
            contextRevision: revision
        )
    }

    private static func containsSourceLabel(_ text: String) -> Bool {
        text.contains("[选区：")
            || text.contains("[材料：")
            || text.contains("[笔记：")
            || text.contains("[学习记录：")
            || text.contains("[学习记忆：")
    }

    private static func verifyNoPersistedTurnState(_ runtimeRoot: URL) throws {
        let fileManager = FileManager.default
        let contextURL = runtimeRoot.appendingPathComponent("context.json")
        let sessionsURL = runtimeRoot.appendingPathComponent("Sessions", isDirectory: true)
        let sessionEntries = (try? fileManager.contentsOfDirectory(atPath: sessionsURL.path)) ?? []
        guard !fileManager.fileExists(atPath: contextURL.path), sessionEntries.isEmpty else {
            throw PiCheckError.persistedTurnState
        }
    }
}

private enum PiCheckError: LocalizedError {
    case invalidLiveReply
    case invalidEvaluation(String)
    case missingIsolatedConfiguration
    case persistedTurnState

    var errorDescription: String? {
        switch self {
        case .invalidLiveReply:
            "PI returned no revision-matched note proposal"
        case let .invalidEvaluation(name):
            "PI evaluation failed: \(name)"
        case .missingIsolatedConfiguration:
            "PI did not use an isolated WeiBei configuration directory"
        case .persistedTurnState:
            "PI persisted a context snapshot or session after the turn"
        }
    }
}
