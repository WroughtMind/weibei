import Foundation

public struct RichAnswerRendererCapabilitySet: Codable, Hashable, Sendable {
    public var families: Set<String>
    public var actions: Set<String>
    public var knowledgeNatures: Set<String>
    public var surfaces: Set<String>
    public var dataKinds: Set<RichAnswerRendererDataKind>
    public var interactions: Set<RichAnswerRenderInteractionKind>
    public var artifactKinds: Set<String>
    public var resources: Set<RichAnswerRendererResource>

    public init(
        families: Set<String> = [],
        actions: Set<String> = [],
        knowledgeNatures: Set<String> = [],
        surfaces: Set<String> = [],
        dataKinds: Set<RichAnswerRendererDataKind> = [],
        interactions: Set<RichAnswerRenderInteractionKind> = [],
        artifactKinds: Set<String> = [],
        resources: Set<RichAnswerRendererResource> = []
    ) {
        self.families = families
        self.actions = actions
        self.knowledgeNatures = knowledgeNatures
        self.surfaces = surfaces
        self.dataKinds = dataKinds
        self.interactions = interactions
        self.artifactKinds = artifactKinds
        self.resources = resources
    }
}

public struct RichAnswerRendererLifecycle: Codable, Hashable, Sendable {
    public var createsRuntime: Bool
    public var supportsStreamingPatch: Bool
    public var supportsDynamicHeight: Bool
    public var needsExplicitTeardown: Bool

    public init(
        createsRuntime: Bool = false,
        supportsStreamingPatch: Bool = false,
        supportsDynamicHeight: Bool = true,
        needsExplicitTeardown: Bool = false
    ) {
        self.createsRuntime = createsRuntime
        self.supportsStreamingPatch = supportsStreamingPatch
        self.supportsDynamicHeight = supportsDynamicHeight
        self.needsExplicitTeardown = needsExplicitTeardown
    }
}

public struct RichAnswerRendererCapabilityDeclaration: Codable, Hashable, Sendable {
    public var renderer: String
    public var displayName: String
    public var purpose: String
    public var specVersions: Set<String>
    public var preferredSpecVersion: String
    public var capabilities: RichAnswerRendererCapabilitySet
    public var limits: RichAnswerRenderQualityBudget
    public var fallbackModes: Set<RichAnswerRenderFallbackMode>
    public var lifecycle: RichAnswerRendererLifecycle
    public var specContract: RichAnswerRenderSpecContract
    public var compatibilityAdapter: String?

    public init(
        renderer: String,
        displayName: String,
        purpose: String,
        specVersions: Set<String>,
        preferredSpecVersion: String,
        capabilities: RichAnswerRendererCapabilitySet,
        limits: RichAnswerRenderQualityBudget,
        fallbackModes: Set<RichAnswerRenderFallbackMode>,
        lifecycle: RichAnswerRendererLifecycle = RichAnswerRendererLifecycle(),
        specContract: RichAnswerRenderSpecContract = RichAnswerRenderSpecContract(),
        compatibilityAdapter: String? = nil
    ) {
        self.renderer = renderer
        self.displayName = displayName
        self.purpose = purpose
        self.specVersions = specVersions
        self.preferredSpecVersion = preferredSpecVersion
        self.capabilities = capabilities
        self.limits = limits
        self.fallbackModes = fallbackModes
        self.lifecycle = lifecycle
        self.specContract = specContract
        self.compatibilityAdapter = compatibilityAdapter
    }
}

public struct RichAnswerRenderNegotiationResult: Codable, Hashable, Sendable {
    public var status: RichAnswerCapabilityNegotiationStatus
    public var renderer: String?
    public var specVersion: String?
    public var declaration: RichAnswerRendererCapabilityDeclaration?
    public var plan: RichAnswerRenderPlan?
    public var mismatch: RichAnswerCapabilityMismatch?

