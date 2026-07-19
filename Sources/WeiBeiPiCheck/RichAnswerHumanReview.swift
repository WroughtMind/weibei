import Foundation

enum RichAnswerHumanReviewVerdict: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case pass
    case warn
    case fail
    case notReviewed
}

enum RichAnswerHumanReviewOverallStatus: String, Codable, Equatable, Sendable {
    case pendingUserAcceptance
    case accepted
    case rejected
}

enum RichAnswerHumanReviewDimension: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case professionalCorrectness
    case sourceGrounding
    case learningGain
    case rendererChoice
    case realInteraction
    case visualDiversity
    case readability
    case responsiveness
    case performanceAndResources
    case honestDegradation

    var label: String {
        switch self {
        case .professionalCorrectness: "专业正确性"
        case .sourceGrounding: "来源"
        case .learningGain: "学习增益"
        case .rendererChoice: "渲染器选择"
        case .realInteraction: "真实互动"
        case .visualDiversity: "视觉多样性"
        case .readability: "可读性"
        case .responsiveness: "响应式"
        case .performanceAndResources: "性能/资源"
        case .honestDegradation: "诚实降级"
        }
    }
}

enum RichAnswerHumanReviewScreenshotKind: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case before
    case after
    case single
    case detail
}

enum RichAnswerHumanReviewValidationSeverity: String, Codable, Equatable, Sendable {
    case error
    case warning
}

struct RichAnswerHumanReviewStatusCounts: Codable, Equatable, Sendable {
    var pass: Int
    var warn: Int
    var fail: Int
    var notReviewed: Int

    static let zero = RichAnswerHumanReviewStatusCounts(
        pass: 0,
        warn: 0,
        fail: 0,
        notReviewed: 0
    )

    var total: Int {
        pass + warn + fail + notReviewed
    }

    mutating func add(_ status: RichAnswerHumanReviewVerdict, count: Int = 1) {
        switch status {
        case .pass:
            pass += count
        case .warn:
            warn += count
        case .fail:
            fail += count
        case .notReviewed:
            notReviewed += count
        }
    }
}

struct RichAnswerHumanReviewScreenshotReference: Codable, Equatable, Sendable {
    var kind: RichAnswerHumanReviewScreenshotKind
    var path: String
    var sha256: String
    var width: Int?
    var height: Int?
    var note: String?
}

struct RichAnswerHumanReviewFailureClusterKey: Codable, Equatable, Hashable, Sendable {
    var dimension: RichAnswerHumanReviewDimension
    var renderer: String
    var failureFamily: String
    var normalizedSignature: String

    var stableKey: String {
        [
            dimension.rawValue,
            Self.normalizedKeyComponent(renderer),
            Self.normalizedKeyComponent(failureFamily),
            Self.normalizedKeyComponent(normalizedSignature),
        ].joined(separator: ":")
    }

    static func make(
        dimension: RichAnswerHumanReviewDimension,
        renderer: String,
        failureFamily: String,
        signature: String
    ) -> RichAnswerHumanReviewFailureClusterKey {
        RichAnswerHumanReviewFailureClusterKey(
            dimension: dimension,
            renderer: renderer,
            failureFamily: failureFamily,
            normalizedSignature: normalizedKeyComponent(signature)
        )
    }

    private static func normalizedKeyComponent(_ rawValue: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let lowered = rawValue.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let scalars = lowered.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(scalars)
            .split(separator: "-")
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return collapsed.isEmpty ? "unspecified" : collapsed
    }
}

struct RichAnswerHumanReviewFinding: Codable, Equatable, Sendable {
    var dimension: RichAnswerHumanReviewDimension
    var status: RichAnswerHumanReviewVerdict
    var evidencePaths: [String]
    var reason: String
    var failureClusterKey: RichAnswerHumanReviewFailureClusterKey?

    var isReviewed: Bool {
        status != .notReviewed
    }
}

struct RichAnswerHumanReviewRetestLink: Codable, Equatable, Sendable {
    var architectureFixID: String
    var fixSummary: String
    var previousRunID: String
    var previousCaseID: String
    var previousRepetition: Int
    var previousEvidencePath: String
    var retestEvidencePath: String
    var result: RichAnswerHumanReviewVerdict
}

struct RichAnswerHumanReviewRoundRecord: Codable, Equatable, Sendable {
    var repetition: Int
    var reviewer: String
    var reviewedAt: String
    var evidenceRecordPath: String
    var rendererUsed: String?
    var screenshotReferences: [RichAnswerHumanReviewScreenshotReference]
    var findings: [RichAnswerHumanReviewFinding]
    var architectureRetestChain: [RichAnswerHumanReviewRetestLink]
}

struct RichAnswerHumanReviewCaseRecord: Codable, Equatable, Sendable {
    var caseID: String
    var caseKind: String
    var subject: String
    var question: String
    var rounds: [RichAnswerHumanReviewRoundRecord]
}

