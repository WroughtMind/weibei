import Foundation

public enum RichAnswerCapabilityFamily: String, Codable, CaseIterable, Hashable, Sendable {
    case textAndAlignment
    case quantityAndCoordinates
    case processAndState
    case relationAndEvidence
    case timeAndSpace
    case imageAndOverlay
    case comparisonAndEvaluation
    case calculationAndConstraints
}

public enum RichAnswerAction: String, Codable, CaseIterable, Hashable, Sendable {
    case explain
    case compare
    case derive
    case trace
    case calculate
    case observe
    case manipulate
    case evaluate
    case practice
}

public enum RichAnswerSurface: String, Codable, CaseIterable, Hashable, Sendable {
    case inline
    case expanded
    case focus
}

public enum RichAnswerObjectKind: String, Codable, CaseIterable, Hashable, Sendable {
    case text
    case quantity
    case formula
    case event
    case region
    case state
    case claim
    case image
    case dataPoint
    case step
    case constraint
    case option
}

public enum RichAnswerRelationKind: String, Codable, CaseIterable, Hashable, Sendable {
    case supports
    case refutes
    case causes
    case precedes
    case aligns
    case contains
    case transforms
    case dependsOn
    case contrasts
    case constrains
}

public enum RichAnswerOperationKind: String, Codable, CaseIterable, Hashable, Sendable {
    case adjust
    case toggle
    case step
    case zoom
    case pan
    case filter
    case sort
    case probe
    case reset
    case compare
    case reveal
    case select
    case scrub
    case playPause
    case measure
}

public enum RichAnswerFrameKind: String, Codable, CaseIterable, Hashable, Sendable {
    case cartesian
    case numberLine
    case timeline
    case space
    case image
    case text
    case table
    case graph
    case process
}

public enum RichAnswerPresentationMode: String, Codable, CaseIterable, Hashable, Sendable {
    case rich
    case narrativeOnly
}

public enum RichAnswerEvidenceState: String, Codable, CaseIterable, Hashable, Sendable {
    case complete
    case partial
    case missing
}

public enum RichAnswerDiagnosticCode: String, Codable, CaseIterable, Hashable, Sendable {
    case staleContext
    case unsupportedSchema
    case unsupportedField
    case decodeFailed
    case duplicateID
    case missingEvidence
    case unsupportedEvidence
    case unauthorizedAsset
    case brokenReference
    case invalidParameter
    case invalidValue
    case unsupportedFamily
    case emptyScene
    case budgetExceeded
}

public struct RichAnswerExpressionPlan: Codable, Hashable, Sendable {
    public var action: RichAnswerAction
    public var summary: String
    public var families: Set<RichAnswerCapabilityFamily>
    public var preferredSurface: RichAnswerSurface
    public var directManipulation: Bool

    public init(
        action: RichAnswerAction,
        summary: String,
        families: Set<RichAnswerCapabilityFamily>,
        preferredSurface: RichAnswerSurface,
        directManipulation: Bool
    ) {
        self.action = action
        self.summary = summary
        self.families = families
        self.preferredSurface = preferredSurface
        self.directManipulation = directManipulation
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case action
        case summary
        case families
        case preferredSurface
        case directManipulation
    }

    public init(from decoder: Decoder) throws {
        try RichAnswerStrictDecoding.rejectUnknownFields(in: decoder, allowed: CodingKeys.allowedFieldNames)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        action = try container.decode(RichAnswerAction.self, forKey: .action)
        summary = try container.decode(String.self, forKey: .summary)
        families = try container.decode(Set<RichAnswerCapabilityFamily>.self, forKey: .families)
        preferredSurface = try container.decode(RichAnswerSurface.self, forKey: .preferredSurface)
        directManipulation = try container.decode(Bool.self, forKey: .directManipulation)
    }
}

public struct RichAnswerEnvelope: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var contextRevision: String
    public var narrative: String
    public var expressionPlan: RichAnswerExpressionPlan
    public var scenes: [RichAnswerScene]
    public var evidenceLedger: [RichAnswerEvidence]
    public var fallback: RichAnswerFallback

    public init(
        schemaVersion: Int = 1,
        contextRevision: String,
        narrative: String,
        expressionPlan: RichAnswerExpressionPlan,
        scenes: [RichAnswerScene],
        evidenceLedger: [RichAnswerEvidence],
        fallback: RichAnswerFallback
    ) {
        self.schemaVersion = schemaVersion
        self.contextRevision = contextRevision
        self.narrative = narrative
        self.expressionPlan = expressionPlan
        self.scenes = scenes
        self.evidenceLedger = evidenceLedger
        self.fallback = fallback
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case contextRevision
        case narrative
        case expressionPlan
        case scenes
        case evidenceLedger
        case fallback
    }

    public init(from decoder: Decoder) throws {
        try RichAnswerStrictDecoding.rejectUnknownFields(in: decoder, allowed: CodingKeys.allowedFieldNames)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        contextRevision = try container.decode(String.self, forKey: .contextRevision)
        narrative = try container.decode(String.self, forKey: .narrative)
        expressionPlan = try container.decode(RichAnswerExpressionPlan.self, forKey: .expressionPlan)
        scenes = try container.decodeIfPresent([RichAnswerScene].self, forKey: .scenes) ?? []
        evidenceLedger = try container.decodeIfPresent([RichAnswerEvidence].self, forKey: .evidenceLedger) ?? []
        fallback = try container.decode(RichAnswerFallback.self, forKey: .fallback)
    }
}

