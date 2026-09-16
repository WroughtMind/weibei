import XCTest
@testable import WeiBeiCore

final class AgentReasoningEffortTests: XCTestCase {
    func testModelSpecificLevelsAndFloatingIsolation() {
        XCTAssertEqual(AgentReasoningEffort.levels(provider: .openai, model: "gpt-5.1"), ["none", "low", "medium", "high"])
        XCTAssertEqual(AgentReasoningEffort.levels(provider: .openai, model: "gpt-5.6-sol").last, "max")
        XCTAssertFalse(AgentReasoningEffort.levels(provider: .openai, model: "gpt-6-astra").contains("none"))
        XCTAssertEqual(AgentReasoningEffort.levels(provider: .openai, model: "gpt-5.4-2026-03-05").last, "xhigh")
        XCTAssertTrue(AgentReasoningEffort.levels(provider: .openai, model: "gpt-5.4-unknown").isEmpty)
        XCTAssertTrue(AgentReasoningEffort.levels(provider: .openai, model: "gpt-4.1").isEmpty)
        XCTAssertTrue(AgentReasoningEffort.levels(provider: .custom, model: "gpt-5.6-sol").isEmpty)
        XCTAssertFalse(AgentReasoningEffort.levels(provider: .anthropic, model: "claude-opus-4-6").contains("xhigh"))
        XCTAssertEqual(AgentReasoningEffort.levels(provider: .anthropic, model: "claude-opus-4-7").suffix(2), ["xhigh", "max"])
        XCTAssertEqual(AgentReasoningEffort.levels(provider: .google, model: "gemini-3.1-pro-preview"), ["low", "medium", "high"])
        XCTAssertEqual(AgentReasoningEffort.levels(provider: .google, model: "gemini-3-flash-preview").first, "minimal")

        let levels = ["low", "medium", "high", "xhigh", "max", "ultra"]
        XCTAssertEqual(AgentReasoningEffort.selected("ultra", levels: levels), "ultra")
        XCTAssertEqual(AgentReasoningEffort.selected("ultra", levels: levels, floating: true), "low")
        XCTAssertEqual(AgentReasoningEffort.selected("ultra", levels: ["low", "high"]), "low")
        XCTAssertNil(AgentReasoningEffort.selected("high", levels: [], floating: true))
        XCTAssertNil(AgentReasoningEffort.selected("max", levels: []))
        XCTAssertNil(AgentReasoningEffort.selected(nil, levels: ["high"], floating: true))
    }

    func testDelegatedRequestInheritsParentEffort() async throws {
        final class Capture: @unchecked Sendable { var effort: String? }
        struct Adapter: NativeLLMAdapter {
            let family = "openai-responses"
            let capture: Capture
            func stream(_ request: NativeLLMRequest) -> AsyncThrowingStream<NativeStreamChunk, Error> {
                if request.purpose == .answer { capture.effort = request.reasoningEffort }
                return AsyncThrowingStream { continuation in
                    continuation.yield(.textDelta(index: 0, text: "完成"))
                    continuation.yield(.finish(reason: .stop, replayState: nil))
                    continuation.finish()
                }
            }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let capture = Capture()
        let result = await NativeSubagentRunner.start(
            .init(task: "说明", capabilities: [], depth: 1), adapter: Adapter(capture: capture), model: "test",
            systemPrompt: "回答", ledgerRoot: root, hostToolHandler: nil, liveStores: .empty, reasoningEffort: "low"
        )
        XCTAssertTrue(result.ok)
        XCTAssertEqual(capture.effort, "low")
    }

    func testCodexCatalogUsesEachModelsAdvertisedLevels() {
        let models = AgentModelListService.codexModels([
            ["slug": "model-a", "supported_in_api": true, "visibility": "list",
             "supported_reasoning_levels": [["effort": "low"], ["effort": "high"]]],
            ["slug": "model-b", "supported_in_api": true, "visibility": "list",
             "supported_reasoning_levels": [["effort": "low"], ["effort": "ultra"], ["effort": "ultra"], ["effort": ""], ["effort": 5]]],
            ["slug": "unknown", "supported_in_api": true, "visibility": "list"]
        ])
        XCTAssertEqual(models.map(\.reasoningLevels), [["low", "high"], ["low", "ultra"], []])
    }

    func testEffortReachesEachProvidersPayloadWithoutDroppingOutputLimit() {
        var request = NativeLLMRequest(model: "test", messages: [], reasoningEffort: "high", maxTokens: 1234)
        XCTAssertEqual((OpenAIResponsesProvider.payload(for: request)["reasoning"] as? [String: String])?["effort"], "high")
        XCTAssertEqual((AnthropicMessagesProvider.payload(for: request)["output_config"] as? [String: String])?["effort"], "high")
        let config = GoogleGenerativeAIProvider.payload(for: request)["generationConfig"] as? [String: Any]
        XCTAssertEqual(config?["maxOutputTokens"] as? Int, 1234)
        XCTAssertEqual((config?["thinkingConfig"] as? [String: String])?["thinkingLevel"], "high")
        request.reasoningEffort = nil
        XCTAssertNil(OpenAIResponsesProvider.payload(for: request)["reasoning"])
        XCTAssertNil(AnthropicMessagesProvider.payload(for: request)["output_config"])
        XCTAssertNil((GoogleGenerativeAIProvider.payload(for: request)["generationConfig"] as? [String: Any])?["thinkingConfig"])
    }
}
