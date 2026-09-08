import ChatRendererKit
import AppKit
import Foundation

@MainActor
final class LabViewController: NSViewController {
    let candidate = CandidateHost(frame: .zero)
    let document = CandidateDocument()
    private let picker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let streamButton = NSButton(title: "重放合成流式", target: nil, action: nil)
    private let note = NSTextField(labelWithString: "候选资格验证 · 非魏碑性能 A/B · 不读取你的资料")
    private var replay: Task<Void, Never>?

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 816, height: 680))
        picker.addItems(withTitles: LabSamples.titles)
        picker.target = self
        picker.action = #selector(changeSample)
        streamButton.target = self
        streamButton.action = #selector(replayStream)
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: 11)
        for child in [candidate, picker, streamButton, note] { view.addSubview(child) }
        document.onApply = { [weak self] content, revision in
            guard let self else { return }
            self.candidate.present(content, theme: self.document.theme, revision: revision)
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let size = view.bounds.size
        picker.frame = NSRect(x: 18, y: size.height - 40, width: 230, height: 26)
        streamButton.frame = NSRect(x: 260, y: size.height - 40, width: 145, height: 26)
        note.frame = NSRect(x: 18, y: 8, width: max(1, size.width - 36), height: 18)
        candidate.frame = NSRect(x: 0, y: 34, width: size.width, height: max(1, size.height - 86))
    }

    @objc func changeSample() {
        replay?.cancel()
        document.reset(); candidate.reset()
        document.submit(LabSamples.source(picker.indexOfSelectedItem))
    }

    @objc private func replayStream() {
        replay?.cancel()
        document.reset(); candidate.reset()
        let chars = Array(LabSamples.source(picker.indexOfSelectedItem))
        replay = Task { [weak self] in
            for length in stride(from: 1, to: chars.count, by: 37) {
                guard !Task.isCancelled, let self else { return }
                self.document.submit(String(chars.prefix(length)))
                do { try await Task.sleep(for: .milliseconds(35)) } catch { return }
            }
            guard !Task.isCancelled, let self else { return }
            self.document.submit(String(chars))
        }
    }
}

@MainActor
final class LabAppDelegate: NSObject, NSApplicationDelegate {
    let verificationDirectory: URL?
    private var window: NSWindow?
    private var controller: LabViewController?

    init(verificationDirectory: URL?) { self.verificationDirectory = verificationDirectory }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = LabViewController()
        self.controller = controller
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 816, height: 680),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        self.window = window
        window.isReleasedWhenClosed = false
        window.title = "魏碑 · 正文候选实验（不是正式版）"
        window.minSize = NSSize(width: 360, height: 360)
        window.contentViewController = controller
        controller.view.layoutSubtreeIfNeeded()
        if let directory = verificationDirectory {
            // Deliberately never orderFront/activate in automated verification.
            Task { @MainActor in
                do {
                    let host = CandidateHost(frame: NSRect(x: 0, y: 0, width: 768, height: 560))
                    let document = CandidateDocument()
                    window.contentViewController = nil
                    window.contentView = host
                    document.onApply = { [weak host] content, revision in
                        host?.present(content, theme: document.theme, revision: revision)
                    }
                    defer { document.onApply = nil }
                    _ = try await CandidateVerification.run(host: host, document: document, directory: directory)
                } catch {
                    let failure = ["error": String(describing: error)]
                    if let data = try? JSONSerialization.data(withJSONObject: failure, options: [.prettyPrinted]) {
                        try? data.write(to: directory.appendingPathComponent("fatal.json"), options: .atomic)
                    }
                }
                NSApp.terminate(nil)
            }
        } else {
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            controller.changeSample()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Ordering the CI diagnostic window out must not terminate the suite
        // before its long-document checks and JSON report finish.
        verificationDirectory == nil
    }
}

@main
@MainActor
enum LabMain {
    static func main() {
        let args = CommandLine.arguments
        let output: URL?
        if let index = args.firstIndex(of: "--verify") {
            guard index + 1 < args.count else { fatalError("--verify requires an output directory") }
            output = URL(fileURLWithPath: args[index + 1], isDirectory: true)
        } else { output = nil }
        let app = NSApplication.shared
        app.setActivationPolicy(output == nil ? .regular : .accessory)
        let delegate = LabAppDelegate(verificationDirectory: output)
        app.delegate = delegate
        let menu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出实验", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let item = NSMenuItem()
        item.submenu = appMenu
        menu.addItem(item)
        app.mainMenu = menu
        withExtendedLifetime(delegate) { app.run() }
    }
}
