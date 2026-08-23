import Foundation
import WeiBeiCore
import XCTest

/// 富回答旧系统退役(2026-08)的数据兼容专项:
/// 旧存档里 AgentMessage 携带 richAnswer 字段,退役后解码必须忽略该键、
/// 正文原样保留,且重新保存时不再写出 richAnswer。
final class RichAnswerRetirementDataSafetyTests: XCTestCase {
    /// 旧格式消息样例:正文 + 已废弃的 richAnswer 载荷(program/ui 形状)。
    private func legacyMessageJSON() throws -> Data {
        let payload: [String: Any] = [
            "id": "11111111-2222-3333-4444-555555555555",
            "role": "assistant",
            "text": "利率是资金使用价格的表达。",
            "toolTrace": [],
            "createdAt": 538_124_800.0,
            "richAnswer": [
                "kind": "program",
                "program": [
                    "type": "columnTable",
                    "columns": ["期数", "利率"],
                    "rows": [["1", "3.25%"]],
                ],
                "ui": ["emphasis": "strong"],
            ],
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    func testLegacyRichAnswerFieldIsIgnoredOnDecode() throws {
        let message = try JSONDecoder().decode(AgentMessage.self, from: legacyMessageJSON())
        XCTAssertEqual(message.text, "利率是资金使用价格的表达。")
        XCTAssertEqual(message.role, .assistant)
    }

    func testReencodedMessageDropsRichAnswerKey() throws {
        let message = try JSONDecoder().decode(AgentMessage.self, from: legacyMessageJSON())
        let data = try JSONEncoder().encode(message)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["richAnswer"], "退役后的消息不得再写出 richAnswer 键")
        XCTAssertEqual(object["text"] as? String, "利率是资金使用价格的表达。")
    }

    func testMalformedContentBlockKeepsItsPositionAndRawDataWithoutRevivingRichAnswer() throws {
        var payload = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: legacyMessageJSON()) as? [String: Any]
        )
        let contentBlocks: [[String: Any]] = [
            ["text": ["_0": "前文"]],
            ["futureInteractiveBlock": ["value": 42]],
            ["text": ["_0": "后文"]],
        ]
        payload["contentBlocks"] = contentBlocks
        let message = try JSONDecoder().decode(
            AgentMessage.self,
            from: try JSONSerialization.data(withJSONObject: payload)
        )

        XCTAssertEqual(message.contentBlocks.count, 3)
        guard case let .unavailable(type, _) = message.contentBlocks[1] else {
            return XCTFail("坏内容块没有留在原位")
        }
        XCTAssertEqual(type, "futureInteractiveBlock")

        let reencoded = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(message)) as? [String: Any]
        )
        let blocks = try XCTUnwrap(reencoded["contentBlocks"] as? [[String: Any]])
        XCTAssertEqual(blocks as NSArray, contentBlocks as NSArray)
    }
}
