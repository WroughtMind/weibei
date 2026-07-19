import Foundation

/// Lightweight P0 performance probes. Enabled only when `WEIBEI_PERF=1`.
/// Logs lines shaped as `[PERF-weibei-2] name=… ms=…` for evidence collection.
enum WeiBeiPerf {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["WEIBEI_PERF"] == "1"
    }

    @discardableResult
    static func measure<T>(_ name: String, thresholdMS: Double = 8, _ body: () throws -> T) rethrows -> T {
        guard isEnabled else { return try body() }
        let start = CFAbsoluteTimeGetCurrent()
        let value = try body()
        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        if ms >= thresholdMS {
            fputs(String(format: "[PERF-weibei-2] name=%@ ms=%.1f\n", name, ms), stderr)
            fflush(stderr)
        }
        return value
    }

    static func log(_ name: String, ms: Double, extra: String = "") {
        guard isEnabled else { return }
        let suffix = extra.isEmpty ? "" : " \(extra)"
        fputs(String(format: "[PERF-weibei-2] name=%@ ms=%.1f%@\n", name, ms, suffix), stderr)
        fflush(stderr)
    }
}
