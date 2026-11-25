import SwiftUI

struct BookEditView: View {
    @ObservedObject var viewModel: ContentViewModel
    @Environment(\.dismiss) private var dismiss
    
    let book: Book
    @State private var editedTitle: String
    @State private var editedContent: String
    @State private var originalContent: String = ""
    @State private var isLoading = true
    /// 正文没读出来。这时编辑框里没有原文，绝不能把它存回去盖掉原书。
    @State private var contentLoadFailed = false
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var showingDiscardConfirmation = false
    
    init(viewModel: ContentViewModel, book: Book) {
        self.viewModel = viewModel
        self.book = book
        self._editedTitle = State(initialValue: book.title)
        self._editedContent = State(initialValue: "")
    }

    private var trimmedTitle: String {
        editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isContentEditable: Bool {
        !isLoading && !contentLoadFailed
    }

    private var contentChanged: Bool {
        isContentEditable && editedContent != originalContent
    }

    private var isContentBlank: Bool {
        isContentEditable && editedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasChanges: Bool {
        trimmedTitle != book.title || contentChanged
    }

    private var canSave: Bool {
        !trimmedTitle.isEmpty && !isLoading && !isSaving && !isContentBlank
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("书名") {
                    TextField("书名", text: $editedTitle)
                }
                
                Section {
                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView("正在加载…")
                            Spacer()
                        }
                    } else if contentLoadFailed {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("正文没能读出来。现在可以只改书名，原来的正文不会被改动。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Button("重新读取正文") {
                                loadBookContent()
                            }
                        }
                        .padding(.vertical, 4)
                    } else {
                        TextEditor(text: $editedContent)
                            .frame(minHeight: 300)
                            .accessibilityLabel("正文")
                    }
                } header: {
                    Text("正文")
                } footer: {
                    if isContentBlank {
                        Text("正文不能为空。不想要这本书的话，回到书架左滑删除。")
                    }
                }
            }
            .disabled(isSaving)
            .navigationTitle("编辑书籍")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(hasChanges || isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        attemptDismiss()
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                            .accessibilityLabel("正在保存")
                    } else {
                        Button("保存") {
                            saveChanges()
                        }
                        .disabled(!canSave)
                    }
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
            .alert("保存失败", isPresented: .init(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("好") { }
            } message: {
                Text(saveError ?? "发生了未知错误，请稍后重试")
            }
        }
        .tint(viewModel.currentAccentColor)
        .onAppear {
            loadBookContent()
        }
    }

    private func attemptDismiss() {
        if hasChanges {
            showingDiscardConfirmation = true
        } else {
            dismiss()
        }
    }
    
    private func loadBookContent() {
        isLoading = true
        contentLoadFailed = false

        viewModel.libraryManager.loadBookContent(book: book) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let content):
                    self.editedContent = content
                    self.originalContent = content
                    self.contentLoadFailed = false
                case .failure:
                    self.editedContent = ""
                    self.originalContent = ""
                    self.contentLoadFailed = true
                }
                self.isLoading = false
            }
        }
    }
    
    private func saveChanges() {
        guard canSave else { return }

        var currentBook = book
        if trimmedTitle != book.title {
            guard viewModel.updateBookTitle(book: book, newTitle: trimmedTitle) else {
                saveError = "书名未能保存，请稍后重试"
                return
            }
            currentBook.title = trimmedTitle
        }
        
        guard contentChanged else {
            dismiss()
            return
        }

        isSaving = true
        viewModel.updateBookContent(book: currentBook, newContent: editedContent) { success in
            self.isSaving = false
            if success {
                self.dismiss()
            } else {
                self.saveError = "正文未能保存，请稍后重试"
            }
        }
    }
}
