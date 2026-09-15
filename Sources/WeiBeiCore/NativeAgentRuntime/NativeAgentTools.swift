import CryptoKit
import Foundation

public enum NativeVisualAssetMagic {
    public static func matches(_ data: Data, mediaType: String) -> Bool {
        let bytes = [UInt8](data.prefix(12))
        switch mediaType {
        case "image/jpeg":
            return bytes.count >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF
        case "image/png":
            return bytes.count >= 8
                && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47
                && bytes[4] == 0x0D && bytes[5] == 0x0A && bytes[6] == 0x1A && bytes[7] == 0x0A
        case "image/webp":
            guard bytes.count >= 12 else { return false }
            let riff = String(bytes: bytes[0..<4], encoding: .ascii)
            let webp = String(bytes: bytes[8..<12], encoding: .ascii)
            return riff == "RIFF" && webp == "WEBP"
        default:
            return false
        }
    }
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
    public var schema: NativeJSONSchema
    public var execute: @Sendable ([String: Any], NativeToolExecutionContext) async throws -> NativeToolExecutionResult

    public init(
        name: String,
        description: String,
        schema: NativeJSONSchema,
        execute: @escaping @Sendable ([String: Any], NativeToolExecutionContext) async throws -> NativeToolExecutionResult
    ) {
        self.name = name
        self.description = description
        self.schema = schema
        self.execute = execute
    }
}

public struct NativeToolExecutionResult: @unchecked Sendable {
    public var text: String
    public var details: [String: Any]
    public var isError: Bool
    public var image: NativeImagePart?

    public init(
        text: String,
        details: [String: Any] = [:],
        isError: Bool = false,
        image: NativeImagePart? = nil
    ) {
        self.text = text
        self.details = details
        self.isError = isError
        self.image = image
    }
}

public struct NativeToolExecutionContext: Sendable {
    public var request: StudyAgentRequest
    public var mode: NativeAgentMode
    public var hostToolHandler: StudyAgentHostToolHandler?
    public var persistentAssetIDsByContextID: [String: String]
    public var currentRunSourceURLs: [String]
    public var lastReadMemoryRevision: UInt64?
    public var userEvidence: [String: String] = [:]
    public var courseProfileUpdated: Bool
    public var loadedSkillIDs: Set<String>
    public var liveStores: NativeLiveStores

    public init(
        request: StudyAgentRequest,
        mode: NativeAgentMode = .assistant,
        hostToolHandler: StudyAgentHostToolHandler? = nil,
        persistentAssetIDsByContextID: [String: String] = [:],
        currentRunSourceURLs: [String] = [],
        lastReadMemoryRevision: UInt64? = nil,
        courseProfileUpdated: Bool = false,
        loadedSkillIDs: Set<String> = [],
        liveStores: NativeLiveStores = .empty
    ) {
        self.request = request
        self.userEvidence = request.userEvidence
        self.mode = mode
        self.hostToolHandler = hostToolHandler
        self.persistentAssetIDsByContextID = persistentAssetIDsByContextID
        self.currentRunSourceURLs = currentRunSourceURLs
        self.lastReadMemoryRevision = lastReadMemoryRevision
        self.courseProfileUpdated = courseProfileUpdated
        self.loadedSkillIDs = loadedSkillIDs
        self.liveStores = liveStores
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

    public init(name: String, argumentsJSON: String, callID: String) {
        self.name = name
        self.argumentsJSON = argumentsJSON
        self.callID = callID
    }
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
        var context = context
        if let refresh = context.liveStores.learning {
            context.request.learningContext = await refresh()
        }
        if let refresh = context.liveStores.profile {
            context.request.courseProfile = await refresh()
        }
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
        try NativeToolSchemaValidation.validate(arguments: arguments, schema: tool.schema)
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
        if name == "weibei_web_open" {
            let url = arguments["url"] as? String ?? ""
            guard WeiBeiWebResearchURLPolicy.isAvailableInCurrentRun(
                url,
                in: context.request.question,
                currentRunSourceURLs: context.currentRunSourceURLs
            ) else {
                throw NativeLLMFailure(code: "guard_denied", message: "该网页地址不在本轮可访问来源中")
            }
        }
    }
}

public enum NativeBuiltinTools {
    public static func registerAll(
        into registry: NativeToolRegistry,
        skillRoot: URL?
    ) async {
        await registry.register(loadSkill)
        await registry.register(createDocument)
        await registry.register(delegate)
        await registry.register(visualize)
        await registry.register(visualAsset)
        await registry.register(courseMap)
        await registry.register(workspaceSearch)
        await registry.register(courseRead)
        await registry.register(discussionSearch)
        await registry.register(discussionRead)
        await registry.register(retryFailedPDFPages)
        await registry.register(webOpen)
        await registry.register(learningMemory)
        await registry.register(learningUpdate)
        await registry.register(courseProfileRead)
        await registry.register(courseProfileUpdate)
        await registry.register(noteProposal)
        await registry.register(relationProposal)
    }

