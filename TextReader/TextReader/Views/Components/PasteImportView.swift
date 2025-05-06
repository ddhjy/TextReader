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