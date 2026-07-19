import CryptoKit
import Foundation
import WeiBeiCore

struct RichAnswerReplayArtifact {
    var artifactURL: URL
    var caseID: String
    var caseKind: String?
    var status: String
    var failureReason: String?
    var elapsedSeconds: TimeInterval?
    var question: String
    var materialTitle: String
    var materialKind: String
    var materialItemID: String
    var verificationAssetID: String?
    var sourceFingerprint: String?
    var verificationAssetFingerprint: String?
    var materialText: String
    var assistantText: String
    var backend: StudyAgentBackend?
    var richAnswer: RichAnswerPresentation?
    var toolTrace: [String]
    var validationIssues: [String]
    var protocolDiagnostics: [String]

    static func load(from rawURL: URL) throws -> RichAnswerReplayArtifact {
        let url = try resolvedArtifactURL(from: rawURL)
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        if let record = try? decoder.decode(EvidenceRecord.self, from: data) {
            return record.replayArtifact(artifactURL: url)
        }
        if let reply = try? decoder.decode(ReplySnapshot.self, from: data) {
            return reply.replayArtifact(artifactURL: url)
        }
        throw ReplayError.unsupportedArtifact(url.path)
    }

    var materialBody: String {
        let body = materialText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty {
            return body
        }
        return "留档器没有写入材料正文；本回放只保留了题目、助手回答与协议状态。"
    }

    var visibleAssistantText: String {
        let body = assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? explicitEmptyResultText : body
    }

    var presentationForDisplay: RichAnswerPresentation? {
        richAnswer?.resolvingAssetIDs(using: replayAssetAliases)
    }

    var referencesCurrentMaterialAsset: Bool {
        guard let presentation = presentationForDisplay else { return false }
        return Self.assetIDs(in: presentation).contains(materialItemID)
    }

    private var explicitEmptyResultText: String {
        if status == "passed", caseKind == "invalid-protocol" {
            return "非法富回答协议已被拦截；这里显示真实拦截结果，而不是空白或预制界面。"
        }
        return "回放没有可渲染的助手正文；这里显示真实留档状态，避免空白误判。"
    }

    private static func resolvedArtifactURL(from rawURL: URL) throws -> URL {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: rawURL.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            let recordURL = rawURL.appendingPathComponent("record.json")
            if FileManager.default.fileExists(atPath: recordURL.path) {
                return recordURL
            }
            let replyURL = rawURL.appendingPathComponent("reply.json")
            if FileManager.default.fileExists(atPath: replyURL.path) {
                return replyURL
            }
        }
        return rawURL
    }

    private var replayAssetAliases: [String: String] {
        guard let assetID = Self.nonEmpty(verificationAssetID),
              assetID != materialItemID else {
            return [:]
        }
        return [assetID: materialItemID]
    }

    private static func assetIDs(in presentation: RichAnswerPresentation) -> Set<String> {
        var assetIDs = Set(presentation.evidenceLedger.flatMap(\.assetIDs))
        for scene in presentation.scenes {
            assetIDs.formUnion(scene.objects.compactMap(\.assetID))
            assetIDs.formUnion(scene.frames.compactMap(\.assetID))
            assetIDs.formUnion(scene.ui?.nodes.compactMap(\.assetID) ?? [])
        }
        return assetIDs
    }

    private static func nonEmpty(_ rawValue: String?) -> String? {
        let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }
}

extension RichAnswerReplayArtifact {
    static func url(fromEnvironmentValue value: String, relativeTo baseURL: URL) -> URL {
        let expanded = (value as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded)
        }
        return baseURL.appendingPathComponent(expanded)
    }
}

private struct EvidenceRecord: Decodable {
    var status: String
    var elapsedSeconds: TimeInterval?
    var failureReason: String?
    var caseSnapshot: CaseSnapshot?
    var promptAndMaterial: PromptSnapshot?
    var modelRawReply: ReplySnapshot?
    var toolAndProtocolValidation: ValidationSnapshot?
    var traceability: TraceabilitySnapshot?

