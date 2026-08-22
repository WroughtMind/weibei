import Foundation

enum NativeToolSchemaValidation {
    static func validate(arguments: [String: Any], schema: NativeJSONSchema) throws {
        let object = schema.object
        if let required = object["required"] as? [String] {
            for key in required {
                if arguments[key] == nil {
                    throw NativeLLMFailure(code: "invalid_arguments", message: "缺少参数 \(key)")
                }
            }
        }
        guard let properties = object["properties"] as? [String: Any] else { return }
        for (key, value) in arguments {
            guard let property = properties[key] as? [String: Any] else { continue }
            try validateValue(value, schema: property, path: key)
        }
    }

    private static func validateValue(_ value: Any, schema: [String: Any], path: String) throws {
        if let allowed = schema["enum"] as? [Any], !allowed.contains(where: { jsonEqual($0, value) }) {
            throw NativeLLMFailure(code: "invalid_arguments", message: "参数 \(path) 不在允许的枚举值里")
        }
        let types = schemaTypes(schema["type"])
        guard !types.isEmpty else { return }
        if types.contains(jsonTypeName(of: value)) { return }
        if types.contains("number"), jsonTypeName(of: value) == "integer" { return }
        throw NativeLLMFailure(
            code: "invalid_arguments",
            message: "参数 \(path) 必须是 \(types.joined(separator: " 或 "))"
        )
    }

    private static func schemaTypes(_ raw: Any?) -> [String] {
        if let name = raw as? String { return [name] }
        if let names = raw as? [String] { return names }
        return []
    }

    private static func jsonTypeName(of value: Any) -> String {
        if value is NSNull { return "null" }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return "boolean" }
            let dbl = number.doubleValue
            if dbl == dbl.rounded(), dbl >= Double(Int.min), dbl <= Double(Int.max) {
                return "integer"
            }
            return "number"
        }
        if value is Bool { return "boolean" }
        if value is String { return "string" }
        if value is [Any] { return "array" }
        if value is [String: Any] { return "object" }
        if value is Int || value is UInt64 || value is Int64 { return "integer" }
        if value is Double || value is Float { return "number" }
        return "object"
    }

    private static func jsonEqual(_ left: Any, _ right: Any) -> Bool {
        if let a = left as? String, let b = right as? String { return a == b }
        if let a = left as? NSNumber, let b = right as? NSNumber { return a == b }
        if let a = left as? Bool, let b = right as? Bool { return a == b }
        return false
    }
}
