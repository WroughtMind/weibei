import Foundation
import XCTest
@testable import WeiBeiCore

final class PiRuntimeBehaviorTests: XCTestCase {
    /**
     * Verifies provider configuration trims explicit values and preserves safe defaults.
     */
    func testProviderConfigurationNormalization() {
        XCTAssertEqual(PiAgentProviderConfiguration().thinkingLevel, "medium")
        XCTAssertEqual(
            PiAgentProviderConfiguration(
                provider: " openai-codex ",
                model: " gpt-5.5 ",
                apiKey: " secret ",
                baseURL: " https://example.test ",
                thinkingLevel: " xhigh "
            ),
            PiAgentProviderConfiguration(
                provider: "openai-codex",
                model: "gpt-5.5",
                apiKey: "secret",
                baseURL: "https://example.test",
                thinkingLevel: "xhigh"
            )
        )
        XCTAssertEqual(PiAgentProviderConfiguration(thinkingLevel: "  ").thinkingLevel, "medium")
    }

    /**
     * Verifies source-free conversation cannot be used to bypass evidence for mixed course questions.
     */
    func testQuestionScopeAndEvidenceRequirement() {
        XCTAssertTrue(StudyAgentQuestionScope.allowsSourceFreeAnswer("给我讲一个笑话"))
        XCTAssertTrue(StudyAgentQuestionScope.allowsSourceFreeAnswer("连通测试：只回复 Pi订阅登录已连通"))
        XCTAssertFalse(StudyAgentQuestionScope.allowsSourceFreeAnswer("讲一个关于费雪方程的笑话"))
        XCTAssertFalse(StudyAgentQuestionScope.allowsSourceFreeAnswer("你叫什么，顺便解释费雪方程"))
        XCTAssertEqual(
            PiAnswerEvidenceRequirement.validationError(
                contentLabels: [],
                learningLabels: [],
                allowsLearningOnlyAnswer: false,
                allowsSourceFreeAnswer: false
            ),
            "PI returned a content answer without a current-turn source citation"
        )
        XCTAssertNil(
            PiAnswerEvidenceRequirement.validationError(
                contentLabels: [],
                learningLabels: ["[学习记录：上次位置]"],
                allowsLearningOnlyAnswer: true,
                allowsSourceFreeAnswer: false
            )
        )
    }

    /**
     * Verifies JSONL framing survives byte-wise UTF-8 delivery and rejects incomplete records.
     */
    func testJSONLFramingAcrossUTF8Boundaries() throws {
        let delta = "中文跨字节\u{2028}仍在同一条 JSON 记录"
        let first = #"{"type":"message_update","assistantMessageEvent":{"type":"text_delta","delta":"中文跨字节 仍在同一条 JSON 记录"}}"#
        let second = #"{"type":"tool_execution_start","toolCallId":"tool-1","toolName":"weibei_context"}"#
        var framer = PiJSONLFramer()
        var records: [Data] = []

        for byte in Data("\(first)\r\n\(second)\n".utf8) {
            records.append(contentsOf: try framer.append(Data([byte])))
        }

        XCTAssertNoThrow(try framer.finish())
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(try PiRPCMessageDecoder.decode(records[0]), .textDelta(delta))
        XCTAssertEqual(
            try PiRPCMessageDecoder.decode(records[1]),
            .toolStarted(id: "tool-1", name: "weibei_context")
        )

        var incomplete = PiJSONLFramer()
        _ = try incomplete.append(Data(#"{"type":"event"}"#.utf8))
        XCTAssertThrowsError(try incomplete.finish()) { error in
            XCTAssertEqual(error as? PiRPCProtocolError, .incompleteLine)
        }

        var bounded = PiJSONLFramer(maximumLineBytes: 3)
        XCTAssertThrowsError(try bounded.append(Data("four".utf8))) { error in
            XCTAssertEqual(error as? PiRPCProtocolError, .lineTooLarge(4))
        }
    }

    /**
     * Verifies RPC decoding retains correlation, revision, and structured tool-failure evidence.
     */
    func testRPCDecoderPreservesToolEvidence() throws {
        let response = try PiRPCMessageDecoder.decode(
            Data(#"{"id":"state-1","type":"response","command":"get_state","success":true,"data":{"isStreaming":false}}"#.utf8)
        )
        guard case let .response(value) = response else {
            return XCTFail("Expected response envelope")
        }
        XCTAssertEqual(value.id, "state-1")
        XCTAssertEqual(value.command, "get_state")
        XCTAssertTrue(value.success)
        XCTAssertNotNil(value.dataJSON)

        XCTAssertEqual(
            try PiRPCMessageDecoder.decode(
                Data(#"{"type":"tool_execution_end","toolCallId":"tool-context","toolName":"weibei_context","isError":false,"result":{"details":{"kind":"weibei_context","contextRevision":"revision-7"}}}"#.utf8)
            ),
            .contextRead(id: "tool-context", contextRevision: "revision-7")
        )
        XCTAssertEqual(
            try PiRPCMessageDecoder.decode(
                Data(#"{"type":"tool_execution_end","toolCallId":"tool-2","toolName":"weibei_context","isError":true,"result":{"content":[{"type":"text","text":"stale context"}]}}"#.utf8)
            ),
            .toolFailed(id: "tool-2", name: "weibei_context", message: "stale context")
        )
    }

    /**
     * Verifies malformed JSON and envelopes fail closed with distinct protocol errors.
     */
    func testRPCDecoderRejectsMalformedInput() {
        XCTAssertThrowsError(try PiRPCMessageDecoder.decode(Data("not-json".utf8))) { error in
            XCTAssertEqual(error as? PiRPCProtocolError, .invalidJSON)
        }
        XCTAssertThrowsError(try PiRPCMessageDecoder.decode(Data(#"{"event":"missing-type"}"#.utf8))) { error in
            XCTAssertEqual(error as? PiRPCProtocolError, .invalidEnvelope)
        }
    }
}