    func replayArtifact(artifactURL: URL) -> RichAnswerReplayArtifact {
        let question = promptAndMaterial?.question
            ?? caseSnapshot?.question
            ?? "留档器没有写入用户问题。"
        let materialTitle = promptAndMaterial?.materialTitle
            ?? caseSnapshot?.materialTitle
            ?? "富回答回放材料"
        let materialIdentity = ReplayMaterialIdentity(
            caseSnapshot: caseSnapshot,
            prompt: promptAndMaterial
        )
        let materialText = promptAndMaterial?.materialText ?? caseSnapshot?.materialText ?? ""
        let sourceFingerprint = ReplaySourceFingerprint.resolve(
            explicit: caseSnapshot?.sourceFingerprint,
            traceabilityPromptHash: traceability?.promptHash,
            materialTitle: materialTitle,
            materialKind: materialIdentity.kind,
            materialItemID: materialIdentity.itemID,
            verificationAssetID: materialIdentity.verificationAssetID,
            materialText: materialText
        )
        let validation = toolAndProtocolValidation
        return RichAnswerReplayArtifact(
            artifactURL: artifactURL,
            caseID: caseSnapshot?.id ?? artifactURL.deletingPathExtension().lastPathComponent,
            caseKind: caseSnapshot?.caseKind,
            status: status,
            failureReason: failureReason,
            elapsedSeconds: elapsedSeconds,
            question: question,
            materialTitle: materialTitle,
            materialKind: materialIdentity.kind,
            materialItemID: materialIdentity.itemID,
            verificationAssetID: materialIdentity.verificationAssetID,
            sourceFingerprint: sourceFingerprint,
            verificationAssetFingerprint: caseSnapshot?.verificationAssetFingerprint
                ?? ReplaySourceFingerprint.verificationAssetFingerprint(
                    for: materialIdentity.verificationAssetID
                ),
            materialText: materialText,
            assistantText: modelRawReply?.text ?? "",
            backend: modelRawReply.flatMap(\.backendValue),
            richAnswer: modelRawReply?.richAnswer,
            toolTrace: modelRawReply?.toolTrace ?? validation?.toolTrace ?? [],
            validationIssues: validation?.issues ?? [],
            protocolDiagnostics: validation?.protocolDiagnostics ?? []
        )
    }
}

private struct CaseSnapshot: Decodable {
    var id: String
    var caseKind: String
    var question: String
    var materialTitle: String?
    var materialKind: String?
    var materialItemID: String?
    var verificationAssetID: String?
    var sourceFingerprint: String?
    var verificationAssetFingerprint: String?
    var materialText: String?
}

private struct PromptSnapshot: Decodable {
    var question: String
    var materialTitle: String
    var materialText: String
    var courseContext: StudyAgentCourseContext?
}

private struct ReplySnapshot: Decodable {
    var text: String
    var backend: String
    var toolTrace: [String]
    var richAnswer: RichAnswerPresentation?

    var backendValue: StudyAgentBackend? {
        StudyAgentBackend(rawValue: backend)
    }

    func replayArtifact(artifactURL: URL) -> RichAnswerReplayArtifact {
        RichAnswerReplayArtifact(
            artifactURL: artifactURL,
            caseID: artifactURL.deletingPathExtension().lastPathComponent,
            caseKind: nil,
            status: "reply-only",
            failureReason: nil,
            elapsedSeconds: nil,
            question: "留档器只提供了 reply.json；没有写入用户问题。",
            materialTitle: "富回答回放材料",
            materialKind: "text",
            materialItemID: "rich-answer-replay-material",
            verificationAssetID: nil,
            sourceFingerprint: nil,
            verificationAssetFingerprint: nil,
            materialText: "",
            assistantText: text,
            backend: backendValue,
            richAnswer: richAnswer,
            toolTrace: toolTrace,
            validationIssues: [],
            protocolDiagnostics: richAnswer?.diagnostics.map { "\($0.code.rawValue):\($0.message)" } ?? []
        )
    }
}

