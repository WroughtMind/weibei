import CryptoKit
import Foundation

public enum RichAnswerPythonArtifactOperation: String, Codable, CaseIterable, Hashable, Sendable {
    case computeStatistics = "compute_statistics"
    case aggregateTable = "aggregate_table"
    case sampleFunction = "sample_function"
    case binDistribution = "bin_distribution"
    case fitRegression = "fit_regression"
    case solveLinearSystem = "solve_linear_system"
    case transformCoordinates = "transform_coordinates"
    case compileRendererSpec = "compile_renderer_spec"
    case imageMeasurementOverlay = "image_measurement_overlay"
}

public enum RichAnswerPythonArtifactKind: String, Codable, CaseIterable, Hashable, Sendable {
    case table
    case numericSeries = "numeric_series"
    case jsonSpec = "json_spec"
    case staticPNG = "static_png"
    case staticSVG = "static_svg"
    case staticHTML = "static_html"
    case imageOverlaySpec = "image_overlay_spec"
    case interactiveAdapterSpec = "interactive_adapter_spec"
}

public enum RichAnswerPythonInteractiveAdapterKind: String, Codable, CaseIterable, Hashable, Sendable {
    case bokehDocument = "bokeh_document"
    case panelDocument = "panel_document"
    case pyodideWorker = "pyodide_worker"
    case weibeiControlsBridge = "weibei_controls_bridge"
}

public enum RichAnswerPythonArtifactSourceRole: String, Codable, CaseIterable, Hashable, Sendable {
    case data
    case formula
    case parameter
    case claim
    case imageAsset = "image_asset"
    case fallback
}

public enum RichAnswerPythonArtifactLifecycleScope: String, Codable, CaseIterable, Hashable, Sendable {
    case transient
    case session
    case exportable
}

public enum RichAnswerPythonArtifactScalar: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
}

public struct RichAnswerPythonArtifactTableColumn: Codable, Hashable, Sendable {
    public var id: String
    public var label: String
    public var unit: String?

    public init(id: String, label: String, unit: String? = nil) {
        self.id = id
        self.label = label
        self.unit = unit
    }
}

public struct RichAnswerPythonArtifactTable: Codable, Hashable, Sendable {
    public var columns: [RichAnswerPythonArtifactTableColumn]
    public var rows: [[RichAnswerPythonArtifactScalar]]

    public init(columns: [RichAnswerPythonArtifactTableColumn], rows: [[RichAnswerPythonArtifactScalar]]) {
        self.columns = columns
        self.rows = rows
    }
}

public struct RichAnswerPythonArtifactImageRef: Codable, Hashable, Sendable {
    public var assetID: String
    public var width: Int?
    public var height: Int?
    public var checksum: String?

    public init(assetID: String, width: Int? = nil, height: Int? = nil, checksum: String? = nil) {
        self.assetID = assetID
        self.width = width
        self.height = height
        self.checksum = checksum
    }
}

public enum RichAnswerPythonArtifactInputPayload: Codable, Hashable, Sendable {
    case scalar(RichAnswerPythonArtifactScalar)
    case numberSeries([Double])
    case table(RichAnswerPythonArtifactTable)
    case expression(RichAnswerMathExpression)
    case imageRef(RichAnswerPythonArtifactImageRef)
    case artifactRef(RichAnswerRenderArtifactRef)
}

public struct RichAnswerPythonArtifactInput: Codable, Hashable, Sendable {
    public var id: String
    public var role: String
    public var payload: RichAnswerPythonArtifactInputPayload
    public var sourceBindingID: String?

    public init(
        id: String,
        role: String,
        payload: RichAnswerPythonArtifactInputPayload,
        sourceBindingID: String? = nil
    ) {
        self.id = id
        self.role = role
        self.payload = payload
        self.sourceBindingID = sourceBindingID
    }
}

public struct RichAnswerPythonArtifactOutputRequest: Codable, Hashable, Sendable {
    public var id: String
    public var kind: RichAnswerPythonArtifactKind
    public var mimeType: String
    public var role: String