public struct RichAnswerScene: Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var family: RichAnswerCapabilityFamily
    public var objects: [RichAnswerObject]
    public var relations: [RichAnswerRelation]
    public var operations: [RichAnswerOperation]
    public var frames: [RichAnswerFrame]
    public var evidenceIDs: [String]
    public var placement: RichAnswerSurface

    public init(
        id: String,
        title: String,
        family: RichAnswerCapabilityFamily,
        objects: [RichAnswerObject],
        relations: [RichAnswerRelation] = [],
        operations: [RichAnswerOperation] = [],
        frames: [RichAnswerFrame] = [],
        evidenceIDs: [String] = [],
        placement: RichAnswerSurface = .inline
    ) {
        self.id = id
        self.title = title
        self.family = family
        self.objects = objects
        self.relations = relations
        self.operations = operations
        self.frames = frames
        self.evidenceIDs = evidenceIDs
        self.placement = placement
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case title
        case family
        case objects
        case relations
        case operations
        case frames
        case evidenceIDs
        case placement
    }

    public init(from decoder: Decoder) throws {
        try RichAnswerStrictDecoding.rejectUnknownFields(in: decoder, allowed: CodingKeys.allowedFieldNames)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        family = try container.decode(RichAnswerCapabilityFamily.self, forKey: .family)
        objects = try container.decodeIfPresent([RichAnswerObject].self, forKey: .objects) ?? []
        relations = try container.decodeIfPresent([RichAnswerRelation].self, forKey: .relations) ?? []
        operations = try container.decodeIfPresent([RichAnswerOperation].self, forKey: .operations) ?? []
        frames = try container.decodeIfPresent([RichAnswerFrame].self, forKey: .frames) ?? []
        evidenceIDs = try container.decodeIfPresent([String].self, forKey: .evidenceIDs) ?? []
        placement = try container.decodeIfPresent(RichAnswerSurface.self, forKey: .placement) ?? .inline
    }
}

public struct RichAnswerObject: Codable, Hashable, Sendable {
    public var id: String
    public var kind: RichAnswerObjectKind
    public var label: String
    public var text: String?
    public var number: Double?
    public var unit: String?
    public var evidenceIDs: [String]
    public var assetID: String?
    public var frameID: String?
    public var coordinate: RichAnswerPoint?
    public var bounds: RichAnswerRegion?

    public init(
        id: String,
        kind: RichAnswerObjectKind,
        label: String,
        text: String? = nil,
        number: Double? = nil,
        unit: String? = nil,
        evidenceIDs: [String] = [],
        assetID: String? = nil,
        frameID: String? = nil,
        coordinate: RichAnswerPoint? = nil,
        bounds: RichAnswerRegion? = nil
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.text = text
        self.number = number
        self.unit = unit
        self.evidenceIDs = evidenceIDs
        self.assetID = assetID
        self.frameID = frameID
        self.coordinate = coordinate
        self.bounds = bounds
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case kind
        case label
        case text
        case number
        case unit
        case evidenceIDs
        case assetID
        case frameID
        case coordinate
        case bounds
    }

    public init(from decoder: Decoder) throws {
        try RichAnswerStrictDecoding.rejectUnknownFields(in: decoder, allowed: CodingKeys.allowedFieldNames)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decode(RichAnswerObjectKind.self, forKey: .kind)
        label = try container.decode(String.self, forKey: .label)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        number = try container.decodeIfPresent(Double.self, forKey: .number)
        unit = try container.decodeIfPresent(String.self, forKey: .unit)
        evidenceIDs = try container.decodeIfPresent([String].self, forKey: .evidenceIDs) ?? []
        assetID = try container.decodeIfPresent(String.self, forKey: .assetID)
        frameID = try container.decodeIfPresent(String.self, forKey: .frameID)
        coordinate = try container.decodeIfPresent(RichAnswerPoint.self, forKey: .coordinate)
        bounds = try container.decodeIfPresent(RichAnswerRegion.self, forKey: .bounds)
    }
}

public struct RichAnswerRelation: Codable, Hashable, Sendable {
    public var id: String
    public var kind: RichAnswerRelationKind
    public var sourceID: String
    public var targetID: String
    public var label: String?
    public var evidenceIDs: [String]

    public init(
        id: String,
        kind: RichAnswerRelationKind,
        sourceID: String,
        targetID: String,
        label: String? = nil,
        evidenceIDs: [String] = []
    ) {
        self.id = id
        self.kind = kind
        self.sourceID = sourceID
        self.targetID = targetID
        self.label = label
        self.evidenceIDs = evidenceIDs
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case kind
        case sourceID
        case targetID
        case label
        case evidenceIDs
    }

    public init(from decoder: Decoder) throws {
        try RichAnswerStrictDecoding.rejectUnknownFields(in: decoder, allowed: CodingKeys.allowedFieldNames)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decode(RichAnswerRelationKind.self, forKey: .kind)
        sourceID = try container.decode(String.self, forKey: .sourceID)
        targetID = try container.decode(String.self, forKey: .targetID)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        evidenceIDs = try container.decodeIfPresent([String].self, forKey: .evidenceIDs) ?? []
    }
}

public struct RichAnswerOperation: Codable, Hashable, Sendable {
    public var id: String
    public var kind: RichAnswerOperationKind
    public var label: String
    public var targetIDs: [String]
    public var parameter: RichAnswerParameter?
    public var frameID: String?

    public init(
        id: String,
        kind: RichAnswerOperationKind,
        label: String,
        targetIDs: [String],
        parameter: RichAnswerParameter? = nil,
        frameID: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.targetIDs = targetIDs
        self.parameter = parameter
        self.frameID = frameID
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case kind
        case label
        case targetIDs
        case parameter
        case frameID
    }

