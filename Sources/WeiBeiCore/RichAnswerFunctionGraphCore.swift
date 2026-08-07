import Foundation

public enum RichAnswerMathUnaryOperator: String, Codable, CaseIterable, Hashable, Sendable {
    case positive
    case negative
}

public enum RichAnswerMathBinaryOperator: String, Codable, CaseIterable, Hashable, Sendable {
    case add
    case subtract
    case multiply
    case divide
    case power
}

public enum RichAnswerMathFunction: String, Codable, CaseIterable, Hashable, Sendable {
    case abs
    case sqrt
    case exp
    case log
    case log10
    case sin
    case cos
    case tan
    case asin
    case acos
    case atan
    case floor
    case ceil
    case round
    case min
    case max
    case pow

    public func acceptsArity(_ count: Int) -> Bool {
        switch self {
        case .min, .max, .pow:
            return count == 2
        case .abs, .sqrt, .exp, .log, .log10, .sin, .cos, .tan, .asin, .acos, .atan, .floor, .ceil, .round:
            return count == 1
        }
    }
}

public indirect enum RichAnswerMathExpression: Codable, Hashable, Sendable {
    case constant(Double)
    case variable(String)
    case parameter(String)
    case unary(RichAnswerMathUnaryOperator, RichAnswerMathExpression)
    case binary(RichAnswerMathBinaryOperator, RichAnswerMathExpression, RichAnswerMathExpression)
    case call(RichAnswerMathFunction, [RichAnswerMathExpression])
}

public struct RichAnswerMathSafetyLimits: Codable, Hashable, Sendable {
    public var maximumDepth: Int
    public var maximumNodeCount: Int
    public var maximumMagnitude: Double
    public var zeroTolerance: Double
    public var rootTolerance: Double

    public init(
        maximumDepth: Int = 32,
        maximumNodeCount: Int = 256,
        maximumMagnitude: Double = 1.0e12,
        zeroTolerance: Double = 1.0e-12,
        rootTolerance: Double = 1.0e-9
    ) {
        self.maximumDepth = maximumDepth
        self.maximumNodeCount = maximumNodeCount
        self.maximumMagnitude = maximumMagnitude
        self.zeroTolerance = zeroTolerance
        self.rootTolerance = rootTolerance
    }

    public static let `default` = RichAnswerMathSafetyLimits()
}

public enum RichAnswerMathExpressionValidationError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidIdentifier(String)
    case unknownVariable(String)
    case unknownParameter(String)
    case nonFiniteConstant(Double)
    case magnitudeExceeded(Double)
    case depthExceeded(Int)
    case nodeCountExceeded(Int)
    case invalidArity(function: RichAnswerMathFunction, received: Int)

    public var description: String {
        switch self {
        case .invalidIdentifier(let name):
            return "invalid math identifier '\(name)'"
        case .unknownVariable(let name):
            return "unknown math variable '\(name)'"
        case .unknownParameter(let name):
            return "unknown math parameter '\(name)'"
        case .nonFiniteConstant(let value):
            return "non-finite math constant \(value)"
        case .magnitudeExceeded(let value):
            return "math value \(value) exceeds configured magnitude guard"
        case .depthExceeded(let depth):
            return "math expression depth \(depth) exceeds configured guard"
        case .nodeCountExceeded(let count):
            return "math expression node count \(count) exceeds configured guard"
        case .invalidArity(let function, let received):
            return "function \(function.rawValue) received \(received) arguments"
        }
    }
}

public enum RichAnswerMathEvaluationError: Error, Equatable, CustomStringConvertible, Sendable {
    case missingVariable(String)
    case missingParameter(String)
    case domain(String)
    case nonFiniteValue
    case magnitudeExceeded(Double)

    public var description: String {
        switch self {
        case .missingVariable(let name):
            return "missing variable '\(name)'"
        case .missingParameter(let name):
            return "missing parameter '\(name)'"
        case .domain(let message):
            return "domain error: \(message)"
        case .nonFiniteValue:
            return "non-finite value"
        case .magnitudeExceeded(let value):
            return "value \(value) exceeds configured magnitude guard"
        }
    }
}

public struct RichAnswerMathEvaluationContext: Codable, Hashable, Sendable {
    public var variables: [String: Double]
    public var parameters: [String: Double]

    public init(variables: [String: Double] = [:], parameters: [String: Double] = [:]) {
        self.variables = variables
        self.parameters = parameters
    }
}

public struct RichAnswerMathInterval: Codable, Hashable, Sendable {
    public var lower: Double
    public var upper: Double

    public init(lower: Double, upper: Double) {
        self.lower = lower
        self.upper = upper
    }

    public var length: Double {
        upper - lower
    }

    public var isFiniteIncreasing: Bool {
        lower.isFinite && upper.isFinite && upper > lower
    }

    public func contains(_ value: Double) -> Bool {
        value >= lower && value <= upper
    }

    public func intersection(_ other: RichAnswerMathInterval) -> RichAnswerMathInterval? {
        let nextLower = Swift.max(lower, other.lower)
        let nextUpper = Swift.min(upper, other.upper)
        guard nextUpper > nextLower else {
            return nil
        }
        return RichAnswerMathInterval(lower: nextLower, upper: nextUpper)
    }
}

public struct RichAnswerFunctionDomain: Codable, Hashable, Sendable {
    public var intervals: [RichAnswerMathInterval]