    public init(
        status: RichAnswerCapabilityNegotiationStatus,
        renderer: String?,
        specVersion: String?,
        declaration: RichAnswerRendererCapabilityDeclaration? = nil,
        plan: RichAnswerRenderPlan? = nil,
        mismatch: RichAnswerCapabilityMismatch? = nil
    ) {
        self.status = status
        self.renderer = renderer
        self.specVersion = specVersion
        self.declaration = declaration
        self.plan = plan
        self.mismatch = mismatch
    }

    public static func accepted(
        declaration: RichAnswerRendererCapabilityDeclaration,
        plan: RichAnswerRenderPlan? = nil
    ) -> RichAnswerRenderNegotiationResult {
        RichAnswerRenderNegotiationResult(
            status: .accepted,
            renderer: declaration.renderer,
            specVersion: plan?.specVersion ?? declaration.preferredSpecVersion,
            declaration: declaration,
            plan: plan
        )
    }

    public static func capabilityMismatch(
        renderer: String?,
        specVersion: String?,
        issues: [RichAnswerCapabilityMismatchIssue]
    ) -> RichAnswerRenderNegotiationResult {
        RichAnswerRenderNegotiationResult(
            status: .capabilityMismatch,
            renderer: renderer,
            specVersion: specVersion,
            mismatch: RichAnswerCapabilityMismatch(
                renderer: renderer,
                specVersion: specVersion,
                issues: issues
            )
        )
    }
}

public enum RichAnswerRendererRegistryError: Error, Equatable {
    case duplicateRenderer(String)
    case emptyRendererIdentifier
    case missingPreferredSpecVersion(String)
}

public struct RichAnswerRendererRegistration: Sendable {
    public var declaration: RichAnswerRendererCapabilityDeclaration
    public var validateSpec: @Sendable (RichAnswerRenderPlan) -> [RichAnswerCapabilityMismatchIssue]

    public init(
        declaration: RichAnswerRendererCapabilityDeclaration,
        validateSpec: (@Sendable (RichAnswerRenderPlan) -> [RichAnswerCapabilityMismatchIssue])? = nil
    ) {
        self.declaration = declaration
        self.validateSpec = validateSpec ?? { _ in [] }
    }
}

public struct RichAnswerRendererRegistry: Sendable {
    public static let openUIProgramRenderer = "weibei.openui.program"
    public static let openUICompositionRenderer = "weibei.openui.composition"

    private var registrationsByRenderer: [String: RichAnswerRendererRegistration]

    public init(registrations: [RichAnswerRendererRegistration] = []) throws {
        registrationsByRenderer = [:]
        for registration in registrations {
            try register(registration)
        }
    }

    public var declarations: [RichAnswerRendererCapabilityDeclaration] {
        registrationsByRenderer.values
            .map(\.declaration)
            .sorted { $0.renderer < $1.renderer }
    }

    public func declaration(for renderer: String) -> RichAnswerRendererCapabilityDeclaration? {
        registrationsByRenderer[renderer]?.declaration
    }

    public mutating func register(_ registration: RichAnswerRendererRegistration) throws {
        let renderer = registration.declaration.renderer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !renderer.isEmpty else {
            throw RichAnswerRendererRegistryError.emptyRendererIdentifier
        }
        guard registration.declaration.specVersions.contains(registration.declaration.preferredSpecVersion) else {
            throw RichAnswerRendererRegistryError.missingPreferredSpecVersion(renderer)
        }
        guard registrationsByRenderer[renderer] == nil else {
            throw RichAnswerRendererRegistryError.duplicateRenderer(renderer)
        }
        registrationsByRenderer[renderer] = registration
    }

    public mutating func registerOrReplace(_ registration: RichAnswerRendererRegistration) throws {
        let renderer = registration.declaration.renderer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !renderer.isEmpty else {
            throw RichAnswerRendererRegistryError.emptyRendererIdentifier
        }
        guard registration.declaration.specVersions.contains(registration.declaration.preferredSpecVersion) else {
            throw RichAnswerRendererRegistryError.missingPreferredSpecVersion(renderer)
        }
        registrationsByRenderer[renderer] = registration
    }

