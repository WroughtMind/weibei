import Foundation

public enum RichAnswerCapabilityNegotiationStatus: String, Codable, Hashable, Sendable {
    case accepted
    case capabilityMismatch = "capability_mismatch"
}

public enum RichAnswerCapabilityMismatchCode: String, Codable, Hashable, Sendable {
    case unknownRenderer = "unknown_renderer"
    case unsupportedSpecVersion = "unsupported_spec_version"
    case unsupportedFamily = "unsupported_family"
    case unsupportedAction = "unsupported_action"
    case unsupportedKnowledgeNature = "unsupported_knowledge_nature"
    case unsupportedSurface = "unsupported_surface"
    case unsupportedDataKind = "unsupported_data_kind"
    case unsupportedInteraction = "unsupported_interaction"
    case unsupportedArtifact = "unsupported_artifact"
    case unsupportedResource = "unsupported_resource"
    case fallbackUnavailable = "fallback_unavailable"
    case budgetExceeded = "budget_exceeded"
    case specContractViolation = "spec_contract_violation"
}

public struct RichAnswerCapabilityMismatchIssue: Codable, Hashable, Sendable {
    public var code: RichAnswerCapabilityMismatchCode
    public var renderer: String?
    public var field: String?
    public var requested: [String]
    public var supported: [String]
    public var message: String
    public var repairHint: String

    public init(
        code: RichAnswerCapabilityMismatchCode,
        renderer: String? = nil,
        field: String? = nil,
        requested: [String] = [],
        supported: [String] = [],
        message: String,
        repairHint: String
    ) {
        self.code = code
        self.renderer = renderer
        self.field = field
        self.requested = requested
        self.supported = supported
        self.message = message
        self.repairHint = repairHint
    }
}

public struct RichAnswerCapabilityMismatch: Codable, Hashable, Sendable {
    public var status: RichAnswerCapabilityNegotiationStatus
    public var renderer: String?
    public var specVersion: String?
    public var issues: [RichAnswerCapabilityMismatchIssue]
    public var recoveryHint: String

    public init(
        renderer: String?,
        specVersion: String? = nil,
        issues: [RichAnswerCapabilityMismatchIssue],
        recoveryHint: String = "重新选择已注册渲染器，或降低规格、交互、产物和质量预算后重新提交完整 renderPlan。"
    ) {
        self.status = .capabilityMismatch
        self.renderer = renderer
        self.specVersion = specVersion
        self.issues = issues
        self.recoveryHint = recoveryHint
    }
}

public enum RichAnswerRenderSpecValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([RichAnswerRenderSpecValue])
    case object([String: RichAnswerRenderSpecValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .number(Double(value))
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([RichAnswerRenderSpecValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: RichAnswerRenderSpecValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "renderPlan.spec only accepts null, bool, number, string, array, or object values"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case let .bool(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        }
    }
}

public struct RichAnswerRenderSpec: Codable, Hashable, Sendable {
    public var fields: [String: RichAnswerRenderSpecValue]

    public init(fields: [String: RichAnswerRenderSpecValue] = [:]) {
        self.fields = fields
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        fields = try container.decode([String: RichAnswerRenderSpecValue].self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(fields)
    }

    public subscript(_ key: String) -> RichAnswerRenderSpecValue? {
        get { fields[key] }
        set { fields[key] = newValue }
    }
}

public struct RichAnswerRenderSpecContract: Codable, Hashable, Sendable {
    public static let defaultForbiddenFieldNames: Set<String> = [
        "css",
        "echartsOption",
        "html",
        "iframe",
        "javascript",
        "pathData",
        "plotlyFigure",
        "rawConfig",
        "script",
        "svgPath",
    ]

    public var requiredRootFields: Set<String>
    public var optionalRootFields: Set<String>
    public var allowAdditionalRootFields: Bool
    public var forbiddenFieldNames: Set<String>
    public var maxDepth: Int
    public var maxObjectFields: Int
    public var maxArrayItems: Int
    public var maxStringLength: Int

    public init(
        requiredRootFields: Set<String> = [],
        optionalRootFields: Set<String> = [],
        allowAdditionalRootFields: Bool = false,
        forbiddenFieldNames: Set<String>? = nil,
        maxDepth: Int = 8,
        maxObjectFields: Int = 80,
        maxArrayItems: Int = 256,
        maxStringLength: Int = 4_000
    ) {
        self.requiredRootFields = requiredRootFields
        self.optionalRootFields = optionalRootFields
        self.allowAdditionalRootFields = allowAdditionalRootFields
        self.forbiddenFieldNames = forbiddenFieldNames ?? Self.defaultForbiddenFieldNames
        self.maxDepth = maxDepth
        self.maxObjectFields = maxObjectFields
        self.maxArrayItems = maxArrayItems
        self.maxStringLength = maxStringLength
    }

    public func validate(_ spec: RichAnswerRenderSpec, renderer: String) -> [RichAnswerCapabilityMismatchIssue] {
        var issues: [RichAnswerCapabilityMismatchIssue] = []
        let allowedRootFields = requiredRootFields.union(optionalRootFields)

        for field in requiredRootFields where spec.fields[field] == nil {
            issues.append(
                RichAnswerCapabilityMismatchIssue(
                    code: .specContractViolation,
                    renderer: renderer,
                    field: "spec.\(field)",
                    requested: [],
                    supported: Array(requiredRootFields).sorted(),
                    message: "renderPlan.spec 缺少渲染器要求的高层字段 \(field)",
                    repairHint: "补齐 \(renderer) 的高层规格字段，不要改用底层图形配置绕过。"
                )
            )
        }

        if !allowAdditionalRootFields {
            for field in spec.fields.keys where !allowedRootFields.contains(field) {
                issues.append(
                    RichAnswerCapabilityMismatchIssue(
                        code: .specContractViolation,
                        renderer: renderer,
                        field: "spec.\(field)",
                        requested: [field],
                        supported: Array(allowedRootFields).sorted(),
                        message: "renderPlan.spec 包含该渲染器未声明的根字段 \(field)",
                        repairHint: "只提交渲染器能力声明允许的高层字段；需要新字段时先扩展渲染器注册声明。"
                    )
                )
            }
        }

        let forbidden = Set(forbiddenFieldNames.map { $0.lowercased() })
        inspectObject(
            spec.fields,
            path: "spec",
            depth: 1,
            forbidden: forbidden,
            issues: &issues,
            renderer: renderer
        )
        return issues
    }

    private func inspectObject(
        _ object: [String: RichAnswerRenderSpecValue],
        path: String,
        depth: Int,
        forbidden: Set<String>,
        issues: inout [RichAnswerCapabilityMismatchIssue],
        renderer: String
    ) {
        if depth > maxDepth {
            issues.append(
                RichAnswerCapabilityMismatchIssue(
                    code: .budgetExceeded,
                    renderer: renderer,
                    field: path,
                    message: "renderPlan.spec 超过允许的嵌套深度",
                    repairHint: "把规格压缩成高层参数，避免把底层图形树塞进 spec。"
                )
            )
            return
        }
        if object.count > maxObjectFields {
            issues.append(
                RichAnswerCapabilityMismatchIssue(
                    code: .budgetExceeded,
                    renderer: renderer,
                    field: path,
                    requested: ["\(object.count)"],
                    supported: ["\(maxObjectFields)"],
                    message: "renderPlan.spec 对象字段数量超过预算",
                    repairHint: "改用数据产物引用或渲染器高层参数，不要内联大量底层字段。"
                )
            )
        }
        for (key, value) in object {
            let fieldPath = "\(path).\(key)"
            if forbidden.contains(key.lowercased()) {
                issues.append(
                    RichAnswerCapabilityMismatchIssue(
                        code: .specContractViolation,
                        renderer: renderer,
                        field: fieldPath,
                        requested: [key],
                        message: "renderPlan.spec 不接受底层配置、脚本、HTML 或复杂 path 字段 \(key)",
                        repairHint: "提交学习语义和受限高层规格，由注册渲染器编译具体配置。"
                    )
                )
            }
            inspectValue(value, path: fieldPath, depth: depth + 1, forbidden: forbidden, issues: &issues, renderer: renderer)
        }
    }

    private func inspectValue(
        _ value: RichAnswerRenderSpecValue,
        path: String,
        depth: Int,
        forbidden: Set<String>,
        issues: inout [RichAnswerCapabilityMismatchIssue],
        renderer: String
    ) {
        switch value {
        case .null, .bool, .number:
            return
        case let .string(text):
            if text.count > maxStringLength {
                issues.append(
                    RichAnswerCapabilityMismatchIssue(
                        code: .budgetExceeded,
                        renderer: renderer,
                        field: path,
                        requested: ["\(text.count)"],
                        supported: ["\(maxStringLength)"],
                        message: "renderPlan.spec 字符串超过预算",
                        repairHint: "长文本、数据或产物应通过 sourceBindings 或 artifactRefs 引用。"
                    )
                )
            }
        case let .array(items):
            if items.count > maxArrayItems {
                issues.append(
                    RichAnswerCapabilityMismatchIssue(
                        code: .budgetExceeded,
                        renderer: renderer,
                        field: path,
                        requested: ["\(items.count)"],
                        supported: ["\(maxArrayItems)"],
                        message: "renderPlan.spec 数组长度超过预算",
                        repairHint: "用受控数据产物或采样摘要承载大数组。"
                    )
                )
            }
            for (index, item) in items.enumerated() {
                inspectValue(item, path: "\(path)[\(index)]", depth: depth + 1, forbidden: forbidden, issues: &issues, renderer: renderer)
            }
        case let .object(object):
            inspectObject(object, path: path, depth: depth, forbidden: forbidden, issues: &issues, renderer: renderer)
        }
    }
}

public enum RichAnswerRendererDataKind: String, Codable, CaseIterable, Hashable, Sendable {
    case artifactReference
    case functionExpression
    case geometry
    case imageRaster
    case imageVector
    case mesh3D
    case semanticGraph
    case simulationState
    case tabularData
    case textEvidence
    case timeSeries
    case vectorField
}

public enum RichAnswerRenderInteractionKind: String, Codable, CaseIterable, Hashable, Sendable {
    case annotation
    case brush
    case picker
    case playPause
    case probe
    case scrubber
    case select
    case slider
    case sourceJump
    case stateReveal
    case step
    case toggle
    case zoomPan
}

public enum RichAnswerRenderFallbackMode: String, Codable, CaseIterable, Hashable, Sendable {
    case artifactPreview
    case narrativeOnly
    case simplifiedRenderer
    case staticSnapshot
}

public enum RichAnswerRendererResource: String, Codable, CaseIterable, Hashable, Sendable {
    case canvas2D
    case dom
    case localArtifact
    case nativeSwiftUI
    case pythonTool
    case webGL
    case webKitBridge
    case webWorker
}

public struct RichAnswerRenderQualityBudget: Codable, Hashable, Sendable {
    public var maxNodes: Int?
    public var maxDataPoints: Int?
    public var maxArtifacts: Int?
    public var maxBytes: Int?
    public var maxWidth: Int?
    public var maxHeight: Int?
    public var maxAnimationFPS: Int?
    public var maxInteractionLatencyMS: Int?
    public var allowAnimation: Bool
    public var allowWebGL: Bool
    public var allowNetwork: Bool

    public init(
        maxNodes: Int? = nil,
        maxDataPoints: Int? = nil,
        maxArtifacts: Int? = nil,
        maxBytes: Int? = nil,
        maxWidth: Int? = nil,
        maxHeight: Int? = nil,
        maxAnimationFPS: Int? = nil,
        maxInteractionLatencyMS: Int? = nil,
        allowAnimation: Bool = true,
        allowWebGL: Bool = false,
        allowNetwork: Bool = false
    ) {
        self.maxNodes = maxNodes
        self.maxDataPoints = maxDataPoints
        self.maxArtifacts = maxArtifacts
        self.maxBytes = maxBytes
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
        self.maxAnimationFPS = maxAnimationFPS
        self.maxInteractionLatencyMS = maxInteractionLatencyMS
        self.allowAnimation = allowAnimation
        self.allowWebGL = allowWebGL
        self.allowNetwork = allowNetwork
    }

    public func merging(_ other: RichAnswerRenderQualityBudget) -> RichAnswerRenderQualityBudget {
        RichAnswerRenderQualityBudget(
            maxNodes: maxOptional(maxNodes, other.maxNodes),
            maxDataPoints: maxOptional(maxDataPoints, other.maxDataPoints),
            maxArtifacts: maxOptional(maxArtifacts, other.maxArtifacts),
            maxBytes: maxOptional(maxBytes, other.maxBytes),
            maxWidth: maxOptional(maxWidth, other.maxWidth),
            maxHeight: maxOptional(maxHeight, other.maxHeight),
            maxAnimationFPS: maxOptional(maxAnimationFPS, other.maxAnimationFPS),
            maxInteractionLatencyMS: maxOptional(maxInteractionLatencyMS, other.maxInteractionLatencyMS),
            allowAnimation: allowAnimation || other.allowAnimation,
            allowWebGL: allowWebGL || other.allowWebGL,
            allowNetwork: allowNetwork || other.allowNetwork
        )
    }
}

public struct RichAnswerRenderInteractionBinding: Codable, Hashable, Sendable {
    public var id: String
    public var kind: RichAnswerRenderInteractionKind
    public var target: String
    public var stateKey: String?
    public var actionName: String?
    public var knowledgeStateEffect: String?

    public init(
        id: String,
        kind: RichAnswerRenderInteractionKind,
        target: String,
        stateKey: String? = nil,
        actionName: String? = nil,
        knowledgeStateEffect: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.target = target
        self.stateKey = stateKey
        self.actionName = actionName
        self.knowledgeStateEffect = knowledgeStateEffect
    }
}

public struct RichAnswerRenderSourceBinding: Codable, Hashable, Sendable {
    public var id: String
    public var evidenceID: String
    public var target: String
    public var role: String
    public var requiredForFallback: Bool

    public init(
        id: String,
        evidenceID: String,
        target: String,
        role: String,
        requiredForFallback: Bool = false
    ) {
        self.id = id
        self.evidenceID = evidenceID
        self.target = target
        self.role = role
        self.requiredForFallback = requiredForFallback
    }

    private enum CodingKeys: String, CodingKey {
        case id, evidenceID, target, role, requiredForFallback
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        evidenceID = try container.decode(String.self, forKey: .evidenceID)
        target = try container.decode(String.self, forKey: .target)
        role = try container.decode(String.self, forKey: .role)
        requiredForFallback = try container.decodeIfPresent(
            Bool.self,
            forKey: .requiredForFallback
        ) ?? false
    }
}

public struct RichAnswerRenderArtifactRef: Codable, Hashable, Sendable {
    public var id: String
    public var kind: String
    public var mimeType: String
    public var role: String
    public var width: Int?
    public var height: Int?
    public var sizeBytes: Int?
    public var checksum: String?
    public var summary: String?
    public var metadata: [String: RichAnswerRenderSpecValue]

    public init(
        id: String,
        kind: String,
        mimeType: String,
        role: String,
        width: Int? = nil,
        height: Int? = nil,
        sizeBytes: Int? = nil,
        checksum: String? = nil,
        summary: String? = nil,
        metadata: [String: RichAnswerRenderSpecValue] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.mimeType = mimeType
        self.role = role
        self.width = width
        self.height = height
        self.sizeBytes = sizeBytes
        self.checksum = checksum
        self.summary = summary
        self.metadata = metadata
    }
}

public struct RichAnswerRenderFallback: Codable, Hashable, Sendable {
    public var mode: RichAnswerRenderFallbackMode
    public var reason: String
    public var text: String
    public var renderer: String?
    public var artifactID: String?
    public var preservesSourceBinding: Bool

    public init(
        mode: RichAnswerRenderFallbackMode,
        reason: String,
        text: String,
        renderer: String? = nil,
        artifactID: String? = nil,
        preservesSourceBinding: Bool = false
    ) {
        self.mode = mode
        self.reason = reason
        self.text = text
        self.renderer = renderer
        self.artifactID = artifactID
        self.preservesSourceBinding = preservesSourceBinding
    }

    private enum CodingKeys: String, CodingKey {
        case mode, reason, text, renderer, artifactID, preservesSourceBinding
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decode(RichAnswerRenderFallbackMode.self, forKey: .mode)
        reason = try container.decode(String.self, forKey: .reason)
        text = try container.decode(String.self, forKey: .text)
        renderer = try container.decodeIfPresent(String.self, forKey: .renderer)
        artifactID = try container.decodeIfPresent(String.self, forKey: .artifactID)
        preservesSourceBinding = try container.decodeIfPresent(
            Bool.self,
            forKey: .preservesSourceBinding
        ) ?? false
    }
}

public struct RichAnswerRenderPlan: Codable, Hashable, Sendable {
    public var renderer: String
    public var specVersion: String
    public var spec: RichAnswerRenderSpec
    public var interactionBindings: [RichAnswerRenderInteractionBinding]
    public var sourceBindings: [RichAnswerRenderSourceBinding]
    public var artifactRefs: [RichAnswerRenderArtifactRef]
    public var fallback: RichAnswerRenderFallback
    public var qualityBudget: RichAnswerRenderQualityBudget

    public init(
        renderer: String,
        specVersion: String,
        spec: RichAnswerRenderSpec,
        interactionBindings: [RichAnswerRenderInteractionBinding] = [],
        sourceBindings: [RichAnswerRenderSourceBinding] = [],
        artifactRefs: [RichAnswerRenderArtifactRef] = [],
        fallback: RichAnswerRenderFallback,
        qualityBudget: RichAnswerRenderQualityBudget = RichAnswerRenderQualityBudget()
    ) {
        self.renderer = renderer
        self.specVersion = specVersion
        self.spec = spec
        self.interactionBindings = interactionBindings
        self.sourceBindings = sourceBindings
        self.artifactRefs = artifactRefs
        self.fallback = fallback
        self.qualityBudget = qualityBudget
    }

    private enum CodingKeys: String, CodingKey {
        case renderer, specVersion, spec, interactionBindings, sourceBindings
        case artifactRefs, fallback, qualityBudget
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        renderer = try container.decode(String.self, forKey: .renderer)
        specVersion = try container.decode(String.self, forKey: .specVersion)
        spec = try container.decode(RichAnswerRenderSpec.self, forKey: .spec)
        interactionBindings = try container.decodeIfPresent(
            [RichAnswerRenderInteractionBinding].self,
            forKey: .interactionBindings
        ) ?? []
        sourceBindings = try container.decodeIfPresent(
            [RichAnswerRenderSourceBinding].self,
            forKey: .sourceBindings
        ) ?? []
        artifactRefs = try container.decodeIfPresent(
            [RichAnswerRenderArtifactRef].self,
            forKey: .artifactRefs
        ) ?? []
        fallback = try container.decode(RichAnswerRenderFallback.self, forKey: .fallback)
        qualityBudget = try container.decodeIfPresent(
            RichAnswerRenderQualityBudget.self,
            forKey: .qualityBudget
        ) ?? RichAnswerRenderQualityBudget()
    }

    public var derivedCapabilityRequest: RichAnswerRendererCapabilityRequest {
        RichAnswerRendererCapabilityRequest(
            preferredRenderer: renderer,
            preferredSpecVersion: specVersion,
            interactions: Set(interactionBindings.map(\.kind)),
            artifactKinds: Set(artifactRefs.map(\.kind)),
            fallbackModes: [fallback.mode],
            qualityBudget: qualityBudget
        )
    }

    public var referencedAssetIDs: Set<String> {
        Set(spec.fields.values.flatMap(\.referencedAssetIDs))
    }

    public var referencedAssetBytes: [Int] {
        artifactRefs.compactMap { artifact in
            guard referencedAssetIDs.contains(artifact.id) else { return nil }
            return artifact.sizeBytes
        }
    }
}

private extension RichAnswerRenderSpecValue {
    var referencedAssetIDs: [String] {
        switch self {
        case .null, .bool, .number, .string:
            return []
        case let .array(values):
            return values.flatMap(\.referencedAssetIDs)
        case let .object(fields):
            var ids = fields.values.flatMap(\.referencedAssetIDs)
            if case let .string(kind)? = fields["kind"],
               kind == "assetRef",
               case let .string(source)? = fields["source"] {
                let normalized = source.trimmingCharacters(in: .whitespacesAndNewlines)
                if !normalized.isEmpty {
                    ids.append(normalized)
                }
            }
            return ids
        }
    }
}

public struct RichAnswerRendererCapabilityRequest: Codable, Hashable, Sendable {
    public var id: String?
    public var preferredRenderer: String?
    public var preferredSpecVersion: String?
    public var families: Set<String>
    public var actions: Set<String>
    public var knowledgeNatures: Set<String>
    public var surfaces: Set<String>
    public var dataKinds: Set<RichAnswerRendererDataKind>
    public var interactions: Set<RichAnswerRenderInteractionKind>
    public var artifactKinds: Set<String>
    public var resources: Set<RichAnswerRendererResource>
    public var fallbackModes: Set<RichAnswerRenderFallbackMode>
    public var qualityBudget: RichAnswerRenderQualityBudget

    public init(
        id: String? = nil,
        preferredRenderer: String? = nil,
        preferredSpecVersion: String? = nil,
        families: Set<String> = [],
        actions: Set<String> = [],
        knowledgeNatures: Set<String> = [],
        surfaces: Set<String> = [],
        dataKinds: Set<RichAnswerRendererDataKind> = [],
        interactions: Set<RichAnswerRenderInteractionKind> = [],
        artifactKinds: Set<String> = [],
        resources: Set<RichAnswerRendererResource> = [],
        fallbackModes: Set<RichAnswerRenderFallbackMode> = [],
        qualityBudget: RichAnswerRenderQualityBudget = RichAnswerRenderQualityBudget()
    ) {
        self.id = id
        self.preferredRenderer = preferredRenderer
        self.preferredSpecVersion = preferredSpecVersion
        self.families = families
        self.actions = actions
        self.knowledgeNatures = knowledgeNatures
        self.surfaces = surfaces
        self.dataKinds = dataKinds
        self.interactions = interactions
        self.artifactKinds = artifactKinds
        self.resources = resources
        self.fallbackModes = fallbackModes
        self.qualityBudget = qualityBudget
    }

    public func merging(_ other: RichAnswerRendererCapabilityRequest) -> RichAnswerRendererCapabilityRequest {
        RichAnswerRendererCapabilityRequest(
            id: id ?? other.id,
            preferredRenderer: other.preferredRenderer ?? preferredRenderer,
            preferredSpecVersion: other.preferredSpecVersion ?? preferredSpecVersion,
            families: families.union(other.families),
            actions: actions.union(other.actions),
            knowledgeNatures: knowledgeNatures.union(other.knowledgeNatures),
            surfaces: surfaces.union(other.surfaces),
            dataKinds: dataKinds.union(other.dataKinds),
            interactions: interactions.union(other.interactions),
            artifactKinds: artifactKinds.union(other.artifactKinds),
            resources: resources.union(other.resources),
            fallbackModes: fallbackModes.union(other.fallbackModes),
            qualityBudget: qualityBudget.merging(other.qualityBudget)
        )
    }
}

private func maxOptional(_ lhs: Int?, _ rhs: Int?) -> Int? {
    switch (lhs, rhs) {
    case let (lhs?, rhs?):
        return max(lhs, rhs)
    case let (lhs?, nil):
        return lhs
    case let (nil, rhs?):
        return rhs
    case (nil, nil):
        return nil
    }
}
