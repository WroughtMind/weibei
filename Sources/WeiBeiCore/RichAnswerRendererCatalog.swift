import Foundation

public extension RichAnswerRendererRegistry {
    static func compatibilityAdapters() -> RichAnswerRendererRegistry {
        let registrations = [
            RichAnswerRendererRegistration(declaration: openUIProgramDeclaration()),
            RichAnswerRendererRegistration(declaration: openUICompositionDeclaration()),
            RichAnswerRendererRegistration(
                declaration: standardChartDeclaration(),
                validateSpec: { plan in validateStandardChartSpec(plan) }
            ),
            RichAnswerRendererRegistration(
                declaration: mathFunctionDeclaration(),
                validateSpec: { plan in validateMathFunctionSpec(plan) }
            ),
            RichAnswerRendererRegistration(declaration: geometry2DDeclaration()),
            RichAnswerRendererRegistration(declaration: scene3DDeclaration()),
            RichAnswerRendererRegistration(declaration: spatialMapDeclaration()),
            RichAnswerRendererRegistration(declaration: imageOverlayDeclaration()),
        ]
        return (try? RichAnswerRendererRegistry(registrations: registrations)) ?? (try! RichAnswerRendererRegistry())
    }
    
    static func defaultRegistry() -> RichAnswerRendererRegistry {
        compatibilityAdapters()
    }
    
    static func openUIProgramDeclaration() -> RichAnswerRendererCapabilityDeclaration {
        RichAnswerRendererCapabilityDeclaration(
            renderer: openUIProgramRenderer,
            displayName: "魏碑 OpenUI 深组件适配器",
            purpose: "承接现有 T1 深组件程序，把旧的高质量联动组件挂到 renderPlan 协商层之后。",
            specVersions: ["weibei.openui.v1"],
            preferredSpecVersion: "weibei.openui.v1",
            capabilities: RichAnswerRendererCapabilitySet(
                dataKinds: [.functionExpression, .semanticGraph, .tabularData, .textEvidence, .timeSeries],
                interactions: [.picker, .probe, .scrubber, .select, .slider, .sourceJump, .stateReveal, .step, .toggle],
                resources: [.canvas2D, .dom, .webKitBridge]
            ),
            limits: RichAnswerRenderQualityBudget(
                maxNodes: 48,
                maxDataPoints: 512,
                maxArtifacts: 8,
                maxBytes: 512_000,
                maxHeight: 720,
                maxAnimationFPS: 30,
                maxInteractionLatencyMS: 120,
                allowAnimation: true,
                allowWebGL: false,
                allowNetwork: false
            ),
            fallbackModes: [.narrativeOnly, .simplifiedRenderer, .staticSnapshot],
            lifecycle: RichAnswerRendererLifecycle(
                createsRuntime: true,
                supportsStreamingPatch: true,
                supportsDynamicHeight: true,
                needsExplicitTeardown: false
            ),
            specContract: RichAnswerRenderSpecContract(
                requiredRootFields: ["adapter", "sceneID"],
                optionalRootFields: ["componentFamilies", "intent", "legacySceneID", "stateBindings"],
                allowAdditionalRootFields: false,
                maxDepth: 6,
                maxObjectFields: 48,
                maxArrayItems: 128,
                maxStringLength: 1_200
            ),
            compatibilityAdapter: "legacy_t1_program"
        )
    }
    
    static func openUICompositionDeclaration() -> RichAnswerRendererCapabilityDeclaration {
        RichAnswerRendererCapabilityDeclaration(
            renderer: openUICompositionRenderer,
            displayName: "魏碑 OpenUI 原语树适配器",
            purpose: "把现有 T2 组合原语作为过渡适配对象保留，不继续扩成低级点线树总线。",
            specVersions: ["weibei.openui.v1"],
            preferredSpecVersion: "weibei.openui.v1",
            capabilities: RichAnswerRendererCapabilitySet(
                dataKinds: [.imageRaster, .semanticGraph, .tabularData, .textEvidence, .timeSeries],
                interactions: [.picker, .probe, .scrubber, .select, .slider, .sourceJump, .step, .toggle, .zoomPan],
                resources: [.canvas2D, .dom, .nativeSwiftUI, .webKitBridge]
            ),
            limits: RichAnswerRenderQualityBudget(
                maxNodes: 48,
                maxDataPoints: 256,
                maxArtifacts: 8,
                maxBytes: 384_000,
                maxHeight: 720,
                maxAnimationFPS: 30,
                maxInteractionLatencyMS: 120,
                allowAnimation: true,
                allowWebGL: false,
                allowNetwork: false
            ),
            fallbackModes: [.narrativeOnly, .simplifiedRenderer, .staticSnapshot],
            lifecycle: RichAnswerRendererLifecycle(
                createsRuntime: true,
                supportsStreamingPatch: false,
                supportsDynamicHeight: true,
                needsExplicitTeardown: false
            ),
            specContract: RichAnswerRenderSpecContract(
                requiredRootFields: ["adapter", "sceneID"],
                optionalRootFields: ["intent", "legacySceneID", "primitiveRoles", "stateBindings"],
                allowAdditionalRootFields: false,
                maxDepth: 6,
                maxObjectFields: 48,
                maxArrayItems: 128,
                maxStringLength: 1_200
            ),
            compatibilityAdapter: "legacy_t2_composition"
        )
    }
    
