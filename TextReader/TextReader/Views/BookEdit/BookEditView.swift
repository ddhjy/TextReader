import SwiftUI

struct BookEditView: View {
    @ObservedObject var viewModel: ContentViewModel
    @Environment(\.dismiss) private var dismiss
    
    let book: Book
    @State private var editedTitle: String
    @State private var editedContent: String
    @State private var originalContent: String = ""
    @State private var isLoading = true
    @State private var saveError: String?
    @State private var showingDiscardConfirmation = false
    
    init(viewModel: ContentViewModel, book: Book) {
        self.viewModel = viewModel
        self.book = book
        self._editedTitle = State(initialValue: book.title)
        self._editedContent = State(initialValue: "")
    }

    private var hasChanges: Bool {
        editedTitle.trimmingCharacters(in: .whitespacesAndNewlines) != book.title
            || (!isLoading && editedContent != originalContent)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("书名") {
                    TextField("书名", text: $editedTitle)
                }
                
                Section("内容") {
                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView("正在加载…")
                            Spacer()
                        }
                    } else {
                        TextEditor(text: $editedContent)
                            .frame(minHeight: 300)
                    }
                }
            }
            .navigationTitle("编辑书籍")
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
                        saveChanges()
                    }
                    .disabled(editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
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
        viewModel.libraryManager.loadBookContent(book: book) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let content):
                    self.editedContent = content
                    self.originalContent = content
                    self.isLoading = false
                case .failure:
                    self.editedContent = "内容加载失败，请返回重试"
                    self.originalContent = self.editedContent
                    self.isLoading = false
                }
            }
        }
    }
    
    private func saveChanges() {
        let trimmedTitle = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        
        let titleChanged = trimmedTitle != book.title
        let contentChanged = editedContent != originalContent
        
        if titleChanged {
            viewModel.updateBookTitle(book: book, newTitle: trimmedTitle)
        }
        
        if contentChanged {
            viewModel.updateBookContent(book: book, newContent: editedContent) { success in
                if success {
                    self.dismiss()
                } else {
                    self.saveError = "内容未能保存，请稍后重试"
                }
            }
        } else {
            dismiss()
        }
    }
}
