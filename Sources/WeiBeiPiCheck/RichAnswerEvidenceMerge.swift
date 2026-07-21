import Darwin
import Foundation

struct RichAnswerEvidenceMergeConfiguration {
    let inputRunIDs: [String]
    let mergedRunID: String
    let baseURL: URL
    let mergedRootURL: URL
    let screenshotManifestURL: URL?

    static func from(environment: [String: String]) throws -> Self? {
        let rawRuns = environment["WEIBEI_PI_RICH_ANSWER_MERGE_RUNS"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !rawRuns.isEmpty else { return nil }

        let inputRunIDs = rawRuns
            .split(separator: ",")
            .map { RichAnswerEvidenceRunConfiguration.safePathComponent(String($0)) }
            .filter { !$0.isEmpty }
        let uniqueInputRunIDs = Array(Set(inputRunIDs)).sorted()
        guard uniqueInputRunIDs.count == inputRunIDs.count else {
            throw RichAnswerEvidenceError.invalidConfiguration(
                "merge input runIDs contain duplicates: \(rawRuns)"
            )
        }
        guard !inputRunIDs.isEmpty else {
            throw RichAnswerEvidenceError.invalidConfiguration("merge-runs cannot be empty")
        }

        let rawMergedRunID = environment["WEIBEI_PI_RICH_ANSWER_MERGED_RUN_ID"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !rawMergedRunID.isEmpty else {
            throw RichAnswerEvidenceError.invalidConfiguration(
                "missing --merged-run-id for rich-answer evidence merge"
            )
        }
        let mergedRunID = RichAnswerEvidenceRunConfiguration.safePathComponent(rawMergedRunID)
        guard !inputRunIDs.contains(mergedRunID) else {
            throw RichAnswerEvidenceError.invalidConfiguration(
                "merged runID \(mergedRunID) must not be one of the input shard runIDs"
            )
        }

        let basePath = environment["WEIBEI_PI_RICH_ANSWER_EVIDENCE_DIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL = URL(fileURLWithPath: basePath?.isEmpty == false
            ? basePath!
            : "\(FileManager.default.currentDirectoryPath)/.build/rich-answer-evidence")
        let screenshotManifestURL = environment["WEIBEI_PI_RICH_ANSWER_SCREENSHOT_MANIFEST"]
            .flatMap { rawValue -> URL? in
                let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : URL(fileURLWithPath: trimmed)
            }
        return Self(
            inputRunIDs: inputRunIDs,
            mergedRunID: mergedRunID,
            baseURL: baseURL,
            mergedRootURL: baseURL.appendingPathComponent(mergedRunID, isDirectory: true),
            screenshotManifestURL: screenshotManifestURL
        )
    }
}

struct RichAnswerEvidenceMergeResult {
    let mergedRunID: String
    let rootURL: URL
    let inputRunIDs: [String]
    let repetitions: [Int]
    let totalRecords: Int
    let reviewPackageURL: URL
}

enum RichAnswerEvidenceMerger {
    private static let targetRepetitions = [1, 2, 3, 4]
    private static let requiredCaseCount = 56

    static func merge(configuration: RichAnswerEvidenceMergeConfiguration) throws -> RichAnswerEvidenceMergeResult {
        try RichAnswerLiveCases.assertMatrixMatchesPressureCases()

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: configuration.mergedRootURL, withIntermediateDirectories: true)
        let lock = try RichAnswerEvidenceMergeLock(rootURL: configuration.mergedRootURL, runID: configuration.mergedRunID)
        defer { lock.release() }

        let matrixCases = RichAnswerLiveCases.fullMatrixRuns
        let matrixCaseIDs = matrixCases.map(\.id)
        let uniqueMatrixCaseIDs = Set(matrixCaseIDs)
        guard matrixCases.count == requiredCaseCount,
              uniqueMatrixCaseIDs.count == requiredCaseCount else {
            throw RichAnswerEvidenceError.invalidConfiguration(
                "merge requires \(requiredCaseCount) unique rich-answer cases; got total=\(matrixCases.count) unique=\(uniqueMatrixCaseIDs.count)"
            )
        }
        let matrixOrder = Dictionary(uniqueKeysWithValues: matrixCases.enumerated().map { index, runCase in
            (runCase.id, index)
        })
        let expectedCaseIDs = Set(matrixCases.map(\.id))

        var sourceRuns: [RichAnswerEvidenceMergeSourceRun] = []
        var recordsByKey: [RichAnswerEvidenceMergeRecordKey: RichAnswerEvidenceMergeInputRecord] = [:]
        var duplicateDescriptions: [String] = []
        var sourceRepetitions = Set<Int>()

        for runID in configuration.inputRunIDs {
            let runURL = configuration.baseURL.appendingPathComponent(runID, isDirectory: true)
            guard fileManager.fileExists(atPath: runURL.path) else {
                throw RichAnswerEvidenceError.invalidConfiguration("merge input run does not exist: \(runURL.path)")
            }

            let metadata = try readSourceMetadataIfPresent(runURL: runURL)
            metadata?.repetitions.forEach { sourceRepetitions.insert($0) }
            let recordURLs = try sourceRecordURLs(runURL: runURL)
            guard !recordURLs.isEmpty else {
                throw RichAnswerEvidenceError.invalidConfiguration("merge input run has no record.json files: \(runURL.path)")
            }

            var sourceRecordCount = 0
            for recordURL in recordURLs {
                let record = try readRecord(recordURL: recordURL)
                guard record.runID == runID else {
                    throw RichAnswerEvidenceError.invalidConfiguration(
                        "record runID mismatch at \(recordURL.path): expected \(runID), got \(record.runID)"
                    )
                }
                guard expectedCaseIDs.contains(record.caseSnapshot.id) else {
                    throw RichAnswerEvidenceError.invalidConfiguration(
                        "unknown caseID in source record: \(record.caseSnapshot.id) at \(recordURL.path)"
                    )
                }
                guard targetRepetitions.contains(record.repetition) else {
                    throw RichAnswerEvidenceError.invalidConfiguration(
                        "unexpected repetition \(record.repetition) in \(recordURL.path); expected \(targetRepetitions.map(String.init).joined(separator: ","))"
                    )
                }
                sourceRepetitions.insert(record.repetition)
                let key = RichAnswerEvidenceMergeRecordKey(
                    repetition: record.repetition,
                    caseID: record.caseSnapshot.id
                )
                let relativePath = relativePath(recordURL, rootURL: runURL)
                let inputRecord = RichAnswerEvidenceMergeInputRecord(
                    sourceRunID: runID,
                    sourceRecordPath: "../\(runID)/\(relativePath)",
                    sourceRecordURL: recordURL,
                    sourceSequence: record.sequence,
                    record: record
                )
                if let existing = recordsByKey[key] {
                    duplicateDescriptions.append(
                        "rep=\(key.repetition) case=\(key.caseID) sources=\(existing.sourceRunID),\(runID)"
                    )
                } else {
                    recordsByKey[key] = inputRecord
                }
                sourceRecordCount += 1
            }

            sourceRuns.append(
                RichAnswerEvidenceMergeSourceRun(
                    runID: runID,
                    rootPath: runURL.path,
                    declaredRepetitions: metadata?.repetitions ?? [],
                    rawRecordCount: sourceRecordCount
                )
            )
        }

        guard duplicateDescriptions.isEmpty else {
            throw RichAnswerEvidenceError.invalidConfiguration(
                "merge found duplicate case/repetition records: \(summarize(duplicateDescriptions))"
            )
        }

        let repetitions = sourceRepetitions.sorted()
        guard repetitions == targetRepetitions else {
            throw RichAnswerEvidenceError.invalidConfiguration(
                "merge requires complete repetitions \(targetRepetitions.map(String.init).joined(separator: ",")); got \(repetitions.map(String.init).joined(separator: ","))"
            )
        }

        let missing = missingKeys(
            repetitions: repetitions,
            matrixCases: matrixCases,
            recordsByKey: recordsByKey
        )
        guard missing.isEmpty else {
            throw RichAnswerEvidenceError.invalidConfiguration(
                "merge found \(missing.count) missing case/repetition record(s): \(summarize(missing))"
            )
        }

        let entries = recordsByKey.values
            .sorted { left, right in
                if left.record.repetition != right.record.repetition {
                    return left.record.repetition < right.record.repetition
                }
                return (matrixOrder[left.record.caseSnapshot.id] ?? Int.max)
                    < (matrixOrder[right.record.caseSnapshot.id] ?? Int.max)
            }
            .map { inputRecord in
                let globalSequence = (matrixOrder[inputRecord.record.caseSnapshot.id] ?? 0) + 1
                return RichAnswerEvidenceMergedIndexEntry(
                    runID: configuration.mergedRunID,
                    sourceRunID: inputRecord.sourceRunID,
                    repetition: inputRecord.record.repetition,
                    sequence: globalSequence,
                    sourceSequence: inputRecord.sourceSequence,
                    caseID: inputRecord.record.caseSnapshot.id,
                    caseKind: inputRecord.record.caseSnapshot.caseKind,
                    subject: inputRecord.record.caseSnapshot.subject,
                    status: inputRecord.record.status,
                    elapsedSeconds: inputRecord.record.elapsedSeconds,
                    actualShape: inputRecord.record.shapeDecision.actualShape,
                    recordPath: inputRecord.sourceRecordPath,
                    failureReason: inputRecord.record.failureReason
                )
            }

        let statusCounts = Dictionary(grouping: entries, by: \.status).mapValues(\.count)
        let createdAt = timestamp()
        let packageResult = try RichAnswerEvidencePackageBuilder.build(
            input: RichAnswerEvidencePackageBuildInput(
                runID: configuration.mergedRunID,
                mergedRootURL: configuration.mergedRootURL,
                expectedCases: matrixCases.enumerated().map { index, runCase in
                    RichAnswerEvidencePackageExpectedCase(
                        sequence: index + 1,
                        caseID: runCase.id,
                        caseKind: runCase.caseKind,
                        subject: runCase.subject
                    )
                },
                observedRepetitions: repetitions,
                records: recordsByKey.values.map { inputRecord in
                    RichAnswerEvidencePackageRecordReference(
                        sourceRunID: inputRecord.sourceRunID,
                        sourceSequence: inputRecord.sourceSequence,
                        repetition: inputRecord.record.repetition,
                        caseID: inputRecord.record.caseSnapshot.id,
                        caseKind: inputRecord.record.caseSnapshot.caseKind,
                        subject: inputRecord.record.caseSnapshot.subject,
                        recordURL: inputRecord.sourceRecordURL,
                        recordPathFromMergedRoot: inputRecord.sourceRecordPath
                    )
                },
                screenshotManifestURL: configuration.screenshotManifestURL
            )
        )
        let metadata = RichAnswerEvidenceMergedRunMetadata(
            schemaVersion: 2,
            runID: configuration.mergedRunID,
            createdAt: createdAt,
            rootPath: configuration.mergedRootURL.path,
            sourceRuns: sourceRuns,
            repetitions: repetitions,
            expectedCaseCount: matrixCases.count,
            expectedRecordCount: matrixCases.count * repetitions.count,
            totalRecords: entries.count,
            completionState: packageResult.summary.completionState,
            reviewPackagePath: "review-package/index.html",
            screenshotManifestPath: configuration.screenshotManifestURL?.path
        )
        let index = RichAnswerEvidenceMergedRunIndex(
            schemaVersion: 2,
            runID: configuration.mergedRunID,
            updatedAt: createdAt,
            rootPath: configuration.mergedRootURL.path,
            inputRunIDs: configuration.inputRunIDs,
            repetitions: repetitions,
            expectedCaseCount: matrixCases.count,
            expectedRecordCount: matrixCases.count * repetitions.count,
            totalRecords: entries.count,
            statusCounts: statusCounts,
            completionState: packageResult.summary.completionState,
            reviewPackagePath: "review-package/index.html",
            screenshotManifestPath: configuration.screenshotManifestURL?.path,
            reviewSummary: packageResult.summary,
            records: entries
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try write(metadata, to: configuration.mergedRootURL.appendingPathComponent("run.json"), encoder: encoder)
        try write(index, to: configuration.mergedRootURL.appendingPathComponent("index.json"), encoder: encoder)
        try writePlainText(indexMarkdown(index), to: configuration.mergedRootURL.appendingPathComponent("index.md"))
        try writePlainText(indexHTML(index), to: configuration.mergedRootURL.appendingPathComponent("index.html"))

        return RichAnswerEvidenceMergeResult(
            mergedRunID: configuration.mergedRunID,
            rootURL: configuration.mergedRootURL,
            inputRunIDs: configuration.inputRunIDs,
            repetitions: repetitions,
            totalRecords: entries.count,
            reviewPackageURL: packageResult.indexURL
        )
    }

    private static func sourceRecordURLs(runURL: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: runURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw RichAnswerEvidenceError.invalidConfiguration("cannot enumerate source run: \(runURL.path)")
        }
        var urls: [URL] = []
        for case let url as URL in enumerator where url.lastPathComponent == "record.json" {
            urls.append(url)
        }
        return urls.sorted { $0.path < $1.path }
    }

    private static func readSourceMetadataIfPresent(runURL: URL) throws -> RichAnswerEvidenceMergeSourceMetadata? {
        let url = runURL.appendingPathComponent("run.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(RichAnswerEvidenceMergeSourceMetadata.self, from: data)
        } catch {
            throw RichAnswerEvidenceError.invalidConfiguration("cannot decode source run metadata at \(url.path): \(error.localizedDescription)")
        }
    }

    private static func readRecord(recordURL: URL) throws -> RichAnswerEvidenceMergeRecord {
        do {
            let data = try Data(contentsOf: recordURL)
            return try JSONDecoder().decode(RichAnswerEvidenceMergeRecord.self, from: data)
        } catch {
            throw RichAnswerEvidenceError.invalidConfiguration("cannot decode source record at \(recordURL.path): \(error.localizedDescription)")
        }
    }

    private static func missingKeys(
        repetitions: [Int],
        matrixCases: [RichAnswerLiveRunCase],
        recordsByKey: [RichAnswerEvidenceMergeRecordKey: RichAnswerEvidenceMergeInputRecord]
    ) -> [String] {
        var missing: [String] = []
        for repetition in repetitions {
            for runCase in matrixCases {
                let key = RichAnswerEvidenceMergeRecordKey(repetition: repetition, caseID: runCase.id)
                if recordsByKey[key] == nil {
                    missing.append("rep=\(repetition) case=\(runCase.id)")
                }
            }
        }
        return missing
    }

    private static func relativePath(_ url: URL, rootURL: URL) -> String {
        let root = rootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(root + "/") else { return path }
        return String(path.dropFirst(root.count + 1))
    }

    private static func write<Value: Encodable>(_ value: Value, to url: URL, encoder: JSONEncoder) throws {
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    private static func writePlainText(_ value: String, to url: URL) throws {
        try value.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    private static func indexMarkdown(_ index: RichAnswerEvidenceMergedRunIndex) -> String {
        let rows = index.records.map { entry in
            "| \(entry.repetition) | \(entry.sequence) | \(entry.sourceRunID) | \(entry.sourceSequence) | \(entry.caseKind) | \(entry.caseID) | \(entry.subject) | \(entry.status) | \(entry.actualShape) | \(String(format: "%.3f", entry.elapsedSeconds)) | [record](\(entry.recordPath)) |"
        }.joined(separator: "\n")
        return """
        # 富回答聚合证据索引 \(index.runID)

        - root: \(index.rootPath)
        - updatedAt: \(index.updatedAt)
        - inputRunIDs: \(index.inputRunIDs.joined(separator: ", "))
        - repetitions: \(index.repetitions.map(String.init).joined(separator: ", "))
        - expected: \(index.expectedRecordCount) records = \(index.expectedCaseCount) cases × \(index.repetitions.count) repetitions
        - totalRecords: \(index.totalRecords)
        - statusCounts: \(index.statusCounts.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", "))
        - completionState: \(index.completionState)
        - baselineID: \(index.reviewSummary.baselineID ?? "missing")
        - baselineGaps: \(index.reviewSummary.baselineMismatchKeys.count)
        - reviewPackage: [逐题验收包](\(index.reviewPackagePath))
        - screenshotManifest: \(index.screenshotManifestPath ?? "未提供；验收包会醒目标出 missing evidence")
        - firstPassTrusted: \(index.reviewSummary.firstPassTrustedInvocationCount)/\(index.reviewSummary.expectedFirstPassRecordCount)
        - fourRoundTrusted: \(index.reviewSummary.threeRoundTrustedInvocationCount)/\(index.reviewSummary.expectedThreeRoundRecordCount)
        - screenshotImages: \(index.reviewSummary.threeRoundScreenshotImageCount)/\(index.reviewSummary.expectedThreeRoundScreenshotImageCount)
        - sevenPartReview: \(index.reviewSummary.threeRoundReviewedItemCount)/\(index.reviewSummary.expectedThreeRoundReviewItemCount), gaps=\(index.reviewSummary.reviewGapItemCount)

        | repetition | sequence | sourceRun | sourceSeq | kind | case | subject | status | shape | seconds | record |
        | --- | ---: | --- | ---: | --- | --- | --- | --- | --- | ---: | --- |
        \(rows)
        """
    }

    private static func indexHTML(_ index: RichAnswerEvidenceMergedRunIndex) -> String {
        let rows = index.records.map { entry in
            """
            <tr>
              <td>\(entry.repetition)</td>
              <td>\(entry.sequence)</td>
              <td>\(escapeHTML(entry.sourceRunID))</td>
              <td>\(entry.sourceSequence)</td>
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
          <title>富回答聚合证据索引 \(escapeHTML(index.runID))</title>
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
          <h1>富回答聚合证据索引</h1>
          <p><strong>runID</strong>: \(escapeHTML(index.runID))</p>
          <p><strong>root</strong>: \(escapeHTML(index.rootPath))</p>
          <p><strong>inputRunIDs</strong>: \(escapeHTML(index.inputRunIDs.joined(separator: ", ")))</p>
          <p><strong>expected</strong>: \(index.expectedRecordCount) records = \(index.expectedCaseCount) cases × \(index.repetitions.count) repetitions</p>
          <p><strong>statusCounts</strong>: \(escapeHTML(index.statusCounts.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", ")))</p>
          <p><strong>completionState</strong>: \(escapeHTML(index.completionState))</p>
          <p><strong>baseline</strong>: \(escapeHTML(index.reviewSummary.baselineID ?? "missing")), gaps \(index.reviewSummary.baselineMismatchKeys.count)</p>
          <p><strong>reviewPackage</strong>: <a href="\(escapeHTML(index.reviewPackagePath))">打开逐题验收包</a></p>
          <p><strong>trustedInvocation</strong>: first \(index.reviewSummary.firstPassTrustedInvocationCount)/\(index.reviewSummary.expectedFirstPassRecordCount), four rounds \(index.reviewSummary.threeRoundTrustedInvocationCount)/\(index.reviewSummary.expectedThreeRoundRecordCount)</p>
          <p><strong>screenshots</strong>: \(index.reviewSummary.threeRoundScreenshotImageCount)/\(index.reviewSummary.expectedThreeRoundScreenshotImageCount) images, minimum \(index.reviewSummary.minimumRequiredScreenshotImageCount), gaps \(index.reviewSummary.screenshotGapAttemptCount)</p>
          <p><strong>sevenPartReview</strong>: \(index.reviewSummary.threeRoundReviewedItemCount)/\(index.reviewSummary.expectedThreeRoundReviewItemCount), gaps \(index.reviewSummary.reviewGapItemCount), experience pass attempts \(index.reviewSummary.experiencePassedAttemptCount)</p>
          <table>
            <thead><tr><th>轮次</th><th>总序号</th><th>来源 run</th><th>来源序号</th><th>类型</th><th>题目</th><th>学科</th><th>状态</th><th>形态</th><th>耗时</th><th>失败原因</th></tr></thead>
            <tbody>
            \(rows)
            </tbody>
          </table>
        </body>
        </html>
        """
    }

    private static func summarize(_ values: [String], limit: Int = 30) -> String {
        let head = values.prefix(limit).joined(separator: " | ")
        let remaining = values.count - min(values.count, limit)
        return remaining > 0 ? "\(head) | ... +\(remaining) more" : head
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}

private struct RichAnswerEvidenceMergeRecordKey: Hashable {
    let repetition: Int
    let caseID: String
}

private struct RichAnswerEvidenceMergeInputRecord {
    let sourceRunID: String
    let sourceRecordPath: String
    let sourceRecordURL: URL
    let sourceSequence: Int
    let record: RichAnswerEvidenceMergeRecord
}

private struct RichAnswerEvidenceMergeRecord: Decodable {
    var runID: String
    var repetition: Int
    var sequence: Int
    var caseSnapshot: RichAnswerEvidenceMergeCaseSnapshot
    var elapsedSeconds: TimeInterval
    var status: String
    var shapeDecision: RichAnswerEvidenceMergeShapeDecision
    var failureReason: String?
}

private struct RichAnswerEvidenceMergeCaseSnapshot: Decodable {
    var id: String
    var caseKind: String
    var subject: String
}

private struct RichAnswerEvidenceMergeShapeDecision: Decodable {
    var actualShape: String
}

private struct RichAnswerEvidenceMergeSourceMetadata: Decodable {
    var runID: String
    var repetitions: [Int]
}

private struct RichAnswerEvidenceMergeSourceRun: Codable {
    var runID: String
    var rootPath: String
    var declaredRepetitions: [Int]
    var rawRecordCount: Int
}

private struct RichAnswerEvidenceMergedRunMetadata: Codable {
    var schemaVersion: Int
    var runID: String
    var createdAt: String
    var rootPath: String
    var sourceRuns: [RichAnswerEvidenceMergeSourceRun]
    var repetitions: [Int]
    var expectedCaseCount: Int
    var expectedRecordCount: Int
    var totalRecords: Int
    var completionState: String
    var reviewPackagePath: String
    var screenshotManifestPath: String?
}

private struct RichAnswerEvidenceMergedRunIndex: Codable {
    var schemaVersion: Int
    var runID: String
    var updatedAt: String
    var rootPath: String
    var inputRunIDs: [String]
    var repetitions: [Int]
    var expectedCaseCount: Int
    var expectedRecordCount: Int
    var totalRecords: Int
    var statusCounts: [String: Int]
    var completionState: String
    var reviewPackagePath: String
    var screenshotManifestPath: String?
    var reviewSummary: RichAnswerEvidencePackageSummary
    var records: [RichAnswerEvidenceMergedIndexEntry]
}

private struct RichAnswerEvidenceMergedIndexEntry: Codable {
    var runID: String
    var sourceRunID: String
    var repetition: Int
    var sequence: Int
    var sourceSequence: Int
    var caseID: String
    var caseKind: String
    var subject: String
    var status: String
    var elapsedSeconds: TimeInterval
    var actualShape: String
    var recordPath: String
    var failureReason: String?
}

private final class RichAnswerEvidenceMergeLock {
    private let lockURL: URL
    private var isHeld = false

    init(rootURL: URL, runID: String) throws {
        lockURL = rootURL.appendingPathComponent(".run.lock")
        let descriptor = open(lockURL.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            let owner = (try? String(contentsOf: lockURL, encoding: .utf8))
                .map { "\ncurrent lock:\n\($0)" } ?? ""
            throw RichAnswerEvidenceError.invalidConfiguration(
                "merged runID \(runID) is already being written; refusing concurrent merge writes at \(lockURL.path)\(owner)"
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

    func release() {
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
