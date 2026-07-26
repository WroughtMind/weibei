import Foundation

public struct RichAnswerRendererRegistrySelfCheckReport: Codable, Hashable, Sendable {
    public var acceptedCompatibilityPlan: Bool
    public var reportsCapabilityMismatch: Bool
    public var diagnostics: [String]

    public init(
        acceptedCompatibilityPlan: Bool,
        reportsCapabilityMismatch: Bool,
        diagnostics: [String]
    ) {
        self.acceptedCompatibilityPlan = acceptedCompatibilityPlan
        self.reportsCapabilityMismatch = reportsCapabilityMismatch
        self.diagnostics = diagnostics
    }

    public var passed: Bool {
        acceptedCompatibilityPlan && reportsCapabilityMismatch && diagnostics.isEmpty
    }
}

public enum RichAnswerRendererRegistrySelfCheck {
    public static func run() -> RichAnswerRendererRegistrySelfCheckReport {
        let registry = RichAnswerRendererRegistry.compatibilityAdapters()
        let acceptedPlan = RichAnswerRenderPlan(
            renderer: RichAnswerRendererRegistry.openUIProgramRenderer,
            specVersion: "weibei.openui.v1",
            spec: RichAnswerRenderSpec(
                fields: [
                    "adapter": .string("legacy_t1_program"),
                    "componentFamilies": .array([.string("FunctionPlot")]),
                    "sceneID": .string("scene_function"),
                ]
            ),
            interactionBindings: [
                RichAnswerRenderInteractionBinding(
                    id: "probe_x",
                    kind: .probe,
                    target: "FunctionPlot",
                    stateKey: "x",
                    knowledgeStateEffect: "更新局部函数值与来源定位"
                ),
            ],
            sourceBindings: [
                RichAnswerRenderSourceBinding(
                    id: "source_function",
                    evidenceID: "ev_function",
                    target: "FunctionPlot",
                    role: "calculation_basis"
                ),
            ],
            fallback: RichAnswerRenderFallback(
                mode: .narrativeOnly,
                reason: "旧深组件不可用时保留带来源的文字解释",
                text: "暂时无法渲染函数组件，保留来源绑定的文字解释。"
            ),
            qualityBudget: RichAnswerRenderQualityBudget(maxNodes: 12, maxDataPoints: 120, maxHeight: 420)
        )
        let accepted = registry.negotiate(plan: acceptedPlan)

        let chartPlan = RichAnswerRenderPlan(
            renderer: RichAnswerRendererRegistry.standardChartRenderer,
            specVersion: "weibei.chart.v1",
            spec: RichAnswerRenderSpec(
                fields: [
                    "chartKind": .string("line"),
                    "series": .array([
                        .object([
                            "name": .string("趋势"),
                            "values": .array([.number(1), .number(3), .number(2)]),
                        ]),
                    ]),
                    "title": .string("样例趋势"),
                    "xLabels": .array([.string("一"), .string("二"), .string("三")]),
                ]
            ),
            interactionBindings: [
                RichAnswerRenderInteractionBinding(
                    id: "probe_point",
                    kind: .probe,
                    target: "series",
                    stateKey: "point",
                    knowledgeStateEffect: "查看数据点对应来源"
                ),
            ],
            sourceBindings: [
                RichAnswerRenderSourceBinding(
                    id: "source_chart",
                    evidenceID: "ev_chart",
                    target: "series",
                    role: "data_basis"
                ),
            ],
            fallback: RichAnswerRenderFallback(
                mode: .narrativeOnly,
                reason: "标准图表不可用时保留带来源的数据解释",
                text: "暂时无法渲染图表，保留来源绑定的数据解释。"
            ),
            qualityBudget: RichAnswerRenderQualityBudget(maxNodes: 8, maxDataPoints: 3, maxHeight: 360)
        )
        let chartAccepted = registry.negotiate(plan: chartPlan)

        let scatterPlan = RichAnswerRenderPlan(
            renderer: RichAnswerRendererRegistry.standardChartRenderer,
            specVersion: "weibei.chart.v1",
            spec: RichAnswerRenderSpec(
                fields: [
                    "chartKind": .string("scatter"),
                    "series": .array([
                        .object([
                            "name": .string("观测"),
                            "xValues": .array([.number(1), .number(2), .number(3)]),
                            "values": .array([.number(2.1), .number(2.9), .number(4.2)]),
                        ]),
                    ]),
                    "title": .string("成对观测"),
                ]
            ),
            interactionBindings: [
                RichAnswerRenderInteractionBinding(
                    id: "probe_observation",
                    kind: .probe,
                    target: "series",
                    stateKey: "observation",
                    knowledgeStateEffect: "查看成对观测"
                ),
            ],
            sourceBindings: [
                RichAnswerRenderSourceBinding(
                    id: "source_scatter",
                    evidenceID: "ev_scatter",
                    target: "series",
                    role: "data_basis"
                ),
            ],
            fallback: RichAnswerRenderFallback(
                mode: .narrativeOnly,
                reason: "散点图不可用时保留带来源的数据解释",
                text: "暂时无法渲染散点图，保留来源绑定的数据解释。"
            ),
            qualityBudget: RichAnswerRenderQualityBudget(maxNodes: 8, maxDataPoints: 3, maxHeight: 360)
        )
        let scatterAccepted = registry.negotiate(plan: scatterPlan)
        var invalidScatterPlan = scatterPlan
        invalidScatterPlan.spec["xLabels"] = .array([.string("一"), .string("二"), .string("三")])
        let invalidScatter = registry.negotiate(plan: invalidScatterPlan)

        let mismatchPlan = RichAnswerRenderPlan(
            renderer: "weibei.unregistered.renderer",
            specVersion: "v1",
            spec: RichAnswerRenderSpec(fields: ["sceneID": .string("scene_unknown")]),
            sourceBindings: [
                RichAnswerRenderSourceBinding(
                    id: "source_unknown",
                    evidenceID: "ev_unknown",
                    target: "unknown",
                    role: "basis"
                ),
            ],
            fallback: RichAnswerRenderFallback(
                mode: .narrativeOnly,
                reason: "未知渲染器无法使用",
                text: "需要重新选择渲染器。"
            )
        )
        let mismatch = registry.negotiate(plan: mismatchPlan)
        var diagnostics: [String] = []
        if accepted.status != .accepted {
            diagnostics.append("compatibility plan was not accepted")
        }
        if chartAccepted.status != .accepted {
            diagnostics.append("standard chart plan was not accepted")
        }
        if scatterAccepted.status != .accepted {
            diagnostics.append("paired scatter plan was not accepted")
        }
        if invalidScatter.status != .capabilityMismatch
            || invalidScatter.mismatch?.issues.first?.field != "spec.xLabels" {
            diagnostics.append("scatter chart did not reject categorical xLabels")
        }
        if mismatch.status != .capabilityMismatch
            || mismatch.mismatch?.issues.first?.code != .unknownRenderer {
            diagnostics.append("unknown renderer did not report capability_mismatch")
        }
        return RichAnswerRendererRegistrySelfCheckReport(
            acceptedCompatibilityPlan: accepted.status == .accepted
                && chartAccepted.status == .accepted
                && scatterAccepted.status == .accepted,
            reportsCapabilityMismatch: mismatch.status == .capabilityMismatch,
            diagnostics: diagnostics
        )
    }
}
