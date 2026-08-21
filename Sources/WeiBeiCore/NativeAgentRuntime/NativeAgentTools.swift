import CryptoKit
import Foundation

public enum NativeToolPermission: String, Codable, Sendable {
    case read
    case writeConfirm
    case destructive
}

public enum NativeToolScope: Hashable, Sendable {
    case global
    case session(String)
}

public struct NativeJSONSchema: @unchecked Sendable {
    public var object: [String: Any]

    public init(_ object: [String: Any]) {
        self.object = object
    }
}

public struct NativeToolDefinition: Sendable {
    public var name: String
    public var description: String
    public var permission: NativeToolPermission
    public var schema: NativeJSONSchema
    public var execute: @Sendable ([String: Any], NativeToolExecutionContext) async throws -> NativeToolExecutionResult

    public init(
        name: String,
        description: String,
        permission: NativeToolPermission,
        schema: NativeJSONSchema,
        execute: @escaping @Sendable ([String: Any], NativeToolExecutionContext) async throws -> NativeToolExecutionResult
    ) {
        self.name = name
        self.description = description
        self.permission = permission
        self.schema = schema
        self.execute = execute
    }
}

public struct NativeToolExecutionResult: @unchecked Sendable {
    public var text: String
    public var details: [String: Any]
    public var isError: Bool

    public init(text: String, details: [String: Any] = [:], isError: Bool = false) {
        self.text = text
        self.details = details
        self.isError = isError
    }
}

public struct NativeToolExecutionContext: Sendable {
    public var request: StudyAgentRequest
    public var mode: NativeAgentMode
    public var hostToolHandler: StudyAgentHostToolHandler?
    public var persistentAssetIDsByContextID: [String: String]
    public var searchedItemIDs: Set<String>
    public var readSourceRevisions: [String: String]
    public var lastReadMemoryRevision: UInt64?
    public var courseProfileUpdated: Bool

    public init(
        request: StudyAgentRequest,
        mode: NativeAgentMode = .assistant,
        hostToolHandler: StudyAgentHostToolHandler? = nil,
        persistentAssetIDsByContextID: [String: String] = [:],
        searchedItemIDs: Set<String> = [],
        readSourceRevisions: [String: String] = [:],
        lastReadMemoryRevision: UInt64? = nil,
        courseProfileUpdated: Bool = false
    ) {
        self.request = request
        self.mode = mode
        self.hostToolHandler = hostToolHandler
        self.persistentAssetIDsByContextID = persistentAssetIDsByContextID
        self.searchedItemIDs = searchedItemIDs
        self.readSourceRevisions = readSourceRevisions
        self.lastReadMemoryRevision = lastReadMemoryRevision
        self.courseProfileUpdated = courseProfileUpdated
    }
}

public enum NativeAgentMode: String, Sendable {
    case assistant
    case tutor
}

public struct NativeToolCallRequest: Sendable {
    public var name: String
    public var argumentsJSON: String
    public var callID: String
}

