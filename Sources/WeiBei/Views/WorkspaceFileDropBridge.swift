#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit
import WeiBeiCore

/// UIKit owns content/hosted-toolbar drag routing. AppKit provides the actual
/// file URLs and receives drags on native window regions. Both enter one import.
struct WorkspaceFileDropBridge: UIViewRepresentable {
    @Binding var isTargeted: Bool
    let receive: ([URL]) -> Void

    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ view: Probe, context: Context) {
        view.isTargeted = $isTargeted
        view.receive = receive
        view.attachToWindow()
    }
    static func dismantleUIView(_ view: Probe, coordinator: ()) { view.detach() }

    final class Probe: UIView, UIDropInteractionDelegate {
        let registrationID = UUID().uuidString
        var isTargeted: Binding<Bool>?
        var receive: ([URL]) -> Void = { _ in }
        private weak var registeredToolbar: NSToolbar?
        private var isRegistered = false
        private weak var dropView: UIView?
        private lazy var fileDropInteraction = UIDropInteraction(delegate: self)
#if WEIBEI_ACCEPTANCE_CHECKS
        var registeredInteraction: UIDropInteraction? {
            guard let dropView, fileDropInteraction.view === dropView, dropView.window === window else { return nil }
            return fileDropInteraction
        }
#endif
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
            if let root = window.rootViewController?.view, dropView !== root {
                dropView?.removeInteraction(fileDropInteraction)
                dropView = root
                root.addInteraction(fileDropInteraction)
                WeiBeiLog.workspace.notice("[DEBUG-wb-drop] uikit_registered enabled=\(root.isUserInteractionEnabled, privacy: .public)")
            }
            guard let toolbar = window.windowScene?.titlebar?.toolbar,
                  registeredToolbar !== toolbar else { return }
            if isRegistered { CatalystDesktopWindow.shared.unregisterFileDrop(id: registrationID) }
            registeredToolbar = toolbar
            isRegistered = true
            CatalystDesktopWindow.shared.registerFileDrop(id: registrationID, toolbar: toolbar,
                targeted: { [weak self] value in self?.isTargeted?.wrappedValue = value },
                receive: { [weak self] urls in self?.receive(urls) })
        }
        func detach() {
            dropView?.removeInteraction(fileDropInteraction)
            dropView = nil
            if isRegistered { CatalystDesktopWindow.shared.unregisterFileDrop(id: registrationID) }
            registeredToolbar = nil
            isRegistered = false
            isTargeted?.wrappedValue = false
        }
        func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
            // Catalyst advertises a file's content type (e.g. plain text), not
            // fileURL. Classify the actual external drag pasteboard instead.
            let accepts = session.localDragSession == nil && !session.items.isEmpty
                && !CatalystDesktopWindow.shared.currentDraggedFileURLs().isEmpty
            WeiBeiLog.workspace.notice("[DEBUG-wb-drop] uikit_can_handle accepted=\(accepts, privacy: .public)")
            return accepts
        }
        func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnter session: UIDropSession) {
            isTargeted?.wrappedValue = dropInteraction(interaction, canHandle: session)
        }
        func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
            let accepts = dropInteraction(interaction, canHandle: session)
            isTargeted?.wrappedValue = accepts
            return UIDropProposal(operation: accepts ? .copy : .cancel)
        }
        func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
            isTargeted?.wrappedValue = false
            guard session.localDragSession == nil else { return }
            let urls = CatalystDesktopWindow.shared.currentDraggedFileURLs()
            WeiBeiLog.workspace.notice("[DEBUG-wb-drop] uikit_performed count=\(urls.count, privacy: .public)")
            guard !urls.isEmpty else { return }
            receive(urls)
        }
        func dropInteraction(_ interaction: UIDropInteraction, sessionDidExit session: UIDropSession) { isTargeted?.wrappedValue = false }
        func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnd session: UIDropSession) { isTargeted?.wrappedValue = false }
    }
}
#endif