    public init(from decoder: Decoder) throws {
        try RichAnswerStrictDecoding.rejectUnknownFields(in: decoder, allowed: CodingKeys.allowedFieldNames)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decode(RichAnswerOperationKind.self, forKey: .kind)
        label = try container.decode(String.self, forKey: .label)
        targetIDs = try container.decodeIfPresent([String].self, forKey: .targetIDs) ?? []
        parameter = try container.decodeIfPresent(RichAnswerParameter.self, forKey: .parameter)
        frameID = try container.decodeIfPresent(String.self, forKey: .frameID)
    }
}

public struct RichAnswerParameter: Codable, Hashable, Sendable {
    public var id: String
    public var label: String
    public var minimum: Double
    public var maximum: Double
    public var step: Double
    public var initialValue: Double
    public var unit: String?

    public init(
        id: String,
        label: String,
        minimum: Double,
        maximum: Double,
        step: Double,
        initialValue: Double,
        unit: String? = nil
    ) {
        self.id = id
        self.label = label
        self.minimum = minimum
        self.maximum = maximum
        self.step = step
        self.initialValue = initialValue
        self.unit = unit
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case label
        case minimum
        case maximum
        case step
        case initialValue
        case unit
    }

    public init(from decoder: Decoder) throws {
        try RichAnswerStrictDecoding.rejectUnknownFields(in: decoder, allowed: CodingKeys.allowedFieldNames)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        minimum = try container.decode(Double.self, forKey: .minimum)
        maximum = try container.decode(Double.self, forKey: .maximum)
        step = try container.decode(Double.self, forKey: .step)
        initialValue = try container.decode(Double.self, forKey: .initialValue)
        unit = try container.decodeIfPresent(String.self, forKey: .unit)
    }
}

public struct RichAnswerFrame: Codable, Hashable, Sendable {
    public var id: String
    public var kind: RichAnswerFrameKind
    public var title: String
    public var objectIDs: [String]
    public var xAxis: RichAnswerAxis?
    public var yAxis: RichAnswerAxis?
    public var assetID: String?
    public var evidenceIDs: [String]

    public init(
        id: String,
        kind: RichAnswerFrameKind,
        title: String,
        objectIDs: [String] = [],
        xAxis: RichAnswerAxis? = nil,
        yAxis: RichAnswerAxis? = nil,
        assetID: String? = nil,
        evidenceIDs: [String] = []
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.objectIDs = objectIDs
        self.xAxis = xAxis
        self.yAxis = yAxis
        self.assetID = assetID
        self.evidenceIDs = evidenceIDs
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case kind
        case title
        case objectIDs
        case xAxis
        case yAxis
        case assetID
        case evidenceIDs
    }

    public init(from decoder: Decoder) throws {
        try RichAnswerStrictDecoding.rejectUnknownFields(in: decoder, allowed: CodingKeys.allowedFieldNames)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decode(RichAnswerFrameKind.self, forKey: .kind)
        title = try container.decode(String.self, forKey: .title)
        objectIDs = try container.decodeIfPresent([String].self, forKey: .objectIDs) ?? []
        xAxis = try container.decodeIfPresent(RichAnswerAxis.self, forKey: .xAxis)
        yAxis = try container.decodeIfPresent(RichAnswerAxis.self, forKey: .yAxis)
        assetID = try container.decodeIfPresent(String.self, forKey: .assetID)
        evidenceIDs = try container.decodeIfPresent([String].self, forKey: .evidenceIDs) ?? []
    }
}

public struct RichAnswerAxis: Codable, Hashable, Sendable {
    public var label: String
    public var minimum: Double
    public var maximum: Double
    public var unit: String?

    public init(label: String, minimum: Double, maximum: Double, unit: String? = nil) {
        self.label = label
        self.minimum = minimum
        self.maximum = maximum
        self.unit = unit
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case label
        case minimum
        case maximum
        case unit
    }

    public init(from decoder: Decoder) throws {
        try RichAnswerStrictDecoding.rejectUnknownFields(in: decoder, allowed: CodingKeys.allowedFieldNames)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decode(String.self, forKey: .label)
        minimum = try container.decode(Double.self, forKey: .minimum)
        maximum = try container.decode(Double.self, forKey: .maximum)
        unit = try container.decodeIfPresent(String.self, forKey: .unit)
    }
}

public struct RichAnswerPoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case x
        case y
    }

    public init(from decoder: Decoder) throws {
        try RichAnswerStrictDecoding.rejectUnknownFields(in: decoder, allowed: CodingKeys.allowedFieldNames)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
    }
}

public struct RichAnswerRegion: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case x
        case y
        case width
        case height
    }

    public init(from decoder: Decoder) throws {
        try RichAnswerStrictDecoding.rejectUnknownFields(in: decoder, allowed: CodingKeys.allowedFieldNames)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        width = try container.decode(Double.self, forKey: .width)
        height = try container.decode(Double.self, forKey: .height)
    }
}

public struct RichAnswerEvidence: Codable, Hashable, Sendable {
    public var id: String
    public var sourceLabel: String
    public var excerpt: String
    public var isTruncated: Bool
    public var tags: Set<String>
    public var assetIDs: [String]

    public init(
        id: String,
        sourceLabel: String,
        excerpt: String,
        isTruncated: Bool = false,
        tags: Set<String> = [],
        assetIDs: [String] = []
    ) {
        self.id = id
        self.sourceLabel = sourceLabel
        self.excerpt = excerpt
        self.isTruncated = isTruncated
        self.tags = tags
        self.assetIDs = assetIDs
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case sourceLabel
        case excerpt
        case isTruncated
        case tags
        case assetIDs
    }

    public init(from decoder: Decoder) throws {
        try RichAnswerStrictDecoding.rejectUnknownFields(in: decoder, allowed: CodingKeys.allowedFieldNames)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        sourceLabel = try container.decode(String.self, forKey: .sourceLabel)
        excerpt = try container.decode(String.self, forKey: .excerpt)
        isTruncated = try container.decodeIfPresent(Bool.self, forKey: .isTruncated) ?? false
        tags = try container.decodeIfPresent(Set<String>.self, forKey: .tags) ?? []
        assetIDs = try container.decodeIfPresent([String].self, forKey: .assetIDs) ?? []
    }
}

