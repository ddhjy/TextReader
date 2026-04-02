import SwiftUI

struct PasteImportView: View {
    @ObservedObject var viewModel: ContentViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var text: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("标题（可选）", text: $title)
                }

                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 200)
                        .onChange(of: text) { _, newText in
                            if title.isEmpty && !newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                let cleanedText = newText.replacingOccurrences(of: "\n", with: " ")
                                title = String(cleanedText.prefix(10))
                            }
                        }
                }
            }
            .navigationTitle("粘贴文本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入") {
                        viewModel.importPastedText(text, title: title)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .tint(viewModel.currentAccentColor)
    }
}
