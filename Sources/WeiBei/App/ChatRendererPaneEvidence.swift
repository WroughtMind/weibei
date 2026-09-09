#if CHAT_RENDERER_LAB || CHAT_RENDERER_BASELINE
import AppKit
import ChatRendererKit
import SwiftUI
import WeiBeiCore

/// One small replay of the real AgentPane, run separately for each of the three
/// requested scenarios. Both binaries use identical inputs and viewport moves.
@MainActor
enum ChatRendererPaneEvidence {
    static func run(store: WorkspaceStore, directory: URL) async throws {
        let scenario = Int(ProcessInfo.processInfo.arguments.last ?? "") ?? 0
        ChatRendererExperiment.open(ChatRendererExperiment.scenarioTitles[scenario], store: store)
        let view = NSHostingView(rootView: AgentPaneView(showsPaneHeader: false)
            .environmentObject(store).environmentObject(store.paneState).environmentObject(store.interaction)
            .environment(\.weiBeiTextScale, CGFloat(1)))
        view.sizingOptions = []
        // Compare the same pane size; report the observed body widths below.
        let windowWidth: CGFloat = 740
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: 640),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        let start = ProcessInfo.processInfo.systemUptime
        window.contentView = view
        var previousTick = start, lateness: [Double] = []
        let timer = Timer.scheduledTimer(withTimeInterval: 0.008, repeats: true) { _ in
            let now = ProcessInfo.processInfo.systemUptime
            lateness.append(max(0, (now - previousTick - 0.008) * 1_000)); previousTick = now
        }
        defer { timer.invalidate(); window.contentView = nil }
        func outerScroll(_ node: NSView) -> NSScrollView? {
            if let scroll = node as? NSScrollView, scroll.bounds.height > 200 { return scroll }
            for child in node.subviews { if let scroll = outerScroll(child) { return scroll } }
            return nil
        }
        func settle() async throws {
            let deadline = ProcessInfo.processInfo.systemUptime + 30
            var stable = 0, previous: CGSize?
            while stable < 3 {
                view.layoutSubtreeIfNeeded()
                let size = outerScroll(view)?.documentView?.frame.size
                if size != nil && size == previous { stable += 1 } else { stable = 0 }
                previous = size
                if ProcessInfo.processInfo.systemUptime >= deadline { throw CocoaError(.coderInvalidValue) }
                try await Task.sleep(for: .milliseconds(20))
            }
        }
        try await settle()
        guard let scroll = outerScroll(view), let document = scroll.documentView else { throw CocoaError(.coderValueNotFound) }
        func phase(_ name: String, since began: Double, from sample: Int) -> [String: Any] {
            let delays = Array(lateness.dropFirst(sample))
            var result: [String: Any] = ["phase": name, "ms": (ProcessInfo.processInfo.systemUptime - began) * 1_000,
                    "main_timer_max_ms": delays.max() ?? 0,
                    "main_timer_over_16_count": delays.filter { $0 > 16 }.count,
                    "main_timer_over_50_count": delays.filter { $0 > 50 }.count]
            #if CHAT_RENDERER_LAB
            if let list = scroll.superview as? ChatRendererListView {
                let documents = list.session.preparedDocuments
                result["renderer_totals"] = [
                    "parses": documents.reduce(0) { $0 + $1.parseCount },
                    "inline_preparations": documents.reduce(0) { $0 + $1.inlinePreparationCount }]
            }
            #endif
            return result
        }
        var phases = [phase("first_open_to_settled_geometry", since: start, from: 0)]
        for name in ["first_pass", "warm_revisit"] {
            let began = ProcessInfo.processInfo.systemUptime
            let sample = lateness.count
            for progress in (0...12).reversed().map({ Double($0) / 12 }) + (1...12).map({ Double($0) / 12 }) {
                let y = max(0, document.bounds.height - scroll.contentView.bounds.height) * progress
                NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
                scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
                scroll.reflectScrolledClipView(scroll.contentView)
                NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: scroll)
                try await settle()
            }
            phases.append(phase(name, since: began, from: sample))
        }
        let resize = ProcessInfo.processInfo.systemUptime
        let resizeSample = lateness.count
        window.setContentSize(NSSize(width: windowWidth - 260, height: 640)); try await settle()
        window.setContentSize(NSSize(width: windowWidth, height: 640)); try await settle()
        phases.append(phase("body_width_436_then_696", since: resize, from: resizeSample))
        var bodyWidths: [CGFloat] = []
        func inspect(_ node: NSView) {
            if let text = node as? CandidateTextView, text.textLabelView.attributedText.length > 0 {
                bodyWidths.append(text.bounds.width)
            } else if let text = node as? NSTextView, text.string.count > 100 {
                bodyWidths.append(text.textContainer?.containerSize.width ?? text.bounds.width)
            }
            for child in node.subviews { inspect(child) }
        }
        inspect(view)
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        let readingPeakRSS = usage.ru_maxrss
        func composer(in node: NSView) -> NSTextView? {
            if let text = node as? NSTextView, text.enclosingScrollView is AgentComposerNativeScrollView { return text }
            for child in node.subviews { if let text = composer(in: child) { return text } }
            return nil
        }
        guard let input = composer(in: view) else { throw CocoaError(.coderValueNotFound) }
        let firstInput = ProcessInfo.processInfo.systemUptime
        let inputSample = lateness.count
        guard window.makeFirstResponder(input) else { throw CocoaError(.coderInvalidValue) }
        input.insertText("首个输入", replacementRange: NSRange(location: 0, length: input.string.utf16.count))
        try await settle()
        guard input.string == "首个输入", store.pendingComposerDraft == input.string else { throw CocoaError(.coderInvalidValue) }
        phases.append(phase("first_focus_and_text_input", since: firstInput, from: inputSample))
        let sweep = ProcessInfo.processInfo.systemUptime
        let sweepSample = lateness.count
        for width in Array(stride(from: 714, through: 480, by: -26)) + Array(stride(from: 506, through: 740, by: 26)) {
            window.setContentSize(NSSize(width: CGFloat(width), height: 640))
            view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        try await settle()
        phases.append(phase("continuous_window_width_740_480_740", since: sweep, from: sweepSample))
        getrusage(RUSAGE_SELF, &usage)
        let report: [String: Any] = [
            "scope": "real AgentPane, Release, hidden window, programmatic viewport replay; not FPS",
            "variant": Bundle.main.object(forInfoDictionaryKey: "WeiBeiExperimentVariant") ?? "unknown",
            "scenario": ChatRendererExperiment.scenarioTitles[scenario], "font_size": 16,
            "window_width": windowWidth, "body_widths": Array(Set(bodyWidths)).sorted(),
            "messages": store.messages.count, "phases": phases, "peak_rss_bytes": usage.ru_maxrss,
            "peak_reading_rss_bytes": readingPeakRSS,
            "main_timer_lateness_ms": ["max": lateness.max() ?? 0, "over_16_count": lateness.filter { $0 > 16 }.count,
                                        "over_50_count": lateness.filter { $0 > 50 }.count],
            "unverified": ["Compositor/presentation completion", "Trackpad momentum", "FPS"]]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("pane-evidence.json"))
    }
}
#endif
