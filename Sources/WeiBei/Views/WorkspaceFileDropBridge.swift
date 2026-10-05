#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// A window-level native receiver also covers independently hosted workspace panes.
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

    final class Probe: UIView, UIDropInteractionDelegate {
        var isTargeted: Binding<Bool>?
        var receive: ([NSItemProvider]) -> Bool = { _ in false }
        private weak var dropView: UIView?
        private lazy var fileDropInteraction = UIDropInteraction(delegate: self)

#if WEIBEI_ACCEPTANCE_CHECKS
        var registrationCheckState: [String: String] {
            ["window_present": String(window != nil), "root_present": String(window?.rootViewController?.viewIfLoaded != nil),
                "registered_view": dropView.map { String(describing: type(of: $0)) } ?? "nil",
                "interaction_view_matches": String(dropView != nil && fileDropInteraction.view === dropView),
                "binding_present": String(isTargeted != nil)]
        }
#endif

        override func didMoveToWindow() {
            super.didMoveToWindow()
            attachToWindow()
        }

        func attachToWindow() {
            guard let target = window?.rootViewController?.view else {
                detach()
                return
            }
            guard dropView !== target else { return }
            detach()
            dropView = target
            target.addInteraction(fileDropInteraction)
        }

        func detach() {
            dropView?.removeInteraction(fileDropInteraction)
            dropView = nil
        }

        func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
            session.hasItemsConforming(toTypeIdentifiers: [UTType.fileURL.identifier])
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnter session: UIDropSession) {
            setTargeted(dropInteraction(interaction, canHandle: session))
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
            let accepts = dropInteraction(interaction, canHandle: session)
            setTargeted(accepts)
            return UIDropProposal(operation: accepts ? .copy : .cancel)
        }

        func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
            setTargeted(false)
            _ = receive(session.items.map(\.itemProvider))
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidExit session: UIDropSession) { setTargeted(false) }
        func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnd session: UIDropSession) { setTargeted(false) }

        private func setTargeted(_ value: Bool) {
            if isTargeted?.wrappedValue != value { isTargeted?.wrappedValue = value }
        }
    }
}
#endif