    public init(intervals: [RichAnswerMathInterval]) {
        self.intervals = intervals
    }

    public static func closed(_ lower: Double, _ upper: Double) -> RichAnswerFunctionDomain {
        RichAnswerFunctionDomain(intervals: [RichAnswerMathInterval(lower: lower, upper: upper)])
    }

    public func visibleIntervals(in displayX: RichAnswerMathInterval) -> [RichAnswerMathInterval] {
        intervals.compactMap { interval in
            interval.intersection(displayX)
        }
    }
}

public struct RichAnswerMathParameter: Codable, Hashable, Sendable {
    public var name: String
    public var value: Double
    public var range: RichAnswerMathInterval?
    public var step: Double?

    public init(name: String, value: Double, range: RichAnswerMathInterval? = nil, step: Double? = nil) {
        self.name = name
        self.value = value
        self.range = range
        self.step = step
    }
}

public struct RichAnswerFunctionGraphSpec: Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var independentVariable: String
    public var expression: RichAnswerMathExpression
    public var parameters: [RichAnswerMathParameter]
    public var domain: RichAnswerFunctionDomain

    public init(
        id: String,
        title: String,
        independentVariable: String = "x",
        expression: RichAnswerMathExpression,
        parameters: [RichAnswerMathParameter] = [],
        domain: RichAnswerFunctionDomain
    ) {
        self.id = id
        self.title = title
        self.independentVariable = independentVariable
        self.expression = expression
        self.parameters = parameters
        self.domain = domain
    }

    public var parameterValues: [String: Double] {
        Dictionary(uniqueKeysWithValues: parameters.map { ($0.name, $0.value) })
    }
}

public struct RichAnswerFunctionDisplayRange: Codable, Hashable, Sendable {
    public var x: RichAnswerMathInterval
    public var y: RichAnswerMathInterval

    public init(x: RichAnswerMathInterval, y: RichAnswerMathInterval) {
        self.x = x
        self.y = y
    }
}

public struct RichAnswerFunctionViewport: Codable, Hashable, Sendable {
    public var widthPoints: Double
    public var heightPoints: Double
    public var devicePixelRatio: Double

    public init(widthPoints: Double, heightPoints: Double, devicePixelRatio: Double) {
        self.widthPoints = widthPoints
        self.heightPoints = heightPoints
        self.devicePixelRatio = devicePixelRatio
    }

    public var widthPixels: Double {
        widthPoints * devicePixelRatio
    }

    public var heightPixels: Double {
        heightPoints * devicePixelRatio
    }
}

public struct RichAnswerFunctionSamplingInput: Codable, Hashable, Sendable {
    public var displayRange: RichAnswerFunctionDisplayRange
    public var viewport: RichAnswerFunctionViewport
    public var maximumScreenErrorPixels: Double
    public var minimumStepPixels: Double
    public var initialSegmentPixels: Double
    public var maximumDepth: Int
    public var maximumInitialSegments: Int
    public var maximumSamplePoints: Int
    public var discontinuityScanSteps: Int

    public init(
        displayRange: RichAnswerFunctionDisplayRange,
        viewport: RichAnswerFunctionViewport,
        maximumScreenErrorPixels: Double = 0.55,
        minimumStepPixels: Double = 0.35,
        initialSegmentPixels: Double = 24,
        maximumDepth: Int = 18,
        maximumInitialSegments: Int = 512,
        maximumSamplePoints: Int = 8_192,
        discontinuityScanSteps: Int = 2_048
    ) {
        self.displayRange = displayRange
        self.viewport = viewport
        self.maximumScreenErrorPixels = maximumScreenErrorPixels
        self.minimumStepPixels = minimumStepPixels
        self.initialSegmentPixels = initialSegmentPixels
        self.maximumDepth = maximumDepth
        self.maximumInitialSegments = maximumInitialSegments
        self.maximumSamplePoints = maximumSamplePoints
        self.discontinuityScanSteps = discontinuityScanSteps
    }
}

public enum RichAnswerFunctionCurveSource: String, Codable, CaseIterable, Hashable, Sendable {
    case analyticalExpression
    case observedData
}

public struct RichAnswerFunctionSamplePoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var screenX: Double
    public var screenY: Double

    public init(x: Double, y: Double, screenX: Double, screenY: Double) {
        self.x = x
        self.y = y
        self.screenX = screenX
        self.screenY = screenY
    }
}

public struct RichAnswerFunctionPolylineSegment: Codable, Hashable, Sendable {
    public var points: [RichAnswerFunctionSamplePoint]

    public init(points: [RichAnswerFunctionSamplePoint]) {
        self.points = points
    }
}

public enum RichAnswerFunctionSamplingDiagnosticCode: String, Codable, CaseIterable, Hashable, Sendable {
    case domainCut
    case discontinuityCut
    case nonFiniteValue
    case overflowValue
    case maxDepthReached
    case budgetExceeded
    case observedDataPreserved
}

public struct RichAnswerFunctionSamplingDiagnostic: Codable, Hashable, Sendable {
    public var code: RichAnswerFunctionSamplingDiagnosticCode
    public var message: String
    public var x: Double?

    public init(code: RichAnswerFunctionSamplingDiagnosticCode, message: String, x: Double? = nil) {
        self.code = code
        self.message = message
        self.x = x
    }
}

