import SwiftUI

struct PasteImportView: View {
    @ObservedObject var viewModel: ContentViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var text: String = ""

    var body: some View {
        NavigationStack {
            VStack {
                TextField("可选标题（留空则取前 10 字）", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)

                TextEditor(text: $text)
                    .border(Color.secondary, width: 1)
                    .padding()
                    .onChange(of: text) { _, newText in
                        // 当文本变化时，如果标题为空，自动填充前10个字符
                        if title.isEmpty && !newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            let cleanedText = newText.replacingOccurrences(of: "\n", with: " ")
                            title = String(cleanedText.prefix(10))
                        }
                    }

                Spacer()
            }
            .navigationTitle("粘贴导入")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        viewModel.importPastedText(text, title: title)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
} 