struct RichAnswerHumanReviewUserAcceptance: Codable, Equatable, Sendable {
    var status: RichAnswerHumanReviewOverallStatus
    var confirmedBy: String
    var confirmedAt: String
    var note: String
}

struct RichAnswerHumanReviewDimensionSummary: Codable, Equatable, Sendable {
    var dimension: RichAnswerHumanReviewDimension
    var label: String
    var statusCounts: RichAnswerHumanReviewStatusCounts
    var overallVerdict: RichAnswerHumanReviewVerdict
}

struct RichAnswerHumanReviewFailureClusterSummary: Codable, Equatable, Sendable {
    var stableKey: String
    var dimension: RichAnswerHumanReviewDimension
    var renderer: String
    var failureFamily: String
    var normalizedSignature: String
    var statusCounts: RichAnswerHumanReviewStatusCounts
    var affectedAttempts: [String]
}

struct RichAnswerHumanReviewArchitectureRetestSummary: Codable, Equatable, Sendable {
    var architectureFixID: String
    var fixSummary: String
    var linkedAttemptCount: Int
    var previousAttempts: [String]
    var retestEvidencePaths: [String]
    var resultCounts: RichAnswerHumanReviewStatusCounts
}

struct RichAnswerHumanReviewSummary: Codable, Equatable, Sendable {
    var overallStatus: RichAnswerHumanReviewOverallStatus
    var technicalGateVerdict: RichAnswerHumanReviewVerdict
    var expectedCaseCount: Int
    var observedCaseCount: Int
    var expectedAttemptCount: Int
    var observedAttemptCount: Int
    var completeAttemptCount: Int
    var expectedReviewItemCount: Int
    var observedReviewItemCount: Int
    var reviewedItemCount: Int
    var statusCounts: RichAnswerHumanReviewStatusCounts
    var dimensionSummaries: [RichAnswerHumanReviewDimensionSummary]
    var expectedScreenshotReferenceCount: Int
    var screenshotReferenceCount: Int
    var screenshotHashReferenceCount: Int
    var minimumScreenshotHashReferenceCount: Int
    var failureClusters: [RichAnswerHumanReviewFailureClusterSummary]
    var architectureRetestChains: [RichAnswerHumanReviewArchitectureRetestSummary]
    var userAcceptanceRequired: Bool
    var userAccepted: Bool
}

struct RichAnswerHumanReviewDocument: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var runID: String
    var generatedAt: String
    var cases: [RichAnswerHumanReviewCaseRecord]
    var userAcceptance: RichAnswerHumanReviewUserAcceptance?
    var summary: RichAnswerHumanReviewSummary

    init(
        runID: String,
        generatedAt: String,
        cases: [RichAnswerHumanReviewCaseRecord],
        userAcceptance: RichAnswerHumanReviewUserAcceptance? = nil,
        policy: RichAnswerHumanReviewValidationPolicy = .standard56x4
    ) {
        self.schemaVersion = 1
        self.runID = runID
        self.generatedAt = generatedAt
        self.cases = cases
        self.userAcceptance = userAcceptance
        self.summary = RichAnswerHumanReviewValidator.summarize(
            cases: cases,
            userAcceptance: userAcceptance,
            policy: policy
        )
    }

    init(
        schemaVersion: Int,
        runID: String,
        generatedAt: String,
        cases: [RichAnswerHumanReviewCaseRecord],
        userAcceptance: RichAnswerHumanReviewUserAcceptance?,
        summary: RichAnswerHumanReviewSummary
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.generatedAt = generatedAt
        self.cases = cases
        self.userAcceptance = userAcceptance
        self.summary = summary
    }
}

struct RichAnswerHumanReviewValidationPolicy: Codable, Equatable, Sendable {
    var expectedCaseIDs: [String]?
    var expectedCaseCount: Int
    var requiredRepetitions: [Int]
    var requiredDimensions: [RichAnswerHumanReviewDimension]
    var maximumReasonCharacterCount: Int
    var minimumScreenshotHashReferenceCount: Int
    var requiresEvidencePathForEveryItem: Bool
    var requiresFailureClusterForFailures: Bool

    static let standard56x4 = RichAnswerHumanReviewValidationPolicy(
        expectedCaseIDs: nil,
        expectedCaseCount: 56,
        requiredRepetitions: [1, 2, 3, 4],
        requiredDimensions: RichAnswerHumanReviewDimension.allCases,
        maximumReasonCharacterCount: 180,
        minimumScreenshotHashReferenceCount: 384,
        requiresEvidencePathForEveryItem: true,
        requiresFailureClusterForFailures: true
    )
}

struct RichAnswerHumanReviewValidationIssue: Codable, Equatable, Sendable {
    var severity: RichAnswerHumanReviewValidationSeverity
    var path: String
    var message: String
}

struct RichAnswerHumanReviewValidationReport: Codable, Equatable, Sendable {
    var isValid: Bool
    var issues: [RichAnswerHumanReviewValidationIssue]
    var computedSummary: RichAnswerHumanReviewSummary
}

