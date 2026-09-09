import Foundation
import UniformTypeIdentifiers
#if targetEnvironment(macCatalyst)
import UIKit
#else
import AppKit
#endif

/// The same file-operation choices on both hosts. A dismissed dialog cancels.
@MainActor
enum WorkspaceFileDialog {
    struct Choice {
        let index: Int
        let text: String?
    }

    static func choose(title: String, message: String, buttons: [String],
                       proposedName: String? = nil) async -> Choice {
#if targetEnvironment(macCatalyst)
        guard let presenter else { return Choice(index: 0, text: nil) }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        if let proposedName {
            alert.addTextField { field in
                field.text = proposedName
                field.accessibilityLabel = "新文件名"
            }
        }
        return await withCheckedContinuation { continuation in
            for (index, title) in buttons.enumerated() {
                alert.addAction(UIAlertAction(title: title, style: index == 0 ? .cancel : .default) { [weak alert] _ in
                    continuation.resume(returning: Choice(index: index, text: alert?.textFields?.first?.text))
                })
            }
            presenter.present(alert, animated: true)
        }
#else
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let field = proposedName.map { NSTextField(string: $0) }
        if let field {
            field.widthAnchor.constraint(equalToConstant: 360).isActive = true
            field.setAccessibilityLabel("新文件名")
            alert.accessoryView = field
        }
        buttons.forEach { alert.addButton(withTitle: $0) }
        return Choice(index: alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue,
                      text: field?.stringValue)
#endif
    }

#if targetEnvironment(macCatalyst)
    static func pick(title: String, types: [UTType], multiple: Bool) async -> [URL] {
        guard let presenter else { return [] }
        let picker = Picker(forOpeningContentTypes: types, asCopy: false)
        picker.title = title
        picker.allowsMultipleSelection = multiple
        picker.delegate = picker
        return await withCheckedContinuation { continuation in
            picker.completion = continuation
            presenter.present(picker, animated: true)
            picker.presentationController?.delegate = picker
        }
    }

    static func export(_ data: Data, name: String) async throws {
        guard let presenter else { return }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent(name)
        try data.write(to: file, options: .atomic)
        let picker = Picker(forExporting: [file], asCopy: true)
        picker.delegate = picker
        _ = await withCheckedContinuation { continuation in
            picker.completion = continuation
            presenter.present(picker, animated: true)
            picker.presentationController?.delegate = picker
        }
    }

    static var presenter: UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive && $0.keyWindow != nil }
        var controller = scene?.keyWindow?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        return controller
    }

    final class Picker: UIDocumentPickerViewController, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
        var completion: CheckedContinuation<[URL], Never>?
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { finish(urls) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish([]) }
        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { finish([]) }
        private func finish(_ urls: [URL]) {
            let pending = completion
            completion = nil
            pending?.resume(returning: urls)
        }
    }
#endif
}
