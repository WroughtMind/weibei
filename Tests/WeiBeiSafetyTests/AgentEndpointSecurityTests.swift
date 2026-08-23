import Foundation
import XCTest
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
        XCTAssertNil(store.load()[AgentProviderID.custom.credentialProviderID])
    }

    func testWebOpenRequiresAnExplicitPublicHTTPSURL() throws {
        XCTAssertTrue(
            WeiBeiWebResearchURLPolicy.isExplicitlyProvided(
                "https://93.184.216.34/guide",
                in: "请读 https://93.184.216.34/guide 并总结"
            )
        )
        XCTAssertFalse(
            WeiBeiWebResearchURLPolicy.isExplicitlyProvided(
                "https://93.184.216.34/other",
                in: "请读 https://93.184.216.34/guide 并总结"
            )
        )
        XCTAssertFalse(
            WeiBeiWebResearchURLPolicy.isExplicitlyProvided(
                "https://example.com/",
                in: "请读 https://example.com.evil/guide 并总结"
            )
        )
        XCTAssertTrue(
            WeiBeiWebResearchURLPolicy.isExplicitlyProvided(
                "https://example.com/guide",
                in: "请读【https://EXAMPLE.com:443/guide#section】，并总结"
            )
        )
        XCTAssertTrue(
            WeiBeiWebResearchURLPolicy.isExplicitlyProvided(
                "https://example.com/",
                in: "请先实际读取 https://example.com/，用一句中文说明正文用途；再用 Mermaid 画流程图"
            )
        )
        for question in [
            "请读[https://example.com/guide]并总结",
            "请读 `https://example.com/guide` 并总结",
        ] {
            XCTAssertTrue(
                WeiBeiWebResearchURLPolicy.isExplicitlyProvided(
                    "https://example.com/guide",
                    in: question
                )
            )
        }
        for (requested, question) in [
            ("https://example.com/guide?version=2", "请读 https://example.com/guide?version=1"),
            ("https://example.com/guide", "请读 https://user@example.com/guide"),
            ("https://example.com/guide", "请读 https://example.com.evil/guide"),
            ("https://example.com/guide", "请读 https://example.com/guide]different"),
            ("https://example.com/guide", "请读 https://example.com/guide`different"),
            ("https://example.com/guide?token=abc", "请读 https://example.com/guide?token=abc]different"),
            ("https://example.com/guide?token=abc", "请读 https://example.com/guide?token=abc`different"),
        ] {
            XCTAssertFalse(
                WeiBeiWebResearchURLPolicy.isExplicitlyProvided(
                    requested,
                    in: question
                )
            )
        }
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
