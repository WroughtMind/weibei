import Foundation
import XCTest
@testable import WeiBeiDevCore

final class DevelopmentWorkflowTests: XCTestCase {
    /// 验证裸 verify 只选择离线学习场景。
    func testVerificationSelectionDefaultsToOfflineLearning() throws {
        let scenarios = try VerificationScenarioRegistry().scenarios(
            for: DevelopmentVerificationOptions(
                scenario: nil,
                allScenarios: false,
                includeLivePI: false,
                visual: false,
                failFast: false
            )
        )

        XCTAssertEqual(scenarios.map(\.id), [.offlineLearningFlow])
    }

    /// 验证显式场景不会连带运行默认或其他视觉场景。
    func testVerificationSelectionRunsOnlyNamedScenario() throws {
        let scenarios = try VerificationScenarioRegistry().scenarios(
            for: DevelopmentVerificationOptions(
                scenario: VerificationScenarioID.richAnswerOpenUIExtendedInline.rawValue,
                allScenarios: false,
                includeLivePI: false,
                visual: false,
                failFast: false
            )
        )

        XCTAssertEqual(scenarios.map(\.id), [.richAnswerOpenUIExtendedInline])
    }

    /// 验证显式完整套件包含离线场景，并按许可控制在线 PI。
    func testVerificationSelectionAllControlsLivePI() throws {
        let registry = VerificationScenarioRegistry()
        let offlineScenarios = try registry.scenarios(
            for: DevelopmentVerificationOptions(
                scenario: nil,
                allScenarios: true,
                includeLivePI: false,
                visual: false,
                failFast: false
            )
        )
        let liveScenarios = try registry.scenarios(
            for: DevelopmentVerificationOptions(
                scenario: nil,
                allScenarios: true,
                includeLivePI: true,
                visual: false,
                failFast: false
            )
        )

        XCTAssertFalse(offlineScenarios.contains { $0.requirements.requiresOnlinePI })
        XCTAssertEqual(liveScenarios.map(\.id), registry.scenarios.map(\.id))
    }

    /// 验证已有活跃租约时拒绝并发生命周期操作。
    func testLifecycleLeaseRejectsConcurrentOperation() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("weibei-lifecycle-\(UUID().uuidString)", isDirectory: true)
        let lockURL = temporaryDirectory.appendingPathComponent("lifecycle.lock", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let lease = try DevelopmentLifecycleLease.acquire(at: lockURL)
        defer { lease.release() }

        do {
            _ = try DevelopmentLifecycleLease.acquire(at: lockURL)
            XCTFail("Expected DevelopmentLifecycleLease.acquire to throw")
        } catch {
            let workflowError = try XCTUnwrap(error as? DevelopmentWorkflowError)
            XCTAssertTrue(workflowError.errorCode == "lifecycle_busy")
        }
    }

    /// 验证主动释放租约后可以重新获取同一生命周期锁。
    func testLifecycleLeaseCanBeReacquiredAfterRelease() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("weibei-lifecycle-\(UUID().uuidString)", isDirectory: true)
        let lockURL = temporaryDirectory.appendingPathComponent("lifecycle.lock", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let firstLease = try DevelopmentLifecycleLease.acquire(at: lockURL)
        firstLease.release()
        let secondLease = try DevelopmentLifecycleLease.acquire(at: lockURL)
        secondLease.release()

        XCTAssertTrue(FileManager.default.fileExists(atPath: lockURL.path))
    }

    /// 验证租约文件保留时，内核锁释放后仍可由当前进程重新获取。
    func testLifecycleLeaseIgnoresUnlockedDiagnosticFile() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("weibei-lifecycle-\(UUID().uuidString)", isDirectory: true)
        let lockURL = temporaryDirectory.appendingPathComponent("lifecycle.lock", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        try Data("\(Int32.max)\n".utf8).write(to: lockURL)

        let lease = try DevelopmentLifecycleLease.acquire(at: lockURL)
        let ownerPID = try String(
            contentsOf: lockURL,
            encoding: .utf8
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(ownerPID == "\(ProcessInfo.processInfo.processIdentifier)")

        lease.release()
        XCTAssertTrue(FileManager.default.fileExists(atPath: lockURL.path))
    }
}
