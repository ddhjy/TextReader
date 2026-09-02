import SwiftUI

struct PasteImportView: View {
    @ObservedObject var viewModel: ContentViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var text: String = ""
    @State private var showingDiscardConfirmation = false

    private var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("标题") {
                    TextField("标题（可选）", text: $title)
                }

                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 200)
                        .onChange(of: text) { _, newText in
                            if title.isEmpty && !newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                let cleanedText = newText.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                                title = String(cleanedText.prefix(10))
                            }
                        }
                } header: {
                    Text("正文")
                } footer: {
                    Text("标题留空时自动取正文前 10 个字。")
                }
            }
            .navigationTitle("粘贴文本")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(hasContent)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        if hasContent {
                            showingDiscardConfirmation = true
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    PasteButton(payloadType: String.self) { strings in
                        if let first = strings.first, !first.isEmpty {
                            text = first
                            if title.isEmpty {
                                let cleanedText = first.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                                title = String(cleanedText.prefix(10))
                            }
                        }
                    }
                    .buttonBorderShape(.capsule)

                    Button("导入") {
                        viewModel.importPastedText(text, title: title)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog("放弃导入？", isPresented: $showingDiscardConfirmation, titleVisibility: .visible) {
                Button("放弃更改", role: .destructive) { dismiss() }
                Button("继续编辑", role: .cancel) {}
            } message: {
                Text("已输入的内容将会丢失。")
            }
        }
        .tint(viewModel.currentAccentColor)
    }
}
