import Foundation
import WeiBeiCore

func runPiAgentSelfChecks() async throws {
    try checkJSONLFraming()
    try checkRPCDecoding()
    try checkStudyAgentContext()
    try checkAnswerGrounding()
    try checkBundledAgentResources()
    try checkPiExecutableLocation()
    try await checkPiRunCancellationControl()
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

private func checkAnswerGrounding() throws {
    for question in ["给我讲一个笑话", "你叫什么"] {
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
        ) == "PI 返回了课程内容，但没有标注本轮读取的来源",
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

    let courseRead = try PiRPCMessageDecoder.decode(Data(#"{"type":"tool_execution_end","toolCallId":"tool-course","toolName":"weibei_course_search","isError":false,"result":{"details":{"kind":"course_search","contextRevision":"revision-7","results":[{"title":"利率","role":"material","searchText":"利率正文"},{"title":"课堂笔记","role":"note","searchText":"笔记正文"},{"title":"只有标题","role":"material","searchText":""}],"evidenceLabels":["[材料：利率，条目：2]","[笔记：课堂笔记]"],"jumpEvidence":{"来源：利率，条目：2，第 3 页":"[材料：利率，条目：2]"}}}}"#.utf8))
    try piRequire(
        courseRead == .courseSourcesRead(
            id: "tool-course",
            contextRevision: "revision-7",
            labels: ["[材料：利率，条目：2]", "[笔记：课堂笔记]"],
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

    let ended = try PiRPCMessageDecoder.decode(Data(#"{"type":"agent_end","messages":[{"role":"assistant","content":[{"type":"text","text":"第一轮"}],"stopReason":"toolUse"},{"role":"assistant","content":[{"type":"text","text":"最终回答"}],"stopReason":"stop"}]}"#.utf8))
    try piRequire(ended == .agentEnded(text: "最终回答", stopReason: "stop", error: nil), "PI agent_end selects the final assistant answer")

    let providerFailure = try PiRPCMessageDecoder.decode(Data(#"{"type":"agent_end","messages":[{"role":"assistant","content":[],"provider":"openai-codex","model":"gpt-5.5","stopReason":"error","diagnostics":[{"type":"provider_transport_failure","error":{"message":"WebSocket failed to connect"}}],"errorMessage":"Was there a typo in the url or port?"}],"willRetry":false}"#.utf8))
    try piRequire(
        providerFailure == .agentEnded(
            text: "",
            stopReason: "error",
            error: "Was there a typo in the url or port?"
        ),
        "PI agent_end preserves the provider error instead of reporting an unknown model"
    )
    try piRequire(
        PiAgentRetryPolicy.shouldRetry(.agentFailed("Codex SSE response headers timed out after 20000ms")),
        "PI retries one bounded transient provider timeout"
    )
    try piRequire(
        PiAgentRetryPolicy.shouldRetry(.agentFailed("unknown certificate verification error")),
        "PI retries one bounded certificate-handshake failure without bypassing verification"
    )
    try piRequire(
        !PiAgentRetryPolicy.shouldRetry(.agentFailed("Unknown model gpt-missing")),
        "PI does not retry permanent model configuration errors"
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
    let interactions = (0..<16).map { index in
        StudyAgentInteractionEvent(
            blockID: "block-\(index)" + String(repeating: "b", count: 140),
            kind: "kind-\(index)" + String(repeating: "k", count: 90),
            action: "action-\(index)" + String(repeating: "a", count: 90),
            detail: "detail-\(index)" + String(repeating: "互", count: 1_300)
        )
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
        question: "请根据当前材料出题",
        materialTitle: String(repeating: "材", count: 320),
        materialText: String(repeating: "材", count: 18_100),
        noteTitle: String(repeating: "记", count: 320),
        noteText: String(repeating: "记", count: 6_100),
        selectionTitle: String(repeating: "选", count: 320),
        selectionText: String(repeating: "选", count: 2_100),
        recentMessages: recentMessages,
        interactions: interactions,
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
    let interactiveRequest = StudyAgentRequest(
        purpose: .conversation,
        question: "把这个概念做成可互动学习卡，先让我想再揭晓",
        materialTitle: "材料",
        materialText: "正文",
        noteTitle: "笔记",
        noteText: "",
        contextRevision: "revision-interactive"
    )
    try piRequire(interactiveRequest.resolvedWorkflow == .interactiveStudy, "study-agent automatic routing selects interactive study")
    let visualInteractiveRequest = StudyAgentRequest(
        purpose: .conversation,
        question: "用函数曲线和滑块调参展示这个关系，再补一个配色对照",
        materialTitle: "材料",
        materialText: "正文",
        noteTitle: "笔记",
        noteText: "",
        contextRevision: "revision-visual-interactive"
    )
    try piRequire(visualInteractiveRequest.resolvedWorkflow == .interactiveStudy, "study-agent routes charts, function plots, controls, comparisons, and palettes to interactive study")
    let proactiveChartRequest = StudyAgentRequest(
        purpose: .conversation,
        question: "这组数据的变化说明了什么？",
        materialTitle: "利率数据",
        materialText: "2022 年为 2.1%，2023 年为 3.4%，2024 年为 4.8%，呈连续上升。",
        noteTitle: "笔记",
        noteText: "",
        contextRevision: "revision-proactive-chart"
    )
    try piRequire(
        proactiveChartRequest.resolvedWorkflow == .interactiveStudy
            && proactiveChartRequest.richPresentationDecision.shape == .chart,
        "study-agent proactively selects a chart when the question and evidence are quantitative"
    )
    let proactiveRelationshipRequest = StudyAgentRequest(
        purpose: .conversation,
        question: "这个机制为什么会影响市场利率？",
        materialTitle: "利率传导",
        materialText: "准备金减少会导致银行可贷资金收缩，因此信贷供给下降，进而推动市场利率上升。",
        noteTitle: "笔记",
        noteText: "",
        contextRevision: "revision-proactive-relationship"
    )
    try piRequire(
        proactiveRelationshipRequest.resolvedWorkflow == .interactiveStudy
            && proactiveRelationshipRequest.richPresentationDecision.shape == .relationshipMap,
        "study-agent proactively selects a relationship map for evidence-backed causal explanations"
    )
    let proactiveTimelineRequest = StudyAgentRequest(
        purpose: .conversation,
        question: "这个过程先后经历了哪些阶段？",
        materialTitle: "政策过程",
        materialText: "第一步确认目标。第二步调整工具。随后观察市场反应。最后复盘结果。",
        noteTitle: "笔记",
        noteText: "",
        contextRevision: "revision-proactive-timeline"
    )
    try piRequire(
        proactiveTimelineRequest.resolvedWorkflow == .interactiveStudy
            && proactiveTimelineRequest.richPresentationDecision.shape == .timeline,
        "study-agent proactively selects a timeline for ordered evidence"
    )
    let proactiveComparisonRequest = StudyAgentRequest(
        purpose: .conversation,
        question: "名义利率和实际利率到底有什么区别？",
        materialTitle: "利率",
        materialText: "名义利率包含预期通胀，实际利率扣除预期通胀，二者用途不同。",
        noteTitle: "笔记",
        noteText: "",
        contextRevision: "revision-proactive-comparison"
    )
    try piRequire(
        proactiveComparisonRequest.resolvedWorkflow == .interactiveStudy
            && proactiveComparisonRequest.richPresentationDecision.shape == .comparisonMatrix,
        "study-agent proactively selects a comparison matrix for concept differences"
    )
    let proactiveAnnotationRequest = StudyAgentRequest(
        purpose: .conversation,
        question: "这段怎么理解？帮我抓住原文里的关键词。",
        materialTitle: "利率",
        materialText: "材料正文",
        noteTitle: "笔记",
        noteText: "",
        selectionTitle: "当前选区",
        selectionText: "名义利率包含预期通胀，而实际利率反映扣除预期通胀后的真实资金成本。这两个概念服务于不同的观察目标。",
        contextRevision: "revision-proactive-annotation"
    )
    try piRequire(
        proactiveAnnotationRequest.richPresentationDecision.shape == .annotatedPassage,
        "study-agent proactively selects inline annotations for a bounded close-reading selection"
    )
    let proactiveDerivationRequest = StudyAgentRequest(
        purpose: .conversation,
        question: "这个关系是怎么推导出来的？",
        materialTitle: "费雪关系",
        materialText: "名义利率约等于实际利率加预期通胀，因此移项后，实际利率约等于名义利率减去预期通胀。",
        noteTitle: "笔记",
        noteText: "",
        contextRevision: "revision-proactive-derivation"
    )
    try piRequire(
        proactiveDerivationRequest.richPresentationDecision.shape == .derivationSteps,
        "study-agent proactively selects progressive derivation for evidence-backed reasoning"
    )
    let proactiveEvidenceRequest = StudyAgentRequest(
        purpose: .conversation,
        question: "这个结论是否成立，证据够吗？",
        materialTitle: "论证",
        materialText: "材料表明实际利率扣除了预期通胀，因此更接近真实资金成本；但是当前片段缺少适用市场条件。",
        noteTitle: "笔记",
        noteText: "",
        contextRevision: "revision-proactive-evidence"
    )
    try piRequire(
        proactiveEvidenceRequest.richPresentationDecision.shape == .evidenceBoard,
        "study-agent proactively selects an evidence board when a claim has support and a gap"
    )
    let proactiveDecisionRequest = StudyAgentRequest(
        purpose: .conversation,
        question: "我应该选哪个指标，怎么判断？",
        materialTitle: "指标选择",
        materialText: "如果观察合约报价，那么看名义利率；如果观察真实资金成本，那么看实际利率，否则需要先确认观察目标。",
        noteTitle: "笔记",
        noteText: "",
        contextRevision: "revision-proactive-decision"
    )
    try piRequire(
        proactiveDecisionRequest.richPresentationDecision.shape == .decisionPath,
        "study-agent proactively selects a decision path for evidence-backed conditional choices"
    )
    let plainDefinitionRequest = StudyAgentRequest(
        purpose: .conversation,
        question: "这里的定义是什么意思？",
        materialTitle: "定义",
        materialText: "利率是资金跨期配置的价格。",
        noteTitle: "笔记",
        noteText: "",
        contextRevision: "revision-plain-definition"
    )
    try piRequire(
        plainDefinitionRequest.resolvedWorkflow == .studyCompanion
            && plainDefinitionRequest.richPresentationDecision.shape == nil,
        "study-agent keeps plain prose when no visual structure would improve the answer"
    )
    let noteMakingWithNumbersRequest = StudyAgentRequest(
        purpose: .conversation,
        question: "把这些数据整理成笔记",
        materialTitle: "利率数据",
        materialText: "2022 年 2.1%，2023 年 3.4%，2024 年 4.8%。",
        noteTitle: "笔记",
        noteText: "",
        contextRevision: "revision-note-over-visual"
    )
    try piRequire(
        noteMakingWithNumbersRequest.resolvedWorkflow == .noteMaking,
        "explicit note-making stays ahead of proactive rich presentation"
    )
    let mixedWayfindingRequest = StudyAgentRequest(
        purpose: .conversation,
        question: "这些文件怎么关联？给我看清知识关系",
        materialTitle: "当前材料",
        materialText: "当前材料解释名义利率。",
        noteTitle: "课堂笔记",
        noteText: "笔记记录实际利率。",
        courseContext: StudyAgentCourseContext(
            title: "利率课程",
            relations: [StudyAgentCourseRelation(noteItemID: "note-1", sourceItemID: "source-1")]
        ),
        contextRevision: "revision-wayfinding-rich"
    )
    try piRequire(
        mixedWayfindingRequest.resolvedWorkflow == .courseWayfinding
            && mixedWayfindingRequest.richPresentationDecision.shape == .relationshipMap,
        "course wayfinding keeps its evidence workflow while independently planning a relationship map"
    )
    let expandedInteractiveShapes: [(String, StudyAgentRichPresentationShape)] = [
        ("把这段原文做成可以逐条点开的夹批", .annotatedPassage),
        ("把这段论证做成一步一步揭晓的推导", .derivationSteps),
        ("把这些概念做成一组可以翻面的记忆卡", .flashcards),
        ("让我自己给这些步骤排序，然后检查", .sequenceBuilder),
        ("做一个情境实验，让我切换条件观察结果", .scenarioLab),
        ("把这个结论的支持证据、反例和缺口分开核验", .evidenceBoard),
        ("把这些观点放到一条连续光谱上让我点选", .spectrum),
        ("把这个选择做成可以逐步分支的决策路径", .decisionPath),
    ]
    for (question, expectedShape) in expandedInteractiveShapes {
        let request = StudyAgentRequest(
            purpose: .conversation,
            question: question,
            materialTitle: "材料",
            materialText: "材料包含足够的结构化证据。",
            noteTitle: "笔记",
            noteText: "",
            contextRevision: "revision-expanded-\(expectedShape.rawValue)"
        )
        try piRequire(
            request.resolvedWorkflow == .interactiveStudy
                && request.richPresentationDecision.shape == expectedShape,
            "study-agent routes \(expectedShape.rawValue) to the expanded interactive vocabulary"
        )
    }
    let allRichShapeRawValues = [
        StudyAgentRichPresentationShape.quiz,
        .reveal,
        .chart,
        .functionPlot,
        .parameterLab,
        .textStudy,
        .designCompare,
        .palette,
        .studyBoard,
        .relationshipMap,
        .timeline,
        .comparisonMatrix,
        .annotatedPassage,
        .derivationSteps,
        .flashcards,
        .sequenceBuilder,
        .scenarioLab,
        .evidenceBoard,
        .spectrum,
        .decisionPath,
        .unitWorkbench,
        .reactionBalance,
        .algorithmTrace,
        .languageAligner,
        .argumentMap,
        .visualAnalysis,
        .spatialLayers,
        .pathwayLab,
    ].map(\.rawValue)
    try piRequire(
        allRichShapeRawValues.count == 28 && Set(allRichShapeRawValues).count == 28,
        "study-agent rich answer vocabulary expands from twenty to twenty-eight unique kinds"
    )
    let crossDisciplinaryProtocolStrings: [(StudyAgentRichPresentationShape, String)] = [
        (
            .unitWorkbench,
            "unit-workbench: title, optional question, variables[{id,label,value(字符串),unit,optional role,source}], checks[{id,label,left,right,result,source}], sources"
        ),
        (
            .reactionBalance,
            "reaction-balance: title, species[{id,label,side reactant/product,coefficient 1...9,atoms 元素->单个分子原子数,source}], sources"
        ),
        (
            .algorithmTrace,
            "algorithm-trace: title, codeLines[string], steps[{lineIndex,summary,optional note,source}], sources"
        ),
        (
            .languageAligner,
            "language-aligner: title, pairs[{label,sourceText,targetText,note,source}], sources"
        ),
        (
            .argumentMap,
            "argument-map: title, optional question, nodes[{id,type premise/claim/objection/reply,label,optional detail,source}], edges[{from,to,optional label}], sources"
        ),
        (
            .visualAnalysis,
            "visual-analysis: title, zones[{id,label,x,y,width,height,note,tone,source}], optional palette[{label,role,tone}], optional lenses[{id,label,note,zoneIds}], sources"
        ),
        (
            .spatialLayers,
            "spatial-layers: title, layers[{id,label,visible}], features[{id,type point/route/region,layerId,label,note,points:[[x,y]...],source}], sources"
        ),
        (
            .pathwayLab,
            "pathway-lab: title, nodes[{id,label,detail,source}], states[{id,label,note,activeNodeIds,source}], edges[{from,to,label}], sources"
        ),
    ]
    for (shape, protocolString) in crossDisciplinaryProtocolStrings {
        try piRequire(
            StudyAgentRichPresentationDecision(shape: shape).promptHint?.contains(protocolString) == true,
            "study-agent runtime prompt hint exposes the editor-compatible \(shape.rawValue) protocol"
        )
    }
    let crossDisciplinaryShapes: [(String, StudyAgentRichPresentationShape)] = [
        ("把这些数值做成单位工作台，检查量纲", .unitWorkbench),
        ("把这个反应做成反应配平，检查原子守恒", .reactionBalance),
        ("把这个过程做成算法跟踪，手动跑一遍", .algorithmTrace),
        ("把这段做成语言对齐，中英对照术语", .languageAligner),
        ("把这段论证做成论证图，看前提和结论", .argumentMap),
        ("把这张图做成视觉分析", .visualAnalysis),
        ("把这个结构做成空间层次示意", .spatialLayers),
        ("做一个通路实验，让我切换状态", .pathwayLab),
    ]
    for (question, expectedShape) in crossDisciplinaryShapes {
        let request = StudyAgentRequest(
            purpose: .conversation,
            question: question,
            materialTitle: "材料",
            materialText: "材料包含足够的结构化证据。",
            noteTitle: "笔记",
            noteText: "",
            contextRevision: "revision-cross-\(expectedShape.rawValue)"
        )
        try piRequire(
            request.resolvedWorkflow == .interactiveStudy
                && request.richPresentationDecision.shape == expectedShape,
            "study-agent routes explicit \(expectedShape.rawValue) requests to the cross-disciplinary vocabulary"
        )
    }
    let proactiveCrossDisciplinaryRoutes: [(StudyAgentRequest, StudyAgentRichPresentationShape)] = [
        (
            StudyAgentRequest(
                purpose: .conversation,
                question: "这两个速度怎么换算并统一单位？",
                materialTitle: "物理量",
                materialText: "实验速度为 36 km/h，目标单位对应 10 m/s，需要做单位换算并检查单位。",
                noteTitle: "笔记",
                noteText: "",
                contextRevision: "revision-proactive-unit"
            ),
            .unitWorkbench
        ),
        (
            StudyAgentRequest(
                purpose: .conversation,
                question: "这个反应式怎么配平？",
                materialTitle: "化学反应",
                materialText: "H2 + O2 -> H2O。反应物和生成物需要按元素 H、O 做原子守恒检查，并确定系数。",
                noteTitle: "笔记",
                noteText: "",
                contextRevision: "revision-proactive-reaction"
            ),
            .reactionBalance
        ),
        (
            StudyAgentRequest(
                purpose: .conversation,
                question: "这个算法的状态变化怎么逐步运行？",
                materialTitle: "算法",
                materialText: "输入数组后，初始状态设置 low 和 high。步骤一比较 mid，循环迭代更新边界，最后输出索引。",
                noteTitle: "笔记",
                noteText: "",
                contextRevision: "revision-proactive-algorithm"
            ),
            .algorithmTrace
        ),
        (
            StudyAgentRequest(
                purpose: .conversation,
                question: "这段原文和译文的术语怎么对应？",
                materialTitle: "双语材料",
                materialText: "原文 real interest rate；译文 实际利率。术语 expected inflation 对应 预期通胀，语气保持教材表达。",
                noteTitle: "笔记",
                noteText: "",
                contextRevision: "revision-proactive-language"
            ),
            .languageAligner
        ),
        (
            StudyAgentRequest(
                purpose: .conversation,
                question: "这段论证的前提和结论是什么？",
                materialTitle: "论证",
                materialText: "结论是实际利率更适合衡量真实资金成本。前提是它扣除预期通胀，因为通胀会改变购买力；但是材料留下适用条件缺口。",
                noteTitle: "笔记",
                noteText: "",
                contextRevision: "revision-proactive-argument"
            ),
            .argumentMap
        ),
        (
            StudyAgentRequest(
                purpose: .conversation,
                question: "这张图做视觉分析，关键区域是什么？",
                materialTitle: "图像说明",
                materialText: "图像左侧区域标注输入端，右侧区域标注输出端，上方箭头表示流程方向，颜色用于区分两类模块。",
                noteTitle: "笔记",
                noteText: "",
                contextRevision: "revision-proactive-visual"
            ),
            .visualAnalysis
        ),
        (
            StudyAgentRequest(
                purpose: .conversation,
                question: "这个结构的空间层次怎么理解？",
                materialTitle: "结构说明",
                materialText: "外层包围内层，上方是入口，下方是出口，左侧和右侧分别是两个区域，中心层承载核心部件。",
                noteTitle: "笔记",
                noteText: "",
                contextRevision: "revision-proactive-spatial"
            ),
            .spatialLayers
        ),
        (
            StudyAgentRequest(
                purpose: .conversation,
                question: "这条信号通路激活或抑制后会怎样？",
                materialTitle: "通路",
                materialText: "通路有基准状态。上游激活会导致下游增强；上游抑制会导致下游减弱。状态转换只在这些已列状态之间发生。",
                noteTitle: "笔记",
                noteText: "",
                contextRevision: "revision-proactive-pathway"
            ),
            .pathwayLab
        ),
    ]
    for (request, expectedShape) in proactiveCrossDisciplinaryRoutes {
        try piRequire(
            request.resolvedWorkflow == .interactiveStudy
                && request.richPresentationDecision.shape == expectedShape,
            "study-agent proactively selects \(expectedShape.rawValue) when course evidence is sufficient"
        )
    }
    let visualURLRequest = StudyAgentRequest(
        purpose: .conversation,
        question: "对 https://example.com/image.png 做视觉分析",
        materialTitle: "图像说明",
        materialText: "图像左侧区域标注输入端，右侧区域标注输出端。",
        noteTitle: "笔记",
        noteText: "",
        contextRevision: "revision-visual-url-reject"
    )
    try piRequire(
        visualURLRequest.richPresentationDecision.shape != .visualAnalysis,
        "study-agent refuses visual-analysis routing for URL or HTML inputs"
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
    try piRequire(envelope.material?.text.count == 18_000 && envelope.note.text.count == 6_000 && envelope.selection?.text.count == 2_000, "study-agent context applies source limits")
    try piRequire(envelope.material?.title.count == 300 && envelope.note.title.count == 300 && envelope.selection?.title.count == 300, "study-agent context bounds source labels consistently")
    try piRequire(envelope.material?.isTruncated == true && envelope.note.isTruncated && envelope.selection?.isTruncated == true, "study-agent context marks every truncated source")
    try piRequire(envelope.recentMessages.count == 20 && envelope.recentMessages.first?.text.hasPrefix("message-4") == true, "study-agent context keeps the latest twenty messages")
    try piRequire(envelope.recentMessages.allSatisfy { $0.text.count <= 1_200 }, "study-agent context bounds recent messages")
    try piRequire(
        envelope.interactions.count == 12
            && envelope.interactions.first?.blockID.hasPrefix("block-4") == true
            && envelope.interactions.allSatisfy {
                $0.blockID.count <= 120 && $0.kind.count <= 80 && $0.action.count <= 80 && $0.detail.count <= 1_200
            },
        "study-agent context keeps only the latest bounded interactive actions"
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

    let message = AgentMessage(role: .assistant, text: "PI answer", source: "材料", backend: .pi)
    let encoded = try JSONEncoder().encode(message)
    try piRequire(try JSONDecoder().decode(AgentMessage.self, from: encoded).backend == .pi, "agent backend round-trips")
    var legacyObject = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] ?? [:]
    legacyObject.removeValue(forKey: "backend")
    let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
    try piRequire(try JSONDecoder().decode(AgentMessage.self, from: legacyData).backend == nil, "legacy agent messages remain decodable")

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
    try piRequire(resources.systemPrompt.contains("weibei-interactive"), "PI system contract exposes the safe interactive answer protocol")
    let crossDisciplinaryProtocolStrings = [
        "unit-workbench: title, optional question, variables[{id,label,value(字符串),unit,optional role,source}], checks[{id,label,left,right,result,source}], sources",
        "reaction-balance: title, species[{id,label,side reactant/product,coefficient 1...9,atoms 元素->单个分子原子数,source}], sources",
        "algorithm-trace: title, codeLines[string], steps[{lineIndex,summary,optional note,source}], sources",
        "language-aligner: title, pairs[{label,sourceText,targetText,note,source}], sources",
        "argument-map: title, optional question, nodes[{id,type premise/claim/objection/reply,label,optional detail,source}], edges[{from,to,optional label}], sources",
        "visual-analysis: title, zones[{id,label,x,y,width,height,note,tone,source}], optional palette[{label,role,tone}], optional lenses[{id,label,note,zoneIds}], sources",
        "spatial-layers: title, layers[{id,label,visible}], features[{id,type point/route/region,layerId,label,note,points:[[x,y]...],source}], sources",
        "pathway-lab: title, nodes[{id,label,detail,source}], states[{id,label,note,activeNodeIds,source}], edges[{from,to,label}], sources",
    ]
    try piRequire(
        crossDisciplinaryProtocolStrings.allSatisfy(resources.systemPrompt.contains),
        "PI system contract pins the editor-compatible cross-disciplinary interactive schemas"
    )
    try piRequire(
        [
            "quiz", "reveal", "chart", "function-plot", "parameter-lab", "text-study",
            "design-compare", "palette", "study-board", "relationship-map", "timeline", "comparison-matrix",
            "annotated-passage", "derivation-steps", "flashcards", "sequence-builder",
            "scenario-lab", "evidence-board", "spectrum", "decision-path",
            "unit-workbench", "reaction-balance", "algorithm-trace", "language-aligner",
            "argument-map", "visual-analysis", "spatial-layers", "pathway-lab",
        ].allSatisfy(resources.systemPrompt.contains),
        "PI system contract exposes the complete twenty-eight-kind interactive vocabulary"
    )
    try piRequire(resources.systemPrompt.contains("不得输出任意 HTML")
        && resources.systemPrompt.contains("不得输出任意 JavaScript"), "PI system contract keeps model-authored HTML and scripts outside the runtime")
    let extensionSource = try String(contentsOf: resources.extensionURL, encoding: .utf8)
    try piRequire(extensionSource.contains("before_agent_start") && extensionSource.contains("tool_call") && extensionSource.contains("pi.on(\"context\""), "PI extension bundles source, permission, and stale-context hooks")
    try piRequire(
        [
            "weibei_context",
            "weibei_course_map",
            "weibei_course_search",
            "weibei_learning_memory",
            "weibei_learning_update",
            "weibei_note_proposal",
        ].allSatisfy(extensionSource.contains),
        "PI extension bundles the WeiBei-owned course, memory, and note tools"
    )
    try piRequire(
        extensionSource.contains("contextFileBytes: 4 * 1024 * 1024")
            && extensionSource.contains("courseCatalogItems: 500")
            && extensionSource.contains("courseMapPageItems: 60")
            && extensionSource.contains("catalogCount: snapshot.course.catalog.length")
            && extensionSource.contains("const offset = params.offset ?? 0")
            && extensionSource.contains("const limit = params.limit ?? 40")
            && extensionSource.contains("与已有 catalog ID 重复")
            && extensionSource.contains("noteTitle: catalogByID.get(relation.noteItemID)!.title")
            && extensionSource.contains("searchedCourseItemIDs.has(item.id)")
            && extensionSource.contains("courseJumpReference")
            && extensionSource.contains("courseEvidenceLabel")
            && extensionSource.contains("jumpEvidence")
            && extensionSource.contains("courseHeading")
            && extensionSource.contains("coursePage")
            && extensionSource.contains("pageJumpReferences")
            && extensionSource.contains("learningLocationJumpReference")
            && extensionSource.contains("duplicateTitle")
            && extensionSource.contains("章节标识")
            && extensionSource.contains("章节序号")
            && extensionSource.contains("resolutionEvidenceMatches")
            && extensionSource.contains("unresolvedTerms")
            && extensionSource.contains("不能够")
            && extensionSource.contains("not yet")
            && extensionSource.contains("不正确")
            && extensionSource.contains("immediateNegation")
            && extensionSource.contains("html-section-")
            && extensionSource.contains("用户陈述型记忆必须直接依据本轮用户原话"),
        "PI extension keeps a paged full catalog, stable file and section jumps, compact context output, strict ids, and read-backed memory evidence"
    )

    for skillName in PiAgentResources.requiredSkillNames {
        let skillURL = resources.skillsURL.appendingPathComponent(skillName).appendingPathComponent("SKILL.md")
        let source = try String(contentsOf: skillURL, encoding: .utf8)
        try piRequire(source.contains("name: \(skillName)") && source.contains("description:"), "PI skill \(skillName) has valid frontmatter")
    }
    let interactiveSkillURL = resources.skillsURL
        .appendingPathComponent("weibei-interactive-study")
        .appendingPathComponent("SKILL.md")
    let interactiveSkill = try String(contentsOf: interactiveSkillURL, encoding: .utf8)
    try piRequire(
        [
            "chart", "function-plot", "parameter-lab", "text-study", "design-compare", "palette",
            "study-board", "relationship-map", "timeline", "comparison-matrix",
            "annotated-passage", "derivation-steps", "flashcards", "sequence-builder",
            "scenario-lab", "evidence-board", "spectrum", "decision-path",
            "unit-workbench", "reaction-balance", "algorithm-trace", "language-aligner",
            "argument-map", "visual-analysis", "spatial-layers", "pathway-lab",
        ].allSatisfy(interactiveSkill.contains),
        "interactive study skill bundles the twenty-eight-kind rich component selection templates"
    )
    try piRequire(
        crossDisciplinaryProtocolStrings.allSatisfy(interactiveSkill.contains),
        "interactive study skill pins the editor-compatible cross-disciplinary JSON schemas"
    )
    try piRequire(
        [
            "\"variables\"",
            "\"checks\"",
            "\"species\"",
            "\"codeLines\"",
            "\"pairs\"",
            "\"zones\"",
            "\"features\"",
            "\"activeNodeIds\"",
        ].allSatisfy(interactiveSkill.contains)
            && [
                "\"quantities\"",
                "\"conversions\"",
                "\"segments\"",
                "\"observations\"",
                "\"regions\"",
                "\"diagramLabel\"",
                "\"initialStateID\"",
                "\"transitions\"",
            ].allSatisfy { !interactiveSkill.contains($0) },
        "interactive study skill examples use only the current editor.js parser field names"
    )
    try piRequire(interactiveSkill.contains("预采样")
        && interactiveSkill.contains("白名单")
        && interactiveSkill.contains("不得输出原始 HTML"), "interactive study skill documents safe curve, controller, and HTML boundaries")
    try piRequire(
        interactiveSkill.contains("不要等待用户说出")
            && interactiveSkill.contains("主动选择纯文字")
            && interactiveSkill.contains("相邻回答不要机械复用同一构图"),
        "interactive study skill includes proactive selection, negative examples, and anti-template variation rules"
    )
    try piRequire(
        interactiveSkill.contains("一条回答最多一个主互动块")
            && interactiveSkill.contains("主动生成必须有课程证据支撑")
            && interactiveSkill.contains("前端只按给定 `atoms` 乘系数")
            && interactiveSkill.contains("只是展示预枚举步骤")
            && interactiveSkill.contains("禁止 URL、HTML")
            && interactiveSkill.contains("文案必须称“示意图”")
            && interactiveSkill.contains("切换预先枚举的 `states`"),
        "interactive study skill documents the new cross-disciplinary safety boundaries"
    )

    let runtimeSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/WeiBeiCore/PiAgentRuntime.swift")
    let runtimeSource = try String(contentsOf: runtimeSourceURL, encoding: .utf8)
    try piRequire(
        runtimeSource.contains("answeredBeforeContext")
            && runtimeSource.contains("allowedSourceLabels")
            && runtimeSource.contains("allowedNoteSourceLabels")
            && runtimeSource.contains("memoryRevision")
            && runtimeSource.contains("courseSourcesRead")
            && runtimeSource.contains("allowedJumpReferences")
            && runtimeSource.contains("jumpEvidenceLabels")
            && runtimeSource.contains("registerJumpEvidence")
            && runtimeSource.contains("canonicalJumpReference")
            && runtimeSource.contains("isDedicatedJumpLine")
            && runtimeSource.contains("contextRevision == run.contextRevision")
            && runtimeSource.contains("citedJumpReferences")
            && runtimeSource.contains("learningUpdateValidationError")
            && runtimeSource.contains("resolutionEvidenceMatches")
            && runtimeSource.contains("StudyAgentResolutionEvidence.matches")
            && runtimeSource.contains("StudyAgentCurrentTurnEvidence.matches")
            && runtimeSource.contains("allowsLearningOnlyAnswer")
            && runtimeSource.contains("PI 返回了课程内容，但没有标注本轮读取的来源")
            && runtimeSource.contains("binary.sha256")
            && runtimeSource.contains("SecStaticCodeCheckValidity"),
        "PI host enforces context-first answers, source labels, binary integrity, and code signatures"
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