public struct RichAnswerFallback: Codable, Hashable, Sendable {
    public var text: String
    public var reason: String

    public init(text: String, reason: String) {
        self.text = text
        self.reason = reason
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case text
        case reason
    }

    public init(from decoder: Decoder) throws {
        try RichAnswerStrictDecoding.rejectUnknownFields(in: decoder, allowed: CodingKeys.allowedFieldNames)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        reason = try container.decode(String.self, forKey: .reason)
    }
}

public struct RichAnswerResourceBudget: Codable, Hashable, Sendable {
    public var maxScenes: Int
    public var maxObjectsPerScene: Int
    public var maxRelationsPerScene: Int
    public var maxOperationsPerScene: Int
    public var maxFramesPerScene: Int
    public var maxEvidenceItems: Int

    public init(
        maxScenes: Int = 6,
        maxObjectsPerScene: Int = 64,
        maxRelationsPerScene: Int = 128,
        maxOperationsPerScene: Int = 16,
        maxFramesPerScene: Int = 12,
        maxEvidenceItems: Int = 32
    ) {
        self.maxScenes = maxScenes
        self.maxObjectsPerScene = maxObjectsPerScene
        self.maxRelationsPerScene = maxRelationsPerScene
        self.maxOperationsPerScene = maxOperationsPerScene
        self.maxFramesPerScene = maxFramesPerScene
        self.maxEvidenceItems = maxEvidenceItems
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case maxScenes
        case maxObjectsPerScene
        case maxRelationsPerScene
        case maxOperationsPerScene
        case maxFramesPerScene
        case maxEvidenceItems
    }

    public init(from decoder: Decoder) throws {
        try RichAnswerStrictDecoding.rejectUnknownFields(in: decoder, allowed: CodingKeys.allowedFieldNames)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        maxScenes = try container.decodeIfPresent(Int.self, forKey: .maxScenes) ?? 6
        maxObjectsPerScene = try container.decodeIfPresent(Int.self, forKey: .maxObjectsPerScene) ?? 64
        maxRelationsPerScene = try container.decodeIfPresent(Int.self, forKey: .maxRelationsPerScene) ?? 128
        maxOperationsPerScene = try container.decodeIfPresent(Int.self, forKey: .maxOperationsPerScene) ?? 16
        maxFramesPerScene = try container.decodeIfPresent(Int.self, forKey: .maxFramesPerScene) ?? 12
        maxEvidenceItems = try container.decodeIfPresent(Int.self, forKey: .maxEvidenceItems) ?? 32
    }
}

public struct RichAnswerEnvironment: Codable, Hashable, Sendable {
    public var contextRevision: String
    public var allowedSourceLabels: Set<String>
    public var allowedEvidenceTags: Set<String>
    public var allowedAssetIDs: Set<String>
    public var resourceBudget: RichAnswerResourceBudget

    public init(
        contextRevision: String,
        allowedSourceLabels: Set<String>,
        allowedEvidenceTags: Set<String> = [],
        allowedAssetIDs: Set<String> = [],
        resourceBudget: RichAnswerResourceBudget = RichAnswerResourceBudget()
    ) {
        self.contextRevision = contextRevision
        self.allowedSourceLabels = allowedSourceLabels
        self.allowedEvidenceTags = allowedEvidenceTags
        self.allowedAssetIDs = allowedAssetIDs
        self.resourceBudget = resourceBudget
    }
}

public struct RichAnswerDiagnostic: Codable, Hashable, Sendable {
    public var code: RichAnswerDiagnosticCode
    public var sceneID: String?
    public var message: String

    public init(code: RichAnswerDiagnosticCode, sceneID: String? = nil, message: String) {
        self.code = code
        self.sceneID = sceneID
        self.message = message
    }
}

public struct RichAnswerPresentation: Codable, Hashable, Sendable {
    public var mode: RichAnswerPresentationMode
    public var narrative: String
    public var expressionPlan: RichAnswerExpressionPlan?
    public var scenes: [RichAnswerScene]
    public var evidenceLedger: [RichAnswerEvidence]
    public var fallback: RichAnswerFallback?
    public var diagnostics: [RichAnswerDiagnostic]
    public var evidenceState: RichAnswerEvidenceState

    public init(
        mode: RichAnswerPresentationMode,
        narrative: String,
        expressionPlan: RichAnswerExpressionPlan? = nil,
        scenes: [RichAnswerScene] = [],
        evidenceLedger: [RichAnswerEvidence] = [],
        fallback: RichAnswerFallback? = nil,
        diagnostics: [RichAnswerDiagnostic] = [],
        evidenceState: RichAnswerEvidenceState = .missing
    ) {
        self.mode = mode
        self.narrative = narrative
        self.expressionPlan = expressionPlan
        self.scenes = scenes
        self.evidenceLedger = evidenceLedger
        self.fallback = fallback
        self.diagnostics = diagnostics
        self.evidenceState = evidenceState
    }

