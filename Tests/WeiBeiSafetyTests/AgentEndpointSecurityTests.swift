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

    func testAzureKeepsPiProviderIDWhileRequiringItsServiceAddress() throws {
        let endpoint = try AgentProviderEndpoint(
            provider: .azureOpenAI,
            baseURL: "HTTPS://Example.openai.azure.com:443/"
        )

        XCTAssertEqual(endpoint.piProviderID, "azure-openai-responses")
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
