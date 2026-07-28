import Foundation
import XCTest
@testable import WeiBeiDevCore

final class ProcessExecutionTests: XCTestCase {
    /// Verifies `.inherit` leaves PATH available to executables that launch child tools.
    func testInheritedEnvironmentPreservesPathLookupForChildTools() async throws {
        let result = try await FoundationProcessExecutor().execute(
            ProcessExecutionRequest(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: ["true"],
                environment: .inherit
            )
        )

        XCTAssertTrue(result.succeeded)
    }

    /// Verifies normal completion and independent stdout/stderr capture.
    func testSuccessfulProcessCapturesOutput() async throws {
        let result = try await FoundationProcessExecutor().execute(
            ProcessExecutionRequest(
                executableURL: URL(fileURLWithPath: "/usr/bin/printf"),
                arguments: ["hello"]
            )
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertTrue(result.termination == .exited(code: 0))
        XCTAssertTrue(result.exitCode == 0)
        XCTAssertTrue(result.standardOutput?.stringUTF8 == "hello")
        XCTAssertTrue(result.standardOutput?.totalByteCount == 5)
        XCTAssertTrue(result.standardOutput?.isTruncated == false)
        XCTAssertTrue(result.standardError?.stringUTF8 == "")
    }

    /// Verifies a nonzero status remains a structured result rather than a thrown error.
    func testNonzeroExitIsStructuredResult() async throws {
        let result = try await FoundationProcessExecutor().execute(
            ProcessExecutionRequest(executableURL: URL(fileURLWithPath: "/usr/bin/false"))
        )

        XCTAssertTrue(!result.succeeded)
        XCTAssertTrue(result.termination == .exited(code: 1))
        XCTAssertTrue(result.exitCode == 1)
    }

    /// Verifies timeout terminates the child and is distinguishable from a signal.
    func testTimeoutReturnsTimedOutResult() async throws {
        let result = try await FoundationProcessExecutor().execute(
            ProcessExecutionRequest(
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["5"],
                timeout: .milliseconds(50),
                terminationGracePeriod: .milliseconds(50)
            )
        )

        XCTAssertTrue(!result.succeeded)
        XCTAssertTrue(result.termination == .timedOut)
        XCTAssertTrue(result.exitCode == nil)
        XCTAssertTrue(result.duration < .seconds(2))
    }

    /// Verifies cancelling the awaiting task terminates the child with a structured result.
    func testCancellationReturnsCancelledResult() async throws {
        let execution = Task {
            try await FoundationProcessExecutor().execute(
                ProcessExecutionRequest(
                    executableURL: URL(fileURLWithPath: "/bin/sleep"),
                    arguments: ["5"],
                    terminationGracePeriod: .milliseconds(50)
                )
            )
        }
        try await Task.sleep(for: .milliseconds(50))
        execution.cancel()

        let result = try await execution.value
        XCTAssertTrue(!result.succeeded)
        XCTAssertTrue(result.termination == .cancelled)
        XCTAssertTrue(result.exitCode == nil)
        XCTAssertTrue(result.duration < .seconds(2))
    }

    /// Verifies capture limits bound retained memory while preserving total byte metadata.
    func testOutputCaptureLimitTruncatesRetainedPrefix() async throws {
        let result = try await FoundationProcessExecutor().execute(
            ProcessExecutionRequest(
                executableURL: URL(fileURLWithPath: "/usr/bin/printf"),
                arguments: ["0123456789"],
                standardOutput: .capture(limit: 4)
            )
        )

        XCTAssertTrue(result.standardOutput?.stringUTF8 == "0123")
        XCTAssertTrue(result.standardOutput?.data.count == 4)
        XCTAssertTrue(result.standardOutput?.totalByteCount == 10)
        XCTAssertTrue(result.standardOutput?.isTruncated == true)
    }
}
