import Foundation

enum NativeToolSchemaValidation {
    static func validate(arguments: [String: Any], schema: NativeJSONSchema) throws {
        try validateValue(arguments, schema: schema.object, path: "")
    }

    private static func validateValue(_ value: Any, schema: [String: Any], path: String) throws {
        if let allowed = schema["enum"] as? [Any], !allowed.contains(where: { jsonEqual($0, value) }) {
            let location = path.isEmpty ? "参数" : "参数 \(path)"
            throw NativeLLMFailure(code: "invalid_arguments", message: "\(location) 不在允许的枚举值里")
        }
        let types = schemaTypes(schema["type"])
        if !types.isEmpty {
            let actual = jsonTypeName(of: value)
            let typeOK = types.contains(actual) || (types.contains("number") && actual == "integer")
            if !typeOK {
                let location = path.isEmpty ? "参数" : "参数 \(path)"
                throw NativeLLMFailure(
                    code: "invalid_arguments",
                    message: "\(location) 必须是 \(types.joined(separator: " 或 "))"
                )
            }
        }
        if let object = jsonObject(value) {
            if let required = schema["required"] as? [String] {
                for key in required where object[key] == nil {
                    let location = path.isEmpty ? key : "\(path).\(key)"
                    throw NativeLLMFailure(code: "invalid_arguments", message: "缺少参数 \(location)")
                }
            }
            if let properties = jsonObject(schema["properties"]) {
                for (key, child) in object {
                    guard let property = jsonObject(properties[key]) else { continue }
                    try validateValue(child, schema: property, path: path.isEmpty ? key : "\(path).\(key)")
                }
            }
        }
        if let array = value as? [Any], let items = jsonObject(schema["items"]) {
            for (index, element) in array.enumerated() {
                let childPath = path.isEmpty ? "[\(index)]" : "\(path)[\(index)]"
                try validateValue(element, schema: items, path: childPath)
            }
        }
    }

    private static func schemaTypes(_ raw: Any?) -> [String] {
        if let name = raw as? String { return [name] }
        if let names = raw as? [String] { return names }
        return []
    }

    private static func jsonObject(_ raw: Any?) -> [String: Any]? {
        if let object = raw as? [String: Any] { return object }
        if let object = raw as? [String: String] {
            return object.mapValues { $0 as Any }
        }
        guard let raw, JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
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