    private static var loadSkill: NativeToolDefinition {
        NativeToolDefinition(
            name: "load_skill",
            description: "按技能 id 加载技能正文并注入当前对话。同一会话每个技能只需加载一次；再次加载同一技能会返回已加载短提示，不再注入全文。加载不改变工具注册，附带工具声明只解析不落注册。",
            schema: NativeJSONSchema([
                "type": "object",
                "properties": ["id": ["type": "string"]],
                "required": ["id"],
            ]),
            execute: { arguments, context in
                let id = arguments["id"] as? String ?? ""
                guard let pack = context.liveStores.skillRegistry.pack(named: id) else {
                    throw NativeLLMFailure(code: "skill_missing", message: "未找到技能 \(id)")
                }
                _ = pack.manifest.tools
                _ = pack.manifest.jscHook
                let loaded: [String: Any] = [
                    "id": pack.manifest.id,
                    "name": pack.manifest.name,
                    "version": pack.manifest.version,
                    "relativePath": pack.relativePath,
                    "sha256": pack.sha256,
                    "byteCount": pack.byteCount,
                ]
                if context.loadedSkillIDs.contains(pack.manifest.id) || context.loadedSkillIDs.contains(id) {
                    return NativeToolExecutionResult(
                        text: "技能 \(pack.manifest.id) 已加载。",
                        details: [
                            "kind": "weibei_skill_read",
                            "alreadyLoaded": true,
                            "loaded": loaded,
                            "declaredTools": pack.manifest.tools,
                            "jscHookPresent": pack.manifest.jscHook != nil,
                        ]
                    )
                }
                return NativeToolExecutionResult(
                    text: pack.body,
                    details: [
                        "kind": "weibei_skill_read",
                        "loaded": loaded,
                        "declaredTools": pack.manifest.tools,
                        "jscHookPresent": pack.manifest.jscHook != nil,
                    ]
                )
            }
        )
    }

    private static var createDocument: NativeToolDefinition {
        NativeToolDefinition(
            name: "create_document",
            description: "把 HTML、Markdown 或 SVG 落盘为工作区文稿，并生成沙箱查看页。Assistant 模式默认不可用。",
            schema: NativeJSONSchema([
                "type": "object",
                "properties": [
                    "title": ["type": "string"],
                    "format": ["type": "string", "enum": ["html", "markdown", "svg"]],
                    "content": ["type": "string"],
                ],
                "required": ["title", "format", "content"],
            ]),
            execute: { arguments, context in
                guard context.mode != .assistant else {
                    throw NativeLLMFailure(code: "guard_denied", message: "create_document 在 Assistant 模式默认关闭")
                }
                guard let root = context.liveStores.documentsRoot else {
                    throw NativeLLMFailure(code: "invalid_document", message: "工作区文稿目录未配置")
                }
                let title = arguments["title"] as? String ?? ""
                let formatRaw = arguments["format"] as? String ?? "markdown"
                guard let format = NativeDocumentFormat(rawValue: formatRaw) else {
                    throw NativeLLMFailure(code: "invalid_document", message: "format 必须是 html、markdown 或 svg")
                }
                let content = arguments["content"] as? String ?? ""
                if let confirm = context.liveStores.confirmDocumentCreation {
                    let approved = await confirm(title, Self.documentCreationSummary(content))
                    guard approved else {
                        return NativeToolExecutionResult(
                            text: "用户没有确认创建文稿「\(title)」，已取消；没有写入任何文件。请询问用户要怎么调整，或换个时机再试。",
                            details: [
                                "kind": "weibei_document",
                                "title": title,
                                "cancelled": true,
                            ]
                        )
                    }
                }
                let created = try NativeDocumentSandbox.write(
                    title: title,
                    format: format,
                    content: content,
                    documentsRoot: root
                )
                return NativeToolExecutionResult(
                    text: "已写入文稿 \(created.title)，查看页 \(created.viewerURL.lastPathComponent)。",
                    details: [
                        "kind": "weibei_document",
                        "title": created.title,
                        "format": created.format.rawValue,
                        "path": created.fileURL.path,
                        "viewer": created.viewerURL.path,
                        "byteCount": created.byteCount,
                        "cancelled": false,
                    ]
                )
            }
        )
    }