    public init(id: String, kind: RichAnswerPythonArtifactKind, mimeType: String, role: String) {
        self.id = id
        self.kind = kind
        self.mimeType = mimeType
        self.role = role
    }
}

public struct RichAnswerPythonArtifactSourceBinding: Codable, Hashable, Sendable {
    public var id: String
    public var evidenceID: String
    public var target: String
    public var role: RichAnswerPythonArtifactSourceRole
    public var requiredForFallback: Bool

    public init(
        id: String,
        evidenceID: String,
        target: String,
        role: RichAnswerPythonArtifactSourceRole,
        requiredForFallback: Bool = true
    ) {
        self.id = id
        self.evidenceID = evidenceID
        self.target = target
        self.role = role
        self.requiredForFallback = requiredForFallback
    }
}

public struct RichAnswerPythonInteractiveAdapterDeclaration: Codable, Hashable, Sendable {
    public var id: String
    public var kind: RichAnswerPythonInteractiveAdapterKind
    public var requiredArtifactIDs: [String]
    public var stateSchema: [String: RichAnswerPythonArtifactScalar]
    public var interactionKinds: Set<RichAnswerRenderInteractionKind>
    public var lifecycle: RichAnswerRendererLifecycle
    public var allowNetwork: Bool
    public var allowFilesystem: Bool

    public init(
        id: String,
        kind: RichAnswerPythonInteractiveAdapterKind,
        requiredArtifactIDs: [String],
        stateSchema: [String: RichAnswerPythonArtifactScalar] = [:],
        interactionKinds: Set<RichAnswerRenderInteractionKind> = [],
        lifecycle: RichAnswerRendererLifecycle = RichAnswerRendererLifecycle(
            createsRuntime: true,
            supportsStreamingPatch: false,
            supportsDynamicHeight: true,
            needsExplicitTeardown: true
        ),
        allowNetwork: Bool = false,
        allowFilesystem: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.requiredArtifactIDs = requiredArtifactIDs
        self.stateSchema = stateSchema
        self.interactionKinds = interactionKinds
        self.lifecycle = lifecycle
        self.allowNetwork = allowNetwork
        self.allowFilesystem = allowFilesystem
    }
}

public struct RichAnswerPythonArtifactLimits: Codable, Hashable, Sendable {
    public var maxInputBytes: Int
    public var maxOutputBytes: Int
    public var maxRows: Int
    public var maxColumns: Int
    public var maxArtifacts: Int
    public var maxRuntimeMS: Int
    public var allowNetwork: Bool
    public var allowFilesystem: Bool

    public init(
        maxInputBytes: Int = 256_000,
        maxOutputBytes: Int = 512_000,
        maxRows: Int = 2_000,
        maxColumns: Int = 80,
        maxArtifacts: Int = 4,
        maxRuntimeMS: Int = 3_000,
        allowNetwork: Bool = false,
        allowFilesystem: Bool = false
    ) {
        self.maxInputBytes = maxInputBytes
        self.maxOutputBytes = maxOutputBytes
        self.maxRows = maxRows
        self.maxColumns = maxColumns
        self.maxArtifacts = maxArtifacts
        self.maxRuntimeMS = maxRuntimeMS
        self.allowNetwork = allowNetwork
        self.allowFilesystem = allowFilesystem
    }

    public static let `default` = RichAnswerPythonArtifactLimits()

    public func constrained(by policy: RichAnswerPythonArtifactLimits) -> RichAnswerPythonArtifactLimits {
        RichAnswerPythonArtifactLimits(
            maxInputBytes: min(maxInputBytes, policy.maxInputBytes),
            maxOutputBytes: min(maxOutputBytes, policy.maxOutputBytes),
            maxRows: min(maxRows, policy.maxRows),
            maxColumns: min(maxColumns, policy.maxColumns),
            maxArtifacts: min(maxArtifacts, policy.maxArtifacts),
            maxRuntimeMS: min(maxRuntimeMS, policy.maxRuntimeMS),
            allowNetwork: allowNetwork && policy.allowNetwork,
            allowFilesystem: allowFilesystem && policy.allowFilesystem
        )
    }
}

