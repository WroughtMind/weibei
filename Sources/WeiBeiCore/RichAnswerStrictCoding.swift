import Foundation

private struct RichAnswerDynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

/**
 * Enforces the closed-field decoding contract shared by Rich Answer wire models.
 */
enum RichAnswerStrictDecoding {
    static func rejectUnknownFields(in decoder: Decoder, allowed: Set<String>) throws {
        let container = try decoder.container(keyedBy: RichAnswerDynamicCodingKey.self)
        if let key = container.allKeys.first(where: { !allowed.contains($0.stringValue) }) {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Unsupported rich-answer field '\(key.stringValue)'"
            )
        }
    }
}

extension CaseIterable where Self: CodingKey {
    static var richAnswerAllowedFieldNames: Set<String> {
        Set(allCases.map(\.stringValue))
    }
}
