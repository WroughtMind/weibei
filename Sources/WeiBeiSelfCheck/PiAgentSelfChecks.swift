import Foundation
import WeiBeiCore

func runPiAgentSelfChecks() throws {
    try checkPiProviderConfiguration()
    try checkJSONLFraming()
    try checkAnswerGrounding()
    try checkRPCDecoding()
    try checkStudyAgentContext()
    try checkBundledAgentResources()
    try checkPiExecutableLocation()
}

private func checkAnswerGrounding() throws {
    for question in [
        "给我讲一个笑话",
        "你叫什么",
        "你好",
        "连通测试：只回复“Pi订阅登录已连通”，不要生成富回答。",
        "2026-07-21 候选包连通测试：只回复“Pi订阅登录已连通”，不要生成富回答。",
    ] {
        try piRequire(
            StudyAgentQuestionScope.allowsSourceFreeAnswer(question),
            "source-free PI answer scope accepts \(question)"
        )
        try piRequire(
            PiAnswerEvidenceRequirement.validationError(
                contentLabels: [],
                learningLabels: [],
                allowsLearningOnlyAnswer: false,
                allowsSourceFreeAnswer: true
            ) == nil,
            "source-free PI answers are not rejected as missing course evidence"
        )
    }

    try piRequire(
        !StudyAgentQuestionScope.allowsSourceFreeAnswer("费雪方程是什么意思？"),
        "course-content questions do not bypass current-turn evidence"
    )
    for question in [
        "你叫什么，顺便解释费雪方程",
        "讲一个关于费雪方程的笑话",
        "你是谁写的这本教材？",
        "连通测试，顺便解释费雪方程",
        "2026-07-21 候选包连通测试，顺便解释费雪方程",
    ] {
        try piRequire(
            !StudyAgentQuestionScope.allowsSourceFreeAnswer(question),
            "mixed or course-dependent questions do not bypass evidence: \(question)"
        )
    }
    try piRequire(
        PiAnswerEvidenceRequirement.validationError(
            contentLabels: [],
            learningLabels: [],
            allowsLearningOnlyAnswer: false,
            allowsSourceFreeAnswer: false
        ) == "PI returned a content answer without a current-turn source citation",
        "course-content answers still require current-turn evidence"
    )
    try piRequire(
        PiAnswerEvidenceRequirement.validationError(
            contentLabels: [],
            learningLabels: ["[学习记录：上次位置]"],
            allowsLearningOnlyAnswer: true,
            allowsSourceFreeAnswer: false
        ) == nil,
        "learning-only answers continue to accept current-turn learning evidence"
    )
}

