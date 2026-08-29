import Foundation
import XCTest
@testable import WeiBei
import WeiBeiCore

final class AgentEndpointSecurityTests: XCTestCase {
    func testCustomCredentialsAreSharedOnlyByNormalizedEndpoint() throws {
        let first = try AgentProviderEndpoint(
            provider: .custom,
            baseURL: "HTTPS://API.Example.com:443/v1/"
        )
        let sameService = try AgentProviderEndpoint(
            provider: .custom,
            baseURL: "https://api.example.com/v1"
        )
        let otherService = try AgentProviderEndpoint(
            provider: .custom,
            baseURL: "https://api.example.com/other"
        )

        XCTAssertEqual(first.baseURL, "https://api.example.com/v1")
        XCTAssertEqual(first.credentialProviderID, sameService.credentialProviderID)
        XCTAssertNotEqual(first.credentialProviderID, otherService.credentialProviderID)
        XCTAssertTrue(first.credentialProviderID.hasPrefix("weibei-custom-"))
    }

    func testAzureKeepsStableProviderIDWhileRequiringItsServiceAddress() throws {
        let endpoint = try AgentProviderEndpoint(
            provider: .azureOpenAI,
            baseURL: "HTTPS://Example.openai.azure.com:443/"
        )

        XCTAssertEqual(endpoint.credentialProviderID, "azure-openai-responses")
        XCTAssertEqual(endpoint.baseURL, "https://example.openai.azure.com")
        XCTAssertThrowsError(
            try AgentProviderEndpoint(provider: .azureOpenAI, baseURL: "")
        ) { error in
            XCTAssertEqual(error as? AgentProviderEndpointError, .missing)
        }
    }

    func testCloudflareRequiresServiceAddress() {
        XCTAssertThrowsError(
            try AgentProviderEndpoint(provider: .cloudflareAIGateway, baseURL: "")
        ) { error in
            XCTAssertEqual(error as? AgentProviderEndpointError, .missing)
        }
        XCTAssertThrowsError(
            try AgentProviderEndpoint(provider: .cloudflareWorkersAI, baseURL: "")
        ) { error in
            XCTAssertEqual(error as? AgentProviderEndpointError, .missing)
        }
        XCTAssertThrowsError(
            try AgentProviderEndpoint(provider: .googleVertex, baseURL: "")
        ) { error in
            XCTAssertEqual(error as? AgentProviderEndpointError, .missing)
        }
    }

    func testBedrockKeepsDefaultRegionWhenAddressIsEmpty() throws {
        let endpoint = try AgentProviderEndpoint(provider: .amazonBedrock, baseURL: "")
        XCTAssertNil(endpoint.baseURL)
        XCTAssertEqual(
            NativeProviderRouting.resolvedBaseURL(provider: .amazonBedrock, endpoint: endpoint)?.host,
            "bedrock-runtime.us-east-1.amazonaws.com"
        )
        XCTAssertTrue(
            NativeProviderRouting.resolvedBaseURL(provider: .amazonBedrock, endpoint: endpoint)?
                .path.contains("/openai/v1") == true
        )
    }

    func testEndpointTransportAllowsLocalHTTPButRejectsPublicHTTP() throws {
        XCTAssertEqual(
            try AgentProviderEndpoint(
                provider: .custom,
                baseURL: "http://127.0.0.1:11434/v1"
            ).baseURL,
            "http://127.0.0.1:11434/v1"
        )
        XCTAssertEqual(
            try AgentProviderEndpoint(
                provider: .custom,
                baseURL: "http://192.168.1.20:11434/v1"
            ).baseURL,
            "http://192.168.1.20:11434/v1"
        )
        XCTAssertEqual(
            try AgentProviderEndpoint(
                provider: .custom,
                baseURL: "http://100.64.0.1:11434/v1"
            ).baseURL,
            "http://100.64.0.1:11434/v1"
        )
        XCTAssertThrowsError(
            try AgentProviderEndpoint(
                provider: .custom,
                baseURL: "http://api.example.com/v1"
            )
        ) { error in
            XCTAssertEqual(error as? AgentProviderEndpointError, .insecurePublicHTTP)
        }
    }

    func testCredentialStoreKeepsEndpointBinding() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WeiBeiEndpointTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let endpoint = try AgentProviderEndpoint(
            provider: .custom,
            baseURL: "https://api.example.com/v1"
        )
        let store = NativeAgentCredentialStore(fileURL: root.appendingPathComponent("credentials.json"))