    fileprivate static func documentCreationSummary(_ content: String) -> String {
        let flattened = content
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let text = flattened.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "(空白内容)" }
        return String(text.prefix(200))
    }

    private static var delegate: NativeToolDefinition {
        NativeToolDefinition(
            name: "delegate",
            description: "把一项子任务交给子智能体。子智能体有独立账本和工具子集。Assistant 模式默认不可用。",
            schema: NativeJSONSchema([
                "type": "object",
                "properties": [
                    "task": ["type": "string"],
                    "capabilities": ["type": "array", "items": ["type": "string"]],
                ],
                "required": ["task"],
            ]),
            execute: { arguments, context in
                guard context.mode != .assistant else {
                    throw NativeLLMFailure(code: "guard_denied", message: "delegate 在 Assistant 模式默认关闭")
                }
                guard let start = context.liveStores.startSubagent else {
                    throw NativeLLMFailure(code: "delegate_unavailable", message: "子智能体未接线")
                }
                let task = arguments["task"] as? String ?? ""
                let names = arguments["capabilities"] as? [String] ?? ["hostTools"]
                let capabilities = NativeSubagentCapabilities.parse(names)
                let result = await start(
                    NativeSubagentRequest(task: task, capabilities: capabilities, depth: 1)
                )
                return NativeToolExecutionResult(
                    text: result.text,
                    details: [
                        "kind": "weibei_delegate",
                        "ok": result.ok,
                        "partial": result.partial,
                        "toolTrace": result.toolTrace,
                    ],
                    isError: !result.ok
                )
            }
        )
    }

    private static var visualize: NativeToolDefinition {
        NativeToolDefinition(
            name: "weibei_visualize",
            description: "把一个 Visualize 互动片段立即穿插显示在当前回答中。",
            schema: NativeJSONSchema([
                "type": "object",
                "properties": [
                    "id": ["type": "string"],
                    "spec": ["type": "object"],
                ],
                "required": ["id", "spec"],
            ]),
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
                    text: "互动界面 \(id) 已接收，等待显示结果。",
                    details: ["kind": "weibei_visualization", "id": id, "spec": spec]
                )
            }
        )
    }

    private static var visualAsset: NativeToolDefinition {
        NativeToolDefinition(
            name: "weibei_visual_asset",
            description: "按当前材料 assetID 读取本轮受控图像像素。",
            schema: NativeJSONSchema([
                "type": "object",
                "properties": ["assetID": ["type": "string"]],
                "required": ["assetID"],
            ]),
            execute: { arguments, context in
                let assetID = arguments["assetID"] as? String ?? ""
                guard let asset = context.request.visualAssets.first(where: { $0.id == assetID }) else {
                    throw NativeLLMFailure(code: "unknown_asset", message: "该 assetID 不是本轮可观察的当前材料图像")
                }
                let data = try Data(contentsOf: URL(fileURLWithPath: asset.filePath))
                if data.isEmpty || data.count > 6_000_000 {
                    throw NativeLLMFailure(code: "asset_size", message: "当前材料图像必须是 1 到 6000000 字节的普通文件")
                }
                guard NativeVisualAssetMagic.matches(data, mediaType: asset.mediaType) else {
                    throw NativeLLMFailure(code: "asset_format", message: "当前材料图像的真实格式与声明不一致")
                }
                let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                return NativeToolExecutionResult(
                    text: "已读取当前材料图像 \(asset.id)；请只依据可见像素和本轮来源判断，不能把近似观察说成精确测量。",
                    details: [
                        "kind": "visual_asset_read",
                        "assetID": asset.id,
                        "mediaType": asset.mediaType,
                        "sha256": sha,
                        "byteCount": data.count,
                    ],
                    image: NativeImagePart(mediaType: asset.mediaType, data: data)
                )
            }
        )
    }

    private static let sourceScopeProperties: [String: Any] = [
        "scope": ["type": "string", "enum": ["material", "course", "library"]],
        "scopeID": ["type": "string"],
        "cursor": ["type": "string"],
        "limit": ["type": "integer", "minimum": 1, "maximum": 100],
    ]

    private static func sourceScope(_ arguments: [String: Any], _ context: NativeToolExecutionContext) throws -> (StudyAgentSourceScope, String?) {
        guard let raw = string(arguments["scope"]), let scope = StudyAgentSourceScope(rawValue: raw) else {
            throw NativeLLMFailure(code: "invalid_arguments", message: "选择材料、课程或整个资料库的查询范围")
        }
        let current = scope == .material
            ? (context.request.selectionSources.first?.itemID ?? context.request.focus?.materialItemID ?? context.request.courseContext.items.first(where: \.isCurrentNote)?.id)
            : context.request.projectScope.courseID
        let id = string(arguments["scopeID"]) ?? current
        guard scope == .library || id != nil else {
            throw NativeLLMFailure(code: "invalid_arguments", message: "当前没有这个范围的资料，请提供范围编号")
        }
        return (scope, scope == .library ? nil : id)
    }

    private static func positiveCount(_ raw: Any?, default fallback: Int, maximum: Int) throws -> Int {
        guard let raw else { return fallback }
        guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue > 0, number.doubleValue.rounded() == number.doubleValue,
              let value = Int(exactly: number.doubleValue) else {
            throw NativeLLMFailure(code: "invalid_arguments", message: "数量需要是正整数")
        }
        return min(value, maximum)
    }

    private static var courseMap: NativeToolDefinition {
        var properties = sourceScopeProperties
        properties["name"] = ["type": "string"]
        return hostTool(
            name: "weibei_course_map",
            description: "列出材料与编号；scope=material 时列出该材料的页/章节位置。scopeID 省略时使用当前材料或课程。name 仅筛选材料名称。nextCursor 表示还有目录，可按需要续页。目录没有正文引用标签。",
            schema: NativeJSONSchema(["type": "object", "properties": properties, "required": ["scope"]]),
            makeRequest: { arguments, context in
                let (scope, id) = try sourceScope(arguments, context)
                return .courseMap(scope: scope, scopeID: id, name: string(arguments["name"]),
                    cursor: string(arguments["cursor"]), limit: try positiveCount(arguments["limit"], default: 40, maximum: 100))
            }
        )
    }

    private static var workspaceSearch: NativeToolDefinition {
        var properties = sourceScopeProperties
        properties["query"] = ["type": "string", "minLength": 1]
        return hostTool(
            name: "weibei_search_workspace",
            description: "在指定材料、课程或整个资料库的原文中查找连续文字，不区分大小写，不拆词。结果带命中页/章节、附近原文和引用标签。可换词或改变范围再查；nextCursor 表示还有结果，按需要续页。",
            schema: NativeJSONSchema(["type": "object", "properties": properties, "required": ["query", "scope"]]),
            makeRequest: { arguments, context in
                let (scope, id) = try sourceScope(arguments, context)
                guard let query = arguments["query"] as? String, !query.isEmpty else {
                    throw NativeLLMFailure(code: "invalid_arguments", message: "查询文字不能为空")
                }
                return .workspaceSearch(query: query, scope: scope, scopeID: id,
                    cursor: string(arguments["cursor"]), limit: try positiveCount(arguments["limit"], default: 20, maximum: 100))
            }
        )
    }

    private static var courseRead: NativeToolDefinition {
        hostTool(
            name: "weibei_course_read",
            description: "按 itemID 读取连续原文。编号可来自当前位置、选区、目录或搜索。PDF 使用结果条目的 page（从1开始）；章节 location 使用返回的完整标识。未指定位置时从开头读。maximumCharacters 是本次正文额度，nextCursor 可用于按需续读。覆盖信息说明哪些页尚未取得正文。",
            schema: NativeJSONSchema([
                "type": "object",
                "properties": [
                    "itemID": ["type": "string"], "page": ["type": "integer", "minimum": 1],
                    "location": ["type": "string"], "cursor": ["type": "string"],
                    "maximumCharacters": ["type": "integer", "minimum": 1, "maximum": 12_000],
                ],
                "required": ["itemID"],
            ]),
            makeRequest: { arguments, context in
                guard let id = string(arguments["itemID"]) else {
                    throw NativeLLMFailure(code: "invalid_arguments", message: "读取需要材料编号")
                }
                let page = try arguments["page"].map { try positiveCount($0, default: 1, maximum: Int.max) }
                let location = string(arguments["location"])
                guard page == nil || location == nil else {
                    throw NativeLLMFailure(code: "invalid_arguments", message: "请选择页码或章节位置")
                }
                return .courseRead(itemID: context.persistentAssetIDsByContextID[id] ?? id,
                    page: page, location: location, cursor: string(arguments["cursor"]),
                    maximumCharacters: try positiveCount(arguments["maximumCharacters"], default: 12_000, maximum: 12_000))
            }
        )
    }

    private static var discussionSearch: NativeToolDefinition {
        hostTool(
            name: "weibei_find_discussions",
            description: "查找之前的聊天和原文旁的问答。用户提到刚才、之前的解释或需要综合几段讨论时使用。省略 query 列出当前主会话及当前资料的相关讨论，按用户提问时间倒序；query 按文字查找，itemID 指定资料，allChats=true 查找其他会话。用返回的 id 读取实际问答。",
            schema: NativeJSONSchema(["type": "object", "properties": [
                "query": ["type": "string"], "itemID": ["type": "string"],
                "allChats": ["type": "boolean"],
            ]]),
            makeRequest: { arguments, _ in
                .discussionSearch(query: string(arguments["query"]), itemID: string(arguments["itemID"]),
                    allChats: arguments["allChats"] as? Bool ?? false)
            }
        )
    }

    private static var discussionRead: NativeToolDefinition {
        hostTool(
            name: "weibei_read_discussion",
            description: "按聊天 id 读取真实问答，包括追问、修正和回答状态。返回的讨论引用标签可以用于回答，让用户点回具体问答；原资料仍可通过资料读取工具查看。",
            schema: NativeJSONSchema(["type": "object", "properties": ["chatID": ["type": "string"]],
                "required": ["chatID"]]),
            makeRequest: { arguments, _ in
                guard let raw = string(arguments["chatID"]), let id = UUID(uuidString: raw) else {
                    throw NativeLLMFailure(code: "invalid_arguments", message: "需要返回结果中的聊天编号")
                }
                return .discussionRead(chatID: id)
            }
        )
    }

    private static var webOpen: NativeToolDefinition {
        hostTool(
            name: "weibei_web_open",
            description: "读取用户本轮明确贴出、原生网页搜索返回，或已成功读取页面中真实链接指向的 HTTPS 网页。单次读取有字符预算；返回 nextCursor 时，必须原样传回 cursor 继续读取，直到 nextCursor 为空。",
            schema: NativeJSONSchema([
                "type": "object",
                "properties": [
                    "url": ["type": "string"],
                    "cursor": ["type": "string"],
                    "maximumCharacters": ["type": "integer"],
                ],
                "required": ["url"],
            ]),
            makeRequest: { arguments, _ in
                .webOpen(
                    url: string(arguments["url"]) ?? "",
                    cursor: string(arguments["cursor"]),
                    maximumCharacters: int(arguments["maximumCharacters"], default: 12_000, range: 1_000...20_000)
                )
            }
        )
    }

    private static var retryFailedPDFPages: NativeToolDefinition {
        hostTool(
            name: "weibei_course_retry_failed_pdf_pages",
            description: "用户本轮明确要求重试或重新索引 PDF 失败页时使用。itemID 可来自当前位置、目录或搜索。后端仅在当前文件确有失败页时重建这些页的索引，不改原文件；普通搜索和普通问答不得调用。",
            schema: NativeJSONSchema([
                "type": "object",
                "properties": ["itemID": ["type": "string"]],
                "required": ["itemID"],
            ]),
            makeRequest: { arguments, context in
                let itemID = string(arguments["itemID"])
                    ?? ""
                guard !itemID.isEmpty else {
                    throw NativeLLMFailure(code: "invalid_arguments", message: "重新索引失败页需要材料编号")
                }
                return .retryFailedPDFPages(
                    itemID: context.persistentAssetIDsByContextID[itemID] ?? itemID
                )
            }
        )
    }

    private static var learningMemory: NativeToolDefinition {
        NativeToolDefinition(
            name: "weibei_read_learning_memory",
            description: "只读取当前可用的全局记忆、课程记忆和上次位置，不会写入或改变任何内容。每条记忆都带 memoryID。更新已有记忆时把这个 memoryID 原样抄到 weibei_update_learning_memory；新建不要自己编 ID。其余明确要求记下、记住或更新进度时改用 weibei_update_learning_memory。",
            schema: NativeJSONSchema(["type": "object", "properties": [:]]),
            execute: { _, context in
                let learning = context.request.learningContext
                let data = try JSONEncoder().encode(learning)
                var object = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
                var evidence = context.userEvidence
                evidence["[用户：本轮]"] = context.request.question
                object["availableUserEvidence"] = evidence
                if let rawMemories = object["memories"] as? [Any] {
                    object["memories"] = rawMemories.map { raw -> Any in
                        guard var entry = raw as? [String: Any] else { return raw }
                        if let id = entry["id"] as? String {
                            entry["memoryID"] = id.lowercased()
                        }
                        return entry
                    }
                }
                let payload = try JSONSerialization.data(withJSONObject: object)
                let text = String(data: payload, encoding: .utf8) ?? "{}"
                return NativeToolExecutionResult(
                    text: text,
                    details: [
                        "kind": "learning_memory",
                        "memoryRevision": learning.memoryRevision,
                        "contextRevision": context.request.contextRevision,
                    ]
                )
            }
        )
    }

    private static var learningUpdate: NativeToolDefinition {
        NativeToolDefinition(
            name: "weibei_update_learning_memory",
            description: "记录或更新学习记忆的唯一入口。未选课程时保存到全局；已选课程时保存到该课程。先读取记忆再更新。读取请用 weibei_read_learning_memory。memoryID 只从读取结果或上次写成功回执抄写，不要自己编，不要传空字符串；新建省略该字段，魏碑会分配 id 并在回执里返回。其余明确要求记下/记住/更新进度或掌握情况时调用。每条含 kind、text、origin 和 evidence；每次最多 12 条。origin 区分 userStatement（用户自述）、observed（用户实际作答）和 agentInference（推断）。evidence 必须是可用来源标签加逐字引用；用户证据标签见读取结果，当前提问可用 [用户：本轮]。助手讲解不能证明用户已掌握。",
            schema: NativeJSONSchema([
                "type": "object",
                "properties": [
                    "entries": [
                        "type": "array",
                        "maxItems": 12,
                        "items": [
                            "type": "object",
                            "properties": [
                                "memoryID": [
                                    "type": "string",
                                    "description": "只从 weibei_read_learning_memory 返回的 memoryID 原样抄写。新建不要传这个字段，也不要传空字符串。不要自己编 UUID。",
                                ],
                                "kind": [
                                    "type": "string",
                                    "enum": [
                                        "goal",
                                        "progress",
                                        "understood",
                                        "confusion",
                                        "nextStep",
                                        "summary",
                                        "preference",
                                    ],
                                ],
                                "text": ["type": "string"],
                                "origin": ["type": "string", "enum": ["userStatement", "observed", "agentInference"]],
                                "evidence": ["type": "string", "description": "真实来源标签加原文摘录，不得自行生成引文"],
                            ],
                            "required": ["kind", "text", "origin", "evidence"],
                        ],
                    ],
                    "resolutions": [
                        "type": "array",
                        "maxItems": 12,
                        "items": [
                            "type": "object",
                            "properties": [
                                "memoryID": [
                                    "type": "string",
                                    "description": "必须是 weibei_read_learning_memory 返回的现有 memoryID，不能为空，不能自己编。",
                                ],
                                "text": ["type": "string"],
                                "evidence": ["type": "string"],
                            ],
                            "required": ["memoryID", "evidence"],
                        ],
                    ],
                ],
                "required": ["entries"],
            ]),
            execute: { arguments, context in
                try requireNonBlankResolutionIDs(arguments["resolutions"] as? [Any] ?? [])
                guard let revision = context.lastReadMemoryRevision else {
                    throw NativeLLMFailure(code: "read_required", message: "请先读取学习记忆，再提交更新。")
                }
                guard revision == context.request.learningContext.memoryRevision else {
                    throw NativeLLMFailure(code: "revision_mismatch", message: "学习记忆已变化，请重新读取后更新。")
                }
                let entries = arguments["entries"] as? [Any] ?? []
                let resolutions = arguments["resolutions"] as? [Any] ?? []
                guard entries.count <= 12, resolutions.count <= 12 else {
                    throw NativeLLMFailure(code: "entry_limit", message: "每次最多更新 12 条记忆、解决 12 条记录。")
                }
                var details: [String: Any] = [
                    "kind": "learning_update",
                    "contextRevision": context.request.contextRevision,
                    "memoryRevision": NSNumber(value: revision),
                    "suggestedNext": [],
                    "entries": omittingBlankIDs(in: entries, key: "memoryID"),
                    "resolutions": resolutions,
                ]
                try requireDecodableLearningUpdate(details)
                guard let persist = context.liveStores.persistLearningUpdate,
                      let update = StudyAgentProposalDecoding.learningUpdate(from: details) else {
                    throw NativeLLMFailure(code: "store_unavailable", message: "当前无法保存学习记忆。")
                }
                for entry in update.entries {
                    try validateMemoryEvidence(entry.evidence, origin: entry.origin, kind: entry.kind, context: context)
                }
                for resolution in update.resolutions {
                    try validateMemoryEvidence(resolution.evidence, origin: .observed, kind: .progress, context: context)
                }
                let receipt = await persist(update)
                guard receipt.accepted, let applied = receipt.memoryUpdate else {
                    return NativeToolExecutionResult(text: try receiptText(receipt), isError: true)
                }
                details["appliedMemoryUpdate"] = [
                    "memoryIDs": applied.memoryIDs.map { $0.uuidString.lowercased() },
                    "summary": applied.summary,
                    "texts": applied.texts,
                ]
                return NativeToolExecutionResult(
                    text: try receiptText(receipt),
                    details: details
                )
            }
        )
    }

    private static var courseProfileRead: NativeToolDefinition {
        NativeToolDefinition(
            name: "weibei_course_profile_read",
            description: "读取本次提问所属课程的知识档案，返回条目 id 和 profileRevision。更新前先读取；未选课程时不能读取课程档案。",
            schema: NativeJSONSchema(["type": "object", "properties": [:]]),
            execute: { _, context in
                guard let courseID = context.request.projectScope.courseID else {
                    throw NativeLLMFailure(code: "missing_course", message: "当前没有课程，请先选择要更新档案的课程。")
                }
                let data = try JSONEncoder().encode(context.request.courseProfile.entries)
                return NativeToolExecutionResult(text: String(decoding: try JSONSerialization.data(withJSONObject: [
                    "courseID": courseID,
                    "profileRevision": NSNumber(value: context.request.courseProfile.revision),
                    "entries": try JSONSerialization.jsonObject(with: data),
                ], options: [.sortedKeys]), as: UTF8.self))
            }
        )
    }

    private static var courseProfileUpdate: NativeToolDefinition {
        NativeToolDefinition(
            name: "weibei_course_profile_update",
            description: "把用户自述掌握状态写入课程知识档案，供后续出题和复习使用。用户明确要求提交时调用；其余时机自行判断。先调用 weibei_course_profile_read 获取当前条目与版本。entryID 只从当前档案已有条目的 id 抄写；新建省略，不要传空字符串，不要自己编。kind=concept，text 以「用户自述：」开头写清对哪个概念掌握到什么程度，checkpoint 用 userRequested。不要把学习记忆的 origin userStatement 当成档案 kind。",
            schema: NativeJSONSchema([
                "type": "object",
                "properties": [
                    "profileRevision": ["type": "integer"],
                    "checkpoint": [
                        "type": "string",
                        "enum": [
                            "sectionCompleted",
                            "topicCompleted",
                            "crossSourceConnection",
                            "beforeContextSwitch",
                            "userRequested",
                        ],
                    ],
                    "entries": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "entryID": [
                                    "type": "string",
                                    "description": "只从当前课程档案已有条目的 id 原样抄写。新建不要传这个字段，也不要传空字符串。不要自己编 UUID。",
                                ],
                                "kind": [
                                    "type": "string",
                                    "enum": ["concept"],
                                ],
                                "text": ["type": "string"],
                            ],
                            "required": ["kind", "text"],
                        ],
                    ],
                    "removedEntryIDs": ["type": "array", "items": ["type": "string"]],
                ],
                "required": ["profileRevision", "checkpoint"],
            ]),
            execute: { arguments, context in
                guard context.request.projectScope.courseID != nil else {
                    throw NativeLLMFailure(code: "missing_course", message: "当前没有课程，不能更新课程档案。")
                }
                try requireMatchingIntegerRevision(
                    arguments["profileRevision"],
                    expected: context.request.courseProfile.revision,
                    message: "课程知识档案已变化，请调用 weibei_course_profile_read 重新读取后更新。"
                )
                guard let checkpoint = arguments["checkpoint"] as? String else {
                    throw NativeLLMFailure(
                        code: "invalid_arguments",
                        message: "缺少参数 checkpoint"
                    )
                }
                var details: [String: Any] = [
                    "kind": "course_profile_update",
                    "contextRevision": context.request.contextRevision,
                    "profileRevision": NSNumber(value: context.request.courseProfile.revision),
                    "checkpoint": checkpoint,
                    "entries": omittingBlankIDs(in: arguments["entries"] as? [Any] ?? [], key: "entryID"),
                    "removedEntryIDs": arguments["removedEntryIDs"] as? [String]
                        ?? (arguments["removedEntryIDs"] as? [Any])?.compactMap { $0 as? String }
                        ?? [],
                ]
                try requireDecodableCourseProfileUpdate(details)
                guard let persist = context.liveStores.persistCourseProfileUpdate,
                      let update = StudyAgentProposalDecoding.courseProfileUpdate(from: details) else {
                    throw NativeLLMFailure(code: "store_unavailable", message: "当前无法保存课程档案。")
                }
                let receipt = await persist(update)
                guard receipt.accepted, let applied = receipt.profileUpdate else {
                    return NativeToolExecutionResult(text: try receiptText(receipt), isError: true)
                }
                details["appliedProfileUpdate"] = [
                    "entryIDs": applied.entryIDs.map { $0.uuidString.lowercased() },
                    "summary": applied.summary,
                    "texts": applied.texts,
                ]
                return NativeToolExecutionResult(
                    text: try receiptText(receipt),
                    details: details
                )
            }
        )
    }

    private static var noteProposal: NativeToolDefinition {
        NativeToolDefinition(
            name: "weibei_note_proposal",
            description: "整理笔记内容并交给魏碑执行。evidence 是字符串数组，每条须以当前材料、笔记或选区的真实来源标签开头。userRequested 只有两种取值：用户明确要求把内容写进笔记（如“写进笔记”“整理成笔记”“补充进去”）时传 true，魏碑会直接写入并告知写到了哪里；用户没有明确要求时传 false，魏碑把内容作为建议卡交给用户自行采用或忽略。不确定用户是否明确要求时一律传 false，不要根据内容自行猜测。",
            schema: NativeJSONSchema([
                "type": "object",
                "properties": [
                    "markdown": ["type": "string"],
                    "evidence": ["type": "array", "items": ["type": "string"]],
                    "userRequested": ["type": "boolean"],
                ],
                "required": ["markdown", "evidence", "userRequested"],
            ]),
            execute: { arguments, context in
                let markdown = arguments["markdown"] as? String ?? ""
                let evidence = stringList(arguments["evidence"])
                let userRequested = arguments["userRequested"] as? Bool == true
                guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !evidence.isEmpty else {
                    throw NativeLLMFailure(code: "empty_proposal", message: "笔记建议必须包含非空 Markdown 和至少一条证据")
                }
                let proposal = StudyAgentNoteProposal(markdown: markdown, evidence: evidence,
                    contextRevision: context.request.contextRevision, userRequested: userRequested)
                guard let perform = context.liveStores.performNoteProposal else {
                    throw NativeLLMFailure(code: "store_unavailable", message: "当前无法提交笔记内容，尚未保存。")
                }
                let receipt = await perform(proposal)
                return NativeToolExecutionResult(text: try receiptText(receipt), isError: !receipt.accepted)
            }
        )
    }

    private static var relationProposal: NativeToolDefinition {
        NativeToolDefinition(
            name: "weibei_relation_proposal",
            description: "关联本次提问所属课程内已保存的笔记与材料。用户明确要求建立关联时 userRequested=true，实际建立后返回结果；否则只保留待采用建议。noteItemID 必须是已经落库的笔记条目 ID；笔记还只是待确认提案时不要调用本工具，应先请用户确认写入。",
            schema: NativeJSONSchema([
                "type": "object",
                "properties": [
                    "noteItemID": ["type": "string"],
                    "sourceItemID": ["type": "string"],
                    "userRequested": ["type": "boolean"],
                ],
                "required": ["noteItemID", "sourceItemID", "userRequested"],
            ]),
            execute: { arguments, context in
                guard let noteID = string(arguments["noteItemID"]),
                      let sourceID = string(arguments["sourceItemID"]) else {
                    throw NativeLLMFailure(code: "missing_target", message: "关联需要已保存的笔记编号和材料编号。")
                }
                let proposal = StudyAgentRelationProposal(noteItemID: noteID, sourceItemID: sourceID,
                    contextRevision: context.request.contextRevision, userRequested: arguments["userRequested"] as? Bool == true)
                guard let perform = context.liveStores.performRelationProposal else {
                    throw NativeLLMFailure(code: "store_unavailable", message: "当前无法提交关联，尚未建立。")
                }
                let receipt = await perform(proposal)
                return NativeToolExecutionResult(text: try receiptText(receipt), isError: !receipt.accepted)
            }
        )
    }

    private static func receiptText(_ receipt: NativeStorePersistReceipt) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var object = try JSONSerialization.jsonObject(with: encoder.encode(receipt)) as! [String: Any]
        if let action = receipt.action {
            var result: [String: Any] = ["id": action.id.uuidString.lowercased(), "state": action.state.rawValue]
            result["targetItemID"] = action.targetItemID
            result["sourceItemID"] = action.sourceItemID
            result["relationID"] = action.createdRelationID?.uuidString.lowercased()
            object["action"] = result
        }
        return String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
    }

    private static func validateMemoryEvidence(
        _ evidence: String, origin: LearningMemoryOrigin, kind: LearningMemoryKind,
        context: NativeToolExecutionContext
    ) throws {
        var userEvidence = context.userEvidence
        userEvidence["[用户：本轮]"] = context.request.question
        func quotes(_ label: String, _ text: String) -> Bool {
            guard evidence.hasPrefix(label) else { return false }
            let quote = evidence.dropFirst(label.count).trimmingCharacters(in: .whitespacesAndNewlines)
            return !quote.isEmpty && text.contains(quote)
        }
        if userEvidence.contains(where: { quotes($0.key, $0.value) }) { return }
        if origin == .agentInference, kind != .understood,
           context.request.knownSources.contains(where: { quotes($0.label, $0.excerpt) }) { return }
        throw NativeLLMFailure(code: "invalid_evidence",
            message: "证据必须逐字引用实际用户消息或已读取来源。自述、作答表现和已经掌握必须有用户原话，不能用助手讲解代替。")
    }

    private static func hostTool(
        name: String,
        description: String,
        schema: NativeJSONSchema,
        makeRequest: @escaping @Sendable ([String: Any], NativeToolExecutionContext) throws -> StudyAgentHostToolRequest
    ) -> NativeToolDefinition {
        NativeToolDefinition(
            name: name,
            description: description,
            schema: schema,
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
                    details: [
                        "kind": name.replacingOccurrences(of: "weibei_", with: ""),
                        "contextRevision": context.request.contextRevision,
                    ]
                )
            }
        )
    }

    private static func string(_ raw: Any?) -> String? {
        guard let value = raw as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func stringList(_ raw: Any?) -> [String] {
        if let values = raw as? [String] {
            return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        if let value = string(raw) {
            return [value]
        }
        return []
    }

    private static func omittingBlankIDs(in entries: [Any], key: String) -> [Any] {
        entries.map { raw in
            guard var entry = raw as? [String: Any] else { return raw }
            if let value = entry[key] as? String,
               value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                entry.removeValue(forKey: key)
            }
            return entry
        }
    }

    private static func requireNonBlankResolutionIDs(_ resolutions: [Any]) throws {
        for (index, raw) in resolutions.enumerated() {
            guard let resolution = raw as? [String: Any] else { continue }
            let memoryID = (resolution["memoryID"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if memoryID.isEmpty {
                throw NativeLLMFailure(
                    code: "invalid_arguments",
                    message: "resolutions[\(index)].memoryID 必须是 weibei_read_learning_memory 返回的现有 id，不能为空，也不能自己编。"
                )
            }
        }
    }

    private static func requireDecodableLearningUpdate(_ details: [String: Any]) throws {
        guard StudyAgentProposalDecoding.learningUpdate(from: details) != nil else {
            throw NativeLLMFailure(code: "invalid_arguments", message: learningUpdateShapeError(details))
        }
    }

    private static func requireDecodableCourseProfileUpdate(_ details: [String: Any]) throws {
        guard StudyAgentProposalDecoding.courseProfileUpdate(from: details) != nil else {
            throw NativeLLMFailure(code: "invalid_arguments", message: courseProfileUpdateShapeError(details))
        }
    }

    private static func learningUpdateShapeError(_ details: [String: Any]) -> String {
        var problems: [String] = []
        if details["suggestedNext"] as? [String] == nil {
            problems.append("suggestedNext 必须是字符串数组")
        }
        if details["resolutions"] as? [Any] == nil {
            problems.append("resolutions 必须是数组")
        }
        guard let rawEntries = details["entries"] as? [Any] else {
            problems.append("entries 必须是数组")
            return "学习记忆写入无法解析：\(problems.joined(separator: "；"))。每条 entries 需要 kind（goal/progress/understood/confusion/nextStep/summary/preference）和 text。"
        }
        for (index, raw) in rawEntries.enumerated() {
            guard let entry = raw as? [String: Any] else {
                problems.append("entries[\(index)] 必须是对象")
                continue
            }
            let kind = entry["kind"] as? String ?? ""
            if LearningMemoryKind(rawValue: kind) == nil {
                problems.append("entries[\(index)].kind 必须是 goal/progress/understood/confusion/nextStep/summary/preference")
            }
            if entry["text"] as? String == nil {
                problems.append("entries[\(index)].text 必须是字符串")
            }
        }
        if problems.isEmpty {
            return "学习记忆写入无法解析。期望 entries 每条含 kind 和 text；更新已有记忆时 memoryID 从 weibei_read_learning_memory 抄写。"
        }
        return "学习记忆写入无法解析：\(problems.joined(separator: "；"))。每条 entries 需要 kind 和 text。"
    }

    private static func courseProfileUpdateShapeError(_ details: [String: Any]) -> String {
        var problems: [String] = []
        let rawEntries: [Any]
        if let typed = details["entries"] as? [Any] {
            rawEntries = typed
        } else if details["entries"] == nil {
            rawEntries = []
        } else {
            problems.append("entries 必须是对象数组")
            rawEntries = []
        }
        for (index, raw) in rawEntries.enumerated() {
            guard let entry = raw as? [String: Any] else {
                problems.append("entries[\(index)] 必须是对象")
                continue
            }
            let kind = entry["kind"] as? String ?? ""
            if CourseKnowledgeProfileEntryKind(rawValue: kind) == nil {
                problems.append("entries[\(index)].kind 必须是 concept，不要用 userStatement")
            }
            if entry["text"] as? String == nil {
                problems.append("entries[\(index)].text 必须是字符串")
            }
        }
        if problems.isEmpty {
            return "课程知识档案写入无法解析。期望 entries 每条含 kind=concept 和 text（以「用户自述：」开头）。"
        }
        return "课程知识档案写入无法解析：\(problems.joined(separator: "；"))。自述掌握用 kind=concept、text 以「用户自述：」开头。"
    }

    fileprivate static func requireMatchingIntegerRevision(_ raw: Any?, expected: UInt64, message: String) throws {
        let value: UInt64?
        if let number = raw as? NSNumber, !(raw is Bool), number.int64Value >= 0 {
            value = number.uint64Value
        } else if let int = raw as? Int, int >= 0 {
            value = UInt64(int)
        } else if let unsigned = raw as? UInt64 {
            value = unsigned
        } else {
            value = nil
        }
        guard value == expected else {
            throw NativeLLMFailure(code: "revision_mismatch", message: message)
        }
    }

    private static func bool(_ raw: Any?, default defaultValue: Bool) -> Bool {
        if let value = raw as? Bool { return value }
        if let text = string(raw)?.lowercased() {
            if text == "true" || text == "1" { return true }
            if text == "false" || text == "0" { return false }
        }
        return defaultValue
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
