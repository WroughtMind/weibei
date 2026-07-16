import WeiBeiCore

enum RichAnswerVerificationFixture {
    static let sourceLabel = "[材料：货币金融学课程 HTML]"

    static func presentation() -> RichAnswerPresentation {
        RichAnswerEngine.prepare(
            envelope: RichAnswerEnvelope(
                contextRevision: "rich-answer-preview",
                narrative: "固定名义利率后，通胀率越高，实际利率越低。",
                expressionPlan: RichAnswerExpressionPlan(
                    action: .manipulate,
                    summary: "调节通胀率，观察名义利率与实际利率之间的变化关系",
                    families: [.quantityAndCoordinates],
                    preferredSurface: .expanded,
                    directManipulation: true
                ),
                scenes: [
                    RichAnswerScene(
                        id: "real-rate-lab",
                        title: "通胀如何改变实际利率",
                        family: .quantityAndCoordinates,
                        objects: [
                            RichAnswerObject(
                                id: "inflation-zero",
                                kind: .dataPoint,
                                label: "通胀 0%，实际利率 5%",
                                unit: "%",
                                evidenceIDs: ["rate-definition"],
                                frameID: "rate-frame",
                                coordinate: RichAnswerPoint(x: 0, y: 0.89)
                            ),
                            RichAnswerObject(
                                id: "inflation-two",
                                kind: .dataPoint,
                                label: "通胀 2%，实际利率 3%",
                                unit: "%",
                                evidenceIDs: ["rate-definition"],
                                frameID: "rate-frame",
                                coordinate: RichAnswerPoint(x: 0.25, y: 0.67)
                            ),
                            RichAnswerObject(
                                id: "inflation-five",
                                kind: .dataPoint,
                                label: "通胀 5%，实际利率 0%",
                                evidenceIDs: ["rate-definition"],
                                frameID: "rate-frame",
                                coordinate: RichAnswerPoint(x: 0.625, y: 0.33)
                            ),
                            RichAnswerObject(
                                id: "inflation-eight",
                                kind: .dataPoint,
                                label: "通胀 8%，实际利率 -3%",
                                evidenceIDs: ["rate-definition"],
                                frameID: "rate-frame",
                                coordinate: RichAnswerPoint(x: 1, y: 0)
                            ),
                        ],
                        relations: [
                            RichAnswerRelation(
                                id: "inflation-reduces-real-rate",
                                kind: .transforms,
                                sourceID: "inflation-zero",
                                targetID: "inflation-eight",
                                label: "通胀每升高 1 个百分点，实际利率约下降 1 个百分点",
                                evidenceIDs: ["rate-definition"]
                            ),
                        ],
                        operations: [
                            RichAnswerOperation(
                                id: "adjust-inflation",
                                kind: .adjust,
                                label: "调节通胀率",
                                targetIDs: ["inflation-zero", "inflation-two", "inflation-five", "inflation-eight"],
                                parameter: RichAnswerParameter(
                                    id: "inflation",
                                    label: "通胀率",
                                    minimum: 0,
                                    maximum: 8,
                                    step: 0.5,
                                    initialValue: 2,
                                    unit: "%"
                                ),
                                frameID: "rate-frame"
                            ),
                        ],
                        frames: [
                            RichAnswerFrame(
                                id: "rate-frame",
                                kind: .cartesian,
                                title: "固定名义利率 5%",
                                objectIDs: ["inflation-zero", "inflation-two", "inflation-five", "inflation-eight"],
                                xAxis: RichAnswerAxis(label: "通胀率", minimum: 0, maximum: 8, unit: "%"),
                                yAxis: RichAnswerAxis(label: "利率", minimum: -3, maximum: 6, unit: "%"),
                                evidenceIDs: ["rate-definition"]
                            ),
                        ],
                        evidenceIDs: ["rate-definition"],
                        placement: .expanded
                    ),
                ],
                evidenceLedger: [
                    RichAnswerEvidence(
                        id: "rate-definition",
                        sourceLabel: sourceLabel,
                        excerpt: "名义利率以货币单位表示，实际利率扣除了通货膨胀后的购买力变化。"
                    ),
                ],
                fallback: RichAnswerFallback(
                    text: "实际利率需要扣除通胀造成的购买力变化。",
                    reason: "场景不可用时保留核心结论"
                )
            ),
            environment: RichAnswerEnvironment(
                contextRevision: "rich-answer-preview",
                allowedSourceLabels: [sourceLabel]
            )
        )
    }
}
