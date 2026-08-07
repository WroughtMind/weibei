import Darwin
import CryptoKit
import Foundation
import WeiBeiCore

enum RichAnswerEvidenceCommandLine {
    static let helpText = """
    WeiBeiPiCheck 富回答证据留档 CLI

    常用：
      --rich-answer-evidence                 启用真实 Pi 富回答证据运行
      --rich-answer-evidence-plan            只打印本次选择，不调用模型
      --list-rich-answer-cases               列出 40+6+9+1 全矩阵
      --run-id <id>                          指定留档 runID
      --case <id> / --cases <id,id>          选择单题或多题
      --filter <group> / --group <group>     按 rich/text-only/degradation/invalid/t1/t2/学科/能力过滤
      --repetitions <1-4|1,2,3,4>            显式指定重复轮次；默认只跑第 1 轮
      --thinking <level>                     仅为本次证据运行设置 Pi 思考级别，不修改全局配置
      --resume                               已有 passed 记录则断点跳过，不覆盖原始记录
      --evidence-dir <path>                  指定证据根目录
      --offset <n> --limit <n>               分片运行
      --continue-on-failure                  失败后继续留档
      --repair-note <text> --retest-of <id>  标记修复复测来源
      --merge-runs <id,id>                   只读合并多个 shard run，不调用模型
      --merged-run-id <id>                   指定聚合输出 runID
      --screenshot-manifest <path>           连接真实魏碑窗口截图清单并生成逐题验收包
    """

    static func mergedEnvironment(
        arguments: [String],
        base: [String: String]
    ) throws -> [String: String] {
        var environment = base
        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            if let parsed = split(argument) {
                try apply(option: parsed.option, value: parsed.value, environment: &environment)
                index += 1
                continue
            }

            switch argument {
            case "--rich-answer-evidence", "--rich-answer-check":
                environment["WEIBEI_PI_RICH_ANSWER_CHECK"] = "1"
            case "--resume", "--rich-answer-resume":
                environment["WEIBEI_PI_RICH_ANSWER_RESUME"] = "1"
            case "--continue-on-failure", "--rich-answer-continue-on-failure":
                environment["WEIBEI_PI_RICH_ANSWER_CONTINUE_ON_FAILURE"] = "1"
            case "--no-evidence", "--rich-answer-no-evidence":
                environment["WEIBEI_PI_RICH_ANSWER_EVIDENCE"] = "0"
            case "--case", "--cases", "--rich-answer-case", "--rich-answer-cases",
                 "--filter", "--group", "--rich-answer-filter",
                 "--run-id", "--rich-answer-run-id",
                 "--repetition", "--repetitions", "--rich-answer-repetition", "--rich-answer-repetitions",
                 "--thinking", "--thinking-level", "--pi-thinking",
                 "--offset", "--rich-answer-offset",
                 "--limit", "--rich-answer-limit",
                 "--evidence-dir", "--rich-answer-evidence-dir",
                 "--repair-note", "--rich-answer-repair-note",
                 "--retest-of", "--rich-answer-retest-of",
                 "--merge-runs", "--rich-answer-merge-runs",
                 "--merged-run-id", "--rich-answer-merged-run-id",
                 "--screenshot-manifest", "--rich-answer-screenshot-manifest":
                guard index + 1 < arguments.count else {
                    throw RichAnswerEvidenceError.invalidConfiguration("missing value for \(argument)")
                }
                try apply(option: argument, value: arguments[index + 1], environment: &environment)
                index += 1
            default:
                break
            }
            index += 1
        }
        return environment
    }

    private static func split(_ argument: String) -> (option: String, value: String)? {
        guard argument.hasPrefix("--"),
              let separator = argument.firstIndex(of: "=") else {
            return nil
        }
        let option = String(argument[..<separator])
        let value = String(argument[argument.index(after: separator)...])
        return (option, value)
    }

    private static func apply(
        option: String,
        value: String,
        environment: inout [String: String]
    ) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw RichAnswerEvidenceError.invalidConfiguration("empty value for \(option)")
        }

        switch option {
        case "--case", "--cases", "--rich-answer-case", "--rich-answer-cases":
            append(trimmed, to: "WEIBEI_PI_RICH_ANSWER_CASES", environment: &environment)
        case "--filter", "--group", "--rich-answer-filter":
            append(trimmed, to: "WEIBEI_PI_RICH_ANSWER_FILTER", environment: &environment)
        case "--run-id", "--rich-answer-run-id":
            environment["WEIBEI_PI_RICH_ANSWER_RUN_ID"] = trimmed
        case "--repetition", "--rich-answer-repetition":
            environment["WEIBEI_PI_RICH_ANSWER_REPETITION"] = trimmed
        case "--repetitions", "--rich-answer-repetitions":
            environment["WEIBEI_PI_RICH_ANSWER_REPETITIONS"] = trimmed
        case "--thinking", "--thinking-level", "--pi-thinking":
            environment["WEIBEI_PI_THINKING_LEVEL"] = trimmed
        case "--offset", "--rich-answer-offset":
            environment["WEIBEI_PI_RICH_ANSWER_OFFSET"] = trimmed
        case "--limit", "--rich-answer-limit":
            environment["WEIBEI_PI_RICH_ANSWER_LIMIT"] = trimmed
        case "--evidence-dir", "--rich-answer-evidence-dir":
            environment["WEIBEI_PI_RICH_ANSWER_EVIDENCE_DIR"] = trimmed
        case "--repair-note", "--rich-answer-repair-note":
            environment["WEIBEI_PI_RICH_ANSWER_REPAIR_NOTE"] = trimmed
        case "--retest-of", "--rich-answer-retest-of":
            environment["WEIBEI_PI_RICH_ANSWER_RETEST_OF"] = trimmed
        case "--merge-runs", "--rich-answer-merge-runs":
            append(trimmed, to: "WEIBEI_PI_RICH_ANSWER_MERGE_RUNS", environment: &environment)
        case "--merged-run-id", "--rich-answer-merged-run-id":
            environment["WEIBEI_PI_RICH_ANSWER_MERGED_RUN_ID"] = trimmed
        case "--screenshot-manifest", "--rich-answer-screenshot-manifest":
            environment["WEIBEI_PI_RICH_ANSWER_SCREENSHOT_MANIFEST"] = trimmed
        default:
            break
        }
    }

    private static func append(
        _ value: String,
        to key: String,
        environment: inout [String: String]
    ) {
        let existing = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        environment[key] = existing.isEmpty ? value : "\(existing),\(value)"
    }
}

struct RichAnswerEvidenceRunConfiguration {
    let runID: String
    let rootURL: URL
    let repetitions: [Int]
    let requestedIDs: Set<String>
    let filters: Set<String>
    let offset: Int?
    let limit: Int?
    let resume: Bool
    let evidenceEnabled: Bool
    let continueAfterFailure: Bool
    let repairNote: String?
    let retestOfRunID: String?
    let thinkingLevel: String?
    let sourceHash: String
    let matrixHash: String

    init(environment: [String: String]) throws {
        let generatedRunID = Self.timestampRunID()
        runID = Self.safePathComponent(environment["WEIBEI_PI_RICH_ANSWER_RUN_ID"] ?? generatedRunID)

        let basePath = environment["WEIBEI_PI_RICH_ANSWER_EVIDENCE_DIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL = URL(fileURLWithPath: basePath?.isEmpty == false
            ? basePath!
            : "\(FileManager.default.currentDirectoryPath)/.build/rich-answer-evidence")
        rootURL = baseURL.appendingPathComponent(runID, isDirectory: true)

        repetitions = try Self.parseRepetitions(
            environment["WEIBEI_PI_RICH_ANSWER_REPETITIONS"]
                ?? environment["WEIBEI_PI_RICH_ANSWER_REPETITION"]
                ?? "1"
        )
        requestedIDs = Set(Self.parseList(environment["WEIBEI_PI_RICH_ANSWER_CASES"]))
        filters = Set(Self.parseList(environment["WEIBEI_PI_RICH_ANSWER_FILTER"]).map {
            $0.lowercased()
        })
        offset = environment["WEIBEI_PI_RICH_ANSWER_OFFSET"].flatMap(Int.init).flatMap {
            $0 > 0 ? $0 : nil
        }
        limit = environment["WEIBEI_PI_RICH_ANSWER_LIMIT"].flatMap(Int.init).flatMap {
            $0 >= 0 ? $0 : nil
        }
        resume = environment["WEIBEI_PI_RICH_ANSWER_RESUME"] == "1"
        evidenceEnabled = environment["WEIBEI_PI_RICH_ANSWER_EVIDENCE"] != "0"
        continueAfterFailure = environment["WEIBEI_PI_RICH_ANSWER_CONTINUE_ON_FAILURE"] == "1"
            || evidenceEnabled
        repairNote = Self.nonEmpty(environment["WEIBEI_PI_RICH_ANSWER_REPAIR_NOTE"])
        retestOfRunID = Self.nonEmpty(environment["WEIBEI_PI_RICH_ANSWER_RETEST_OF"])
        thinkingLevel = Self.nonEmpty(environment["WEIBEI_PI_THINKING_LEVEL"])
        if let thinkingLevel,
           !["off", "minimal", "low", "medium", "high", "xhigh"].contains(thinkingLevel.lowercased()) {
            throw RichAnswerEvidenceError.invalidConfiguration("invalid Pi thinking level: \(thinkingLevel)")
        }
        sourceHash = try Self.computeSourceHash()
        matrixHash = try Self.computeMatrixHash()
        try RichAnswerEvidenceModelProofSnapshot.assertBackendProviderSeparationSelfCheck()
    }

    var runDescription: String {
        "\(runID) repetitions=\(repetitions.map(String.init).joined(separator: ",")) thinking=\(thinkingLevel ?? "medium") root=\(rootURL.path)"
    }

    var piProviderConfiguration: PiAgentProviderConfiguration {
        PiAgentProviderConfiguration(thinkingLevel: thinkingLevel ?? "medium")
    }