public struct RichAnswerFunctionSamplingResult: Codable, Hashable, Sendable {
    public var source: RichAnswerFunctionCurveSource
    public var segments: [RichAnswerFunctionPolylineSegment]
    public var diagnostics: [RichAnswerFunctionSamplingDiagnostic]
    public var usedDevicePixelRatio: Double
    public var isSmoothed: Bool

    public init(
        source: RichAnswerFunctionCurveSource,
        segments: [RichAnswerFunctionPolylineSegment],
        diagnostics: [RichAnswerFunctionSamplingDiagnostic],
        usedDevicePixelRatio: Double,
        isSmoothed: Bool
    ) {
        self.source = source
        self.segments = segments
        self.diagnostics = diagnostics
        self.usedDevicePixelRatio = usedDevicePixelRatio
        self.isSmoothed = isSmoothed
    }

    public var pointCount: Int {
        segments.reduce(0) { count, segment in
            count + segment.points.count
        }
    }
}

public struct RichAnswerObservedDataPoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var label: String?

    public init(x: Double, y: Double, label: String? = nil) {
        self.x = x
        self.y = y
        self.label = label
    }
}

public struct RichAnswerObservedDataSeries: Codable, Hashable, Sendable {
    public var id: String
    public var points: [RichAnswerObservedDataPoint]

    public init(id: String, points: [RichAnswerObservedDataPoint]) {
        self.id = id
        self.points = points
    }
}

public enum RichAnswerFunctionSamplingError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidIdentifier(String)
    case invalidDomain
    case invalidDisplayRange
    case invalidViewport
    case invalidSamplingBudget
    case duplicateParameter(String)
    case invalidParameter(String)
    case noVisibleDomain
    case budgetExceeded(Int)

    public var description: String {
        switch self {
        case .invalidIdentifier(let name):
            return "invalid identifier '\(name)'"
        case .invalidDomain:
            return "function domain must contain finite increasing intervals"
        case .invalidDisplayRange:
            return "display x and y ranges must be finite increasing intervals"
        case .invalidViewport:
            return "viewport dimensions and device pixel ratio must be finite positive values"
        case .invalidSamplingBudget:
            return "sampling budget must be finite positive values"
        case .duplicateParameter(let name):
            return "duplicate parameter '\(name)'"
        case .invalidParameter(let name):
            return "invalid parameter '\(name)'"
        case .noVisibleDomain:
            return "domain has no overlap with display x range"
        case .budgetExceeded(let count):
            return "sample point count \(count) exceeded configured budget"
        }
    }
}

public enum RichAnswerFunctionGraphSampler {
    public static func sample(
        spec: RichAnswerFunctionGraphSpec,
        input: RichAnswerFunctionSamplingInput,
        limits: RichAnswerMathSafetyLimits = .default
    ) throws -> RichAnswerFunctionSamplingResult {
        try validate(spec: spec, input: input, limits: limits)
        let visibleIntervals = spec.domain.visibleIntervals(in: input.displayRange.x)
        guard !visibleIntervals.isEmpty else {
            throw RichAnswerFunctionSamplingError.noVisibleDomain
        }

        var diagnostics: [RichAnswerFunctionSamplingDiagnostic] = []
        let breakpoints = discontinuityBreakpoints(
            expression: spec.expression,
            independentVariable: spec.independentVariable,
            parameters: spec.parameterValues,
            intervals: visibleIntervals,
            input: input,
            limits: limits
        )
        var segments: [RichAnswerFunctionPolylineSegment] = []
        for interval in split(intervals: visibleIntervals, at: breakpoints, input: input, diagnostics: &diagnostics) {
            for seed in seedIntervals(in: interval, input: input) {
                let sampled = adaptiveSegments(
                    spec: spec,
                    interval: seed,
                    input: input,
                    limits: limits,
                    diagnostics: &diagnostics
                )
                segments = merge(segments, sampled)
            }
        }

        let result = RichAnswerFunctionSamplingResult(
            source: .analyticalExpression,
            segments: segments.filter { $0.points.count >= 2 },
            diagnostics: diagnostics,
            usedDevicePixelRatio: input.viewport.devicePixelRatio,
            isSmoothed: false
        )
        guard result.pointCount <= input.maximumSamplePoints else {
            throw RichAnswerFunctionSamplingError.budgetExceeded(result.pointCount)
        }
        return result
    }

    public static func sampleObservedData(
        series: RichAnswerObservedDataSeries,
        input: RichAnswerFunctionSamplingInput,
        limits: RichAnswerMathSafetyLimits = .default
    ) throws -> RichAnswerFunctionSamplingResult {
        try validate(input: input)
        var diagnostics = [
            RichAnswerFunctionSamplingDiagnostic(
                code: .observedDataPreserved,
                message: "Observed data is emitted as raw polyline segments with no smoothing or synthetic interpolation."
            )
        ]
        var segments: [RichAnswerFunctionPolylineSegment] = []
        var current: [RichAnswerFunctionSamplePoint] = []
        for point in series.points {
            guard point.x.isFinite,
                  point.y.isFinite,
                  abs(point.x) <= limits.maximumMagnitude,
                  abs(point.y) <= limits.maximumMagnitude else {
                if current.count >= 2 {
                    segments.append(RichAnswerFunctionPolylineSegment(points: current))
                }
                current.removeAll()
                record(
                    .nonFiniteValue,
                    "Observed point was finite-check rejected and cut from the polyline.",
                    x: point.x.isFinite ? point.x : nil,
                    diagnostics: &diagnostics
                )
                continue
            }
            current.append(screenPoint(x: point.x, y: point.y, input: input))
        }
        if current.count >= 2 {
            segments.append(RichAnswerFunctionPolylineSegment(points: current))
        }
        let result = RichAnswerFunctionSamplingResult(
            source: .observedData,
            segments: segments,
            diagnostics: diagnostics,
            usedDevicePixelRatio: input.viewport.devicePixelRatio,
            isSmoothed: false
        )
        guard result.pointCount <= input.maximumSamplePoints else {
            throw RichAnswerFunctionSamplingError.budgetExceeded(result.pointCount)
        }
        return result
    }
}