enum RichAnswerHumanReviewValidator {
    static func validate(
        document: RichAnswerHumanReviewDocument,
        policy: RichAnswerHumanReviewValidationPolicy = .standard56x4
    ) -> RichAnswerHumanReviewValidationReport {
        let computedSummary = summarize(
            cases: document.cases,
            userAcceptance: document.userAcceptance,
            policy: policy
        )
        var issues: [RichAnswerHumanReviewValidationIssue] = []

        if document.schemaVersion != 1 {
            issues.append(error("schemaVersion", "人工专业审查记录 schemaVersion 必须为 1"))
        }
        if trimmed(document.runID).isEmpty {
            issues.append(error("runID", "runID 不能为空"))
        }
        if trimmed(document.generatedAt).isEmpty {
            issues.append(error("generatedAt", "generatedAt 不能为空"))
        }
        if document.summary != computedSummary {
            issues.append(error("summary", "summary 必须由确定性汇总重新生成，不能手写成 accepted"))
        }

        validateAcceptance(
            summary: document.summary,
            userAcceptance: document.userAcceptance,
            issues: &issues
        )
        validateCases(document.cases, policy: policy, issues: &issues)

        if document.userAcceptance?.status == .accepted,
           computedSummary.technicalGateVerdict != .pass {
            issues.append(warning(
                "userAcceptance.status",
                "用户已确认，但技术闸门仍为 \(computedSummary.technicalGateVerdict.rawValue)"
            ))
        }

        let isValid = !issues.contains { $0.severity == .error }
        return RichAnswerHumanReviewValidationReport(
            isValid: isValid,
            issues: issues.sorted { issueA, issueB in
                issueA.path == issueB.path
                    ? issueA.message < issueB.message
                    : issueA.path < issueB.path
            },
            computedSummary: computedSummary
        )
    }

