import SwiftUI

struct PromptTemplatePicker: View {
    @ObservedObject var viewModel: ContentViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var editing: PromptTemplate?  // nil = new
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.templates) { tpl in
                    Button {
                        viewModel.buildPrompt(using: tpl)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading) {
                            Text(tpl.name).font(.headline)
                            Text(tpl.content).font(.caption).lineLimit(2)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            viewModel.deleteTemplate(tpl)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        
                        Button {
                            editing = tpl
                        } label: {
                            Label("编辑", systemImage: "square.and.pencil")
                        }
                    }
                }
            }
            .navigationTitle("提示词模板")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("完成") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        editing = PromptTemplate(id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!, name: "", content: "")
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $editing) { tpl in
                PromptTemplateEditor(
                    original: tpl,
                    onSave: { viewModel.updateTemplate($0) },
                    onAdd: { viewModel.addTemplate($0) }
                )
            }
        }
    }
} 