import SwiftUI

struct BookListView: View {
    @ObservedObject var viewModel: ContentViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteAlert = false
    @State private var bookToDelete: Book?

    var body: some View {
        List {
            ForEach(viewModel.books) { book in
                Button(action: {
                    viewModel.loadBook(book)
                    dismiss()
                }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(book.title)
                                .foregroundColor(.primary)
                            if let progressText = viewModel.getBookProgressDisplay(book: book) {
                                Text(progressText)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        if viewModel.currentBookId == book.id {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        bookToDelete = book
                        showingDeleteAlert = true
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("选择书本")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) { 
                Button {
                    viewModel.showingDocumentPicker = true
                } label: {
                    Image(systemName: "plus.circle") 
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("完成") {
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $viewModel.showingDocumentPicker) {
            DocumentPicker(viewModel: viewModel)
        }
        .alert("确认删除", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if let book = bookToDelete {
                    viewModel.deleteBook(book)
                }
            }
        } message: {
            if let book = bookToDelete {
                Text("确定要删除《\(book.title)》吗？此操作不可恢复。")
            }
        }
    }
} 