    static func summarize(
        cases: [RichAnswerHumanReviewCaseRecord],
        userAcceptance: RichAnswerHumanReviewUserAcceptance?,
        policy: RichAnswerHumanReviewValidationPolicy = .standard56x4
    ) -> RichAnswerHumanReviewSummary {
        let expectedAttemptCount = policy.expectedCaseCount * policy.requiredRepetitions.count
        let observedAttemptCount = cases.reduce(0) { count, reviewCase in
            count + reviewCase.rounds.count
        }
        let allRounds = cases.flatMap { reviewCase in
            reviewCase.rounds.map { round in
                (reviewCase: reviewCase, round: round)
            }
        }
        let allFindings = allRounds.flatMap { attempt in
            attempt.round.findings.map { finding in
                (attempt: attempt, finding: finding)
            }
        }

        var statusCounts = RichAnswerHumanReviewStatusCounts.zero
        for finding in allFindings {
            statusCounts.add(finding.finding.status)
        }

        let expectedReviewItemCount = expectedAttemptCount * policy.requiredDimensions.count
        let observedReviewItemCount = allFindings.count
        let missingReviewItemCount = max(0, expectedReviewItemCount - observedReviewItemCount)
        statusCounts.add(.notReviewed, count: missingReviewItemCount)

        let dimensionSummaries = policy.requiredDimensions.map { dimension -> RichAnswerHumanReviewDimensionSummary in
            let observedDimensionFindings = allFindings.filter { $0.finding.dimension == dimension }
            var dimensionCounts = RichAnswerHumanReviewStatusCounts.zero
            for finding in observedDimensionFindings {
                dimensionCounts.add(finding.finding.status)
            }
            dimensionCounts.add(
                .notReviewed,
                count: max(0, expectedAttemptCount - observedDimensionFindings.count)
            )
            return RichAnswerHumanReviewDimensionSummary(
                dimension: dimension,
                label: dimension.label,
                statusCounts: dimensionCounts,
                overallVerdict: verdict(from: dimensionCounts)
            )
        }

        let completeAttemptCount = allRounds.filter { attempt in
            let dimensions = Set(attempt.round.findings.map(\.dimension))
            let requiredDimensions = Set(policy.requiredDimensions)
            return dimensions == requiredDimensions
                && attempt.round.findings.allSatisfy(\.isReviewed)
                && screenshotKindsAreComplete(
                    attempt.round.screenshotReferences,
                    caseKind: attempt.reviewCase.caseKind
                )
        }.count

        let screenshotReferenceCount = allRounds.reduce(0) { count, attempt in
            count + attempt.round.screenshotReferences.count
        }
        let screenshotHashReferenceCount = allRounds.reduce(0) { count, attempt in
            count + attempt.round.screenshotReferences.filter { isSHA256($0.sha256) }.count
        }
        let expectedScreenshotReferenceCount = cases.reduce(0) { count, reviewCase in
            count + expectedScreenshotKinds(caseKind: reviewCase.caseKind).count
                * policy.requiredRepetitions.count
        }

        var clusterBuckets: [String: RichAnswerHumanReviewFailureClusterSummary] = [:]
        for item in allFindings {
            guard let key = item.finding.failureClusterKey else { continue }
            let stableKey = key.stableKey
            var summary = clusterBuckets[stableKey] ?? RichAnswerHumanReviewFailureClusterSummary(
                stableKey: stableKey,
                dimension: key.dimension,
                renderer: key.renderer,
                failureFamily: key.failureFamily,
                normalizedSignature: key.normalizedSignature,
                statusCounts: .zero,
                affectedAttempts: []
            )
            summary.statusCounts.add(item.finding.status)
            summary.affectedAttempts.append(
                attemptKey(caseID: item.attempt.reviewCase.caseID, repetition: item.attempt.round.repetition)
            )
            summary.affectedAttempts = Array(Set(summary.affectedAttempts)).sorted()
            clusterBuckets[stableKey] = summary
        }

        var retestBuckets: [String: RichAnswerHumanReviewArchitectureRetestSummary] = [:]
        for attempt in allRounds {
            for link in attempt.round.architectureRetestChain {
                var summary = retestBuckets[link.architectureFixID] ?? RichAnswerHumanReviewArchitectureRetestSummary(
                    architectureFixID: link.architectureFixID,
                    fixSummary: link.fixSummary,
                    linkedAttemptCount: 0,
                    previousAttempts: [],
                    retestEvidencePaths: [],
                    resultCounts: .zero
                )
                summary.linkedAttemptCount += 1
                summary.previousAttempts.append(
                    attemptKey(caseID: link.previousCaseID, repetition: link.previousRepetition)
                )
                summary.previousAttempts = Array(Set(summary.previousAttempts)).sorted()
                summary.retestEvidencePaths.append(link.retestEvidencePath)
                summary.retestEvidencePaths = Array(Set(summary.retestEvidencePaths)).sorted()
                summary.resultCounts.add(link.result)
                retestBuckets[link.architectureFixID] = summary
            }
        }

        let technicalGateVerdict = technicalVerdict(
            statusCounts: statusCounts,
            expectedAttemptCount: expectedAttemptCount,
            observedAttemptCount: observedAttemptCount,
            screenshotHashReferenceCount: screenshotHashReferenceCount,
            minimumScreenshotHashReferenceCount: policy.minimumScreenshotHashReferenceCount
        )
        return RichAnswerHumanReviewSummary(
            overallStatus: overallStatus(from: userAcceptance),
            technicalGateVerdict: technicalGateVerdict,
            expectedCaseCount: policy.expectedCaseCount,
            observedCaseCount: Set(cases.map(\.caseID)).count,
            expectedAttemptCount: expectedAttemptCount,
            observedAttemptCount: observedAttemptCount,
            completeAttemptCount: completeAttemptCount,
            expectedReviewItemCount: expectedReviewItemCount,
            observedReviewItemCount: observedReviewItemCount,
            reviewedItemCount: allFindings.filter { $0.finding.isReviewed }.count,
            statusCounts: statusCounts,
            dimensionSummaries: dimensionSummaries,
            expectedScreenshotReferenceCount: expectedScreenshotReferenceCount,
            screenshotReferenceCount: screenshotReferenceCount,
            screenshotHashReferenceCount: screenshotHashReferenceCount,
            minimumScreenshotHashReferenceCount: policy.minimumScreenshotHashReferenceCount,
            failureClusters: clusterBuckets.values.sorted { $0.stableKey < $1.stableKey },
            architectureRetestChains: retestBuckets.values.sorted { $0.architectureFixID < $1.architectureFixID },
            userAcceptanceRequired: true,
            userAccepted: userAcceptance?.status == .accepted
        )
    }

    private static func validateAcceptance(
        summary: RichAnswerHumanReviewSummary,
        userAcceptance: RichAnswerHumanReviewUserAcceptance?,
        issues: inout [RichAnswerHumanReviewValidationIssue]
    ) {
        if userAcceptance == nil,
           summary.overallStatus != .pendingUserAcceptance {
            issues.append(error(
                "summary.overallStatus",
                "用户确认前总状态必须保持 pendingUserAcceptance"
            ))
        }
        if summary.technicalGateVerdict == .pass,
           summary.overallStatus == .accepted,
           userAcceptance?.status != .accepted {
            issues.append(error(
                "summary.overallStatus",
                "技术闸门通过不得自动转成 accepted"
            ))
        }
        guard let userAcceptance else { return }
        if userAcceptance.status == .pendingUserAcceptance {
            issues.append(error(
                "userAcceptance.status",
                "userAcceptance 只能记录用户明确 accepted 或 rejected，未确认时应为空"
            ))
        }
        if trimmed(userAcceptance.confirmedBy).isEmpty {
            issues.append(error("userAcceptance.confirmedBy", "用户确认人不能为空"))
        }
        if trimmed(userAcceptance.confirmedAt).isEmpty {
            issues.append(error("userAcceptance.confirmedAt", "用户确认时间不能为空"))
        }
    }