    public func select(
        _ request: RichAnswerRendererCapabilityRequest
    ) -> RichAnswerRenderNegotiationResult {
        if let preferredRenderer = request.preferredRenderer {
            guard let registration = registrationsByRenderer[preferredRenderer] else {
                return .capabilityMismatch(
                    renderer: preferredRenderer,
                    specVersion: request.preferredSpecVersion,
                    issues: [
                        RichAnswerCapabilityMismatchIssue(
                            code: .unknownRenderer,
                            renderer: preferredRenderer,
                            field: "renderer",
                            requested: [preferredRenderer],
                            supported: declarations.map(\.renderer),
                            message: "renderPlan 选择的渲染器尚未注册",
                            repairHint: "调用注册表能力清单，改用已注册渲染器，或先注册新的渲染器适配器。"
                        ),
                    ]
                )
            }
            let issues = requestIssues(for: request, declaration: registration.declaration)
            return issues.isEmpty
                ? .accepted(declaration: registration.declaration)
                : .capabilityMismatch(
                    renderer: preferredRenderer,
                    specVersion: request.preferredSpecVersion,
                    issues: issues
                )
        }

        let scored = registrationsByRenderer.values.map { registration in
            (
                registration: registration,
                issues: requestIssues(for: request, declaration: registration.declaration),
                score: score(registration.declaration, for: request)
            )
        }
        if let accepted = scored
            .filter({ $0.issues.isEmpty })
            .sorted(by: { lhs, rhs in
                lhs.score == rhs.score
                    ? lhs.registration.declaration.renderer < rhs.registration.declaration.renderer
                    : lhs.score > rhs.score
            })
            .first {
            return .accepted(declaration: accepted.registration.declaration)
        }

        let closest = scored
            .sorted(by: { lhs, rhs in
                lhs.issues.count == rhs.issues.count
                    ? lhs.score > rhs.score
                    : lhs.issues.count < rhs.issues.count
            })
            .first
        return .capabilityMismatch(
            renderer: nil,
            specVersion: request.preferredSpecVersion,
            issues: closest?.issues ?? [
                RichAnswerCapabilityMismatchIssue(
                    code: .unknownRenderer,
                    field: "renderer",
                    message: "当前没有可用的富回答渲染器注册声明",
                    repairHint: "先注册至少一个渲染器能力声明，再进行 renderPlan 选择。"
                ),
            ]
        )
    }

    public func negotiate(
        plan: RichAnswerRenderPlan,
        intent: RichAnswerRendererCapabilityRequest? = nil
    ) -> RichAnswerRenderNegotiationResult {
        guard let registration = registrationsByRenderer[plan.renderer] else {
            return .capabilityMismatch(
                renderer: plan.renderer,
                specVersion: plan.specVersion,
                issues: [
                    RichAnswerCapabilityMismatchIssue(
                        code: .unknownRenderer,
                        renderer: plan.renderer,
                        field: "renderer",
                        requested: [plan.renderer],
                        supported: declarations.map(\.renderer),
                        message: "renderPlan 选择的渲染器尚未注册",
                        repairHint: "让模型根据注册表返回的能力清单重新规划，而不是直接降级成纯文本。"
                    ),
                ]
            )
        }

        let request = (intent ?? RichAnswerRendererCapabilityRequest())
            .merging(plan.derivedCapabilityRequest)
        var issues = requestIssues(for: request, declaration: registration.declaration)
        if plan.sourceBindings.isEmpty {
            issues.append(
                RichAnswerCapabilityMismatchIssue(
                    code: .missingSourceBinding,
                    renderer: plan.renderer,
                    field: "sourceBindings",
                    message: "renderPlan 没有绑定任何来源或证据",
                    repairHint: "为视觉参数、数据、结论或降级内容绑定本轮 evidenceID。"
                )
            )
        }
        issues.append(contentsOf: registration.declaration.specContract.validate(plan.spec, renderer: plan.renderer))
        issues.append(contentsOf: registration.validateSpec(plan))

        return issues.isEmpty
            ? .accepted(declaration: registration.declaration, plan: plan)
            : .capabilityMismatch(
                renderer: plan.renderer,
                specVersion: plan.specVersion,
                issues: issues
            )
    }

