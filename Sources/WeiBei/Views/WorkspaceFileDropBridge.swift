#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Bind the workspace to its native window, including the native toolbar.
struct WorkspaceFileDropBridge: UIViewRepresentable {
    @Binding var isTargeted: Bool
    let receive: ([NSItemProvider]) -> Bool

    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ view: Probe, context: Context) {
        view.isTargeted = $isTargeted
        view.receive = receive
        view.attachToWindow()
    }
    static func dismantleUIView(_ view: Probe, coordinator: ()) { view.detach() }

    final class Probe: UIView {
        let registrationID = UUID().uuidString
        var isTargeted: Binding<Bool>?
        var receive: ([NSItemProvider]) -> Bool = { _ in false }
        private weak var registeredToolbar: NSToolbar?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            attachToWindow()
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            attachToWindow()
        }
        func attachToWindow() {
            guard let window else { detach(); return }
            guard let toolbar = window.windowScene?.titlebar?.toolbar,
                  registeredToolbar !== toolbar else { return }
            detach()
            registeredToolbar = toolbar
            CatalystDesktopWindow.shared.registerFileDrop(id: registrationID, toolbar: toolbar,
                targeted: { [weak self] value in self?.isTargeted?.wrappedValue = value },
                receive: { [weak self] urls in
                    guard let self else { return }
                    _ = self.receive(urls.map {
                        NSItemProvider(item: $0 as NSURL, typeIdentifier: UTType.fileURL.identifier)
                    })
                })
        }
        func detach() {
            guard registeredToolbar != nil else { return }
            CatalystDesktopWindow.shared.unregisterFileDrop(id: registrationID)
            registeredToolbar = nil
            isTargeted?.wrappedValue = false
        }
    }
}
#endif
