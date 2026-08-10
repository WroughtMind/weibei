import Dispatch
import Foundation
import os

/// Lightweight performance probes.
///
/// - Always available via `measure` / `begin` / `end`.
/// - Full stderr sample lines when `WEIBEI_PERF=1`.
/// - DEBUG builds always record duration and emit `os_log` faults when a
///   sample exceeds its budget or when a named probe fires too often.
enum WeiBeiPerf {
    struct Span: Sendable {
        fileprivate let name: String
        fileprivate let sampleID: UUID
        fileprivate let startedAtNanoseconds: UInt64
    }

    /// Named budgets (milliseconds). Used for DEBUG faulting after S2 simplified
    /// the note write path; workspace.save is still full JSON encode on main.
    enum Budget {
        /// Snapshot+encode of a large workspace on main (old path).
        static let workspaceSaveMS: Double = 250
        /// Note triple write (backup + atomic write).
        static let notePersistMS: Double = 50
        /// Document / note selection path.
        static let documentSwitchMS: Double = 32
        /// Course / note index query.
        static let indexQueryMS: Double = 16
    }

    static let isEnabled =
        ProcessInfo.processInfo.environment["WEIBEI_PERF"] == "1"

    static var scenarioID: String {
        let environment = ProcessInfo.processInfo.environment
        let raw = environment["WEIBEI_PERF_SCENARIO"]
            ?? "manual"
        return token(raw)
    }

    private static let logger = Logger(
        subsystem: "com.changfenhuang.weibei",
        category: "perf"
    )

    /// Rolling window for rate alarms (seconds).
    private static let rateWindowSeconds: TimeInterval = 1
    /// Max samples per window before DEBUG fault.
    private static let rateLimitPerWindow = 8

    private static let rateLock = NSLock()
    private static var rateBuckets: [String: (windowStart: Date, count: Int)] = [:]

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
#if DEBUG
        // Always create spans in DEBUG so budgets apply without WEIBEI_PERF=1.
        return Span(
            name: name,
            sampleID: UUID(),
            startedAtNanoseconds: DispatchTime.now().uptimeNanoseconds
        )
#else
        guard isEnabled else { return nil }
        return Span(
            name: name,
            sampleID: UUID(),
            startedAtNanoseconds: DispatchTime.now().uptimeNanoseconds
        )
#endif
    }

    static func end(_ span: Span?, extra: String = "") {
        guard let span else { return }
        let elapsed = DispatchTime.now().uptimeNanoseconds
            &- span.startedAtNanoseconds
        let ms = Double(elapsed) / 1_000_000
        record(name: span.name, sampleID: span.sampleID, ms: ms, extra: extra)
    }

    @discardableResult
    static func measure<T>(
        _ name: String,
        extra: String = "",
        _ body: () throws -> T
    ) rethrows -> T {
#if DEBUG
        let span = begin(name)
        let value = try body()
        end(span, extra: extra)
        return value
#else
        guard isEnabled else { return try body() }
        let span = begin(name)
        let value = try body()
        end(span, extra: extra)
        return value
#endif
    }

    static func event(_ name: String, extra: String = "") {
#if DEBUG
        record(name: name, sampleID: UUID(), ms: 0, extra: extra)
#else
        guard isEnabled else { return }
        record(name: name, sampleID: UUID(), ms: 0, extra: extra)
#endif
    }

    static func log(
        _ name: String,
        ms: Double,
        extra: String = ""
    ) {
#if DEBUG
        record(name: name, sampleID: UUID(), ms: ms, extra: extra)
#else
        guard isEnabled else { return }
        record(name: name, sampleID: UUID(), ms: ms, extra: extra)
#endif
    }

    /// Budget for a well-known probe name, if any.
    static func budgetMilliseconds(for name: String) -> Double? {
        switch name {
        case "workspace.save",
             "workspace.save_snapshot",
             "workspace.save_transaction_to_ui_publish":
            return Budget.workspaceSaveMS
        case "note.persist", "note.persist.flush":
            return Budget.notePersistMS
        case "workspace.select", "document.switch":
            return Budget.documentSwitchMS
        case "index.query", "course.search_to_next_main_queue_proxy":
            return Budget.indexQueryMS
        default:
            return nil
        }
    }

    private static func record(
        name: String,
        sampleID: UUID,
        ms: Double,
        extra: String
    ) {
        if isEnabled {
            emit(name, sampleID: sampleID, ms: ms, extra: extra)
        }
#if DEBUG
        if let budget = budgetMilliseconds(for: name), ms > budget {
            logger.fault(
                "perf budget exceeded name=\(token(name), privacy: .public) ms=\(ms, format: .fixed(precision: 3)) budget=\(budget, format: .fixed(precision: 1)) main=\(Thread.isMainThread) \(extra, privacy: .public)"
            )
        }
        noteRate(name: name)
#endif
    }

    private static func noteRate(name: String) {
        rateLock.lock()
        defer { rateLock.unlock() }
        let now = Date()
        var bucket = rateBuckets[name] ?? (windowStart: now, count: 0)
        if now.timeIntervalSince(bucket.windowStart) >= rateWindowSeconds {
            bucket = (windowStart: now, count: 0)
        }
        bucket.count += 1
        rateBuckets[name] = bucket
        if bucket.count > rateLimitPerWindow {
            logger.fault(
                "perf rate high name=\(token(name), privacy: .public) count=\(bucket.count) window_s=\(rateWindowSeconds, format: .fixed(precision: 0))"
            )
            // Reset so we don't spam every subsequent call in the same window.
            rateBuckets[name] = (windowStart: now, count: 0)
        }
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
