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

    private var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PasteButton(payloadType: String.self) { pasted in
                        if let pastedText = pasted.first {
                            text = pastedText
                        }
                    }
                    .buttonBorderShape(.capsule)

                    TextEditor(text: $text)
                        .frame(minHeight: 200)
                        .accessibilityLabel("正文")
                } header: {
                    Text("正文")
                } footer: {
                    Text("点「粘贴」放入剪贴板里的文字，也可以直接在下面输入。")
                }

                Section {
                    // 书名不会随正文自动填：自动填进去的往往只是正文开头的一两个字母。
                    TextField("可不填", text: $title)
                        .accessibilityLabel("书名")
                } header: {
                    Text("书名")
                } footer: {
                    Text("不填时用正文的第一行做书名。")
                }
            }
            .noticeBanner(
                viewModel.notice,
                errorsOnly: true,
                onShown: viewModel.noticeDidAppear,
                onDismiss: viewModel.dismissNotice
            )
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
                        // 失败时留在这一页，输入的内容不丢，原因显示在顶部。
                        if viewModel.importPastedText(text, title: title) {
                            dismiss()
                        }
                    }
                    .disabled(!hasText)
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