    static func standardChartDeclaration() -> RichAnswerRendererCapabilityDeclaration {
        RichAnswerRendererCapabilityDeclaration(
            renderer: standardChartRenderer,
            displayName: "魏碑标准数据图适配器",
            purpose: "渲染标准 line/bar/area/scatter/mixed/histogram 数据图，只接受高层图表规格，不接收裸 ECharts option。",
            specVersions: ["weibei.chart.v1"],
            preferredSpecVersion: "weibei.chart.v1",
            capabilities: RichAnswerRendererCapabilitySet(
                dataKinds: [.tabularData, .timeSeries],
                interactions: [.probe, .select],
                resources: [.canvas2D, .dom, .webKitBridge]
            ),
            limits: RichAnswerRenderQualityBudget(
                maxNodes: 24,
                maxDataPoints: 1_024,
                maxArtifacts: 0,
                maxBytes: 256_000,
                maxHeight: 640,
                maxAnimationFPS: 30,
                maxInteractionLatencyMS: 120,
                allowAnimation: true,
                allowWebGL: false,
                allowNetwork: false
            ),
            fallbackModes: [.narrativeOnly, .simplifiedRenderer, .staticSnapshot],
            lifecycle: RichAnswerRendererLifecycle(
                createsRuntime: true,
                supportsStreamingPatch: false,
                supportsDynamicHeight: true,
                needsExplicitTeardown: false
            ),
            specContract: RichAnswerRenderSpecContract(
                requiredRootFields: ["chartKind", "title"],
                optionalRootFields: [
                    "binCount",
                    "caption",
                    "focusEnabled",
                    "samples",
                    "series",
                    "xAxisLabel",
                    "xLabels",
                    "yAxisLabel",
                ],
                allowAdditionalRootFields: false,
                maxDepth: 6,
                maxObjectFields: 64,
                maxArrayItems: 512,
                maxStringLength: 1_200
            ),
            compatibilityAdapter: "standard_echarts_chart"
        )
    }
    
    static func mathFunctionDeclaration() -> RichAnswerRendererCapabilityDeclaration {
        RichAnswerRendererCapabilityDeclaration(
            renderer: mathFunctionRenderer,
            displayName: "魏碑受限数学函数适配器",
            purpose: "根据受限表达式图、定义域和参数绘制函数；采样、间断切段和响应式由本地运行时负责。",
            specVersions: ["weibei.math-function.v1"],
            preferredSpecVersion: "weibei.math-function.v1",
            capabilities: RichAnswerRendererCapabilitySet(
                dataKinds: [.functionExpression],
                interactions: [.probe, .slider],
                resources: [.canvas2D, .dom, .webKitBridge]
            ),
            limits: RichAnswerRenderQualityBudget(
                maxNodes: 64,
                maxDataPoints: 1_600,
                maxArtifacts: 0,
                maxBytes: 256_000,
                maxHeight: 640,
                maxAnimationFPS: 30,
                maxInteractionLatencyMS: 120,
                allowAnimation: true,
                allowWebGL: false,
                allowNetwork: false
            ),
            fallbackModes: [.narrativeOnly, .simplifiedRenderer, .staticSnapshot],
            lifecycle: RichAnswerRendererLifecycle(
                createsRuntime: true,
                supportsStreamingPatch: false,
                supportsDynamicHeight: true,
                needsExplicitTeardown: false
            ),
            specContract: RichAnswerRenderSpecContract(
                requiredRootFields: ["domain", "expression", "title", "variable"],
                optionalRootFields: [
                    "caption",
                    "parameters",
                    "probeEnabled",
                    "xAxisLabel",
                    "yAxisLabel",
                ],
                allowAdditionalRootFields: false,
                maxDepth: 7,
                maxObjectFields: 96,
                maxArrayItems: 128,
                maxStringLength: 1_200
            ),
            compatibilityAdapter: "restricted_math_function"
        )
    }
    
