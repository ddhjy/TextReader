import SwiftUI

struct PromptTemplateEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var template: PromptTemplate
    @State private var showingDiscardConfirmation = false
    let viewModel: ContentViewModel
    let onSave: (PromptTemplate) -> Void
    let onAdd: (PromptTemplate) -> Void
    private let original: PromptTemplate
    
    private static let emptyUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    /// 「新建模板」用的空白草稿。去向默认「仅复制」：最不会出意外的一种。
    static func newTemplateDraft() -> PromptTemplate {
        PromptTemplate(id: emptyUUID, name: "", content: "", destination: .copyOnly)
    }
    
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

    private var isNewTemplate: Bool {
        template.id == Self.emptyUUID
    }

    private var hasChanges: Bool {
        template.name != original.name
            || template.content != original.content
            || template.destination != original.destination
    }

    private var trimmedName: String {
        template.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedContent: String {
        template.content.trimmingCharacters(in: .whitespacesAndNewlines)
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
                        .accessibilityLabel("内容")
                } header: {
                    Text("内容")
                } footer: {
                    Text("可以写这三个变量，用的时候会被换掉：\n{selection} 选中的文字\n{page} 当前页，加上它的前一页和后一页\n{book} 书名")
                }

                Section {
                    Picker("用完之后", selection: $template.destination) {
                        if original.destination == nil {
                            Text("第一次用时再选").tag(PromptTemplate.Destination?.none)
                        }
                        ForEach(PromptTemplate.Destination.allCases) { destination in
                            Text(destination.displayName).tag(PromptTemplate.Destination?.some(destination))
                        }
                    }
                } footer: {
                    Text("提示词每次都会先复制好。对应的 App 没有安装、打不开时会提示，这时可以自己粘贴。")
                }
            }
            .navigationTitle(isNewTemplate ? "新建模板" : "编辑模板")
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
                        if isNewTemplate {
                            onAdd(PromptTemplate(
                                name: trimmedName,
                                content: trimmedContent,
                                destination: template.destination
                            ))
                        } else {
                            var saved = template
                            saved.name = trimmedName
                            saved.content = trimmedContent
                            onSave(saved)
                        }
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty || trimmedContent.isEmpty)
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
