import SwiftUI
import UniformTypeIdentifiers

struct DocumentPicker: UIViewControllerRepresentable {
    @ObservedObject var viewModel: ContentViewModel
    @Environment(\.presentationMode) var presentationMode

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let supportedTypes: [UTType] = [.text, .plainText]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: supportedTypes, asCopy: true)
        picker.delegate = context.coordinator
        picker.shouldShowFileExtensions = true
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: DocumentPicker

        init(_ parent: DocumentPicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                print("[DocumentPicker][Error] No URL selected or provided by picker.")
                parent.presentationMode.wrappedValue.dismiss()
                return
            }
            print("[DocumentPicker] Picked URL: \(url.absoluteString)")
            print("[DocumentPicker] Is File URL: \(url.isFileURL)")

            parent.viewModel.importBookFromURL(url)
            parent.presentationMode.wrappedValue.dismiss()
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            print("[DocumentPicker] Picker was cancelled by user.")
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
} 