    static func geometry2DDeclaration() -> RichAnswerRendererCapabilityDeclaration {
        RichAnswerRendererCapabilityDeclaration(
            renderer: geometry2DRenderer,
            displayName: "魏碑受限二维几何适配器",
            purpose: "用高层点、线、圆、角、约束、轨迹、控件与读数组合二维几何和确定性实验。",
            specVersions: ["weibei.geometry-2d.v1"],
            preferredSpecVersion: "weibei.geometry-2d.v1",
            capabilities: RichAnswerRendererCapabilitySet(
                dataKinds: [.geometry, .simulationState],
                interactions: [.probe, .select, .slider, .toggle, .zoomPan],
                resources: [.canvas2D, .dom, .webKitBridge]
            ),
            limits: RichAnswerRenderQualityBudget(
                maxNodes: 260,
                maxDataPoints: 1_200,
                maxArtifacts: 0,
                maxBytes: 256_000,
                maxHeight: 720,
                maxAnimationFPS: 30,
                maxInteractionLatencyMS: 120,
                allowAnimation: true,
                allowWebGL: false,
                allowNetwork: false
            ),
            fallbackModes: [.narrativeOnly, .simplifiedRenderer, .staticSnapshot],
            lifecycle: RichAnswerRendererLifecycle(createsRuntime: true),
            specContract: RichAnswerRenderSpecContract(
                requiredRootFields: ["coordinateSpace", "points"],
                optionalRootFields: ["caption", "controls", "readouts", "shapes", "showAxes", "showGrid", "title"],
                allowAdditionalRootFields: false,
                maxDepth: 9,
                maxObjectFields: 260,
                maxArrayItems: 1_200,
                maxStringLength: 1_200
            ),
            compatibilityAdapter: "restricted_geometry_2d"
        )
    }
    
    static func scene3DDeclaration() -> RichAnswerRendererCapabilityDeclaration {
        RichAnswerRendererCapabilityDeclaration(
            renderer: scene3DRenderer,
            displayName: "魏碑受控三维场景适配器",
            purpose: "用本地确定性投影承载相机、坐标、几何体、切片和图层交互，不依赖外链模型或任意脚本。",
            specVersions: ["weibei.scene-3d.v1"],
            preferredSpecVersion: "weibei.scene-3d.v1",
            capabilities: RichAnswerRendererCapabilitySet(
                dataKinds: [.geometry, .mesh3D, .simulationState],
                interactions: [.probe, .select, .slider, .toggle, .zoomPan],
                resources: [.canvas2D, .dom, .webKitBridge]
            ),
            limits: RichAnswerRenderQualityBudget(
                maxNodes: 24,
                maxDataPoints: 3_200,
                maxArtifacts: 0,
                maxBytes: 256_000,
                maxHeight: 720,
                maxAnimationFPS: 30,
                maxInteractionLatencyMS: 160,
                allowAnimation: true,
                allowWebGL: false,
                allowNetwork: false
            ),
            fallbackModes: [.narrativeOnly, .simplifiedRenderer, .staticSnapshot],
            lifecycle: RichAnswerRendererLifecycle(createsRuntime: true),
            specContract: RichAnswerRenderSpecContract(
                requiredRootFields: ["camera", "title"],
                optionalRootFields: ["bounds", "caption", "controls", "coordinateUnits", "focusEnabled", "layers", "objects", "slices", "stateBinding", "states"],
                allowAdditionalRootFields: false,
                maxDepth: 10,
                maxObjectFields: 240,
                maxArrayItems: 3_200,
                maxStringLength: 1_200
            ),
            compatibilityAdapter: "controlled_scene_3d"
        )
    }
    
