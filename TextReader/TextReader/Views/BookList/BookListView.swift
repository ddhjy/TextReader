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
                                .font(.headline)
                                .lineLimit(1)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                if let progressText = viewModel.getBookProgressDisplay(book: book) {
                                    Text(progressText)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                
                                if let lastAccessedText = viewModel.getLastAccessedTimeDisplay(book: book) {
                                    Text(lastAccessedText)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
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
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Select Book")
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
                Button("Done") {
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $viewModel.showingDocumentPicker) {
            DocumentPicker(viewModel: viewModel)
        }
        .alert("Confirm Deletion", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let book = bookToDelete {
                    viewModel.deleteBook(book)
                }
            }
        } message: {
            if let book = bookToDelete {
                Text("Are you sure you want to delete \"\(book.title)\"? This action cannot be undone.")
            }
        }
    }
} 