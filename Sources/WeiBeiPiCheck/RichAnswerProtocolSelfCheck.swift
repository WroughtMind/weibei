import Foundation
import WeiBeiCore

func runRichAnswerProtocolSelfCheck() throws {
    try checkAcceptedInteractiveScene()
    try checkStaleEvidenceFallsBackToNarrative()
    try checkBrokenReferencesDropOnlyTheirScene()
    try checkRawWebPayloadIsRejected()
    try checkDirectManipulationPlanMatchesOperations()
    try checkImageRegionsStayInsideTheirFrame()
    try checkTruncatedEvidenceStaysVisibleAsPartial()
    try checkDefaultSceneBudgetIsBounded()
    try checkAssetAliasesResolveBeforePersistence()
    try richAnswerRequire(
        RichAnswerCapabilityFamily.allCases.count == 8,
        "the first protocol covers all eight rich-answer capability families"
    )
    try richAnswerRequire(
        RichAnswerPressureCases.learningQuestions.count == 15
            && RichAnswerPressureCases.faultInjectionCases.count == 4,
        "the first pressure matrix keeps fifteen learning domains and four controlled failures"
    )
}

private func checkAssetAliasesResolveBeforePersistence() throws {
    var envelope = minimalEnvelope(contextRevision: "revision-7")
    envelope.expressionPlan.families = [.imageAndOverlay]
    envelope.scenes = [
        RichAnswerScene(
            id: "image-scene",
            title: "图像定位",
            family: .imageAndOverlay,
            objects: [
                RichAnswerObject(
                    id: "image",
                    kind: .image,
                    label: "材料原图",
                    evidenceIDs: ["source-1"],
                    assetID: "course-item-1",
                    frameID: "image-frame"
                ),
            ],
            frames: [
                RichAnswerFrame(
                    id: "image-frame",
                    kind: .image,
                    title: "材料原图",
                    objectIDs: ["image"],
                    assetID: "course-item-1",
                    evidenceIDs: ["source-1"]
                ),
            ],
            evidenceIDs: ["source-1"]
        ),
    ]
    envelope.evidenceLedger[0].assetIDs = ["course-item-1"]
    let presentation = RichAnswerEngine.prepare(
        envelope: envelope,
        environment: RichAnswerEnvironment(
            contextRevision: "revision-7",
            allowedSourceLabels: ["[材料：样例]"],
            allowedAssetIDs: ["course-item-1"]
        )
    ).resolvingAssetIDs(using: ["course-item-1": "persistent-material-id"])

    try richAnswerRequire(presentation.mode == .rich, "a grounded local image may render")
    try richAnswerRequire(
        presentation.scenes[0].objects[0].assetID == "persistent-material-id"
            && presentation.scenes[0].frames[0].assetID == "persistent-material-id"
            && presentation.evidenceLedger[0].assetIDs == ["persistent-material-id"],
        "request-local asset aliases resolve before the answer is persisted"
    )
}

private func checkDirectManipulationPlanMatchesOperations() throws {
    var envelope = minimalEnvelope(contextRevision: "revision-7")
    envelope.expressionPlan.directManipulation = true
    let presentation = RichAnswerEngine.prepare(
        envelope: envelope,
        environment: RichAnswerEnvironment(
            contextRevision: "revision-7",
            allowedSourceLabels: ["[材料：样例]"]
        )
    )

    try richAnswerRequire(presentation.mode == .narrativeOnly, "a false interaction promise cannot render")
    try richAnswerRequire(
        presentation.diagnostics.contains(where: { $0.code == .invalidParameter }),
        "an interaction-plan mismatch exposes a protocol diagnostic"
    )
}

private func checkImageRegionsStayInsideTheirFrame() throws {
    var envelope = minimalEnvelope(contextRevision: "revision-7")
    envelope.expressionPlan.families = [.imageAndOverlay]
    envelope.scenes = [
        RichAnswerScene(
            id: "overlay",
            title: "图像叠层",
            family: .imageAndOverlay,
            objects: [
                RichAnswerObject(
                    id: "region",
                    kind: .region,
                    label: "越界区域",
                    frameID: "image-frame",
                    bounds: RichAnswerRegion(x: 0.8, y: 0.2, width: 0.4, height: 0.4)
                ),
            ],
            frames: [
                RichAnswerFrame(id: "image-frame", kind: .image, title: "原图", objectIDs: ["region"]),
            ],
            evidenceIDs: ["source-1"]
        ),
    ]
    let presentation = RichAnswerEngine.prepare(
        envelope: envelope,
        environment: RichAnswerEnvironment(
            contextRevision: "revision-7",
            allowedSourceLabels: ["[材料：样例]"]
        )
    )

    try richAnswerRequire(presentation.mode == .narrativeOnly, "an out-of-bounds overlay cannot render")
    try richAnswerRequire(
        presentation.diagnostics.contains(where: { $0.sceneID == "overlay" && $0.code == .invalidValue }),
        "an out-of-bounds overlay exposes a scene diagnostic"
    )
}