    static func spatialMapDeclaration() -> RichAnswerRendererCapabilityDeclaration {
        RichAnswerRendererCapabilityDeclaration(
            renderer: spatialMapRenderer,
            displayName: "魏碑地图与空间图层适配器",
            purpose: "承载本地底图、点线面、比例尺、图层开关和标签共享显隐绑定。",
            specVersions: ["weibei.spatial.map.v1"],
            preferredSpecVersion: "weibei.spatial.map.v1",
            capabilities: RichAnswerRendererCapabilitySet(
                dataKinds: [.geometry, .imageRaster, .semanticGraph],
                interactions: [.probe, .select, .toggle, .zoomPan],
                artifactKinds: ["source-image"],
                resources: [.canvas2D, .dom, .localArtifact, .webKitBridge]
            ),
            limits: RichAnswerRenderQualityBudget(
                maxNodes: 280,
                maxDataPoints: 8_000,
                maxArtifacts: 2,
                maxBytes: 1_500_000,
                maxHeight: 720,
                maxAnimationFPS: 30,
                maxInteractionLatencyMS: 140,
                allowAnimation: true,
                allowWebGL: false,
                allowNetwork: false
            ),
            fallbackModes: [.artifactPreview, .narrativeOnly, .simplifiedRenderer, .staticSnapshot],
            lifecycle: RichAnswerRendererLifecycle(createsRuntime: true),
            specContract: RichAnswerRenderSpecContract(
                requiredRootFields: ["coordinateMode", "features"],
                optionalRootFields: ["bounds", "caption", "controls", "coordinateHint", "crs", "focusEnabled", "layers", "mapAsset", "scaleBar", "title"],
                allowAdditionalRootFields: false,
                maxDepth: 9,
                maxObjectFields: 400,
                maxArrayItems: 8_000,
                maxStringLength: 120_000
            ),
            compatibilityAdapter: "controlled_spatial_map"
        )
    }
    
    static func imageOverlayDeclaration() -> RichAnswerRendererCapabilityDeclaration {
        RichAnswerRendererCapabilityDeclaration(
            renderer: imageOverlayRenderer,
            displayName: "魏碑图像覆盖观察适配器",
            purpose: "在当前材料图像上承载透明叠层、测量、批注和对照，并保持图形、标签和读数状态一致。",
            specVersions: ["weibei.image-overlay.v1"],
            preferredSpecVersion: "weibei.image-overlay.v1",
            capabilities: RichAnswerRendererCapabilitySet(
                dataKinds: [.geometry, .imageRaster],
                interactions: [.annotation, .probe, .select, .slider, .toggle, .zoomPan],
                artifactKinds: ["source-image"],
                resources: [.dom, .localArtifact, .webKitBridge]
            ),
            limits: RichAnswerRenderQualityBudget(
                maxNodes: 180,
                maxDataPoints: 1_200,
                maxArtifacts: 2,
                maxBytes: 1_500_000,
                maxHeight: 720,
                maxAnimationFPS: 30,
                maxInteractionLatencyMS: 140,
                allowAnimation: true,
                allowWebGL: false,
                allowNetwork: false
            ),
            fallbackModes: [.artifactPreview, .narrativeOnly, .simplifiedRenderer, .staticSnapshot],
            lifecycle: RichAnswerRendererLifecycle(createsRuntime: true),
            specContract: RichAnswerRenderSpecContract(
                requiredRootFields: ["image", "layers"],
                optionalRootFields: ["annotations", "caption", "comparison", "measurement", "objectFit", "showReadout", "title"],
                allowAdditionalRootFields: false,
                maxDepth: 10,
                maxObjectFields: 260,
                maxArrayItems: 1_200,
                maxStringLength: 1_500_000
            ),
            compatibilityAdapter: "controlled_image_overlay"
        )
    }
    
    private static func validateMathFunctionSpec(
        _ plan: RichAnswerRenderPlan
    ) -> [RichAnswerCapabilityMismatchIssue] {
        guard case let .object(domain)? = plan.spec["domain"],
              case let .number(minimum)? = domain["minimum"],
              case let .number(maximum)? = domain["maximum"],
              minimum.isFinite,
              maximum.isFinite,
              minimum < maximum else {
            return [
                RichAnswerCapabilityMismatchIssue(
                    code: .specContractViolation,
                    renderer: mathFunctionRenderer,
                    field: "spec.domain",
                    message: "函数定义域必须是有限区间，且 minimum < maximum",
                    repairHint: "提交明确的 domain.minimum 和 domain.maximum，不要提交采样点。"
                ),
            ]
        }
        guard case let .object(expression)? = plan.spec["expression"],
              case let .string(rootNodeID)? = expression["rootNodeID"],
              case let .array(rawNodes)? = expression["nodes"],
              !rootNodeID.isEmpty,
              !rawNodes.isEmpty,
              rawNodes.count <= 64 else {
            return [
                RichAnswerCapabilityMismatchIssue(
                    code: .specContractViolation,
                    renderer: mathFunctionRenderer,
                    field: "spec.expression",
                    message: "函数 expression 必须包含 rootNodeID 和 1–64 个受限节点",
                    repairHint: "只提交常数、变量、参数和白名单运算节点，不要提交公式代码。"
                ),
            ]
        }
        let nodeIDs = Set(rawNodes.compactMap { value -> String? in
            guard case let .object(node) = value,
                  case let .string(id)? = node["id"],
                  !id.isEmpty else { return nil }
            return id
        })
        guard nodeIDs.count == rawNodes.count, nodeIDs.contains(rootNodeID) else {
            return [
                RichAnswerCapabilityMismatchIssue(
                    code: .specContractViolation,
                    renderer: mathFunctionRenderer,
                    field: "spec.expression.nodes",
                    message: "函数表达式节点 id 必须唯一，rootNodeID 必须可解析",
                    repairHint: "为每个节点使用唯一 id，并让 rootNodeID 引用最终运算节点。"
                ),
            ]
        }
        return []
    }
    
