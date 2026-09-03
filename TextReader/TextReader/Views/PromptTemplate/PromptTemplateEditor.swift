import SwiftUI

struct PromptTemplateEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var template: PromptTemplate
    @State private var showingDiscardConfirmation = false
    let viewModel: ContentViewModel
    let onSave: (PromptTemplate) -> Void
    let onAdd: (PromptTemplate) -> Void
    private let original: PromptTemplate
    
    private let emptyUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    
    init(viewModel: ContentViewModel,
         original: PromptTemplate,
         onSave: @escaping (PromptTemplate) -> Void,
         onAdd: @escaping (PromptTemplate) -> Void) {
        self.viewModel = viewModel
        self.original = original
        _template = State(initialValue: original)
        self.onSave = onSave
        self.onAdd = onAdd
    }

    private var hasChanges: Bool {
        template.name != original.name || template.content != original.content
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("如：翻译、总结、解释", text: $template.name)
                }

                Section {
                    TextEditor(text: $template.content)
                        .frame(minHeight: 180)
                } header: {
                    Text("内容")
                } footer: {
                    Text("可用变量：{selection} 选中文本 · {page} 当前页 · {book} 书名")
                }
            }
            .navigationTitle(template.id == emptyUUID ? "新建模板" : "编辑模板")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(hasChanges)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        attemptDismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if template.id == emptyUUID {
                            onAdd(PromptTemplate(name: template.name, content: template.content))
                        } else {
                            onSave(template)
                        }
                        dismiss()
                    }
                    .disabled(
                        template.name.trimmingCharacters(in: .whitespaces).isEmpty ||
                        template.content.trimmingCharacters(in: .whitespaces).isEmpty
                    )
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