private struct ReplayMaterialIdentity {
    var itemID: String
    var kind: String
    var verificationAssetID: String?

    init(caseSnapshot: CaseSnapshot?, prompt: PromptSnapshot?) {
        let currentMaterial = Self.currentMaterial(in: prompt?.courseContext)
        let resolvedVerificationAssetID = Self.nonEmpty(caseSnapshot?.verificationAssetID)
            ?? Self.verificationAssetID(in: prompt?.materialText)
        itemID = Self.nonEmpty(caseSnapshot?.materialItemID)
            ?? currentMaterial?.id
            ?? "rich-answer-replay-material"
        kind = Self.nonEmpty(caseSnapshot?.materialKind)
            ?? (resolvedVerificationAssetID == nil ? currentMaterial?.kind : "image")
            ?? "text"
        verificationAssetID = resolvedVerificationAssetID
    }

    private static func currentMaterial(
        in context: StudyAgentCourseContext?
    ) -> (id: String, kind: String)? {
        if let item = context?.items.first(where: \.isCurrentMaterial),
           let id = nonEmpty(item.id),
           let kind = nonEmpty(item.kind) {
            return (id, kind)
        }
        if let item = context?.catalog.first(where: \.isCurrentMaterial),
           let id = nonEmpty(item.id),
           let kind = nonEmpty(item.kind) {
            return (id, kind)
        }
        return nil
    }

    private static func verificationAssetID(in materialText: String?) -> String? {
        guard let materialText else { return nil }
        let prefixes = ["来源登记 ID：", "来源登记 ID:"]
        for line in materialText.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            for prefix in prefixes where trimmed.hasPrefix(prefix) {
                return nonEmpty(String(trimmed.dropFirst(prefix.count)))
            }
        }
        return nil
    }

    private static func nonEmpty(_ rawValue: String?) -> String? {
        let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }
}

private enum ReplaySourceFingerprint {
    static func resolve(
        explicit: String?,
        traceabilityPromptHash: String?,
        materialTitle: String,
        materialKind: String,
        materialItemID: String,
        verificationAssetID: String?,
        materialText: String
    ) -> String? {
        if let value = nonEmpty(explicit) {
            return value
        }
        if materialKind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "image",
           let value = verificationAssetFingerprint(for: verificationAssetID) {
            return value
        }
        if let value = nonEmpty(traceabilityPromptHash) {
            return value
        }
        return sha256(
            [
                "materialTitle": materialTitle,
                "materialKind": materialKind,
                "materialItemID": materialItemID,
                "verificationAssetID": verificationAssetID ?? "",
                "materialText": materialText,
            ]
        )
    }

    static func verificationAssetFingerprint(for assetID: String?) -> String? {
        guard let assetID = nonEmpty(assetID) else { return nil }
        return RichAnswerVerificationAssets.asset(for: assetID)?.sha256
    }

    private static func sha256(_ fields: [String: String]) -> String? {
        let payload = fields
            .map { "\($0.key)=\($0.value.trimmingCharacters(in: .whitespacesAndNewlines))" }
            .sorted()
            .joined(separator: "\n")
        guard !payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return SHA256.hash(data: Data(payload.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func nonEmpty(_ rawValue: String?) -> String? {
        let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }
}

private struct ValidationSnapshot: Decodable {
    var issues: [String]
    var toolTrace: [String]
    var protocolDiagnostics: [String]
}

private struct TraceabilitySnapshot: Decodable {
    var sourceHash: String?
    var promptHash: String?
}

private enum ReplayError: LocalizedError {
    case unsupportedArtifact(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedArtifact(path):
            return "不支持的富回答回放留档格式：\(path)"
        }
    }
}
