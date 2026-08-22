import Foundation
import WeiBeiCore

func runPiAgentSelfChecks() throws {
    try checkCourseDocumentSearchReadiness()
    try checkPiProviderConfiguration()
    try checkPiProxyEnvironmentResolution()
    try checkJSONLFraming()
    try checkRPCDecoding()
    try checkStudyAgentContext()
    try checkPiExecutableLocation()
}

private func checkPiProviderConfiguration() throws {
    let inherited = PiAgentProviderConfiguration()
    try piRequire(
        inherited.provider == nil && inherited.model == nil && inherited.thinkingLevel == "medium",
        "PI provider defaults keep the current medium thinking level"
    )

    let explicit = PiAgentProviderConfiguration(
        provider: " openai-codex ",
        model: " gpt-5.5 ",
        thinkingLevel: " xhigh "
    )
    try piRequire(
        explicit.provider == "openai-codex" && explicit.model == "gpt-5.5" && explicit.thinkingLevel == "xhigh",
        "PI provider keeps explicit subscription model and thinking overrides"
    )
}

private func piRequire(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try condition() else { throw PiAgentSelfCheckError.failed(message) }
}

private func checkPiProxyEnvironmentResolution() throws {
    // Explicit host variables always win over the macOS system proxy.
    let hostWins = PiProxyEnvironmentResolver.resolve(
        hostEnvironment: ["HTTPS_PROXY": "http://127.0.0.1:7890"],
        systemProxySettings: ["HTTPSEnable": 1, "HTTPSProxy": "10.0.0.2", "HTTPSPort": 8080]
    )
    try piRequire(
        hostWins.source == .hostEnvironment
            && hostWins.variables == ["HTTPS_PROXY": "http://127.0.0.1:7890"],
        "PI proxy keeps explicit host variables ahead of the system proxy"
    )

    // Without host variables, an enabled system HTTPS proxy is injected along
    // with its bypass list as NO_PROXY.
    let systemInjected = PiProxyEnvironmentResolver.resolve(
        hostEnvironment: [:],
        systemProxySettings: [
            "HTTPSEnable": 1, "HTTPSProxy": "10.0.0.2", "HTTPSPort": 8080,
            "ExceptionsList": ["*.local", "192.168.0.0/16"],
        ]
    )
    try piRequire(
        systemInjected.source == .systemProxy
            && systemInjected.variables["HTTPS_PROXY"] == "http://10.0.0.2:8080"
            && systemInjected.variables["NO_PROXY"] == "*.local,192.168.0.0/16",
        "PI proxy injects the macOS system proxy when no host variables exist"
    )

    // A SOCKS-only system proxy maps to ALL_PROXY.
    let socksOnly = PiProxyEnvironmentResolver.resolve(
        hostEnvironment: [:],
        systemProxySettings: ["SOCKSEnable": 1, "SOCKSProxy": "10.0.0.3", "SOCKSPort": 1080]
    )
    try piRequire(
        socksOnly.source == .systemProxy
            && socksOnly.variables == ["ALL_PROXY": "socks5://10.0.0.3:1080"],
        "PI proxy maps a SOCKS-only system proxy to ALL_PROXY"
    )

    // A disabled or unreadable system proxy stays direct and injects nothing.
    let disabled = PiProxyEnvironmentResolver.resolve(
        hostEnvironment: [:],
        systemProxySettings: ["HTTPEnable": 0, "HTTPSEnable": 0, "SOCKSEnable": 0]
    )
    let missing = PiProxyEnvironmentResolver.resolve(hostEnvironment: [:], systemProxySettings: nil)
    try piRequire(
        disabled.source == .direct && disabled.variables.isEmpty
            && missing.source == .direct && missing.variables.isEmpty,
        "PI proxy stays direct when the system proxy is off or unreadable"
    )

    // PAC cannot be translated into plain proxy variables and falls back to direct.
    let pac = PiProxyEnvironmentResolver.resolve(
        hostEnvironment: [:],
        systemProxySettings: [
            "ProxyAutoConfigEnable": 1,
            "HTTPSEnable": 1, "HTTPSProxy": "10.0.0.2", "HTTPSPort": 8080,
        ]
    )
    try piRequire(
        pac.source == .direct && pac.variables.isEmpty,
        "PI proxy skips PAC-based system proxy settings"
    )

    // Malformed host values are rejected with the same rule as before.
    let invalid = PiProxyEnvironmentResolver.resolve(
        hostEnvironment: ["HTTPS_PROXY": "http://bad\nhost"],
        systemProxySettings: nil
    )
    try piRequire(
        invalid.source == .direct && invalid.variables.isEmpty,
        "PI proxy rejects malformed host proxy variables"
    )
}

private func checkJSONLFraming() throws {
    let delta = "中文跨字节\u{2028}仍在同一条 JSON 记录"
    let first = #"{"type":"message_update","assistantMessageEvent":{"type":"text_delta","delta":"中文跨字节 仍在同一条 JSON 记录"}}"#
    let second = #"{"type":"tool_execution_start","toolCallId":"tool-1","toolName":"weibei_course_search","args":{"query":"利率","limit":3}}"#
    var framer = PiJSONLFramer()
    var records: [Data] = []
    for byte in Data("\(first)\r\n\(second)\n".utf8) {
        records.append(contentsOf: try framer.append(Data([byte])))
    }
    _ = try framer.finish()
    try piRequire(records.count == 2, "PI JSONL keeps CRLF compatibility and emits two records")
    try piRequire(PiRPCMessageDecoder.decode(records[0]) == .textDelta(delta), "PI JSONL preserves split UTF-8 and U+2028")
    guard case let .toolStarted(id, name, argumentsJSON) = try PiRPCMessageDecoder.decode(records[1]),
          let argumentsJSON,
          let arguments = try JSONSerialization.jsonObject(with: argumentsJSON) as? [String: Any] else {
        throw PiAgentSelfCheckError.failed("PI JSONL lost host tool arguments")
    }
    try piRequire(
        id == "tool-1"
            && name == "weibei_course_search"
            && arguments["query"] as? String == "利率"
            && (arguments["limit"] as? NSNumber)?.intValue == 3,
        "PI JSONL preserves bounded host tool ids and arguments"
    )

    var incomplete = PiJSONLFramer()
    _ = try incomplete.append(Data("{\"type\":\"event\"}".utf8))
    do {
        _ = try incomplete.finish()
        throw PiAgentSelfCheckError.failed("PI JSONL accepted an unterminated record")
    } catch let error as PiRPCProtocolError {
        try piRequire(error == .incompleteLine, "PI JSONL rejects an unterminated record")
    }

    var bounded = PiJSONLFramer(maximumLineBytes: 3)
    do {
        _ = try bounded.append(Data("four".utf8))
        throw PiAgentSelfCheckError.failed("PI JSONL accepted an oversized record")
    } catch let error as PiRPCProtocolError {
        try piRequire(error == .lineTooLarge(4), "PI JSONL enforces its byte limit")
    }
}