public actor NativeToolRegistry {
    private var global: [String: NativeToolDefinition] = [:]
    private var sessionLayers: [String: [String: NativeToolDefinition]] = [:]
    private var sessionHidden: [String: Set<String>] = [:]

    public init() {}

    @discardableResult
    public func register(_ definition: NativeToolDefinition, scope: NativeToolScope = .global) -> NativeRegistration {
        switch scope {
        case .global:
            global[definition.name] = definition
            return NativeRegistration { [weak self] in
                Task { await self?.remove(name: definition.name, scope: .global) }
            }
        case let .session(id):
            var layer = sessionLayers[id] ?? [:]
            layer[definition.name] = definition
            sessionLayers[id] = layer
            return NativeRegistration { [weak self] in
                Task { await self?.remove(name: definition.name, scope: .session(id)) }
            }
        }
    }

    public func hide(_ name: String, scope: NativeToolScope) {
        if case let .session(id) = scope {
            var hidden = sessionHidden[id] ?? []
            hidden.insert(name)
            sessionHidden[id] = hidden
        }
    }

    private func remove(name: String, scope: NativeToolScope) {
        switch scope {
        case .global:
            global.removeValue(forKey: name)
        case let .session(id):
            sessionLayers[id]?[name] = nil
        }
    }

    public func resolved(scope: NativeToolScope) -> [NativeToolDefinition] {
        var merged = global
        if case let .session(id) = scope {
            if let layer = sessionLayers[id] {
                merged.merge(layer, uniquingKeysWith: { _, new in new })
            }
            if let hidden = sessionHidden[id] {
                for name in hidden { merged.removeValue(forKey: name) }
            }
        }
        return merged.values.sorted { $0.name < $1.name }
    }

    public func execute(
        _ request: NativeToolCallRequest,
        context: NativeToolExecutionContext,
        scope: NativeToolScope
    ) async throws -> NativeToolExecutionResult {
        try Task.checkCancellation()
        let tools = resolved(scope: scope)
        guard let tool = tools.first(where: { $0.name == request.name }) else {
            throw NativeLLMFailure(code: "unknown_tool", message: "tool \(request.name) is not registered")
        }
        guard NativeToolCallAssembler.isCompleteJSONObject(request.argumentsJSON) || request.argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NativeLLMFailure(
                code: "incomplete_tool_arguments",
                message: "refusing to execute a tool call with incomplete JSON arguments"
            )
        }
        let arguments = try parseArguments(request.argumentsJSON)
        switch tool.permission {
        case .read:
            break
        case .writeConfirm, .destructive:
            break
        }
        try NativeToolGuard.enforce(name: tool.name, arguments: arguments, context: context)
        let result = try await tool.execute(arguments, context)
        return result
    }

    private func parseArguments(_ raw: String) throws -> [String: Any] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [:] }
        guard let data = trimmed.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NativeLLMFailure(code: "invalid_arguments", message: "tool arguments must be a JSON object")
        }
        return object
    }
}

enum NativeToolGuard {
    static func enforce(
        name: String,
        arguments: [String: Any],
        context: NativeToolExecutionContext
    ) throws {
        if name == "read" {
            let path = (arguments["path"] as? String ?? "")
            let allowed = path == "skill://visualize" || path.contains("/skills/visualize/SKILL.md")
            if !allowed {
                throw NativeLLMFailure(code: "guard_denied", message: "read 只接受魏碑已登记的 skill:// 路径")
            }
        }
        if name == "weibei_web_open" {
            let url = arguments["url"] as? String ?? ""
            guard WeiBeiWebResearchURLPolicy.isExplicitlyProvided(url, in: context.request.question) else {
                throw NativeLLMFailure(code: "guard_denied", message: "网页工具只能读取用户本轮明确提供的地址")
            }
        }
        if ["weibei_learning_memory", "weibei_learning_update", "weibei_course_profile_update", "weibei_relation_proposal"].contains(name) {
            let courseID = context.request.projectScope.courseID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if courseID.isEmpty {
                throw NativeLLMFailure(code: "guard_denied", message: "该工具只在课程 Chat 中使用")
            }
        }
        if name == "weibei_visualize", context.request.interactiveVisualizationsEnabled == false {
            throw NativeLLMFailure(code: "guard_denied", message: "用户已关闭新互动界面")
        }
    }
}

public enum NativeBuiltinTools {
    public static func registerAll(
        into registry: NativeToolRegistry,
        skillRoot: URL?
    ) async {
        await registry.register(readSkill(skillRoot: skillRoot))
        await registry.register(visualize)
        await registry.register(visualAsset)
        await registry.register(courseMap)
        await registry.register(courseSearch)
        await registry.register(courseRead)
        await registry.register(webOpen)
        await registry.register(learningMemory)
        await registry.register(learningUpdate)
        await registry.register(courseProfileUpdate)
        await registry.register(noteProposal)
        await registry.register(relationProposal)
    }