public struct RichAnswerPythonArtifactPolicy: Codable, Hashable, Sendable {
    public var allowedOperations: Set<RichAnswerPythonArtifactOperation>
    public var allowedOutputKinds: Set<RichAnswerPythonArtifactKind>
    public var allowedInteractiveAdapters: Set<RichAnswerPythonInteractiveAdapterKind>
    public var limits: RichAnswerPythonArtifactLimits
    public var requireSourceBindings: Bool
    public var allowInteractiveAdapters: Bool

    public init(
        allowedOperations: Set<RichAnswerPythonArtifactOperation> = Set(RichAnswerPythonArtifactOperation.allCases),
        allowedOutputKinds: Set<RichAnswerPythonArtifactKind> = Set(RichAnswerPythonArtifactKind.allCases),
        allowedInteractiveAdapters: Set<RichAnswerPythonInteractiveAdapterKind> = Set(RichAnswerPythonInteractiveAdapterKind.allCases),
        limits: RichAnswerPythonArtifactLimits = .default,
        requireSourceBindings: Bool = true,
        allowInteractiveAdapters: Bool = false
    ) {
        self.allowedOperations = allowedOperations
        self.allowedOutputKinds = allowedOutputKinds
        self.allowedInteractiveAdapters = allowedInteractiveAdapters
        self.limits = limits
        self.requireSourceBindings = requireSourceBindings
        self.allowInteractiveAdapters = allowInteractiveAdapters
    }

    public static let `default` = RichAnswerPythonArtifactPolicy()
}

public struct RichAnswerPythonArtifactRequest: Codable, Hashable, Sendable {
    public var id: String
    public var operation: RichAnswerPythonArtifactOperation
    public var inputs: [RichAnswerPythonArtifactInput]
    public var parameters: [String: RichAnswerPythonArtifactScalar]
    public var requestedOutputs: [RichAnswerPythonArtifactOutputRequest]
    public var limits: RichAnswerPythonArtifactLimits
    public var sourceBindings: [RichAnswerPythonArtifactSourceBinding]
    public var interactiveAdapter: RichAnswerPythonInteractiveAdapterDeclaration?

    public init(
        id: String,
        operation: RichAnswerPythonArtifactOperation,
        inputs: [RichAnswerPythonArtifactInput],
        parameters: [String: RichAnswerPythonArtifactScalar] = [:],
        requestedOutputs: [RichAnswerPythonArtifactOutputRequest],
        limits: RichAnswerPythonArtifactLimits = .default,
        sourceBindings: [RichAnswerPythonArtifactSourceBinding],
        interactiveAdapter: RichAnswerPythonInteractiveAdapterDeclaration? = nil
    ) {
        self.id = id
        self.operation = operation
        self.inputs = inputs
        self.parameters = parameters
        self.requestedOutputs = requestedOutputs
        self.limits = limits
        self.sourceBindings = sourceBindings
        self.interactiveAdapter = interactiveAdapter
    }