    private static func validateCases(
        _ cases: [RichAnswerHumanReviewCaseRecord],
        policy: RichAnswerHumanReviewValidationPolicy,
        issues: inout [RichAnswerHumanReviewValidationIssue]
    ) {
        let caseIDs = cases.map(\.caseID)
        let uniqueCaseIDs = Set(caseIDs)
        if uniqueCaseIDs.count != caseIDs.count {
            issues.append(error("cases", "caseID 不能重复"))
        }
        if let expectedCaseIDs = policy.expectedCaseIDs {
            let expected = Set(expectedCaseIDs)
            let missing = expected.subtracting(uniqueCaseIDs).sorted()
            let unexpected = uniqueCaseIDs.subtracting(expected).sorted()
            if !missing.isEmpty {
                issues.append(error("cases", "缺少题目：\(missing.joined(separator: ","))"))
            }
            if !unexpected.isEmpty {
                issues.append(error("cases", "出现非矩阵题目：\(unexpected.joined(separator: ","))"))
            }
        } else if uniqueCaseIDs.count != policy.expectedCaseCount {
            issues.append(error(
                "cases",
                "人工专业审查必须覆盖 \(policy.expectedCaseCount) 题，当前 \(uniqueCaseIDs.count) 题"
            ))
        }

        for (caseIndex, reviewCase) in cases.enumerated() {
            let casePath = "cases[\(caseIndex)]"
            validateCase(reviewCase, path: casePath, policy: policy, issues: &issues)
        }
    }

    private static func validateCase(
        _ reviewCase: RichAnswerHumanReviewCaseRecord,
        path: String,
        policy: RichAnswerHumanReviewValidationPolicy,
        issues: inout [RichAnswerHumanReviewValidationIssue]
    ) {
        if trimmed(reviewCase.caseID).isEmpty {
            issues.append(error("\(path).caseID", "caseID 不能为空"))
        }
        if trimmed(reviewCase.caseKind).isEmpty {
            issues.append(error("\(path).caseKind", "caseKind 不能为空"))
        }
        if trimmed(reviewCase.subject).isEmpty {
            issues.append(error("\(path).subject", "subject 不能为空"))
        }
        if trimmed(reviewCase.question).isEmpty {
            issues.append(error("\(path).question", "question 不能为空"))
        }

        let repetitions = reviewCase.rounds.map(\.repetition)
        let uniqueRepetitions = Set(repetitions)
        if uniqueRepetitions.count != repetitions.count {
            issues.append(error("\(path).rounds", "同一题的 repetition 不能重复"))
        }
        let requiredRepetitions = Set(policy.requiredRepetitions)
        let missingRepetitions = requiredRepetitions.subtracting(uniqueRepetitions).sorted()
        let unexpectedRepetitions = uniqueRepetitions.subtracting(requiredRepetitions).sorted()
        if !missingRepetitions.isEmpty {
            issues.append(error(
                "\(path).rounds",
                "\(reviewCase.caseID) 缺少轮次：\(missingRepetitions.map(String.init).joined(separator: ","))"
            ))
        }
        if !unexpectedRepetitions.isEmpty {
            issues.append(error(
                "\(path).rounds",
                "\(reviewCase.caseID) 出现非法轮次：\(unexpectedRepetitions.map(String.init).joined(separator: ","))"
            ))
        }

        for (roundIndex, round) in reviewCase.rounds.enumerated() {
            validateRound(
                round,
                caseID: reviewCase.caseID,
                caseKind: reviewCase.caseKind,
                path: "\(path).rounds[\(roundIndex)]",
                policy: policy,
                issues: &issues
            )
        }
    }

    private static func validateRound(
        _ round: RichAnswerHumanReviewRoundRecord,
        caseID: String,
        caseKind: String,
        path: String,
        policy: RichAnswerHumanReviewValidationPolicy,
        issues: inout [RichAnswerHumanReviewValidationIssue]
    ) {
        if trimmed(round.reviewer).isEmpty {
            issues.append(error("\(path).reviewer", "人工审查人不能为空"))
        }
        if trimmed(round.reviewedAt).isEmpty {
            issues.append(error("\(path).reviewedAt", "reviewedAt 不能为空"))
        }
        if trimmed(round.evidenceRecordPath).isEmpty {
            issues.append(error("\(path).evidenceRecordPath", "必须引用本轮 record.json 或等价证据记录"))
        }

        validateScreenshots(
            round.screenshotReferences,
            caseKind: caseKind,
            path: "\(path).screenshotReferences",
            issues: &issues
        )
        validateFindings(
            round.findings,
            caseID: caseID,
            repetition: round.repetition,
            path: "\(path).findings",
            policy: policy,
            issues: &issues
        )
        validateRetestChain(
            round.architectureRetestChain,
            path: "\(path).architectureRetestChain",
            policy: policy,
            issues: &issues
        )
    }

