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
        try RichAnswerStrictDecoding.rejectUnknownFields(in: decoder, allowed: CodingKeys.richAnswerAllowedFieldNames)
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
    /// The only supported Rich Answer envelope wire version.
    public static let supportedSchemaVersion = 2

    public var schemaVersion: Int
    public var contextRevision: String
    public var narrative: String
    public var expressionPlan: RichAnswerExpressionPlan
    public var scenes: [RichAnswerScene]
    public var evidenceLedger: [RichAnswerEvidence]
    public var fallback: RichAnswerFallback

    public init(
        schemaVersion: Int = RichAnswerEnvelope.supportedSchemaVersion,
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
        try RichAnswerStrictDecoding.rejectUnknownFields(in: decoder, allowed: CodingKeys.richAnswerAllowedFieldNames)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.supportedSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "unsupported rich-answer envelope schema version \(schemaVersion); expected \(Self.supportedSchemaVersion)"
            )
        }
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
        try RichAnswerStrictDecoding.rejectUnknownFields(in: decoder, allowed: CodingKeys.richAnswerAllowedFieldNames)
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
        try RichAnswerStrictDecoding.rejectUnknownFields(in: decoder, allowed: CodingKeys.richAnswerAllowedFieldNames)
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
        try RichAnswerStrictDecoding.rejectUnknownFields(in: decoder, allowed: CodingKeys.richAnswerAllowedFieldNames)
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
        try RichAnswerStrictDecoding.rejectUnknownFields(in: decoder, allowed: CodingKeys.richAnswerAllowedFieldNames)
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
        try RichAnswerStrictDecoding.rejectUnknownFields(in: decoder, allowed: CodingKeys.richAnswerAllowedFieldNames)
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
        try RichAnswerStrictDecoding.rejectUnknownFields(in: decoder, allowed: CodingKeys.richAnswerAllowedFieldNames)
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
        try RichAnswerStrictDecoding.rejectUnknownFields(in: decoder, allowed: CodingKeys.richAnswerAllowedFieldNames)
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
        try RichAnswerStrictDecoding.rejectUnknownFields(in: decoder, allowed: CodingKeys.richAnswerAllowedFieldNames)
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
        try RichAnswerStrictDecoding.rejectUnknownFields(in: decoder, allowed: CodingKeys.richAnswerAllowedFieldNames)
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
        try RichAnswerStrictDecoding.rejectUnknownFields(in: decoder, allowed: CodingKeys.richAnswerAllowedFieldNames)
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
        try RichAnswerStrictDecoding.rejectUnknownFields(in: decoder, allowed: CodingKeys.richAnswerAllowedFieldNames)
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
        try RichAnswerStrictDecoding.rejectUnknownFields(in: decoder, allowed: CodingKeys.richAnswerAllowedFieldNames)
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