    private static func validateStandardChartSpec(
        _ plan: RichAnswerRenderPlan
    ) -> [RichAnswerCapabilityMismatchIssue] {
        let supportedChartKinds = ["area", "bar", "histogram", "line", "mixed", "scatter"]
        guard case let .string(chartKind)? = plan.spec["chartKind"],
              supportedChartKinds.contains(chartKind) else {
            return [
                RichAnswerCapabilityMismatchIssue(
                    code: .specContractViolation,
                    renderer: standardChartRenderer,
                    field: "spec.chartKind",
                    requested: plan.spec["chartKind"].map { ["\($0)"] } ?? [],
                    supported: supportedChartKinds,
                    message: "标准数据图只支持 line、bar、area、scatter、mixed、histogram",
                    repairHint: "把 chartKind 改为标准图表类型，不要提交底层 ECharts option。"
                ),
            ]
        }
        if chartKind == "scatter" {
            if plan.spec["xLabels"] != nil {
                return [
                    RichAnswerCapabilityMismatchIssue(
                        code: .specContractViolation,
                        renderer: standardChartRenderer,
                        field: "spec.xLabels",
                        message: "scatter 使用 series[].xValues，不接受分类 xLabels",
                        repairHint: "删除 xLabels，并为每个 series 提供与 values 等长的 xValues。"
                    ),
                ]
            }
            guard case let .array(rawSeries)? = plan.spec["series"], !rawSeries.isEmpty else {
                return [
                    RichAnswerCapabilityMismatchIssue(
                        code: .specContractViolation,
                        renderer: standardChartRenderer,
                        field: "spec.series",
                        message: "scatter 必须提供至少一个数值系列",
                        repairHint: "为每个系列提交 name、values 和等长的 xValues。"
                    ),
                ]
            }
            for (index, value) in rawSeries.enumerated() {
                guard case let .object(series) = value,
                      case let .array(values)? = series["values"],
                      case let .array(xValues)? = series["xValues"],
                      !values.isEmpty,
                      values.count == xValues.count else {
                    return [
                        RichAnswerCapabilityMismatchIssue(
                            code: .specContractViolation,
                            renderer: standardChartRenderer,
                            field: "spec.series[\(index)].xValues",
                            message: "scatter 的 xValues 必须存在并与 values 等长",
                            repairHint: "提交成对的 xValues/values 数值，不要改用分类 xLabels。"
                        ),
                    ]
                }
            }
            return []
        }
        guard chartKind == "mixed" else { return [] }
        guard case let .array(rawSeries)? = plan.spec["series"] else {
            return [
                RichAnswerCapabilityMismatchIssue(
                    code: .specContractViolation,
                    renderer: standardChartRenderer,
                    field: "spec.series",
                    message: "mixed 图必须提供带相同 unit 的系列",
                    repairHint: "为每个 series 声明同一个 unit；跨单位比较改用已注册双轴或归一化渲染器。"
                ),
            ]
        }
        let units = rawSeries.compactMap { value -> String? in
            guard case let .object(series) = value,
                  case let .string(unit)? = series["unit"] else { return nil }
            let trimmed = unit.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard units.count == rawSeries.count, Set(units).count == 1 else {
            return [
                RichAnswerCapabilityMismatchIssue(
                    code: .specContractViolation,
                    renderer: standardChartRenderer,
                    field: "spec.series[].unit",
                    requested: units,
                    message: "mixed 图不能把不同单位放在同一纵轴",
                    repairHint: "为每个 series 声明同一个 unit；跨单位比较改用已注册双轴或归一化渲染器。"
                ),
            ]
        }
        return []
    }
}