extension RichAnswerMathExpression {
    public func validate(
        allowedVariables: Set<String>,
        allowedParameters: Set<String>,
        limits: RichAnswerMathSafetyLimits = .default
    ) throws {
        var nodeCount = 0
        try validate(
            allowedVariables: allowedVariables,
            allowedParameters: allowedParameters,
            limits: limits,
            depth: 0,
            nodeCount: &nodeCount
        )
    }

    public func evaluated(
        in context: RichAnswerMathEvaluationContext,
        limits: RichAnswerMathSafetyLimits = .default
    ) throws -> Double {
        try evaluated(in: context, limits: limits, depth: 0)
    }
}

private extension RichAnswerFunctionGraphSampler {
    static func validate(
        spec: RichAnswerFunctionGraphSpec,
        input: RichAnswerFunctionSamplingInput,
        limits: RichAnswerMathSafetyLimits
    ) throws {
        try validate(input: input)
        guard !spec.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              spec.id.count <= 128 else {
            throw RichAnswerFunctionSamplingError.invalidIdentifier(spec.id)
        }
        guard isValidIdentifier(spec.independentVariable) else {
            throw RichAnswerFunctionSamplingError.invalidIdentifier(spec.independentVariable)
        }
        guard !spec.domain.intervals.isEmpty,
              spec.domain.intervals.allSatisfy(\.isFiniteIncreasing) else {
            throw RichAnswerFunctionSamplingError.invalidDomain
        }
        var parameterNames = Set<String>()
        for parameter in spec.parameters {
            guard isValidIdentifier(parameter.name),
                  parameter.value.isFinite,
                  abs(parameter.value) <= limits.maximumMagnitude else {
                throw RichAnswerFunctionSamplingError.invalidParameter(parameter.name)
            }
            guard parameterNames.insert(parameter.name).inserted else {
                throw RichAnswerFunctionSamplingError.duplicateParameter(parameter.name)
            }
            if let range = parameter.range, !range.isFiniteIncreasing {
                throw RichAnswerFunctionSamplingError.invalidParameter(parameter.name)
            }
            if let step = parameter.step, !(step.isFinite && step > 0) {
                throw RichAnswerFunctionSamplingError.invalidParameter(parameter.name)
            }
        }
        try spec.expression.validate(
            allowedVariables: [spec.independentVariable],
            allowedParameters: parameterNames,
            limits: limits
        )
    }

    static func validate(input: RichAnswerFunctionSamplingInput) throws {
        guard input.displayRange.x.isFiniteIncreasing,
              input.displayRange.y.isFiniteIncreasing else {
            throw RichAnswerFunctionSamplingError.invalidDisplayRange
        }
        guard input.viewport.widthPoints.isFinite,
              input.viewport.heightPoints.isFinite,
              input.viewport.devicePixelRatio.isFinite,
              input.viewport.widthPoints > 0,
              input.viewport.heightPoints > 0,
              input.viewport.devicePixelRatio > 0 else {
            throw RichAnswerFunctionSamplingError.invalidViewport
        }
        guard input.maximumScreenErrorPixels.isFinite,
              input.minimumStepPixels.isFinite,
              input.initialSegmentPixels.isFinite,
              input.maximumScreenErrorPixels > 0,
              input.minimumStepPixels > 0,
              input.initialSegmentPixels > 0,
              input.maximumDepth > 0,
              input.maximumInitialSegments > 0,
              input.maximumSamplePoints > 0,
              input.discontinuityScanSteps > 8 else {
            throw RichAnswerFunctionSamplingError.invalidSamplingBudget
        }
    }

    static func adaptiveSegments(
        spec: RichAnswerFunctionGraphSpec,
        interval: RichAnswerMathInterval,
        input: RichAnswerFunctionSamplingInput,
        limits: RichAnswerMathSafetyLimits,
        diagnostics: inout [RichAnswerFunctionSamplingDiagnostic]
    ) -> [RichAnswerFunctionPolylineSegment] {
        sampleInterval(
            spec: spec,
            x0: interval.lower,
            x1: interval.upper,
            depth: 0,
            input: input,
            limits: limits,
            diagnostics: &diagnostics
        )
    }

