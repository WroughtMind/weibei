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
        XCTAssertEqual(first.piProviderID, sameService.piProviderID)
        XCTAssertNotEqual(first.piProviderID, otherService.piProviderID)
        XCTAssertTrue(first.piProviderID.hasPrefix("weibei-custom-"))
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

    func testCustomModelsUseEndpointBoundProviderID() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WeiBeiEndpointTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = PiAgentRuntime(
            executableURL: root.appendingPathComponent("unused-pi"),
            runtimeDirectory: root.appendingPathComponent("runtime", isDirectory: true),
            persistentPiConfigurationDirectory: root.appendingPathComponent("pi", isDirectory: true)
        )
        let endpoint = try AgentProviderEndpoint(
            provider: .custom,
            baseURL: "https://api.example.com/v1"
        )

        try await runtime.writeCustomModelsJSONIfNeeded(
            providerID: .custom,
            baseURL: "https://api.example.com/v1",
            model: "test-model"
        )

        let modelsURL = root.appendingPathComponent("pi/models.json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: modelsURL))
        let providers = try XCTUnwrap(
            (object as? [String: Any])?["providers"] as? [String: Any]
        )
        XCTAssertEqual(Set(providers.keys), [endpoint.piProviderID])
        XCTAssertNil(providers["weibei-custom"])
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
