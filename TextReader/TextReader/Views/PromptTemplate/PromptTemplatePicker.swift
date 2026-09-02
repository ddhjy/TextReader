import SwiftUI

struct PromptTemplatePicker: View {
    @ObservedObject var viewModel: ContentViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var editing: PromptTemplate?
    
    private let emptyUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.templates.isEmpty {
                    ContentUnavailableView {
                        Label("没有模板", systemImage: "text.badge.star")
                    } description: {
                        Text("点按右上角加号创建你的第一个提示词模板。")
                    } actions: {
                        Button("新建模板") {
                            editing = PromptTemplate(id: emptyUUID, name: "", content: "")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(viewModel.templates) { tpl in
                            Menu {
                                Button {
                                    viewModel.buildPrompt(using: tpl, destination: .perplexity)
                                    dismiss()
                                } label: {
                                    Label("打开 Perplexity", systemImage: "safari")
                                }
                                Button {
                                    viewModel.buildPrompt(using: tpl, destination: .raycast)
                                    dismiss()
                                } label: {
                                    Label("打开 Raycast", systemImage: "command")
                                }
                                Button {
                                    viewModel.buildPrompt(using: tpl, destination: .copyOnly)
                                    dismiss()
                                } label: {
                                    Label("仅复制", systemImage: "doc.on.doc")
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(tpl.name)
                                            .font(.body)
                                            .fontWeight(.medium)
                                            .foregroundStyle(.primary)
                                        Text(tpl.content)
                                            .font(.subheadline)
                                            .lineLimit(2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 2)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    viewModel.deleteTemplate(tpl)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }

                                Button {
                                    editing = tpl
                                } label: {
                                    Label("编辑", systemImage: "pencil")
                                }
                                .tint(viewModel.currentAccentColor)
                            }
                            .contextMenu {
                                Button {
                                    viewModel.buildPrompt(using: tpl, destination: .perplexity)
                                    dismiss()
                                } label: {
                                    Label("打开 Perplexity", systemImage: "safari")
                                }
                                Button {
                                    viewModel.buildPrompt(using: tpl, destination: .raycast)
                                    dismiss()
                                } label: {
                                    Label("打开 Raycast", systemImage: "command")
                                }
                                Button {
                                    viewModel.buildPrompt(using: tpl, destination: .copyOnly)
                                    dismiss()
                                } label: {
                                    Label("仅复制", systemImage: "doc.on.doc")
                                }
                                Divider()
                                Button {
                                    editing = tpl
                                } label: {
                                    Label("编辑", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    viewModel.deleteTemplate(tpl)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("提示词模板")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        editing = PromptTemplate(id: emptyUUID, name: "", content: "")
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("新建模板")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $editing) { tpl in
                PromptTemplateEditor(
                    viewModel: viewModel,
                    original: tpl,
                    onSave: { viewModel.updateTemplate($0) },
                    onAdd: { viewModel.addTemplate($0) }
                )
            }
        }
        .tint(viewModel.currentAccentColor)
    }
}