    public init(from decoder: Decoder) throws {
        let allKeys = try decoder.container(keyedBy: RichAnswerPythonArtifactAnyCodingKey.self).allKeys
        let knownKeys = Set(CodingKeys.allCases.map(\.stringValue))
        let unknownKeys = allKeys.map(\.stringValue).filter { !knownKeys.contains($0) }
        guard unknownKeys.isEmpty else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "python artifact request contains unsupported root fields: \(unknownKeys.sorted().joined(separator: ", "))"
                )
            )
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        operation = try container.decode(RichAnswerPythonArtifactOperation.self, forKey: .operation)
        inputs = try container.decode([RichAnswerPythonArtifactInput].self, forKey: .inputs)
        parameters = try container.decodeIfPresent([String: RichAnswerPythonArtifactScalar].self, forKey: .parameters) ?? [:]
        requestedOutputs = try container.decode([RichAnswerPythonArtifactOutputRequest].self, forKey: .requestedOutputs)
        limits = try container.decodeIfPresent(RichAnswerPythonArtifactLimits.self, forKey: .limits) ?? .default
        sourceBindings = try container.decode([RichAnswerPythonArtifactSourceBinding].self, forKey: .sourceBindings)
        interactiveAdapter = try container.decodeIfPresent(RichAnswerPythonInteractiveAdapterDeclaration.self, forKey: .interactiveAdapter)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(operation, forKey: .operation)
        try container.encode(inputs, forKey: .inputs)
        try container.encode(parameters, forKey: .parameters)
        try container.encode(requestedOutputs, forKey: .requestedOutputs)
        try container.encode(limits, forKey: .limits)
        try container.encode(sourceBindings, forKey: .sourceBindings)
        try container.encodeIfPresent(interactiveAdapter, forKey: .interactiveAdapter)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case operation
        case inputs
        case parameters
        case requestedOutputs
        case limits
        case sourceBindings
        case interactiveAdapter
    }
}

public struct RichAnswerPythonArtifactLifecycle: Codable, Hashable, Sendable {
    public var scope: RichAnswerPythonArtifactLifecycleScope
    public var createdAt: Date
    public var expiresAt: Date?
    public var cleanupToken: String?
    public var requiresExplicitCleanup: Bool

    public init(
        scope: RichAnswerPythonArtifactLifecycleScope = .transient,
        createdAt: Date = Date(),
        expiresAt: Date? = nil,
        cleanupToken: String? = nil,
        requiresExplicitCleanup: Bool = true
    ) {
        self.scope = scope
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.cleanupToken = cleanupToken
        self.requiresExplicitCleanup = requiresExplicitCleanup
    }
}

public enum RichAnswerPythonArtifactPayload: Codable, Hashable, Sendable {
    case bytes(Data)
    case text(String)
    case json(RichAnswerRenderSpecValue)

    public func canonicalData() throws -> Data {
        switch self {
        case let .bytes(data):
            return data
        case let .text(text):
            return Data(text.utf8)
        case let .json(value):
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return try encoder.encode(value)
        }
    }
}

public struct RichAnswerPythonArtifactProduced: Codable, Hashable, Sendable {
    public var id: String
    public var kind: RichAnswerPythonArtifactKind
    public var mimeType: String
    public var role: String
    public var payload: RichAnswerPythonArtifactPayload
    public var sizeBytes: Int
    public var sha256: String
    public var sourceBindings: [RichAnswerPythonArtifactSourceBinding]
    public var lifecycle: RichAnswerPythonArtifactLifecycle
    public var metadata: [String: RichAnswerRenderSpecValue]

    public init(
        id: String,
        kind: RichAnswerPythonArtifactKind,
        mimeType: String,
        role: String,
        payload: RichAnswerPythonArtifactPayload,
        sourceBindings: [RichAnswerPythonArtifactSourceBinding],
        lifecycle: RichAnswerPythonArtifactLifecycle = RichAnswerPythonArtifactLifecycle(),
        metadata: [String: RichAnswerRenderSpecValue] = [:]
    ) throws {
        let data = try payload.canonicalData()
        self.id = id
        self.kind = kind
        self.mimeType = mimeType
        self.role = role
        self.payload = payload
        self.sizeBytes = data.count
        self.sha256 = RichAnswerPythonArtifactChecksum.sha256(data)
        self.sourceBindings = sourceBindings
        self.lifecycle = lifecycle
        self.metadata = metadata
    }

    public func renderArtifactRef(summary: String? = nil) -> RichAnswerRenderArtifactRef {
        RichAnswerRenderArtifactRef(
            id: id,
            kind: kind.rawValue,
            mimeType: mimeType,
            role: role,
            sizeBytes: sizeBytes,
            checksum: sha256,
            summary: summary,
            metadata: metadata
        )
    }
}

