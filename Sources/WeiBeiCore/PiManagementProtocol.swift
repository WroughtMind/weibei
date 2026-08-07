import Foundation

public enum PiCredentialType: String, Codable, Sendable {
    case apiKey = "api_key"
    case oauth
}

public struct PiManagementCredentialInfo: Decodable, Equatable, Sendable {
    public var providerId: String
    public var type: PiCredentialType
}

public struct PiManagementProvider: Decodable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var authTypes: [PiCredentialType]
    public var configured: Bool
    public var authSource: String?
}

public struct PiManagementModel: Decodable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var providerId: String
    public var api: String
    public var reasoning: Bool
    public var input: [String]
    public var contextWindow: Int
    public var maxTokens: Int
}

public struct PiManagementCatalog: Decodable, Equatable, Sendable {
    public var providers: [PiManagementProvider]
    public var models: [PiManagementModel]
    public var credentials: [PiManagementCredentialInfo]
}

public enum PiManagementPromptType: String, Decodable, Sendable {
    case text
    case secret
    case select
    case manualCode = "manual_code"
}

public struct PiManagementPromptOption: Decodable, Equatable, Sendable {
    public var id: String
    public var label: String
    public var description: String?
}

public struct PiManagementPrompt: Decodable, Equatable, Sendable {
    public var type: PiManagementPromptType
    public var message: String
    public var placeholder: String?
    public var options: [PiManagementPromptOption]?
}

public enum PiManagementNoticeType: String, Decodable, Sendable {
    case info
    case authURL = "auth_url"
    case deviceCode = "device_code"
    case progress
}

public struct PiManagementNoticeLink: Decodable, Equatable, Sendable {
    public var url: String
    public var label: String?
}

public struct PiManagementNotice: Decodable, Equatable, Sendable {
    public var type: PiManagementNoticeType
    public var message: String?
    public var links: [PiManagementNoticeLink]?
    public var url: String?
    public var instructions: String?
    public var userCode: String?
    public var verificationUri: String?
    public var intervalSeconds: Double?
    public var expiresInSeconds: Double?
}

public struct PiManagementInteraction: Sendable {
    public var prompt: @Sendable (PiManagementPrompt) async throws -> String
    public var notify: @Sendable (PiManagementNotice) async -> Void

    public init(
        prompt: @escaping @Sendable (PiManagementPrompt) async throws -> String,
        notify: @escaping @Sendable (PiManagementNotice) async -> Void
    ) {
        self.prompt = prompt
        self.notify = notify
    }

    public static let nonInteractive = PiManagementInteraction(
        prompt: { _ in
            throw PiAgentRuntimeError.protocolFailure("PI unexpectedly requested management input")
        },
        notify: { _ in }
    )
}

enum PiManagementAction: String, Codable, Sendable {
    case catalog
    case login
    case logout
}

struct PiManagementRequest: Encodable, Sendable {
    var action: PiManagementAction
    var refresh: Bool? = nil
    var providerId: String? = nil
    var authType: PiCredentialType? = nil
}

struct PiManagementEnvelope: Decodable, Sendable {
    var schemaVersion: Int
    var channel: String
    var kind: String
    var action: PiManagementAction?
    var event: PiManagementNotice?
    var catalog: PiManagementCatalog?
    var credential: PiManagementCredentialInfo?
    var providerId: String?
    var message: String?
}

private struct PiManagementPromptEnvelope: Decodable {
    var schemaVersion: Int
    var channel: String
    var kind: String
    var prompt: PiManagementPrompt
}

enum PiManagementCodec {
    static let channel = "weibei.pi.management"
    private static let schemaVersion = 1

    static func command(for request: PiManagementRequest) throws -> String {
        if let providerId = request.providerId,
           !isValidProviderID(providerId) {
            throw PiAgentRuntimeError.protocolFailure("invalid PI provider id")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(request)
        guard data.count <= 4_096,
              let json = String(data: data, encoding: .utf8) else {
            throw PiAgentRuntimeError.protocolFailure("invalid PI management request")
        }
        return "/weibei-management \(json)"
    }

    static func prompt(from title: String) throws -> PiManagementPrompt {
        guard title.utf8.count <= 65_536,
              let data = title.data(using: .utf8) else {
            throw PiAgentRuntimeError.protocolFailure("invalid PI management prompt")
        }
        let envelope = try JSONDecoder().decode(PiManagementPromptEnvelope.self, from: data)
        let optionsAreValid = envelope.prompt.options?.allSatisfy { option in
            !option.id.isEmpty
                && option.id.utf8.count <= 4_096
                && !option.label.isEmpty
                && option.label.utf8.count <= 16_384
                && (option.description?.utf8.count ?? 0) <= 16_384
        } ?? true
        guard envelope.schemaVersion == schemaVersion,
              envelope.channel == channel,
              envelope.kind == "prompt",
              !envelope.prompt.message.isEmpty,
              envelope.prompt.message.utf8.count <= 16_384,
              (envelope.prompt.placeholder?.utf8.count ?? 0) <= 16_384,
              (envelope.prompt.options?.count ?? 0) <= 100,
              optionsAreValid else {
            throw PiAgentRuntimeError.protocolFailure("invalid PI management prompt")
        }
        return envelope.prompt
    }

    static func envelope(from message: String) throws -> PiManagementEnvelope? {
        guard message.contains(channel) else { return nil }
        guard message.utf8.count <= 8 * 1_024 * 1_024,
              let data = message.data(using: .utf8) else {
            throw PiAgentRuntimeError.protocolFailure("invalid PI management result")
        }
        let envelope = try JSONDecoder().decode(PiManagementEnvelope.self, from: data)
        guard envelope.schemaVersion == schemaVersion,
              envelope.channel == channel,
              ["event", "result", "error"].contains(envelope.kind) else {
            throw PiAgentRuntimeError.protocolFailure("invalid PI management result")
        }
        return envelope
    }

    private static func isValidProviderID(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 128 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._"))
        return value.unicodeScalars.allSatisfy(allowed.contains)
    }
}
