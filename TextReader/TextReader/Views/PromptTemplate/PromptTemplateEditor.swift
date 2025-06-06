import SwiftUI

struct PromptTemplateEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var template: PromptTemplate
    let onSave: (PromptTemplate) -> Void
    let onAdd: (PromptTemplate) -> Void
    
    // 用于表示新创建的模板
    private let emptyUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    
    init(original: PromptTemplate,
         onSave: @escaping (PromptTemplate) -> Void,
         onAdd: @escaping (PromptTemplate) -> Void) {
        _template = State(initialValue: original)
        self.onSave = onSave
        self.onAdd = onAdd
    }
    
    var body: some View {
        NavigationStack {
            Form {
                TextField("模板名称", text: $template.name)
                
                TextEditor(text: $template.content)
                    .frame(height: 180)
                
                Text("可用占位符: {selection}  {page}  {book}")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .navigationTitle(template.id == emptyUUID ? "新建模板" : "编辑模板")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        if template.id == emptyUUID {
                            // 新增
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
    }
} 