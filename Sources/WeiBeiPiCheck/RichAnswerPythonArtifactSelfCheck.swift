import Foundation
import WeiBeiCore

public enum RichAnswerPythonArtifactSelfCheckError: Error, Equatable, CustomStringConvertible, Sendable {
    case failed(String)

    public var description: String {
        switch self {
        case let .failed(message):
            return message
        }
    }
}

public enum RichAnswerPythonArtifactSelfCheck {
    public static func runStaticChecks() throws {
        let request = sampleRequest()
        _ = try RichAnswerPythonArtifactPipeline.validate(request)

        let encoded = try JSONEncoder().encode(request)
        let decoded = try RichAnswerPythonArtifactPipeline.decodeRequestStrict(from: encoded)
        try require(decoded.operation == .sampleFunction, "strict decoder did not preserve operation")

        let customScript = """
        {
          "id": "unsafe-script",
          "operation": "sample_function",
          "inputs": [],
          "requestedOutputs": [],
          "sourceBindings": [],
          "pythonCode": "print(1)"
        }
        """.data(using: .utf8)!
        try requireThrows(
            try RichAnswerPythonArtifactPipeline.decodeRequestStrict(from: customScript),
            "strict decoder accepted a pythonCode root field"
        )

        let unsupportedOperation = """
        {
          "id": "unsafe-operation",
          "operation": "custom_python",
          "inputs": [],
          "requestedOutputs": [],
          "sourceBindings": []
        }
        """.data(using: .utf8)!
        try requireThrows(
            try RichAnswerPythonArtifactPipeline.decodeRequestStrict(from: unsupportedOperation),
            "decoder accepted a non-whitelisted operation"
        )

        var noSource = request
        noSource.sourceBindings = []
        for index in noSource.inputs.indices {
            noSource.inputs[index].sourceBindingID = nil
        }
        _ = try RichAnswerPythonArtifactPipeline.validate(noSource)

        var danglingSource = request
        danglingSource.inputs[0].sourceBindingID = "missing-source"
        try requireThrows(
            try RichAnswerPythonArtifactPipeline.validate(danglingSource),
            "validator accepted an input with a missing source binding"
        )

        var fileAccess = request
        fileAccess.limits = RichAnswerPythonArtifactLimits(allowFilesystem: true)
        try requireThrows(
            try RichAnswerPythonArtifactPipeline.validate(fileAccess),
            "validator accepted arbitrary filesystem access"
        )

        var networkAccess = request
        networkAccess.limits = RichAnswerPythonArtifactLimits(allowNetwork: true)
        try requireThrows(
            try RichAnswerPythonArtifactPipeline.validate(networkAccess),
            "validator accepted network access"
        )

        let unsafeImage = RichAnswerPythonArtifactRequest(
            id: "unsafe-image",
            operation: .imageMeasurementOverlay,
            inputs: [
                RichAnswerPythonArtifactInput(
                    id: "image",
                    role: "asset",
                    payload: .imageRef(RichAnswerPythonArtifactImageRef(assetID: "../secret.png")),
                    sourceBindingID: "source-1"
                ),
            ],
            requestedOutputs: [
                RichAnswerPythonArtifactOutputRequest(
                    id: "overlay",
                    kind: .imageOverlaySpec,
                    mimeType: "application/json",
                    role: "overlay"
                ),
            ],
            sourceBindings: sampleSourceBindings(target: "image")
        )
        try requireThrows(
            try RichAnswerPythonArtifactPipeline.validate(unsafeImage),
            "validator accepted path-like image asset ID"
        )

        var sourceFreeImage = unsafeImage
        sourceFreeImage.inputs[0].payload = .imageRef(
            RichAnswerPythonArtifactImageRef(assetID: "material-image")
        )
        sourceFreeImage.inputs[0].sourceBindingID = nil
        sourceFreeImage.sourceBindings = []
        try requireThrows(
            try RichAnswerPythonArtifactPipeline.validate(sourceFreeImage),
            "validator accepted an image input without a real source binding"
        )
    }

