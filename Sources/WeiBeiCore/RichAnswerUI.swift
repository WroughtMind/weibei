import Foundation

public enum RichAnswerUIRole: String, Codable, CaseIterable, Hashable, Sendable {
    case vstack
    case hstack
    case zstack
    case grid
    case panel
    case canvas
    case text
    case metric
    case sequence
    case axis
    case line
    case path
    case point
    case area
    case shape
    case bar
    case dotMatrix
    case vector
    case region
    case image
    case label
    case divider
    case slider
    case toggle
    case scrubber
    case select
    case reset
    case probe
    case evidence
}

public enum RichAnswerUIShape: String, Codable, CaseIterable, Hashable, Sendable {
    case rectangle
    case roundedRectangle
    case circle
    case ellipse
    case triangle
    case diamond
    case capsule
}

public enum RichAnswerUIFill: String, Codable, CaseIterable, Hashable, Sendable {
    case outline
    case soft
    case solid
}

public enum RichAnswerUITone: String, Codable, CaseIterable, Hashable, Sendable {
    case ink
    case muted
    case accent
    case warning
    case positive
    case gridline
}

public enum RichAnswerUIEmphasis: String, Codable, CaseIterable, Hashable, Sendable {
    case quiet
    case regular
    case strong
}

public enum RichAnswerUISpacing: String, Codable, CaseIterable, Hashable, Sendable {
    case tight
    case regular
    case loose
}

public enum RichAnswerUIAlignment: String, Codable, CaseIterable, Hashable, Sendable {
    case leading
    case center
    case trailing
}

public enum RichAnswerUISize: String, Codable, CaseIterable, Hashable, Sendable {
    case compact
    case regular
    case large
}

public enum RichAnswerUIProgramGraphics: String, Codable, CaseIterable, Hashable, Sendable {
    case dom
    case canvas
}

public struct RichAnswerUIProgram: Codable, Hashable, Sendable {
    public var version: String
    public var source: String
    public var capabilities: [String]
    public var directManipulation: Bool
    public var maxHeight: Int
    public var graphics: RichAnswerUIProgramGraphics

    public init(
        version: String = "weibei.openui.v1",
        source: String,
        capabilities: [String],
        directManipulation: Bool,
        maxHeight: Int = 680,
        graphics: RichAnswerUIProgramGraphics
    ) {
        self.version = version
        self.source = source
        self.capabilities = capabilities
        self.directManipulation = directManipulation
        self.maxHeight = maxHeight
        self.graphics = graphics
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case version
        case source
        case capabilities
        case directManipulation
        case maxHeight
        case graphics
    }

    public init(from decoder: Decoder) throws {
        try RichAnswerUIStrictDecoding.rejectUnknownFields(in: decoder, allowed: CodingKeys.allowedFieldNames)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(String.self, forKey: .version)
        source = try container.decode(String.self, forKey: .source)
        capabilities = try container.decode([String].self, forKey: .capabilities)
        directManipulation = try container.decode(Bool.self, forKey: .directManipulation)
        maxHeight = try container.decodeIfPresent(Int.self, forKey: .maxHeight) ?? 680
        graphics = try container.decode(RichAnswerUIProgramGraphics.self, forKey: .graphics)
    }
}

public struct RichAnswerUIComposition: Codable, Hashable, Sendable {
    public var rootID: String
    public var nodes: [RichAnswerUINode]
    public var datasets: [RichAnswerUIDataset]
    public var bindings: [RichAnswerUIBinding]

    public init(
        rootID: String,
        nodes: [RichAnswerUINode],
        datasets: [RichAnswerUIDataset] = [],
        bindings: [RichAnswerUIBinding] = []
    ) {
        self.rootID = rootID
        self.nodes = nodes
        self.datasets = datasets
        self.bindings = bindings
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case rootID
        case nodes
        case datasets
        case bindings
    }