    private static func validateScreenshots(
        _ screenshots: [RichAnswerHumanReviewScreenshotReference],
        caseKind: String,
        path: String,
        issues: inout [RichAnswerHumanReviewValidationIssue]
    ) {
        let actualKinds = Set(screenshots.map(\.kind))
        let missingKinds = expectedScreenshotKinds(caseKind: caseKind).subtracting(actualKinds)
        if !missingKinds.isEmpty {
            issues.append(error(
                path,
                "缺少截图类型：\(missingKinds.map(\.rawValue).sorted().joined(separator: ","))"
            ))
        }
        for (index, screenshot) in screenshots.enumerated() {
            let screenshotPath = "\(path)[\(index)]"
            if trimmed(screenshot.path).isEmpty {
                issues.append(error("\(screenshotPath).path", "截图路径不能为空"))
            }
            if !isSHA256(screenshot.sha256) {
                issues.append(error("\(screenshotPath).sha256", "截图必须引用 64 位 SHA-256"))
            }
            if let width = screenshot.width, width <= 0 {
                issues.append(error("\(screenshotPath).width", "截图宽度必须大于 0"))
            }
            if let height = screenshot.height, height <= 0 {
                issues.append(error("\(screenshotPath).height", "截图高度必须大于 0"))
            }
        }
    }

    private static func validateFindings(
        _ findings: [RichAnswerHumanReviewFinding],
        caseID: String,
        repetition: Int,
        path: String,
        policy: RichAnswerHumanReviewValidationPolicy,
        issues: inout [RichAnswerHumanReviewValidationIssue]
    ) {
        let dimensions = findings.map(\.dimension)
        let uniqueDimensions = Set(dimensions)
        if uniqueDimensions.count != dimensions.count {
            issues.append(error(path, "同一轮同一审查项不能重复"))
        }
        let requiredDimensions = Set(policy.requiredDimensions)
        let missingDimensions = requiredDimensions.subtracting(uniqueDimensions).sorted { $0.rawValue < $1.rawValue }
        let unexpectedDimensions = uniqueDimensions.subtracting(requiredDimensions).sorted { $0.rawValue < $1.rawValue }
        if !missingDimensions.isEmpty {
            issues.append(error(
                path,
                "\(caseID) 第 \(repetition) 轮缺少审查项：\(missingDimensions.map(\.rawValue).joined(separator: ","))"
            ))
        }
        if !unexpectedDimensions.isEmpty {
            issues.append(error(
                path,
                "\(caseID) 第 \(repetition) 轮出现非标准审查项：\(unexpectedDimensions.map(\.rawValue).joined(separator: ","))"
            ))
        }

        for (index, finding) in findings.enumerated() {
            let findingPath = "\(path)[\(index)]"
            let reason = trimmed(finding.reason)
            if reason.isEmpty {
                issues.append(error("\(findingPath).reason", "每项必须写简短原因"))
            }
            if reason.count > policy.maximumReasonCharacterCount {
                issues.append(error(
                    "\(findingPath).reason",
                    "原因过长，应不超过 \(policy.maximumReasonCharacterCount) 字"
                ))
            }
            if policy.requiresEvidencePathForEveryItem,
               finding.evidencePaths.map(trimmed).filter({ !$0.isEmpty }).isEmpty {
                issues.append(error("\(findingPath).evidencePaths", "每项必须至少引用一个证据路径"))
            }
            for (evidenceIndex, evidencePath) in finding.evidencePaths.enumerated()
                where trimmed(evidencePath).isEmpty {
                issues.append(error("\(findingPath).evidencePaths[\(evidenceIndex)]", "证据路径不能为空"))
            }
            if finding.status == .fail,
               policy.requiresFailureClusterForFailures,
               finding.failureClusterKey == nil {
                issues.append(error(
                    "\(findingPath).failureClusterKey",
                    "fail 项必须提供同类失败聚类键，便于修架构而不是逐题硬补"
                ))
            }
            if let clusterKey = finding.failureClusterKey {
                validateClusterKey(clusterKey, path: "\(findingPath).failureClusterKey", issues: &issues)
            }
        }
    }

    private static func validateClusterKey(
        _ clusterKey: RichAnswerHumanReviewFailureClusterKey,
        path: String,
        issues: inout [RichAnswerHumanReviewValidationIssue]
    ) {
        if trimmed(clusterKey.renderer).isEmpty {
            issues.append(error("\(path).renderer", "聚类键 renderer 不能为空"))
        }
        if trimmed(clusterKey.failureFamily).isEmpty {
            issues.append(error("\(path).failureFamily", "聚类键 failureFamily 不能为空"))
        }
        if trimmed(clusterKey.normalizedSignature).isEmpty {
            issues.append(error("\(path).normalizedSignature", "聚类键 normalizedSignature 不能为空"))
        }
    }

