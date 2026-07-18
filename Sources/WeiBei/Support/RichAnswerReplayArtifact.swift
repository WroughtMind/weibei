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
        richAnswer
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

    func replayArtifact(artifactURL: URL) -> RichAnswerReplayArtifact {
        let question = promptAndMaterial?.question
            ?? caseSnapshot?.question
            ?? "留档器没有写入用户问题。"
        let materialTitle = promptAndMaterial?.materialTitle
            ?? caseSnapshot?.materialTitle
            ?? "富回答回放材料"
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
            materialText: promptAndMaterial?.materialText ?? "",
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
}

private struct PromptSnapshot: Decodable {
    var question: String
    var materialTitle: String
    var materialText: String
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

private struct ValidationSnapshot: Decodable {
    var issues: [String]
    var toolTrace: [String]
    var protocolDiagnostics: [String]
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
