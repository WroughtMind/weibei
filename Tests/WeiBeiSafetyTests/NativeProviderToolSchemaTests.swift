import XCTest
@testable import WeiBeiCore

final class NativeProviderToolSchemaTests: XCTestCase {
    func testResponsesKeepsOptionalArgumentsOptionalAndLocallyValidated() throws {
        let schema = NativeJSONSchema([
            "type": "object",
            "properties": ["id": ["type": "string"], "resource": ["type": "string"]],
            "required": ["id"],
        ])
        let tool = NativeToolDefinition(name: "load_skill", description: "Omit resource to read the entrypoint",
            schema: schema, execute: { _, _ in NativeToolExecutionResult(text: "unused") })
        let request = NativeLLMRequest(model: "test", messages: [], tools: [tool], enableNativeWebSearch: true)
        let provider = OpenAIResponsesProvider(baseURL: URL(string: "https://chatgpt.com/backend-api/codex")!,
            accessToken: "test", chatgptBackend: true)
        let body = try XCTUnwrap(provider.makeURLRequest(request).httpBody)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let tools = try XCTUnwrap(payload["tools"] as? [[String: Any]])
        let function = try XCTUnwrap(tools.first { $0["name"] as? String == "load_skill" })
        // Omission lets Responses normalize every property into a required field.
        XCTAssertEqual(function["strict"] as? Bool, false)
        let sentSchema = try XCTUnwrap(function["parameters"] as? [String: Any])
        XCTAssertTrue(NSDictionary(dictionary: sentSchema).isEqual(to: schema.object))
        XCTAssertNotNil(tools.first { $0["type"] as? String == "web_search" })
        XCTAssertNoThrow(try NativeToolSchemaValidation.validate(arguments: ["id": "web-research"], schema: schema))
        XCTAssertThrowsError(try NativeToolSchemaValidation.validate(arguments: [:], schema: schema))
        XCTAssertThrowsError(try NativeToolSchemaValidation.validate(arguments: ["id": "web-research", "resource": 1], schema: schema))
    }
}
