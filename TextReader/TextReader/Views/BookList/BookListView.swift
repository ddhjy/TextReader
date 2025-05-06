import SwiftUI

struct BookListView: View {
    @ObservedObject var viewModel: ContentViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteAlert = false
    @State private var bookToDelete: Book?
    @State private var showingPasteImport = false

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
                Menu {
                    Button {
                        viewModel.showingDocumentPicker = true    // 原文件导入
                    } label: {
                        Label("从文件导入", systemImage: "doc")
                    }

                    Button {
                        showingPasteImport = true                 // 打开粘贴导入
                    } label: {
                        Label("粘贴文本", systemImage: "doc.on.clipboard")
                    }
                    
                    Button {
                        viewModel.showingWiFiTransferView = true   // 触发 Sheet
                    } label: {
                        Label("WiFi 传输", systemImage: "wifi")     // 系统图标
                    }
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
        .sheet(isPresented: $showingPasteImport) {
            PasteImportView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showingWiFiTransferView) {
            WiFiTransferView(viewModel: viewModel)
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