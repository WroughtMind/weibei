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

public enum RichAnswerKnowledgeNature: String, Codable, CaseIterable, Hashable, Sendable {
    case functionOrDataCurve
    case objectMechanism
    case spatialStructure
    case processOrState
    case argumentOrEvidence
    case imageObservation
    case comparisonOrEvaluation
    case calculationOrConstraint
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
    public var knowledgeNatures: Set<RichAnswerKnowledgeNature>
    public var knowledgeObjects: [String]
    public var knowledgeRelations: [String]
    public var knowledgeProcesses: [String]
    public var visualPrimitives: [String]
    public var visualRationale: [String]

    public init(
        action: RichAnswerAction,
        summary: String,
        families: Set<RichAnswerCapabilityFamily>,
        preferredSurface: RichAnswerSurface,
        directManipulation: Bool,
        knowledgeNatures: Set<RichAnswerKnowledgeNature> = [],
        knowledgeObjects: [String] = [],
        knowledgeRelations: [String] = [],
        knowledgeProcesses: [String] = [],
        visualPrimitives: [String] = [],
        visualRationale: [String] = []
    ) {
        self.action = action
        self.summary = summary
        self.families = families
        self.preferredSurface = preferredSurface
        self.directManipulation = directManipulation
        self.knowledgeNatures = knowledgeNatures
        self.knowledgeObjects = knowledgeObjects
        self.knowledgeRelations = knowledgeRelations
        self.knowledgeProcesses = knowledgeProcesses
        self.visualPrimitives = visualPrimitives
        self.visualRationale = visualRationale
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case action
        case summary
        case families
        case preferredSurface
        case directManipulation
        case knowledgeNatures
        case knowledgeObjects
        case knowledgeRelations
        case knowledgeProcesses
        case visualPrimitives
        case visualRationale
    }