private func checkTruncatedEvidenceStaysVisibleAsPartial() throws {
    var envelope = minimalEnvelope(contextRevision: "revision-7")
    envelope.evidenceLedger[0].isTruncated = true
    let presentation = RichAnswerEngine.prepare(
        envelope: envelope,
        environment: RichAnswerEnvironment(
            contextRevision: "revision-7",
            allowedSourceLabels: ["[材料：样例]"]
        )
    )

    try richAnswerRequire(presentation.mode == .rich, "a grounded excerpt may render even when its source is truncated")
    try richAnswerRequire(presentation.evidenceState == .partial, "truncated source evidence is never reported as complete")
}

private func checkDefaultSceneBudgetIsBounded() throws {
    var envelope = minimalEnvelope(contextRevision: "revision-7")
    envelope.scenes = (0..<7).map { index in
        var scene = envelope.scenes[0]
        scene.id = "scene-\(index)"
        scene.objects[0].id = "claim-\(index)"
        return scene
    }
    let presentation = RichAnswerEngine.prepare(
        envelope: envelope,
        environment: RichAnswerEnvironment(
            contextRevision: "revision-7",
            allowedSourceLabels: ["[材料：样例]"]
        )
    )

    try richAnswerRequire(presentation.scenes.count == 6, "the default host budget keeps at most six scenes")
    try richAnswerRequire(
        presentation.diagnostics.contains(where: { $0.code == .budgetExceeded }),
        "scene budget clipping remains inspectable"
    )
}

private func checkAcceptedInteractiveScene() throws {
    let envelope = RichAnswerEnvelope(
        contextRevision: "revision-7",
        narrative: "名义利率减去通胀率，可以近似理解为实际利率。",
        expressionPlan: RichAnswerExpressionPlan(
            action: .manipulate,
            summary: "让用户调节通胀率并观察实际利率变化",
            families: [.quantityAndCoordinates, .calculationAndConstraints],
            preferredSurface: .expanded,
            directManipulation: true
        ),
        scenes: [
            RichAnswerScene(
                id: "real-rate-lab",
                title: "名义利率与实际利率",
                family: .quantityAndCoordinates,
                objects: [
                    RichAnswerObject(
                        id: "nominal-rate",
                        kind: .quantity,
                        label: "名义利率",
                        number: 5,
                        unit: "%"
                    ),
                    RichAnswerObject(
                        id: "inflation-rate",
                        kind: .quantity,
                        label: "通胀率",
                        number: 2,
                        unit: "%"
                    ),
                    RichAnswerObject(
                        id: "real-rate",
                        kind: .formula,
                        label: "实际利率",
                        text: "名义利率 − 通胀率"
                    ),
                ],
                relations: [
                    RichAnswerRelation(
                        id: "inflation-reduces-real-rate",
                        kind: .transforms,
                        sourceID: "inflation-rate",
                        targetID: "real-rate",
                        label: "扣除"
                    ),
                ],
                operations: [
                    RichAnswerOperation(
                        id: "adjust-inflation",
                        kind: .adjust,
                        label: "调节通胀率",
                        targetIDs: ["inflation-rate", "real-rate"],
                        parameter: RichAnswerParameter(
                            id: "inflation",
                            label: "通胀率",
                            minimum: 0,
                            maximum: 10,
                            step: 0.5,
                            initialValue: 2,
                            unit: "%"
                        )
                    ),
                ],
                frames: [
                    RichAnswerFrame(
                        id: "rate-comparison",
                        kind: .cartesian,
                        title: "利率变化",
                        objectIDs: ["nominal-rate", "inflation-rate", "real-rate"],
                        xAxis: RichAnswerAxis(label: "通胀率", minimum: 0, maximum: 10, unit: "%"),
                        yAxis: RichAnswerAxis(label: "利率", minimum: -5, maximum: 10, unit: "%")
                    ),
                ],
                evidenceIDs: ["rates-definition"],
                placement: .expanded
            ),
        ],
        evidenceLedger: [
            RichAnswerEvidence(
                id: "rates-definition",
                sourceLabel: "[材料：利率课程]",
                excerpt: "实际利率扣除了通货膨胀后的购买力变化。"
            ),
        ],
        fallback: RichAnswerFallback(text: "实际利率需要扣除通胀影响。", reason: "富回答不可用时保留核心结论")
    )
    let environment = RichAnswerEnvironment(
        contextRevision: "revision-7",
        allowedSourceLabels: ["[材料：利率课程]"]
    )

    let presentation = RichAnswerEngine.prepare(envelope: envelope, environment: environment)

    try richAnswerRequire(presentation.mode == .rich, "a valid grounded scene stays rich")
    try richAnswerRequire(presentation.scenes.count == 1, "a valid scene survives validation")
    try richAnswerRequire(presentation.scenes[0].operations.count == 1, "direct manipulation survives validation")
    try richAnswerRequire(presentation.evidenceState == .complete, "complete evidence is reported as complete")

    let encoded = try JSONEncoder().encode(envelope)
    let decoded = RichAnswerEngine.prepare(data: encoded, fallbackText: "fallback", environment: environment)
    try richAnswerRequire(decoded == presentation, "the Pi JSON boundary preserves a valid presentation")
}