    public static func compatibilityAdapters() -> RichAnswerRendererRegistry {
        let registrations = [
            RichAnswerRendererRegistration(declaration: openUIProgramDeclaration()),
            RichAnswerRendererRegistration(declaration: openUICompositionDeclaration()),
        ]
        return (try? RichAnswerRendererRegistry(registrations: registrations)) ?? (try! RichAnswerRendererRegistry())
    }

    public static func openUIProgramDeclaration() -> RichAnswerRendererCapabilityDeclaration {
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

    public static func openUICompositionDeclaration() -> RichAnswerRendererCapabilityDeclaration {
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

    private func requestIssues(
        for request: RichAnswerRendererCapabilityRequest,
        declaration: RichAnswerRendererCapabilityDeclaration
    ) -> [RichAnswerCapabilityMismatchIssue] {
        var issues: [RichAnswerCapabilityMismatchIssue] = []
        if let specVersion = request.preferredSpecVersion,
           !declaration.specVersions.contains(specVersion) {
            issues.append(
                issue(
                    .unsupportedSpecVersion,
                    declaration: declaration,
                    field: "specVersion",
                    requested: [specVersion],
                    supported: declaration.specVersions,
                    message: "渲染器不支持请求的 specVersion",
                    repairHint: "改用渲染器声明的 specVersion，或注册新版本适配器。"
                )
            )
        }

        appendUnsupportedStrings(
            request.families,
            supported: declaration.capabilities.families,
            code: .unsupportedFamily,
            field: "families",
            declaration: declaration,
            issues: &issues
        )
        appendUnsupportedStrings(
            request.actions,
            supported: declaration.capabilities.actions,
            code: .unsupportedAction,
            field: "actions",
            declaration: declaration,
            issues: &issues
        )
        appendUnsupportedStrings(
            request.knowledgeNatures,
            supported: declaration.capabilities.knowledgeNatures,
            code: .unsupportedKnowledgeNature,
            field: "knowledgeNatures",
            declaration: declaration,
            issues: &issues
        )
        appendUnsupportedStrings(
            request.surfaces,
            supported: declaration.capabilities.surfaces,
            code: .unsupportedSurface,
            field: "surfaces",
            declaration: declaration,
            issues: &issues
        )
        appendUnsupportedEnums(
            request.dataKinds,
            supported: declaration.capabilities.dataKinds,
            code: .unsupportedDataKind,
            field: "dataKinds",
            declaration: declaration,
            issues: &issues
        )
        appendUnsupportedEnums(
            request.interactions,
            supported: declaration.capabilities.interactions,
            code: .unsupportedInteraction,
            field: "interactionBindings",
            declaration: declaration,
            issues: &issues
        )
        appendUnsupportedStrings(
            request.artifactKinds,
            supported: declaration.capabilities.artifactKinds,
            code: .unsupportedArtifact,
            field: "artifactRefs",
            declaration: declaration,
            issues: &issues
        )
        appendUnsupportedEnums(
            request.resources,
            supported: declaration.capabilities.resources,
            code: .unsupportedResource,
            field: "resources",
            declaration: declaration,
            issues: &issues
        )
        appendUnsupportedEnums(
            request.fallbackModes,
            supported: declaration.fallbackModes,
            code: .fallbackUnavailable,
            field: "fallback",
            declaration: declaration,
            issues: &issues
        )
        issues.append(contentsOf: budgetIssues(request.qualityBudget, declaration: declaration))
        return issues
    }

    private func budgetIssues(
        _ requested: RichAnswerRenderQualityBudget,
        declaration: RichAnswerRendererCapabilityDeclaration
    ) -> [RichAnswerCapabilityMismatchIssue] {
        var issues: [RichAnswerCapabilityMismatchIssue] = []
        appendBudgetIssue(requested.maxNodes, limit: declaration.limits.maxNodes, field: "qualityBudget.maxNodes", declaration: declaration, issues: &issues)
        appendBudgetIssue(requested.maxDataPoints, limit: declaration.limits.maxDataPoints, field: "qualityBudget.maxDataPoints", declaration: declaration, issues: &issues)
        appendBudgetIssue(requested.maxArtifacts, limit: declaration.limits.maxArtifacts, field: "qualityBudget.maxArtifacts", declaration: declaration, issues: &issues)
        appendBudgetIssue(requested.maxBytes, limit: declaration.limits.maxBytes, field: "qualityBudget.maxBytes", declaration: declaration, issues: &issues)
        appendBudgetIssue(requested.maxWidth, limit: declaration.limits.maxWidth, field: "qualityBudget.maxWidth", declaration: declaration, issues: &issues)
        appendBudgetIssue(requested.maxHeight, limit: declaration.limits.maxHeight, field: "qualityBudget.maxHeight", declaration: declaration, issues: &issues)
        appendBudgetIssue(requested.maxAnimationFPS, limit: declaration.limits.maxAnimationFPS, field: "qualityBudget.maxAnimationFPS", declaration: declaration, issues: &issues)
        appendBudgetIssue(requested.maxInteractionLatencyMS, limit: declaration.limits.maxInteractionLatencyMS, field: "qualityBudget.maxInteractionLatencyMS", declaration: declaration, issues: &issues)

        if requested.allowWebGL && !declaration.limits.allowWebGL {
            issues.append(
                issue(
                    .unsupportedResource,
                    declaration: declaration,
                    field: "qualityBudget.allowWebGL",
                    requested: ["true"],
                    supported: ["false"],
                    message: "渲染器能力声明不允许 WebGL",
                    repairHint: "改用支持 WebGL 的渲染器，或重新规划成 Canvas/DOM/静态产物。"
                )
            )
        }
        if requested.allowNetwork && !declaration.limits.allowNetwork {
            issues.append(
                issue(
                    .unsupportedResource,
                    declaration: declaration,
                    field: "qualityBudget.allowNetwork",
                    requested: ["true"],
                    supported: ["false"],
                    message: "renderPlan 不允许通过网络加载外部资源",
                    repairHint: "把资源纳入受控 artifactRefs 或本地 bundle，不要依赖外部 URL。"
                )
            )
        }
        if requested.allowAnimation && !declaration.limits.allowAnimation {
            issues.append(
                issue(
                    .budgetExceeded,
                    declaration: declaration,
                    field: "qualityBudget.allowAnimation",
                    requested: ["true"],
                    supported: ["false"],
                    message: "渲染器能力声明不允许动画",
                    repairHint: "改成静态快照、步进控件或低动态解释。"
                )
            )
        }
        return issues
    }

    private func appendBudgetIssue(
        _ requested: Int?,
        limit: Int?,
        field: String,
        declaration: RichAnswerRendererCapabilityDeclaration,
        issues: inout [RichAnswerCapabilityMismatchIssue]
    ) {
        guard let requested, let limit, requested > limit else { return }
        issues.append(
            issue(
                .budgetExceeded,
                declaration: declaration,
                field: field,
                requested: ["\(requested)"],
                supported: ["\(limit)"],
                message: "renderPlan 超出渲染器质量预算 \(field)",
                repairHint: "降低节点、数据、尺寸或动画预算，或选择更强的注册渲染器。"
            )
        )
    }

    private func appendUnsupportedStrings(
        _ requested: Set<String>,
        supported: Set<String>,
        code: RichAnswerCapabilityMismatchCode,
        field: String,
        declaration: RichAnswerRendererCapabilityDeclaration,
        issues: inout [RichAnswerCapabilityMismatchIssue]
    ) {
        guard !supported.isEmpty else { return }
        let unsupported = requested.subtracting(supported)
        guard !unsupported.isEmpty else { return }
        issues.append(
            issue(
                code,
                declaration: declaration,
                field: field,
                requested: Array(unsupported).sorted(),
                supported: Array(supported).sorted(),
                message: "渲染器能力声明不覆盖请求的 \(field)",
                repairHint: "换用覆盖该能力的渲染器，或让模型重新规划学习表达。"
            )
        )
    }

    private func appendUnsupportedEnums<T: RawRepresentable & Hashable>(
        _ requested: Set<T>,
        supported: Set<T>,
        code: RichAnswerCapabilityMismatchCode,
        field: String,
        declaration: RichAnswerRendererCapabilityDeclaration,
        issues: inout [RichAnswerCapabilityMismatchIssue]
    ) where T.RawValue == String {
        guard !supported.isEmpty else { return }
        let unsupported = requested.subtracting(supported)
        guard !unsupported.isEmpty else { return }
        issues.append(
            issue(
                code,
                declaration: declaration,
                field: field,
                requested: unsupported.map(\.rawValue).sorted(),
                supported: supported.map(\.rawValue).sorted(),
                message: "渲染器能力声明不覆盖请求的 \(field)",
                repairHint: "换用覆盖该能力的渲染器，或减少 renderPlan 的交互、数据或资源要求。"
            )
        )
    }

    private func issue(
        _ code: RichAnswerCapabilityMismatchCode,
        declaration: RichAnswerRendererCapabilityDeclaration,
        field: String,
        requested: [String],
        supported: Set<String>,
        message: String,
        repairHint: String
    ) -> RichAnswerCapabilityMismatchIssue {
        issue(
            code,
            declaration: declaration,
            field: field,
            requested: requested,
            supported: Array(supported).sorted(),
            message: message,
            repairHint: repairHint
        )
    }

    private func issue(
        _ code: RichAnswerCapabilityMismatchCode,
        declaration: RichAnswerRendererCapabilityDeclaration,
        field: String,
        requested: [String],
        supported: [String],
        message: String,
        repairHint: String
    ) -> RichAnswerCapabilityMismatchIssue {
        RichAnswerCapabilityMismatchIssue(
            code: code,
            renderer: declaration.renderer,
            field: field,
            requested: requested,
            supported: supported,
            message: message,
            repairHint: repairHint
        )
    }

    private func score(
        _ declaration: RichAnswerRendererCapabilityDeclaration,
        for request: RichAnswerRendererCapabilityRequest
    ) -> Int {
        var score = 0
        score += intersectionCount(request.dataKinds, declaration.capabilities.dataKinds) * 5
        score += intersectionCount(request.interactions, declaration.capabilities.interactions) * 4
        score += intersectionCount(request.resources, declaration.capabilities.resources) * 3
        score += request.artifactKinds.intersection(declaration.capabilities.artifactKinds).count * 3
        score += request.fallbackModes.intersection(declaration.fallbackModes).count
        return score
    }

    private func intersectionCount<T: Hashable>(_ lhs: Set<T>, _ rhs: Set<T>) -> Int {
        guard !rhs.isEmpty else { return lhs.isEmpty ? 0 : 1 }
        return lhs.intersection(rhs).count
    }
}

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
        if mismatch.status != .capabilityMismatch
            || mismatch.mismatch?.issues.first?.code != .unknownRenderer {
            diagnostics.append("unknown renderer did not report capability_mismatch")
        }
        return RichAnswerRendererRegistrySelfCheckReport(
            acceptedCompatibilityPlan: accepted.status == .accepted,
            reportsCapabilityMismatch: mismatch.status == .capabilityMismatch,
            diagnostics: diagnostics
        )
    }
}
