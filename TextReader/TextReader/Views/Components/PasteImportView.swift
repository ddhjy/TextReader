import SwiftUI

struct PasteImportView: View {
    @ObservedObject var viewModel: ContentViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var text: String = ""
    @State private var showingDiscardConfirmation = false

    private var hasChanges: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("标题（可选）", text: $title)
                } header: {
                    Text("标题")
                } footer: {
                    Text("留空时自动取正文前 10 个字")
                }

                Section("正文") {
                    TextEditor(text: $text)
                        .frame(minHeight: 200)
                        .onChange(of: text) { _, newText in
                            if title.isEmpty && !newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                let cleanedText = newText.replacingOccurrences(of: "\n", with: " ")
                                title = String(cleanedText.prefix(10))
                            }
                        }

                    PasteButton(payloadType: String.self) { pasted in
                        if let pastedText = pasted.first {
                            text = pastedText
                        }
                    }
                    .buttonBorderShape(.capsule)
                }
            }
            .navigationTitle("粘贴文本")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(hasChanges)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        attemptDismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入") {
                        viewModel.importPastedText(text, title: title)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog("放弃更改？", isPresented: $showingDiscardConfirmation, titleVisibility: .visible) {
                Button("放弃更改", role: .destructive) {
                    dismiss()
                }
                Button("继续编辑", role: .cancel) {}
            } message: {
                Text("你所做的修改将不会被保存。")
            }
        }
        .tint(viewModel.currentAccentColor)
    }

    private func attemptDismiss() {
        if hasChanges {
            showingDiscardConfirmation = true
        } else {
            dismiss()
        }
    }
}
