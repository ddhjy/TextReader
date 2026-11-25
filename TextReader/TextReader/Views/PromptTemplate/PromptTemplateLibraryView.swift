import SwiftUI

/// 管理提示词模板：新建、修改、删除。
/// 「用」模板在选词页的「模板」菜单里；这里点一行就是修改这一条。
///
/// 自己不带导航容器：从选词页以弹层打开时由外面包一层并显示关闭按钮，从设置进入时直接压栈。
struct PromptTemplateLibraryView: View {
    @ObservedObject var viewModel: ContentViewModel
    let showsCloseButton: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var editing: PromptTemplate?
    @State private var templatePendingDeletion: PromptTemplate?

    var body: some View {
        Group {
            if viewModel.templates.isEmpty {
                ContentUnavailableView {
                    Label("还没有模板", systemImage: "text.badge.plus")
                } description: {
                    Text("模板是一段固定的提示词，选词之后可以把选中的文字套进去。")
                } actions: {
                    Button("新建模板") {
                        startNewTemplate()
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    Section {
                        ForEach(viewModel.templates) { template in
                            row(for: template)
                        }
                    } footer: {
                        Text("点一条可以修改。要用模板：在正文上按住选词，再点「模板」。")
                    }
                }
            }
        }
        // 模板没能存进磁盘时就在这一页说出来：这一页盖在阅读页上面，等回到阅读页再说就晚了。
        .noticeBanner(
            viewModel.notice,
            edge: .bottom,
            isCovered: editing != nil,
            errorsOnly: true,
            onShown: viewModel.noticeDidAppear,
            onDismiss: viewModel.dismissNotice
        )
        .navigationTitle("提示词模板")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    startNewTemplate()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("新建模板")
            }

            if showsCloseButton {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)

                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) {
                        dismiss()
                    }
                    .accessibilityLabel("关闭")
                }
            }
        }
        .sheet(item: $editing) { template in
            PromptTemplateEditor(
                viewModel: viewModel,
                original: template,
                onSave: { viewModel.updateTemplate($0) },
                onAdd: { viewModel.addTemplate($0) }
            )
        }
        .alert(
            "删除模板「\(ContentViewModel.shortTitle(templatePendingDeletion?.name ?? "", maxLength: 12))」？",
            isPresented: Binding(
                get: { templatePendingDeletion != nil },
                set: { if !$0 { templatePendingDeletion = nil } }
            ),
            presenting: templatePendingDeletion
        ) { template in
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                viewModel.deleteTemplate(template)
            }
        } message: { _ in
            Text("删除后无法恢复。")
        }
    }

    private func startNewTemplate() {
        editing = PromptTemplateEditor.newTemplateDraft()
    }

    private func row(for template: PromptTemplate) -> some View {
        Button {
            editing = template
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name)
                        .font(.headline)
                        .foregroundStyle(Color.primary)

                    Text(template.content)
                        .font(.caption)
                        .lineLimit(2)
                        .foregroundStyle(.secondary)

                    Text("用完后：\(template.destination?.shortName ?? "第一次用时再选")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("轻点修改")
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                templatePendingDeletion = template
            } label: {
                Label("删除", systemImage: "trash")
            }
            // 整个界面套了强调色，不单独指定的话「删除」会跟着变成蓝色。
            .tint(.red)
        }
    }
}