    public func resolvingAssetIDs(using aliases: [String: String]) -> RichAnswerPresentation {
        guard !aliases.isEmpty else { return self }
        var resolved = self
        resolved.scenes = scenes.map { scene in
            var resolvedScene = scene
            resolvedScene.objects = scene.objects.map { object in
                var resolvedObject = object
                if let assetID = object.assetID {
                    resolvedObject.assetID = aliases[assetID] ?? assetID
                }
                return resolvedObject
            }
            resolvedScene.frames = scene.frames.map { frame in
                var resolvedFrame = frame
                if let assetID = frame.assetID {
                    resolvedFrame.assetID = aliases[assetID] ?? assetID
                }
                return resolvedFrame
            }
            return resolvedScene
        }
        resolved.evidenceLedger = evidenceLedger.map { evidence in
            var resolvedEvidence = evidence
            resolvedEvidence.assetIDs = evidence.assetIDs.map { aliases[$0] ?? $0 }
            return resolvedEvidence
        }
        return resolved
    }
}

public enum RichAnswerEngine {
    public static func prepare(
        envelope: RichAnswerEnvelope,
        environment: RichAnswerEnvironment
    ) -> RichAnswerPresentation {
        var diagnostics: [RichAnswerDiagnostic] = []

        guard envelope.schemaVersion == 1 else {
            return narrativeFallback(
                envelope: envelope,
                diagnostics: [
                    RichAnswerDiagnostic(
                        code: .unsupportedSchema,
                        message: "unsupported rich-answer schema version \(envelope.schemaVersion)"
                    ),
                ]
            )
        }

        guard envelope.contextRevision == environment.contextRevision,
              !envelope.contextRevision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return narrativeFallback(
                envelope: envelope,
                diagnostics: [
                    RichAnswerDiagnostic(
                        code: .staleContext,
                        message: "rich answer context does not match the current material revision"
                    ),
                ]
            )
        }

        guard !envelope.narrative.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              envelope.narrative.count <= 12_000,
              !envelope.fallback.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              envelope.fallback.text.count <= 12_000,
              !envelope.expressionPlan.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              envelope.expressionPlan.summary.count <= 600 else {
            return narrativeFallback(
                envelope: envelope,
                diagnostics: [
                    RichAnswerDiagnostic(
                        code: .budgetExceeded,
                        message: "rich answer narrative or expression plan exceeded its text budget"
                    ),
                ]
            )
        }

        if envelope.expressionPlan.families.isEmpty {
            diagnostics.append(
                RichAnswerDiagnostic(
                    code: .unsupportedFamily,
                    message: "rich answer expression plan did not declare a capability family"
                )
            )
        }

        let evidenceResult = validateEvidenceLedger(
            envelope.evidenceLedger,
            environment: environment,
            diagnostics: &diagnostics
        )
        let sceneResult = validateScenes(
            envelope.scenes,
            expressionPlan: envelope.expressionPlan,
            evidenceByID: evidenceResult.validEvidenceByID,
            environment: environment,
            diagnostics: &diagnostics
        )

        let scenes = sceneResult.validScenes
        let evidenceLedger = referencedEvidenceLedger(
            from: scenes,
            evidenceByID: evidenceResult.validEvidenceByID
        )
        let hasDirectOperations = scenes.contains(where: { !$0.operations.isEmpty })
        guard envelope.expressionPlan.directManipulation == hasDirectOperations else {
            diagnostics.append(
                RichAnswerDiagnostic(
                    code: .invalidParameter,
                    message: "rich answer direct-manipulation plan does not match its accepted operations"
                )
            )
            return narrativeFallback(envelope: envelope, diagnostics: diagnostics)
        }
        let mode: RichAnswerPresentationMode = scenes.isEmpty ? .narrativeOnly : .rich
        let narrative = scenes.isEmpty && !diagnostics.isEmpty ? envelope.fallback.text : envelope.narrative

