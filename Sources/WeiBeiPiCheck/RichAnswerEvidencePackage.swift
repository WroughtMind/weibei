import CryptoKit
import Foundation

struct RichAnswerEvidencePackageExpectedCase {
    let sequence: Int
    let caseID: String
    let caseKind: String
    let subject: String
}

struct RichAnswerEvidencePackageRecordReference {
    let sourceRunID: String
    let sourceSequence: Int
    let repetition: Int
    let caseID: String
    let caseKind: String
    let subject: String
    let recordURL: URL
    let recordPathFromMergedRoot: String
}

struct RichAnswerEvidencePackageBuildInput {
    let runID: String
    let mergedRootURL: URL
    let expectedCases: [RichAnswerEvidencePackageExpectedCase]
    let observedRepetitions: [Int]
    let records: [RichAnswerEvidencePackageRecordReference]
    let screenshotManifestURL: URL?
}

struct RichAnswerEvidencePackageResult {
    let rootURL: URL
    let indexURL: URL
    let summary: RichAnswerEvidencePackageSummary
}

struct RichAnswerEvidencePackageSummary: Codable {
    let completionState: String
    let automaticCompletionAllowed: Bool
    let expectedCaseCount: Int
    let requiredCaseCount: Int
    let uniqueCaseCount: Int
    let expectedFirstPassRecordCount: Int
    let firstPassRecordCount: Int
    let firstPassTrustedInvocationCount: Int
    let firstPassCompleteEvidenceCount: Int
    let firstPassPassedCount: Int
    let expectedThreeRoundRecordCount: Int
    let threeRoundRecordCount: Int
    let threeRoundTrustedInvocationCount: Int
    let threeRoundCompleteEvidenceCount: Int
    let threeRoundPassedCount: Int
    let stableThreeRoundCaseCount: Int
    let modelInvocationCount: Int
    let deterministicInvocationCount: Int
    let fixtureInvocationCount: Int
    let unknownInvocationCount: Int
    let contradictoryInvocationCount: Int
    let nonModelInvocationCount: Int
    let firstPassScreenshotCompleteCount: Int
    let threeRoundScreenshotCompleteCount: Int
    let expectedFirstPassScreenshotImageCount: Int
    let firstPassScreenshotImageCount: Int
    let expectedThreeRoundScreenshotImageCount: Int
    let minimumRequiredScreenshotImageCount: Int
    let threeRoundScreenshotImageCount: Int
    let screenshotMinimumSatisfied: Bool
    let screenshotGapAttemptCount: Int
    let screenshotMissingImageCount: Int
    let expectedFirstPassReviewItemCount: Int
    let firstPassReviewedItemCount: Int
    let expectedThreeRoundReviewItemCount: Int
    let threeRoundReviewedItemCount: Int
    let reviewCompleteAttemptCount: Int
    let experiencePassedAttemptCount: Int
    let reviewGapItemCount: Int
    let shapeDriftCaseIDs: [String]
    let contentDriftCaseIDs: [String]
    let missingFirstPassCaseIDs: [String]
    let missingThreeRoundRecordKeys: [String]
    let missingScreenshotKeys: [String]
    let missingRecordEvidenceKeys: [String]
    let reviewGapKeys: [String]
    let fixtureOrUntrustedRecordKeys: [String]
    let baselineID: String?
    let baselineManifestPath: String?
    let baselineMismatchKeys: [String]
}

enum RichAnswerEvidencePackageBuilder {
    private static let completionState = "待用户验收"
    private static let targetRepetitions = [1, 2, 3, 4]
    private static let requiredCaseCount = 56
    private static let minimumRequiredScreenshotImageCount = 384

    static func build(input: RichAnswerEvidencePackageBuildInput) throws -> RichAnswerEvidencePackageResult {
        try assertSucceededScreenshotRecordWinsDuplicateFixture()
        let fileManager = FileManager.default
        let rootURL = input.mergedRootURL.appendingPathComponent("review-package", isDirectory: true)
        if fileManager.fileExists(atPath: rootURL.path) {
            throw RichAnswerEvidenceError.invalidConfiguration(
                "review package already exists and will not be overwritten silently: \(rootURL.path). Move it aside explicitly before rebuilding the package."
            )
        }
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: rootURL.appendingPathComponent("cases", isDirectory: true),
            withIntermediateDirectories: true
        )

        let screenshotManifest = try readScreenshotManifest(input.screenshotManifestURL)
        let screenshotsByRecordPath = screenshotManifest.map(indexScreenshotsByRecordPath) ?? [:]
        let baselineID = screenshotManifest?.baselineID
        let baselineManifestPath = screenshotManifest?.baselineManifestPath
        let copiedBaselineManifestPath = try copyBaselineManifestIfPresent(
            baselineManifestPath,
            packageRootURL: rootURL
        )
        let parsedAttempts = try input.records.map { reference -> RichAnswerEvidencePackageAttempt in
            let record = try RichAnswerEvidencePackageRecord(reference: reference)
            let artifacts = try collectRecordArtifacts(record: record, packageRootURL: rootURL)
            let screenshot = try collectScreenshotEvidence(
                record: record,
                screenshotRecord: screenshotsByRecordPath[canonicalPath(reference.recordURL)],
                packageRootURL: rootURL
            )
            return RichAnswerEvidencePackageAttempt(
                record: record,
                artifacts: artifacts,
                screenshot: screenshot
            )
        }

        let expectedCases = try validatedExpectedCases(input.expectedCases)
            .sorted { $0.sequence < $1.sequence }
        let uniqueCaseCount = Set(expectedCases.map(\.caseID)).count
        let attemptsByCase = Dictionary(grouping: parsedAttempts, by: { $0.record.caseID })
        var caseSummaries: [RichAnswerEvidencePackageCaseSummary] = []
        var shapeDriftCaseIDs: [String] = []
        var contentDriftCaseIDs: [String] = []
        var missingFirstPassCaseIDs: [String] = []
        var missingThreeRoundRecordKeys: [String] = []
        var missingScreenshotKeys: [String] = []
        var missingRecordEvidenceKeys: [String] = []
        var reviewGapKeys: [String] = []
        var baselineMismatchKeys: [String] = []

        for expectedCase in expectedCases {
            let attempts = (attemptsByCase[expectedCase.caseID] ?? []).sorted {
                $0.record.repetition < $1.record.repetition
            }
            let attemptsByRepetition = Dictionary(uniqueKeysWithValues: attempts.map {
                ($0.record.repetition, $0)
            })
            let trustedAttempts = attempts.filter(\.isTrustedInvocation)
            let shapeValues = Set(trustedAttempts.map { $0.record.actualShape }.filter { !$0.isEmpty })
            let contentValues = Set(trustedAttempts.compactMap { $0.record.normalizedModelText }.filter { !$0.isEmpty })
            let shapeDrift = shapeValues.count > 1
            let contentDrift = contentValues.count > 1
            if shapeDrift { shapeDriftCaseIDs.append(expectedCase.caseID) }
            if contentDrift { contentDriftCaseIDs.append(expectedCase.caseID) }
            if attemptsByRepetition[1] == nil { missingFirstPassCaseIDs.append(expectedCase.caseID) }

            var completeScreenshotRepetitions: [Int] = []
            for repetition in targetRepetitions {
                let key = evidenceKey(repetition: repetition, caseID: expectedCase.caseID)
                guard let attempt = attemptsByRepetition[repetition] else {
                    missingThreeRoundRecordKeys.append(key)
                    missingScreenshotKeys.append("\(key) missing=record")
                    reviewGapKeys.append(contentsOf: RichAnswerEvidenceExperienceReview.dimensions.map {
                        "\(key) review=\($0.key) missing=record"
                    })
                    continue
                }
                let missingRecordEvidence = attempt.record.missingRequiredEvidenceFields
                    + attempt.artifacts.missingKinds.map { "package:\($0)" }
                if !missingRecordEvidence.isEmpty {
                    missingRecordEvidenceKeys.append(
                        "\(key) missing=\(missingRecordEvidence.joined(separator: ","))"
                    )
                }
                if attempt.screenshot.isComplete {
                    completeScreenshotRepetitions.append(repetition)
                } else {
                    missingScreenshotKeys.append(
                        "\(key) missing=\(attempt.screenshot.missingKinds.joined(separator: ","))"
                    )
                }
                if repetition == 1 {
                    if baselineID == nil {
                        baselineMismatchKeys.append("\(key) baseline=missing-batch-baseline")
                    } else if attempt.screenshot.baselineID != baselineID {
                        baselineMismatchKeys.append("\(key) baseline=\(attempt.screenshot.baselineID ?? "missing") expected=\(baselineID ?? "missing")")
                    }
                }
                for item in attempt.record.review.items where !attempt.isTrustedInvocation || !item.isReviewed {
                    reviewGapKeys.append(
                        "\(key) review=\(item.key) missing=\(attempt.isTrustedInvocation ? "pending" : "untrusted-invocation")"
                    )
                }
            }

            let pagePath = "cases/\(safePathComponent(expectedCase.caseID)).html"
            let summary = RichAnswerEvidencePackageCaseSummary(
                sequence: expectedCase.sequence,
                caseID: expectedCase.caseID,
                caseKind: expectedCase.caseKind,
                subject: expectedCase.subject,
                casePagePath: pagePath,
                observedRepetitions: attempts.map { $0.record.repetition },
                trustedRepetitions: trustedAttempts.map { $0.record.repetition },
                screenshotCompleteRepetitions: completeScreenshotRepetitions,
                reviewCompleteRepetitions: trustedAttempts.filter { $0.record.review.isComplete }.map { $0.record.repetition },
                experiencePassedRepetitions: trustedAttempts.filter { $0.record.review.isExperiencePass }.map { $0.record.repetition },
                shapeDrift: shapeDrift,
                contentDrift: contentDrift,
                attempts: attempts.map(\.summary)
            )
            caseSummaries.append(summary)
            let pageURL = rootURL.appendingPathComponent(pagePath)
            try writeText(
                caseHTML(expectedCase: expectedCase, attemptsByRepetition: attemptsByRepetition),
                to: pageURL
            )
        }

        let observedTargetAttempts = parsedAttempts.filter { targetRepetitions.contains($0.record.repetition) }
        let firstPassAttempts = parsedAttempts.filter { $0.record.repetition == 1 }
        let expectedFirstPassImages = expectedCases.reduce(0) { $0 + expectedImageCount(caseKind: $1.caseKind) }
        let expectedThreeRoundImages = expectedFirstPassImages * targetRepetitions.count
        let capturedFirstPassImages = firstPassAttempts.reduce(0) { $0 + $1.screenshot.capturedImageCount }
        let capturedThreeRoundImages = observedTargetAttempts.reduce(0) { $0 + $1.screenshot.capturedImageCount }
        let screenshotMissingImageCount = expectedThreeRoundImages - capturedThreeRoundImages
        let firstPassReviewedItems = firstPassAttempts.filter(\.isTrustedInvocation).reduce(0) {
            $0 + $1.record.review.reviewedItemCount
        }
        let threeRoundReviewedItems = observedTargetAttempts.filter(\.isTrustedInvocation).reduce(0) {
            $0 + $1.record.review.reviewedItemCount
        }
        let fixtureOrUntrustedKeys = observedTargetAttempts
            .filter { !$0.isTrustedInvocation }
            .map { evidenceKey(repetition: $0.record.repetition, caseID: $0.record.caseID) }
            .sorted()
        let fullyStableCaseCount = expectedCases.filter { expectedCase in
            let attempts = (attemptsByCase[expectedCase.caseID] ?? []).filter {
                targetRepetitions.contains($0.record.repetition)
            }
            return Set(attempts.map { $0.record.repetition }) == Set(targetRepetitions)
                && attempts.allSatisfy(\.isTrustedInvocation)
                && attempts.allSatisfy { $0.record.missingRequiredEvidenceFields.isEmpty }
                && attempts.allSatisfy { $0.artifacts.missingKinds.isEmpty }
                && attempts.allSatisfy { $0.screenshot.isComplete }
                && attempts.allSatisfy { $0.record.review.isComplete }
                && attempts.allSatisfy { $0.record.review.isExperiencePass }
                && Set(attempts.map { $0.record.actualShape }).count <= 1
                && Set(attempts.compactMap { $0.record.normalizedModelText }).count <= 1
        }.count