        try store.upsert(NativeAgentCredentialRecord(
            provider: endpoint.credentialProviderID,
            apiKey: "secret",
            boundEndpoint: endpoint.baseURL
        ))

        let record = try XCTUnwrap(store.load()[endpoint.credentialProviderID])
        XCTAssertEqual(record.boundEndpoint, endpoint.baseURL)
        XCTAssertNil(try store.load()[AgentProviderID.custom.credentialProviderID])
    }

    @MainActor
    func testAgentOwnedRootsRejectSymlinksOutsideWorkspace() throws {
        enum OwnedRoot: String {
            case chats = "AgentRuntime/Chats"
            case ledgers = "NativeAgent/Ledgers"
            case documents = "NativeAgent/Documents"
        }

        let fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("WeiBeiAgentRoot-\(UUID().uuidString)", isDirectory: true)
        let workspace = fixture.appendingPathComponent("workspace", isDirectory: true)
        let outside = fixture.appendingPathComponent("outside", isDirectory: true)
        let sentinel = outside.appendingPathComponent("sentinel.txt")
        defer { try? FileManager.default.removeItem(at: fixture) }

        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("保留".utf8).write(to: sentinel)

        for ownedRoot in [OwnedRoot.chats, .ledgers, .documents] {
            let linkedRoot = workspace.appendingPathComponent(ownedRoot.rawValue, isDirectory: true)
            try FileManager.default.createDirectory(
                at: linkedRoot.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.createSymbolicLink(at: linkedRoot, withDestinationURL: outside)

            switch ownedRoot {
            case .chats:
                let store = WorkspaceStore(
                    workspaceDirectory: workspace,
                    startsAtBlankEntries: true,
                    startsCourseFileMaintenance: false
                )
                XCTAssertNotNil(store.createStudySession(courseID: nil))
                let rejection = store.askAgent(questionOverride: "解释这段材料")
                store.cancelAgentRequest()
                XCTAssertNotNil(rejection, "聊天目录指向资料库外时必须拒绝发送")
            case .ledgers:
                let ledgerURL = linkedRoot
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                    .appendingPathComponent("ledger.jsonl")
                XCTAssertThrowsError(try NativeAgentLedger(fileURL: ledgerURL))
            case .documents:
                XCTAssertThrowsError(
                    try NativeDocumentSandbox.write(
                        title: "说明",
                        format: .markdown,
                        content: "正文",
                        documentsRoot: linkedRoot
                    )
                )
            }
        }

        XCTAssertEqual(try Data(contentsOf: sentinel), Data("保留".utf8))
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: outside.path).sorted(),
            [sentinel.lastPathComponent],
            "Agent 本地目录异常时不得改动资料库外内容"
        )
    }

    func testEquivalentCurrentRunSourceURLsMatch() {
        XCTAssertTrue(WeiBeiWebResearchURLPolicy.isAvailableInCurrentRun(
            "https://example.com/guide",
            in: "",
            currentRunSourceURLs: ["HTTPS://EXAMPLE.COM:443/guide/#section"]
        ))
        XCTAssertFalse(WeiBeiWebResearchURLPolicy.isAvailableInCurrentRun(
            "https://example.com/guide//",
            in: "",
            currentRunSourceURLs: ["https://example.com/guide"]
        ))
    }

    func testPrivateQueryAddedToCurrentRunSourceIsRejected() {
        XCTAssertFalse(WeiBeiWebResearchURLPolicy.isAvailableInCurrentRun(
            "https://example.com/guide?topic=public&note=private-course-text",
            in: "",
            currentRunSourceURLs: ["https://example.com/guide?topic=public"]
        ))
    }

    func testWebOpenRequiresPublicHTTPSURL() throws {
        XCTAssertEqual(
            try WeiBeiWebResearchURLPolicy.validatedPublicHTTPSURL(
                "https://93.184.216.34/guide#section"
            ).absoluteString,
            "https://93.184.216.34/guide"
        )
        XCTAssertThrowsError(
            try WeiBeiWebResearchURLPolicy.validatedPublicHTTPSURL(
                "http://93.184.216.34/guide"
            )
        ) { error in
            XCTAssertEqual(error as? WeiBeiWebResearchError, .insecureURL)
        }
        XCTAssertThrowsError(
            try WeiBeiWebResearchURLPolicy.validatedPublicHTTPSURL(
                "https://127.0.0.1/admin"
            )
        ) { error in
            XCTAssertEqual(error as? WeiBeiWebResearchError, .privateAddress)
        }
    }
}