    public init(from decoder: Decoder) throws {
        try RichAnswerUIStrictDecoding.rejectUnknownFields(in: decoder, allowed: CodingKeys.allowedFieldNames)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rootID = try container.decode(String.self, forKey: .rootID)
        nodes = try container.decode([RichAnswerUINode].self, forKey: .nodes)
        datasets = try container.decodeIfPresent([RichAnswerUIDataset].self, forKey: .datasets) ?? []
        bindings = try container.decodeIfPresent([RichAnswerUIBinding].self, forKey: .bindings) ?? []
    }
}

public struct RichAnswerUINode: Codable, Hashable, Sendable {
    public var id: String
    public var role: RichAnswerUIRole
    public var children: [String]
    public var label: String?
    public var text: String?
    public var unit: String?
    public var datasetID: String?
    public var bindingID: String?
    public var assetID: String?
    public var evidenceIDs: [String]
    public var xAxis: RichAnswerAxis?
    public var yAxis: RichAnswerAxis?
    public var region: RichAnswerRegion?
    public var shape: RichAnswerUIShape?
    public var fill: RichAnswerUIFill?
    public var columns: Int?
    public var tone: RichAnswerUITone
    public var emphasis: RichAnswerUIEmphasis
    public var spacing: RichAnswerUISpacing
    public var alignment: RichAnswerUIAlignment
    public var size: RichAnswerUISize

    public init(
        id: String,
        role: RichAnswerUIRole,
        children: [String] = [],
        label: String? = nil,
        text: String? = nil,
        unit: String? = nil,
        datasetID: String? = nil,
        bindingID: String? = nil,
        assetID: String? = nil,
        evidenceIDs: [String] = [],
        xAxis: RichAnswerAxis? = nil,
        yAxis: RichAnswerAxis? = nil,
        region: RichAnswerRegion? = nil,
        shape: RichAnswerUIShape? = nil,
        fill: RichAnswerUIFill? = nil,
        columns: Int? = nil,
        tone: RichAnswerUITone = .ink,
        emphasis: RichAnswerUIEmphasis = .regular,
        spacing: RichAnswerUISpacing = .regular,
        alignment: RichAnswerUIAlignment = .leading,
        size: RichAnswerUISize = .regular
    ) {
        self.id = id
        self.role = role
        self.children = children
        self.label = label
        self.text = text
        self.unit = unit
        self.datasetID = datasetID
        self.bindingID = bindingID
        self.assetID = assetID
        self.evidenceIDs = evidenceIDs
        self.xAxis = xAxis
        self.yAxis = yAxis
        self.region = region
        self.shape = shape
        self.fill = fill
        self.columns = columns
        self.tone = tone
        self.emphasis = emphasis
        self.spacing = spacing
        self.alignment = alignment
        self.size = size
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case role
        case children
        case label
        case text
        case unit
        case datasetID
        case bindingID
        case assetID
        case evidenceIDs
        case xAxis
        case yAxis
        case region
        case shape
        case fill
        case columns
        case tone
        case emphasis
        case spacing
        case alignment
        case size
    }

    public init(from decoder: Decoder) throws {
        try RichAnswerUIStrictDecoding.rejectUnknownFields(in: decoder, allowed: CodingKeys.allowedFieldNames)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        role = try container.decode(RichAnswerUIRole.self, forKey: .role)
        children = try container.decodeIfPresent([String].self, forKey: .children) ?? []
        label = try container.decodeIfPresent(String.self, forKey: .label)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        unit = try container.decodeIfPresent(String.self, forKey: .unit)
        datasetID = try container.decodeIfPresent(String.self, forKey: .datasetID)
        bindingID = try container.decodeIfPresent(String.self, forKey: .bindingID)
        assetID = try container.decodeIfPresent(String.self, forKey: .assetID)
        evidenceIDs = try container.decodeIfPresent([String].self, forKey: .evidenceIDs) ?? []
        xAxis = try container.decodeIfPresent(RichAnswerAxis.self, forKey: .xAxis)
        yAxis = try container.decodeIfPresent(RichAnswerAxis.self, forKey: .yAxis)
        region = try container.decodeIfPresent(RichAnswerRegion.self, forKey: .region)
        shape = try container.decodeIfPresent(RichAnswerUIShape.self, forKey: .shape)
        fill = try container.decodeIfPresent(RichAnswerUIFill.self, forKey: .fill)
        columns = try container.decodeIfPresent(Int.self, forKey: .columns)
        tone = try container.decodeIfPresent(RichAnswerUITone.self, forKey: .tone) ?? .ink
        emphasis = try container.decodeIfPresent(RichAnswerUIEmphasis.self, forKey: .emphasis) ?? .regular
        spacing = try container.decodeIfPresent(RichAnswerUISpacing.self, forKey: .spacing) ?? .regular
        alignment = try container.decodeIfPresent(RichAnswerUIAlignment.self, forKey: .alignment) ?? .leading
        size = try container.decodeIfPresent(RichAnswerUISize.self, forKey: .size) ?? .regular
    }
}