    public static func runExecutorChecks() async throws {
        let request = sampleRequest()
        let executor = RichAnswerPythonArtifactExecutor { validated in
            let artifact = try RichAnswerPythonArtifactProduced(
                id: "sample-output",
                kind: .jsonSpec,
                mimeType: "application/json",
                role: "function-samples",
                payload: .json(
                    .object([
                        "x": .array([.number(-1), .number(0), .number(1)]),
                        "y": .array([.number(1), .number(0), .number(1)]),
                    ])
                ),
                sourceBindings: validated.request.sourceBindings
            )
            return RichAnswerPythonArtifactExecutionResult(
                requestID: validated.request.id,
                operation: validated.request.operation,
                artifacts: [artifact]
            )
        }

        let result = try await RichAnswerPythonArtifactPipeline.execute(
            request: request,
            executor: executor
        )
        try require(result.artifacts.count == 1, "executor did not produce one artifact")
        try require(result.artifacts[0].sha256.count == 64, "artifact sha256 was not recorded")
        try require(!result.artifacts[0].sourceBindings.isEmpty, "artifact did not retain source binding")

        let droppedSourceExecutor = RichAnswerPythonArtifactExecutor { validated in
            let artifact = try RichAnswerPythonArtifactProduced(
                id: "sample-output",
                kind: .jsonSpec,
                mimeType: "application/json",
                role: "function-samples",
                payload: .json(.object(["x": .array([.number(0)])])),
                sourceBindings: []
            )
            return RichAnswerPythonArtifactExecutionResult(
                requestID: validated.request.id,
                operation: validated.request.operation,
                artifacts: [artifact]
            )
        }
        try await requireThrowsAsync(
            try await RichAnswerPythonArtifactPipeline.execute(
                request: request,
                executor: droppedSourceExecutor
            ),
            "pipeline accepted an artifact that dropped validated source bindings"
        )

        var noSourceRequest = request
        noSourceRequest.sourceBindings = []
        for index in noSourceRequest.inputs.indices {
            noSourceRequest.inputs[index].sourceBindingID = nil
        }
        let noSourceResult = try await RichAnswerPythonArtifactPipeline.execute(
            request: noSourceRequest,
            executor: executor
        )
        try require(
            noSourceResult.artifacts.first?.sourceBindings.isEmpty == true,
            "deterministic artifact without course material was rejected"
        )

        let oversizedExecutor = RichAnswerPythonArtifactExecutor { validated in
            let data = Data(repeating: 7, count: validated.effectiveLimits.maxOutputBytes + 1)
            let artifact = try RichAnswerPythonArtifactProduced(
                id: "oversized-output",
                kind: .staticPNG,
                mimeType: "image/png",
                role: "oversized",
                payload: .bytes(data),
                sourceBindings: validated.request.sourceBindings
            )
            return RichAnswerPythonArtifactExecutionResult(
                requestID: validated.request.id,
                operation: validated.request.operation,
                artifacts: [artifact]
            )
        }
        try await requireThrowsAsync(
            try await RichAnswerPythonArtifactPipeline.execute(request: request, executor: oversizedExecutor),
            "pipeline accepted an oversized artifact"
        )

        var tightTimeout = request
        tightTimeout.limits = RichAnswerPythonArtifactLimits(maxRuntimeMS: 1)
        let slowExecutor = RichAnswerPythonArtifactExecutor { validated in
            try await Task.sleep(nanoseconds: 50_000_000)
            return RichAnswerPythonArtifactExecutionResult(
                requestID: validated.request.id,
                operation: validated.request.operation,
                artifacts: []
            )
        }
        try await requireThrowsAsync(
            try await RichAnswerPythonArtifactPipeline.execute(request: tightTimeout, executor: slowExecutor),
            "pipeline did not enforce executor timeout"
        )
    }

    public static func sampleRequest() -> RichAnswerPythonArtifactRequest {
        RichAnswerPythonArtifactRequest(
            id: "sample-function-request",
            operation: .sampleFunction,
            inputs: [
                RichAnswerPythonArtifactInput(
                    id: "expression",
                    role: "function",
                    payload: .expression(
                        .binary(
                            .multiply,
                            .variable("x"),
                            .variable("x")
                        )
                    ),
                    sourceBindingID: "source-1"
                ),
                RichAnswerPythonArtifactInput(
                    id: "domain",
                    role: "range",
                    payload: .numberSeries([-1, 0, 1]),
                    sourceBindingID: "source-1"
                ),
            ],
            parameters: [
                "samples": .number(3),
            ],
            requestedOutputs: [
                RichAnswerPythonArtifactOutputRequest(
                    id: "sample-output",
                    kind: .jsonSpec,
                    mimeType: "application/json",
                    role: "function-samples"
                ),
            ],
            sourceBindings: sampleSourceBindings(target: "expression")
        )
    }

    private static func sampleSourceBindings(target: String) -> [RichAnswerPythonArtifactSourceBinding] {
        [
            RichAnswerPythonArtifactSourceBinding(
                id: "source-1",
                evidenceID: "evidence:function",
                target: target,
                role: .formula
            ),
        ]
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw RichAnswerPythonArtifactSelfCheckError.failed(message)
        }
    }

    private static func requireThrows<T>(_ operation: @autoclosure () throws -> T, _ message: String) throws {
        do {
            _ = try operation()
        } catch {
            return
        }
        throw RichAnswerPythonArtifactSelfCheckError.failed(message)
    }

    private static func requireThrowsAsync<T>(_ operation: @autoclosure () async throws -> T, _ message: String) async throws {
        do {
            _ = try await operation()
        } catch {
            return
        }
        throw RichAnswerPythonArtifactSelfCheckError.failed(message)
    }
}