    private static func validateRetestChain(
        _ links: [RichAnswerHumanReviewRetestLink],
        path: String,
        policy: RichAnswerHumanReviewValidationPolicy,
        issues: inout [RichAnswerHumanReviewValidationIssue]
    ) {
        for (index, link) in links.enumerated() {
            let linkPath = "\(path)[\(index)]"
            if trimmed(link.architectureFixID).isEmpty {
                issues.append(error("\(linkPath).architectureFixID", "架构修复 ID 不能为空"))
            }
            if trimmed(link.fixSummary).isEmpty {
                issues.append(error("\(linkPath).fixSummary", "架构修复摘要不能为空"))
            }
            if trimmed(link.previousRunID).isEmpty {
                issues.append(error("\(linkPath).previousRunID", "复测链必须引用前一轮 runID"))
            }
            if trimmed(link.previousCaseID).isEmpty {
                issues.append(error("\(linkPath).previousCaseID", "复测链必须引用前一题 caseID"))
            }
            if !policy.requiredRepetitions.contains(link.previousRepetition) {
                issues.append(error("\(linkPath).previousRepetition", "复测链 previousRepetition 不在四轮范围内"))
            }
            if trimmed(link.previousEvidencePath).isEmpty {
                issues.append(error("\(linkPath).previousEvidencePath", "复测链必须引用修复前证据"))
            }
            if trimmed(link.retestEvidencePath).isEmpty {
                issues.append(error("\(linkPath).retestEvidencePath", "复测链必须引用修复后复测证据"))
            }
            if link.result == .notReviewed {
                issues.append(error("\(linkPath).result", "架构修复复测结果不能停在 notReviewed"))
            }
        }
    }

    private static func overallStatus(
        from userAcceptance: RichAnswerHumanReviewUserAcceptance?
    ) -> RichAnswerHumanReviewOverallStatus {
        guard let userAcceptance else { return .pendingUserAcceptance }
        switch userAcceptance.status {
        case .accepted:
            return .accepted
        case .rejected:
            return .rejected
        case .pendingUserAcceptance:
            return .pendingUserAcceptance
        }
    }

    private static func technicalVerdict(
        statusCounts: RichAnswerHumanReviewStatusCounts,
        expectedAttemptCount: Int,
        observedAttemptCount: Int,
        screenshotHashReferenceCount: Int,
        minimumScreenshotHashReferenceCount: Int
    ) -> RichAnswerHumanReviewVerdict {
        if statusCounts.fail > 0 {
            return .fail
        }
        if statusCounts.warn > 0 {
            return .warn
        }
        if statusCounts.notReviewed > 0
            || observedAttemptCount < expectedAttemptCount
            || screenshotHashReferenceCount < minimumScreenshotHashReferenceCount {
            return .notReviewed
        }
        return .pass
    }

    private static func verdict(
        from counts: RichAnswerHumanReviewStatusCounts
    ) -> RichAnswerHumanReviewVerdict {
        if counts.fail > 0 { return .fail }
        if counts.warn > 0 { return .warn }
        if counts.notReviewed > 0 { return .notReviewed }
        return .pass
    }

    private static func screenshotKindsAreComplete(
        _ screenshots: [RichAnswerHumanReviewScreenshotReference],
        caseKind: String
    ) -> Bool {
        expectedScreenshotKinds(caseKind: caseKind).isSubset(of: Set(screenshots.map(\.kind)))
            && screenshots.allSatisfy { isSHA256($0.sha256) && !trimmed($0.path).isEmpty }
    }

    private static func expectedScreenshotKinds(
        caseKind: String
    ) -> Set<RichAnswerHumanReviewScreenshotKind> {
        switch caseKind {
        case "rich":
            return [.before, .after]
        case "text-only", "degradation", "invalid-protocol":
            return [.single]
        default:
            return [.single]
        }
    }

    private static func attemptKey(caseID: String, repetition: Int) -> String {
        "rep=\(repetition) case=\(caseID)"
    }

    private static func isSHA256(_ value: String) -> Bool {
        let trimmedValue = trimmed(value)
        guard trimmedValue.count == 64 else { return false }
        return trimmedValue.unicodeScalars.allSatisfy { scalar in
            ("0"..."9").contains(String(scalar)) || ("a"..."f").contains(String(scalar))
        }
    }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func error(_ path: String, _ message: String) -> RichAnswerHumanReviewValidationIssue {
        RichAnswerHumanReviewValidationIssue(severity: .error, path: path, message: message)
    }

    private static func warning(_ path: String, _ message: String) -> RichAnswerHumanReviewValidationIssue {
        RichAnswerHumanReviewValidationIssue(severity: .warning, path: path, message: message)
    }
}

struct RichAnswerHumanReviewSelfCheckResult: Codable, Equatable, Sendable {
    var validPendingReport: RichAnswerHumanReviewValidationReport
    var autoAcceptanceGuardReport: RichAnswerHumanReviewValidationReport
}