private func checkStaleEvidenceFallsBackToNarrative() throws {
    let envelope = minimalEnvelope(contextRevision: "old-revision")
    let presentation = RichAnswerEngine.prepare(
        envelope: envelope,
        environment: RichAnswerEnvironment(
            contextRevision: "current-revision",
            allowedSourceLabels: ["[材料：样例]"]
        )
    )

    try richAnswerRequire(presentation.mode == .narrativeOnly, "stale context cannot render a scene")
    try richAnswerRequire(presentation.scenes.isEmpty, "stale context removes all scenes")
    try richAnswerRequire(
        presentation.diagnostics.contains(where: { $0.code == .staleContext }),
        "stale context exposes a diagnostic"
    )
}

private func checkBrokenReferencesDropOnlyTheirScene() throws {
    var invalid = minimalEnvelope(contextRevision: "revision-7").scenes[0]
    invalid.id = "broken"
    invalid.relations = [
        RichAnswerRelation(
            id: "missing-target",
            kind: .supports,
            sourceID: "claim",
            targetID: "not-present"
        ),
    ]
    var envelope = minimalEnvelope(contextRevision: "revision-7")
    envelope.scenes.append(invalid)
    let presentation = RichAnswerEngine.prepare(
        envelope: envelope,
        environment: RichAnswerEnvironment(
            contextRevision: "revision-7",
            allowedSourceLabels: ["[材料：样例]"]
        )
    )

    try richAnswerRequire(presentation.mode == .rich, "one invalid scene does not erase a valid scene")
    try richAnswerRequire(presentation.scenes.map(\.id) == ["simple"], "only the broken scene is removed")
    try richAnswerRequire(
        presentation.diagnostics.contains(where: { $0.sceneID == "broken" && $0.code == .brokenReference }),
        "broken references expose a scene diagnostic"
    )
}

private func checkRawWebPayloadIsRejected() throws {
    let data = Data(
        #"{"schemaVersion":1,"contextRevision":"revision-7","narrative":"说明","expressionPlan":{"action":"explain","summary":"说明","families":["textAndAlignment"],"preferredSurface":"inline","directManipulation":false},"scenes":[],"evidenceLedger":[],"fallback":{"text":"安全回退","reason":"协议不支持网页"},"html":"<script>alert(1)</script>"}"#.utf8
    )
    let presentation = RichAnswerEngine.prepare(
        data: data,
        fallbackText: "文本回答",
        environment: RichAnswerEnvironment(contextRevision: "revision-7", allowedSourceLabels: [])
    )

    try richAnswerRequire(presentation.mode == .narrativeOnly, "raw web payloads never render")
    try richAnswerRequire(presentation.narrative == "文本回答", "decode failure uses the trusted text answer")
    try richAnswerRequire(
        presentation.diagnostics.contains(where: { $0.code == .unsupportedField }),
        "unsupported web fields expose a protocol diagnostic"
    )
}

private func minimalEnvelope(contextRevision: String) -> RichAnswerEnvelope {
    RichAnswerEnvelope(
        contextRevision: contextRevision,
        narrative: "这是一个有依据的简短说明。",
        expressionPlan: RichAnswerExpressionPlan(
            action: .explain,
            summary: "对齐原文和解释",
            families: [.textAndAlignment],
            preferredSurface: .inline,
            directManipulation: false
        ),
        scenes: [
            RichAnswerScene(
                id: "simple",
                title: "原文与解释",
                family: .textAndAlignment,
                objects: [
                    RichAnswerObject(id: "claim", kind: .text, label: "解释", text: "概念说明"),
                ],
                evidenceIDs: ["source-1"]
            ),
        ],
        evidenceLedger: [
            RichAnswerEvidence(id: "source-1", sourceLabel: "[材料：样例]", excerpt: "原文片段"),
        ],
        fallback: RichAnswerFallback(text: "概念说明", reason: "场景不可用")
    )
}

private func richAnswerRequire(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw RichAnswerProtocolCheckError.failed(message) }
}

private enum RichAnswerProtocolCheckError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case let .failed(message):
            return message
        }
    }
}