    static func sampleInterval(
        spec: RichAnswerFunctionGraphSpec,
        x0: Double,
        x1: Double,
        depth: Int,
        input: RichAnswerFunctionSamplingInput,
        limits: RichAnswerMathSafetyLimits,
        diagnostics: inout [RichAnswerFunctionSamplingDiagnostic]
    ) -> [RichAnswerFunctionPolylineSegment] {
        guard x1 > x0 else {
            return []
        }
        let p0 = samplePoint(spec: spec, x: x0, input: input, limits: limits, diagnostics: &diagnostics)
        let p1 = samplePoint(spec: spec, x: x1, input: input, limits: limits, diagnostics: &diagnostics)
        guard let start = p0, let end = p1 else {
            guard depth < input.maximumDepth,
                  screenWidth(from: x0, to: x1, input: input) > input.minimumStepPixels else {
                return []
            }
            let midpoint = x0 + (x1 - x0) / 2
            return sampleInterval(
                spec: spec,
                x0: x0,
                x1: midpoint,
                depth: depth + 1,
                input: input,
                limits: limits,
                diagnostics: &diagnostics
            ) + sampleInterval(
                spec: spec,
                x0: midpoint,
                x1: x1,
                depth: depth + 1,
                input: input,
                limits: limits,
                diagnostics: &diagnostics
            )
        }

        let midpointX = x0 + (x1 - x0) / 2
        guard let midpoint = samplePoint(spec: spec, x: midpointX, input: input, limits: limits, diagnostics: &diagnostics) else {
            guard depth < input.maximumDepth else {
                record(.discontinuityCut, "Invalid midpoint cut this interval.", x: midpointX, diagnostics: &diagnostics)
                return []
            }
            let left = sampleInterval(
                spec: spec,
                x0: x0,
                x1: midpointX,
                depth: depth + 1,
                input: input,
                limits: limits,
                diagnostics: &diagnostics
            )
            let right = sampleInterval(
                spec: spec,
                x0: midpointX,
                x1: x1,
                depth: depth + 1,
                input: input,
                limits: limits,
                diagnostics: &diagnostics
            )
            return left + right
        }

        let screenError = midpointScreenError(start: start, midpoint: midpoint, end: end)
        if screenError <= input.maximumScreenErrorPixels ||
            depth >= input.maximumDepth ||
            screenWidth(from: x0, to: x1, input: input) <= input.minimumStepPixels {
            if depth >= input.maximumDepth && screenError > input.maximumScreenErrorPixels {
                record(.maxDepthReached, "Adaptive sampler reached maximum depth before screen error target.", x: midpointX, diagnostics: &diagnostics)
            }
            return [RichAnswerFunctionPolylineSegment(points: [start, end])]
        }

        let left = sampleInterval(
            spec: spec,
            x0: x0,
            x1: midpointX,
            depth: depth + 1,
            input: input,
            limits: limits,
            diagnostics: &diagnostics
        )
        let right = sampleInterval(
            spec: spec,
            x0: midpointX,
            x1: x1,
            depth: depth + 1,
            input: input,
            limits: limits,
            diagnostics: &diagnostics
        )
        return merge(left, right)
    }

    static func samplePoint(
        spec: RichAnswerFunctionGraphSpec,
        x: Double,
        input: RichAnswerFunctionSamplingInput,
        limits: RichAnswerMathSafetyLimits,
        diagnostics: inout [RichAnswerFunctionSamplingDiagnostic]
    ) -> RichAnswerFunctionSamplePoint? {
        do {
            let y = try spec.expression.evaluated(
                in: RichAnswerMathEvaluationContext(
                    variables: [spec.independentVariable: x],
                    parameters: spec.parameterValues
                ),
                limits: limits
            )
            return screenPoint(x: x, y: y, input: input)
        } catch let error as RichAnswerMathEvaluationError {
            switch error {
            case .magnitudeExceeded:
                record(.overflowValue, error.description, x: x, diagnostics: &diagnostics)
            case .nonFiniteValue:
                record(.nonFiniteValue, error.description, x: x, diagnostics: &diagnostics)
            case .domain, .missingParameter, .missingVariable:
                record(.nonFiniteValue, error.description, x: x, diagnostics: &diagnostics)
            }
            return nil
        } catch {
            record(.nonFiniteValue, "\(error)", x: x, diagnostics: &diagnostics)
            return nil
        }
    }

    static func seedIntervals(in interval: RichAnswerMathInterval, input: RichAnswerFunctionSamplingInput) -> [RichAnswerMathInterval] {
        let pixelWidth = screenWidth(from: interval.lower, to: interval.upper, input: input)
        let segmentCount = Swift.max(
            1,
            Swift.min(
                input.maximumInitialSegments,
                Int(ceil(pixelWidth / input.initialSegmentPixels))
            )
        )
        guard segmentCount > 1 else {
            return [interval]
        }
        return (0..<segmentCount).map { index in
            let lower = interval.lower + interval.length * Double(index) / Double(segmentCount)
            let upper = interval.lower + interval.length * Double(index + 1) / Double(segmentCount)
            return RichAnswerMathInterval(lower: lower, upper: upper)
        }
    }