    private static func parseList(_ rawValue: String?) -> [String] {
        (rawValue ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func parseRepetitions(_ rawValue: String) throws -> [Int] {
        let tokens = parseList(rawValue)
        let parsedTokens = tokens.isEmpty ? ["1"] : tokens
        var repetitions: [Int] = []
        for token in parsedTokens {
            if token.contains("-") {
                let parts = token.split(separator: "-", maxSplits: 1).compactMap {
                    Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                guard parts.count == 2, parts[0] > 0, parts[1] >= parts[0] else {
                    throw RichAnswerEvidenceError.invalidConfiguration("invalid repetition range: \(token)")
                }
                repetitions.append(contentsOf: parts[0]...parts[1])
            } else if let value = Int(token), value > 0 {
                repetitions.append(value)
            } else {
                throw RichAnswerEvidenceError.invalidConfiguration("invalid repetition: \(token)")
            }
        }
        let unique = Array(Set(repetitions)).sorted()
        guard !unique.isEmpty else {
            throw RichAnswerEvidenceError.invalidConfiguration("rich-answer repetitions cannot be empty")
        }
        return unique
    }

    private static func timestampRunID() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withDashSeparatorInDate,
            .withColonSeparatorInTime,
            .withFractionalSeconds,
        ]
        return "rich-answer-\(formatter.string(from: Date()))-\(UUID().uuidString.lowercased())"
    }

    static func safePathComponent(_ rawValue: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = rawValue.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let result = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return result.isEmpty ? timestampRunID() : result
    }

    private static func nonEmpty(_ rawValue: String?) -> String? {
        let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    static func promptHash(for runCase: RichAnswerLiveRunCase) throws -> String {
        try sha256(
            of: encodeForHash(
                RichAnswerEvidencePromptHashSnapshot(runCase: runCase)
            )
        )
    }

    private static func computeMatrixHash() throws -> String {
        try sha256(
            of: encodeForHash(
                RichAnswerLiveCases.fullMatrixRuns.map { RichAnswerEvidenceCaseSnapshot($0) }
            )
        )
    }

    private static func computeSourceHash() throws -> String {
        let repositoryRoot = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let sourceRoots = [
            "Sources/WeiBei",
            "Sources/WeiBeiCore",
            "Sources/WeiBeiPiCheck",
            "Prototypes/RichAnswerWebRuntime/src",
            "script",
        ]
        let allowedExtensions: Set<String> = [
            "swift",
            "ts",
            "tsx",
            "js",
            "jsx",
            "css",
            "html",
            "sh",
            "md",
        ]
        var candidates: [(relativePath: String, url: URL)] = []
        for sourceRoot in sourceRoots {
            let sourceRootURL = repositoryRoot.appendingPathComponent(sourceRoot, isDirectory: true)
            guard FileManager.default.fileExists(atPath: sourceRootURL.path),
                  let enumerator = FileManager.default.enumerator(
                      at: sourceRootURL,
                      includingPropertiesForKeys: [.isRegularFileKey],
                      options: [.skipsHiddenFiles, .skipsPackageDescendants]
                  ) else {
                continue
            }
            for case let url as URL in enumerator {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey])
                guard values.isRegularFile == true,
                      allowedExtensions.contains(url.pathExtension.lowercased()) else {
                    continue
                }
                let rootPath = repositoryRoot.standardizedFileURL.path
                let path = url.standardizedFileURL.path
                guard path.hasPrefix(rootPath + "/") else { continue }
                candidates.append((String(path.dropFirst(rootPath.count + 1)), url))
            }
        }

        var hasher = SHA256()
        for candidate in candidates.sorted(by: { $0.relativePath < $1.relativePath }) {
            hasher.update(data: Data(candidate.relativePath.utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: try Data(contentsOf: candidate.url))
            hasher.update(data: Data([255]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func encodeForHash<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

final class RichAnswerEvidenceRecorder {
    let configuration: RichAnswerEvidenceRunConfiguration
    private var indexEntries: [RichAnswerEvidenceIndexEntry] = []
    private var runLock: RichAnswerEvidenceRunLock?
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    init(configuration: RichAnswerEvidenceRunConfiguration) throws {
        self.configuration = configuration
        guard configuration.evidenceEnabled else { return }
        try fileManager.createDirectory(
            at: configuration.rootURL,
            withIntermediateDirectories: true
        )
        runLock = try RichAnswerEvidenceRunLock(rootURL: configuration.rootURL, runID: configuration.runID)
        try write(
            RichAnswerEvidenceRunMetadata(
                schemaVersion: 1,
                runID: configuration.runID,
                createdAt: Self.timestamp(),
                repetitions: configuration.repetitions,
                filters: Array(configuration.filters).sorted(),
                requestedIDs: Array(configuration.requestedIDs).sorted(),
                resume: configuration.resume,
                continueAfterFailure: configuration.continueAfterFailure,
                repairNote: configuration.repairNote,
                retestOfRunID: configuration.retestOfRunID,
                sourceHash: configuration.sourceHash,
                matrixHash: configuration.matrixHash,
                rootPath: configuration.rootURL.path
            ),
            to: configuration.rootURL.appendingPathComponent("run.json")
        )
    }

    func caseDirectory(
        repetition: Int,
        runCase: RichAnswerLiveRunCase
    ) -> URL {
        configuration.rootURL
            .appendingPathComponent(Self.repetitionDirectoryName(repetition), isDirectory: true)
            .appendingPathComponent(RichAnswerEvidenceRunConfiguration.safePathComponent(runCase.id), isDirectory: true)
    }

    func hasPassingRecord(
        repetition: Int,
        runCase: RichAnswerLiveRunCase
    ) -> Bool {
        guard configuration.evidenceEnabled else { return false }
        let directory = caseDirectory(repetition: repetition, runCase: runCase)
        let recordURL = directory.appendingPathComponent("record.json")
        let manifestURL = directory.appendingPathComponent("evidence-manifest.json")
        guard let runMetadata = try? readRunMetadata(),
              runMetadata.runID == configuration.runID,
              runMetadata.sourceHash == configuration.sourceHash,
              runMetadata.matrixHash == configuration.matrixHash,
              let currentPromptHash = try? RichAnswerEvidenceRunConfiguration.promptHash(for: runCase) else {
            return false
        }
        guard let data = try? Data(contentsOf: recordURL),
              let probe = try? JSONDecoder().decode(RichAnswerEvidenceResumeProbe.self, from: data),
              let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(RichAnswerEvidenceArtifactManifest.self, from: manifestData) else {
            return false
        }
        guard probe.status == "passed",
              probe.runID == configuration.runID,
              probe.repetition == repetition,
              probe.caseSnapshot.id == runCase.id,
              probe.caseSnapshot.caseKind == runCase.caseKind,
              probe.fixtureInvocation == false,
              probe.traceability.runID == configuration.runID,
              probe.traceability.sourceHash == configuration.sourceHash,
              probe.traceability.matrixHash == configuration.matrixHash,
              probe.traceability.promptHash == currentPromptHash,
              manifest.runID == configuration.runID,
              manifest.caseID == runCase.id,
              manifest.caseKind == runCase.caseKind,
              manifest.repetition == repetition,
              manifest.status == "passed" else {
            return false
        }
        if runCase.invokesModel {
            guard probe.modelInvocation == true,
                  probe.traceability.modelProof.trustedModelInvocation == true,
                  probe.traceability.modelProof.fixtureInvocation == false,
                  Self.nonEmpty(probe.traceability.modelProof.backend) == "pi",
                  Self.nonEmpty(probe.traceability.modelProof.provider) != nil,
                  Self.nonEmpty(probe.traceability.modelProof.model) != nil,
                  Self.nonEmpty(probe.traceability.modelProof.requestID) != nil,
                  !probe.traceability.modelProof.nonFixtureEvidence.isEmpty,
                  probe.modelRawReply?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                return false
            }
        } else {
            guard probe.modelInvocation == false else { return false }
        }
        return evidenceManifestIsComplete(manifest, in: directory, requiresModelText: runCase.invokesModel)
    }

    func recordSkipped(
        repetition: Int,
        sequence: Int,
        total: Int,
        runCase: RichAnswerLiveRunCase
    ) throws {
        guard configuration.evidenceEnabled else { return }
        let directory = caseDirectory(repetition: repetition, runCase: runCase)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let record = RichAnswerEvidenceRecord(
            schemaVersion: 1,
            runID: configuration.runID,
            repetition: repetition,
            sequence: sequence,
            totalSelectedCases: total,
            caseSnapshot: .init(runCase),
            startedAt: Self.timestamp(),
            finishedAt: Self.timestamp(),
            elapsedSeconds: 0,
            status: "skipped",
            modelInvocation: false,
            fixtureInvocation: false,
            promptAndMaterial: nil,
            modelRawReply: nil,
            shapeDecision: .skipped(runCase),
            expressionPlan: .empty,
            toolAndProtocolValidation: .skipped(reason: "resume found an existing passed record"),
            sourceBinding: .empty,
            expertObservation: .init(runCase: runCase, reply: nil),
            traceability: try traceabilitySnapshot(
                runCase: runCase,
                request: nil,
                reply: nil
            ),
            failureReason: nil,
            repairAndRetest: repairSnapshot(previousStatus: "passed")
        )
        let skipURL = directory.appendingPathComponent("resume-skip-\(Self.safeTimestampForFilename()).json")
        try write(record, to: skipURL)
        try writePlainText(
            caseMarkdown(record, recordPath: relativePath(skipURL)),
            to: directory.appendingPathComponent(skipURL.deletingPathExtension().lastPathComponent + ".md")
        )
        indexEntries.append(
            RichAnswerEvidenceIndexEntry(
                runID: record.runID,
                repetition: record.repetition,
                sequence: record.sequence,
                caseID: record.caseSnapshot.id,
                caseKind: record.caseSnapshot.caseKind,
                subject: record.caseSnapshot.subject,
                status: record.status,
                elapsedSeconds: record.elapsedSeconds,
                actualShape: record.shapeDecision.actualShape,
                recordPath: relativePath(skipURL),
                failureReason: nil
            )
        )
    }

    func recordResult(
        repetition: Int,
        sequence: Int,
        total: Int,
        runCase: RichAnswerLiveRunCase,
        request: StudyAgentRequest?,
        reply: StudyAgentReply?,
        startedAt: Date,
        elapsedSeconds: TimeInterval,
        validation: RichAnswerEvidenceValidationSnapshot,
        failureReason: String?
    ) throws {
        guard configuration.evidenceEnabled else { return }
        let directory = caseDirectory(repetition: repetition, runCase: runCase)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let previousStatus = previousStatus(in: directory)
        let promptSnapshot = request.map(RichAnswerEvidencePromptSnapshot.init)
        let replySnapshot = reply.map(RichAnswerEvidenceReplySnapshot.init)
        let traceability = try traceabilitySnapshot(
            runCase: runCase,
            request: promptSnapshot,
            reply: replySnapshot
        )
        let caseSnapshot = RichAnswerEvidenceCaseSnapshot(runCase, request: request)
        let objectiveIssues = Self.objectiveRenderPlanEvidenceIssues(
            caseSnapshot: caseSnapshot,
            reply: reply
        )
        let finalValidation = validation.checkedAgainstModelProof(
            traceability.modelProof,
            requiresModel: runCase.invokesModel
        ).checkedAgainstObjectiveEvidenceIssues(
            objectiveIssues
        )
        let modelProofFailureReason = Self.failureReason(
            existing: failureReason,
            proof: traceability.modelProof,
            requiresModel: runCase.invokesModel
        )
        let finalFailureReason = Self.failureReason(
            existing: modelProofFailureReason,
            objectiveIssues: objectiveIssues
        )
        let expertObservation = RichAnswerEvidenceExpertObservationSnapshot(
            runCase: runCase,
            reply: reply
        )
        let record = RichAnswerEvidenceRecord(
            schemaVersion: 1,
            runID: configuration.runID,
            repetition: repetition,
            sequence: sequence,
            totalSelectedCases: total,
            caseSnapshot: caseSnapshot,
            startedAt: Self.timestamp(startedAt),
            finishedAt: Self.timestamp(),
            elapsedSeconds: elapsedSeconds,
            status: finalValidation.status,
            modelInvocation: traceability.modelProof.trustedModelInvocation,
            fixtureInvocation: traceability.modelProof.fixtureInvocation,
            promptAndMaterial: promptSnapshot,
            modelRawReply: replySnapshot,
            shapeDecision: RichAnswerEvidenceShapeDecision(runCase: runCase, reply: reply),
            expressionPlan: RichAnswerEvidenceExpressionSnapshot(reply: reply),
            toolAndProtocolValidation: finalValidation,
            sourceBinding: RichAnswerEvidenceSourceBinding(runCase: runCase, reply: reply),
            expertObservation: expertObservation,
            traceability: traceability,
            failureReason: finalFailureReason,
            repairAndRetest: repairSnapshot(previousStatus: previousStatus)
        )
        try persist(record, directory: directory, validation: finalValidation)
    }

    func finishIndex() throws {
        guard configuration.evidenceEnabled else { return }
        let statusCounts = Dictionary(grouping: indexEntries, by: \.status).mapValues(\.count)
        let index = RichAnswerEvidenceRunIndex(
            schemaVersion: 1,
            runID: configuration.runID,
            updatedAt: Self.timestamp(),
            rootPath: configuration.rootURL.path,
            totalRecords: indexEntries.count,
            statusCounts: statusCounts,
            records: indexEntries
        )
        try write(index, to: configuration.rootURL.appendingPathComponent("index.json"))
        try writePlainText(indexMarkdown(index), to: configuration.rootURL.appendingPathComponent("index.md"))
        try writePlainText(indexHTML(index), to: configuration.rootURL.appendingPathComponent("index.html"))
    }

    private func persist(
        _ record: RichAnswerEvidenceRecord,
        directory: URL,
        validation: RichAnswerEvidenceValidationSnapshot
    ) throws {
        let recordURL = directory.appendingPathComponent("record.json")
        let requestURL = directory.appendingPathComponent("request.json")
        let replyURL = directory.appendingPathComponent("reply.json")
        let validationURL = directory.appendingPathComponent("validation.json")
        let modelResponseURL = directory.appendingPathComponent("model-response.txt")
        try write(record, to: recordURL)
        try write(record.promptAndMaterial, to: requestURL)
        try write(record.modelRawReply, to: replyURL)
        try write(validation, to: validationURL)
        try writePlainText(record.modelRawReply?.text ?? "", to: modelResponseURL)
        let artifactURLs = [
            recordURL,
            requestURL,
            replyURL,
            validationURL,
            modelResponseURL,
        ]
        let artifactManifest = try RichAnswerEvidenceArtifactManifest(
            generatedAt: Self.timestamp(),
            record: record,
            artifacts: artifactURLs.map { url in
                try RichAnswerEvidenceArtifactHash(
                    path: url.lastPathComponent,
                    url: url
                )
            }
        )
        try write(artifactManifest, to: directory.appendingPathComponent("evidence-manifest.json"))
        let attemptName = "attempt-\(Self.safeTimestampForFilename()).json"
        try write(record, to: directory.appendingPathComponent(attemptName))
        try writePlainText(
            caseMarkdown(record, recordPath: relativePath(directory.appendingPathComponent("record.json"))),
            to: directory.appendingPathComponent("summary.md")
        )
        indexEntries.append(
            RichAnswerEvidenceIndexEntry(
                runID: record.runID,
                repetition: record.repetition,
                sequence: record.sequence,
                caseID: record.caseSnapshot.id,
                caseKind: record.caseSnapshot.caseKind,
                subject: record.caseSnapshot.subject,
                status: record.status,
                elapsedSeconds: record.elapsedSeconds,
                actualShape: record.shapeDecision.actualShape,
                recordPath: relativePath(directory.appendingPathComponent("record.json")),
                failureReason: record.failureReason
            )
        )
    }

    private func evidenceManifestIsComplete(
        _ manifest: RichAnswerEvidenceArtifactManifest,
        in directory: URL,
        requiresModelText: Bool
    ) -> Bool {
        let requiredPaths = Set([
            "record.json",
            "request.json",
            "reply.json",
            "validation.json",
            "model-response.txt",
        ])
        var artifactsByPath: [String: RichAnswerEvidenceArtifactHash] = [:]
        for artifact in manifest.artifacts {
            guard artifactsByPath[artifact.path] == nil else { return false }
            artifactsByPath[artifact.path] = artifact
        }
        guard Set(artifactsByPath.keys).isSuperset(of: requiredPaths) else { return false }
        for path in requiredPaths {
            guard let artifact = artifactsByPath[path] else { return false }
            let url = directory.appendingPathComponent(path)
            guard fileManager.fileExists(atPath: url.path),
                  (try? Self.sha256(of: url)) == artifact.sha256,
                  (try? Self.byteCount(of: url)) == artifact.byteCount else {
                return false
            }
        }
        if requiresModelText {
            let modelTextURL = directory.appendingPathComponent("model-response.txt")
            guard let text = try? String(contentsOf: modelTextURL, encoding: .utf8),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }
        }
        return true
    }

    private func traceabilitySnapshot(
        runCase: RichAnswerLiveRunCase,
        request: RichAnswerEvidencePromptSnapshot?,
        reply: RichAnswerEvidenceReplySnapshot?
    ) throws -> RichAnswerEvidenceTraceabilitySnapshot {
        try RichAnswerEvidenceTraceabilitySnapshot(
            runID: configuration.runID,
            sourceHash: configuration.sourceHash,
            matrixHash: configuration.matrixHash,
            promptHash: RichAnswerEvidenceRunConfiguration.promptHash(for: runCase),
            modelProof: RichAnswerEvidenceModelProofSnapshot(
                runCase: runCase,
                request: request,
                reply: reply
            )
        )
    }

    private func readRunMetadata() throws -> RichAnswerEvidenceRunMetadata {
        let data = try Data(contentsOf: configuration.rootURL.appendingPathComponent("run.json"))
        return try JSONDecoder().decode(RichAnswerEvidenceRunMetadata.self, from: data)
    }

    private static func failureReason(
        existing: String?,
        proof: RichAnswerEvidenceModelProofSnapshot,
        requiresModel: Bool
    ) -> String? {
        guard requiresModel, proof.trustedModelInvocation == false else { return existing }
        let proofReason = "model proof failed: \(proof.issues.joined(separator: "; "))"
        guard let existing = nonEmpty(existing) else { return proofReason }
        return "\(existing) | \(proofReason)"
    }

    private static func failureReason(
        existing: String?,
        objectiveIssues: [String]
    ) -> String? {
        guard !objectiveIssues.isEmpty else { return existing }
        let objectiveReason = "objective renderPlan evidence check failed: \(objectiveIssues.joined(separator: "; "))"
        guard let existing = nonEmpty(existing) else { return objectiveReason }
        return "\(existing) | \(objectiveReason)"
    }

    private static func objectiveRenderPlanEvidenceIssues(
        caseSnapshot: RichAnswerEvidenceCaseSnapshot,
        reply: StudyAgentReply?
    ) -> [String] {
        guard let presentation = reply?.richAnswer else { return [] }
        var issues: [String] = []
        for scene in presentation.scenes {
            guard let plan = scene.renderPlan else { continue }
            let scenePrefix = "scene \(scene.id) renderPlan"
            if nonEmpty(plan.renderer) == nil {
                issues.append("\(scenePrefix) missing renderer")
            }
            if plan.spec.fields.isEmpty {
                issues.append("\(scenePrefix) missing spec")
            }
            let visualAssetRefs = visualAssetRefs(in: plan.spec.fields)
            for assetRef in visualAssetRefs {
                guard let source = nonEmpty(assetRef.source) else {
                    issues.append("\(scenePrefix) \(assetRef.path) assetRef source is empty")
                    continue
                }
                if source == caseSnapshot.materialItemID,
                   !isParseableVisualMaterialKind(caseSnapshot.materialKind) {
                    issues.append("\(scenePrefix) \(assetRef.path) uses materialItemID \(source) as a visual asset while materialKind is \(caseSnapshot.materialKind ?? "nil")")
                }
            }
        }
        return issues
    }

    private static func visualAssetRefs(
        in fields: [String: RichAnswerRenderSpecValue]
    ) -> [(path: String, source: String?)] {
        fields.flatMap { key, value in
            visualAssetRefs(in: value, path: "spec.\(key)", visualContext: isVisualAssetContext(key))
        }
    }

    private static func visualAssetRefs(
        in value: RichAnswerRenderSpecValue,
        path: String,
        visualContext: Bool
    ) -> [(path: String, source: String?)] {
        switch value {
        case .null, .bool, .number, .string:
            return []
        case let .array(items):
            return items.enumerated().flatMap { index, item in
                visualAssetRefs(in: item, path: "\(path)[\(index)]", visualContext: visualContext)
            }
        case let .object(object):
            if isAssetRefObject(object), visualContext {
                return [(path, stringField("source", in: object))]
            }
            return object.flatMap { key, child in
                visualAssetRefs(
                    in: child,
                    path: "\(path).\(key)",
                    visualContext: visualContext || isVisualAssetContext(key)
                )
            }
        }
    }

    private static func isAssetRefObject(_ object: [String: RichAnswerRenderSpecValue]) -> Bool {
        guard case let .string(kind)? = object["kind"] else { return false }
        return kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "assetref"
    }

    private static func stringField(
        _ key: String,
        in object: [String: RichAnswerRenderSpecValue]
    ) -> String? {
        guard case let .string(value)? = object[key] else { return nil }
        return value
    }

    private static func isVisualAssetContext(_ key: String) -> Bool {
        let normalizedKey = key
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalizedKey.contains("image") || normalizedKey.contains("map")
    }

    private static func isParseableVisualMaterialKind(_ materialKind: String?) -> Bool {
        guard let kind = nonEmpty(materialKind)?.lowercased() else { return false }
        return ["image", "pdf"].contains(kind)
    }

    private static func nonEmpty(_ rawValue: String?) -> String? {
        let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    private func repairSnapshot(previousStatus: String?) -> RichAnswerEvidenceRepairSnapshot {
        RichAnswerEvidenceRepairSnapshot(
            previousRunID: configuration.retestOfRunID,
            previousStatus: previousStatus,
            repairNote: configuration.repairNote,
            isRetest: configuration.retestOfRunID != nil
        )
    }

    private func previousStatus(in directory: URL) -> String? {
        let url = directory.appendingPathComponent("record.json")
        guard let data = try? Data(contentsOf: url),
              let status = try? JSONDecoder().decode(RichAnswerEvidenceStatusProbe.self, from: data) else {
            return nil
        }
        return status.status
    }

    private func write<Value: Encodable>(_ value: Value, to url: URL) throws {
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    private func writePlainText(_ value: String, to url: URL) throws {
        try value.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    private func relativePath(_ url: URL) -> String {
        let root = configuration.rootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(root + "/") else { return path }
        return String(path.dropFirst(root.count + 1))
    }

    private func caseMarkdown(
        _ record: RichAnswerEvidenceRecord,
        recordPath: String
    ) -> String {
        let prompt = record.promptAndMaterial
        let reply = record.modelRawReply
        let validation = record.toolAndProtocolValidation
        let source = record.sourceBinding
        let plan = record.expressionPlan
        return """
        # \(record.caseSnapshot.id)

        | 字段 | 值 |
        | --- | --- |
        | runID | \(record.runID) |
        | repetition | \(record.repetition) |
        | sequence | \(record.sequence)/\(record.totalSelectedCases) |
        | status | \(record.status) |
        | kind | \(record.caseSnapshot.caseKind) |
        | subject | \(record.caseSnapshot.subject) |
        | elapsedSeconds | \(String(format: "%.3f", record.elapsedSeconds)) |
        | expectedShape | \(record.shapeDecision.expectedShape) |
        | actualShape | \(record.shapeDecision.actualShape) |
        | T1 scenes | \(record.shapeDecision.t1SceneCount) |
        | T2 scenes | \(record.shapeDecision.t2SceneCount) |
        | renderPlan scenes | \(record.shapeDecision.renderPlanSceneCount ?? 0) |
        | record | \(recordPath) |

        ## 题目与材料

        **题目**：\(record.caseSnapshot.question)

        **材料标题**：\(prompt?.materialTitle ?? record.caseSnapshot.materialTitle ?? "无")

        **材料类型**：\(record.caseSnapshot.materialKind ?? "无")

        **材料正文**

        \(fenced(prompt?.materialText ?? record.caseSnapshot.materialText ?? "无"))

        **选区标题**：\(prompt?.selectionTitle ?? record.caseSnapshot.selectionTitle ?? "无")

        **选区正文**

        \(fenced(prompt?.selectionText ?? record.caseSnapshot.selectionText ?? "无"))

        ## 模型原始回答

        \(fenced(reply?.text ?? "无模型回复"))

        ## 专家观察（不作为运行时硬拒绝）

        - 策略：\(record.expertObservation.policy)
        - 期望文本组：\(record.expertObservation.expectedTextGroups.map { $0.joined(separator: "/") }.joined(separator: " | "))
        - 已命中文本组：\(record.expertObservation.matchedExpectedTextGroups.map { $0.joined(separator: "/") }.joined(separator: " | "))
        - 缺失文本组：\(record.expertObservation.missingExpectedTextGroups.map { $0.joined(separator: "/") }.joined(separator: " | "))
        - 命中完整度：\(record.expertObservation.satisfiedExpectedTextGroups)

        ## 形态判断

        - 预期：\(record.shapeDecision.expectedShape)
        - 实际：\(record.shapeDecision.actualShape)
        - 首选呈现：\(record.shapeDecision.preferredSurface ?? "无")
        - 直接操控：\(record.shapeDecision.directManipulation.map(String.init) ?? "无")
        - 叙述字数：\(record.shapeDecision.narrativeCharacterCount)

        ## T1/T2 表达计划

        - T1 程序数：\(plan.t1Programs.count)
        - T1 组件：\(plan.t1Programs.flatMap(\.componentNames).joined(separator: ", "))
        - T2 组合数：\(plan.t2Compositions.count)
        - T2 角色：\(plan.t2Compositions.flatMap(\.roles).joined(separator: ", "))
        - T2 数据行：\(plan.t2Compositions.map(\.dataRowCount).reduce(0, +))
        - T2 绑定：\(plan.t2Compositions.map(\.bindingCount).reduce(0, +))

        ## 协议校验

        - 类型：\(validation.validationKind)
        - 通过项：\(validation.passedChecks.joined(separator: ", "))
        - 问题：\(validation.issues.joined(separator: " | "))
        - 协议诊断：\(validation.protocolDiagnostics.joined(separator: " | "))

        ## 来源绑定

        - 文本来源：\(source.textSourceLabels.joined(separator: " | "))
        - 账本来源：\(source.evidenceLedgerLabels.joined(separator: " | "))
        - materialItemID：\(record.caseSnapshot.materialItemID ?? "无")
        - verificationAssetID：\(record.caseSnapshot.verificationAssetID ?? "无")
        - sourceFingerprint：\(record.caseSnapshot.sourceFingerprint ?? "无")
        - verificationAssetFingerprint：\(record.caseSnapshot.verificationAssetFingerprint ?? "无")
        - 证据状态：\(source.evidenceState ?? "无")
        - 场景证据：\(source.sceneEvidenceIDs.joined(separator: ", "))
        - 命中预期来源：\(source.hasExpectedSource)

        ## 真实模型证明与可追溯哈希

        - sourceHash：\(record.traceability.sourceHash)
        - matrixHash：\(record.traceability.matrixHash)
        - promptHash：\(record.traceability.promptHash)
        - backend：\(record.traceability.modelProof.backend ?? "无")
        - provider：\(record.traceability.modelProof.provider ?? "无")
        - model：\(record.traceability.modelProof.model ?? "无")
        - requestID：\(record.traceability.modelProof.requestID ?? "无")
        - 非 fixture 证据：\(record.traceability.modelProof.nonFixtureEvidence.joined(separator: " | "))
        - 证明问题：\(record.traceability.modelProof.issues.joined(separator: " | "))

        ## 失败与复测

        - 失败原因：\(record.failureReason ?? "无")
        - 上次 runID：\(record.repairAndRetest.previousRunID ?? "无")
        - 上次状态：\(record.repairAndRetest.previousStatus ?? "无")
        - 修复说明：\(record.repairAndRetest.repairNote ?? "无")
        - 是否复测：\(record.repairAndRetest.isRetest)

        ## 工具轨迹

        \(fenced(validation.toolTrace.joined(separator: "\n")))
        """
    }

    private func indexMarkdown(_ index: RichAnswerEvidenceRunIndex) -> String {
        let rows = index.records.map { entry in
            "| \(entry.repetition) | \(entry.sequence) | \(entry.caseKind) | \(entry.caseID) | \(entry.subject) | \(entry.status) | \(entry.actualShape) | \(String(format: "%.3f", entry.elapsedSeconds)) | [record](\(entry.recordPath)) |"
        }.joined(separator: "\n")
        return """
        # 富回答证据索引 \(index.runID)

        - root: \(index.rootPath)
        - updatedAt: \(index.updatedAt)
        - totalRecords: \(index.totalRecords)
        - statusCounts: \(index.statusCounts.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", "))

        | repetition | sequence | kind | case | subject | status | shape | seconds | record |
        | --- | ---: | --- | --- | --- | --- | --- | ---: | --- |
        \(rows)
        """
    }

    private func indexHTML(_ index: RichAnswerEvidenceRunIndex) -> String {
        let rows = index.records.map { entry in
            """
            <tr>
              <td>\(entry.repetition)</td>
              <td>\(entry.sequence)</td>
              <td>\(escapeHTML(entry.caseKind))</td>
              <td><a href="\(escapeHTML(entry.recordPath))">\(escapeHTML(entry.caseID))</a></td>
              <td>\(escapeHTML(entry.subject))</td>
              <td class="status-\(escapeHTML(entry.status))">\(escapeHTML(entry.status))</td>
              <td>\(escapeHTML(entry.actualShape))</td>
              <td>\(String(format: "%.3f", entry.elapsedSeconds))</td>
              <td>\(escapeHTML(entry.failureReason ?? ""))</td>
            </tr>
            """
        }.joined(separator: "\n")
        return """
        <!doctype html>
        <html lang="zh-CN">
        <head>
          <meta charset="utf-8">
          <title>富回答证据索引 \(escapeHTML(index.runID))</title>
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, "Songti SC", serif; margin: 32px; background: #f4efe4; color: #2d261f; }
            table { border-collapse: collapse; width: 100%; background: rgba(255,255,255,.42); }
            th, td { border-bottom: 1px solid #d8cebd; padding: 8px 10px; text-align: left; vertical-align: top; }
            th { background: rgba(83, 70, 52, .08); }
            a { color: #7f3f2d; }
            .status-passed { color: #2f6935; font-weight: 700; }
            .status-failed { color: #9b2f24; font-weight: 700; }
            .status-skipped { color: #766850; }
          </style>
        </head>
        <body>
          <h1>富回答证据索引</h1>
          <p><strong>runID</strong>: \(escapeHTML(index.runID))</p>
          <p><strong>root</strong>: \(escapeHTML(index.rootPath))</p>
          <p><strong>updatedAt</strong>: \(escapeHTML(index.updatedAt))</p>
          <p><strong>statusCounts</strong>: \(escapeHTML(index.statusCounts.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", ")))</p>
          <table>
            <thead><tr><th>轮次</th><th>序号</th><th>类型</th><th>题目</th><th>学科</th><th>状态</th><th>形态</th><th>耗时</th><th>失败原因</th></tr></thead>
            <tbody>
            \(rows)
            </tbody>
          </table>
        </body>
        </html>
        """
    }

    private func fenced(_ text: String) -> String {
        "```text\n\(text.replacingOccurrences(of: "```", with: "` ` `"))\n```"
    }

    private func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func repetitionDirectoryName(_ repetition: Int) -> String {
        "repetition-\(String(format: "%03d", repetition))"
    }

    private static func timestamp(_ date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func safeTimestampForFilename() -> String {
        timestamp()
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
    }

    fileprivate static func sha256(of url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    fileprivate static func byteCount(of url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? -1
    }
}

private final class RichAnswerEvidenceRunLock {
    private let lockURL: URL
    private var isHeld = false

    init(rootURL: URL, runID: String) throws {
        lockURL = rootURL.appendingPathComponent(".run.lock")
        let descriptor = open(lockURL.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            let owner = (try? String(contentsOf: lockURL, encoding: .utf8))
                .map { "\ncurrent lock:\n\($0)" } ?? ""
            throw RichAnswerEvidenceError.invalidConfiguration(
                "runID \(runID) is already being written; refusing concurrent evidence writes at \(lockURL.path)\(owner)"
            )
        }
        isHeld = true
        let payload = """
        runID=\(runID)
        pid=\(getpid())
        createdAt=\(Self.timestamp())
        """
        _ = payload.withCString { pointer in
            Darwin.write(descriptor, pointer, strlen(pointer))
        }
        close(descriptor)
    }

    deinit {
        release()
    }

    private func release() {
        guard isHeld else { return }
        try? FileManager.default.removeItem(at: lockURL)
        isHeld = false
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}

struct RichAnswerEvidenceValidationSnapshot: Codable {
    var status: String
    var validationKind: String
    var passedChecks: [String]
    var issues: [String]
    var toolTrace: [String]
    var protocolDiagnostics: [String]

    static func passed(
        kind: String,
        checks: [String],
        reply: StudyAgentReply?
    ) -> Self {
        Self(
            status: "passed",
            validationKind: kind,
            passedChecks: checks,
            issues: [],
            toolTrace: reply?.toolTrace ?? [],
            protocolDiagnostics: reply?.richAnswer?.diagnostics.map { "\($0.code.rawValue):\($0.message)" } ?? []
        )
    }

    static func failed(
        kind: String,
        error: Error,
        reply: StudyAgentReply?
    ) -> Self {
        Self(
            status: "failed",
            validationKind: kind,
            passedChecks: [],
            issues: [error.localizedDescription],
            toolTrace: reply?.toolTrace ?? [],
            protocolDiagnostics: reply?.richAnswer?.diagnostics.map { "\($0.code.rawValue):\($0.message)" } ?? []
        )
    }

    static func deterministicInvalidProtocolPassed() -> Self {
        Self(
            status: "passed",
            validationKind: "deterministic-invalid-protocol",
            passedChecks: ["runRichAnswerProtocolSelfCheck"],
            issues: [],
            toolTrace: [],
            protocolDiagnostics: []
        )
    }

    static func deterministicInvalidProtocolFailed(_ error: Error) -> Self {
        Self(
            status: "failed",
            validationKind: "deterministic-invalid-protocol",
            passedChecks: [],
            issues: [error.localizedDescription],
            toolTrace: [],
            protocolDiagnostics: []
        )
    }

    static func skipped(reason: String) -> Self {
        Self(
            status: "skipped",
            validationKind: "resume",
            passedChecks: [],
            issues: [reason],
            toolTrace: [],
            protocolDiagnostics: []
        )
    }

    fileprivate func checkedAgainstModelProof(
        _ proof: RichAnswerEvidenceModelProofSnapshot,
        requiresModel: Bool
    ) -> Self {
        guard requiresModel, proof.trustedModelInvocation == false else { return self }
        var updated = self
        updated.status = "failed"
        updated.issues.append(contentsOf: proof.issues.map { "model-proof:\($0)" })
        return updated
    }

    fileprivate func checkedAgainstObjectiveEvidenceIssues(_ issues: [String]) -> Self {
        guard !issues.isEmpty else { return self }
        var updated = self
        updated.status = "failed"
        updated.issues.append(contentsOf: issues.map { "objective-evidence:\($0)" })
        return updated
    }
}

private struct RichAnswerEvidenceRecord: Codable {
    var schemaVersion: Int
    var runID: String
    var repetition: Int
    var sequence: Int
    var totalSelectedCases: Int
    var caseSnapshot: RichAnswerEvidenceCaseSnapshot
    var startedAt: String
    var finishedAt: String
    var elapsedSeconds: TimeInterval
    var status: String
    var modelInvocation: Bool
    var fixtureInvocation: Bool
    var promptAndMaterial: RichAnswerEvidencePromptSnapshot?
    var modelRawReply: RichAnswerEvidenceReplySnapshot?
    var shapeDecision: RichAnswerEvidenceShapeDecision
    var expressionPlan: RichAnswerEvidenceExpressionSnapshot
    var toolAndProtocolValidation: RichAnswerEvidenceValidationSnapshot
    var sourceBinding: RichAnswerEvidenceSourceBinding
    var expertObservation: RichAnswerEvidenceExpertObservationSnapshot
    var traceability: RichAnswerEvidenceTraceabilitySnapshot
    var failureReason: String?
    var repairAndRetest: RichAnswerEvidenceRepairSnapshot
}

private struct RichAnswerEvidenceRunMetadata: Codable {
    var schemaVersion: Int
    var runID: String
    var createdAt: String
    var repetitions: [Int]
    var filters: [String]
    var requestedIDs: [String]
    var resume: Bool
    var continueAfterFailure: Bool
    var repairNote: String?
    var retestOfRunID: String?
    var sourceHash: String
    var matrixHash: String
    var rootPath: String
}

private struct RichAnswerEvidenceRunIndex: Codable {
    var schemaVersion: Int
    var runID: String
    var updatedAt: String
    var rootPath: String
    var totalRecords: Int
    var statusCounts: [String: Int]
    var records: [RichAnswerEvidenceIndexEntry]
}

private struct RichAnswerEvidenceIndexEntry: Codable {
    var runID: String
    var repetition: Int
    var sequence: Int
    var caseID: String
    var caseKind: String
    var subject: String
    var status: String
    var elapsedSeconds: TimeInterval
    var actualShape: String
    var recordPath: String
    var failureReason: String?
}

private struct RichAnswerEvidenceStatusProbe: Decodable {
    var status: String
}

private struct RichAnswerEvidenceResumeProbe: Decodable {
    var runID: String
    var repetition: Int
    var status: String
    var modelInvocation: Bool
    var fixtureInvocation: Bool
    var caseSnapshot: RichAnswerEvidenceResumeCaseSnapshot
    var modelRawReply: RichAnswerEvidenceResumeReplySnapshot?
    var traceability: RichAnswerEvidenceResumeTraceabilitySnapshot
}

private struct RichAnswerEvidenceResumeCaseSnapshot: Decodable {
    var id: String
    var caseKind: String
}

private struct RichAnswerEvidenceResumeReplySnapshot: Decodable {
    var text: String
}

private struct RichAnswerEvidenceResumeTraceabilitySnapshot: Decodable {
    var runID: String
    var sourceHash: String
    var matrixHash: String
    var promptHash: String
    var modelProof: RichAnswerEvidenceResumeModelProofSnapshot
}

private struct RichAnswerEvidenceResumeModelProofSnapshot: Decodable {
    var provider: String?
    var model: String?
    var requestID: String?
    var backend: String?
    var nonFixtureEvidence: [String]
    var trustedModelInvocation: Bool
    var fixtureInvocation: Bool
}

private struct RichAnswerEvidenceArtifactManifest: Codable {
    var schemaVersion: Int
    var generatedAt: String
    var runID: String
    var caseID: String
    var caseKind: String
    var repetition: Int
    var status: String
    var artifacts: [RichAnswerEvidenceArtifactHash]

    init(
        generatedAt: String,
        record: RichAnswerEvidenceRecord,
        artifacts: [RichAnswerEvidenceArtifactHash]
    ) {
        schemaVersion = 1
        self.generatedAt = generatedAt
        runID = record.runID
        caseID = record.caseSnapshot.id
        caseKind = record.caseSnapshot.caseKind
        repetition = record.repetition
        status = record.status
        self.artifacts = artifacts
    }
}

private struct RichAnswerEvidenceArtifactHash: Codable {
    var path: String
    var sha256: String
    var byteCount: Int64

    init(path: String, url: URL) throws {
        self.path = path
        sha256 = try RichAnswerEvidenceRecorder.sha256(of: url)
        byteCount = try RichAnswerEvidenceRecorder.byteCount(of: url)
    }
}

private struct RichAnswerEvidenceTraceabilitySnapshot: Codable {
    var runID: String
    var sourceHash: String
    var matrixHash: String
    var promptHash: String
    var modelProof: RichAnswerEvidenceModelProofSnapshot
}

private struct RichAnswerEvidenceModelProofSnapshot: Codable {
    var provider: String?
    var model: String?
    var requestID: String?
    var backend: String?
    var nonFixtureEvidence: [String]
    var issues: [String]
    var trustedModelInvocation: Bool
    var fixtureInvocation: Bool

    init(
        runCase: RichAnswerLiveRunCase,
        request: RichAnswerEvidencePromptSnapshot?,
        reply: RichAnswerEvidenceReplySnapshot?
    ) {
        backend = Self.normalized(reply?.backend)
        requestID = request?.requestID
        provider = Self.provider(from: reply)
        model = Self.model(from: reply)
        fixtureInvocation = Self.isFixture(reply: reply)

        if !runCase.invokesModel {
            nonFixtureEvidence = ["deterministic-case-kind=\(runCase.caseKind)"]
            issues = []
            trustedModelInvocation = false
            return
        }

        var evidence: [String] = []
        var proofIssues: [String] = []
        if let provider, !provider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            evidence.append("provider=\(provider)")
        } else {
            proofIssues.append("missing upstream provider in toolTrace")
        }
        if let model, !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            evidence.append("model=\(model)")
        } else {
            proofIssues.append("missing model in toolTrace")
        }
        if let requestID, !requestID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            evidence.append("requestID=\(requestID)")
        } else {
            proofIssues.append("missing requestID in prompt snapshot")
        }
        if let backend, backend == "pi" {
            evidence.append("backend=\(backend)")
        } else if let backend, !backend.isEmpty {
            proofIssues.append("backend is \(backend); expected pi")
        } else {
            proofIssues.append("backend is missing")
        }
        if let text = reply?.text,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            evidence.append("replyTextBytes=\(text.utf8.count)")
        } else {
            proofIssues.append("missing non-empty model reply text")
        }
        if fixtureInvocation {
            proofIssues.append("fixture or offline invocation detected")
        }
        nonFixtureEvidence = evidence
        issues = proofIssues
        trustedModelInvocation = proofIssues.isEmpty
    }

    private static func provider(from reply: RichAnswerEvidenceReplySnapshot?) -> String? {
        guard let reply,
              let value = traceValue(
                  in: reply.toolTrace,
                  keys: ["provider", "upstreamProvider", "upstream-provider", "llmProvider", "llm-provider"]
              ) else { return nil }
        let backend = normalized(reply.backend)
        let normalizedValue = value.lowercased()
        guard backend.map({ normalizedValue != $0 }) ?? true,
              !["offline", "fixture", "mock"].contains(normalizedValue) else {
            return nil
        }
        return value
    }

    private static func model(from reply: RichAnswerEvidenceReplySnapshot?) -> String? {
        guard let reply else { return nil }
        return traceValue(in: reply.toolTrace, keys: ["model", "llm"])
    }

    private static func isFixture(reply: RichAnswerEvidenceReplySnapshot?) -> Bool {
        guard let reply else { return false }
        if reply.backend == "offline" { return true }
        return reply.toolTrace.contains { trace in
            trace.range(of: "fixture", options: [.caseInsensitive]) != nil
        }
    }

    static func assertBackendProviderSeparationSelfCheck() throws {
        guard let runCase = RichAnswerLiveCases.fullMatrixRuns.first(where: { $0.invokesModel }) else {
            throw RichAnswerEvidenceError.invalidConfiguration(
                "model proof self-check cannot find a model-backed rich-answer case"
            )
        }
        let requestSnapshot = RichAnswerEvidencePromptSnapshot(
            StudyAgentRequest(
                purpose: .conversation,
                question: "证明 backend 与 provider 分离",
                materialTitle: "model proof self-check",
                materialText: "provider=openai-codex 必须来自 toolTrace，backend=pi 只能证明运行入口。",
                noteTitle: "model proof self-check",
                noteText: "",
                contextRevision: "model-proof-self-check"
            )
        )
        let replySnapshot = RichAnswerEvidenceReplySnapshot(
            StudyAgentReply(
                text: "真实上游通过 trace 声明。",
                backend: .pi,
                toolTrace: [
                    "provider=openai-codex",
                    "model=gpt-proof-check",
                ]
            )
        )
        let proof = RichAnswerEvidenceModelProofSnapshot(
            runCase: runCase,
            request: requestSnapshot,
            reply: replySnapshot
        )
        guard proof.backend == "pi",
              proof.provider == "openai-codex",
              proof.model == "gpt-proof-check",
              proof.trustedModelInvocation,
              proof.nonFixtureEvidence.contains("backend=pi"),
              !proof.nonFixtureEvidence.contains(where: { $0.contains("Optional(") }) else {
            throw RichAnswerEvidenceError.invalidConfiguration(
                "model proof self-check failed to separate backend=pi from provider=openai-codex"
            )
        }

        let backendOnlyReplySnapshot = RichAnswerEvidenceReplySnapshot(
            StudyAgentReply(
                text: "backend 不能冒充 provider。",
                backend: .pi,
                toolTrace: [
                    "provider=pi",
                    "model=gpt-proof-check",
                ]
            )
        )
        let backendOnlyProof = RichAnswerEvidenceModelProofSnapshot(
            runCase: runCase,
            request: requestSnapshot,
            reply: backendOnlyReplySnapshot
        )
        guard backendOnlyProof.provider == nil,
              !backendOnlyProof.trustedModelInvocation else {
            throw RichAnswerEvidenceError.invalidConfiguration(
                "model proof self-check accepted backend=pi as upstream provider"
            )
        }
    }

    private static func traceValue(in traces: [String], keys: [String]) -> String? {
        for trace in traces {
            if let value = traceValue(in: trace, keys: keys) {
                return value
            }
        }
        return nil
    }

    private static func traceValue(in trace: String, keys: [String]) -> String? {
        let trimmedTrace = trace.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTrace.isEmpty else { return nil }
        for key in keys {
            let escapedKey = NSRegularExpression.escapedPattern(for: key)
            let pattern = "(?:^|[\\s,;])\(escapedKey)\\s*[:=]\\s*([^\\s,;]+)"
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(trimmedTrace.startIndex..<trimmedTrace.endIndex, in: trimmedTrace)
            guard let match = expression.firstMatch(in: trimmedTrace, range: range),
                  match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: trimmedTrace) else {
                continue
            }
            let value = cleanTraceValue(String(trimmedTrace[valueRange]))
            if !value.isEmpty { return value }
        }
        return nil
    }

    private static func cleanTraceValue(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`[](){}"))
    }

    private static func normalized(_ value: String?) -> String? {
        guard let normalizedValue = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !normalizedValue.isEmpty else {
            return nil
        }
        return normalizedValue
    }
}

private struct RichAnswerEvidencePromptHashSnapshot: Codable {
    var caseID: String
    var caseKind: String
    var subject: String
    var question: String
    var materialTitle: String?
    var materialKind: String?
    var materialText: String?
    var selectionTitle: String?
    var selectionText: String?
    var expectedRenderer: String?
    var expectedShape: String
    var expectedCapabilityFamilies: [String]
    var userBenefitCriteria: [String]
    var rejectedOrDegradedBehaviors: [String]
    var expectedSourceLabels: [String]

    init(runCase: RichAnswerLiveRunCase) {
        caseID = runCase.id
        caseKind = runCase.caseKind
        subject = runCase.subject
        question = runCase.question
        materialTitle = runCase.materialTitle
        materialKind = runCase.materialKind
        materialText = runCase.materialText
        selectionTitle = runCase.selectionTitle
        selectionText = runCase.selectionText
        expectedRenderer = runCase.expectedRenderer
        expectedShape = runCase.expectedShape
        expectedCapabilityFamilies = runCase.expectedCapabilityFamilies.sorted()
        userBenefitCriteria = runCase.userBenefitCriteria
        rejectedOrDegradedBehaviors = runCase.rejectedOrDegradedBehaviors
        expectedSourceLabels = runCase.expectedSourceLabels.sorted()
    }
}

private struct RichAnswerEvidenceCaseSnapshot: Codable {
    var id: String
    var caseKind: String
    var subject: String
    var question: String
    var materialTitle: String?
    var materialKind: String?
    var materialItemID: String?
    var verificationAssetID: String?
    var sourceFingerprint: String?
    var verificationAssetFingerprint: String?
    var materialText: String?
    var selectionTitle: String?
    var selectionText: String?
    var expectedRenderer: String?
    var expectedCapabilityFamilies: [String]
    var userBenefitCriteria: [String]
    var rejectedOrDegradedBehaviors: [String]

    init(_ runCase: RichAnswerLiveRunCase, request: StudyAgentRequest? = nil) {
        id = runCase.id
        caseKind = runCase.caseKind
        subject = runCase.subject
        question = runCase.question
        let resolvedMaterialTitle = runCase.materialTitle
        let resolvedMaterialKind = runCase.materialKind
        let resolvedMaterialItemID = Self.currentMaterialID(in: request?.courseContext)
            ?? runCase.materialItemID
        let resolvedVerificationAssetID = runCase.verificationAssetID
        let resolvedMaterialText = runCase.materialText
        let resolvedSelectionTitle = runCase.selectionTitle
        let resolvedSelectionText = runCase.selectionText
        materialTitle = resolvedMaterialTitle
        materialKind = resolvedMaterialKind
        materialItemID = resolvedMaterialItemID
        verificationAssetID = resolvedVerificationAssetID
        sourceFingerprint = Self.sourceFingerprint(
            materialTitle: resolvedMaterialTitle,
            materialKind: resolvedMaterialKind,
            materialItemID: resolvedMaterialItemID,
            verificationAssetID: resolvedVerificationAssetID,
            materialText: resolvedMaterialText,
            selectionTitle: resolvedSelectionTitle,
            selectionText: resolvedSelectionText
        )
        verificationAssetFingerprint = Self.verificationAssetFingerprint(for: resolvedVerificationAssetID)
        materialText = resolvedMaterialText
        selectionTitle = resolvedSelectionTitle
        selectionText = resolvedSelectionText
        expectedRenderer = runCase.expectedRenderer
        expectedCapabilityFamilies = runCase.expectedCapabilityFamilies.sorted()
        userBenefitCriteria = runCase.userBenefitCriteria
        rejectedOrDegradedBehaviors = runCase.rejectedOrDegradedBehaviors
    }

    private static func currentMaterialID(in context: StudyAgentCourseContext?) -> String? {
        if let id = context?.items.first(where: \.isCurrentMaterial)?.id,
           !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return id
        }
        if let id = context?.catalog.first(where: \.isCurrentMaterial)?.id,
           !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return id
        }
        return nil
    }

    private static func sourceFingerprint(
        materialTitle: String?,
        materialKind: String?,
        materialItemID: String?,
        verificationAssetID: String?,
        materialText: String?,
        selectionTitle: String?,
        selectionText: String?
    ) -> String? {
        let fields = [
            "materialTitle": materialTitle,
            "materialKind": materialKind,
            "materialItemID": materialItemID,
            "verificationAssetID": verificationAssetID,
            "materialText": materialText,
            "selectionTitle": selectionTitle,
            "selectionText": selectionText,
        ]
        let normalizedFields = fields.compactMap { key, value -> String? in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : "\(key)=\(trimmed)"
        }
        guard !normalizedFields.isEmpty else { return nil }
        let payload = normalizedFields.sorted().joined(separator: "\n")
        return SHA256.hash(data: Data(payload.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func verificationAssetFingerprint(for assetID: String?) -> String? {
        guard let assetID,
              !assetID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        guard let manifestURL = verificationAssetManifestURL(),
              let manifestData = try? Data(contentsOf: manifestURL),
              let manifestObject = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              let manifestAssets = manifestObject["assets"] as? [[String: Any]] else {
            return nil
        }
        for entry in manifestAssets {
            guard entry["id"] as? String == assetID,
                  let derivative = entry["derivative"] as? [String: Any],
                  let sha256 = derivative["sha256"] as? String,
                  !sha256.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            return sha256
        }
        return nil
    }

    private static func verificationAssetManifestURL() -> URL? {
        var cursor = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<8 {
            let candidate = cursor
                .appendingPathComponent("Sources/WeiBei/Resources/RichAnswerVerificationAssets")
                .appendingPathComponent("manifest.json")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            cursor.deleteLastPathComponent()
        }
        return nil
    }
}

private struct RichAnswerEvidencePromptSnapshot: Codable {
    var requestID: String
    var purpose: String
    var answerFormPolicy: String?
    var question: String
    var materialTitle: String
    var materialText: String
    var materialIsTruncated: Bool
    var noteTitle: String
    var noteText: String
    var selectionTitle: String?
    var selectionText: String?
    var contextRevision: String
    var courseContext: StudyAgentCourseContext
    var learningContext: StudyAgentLearningContext

    init(_ request: StudyAgentRequest) {
        requestID = request.id.uuidString
        purpose = request.purpose.rawValue
        answerFormPolicy = request.answerFormPolicy.rawValue
        question = request.question
        materialTitle = request.materialTitle
        materialText = request.materialText
        materialIsTruncated = request.materialIsTruncated
        noteTitle = request.noteTitle
        noteText = request.noteText
        selectionTitle = request.selectionTitle
        selectionText = request.selectionText
        contextRevision = request.contextRevision
        courseContext = request.courseContext
        learningContext = request.learningContext
    }
}

private struct RichAnswerEvidenceReplySnapshot: Codable {
    var text: String
    var backend: String
    var toolTrace: [String]
    var loadedSkills: [StudyAgentLoadedSkill]
    var richAnswer: RichAnswerPresentation?
    var noteProposal: StudyAgentNoteProposal?
    var learningUpdate: StudyAgentLearningUpdate?

    init(_ reply: StudyAgentReply) {
        text = reply.text
        backend = reply.backend.rawValue
        toolTrace = reply.toolTrace
        loadedSkills = reply.loadedSkills
        richAnswer = reply.richAnswer
        noteProposal = reply.noteProposal
        learningUpdate = reply.learningUpdate
    }
}

private struct RichAnswerEvidenceShapeDecision: Codable {
    var expectedShape: String
    var actualShape: String
    var preferredSurface: String?
    var directManipulation: Bool?
    var sceneCount: Int
    var t1SceneCount: Int
    var t2SceneCount: Int
    var renderPlanSceneCount: Int?
    var narrativeCharacterCount: Int

    init(runCase: RichAnswerLiveRunCase, reply: StudyAgentReply?) {
        expectedShape = runCase.expectedShape
        let presentation = reply?.richAnswer
        let t1Count = presentation?.scenes.filter { $0.program != nil }.count ?? 0
        let t2Count = presentation?.scenes.filter { $0.ui != nil }.count ?? 0
        let renderPlanCount = presentation?.scenes.filter { $0.renderPlan != nil }.count ?? 0
        sceneCount = presentation?.scenes.count ?? 0
        t1SceneCount = t1Count
        t2SceneCount = t2Count
        renderPlanSceneCount = renderPlanCount
        preferredSurface = presentation?.expressionPlan?.preferredSurface.rawValue
        directManipulation = presentation?.expressionPlan?.directManipulation
        narrativeCharacterCount = reply?.text.count ?? 0
        if presentation?.mode == .rich {
            let activeRoutes = [t1Count > 0, t2Count > 0, renderPlanCount > 0].filter { $0 }.count
            if activeRoutes > 1 {
                actualShape = "rich-mixed-render-routes"
            } else if t1Count > 0 {
                actualShape = "rich-t1-openui-program"
            } else if t2Count > 0 {
                actualShape = "rich-t2-composable-ui"
            } else if renderPlanCount > 0 {
                actualShape = "rich-render-plan"
            } else {
                actualShape = "rich-without-renderer"
            }
        } else if reply == nil {
            actualShape = "no-model-reply"
        } else {
            actualShape = "text-only"
        }
    }

    static func skipped(_ runCase: RichAnswerLiveRunCase) -> Self {
        var decision = RichAnswerEvidenceShapeDecision(runCase: runCase, reply: nil)
        decision.actualShape = "skipped"
        return decision
    }
}

private struct RichAnswerEvidenceExpressionSnapshot: Codable {
    var expressionPlan: RichAnswerExpressionPlan?
    var t1Programs: [RichAnswerEvidenceT1ProgramSnapshot]
    var t2Compositions: [RichAnswerEvidenceT2CompositionSnapshot]
    var renderPlans: [RichAnswerEvidenceRenderPlanSnapshot]?

    static let empty = RichAnswerEvidenceExpressionSnapshot(reply: nil)

    init(reply: StudyAgentReply?) {
        expressionPlan = reply?.richAnswer?.expressionPlan
        t1Programs = reply?.richAnswer?.scenes.compactMap { scene in
            scene.program.map { RichAnswerEvidenceT1ProgramSnapshot(scene: scene, program: $0) }
        } ?? []
        t2Compositions = reply?.richAnswer?.scenes.compactMap { scene in
            scene.ui.map { RichAnswerEvidenceT2CompositionSnapshot(scene: scene, ui: $0) }
        } ?? []
        renderPlans = reply?.richAnswer?.scenes.compactMap { scene in
            scene.renderPlan.map { RichAnswerEvidenceRenderPlanSnapshot(scene: scene, plan: $0) }
        } ?? []
    }
}

private struct RichAnswerEvidenceRenderPlanSnapshot: Codable {
    var sceneID: String
    var family: String
    var renderer: String
    var specVersion: String
    var specFields: [String]
    var interactionKinds: [String]
    var interactionIDs: [String]
    var actionNames: [String]
    var stateKeys: [String]
    var sourceEvidenceIDs: [String]
    var sourceRoles: [String]
    var artifactKinds: [String]
    var fallbackMode: String
    var negotiationStatus: String
    var negotiationIssues: [String]

    init(scene: RichAnswerScene, plan: RichAnswerRenderPlan) {
        let negotiation = RichAnswerRendererRegistry.defaultRegistry().negotiate(plan: plan)
        sceneID = scene.id
        family = scene.family.rawValue
        renderer = plan.renderer
        specVersion = plan.specVersion
        specFields = plan.spec.fields.keys.sorted()
        interactionKinds = Array(Set(plan.interactionBindings.map(\.kind.rawValue))).sorted()
        interactionIDs = plan.interactionBindings.map(\.id).sorted()
        actionNames = plan.interactionBindings.compactMap(\.actionName).sorted()
        stateKeys = plan.interactionBindings.compactMap(\.stateKey).sorted()
        sourceEvidenceIDs = Array(Set(plan.sourceBindings.map(\.evidenceID))).sorted()
        sourceRoles = Array(Set(plan.sourceBindings.map(\.role))).sorted()
        artifactKinds = Array(Set(plan.artifactRefs.map(\.kind))).sorted()
        fallbackMode = plan.fallback.mode.rawValue
        negotiationStatus = negotiation.status.rawValue
        negotiationIssues = negotiation.mismatch?.issues.map { issue in
            "\(issue.code.rawValue):\(issue.field ?? "unknown"):\(issue.message)"
        } ?? []
    }
}

private struct RichAnswerEvidenceT1ProgramSnapshot: Codable {
    var sceneID: String
    var family: String
    var version: String
    var capabilities: [String]
    var directManipulation: Bool
    var maxHeight: Int
    var graphics: String
    var sourceCharacterCount: Int
    var componentNames: [String]

    init(scene: RichAnswerScene, program: RichAnswerUIProgram) {
        sceneID = scene.id
        family = scene.family.rawValue
        version = program.version
        capabilities = program.capabilities
        directManipulation = program.directManipulation
        maxHeight = program.maxHeight
        graphics = program.graphics.rawValue
        sourceCharacterCount = program.source.count
        componentNames = Self.componentNames(in: program.source)
    }

    private static func componentNames(in source: String) -> [String] {
        let names = source.split(separator: "\n").compactMap { line -> String? in
            guard let openParenthesis = line.firstIndex(of: "(") else { return nil }
            let prefix = line[..<openParenthesis]
            let tokens = prefix.split { !$0.isLetter && !$0.isNumber && $0 != "_" }
            return tokens.last.map(String.init)
        }
        return Array(Set(names)).sorted()
    }
}

private struct RichAnswerEvidenceT2CompositionSnapshot: Codable {
    var sceneID: String
    var family: String
    var rootID: String
    var roles: [String]
    var nodeCount: Int
    var datasetCount: Int
    var dataRowCount: Int
    var bindingCount: Int
    var bindingLabels: [String]
    var evidenceIDs: [String]

    init(scene: RichAnswerScene, ui: RichAnswerUIComposition) {
        sceneID = scene.id
        family = scene.family.rawValue
        rootID = ui.rootID
        roles = Array(Set(ui.nodes.map(\.role.rawValue))).sorted()
        nodeCount = ui.nodes.count
        datasetCount = ui.datasets.count
        dataRowCount = ui.datasets.reduce(0) { $0 + $1.rows.count }
        bindingCount = ui.bindings.count
        bindingLabels = ui.bindings.map(\.label)
        evidenceIDs = Array(Set(ui.nodes.flatMap(\.evidenceIDs) + ui.datasets.flatMap { dataset in
            dataset.rows.flatMap(\.evidenceIDs)
        })).sorted()
    }
}

private struct RichAnswerEvidenceSourceBinding: Codable {
    var textSourceLabels: [String]
    var evidenceLedgerLabels: [String]
    var evidenceState: String?
    var sceneEvidenceIDs: [String]
    var hasExpectedSource: Bool

    static let empty = RichAnswerEvidenceSourceBinding(runCase: .invalidProtocol("none"), reply: nil)

    init(runCase: RichAnswerLiveRunCase, reply: StudyAgentReply?) {
        let textLabels = Self.sourceLabels(in: reply?.text ?? "")
        let ledgerLabels = Array(Set(reply?.richAnswer?.evidenceLedger.map(\.sourceLabel) ?? [])).sorted()
        textSourceLabels = textLabels
        evidenceLedgerLabels = ledgerLabels
        evidenceState = reply?.richAnswer?.evidenceState.rawValue
        sceneEvidenceIDs = Array(Set(reply?.richAnswer?.scenes.flatMap(\.evidenceIDs) ?? [])).sorted()
        hasExpectedSource = runCase.expectedSourceLabels.contains { expected in
            textLabels.contains { $0.hasPrefix(expected) }
                || ledgerLabels.contains { $0.hasPrefix(expected) }
        }
    }

    private static func sourceLabels(in text: String) -> [String] {
        var labels: [String] = []
        var remainder = text[...]
        while let start = remainder.firstIndex(of: "["),
              let end = remainder[start...].firstIndex(of: "]") {
            let label = String(remainder[start...end])
            if label.hasPrefix("[材料：")
                || label.hasPrefix("[选区：")
                || label.hasPrefix("[笔记：")
                || label.hasPrefix("[学习记录：")
                || label.hasPrefix("[学习记忆：") {
                labels.append(label)
            }
            remainder = remainder[remainder.index(after: end)...]
        }
        return Array(Set(labels)).sorted()
    }
}

private struct RichAnswerEvidenceExpertObservationSnapshot: Codable {
    var policy: String
    var expectedTextGroups: [[String]]
    var expectedLimitationGroups: [[String]]
    var matchedExpectedTextGroups: [[String]]
    var missingExpectedTextGroups: [[String]]
    var satisfiedExpectedTextGroups: Bool

    static let empty = RichAnswerEvidenceExpertObservationSnapshot(runCase: .invalidProtocol("none"), reply: nil)

    init(runCase: RichAnswerLiveRunCase, reply: StudyAgentReply?) {
        policy = "development-observation-not-runtime-hard-gate"
        expectedTextGroups = runCase.expertExpectedTextGroups
        expectedLimitationGroups = runCase.expertExpectedLimitationGroups
        let corpus = reply?.text ?? ""
        matchedExpectedTextGroups = expectedTextGroups.filter {
            Self.containsAny(in: corpus, group: $0)
        }
        missingExpectedTextGroups = expectedTextGroups.filter {
            !Self.containsAny(in: corpus, group: $0)
        }
        satisfiedExpectedTextGroups = missingExpectedTextGroups.isEmpty
    }

    private static func containsAny(in text: String, group: [String]) -> Bool {
        group.contains { text.localizedCaseInsensitiveContains($0) }
    }
}

private struct RichAnswerEvidenceRepairSnapshot: Codable {
    var previousRunID: String?
    var previousStatus: String?
    var repairNote: String?
    var isRetest: Bool
}

extension RichAnswerLiveRunCase {
    var invokesModel: Bool {
        if case .invalidProtocol = self { return false }
        return true
    }

    var caseKind: String {
        switch self {
        case .invalidProtocol: "invalid-protocol"
        case .success: "rich"
        case .textOnly: "text-only"
        case .degradation: "degradation"
        }
    }

    var subject: String {
        switch self {
        case .invalidProtocol:
            invalidPressureCase?.subject ?? "协议"
        case let .success(checkCase):
            checkCase.discipline
        case let .textOnly(checkCase):
            checkCase.subject
        case let .degradation(checkCase):
            checkCase.pressureCase.subject
        }
    }

    var question: String {
        switch self {
        case .invalidProtocol:
            invalidPressureCase?.question ?? "非法协议结构必须被拦截。"
        case let .success(checkCase):
            checkCase.question
        case let .textOnly(checkCase):
            checkCase.question
        case let .degradation(checkCase):
            checkCase.question
        }
    }

    var materialTitle: String? {
        switch self {
        case .invalidProtocol:
            nil
        case let .success(checkCase):
            checkCase.materialTitle
        case let .textOnly(checkCase):
            checkCase.materialTitle
        case let .degradation(checkCase):
            checkCase.materialTitle
        }
    }

    var materialKind: String? {
        switch self {
        case .invalidProtocol:
            nil
        case let .success(checkCase):
            checkCase.materialKind
        case let .textOnly(checkCase):
            checkCase.materialKind
        case let .degradation(checkCase):
            checkCase.materialKind
        }
    }

    var selectionTitle: String? {
        switch self {
        case .invalidProtocol:
            nil
        case let .success(checkCase):
            checkCase.selectionTitle
        case let .textOnly(checkCase):
            checkCase.selectionTitle
        case let .degradation(checkCase):
            checkCase.selectionTitle
        }
    }

    var materialText: String? {
        switch self {
        case .invalidProtocol:
            nil
        case let .success(checkCase):
            checkCase.materialText
        case let .textOnly(checkCase):
            checkCase.materialText
        case let .degradation(checkCase):
            checkCase.materialText
        }
    }

    var materialItemID: String? {
        switch self {
        case .invalidProtocol:
            nil
        case let .success(checkCase):
            checkCase.materialID
        case let .textOnly(checkCase):
            "material-\(checkCase.id)"
        case let .degradation(checkCase):
            "material-\(checkCase.id)"
        }
    }

    var verificationAssetID: String? {
        guard materialKind == "image" else { return nil }
        return RichAnswerEvidenceCaseSnapshotVerificationAssetParser.assetID(in: materialText)
    }

    var selectionText: String? {
        switch self {
        case .invalidProtocol:
            nil
        case let .success(checkCase):
            checkCase.selectionText
        case let .textOnly(checkCase):
            checkCase.selectionText
        case let .degradation(checkCase):
            checkCase.selectionText
        }
    }

    var expectedRenderer: String? {
        switch self {
        case .invalidProtocol:
            "protocol-rejection"
        case let .success(checkCase):
            switch checkCase.rendererRequirement {
            case .either: "t1-or-t2"
            case .t1: "t1"
            case .t2: "t2"
            }
        case .textOnly:
            "none"
        case let .degradation(checkCase):
            checkCase.allowsPartialRichAnswer ? "optional-partial-rich" : "none"
        }
    }

    var expectedShape: String {
        switch self {
        case .invalidProtocol:
            "deterministic-protocol-rejection"
        case .success:
            "rich-answer-inline"
        case .textOnly:
            "source-grounded-text-only"
        case .degradation:
            "honest-degradation"
        }
    }

    var expectedCapabilityFamilies: [String] {
        let families: Set<RichAnswerCapabilityFamily>
        switch self {
        case .invalidProtocol:
            families = invalidPressureCase?.expectedCapabilityFamilies ?? []
        case let .success(checkCase):
            families = checkCase.pressureCase.expectedCapabilityFamilies
        case .textOnly:
            families = []
        case let .degradation(checkCase):
            families = checkCase.pressureCase.expectedCapabilityFamilies
        }
        return families.map(\.rawValue)
    }

    var userBenefitCriteria: [String] {
        switch self {
        case .invalidProtocol:
            invalidPressureCase?.userBenefitCriteria ?? []
        case let .success(checkCase):
            checkCase.pressureCase.userBenefitCriteria
        case .textOnly:
            ["该题应保持短文本，证明模型能主动拒绝不必要 UI。"]
        case let .degradation(checkCase):
            checkCase.pressureCase.userBenefitCriteria
        }
    }

    var rejectedOrDegradedBehaviors: [String] {
        switch self {
        case .invalidProtocol:
            invalidPressureCase?.rejectedOrDegradedBehaviors ?? []
        case let .success(checkCase):
            checkCase.pressureCase.rejectedOrDegradedBehaviors
        case let .textOnly(checkCase):
            checkCase.forbiddenTextFragments
        case let .degradation(checkCase):
            checkCase.pressureCase.rejectedOrDegradedBehaviors + checkCase.forbiddenTextFragments
        }
    }

    var expertExpectedTextGroups: [[String]] {
        switch self {
        case .invalidProtocol, .success:
            []
        case let .textOnly(checkCase):
            checkCase.expectedTextGroups
        case let .degradation(checkCase):
            checkCase.expectedTextGroups
        }
    }

    var expertExpectedLimitationGroups: [[String]] {
        switch self {
        case let .degradation(checkCase):
            checkCase.expectedTextGroups
        case .invalidProtocol, .success, .textOnly:
            []
        }
    }

    var expectedSourceLabels: [String] {
        switch self {
        case .invalidProtocol:
            return []
        case let .success(checkCase):
            return ["[材料：\(checkCase.materialTitle)", "[选区：\(checkCase.selectionTitle)"]
        case let .textOnly(checkCase):
            return ["[材料：\(checkCase.materialTitle)", "[选区：\(checkCase.selectionTitle)"]
        case let .degradation(checkCase):
            var labels = ["[材料：\(checkCase.materialTitle)"]
            if let selectionTitle = checkCase.selectionTitle {
                labels.append("[选区：\(selectionTitle)")
            }
            return labels
        }
    }

    private var invalidPressureCase: RichAnswerPressureCase? {
        RichAnswerPressureCases.faultInjectionCases.first {
            $0.id == RichAnswerLiveCases.invalidProtocolCaseID
        }
    }
}

private enum RichAnswerEvidenceCaseSnapshotVerificationAssetParser {
    static func assetID(in materialText: String?) -> String? {
        guard let materialText else { return nil }
        let prefixes = ["来源登记 ID：", "来源登记 ID:"]
        for line in materialText.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            for prefix in prefixes where trimmed.hasPrefix(prefix) {
                let value = String(trimmed.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }
}

enum RichAnswerEvidenceError: LocalizedError {
    case invalidConfiguration(String)

    var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(message):
            "rich-answer evidence configuration is invalid: \(message)"
        }
    }
}