public struct RichAnswerPythonArtifactExecutionResult: Codable, Hashable, Sendable {
    public var requestID: String
    public var operation: RichAnswerPythonArtifactOperation
    public var artifacts: [RichAnswerPythonArtifactProduced]
    public var diagnostics: [String]

    public init(
        requestID: String,
        operation: RichAnswerPythonArtifactOperation,
        artifacts: [RichAnswerPythonArtifactProduced],
        diagnostics: [String] = []
    ) {
        self.requestID = requestID
        self.operation = operation
        self.artifacts = artifacts
        self.diagnostics = diagnostics
    }
}

public struct RichAnswerPythonArtifactValidatedRequest: Sendable {
    public var request: RichAnswerPythonArtifactRequest
    public var effectiveLimits: RichAnswerPythonArtifactLimits

    public init(request: RichAnswerPythonArtifactRequest, effectiveLimits: RichAnswerPythonArtifactLimits) {
        self.request = request
        self.effectiveLimits = effectiveLimits
    }
}

public struct RichAnswerPythonArtifactExecutor: Sendable {
    public var execute: @Sendable (RichAnswerPythonArtifactValidatedRequest) async throws -> RichAnswerPythonArtifactExecutionResult

    public init(
        execute: @escaping @Sendable (RichAnswerPythonArtifactValidatedRequest) async throws -> RichAnswerPythonArtifactExecutionResult
    ) {
        self.execute = execute
    }
}

public enum RichAnswerPythonArtifactError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidIdentifier(field: String, value: String)
    case unsupportedOperation(RichAnswerPythonArtifactOperation)
    case unsupportedOutputKind(RichAnswerPythonArtifactKind)
    case unsupportedInteractiveAdapter(RichAnswerPythonInteractiveAdapterKind)
    case sourceBindingRequired
    case sourceBindingMissing(target: String)
    case duplicateIdentifier(String)
    case budgetExceeded(field: String, actual: Int, limit: Int)
    case networkNotAllowed
    case filesystemNotAllowed
    case outputMismatch(String)
    case executionTimedOut(milliseconds: Int)

    public var description: String {
        switch self {
        case let .invalidIdentifier(field, value):
            return "\(field) has an unsafe identifier: \(value)"
        case let .unsupportedOperation(operation):
            return "operation is not in the allowlist: \(operation.rawValue)"
        case let .unsupportedOutputKind(kind):
            return "output kind is not in the allowlist: \(kind.rawValue)"
        case let .unsupportedInteractiveAdapter(kind):
            return "interactive adapter is not in the allowlist: \(kind.rawValue)"
        case .sourceBindingRequired:
            return "python artifact request requires at least one source binding"
        case let .sourceBindingMissing(target):
            return "python artifact source binding target is missing: \(target)"
        case let .duplicateIdentifier(identifier):
            return "duplicate python artifact identifier: \(identifier)"
        case let .budgetExceeded(field, actual, limit):
            return "\(field) exceeds budget: \(actual) > \(limit)"
        case .networkNotAllowed:
            return "python artifact chain cannot use network access"
        case .filesystemNotAllowed:
            return "python artifact chain cannot access arbitrary files"
        case let .outputMismatch(message):
            return message
        case let .executionTimedOut(milliseconds):
            return "python artifact executor timed out after \(milliseconds)ms"
        }
    }
}

public enum RichAnswerPythonArtifactPipeline {
    public static func decodeRequestStrict(from data: Data, decoder: JSONDecoder = JSONDecoder()) throws -> RichAnswerPythonArtifactRequest {
        try decoder.decode(RichAnswerPythonArtifactRequest.self, from: data)
    }