    static func split(
        intervals: [RichAnswerMathInterval],
        at breakpoints: [Double],
        input: RichAnswerFunctionSamplingInput,
        diagnostics: inout [RichAnswerFunctionSamplingDiagnostic]
    ) -> [RichAnswerMathInterval] {
        let xGuard = Swift.max(
            input.displayRange.x.length / Swift.max(input.viewport.widthPixels, 1) * 0.75,
            input.displayRange.x.length * 1.0e-12
        )
        var result: [RichAnswerMathInterval] = []
        for interval in intervals {
            var start = interval.lower
            for breakpoint in breakpoints where breakpoint > interval.lower && breakpoint < interval.upper {
                let leftUpper = breakpoint - xGuard
                if leftUpper > start {
                    result.append(RichAnswerMathInterval(lower: start, upper: leftUpper))
                }
                record(.discontinuityCut, "Function path cut at a detected undefined or asymptotic x value.", x: breakpoint, diagnostics: &diagnostics)
                start = breakpoint + xGuard
            }
            if interval.upper > start {
                result.append(RichAnswerMathInterval(lower: start, upper: interval.upper))
            }
        }
        return result
    }

    static func discontinuityBreakpoints(
        expression: RichAnswerMathExpression,
        independentVariable: String,
        parameters: [String: Double],
        intervals: [RichAnswerMathInterval],
        input: RichAnswerFunctionSamplingInput,
        limits: RichAnswerMathSafetyLimits
    ) -> [Double] {
        let probes = expression.singularityProbes()
        guard !probes.isEmpty else {
            return []
        }
        var roots: [Double] = []
        for probe in probes {
            for interval in intervals {
                roots.append(contentsOf: scanRoots(
                    probe: probe,
                    independentVariable: independentVariable,
                    parameters: parameters,
                    interval: interval,
                    input: input,
                    limits: limits
                ))
            }
        }
        return uniquedSorted(roots, tolerance: Swift.max(limits.rootTolerance, input.displayRange.x.length * 1.0e-10))
    }

    static func scanRoots(
        probe: RichAnswerMathExpression,
        independentVariable: String,
        parameters: [String: Double],
        interval: RichAnswerMathInterval,
        input: RichAnswerFunctionSamplingInput,
        limits: RichAnswerMathSafetyLimits
    ) -> [Double] {
        let steps = Swift.max(
            16,
            Swift.min(
                input.discontinuityScanSteps,
                Int(ceil(screenWidth(from: interval.lower, to: interval.upper, input: input) * 2))
            )
        )
        var roots: [Double] = []
        var previousX: Double?
        var previousValue: Double?
        for index in 0...steps {
            let x = interval.lower + interval.length * Double(index) / Double(steps)
            guard let value = try? probe.evaluated(
                in: RichAnswerMathEvaluationContext(
                    variables: [independentVariable: x],
                    parameters: parameters
                ),
                limits: limits
            ), value.isFinite else {
                previousX = nil
                previousValue = nil
                continue
            }
            if abs(value) <= Swift.max(limits.rootTolerance, 1.0e-10) {
                roots.append(x)
            }
            if let leftX = previousX,
               let leftValue = previousValue,
               leftValue.sign != value.sign,
               let root = bisectRoot(
                   probe: probe,
                   independentVariable: independentVariable,
                   parameters: parameters,
                   lower: leftX,
                   upper: x,
                   limits: limits
               ) {
                roots.append(root)
            }
            previousX = x
            previousValue = value
        }
        return roots
    }

    static func bisectRoot(
        probe: RichAnswerMathExpression,
        independentVariable: String,
        parameters: [String: Double],
        lower: Double,
        upper: Double,
        limits: RichAnswerMathSafetyLimits
    ) -> Double? {
        var a = lower
        var b = upper
        guard var fa = try? probe.evaluated(
            in: RichAnswerMathEvaluationContext(variables: [independentVariable: a], parameters: parameters),
            limits: limits
        ), fa.isFinite else {
            return nil
        }
        for _ in 0..<64 {
            let middle = a + (b - a) / 2
            guard let fm = try? probe.evaluated(
                in: RichAnswerMathEvaluationContext(variables: [independentVariable: middle], parameters: parameters),
                limits: limits
            ), fm.isFinite else {
                return middle
            }
            if abs(fm) <= limits.rootTolerance || abs(b - a) <= limits.rootTolerance {
                return middle
            }
            if fa.sign == fm.sign {
                a = middle
                fa = fm
            } else {
                b = middle
            }
        }
        return a + (b - a) / 2
    }

    static func merge(
        _ left: [RichAnswerFunctionPolylineSegment],
        _ right: [RichAnswerFunctionPolylineSegment]
    ) -> [RichAnswerFunctionPolylineSegment] {
        guard var last = left.last,
              let first = right.first,
              let lastPoint = last.points.last,
              let firstPoint = first.points.first,
              approximatelySameSample(lastPoint, firstPoint) else {
            return left + right
        }
        last.points.append(contentsOf: first.points.dropFirst())
        return left.dropLast() + [last] + right.dropFirst()
    }

    static func screenPoint(x: Double, y: Double, input: RichAnswerFunctionSamplingInput) -> RichAnswerFunctionSamplePoint {
        let screenX = (x - input.displayRange.x.lower) / input.displayRange.x.length * input.viewport.widthPixels
        let screenY = (input.displayRange.y.upper - y) / input.displayRange.y.length * input.viewport.heightPixels
        return RichAnswerFunctionSamplePoint(x: x, y: y, screenX: screenX, screenY: screenY)
    }

    static func screenWidth(from lower: Double, to upper: Double, input: RichAnswerFunctionSamplingInput) -> Double {
        abs(upper - lower) / input.displayRange.x.length * input.viewport.widthPixels
    }

