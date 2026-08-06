import Dispatch
import Foundation

/// Lightweight P0 performance probes. Enabled only when `WEIBEI_PERF=1`.
/// Every enabled sample is logged so raw evidence can be used to recompute p95.
enum WeiBeiPerf {
    struct Span: Sendable {
        fileprivate let name: String
        fileprivate let sampleID: UUID
        fileprivate let startedAtNanoseconds: UInt64
    }

    static let isEnabled =
        ProcessInfo.processInfo.environment["WEIBEI_PERF"] == "1"

    static var scenarioID: String {
        let environment = ProcessInfo.processInfo.environment
        let raw = environment["WEIBEI_PERF_SCENARIO"]
            ?? "manual"
        return token(raw)
    }

    @MainActor private static var launchSpan: Span?

    @MainActor
    static func beginLaunch() {
        launchSpan = begin("app.restore_to_next_main_queue_proxy")
    }

    @MainActor
    static func finishLaunch() {
        guard let launchSpan else { return }
        self.launchSpan = nil
        end(
            launchSpan,
            extra: "outcome=completed endpoint=next_main_queue_proxy"
        )
    }

    static func begin(_ name: String) -> Span? {
        guard isEnabled else { return nil }
        return Span(
            name: name,
            sampleID: UUID(),
            startedAtNanoseconds: DispatchTime.now().uptimeNanoseconds
        )
    }

    static func end(_ span: Span?, extra: String = "") {
        guard let span else { return }
        let elapsed = DispatchTime.now().uptimeNanoseconds
            &- span.startedAtNanoseconds
        emit(
            span.name,
            sampleID: span.sampleID,
            ms: Double(elapsed) / 1_000_000,
            extra: extra
        )
    }

    @discardableResult
    static func measure<T>(
        _ name: String,
        extra: String = "",
        _ body: () throws -> T
    ) rethrows -> T {
        guard isEnabled else { return try body() }
        let span = begin(name)
        let value = try body()
        end(span, extra: extra)
        return value
    }

    static func event(_ name: String, extra: String = "") {
        guard isEnabled else { return }
        emit(name, sampleID: UUID(), ms: 0, extra: extra)
    }

    static func log(
        _ name: String,
        ms: Double,
        extra: String = ""
    ) {
        guard isEnabled else { return }
        emit(name, sampleID: UUID(), ms: ms, extra: extra)
    }

    private static func emit(
        _ name: String,
        sampleID: UUID,
        ms: Double,
        extra: String
    ) {
        let suffix = extra.isEmpty ? "" : " \(extra)"
        let line = String(
            format:
                "[PERF-weibei-2] scenario=%@ sample=%@ name=%@ ms=%.3f main=%d%@\n",
            scenarioID,
            sampleID.uuidString.lowercased(),
            token(name),
            ms,
            Thread.isMainThread ? 1 : 0,
            suffix
        )
        fputs(line, stderr)
        fflush(stderr)
    }

    private static func token(_ raw: String) -> String {
        let scalars = raw.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar)
                || "-._".unicodeScalars.contains(scalar)
                ? Character(scalar)
                : "_"
        }
        let value = String(scalars)
        return value.isEmpty ? "unknown" : value
    }
}