    public static func validate(
        _ request: RichAnswerPythonArtifactRequest,
        policy: RichAnswerPythonArtifactPolicy = .default
    ) throws -> RichAnswerPythonArtifactValidatedRequest {
        let effectiveLimits = request.limits.constrained(by: policy.limits)

        guard RichAnswerPythonArtifactID.isSafe(request.id) else {
            throw RichAnswerPythonArtifactError.invalidIdentifier(field: "request.id", value: request.id)
        }
        guard policy.allowedOperations.contains(request.operation) else {
            throw RichAnswerPythonArtifactError.unsupportedOperation(request.operation)
        }
        if request.limits.allowNetwork && !policy.limits.allowNetwork {
            throw RichAnswerPythonArtifactError.networkNotAllowed
        }
        if request.limits.allowFilesystem && !policy.limits.allowFilesystem {
            throw RichAnswerPythonArtifactError.filesystemNotAllowed
        }
        if policy.requireSourceBindings && request.sourceBindings.isEmpty {
            throw RichAnswerPythonArtifactError.sourceBindingRequired
        }
        try validateUniqueIDs(
            request.inputs.map(\.id) + request.requestedOutputs.map(\.id) + request.sourceBindings.map(\.id)
        )
        try validateSourceBindings(request.sourceBindings)
        try validateInputs(request.inputs, limits: effectiveLimits)
        try validateRequestedOutputs(request.requestedOutputs, policy: policy, limits: effectiveLimits)
        try validateInteractiveAdapter(request.interactiveAdapter, policy: policy)

        let encodedRequestSize = try JSONEncoder().encode(request).count
        if encodedRequestSize > effectiveLimits.maxInputBytes {
            throw RichAnswerPythonArtifactError.budgetExceeded(
                field: "request",
                actual: encodedRequestSize,
                limit: effectiveLimits.maxInputBytes
            )
        }

        return RichAnswerPythonArtifactValidatedRequest(request: request, effectiveLimits: effectiveLimits)
    }

