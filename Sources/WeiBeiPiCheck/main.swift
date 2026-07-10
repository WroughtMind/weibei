import Darwin
import Foundation
import WeiBeiCore

@main
struct WeiBeiPiCheck {
    static func main() async {
        let environment = ProcessInfo.processInfo.environment
        let liveCheckSetting = environment["WEIBEI_PI_LIVE_CHECK"] ?? "auto"
        let runsEvaluation = environment["WEIBEI_PI_EVAL"] == "1"
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
            if runsEvaluation {
                try await checkCloseReading(runtime)
                try await checkRecallPractice(runtime)
                print("pi-eval passed: close-reading, note-making, recall-practice")
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
            materialText: "利率是资金使用价格的表达。名义利率以货币单位表示，实际利率扣除了通货膨胀后的购买力变化。",
            noteTitle: "课堂笔记",
            noteText: "# 利率\n\n## 待整理",
            selectionTitle: "利率定义",
            selectionText: "利率是资金使用价格的表达。",
            language: .chinese,
            contextRevision: revision
        )
    }

    private static func containsSourceLabel(_ text: String) -> Bool {
        text.contains("[选区：") || text.contains("[材料：") || text.contains("[笔记：")
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
