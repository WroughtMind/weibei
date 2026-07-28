import ArgumentParser
import Foundation
import XCTest
@testable import WeiBeiDevTool

final class WeiBeiDevToolCommandTests: XCTestCase {
    /// 验证 run 的诊断模式会映射为类型化工作流请求。
    func testRunDebugBuildsTypedRequest() async throws {
        let workflow = RecordingWorkflow()
        let output = RecordingOutput()
        DevToolServices.install(workflow: workflow, output: output)
        defer { DevToolServices.reset() }
        var command = try RunCommand.parse(["--debug"])

        try await command.run()

        let requests = await workflow.requests
        XCTAssertTrue(requests == [.run(.debug)])
        XCTAssertTrue(output.standardOutput == ["完成"])
        XCTAssertTrue(output.standardError.isEmpty)
    }

    /// 验证 run 的互斥模式由参数校验拒绝。
    func testRunRejectsConflictingModes() throws {
        do {
            _ = try RunCommand.parse(["--debug", "--logs"])
            XCTFail("预期互斥运行模式被拒绝")
        } catch {
            XCTAssertTrue(String(describing: error).contains("不能同时使用"))
        }
    }

    /// 验证 verify 的全部场景和单场景选择不能同时出现。
    func testVerifyRejectsConflictingScenarioSelection() throws {
        do {
            _ = try VerifyCommand.parse(["--all", "--scenario", "offline-learning-flow"])
            XCTFail("预期冲突场景选择被拒绝")
        } catch {
            XCTAssertTrue(VerifyCommand.message(for: error).contains("不能同时使用"))
        }
    }

    /// 验证未知场景名称在 CLI 参数边界被拒绝。
    func testVerifyRejectsUnknownScenario() throws {
        do {
            _ = try VerifyCommand.parse(["--scenario", "not-registered"])
            XCTFail("预期未知场景被拒绝")
        } catch {
            XCTAssertTrue(VerifyCommand.message(for: error).contains("not-registered"))
        }
    }

    /// 验证 verify 的全部选项完整映射到核心模型。
    func testVerifyBuildsTypedOptions() async throws {
        let workflow = RecordingWorkflow()
        let output = RecordingOutput()
        DevToolServices.install(workflow: workflow, output: output)
        defer { DevToolServices.reset() }
        var command = try VerifyCommand.parse([
            "--scenario", "offline-learning-flow",
            "--visual",
            "--include-live-pi",
            "--fail-fast"
        ])

        try await command.run()

        let requests = await workflow.requests
        XCTAssertTrue(
            requests == [
                .verify(
                    VerificationOptions(
                        scenario: "offline-learning-flow",
                        runsAllScenarios: false,
                        includesLivePi: true,
                        performsVisualChecks: true,
                        failsFast: true
                    )
                )
            ]
        )
    }

    /// 验证 JSON 成功输出包含稳定命令名和详情。
    func testJSONSuccessOutput() async throws {
        let workflow = RecordingWorkflow(
            result: DevToolWorkflowResult(summary: "完成", details: ["artifact": "/tmp/app"])
        )
        let output = RecordingOutput()
        DevToolServices.install(workflow: workflow, output: output)
        defer { DevToolServices.reset() }
        var command = try PackageCommand.parse(["--format", "json"])

        try await command.run()

        let data = try XCTUnwrap(output.standardOutput.first?.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertTrue(object["success"] as? Bool == true)
        XCTAssertTrue(object["command"] as? String == "package")
        XCTAssertTrue(object["summary"] as? String == "完成")
    }

    /// 验证 JSON 失败输出使用核心错误的稳定代码。
    func testJSONFailureOutputUsesStableErrorCode() async throws {
        let workflow = RecordingWorkflow(
            error: DevToolExecutionError(errorCode: "pi_hash_mismatch", errorMessage: "哈希不匹配")
        )
        let output = RecordingOutput()
        DevToolServices.install(workflow: workflow, output: output)
        defer { DevToolServices.reset() }
        var command = try PreparePiRuntimeCommand.parse(["--format", "json"])

        do {
            try await command.run()
            XCTFail("预期命令失败")
        } catch let exitCode as ExitCode {
            XCTAssertTrue(exitCode == .failure)
        }

        let data = try XCTUnwrap(output.standardOutput.first?.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let error = try XCTUnwrap(object["error"] as? [String: Any])
        XCTAssertTrue(object["success"] as? Bool == false)
        XCTAssertTrue(error["code"] as? String == "pi_hash_mismatch")
        XCTAssertTrue(output.standardError.isEmpty)
    }

    /// 验证 path 输出仅写出供旧脚本消费的主要产物绝对路径。
    func testPathOutputWritesOnlyPrimaryPath() async throws {
        let workflow = RecordingWorkflow(
            result: DevToolWorkflowResult(
                summary: "完成",
                details: ["runtime": "/tmp/PiRuntime"],
                primaryPath: "/tmp/PiRuntime"
            )
        )
        let output = RecordingOutput()
        DevToolServices.install(workflow: workflow, output: output)
        defer { DevToolServices.reset() }
        var command = try PreparePiRuntimeCommand.parse(["--format", "path"])

        try await command.run()

        XCTAssertEqual(output.standardOutput, ["/tmp/PiRuntime"])
        XCTAssertTrue(output.standardError.isEmpty)
    }

    /// 验证没有主要产物的结果会拒绝 path 输出并返回稳定错误。
    func testPathOutputRejectsMissingPrimaryPath() async throws {
        let workflow = RecordingWorkflow(result: DevToolWorkflowResult(summary: "完成"))
        let output = RecordingOutput()
        DevToolServices.install(workflow: workflow, output: output)
        defer { DevToolServices.reset() }
        var command = try CheckCommand.parse(["--format", "path"])

        do {
            try await command.run()
            XCTFail("预期缺少主要产物路径时命令失败")
        } catch let exitCode as ExitCode {
            XCTAssertEqual(exitCode, .failure)
        }

        XCTAssertTrue(output.standardOutput.isEmpty)
        XCTAssertEqual(
            output.standardError,
            ["[path_output_unavailable] check 没有可输出的主要产物路径。"]
        )
    }
}

private actor RecordingWorkflow: WorkflowProviding {
    private(set) var requests: [DevToolCommandRequest] = []
    private let result: DevToolWorkflowResult
    private let error: Error?

    /// 创建可记录请求并返回固定结果或错误的工作流。
    init(
        result: DevToolWorkflowResult = DevToolWorkflowResult(summary: "完成"),
        error: Error? = nil
    ) {
        self.result = result
        self.error = error
    }

    /// 记录类型化请求并返回配置的 fixture 结果。
    func execute(_ request: DevToolCommandRequest) async throws -> DevToolWorkflowResult {
        requests.append(request)
        if let error {
            throw error
        }
        return result
    }
}

private final class RecordingOutput: DevToolOutputWriting, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var standardOutput: [String] = []
    private(set) var standardError: [String] = []

    /// 记录一行标准输出。
    func writeStandardOutput(_ line: String) {
        lock.lock()
        standardOutput.append(line)
        lock.unlock()
    }

    /// 记录一行标准错误。
    func writeStandardError(_ line: String) {
        lock.lock()
        standardError.append(line)
        lock.unlock()
    }
}
