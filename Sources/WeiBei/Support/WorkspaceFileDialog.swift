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
    static let markdownType = UTType(
        importedAs: "net.daringfireball.markdown",
        conformingTo: .plainText
    )

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
        let canChooseDirectories = types.contains(.folder)
        let fileTypes = types.filter { $0 != .folder }
        if canChooseDirectories, !fileTypes.isEmpty {
            let sourceWindow = presenter.view.window
            let toolbar = sourceWindow?.windowScene?.titlebar?.toolbar
            if toolbar == nil, sourceWindow?.isKeyWindow != true {
                await showNativeOpenPanelFailure(NSError(
                    domain: "WeiBei.NativeOpenPanel",
                    code: 5
                ), from: presenter)
                return []
            }
            let result: ([URL], NSError?) = await withCheckedContinuation { continuation in
                CatalystDesktopWindow.shared.presentOpenPanel(
                    title: title,
                    contentTypeIdentifiers: fileTypes.map(\.identifier),
                    allowsMultipleSelection: multiple,
                    canChooseDirectories: true,
                    canChooseFiles: true,
                    presentationToolbar: toolbar
                ) { urls, error in
                    continuation.resume(returning: (urls, error))
                }
            }
            if let error = result.1 {
                await showNativeOpenPanelFailure(error, from: presenter)
                return []
            }
            return result.0
        }
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
        guard let presenter else { throw CocoaError(.featureUnsupported) }
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
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.windows.contains(where: \.isKeyWindow) }
            ?? scenes.first { $0.activationState == .foregroundActive && $0.keyWindow != nil }
        let window = scene?.windows.first(where: \.isKeyWindow) ?? scene?.keyWindow
        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        return controller
    }

    private static func showNativeOpenPanelFailure(
        _ error: NSError,
        from presenter: UIViewController
    ) async {
        let store = AppDelegate.workspace
        let busy = error.code == 1 || error.code == 4
        let alert = UIAlertController(
            title: store.ui("无法打开文件选择器", "File Picker Unavailable"),
            message: busy
                ? store.ui(
                    "当前窗口正在显示另一个文件选择器，请先关闭后重试。",
                    "Another file picker is already open. Close it and try again."
                )
                : store.ui(
                    "当前窗口暂时无法打开文件选择器，请关闭其他弹窗后重试。",
                    "The file picker cannot open in this window right now. Close other dialogs and try again."
                ),
            preferredStyle: .alert
        )
        await withCheckedContinuation { continuation in
            alert.addAction(UIAlertAction(title: store.ui("好", "OK"), style: .default) { _ in
                continuation.resume()
            })
            presenter.present(alert, animated: true)
        }
    }

    final class Picker: UIDocumentPickerViewController, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
        var completion: CheckedContinuation<[URL], Never>?
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { finish(urls) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish([]) }
        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { finish([]) }
        private func finish(_ urls: [URL]) {
            let pending = completion
            completion = nil
            // A following confirmation must wait until the picker releases its presenter.
            if presentingViewController != nil {
                dismiss(animated: true) { pending?.resume(returning: urls) }
            } else {
                pending?.resume(returning: urls)
            }
        }
    }
#endif
}