    private static func readSkill(skillRoot: URL?) -> NativeToolDefinition {
        NativeToolDefinition(
            name: "read",
            description: "视觉表达可能明显改善理解、比较或探索时，读取魏碑随 App 打包的 visualize Skill。",
            permission: .read,
            schema: NativeJSONSchema(["type": "object", "properties": ["path": ["type": "string"]], "required": ["path"]]),
            execute: { arguments, _ in
                let path = arguments["path"] as? String ?? ""
                let file: URL
                if let skillRoot {
                    file = skillRoot.appendingPathComponent("visualize/SKILL.md")
                } else if path.hasPrefix("/") {
                    file = URL(fileURLWithPath: path)
                } else {
                    throw NativeLLMFailure(code: "skill_missing", message: "visualize Skill 未打包")
                }
                let content = try String(contentsOf: file, encoding: .utf8)
                let digest = SHA256.hash(data: Data(content.utf8))
                let sha = digest.map { String(format: "%02x", $0) }.joined()
                return NativeToolExecutionResult(
                    text: content,
                    details: [
                        "kind": "weibei_skill_read",
                        "loaded": [
                            "id": "visualize",
                            "name": "Visualize",
                            "relativePath": "skills/visualize/SKILL.md",
                            "sha256": sha,
                            "byteCount": content.utf8.count,
                        ],
                    ]
                )
            }
        )
    }