    public init(from decoder: Decoder) throws {
        try RichAnswerStrictDecoding.rejectUnknownFields(in: decoder, allowed: CodingKeys.allowedFieldNames)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        action = try container.decode(RichAnswerAction.self, forKey: .action)
        summary = try container.decode(String.self, forKey: .summary)
        families = try container.decode(Set<RichAnswerCapabilityFamily>.self, forKey: .families)
        preferredSurface = try container.decode(RichAnswerSurface.self, forKey: .preferredSurface)
        directManipulation = try container.decode(Bool.self, forKey: .directManipulation)
        knowledgeNatures = try container.decodeIfPresent(Set<RichAnswerKnowledgeNature>.self, forKey: .knowledgeNatures) ?? []
        knowledgeObjects = try container.decodeIfPresent([String].self, forKey: .knowledgeObjects) ?? []
        knowledgeRelations = try container.decodeIfPresent([String].self, forKey: .knowledgeRelations) ?? []
        knowledgeProcesses = try container.decodeIfPresent([String].self, forKey: .knowledgeProcesses) ?? []
        visualPrimitives = try container.decodeIfPresent([String].self, forKey: .visualPrimitives) ?? []
        visualRationale = try container.decodeIfPresent([String].self, forKey: .visualRationale) ?? []
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
    public var ui: RichAnswerUIComposition?
    public var program: RichAnswerUIProgram?
    public var renderPlan: RichAnswerRenderPlan?

    public init(
        id: String,
        title: String,
        family: RichAnswerCapabilityFamily,
        objects: [RichAnswerObject],
        relations: [RichAnswerRelation] = [],
        operations: [RichAnswerOperation] = [],
        frames: [RichAnswerFrame] = [],
        evidenceIDs: [String] = [],
        placement: RichAnswerSurface = .inline,
        ui: RichAnswerUIComposition? = nil,
        program: RichAnswerUIProgram? = nil,
        renderPlan: RichAnswerRenderPlan? = nil
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
        self.ui = ui
        self.program = program
        self.renderPlan = renderPlan
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
        case ui
        case program
        case renderPlan
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
        ui = try container.decodeIfPresent(RichAnswerUIComposition.self, forKey: .ui)
        program = try container.decodeIfPresent(RichAnswerUIProgram.self, forKey: .program)
        renderPlan = try container.decodeIfPresent(RichAnswerRenderPlan.self, forKey: .renderPlan)
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
    public var maxUINodesPerScene: Int
    public var maxUIDataRowsPerScene: Int
    public var maxUIBindingsPerScene: Int

    public init(
        maxScenes: Int = 6,
        maxObjectsPerScene: Int = 64,
        maxRelationsPerScene: Int = 128,
        maxOperationsPerScene: Int = 16,
        maxFramesPerScene: Int = 12,
        maxEvidenceItems: Int = 32,
        maxUINodesPerScene: Int = 48,
        maxUIDataRowsPerScene: Int = 256,
        maxUIBindingsPerScene: Int = 8
    ) {
        self.maxScenes = maxScenes
        self.maxObjectsPerScene = maxObjectsPerScene
        self.maxRelationsPerScene = maxRelationsPerScene
        self.maxOperationsPerScene = maxOperationsPerScene
        self.maxFramesPerScene = maxFramesPerScene
        self.maxEvidenceItems = maxEvidenceItems
        self.maxUINodesPerScene = maxUINodesPerScene
        self.maxUIDataRowsPerScene = maxUIDataRowsPerScene
        self.maxUIBindingsPerScene = maxUIBindingsPerScene
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case maxScenes
        case maxObjectsPerScene
        case maxRelationsPerScene
        case maxOperationsPerScene
        case maxFramesPerScene
        case maxEvidenceItems
        case maxUINodesPerScene
        case maxUIDataRowsPerScene
        case maxUIBindingsPerScene
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
        maxUINodesPerScene = try container.decodeIfPresent(Int.self, forKey: .maxUINodesPerScene) ?? 48
        maxUIDataRowsPerScene = try container.decodeIfPresent(Int.self, forKey: .maxUIDataRowsPerScene) ?? 256
        maxUIBindingsPerScene = try container.decodeIfPresent(Int.self, forKey: .maxUIBindingsPerScene) ?? 8
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

public enum RichAnswerDisplayText {
    /// Hang-proof math readability for agent chat + rich-answer narrative.
    /// Strips common LaTeX delimiters/commands into Unicode so native
    /// `AttributedString` stays legible without per-message KaTeX WKWebView.
    public static func normalizedInlineMath(_ text: String) -> String {
        var result = text
            .replacingOccurrences(of: "$$", with: "")
            .replacingOccurrences(of: #"\("#, with: "")
            .replacingOccurrences(of: #"\)"#, with: "")
            .replacingOccurrences(of: #"\["#, with: "")
            .replacingOccurrences(of: #"\]"#, with: "")

        // Pseudo display math from models: [ y_i=\hat y_i ] / multiline bracket blocks.
        if let multi = try? NSRegularExpression(pattern: #"\[\s*\n([\s\S]*?\\[A-Za-z]+[\s\S]*?)\n\s*\]"#) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = multi.stringByReplacingMatches(in: result, range: range, withTemplate: "$1")
        }
        if let single = try? NSRegularExpression(pattern: #"(?m)^\[\s*([^\n\]]*?\\[A-Za-z]+[^\n\]]*?)\]\s*$"#) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = single.stringByReplacingMatches(in: result, range: range, withTemplate: "$1")
        }

        result = replacing(
            #"\\(?:text|mathrm|operatorname|mathbf|mathit)\s*\{([^{}]+)\}"#,
            in: result,
            with: "$1"
        )
        result = replacing(
            #"\\frac\s*\{([^{}]+)\}\s*\{([^{}]+)\}"#,
            in: result,
            with: "($1)/($2)"
        )
        result = replacing(
            #"\\sqrt\s*\{([^{}]+)\}"#,
            in: result,
            with: "√($1)"
        )
        result = replacing(
            #"\\sqrt\s*([A-Za-z0-9.]+)"#,
            in: result,
            with: "√$1"
        )
        // Accents: \hat{y} / \hat y → ŷ
        result = replacing(#"\\hat\s*\{([^{}]+)\}"#, in: result, with: "$1\u{0302}")
        result = replacing(#"\\hat\s*([A-Za-z0-9])"#, in: result, with: "$1\u{0302}")
        result = replacing(#"\\bar\s*\{([^{}]+)\}"#, in: result, with: "$1\u{0304}")
        result = replacing(#"\\bar\s*([A-Za-z0-9])"#, in: result, with: "$1\u{0304}")
        result = replacing(#"\\tilde\s*\{([^{}]+)\}"#, in: result, with: "$1\u{0303}")
        result = replacing(#"\\tilde\s*([A-Za-z0-9])"#, in: result, with: "$1\u{0303}")
        result = replacing(#"\\vec\s*\{([^{}]+)\}"#, in: result, with: "$1\u{20D7}")
        result = replacing(#"\\vec\s*([A-Za-z0-9])"#, in: result, with: "$1\u{20D7}")

        let commandReplacements = [
            (#"\left"#, ""),
            (#"\right"#, ""),
            (#"\times"#, "×"),
            (#"\cdot"#, "·"),
            (#"\div"#, "÷"),
            (#"\sum"#, "∑"),
            (#"\prod"#, "∏"),
            (#"\int"#, "∫"),
            (#"\infty"#, "∞"),
            (#"\partial"#, "∂"),
            (#"\nabla"#, "∇"),
            (#"\rightarrow"#, "→"),
            (#"\leftarrow"#, "←"),
            (#"\Rightarrow"#, "⇒"),
            (#"\Leftarrow"#, "⇐"),
            (#"\leftrightarrow"#, "↔"),
            (#"\ldots"#, "…"),
            (#"\cdots"#, "⋯"),
            (#"\alpha"#, "α"),
            (#"\beta"#, "β"),
            (#"\gamma"#, "γ"),
            (#"\pi"#, "π"),
            (#"\sigma"#, "σ"),
            (#"\mu"#, "μ"),
            (#"\phi"#, "φ"),
            (#"\omega"#, "ω"),
            (#"\Gamma"#, "Γ"),
            (#"\Delta"#, "Δ"),
            (#"\Theta"#, "Θ"),
            (#"\Lambda"#, "Λ"),
            (#"\Sigma"#, "Σ"),
            (#"\Omega"#, "Ω"),
            (#"\delta"#, "δ"),
            (#"\theta"#, "θ"),
            (#"\lambda"#, "λ"),
            (#"\leq"#, "≤"),
            (#"\le"#, "≤"),
            (#"\geq"#, "≥"),
            (#"\ge"#, "≥"),
            (#"\neq"#, "≠"),
            (#"\approx"#, "≈"),
            (#"\propto"#, "∝"),
            (#"\pm"#, "±"),
            (#"\,"#, ""),
            (#"\;"#, ""),
            (#"\!"#, ""),
        ]
        for (command, replacement) in commandReplacements {
            result = result.replacingOccurrences(of: command, with: replacement)
        }

        // Single-dollar inline math: $...$ (skip $$ already cleared).
        result = replacing(#"\$([^$\n]{1,120})\$"#, in: result, with: "$1")

        result = replacing(#"\s*([≤≥≠≈∝])\s*"#, in: result, with: "$1")
        result = replacing(#"√\(([A-Za-z0-9.]+)\)"#, in: result, with: "√$1")
        result = replacing(#"\^\{([^{}]+)\}"#, in: result, with: "^$1")
        result = replacing(#"_\{([^{}]+)\}"#, in: result, with: "_$1")
        // Common single-char subscripts after normalize (y_i → yᵢ).
        let subscripts: [(String, String)] = [
            ("_0", "₀"), ("_1", "₁"), ("_2", "₂"), ("_3", "₃"), ("_4", "₄"),
            ("_5", "₅"), ("_6", "₆"), ("_7", "₇"), ("_8", "₈"), ("_9", "₉"),
            ("_i", "ᵢ"), ("_j", "ⱼ"), ("_n", "ₙ"), ("_t", "ₜ"), ("_x", "ₓ"),
        ]
        for (from, to) in subscripts {
            result = result.replacingOccurrences(of: from, with: to)
        }
        return result
    }

    private static func replacing(
        _ pattern: String,
        in text: String,
        with template: String
    ) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: template
        )
    }
}

public enum RichAnswerPartKind: String, Codable, Hashable, Sendable {
    case narrative
    case scene
}

public struct RichAnswerPart: Codable, Hashable, Sendable {
    public var kind: RichAnswerPartKind
    public var text: String?
    public var sceneID: String?

    public init(kind: RichAnswerPartKind, text: String? = nil, sceneID: String? = nil) {
        self.kind = kind
        self.text = text
        self.sceneID = sceneID
    }

    public static func narrative(_ text: String) -> RichAnswerPart {
        RichAnswerPart(kind: .narrative, text: text)
    }

    public static func scene(_ sceneID: String) -> RichAnswerPart {
        RichAnswerPart(kind: .scene, sceneID: sceneID)
    }
}

public struct RichAnswerPresentation: Codable, Hashable, Sendable {
    public var mode: RichAnswerPresentationMode
    public var narrative: String
    public var parts: [RichAnswerPart]?
    public var expressionPlan: RichAnswerExpressionPlan?
    public var scenes: [RichAnswerScene]
    public var evidenceLedger: [RichAnswerEvidence]
    public var fallback: RichAnswerFallback?
    public var diagnostics: [RichAnswerDiagnostic]
    public var evidenceState: RichAnswerEvidenceState

    public init(
        mode: RichAnswerPresentationMode,
        narrative: String,
        parts: [RichAnswerPart]? = nil,
        expressionPlan: RichAnswerExpressionPlan? = nil,
        scenes: [RichAnswerScene] = [],
        evidenceLedger: [RichAnswerEvidence] = [],
        fallback: RichAnswerFallback? = nil,
        diagnostics: [RichAnswerDiagnostic] = [],
        evidenceState: RichAnswerEvidenceState = .missing
    ) {
        self.mode = mode
        self.narrative = narrative
        self.parts = parts
        self.expressionPlan = expressionPlan
        self.scenes = scenes
        self.evidenceLedger = evidenceLedger
        self.fallback = fallback
        self.diagnostics = diagnostics
        self.evidenceState = evidenceState
    }

    public var resolvedParts: [RichAnswerPart] {
        if let parts, !parts.isEmpty {
            return parts
        }
        var fallbackParts: [RichAnswerPart] = []
        let trimmedNarrative = narrative.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNarrative.isEmpty {
            fallbackParts.append(.narrative(trimmedNarrative))
        }
        fallbackParts.append(contentsOf: scenes.map { .scene($0.id) })
        return fallbackParts
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
            if var ui = scene.ui {
                ui.nodes = ui.nodes.map { node in
                    var resolvedNode = node
                    if let assetID = node.assetID {
                        resolvedNode.assetID = aliases[assetID] ?? assetID
                    }
                    return resolvedNode
                }
                resolvedScene.ui = ui
            }
            if var renderPlan = scene.renderPlan {
                renderPlan.spec.fields = renderPlan.spec.fields.mapValues {
                    $0.resolvingAssetReferences(using: aliases)
                }
                resolvedScene.renderPlan = renderPlan
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

private extension RichAnswerRenderSpecValue {
    func resolvingAssetReferences(using aliases: [String: String]) -> RichAnswerRenderSpecValue {
        switch self {
        case .null, .bool, .number, .string:
            return self
        case let .array(values):
            return .array(values.map { $0.resolvingAssetReferences(using: aliases) })
        case let .object(fields):
            var resolvedFields = fields.mapValues {
                $0.resolvingAssetReferences(using: aliases)
            }
            if case let .string(kind)? = fields["kind"],
               kind == "assetRef",
               case let .string(source)? = fields["source"] {
                resolvedFields["source"] = .string(aliases[source] ?? source)
            }
            return .object(resolvedFields)
        }
    }
}

public enum RichAnswerEngine {
    public static func prepare(
        envelope: RichAnswerEnvelope,
        environment: RichAnswerEnvironment
    ) -> RichAnswerPresentation {
        var diagnostics: [RichAnswerDiagnostic] = []

        guard envelope.schemaVersion == 1 || envelope.schemaVersion == 2 else {
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
              envelope.narrative.count <= 3_200,
              !envelope.fallback.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              envelope.fallback.text.count <= 3_200,
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
        if let issue = validateExpressionPlanIntentBudget(envelope.expressionPlan) {
            diagnostics.append(issue)
            return narrativeFallback(envelope: envelope, diagnostics: diagnostics)
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
        let directUIRoles: Set<RichAnswerUIRole> = [.slider, .toggle, .scrubber, .select, .probe, .sequence]
        let hasDirectOperations = scenes.contains { scene in
            !scene.operations.isEmpty
                || scene.program?.directManipulation == true
                || scene.ui?.nodes.contains(where: { directUIRoles.contains($0.role) }) == true
                || scene.renderPlan?.interactionBindings.isEmpty == false
        }
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
        let flow = contentFlow(
            narrative: envelope.narrative,
            scenes: scenes,
            diagnostics: &diagnostics
        )
        guard mode != .rich || !flow.narrative.isEmpty else {
            diagnostics.append(
                RichAnswerDiagnostic(
                    code: .invalidValue,
                    message: "rich answer content flow must retain readable narrative"
                )
            )
            return narrativeFallback(envelope: envelope, diagnostics: diagnostics)
        }
        let narrative = scenes.isEmpty && !diagnostics.isEmpty ? envelope.fallback.text : flow.narrative

        return RichAnswerPresentation(
            mode: mode,
            narrative: narrative,
            parts: mode == .rich ? flow.parts : nil,
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

    private static func contentFlow(
        narrative: String,
        scenes: [RichAnswerScene],
        diagnostics: inout [RichAnswerDiagnostic]
    ) -> (narrative: String, parts: [RichAnswerPart]) {
        let scenesByID = Dictionary(uniqueKeysWithValues: scenes.map { ($0.id, $0) })
        var parts: [RichAnswerPart] = []
        var narrativeLines: [String] = []
        var referencedSceneIDs: Set<String> = []

        func flushNarrative() {
            let text = narrativeLines
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            narrativeLines.removeAll(keepingCapacity: true)
            if !text.isEmpty {
                parts.append(.narrative(text))
            }
        }

        for line in narrative.components(separatedBy: .newlines) {
            guard let sceneID = richAnswerSceneMarkerID(in: line) else {
                if line.contains("weibei-scene:") {
                    diagnostics.append(
                        RichAnswerDiagnostic(
                            code: .invalidValue,
                            message: "rich answer narrative contains a malformed scene marker"
                        )
                    )
                    continue
                }
                narrativeLines.append(line)
                continue
            }
            flushNarrative()
            guard scenesByID[sceneID] != nil else {
                diagnostics.append(
                    RichAnswerDiagnostic(
                        code: .brokenReference,
                        sceneID: sceneID,
                        message: "rich answer narrative references an unknown scene"
                    )
                )
                continue
            }
            guard referencedSceneIDs.insert(sceneID).inserted else {
                diagnostics.append(
                    RichAnswerDiagnostic(
                        code: .duplicateID,
                        sceneID: sceneID,
                        message: "rich answer narrative references the same scene more than once"
                    )
                )
                continue
            }
            parts.append(.scene(sceneID))
        }
        flushNarrative()

        for scene in scenes where !referencedSceneIDs.contains(scene.id) {
            parts.append(.scene(scene.id))
        }

        let plainNarrative = parts.compactMap { part -> String? in
            guard part.kind == .narrative else { return nil }
            return part.text
        }.joined(separator: "\n\n")

        return (plainNarrative, parts)
    }

    private static func richAnswerSceneMarkerID(in line: String) -> String? {
        let marker = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "<!-- weibei-scene:"
        let suffix = "-->"
        guard marker.hasPrefix(prefix), marker.hasSuffix(suffix) else { return nil }
        let start = marker.index(marker.startIndex, offsetBy: prefix.count)
        let end = marker.index(marker.endIndex, offsetBy: -suffix.count)
        let sceneID = marker[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        return isSafeIdentifier(sceneID) ? sceneID : nil
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
        let rendererEntryCount = [scene.program != nil, scene.ui != nil, scene.renderPlan != nil]
            .filter { $0 }
            .count
        guard rendererEntryCount > 0 || !scene.objects.isEmpty else {
            return RichAnswerDiagnostic(
                code: .emptyScene,
                sceneID: scene.id,
                message: "scene must submit one generated renderer entry or a legacy knowledge-object scene"
            )
        }
        guard rendererEntryCount <= 1 else {
            return RichAnswerDiagnostic(
                code: .unsupportedField,
                sceneID: scene.id,
                message: "scene cannot submit more than one of program, ui, or renderPlan"
            )
        }
        guard scene.program == nil || scene.operations.isEmpty else {
            return RichAnswerDiagnostic(
                code: .unsupportedField,
                sceneID: scene.id,
                message: "OpenUI program scenes cannot also submit legacy operations"
            )
        }
        guard scene.renderPlan == nil || scene.operations.isEmpty else {
            return RichAnswerDiagnostic(
                code: .unsupportedField,
                sceneID: scene.id,
                message: "renderPlan scenes cannot also submit legacy operations"
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
              scene.frames.count <= environment.resourceBudget.maxFramesPerScene,
              (scene.ui?.nodes.count ?? 0) <= environment.resourceBudget.maxUINodesPerScene,
              (scene.ui?.datasets.flatMap(\.rows).count ?? 0) <= environment.resourceBudget.maxUIDataRowsPerScene,
              (scene.ui?.bindings.count ?? 0) <= environment.resourceBudget.maxUIBindingsPerScene else {
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

        if let program = scene.program {
            if let issue = validateUIProgram(program, scene: scene) {
                return issue
            }
            return nil
        }

        if let ui = scene.ui {
            if let issue = validateUIComposition(
                ui,
                sceneID: scene.id,
                evidenceByID: evidenceByID,
                environment: environment
            ) {
                return issue
            }
            let boundEvidenceIDs = reachableUIEvidenceIDs(in: ui)
            guard Set(scene.evidenceIDs).isSubset(of: boundEvidenceIDs) else {
                return missingEvidence(
                    sceneID: scene.id,
                    "generated UI does not bind every scene evidence item to a reachable node or data row"
                )
            }
            return nil
        }

        if let renderPlan = scene.renderPlan {
            return validateRenderPlan(
                renderPlan,
                scene: scene,
                evidenceByID: evidenceByID
            )
        }

        if let issue = validateFamilyContract(scene) {
            return issue
        }

        return nil
    }

    private static func validateRenderPlan(
        _ plan: RichAnswerRenderPlan,
        scene: RichAnswerScene,
        evidenceByID: [String: RichAnswerEvidence]
    ) -> RichAnswerDiagnostic? {
        let negotiation = RichAnswerRendererRegistry.defaultRegistry().negotiate(plan: plan)
        guard negotiation.status == .accepted else {
            let message = negotiation.mismatch?.issues.first?.message ?? "renderPlan capability negotiation failed"
            return RichAnswerDiagnostic(
                code: .invalidParameter,
                sceneID: scene.id,
                message: "renderPlan capability negotiation failed: \(message)"
            )
        }

        let sceneEvidenceIDs = Set(scene.evidenceIDs)
        let boundEvidenceIDs = Set(plan.sourceBindings.map(\.evidenceID))
        guard plan.sourceBindings.allSatisfy({
            sceneEvidenceIDs.contains($0.evidenceID) && evidenceByID[$0.evidenceID] != nil
        }) else {
            return missingEvidence(
                sceneID: scene.id,
                "renderPlan sourceBindings must reference evidence IDs declared by this scene and evidence ledger"
            )
        }
        guard sceneEvidenceIDs.isSubset(of: boundEvidenceIDs) else {
            return missingEvidence(
                sceneID: scene.id,
                "renderPlan sourceBindings must cover every scene evidence item"
            )
        }

        return nil
    }

    private static func validateUIProgram(
        _ program: RichAnswerUIProgram,
        scene: RichAnswerScene
    ) -> RichAnswerDiagnostic? {
        let sceneID = scene.id
        guard program.version == "weibei.openui.v1" else {
            return RichAnswerDiagnostic(
                code: .unsupportedSchema,
                sceneID: sceneID,
                message: "generated UI program uses an unsupported protocol version"
            )
        }

        let source = program.source.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = source
            .split(whereSeparator: { character in character.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !source.isEmpty,
              source.count <= 10_000,
              !lines.isEmpty,
              lines.count <= 48,
              (160...720).contains(program.maxHeight),
              !program.capabilities.isEmpty,
              program.capabilities.count <= 12,
              Set(program.capabilities).count == program.capabilities.count else {
            return RichAnswerDiagnostic(
                code: .budgetExceeded,
                sceneID: sceneID,
                message: "generated UI program exceeds its source, capability, or height budget"
            )
        }

        let forbiddenFragments = [
            "<script", "</script", "<svg", "<iframe", "javascript:",
            "http://", "https://", "Query(", "Mutation(", "OpenUrl(",
        ]
        guard forbiddenFragments.allSatisfy({ !source.localizedCaseInsensitiveContains($0) }) else {
            return RichAnswerDiagnostic(
                code: .unauthorizedAsset,
                sceneID: sceneID,
                message: "generated UI program attempted to use markup, network access, or executable tools"
            )
        }

        let allowedComponents: Set<String> = [
            "RichAnswerRoot", "LearningStage", "NarrativeBlock", "ParameterSlider",
            "ParameterReadout", "ValuePicker", "FunctionPlot", "ComparisonRow",
            "ComparisonTable", "EvidenceSnippet", "ReasonStep", "ProcessStepper",
            "QuadraticMechanism", "FollowUpAction", "ChartSeries", "LinkedDataChart",
            "MetricItem", "MetricStrip", "ExecutionFrame", "ExecutionTrack",
            "ArgumentUnit", "ArgumentReader", "CausalEvent", "CausalTrack",
            "TwoPointLineLab", "BalanceExperiment", "SpatialLayer", "SpatialRegion",
            "SpatialPath", "SpatialPoint", "LayeredSpatialView", "DistributionBrush",
            "FlowAssumption", "DependencyNode", "FlowMetric", "DependencyFlow",
        ]
        var hasRoot = false
        let evidenceBindingComponents: Set<String> = [
            "EvidenceSnippet",
            "ArgumentUnit",
            "CausalEvent",
            "SpatialPoint",
        ]
        var evidenceBindingLines: [String] = []
        for line in lines {
            if line.hasPrefix("$") {
                guard line.range(
                    of: #"^\$[A-Za-z][A-Za-z0-9_]*\s*=\s*.+$"#,
                    options: .regularExpression
                ) != nil else {
                    return invalidValue(sceneID: sceneID, "generated UI program has an invalid state declaration")
                }
                continue
            }

            guard let equals = line.firstIndex(of: "="),
                  let openParenthesis = line[equals...].firstIndex(of: "(") else {
                return invalidValue(sceneID: sceneID, "generated UI program has an invalid component statement")
            }
            let statementID = line[..<equals].trimmingCharacters(in: .whitespacesAndNewlines)
            let componentName = line[line.index(after: equals)..<openParenthesis]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard isSafeIdentifier(statementID), allowedComponents.contains(componentName) else {
                return RichAnswerDiagnostic(
                    code: .unsupportedField,
                    sceneID: sceneID,
                    message: "generated UI program references a component outside WeiBei's catalog"
                )
            }
            if statementID == "root" {
                hasRoot = componentName == "RichAnswerRoot"
            }
            if evidenceBindingComponents.contains(componentName) {
                evidenceBindingLines.append(line)
            }
        }

        guard hasRoot else {
            return brokenReference(sceneID: sceneID, "generated UI program does not define a RichAnswerRoot")
        }
        let canvasComponents = [
            "FunctionPlot(", "LinkedDataChart(", "TwoPointLineLab(",
            "LayeredSpatialView(", "DistributionBrush(",
        ]
        if program.graphics == .dom,
           canvasComponents.contains(where: source.contains) {
            return invalidValue(sceneID: sceneID, "generated UI Canvas components require the Canvas graphics kernel")
        }
        let bindsEveryEvidence = scene.evidenceIDs.allSatisfy { evidenceID in
            guard let data = try? JSONEncoder().encode(evidenceID),
                  let quotedEvidenceID = String(data: data, encoding: .utf8) else { return false }
            return evidenceBindingLines.contains { line in
                line.contains(quotedEvidenceID)
            }
        }
        guard bindsEveryEvidence else {
            return missingEvidence(
                sceneID: sceneID,
                "generated UI program must bind every scene evidence item through EvidenceSnippet, ArgumentUnit, CausalEvent, or SpatialPoint"
            )
        }
        return nil
    }

    private static func validateUIComposition(
        _ ui: RichAnswerUIComposition,
        sceneID: String,
        evidenceByID: [String: RichAnswerEvidence],
        environment: RichAnswerEnvironment
    ) -> RichAnswerDiagnostic? {
        guard !ui.nodes.isEmpty else {
            return invalidValue(sceneID: sceneID, "generated UI requires at least one node")
        }

        let nodeIDs = ui.nodes.map(\.id)
        let datasetIDs = ui.datasets.map(\.id)
        let bindingIDs = ui.bindings.map(\.id)
        let rowIDs = ui.datasets.flatMap { $0.rows.map(\.id) }
        guard idsAreUniqueAndSafe(nodeIDs + datasetIDs + bindingIDs + rowIDs) else {
            return RichAnswerDiagnostic(
                code: .duplicateID,
                sceneID: sceneID,
                message: "generated UI node, dataset, row, and binding ids must be unique and safe"
            )
        }

        let nodesByID = Dictionary(uniqueKeysWithValues: ui.nodes.map { ($0.id, $0) })
        let datasetsByID = Dictionary(uniqueKeysWithValues: ui.datasets.map { ($0.id, $0) })
        let bindingsByID = Dictionary(uniqueKeysWithValues: ui.bindings.map { ($0.id, $0) })
        guard nodesByID[ui.rootID] != nil else {
            return brokenReference(sceneID: sceneID, "generated UI root references a missing node")
        }

        var parentCounts: [String: Int] = [:]
        for node in ui.nodes {
            guard node.children.allSatisfy({ nodesByID[$0] != nil }) else {
                return brokenReference(sceneID: sceneID, "generated UI node \(node.id) references a missing child")
            }
            for childID in node.children {
                parentCounts[childID, default: 0] += 1
            }
            if let issue = validateUINode(
                node,
                sceneID: sceneID,
                nodesByID: nodesByID,
                datasetsByID: datasetsByID,
                bindingsByID: bindingsByID,
                evidenceByID: evidenceByID,
                environment: environment
            ) {
                return issue
            }
        }

        guard parentCounts[ui.rootID, default: 0] == 0,
              parentCounts.values.allSatisfy({ $0 <= 1 }) else {
            return invalidValue(sceneID: sceneID, "generated UI must be a tree with one parent per node")
        }

        var visited: Set<String> = []
        var active: Set<String> = []
        func visit(_ nodeID: String, depth: Int) -> Bool {
            guard depth <= 7, let node = nodesByID[nodeID] else { return false }
            if active.contains(nodeID) { return false }
            if visited.contains(nodeID) { return true }
            active.insert(nodeID)
            for childID in node.children where !visit(childID, depth: depth + 1) {
                return false
            }
            active.remove(nodeID)
            visited.insert(nodeID)
            return true
        }
        guard visit(ui.rootID, depth: 1), visited.count == ui.nodes.count else {
            return invalidValue(sceneID: sceneID, "generated UI contains a cycle, unreachable node, or excessive nesting")
        }
        let reachableNodes = ui.nodes.filter { visited.contains($0.id) }

        for dataset in ui.datasets {
            guard !dataset.rows.isEmpty else {
                return invalidValue(sceneID: sceneID, "generated UI dataset \(dataset.id) is empty")
            }
            for row in dataset.rows {
                guard row.x.isFinite,
                      row.y.isFinite,
                      row.x >= 0,
                      row.x <= 1,
                      row.y >= 0,
                      row.y <= 1,
                      row.value.map(\.isFinite) ?? true,
                      row.result.map(\.isFinite) ?? true else {
                    return invalidValue(sceneID: sceneID, "generated UI row \(row.id) has invalid normalized coordinates")
                }
                let hasSecondPoint = row.x2 != nil || row.y2 != nil
                if hasSecondPoint {
                    guard let x2 = row.x2, let y2 = row.y2,
                          x2.isFinite,
                          y2.isFinite,
                          x2 >= 0,
                          x2 <= 1,
                          y2 >= 0,
                          y2 <= 1 else {
                        return invalidValue(sceneID: sceneID, "generated UI row \(row.id) has an invalid vector endpoint")
                    }
                }
                guard row.evidenceIDs.allSatisfy({ evidenceByID[$0] != nil }) else {
                    return missingEvidence(sceneID: sceneID, "generated UI row \(row.id) references missing evidence")
                }
            }
        }

        for binding in ui.bindings {
            guard binding.minimum.isFinite,
                  binding.maximum.isFinite,
                  binding.step.isFinite,
                  binding.initialValue.isFinite,
                  binding.minimum < binding.maximum,
                  binding.step > 0,
                  binding.initialValue >= binding.minimum,
                  binding.initialValue <= binding.maximum else {
                return RichAnswerDiagnostic(
                    code: .invalidParameter,
                    sceneID: sceneID,
                    message: "generated UI binding \(binding.id) has invalid bounds"
                )
            }
            let controlRoles: Set<RichAnswerUIRole> = [.slider, .toggle, .scrubber, .probe]
            let outputRoles: Set<RichAnswerUIRole> = [
                .metric, .sequence, .line, .path, .point, .area, .shape, .bar,
                .dotMatrix, .vector, .region, .image,
            ]
            let hasControl = reachableNodes.contains {
                $0.bindingID == binding.id && controlRoles.contains($0.role)
            }
            let hasDrivenOutput = reachableNodes.contains {
                $0.bindingID == binding.id && outputRoles.contains($0.role)
            }
            guard hasControl, hasDrivenOutput else {
                return invalidValue(
                    sceneID: sceneID,
                    "generated UI binding \(binding.id) must connect a visible control to a driven mark or metric"
                )
            }
            guard bindingHasChangingOutcome(
                binding,
                reachableNodes: reachableNodes,
                datasetsByID: datasetsByID
            ) else {
                return invalidValue(
                    sceneID: sceneID,
                    "generated UI binding \(binding.id) must produce a verifiable semantic or quantitative outcome change"
                )
            }
        }
        return nil
    }

    private static func bindingHasChangingOutcome(
        _ binding: RichAnswerUIBinding,
        reachableNodes: [RichAnswerUINode],
        datasetsByID: [String: RichAnswerUIDataset]
    ) -> Bool {
        let outputRoles: Set<RichAnswerUIRole> = [
            .metric,
            .sequence,
            .line,
            .path,
            .point,
            .area,
            .shape,
            .bar,
            .dotMatrix,
            .vector,
            .region,
            .image,
        ]
        let drivenOutputs = reachableNodes.filter {
            $0.bindingID == binding.id && outputRoles.contains($0.role)
        }
        return drivenOutputs.contains { node in
            guard let datasetID = node.datasetID,
                  let dataset = datasetsByID[datasetID] else {
                return false
            }
            return datasetRowsHaveChangingOutcome(
                dataset.rows,
                acceptsSemanticOnly: node.role == .sequence
            )
        }
    }

    private static func datasetRowsHaveChangingOutcome(
        _ rows: [RichAnswerUIDataRow],
        acceptsSemanticOnly: Bool
    ) -> Bool {
        guard rows.count >= 2 else { return false }
        let signatures = Set(rows.map { row in
            [
                row.value.map { String(format: "%.6f", $0) } ?? "",
                row.result.map { String(format: "%.6f", $0) } ?? "",
                String(format: "%.6f", row.x),
                String(format: "%.6f", row.y),
                row.x2.map { String(format: "%.6f", $0) } ?? "",
                row.y2.map { String(format: "%.6f", $0) } ?? "",
                row.label?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "",
            ].joined(separator: "|")
        })
        let hasVaryingNumericState = Set(rows.compactMap(\.value)).count >= 2
            || Set(rows.compactMap(\.result)).count >= 2
            || Set(rows.map(\.x)).count >= 2
            || Set(rows.map(\.y)).count >= 2
            || Set(rows.compactMap(\.x2)).count >= 2
            || Set(rows.compactMap(\.y2)).count >= 2
        let hasVaryingSemanticState = Set(
            rows.compactMap { row in
                row.label?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }.filter { !$0.isEmpty }
        ).count >= 2
        return signatures.count >= 2
            && (hasVaryingNumericState || (acceptsSemanticOnly && hasVaryingSemanticState))
    }

    private static func reachableUIEvidenceIDs(in ui: RichAnswerUIComposition) -> Set<String> {
        let nodesByID = Dictionary(uniqueKeysWithValues: ui.nodes.map { ($0.id, $0) })
        var visited: Set<String> = []
        var active: Set<String> = []
        func visit(_ nodeID: String, depth: Int) {
            guard depth <= 7,
                  let node = nodesByID[nodeID],
                  !active.contains(nodeID),
                  !visited.contains(nodeID) else { return }
            active.insert(nodeID)
            for childID in node.children {
                visit(childID, depth: depth + 1)
            }
            active.remove(nodeID)
            visited.insert(nodeID)
        }
        visit(ui.rootID, depth: 1)
        let reachableNodes = ui.nodes.filter { visited.contains($0.id) }
        let reachableDatasetIDs = Set(reachableNodes.compactMap(\.datasetID))
        let nodeEvidenceIDs = reachableNodes.flatMap(\.evidenceIDs)
        let rowEvidenceIDs = ui.datasets
            .filter { reachableDatasetIDs.contains($0.id) }
            .flatMap { dataset in dataset.rows.flatMap(\.evidenceIDs) }
        return Set(nodeEvidenceIDs + rowEvidenceIDs)
    }

    private static func validateUINode(
        _ node: RichAnswerUINode,
        sceneID: String,
        nodesByID: [String: RichAnswerUINode],
        datasetsByID: [String: RichAnswerUIDataset],
        bindingsByID: [String: RichAnswerUIBinding],
        evidenceByID: [String: RichAnswerEvidence],
        environment: RichAnswerEnvironment
    ) -> RichAnswerDiagnostic? {
        let containerRoles: Set<RichAnswerUIRole> = [.vstack, .hstack, .zstack, .grid, .panel]
        let canvasRoles: Set<RichAnswerUIRole> = [
            .axis, .line, .path, .point, .area, .shape, .bar, .dotMatrix,
            .vector, .region, .image, .label,
        ]
        let datasetRoles: Set<RichAnswerUIRole> = [
            .metric, .sequence, .line, .path, .point, .area, .bar, .dotMatrix, .vector, .label,
        ]
        let bindingRoles: Set<RichAnswerUIRole> = [.slider, .toggle, .scrubber, .probe]

        if containerRoles.contains(node.role) {
            guard !node.children.isEmpty else {
                return invalidValue(sceneID: sceneID, "generated UI container \(node.id) has no children")
            }
        } else if node.role == .canvas {
            guard !node.children.isEmpty,
                  node.children.allSatisfy({ childID in
                      nodesByID[childID].map { canvasRoles.contains($0.role) } == true
                  }) else {
                return invalidValue(sceneID: sceneID, "generated UI canvas \(node.id) only accepts visual mark children")
            }
            guard node.xAxis.map({ $0.minimum.isFinite && $0.maximum.isFinite && $0.minimum < $0.maximum }) ?? true,
                  node.yAxis.map({ $0.minimum.isFinite && $0.maximum.isFinite && $0.minimum < $0.maximum }) ?? true else {
                return invalidValue(sceneID: sceneID, "generated UI canvas \(node.id) has an invalid axis")
            }
        } else {
            guard node.children.isEmpty else {
                return invalidValue(sceneID: sceneID, "generated UI leaf \(node.id) cannot have children")
            }
        }

        if node.role == .grid {
            guard let columns = node.columns, (2...3).contains(columns) else {
                return invalidValue(sceneID: sceneID, "generated UI grid \(node.id) requires two or three columns")
            }
        } else if node.columns != nil {
            return RichAnswerDiagnostic(
                code: .unsupportedField,
                sceneID: sceneID,
                message: "generated UI node \(node.id) uses columns outside a grid"
            )
        }

        if datasetRoles.contains(node.role) {
            guard let datasetID = node.datasetID, datasetsByID[datasetID] != nil else {
                return brokenReference(sceneID: sceneID, "generated UI node \(node.id) references a missing dataset")
            }
        } else if node.role == .shape, let datasetID = node.datasetID {
            guard datasetsByID[datasetID] != nil else {
                return brokenReference(sceneID: sceneID, "generated UI shape \(node.id) references a missing dataset")
            }
        } else if node.datasetID != nil && node.role != .select {
            return RichAnswerDiagnostic(
                code: .unsupportedField,
                sceneID: sceneID,
                message: "generated UI node \(node.id) cannot bind a dataset"
            )
        }

        if bindingRoles.contains(node.role) {
            guard let bindingID = node.bindingID, bindingsByID[bindingID] != nil else {
                return brokenReference(sceneID: sceneID, "generated UI control \(node.id) references a missing binding")
            }
        } else if let bindingID = node.bindingID,
                  bindingsByID[bindingID] == nil {
            return brokenReference(sceneID: sceneID, "generated UI node \(node.id) references a missing binding")
        }

        if node.role == .text {
            guard node.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                return invalidValue(sceneID: sceneID, "generated UI text \(node.id) is empty")
            }
        }
        if node.role == .sequence {
            guard let datasetID = node.datasetID,
                  let dataset = datasetsByID[datasetID],
                  dataset.rows.count >= 2 else {
                return invalidValue(sceneID: sceneID, "generated UI sequence \(node.id) requires at least two dataset rows")
            }
            guard dataset.rows.allSatisfy({ hasMeaningfulText($0.label) }) else {
                return invalidValue(sceneID: sceneID, "generated UI sequence \(node.id) requires every row to expose a visible label")
            }
        }
        if node.role == .region, node.region == nil {
            return invalidValue(sceneID: sceneID, "generated UI region \(node.id) has no bounds")
        }
        if node.role == .shape {
            guard node.shape != nil, node.region != nil, node.fill != nil else {
                return invalidValue(sceneID: sceneID, "generated UI shape \(node.id) requires a shape kind, fill, and bounds")
            }
            if node.bindingID != nil, node.datasetID == nil {
                return invalidValue(sceneID: sceneID, "generated UI movable shape \(node.id) requires a dataset")
            }
        } else if node.shape != nil {
            return RichAnswerDiagnostic(
                code: .unsupportedField,
                sceneID: sceneID,
                message: "generated UI node \(node.id) uses a shape kind outside a shape mark"
            )
        }
        let fillRoles: Set<RichAnswerUIRole> = [.shape, .bar, .dotMatrix, .region, .area]
        if node.fill != nil, !fillRoles.contains(node.role) {
            return RichAnswerDiagnostic(
                code: .unsupportedField,
                sceneID: sceneID,
                message: "generated UI node \(node.id) uses fill outside a filled visual mark"
            )
        }
        if let region = node.region,
           !(region.x.isFinite
                && region.y.isFinite
                && region.width.isFinite
                && region.height.isFinite
                && region.x >= 0
                && region.y >= 0
                && region.width > 0
                && region.height > 0
                && region.x + region.width <= 1
                && region.y + region.height <= 1) {
            return invalidValue(sceneID: sceneID, "generated UI node \(node.id) has invalid bounds")
        }
        if node.role == .image {
            guard let assetID = node.assetID, isAllowedAssetID(assetID, environment: environment) else {
                return RichAnswerDiagnostic(
                    code: .unauthorizedAsset,
                    sceneID: sceneID,
                    message: "generated UI image \(node.id) references an unauthorized asset"
                )
            }
        } else if node.assetID != nil {
            return RichAnswerDiagnostic(
                code: .unsupportedField,
                sceneID: sceneID,
                message: "generated UI node \(node.id) uses an asset outside an image mark"
            )
        }
        guard node.evidenceIDs.allSatisfy({ evidenceByID[$0] != nil }) else {
            return missingEvidence(sceneID: sceneID, "generated UI node \(node.id) references missing evidence")
        }
        if node.role == .evidence, node.evidenceIDs.isEmpty {
            return missingEvidence(sceneID: sceneID, "generated UI evidence node \(node.id) has no source")
        }
        return nil
    }

    private static func validateFamilyContract(_ scene: RichAnswerScene) -> RichAnswerDiagnostic? {
        if let issue = validateSupportedOperations(scene) {
            return issue
        }

        switch scene.family {
        case .textAndAlignment:
            return validateTextAlignmentContract(scene)
        case .quantityAndCoordinates:
            return validateQuantityCoordinateContract(scene)
        case .processAndState:
            return validateProcessStateContract(scene)
        case .relationAndEvidence:
            return validateRelationEvidenceContract(scene)
        case .timeAndSpace:
            return validateTimeSpaceContract(scene)
        case .imageAndOverlay:
            return validateImageOverlayContract(scene)
        case .comparisonAndEvaluation:
            return validateComparisonEvaluationContract(scene)
        case .calculationAndConstraints:
            return validateCalculationConstraintContract(scene)
        }
    }

    private static func validateExpressionPlanIntentBudget(
        _ plan: RichAnswerExpressionPlan
    ) -> RichAnswerDiagnostic? {
        let groups = [
            plan.knowledgeObjects,
            plan.knowledgeRelations,
            plan.knowledgeProcesses,
            plan.visualPrimitives,
            plan.visualRationale,
        ]
        guard plan.knowledgeNatures.count <= 8,
              groups.allSatisfy({ $0.count <= 12 }),
              groups.flatMap({ $0 }).allSatisfy({
                  let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                  return !trimmed.isEmpty && trimmed.count <= 240
              }) else {
            return RichAnswerDiagnostic(
                code: .budgetExceeded,
                message: "rich answer expression intent exceeded its declaration budget"
            )
        }
        return nil
    }

    private static func validateGeneratedFamilyContract(_ scene: RichAnswerScene) -> RichAnswerDiagnostic? {
        let programComponents = generatedProgramComponents(in: scene.program?.source)
        let nodes = scene.ui?.nodes ?? []
        let roles = Set(nodes.map(\.role))
        let dataRowCount = scene.ui?.datasets.reduce(0) { $0 + $1.rows.count } ?? 0
        let bindingCount = scene.ui?.bindings.count ?? 0

        func usesProgram(_ names: Set<String>) -> Bool {
            !programComponents.isDisjoint(with: names)
        }

        func usesRole(_ candidates: Set<RichAnswerUIRole>) -> Bool {
            !roles.isDisjoint(with: candidates)
        }
        let hasEvidenceNode = roles.contains(.evidence)
        let semanticRelationLabelCount = nodes.filter { node in
            [.label, .text, .sequence, .metric].contains(node.role)
                && (
                    !node.evidenceIDs.isEmpty
                        || node.datasetID != nil
                        || node.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                )
        }.count
        let hasQuantityCanvas = roles.contains(.canvas)
            && usesRole([.axis, .line, .path, .point, .area, .bar, .dotMatrix, .vector, .metric])

        let isValid: Bool
        switch scene.family {
        case .textAndAlignment:
            isValid = usesProgram(["ArgumentReader", "ArgumentUnit", "ComparisonTable"])
                || (roles.contains(.text) && (roles.contains(.evidence) || usesRole([.select, .toggle, .probe])))
        case .quantityAndCoordinates:
            isValid = usesProgram([
                "FunctionPlot", "TwoPointLineLab", "LinkedDataChart", "DistributionBrush",
                "DependencyFlow", "ComparisonTable", "MetricStrip",
            ]) || (hasQuantityCanvas && dataRowCount > 0 && (bindingCount > 0 || roles.contains(.metric)))
        case .processAndState:
            isValid = usesProgram([
                "ProcessStepper", "QuadraticMechanism", "ExecutionTrack", "BalanceExperiment",
                "ArgumentReader", "CausalTrack",
            ]) || roles.contains(.sequence)
                || (usesRole([.slider, .scrubber, .select, .toggle, .probe])
                && (dataRowCount >= 2 || roles.contains(.text) || roles.contains(.metric)))
        case .relationAndEvidence:
            isValid = usesProgram([
                "ArgumentReader", "CausalTrack", "DependencyFlow", "LayeredSpatialView", "ComparisonTable",
            ]) || (hasEvidenceNode && (
                (roles.contains(.sequence) && dataRowCount >= 2)
                    || (usesRole([.path, .line, .vector]) && semanticRelationLabelCount >= 2)
            ))
        case .timeAndSpace:
            isValid = usesProgram(["CausalTrack", "LayeredSpatialView", "LinkedDataChart"])
                || (usesRole([.canvas, .image]) && usesRole([.path, .point, .region, .vector, .area]))
                || (roles.contains(.sequence) && dataRowCount >= 2)
        case .imageAndOverlay:
            isValid = roles.contains(.image) && usesRole([.region, .path, .point, .shape])
        case .comparisonAndEvaluation:
            let comparisonValueCount = scene.ui?.nodes.filter {
                [.metric, .text, .label, .bar, .dotMatrix].contains($0.role)
            }.count ?? 0
            isValid = usesProgram([
                "ComparisonTable", "LinkedDataChart", "DistributionBrush", "ArgumentReader",
                "MetricStrip", "DependencyFlow",
            ]) || (usesRole([.grid, .hstack, .vstack]) && comparisonValueCount >= 2)
        case .calculationAndConstraints:
            isValid = usesProgram([
                "DependencyFlow", "FunctionPlot", "TwoPointLineLab", "QuadraticMechanism",
                "DistributionBrush", "BalanceExperiment",
            ]) || (bindingCount > 0 && roles.contains(.metric)
                && usesRole([.slider, .scrubber, .probe])
                && usesRole([.shape, .line, .path, .bar, .metric]))
        }

        guard isValid else {
            return invalidValue(
                sceneID: scene.id,
                "generated UI structure does not satisfy the declared \(scene.family.rawValue) capability contract"
            )
        }
        return nil
    }

    private static func validateGeneratedIntentContract(
        _ scene: RichAnswerScene,
        expressionPlan: RichAnswerExpressionPlan
    ) -> RichAnswerDiagnostic? {
        guard let ui = scene.ui else { return nil }
        let planDeclaresIntent = !expressionPlan.knowledgeNatures.isEmpty
            || !expressionPlan.knowledgeObjects.isEmpty
            || !expressionPlan.knowledgeRelations.isEmpty
            || !expressionPlan.knowledgeProcesses.isEmpty
            || !expressionPlan.visualPrimitives.isEmpty
            || !expressionPlan.visualRationale.isEmpty
        guard planDeclaresIntent else { return nil }

        let roles = Set(ui.nodes.map(\.role))
        if !expressionPlan.visualPrimitives.isEmpty {
            let primitiveRoles = expressionPlan.visualPrimitives.compactMap(RichAnswerUIRole.init(rawValue:))
            guard primitiveRoles.count == expressionPlan.visualPrimitives.count else {
                return invalidValue(
                    sceneID: scene.id,
                    "generated UI expression plan names primitives outside the T2 role catalog"
                )
            }
            let missingRoles = Set(primitiveRoles).subtracting(roles)
            guard missingRoles.isEmpty else {
                return invalidValue(
                    sceneID: scene.id,
                    "generated UI does not use its declared visual primitives: \(missingRoles.map(\.rawValue).sorted().joined(separator: ", "))"
                )
            }
        }

        let visibleText = visibleSemanticText(in: ui, sceneTitle: scene.title)
        var missingCategories: [String] = []
        if !expressionPlan.knowledgeObjects.isEmpty {
            let matchedObjectCount = expressionPlan.knowledgeObjects.filter {
                semanticText(visibleText, contains: $0)
            }.count
            let requiredObjectCount = min(2, expressionPlan.knowledgeObjects.count)
            if matchedObjectCount < requiredObjectCount {
                missingCategories.append(
                    "knowledge objects (show at least \(requiredObjectCount)): \(declarationSamples(expressionPlan.knowledgeObjects))"
                )
            }
        }

        if !expressionPlan.knowledgeRelations.isEmpty,
           !expressionPlan.knowledgeRelations.contains(where: {
               semanticText(visibleText, contains: $0)
           }),
           !generatedUIHasSemanticRelationStructure(
               ui,
               relations: expressionPlan.knowledgeRelations,
               visibleText: visibleText
           ) {
            missingCategories.append(
                "knowledge relation: \(declarationSamples(expressionPlan.knowledgeRelations))"
            )
        }

        if !expressionPlan.knowledgeProcesses.isEmpty {
            let hasVisibleProcess = expressionPlan.knowledgeProcesses.contains {
                semanticText(visibleText, contains: $0)
            }
            let declaresInteractiveProcess = expressionPlan.knowledgeProcesses.contains {
                declaresInteractionProcess($0)
            }
            let processHasVisibleAnchors = expressionPlan.knowledgeProcesses.contains {
                relationHasVisibleAnchors($0, visibleText: visibleText)
            }
            let hasStructuredProcess =
                (ui.nodes.contains(where: { $0.role == .sequence }) && processHasVisibleAnchors)
                || (generatedUIHasBoundSemanticInteraction(ui)
                    && (declaresInteractiveProcess || processHasVisibleAnchors))
            if !hasVisibleProcess && !hasStructuredProcess {
                missingCategories.append(
                    "knowledge process: \(declarationSamples(expressionPlan.knowledgeProcesses))"
                )
            }
        }

        if !missingCategories.isEmpty {
            return invalidValue(
                sceneID: scene.id,
                "generated UI misses declared semantic categories: \(missingCategories.joined(separator: "; ")); "
                    + "visible semantic summary: \(boundedVisibleSemanticSummary(in: ui, sceneTitle: scene.title))"
            )
        }

        let embodiedNatures: Set<RichAnswerKnowledgeNature> = [
            .objectMechanism,
            .spatialStructure,
            .imageObservation,
        ]
        let requiresEmbodiedVisual = !expressionPlan.knowledgeNatures.isDisjoint(with: embodiedNatures)
        if requiresEmbodiedVisual {
            let embodiedRoles: Set<RichAnswerUIRole> = [
                .shape,
                .vector,
                .region,
                .image,
                .area,
                .sequence,
                .bar,
                .dotMatrix,
                .line,
                .path,
                .point,
                .metric,
            ]
            guard !roles.isDisjoint(with: embodiedRoles) else {
                return invalidValue(
                    sceneID: scene.id,
                    "object, space, or image knowledge must bind to a visible semantic mark"
                )
            }
            if !ui.bindings.isEmpty {
                let controlDrivesEmbodiedMark = ui.bindings.contains { binding in
                    ui.nodes.contains { node in
                        node.bindingID == binding.id && embodiedRoles.contains(node.role)
                    }
                }
                guard controlDrivesEmbodiedMark else {
                    return invalidValue(
                        sceneID: scene.id,
                        "object, space, or image controls must change a visible semantic mark or readout"
                    )
                }
            }
        }

        return nil
    }

    private static func visibleSemanticText(
        in ui: RichAnswerUIComposition,
        sceneTitle: String
    ) -> String {
        let nodeText = ui.nodes.flatMap { node in
            [node.label, node.text, node.unit, node.xAxis?.label, node.yAxis?.label].compactMap { $0 }
        }
        let rowText = ui.datasets.flatMap { dataset in
            dataset.rows.compactMap(\.label)
        }
        let bindingText = ui.bindings.flatMap { binding in
            [binding.label, binding.unit].compactMap { $0 }
        }
        return ([sceneTitle] + nodeText + rowText + bindingText).joined(separator: " ")
    }

    private static func semanticText(_ haystack: String, contains needle: String) -> Bool {
        let normalizedHaystack = semanticSearchText(haystack)
        let normalizedNeedle = semanticSearchText(needle)
        if normalizedNeedle.count == 1 {
            if normalizedNeedle.range(of: #"^[a-z]$"#, options: [.regularExpression, .caseInsensitive]) != nil {
                let escaped = NSRegularExpression.escapedPattern(for: normalizedNeedle)
                return haystack.range(
                    of: "(^|[^A-Za-z0-9])\(escaped)($|[^A-Za-z0-9])",
                    options: [.regularExpression, .caseInsensitive]
                ) != nil
            }
            return normalizedHaystack.contains(normalizedNeedle)
        }
        guard normalizedNeedle.count >= 2 else { return false }
        if normalizedHaystack.contains(normalizedNeedle) { return true }
        guard normalizedNeedle.count > 4 else { return false }
        let characters = Array(normalizedNeedle)
        let bigrams = Set((0..<(characters.count - 1)).map { index in
            String(characters[index...index + 1])
        })
        guard !bigrams.isEmpty else { return false }
        let matchedBigrams = bigrams.filter { normalizedHaystack.contains($0) }.count
        let requiredRatio = normalizedNeedle.count <= 8 ? 0.60 : 0.45
        return matchedBigrams >= 2
            && Double(matchedBigrams) / Double(bigrams.count) >= requiredRatio
    }

    private static func semanticSearchText(_ text: String) -> String {
        let semanticSymbols: Set<Character> = ["=", "²", "π", "√", "∝", "Δ", "<", ">", "/", "≤", "≥", "±"]
        return text
            .lowercased()
            .filter { character in
                character.isLetter || character.isNumber || semanticSymbols.contains(character)
            }
            .map(String.init)
            .joined()
    }

    private static func declaresInteractionProcess(_ text: String) -> Bool {
        let interactionTerms = [
            "拖动", "滑动", "调节", "调整", "切换", "选择", "点击", "探查", "探针",
            "观察", "联动", "播放", "暂停", "步进", "筛选", "缩放", "旋转", "重置", "对照", "比较",
        ]
        return interactionTerms.contains(where: text.contains)
    }

    private static func generatedUIHasBoundSemanticInteraction(
        _ ui: RichAnswerUIComposition
    ) -> Bool {
        let controlRoles: Set<RichAnswerUIRole> = [.slider, .toggle, .scrubber, .probe]
        let datasetsByID = Dictionary(uniqueKeysWithValues: ui.datasets.map { ($0.id, $0) })
        return ui.bindings.contains { binding in
            let hasControl = ui.nodes.contains {
                $0.bindingID == binding.id && controlRoles.contains($0.role)
            }
            return hasControl && bindingHasChangingOutcome(
                binding,
                reachableNodes: ui.nodes,
                datasetsByID: datasetsByID
            )
        }
    }

    private static let genericRelationBigrams: Set<String> = [
        "通过", "变化", "观察", "对应", "关系", "增加", "减少", "上升", "下降", "影响", "结果", "条件", "数据",
    ]

    private static func semanticAnchorTokens(_ text: String) -> [String] {
        let pattern = #"[A-Za-z]+|[0-9]+(?:\.[0-9]+)?|[πΔ√][A-Za-z0-9]+"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return Array(Set(expression.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { text[$0].lowercased() }
        }))
    }

    private static func hanBigrams(_ text: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: #"[一-鿿]+"#) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let bigrams = expression.matches(in: text, range: range).flatMap { match -> [String] in
            guard let matchRange = Range(match.range, in: text) else { return [] }
            let characters = Array(text[matchRange])
            guard characters.count >= 2 else { return [] }
            return (0..<(characters.count - 1)).map { index in
                String(characters[index...index + 1])
            }
        }.filter { !genericRelationBigrams.contains($0) }
        return Array(Set(bigrams))
    }

    private static func relationHasVisibleAnchors(
        _ relation: String,
        visibleText: String
    ) -> Bool {
        if semanticText(visibleText, contains: relation) { return true }
        let tokenMatches = semanticAnchorTokens(relation).filter {
            semanticText(visibleText, contains: $0)
        }.count
        let bigramMatches = hanBigrams(relation).filter { visibleText.contains($0) }.count
        return tokenMatches >= 2
            || bigramMatches >= 2
            || (tokenMatches >= 1 && bigramMatches >= 1)
    }

    private static func generatedUIHasSemanticRelationStructure(
        _ ui: RichAnswerUIComposition,
        relations: [String],
        visibleText: String
    ) -> Bool {
        guard relations.contains(where: {
            relationHasVisibleAnchors($0, visibleText: visibleText)
        }) else {
            return false
        }
        let relationRoles: Set<RichAnswerUIRole> = [
            .line, .path, .point, .area, .bar, .dotMatrix, .vector, .sequence, .metric,
        ]
        let datasetsByID = Dictionary(uniqueKeysWithValues: ui.datasets.map { ($0.id, $0) })
        let hasNamedAxis = ui.nodes.contains { node in
            node.xAxis?.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                || node.yAxis?.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
        let hasNamedBinding = ui.bindings.contains {
            !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return ui.nodes.contains { node in
            guard relationRoles.contains(node.role),
                  let datasetID = node.datasetID,
                  let dataset = datasetsByID[datasetID],
                  datasetRowsHaveChangingOutcome(
                      dataset.rows,
                      acceptsSemanticOnly: node.role == .sequence
                  ) else {
                return false
            }
            let hasVisibleLabel = node.label?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                || dataset.rows.contains {
                    $0.label?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                }
            return hasVisibleLabel || hasNamedAxis || hasNamedBinding
        }
    }

    private static func boundedVisibleSemanticSummary(
        in ui: RichAnswerUIComposition,
        sceneTitle: String
    ) -> String {
        let roles = Set(ui.nodes.map { $0.role.rawValue }).sorted().joined(separator: ",")
        let visible = visibleSemanticText(in: ui, sceneTitle: sceneTitle)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        let summary = "roles=\(roles.isEmpty ? "none" : roles); text=\(visible.isEmpty ? "none" : visible)"
        guard summary.count > 360 else { return summary }
        return String(summary.prefix(357)) + "..."
    }

    private static func declarationSamples(_ values: [String]) -> String {
        values.prefix(2).joined(separator: "、")
    }

    private static func generatedProgramComponents(in source: String?) -> Set<String> {
        guard let source else { return [] }
        return Set(source.split(whereSeparator: { $0.isNewline }).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.hasPrefix("$"),
                  let equals = line.firstIndex(of: "="),
                  let openParenthesis = line[equals...].firstIndex(of: "(") else {
                return nil
            }
            return line[line.index(after: equals)..<openParenthesis]
                .trimmingCharacters(in: .whitespacesAndNewlines)
        })
    }

    private static func validateSupportedOperations(_ scene: RichAnswerScene) -> RichAnswerDiagnostic? {
        let supportedKinds = supportedOperationKinds(for: scene.family)
        if let unsupportedOperation = scene.operations.first(where: { !supportedKinds.contains($0.kind) }) {
            return RichAnswerDiagnostic(
                code: .unsupportedField,
                sceneID: scene.id,
                message: "operation \(unsupportedOperation.kind.rawValue) is not supported by the \(scene.family.rawValue) renderer"
            )
        }
        return nil
    }

    private static func supportedOperationKinds(
        for family: RichAnswerCapabilityFamily
    ) -> Set<RichAnswerOperationKind> {
        switch family {
        case .textAndAlignment:
            return [.select, .reveal, .reset]
        case .quantityAndCoordinates:
            return [.adjust, .probe, .select, .reset]
        case .processAndState:
            return [.select, .step, .playPause, .reset]
        case .relationAndEvidence:
            return [.select, .reveal, .reset]
        case .timeAndSpace:
            return [.scrub, .toggle, .reset]
        case .imageAndOverlay:
            return [.select, .toggle, .zoom]
        case .comparisonAndEvaluation:
            return [.compare, .select, .reset]
        case .calculationAndConstraints:
            return [.adjust, .reset]
        }
    }

    private static func validateTextAlignmentContract(_ scene: RichAnswerScene) -> RichAnswerDiagnostic? {
        let selectableTextIDs = Set(
            scene.objects.lazy
                .filter { $0.kind == .text && hasMeaningfulText($0.text) }
                .map(\.id)
        )
        guard !selectableTextIDs.isEmpty,
              scene.operations.contains(where: {
                  $0.kind == .select && $0.targetIDs.contains(where: selectableTextIDs.contains)
              }) else {
            return invalidValue(
                sceneID: scene.id,
                "text alignment scenes require a selectable text object"
            )
        }
        return nil
    }

    private static func validateQuantityCoordinateContract(_ scene: RichAnswerScene) -> RichAnswerDiagnostic? {
        let coordinateFrameIDs = Set(
            scene.frames.lazy
                .filter { $0.kind == .cartesian }
                .map(\.id)
        )
        guard !coordinateFrameIDs.isEmpty else {
            return invalidValue(sceneID: scene.id, "quantity scenes require a cartesian coordinate frame")
        }

        let plottedObjects = scene.objects.filter { object in
            (object.kind == .quantity || object.kind == .dataPoint)
                && object.coordinate?.isNormalized == true
                && object.frameID.map(coordinateFrameIDs.contains) == true
        }
        guard plottedObjects.count >= 2 else {
            return invalidValue(
                sceneID: scene.id,
                "quantity scenes require at least two coordinate points attached to a coordinate frame"
            )
        }
        return nil
    }

    private static func validateProcessStateContract(_ scene: RichAnswerScene) -> RichAnswerDiagnostic? {
        let processObjectIDs = Set(
            scene.objects.lazy
                .filter { $0.kind == .step || $0.kind == .state }
                .map(\.id)
        )
        guard processObjectIDs.count >= 2 else {
            return invalidValue(sceneID: scene.id, "process scenes require at least two step or state objects")
        }
        guard operationExists(in: scene, kind: .step, targetingAtLeast: 2, within: processObjectIDs),
              operationExists(in: scene, kind: .playPause, targetingAtLeast: 2, within: processObjectIDs) else {
            return invalidValue(sceneID: scene.id, "process scenes require step and play controls targeting process objects")
        }
        return nil
    }

    private static func validateRelationEvidenceContract(_ scene: RichAnswerScene) -> RichAnswerDiagnostic? {
        guard !scene.relations.isEmpty else {
            return invalidValue(sceneID: scene.id, "relation scenes require at least one relationship")
        }
        return nil
    }

    private static func validateTimeSpaceContract(_ scene: RichAnswerScene) -> RichAnswerDiagnostic? {
        let navigableFrameIDs = Set(
            scene.frames.lazy
                .filter { $0.kind == .timeline || $0.kind == .space }
                .map(\.id)
        )
        guard !navigableFrameIDs.isEmpty else {
            return invalidValue(sceneID: scene.id, "time-space scenes require a timeline or space frame")
        }

        let navigableObjectIDs = Set(
            scene.objects.lazy
                .filter {
                    $0.coordinate?.isNormalized == true
                        && $0.frameID.map(navigableFrameIDs.contains) == true
                }
                .map(\.id)
        )
        guard navigableObjectIDs.count >= 2 else {
            return invalidValue(
                sceneID: scene.id,
                "time-space scenes require at least two positioned objects on a timeline or space frame"
            )
        }
        guard operationExists(in: scene, kind: .scrub, targetingAtLeast: 1, within: navigableObjectIDs.union(navigableFrameIDs)) else {
            return invalidValue(sceneID: scene.id, "time-space scenes require a scrub operation")
        }
        return nil
    }

    private static func validateImageOverlayContract(_ scene: RichAnswerScene) -> RichAnswerDiagnostic? {
        let imageFrames = scene.frames.filter { $0.kind == .image && $0.assetID != nil }
        let imageFrameIDs = Set(imageFrames.map(\.id))
        guard !imageFrameIDs.isEmpty else {
            return invalidValue(sceneID: scene.id, "image overlay scenes require an image frame with an asset")
        }

        let frameAssetIDs = Set(imageFrames.compactMap(\.assetID))
        let imageObjects = scene.objects.filter {
            $0.kind == .image
                && $0.assetID.map(frameAssetIDs.contains) == true
                && $0.frameID.map(imageFrameIDs.contains) == true
        }
        let regionObjects = scene.objects.filter {
            $0.kind == .region
                && $0.bounds != nil
                && $0.frameID.map(imageFrameIDs.contains) == true
        }
        guard !imageObjects.isEmpty, !regionObjects.isEmpty else {
            return invalidValue(
                sceneID: scene.id,
                "image overlay scenes require an image object and a bounded region in the image frame"
            )
        }
        return nil
    }

    private static func validateComparisonEvaluationContract(_ scene: RichAnswerScene) -> RichAnswerDiagnostic? {
        let objectIDs = Set(scene.objects.map(\.id))
        guard scene.operations.contains(where: { operation in
            operation.kind == .compare
                && Set(operation.targetIDs).intersection(objectIDs).count >= 2
        }) else {
            return invalidValue(sceneID: scene.id, "comparison scenes require a compare operation with at least two object targets")
        }
        return nil
    }

    private static func validateCalculationConstraintContract(_ scene: RichAnswerScene) -> RichAnswerDiagnostic? {
        guard scene.objects.contains(where: { $0.kind == .formula && hasMeaningfulText($0.text) }),
              scene.objects.contains(where: { $0.kind == .constraint && hasMeaningfulText($0.text) }) else {
            return invalidValue(sceneID: scene.id, "calculation scenes require a formula and a constraint")
        }

        let frameIDs = Set(scene.frames.map(\.id))
        guard scene.operations.contains(where: { operation in
            guard operation.kind == .adjust, operation.parameter != nil else { return false }
            let samples = numericCoordinateSamples(for: operation, in: scene, frameIDs: frameIDs)
            return samples.count >= 2 && Set(samples.compactMap { $0.coordinate?.x }).count >= 2
        }) else {
            return invalidValue(
                sceneID: scene.id,
                "calculation scenes require an adjust operation targeting at least two numeric coordinate samples"
            )
        }
        return nil
    }

    private static func operationExists(
        in scene: RichAnswerScene,
        kind: RichAnswerOperationKind,
        targetingAtLeast minimumTargetCount: Int,
        within allowedTargetIDs: Set<String>
    ) -> Bool {
        scene.operations.contains { operation in
            operation.kind == kind
                && Set(operation.targetIDs).intersection(allowedTargetIDs).count >= minimumTargetCount
        }
    }

    private static func numericCoordinateSamples(
        for operation: RichAnswerOperation,
        in scene: RichAnswerScene,
        frameIDs: Set<String>
    ) -> [RichAnswerObject] {
        let targetIDs = Set(operation.targetIDs)
        return scene.objects.filter { object in
            targetIDs.contains(object.id)
                && object.number != nil
                && object.coordinate?.isNormalized == true
                && object.frameID.map(frameIDs.contains) == true
        }
    }

    private static func hasMeaningfulText(_ text: String?) -> Bool {
        text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
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

    var isNormalized: Bool {
        isFinite && x >= 0 && x <= 1 && y >= 0 && y <= 1
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
        var identifiers = evidenceIDs
        identifiers.append(contentsOf: objects.flatMap(\.evidenceIDs))
        identifiers.append(contentsOf: relations.flatMap(\.evidenceIDs))
        identifiers.append(contentsOf: frames.flatMap(\.evidenceIDs))
        identifiers.append(contentsOf: ui?.allEvidenceIDs ?? [])
        identifiers.append(contentsOf: renderPlan?.sourceBindings.map(\.evidenceID) ?? [])
        return identifiers
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