        return RichAnswerPresentation(
            mode: mode,
            narrative: narrative,
            expressionPlan: envelope.expressionPlan,
            scenes: scenes,
            evidenceLedger: evidenceLedger,
            fallback: envelope.fallback,
            diagnostics: diagnostics,
            evidenceState: evidenceState(
                hasScenes: !scenes.isEmpty,
                diagnostics: diagnostics,
                invalidEvidenceWasSeen: evidenceResult.invalidEvidenceWasSeen,
                hasTruncatedEvidence: evidenceLedger.contains(where: \.isTruncated)
            )
        )
    }

    public static func prepare(
        data: Data,
        fallbackText: String,
        environment: RichAnswerEnvironment
    ) -> RichAnswerPresentation {
        do {
            let envelope = try JSONDecoder().decode(RichAnswerEnvelope.self, from: data)
            return prepare(envelope: envelope, environment: environment)
        } catch {
            let code: RichAnswerDiagnosticCode = error.isUnsupportedRichAnswerField ? .unsupportedField : .decodeFailed
            return RichAnswerPresentation(
                mode: .narrativeOnly,
                narrative: fallbackText,
                diagnostics: [
                    RichAnswerDiagnostic(
                        code: code,
                        message: "rich answer payload was rejected: \(error.localizedDescription)"
                    ),
                ],
                evidenceState: .missing
            )
        }
    }

    private static func narrativeFallback(
        envelope: RichAnswerEnvelope,
        diagnostics: [RichAnswerDiagnostic]
    ) -> RichAnswerPresentation {
        RichAnswerPresentation(
            mode: .narrativeOnly,
            narrative: envelope.fallback.text,
            expressionPlan: envelope.expressionPlan,
            fallback: envelope.fallback,
            diagnostics: diagnostics,
            evidenceState: .missing
        )
    }

    private static func validateEvidenceLedger(
        _ ledger: [RichAnswerEvidence],
        environment: RichAnswerEnvironment,
        diagnostics: inout [RichAnswerDiagnostic]
    ) -> EvidenceValidationResult {
        var validEvidenceByID: [String: RichAnswerEvidence] = [:]
        var seenIDs: Set<String> = []
        var duplicateIDs: Set<String> = []
        var invalidEvidenceWasSeen = ledger.count > environment.resourceBudget.maxEvidenceItems

        if ledger.count > environment.resourceBudget.maxEvidenceItems {
            diagnostics.append(
                RichAnswerDiagnostic(
                    code: .budgetExceeded,
                    message: "rich answer evidence ledger exceeded the allowed item budget"
                )
            )
        }

        for evidence in ledger.prefix(max(0, environment.resourceBudget.maxEvidenceItems)) {
            guard isSafeIdentifier(evidence.id) else {
                invalidEvidenceWasSeen = true
                diagnostics.append(
                    RichAnswerDiagnostic(
                        code: .invalidValue,
                        message: "evidence id is empty or unsafe"
                    )
                )
                continue
            }
            guard seenIDs.insert(evidence.id).inserted else {
                duplicateIDs.insert(evidence.id)
                invalidEvidenceWasSeen = true
                diagnostics.append(
                    RichAnswerDiagnostic(
                        code: .duplicateID,
                        message: "evidence id \(evidence.id) is duplicated"
                    )
                )
                continue
            }
            guard environment.allowedSourceLabels.contains(evidence.sourceLabel) else {
                invalidEvidenceWasSeen = true
                diagnostics.append(
                    RichAnswerDiagnostic(
                        code: .unsupportedEvidence,
                        message: "evidence \(evidence.id) uses a source label that is not allowed in this context"
                    )
                )
                continue
            }
            guard !evidence.excerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  evidence.excerpt.count <= 1_200 else {
                invalidEvidenceWasSeen = true
                diagnostics.append(
                    RichAnswerDiagnostic(
                        code: .budgetExceeded,
                        message: "evidence \(evidence.id) has an empty or oversized excerpt"
                    )
                )
                continue
            }
            guard evidence.tags.isSubset(of: environment.allowedEvidenceTags) else {
                invalidEvidenceWasSeen = true
                diagnostics.append(
                    RichAnswerDiagnostic(
                        code: .unsupportedEvidence,
                        message: "evidence \(evidence.id) uses a tag that is not allowed in this context"
                    )
                )
                continue
            }
            guard evidence.assetIDs.allSatisfy({ isAllowedAssetID($0, environment: environment) }) else {
                invalidEvidenceWasSeen = true
                diagnostics.append(
                    RichAnswerDiagnostic(
                        code: .unauthorizedAsset,
                        message: "evidence \(evidence.id) references an asset that is not allowed in this context"
                    )
                )
                continue
            }
            validEvidenceByID[evidence.id] = evidence
        }

        for duplicateID in duplicateIDs {
            validEvidenceByID.removeValue(forKey: duplicateID)
        }

        return EvidenceValidationResult(
            validEvidenceByID: validEvidenceByID,
            invalidEvidenceWasSeen: invalidEvidenceWasSeen
        )
    }

    private static func validateScenes(
        _ scenes: [RichAnswerScene],
        expressionPlan: RichAnswerExpressionPlan,
        evidenceByID: [String: RichAnswerEvidence],
        environment: RichAnswerEnvironment,
        diagnostics: inout [RichAnswerDiagnostic]
    ) -> SceneValidationResult {
        var validScenes: [RichAnswerScene] = []
        var seenSceneIDs: Set<String> = []
        let maxScenes = max(0, environment.resourceBudget.maxScenes)

        for scene in scenes.prefix(maxScenes) {
            if !seenSceneIDs.insert(scene.id).inserted {
                diagnostics.append(
                    RichAnswerDiagnostic(
                        code: .duplicateID,
                        sceneID: scene.id,
                        message: "scene id \(scene.id) is duplicated"
                    )
                )
                continue
            }

            if let issue = validateScene(
                scene,
                expressionPlan: expressionPlan,
                evidenceByID: evidenceByID,
                environment: environment
            ) {
                diagnostics.append(issue)
                continue
            }

            validScenes.append(scene)
        }

        if scenes.count > maxScenes {
            for scene in scenes.dropFirst(maxScenes) {
                diagnostics.append(
                    RichAnswerDiagnostic(
                        code: .budgetExceeded,
                        sceneID: scene.id,
                        message: "scene exceeded the allowed scene budget"
                    )
                )
            }
        }

        return SceneValidationResult(validScenes: validScenes)
    }

    private static func validateScene(
        _ scene: RichAnswerScene,
        expressionPlan: RichAnswerExpressionPlan,
        evidenceByID: [String: RichAnswerEvidence],
        environment: RichAnswerEnvironment
    ) -> RichAnswerDiagnostic? {
        guard isSafeIdentifier(scene.id) else {
            return RichAnswerDiagnostic(
                code: .invalidValue,
                sceneID: scene.id,
                message: "scene id is empty or unsafe"
            )
        }
        guard expressionPlan.families.contains(scene.family) else {
            return RichAnswerDiagnostic(
                code: .unsupportedFamily,
                sceneID: scene.id,
                message: "scene family is not declared by the expression plan"
            )
        }
        guard !scene.objects.isEmpty else {
            return RichAnswerDiagnostic(
                code: .emptyScene,
                sceneID: scene.id,
                message: "scene does not contain any knowledge objects"
            )
        }
        guard !scene.evidenceIDs.isEmpty else {
            return RichAnswerDiagnostic(
                code: .missingEvidence,
                sceneID: scene.id,
                message: "scene does not bind to any evidence"
            )
        }
        guard scene.objects.count <= environment.resourceBudget.maxObjectsPerScene,
              scene.relations.count <= environment.resourceBudget.maxRelationsPerScene,
              scene.operations.count <= environment.resourceBudget.maxOperationsPerScene,
              scene.frames.count <= environment.resourceBudget.maxFramesPerScene else {
            return RichAnswerDiagnostic(
                code: .budgetExceeded,
                sceneID: scene.id,
                message: "scene exceeded the rich-answer resource budget"
            )
        }
        guard scene.evidenceIDs.allSatisfy({ evidenceByID[$0] != nil }) else {
            return RichAnswerDiagnostic(
                code: .missingEvidence,
                sceneID: scene.id,
                message: "scene references evidence that is missing or not allowed"
            )
        }

        let objectIDs = scene.objects.map(\.id)
        let relationIDs = scene.relations.map(\.id)
        let operationIDs = scene.operations.map(\.id)
        let frameIDs = scene.frames.map(\.id)
        let allLocalIDs = objectIDs + relationIDs + operationIDs + frameIDs
        guard idsAreUniqueAndSafe(allLocalIDs) else {
            return RichAnswerDiagnostic(
                code: .duplicateID,
                sceneID: scene.id,
                message: "scene object, relation, operation, and frame ids must be unique and safe"
            )
        }

        let objectIDSet = Set(objectIDs)
        let relationIDSet = Set(relationIDs)
        let frameIDSet = Set(frameIDs)
        let referableIDs = objectIDSet.union(relationIDSet).union(frameIDSet)

        for object in scene.objects {
            if let issue = validateObject(
                object,
                sceneID: scene.id,
                frameIDs: frameIDSet,
                evidenceByID: evidenceByID,
                environment: environment
            ) {
                return issue
            }
        }

        for relation in scene.relations {
            if let issue = validateRelation(
                relation,
                sceneID: scene.id,
                objectIDs: objectIDSet,
                evidenceByID: evidenceByID
            ) {
                return issue
            }
        }

        for operation in scene.operations {
            if let issue = validateOperation(
                operation,
                sceneID: scene.id,
                referableIDs: referableIDs,
                frameIDs: frameIDSet
            ) {
                return issue
            }
        }

        for frame in scene.frames {
            if let issue = validateFrame(
                frame,
                sceneID: scene.id,
                objectIDs: objectIDSet,
                evidenceByID: evidenceByID,
                environment: environment
            ) {
                return issue
            }
        }

        return nil
    }

    private static func validateObject(
        _ object: RichAnswerObject,
        sceneID: String,
        frameIDs: Set<String>,
        evidenceByID: [String: RichAnswerEvidence],
        environment: RichAnswerEnvironment
    ) -> RichAnswerDiagnostic? {
        guard object.number.map({ $0.isFinite }) ?? true else {
            return invalidValue(sceneID: sceneID, "object \(object.id) has a non-finite number")
        }
        guard object.evidenceIDs.allSatisfy({ evidenceByID[$0] != nil }) else {
            return missingEvidence(sceneID: sceneID, "object \(object.id) references missing or disallowed evidence")
        }
        if let assetID = object.assetID, !isAllowedAssetID(assetID, environment: environment) {
            return RichAnswerDiagnostic(
                code: .unauthorizedAsset,
                sceneID: sceneID,
                message: "object \(object.id) references an asset that is not allowed in this context"
            )
        }
        if let frameID = object.frameID, !frameIDs.contains(frameID) {
            return brokenReference(sceneID: sceneID, "object \(object.id) references missing frame \(frameID)")
        }
        if (object.coordinate != nil || object.bounds != nil), object.frameID == nil {
            return brokenReference(sceneID: sceneID, "object \(object.id) has coordinates without a frame reference")
        }
        if let coordinate = object.coordinate, !coordinate.isFinite {
            return invalidValue(sceneID: sceneID, "object \(object.id) has non-finite coordinates")
        }
        if let bounds = object.bounds, !bounds.isValid {
            return invalidValue(sceneID: sceneID, "object \(object.id) has invalid bounds")
        }
        return nil
    }

    private static func validateRelation(
        _ relation: RichAnswerRelation,
        sceneID: String,
        objectIDs: Set<String>,
        evidenceByID: [String: RichAnswerEvidence]
    ) -> RichAnswerDiagnostic? {
        guard objectIDs.contains(relation.sourceID),
              objectIDs.contains(relation.targetID) else {
            return brokenReference(
                sceneID: sceneID,
                "relation \(relation.id) references an object that is not present"
            )
        }
        guard relation.evidenceIDs.allSatisfy({ evidenceByID[$0] != nil }) else {
            return missingEvidence(sceneID: sceneID, "relation \(relation.id) references missing or disallowed evidence")
        }
        return nil
    }

    private static func validateOperation(
        _ operation: RichAnswerOperation,
        sceneID: String,
        referableIDs: Set<String>,
        frameIDs: Set<String>
    ) -> RichAnswerDiagnostic? {
        guard !operation.targetIDs.isEmpty,
              operation.targetIDs.allSatisfy({ referableIDs.contains($0) }) else {
            return brokenReference(
                sceneID: sceneID,
                "operation \(operation.id) references a target that is not present"
            )
        }
        if let frameID = operation.frameID, !frameIDs.contains(frameID) {
            return brokenReference(sceneID: sceneID, "operation \(operation.id) references missing frame \(frameID)")
        }
        if let parameter = operation.parameter, !parameter.isValid {
            return RichAnswerDiagnostic(
                code: .invalidParameter,
                sceneID: sceneID,
                message: "operation \(operation.id) has an invalid adjustment parameter"
            )
        }
        return nil
    }

    private static func validateFrame(
        _ frame: RichAnswerFrame,
        sceneID: String,
        objectIDs: Set<String>,
        evidenceByID: [String: RichAnswerEvidence],
        environment: RichAnswerEnvironment
    ) -> RichAnswerDiagnostic? {
        guard frame.objectIDs.allSatisfy({ objectIDs.contains($0) }) else {
            return brokenReference(sceneID: sceneID, "frame \(frame.id) references an object that is not present")
        }
        guard frame.evidenceIDs.allSatisfy({ evidenceByID[$0] != nil }) else {
            return missingEvidence(sceneID: sceneID, "frame \(frame.id) references missing or disallowed evidence")
        }
        if frame.kind == .cartesian {
            guard let xAxis = frame.xAxis, let yAxis = frame.yAxis,
                  xAxis.isValid,
                  yAxis.isValid else {
                return invalidValue(sceneID: sceneID, "cartesian frame \(frame.id) requires valid x and y axes")
            }
        } else {
            guard frame.xAxis.map(\.isValid) ?? true,
                  frame.yAxis.map(\.isValid) ?? true else {
                return invalidValue(sceneID: sceneID, "frame \(frame.id) has an invalid axis")
            }
        }
        if let assetID = frame.assetID, !isAllowedAssetID(assetID, environment: environment) {
            return RichAnswerDiagnostic(
                code: .unauthorizedAsset,
                sceneID: sceneID,
                message: "frame \(frame.id) references an asset that is not allowed in this context"
            )
        }
        return nil
    }

    private static func referencedEvidenceLedger(
        from scenes: [RichAnswerScene],
        evidenceByID: [String: RichAnswerEvidence]
    ) -> [RichAnswerEvidence] {
        let referencedIDs = Set(scenes.flatMap(\.allEvidenceIDs))
        return evidenceByID.values
            .filter { referencedIDs.contains($0.id) }
            .sorted { $0.id < $1.id }
    }

    private static func evidenceState(
        hasScenes: Bool,
        diagnostics: [RichAnswerDiagnostic],
        invalidEvidenceWasSeen: Bool,
        hasTruncatedEvidence: Bool
    ) -> RichAnswerEvidenceState {
        guard hasScenes else { return .missing }
        let evidenceCodes: Set<RichAnswerDiagnosticCode> = [
            .missingEvidence,
            .unsupportedEvidence,
            .unauthorizedAsset,
        ]
        if hasTruncatedEvidence
            || invalidEvidenceWasSeen
            || diagnostics.contains(where: { evidenceCodes.contains($0.code) }) {
            return .partial
        }
        return .complete
    }

    private static func idsAreUniqueAndSafe(_ ids: [String]) -> Bool {
        ids.allSatisfy(isSafeIdentifier) && Set(ids).count == ids.count
    }

    private static func isSafeIdentifier(_ id: String) -> Bool {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 120 else { return false }
        return !trimmed.contains("://") && !trimmed.contains("<") && !trimmed.contains(">")
    }

    private static func isAllowedAssetID(_ assetID: String, environment: RichAnswerEnvironment) -> Bool {
        isSafeIdentifier(assetID) && environment.allowedAssetIDs.contains(assetID)
    }

    private static func brokenReference(sceneID: String, _ message: String) -> RichAnswerDiagnostic {
        RichAnswerDiagnostic(code: .brokenReference, sceneID: sceneID, message: message)
    }

    private static func missingEvidence(sceneID: String, _ message: String) -> RichAnswerDiagnostic {
        RichAnswerDiagnostic(code: .missingEvidence, sceneID: sceneID, message: message)
    }

    private static func invalidValue(sceneID: String, _ message: String) -> RichAnswerDiagnostic {
        RichAnswerDiagnostic(code: .invalidValue, sceneID: sceneID, message: message)
    }
}