    static func midpointScreenError(
        start: RichAnswerFunctionSamplePoint,
        midpoint: RichAnswerFunctionSamplePoint,
        end: RichAnswerFunctionSamplePoint
    ) -> Double {
        let expectedX = (start.screenX + end.screenX) / 2
        let expectedY = (start.screenY + end.screenY) / 2
        let dx = midpoint.screenX - expectedX
        let dy = midpoint.screenY - expectedY
        return sqrt(dx * dx + dy * dy)
    }

    static func approximatelySameSample(
        _ left: RichAnswerFunctionSamplePoint,
        _ right: RichAnswerFunctionSamplePoint
    ) -> Bool {
        abs(left.x - right.x) <= 1.0e-10 &&
            abs(left.y - right.y) <= 1.0e-8
    }

    static func uniquedSorted(_ values: [Double], tolerance: Double) -> [Double] {
        var result: [Double] = []
        for value in values.sorted() where value.isFinite {
            if let last = result.last, abs(last - value) <= tolerance {
                continue
            }
            result.append(value)
        }
        return result
    }

    static func record(
        _ code: RichAnswerFunctionSamplingDiagnosticCode,
        _ message: String,
        x: Double?,
        diagnostics: inout [RichAnswerFunctionSamplingDiagnostic]
    ) {
        guard diagnostics.count < 80 else {
            return
        }
        diagnostics.append(RichAnswerFunctionSamplingDiagnostic(code: code, message: message, x: x))
    }

    static func isValidIdentifier(_ name: String) -> Bool {
        RichAnswerMathExpression.isValidIdentifier(name)
    }
}

private extension RichAnswerMathExpression {
    func validate(
        allowedVariables: Set<String>,
        allowedParameters: Set<String>,
        limits: RichAnswerMathSafetyLimits,
        depth: Int,
        nodeCount: inout Int
    ) throws {
        guard depth <= limits.maximumDepth else {
            throw RichAnswerMathExpressionValidationError.depthExceeded(depth)
        }
        nodeCount += 1
        guard nodeCount <= limits.maximumNodeCount else {
            throw RichAnswerMathExpressionValidationError.nodeCountExceeded(nodeCount)
        }
        switch self {
        case .constant(let value):
            guard value.isFinite else {
                throw RichAnswerMathExpressionValidationError.nonFiniteConstant(value)
            }
            guard abs(value) <= limits.maximumMagnitude else {
                throw RichAnswerMathExpressionValidationError.magnitudeExceeded(value)
            }
        case .variable(let name):
            guard Self.isValidIdentifier(name) else {
                throw RichAnswerMathExpressionValidationError.invalidIdentifier(name)
            }
            guard allowedVariables.contains(name) else {
                throw RichAnswerMathExpressionValidationError.unknownVariable(name)
            }
        case .parameter(let name):
            guard Self.isValidIdentifier(name) else {
                throw RichAnswerMathExpressionValidationError.invalidIdentifier(name)
            }
            guard allowedParameters.contains(name) else {
                throw RichAnswerMathExpressionValidationError.unknownParameter(name)
            }
        case .unary(_, let expression):
            try expression.validate(
                allowedVariables: allowedVariables,
                allowedParameters: allowedParameters,
                limits: limits,
                depth: depth + 1,
                nodeCount: &nodeCount
            )
        case .binary(_, let left, let right):
            try left.validate(
                allowedVariables: allowedVariables,
                allowedParameters: allowedParameters,
                limits: limits,
                depth: depth + 1,
                nodeCount: &nodeCount
            )
            try right.validate(
                allowedVariables: allowedVariables,
                allowedParameters: allowedParameters,
                limits: limits,
                depth: depth + 1,
                nodeCount: &nodeCount
            )
        case .call(let function, let arguments):
            guard function.acceptsArity(arguments.count) else {
                throw RichAnswerMathExpressionValidationError.invalidArity(function: function, received: arguments.count)
            }
            for argument in arguments {
                try argument.validate(
                    allowedVariables: allowedVariables,
                    allowedParameters: allowedParameters,
                    limits: limits,
                    depth: depth + 1,
                    nodeCount: &nodeCount
                )
            }
        }
    }

    func evaluated(
        in context: RichAnswerMathEvaluationContext,
        limits: RichAnswerMathSafetyLimits,
        depth: Int
    ) throws -> Double {
        guard depth <= limits.maximumDepth else {
            throw RichAnswerMathEvaluationError.domain("expression depth exceeded")
        }
        let value: Double
        switch self {
        case .constant(let constant):
            value = constant
        case .variable(let name):
            guard let variable = context.variables[name] else {
                throw RichAnswerMathEvaluationError.missingVariable(name)
            }
            value = variable
        case .parameter(let name):
            guard let parameter = context.parameters[name] else {
                throw RichAnswerMathEvaluationError.missingParameter(name)
            }
            value = parameter
        case .unary(let operation, let expression):
            let operand = try expression.evaluated(in: context, limits: limits, depth: depth + 1)
            switch operation {
            case .positive:
                value = operand
            case .negative:
                value = -operand
            }
        case .binary(let operation, let leftExpression, let rightExpression):
            let left = try leftExpression.evaluated(in: context, limits: limits, depth: depth + 1)
            let right = try rightExpression.evaluated(in: context, limits: limits, depth: depth + 1)
            value = try Self.evaluateBinary(operation, left, right, limits: limits)
        case .call(let function, let arguments):
            let values = try arguments.map { expression in
                try expression.evaluated(in: context, limits: limits, depth: depth + 1)
            }
            value = try Self.evaluateFunction(function, values, limits: limits)
        }
        return try Self.checked(value, limits: limits)
    }