private func checkRPCDecoding() throws {
    let named = try PiRPCMessageDecoder.decode(
        Data(#"{"type":"session_info_changed","name":"利率为何不同"}"#.utf8)
    )
    try piRequire(
        named == .sessionNameChanged("利率为何不同"),
        "PI session name events preserve semantic titles"
    )

    let state = try PiRPCMessageDecoder.decode(Data(#"{"id":"state-1","type":"response","command":"get_state","success":true,"data":{"isStreaming":false}}"#.utf8))
    guard case let .response(response) = state else {
        throw PiAgentSelfCheckError.failed("PI get_state response did not decode")
    }
    try piRequire(response.id == "state-1" && response.command == "get_state" && response.success && response.dataJSON != nil, "PI get_state keeps correlation and data")

    let rejection = try PiRPCMessageDecoder.decode(Data(#"{"id":"prompt-1","type":"response","command":"prompt","success":false,"error":"busy"}"#.utf8))
    try piRequire(rejection == .response(PiRPCResponse(id: "prompt-1", command: "prompt", success: false, error: "busy")), "PI rejected commands keep their errors")

    let failedTool = try PiRPCMessageDecoder.decode(Data(#"{"type":"tool_execution_end","toolCallId":"tool-2","toolName":"weibei_course_search","isError":true,"result":{"content":[{"type":"text","text":"stale context"}]}}"#.utf8))
    try piRequire(failedTool == .toolFailed(id: "tool-2", name: "weibei_course_search", message: "stale context"), "PI tool failures keep ids and messages")

    let visualAssetRead = try PiRPCMessageDecoder.decode(Data(#"{"type":"tool_execution_end","toolCallId":"tool-visual","toolName":"weibei_visual_asset","isError":false,"result":{"details":{"kind":"visual_asset_read","contextRevision":"revision-7","assetID":"course-item-1","sha256":"abc123","byteCount":2048}}}"#.utf8))
    try piRequire(
        visualAssetRead == .visualAssetRead(
            id: "tool-visual",
            contextRevision: "revision-7",
            assetID: "course-item-1",
            sha256: "abc123",
            byteCount: 2_048
        ),
        "PI visual asset reads preserve source ID, hash, and byte count"
    )

    let skillRead = try PiRPCMessageDecoder.decode(Data(#"{"type":"tool_execution_end","toolCallId":"tool-skill","toolName":"read","isError":false,"result":{"details":{"kind":"weibei_skill_read","contextRevision":"revision-7","loaded":{"id":"visualize","name":"Visualize","version":"1.0.0","sha256":"abc123","byteCount":1840,"relativePath":"skills/visualize/SKILL.md","loadedAtContextRevision":"revision-7"}}}}"#.utf8))
    try piRequire(
        skillRead == .skillsLoaded(
            id: "tool-skill",
            contextRevision: "revision-7",
            skills: [
                StudyAgentLoadedSkill(
                    id: "visualize",
                    name: "Visualize",
                    version: "1.0.0",
                    sha256: "abc123",
                    byteCount: 1840,
                    relativePath: "skills/visualize/SKILL.md",
                    loadedAtContextRevision: "revision-7"
                ),
            ]
        ),
        "PI native skill reads preserve versioned evidence metadata"
    )

    let visualization = try PiRPCMessageDecoder.decode(Data(#"{"type":"tool_execution_end","toolCallId":"tool-visualize","toolName":"weibei_visualize","isError":false,"result":{"details":{"kind":"weibei_visualization","id":"energy-flow","spec":{"items":[{"type":"button","label":"调整","action":"adjust"}]}}}}"#.utf8))
    try piRequire(
        visualization == .visualization(
            id: "tool-visualize",
            fragment: AgentVisualization(
                id: "energy-flow",
                specJSON: #"{"items":[{"action":"adjust","label":"调整","type":"button"}]}"#
            )
        ),
        "PI Visualize results preserve stable id and component tree"
    )
    do {
        _ = try PiRPCMessageDecoder.decode(Data(#"{"type":"tool_execution_end","toolCallId":"tool-visualize","toolName":"weibei_visualize","isError":false,"result":{"details":{"kind":"weibei_visualization","id":"Bad--ID","spec":{"items":[{"type":"button","label":"调整"}]}}}}"#.utf8))
        throw PiAgentSelfCheckError.failed("PI Visualize rejects unstable ids")
    } catch PiRPCProtocolError.invalidEnvelope {
        // Expected: same-id updates require one canonical lowercase identifier.
    }

    let courseRead = try PiRPCMessageDecoder.decode(Data(#"{"type":"tool_execution_end","toolCallId":"tool-course","toolName":"weibei_course_search","isError":false,"result":{"details":{"kind":"course_search","contextRevision":"revision-7","results":[{"id":"material-rates","title":"利率","role":"material","searchText":"利率正文","sourceRevision":"source-revision-1"},{"id":"note-rates","title":"课堂笔记","role":"note","searchText":"笔记正文"},{"id":"title-only","title":"只有标题","role":"material","searchText":""}],"evidenceLabels":["[材料：利率，条目：2]","[笔记：课堂笔记]"],"jumpEvidence":{"来源：利率":"[材料：利率，条目：2]","来源：利率，条目：2，第 3 页":"[材料：利率，条目：2]"}}}}"#.utf8))
    if case let .courseSourcesRead(
        id,
        toolName,
        revision,
        labels,
        assetIDs,
        sourceRevisions,
        jumpEvidence,
        sources
    ) = courseRead {
        try piRequire(
            id == "tool-course"
                && toolName == "weibei_course_search"
                && revision == "revision-7"
                && labels == ["[材料：利率，条目：2]", "[笔记：课堂笔记]"]
                && assetIDs == ["material-rates", "note-rates"]
                && sourceRevisions == ["material-rates": "source-revision-1"]
                && jumpEvidence == [
                    "来源：利率": "[材料：利率，条目：2]",
                    "来源：利率，条目：2，第 3 页": "[材料：利率，条目：2]",
                ]
                && sources.map(\.itemID) == ["material-rates", "note-rates"]
                && sources.map(\.excerpt) == ["利率正文", "笔记正文"]
                && sources.first?.pageIndex == 2
                && sources.first?.courseItemOrdinal == 2,
            "PI course tools preserve source IDs, excerpts, and jump locations read this turn"
        )
    } else {
        try piRequire(false, "PI course search decodes as a structured source event")
    }

    let profileUpdate = try PiRPCMessageDecoder.decode(Data(#"{"type":"tool_execution_end","toolCallId":"tool-profile","toolName":"weibei_course_profile_update","isError":false,"result":{"details":{"kind":"course_profile_update","contextRevision":"revision-7","profileRevision":2,"checkpoint":"sectionCompleted","entries":[{"kind":"concept","text":"政策利率影响资金价格。","sources":[{"itemID":"material-rates","role":"material","location":"利率渠道","sourceRevision":"source-revision-1"}]}],"removedEntryIDs":[]}}}"#.utf8))
    try piRequire(
        profileUpdate == .courseProfileUpdate(
            id: "tool-profile",
            StudyAgentCourseProfileUpdate(
                contextRevision: "revision-7",
                profileRevision: 2,
                checkpoint: "sectionCompleted",
                entries: [
                    StudyAgentCourseProfileUpdateEntry(
                        kind: .concept,
                        text: "政策利率影响资金价格。",
                        sources: [
                            StudyAgentCourseProfileSource(
                                itemID: "material-rates",
                                role: "material",
                                location: "利率渠道",
                                sourceRevision: "source-revision-1"
                            ),
                        ]
                    ),
                ]
            )
        ),
        "PI course-profile updates preserve checkpoint and actually read source revisions"
    )
    let mapRead = try PiRPCMessageDecoder.decode(Data(#"{"type":"tool_execution_end","toolCallId":"tool-map","toolName":"weibei_course_map","isError":false,"result":{"details":{"kind":"course_map","catalog":[{"title":"只有目录标题","role":"material"}]}}}"#.utf8))
    try piRequire(
        mapRead == .event("tool_execution_end"),
        "PI course-map metadata does not unlock a material as content evidence"
    )

    let memoryRead = try PiRPCMessageDecoder.decode(Data(#"{"type":"tool_execution_end","toolCallId":"tool-learning","toolName":"weibei_read_learning_memory","isError":false,"result":{"details":{"kind":"learning_memory","contextRevision":"revision-7","memoryRevision":4,"learning":{"memories":[]},"jumpEvidence":{}}}}"#.utf8))
    try piRequire(
        memoryRead == .learningMemoryRead(
            id: "tool-learning",
            contextRevision: "revision-7",
            memoryRevision: 4,
            labels: ["[学习记忆：无记录]"],
            jumpEvidence: [:]
        ),
        "PI learning-memory reads preserve the validated revision and expose only the memory evidence that actually exists"
    )

    let proposalData = try JSONSerialization.data(withJSONObject: [
        "type": "tool_execution_end",
        "toolCallId": "tool-3",
        "toolName": "weibei_note_proposal",
        "isError": false,
        "result": [
            "content": [["type": "text", "text": "accepted"]],
            "details": [
                "kind": "note_proposal",
                "markdown": "## 核心要点\n- 利率是资金价格。",
                "evidence": ["[选区：利率定义]"],
                "contextRevision": "revision-7",
            ],
        ],
    ])
    let proposal = try PiRPCMessageDecoder.decode(proposalData)
    try piRequire(
        proposal == .noteProposal(
            id: "tool-3",
            StudyAgentNoteProposal(
                markdown: "## 核心要点\n- 利率是资金价格。",
                evidence: ["[选区：利率定义]"],
                contextRevision: "revision-7"
            )
        ),
        "PI note proposals preserve Markdown, evidence, and revision"
    )

    let relationProposalData = try JSONSerialization.data(withJSONObject: [
        "type": "tool_execution_end",
        "toolCallId": "tool-relation",
        "toolName": "weibei_relation_proposal",
        "isError": false,
        "result": [
            "details": [
                "kind": "relation_proposal",
                "noteItemID": "course-item-1",
                "sourceItemID": "course-item-2",
                "contextRevision": "revision-7",
            ],
        ],
    ])
    let relationProposal = try PiRPCMessageDecoder.decode(relationProposalData)
    try piRequire(
        relationProposal == .relationProposal(
            id: "tool-relation",
            StudyAgentRelationProposal(
                noteItemID: "course-item-1",
                sourceItemID: "course-item-2",
                contextRevision: "revision-7"
            )
        ),
        "PI relation proposals preserve both targets and revision"
    )

    let learningData = try JSONSerialization.data(withJSONObject: [
        "type": "tool_execution_end",
        "toolCallId": "tool-memory",
        "toolName": "weibei_update_learning_memory",
        "isError": false,
        "result": [
            "details": [
                "kind": "learning_update",
                "contextRevision": "revision-7",
                "memoryRevision": 4,
                "sessionSummary": "学到实际利率。",
                "suggestedPhase": "recall",
                "suggestedNext": ["用一道题区分名义利率与实际利率"],
                "entries": [
                    [
                        "memoryID": "00000000-0000-0000-0000-000000000003",
                        "kind": "confusion",
                        "text": "还不熟悉费雪方程",
                        "evidence": "[用户：本轮] 用户明确说不熟悉",
                        "origin": "userStatement",
                    ],
                    [
                        "kind": "nextStep",
                        "text": "练习一道费雪方程题",
                        "evidence": "[会话：当前] 用户要求安排一道练习",
                        "origin": "agentInference",
                    ],
                ],
                "resolutions": [
                    [
                        "memoryID": "00000000-0000-0000-0000-000000000004",
                        "text": "曾经不熟悉费雪方程",
                        "evidence": "[会话：当前] 用户在回忆题中正确解释",
                    ],
                ],
            ],
        ],
    ])
    let learningUpdate = try PiRPCMessageDecoder.decode(learningData)
    try piRequire(
        learningUpdate == .learningUpdate(
            id: "tool-memory",
            StudyAgentLearningUpdate(
                contextRevision: "revision-7",
                memoryRevision: 4,
                sessionSummary: "学到实际利率。",
                suggestedPhase: .recall,
                suggestedNext: ["用一道题区分名义利率与实际利率"],
                entries: [
                    StudyAgentMemoryUpdateEntry(
                        memoryID: "00000000-0000-0000-0000-000000000003",
                        kind: .confusion,
                        text: "还不熟悉费雪方程",
                        evidence: "[用户：本轮] 用户明确说不熟悉",
                        origin: .userStatement
                    ),
                    StudyAgentMemoryUpdateEntry(
                        kind: .nextStep,
                        text: "练习一道费雪方程题",
                        evidence: "[会话：当前] 用户要求安排一道练习",
                        origin: .agentInference
                    ),
                ],
                resolutions: [
                    StudyAgentMemoryResolution(
                        memoryID: "00000000-0000-0000-0000-000000000004",
                        text: "曾经不熟悉费雪方程",
                        evidence: "[会话：当前] 用户在回忆题中正确解释"
                    ),
                ]
            )
        ),
        "PI learning updates preserve context, memory revision, evidence, and flow"
    )
    let partiallyMalformedLearningData = try JSONSerialization.data(withJSONObject: [
        "type": "tool_execution_end",
        "toolCallId": "tool-memory-malformed",
        "toolName": "weibei_update_learning_memory",
        "isError": false,
        "result": [
            "details": [
                "kind": "learning_update",
                "contextRevision": "revision-7",
                "memoryRevision": 4,
                "suggestedNext": [],
                "entries": [
                    [
                        "kind": "progress",
                        "text": "完成第一节",
                        "evidence": "[用户：本轮] 完成第一节",
                        "origin": "userStatement",
                    ],
                    [
                        "kind": "confusion",
                        "text": "这条缺少 origin，不能被静默吞掉",
                        "evidence": "[用户：本轮] 仍然困惑",
                    ],
                ],
                "resolutions": [],
            ],
        ],
    ])
    try piRequire(
        try PiRPCMessageDecoder.decode(partiallyMalformedLearningData)
            == .event("tool_execution_end"),
        "PI rejects an entire learning update instead of silently dropping malformed entries"
    )
    let partiallyMalformedResolutionData = try JSONSerialization.data(withJSONObject: [
        "type": "tool_execution_end",
        "toolCallId": "tool-resolution-malformed",
        "toolName": "weibei_update_learning_memory",
        "isError": false,
        "result": [
            "details": [
                "kind": "learning_update",
                "contextRevision": "revision-7",
                "memoryRevision": 4,
                "suggestedNext": [],
                "entries": [],
                "resolutions": [
                    [
                        "memoryID": "00000000-0000-0000-0000-000000000004",
                        "text": "已经解决",
                        "evidence": "[用户：本轮] 已经解决",
                    ],
                    [
                        "memoryID": "00000000-0000-0000-0000-000000000005",
                        "text": "这条缺少 evidence，不能被静默吞掉",
                    ],
                ],
            ],
        ],
    ])
    try piRequire(
        try PiRPCMessageDecoder.decode(partiallyMalformedResolutionData)
            == .event("tool_execution_end"),
        "PI rejects an entire learning update instead of silently dropping malformed resolutions"
    )

    let ended = try PiRPCMessageDecoder.decode(Data(#"{"type":"agent_end","messages":[{"role":"assistant","content":[{"type":"text","text":"第一轮"}],"stopReason":"toolUse","provider":"openai","model":"older-model"},{"role":"assistant","content":[{"type":"text","text":"最终回答"}],"stopReason":"stop","provider":"openai","model":"gpt-test"}]}"#.utf8))
    try piRequire(
        ended == .agentEnded(
            text: "最终回答",
            stopReason: "stop",
            error: nil,
            provider: "openai",
            model: "gpt-test"
        ),
        "PI agent_end preserves the final assistant answer and model provenance"
    )

    let messageEndError = try PiRPCMessageDecoder.decode(Data(#"{"type":"message_end","message":{"role":"assistant","stopReason":"error","errorMessage":"上游服务拒绝了这次请求"}}"#.utf8))
    try piRequire(
        messageEndError == .assistantError("上游服务拒绝了这次请求"),
        "PI message_end exposes the assistant error instead of collapsing it into an unknown error"
    )

    let turnEndError = try PiRPCMessageDecoder.decode(Data(#"{"type":"turn_end","message":{"role":"assistant","stopReason":"error","diagnostics":[{"message":"旧诊断"},{"error":{"message":"证书校验失败"}}]}}"#.utf8))
    try piRequire(
        turnEndError == .assistantError("证书校验失败"),
        "PI turn_end exposes the newest nested diagnostic"
    )

    let thinking = try PiRPCMessageDecoder.decode(Data(#"{"type":"message_update","assistantMessageEvent":{"type":"thinking_delta","delta":"正在核对来源"}}"#.utf8))
    try piRequire(thinking == .runActivity(.thinking), "PI thinking deltas count as real run activity")
    let retrying = try PiRPCMessageDecoder.decode(Data(#"{"type":"auto_retry_start","attempt":2}"#.utf8))
    try piRequire(retrying == .runActivity(.retrying), "PI provider retries count as real run activity")
    let toolUpdate = try PiRPCMessageDecoder.decode(Data(#"{"type":"tool_execution_update","toolCallId":"tool-9","toolName":"weibei_course_search"}"#.utf8))
    try piRequire(toolUpdate == .runActivity(.tool), "PI tool updates count as real run activity")

    let endedWithError = try PiRPCMessageDecoder.decode(Data(#"{"type":"agent_end","messages":[{"role":"assistant","content":[],"stopReason":"error","diagnostics":[{"error":{"message":"真实模型错误"}}]}]}"#.utf8))
    try piRequire(
        endedWithError == .agentEnded(
            text: "",
            stopReason: "error",
            error: "真实模型错误",
            provider: nil,
            model: nil
        ),
        "PI agent_end preserves the terminal model error"
    )
    try piRequire(try PiRPCMessageDecoder.decode(Data(#"{"type":"future_event"}"#.utf8)) == .event("future_event"), "PI decoder tolerates unknown future events")

    do {
        _ = try PiRPCMessageDecoder.decode(Data("not-json".utf8))
        throw PiAgentSelfCheckError.failed("PI decoder accepted invalid JSON")
    } catch let error as PiRPCProtocolError {
        try piRequire(error == .invalidJSON, "PI decoder rejects invalid JSON")
    }
}

private func checkStudyAgentContext() throws {
    let courseItems = (0..<90).map { index in
        StudyAgentCourseItem(
            id: "item-\(index)",
            title: "课程条目 \(index)",
            subtitle: "subtitle-\(index)",
            kind: index.isMultiple(of: 2) ? "pdf" : "markdown",
            role: index.isMultiple(of: 2) ? "material" : "note",
            linkedItemIDs: (0..<30).map { "linked-\($0)" },
            headings: (0..<18).map { "heading-\($0)" },
            tags: (0..<20).map { "#tag-\($0)" },
            searchText: String(repeating: "课", count: 2_500)
        )
    }
    let resolvedMemoryID = UUID(uuidString: "00000000-0000-0000-0000-000000000099")!
    var learningMemories: [LearningMemoryEntry] = []
    learningMemories.reserveCapacity(60)
    for index in 0..<60 {
        learningMemories.append(
            LearningMemoryEntry(
                id: index == 59 ? resolvedMemoryID : UUID(),
                kind: index.isMultiple(of: 2) ? .confusion : .nextStep,
                text: "memory-\(index)" + String(repeating: "学", count: 520),
                evidence: "[用户：本轮] evidence-\(index)" + String(repeating: "据", count: 420),
                origin: .userStatement,
                status: index == 59 ? .resolved : .active,
                updatedAt: Date(timeIntervalSinceReferenceDate: TimeInterval(index))
            )
        )
    }
    let request = StudyAgentRequest(
        purpose: .conversation,
        answerFormPolicy: .textOnly,
        question: "请根据当前材料出题",
        materialTitle: String(repeating: "材", count: 320),
        materialText: String(repeating: "材", count: 18_100),
        noteTitle: String(repeating: "记", count: 320),
        noteText: String(repeating: "记", count: 6_100),
        selectionTitle: String(repeating: "选", count: 320),
        selectionText: String(repeating: "选", count: 2_100),
        courseContext: StudyAgentCourseContext(
            title: "测试课程",
            items: courseItems,
            relations: (0..<210).map {
                StudyAgentCourseRelation(noteItemID: "item-\($0 % 80)", sourceItemID: "item-\(($0 + 1) % 80)")
            }
        ),
        learningContext: StudyAgentLearningContext(
            memoryRevision: 7,
            lastLocation: StudyLocation(
                itemID: "item-0",
                itemTitle: String(repeating: "位", count: 320),
                locationID: "html-section-a1b2c3d4",
                locationTitle: String(repeating: "章", count: 320),
                pageIndex: 12
            ),
            memories: learningMemories,
            session: StudyAgentSessionSnapshot(
                id: "session-1",
                title: String(repeating: "会", count: 320),
                summary: String(repeating: "摘", count: 2_100),
                phase: StudyPhase.recall.rawValue,
                focusItemIDs: (0..<30).map { "item-\($0)" },
                turnCount: 20
            )
        ),
        language: .chinese,
        contextRevision: "revision-9"
    )
    try piRequire(
        StudyAgentCurrentTurnEvidence.matches(
            "[用户：本轮]我还不懂名义利率和实际利率的区别",
            question: "上次学到哪？我还不懂名义利率和实际利率的区别，请记住。"
        )
            && StudyAgentCurrentTurnEvidence.matches(
                "[用户：本轮]我已经能够区分名义利率和实际利率了",
                question: "我已经能够区分名义利率和实际利率了"
            )
            && StudyAgentCurrentTurnEvidence.matches(
                "[用户：本轮]利率",
                question: "实际利率；利率，"
            )
            && !StudyAgentCurrentTurnEvidence.matches(
                "[用户：本轮]我掌握了全部内容",
                question: "我还不懂名义利率和实际利率的区别"
            )
            && !StudyAgentCurrentTurnEvidence.matches(
                "[用户：本轮]利率",
                question: "实际利率"
            ),
        "current-turn memory evidence validates only an exact bounded quote, not its meaning"
    )

    let envelope = StudyAgentContextEnvelope(request: request)
    try piRequire(envelope.schemaVersion == 2 && envelope.contextRevision == "revision-9", "study-agent context carries schema and revision")
    try piRequire(envelope.answerFormPolicy == StudyAgentAnswerFormPolicy.textOnly.rawValue, "study-agent context carries structured answer-form policy")
    try piRequire(envelope.material?.text.count == 18_000 && envelope.note.text.count == 6_000 && envelope.selection?.text.count == 2_000, "study-agent context applies source limits")
    try piRequire(envelope.material?.title.count == 300 && envelope.note.title.count == 300 && envelope.selection?.title.count == 300, "study-agent context bounds source labels consistently")
    try piRequire(envelope.material?.isTruncated == true && envelope.note.isTruncated && envelope.selection?.isTruncated == true, "study-agent context marks every truncated source")
    let encodedEnvelope = try JSONEncoder().encode(envelope)
    try piRequire(
        !String(decoding: encodedEnvelope, as: UTF8.self).contains("recentMessages"),
        "study-agent context leaves conversation history to the native PI session"
    )
    try piRequire(envelope.course.catalog.count == 90 && envelope.course.items.count == 80 && envelope.course.relations.count == 210 && envelope.course.isTruncated, "study-agent context keeps the full catalog while bounding query candidates")
    try piRequire(
        envelope.course.catalog.allSatisfy { $0.id.hasPrefix("course-item-") }
            && envelope.course.items.allSatisfy { $0.id.hasPrefix("course-item-") }
            && envelope.course.relations.allSatisfy {
                $0.noteItemID.hasPrefix("course-item-") && $0.sourceItemID.hasPrefix("course-item-")
            },
        "study-agent context replaces workspace item ids with request-local opaque ids"
    )
    try piRequire(envelope.course.items.allSatisfy { $0.searchText.count <= 2_400 && $0.headings.count <= 12 && $0.tags.count <= 16 && $0.linkedItemIDs.count <= 24 }, "study-agent context bounds course search metadata")
    let retainsRecentResolvedMemory = envelope.learning.memories.contains {
        $0.id == resolvedMemoryID && $0.status == LearningMemoryStatus.resolved
    }
    try piRequire(
        envelope.learning.memoryRevision == 7
            && envelope.learning.memories.count == 48
            && retainsRecentResolvedMemory,
        "study-agent context carries a bounded memory revision and recent resolved history"
    )
    try piRequire(envelope.learning.memories.allSatisfy { $0.text.count <= 500 && $0.evidence.count <= 400 }, "study-agent context bounds durable learning memory")
    try piRequire(
        envelope.learning.lastLocation?.itemTitle.count == 300
            && envelope.learning.lastLocation?.itemID == "course-item-1"
            && envelope.learning.lastLocation?.locationID == "html-section-a1b2c3d4"
            && envelope.learning.lastLocation?.pageIndex == 13
            && envelope.learning.session?.summary.count == 2_000
            && envelope.learning.session?.focusItemIDs.count == 24,
        "study-agent context bounds location and session state, uses opaque ids, and exposes one-based page numbers"
    )

    let visualEnvelope = StudyAgentContextEnvelope(
        request: StudyAgentRequest(
            purpose: .conversation,
            question: "观察当前地图",
            materialTitle: "当前地图",
            materialText: "地图材料",
            noteTitle: "笔记",
            noteText: "",
            courseContext: StudyAgentCourseContext(
                title: "地图课程",
                items: [
                    StudyAgentCourseItem(
                        id: "current-map",
                        title: "当前地图",
                        subtitle: "PNG",
                        kind: "image",
                        role: "material",
                        isCurrentMaterial: true
                    ),
                    StudyAgentCourseItem(
                        id: "other-map",
                        title: "其他地图",
                        subtitle: "PNG",
                        kind: "image",
                        role: "material"
                    ),
                ]
            ),
            visualAssets: [
                StudyAgentVisualAsset(id: "current-map", filePath: "/private/tmp/current-map.png", mediaType: "image/png"),
                StudyAgentVisualAsset(id: "other-map", filePath: "/private/tmp/other-map.png", mediaType: "image/png"),
                StudyAgentVisualAsset(id: "current-map", filePath: "/private/tmp/current-map.svg", mediaType: "image/svg+xml"),
            ],
            contextRevision: "visual-assets-test"
        )
    )
    try piRequire(
        visualEnvelope.visualAssets == [
            StudyAgentVisualAsset(id: "course-item-1", filePath: "/private/tmp/current-map.png", mediaType: "image/png"),
        ],
        "study-agent context only carries bounded raster assets for the current material and remaps their ids"
    )

    let projectIdentity = StudyAgentFileIdentity(
        ImportedFileIdentity(
            volumeID: 1,
            fileID: 2,
            birthTimeSeconds: 3,
            birthTimeNanoseconds: 4
        )
    )
    let globalChatID = UUID().uuidString.lowercased()
    let globalProjectEnvelope = StudyAgentContextEnvelope(
        request: StudyAgentRequest(
            purpose: .conversation,
            question: "解释当前材料",
            materialTitle: "当前材料",
            materialText: "",
            noteTitle: "笔记",
            noteText: "",
            courseContext: StudyAgentCourseContext(
                title: "当前课程",
                items: [
                    StudyAgentCourseItem(
                        id: "current-material",
                        title: "当前材料",
                        subtitle: "Markdown",
                        kind: "markdown",
                        role: "material"
                    ),
                ]
            ),
            projectScope: StudyAgentProjectScope(
                kind: .global,
                chatID: globalChatID,
                courseID: UUID().uuidString.lowercased(),
                rootPath: "/private/tmp/course-root",
                rootIdentity: projectIdentity,
                items: [
                    StudyAgentProjectItem(
                        itemID: "current-material",
                        title: "当前材料",
                        kind: "markdown",
                        role: "material",
                        relativePath: "文稿/current.md",
                        resolvedPath: "/private/tmp/course-root/文稿/current.md",
                        entryIdentity: projectIdentity,
                        targetIdentity: projectIdentity,
                        isShared: false,
                        courseIDs: ["course-id"],
                        sourceRevision: "revision-1"
                    ),
                ]
            ),
            contextRevision: "global-project-boundary"
        )
    )
    try piRequire(
        globalProjectEnvelope.project.kind == .global
            && globalProjectEnvelope.project.chatID == globalChatID
            && globalProjectEnvelope.project.rootPath == nil
            && globalProjectEnvelope.project.rootIdentity == nil
            && globalProjectEnvelope.project.items.first?.itemID == "course-item-1"
            && globalProjectEnvelope.project.items.first?.relativePath == ""
            && globalProjectEnvelope.project.items.first?.resolvedPath == ""
            && globalProjectEnvelope.project.items.first?.entryIdentity == nil
            && globalProjectEnvelope.project.items.first?.targetIdentity == nil
            && globalProjectEnvelope.project.items.first?.courseIDs == ["course-id"]
            && globalProjectEnvelope.project.items.first?.sourceRevision == "revision-1",
        "global Chat strips local course-file authorization while retaining the host-readable material identity"
    )

    let privatePath = "/Users/student/Private Course/secret.pdf"
    let privateItem = StudyAgentCourseItem(
        id: "file:\(privatePath)",
        title: "课程资料",
        subtitle: "secret.pdf",
        kind: "pdf",
        role: "material",
        searchText: "测试内容"
    )
    let privateEnvelope = StudyAgentContextEnvelope(
        request: StudyAgentRequest(
            purpose: .conversation,
            question: "解释",
            materialTitle: "课程资料",
            materialText: "测试内容",
            noteTitle: "笔记",
            noteText: "",
            courseContext: StudyAgentCourseContext(title: "课程", items: [privateItem]),
            learningContext: StudyAgentLearningContext(
                lastLocation: StudyLocation(itemID: "file:\(privatePath)", itemTitle: "课程资料")
            ),
            contextRevision: "private-path-test"
        )
    )
    let privateEnvelopeJSON = String(decoding: try JSONEncoder().encode(privateEnvelope), as: UTF8.self)
    try piRequire(
        !privateEnvelopeJSON.contains(privatePath)
            && privateEnvelope.course.catalog.first?.id == "course-item-1"
            && privateEnvelope.learning.lastLocation?.itemID == "course-item-1",
        "study-agent context never exposes imported absolute paths to PI"
    )

    let courseIndex = CourseKnowledgeIndex.build(
        title: "货币金融学",
        sources: [
            CourseKnowledgeSource(
                id: "rates",
                title: "利率",
                subtitle: "HTML",
                kind: "html",
                role: "material",
                text: "## 名义利率\n\n名义利率以货币单位表示。\n\n## 实际利率\n\n实际利率扣除通货膨胀影响。"
            ),
            CourseKnowledgeSource(
                id: "inflation-note",
                title: "通货膨胀笔记",
                subtitle: "Markdown",
                kind: "markdown",
                role: "note",
                text: "# 通货膨胀\n\n#购买力\n\n通货膨胀会影响实际利率和购买力。"
            ),
        ],
        links: [NoteSourceLink(noteItemID: "inflation-note", sourceItemID: "rates")],
        query: "通货膨胀和实际利率的关联",
        currentMaterialID: "rates",
        currentNoteID: "inflation-note"
    )
    try piRequire(courseIndex.catalog.count == 2 && courseIndex.items.count == 2 && courseIndex.relations.count == 1, "course index preserves materials, notes, and durable links")
    try piRequire(courseIndex.items.first(where: { $0.id == "inflation-note" })?.searchText.contains("实际利率") == true, "course index selects query-relevant knowledge excerpts")
    try piRequire(courseIndex.items.first(where: { $0.id == "inflation-note" })?.tags.contains("#购买力") == true, "course index exposes notebook tags")

    let largeCourseIndex = CourseKnowledgeIndex.build(
        title: "微观经济学",
        sources: (0..<100).map { index in
            CourseKnowledgeSource(
                id: "chapter-\(index)",
                title: "课程文件 \(index)",
                subtitle: "chapter-\(index).md",
                kind: "markdown",
                role: "material",
                text: index == 99 ? "边际替代率描述消费者愿意交换两种商品的比例。" : "一般课程内容 \(index)"
            )
        },
        links: [],
        query: "边际替代率在哪个文件？",
        currentMaterialID: nil,
        currentNoteID: nil
    )
    try piRequire(
        largeCourseIndex.catalog.count == 100
            && largeCourseIndex.items.count == 80
            && largeCourseIndex.items.contains(where: { $0.id == "chapter-99" }),
        "course index keeps every file name and ranks a relevant file beyond the first eighty into the search window"
    )

    let message = AgentMessage(
        role: .assistant,
        text: "PI answer",
        contentBlocks: [
            .text("先看变化。"),
            .visualization(AgentVisualization(
                id: "energy-flow",
                specJSON: #"{"items":[{"id":"energy","max":5,"min":0,"type":"slider","value":3}]}"#,
                stateJSON: #"{"value":3}"#
            )),
            .text("再比较结果。"),
        ],
        source: "材料",
        backend: .pi
    )
    let encoded = try JSONEncoder().encode(message)
    let decodedMessage = try JSONDecoder().decode(AgentMessage.self, from: encoded)
    try piRequire(
        decodedMessage.backend == .pi
            && decodedMessage.contentBlocks.count == 3
            && decodedMessage.contentBlocks[1] == .visualization(
                AgentVisualization(
                    id: "energy-flow",
                    specJSON: #"{"items":[{"id":"energy","max":5,"min":0,"type":"slider","value":3}]}"#,
                    stateJSON: #"{"value":3}"#
                )
            ),
        "agent backend and ordered Visualize blocks round-trip together"
    )
    var legacyObject = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] ?? [:]
    legacyObject.removeValue(forKey: "backend")
    let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
    let legacyMessage = try JSONDecoder().decode(AgentMessage.self, from: legacyData)
    try piRequire(
        legacyMessage.backend == nil,
        "legacy agent messages remain decodable without optional sidecar fields"
    )
    let sessionID = UUID()
    let persisted = PersistedWorkspace(
        noteSourceLinks: [NoteSourceLink(noteItemID: "inflation-note", sourceItemID: "rates")],
        studyLocationsByItemID: [
            "rates": StudyLocation(
                itemID: "rates",
                itemTitle: "利率",
                locationID: "section-real-rate",
                locationTitle: "实际利率",
                pageIndex: 3
            ),
        ],
        learningMemoryEntries: [
            LearningMemoryEntry(
                kind: .confusion,
                text: "还不熟悉费雪方程",
                evidence: "[用户：本轮] 用户明确说不熟悉",
                origin: .userStatement,
                status: .resolved,
                sessionID: sessionID,
                resolvedAt: Date(timeIntervalSinceReferenceDate: 200),
                resolutionEvidence: "[会话：当前] 用户已正确解释"
            ),
        ],
        learningMemoryRevision: 4,
        studySessions: [
            StudySession(
                id: sessionID,
                title: "实际利率",
                messages: [message],
                summary: "学到实际利率。",
                focusItemIDs: ["rates"],
                flow: StudyFlowState(phase: .recall, suggestedNext: ["练习费雪方程"])
            ),
        ],
        activeStudySessionID: sessionID
    )
    let persistedData = try JSONEncoder().encode(persisted)
    let decodedPersisted = try JSONDecoder().decode(PersistedWorkspace.self, from: persistedData)
    try piRequire(
        decodedPersisted.noteSourceLinks?.count == 1
            && decodedPersisted.studyLocationsByItemID?["rates"]?.pageIndex == 3
            && decodedPersisted.studyLocationsByItemID?["rates"]?.locationID == "section-real-rate"
            && decodedPersisted.learningMemoryEntries?.first?.sessionID == sessionID
            && decodedPersisted.learningMemoryEntries?.first?.status == .resolved
            && decodedPersisted.learningMemoryEntries?.first?.resolutionEvidence?.hasPrefix("[会话：当前]") == true
            && decodedPersisted.learningMemoryRevision == 4
            && decodedPersisted.studySessions?.first?.flow.phase == .recall
            && decodedPersisted.activeStudySessionID == sessionID,
        "course links, progress, learning memory, and sessions round-trip through workspace persistence"
    )
    let legacyWorkspaceData = Data(#"{"importedItems":[],"notesByItemID":{}}"#.utf8)
    let legacyWorkspace = try JSONDecoder().decode(PersistedWorkspace.self, from: legacyWorkspaceData)
    try piRequire(
        legacyWorkspace.noteSourceLinks == nil
            && legacyWorkspace.studyLocationsByItemID == nil
            && legacyWorkspace.learningMemoryEntries == nil
            && legacyWorkspace.studySessions == nil,
        "legacy workspaces remain decodable without course-learning state"
    )


    let diagnostic = PiAgentDiagnosticSanitizer.sanitize(
        #"Authorization: Bearer abcdefghijklmnop api_key="sk-sensitive-token""#
    )
    try piRequire(
        diagnostic.contains("[REDACTED]")
            && !diagnostic.contains("abcdefghijklmnop")
            && !diagnostic.contains("sk-sensitive-token"),
        "PI diagnostics redact provider credentials before reaching logs or UI"
    )
}


private func checkPiExecutableLocation() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent("weibei-pi-locator-\(UUID().uuidString)", isDirectory: true)
    defer { try? fileManager.removeItem(at: root) }

    func makeExecutable(_ url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    let bundleURL = root.appendingPathComponent("WeiBei.app", isDirectory: true)
    let runtimeURL = bundleURL.appendingPathComponent("Contents/Resources/PiRuntime", isDirectory: true)
    let executableURL = runtimeURL.appendingPathComponent("bin/pi")
    try makeExecutable(executableURL)

    try piRequire(
        PiExecutableLocator.locate(
            bundleURL: bundleURL,
            fileManager: fileManager,
            validator: { candidate, _ in candidate.standardizedFileURL == executableURL.standardizedFileURL }
        )?.standardizedFileURL == executableURL.standardizedFileURL,
        "PI executable locator resolves the app-bundled runtime path"
    )
    try piRequire(
        PiExecutableLocator.locate(bundleURL: bundleURL, fileManager: fileManager) == nil,
        "PI executable locator rejects a bundled runtime that fails integrity validation"
    )

    let externalPi = root.appendingPathComponent(".nvm/versions/node/v24.13.0/bin/pi")
    try makeExecutable(externalPi)
    let emptyBundle = root.appendingPathComponent("Empty.app", isDirectory: true)
    try piRequire(
        PiExecutableLocator.locate(
            bundleURL: emptyBundle,
            fileManager: fileManager,
            validator: { _, _ in true }
        ) == nil,
        "PI executable locator never falls back to a user-installed runtime"
    )

    let preparedRuntime = ProcessInfo.processInfo.environment["WEIBEI_PI_EXECUTABLE"]?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !preparedRuntime.isEmpty {
        let manifest = try PiBundledRuntime.validate(executableURL: URL(fileURLWithPath: preparedRuntime))
        try piRequire(manifest.piVersion == PiBundledRuntime.requiredVersion, "PI runtime validation pins binary integrity and version")
    }
}

private enum PiAgentSelfCheckError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case let .failed(message): message
        }
    }
}
