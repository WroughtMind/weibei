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
    public var searchedItemIDs: [String]
    public var webSearchURLs: [String]
    public var readSourceRevisions: [String: String]
    public var lastReadMemoryRevision: UInt64?
    public var courseProfileUpdated: Bool
    public var loadedSkillIDs: Set<String>
    public var liveStores: NativeLiveStores

    public init(
        request: StudyAgentRequest,
        mode: NativeAgentMode = .assistant,
        hostToolHandler: StudyAgentHostToolHandler? = nil,
        persistentAssetIDsByContextID: [String: String] = [:],
        searchedItemIDs: [String] = [],
        webSearchURLs: [String] = [],
        readSourceRevisions: [String: String] = [:],
        lastReadMemoryRevision: UInt64? = nil,
        courseProfileUpdated: Bool = false,
        loadedSkillIDs: Set<String> = [],
        liveStores: NativeLiveStores = .empty
    ) {
        self.request = request
        self.mode = mode
        self.hostToolHandler = hostToolHandler
        self.persistentAssetIDsByContextID = persistentAssetIDsByContextID
        self.searchedItemIDs = searchedItemIDs
        self.webSearchURLs = webSearchURLs
        self.readSourceRevisions = readSourceRevisions
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
            guard WeiBeiWebResearchURLPolicy.isAuthorized(
                url,
                in: context.request.question,
                webSearchURLs: context.webSearchURLs
            ) else {
                throw NativeLLMFailure(code: "guard_denied", message: "网页工具只能读取用户本轮明确提供或刚搜索到的地址")
            }
        }
        if ["weibei_read_learning_memory", "weibei_update_learning_memory", "weibei_course_profile_update", "weibei_relation_proposal"].contains(name) {
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
        await registry.register(loadSkill)
        await registry.register(createDocument)
        await registry.register(delegate)
        await registry.register(visualize)
        await registry.register(visualAsset)
        await registry.register(courseMap)
        await registry.register(courseSearch)
        await registry.register(courseRead)
        await registry.register(retryFailedPDFPages)
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
            schema: NativeJSONSchema([
                "type": "object",
                "properties": ["path": ["type": "string"]],
                "required": ["path"],
            ]),
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

    private static var loadSkill: NativeToolDefinition {
        NativeToolDefinition(
            name: "load_skill",
            description: "按技能 id 加载技能正文并注入当前对话。同一会话每个技能只需加载一次；再次加载同一技能会返回已加载短提示，不再注入全文。加载不改变工具注册，附带工具声明只解析不落注册。",
            permission: .read,
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
            permission: .writeConfirm,
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
                    ]
                )
            }
        )
    }

    private static var delegate: NativeToolDefinition {
        NativeToolDefinition(
            name: "delegate",
            description: "把一项子任务交给子智能体。子智能体有独立账本和工具子集。Assistant 模式默认不可用。",
            permission: .writeConfirm,
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
            permission: .read,
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
            schema: NativeJSONSchema([
                "type": "object",
                "properties": [
                    "itemID": ["type": "string"],
                    "offset": ["type": "integer"],
                    "limit": ["type": "integer"],
                ],
            ]),
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
            description: "在课程索引中搜索材料与笔记。用户点名课程、教材、章节，或问题可能落在当前课程里时，先用本工具再读正文，不要先反问要查哪一种。搜到命中后应接着 weibei_course_read，itemID 用搜索结果里的 id。PDF 结果的 indexedPageCount/totalPageCount 是当前文件版本的索引覆盖率，uncoveredPageNumbers 是未覆盖页，failedPageNumbers/failedPageReasons 是最终失败页及原因；即使没有正文命中也要报告这些状态，存在未覆盖页时不得声称搜遍全文。确认课程里没有后，可以网页搜索并说明「课程里没有，我上网查了」。闲聊、冷知识、与课程无关的问题不要调用本工具。",
            permission: .read,
            schema: NativeJSONSchema([
                "type": "object",
                "properties": [
                    "query": ["type": "string"],
                    "limit": ["type": "integer"],
                ],
                "required": ["query"],
            ]),
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
            description: "按搜索结果里的 itemID 渐进读取真实正文。课程搜索命中后应读取最相关的一条，不要停下来反问用户。itemID 必须是搜索返回的 id。PDF 的 uncoveredPageNumbers 与 failedPageNumbers 不在已读正文覆盖范围内；failedPageReasons 是失败原因。",
            permission: .read,
            schema: NativeJSONSchema([
                "type": "object",
                "properties": [
                    "itemID": ["type": "string"],
                    "query": ["type": "string"],
                    "location": ["type": "string"],
                    "cursor": ["type": "string"],
                    "maximumCharacters": ["type": "integer"],
                ],
            ]),
            makeRequest: { arguments, context in
                let itemID = string(arguments["itemID"])
                    ?? context.searchedItemIDs.last
                    ?? ""
                if itemID.isEmpty {
                    throw NativeLLMFailure(code: "invalid_arguments", message: "weibei_course_read 需要搜索结果里的 itemID")
                }
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
            description: "读取用户本轮明确贴出或本轮网页搜索刚返回的 HTTPS 网页。",
            permission: .read,
            schema: NativeJSONSchema([
                "type": "object",
                "properties": [
                    "url": ["type": "string"],
                    "maximumCharacters": ["type": "integer"],
                ],
                "required": ["url"],
            ]),
            makeRequest: { arguments, _ in
                .webOpen(
                    url: string(arguments["url"]) ?? "",
                    maximumCharacters: int(arguments["maximumCharacters"], default: 12_000, range: 1_000...20_000)
                )
            }
        )
    }

    private static var retryFailedPDFPages: NativeToolDefinition {
        hostTool(
            name: "weibei_course_retry_failed_pdf_pages",
            description: "用户明确要求重试或重新索引 PDF 失败页时使用。itemID 必须来自课程搜索结果。它只重建失败页索引，不改原文件；普通搜索不得调用。",
            permission: .read,
            schema: NativeJSONSchema([
                "type": "object",
                "properties": ["itemID": ["type": "string"]],
                "required": ["itemID"],
            ]),
            makeRequest: { arguments, context in
                let itemID = string(arguments["itemID"])
                    ?? context.searchedItemIDs.last
                    ?? ""
                guard !itemID.isEmpty else {
                    throw NativeLLMFailure(code: "invalid_arguments", message: "重新索引失败页需要搜索结果里的 itemID")
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
            description: "只读取本课程学习记忆和上次位置，不会写入或改变任何内容。每条记忆都带 memoryID。更新已有记忆时把这个 memoryID 原样抄到 weibei_update_learning_memory；新建不要自己编 ID。用户要求记下、记住或更新进度时不要调用本工具，改用 weibei_update_learning_memory。返回里的 contextRevision 必须原样回传给写入类工具。",
            permission: .read,
            schema: NativeJSONSchema(["type": "object", "properties": [:]]),
            execute: { _, context in
                let learning = context.request.learningContext
                let data = try JSONEncoder().encode(learning)
                var object = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
                object["contextRevision"] = context.request.contextRevision
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
            description: "记录或更新本课程学习记忆的唯一入口。读取请用 weibei_read_learning_memory。memoryID 只从读取结果或上次写成功回执抄写，不要自己编，不要传空字符串；新建省略该字段，魏碑会分配 id 并在回执里返回。用户要求记下/记住/更新进度或掌握情况时必须调用；即使用户说先看看怎么写、不要直接改，也仍要调用，写入后在回答里逐条展示内容。contextRevision 必须原样回传。userStatement 的 evidence 必须以「[用户：本轮]」开头并带上用户原话。",
            permission: .writeConfirm,
            schema: NativeJSONSchema([
                "type": "object",
                "properties": [
                    "contextRevision": ["type": "string"],
                    "memoryRevision": ["type": "integer"],
                    "sessionSummary": ["type": "string"],
                    "suggestedPhase": [
                        "type": "string",
                        "enum": ["orient", "explore", "closeRead", "note", "recall", "consolidate", "plan"],
                    ],
                    "suggestedNext": ["type": "array", "items": ["type": "string"]],
                    "entries": [
                        "type": "array",
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
                                "evidence": ["type": "string"],
                                "origin": [
                                    "type": "string",
                                    "enum": ["userStatement", "agentInference"],
                                ],
                            ],
                            "required": ["kind", "text", "evidence", "origin"],
                        ],
                    ],
                    "resolutions": [
                        "type": "array",
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
                "required": ["contextRevision", "memoryRevision", "entries"],
            ]),
            execute: { arguments, context in
                try requireMatchingRevision(
                    arguments["contextRevision"],
                    expected: context.request.contextRevision,
                    message: "学习状态建议的上下文或记忆修订号不匹配；当前修订号为 \(context.request.contextRevision)，请原样回传"
                )
                try requireMatchingIntegerRevision(
                    arguments["memoryRevision"],
                    expected: context.request.learningContext.memoryRevision,
                    message: "学习状态建议的记忆修订号不匹配；当前 memoryRevision 为 \(context.request.learningContext.memoryRevision)，请原样回传"
                )
                try requireNonBlankResolutionIDs(arguments["resolutions"] as? [Any] ?? [])
                var details: [String: Any] = [
                    "kind": "learning_update",
                    "contextRevision": context.request.contextRevision,
                    "memoryRevision": NSNumber(value: context.request.learningContext.memoryRevision),
                    "suggestedNext": arguments["suggestedNext"] as? [String] ?? [],
                    "entries": omittingBlankIDs(in: arguments["entries"] as? [Any] ?? [], key: "memoryID"),
                    "resolutions": arguments["resolutions"] as? [Any] ?? [],
                ]
                if let summary = arguments["sessionSummary"] as? String {
                    details["sessionSummary"] = summary
                }
                if let phase = arguments["suggestedPhase"] as? String {
                    details["suggestedPhase"] = phase
                }
                try requireDecodableLearningUpdate(details)
                let queued = "学习状态更新已校验并交给魏碑；魏碑只会保存当前作用域中的实际变化。"
                guard let persist = context.liveStores.persistLearningUpdate,
                      let update = StudyAgentProposalDecoding.learningUpdate(from: details) else {
                    return NativeToolExecutionResult(text: queued, details: details)
                }
                let receipt = await persist(update)
                guard receipt.accepted, let applied = receipt.memoryUpdate else {
                    throw NativeLLMFailure(
                        code: "store_rejected",
                        message: receipt.message
                    )
                }
                details["appliedMemoryUpdate"] = [
                    "memoryIDs": applied.memoryIDs.map { $0.uuidString.lowercased() },
                    "summary": applied.summary,
                ]
                return NativeToolExecutionResult(
                    text: learningPersistSuccessText(applied),
                    details: details
                )
            }
        )
    }

    private static var courseProfileUpdate: NativeToolDefinition {
        NativeToolDefinition(
            name: "weibei_course_profile_update",
            description: "把课程认识或用户自述掌握状态写入课程知识档案。用户明确要求时必须提交。entryID 只从当前档案已有条目的 id 抄写；新建省略，不要传空字符串，不要自己编。自述掌握用 kind=concept、text 以「用户自述：」开头、sources 可空，checkpoint 用 userRequested。不要把学习记忆的 origin userStatement 当成档案 kind。材料认识仍须带来源。contextRevision 必须原样回传本轮字符串。",
            permission: .writeConfirm,
            schema: NativeJSONSchema([
                "type": "object",
                "properties": [
                    "contextRevision": ["type": "string"],
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
                                    "enum": ["overview", "section", "concept", "relation"],
                                ],
                                "text": ["type": "string"],
                                "sources": [
                                    "type": "array",
                                    "items": [
                                        "type": "object",
                                        "properties": [
                                            "itemID": ["type": "string"],
                                            "role": [
                                                "type": "string",
                                                "enum": ["material", "note"],
                                            ],
                                            "location": ["type": "string"],
                                            "sourceRevision": ["type": "string"],
                                        ],
                                        "required": ["itemID", "role", "sourceRevision"],
                                    ],
                                ],
                            ],
                            "required": ["kind", "text"],
                        ],
                    ],
                    "removedEntryIDs": ["type": "array", "items": ["type": "string"]],
                ],
                "required": ["contextRevision", "profileRevision", "checkpoint"],
            ]),
            execute: { arguments, context in
                try requireMatchingRevision(
                    arguments["contextRevision"],
                    expected: context.request.contextRevision,
                    message: "课程知识档案版本已变化；当前 contextRevision 为 \(context.request.contextRevision)，请原样回传"
                )
                try requireMatchingIntegerRevision(
                    arguments["profileRevision"],
                    expected: context.request.courseProfile.revision,
                    message: "课程知识档案版本已变化；当前 profileRevision 为 \(context.request.courseProfile.revision)，请原样回传"
                )
                var details: [String: Any] = [
                    "kind": "course_profile_update",
                    "contextRevision": context.request.contextRevision,
                    "profileRevision": NSNumber(value: context.request.courseProfile.revision),
                    "checkpoint": arguments["checkpoint"] as? String ?? "userRequested",
                    "entries": omittingBlankIDs(in: arguments["entries"] as? [Any] ?? [], key: "entryID"),
                    "removedEntryIDs": arguments["removedEntryIDs"] as? [String]
                        ?? (arguments["removedEntryIDs"] as? [Any])?.compactMap { $0 as? String }
                        ?? [],
                ]
                try requireDecodableCourseProfileUpdate(details)
                let queued = "本轮阶段性课程认识已提交保存。"
                guard let persist = context.liveStores.persistCourseProfileUpdate,
                      let update = StudyAgentProposalDecoding.courseProfileUpdate(from: details) else {
                    return NativeToolExecutionResult(text: queued, details: details)
                }
                let receipt = await persist(update)
                guard receipt.accepted, let applied = receipt.profileUpdate else {
                    throw NativeLLMFailure(
                        code: "store_rejected",
                        message: receipt.message
                    )
                }
                details["appliedProfileUpdate"] = [
                    "entryIDs": applied.entryIDs.map { $0.uuidString.lowercased() },
                    "summary": applied.summary,
                    "texts": applied.texts,
                ]
                return NativeToolExecutionResult(
                    text: profilePersistSuccessText(applied),
                    details: details
                )
            }
        )
    }

    private static var noteProposal: NativeToolDefinition {
        NativeToolDefinition(
            name: "weibei_note_proposal",
            description: "返回一份待用户确认的 Markdown 笔记建议，不会写入笔记。contextRevision 必须原样回传本轮字符串。evidence 是字符串数组，每条须以当前材料、笔记或选区的真实来源标签开头。",
            permission: .writeConfirm,
            schema: NativeJSONSchema([
                "type": "object",
                "properties": [
                    "markdown": ["type": "string"],
                    "evidence": ["type": "array", "items": ["type": "string"]],
                    "contextRevision": ["type": "string"],
                ],
                "required": ["markdown", "evidence", "contextRevision"],
            ]),
            execute: { arguments, context in
                try requireMatchingRevision(
                    arguments["contextRevision"],
                    expected: context.request.contextRevision,
                    message: "笔记建议的 contextRevision 不匹配；当前修订号为 \(context.request.contextRevision)，请原样回传"
                )
                let markdown = arguments["markdown"] as? String ?? ""
                let evidence = stringList(arguments["evidence"])
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
            description: "返回一份当前课程内笔记与材料的待确认关联。noteItemID 必须是已经落库的笔记条目 ID；笔记还只是待确认提案时不要调用本工具，应先请用户确认写入。contextRevision 必须原样回传本轮字符串。",
            permission: .writeConfirm,
            schema: NativeJSONSchema([
                "type": "object",
                "properties": [
                    "noteItemID": ["type": "string"],
                    "sourceItemID": ["type": "string"],
                    "contextRevision": ["type": "string"],
                ],
                "required": ["noteItemID", "sourceItemID", "contextRevision"],
            ]),
            execute: { arguments, context in
                try requireMatchingRevision(
                    arguments["contextRevision"],
                    expected: context.request.contextRevision,
                    message: "关系建议的 contextRevision 不匹配；当前修订号为 \(context.request.contextRevision)，请原样回传"
                )
                return NativeToolExecutionResult(
                    text: "关系建议已校验并交给魏碑；这仍是待确认建议，尚未建立关系。",
                    details: [
                        "kind": "relation_proposal",
                        "noteItemID": arguments["noteItemID"] as? String ?? "",
                        "sourceItemID": arguments["sourceItemID"] as? String ?? "",
                        "contextRevision": context.request.contextRevision,
                    ]
                )
            }
        )
    }

    private static func hostTool(
        name: String,
        description: String,
        permission: NativeToolPermission,
        schema: NativeJSONSchema,
        makeRequest: @escaping @Sendable ([String: Any], NativeToolExecutionContext) throws -> StudyAgentHostToolRequest
    ) -> NativeToolDefinition {
        NativeToolDefinition(
            name: name,
            description: description,
            permission: permission,
            schema: schema,
            execute: { arguments, context in
                guard let handler = context.hostToolHandler else {
                    throw NativeLLMFailure(code: "no_host", message: "当前 Chat 没有可用的课程查询宿主")
                }
                let request = try makeRequest(arguments, context)
                let result = try await handler(request)
                let data = try JSONEncoder().encode(result)
                let text = String(data: data, encoding: .utf8) ?? "{}"
                var details: [String: Any] = [
                    "kind": name.replacingOccurrences(of: "weibei_", with: ""),
                    "contextRevision": context.request.contextRevision,
                ]
                if name == "weibei_web_open", let url = string(arguments["url"]) {
                    details["requestedURL"] = url
                }
                return NativeToolExecutionResult(
                    text: text,
                    details: details
                )
            }
        )
    }

    private static func string(_ raw: Any?) -> String? {
        guard let value = raw as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func revisionValue(_ raw: Any?) -> String? {
        if let text = string(raw) { return text }
        if let number = raw as? NSNumber, !(raw is Bool) {
            return number.stringValue
        }
        if let value = raw as? Int {
            return String(value)
        }
        return nil
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

    private static func learningPersistSuccessText(_ update: AgentReplyMemoryUpdate) -> String {
        let ids = update.memoryIDs.map { $0.uuidString.lowercased() }.joined(separator: "、")
        return "已写入学习记忆：\(update.summary)。memoryID：\(ids)。这些 id 由魏碑分配；下次更新同一条时从 weibei_read_learning_memory 抄写，不要自己编，也不要传空字符串。"
    }

    private static func profilePersistSuccessText(_ update: AgentReplyProfileUpdate) -> String {
        let ids = update.entryIDs.map { $0.uuidString.lowercased() }.joined(separator: "、")
        let body = update.texts.isEmpty ? update.summary : update.texts.joined(separator: "；")
        return "已写入课程知识档案：\(body)。entryID：\(ids)。这些 id 由魏碑分配；下次更新同一条时从当前档案已有条目抄写，不要自己编，也不要传空字符串。"
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
            return "学习记忆写入无法解析：\(problems.joined(separator: "；"))。每条 entries 需要 kind（goal/progress/understood/confusion/nextStep/summary/preference）、text、evidence、origin（userStatement 或 agentInference）。"
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
            if entry["evidence"] as? String == nil {
                problems.append("entries[\(index)].evidence 必须是字符串")
            }
            let origin = entry["origin"] as? String ?? ""
            if LearningMemoryOrigin(rawValue: origin) == nil {
                problems.append("entries[\(index)].origin 必须是 userStatement 或 agentInference")
            }
        }
        if problems.isEmpty {
            return "学习记忆写入无法解析。期望 entries 每条含 kind、text、evidence、origin；suggestedNext 为字符串数组。"
        }
        return "学习记忆写入无法解析：\(problems.joined(separator: "；"))。用户自述用 origin=userStatement，evidence 以「[用户：本轮]」开头。"
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
                problems.append("entries[\(index)].kind 必须是 overview/section/concept/relation，不要用 userStatement")
            }
            if entry["text"] as? String == nil {
                problems.append("entries[\(index)].text 必须是字符串")
            }
            if let sources = entry["sources"] {
                let list = sources as? [[String: Any]]
                    ?? (sources as? [Any])?.compactMap { $0 as? [String: Any] }
                if list == nil {
                    problems.append("entries[\(index)].sources 必须是对象数组")
                } else {
                    for (sourceIndex, source) in (list ?? []).enumerated() {
                        if source["itemID"] as? String == nil {
                            problems.append("entries[\(index)].sources[\(sourceIndex)].itemID 必须是字符串")
                        }
                        if source["role"] as? String == nil {
                            problems.append("entries[\(index)].sources[\(sourceIndex)].role 必须是 material 或 note")
                        }
                        if source["sourceRevision"] as? String == nil {
                            problems.append("entries[\(index)].sources[\(sourceIndex)].sourceRevision 必须是字符串")
                        }
                    }
                }
            }
        }
        if problems.isEmpty {
            return "课程知识档案写入无法解析。期望 entries 每条含 kind（overview/section/concept/relation）和 text；sources 每项含 itemID、role、sourceRevision。"
        }
        return "课程知识档案写入无法解析：\(problems.joined(separator: "；"))。自述掌握用 kind=concept、text 以「用户自述：」开头、sources 可空。"
    }

    fileprivate static func requireMatchingRevision(_ raw: Any?, expected: String, message: String) throws {
        guard revisionValue(raw) == expected else {
            throw NativeLLMFailure(code: "revision_mismatch", message: message)
        }
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