private struct EvidenceValidationResult {
    var validEvidenceByID: [String: RichAnswerEvidence]
    var invalidEvidenceWasSeen: Bool
}

private struct SceneValidationResult {
    var validScenes: [RichAnswerScene]
}

private struct RichAnswerDynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

private enum RichAnswerStrictDecoding {
    static func rejectUnknownFields(in decoder: Decoder, allowed: Set<String>) throws {
        let container = try decoder.container(keyedBy: RichAnswerDynamicCodingKey.self)
        if let key = container.allKeys.first(where: { !allowed.contains($0.stringValue) }) {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Unsupported rich-answer field '\(key.stringValue)'"
            )
        }
    }
}

private extension CaseIterable where Self: CodingKey {
    static var allowedFieldNames: Set<String> {
        Set(allCases.map(\.stringValue))
    }
}

private extension RichAnswerParameter {
    var isValid: Bool {
        minimum.isFinite
            && maximum.isFinite
            && step.isFinite
            && initialValue.isFinite
            && minimum < maximum
            && step > 0
            && initialValue >= minimum
            && initialValue <= maximum
    }
}

private extension RichAnswerAxis {
    var isValid: Bool {
        minimum.isFinite && maximum.isFinite && minimum < maximum
    }
}

private extension RichAnswerPoint {
    var isFinite: Bool {
        x.isFinite && y.isFinite
    }
}

private extension RichAnswerRegion {
    var isValid: Bool {
        x.isFinite
            && y.isFinite
            && width.isFinite
            && height.isFinite
            && x >= 0
            && y >= 0
            && width > 0
            && height > 0
            && x + width <= 1
            && y + height <= 1
    }
}

private extension RichAnswerScene {
    var allEvidenceIDs: [String] {
        evidenceIDs
            + objects.flatMap(\.evidenceIDs)
            + relations.flatMap(\.evidenceIDs)
            + frames.flatMap(\.evidenceIDs)
    }
}

private extension Error {
    var isUnsupportedRichAnswerField: Bool {
        guard let decodingError = self as? DecodingError else { return false }
        switch decodingError {
        case let DecodingError.dataCorrupted(context):
            return context.debugDescription.contains("Unsupported rich-answer field")
        case let DecodingError.keyNotFound(_, context),
             let DecodingError.typeMismatch(_, context),
             let DecodingError.valueNotFound(_, context):
            return context.debugDescription.contains("Unsupported rich-answer field")
        default:
            return false
        }
    }
}
