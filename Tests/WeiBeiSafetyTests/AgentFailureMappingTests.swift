import XCTest
@testable import WeiBeiCore

final class AgentFailureMappingTests: XCTestCase {
    func testStatusAndQuotaCodeMapAcrossProviderBodies() throws {
        let quotaBody = try body(["error": ["message": "You exceeded your current quota", "type": "insufficient_quota", "code": "insufficient_quota"]])
        let rateBody = try body(["error": ["message": "Rate limit reached", "type": "tokens", "code": "rate_limit_exceeded"]])
        let missingModel = try body(["error": ["message": "The model does not exist", "code": "model_not_found"]])
        let unauthorized = try body(["error": ["message": "Incorrect API key", "code": "invalid_api_key"]])
        let anthropicBilling = try body(["type": "error", "error": ["type": "billing_error", "message": "Your credit balance is too low"]])
        let geminiQuota = try body(["error": ["code": 429, "message": "Quota exceeded for quota metric", "status": "RESOURCE_EXHAUSTED"]])

        XCTAssertEqual(AgentFailureKind.classify(NativeHTTPByteStream.httpFailure(402, body: quotaBody)), .insufficientQuota)
        let quota429 = NativeHTTPByteStream.httpFailure(429, body: quotaBody)
        XCTAssertEqual(quota429.code, "insufficient_quota")
        XCTAssertEqual(AgentFailureKind.classify(quota429), .insufficientQuota)
        XCTAssertFalse(AgentFailureKind.insufficientQuota.isRetryable)

        XCTAssertEqual(NativeHTTPByteStream.httpFailure(429, body: rateBody).code, "rate_limited")
        XCTAssertEqual(AgentFailureKind.classify(NativeHTTPByteStream.httpFailure(429, body: rateBody)), .rateLimited)

        XCTAssertEqual(AgentFailureKind.classify(NativeHTTPByteStream.httpFailure(404, body: missingModel)), .modelUnavailable)
        XCTAssertEqual(
            AgentFailureKind.modelUnavailable.title(language: .chinese),
            "请求被拒 · 检查所选模型"
        )

        XCTAssertEqual(AgentFailureKind.classify(NativeHTTPByteStream.httpFailure(401, body: unauthorized)), .unauthorized)

        XCTAssertEqual(NativeHTTPByteStream.httpFailure(400, body: anthropicBilling).code, "insufficient_quota")
        XCTAssertEqual(NativeHTTPByteStream.httpFailure(429, body: geminiQuota).code, "insufficient_quota")

        let streamQuota = NativeHTTPByteStream.providerFailure(
            code: "insufficient_quota",
            type: "insufficient_quota",
            message: "You exceeded your current quota"
        )
        XCTAssertEqual(streamQuota.asAgentFailureKind, .insufficientQuota)
        let streamRate = NativeHTTPByteStream.providerFailure(type: "rate_limit_error", message: "Rate limited")
        XCTAssertEqual(streamRate.asAgentFailureKind, .rateLimited)

        XCTAssertEqual(
            AgentFailureKind.cancelled.partialFailureNotice(language: .chinese, receivedText: false),
            "已停止"
        )
        XCTAssertFalse(
            AgentFailureKind.offline.partialFailureNotice(language: .chinese, receivedText: false).contains("已保留")
        )
        XCTAssertTrue(
            AgentFailureKind.offline.partialFailureNotice(language: .chinese, receivedText: true).contains("已保留收到的内容")
        )
        XCTAssertEqual(
            AgentCitationMarkup.displayText(from: "说明 [材料：货币金融学] 结束"),
            "说明  结束"
        )
    }

    private func body(_ object: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }
}