private func checkPiProviderConfiguration() throws {
    let inherited = PiAgentProviderConfiguration()
    try piRequire(
        inherited.provider == nil && inherited.model == nil && inherited.apiKey == nil && inherited.thinkingLevel == "medium",
        "PI provider defaults keep the current medium thinking level without injecting API-key overrides"
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

private func checkJSONLFraming() throws {
    let delta = "中文跨字节\u{2028}仍在同一条 JSON 记录"
    let first = #"{"type":"message_update","assistantMessageEvent":{"type":"text_delta","delta":"中文跨字节 仍在同一条 JSON 记录"}}"#
    let second = #"{"type":"tool_execution_start","toolCallId":"tool-1","toolName":"weibei_context"}"#
    var framer = PiJSONLFramer()
    var records: [Data] = []
    for byte in Data("\(first)\r\n\(second)\n".utf8) {
        records.append(contentsOf: try framer.append(Data([byte])))
    }
    _ = try framer.finish()
    try piRequire(records.count == 2, "PI JSONL keeps CRLF compatibility and emits two records")
    try piRequire(PiRPCMessageDecoder.decode(records[0]) == .textDelta(delta), "PI JSONL preserves split UTF-8 and U+2028")
    try piRequire(PiRPCMessageDecoder.decode(records[1]) == .toolStarted(id: "tool-1", name: "weibei_context"), "PI JSONL preserves tool ids")

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
    let state = try PiRPCMessageDecoder.decode(Data(#"{"id":"state-1","type":"response","command":"get_state","success":true,"data":{"isStreaming":false}}"#.utf8))
    guard case let .response(response) = state else {
        throw PiAgentSelfCheckError.failed("PI get_state response did not decode")
    }
    try piRequire(response.id == "state-1" && response.command == "get_state" && response.success && response.dataJSON != nil, "PI get_state keeps correlation and data")

    let rejection = try PiRPCMessageDecoder.decode(Data(#"{"id":"prompt-1","type":"response","command":"prompt","success":false,"error":"busy"}"#.utf8))
    try piRequire(rejection == .response(PiRPCResponse(id: "prompt-1", command: "prompt", success: false, error: "busy")), "PI rejected commands keep their errors")

    let failedTool = try PiRPCMessageDecoder.decode(Data(#"{"type":"tool_execution_end","toolCallId":"tool-2","toolName":"weibei_context","isError":true,"result":{"content":[{"type":"text","text":"stale context"}]}}"#.utf8))
    try piRequire(failedTool == .toolFailed(id: "tool-2", name: "weibei_context", message: "stale context"), "PI tool failures keep ids and messages")

    let contextRead = try PiRPCMessageDecoder.decode(Data(#"{"type":"tool_execution_end","toolCallId":"tool-context","toolName":"weibei_context","isError":false,"result":{"details":{"kind":"weibei_context","contextRevision":"revision-7"}}}"#.utf8))
    try piRequire(contextRead == .contextRead(id: "tool-context", contextRevision: "revision-7"), "PI context reads preserve the validated revision")

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

    let skillRead = try PiRPCMessageDecoder.decode(Data(#"{"type":"tool_execution_end","toolCallId":"tool-skill","toolName":"read","isError":false,"result":{"details":{"kind":"weibei_skill_read","contextRevision":"revision-7","loaded":{"id":"rich-answer-director","name":"富回答导演","version":"1.0.0","sha256":"abc123","byteCount":1524,"relativePath":"skills/rich-answer/rich-answer-director/SKILL.md","loadedAtContextRevision":"revision-7"}}}}"#.utf8))
    try piRequire(
        skillRead == .skillsLoaded(
            id: "tool-skill",
            contextRevision: "revision-7",
            skills: [
                StudyAgentLoadedSkill(
                    id: "rich-answer-director",
                    name: "富回答导演",
                    version: "1.0.0",
                    sha256: "abc123",
                    byteCount: 1524,
                    relativePath: "skills/rich-answer/rich-answer-director/SKILL.md",
                    loadedAtContextRevision: "revision-7"
                ),
            ]
        ),
        "PI native skill reads preserve versioned evidence metadata"
    )

    let artifactComputed = try PiRPCMessageDecoder.decode(Data(#"{"type":"tool_execution_end","toolCallId":"tool-python","toolName":"weibei_compute_artifact","isError":false,"result":{"details":{"kind":"compute_artifact","schemaVersion":1,"contextRevision":"revision-7","requestID":"stats-1","operation":"compute_statistics","workerVersion":"1.0.0","requestSHA256":"request-hash","outputSHA256":"output-hash","durationMS":23,"artifacts":[{"sha256":"artifact-hash"}]}}}"#.utf8))
    try piRequire(
        artifactComputed == .artifactComputed(
            id: "tool-python",
            contextRevision: "revision-7",
            requestID: "stats-1",
            operation: "compute_statistics",
            workerVersion: "1.0.0",
            requestSHA256: "request-hash",
            outputSHA256: "output-hash",
            artifactSHA256s: ["artifact-hash"],
            durationMS: 23
        ),
        "PI controlled Python results preserve operation, hashes, source run, and duration evidence"
    )

    let courseRead = try PiRPCMessageDecoder.decode(Data(#"{"type":"tool_execution_end","toolCallId":"tool-course","toolName":"weibei_course_search","isError":false,"result":{"details":{"kind":"course_search","contextRevision":"revision-7","results":[{"id":"material-rates","title":"利率","role":"material","searchText":"利率正文"},{"id":"note-rates","title":"课堂笔记","role":"note","searchText":"笔记正文"},{"id":"title-only","title":"只有标题","role":"material","searchText":""}],"evidenceLabels":["[材料：利率，条目：2]","[笔记：课堂笔记]"],"jumpEvidence":{"来源：利率，条目：2，第 3 页":"[材料：利率，条目：2]"}}}}"#.utf8))
    try piRequire(
        courseRead == .courseSourcesRead(
            id: "tool-course",
            contextRevision: "revision-7",
            labels: ["[材料：利率，条目：2]", "[笔记：课堂笔记]"],
            assetIDs: ["material-rates", "note-rates"],
            jumpEvidence: ["来源：利率，条目：2，第 3 页": "[材料：利率，条目：2]"]
        ),
        "PI course tools expose only labels backed by non-empty source excerpts read this turn"
    )
    let mapRead = try PiRPCMessageDecoder.decode(Data(#"{"type":"tool_execution_end","toolCallId":"tool-map","toolName":"weibei_course_map","isError":false,"result":{"details":{"kind":"course_map","catalog":[{"title":"只有目录标题","role":"material"}]}}}"#.utf8))
    try piRequire(
        mapRead == .event("tool_execution_end"),
        "PI course-map metadata does not unlock a material as content evidence"
    )

    let memoryRead = try PiRPCMessageDecoder.decode(Data(#"{"type":"tool_execution_end","toolCallId":"tool-learning","toolName":"weibei_learning_memory","isError":false,"result":{"details":{"kind":"learning_memory","contextRevision":"revision-7","memoryRevision":4,"learning":{"memories":[]},"jumpEvidence":{}}}}"#.utf8))
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

    let richAnswerData = try JSONSerialization.data(withJSONObject: [
        "type": "tool_execution_end",
        "toolCallId": "tool-rich",
        "toolName": "weibei_rich_answer",
        "isError": false,
        "result": [
            "details": [
                "kind": "rich_answer",
                "contextRevision": "revision-7",
                "envelope": [
                    "schemaVersion": 2,
                    "contextRevision": "revision-7",
                    "narrative": "利率关系说明",
                    "expressionPlan": [
                        "action": "explain",
                        "summary": "解释利率关系",
                        "families": ["quantityAndCoordinates"],
                        "preferredSurface": "inline",
                        "directManipulation": false,
                    ],
                    "scenes": [],
                    "evidenceLedger": [],
                    "fallback": ["text": "利率关系说明", "reason": "文本回退"],
                ],
            ],
        ],
    ])
    let richAnswer = try PiRPCMessageDecoder.decode(richAnswerData)
    guard case let .richAnswer(id, envelopeData) = richAnswer,
          let envelope = try JSONSerialization.jsonObject(with: envelopeData) as? [String: Any] else {
        throw PiAgentSelfCheckError.failed("PI rich-answer tool result did not decode")
    }
    try piRequire(
        id == "tool-rich"
            && envelope["contextRevision"] as? String == "revision-7"
            && envelope["schemaVersion"] as? Int == 2,
        "PI rich-answer results preserve their isolated semantic envelope"
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

    let learningData = try JSONSerialization.data(withJSONObject: [
        "type": "tool_execution_end",
        "toolCallId": "tool-memory",
        "toolName": "weibei_learning_update",
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
                        "kind": "confusion",
                        "text": "还不熟悉费雪方程",
                        "evidence": "[用户：本轮] 用户明确说不熟悉",
                        "origin": "userStatement",
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
                        kind: .confusion,
                        text: "还不熟悉费雪方程",
                        evidence: "[用户：本轮] 用户明确说不熟悉",
                        origin: .userStatement
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
    let recentMessages = (0..<24).map { index in
        AgentMessage(role: index.isMultiple(of: 2) ? .user : .assistant, text: "message-\(index)" + String(repeating: "字", count: 1_300), source: "source-\(index)")
    }
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
    let learningMemories = (0..<60).map { index in
        LearningMemoryEntry(
            kind: index.isMultiple(of: 2) ? .confusion : .nextStep,
            text: "memory-\(index)" + String(repeating: "学", count: 520),
            evidence: "[用户：本轮] evidence-\(index)" + String(repeating: "据", count: 420),
            origin: .userStatement,
            updatedAt: Date(timeIntervalSinceReferenceDate: TimeInterval(index))
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
        recentMessages: recentMessages,
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
    try piRequire(request.resolvedWorkflow == .recallPractice, "study-agent automatic routing selects recall practice")
    try piRequire(
        StudyAgentSourceLimitation.isHonest("当前没有可读材料或数据，因此无法给出剂量结论。")
            && StudyAgentSourceLimitation.isHonest("No readable source data was provided, so I cannot calculate a dose.")
            && !StudyAgentSourceLimitation.isHonest("我不能回答这个问题。")
            && !StudyAgentSourceLimitation.isHonest("材料显示安全剂量为 10 mg。")
            && !StudyAgentSourceLimitation.isHonest("当前缺少材料，所以我估计安全剂量约为 10 mg。"),
        "source-free answers are limited to explicit evidence-gap explanations"
    )
    let noteRequest = StudyAgentRequest(
        purpose: .conversation,
        question: "整理成笔记",
        materialTitle: "材料",
        materialText: "正文",
        noteTitle: "笔记",
        noteText: "",
        contextRevision: "revision-10"
    )
    try piRequire(noteRequest.resolvedWorkflow == .noteMaking, "study-agent automatic routing selects note making")
    let wayfindingRequest = StudyAgentRequest(
        purpose: .conversation,
        question: "这个概念和课程里哪本书相关？",
        materialTitle: "材料",
        materialText: "正文",
        noteTitle: "笔记",
        noteText: "",
        contextRevision: "revision-wayfinding"
    )
    try piRequire(wayfindingRequest.resolvedWorkflow == .courseWayfinding, "study-agent automatic routing selects course wayfinding")
    let companionRequest = StudyAgentRequest(
        purpose: .conversation,
        question: "我上次学到哪了？",
        materialTitle: "材料",
        materialText: "正文",
        noteTitle: "笔记",
        noteText: "",
        contextRevision: "revision-companion"
    )
    try piRequire(companionRequest.resolvedWorkflow == .studyCompanion, "study-agent automatic routing selects the study companion")
    try piRequire(
        StudyAgentQuestionScope.allowsLearningOnlyAnswer("我上次学到哪了？请告诉我位置和下一步。")
            && StudyAgentQuestionScope.allowsLearningOnlyAnswer("我的学习目标是什么？")
            && !StudyAgentQuestionScope.allowsLearningOnlyAnswer("继续学习")
            && !StudyAgentQuestionScope.allowsLearningOnlyAnswer("continue learning")
            && !StudyAgentQuestionScope.allowsLearningOnlyAnswer("我上次学到的费雪方程怎么算？")
            && !StudyAgentQuestionScope.allowsLearningOnlyAnswer("我的困惑是名义利率；请解释它和实际利率的区别。"),
        "learning-only answers are limited to structured progress and memory questions, not course-content questions that mention prior study"
    )
    try piRequire(
        StudyAgentCurrentTurnEvidence.matches(
            "[用户：本轮]我还不懂名义利率和实际利率的区别",
            question: "上次学到哪？我还不懂名义利率和实际利率的区别，请记住。"
        )
            && StudyAgentCurrentTurnEvidence.matches(
                "[用户：本轮]I like reasoning from first principles",
                question: "I do not like rote memorization, I like reasoning from first principles."
            )
            && !StudyAgentCurrentTurnEvidence.matches(
                "[用户：本轮]喜欢死记硬背",
                question: "我不喜欢死记硬背"
            )
            && !StudyAgentCurrentTurnEvidence.matches(
                "[用户：本轮]喜欢死记硬背",
                question: "我不太喜欢死记硬背"
            )
            && !StudyAgentCurrentTurnEvidence.matches(
                "[用户：本轮]like rote memorization",
                question: "I do not like rote memorization"
            ),
        "current-turn memory evidence requires a bounded verbatim clause and cannot omit leading negation"
    )
    try piRequire(
        !StudyAgentResolutionEvidence.matches(
            "[用户：本轮]我还不能够区分名义利率和实际利率",
            question: "我还不能够区分名义利率和实际利率"
        )
            && !StudyAgentResolutionEvidence.matches(
                "[用户：本轮]I am not yet able to distinguish nominal and real rates",
                question: "I am not yet able to distinguish nominal and real rates"
            )
            && !StudyAgentResolutionEvidence.matches(
                "[用户：本轮]这个答案不正确",
                question: "这个答案不正确"
            )
            && !StudyAgentResolutionEvidence.matches(
                "[用户：本轮]This answer is not correct",
                question: "This answer is not correct"
            )
            && StudyAgentResolutionEvidence.matches(
                "[用户：本轮]我已经能够区分名义利率和实际利率了",
                question: "我已经能够区分名义利率和实际利率了"
            ),
        "learning-memory resolution rejects negated mastery phrases before accepting explicit mastery"
    )
    let quietRequest = StudyAgentRequest(
        purpose: .quietInsight,
        question: "出题",
        materialTitle: "材料",
        materialText: "正文",
        noteTitle: "笔记",
        noteText: "",
        contextRevision: "revision-11"
    )
    try piRequire(quietRequest.resolvedWorkflow == .closeReading, "quiet insight stays on close reading")

    let envelope = StudyAgentContextEnvelope(request: request)
    try piRequire(envelope.schemaVersion == 2 && envelope.contextRevision == "revision-9", "study-agent context carries schema and revision")
    try piRequire(envelope.workflow == StudyAgentWorkflow.recallPractice.rawValue, "study-agent context carries resolved workflow")
    try piRequire(envelope.answerFormPolicy == StudyAgentAnswerFormPolicy.textOnly.rawValue, "study-agent context carries structured answer-form policy")
    try piRequire(envelope.material?.text.count == 18_000 && envelope.note.text.count == 6_000 && envelope.selection?.text.count == 2_000, "study-agent context applies source limits")
    try piRequire(envelope.material?.title.count == 300 && envelope.note.title.count == 300 && envelope.selection?.title.count == 300, "study-agent context bounds source labels consistently")
    try piRequire(envelope.material?.isTruncated == true && envelope.note.isTruncated && envelope.selection?.isTruncated == true, "study-agent context marks every truncated source")
    try piRequire(envelope.recentMessages.count == 20 && envelope.recentMessages.first?.text.hasPrefix("message-4") == true, "study-agent context keeps the latest twenty messages")
    try piRequire(envelope.recentMessages.allSatisfy { $0.text.count <= 1_200 }, "study-agent context bounds recent messages")
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
    try piRequire(envelope.learning.memoryRevision == 7 && envelope.learning.memories.count == 48, "study-agent context carries a bounded learning-memory revision")
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

    let richEnvelope = RichAnswerEnvelope(
        contextRevision: "message-revision",
        narrative: "PI answer",
        expressionPlan: RichAnswerExpressionPlan(
            action: .explain,
            summary: "对齐材料与解释",
            families: [.textAndAlignment],
            preferredSurface: .inline,
            directManipulation: true
        ),
        scenes: [
            RichAnswerScene(
                id: "message-scene",
                title: "材料解释",
                family: .textAndAlignment,
                objects: [RichAnswerObject(id: "message-claim", kind: .text, label: "结论", text: "PI answer")],
                operations: [
                    RichAnswerOperation(
                        id: "message-select",
                        kind: .select,
                        label: "选择解释",
                        targetIDs: ["message-claim"]
                    ),
                ],
                evidenceIDs: ["message-evidence"]
            ),
        ],
        evidenceLedger: [
            RichAnswerEvidence(id: "message-evidence", sourceLabel: "[材料：材料]", excerpt: "PI answer"),
        ],
        fallback: RichAnswerFallback(text: "PI answer", reason: "scene unavailable")
    )
    let richPresentation = RichAnswerEngine.prepare(
        envelope: richEnvelope,
        environment: RichAnswerEnvironment(
            contextRevision: "message-revision",
            allowedSourceLabels: ["[材料：材料]"]
        )
    )
    let message = AgentMessage(
        role: .assistant,
        text: "PI answer",
        source: "材料",
        backend: .pi,
        richAnswer: richPresentation
    )
    let encoded = try JSONEncoder().encode(message)
    let decodedMessage = try JSONDecoder().decode(AgentMessage.self, from: encoded)
    try piRequire(
        decodedMessage.backend == .pi
            && decodedMessage.richAnswer?.mode == .rich
            && decodedMessage.richAnswer?.scenes.first?.id == "message-scene",
        "agent backend and validated rich-answer sidecar round-trip together"
    )
    var legacyObject = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] ?? [:]
    legacyObject.removeValue(forKey: "backend")
    legacyObject.removeValue(forKey: "richAnswer")
    let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
    let legacyMessage = try JSONDecoder().decode(AgentMessage.self, from: legacyData)
    try piRequire(
        legacyMessage.backend == nil && legacyMessage.richAnswer == nil,
        "legacy agent messages remain decodable without rich-answer sidecars"
    )
    var malformedSidecarObject = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] ?? [:]
    malformedSidecarObject["richAnswer"] = ["mode": "future-unsupported-mode"]
    let malformedSidecarData = try JSONSerialization.data(withJSONObject: malformedSidecarObject)
    let messageWithMalformedSidecar = try JSONDecoder().decode(AgentMessage.self, from: malformedSidecarData)
    try piRequire(
        messageWithMalformedSidecar.id == message.id
            && messageWithMalformedSidecar.text == message.text
            && messageWithMalformedSidecar.backend == .pi
            && messageWithMalformedSidecar.richAnswer == nil,
        "a malformed rich-answer sidecar is discarded without losing the durable conversation message"
    )
    try piRequire(
        StudyAgentRichAnswerRequest.isExplicit("请用可调的富回答解释这个函数")
            && StudyAgentRichAnswerRequest.isExplicit("请用图示解释这段关系")
            && StudyAgentRichAnswerRequest.isExplicit("请基于材料做个实验")
            && StudyAgentRichAnswerRequest.isExplicit("Show this as an interactive timeline")
            && StudyAgentRichAnswerRequest.isExplicit("Explain this with a diagram")
            && StudyAgentRichAnswerRequest.isExplicit("Run an experiment from the source")
            && !StudyAgentRichAnswerRequest.isExplicit("自行选择最合适的回答形态；只有交互显著提高理解时才生成富回答")
            && !StudyAgentRichAnswerRequest.isExplicit("直接解释这段材料"),
        "explicit rich-answer requests are detected without forcing ordinary questions into rich mode"
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

    try piRequire(PiAgentRuntimeError.unavailable.permitsAutomaticFallback, "PI startup failures may use the existing fallback")
    try piRequire(!PiAgentRuntimeError.agentFailed("model error").permitsAutomaticFallback, "accepted PI runs are never replayed automatically")
    try piRequire(!PiAgentRuntimeError.commandTimedOut("prompt").permitsAutomaticFallback, "unknown prompt acceptance is never replayed automatically")

    let diagnostic = PiAgentDiagnosticSanitizer.sanitize(
        #"Authorization: Bearer abcdefghijklmnop api_key="sk-sensitive-token""#,
        secret: "sk-sensitive-token"
    )
    try piRequire(
        diagnostic.contains("[REDACTED]")
            && !diagnostic.contains("abcdefghijklmnop")
            && !diagnostic.contains("sk-sensitive-token"),
        "PI diagnostics redact provider credentials before reaching logs or UI"
    )
}

private func checkBundledAgentResources() throws {
    let resources = try PiAgentResources.bundled()
    try piRequire(resources.systemPrompt.contains("魏碑拥有材料、选区、笔记"), "PI system contract is bundled")
    try piRequire(resources.systemPrompt.contains("课程地图") && resources.systemPrompt.contains("学习记忆与会话"), "PI system contract separates course evidence from learning memory")

    for skillName in PiAgentResources.requiredSkillNames {
        let skillURL = resources.skillsURL.appendingPathComponent(skillName).appendingPathComponent("SKILL.md")
        let source = try String(contentsOf: skillURL, encoding: .utf8)
        try piRequire(source.contains("name: \(skillName)") && source.contains("description:"), "PI skill \(skillName) has valid frontmatter")
        if source.contains("weibei_rich_answer") {
            try piRequire(
                source.contains("allowed-tools:")
                    && source.contains("weibei_ui_catalog")
                    && source.contains("weibei_compute_artifact")
                    && source.contains("weibei_visual_asset"),
                "PI skill \(skillName) authorizes the catalog, current-material visual inspection, and optional controlled computation before rich answers"
            )
        }
    }

    for skillName in PiAgentResources.requiredRichAnswerSkillNames {
        let skillURL = resources.skillsURL
            .appendingPathComponent("rich-answer", isDirectory: true)
            .appendingPathComponent(skillName, isDirectory: true)
            .appendingPathComponent("SKILL.md")
        let source = try String(contentsOf: skillURL, encoding: .utf8)
        try piRequire(
            source.contains("name: \(skillName)") && source.contains("description:") && source.contains("version:"),
            "PI rich-answer subskill \(skillName) has progressive-disclosure metadata"
        )
    }

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