public struct RichAnswerUIDataset: Codable, Hashable, Sendable {
    public var id: String
    public var rows: [RichAnswerUIDataRow]

    public init(id: String, rows: [RichAnswerUIDataRow]) {
        self.id = id
        self.rows = rows
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case rows
    }

    public init(from decoder: Decoder) throws {
        try RichAnswerUIStrictDecoding.rejectUnknownFields(in: decoder, allowed: CodingKeys.allowedFieldNames)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        rows = try container.decode([RichAnswerUIDataRow].self, forKey: .rows)
    }
}

public struct RichAnswerUIDataRow: Codable, Hashable, Sendable {
    public var id: String
    public var x: Double
    public var y: Double
    public var x2: Double?
    public var y2: Double?
    public var value: Double?
    public var result: Double?
    public var label: String?
    public var evidenceIDs: [String]

    public init(
        id: String,
        x: Double,
        y: Double,
        x2: Double? = nil,
        y2: Double? = nil,
        value: Double? = nil,
        result: Double? = nil,
        label: String? = nil,
        evidenceIDs: [String] = []
    ) {
        self.id = id
        self.x = x
        self.y = y
        self.x2 = x2
        self.y2 = y2
        self.value = value
        self.result = result
        self.label = label
        self.evidenceIDs = evidenceIDs
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case x
        case y
        case x2
        case y2
        case value
        case result
        case label
        case evidenceIDs
    }

    public init(from decoder: Decoder) throws {
        try RichAnswerUIStrictDecoding.rejectUnknownFields(in: decoder, allowed: CodingKeys.allowedFieldNames)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        x2 = try container.decodeIfPresent(Double.self, forKey: .x2)
        y2 = try container.decodeIfPresent(Double.self, forKey: .y2)
        value = try container.decodeIfPresent(Double.self, forKey: .value)
        result = try container.decodeIfPresent(Double.self, forKey: .result)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        evidenceIDs = try container.decodeIfPresent([String].self, forKey: .evidenceIDs) ?? []
    }
}

public struct RichAnswerUIBinding: Codable, Hashable, Sendable {
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
        try RichAnswerUIStrictDecoding.rejectUnknownFields(in: decoder, allowed: CodingKeys.allowedFieldNames)
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

extension RichAnswerUIComposition {
    var allEvidenceIDs: [String] {
        nodes.flatMap(\.evidenceIDs) + datasets.flatMap { $0.rows.flatMap(\.evidenceIDs) }
    }

    var allAssetIDs: [String] {
        nodes.compactMap(\.assetID)
    }
}

private struct RichAnswerUIDynamicCodingKey: CodingKey {
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

private enum RichAnswerUIStrictDecoding {
    static func rejectUnknownFields(in decoder: Decoder, allowed: Set<String>) throws {
        let container = try decoder.container(keyedBy: RichAnswerUIDynamicCodingKey.self)
        if let key = container.allKeys.first(where: { !allowed.contains($0.stringValue) }) {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Unsupported rich-answer field 'ui.\(key.stringValue)'"
            )
        }
    }
}

private extension CaseIterable where Self: CodingKey {
    static var allowedFieldNames: Set<String> {
        Set(allCases.map(\.stringValue))
    }
}
