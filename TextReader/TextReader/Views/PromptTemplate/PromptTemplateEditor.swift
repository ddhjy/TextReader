import SwiftUI

struct PromptTemplateEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var template: PromptTemplate
    let viewModel: ContentViewModel
    let onSave: (PromptTemplate) -> Void
    let onAdd: (PromptTemplate) -> Void
    
    private let emptyUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    
    init(viewModel: ContentViewModel,
         original: PromptTemplate,
         onSave: @escaping (PromptTemplate) -> Void,
         onAdd: @escaping (PromptTemplate) -> Void) {
        self.viewModel = viewModel
        _template = State(initialValue: original)
        self.onSave = onSave
        self.onAdd = onAdd
    }
    
    var body: some View {
        NavigationStack {
            Form {
                TextField("如：翻译、总结、解释", text: $template.name)
                
                TextEditor(text: $template.content)
                    .frame(height: 180)
                
                Text("可用变量：{selection} 选中文本 · {page} 当前页 · {book} 书名")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle(template.id == emptyUUID ? "新建模板" : "编辑模板")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
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
        }
        .tint(viewModel.currentAccentColor)
    }
}
