import Foundation
import XCTest
@testable import WeiBeiCore

/// Locks the breaking Rich Answer envelope migration to schema version 2.
final class RichAnswerEnvelopeVersionTests: XCTestCase {
    /// Builds a minimal wire envelope with a caller-selected schema-version field.
    private func envelopeData(schemaVersionField: String) -> Data {
        Data(
            """
            {
              \(schemaVersionField)
              "contextRevision": "revision:v2",
              "narrative": "利率是资金使用价格的表达。",
              "expressionPlan": {
                "action": "explain",
                "summary": "解释利率",
                "families": ["textAndAlignment"],
                "preferredSurface": "inline",
                "directManipulation": false
              },
              "fallback": {
                "text": "利率是资金使用价格的表达。",
                "reason": "plain-text fallback"
              }
            }
            """.utf8
        )
    }

    /// Verifies newly constructed envelopes default to the sole supported version.
    func testInitializerDefaultsToVersionTwo() {
        let envelope = RichAnswerEnvelope(
            contextRevision: "revision:v2",
            narrative: "正文",
            expressionPlan: RichAnswerExpressionPlan(
                action: .explain,
                summary: "解释",
                families: [.textAndAlignment],
                preferredSurface: .inline,
                directManipulation: false
            ),
            scenes: [],
            evidenceLedger: [],
            fallback: RichAnswerFallback(text: "正文", reason: "fallback")
        )

        XCTAssertEqual(RichAnswerEnvelope.supportedSchemaVersion, 2)
        XCTAssertEqual(envelope.schemaVersion, 2)
    }

    /// Verifies a valid version-2 envelope decodes successfully.
    func testDecodesVersionTwoEnvelope() throws {
        let envelope = try JSONDecoder().decode(
            RichAnswerEnvelope.self,
            from: envelopeData(schemaVersionField: #""schemaVersion": 2,"#)
        )

        XCTAssertEqual(envelope.schemaVersion, 2)
        XCTAssertEqual(envelope.contextRevision, "revision:v2")
        XCTAssertEqual(envelope.expressionPlan.families, [.textAndAlignment])
    }

    /// Verifies the removed version-1 protocol is rejected at the decoding boundary.
    func testRejectsVersionOneEnvelope() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                RichAnswerEnvelope.self,
                from: envelopeData(schemaVersionField: #""schemaVersion": 1,"#)
            )
        )
    }

    /// Verifies omitting the version no longer silently opts into the removed v1 default.
    func testRejectsMissingSchemaVersion() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                RichAnswerEnvelope.self,
                from: envelopeData(schemaVersionField: "")
            )
        )
    }

    /// Verifies unknown future versions fail until their contract is implemented explicitly.
    func testRejectsUnknownSchemaVersion() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                RichAnswerEnvelope.self,
                from: envelopeData(schemaVersionField: #""schemaVersion": 99,"#)
            )
        )
    }
}
