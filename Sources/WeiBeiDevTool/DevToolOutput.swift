import ArgumentParser
import Foundation

/// CLI 支持的结果输出格式。
public enum DevToolOutputFormat: String, CaseIterable, ExpressibleByArgument, Sendable {
    case text
    case json
    case path
}

/// 可在各叶子命令复用的输出参数。
public struct DevToolOutputOptions: ParsableArguments {
    @Option(name: .long, help: "结果格式：text、json 或仅输出主要产物的 path。")
    public var format: DevToolOutputFormat = .text

    /// 创建默认文本输出参数。
    public init() {}
}

private struct SuccessEnvelope: Encodable {
    let success = true
    let command: String
    let summary: String
    let details: [String: String]
}

private struct FailureEnvelope: Encodable {
    let success = false
    let command: String
    let error: ErrorBody

    struct ErrorBody: Encodable {
        let code: String
        let message: String
    }
}

/// 执行核心工作流并按照稳定的 CLI 契约渲染结果。
///
/// - Parameters:
///   - request: 已完成参数校验的类型化命令请求
///   - format: 用户选择的输出格式
public func executeDevToolRequest(
    _ request: DevToolCommandRequest,
    format: DevToolOutputFormat
) async throws {
    let services = DevToolServices.snapshot()

    do {
        let result = try await services.workflow.execute(request)
        switch format {
        case .text:
            services.output.writeStandardOutput(result.summary)
            for key in result.details.keys.sorted() {
                if let value = result.details[key] {
                    services.output.writeStandardOutput("\(key): \(value)")
                }
            }
        case .json:
            services.output.writeStandardOutput(
                try encodeJSON(
                    SuccessEnvelope(
                        command: request.commandName,
                        summary: result.summary,
                        details: result.details
                    )
                )
            )
        case .path:
            guard let primaryPath = result.primaryPath else {
                throw DevToolExecutionError(
                    errorCode: "path_output_unavailable",
                    errorMessage: "\(request.commandName) 没有可输出的主要产物路径。"
                )
            }
            services.output.writeStandardOutput(primaryPath)
        }
    } catch {
        let codedError = error as? any DevToolCodedError
        let code = codedError?.errorCode ?? "execution_failed"
        let message = codedError?.errorMessage ?? String(describing: error)

        switch format {
        case .text:
            services.output.writeStandardError("[\(code)] \(message)")
        case .json:
            services.output.writeStandardOutput(
                try encodeJSON(
                    FailureEnvelope(
                        command: request.commandName,
                        error: .init(code: code, message: message)
                    )
                )
            )
        case .path:
            services.output.writeStandardError("[\(code)] \(message)")
        }
        throw ExitCode.failure
    }
}

/// Encodes one stable output envelope as a sorted single-line JSON document.
private func encodeJSON<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(value)
    guard let json = String(data: data, encoding: .utf8) else {
        throw DevToolExecutionError(
            errorCode: "json_encoding_failed",
            errorMessage: "无法将命令结果编码为 UTF-8 JSON。"
        )
    }
    return json
}