    private static var visualize: NativeToolDefinition {
        NativeToolDefinition(
            name: "weibei_visualize",
            description: "把一个 Visualize 互动片段立即穿插显示在当前回答中。",
            permission: .read,
            schema: NativeJSONSchema(["type": "object", "required": ["id", "spec"]]),
            execute: { arguments, _ in
                let id = (arguments["id"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard id.range(of: "^[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression) != nil,
                      let spec = arguments["spec"] as? [String: Any],
                      let items = spec["items"] as? [Any],
                      !items.isEmpty else {
                    throw NativeLLMFailure(code: "invalid_visualize", message: "Visualize 界面必须包含稳定 id 和完整组件树")
                }
                let specJSON = try JSONSerialization.data(withJSONObject: spec)
                if specJSON.count > 1_000_000 {
                    throw NativeLLMFailure(code: "invalid_visualize", message: "Visualize 界面必须包含稳定 id 和完整组件树")
                }
                return NativeToolExecutionResult(
                    text: "互动界面 \(id) 已显示。",
                    details: ["kind": "weibei_visualization", "id": id, "spec": spec]
                )
            }
        )
    }

    private static var visualAsset: NativeToolDefinition {
        NativeToolDefinition(
            name: "weibei_visual_asset",
            description: "按当前材料 assetID 读取本轮受控图像像素。",
            permission: .read,
            schema: NativeJSONSchema(["type": "object", "required": ["assetID"]]),
            execute: { arguments, context in
                let assetID = arguments["assetID"] as? String ?? ""
                guard let asset = context.request.visualAssets.first(where: { $0.id == assetID }) else {
                    throw NativeLLMFailure(code: "unknown_asset", message: "该 assetID 不是本轮可观察的当前材料图像")
                }
                let data = try Data(contentsOf: URL(fileURLWithPath: asset.filePath))
                if data.isEmpty || data.count > 6_000_000 {
                    throw NativeLLMFailure(code: "asset_size", message: "当前材料图像必须是 1 到 6000000 字节的普通文件")
                }
                let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                return NativeToolExecutionResult(
                    text: "已读取当前材料图像 \(asset.id)；请只依据可见像素和本轮来源判断。",
                    details: [
                        "kind": "visual_asset_read",
                        "assetID": asset.id,
                        "mediaType": asset.mediaType,
                        "sha256": sha,
                        "byteCount": data.count,
                    ]
                )
            }
        )
    }

    private static var courseMap: NativeToolDefinition {
        hostTool(
            name: "weibei_course_map",
            description: "按需列出全部课程资料。",
            permission: .read,
            makeRequest: { arguments, context in
                let itemID = string(arguments["itemID"])
                let persistent = itemID.flatMap { context.persistentAssetIDsByContextID[$0] ?? $0 }
                return .courseMap(
                    itemID: persistent,
                    offset: int(arguments["offset"], default: 0),
                    limit: int(arguments["limit"], default: 40, range: 1...40)
                )
            }
        )
    }

    private static var courseSearch: NativeToolDefinition {
        hostTool(
            name: "weibei_course_search",
            description: "在课程索引片段中搜索相关材料与笔记。",
            permission: .read,
            makeRequest: { arguments, _ in
                .courseSearch(
                    query: string(arguments["query"]) ?? "",
                    limit: int(arguments["limit"], default: 8, range: 1...8)
                )
            }
        )
    }

    private static var courseRead: NativeToolDefinition {
        hostTool(
            name: "weibei_course_read",
            description: "按临时资料 ID 渐进读取真实正文。",
            permission: .read,
            makeRequest: { arguments, context in
                let itemID = string(arguments["itemID"]) ?? ""
                let persistent = context.persistentAssetIDsByContextID[itemID] ?? itemID
                return .courseRead(
                    itemID: persistent,
                    query: string(arguments["query"]) ?? "",
                    location: string(arguments["location"]),
                    cursor: string(arguments["cursor"]),
                    maximumCharacters: int(arguments["maximumCharacters"], default: 6_000, range: 1_000...12_000)
                )
            }
        )
    }

    private static var webOpen: NativeToolDefinition {
        hostTool(
            name: "weibei_web_open",
            description: "读取用户本轮明确贴出的 HTTPS 网页。",
            permission: .read,
            makeRequest: { arguments, _ in
                .webOpen(
                    url: string(arguments["url"]) ?? "",
                    maximumCharacters: int(arguments["maximumCharacters"], default: 12_000, range: 1_000...20_000)
                )
            }
        )
    }

    private static var learningMemory: NativeToolDefinition {
        NativeToolDefinition(
            name: "weibei_learning_memory",
            description: "读取用户上次学到的位置与学习状态。记忆不是课程事实证据。",
            permission: .read,
            schema: NativeJSONSchema(["type": "object"]),
            execute: { _, context in
                let learning = context.request.learningContext
                let data = try JSONEncoder().encode(learning)
                let text = String(data: data, encoding: .utf8) ?? "{}"
                return NativeToolExecutionResult(
                    text: text,
                    details: [
                        "kind": "learning_memory",
                        "memoryRevision": learning.memoryRevision,
                    ]
                )
            }
        )
    }

    private static var learningUpdate: NativeToolDefinition {
        NativeToolDefinition(
            name: "weibei_learning_update",
            description: "在课程阶段节点提出学习状态更新建议，不自动落库。",
            permission: .writeConfirm,
            schema: NativeJSONSchema(["type": "object", "required": ["contextRevision", "memoryRevision"]]),
            execute: { arguments, context in
                let revision = arguments["contextRevision"] as? String ?? ""
                guard revision == context.request.contextRevision else {
                    throw NativeLLMFailure(code: "revision_mismatch", message: "学习状态建议的上下文或记忆修订号不匹配")
                }
                return NativeToolExecutionResult(
                    text: "学习状态更新已校验并交给魏碑；魏碑只会保存当前作用域中的实际变化。",
                    details: ["kind": "learning_update", "entries": arguments["entries"] ?? []]
                )
            }
        )
    }

    private static var courseProfileUpdate: NativeToolDefinition {
        NativeToolDefinition(
            name: "weibei_course_profile_update",
            description: "把本轮真实读到的课程认识批量写入课程知识档案建议。",
            permission: .writeConfirm,
            schema: NativeJSONSchema(["type": "object", "required": ["contextRevision", "profileRevision", "checkpoint"]]),
            execute: { arguments, context in
                if context.courseProfileUpdated {
                    throw NativeLLMFailure(code: "already_updated", message: "本轮已经整理过课程知识档案")
                }
                guard arguments["contextRevision"] as? String == context.request.contextRevision else {
                    throw NativeLLMFailure(code: "revision_mismatch", message: "课程知识档案版本已变化，请按当前课程地图重新整理")
                }
                return NativeToolExecutionResult(
                    text: "本轮阶段性课程认识已提交保存。",
                    details: ["kind": "course_profile_update"]
                )
            }
        )
    }

    private static var noteProposal: NativeToolDefinition {
        NativeToolDefinition(
            name: "weibei_note_proposal",
            description: "返回一份待用户确认的 Markdown 笔记建议，不会写入笔记。",
            permission: .writeConfirm,
            schema: NativeJSONSchema(["type": "object", "required": ["markdown", "evidence", "contextRevision"]]),
            execute: { arguments, context in
                guard arguments["contextRevision"] as? String == context.request.contextRevision else {
                    throw NativeLLMFailure(code: "revision_mismatch", message: "笔记建议的 contextRevision 不匹配")
                }
                let markdown = arguments["markdown"] as? String ?? ""
                let evidence = arguments["evidence"] as? [String] ?? []
                guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !evidence.isEmpty else {
                    throw NativeLLMFailure(code: "empty_proposal", message: "笔记建议必须包含非空 Markdown 和至少一条证据")
                }
                return NativeToolExecutionResult(
                    text: "笔记建议格式与上下文修订号已校验；这仍是待确认建议，尚未写回任何笔记。",
                    details: [
                        "kind": "note_proposal",
                        "markdown": markdown,
                        "evidence": evidence,
                        "contextRevision": context.request.contextRevision,
                    ]
                )
            }
        )
    }

    private static var relationProposal: NativeToolDefinition {
        NativeToolDefinition(
            name: "weibei_relation_proposal",
            description: "返回一份当前课程内笔记与材料的待确认关联。",
            permission: .writeConfirm,
            schema: NativeJSONSchema(["type": "object", "required": ["noteItemID", "sourceItemID", "contextRevision"]]),
            execute: { arguments, context in
                guard arguments["contextRevision"] as? String == context.request.contextRevision else {
                    throw NativeLLMFailure(code: "revision_mismatch", message: "关系建议的 contextRevision 不匹配")
                }
                return NativeToolExecutionResult(
                    text: "关系建议已校验并交给魏碑；这仍是待确认建议，尚未建立关系。",
                    details: [
                        "kind": "relation_proposal",
                        "noteItemID": arguments["noteItemID"] as? String ?? "",
                        "sourceItemID": arguments["sourceItemID"] as? String ?? "",
                    ]
                )
            }
        )
    }

    private static func hostTool(
        name: String,
        description: String,
        permission: NativeToolPermission,
        makeRequest: @escaping @Sendable ([String: Any], NativeToolExecutionContext) throws -> StudyAgentHostToolRequest
    ) -> NativeToolDefinition {
        NativeToolDefinition(
            name: name,
            description: description,
            permission: permission,
            schema: NativeJSONSchema(["type": "object"]),
            execute: { arguments, context in
                guard let handler = context.hostToolHandler else {
                    throw NativeLLMFailure(code: "no_host", message: "当前 Chat 没有可用的课程查询宿主")
                }
                let request = try makeRequest(arguments, context)
                let result = try await handler(request)
                let data = try JSONEncoder().encode(result)
                let text = String(data: data, encoding: .utf8) ?? "{}"
                return NativeToolExecutionResult(
                    text: text,
                    details: ["kind": name.replacingOccurrences(of: "weibei_", with: "")]
                )
            }
        )
    }

    private static func string(_ raw: Any?) -> String? {
        guard let value = raw as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func int(_ raw: Any?, default defaultValue: Int, range: ClosedRange<Int>? = nil) -> Int {
        let value: Int
        if let number = raw as? Int {
            value = number
        } else if let number = raw as? NSNumber, !(raw is Bool) {
            value = number.intValue
        } else {
            value = defaultValue
        }
        if let range { return min(max(value, range.lowerBound), range.upperBound) }
        return value
    }
}