    func singularityProbes() -> [RichAnswerMathExpression] {
        switch self {
        case .constant, .variable, .parameter:
            return []
        case .unary(_, let expression):
            return expression.singularityProbes()
        case .binary(let operation, let left, let right):
            var probes = left.singularityProbes() + right.singularityProbes()
            if operation == .divide {
                probes.append(right)
            }
            if operation == .power {
                probes.append(left)
            }
            return probes
        case .call(let function, let arguments):
            var probes = arguments.flatMap { $0.singularityProbes() }
            guard let first = arguments.first else {
                return probes
            }
            switch function {
            case .tan:
                probes.append(.call(.cos, [first]))
            case .log, .log10, .sqrt:
                probes.append(first)
            case .asin, .acos:
                probes.append(.binary(.subtract, first, .constant(1)))
                probes.append(.binary(.add, first, .constant(1)))
            case .abs, .exp, .sin, .cos, .atan, .floor, .ceil, .round, .min, .max, .pow:
                break
            }
            return probes
        }
    }

    static func isValidIdentifier(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first,
              name.unicodeScalars.count <= 64,
              (first == "_" || CharacterSet.letters.contains(first)) else {
            return false
        }
        return name.unicodeScalars.dropFirst().allSatisfy { scalar in
            scalar == "_" ||
                CharacterSet.letters.contains(scalar) ||
                CharacterSet.decimalDigits.contains(scalar)
        }
    }

    static func evaluateBinary(
        _ operation: RichAnswerMathBinaryOperator,
        _ left: Double,
        _ right: Double,
        limits: RichAnswerMathSafetyLimits
    ) throws -> Double {
        switch operation {
        case .add:
            return left + right
        case .subtract:
            return left - right
        case .multiply:
            return left * right
        case .divide:
            guard abs(right) > limits.zeroTolerance else {
                throw RichAnswerMathEvaluationError.domain("division by zero")
            }
            return left / right
        case .power:
            if left < 0, !isInteger(right, tolerance: limits.zeroTolerance) {
                throw RichAnswerMathEvaluationError.domain("negative base with non-integer exponent")
            }
            return pow(left, right)
        }
    }

    static func evaluateFunction(
        _ function: RichAnswerMathFunction,
        _ values: [Double],
        limits: RichAnswerMathSafetyLimits
    ) throws -> Double {
        guard function.acceptsArity(values.count) else {
            throw RichAnswerMathEvaluationError.domain("invalid function arity")
        }
        switch function {
        case .abs:
            return abs(values[0])
        case .sqrt:
            guard values[0] >= -limits.zeroTolerance else {
                throw RichAnswerMathEvaluationError.domain("sqrt input is negative")
            }
            return sqrt(Swift.max(0, values[0]))
        case .exp:
            return exp(values[0])
        case .log:
            guard values[0] > 0 else {
                throw RichAnswerMathEvaluationError.domain("log input must be positive")
            }
            return log(values[0])
        case .log10:
            guard values[0] > 0 else {
                throw RichAnswerMathEvaluationError.domain("log10 input must be positive")
            }
            return log10(values[0])
        case .sin:
            return sin(values[0])
        case .cos:
            return cos(values[0])
        case .tan:
            guard abs(cos(values[0])) > limits.zeroTolerance else {
                throw RichAnswerMathEvaluationError.domain("tan is undefined at this input")
            }
            return tan(values[0])
        case .asin:
            guard values[0] >= -1 - limits.zeroTolerance,
                  values[0] <= 1 + limits.zeroTolerance else {
                throw RichAnswerMathEvaluationError.domain("asin input must be in [-1, 1]")
            }
            return asin(Swift.max(-1, Swift.min(1, values[0])))
        case .acos:
            guard values[0] >= -1 - limits.zeroTolerance,
                  values[0] <= 1 + limits.zeroTolerance else {
                throw RichAnswerMathEvaluationError.domain("acos input must be in [-1, 1]")
            }
            return acos(Swift.max(-1, Swift.min(1, values[0])))
        case .atan:
            return atan(values[0])
        case .floor:
            return floor(values[0])
        case .ceil:
            return ceil(values[0])
        case .round:
            return values[0].rounded()
        case .min:
            return Swift.min(values[0], values[1])
        case .max:
            return Swift.max(values[0], values[1])
        case .pow:
            return try evaluateBinary(.power, values[0], values[1], limits: limits)
        }
    }

    static func checked(_ value: Double, limits: RichAnswerMathSafetyLimits) throws -> Double {
        guard value.isFinite else {
            throw RichAnswerMathEvaluationError.nonFiniteValue
        }
        guard abs(value) <= limits.maximumMagnitude else {
            throw RichAnswerMathEvaluationError.magnitudeExceeded(value)
        }
        return value
    }

    static func isInteger(_ value: Double, tolerance: Double) -> Bool {
        abs(value.rounded() - value) <= tolerance
    }
}