enum RichAnswerHumanReviewSelfCheckError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case let .failed(message):
            return message
        }
    }
}

enum RichAnswerHumanReviewSelfCheck {
    static func run() throws -> RichAnswerHumanReviewSelfCheckResult {
        let expectedCaseIDs = (1...56).map { String(format: "review-fixture-%02d", $0) }
        var policy = RichAnswerHumanReviewValidationPolicy.standard56x4
        policy.expectedCaseIDs = expectedCaseIDs
        let cases = expectedCaseIDs.enumerated().map { index, caseID in
            fixtureCase(index: index + 1, caseID: caseID, policy: policy)
        }
        let validDocument = RichAnswerHumanReviewDocument(
            runID: "human-review-self-check",
            generatedAt: "2026-07-18T00:00:00Z",
            cases: cases,
            policy: policy
        )
        let validReport = RichAnswerHumanReviewValidator.validate(
            document: validDocument,
            policy: policy
        )
        guard validReport.isValid,
              validReport.computedSummary.technicalGateVerdict == .pass,
              validReport.computedSummary.overallStatus == .pendingUserAcceptance else {
            throw RichAnswerHumanReviewSelfCheckError.failed(
                "完整 56×4 fixture 应技术通过且保持 pendingUserAcceptance"
            )
        }

        var forbiddenSummary = validDocument.summary
        forbiddenSummary.overallStatus = .accepted
        let forbiddenDocument = RichAnswerHumanReviewDocument(
            schemaVersion: 1,
            runID: validDocument.runID,
            generatedAt: validDocument.generatedAt,
            cases: validDocument.cases,
            userAcceptance: nil,
            summary: forbiddenSummary
        )
        let guardReport = RichAnswerHumanReviewValidator.validate(
            document: forbiddenDocument,
            policy: policy
        )
        guard !guardReport.isValid,
              guardReport.issues.contains(where: {
                  $0.path == "summary.overallStatus"
                      && $0.message.contains("pendingUserAcceptance")
              }) else {
            throw RichAnswerHumanReviewSelfCheckError.failed(
                "缺少用户确认时 accepted 必须被确定性校验拦截"
            )
        }

        return RichAnswerHumanReviewSelfCheckResult(
            validPendingReport: validReport,
            autoAcceptanceGuardReport: guardReport
        )
    }

    static func assertPasses() throws {
        _ = try run()
    }

    private static func fixtureCase(
        index: Int,
        caseID: String,
        policy: RichAnswerHumanReviewValidationPolicy
    ) -> RichAnswerHumanReviewCaseRecord {
        let caseKind: String
        if index <= 40 {
            caseKind = "rich"
        } else if index <= 46 {
            caseKind = "text-only"
        } else if index <= 55 {
            caseKind = "degradation"
        } else {
            caseKind = "invalid-protocol"
        }
        return RichAnswerHumanReviewCaseRecord(
            caseID: caseID,
            caseKind: caseKind,
            subject: "fixture",
            question: "fixture question \(index)",
            rounds: policy.requiredRepetitions.map { repetition in
                fixtureRound(caseID: caseID, caseKind: caseKind, repetition: repetition, policy: policy)
            }
        )
    }

    private static func fixtureRound(
        caseID: String,
        caseKind: String,
        repetition: Int,
        policy: RichAnswerHumanReviewValidationPolicy
    ) -> RichAnswerHumanReviewRoundRecord {
        RichAnswerHumanReviewRoundRecord(
            repetition: repetition,
            reviewer: "self-check",
            reviewedAt: "2026-07-18T00:00:00Z",
            evidenceRecordPath: "records/rep-\(repetition)/\(caseID)/record.json",
            rendererUsed: caseKind == "rich" ? "openui-dom" : nil,
            screenshotReferences: fixtureScreenshots(caseID: caseID, caseKind: caseKind, repetition: repetition),
            findings: policy.requiredDimensions.map { dimension in
                RichAnswerHumanReviewFinding(
                    dimension: dimension,
                    status: .pass,
                    evidencePaths: ["records/rep-\(repetition)/\(caseID)/review.md"],
                    reason: "\(dimension.label) 已由人工 fixture 覆盖",
                    failureClusterKey: nil
                )
            },
            architectureRetestChain: []
        )
    }

    private static func fixtureScreenshots(
        caseID: String,
        caseKind: String,
        repetition: Int
    ) -> [RichAnswerHumanReviewScreenshotReference] {
        let kinds: [RichAnswerHumanReviewScreenshotKind] = caseKind == "rich"
            ? [.before, .after]
            : [.single]
        return kinds.map { kind in
            RichAnswerHumanReviewScreenshotReference(
                kind: kind,
                path: "screenshots/rep-\(repetition)/\(caseID)/\(kind.rawValue).png",
                sha256: String(repeating: "a", count: 64),
                width: 1200,
                height: 900,
                note: "self-check fixture"
            )
        }
    }
}