    public static func execute(
        request: RichAnswerPythonArtifactRequest,
        policy: RichAnswerPythonArtifactPolicy = .default,
        executor: RichAnswerPythonArtifactExecutor
    ) async throws -> RichAnswerPythonArtifactExecutionResult {
        let validated = try validate(request, policy: policy)
        let result = try await withThrowingTaskGroup(of: RichAnswerPythonArtifactExecutionResult.self) { group in
            group.addTask {
                try await executor.execute(validated)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(1, validated.effectiveLimits.maxRuntimeMS)) * 1_000_000)
                throw RichAnswerPythonArtifactError.executionTimedOut(milliseconds: validated.effectiveLimits.maxRuntimeMS)
            }
            guard let first = try await group.next() else {
                throw RichAnswerPythonArtifactError.outputMismatch("python artifact executor returned no result")
            }
            group.cancelAll()
            return first
        }
        try validate(result, for: validated, policy: policy)
        return result
    }

    public static func validate(
        _ result: RichAnswerPythonArtifactExecutionResult,
        for validated: RichAnswerPythonArtifactValidatedRequest,
        policy: RichAnswerPythonArtifactPolicy = .default
    ) throws {
        guard result.requestID == validated.request.id else {
            throw RichAnswerPythonArtifactError.outputMismatch("result requestID does not match validated request")
        }
        guard result.operation == validated.request.operation else {
            throw RichAnswerPythonArtifactError.outputMismatch("result operation does not match validated request")
        }
        if result.artifacts.count > validated.effectiveLimits.maxArtifacts {
            throw RichAnswerPythonArtifactError.budgetExceeded(
                field: "artifacts",
                actual: result.artifacts.count,
                limit: validated.effectiveLimits.maxArtifacts
            )
        }
        try validateUniqueIDs(result.artifacts.map(\.id))

        var totalBytes = 0
        for artifact in result.artifacts {
            guard RichAnswerPythonArtifactID.isSafe(artifact.id) else {
                throw RichAnswerPythonArtifactError.invalidIdentifier(field: "artifact.id", value: artifact.id)
            }
            guard policy.allowedOutputKinds.contains(artifact.kind) else {
                throw RichAnswerPythonArtifactError.unsupportedOutputKind(artifact.kind)
            }
            totalBytes += artifact.sizeBytes
            if artifact.sizeBytes > validated.effectiveLimits.maxOutputBytes {
                throw RichAnswerPythonArtifactError.budgetExceeded(
                    field: "artifact.\(artifact.id)",
                    actual: artifact.sizeBytes,
                    limit: validated.effectiveLimits.maxOutputBytes
                )
            }
            let payload = try artifact.payload.canonicalData()
            let checksum = RichAnswerPythonArtifactChecksum.sha256(payload)
            guard checksum == artifact.sha256 else {
                throw RichAnswerPythonArtifactError.outputMismatch("artifact \(artifact.id) checksum does not match payload")
            }
            if policy.requireSourceBindings && artifact.sourceBindings.isEmpty {
                throw RichAnswerPythonArtifactError.sourceBindingRequired
            }
            try validateSourceBindings(artifact.sourceBindings)
        }
        if totalBytes > validated.effectiveLimits.maxOutputBytes {
            throw RichAnswerPythonArtifactError.budgetExceeded(
                field: "result.artifacts",
                actual: totalBytes,
                limit: validated.effectiveLimits.maxOutputBytes
            )
        }
    }

    private static func validateInputs(
        _ inputs: [RichAnswerPythonArtifactInput],
        limits: RichAnswerPythonArtifactLimits
    ) throws {
        var totalBytes = 0
        for input in inputs {
            guard RichAnswerPythonArtifactID.isSafe(input.id) else {
                throw RichAnswerPythonArtifactError.invalidIdentifier(field: "input.id", value: input.id)
            }
            guard RichAnswerPythonArtifactID.isSafe(input.role) else {
                throw RichAnswerPythonArtifactError.invalidIdentifier(field: "input.role", value: input.role)
            }
            totalBytes += try RichAnswerPythonArtifactSize.encodedSize(input.payload)
            switch input.payload {
            case let .numberSeries(values):
                if values.count > limits.maxRows {
                    throw RichAnswerPythonArtifactError.budgetExceeded(field: input.id, actual: values.count, limit: limits.maxRows)
                }
                if values.contains(where: { !$0.isFinite }) {
                    throw RichAnswerPythonArtifactError.invalidIdentifier(field: "numberSeries.\(input.id)", value: "non-finite")
                }
            case let .table(table):
                try validate(table, id: input.id, limits: limits)
            case let .imageRef(image):
                guard RichAnswerPythonArtifactID.isSafeAssetID(image.assetID) else {
                    throw RichAnswerPythonArtifactError.invalidIdentifier(field: "image.assetID", value: image.assetID)
                }
            case .scalar, .expression, .artifactRef:
                break
            }
        }
        if totalBytes > limits.maxInputBytes {
            throw RichAnswerPythonArtifactError.budgetExceeded(field: "inputs", actual: totalBytes, limit: limits.maxInputBytes)
        }
    }

    private static func validate(
        _ table: RichAnswerPythonArtifactTable,
        id: String,
        limits: RichAnswerPythonArtifactLimits
    ) throws {
        if table.columns.count > limits.maxColumns {
            throw RichAnswerPythonArtifactError.budgetExceeded(field: "\(id).columns", actual: table.columns.count, limit: limits.maxColumns)
        }
        if table.rows.count > limits.maxRows {
            throw RichAnswerPythonArtifactError.budgetExceeded(field: "\(id).rows", actual: table.rows.count, limit: limits.maxRows)
        }
        try validateUniqueIDs(table.columns.map(\.id))
        for column in table.columns {
            guard RichAnswerPythonArtifactID.isSafe(column.id) else {
                throw RichAnswerPythonArtifactError.invalidIdentifier(field: "\(id).column.id", value: column.id)
            }
        }
        for row in table.rows where row.count != table.columns.count {
            throw RichAnswerPythonArtifactError.outputMismatch("table \(id) row width does not match columns")
        }
    }

    private static func validateRequestedOutputs(
        _ outputs: [RichAnswerPythonArtifactOutputRequest],
        policy: RichAnswerPythonArtifactPolicy,
        limits: RichAnswerPythonArtifactLimits
    ) throws {
        if outputs.count > limits.maxArtifacts {
            throw RichAnswerPythonArtifactError.budgetExceeded(field: "requestedOutputs", actual: outputs.count, limit: limits.maxArtifacts)
        }
        for output in outputs {
            guard RichAnswerPythonArtifactID.isSafe(output.id) else {
                throw RichAnswerPythonArtifactError.invalidIdentifier(field: "output.id", value: output.id)
            }
            guard policy.allowedOutputKinds.contains(output.kind) else {
                throw RichAnswerPythonArtifactError.unsupportedOutputKind(output.kind)
            }
            guard output.mimeType.contains("/") && !output.mimeType.contains("..") else {
                throw RichAnswerPythonArtifactError.invalidIdentifier(field: "output.mimeType", value: output.mimeType)
            }
        }
    }

    private static func validateInteractiveAdapter(
        _ adapter: RichAnswerPythonInteractiveAdapterDeclaration?,
        policy: RichAnswerPythonArtifactPolicy
    ) throws {
        guard let adapter else { return }
        guard policy.allowInteractiveAdapters else {
            throw RichAnswerPythonArtifactError.unsupportedInteractiveAdapter(adapter.kind)
        }
        guard policy.allowedInteractiveAdapters.contains(adapter.kind) else {
            throw RichAnswerPythonArtifactError.unsupportedInteractiveAdapter(adapter.kind)
        }
        guard RichAnswerPythonArtifactID.isSafe(adapter.id) else {
            throw RichAnswerPythonArtifactError.invalidIdentifier(field: "interactiveAdapter.id", value: adapter.id)
        }
        if adapter.allowNetwork {
            throw RichAnswerPythonArtifactError.networkNotAllowed
        }
        if adapter.allowFilesystem {
            throw RichAnswerPythonArtifactError.filesystemNotAllowed
        }
        for artifactID in adapter.requiredArtifactIDs where !RichAnswerPythonArtifactID.isSafe(artifactID) {
            throw RichAnswerPythonArtifactError.invalidIdentifier(field: "interactiveAdapter.requiredArtifactIDs", value: artifactID)
        }
    }

    private static func validateSourceBindings(_ bindings: [RichAnswerPythonArtifactSourceBinding]) throws {
        for binding in bindings {
            guard RichAnswerPythonArtifactID.isSafe(binding.id) else {
                throw RichAnswerPythonArtifactError.invalidIdentifier(field: "sourceBinding.id", value: binding.id)
            }
            guard RichAnswerPythonArtifactID.isSafe(binding.evidenceID) else {
                throw RichAnswerPythonArtifactError.invalidIdentifier(field: "sourceBinding.evidenceID", value: binding.evidenceID)
            }
            guard RichAnswerPythonArtifactID.isSafe(binding.target) else {
                throw RichAnswerPythonArtifactError.sourceBindingMissing(target: binding.target)
            }
        }
    }

    private static func validateUniqueIDs(_ identifiers: [String]) throws {
        var seen: Set<String> = []
        for identifier in identifiers {
            if seen.contains(identifier) {
                throw RichAnswerPythonArtifactError.duplicateIdentifier(identifier)
            }
            seen.insert(identifier)
        }
    }
}

private enum RichAnswerPythonArtifactChecksum {
    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private enum RichAnswerPythonArtifactSize {
    static func encodedSize<T: Encodable>(_ value: T) throws -> Int {
        try JSONEncoder().encode(value).count
    }
}

private enum RichAnswerPythonArtifactID {
    static func isSafe(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 96 else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar)
                || scalar == "-"
                || scalar == "_"
                || scalar == "."
                || scalar == ":"
        }
    }

    static func isSafeAssetID(_ value: String) -> Bool {
        guard isSafe(value), !value.lowercased().hasPrefix("file:"), !value.contains("/") else {
            return false
        }
        return !value.contains("\\") && !value.contains("..")
    }
}

private struct RichAnswerPythonArtifactAnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = "\(intValue)"
        self.intValue = intValue
    }
}