        let summary = RichAnswerEvidencePackageSummary(
            completionState: completionState,
            automaticCompletionAllowed: false,
            expectedCaseCount: expectedCases.count,
            requiredCaseCount: requiredCaseCount,
            uniqueCaseCount: uniqueCaseCount,
            expectedFirstPassRecordCount: expectedCases.count,
            firstPassRecordCount: firstPassAttempts.count,
            firstPassTrustedInvocationCount: firstPassAttempts.filter(\.isTrustedInvocation).count,
            firstPassCompleteEvidenceCount: firstPassAttempts.filter {
                $0.isTrustedInvocation
                    && $0.record.missingRequiredEvidenceFields.isEmpty
                    && $0.artifacts.missingKinds.isEmpty
            }.count,
            firstPassPassedCount: firstPassAttempts.filter { $0.record.status == "passed" }.count,
            expectedThreeRoundRecordCount: expectedCases.count * targetRepetitions.count,
            threeRoundRecordCount: observedTargetAttempts.count,
            threeRoundTrustedInvocationCount: observedTargetAttempts.filter(\.isTrustedInvocation).count,
            threeRoundCompleteEvidenceCount: observedTargetAttempts.filter {
                $0.isTrustedInvocation
                    && $0.record.missingRequiredEvidenceFields.isEmpty
                    && $0.artifacts.missingKinds.isEmpty
            }.count,
            threeRoundPassedCount: observedTargetAttempts.filter { $0.record.status == "passed" }.count,
            stableThreeRoundCaseCount: fullyStableCaseCount,
            modelInvocationCount: observedTargetAttempts.filter { $0.invocationKind == .model }.count,
            deterministicInvocationCount: observedTargetAttempts.filter { $0.invocationKind == .deterministic }.count,
            fixtureInvocationCount: observedTargetAttempts.filter { $0.invocationKind == .fixture }.count,
            unknownInvocationCount: observedTargetAttempts.filter { $0.invocationKind == .unknown }.count,
            contradictoryInvocationCount: observedTargetAttempts.filter { $0.invocationKind == .contradictory }.count,
            nonModelInvocationCount: observedTargetAttempts.filter { $0.invocationKind == .nonModel }.count,
            firstPassScreenshotCompleteCount: firstPassAttempts.filter { $0.screenshot.isComplete }.count,
            threeRoundScreenshotCompleteCount: observedTargetAttempts.filter { $0.screenshot.isComplete }.count,
            expectedFirstPassScreenshotImageCount: expectedFirstPassImages,
            firstPassScreenshotImageCount: capturedFirstPassImages,
            expectedThreeRoundScreenshotImageCount: expectedThreeRoundImages,
            minimumRequiredScreenshotImageCount: minimumRequiredScreenshotImageCount,
            threeRoundScreenshotImageCount: capturedThreeRoundImages,
            screenshotMinimumSatisfied: capturedThreeRoundImages >= minimumRequiredScreenshotImageCount,
            screenshotGapAttemptCount: missingScreenshotKeys.count,
            screenshotMissingImageCount: max(0, screenshotMissingImageCount),
            expectedFirstPassReviewItemCount: expectedCases.count * RichAnswerEvidenceExperienceReview.dimensions.count,
            firstPassReviewedItemCount: firstPassReviewedItems,
            expectedThreeRoundReviewItemCount: expectedCases.count * targetRepetitions.count * RichAnswerEvidenceExperienceReview.dimensions.count,
            threeRoundReviewedItemCount: threeRoundReviewedItems,
            reviewCompleteAttemptCount: observedTargetAttempts.filter {
                $0.isTrustedInvocation && $0.record.review.isComplete
            }.count,
            experiencePassedAttemptCount: observedTargetAttempts.filter {
                $0.isTrustedInvocation && $0.record.review.isExperiencePass
            }.count,
            reviewGapItemCount: reviewGapKeys.count,
            shapeDriftCaseIDs: shapeDriftCaseIDs.sorted(),
            contentDriftCaseIDs: contentDriftCaseIDs.sorted(),
            missingFirstPassCaseIDs: missingFirstPassCaseIDs.sorted(),
            missingThreeRoundRecordKeys: missingThreeRoundRecordKeys.sorted(),
            missingScreenshotKeys: missingScreenshotKeys.sorted(),
            missingRecordEvidenceKeys: missingRecordEvidenceKeys.sorted(),
            reviewGapKeys: reviewGapKeys.sorted(),
            fixtureOrUntrustedRecordKeys: fixtureOrUntrustedKeys,
            baselineID: baselineID,
            baselineManifestPath: copiedBaselineManifestPath ?? baselineManifestPath,
            baselineMismatchKeys: baselineMismatchKeys.sorted()
        )

