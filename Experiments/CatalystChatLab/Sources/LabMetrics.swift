import UIKit
import QuartzCore
import Darwin

@MainActor
final class LabMetrics: NSObject {
    private(set) var samples: [String: [Double]] = [:]
    var checks: [String: String] = [:]
    private var displayLink: CADisplayLink?
    private var previous: CFTimeInterval?
    private var started: CFTimeInterval = 0
    private var sampleName = ""
    private var step: ((Double) -> Void)?
    private var completed: (() -> Void)?
    func record(_ name: String, _ value: Double) { samples[name, default: []].append(value) }
    func scrollSample(name: String, step: @escaping (Double) -> Void, completed: @escaping () -> Void) {
        displayLink?.invalidate()
        self.step = step; self.completed = completed
        sampleName = name
        previous = nil; started = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(frame(_:)))
        displayLink = link
        link.add(to: .main, forMode: .common)
    }
    @objc private func frame(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let elapsed = now - started
        if let previous { record("\(sampleName)_\(elapsed < 6 ? "outbound" : "return")_display_callback_interval_ms", (now - previous) * 1000) }
        previous = now
        step?(elapsed)
        if elapsed >= 12 {
            displayLink?.invalidate(); displayLink = nil
            step = nil
            let callback = completed; completed = nil; callback?()
        }
    }
    static let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(Bundle.main.bundleIdentifier! + "/Results", isDirectory: true)
    static func residentMemory() -> UInt64? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let memory = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) }
        }
        return memory == KERN_SUCCESS ? info.resident_size : nil
    }
    func write(controller: ConversationController) throws -> URL {
        var output: [String: Any] = [
            "recorded_at": ISO8601DateFormatter().string(from: Date()),
            "system": ProcessInfo.processInfo.operatingSystemVersionString,
            "build_configuration": "Release",
            "bundle_id": Bundle.main.bundleIdentifier ?? "",
            "source_revision": Bundle.main.object(forInfoDictionaryKey: "LabSourceRevision") as? String ?? "unrecorded",
            "source_dirty": Bundle.main.object(forInfoDictionaryKey: "LabSourceDirty") as? String ?? "unrecorded",
            "idiom": UIDevice.current.userInterfaceIdiom == .mac ? "mac" : "other",
            "body_width_pt": controller.bodyWidth, "font_size_pt": controller.store.theme.fonts.body.pointSize,
            "message_count": controller.messages.count,
            "body_block_count": controller.messages.flatMap(\.blocks).count,
            "source_utf16_count": controller.messages.reduce(0) { $0 + $1.markdown.utf16.count },
            "parse_count": controller.store.parseCount,
            "render_count": controller.store.renderedCount,
            "measure_count": controller.store.measureCount,
            "preparation_ms": controller.store.preparationMS,
            "retained_block_views": controller.store.retainedViewCount,
            "peak_block_views": controller.store.peakViewCount,
            "checks": checks,
            "samples": samples,
            "frame_evidence_boundary": "CADisplayLink callback delivery intervals during programmatic scrolling; these are not GPU presentation timestamps and are not FPS or human trackpad acceptance."
        ]
        if let memory = Self.residentMemory() { output["resident_memory_bytes"] = memory }
        #if targetEnvironment(macCatalyst)
        output["platform"] = "Mac Catalyst"
        #endif
        let summary = samples.mapValues { values -> [String: Double] in
            let sorted = values.sorted()
            return ["count": Double(values.count), "median": sorted[sorted.count/2], "p95": sorted[min(sorted.count-1, Int(Double(sorted.count)*0.95))], "max": sorted.last!]
        }
        output["summary"] = summary
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        let url = Self.directory.appendingPathComponent("latest.json")
        try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
        return url
    }
}
