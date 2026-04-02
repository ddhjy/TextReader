import SwiftUI

struct BookEditView: View {
    @ObservedObject var viewModel: ContentViewModel
    @Environment(\.dismiss) private var dismiss
    
    let book: Book
    @State private var editedTitle: String
    @State private var editedContent: String
    @State private var isLoading = true
    @State private var showingSaveAlert = false
    @State private var saveError: String?
    
    init(viewModel: ContentViewModel, book: Book) {
        self.viewModel = viewModel
        self.book = book
        self._editedTitle = State(initialValue: book.title)
        self._editedContent = State(initialValue: "")
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                TextField("书名", text: $editedTitle)
                    .textFieldStyle(.roundedBorder)
                    .padding()
                
                TextEditor(text: $editedContent)
                    .padding(.horizontal)
                    .overlay(
                        Group {
                            if isLoading {
                                ProgressView("正在加载…")
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(Color.black.opacity(0.3))
                            }
                        }
                    )
            }
            .navigationTitle("编辑书籍")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                    .foregroundColor(viewModel.currentAccentColor)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        saveChanges()
                    }
                    .foregroundColor(viewModel.currentAccentColor)
                    .disabled(editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("已保存", isPresented: $showingSaveAlert) {
                Button("好的") { dismiss() }
            } message: {
                Text("修改已生效")
            }
            .alert("保存失败", isPresented: .init(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("好的") { }
            } message: {
                Text(saveError ?? "发生了未知错误，请稍后重试")
            }
        }
        .onAppear {
            loadBookContent()
        }
    }
    
    private func loadBookContent() {
        viewModel.libraryManager.loadBookContent(book: book) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let content):
                    self.editedContent = content
                    self.isLoading = false
                case .failure(let error):
                    self.editedContent = "内容加载失败，请返回重试"
                    self.isLoading = false
                }
            }
        }
    }
    
    private func saveChanges() {
        let trimmedTitle = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        
        let titleChanged = trimmedTitle != book.title
        let contentChanged = editedContent != viewModel.pages.joined(separator: " ")
        
        if titleChanged {
            viewModel.updateBookTitle(book: book, newTitle: trimmedTitle)
        }
        
        if contentChanged {
            viewModel.updateBookContent(book: book, newContent: editedContent) { success in
                if success && titleChanged {
                    self.showingSaveAlert = true
                } else if success {
                    self.showingSaveAlert = true
                } else {
                    self.saveError = "内容未能保存，请稍后重试"
                }
            }
        } else if titleChanged {
            showingSaveAlert = true
        } else {
            dismiss()
        }
    }
} 