        let document = RichAnswerEvidencePackageDocument(
            schemaVersion: 1,
            runID: input.runID,
            generatedAt: timestamp(),
            completionState: completionState,
            screenshotManifestPath: input.screenshotManifestURL?.path,
            baselineManifestPath: copiedBaselineManifestPath ?? baselineManifestPath,
            observedRepetitions: input.observedRepetitions,
            summary: summary,
            cases: caseSummaries
        )
        try writeJSON(document, to: rootURL.appendingPathComponent("package.json"))
        try writeText(indexMarkdown(document), to: rootURL.appendingPathComponent("index.md"))
        let indexURL = rootURL.appendingPathComponent("index.html")
        try writeText(indexHTML(document), to: indexURL)
        return RichAnswerEvidencePackageResult(rootURL: rootURL, indexURL: indexURL, summary: summary)
    }

    private static func readScreenshotManifest(_ url: URL?) throws -> RichAnswerScreenshotBatchManifest? {
        guard let url else { return nil }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw RichAnswerEvidenceError.invalidConfiguration(
                "screenshot manifest does not exist: \(url.path)"
            )
        }
        do {
            return try JSONDecoder().decode(
                RichAnswerScreenshotBatchManifest.self,
                from: Data(contentsOf: url)
            )
        } catch {
            throw RichAnswerEvidenceError.invalidConfiguration(
                "cannot decode screenshot manifest at \(url.path): \(error.localizedDescription)"
            )
        }
    }

    private static func validatedExpectedCases(
        _ cases: [RichAnswerEvidencePackageExpectedCase]
    ) throws -> [RichAnswerEvidencePackageExpectedCase] {
        let caseIDs = cases.map(\.caseID)
        let uniqueIDs = Set(caseIDs)
        guard cases.count == requiredCaseCount,
              uniqueIDs.count == requiredCaseCount else {
            throw RichAnswerEvidenceError.invalidConfiguration(
                "rich-answer package requires \(requiredCaseCount) unique cases; got total=\(cases.count) unique=\(uniqueIDs.count)"
            )
        }
        let kindCounts = Dictionary(grouping: cases, by: \.caseKind).mapValues(\.count)
        guard kindCounts["rich"] == 40,
              kindCounts["text-only"] == 6,
              kindCounts["degradation"] == 9,
              kindCounts["invalid-protocol"] == 1 else {
            throw RichAnswerEvidenceError.invalidConfiguration(
                "rich-answer package matrix must be 40 rich + 6 text-only + 9 degradation + 1 invalid-protocol; got \(kindCounts)"
            )
        }
        return cases
    }

    private static func indexScreenshotsByRecordPath(
        _ manifest: RichAnswerScreenshotBatchManifest
    ) -> [String: RichAnswerScreenshotRecord] {
        var result: [String: RichAnswerScreenshotRecord] = [:]
        for record in manifest.records {
            guard let replayArtifact = nonEmpty(record.replayArtifact) else { continue }
            let key = canonicalPath(URL(fileURLWithPath: replayArtifact))
            if result[key] == nil || record.status == "succeeded" {
                result[key] = record
            }
        }
        return result
    }

    private static func copyBaselineManifestIfPresent(
        _ path: String?,
        packageRootURL: URL
    ) throws -> String? {
        guard let path = nonEmpty(path) else { return nil }
        let sourceURL = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { return nil }
        let relativePath = "baseline-manifest.json"
        let destinationURL = packageRootURL.appendingPathComponent(relativePath)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            let archivedURL = packageRootURL.appendingPathComponent(
                "baseline-manifest-previous-\(safeTimestampForPath()).json"
            )
            try FileManager.default.moveItem(at: destinationURL, to: archivedURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return relativePath
    }

    private static func assertSucceededScreenshotRecordWinsDuplicateFixture() throws {
        let replayArtifact = "/private/tmp/weibei-duplicate-screenshot-fixture/record.json"
        let failed = RichAnswerScreenshotRecord(
            status: "failed",
            captureStatus: "failed",
            failureReason: "fixture failure",
            captureKind: "rich-interaction",
            replayArtifact: replayArtifact,
            caseID: nil,
            caseKind: nil,
            repetition: nil,
            sequence: nil,
            baselineID: nil,
            baselineManifestPath: nil,
            recordPath: nil,
            recordSHA256: nil,
            screenshots: RichAnswerScreenshotPaths(overview: nil, before: nil, after: nil, single: nil),
            screenshotSHA256: nil,
            screenshotEvidence: nil,
            captureReceipts: nil,
            qualityGate: nil,
            reviewStatus: nil
        )
        let succeeded = RichAnswerScreenshotRecord(
            status: "succeeded",
            captureStatus: "succeeded",
            failureReason: nil,
            captureKind: "rich-interaction",
            replayArtifact: replayArtifact,
            caseID: nil,
            caseKind: nil,
            repetition: nil,
            sequence: nil,
            baselineID: nil,
            baselineManifestPath: nil,
            recordPath: nil,
            recordSHA256: nil,
            screenshots: RichAnswerScreenshotPaths(
                overview: nil,
                before: "/private/tmp/before.png",
                after: "/private/tmp/after.png",
                single: nil
            ),
            screenshotSHA256: nil,
            screenshotEvidence: nil,
            captureReceipts: nil,
            qualityGate: nil,
            reviewStatus: nil
        )
        let key = canonicalPath(URL(fileURLWithPath: replayArtifact))
        for records in [[failed, succeeded], [succeeded, failed]] {
            let selected = indexScreenshotsByRecordPath(
                RichAnswerScreenshotBatchManifest(
                    baselineID: nil,
                    baselineManifestPath: nil,
                    records: records
                )
            )[key]
            guard selected?.status == "succeeded" else {
                throw RichAnswerEvidenceError.invalidConfiguration(
                    "duplicate screenshot fixture failed: succeeded record must win regardless of order"
                )
            }
        }
    }

    private static func collectRecordArtifacts(
        record: RichAnswerEvidencePackageRecord,
        packageRootURL: URL
    ) throws -> RichAnswerEvidencePackageArtifacts {
        let relativeDirectory = [
            "evidence",
            repetitionDirectoryName(record.repetition),
            safePathComponent(record.caseID),
        ].joined(separator: "/")
        let destinationDirectory = packageRootURL.appendingPathComponent(
            relativeDirectory,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: destinationDirectory,
            withIntermediateDirectories: true
        )
        let sourceDirectory = record.reference.recordURL.deletingLastPathComponent()
        var copiedPaths: [String: String] = [:]
        var missingKinds: [String] = []

        func copy(_ fileName: String, required: Bool) throws {
            let sourceURL = sourceDirectory.appendingPathComponent(fileName)
            let destinationURL = destinationDirectory.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: sourceURL.path) {
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                copiedPaths[fileName] = "\(relativeDirectory)/\(fileName)"
            } else if required {
                missingKinds.append(fileName)
            }
        }

        try copy("record.json", required: true)
        if FileManager.default.fileExists(atPath: sourceDirectory.appendingPathComponent("request.json").path) {
            try copy("request.json", required: true)
        } else if let rawRequestJSON = record.rawRequestJSON {
            try writeText(rawRequestJSON, to: destinationDirectory.appendingPathComponent("request.json"))
            copiedPaths["request.json"] = "\(relativeDirectory)/request.json"
        } else if record.caseKind != "invalid-protocol" {
            missingKinds.append("request.json")
        }
        if FileManager.default.fileExists(atPath: sourceDirectory.appendingPathComponent("reply.json").path) {
            try copy("reply.json", required: true)
        } else if let rawModelReplyJSON = record.rawModelReplyJSON {
            try writeText(rawModelReplyJSON, to: destinationDirectory.appendingPathComponent("reply.json"))
            copiedPaths["reply.json"] = "\(relativeDirectory)/reply.json"
        } else if record.caseKind != "invalid-protocol" {
            missingKinds.append("reply.json")
        }
        if FileManager.default.fileExists(atPath: sourceDirectory.appendingPathComponent("review.json").path) {
            try copy("review.json", required: false)
        } else if let rawReviewJSON = record.review.rawJSON {
            try writeText(rawReviewJSON, to: destinationDirectory.appendingPathComponent("review.json"))
            copiedPaths["review.json"] = "\(relativeDirectory)/review.json"
        }
        try copy("validation.json", required: false)
        try copy("model-response.txt", required: false)
        try copy("summary.md", required: false)
        return RichAnswerEvidencePackageArtifacts(
            copiedPaths: copiedPaths,
            missingKinds: missingKinds
        )
    }

    private static func collectScreenshotEvidence(
        record: RichAnswerEvidencePackageRecord,
        screenshotRecord: RichAnswerScreenshotRecord?,
        packageRootURL: URL
    ) throws -> RichAnswerEvidencePackageScreenshot {
        let expectedKinds = record.caseKind == "rich" ? ["before", "after"] : ["single"]
        guard let screenshotRecord else {
            return RichAnswerEvidencePackageScreenshot(
                manifestStatus: "missing",
                captureStatus: nil,
                captureKind: nil,
                failureReason: "没有与 record.json 精确回链的截图记录",
                copiedPaths: [:],
                sha256ByKind: [:],
                recordSHA256: nil,
                qualityGateStatus: nil,
                reviewStatus: nil,
                baselineID: nil,
                baselineManifestPath: nil,
                expectedKinds: expectedKinds,
                missingKinds: expectedKinds
            )
        }

        let sourcePaths = [
            "overview": screenshotRecord.screenshots.overview,
            "before": screenshotRecord.screenshots.before,
            "after": screenshotRecord.screenshots.after,
            "single": screenshotRecord.screenshots.single,
        ]
        let sourceHashes = [
            "overview": screenshotRecord.screenshotSHA256?.overview,
            "before": screenshotRecord.screenshotSHA256?.before,
            "after": screenshotRecord.screenshotSHA256?.after,
            "single": screenshotRecord.screenshotSHA256?.single,
        ]
        let optionalKinds = ["overview"].filter { kind in
            screenshotRecord.screenshotEvidence?.item(for: kind) != nil
                || nonEmpty(sourcePaths[kind] ?? nil) != nil
        }
        let kindsToValidate = expectedKinds + optionalKinds.filter { !expectedKinds.contains($0) }
        let expectedCaptureKind = record.caseKind == "rich" ? "rich-interaction" : "single"
        let qualityGateStatus = nonEmpty(screenshotRecord.qualityGate?.status)
        let reviewStatus = nonEmpty(screenshotRecord.reviewStatus)
        var copiedPaths: [String: String] = [:]
        var sha256ByKind: [String: String] = [:]
        var missingKinds: [String] = []
        let actualRecordSHA256 = try sha256(of: record.reference.recordURL)
        if screenshotRecord.caseID != record.caseID {
            missingKinds.append("manifest.caseID")
        }
        if screenshotRecord.caseKind != record.caseKind {
            missingKinds.append("manifest.caseKind")
        }
        if screenshotRecord.repetition != record.repetition {
            missingKinds.append("manifest.repetition")
        }
        if nonEmpty(screenshotRecord.recordPath) != record.reference.recordPathFromMergedRoot {
            missingKinds.append("manifest.recordPath")
        }
        if nonEmpty(screenshotRecord.recordSHA256) != actualRecordSHA256 {
            missingKinds.append("recordSHA256")
        }
        if screenshotRecord.captureStatus != "succeeded" {
            missingKinds.append("captureStatus")
        }
        if screenshotRecord.captureKind != expectedCaptureKind {
            missingKinds.append("captureKind")
        }
        if !["pass", "warn"].contains(qualityGateStatus ?? "") {
            missingKinds.append("qualityGate.status")
        }
        if reviewStatus == nil {
            missingKinds.append("reviewStatus")
        }
        if nonEmpty(screenshotRecord.baselineID) == nil {
            missingKinds.append("baselineID")
        }
        if screenshotRecord.status != "succeeded",
           nonEmpty(screenshotRecord.failureReason) == nil {
            missingKinds.append("failureReason")
        }
        for kind in kindsToValidate {
            let evidenceItem = screenshotRecord.screenshotEvidence?.item(for: kind)
            guard let rawPath = evidenceItem?.path ?? sourcePaths[kind] ?? nil,
                  let path = nonEmpty(rawPath),
                  FileManager.default.fileExists(atPath: path) else {
                missingKinds.append(kind)
                continue
            }
            let sourceURL = URL(fileURLWithPath: path)
            let actualSHA256 = try sha256(of: sourceURL)
            guard let expectedSHA256 = nonEmpty(evidenceItem?.sha256 ?? sourceHashes[kind] ?? nil) else {
                missingKinds.append("\(kind).sha256")
                continue
            }
            guard expectedSHA256 == actualSHA256 else {
                missingKinds.append("\(kind).sha256Mismatch")
                continue
            }
            let actualBytes = try byteCount(of: sourceURL)
            if let expectedBytes = evidenceItem?.bytes,
               expectedBytes != actualBytes {
                missingKinds.append("\(kind).bytesMismatch")
                continue
            }
            missingKinds.append(
                contentsOf: validateCaptureReceipt(
                    screenshotRecord.captureReceipts?.item(for: kind),
                    kind: kind,
                    screenshotPath: path,
                    screenshotSHA256: actualSHA256,
                    screenshotBytes: actualBytes,
                    requireRenderReady: record.caseKind == "rich"
                )
            )
            let extensionName = URL(fileURLWithPath: path).pathExtension.isEmpty
                ? "png"
                : URL(fileURLWithPath: path).pathExtension
            let relativePath = [
                "assets",
                "screenshots",
                repetitionDirectoryName(record.repetition),
                safePathComponent(record.caseID),
                "\(kind).\(extensionName)",
            ].joined(separator: "/")
            let destinationURL = packageRootURL.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            copiedPaths[kind] = relativePath
            sha256ByKind[kind] = actualSHA256
        }
        if screenshotRecord.status != "succeeded" && missingKinds.isEmpty {
            missingKinds = expectedKinds
        }
        return RichAnswerEvidencePackageScreenshot(
            manifestStatus: screenshotRecord.status,
            captureStatus: screenshotRecord.captureStatus,
            captureKind: screenshotRecord.captureKind,
            failureReason: screenshotRecord.failureReason,
            copiedPaths: copiedPaths,
            sha256ByKind: sha256ByKind,
            recordSHA256: actualRecordSHA256,
            qualityGateStatus: qualityGateStatus,
            reviewStatus: reviewStatus,
            baselineID: screenshotRecord.baselineID,
            baselineManifestPath: screenshotRecord.baselineManifestPath,
            expectedKinds: expectedKinds,
            missingKinds: missingKinds
        )
    }

    private static func validateCaptureReceipt(
        _ receipt: RichAnswerScreenshotCaptureReceipt?,
        kind: String,
        screenshotPath: String,
        screenshotSHA256: String,
        screenshotBytes: Int64,
        requireRenderReady: Bool
    ) -> [String] {
        guard let receipt else {
            return ["\(kind).captureReceipts"]
        }

        var missingKinds: [String] = []
        let requestResult: ReceiptDecodeResult<RichAnswerScreenshotCaptureRequest> = decodeReceiptJSON(
            receipt.request,
            kind: kind,
            label: "request"
        )
        let acknowledgementResult: ReceiptDecodeResult<RichAnswerScreenshotCaptureAcknowledgement> = decodeReceiptJSON(
            receipt.acknowledgement,
            kind: kind,
            label: "acknowledgement"
        )
        missingKinds.append(contentsOf: requestResult.missingKinds)
        missingKinds.append(contentsOf: acknowledgementResult.missingKinds)

        guard let request = requestResult.value,
              let acknowledgement = acknowledgementResult.value else {
            return missingKinds
        }

        guard let requestID = nonEmpty(request.id) else {
            missingKinds.append("\(kind).captureReceipts.request.id")
            return missingKinds
        }
        if nonEmpty(acknowledgement.id) != requestID {
            missingKinds.append("\(kind).captureReceipts.acknowledgement.id")
        }
        if nonEmpty(acknowledgement.requestID) != requestID {
            missingKinds.append("\(kind).captureReceipts.acknowledgement.requestID")
        }
        if !pathsMatch(request.capturePath, screenshotPath) {
            missingKinds.append("\(kind).captureReceipts.request.capturePath")
        }
        if !pathsMatch(acknowledgement.requestCapturePath, screenshotPath) {
            missingKinds.append("\(kind).captureReceipts.acknowledgement.requestCapturePath")
        }
        if !pathsMatch(acknowledgement.capturePath, screenshotPath) {
            missingKinds.append("\(kind).captureReceipts.acknowledgement.capturePath")
        }
        if nonEmpty(acknowledgement.status) != "succeeded" {
            missingKinds.append("\(kind).captureReceipts.acknowledgement.status")
        }
        guard let actualPNG = acknowledgement.actualPNG else {
            missingKinds.append("\(kind).captureReceipts.acknowledgement.actualPNG")
            return missingKinds
        }
        if !pathsMatch(actualPNG.path, screenshotPath) {
            missingKinds.append("\(kind).captureReceipts.acknowledgement.actualPNG.path")
        }
        if nonEmpty(actualPNG.sha256) != screenshotSHA256 {
            missingKinds.append("\(kind).captureReceipts.acknowledgement.actualPNG.sha256")
        }
        if let hash = nonEmpty(actualPNG.hash),
           hash != "sha256:\(screenshotSHA256)" {
            missingKinds.append("\(kind).captureReceipts.acknowledgement.actualPNG.hash")
        }
        if actualPNG.bytes ?? -1 != screenshotBytes {
            missingKinds.append("\(kind).captureReceipts.acknowledgement.actualPNG.bytes")
        }
        if requireRenderReady {
            guard let renderReady = acknowledgement.renderReady else {
                missingKinds.append("\(kind).captureReceipts.acknowledgement.renderReady")
                return missingKinds
            }
            if renderReady.seen != true {
                missingKinds.append("\(kind).captureReceipts.acknowledgement.renderReady.seen")
            }
            if !isHexSHA256(renderReady.sha256) {
                missingKinds.append("\(kind).captureReceipts.acknowledgement.renderReady.sha256")
            }
            if let signature = nonEmpty(renderReady.signature),
               signature != "sha256:\(renderReady.sha256 ?? "")" {
                missingKinds.append("\(kind).captureReceipts.acknowledgement.renderReady.signature")
            }
            if let bytes = renderReady.bytes,
               bytes <= 0 {
                missingKinds.append("\(kind).captureReceipts.acknowledgement.renderReady.bytes")
            }
        }
        return missingKinds
    }

    private static func decodeReceiptJSON<Value: Decodable>(
        _ item: RichAnswerScreenshotEvidenceItem?,
        kind: String,
        label: String
    ) -> ReceiptDecodeResult<Value> {
        let prefix = "\(kind).captureReceipts.\(label)"
        guard let item else {
            return ReceiptDecodeResult(value: nil, missingKinds: [prefix])
        }
        guard let path = nonEmpty(item.path),
              FileManager.default.fileExists(atPath: path) else {
            return ReceiptDecodeResult(value: nil, missingKinds: ["\(prefix).path"])
        }
        let url = URL(fileURLWithPath: path)
        do {
            let actualSHA256 = try sha256(of: url)
            var missingKinds: [String] = []
            if nonEmpty(item.sha256) != actualSHA256 {
                missingKinds.append("\(prefix).sha256")
            }
            let actualBytes = try byteCount(of: url)
            if item.bytes != actualBytes || actualBytes <= 0 {
                missingKinds.append("\(prefix).bytes")
            }
            let data = try Data(contentsOf: url)
            let value = try JSONDecoder().decode(Value.self, from: data)
            return ReceiptDecodeResult(value: value, missingKinds: missingKinds)
        } catch {
            return ReceiptDecodeResult(value: nil, missingKinds: ["\(prefix).decode"])
        }
    }

    private static func indexMarkdown(_ document: RichAnswerEvidencePackageDocument) -> String {
        let summary = document.summary
        let rows = document.cases.map { item in
            let invocation = item.attempts.map(\.invocationKind).joined(separator: ", ")
            let screenshots = item.screenshotCompleteRepetitions.map(String.init).joined(separator: ",")
            return "| \(item.sequence) | \(item.subject) | [\(item.caseID)](\(item.casePagePath)) | \(item.caseKind) | \(invocation) | \(item.observedRepetitions.map(String.init).joined(separator: ",")) | \(screenshots) | \(item.reviewCompleteRepetitions.map(String.init).joined(separator: ",")) | \(item.shapeDrift ? "是" : "否") | \(item.contentDrift ? "是" : "否") |"
        }.joined(separator: "\n")
        return """
        # 魏碑富回答逐题验收包

        - 整体状态：**\(document.completionState)**
        - 自动完成：禁止
        - 首轮 baseline：\(summary.baselineID ?? "缺失")
        - baseline manifest：\(summary.baselineManifestPath ?? "缺失")
        - baseline 不一致：\(summary.baselineMismatchKeys.count)
        - 首轮记录：\(summary.firstPassRecordCount)/\(summary.expectedFirstPassRecordCount)
        - 首轮可信调用：\(summary.firstPassTrustedInvocationCount)/\(summary.expectedFirstPassRecordCount)
        - 首轮完整记录证据：\(summary.firstPassCompleteEvidenceCount)/\(summary.expectedFirstPassRecordCount)
        - 四轮记录：\(summary.threeRoundRecordCount)/\(summary.expectedThreeRoundRecordCount)
        - 四轮可信调用：\(summary.threeRoundTrustedInvocationCount)/\(summary.expectedThreeRoundRecordCount)
        - 四轮完整记录证据：\(summary.threeRoundCompleteEvidenceCount)/\(summary.expectedThreeRoundRecordCount)
        - 四轮稳定案例：\(summary.stableThreeRoundCaseCount)/\(summary.expectedCaseCount)
        - 首轮截图图片：\(summary.firstPassScreenshotImageCount)/\(summary.expectedFirstPassScreenshotImageCount)
        - 四轮截图图片：\(summary.threeRoundScreenshotImageCount)/\(summary.expectedThreeRoundScreenshotImageCount)，最低 \(summary.minimumRequiredScreenshotImageCount)，达标 \(summary.screenshotMinimumSatisfied)
        - 四轮七类审查：\(summary.threeRoundReviewedItemCount)/\(summary.expectedThreeRoundReviewItemCount)，缺口 \(summary.reviewGapItemCount)
        - 体验七项全通过 attempt：\(summary.experiencePassedAttemptCount)/\(summary.expectedThreeRoundRecordCount)
        - 夹具记录：\(summary.fixtureInvocationCount)，未声明：\(summary.unknownInvocationCount)，矛盾声明：\(summary.contradictoryInvocationCount)
        - 形态漂移：\(summary.shapeDriftCaseIDs.count)，内容漂移：\(summary.contentDriftCaseIDs.count)

        > 夹具与未声明调用类型的记录永远不计入真实 Pi 覆盖；缺少截图的题目永远保留 missing evidence。

        | 序号 | 学科 | 题目 | 类型 | 调用证据 | 已有轮次 | 截图完整轮次 | 七项审查完整轮次 | 形态漂移 | 内容漂移 |
        | ---: | --- | --- | --- | --- | --- | --- | --- | --- | --- |
        \(rows)
        """
    }

    private static func indexHTML(_ document: RichAnswerEvidencePackageDocument) -> String {
        let summary = document.summary
        let rows = document.cases.map { item -> String in
            let invocation = Array(Set(item.attempts.map(\.invocationKind))).sorted().joined(separator: "、")
            let invocationClass = item.attempts.allSatisfy { $0.trustedInvocation } && !item.attempts.isEmpty
                ? "ok"
                : "bad"
            let screenshotText = "\(item.screenshotCompleteRepetitions.count)/\(targetRepetitions.count) 轮"
            let reviewText = "\(item.reviewCompleteRepetitions.count)/\(targetRepetitions.count) 轮"
            let drift = [
                item.shapeDrift ? "形态漂移" : nil,
                item.contentDrift ? "内容漂移" : nil,
            ].compactMap { $0 }.joined(separator: "、")
            return """
            <tr>
              <td class="num">\(item.sequence)</td>
              <td>\(escapeHTML(item.subject))</td>
              <td><a href="\(urlPath(item.casePagePath))">\(escapeHTML(item.caseID))</a></td>
              <td>\(escapeHTML(kindLabel(item.caseKind)))</td>
              <td class="\(invocationClass)">\(escapeHTML(invocation.isEmpty ? "缺记录" : invocation))</td>
              <td>\(escapeHTML(item.observedRepetitions.map(String.init).joined(separator: ", ")))</td>
              <td class="\(item.screenshotCompleteRepetitions.count == targetRepetitions.count ? "ok" : "bad")">\(screenshotText)</td>
              <td class="\(item.reviewCompleteRepetitions.count == targetRepetitions.count ? "ok" : "warn")">\(reviewText)</td>
              <td>\(escapeHTML(drift.isEmpty ? "—" : drift))</td>
            </tr>
            """
        }.joined(separator: "\n")
        let missingPreview = summary.missingScreenshotKeys.prefix(20).map {
            "<li>\(escapeHTML($0))</li>"
        }.joined(separator: "")
        let reviewGapPreview = summary.reviewGapKeys.prefix(20).map {
            "<li>\(escapeHTML($0))</li>"
        }.joined(separator: "")
        let baselineGapPreview = summary.baselineMismatchKeys.prefix(20).map {
            "<li>\(escapeHTML($0))</li>"
        }.joined(separator: "")
        return htmlDocument(
            title: "魏碑富回答逐题验收包",
            body: """
            <header class="masthead">
              <p class="eyebrow">WeiBei · 真实证据浏览</p>
              <h1>富回答逐题验收包</h1>
              <p class="state">\(completionState)</p>
              <p class="lede">这里连接模型原始记录与真实魏碑窗口截图。它是验收资料，不是新的网页演示。</p>
            </header>
            <section class="summary-rule" aria-label="覆盖摘要">
              <p><strong>首轮</strong> 记录 \(summary.firstPassRecordCount)/\(summary.expectedFirstPassRecordCount)，可信调用 \(summary.firstPassTrustedInvocationCount)/\(summary.expectedFirstPassRecordCount)，截图图片 \(summary.firstPassScreenshotImageCount)/\(summary.expectedFirstPassScreenshotImageCount)。</p>
              <p><strong>矩阵</strong> 唯一案例 \(summary.uniqueCaseCount)/\(summary.requiredCaseCount)，四轮目标 \(summary.expectedThreeRoundRecordCount) 次。</p>
              <p><strong>首轮基线</strong> baseline \(escapeHTML(summary.baselineID ?? "缺失"))，manifest \(escapeHTML(summary.baselineManifestPath ?? "缺失"))，不一致 \(summary.baselineMismatchKeys.count) 条。</p>
              <p><strong>记录完整性</strong> 首轮 \(summary.firstPassCompleteEvidenceCount)/\(summary.expectedFirstPassRecordCount)，四轮 \(summary.threeRoundCompleteEvidenceCount)/\(summary.expectedThreeRoundRecordCount)。</p>
              <p><strong>四轮</strong> 记录 \(summary.threeRoundRecordCount)/\(summary.expectedThreeRoundRecordCount)，可信调用 \(summary.threeRoundTrustedInvocationCount)/\(summary.expectedThreeRoundRecordCount)，稳定案例 \(summary.stableThreeRoundCaseCount)/\(summary.expectedCaseCount)。</p>
              <p><strong>证据警报</strong> 夹具 \(summary.fixtureInvocationCount)，未声明 \(summary.unknownInvocationCount)，矛盾声明 \(summary.contradictoryInvocationCount)，缺图尝试 \(summary.screenshotGapAttemptCount)。</p>
              <p><strong>截图下限</strong> 已核验 SHA-256 图片 \(summary.threeRoundScreenshotImageCount)/\(summary.expectedThreeRoundScreenshotImageCount)，最低要求 \(summary.minimumRequiredScreenshotImageCount)，达标 \(summary.screenshotMinimumSatisfied)。</p>
              <p><strong>七类审查</strong> 已填 \(summary.threeRoundReviewedItemCount)/\(summary.expectedThreeRoundReviewItemCount)，完整 attempt \(summary.reviewCompleteAttemptCount)/\(summary.expectedThreeRoundRecordCount)，七项全通过 \(summary.experiencePassedAttemptCount)/\(summary.expectedThreeRoundRecordCount)。</p>
              <p><strong>漂移</strong> 形态 \(summary.shapeDriftCaseIDs.count) 题，内容 \(summary.contentDriftCaseIDs.count) 题。任何全绿都只代表可提交用户验收，不会自动宣布完成。</p>
            </section>
            <aside class="warning">
              <strong>证据边界：</strong>只有明确 <code>modelInvocation=true</code> 且 <code>fixtureInvocation=false</code> 的记录才计入真实 Pi；非法协议题按确定性拦截单独计数。缺少真实窗口截图时固定标记 <em>missing evidence</em>；协议 pass 永远不会自动转换成七类体验审查 pass。
            </aside>
            <section>
              <div class="section-heading"><h2>逐题索引</h2><p>点开题目查看材料、原始回复、表达计划、校验、来源、修复复测与前后截图。</p></div>
              <div class="table-wrap">
                <table>
                  <thead><tr><th>#</th><th>学科</th><th>题目</th><th>类型</th><th>调用证据</th><th>轮次</th><th>截图</th><th>七类审查</th><th>漂移</th></tr></thead>
                  <tbody>\(rows)</tbody>
                </table>
              </div>
            </section>
            <section class="missing">
              <details>
                <summary>截图缺口（\(summary.missingScreenshotKeys.count) 条）</summary>
                <ol>\(missingPreview)\(summary.missingScreenshotKeys.count > 20 ? "<li>其余见 package.json</li>" : "")</ol>
              </details>
              <details>
                <summary>七类审查缺口（\(summary.reviewGapKeys.count) 条）</summary>
                <ol>\(reviewGapPreview)\(summary.reviewGapKeys.count > 20 ? "<li>其余见 package.json</li>" : "")</ol>
              </details>
              <details>
                <summary>首轮 baseline 缺口（\(summary.baselineMismatchKeys.count) 条）</summary>
                <ol>\(baselineGapPreview)\(summary.baselineMismatchKeys.count > 20 ? "<li>其余见 package.json</li>" : "")</ol>
              </details>
              <p class="files"><a href="package.json">结构化汇总</a> · <a href="index.md">Markdown 索引</a></p>
            </section>
            """
        )
    }

    private static func caseHTML(
        expectedCase: RichAnswerEvidencePackageExpectedCase,
        attemptsByRepetition: [Int: RichAnswerEvidencePackageAttempt]
    ) -> String {
        let firstRecord = targetRepetitions.compactMap { attemptsByRepetition[$0]?.record }.first
        let question = firstRecord?.question ?? "缺少题目记录"
        let materialTitle = firstRecord?.materialTitle ?? "缺少材料标题"
        let materialText = firstRecord?.materialText ?? "缺少材料正文"
        let selectionTitle = firstRecord?.selectionTitle
        let selectionText = firstRecord?.selectionText
        let repetitionSections = targetRepetitions.map { repetition -> String in
            guard let attempt = attemptsByRepetition[repetition] else {
                return """
                <section class="attempt missing-attempt">
                  <h2>第 \(repetition) 轮</h2>
                  <p class="bad"><strong>missing evidence</strong>：缺少本轮 record.json，因此模型、协议、来源与截图均不能验收。</p>
                </section>
                """
            }
            return attemptHTML(attempt)
        }.joined(separator: "\n")
        let selection = [selectionTitle, selectionText].compactMap { $0 }
        return htmlDocument(
            title: "\(expectedCase.caseID) · 富回答验收",
            body: """
            <nav class="back"><a href="../index.html">← 返回逐题索引</a></nav>
            <header class="case-head">
              <p class="eyebrow">\(escapeHTML(expectedCase.subject)) · \(escapeHTML(kindLabel(expectedCase.caseKind)))</p>
              <h1>\(escapeHTML(expectedCase.caseID))</h1>
              <p class="question">\(escapeHTML(question))</p>
            </header>
            <section class="source">
              <h2>题目与材料</h2>
              <h3>\(escapeHTML(materialTitle))</h3>
              <pre>\(escapeHTML(materialText))</pre>
              \(selection.isEmpty ? "" : "<h3>选区：\(escapeHTML(selectionTitle ?? ""))</h3><pre>\(escapeHTML(selectionText ?? ""))</pre>")
            </section>
            \(repetitionSections)
            """
        )
    }

    private static func attemptHTML(_ attempt: RichAnswerEvidencePackageAttempt) -> String {
        let record = attempt.record
        let invocation = invocationPresentation(attempt.invocationKind)
        let screenshots = screenshotHTML(attempt.screenshot)
        let t1Items = record.t1Programs.map { program in
            let components = strings(program["componentNames"]).joined(separator: "、")
            let capabilities = strings(program["capabilities"]).joined(separator: "、")
            return "<li><strong>\(escapeHTML(string(program["family"]) ?? "T1"))</strong> · 组件 \(escapeHTML(components.isEmpty ? "未记录" : components)) · 能力 \(escapeHTML(capabilities.isEmpty ? "未记录" : capabilities))</li>"
        }.joined(separator: "")
        let t2Items = record.t2Compositions.map { composition in
            let roles = strings(composition["roles"]).joined(separator: "、")
            let labels = strings(composition["bindingLabels"]).joined(separator: "、")
            return "<li><strong>\(escapeHTML(string(composition["family"]) ?? "T2"))</strong> · 原语 \(escapeHTML(roles.isEmpty ? "未记录" : roles)) · 绑定 \(escapeHTML(labels.isEmpty ? "未记录" : labels)) · 节点 \(integer(composition["nodeCount"]) ?? 0)</li>"
        }.joined(separator: "")
        let renderPlanItems = record.renderPlans.map { plan in
            let renderer = string(plan["renderer"]) ?? "未记录渲染器"
            let specVersion = string(plan["specVersion"]) ?? "未记录版本"
            let interactions = strings(plan["interactionKinds"]).joined(separator: "、")
            let sources = strings(plan["sourceEvidenceIDs"]).joined(separator: "、")
            let negotiation = string(plan["negotiationStatus"]) ?? "未记录协商"
            return "<li><strong>\(escapeHTML(renderer))@\(escapeHTML(specVersion))</strong> · 交互 \(escapeHTML(interactions.isEmpty ? "无" : interactions)) · 来源 \(escapeHTML(sources.isEmpty ? "未记录" : sources)) · 能力协商 \(escapeHTML(negotiation))</li>"
        }.joined(separator: "")
        let validationIssues = record.validationIssues.isEmpty ? "无" : record.validationIssues.joined(separator: "；")
        let protocolDiagnostics = record.protocolDiagnostics.isEmpty ? "无" : record.protocolDiagnostics.joined(separator: "；")
        let sourceLabels = (record.textSourceLabels + record.evidenceLedgerLabels).uniqued().joined(separator: "；")
        let artifactLinks = ["record.json", "request.json", "reply.json", "review.json"].compactMap { fileName -> String? in
            guard let relativePath = attempt.artifacts.copiedPaths[fileName] else { return nil }
            return "<a href=\"../\(urlPath(relativePath))\">\(escapeHTML(fileName))</a>"
        }.joined(separator: " · ")
        let artifactWarning = attempt.artifacts.missingKinds.isEmpty
            ? ""
            : "<p class=\"bad\"><strong>package artifact missing：</strong>\(escapeHTML(attempt.artifacts.missingKinds.joined(separator: "、")))</p>"
        let recordEvidenceWarning = record.missingRequiredEvidenceFields.isEmpty
            ? ""
            : "<p class=\"bad\"><strong>record evidence missing：</strong>\(escapeHTML(record.missingRequiredEvidenceFields.joined(separator: "、")))</p>"
        let reviewRows = record.review.items.map { item in
            let score = item.score.map { String(format: "%.1f", $0) } ?? "—"
            let evidence = item.evidence.isEmpty ? "—" : item.evidence.joined(separator: "；")
            return "<tr><th>\(escapeHTML(item.label))</th><td class=\"\(reviewStatusClass(item))\">\(escapeHTML(item.status))</td><td>\(score)</td><td>\(escapeHTML(item.reason ?? "—"))</td><td>\(escapeHTML(evidence))</td></tr>"
        }.joined(separator: "")
        let reviewBoundary = attempt.isTrustedInvocation
            ? "协议通过不代表体验通过；只有审查者明确填写的结果才计入。"
            : "这是夹具或非可信调用；即使 review 格式完整，也不计入真实审查覆盖。"
        return """
        <section class="attempt">
          <div class="attempt-title">
            <h2>第 \(record.repetition) 轮</h2>
            <p class="\(invocation.cssClass)">\(escapeHTML(invocation.label))</p>
          </div>
          <table class="facts">
            <tr><th>本轮验收状态</th><td>\(escapeHTML(attempt.acceptanceStatus))</td><th>耗时</th><td>\(String(format: "%.3f", record.elapsedSeconds)) 秒</td></tr>
            <tr><th>模型/协议状态</th><td>\(escapeHTML(record.status))</td><th>视觉技术门禁</th><td>\(escapeHTML(attempt.screenshot.qualityGateStatus ?? "未记录"))</td></tr>
            <tr><th>模型调用</th><td>\(optionalBool(record.modelInvocation))</td><th>夹具调用</th><td>\(optionalBool(record.fixtureInvocation))</td></tr>
            <tr><th>预期形态</th><td>\(escapeHTML(record.expectedShape))</td><th>实际形态</th><td>\(escapeHTML(record.actualShape))</td></tr>
            <tr><th>来源 run</th><td>\(escapeHTML(record.reference.sourceRunID))</td><th>包内原始文件</th><td>\(artifactLinks.isEmpty ? "缺失" : artifactLinks)</td></tr>
          </table>
          \(recordEvidenceWarning)
          \(artifactWarning)
          \(screenshots)
          <div class="evidence-grid">
            <section>
              <h3>形态与表达计划</h3>
              <p>\(escapeHTML(record.expressionSummary ?? "未记录表达计划摘要"))</p>
              <ul>\(t1Items.isEmpty ? "<li>T1：无</li>" : t1Items)\(t2Items.isEmpty ? "<li>T2：无</li>" : t2Items)\(renderPlanItems.isEmpty ? "<li>renderPlan：无</li>" : renderPlanItems)</ul>
            </section>
            <section>
              <h3>协议与来源</h3>
              <p><strong>校验：</strong>\(escapeHTML(record.validationStatus ?? "未记录")) · \(escapeHTML(record.validationKind ?? "未记录"))</p>
              <p><strong>问题：</strong>\(escapeHTML(validationIssues))</p>
              <p><strong>诊断：</strong>\(escapeHTML(protocolDiagnostics))</p>
              <p><strong>来源：</strong>\(escapeHTML(sourceLabels.isEmpty ? "未记录" : sourceLabels))</p>
              <p><strong>命中预期：</strong>\(optionalBool(record.hasExpectedSource))</p>
            </section>
          </div>
          <section class="experience-review">
            <h3>七类体验审查</h3>
            <p class="review-boundary">\(escapeHTML(reviewBoundary))</p>
            <div class="table-wrap"><table><thead><tr><th>审查项</th><th>状态</th><th>分数</th><th>理由</th><th>证据</th></tr></thead><tbody>\(reviewRows)</tbody></table></div>
          </section>
          <section class="reply">
            <h3>模型原始回答</h3>
            <pre>\(escapeHTML(record.modelText ?? "无模型文本"))</pre>
            <details><summary>查看模型原始回复 JSON</summary><pre>\(escapeHTML(record.rawModelReplyJSON ?? "无"))</pre></details>
          </section>
          <section class="repair">
            <h3>失败、修复与复测</h3>
            <p><strong>失败原因：</strong>\(escapeHTML(record.failureReason ?? "无"))</p>
            <p><strong>修复说明：</strong>\(escapeHTML(record.repairNote ?? "无"))</p>
            <p><strong>复测来源：</strong>\(escapeHTML(record.previousRunID ?? "无")) · <strong>是否复测：</strong>\(optionalBool(record.isRetest))</p>
          </section>
        </section>
        """
    }

    private static func screenshotHTML(_ screenshot: RichAnswerEvidencePackageScreenshot) -> String {
        guard screenshot.isComplete else {
            return """
            <section class="screenshots missing-shot">
              <h3>真实魏碑窗口截图</h3>
              <p class="bad"><strong>missing evidence</strong>：缺少 \(escapeHTML(screenshot.missingKinds.joined(separator: "、")))。\(escapeHTML(screenshot.failureReason ?? ""))</p>
            </section>
            """
        }
        let figureKinds = screenshot.expectedKinds
            + ["overview"].filter { screenshot.copiedPaths[$0] != nil && !screenshot.expectedKinds.contains($0) }
        let figures = figureKinds.compactMap { kind -> String? in
            guard let relativePath = screenshot.copiedPaths[kind] else { return nil }
            let label: String
            switch kind {
            case "overview": label = "富回答总览"
            case "before": label = "操作前"
            case "after": label = "操作后"
            default: label = "真实结果"
            }
            let sha = screenshot.sha256ByKind[kind] ?? "缺 SHA-256"
            return "<figure><img src=\"../\(urlPath(relativePath))\" alt=\"\(escapeHTML(label))\"><figcaption>\(escapeHTML(label)) · SHA-256 \(escapeHTML(sha))</figcaption></figure>"
        }.joined(separator: "")
        return """
        <section class="screenshots">
          <h3>真实魏碑窗口截图</h3>
          <p class="review-boundary">capture=\(escapeHTML(screenshot.captureStatus ?? "未记录")) · qualityGate=\(escapeHTML(screenshot.qualityGateStatus ?? "未记录")) · reviewStatus=\(escapeHTML(screenshot.reviewStatus ?? "未记录")) · baseline=\(escapeHTML(screenshot.baselineID ?? "未记录")) · recordSHA256=\(escapeHTML(screenshot.recordSHA256 ?? "未记录"))</p>
          <div class="shot-grid">\(figures)</div>
        </section>
        """
    }

    private static func htmlDocument(title: String, body: String) -> String {
        """
        <!doctype html>
        <html lang="zh-CN">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(escapeHTML(title))</title>
          <style>
            :root { color-scheme: light; --paper:#f4efe4; --paper-2:#fbf8f0; --ink:#2d261f; --muted:#756b5d; --rule:#d8cebd; --rust:#7f3f2d; --green:#315f3a; --red:#8f3027; --amber:#8a642c; }
            * { box-sizing: border-box; }
            body { margin:0; background:var(--paper); color:var(--ink); font:15px/1.72 -apple-system,BlinkMacSystemFont,"PingFang SC","Noto Sans CJK SC",sans-serif; }
            body::before { content:""; position:fixed; inset:0; pointer-events:none; opacity:.18; background-image:linear-gradient(to right,rgba(86,73,55,.08) 1px,transparent 1px); background-size:88px 100%; }
            body > * { position:relative; }
            header, nav, section, aside { width:min(1120px,calc(100% - 40px)); margin-inline:auto; }
            h1,h2,h3 { font-family:"Songti SC","STSong",serif; font-weight:600; letter-spacing:.01em; }
            h1 { font-size:clamp(30px,4vw,48px); line-height:1.15; margin:.15em 0 .3em; }
            h2 { font-size:23px; margin:0 0 12px; }
            h3 { font-size:17px; margin:20px 0 8px; }
            a { color:var(--rust); text-underline-offset:3px; }
            code,pre { font-family:"SFMono-Regular",Menlo,monospace; }
            pre { white-space:pre-wrap; overflow-wrap:anywhere; background:rgba(255,255,255,.34); border-left:2px solid var(--rule); padding:14px 16px; margin:10px 0; }
            .masthead,.case-head { padding-top:56px; padding-bottom:26px; border-bottom:1px solid var(--rule); }
            .eyebrow { margin:0; color:var(--rust); font-size:12px; letter-spacing:.14em; text-transform:uppercase; }
            .state { display:inline-block; margin:4px 0 12px; padding:2px 8px; border:1px solid var(--amber); color:var(--amber); font-weight:700; }
            .lede,.question { max-width:760px; font-size:17px; margin:8px 0 0; }
            .summary-rule { padding:20px 0; border-bottom:1px solid var(--rule); }
            .summary-rule p { margin:4px 0; }
            .warning { margin-top:22px; margin-bottom:32px; padding:12px 15px; border-left:3px solid var(--rust); background:rgba(127,63,45,.06); }
            .section-heading { display:flex; align-items:baseline; justify-content:space-between; gap:20px; margin-top:34px; border-bottom:1px solid var(--rule); }
            .section-heading p { color:var(--muted); }
            .table-wrap { overflow:auto; border-bottom:1px solid var(--rule); }
            table { width:100%; border-collapse:collapse; background:rgba(255,255,255,.2); }
            th,td { text-align:left; vertical-align:top; padding:9px 10px; border-bottom:1px solid var(--rule); }
            th { color:var(--muted); font-size:12px; letter-spacing:.06em; white-space:nowrap; }
            .num { font-variant-numeric:tabular-nums; color:var(--muted); }
            .ok { color:var(--green); font-weight:700; }
            .bad { color:var(--red); font-weight:700; }
            .warn { color:var(--amber); font-weight:700; }
            .missing { padding:24px 0 64px; }
            .files { margin-top:18px; }
            .back { padding-top:28px; }
            .source { padding:28px 0; border-bottom:1px solid var(--rule); }
            .attempt { padding:30px 0 42px; border-bottom:2px solid var(--ink); }
            .attempt > section { width:auto; margin-inline:0; }
            .attempt-title { display:flex; align-items:baseline; justify-content:space-between; gap:16px; }
            .attempt-title p { margin:0; }
            .facts th { width:13%; }
            .facts td { width:37%; }
            .screenshots { margin-top:24px; }
            .missing-shot,.missing-attempt { padding:16px; border:1px solid var(--red); background:rgba(143,48,39,.04); }
            .shot-grid { display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:16px; }
            figure { margin:0; }
            img { display:block; width:100%; height:auto; border:1px solid var(--rule); background:var(--paper-2); }
            figcaption { padding-top:6px; color:var(--muted); font-size:13px; }
            .evidence-grid { display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:28px; margin-top:24px; }
            .evidence-grid section { width:auto; margin:0; }
            .review-boundary { color:var(--muted); }
            details { margin-top:12px; }
            summary { cursor:pointer; color:var(--rust); }
            @media (max-width:760px) { body::before{display:none}.shot-grid,.evidence-grid{grid-template-columns:1fr}.facts th,.facts td{display:block;width:100%}.section-heading,.attempt-title{display:block}header,nav,section,aside{width:min(100% - 24px,1120px)} }
          </style>
        </head>
        <body>\(body)</body>
        </html>
        """
    }

    private static func invocationPresentation(
        _ kind: RichAnswerEvidenceInvocationKind
    ) -> (label: String, cssClass: String) {
        switch kind {
        case .model: ("真实 Pi 模型调用", "ok")
        case .deterministic: ("确定性非法协议拦截", "ok")
        case .fixture: ("夹具调用，不计入真实 Pi", "bad")
        case .unknown: ("调用类型未声明，按非真实处理", "bad")
        case .contradictory: ("模型/夹具声明矛盾，证据无效", "bad")
        case .nonModel: ("非模型调用，不计入真实 Pi", "bad")
        }
    }

    private static func reviewStatusClass(_ item: RichAnswerEvidenceReviewItem) -> String {
        if !item.isReviewed { return "warn" }
        return item.isPass ? "ok" : "bad"
    }

    private static func expectedImageCount(caseKind: String) -> Int {
        caseKind == "rich" ? 2 : 1
    }

    private static func evidenceKey(repetition: Int, caseID: String) -> String {
        "rep=\(repetition) case=\(caseID)"
    }

    private static func repetitionDirectoryName(_ repetition: Int) -> String {
        "repetition-\(String(format: "%03d", repetition))"
    }

    private static func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func pathsMatch(_ left: String?, _ right: String) -> Bool {
        guard let left = nonEmpty(left) else { return false }
        if left == right { return true }
        return canonicalPath(URL(fileURLWithPath: left)) == canonicalPath(URL(fileURLWithPath: right))
    }

    private static func isHexSHA256(_ value: String?) -> Bool {
        guard let value = nonEmpty(value),
              value.count == 64 else { return false }
        let allowed = CharacterSet(charactersIn: "0123456789abcdef")
        return value.unicodeScalars.allSatisfy {
            allowed.contains($0)
        }
    }

    private static func safePathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let mapped = value.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
        let result = String(mapped).trimmingCharacters(in: CharacterSet(charactersIn: "-._"))
        return result.isEmpty ? "case" : result
    }

    private static func sha256(of url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func byteCount(of url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? -1
    }

    private static func writeText(_ value: String, to url: URL) throws {
        guard let data = value.data(using: .utf8) else {
            throw RichAnswerEvidenceError.invalidConfiguration("cannot encode UTF-8 for \(url.path)")
        }
        try data.write(to: url, options: .atomic)
    }

    private static func writeJSON<Value: Encodable>(_ value: Value, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private static func optionalBool(_ value: Bool?) -> String {
        value.map(String.init) ?? "未声明"
    }

    private static func kindLabel(_ value: String) -> String {
        switch value {
        case "rich": "富回答"
        case "text-only": "纯文本"
        case "degradation": "诚实降级"
        case "invalid-protocol": "非法协议拦截"
        default: value
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func urlPath(_ value: String) -> String {
        escapeHTML(value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value)
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private static func safeTimestampForPath() -> String {
        timestamp()
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
    }
}

private struct RichAnswerEvidencePackageDocument: Codable {
    let schemaVersion: Int
    let runID: String
    let generatedAt: String
    let completionState: String
    let screenshotManifestPath: String?
    let baselineManifestPath: String?
    let observedRepetitions: [Int]
    let summary: RichAnswerEvidencePackageSummary
    let cases: [RichAnswerEvidencePackageCaseSummary]
}

private struct RichAnswerEvidencePackageCaseSummary: Codable {
    let sequence: Int
    let caseID: String
    let caseKind: String
    let subject: String
    let casePagePath: String
    let observedRepetitions: [Int]
    let trustedRepetitions: [Int]
    let screenshotCompleteRepetitions: [Int]
    let reviewCompleteRepetitions: [Int]
    let experiencePassedRepetitions: [Int]
    let shapeDrift: Bool
    let contentDrift: Bool
    let attempts: [RichAnswerEvidencePackageAttemptSummary]
}

private struct RichAnswerEvidencePackageAttemptSummary: Codable {
    let repetition: Int
    let status: String
    let acceptanceStatus: String
    let invocationKind: String
    let trustedInvocation: Bool
    let modelInvocation: Bool?
    let fixtureInvocation: Bool?
    let actualShape: String
    let elapsedSeconds: TimeInterval
    let contentFingerprint: String?
    let screenshotComplete: Bool
    let screenshotPaths: [String: String]
    let screenshotSHA256: [String: String]
    let missingScreenshots: [String]
    let baselineID: String?
    let baselineManifestPath: String?
    let missingRecordFields: [String]
    let artifactPaths: [String: String]
    let missingArtifacts: [String]
    let reviews: [RichAnswerEvidenceReviewItem]
    let reviewComplete: Bool
    let experiencePass: Bool
    let sourceRunID: String
    let recordPath: String
}

private struct RichAnswerEvidencePackageAttempt {
    let record: RichAnswerEvidencePackageRecord
    let artifacts: RichAnswerEvidencePackageArtifacts
    let screenshot: RichAnswerEvidencePackageScreenshot

    var invocationKind: RichAnswerEvidenceInvocationKind {
        RichAnswerEvidenceInvocationKind(
            caseKind: record.caseKind,
            modelInvocation: record.modelInvocation,
            fixtureInvocation: record.fixtureInvocation
        )
    }

    var isTrustedInvocation: Bool {
        invocationKind == .model || invocationKind == .deterministic
    }

    var acceptanceStatus: String {
        guard record.status == "passed" else { return "运行失败" }
        guard isTrustedInvocation else { return "非可信调用" }
        guard screenshot.isComplete else { return "截图证据不完整" }
        guard screenshot.qualityGateStatus == "pass" else { return "视觉门禁待复核" }
        return "待用户验收"
    }

    var summary: RichAnswerEvidencePackageAttemptSummary {
        RichAnswerEvidencePackageAttemptSummary(
            repetition: record.repetition,
            status: record.status,
            acceptanceStatus: acceptanceStatus,
            invocationKind: invocationKind.rawValue,
            trustedInvocation: isTrustedInvocation,
            modelInvocation: record.modelInvocation,
            fixtureInvocation: record.fixtureInvocation,
            actualShape: record.actualShape,
            elapsedSeconds: record.elapsedSeconds,
            contentFingerprint: record.normalizedModelText.map(stableFingerprint),
            screenshotComplete: screenshot.isComplete,
            screenshotPaths: screenshot.copiedPaths,
            screenshotSHA256: screenshot.sha256ByKind,
            missingScreenshots: screenshot.missingKinds,
            baselineID: screenshot.baselineID,
            baselineManifestPath: screenshot.baselineManifestPath,
            missingRecordFields: record.missingRequiredEvidenceFields,
            artifactPaths: artifacts.copiedPaths,
            missingArtifacts: artifacts.missingKinds,
            reviews: record.review.items,
            reviewComplete: isTrustedInvocation && record.review.isComplete,
            experiencePass: isTrustedInvocation && record.review.isExperiencePass,
            sourceRunID: record.reference.sourceRunID,
            recordPath: record.reference.recordPathFromMergedRoot
        )
    }
}

private enum RichAnswerEvidenceInvocationKind: String {
    case model = "真实 Pi"
    case deterministic = "确定性拦截"
    case fixture = "夹具"
    case unknown = "未声明"
    case contradictory = "声明矛盾"
    case nonModel = "非模型"

    init(caseKind: String, modelInvocation: Bool?, fixtureInvocation: Bool?) {
        if modelInvocation == true && fixtureInvocation == true {
            self = .contradictory
        } else if fixtureInvocation == true {
            self = .fixture
        } else if caseKind == "invalid-protocol",
                  modelInvocation == false,
                  fixtureInvocation == false {
            self = .deterministic
        } else if modelInvocation == true,
                  fixtureInvocation == false {
            self = .model
        } else if modelInvocation == false,
                  fixtureInvocation == false {
            self = .nonModel
        } else {
            self = .unknown
        }
    }
}

private struct RichAnswerEvidencePackageArtifacts {
    let copiedPaths: [String: String]
    let missingKinds: [String]
}

private struct ReceiptDecodeResult<Value> {
    let value: Value?
    let missingKinds: [String]
}

private struct RichAnswerEvidencePackageScreenshot {
    let manifestStatus: String
    let captureStatus: String?
    let captureKind: String?
    let failureReason: String?
    let copiedPaths: [String: String]
    let sha256ByKind: [String: String]
    let recordSHA256: String?
    let qualityGateStatus: String?
    let reviewStatus: String?
    let baselineID: String?
    let baselineManifestPath: String?
    let expectedKinds: [String]
    let missingKinds: [String]

    var isComplete: Bool {
        manifestStatus == "succeeded"
            && captureStatus == "succeeded"
            && missingKinds.isEmpty
            && expectedKinds.allSatisfy { copiedPaths[$0] != nil }
            && expectedKinds.allSatisfy { sha256ByKind[$0] != nil }
    }

    var capturedImageCount: Int {
        guard manifestStatus == "succeeded",
              captureStatus == "succeeded" else { return 0 }
        return expectedKinds.filter { kind in
            copiedPaths[kind] != nil && sha256ByKind[kind] != nil
        }.count
    }
}

private struct RichAnswerScreenshotBatchManifest: Decodable {
    let baselineID: String?
    let baselineManifestPath: String?
    let records: [RichAnswerScreenshotRecord]

    init(
        baselineID: String?,
        baselineManifestPath: String?,
        records: [RichAnswerScreenshotRecord]
    ) {
        self.baselineID = baselineID
        self.baselineManifestPath = baselineManifestPath
        self.records = records
    }

    private enum CodingKeys: String, CodingKey {
        case baselineID
        case baselineManifestPath
        case records
    }

    init(from decoder: Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        if let records = try? singleValueContainer.decode([RichAnswerScreenshotRecord].self) {
            self.baselineID = records.compactMap(\.baselineID).first
            self.baselineManifestPath = records.compactMap(\.baselineManifestPath).first
            self.records = records
            return
        }

        let keyedContainer = try decoder.container(keyedBy: CodingKeys.self)
        if let records = try keyedContainer.decodeIfPresent(
            [RichAnswerScreenshotRecord].self,
            forKey: .records
        ) {
            self.baselineID = try keyedContainer.decodeIfPresent(String.self, forKey: .baselineID)
            self.baselineManifestPath = try keyedContainer.decodeIfPresent(
                String.self,
                forKey: .baselineManifestPath
            )
            self.records = records
            return
        }

        let record = try RichAnswerScreenshotRecord(from: decoder)
        self.baselineID = record.baselineID
        self.baselineManifestPath = record.baselineManifestPath
        self.records = [record]
    }
}

private struct RichAnswerScreenshotRecord: Decodable {
    let status: String
    let captureStatus: String?
    let failureReason: String?
    let captureKind: String?
    let replayArtifact: String?
    let caseID: String?
    let caseKind: String?
    let repetition: Int?
    let sequence: Int?
    let baselineID: String?
    let baselineManifestPath: String?
    let recordPath: String?
    let recordSHA256: String?
    let screenshots: RichAnswerScreenshotPaths
    let screenshotSHA256: RichAnswerScreenshotPaths?
    let screenshotEvidence: RichAnswerScreenshotEvidence?
    let captureReceipts: RichAnswerScreenshotCaptureReceipts?
    let qualityGate: RichAnswerScreenshotQualityGate?
    let reviewStatus: String?
}

private struct RichAnswerScreenshotPaths: Decodable {
    let overview: String?
    let before: String?
    let after: String?
    let single: String?
}

private struct RichAnswerScreenshotEvidence: Decodable {
    let overview: RichAnswerScreenshotEvidenceItem?
    let before: RichAnswerScreenshotEvidenceItem?
    let after: RichAnswerScreenshotEvidenceItem?
    let single: RichAnswerScreenshotEvidenceItem?

    func item(for kind: String) -> RichAnswerScreenshotEvidenceItem? {
        switch kind {
        case "overview": overview
        case "before": before
        case "after": after
        case "single": single
        default: nil
        }
    }
}

private struct RichAnswerScreenshotEvidenceItem: Decodable {
    let path: String?
    let sha256: String?
    let bytes: Int64?
}

private struct RichAnswerScreenshotCaptureReceipts: Decodable {
    let overview: RichAnswerScreenshotCaptureReceipt?
    let before: RichAnswerScreenshotCaptureReceipt?
    let after: RichAnswerScreenshotCaptureReceipt?
    let single: RichAnswerScreenshotCaptureReceipt?

    func item(for kind: String) -> RichAnswerScreenshotCaptureReceipt? {
        switch kind {
        case "overview": overview
        case "before": before
        case "after": after
        case "single": single
        default: nil
        }
    }
}

private struct RichAnswerScreenshotCaptureReceipt: Decodable {
    let request: RichAnswerScreenshotEvidenceItem?
    let acknowledgement: RichAnswerScreenshotEvidenceItem?
}

private struct RichAnswerScreenshotCaptureRequest: Decodable {
    let id: String?
    let capturePath: String?
}

private struct RichAnswerScreenshotCaptureAcknowledgement: Decodable {
    let id: String?
    let requestID: String?
    let requestCapturePath: String?
    let capturePath: String?
    let status: String?
    let failureReason: String?
    let actualPNG: RichAnswerScreenshotActualPNG?
    let renderReady: RichAnswerScreenshotRenderReady?
}

private struct RichAnswerScreenshotActualPNG: Decodable {
    let path: String?
    let bytes: Int64?
    let sha256: String?
    let hash: String?
}

private struct RichAnswerScreenshotRenderReady: Decodable {
    let seen: Bool?
    let path: String?
    let bytes: Int64?
    let sha256: String?
    let signature: String?
}

private struct RichAnswerScreenshotQualityGate: Decodable {
    let status: String?
}

private struct RichAnswerEvidenceReviewDimension {
    let key: String
    let label: String
    let aliases: [String]
}

private struct RichAnswerEvidenceReviewItem: Codable {
    let key: String
    let label: String
    let status: String
    let score: Double?
    let reason: String?
    let evidence: [String]

    var isReviewed: Bool {
        let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !normalized.isEmpty
            && !["待审", "pending", "unreviewed", "missing", "not-reviewed"].contains(normalized)
    }

    var isPass: Bool {
        let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["pass", "passed", "通过", "合格"].contains(normalized)
    }
}

private struct RichAnswerEvidenceExperienceReview {
    static let dimensions = [
        RichAnswerEvidenceReviewDimension(
            key: "professionalCorrectness",
            label: "专业正确性",
            aliases: ["professionalCorrectness", "professional_correctness", "professional", "专业正确性"]
        ),
        RichAnswerEvidenceReviewDimension(
            key: "aestheticQuality",
            label: "审美",
            aliases: ["aestheticQuality", "aesthetic_quality", "aesthetics", "审美"]
        ),
        RichAnswerEvidenceReviewDimension(
            key: "feasibility",
            label: "可实行性",
            aliases: ["feasibility", "practicality", "可实行性"]
        ),
        RichAnswerEvidenceReviewDimension(
            key: "usability",
            label: "可用性",
            aliases: ["usability", "可用性"]
        ),
        RichAnswerEvidenceReviewDimension(
            key: "readability",
            label: "可读性",
            aliases: ["readability", "可读性"]
        ),
        RichAnswerEvidenceReviewDimension(
            key: "interactionAuthenticity",
            label: "交互真实性",
            aliases: ["interactionAuthenticity", "interaction_authenticity", "interaction", "交互真实性"]
        ),
        RichAnswerEvidenceReviewDimension(
            key: "learningEffectiveness",
            label: "学习有效性",
            aliases: ["learningEffectiveness", "learning_effectiveness", "learning", "学习有效性"]
        ),
    ]

    let items: [RichAnswerEvidenceReviewItem]
    let rawJSON: String?

    var reviewedItemCount: Int {
        items.filter(\.isReviewed).count
    }

    var isComplete: Bool {
        items.count == Self.dimensions.count && items.allSatisfy(\.isReviewed)
    }

    var isExperiencePass: Bool {
        isComplete && items.allSatisfy(\.isPass)
    }

    static func load(
        recordRoot: [String: Any],
        sourceDirectory: URL
    ) -> RichAnswerEvidenceExperienceReview {
        let reviewURL = sourceDirectory.appendingPathComponent("review.json")
        if FileManager.default.fileExists(atPath: reviewURL.path) {
            do {
                let rawValue = try JSONSerialization.jsonObject(with: Data(contentsOf: reviewURL))
                return parse(rawValue: rawValue, errorReason: nil)
            } catch {
                return pending(reason: "review.json 无法读取：\(error.localizedDescription)")
            }
        }
        if let embeddedReview = recordRoot["review"] {
            return parse(rawValue: embeddedReview, errorReason: nil)
        }
        return pending(reason: "未提供 review.json 或 record.review")
    }

    private static func parse(rawValue: Any, errorReason: String?) -> Self {
        guard let root = rawValue as? [String: Any] else {
            return pending(reason: errorReason ?? "review 不是 JSON 对象")
        }
        let dimensionsObject = dictionary(root["dimensions"])
        let keyedItems = dimensionsObject.isEmpty ? root : dimensionsObject
        let listedItems = dictionaries(root["items"])
        let items = dimensions.map { dimension -> RichAnswerEvidenceReviewItem in
            let keyedValue = dimension.aliases.compactMap { alias in
                keyedItems[alias] as? [String: Any]
            }.first
            let listedValue = listedItems.first { candidate in
                let candidateKey = string(candidate["dimension"])
                    ?? string(candidate["key"])
                    ?? string(candidate["id"])
                    ?? string(candidate["label"])
                    ?? ""
                return dimension.aliases.contains { alias in
                    alias.caseInsensitiveCompare(candidateKey) == .orderedSame
                }
            }
            guard let value = keyedValue ?? listedValue else {
                return pendingItem(dimension: dimension, reason: "未提供该项审查")
            }
            let status = string(value["status"])?.trimmingCharacters(in: .whitespacesAndNewlines)
            let evidence: [String]
            if let evidenceText = string(value["evidence"]) {
                evidence = [evidenceText]
            } else {
                evidence = strings(value["evidence"])
            }
            return RichAnswerEvidenceReviewItem(
                key: dimension.key,
                label: dimension.label,
                status: status?.isEmpty == false ? status! : "待审",
                score: number(value["score"]),
                reason: string(value["reason"]),
                evidence: evidence
            )
        }
        return Self(items: items, rawJSON: prettyJSONString(rawValue))
    }

    private static func pending(reason: String) -> Self {
        Self(
            items: dimensions.map { pendingItem(dimension: $0, reason: reason) },
            rawJSON: nil
        )
    }

    private static func pendingItem(
        dimension: RichAnswerEvidenceReviewDimension,
        reason: String
    ) -> RichAnswerEvidenceReviewItem {
        RichAnswerEvidenceReviewItem(
            key: dimension.key,
            label: dimension.label,
            status: "待审",
            score: nil,
            reason: reason,
            evidence: []
        )
    }
}

private struct RichAnswerEvidencePackageRecord {
    let reference: RichAnswerEvidencePackageRecordReference
    let repetition: Int
    let caseID: String
    let caseKind: String
    let subject: String
    let status: String
    let elapsedSeconds: TimeInterval
    let modelInvocation: Bool?
    let fixtureInvocation: Bool?
    let question: String
    let materialTitle: String?
    let materialText: String?
    let selectionTitle: String?
    let selectionText: String?
    let modelText: String?
    let normalizedModelText: String?
    let rawRequestJSON: String?
    let rawModelReplyJSON: String?
    let expectedShape: String
    let actualShape: String
    let expressionSummary: String?
    let t1Programs: [[String: Any]]
    let t2Compositions: [[String: Any]]
    let renderPlans: [[String: Any]]
    let validationStatus: String?
    let validationKind: String?
    let validationIssues: [String]
    let protocolDiagnostics: [String]
    let textSourceLabels: [String]
    let evidenceLedgerLabels: [String]
    let hasExpectedSource: Bool?
    let failureReason: String?
    let previousRunID: String?
    let repairNote: String?
    let isRetest: Bool?
    let review: RichAnswerEvidenceExperienceReview
    let missingRequiredEvidenceFields: [String]

    init(reference: RichAnswerEvidencePackageRecordReference) throws {
        self.reference = reference
        let data = try Data(contentsOf: reference.recordURL)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RichAnswerEvidenceError.invalidConfiguration(
                "record is not a JSON object: \(reference.recordURL.path)"
            )
        }
        let caseSnapshot = dictionary(root["caseSnapshot"])
        let prompt = dictionary(root["promptAndMaterial"])
        let shape = dictionary(root["shapeDecision"])
        let expression = dictionary(root["expressionPlan"])
        let expressionPlan = dictionary(expression["expressionPlan"])
        let validation = dictionary(root["toolAndProtocolValidation"])
        let source = dictionary(root["sourceBinding"])
        let repair = dictionary(root["repairAndRetest"])
        let reply = dictionary(root["modelRawReply"])
        let review = RichAnswerEvidenceExperienceReview.load(
            recordRoot: root,
            sourceDirectory: reference.recordURL.deletingLastPathComponent()
        )

        repetition = integer(root["repetition"]) ?? reference.repetition
        caseID = string(caseSnapshot["id"]) ?? reference.caseID
        caseKind = string(caseSnapshot["caseKind"]) ?? reference.caseKind
        subject = string(caseSnapshot["subject"]) ?? reference.subject
        status = string(root["status"]) ?? "missing"
        elapsedSeconds = number(root["elapsedSeconds"]) ?? 0
        modelInvocation = boolean(root["modelInvocation"])
        fixtureInvocation = boolean(root["fixtureInvocation"])
        question = string(prompt["question"])
            ?? string(caseSnapshot["question"])
            ?? "缺少题目"
        materialTitle = string(prompt["materialTitle"]) ?? string(caseSnapshot["materialTitle"])
        materialText = string(prompt["materialText"]) ?? string(caseSnapshot["materialText"])
        selectionTitle = string(prompt["selectionTitle"]) ?? string(caseSnapshot["selectionTitle"])
        selectionText = string(prompt["selectionText"]) ?? string(caseSnapshot["selectionText"])
        modelText = string(reply["text"])
        normalizedModelText = modelText.map(normalizeText)
        rawRequestJSON = root["promptAndMaterial"].flatMap(prettyJSONString)
        rawModelReplyJSON = root["modelRawReply"].flatMap(prettyJSONString)
        expectedShape = string(shape["expectedShape"]) ?? "未记录"
        actualShape = string(shape["actualShape"]) ?? "未记录"
        expressionSummary = string(expressionPlan["summary"])
        t1Programs = dictionaries(expression["t1Programs"])
        t2Compositions = dictionaries(expression["t2Compositions"])
        renderPlans = dictionaries(expression["renderPlans"])
        validationStatus = string(validation["status"])
        validationKind = string(validation["validationKind"])
        validationIssues = strings(validation["issues"])
        protocolDiagnostics = strings(validation["protocolDiagnostics"])
        textSourceLabels = strings(source["textSourceLabels"])
        evidenceLedgerLabels = strings(source["evidenceLedgerLabels"])
        hasExpectedSource = boolean(source["hasExpectedSource"])
        failureReason = string(root["failureReason"])
        previousRunID = string(repair["previousRunID"])
        repairNote = string(repair["repairNote"])
        isRetest = boolean(repair["isRetest"])
        self.review = review
        var missingFields: [String] = []
        if root["modelInvocation"] == nil { missingFields.append("modelInvocation") }
        if root["fixtureInvocation"] == nil { missingFields.append("fixtureInvocation") }
        if root["shapeDecision"] == nil { missingFields.append("shapeDecision") }
        if root["expressionPlan"] == nil { missingFields.append("expressionPlan") }
        if root["toolAndProtocolValidation"] == nil { missingFields.append("toolAndProtocolValidation") }
        if root["sourceBinding"] == nil { missingFields.append("sourceBinding") }
        if root["repairAndRetest"] == nil { missingFields.append("repairAndRetest") }
        if root["elapsedSeconds"] == nil { missingFields.append("elapsedSeconds") }
        if caseSnapshot["question"] == nil && prompt["question"] == nil { missingFields.append("question") }
        if caseSnapshot["materialText"] == nil && prompt["materialText"] == nil { missingFields.append("materialText") }
        if caseKind != "invalid-protocol" && root["modelRawReply"] == nil { missingFields.append("modelRawReply") }
        if modelInvocation == true && nonEmptyString(modelText) == nil { missingFields.append("modelRawReply.text") }
        if status == "failed" && nonEmptyString(failureReason) == nil { missingFields.append("failureReason") }
        missingRequiredEvidenceFields = missingFields
    }
}

private func dictionary(_ value: Any?) -> [String: Any] {
    value as? [String: Any] ?? [:]
}

private func dictionaries(_ value: Any?) -> [[String: Any]] {
    value as? [[String: Any]] ?? []
}

private func string(_ value: Any?) -> String? {
    value as? String
}

private func nonEmptyString(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func strings(_ value: Any?) -> [String] {
    value as? [String] ?? []
}

private func boolean(_ value: Any?) -> Bool? {
    value as? Bool
}

private func integer(_ value: Any?) -> Int? {
    if let value = value as? Int { return value }
    return (value as? NSNumber)?.intValue
}

private func number(_ value: Any?) -> Double? {
    if let value = value as? Double { return value }
    return (value as? NSNumber)?.doubleValue
}

private func prettyJSONString(_ value: Any) -> String? {
    guard JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(
              withJSONObject: value,
              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
          ) else { return nil }
    return String(data: data, encoding: .utf8)
}

private func normalizeText(_ value: String) -> String {
    value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

private func stableFingerprint(_ value: String) -> String {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in value.utf8 {
        hash ^= UInt64(byte)
        hash &*= 1_099_511_628_211
    }
    return String(format: "%016llx", hash)
}

private extension Array where Element == String {
    func uniqued() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}
