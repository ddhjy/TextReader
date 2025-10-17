import SwiftUI

struct BookListView: View {
    @ObservedObject var viewModel: ContentViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteAlert = false
    @State private var bookToDelete: Book?
    @State private var showingPasteImport = false
    @State private var isEditing = false
    @State private var selectedBookIDs = Set<String>()

    var body: some View {
        List(selection: isEditing ? $selectedBookIDs : .constant(Set<String>())) {
            ForEach(viewModel.books) { book in
                HStack {
                    if isEditing {
                        Image(systemName: selectedBookIDs.contains(book.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(selectedBookIDs.contains(book.id) ? viewModel.currentAccentColor : .secondary)
                            .onTapGesture {
                                if selectedBookIDs.contains(book.id) {
                                    selectedBookIDs.remove(book.id)
                                } else {
                                    selectedBookIDs.insert(book.id)
                                }
                            }
                    }
                    Button(action: {
                        if isEditing {
                            if selectedBookIDs.contains(book.id) {
                                selectedBookIDs.remove(book.id)
                            } else {
                                selectedBookIDs.insert(book.id)
                            }
                        } else {
                            viewModel.loadBook(book)
                            dismiss()
                        }
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
                            if viewModel.currentBookId == book.id && !isEditing {
                                Image(systemName: "checkmark")
                                    .foregroundColor(viewModel.currentAccentColor)
                            }
                        }
                    }
                    .disabled(isEditing && book.isBuiltIn)
                }
                .contentShape(Rectangle())
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if !isEditing {
                        Button(role: .destructive) {
                            bookToDelete = book
                            showingDeleteAlert = true
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        
                        if !book.isBuiltIn {
                            Button {
                                viewModel.bookToEdit = book
                                viewModel.showingBookEdit = true
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                            .tint(viewModel.currentAccentColor)
                        }
                    }
                }
            }
        }
        .navigationTitle("选择书籍")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) { 
                Menu {
                    Button {
                        viewModel.showingDocumentPicker = true
                    } label: {
                        Label("从文件导入", systemImage: "doc")
                    }

                    Button {
                        showingPasteImport = true
                    } label: {
                        Label("粘贴文本", systemImage: "doc.on.clipboard")
                    }
                    
                    Button {
                        viewModel.showingWiFiTransferView = true
                    } label: {
                        Label("WiFi 传输", systemImage: "wifi")
                    }
                } label: {
                    Image(systemName: "plus.circle")
                        .foregroundColor(viewModel.currentAccentColor)
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                if isEditing {
                    HStack(spacing: 16) {
                        Button("全选") {
                            selectedBookIDs = Set(viewModel.books.filter { !$0.isBuiltIn }.map { $0.id })
                        }
                        .disabled(viewModel.books.filter { !$0.isBuiltIn }.isEmpty)

                        Button(role: .destructive) {
                            // 弹出确认删除对话框（批量）
                            showingDeleteAlert = true
                        } label: {
                            Text("删除")
                        }
                        .disabled(selectedBookIDs.isEmpty)

                        Button("完成") {
                            isEditing = false
                            selectedBookIDs.removeAll()
                        }
                        .foregroundColor(viewModel.currentAccentColor)
                    }
                } else {
                    HStack(spacing: 16) {
                        Button("编辑") {
                            isEditing = true
                            selectedBookIDs.removeAll()
                        }
                        Button("完成") {
                            dismiss()
                        }
                        .foregroundColor(viewModel.currentAccentColor)
                    }
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
        .sheet(isPresented: $viewModel.showingBookEdit) {
            if let book = viewModel.bookToEdit {
                BookEditView(viewModel: viewModel, book: book)
            }
        }
        .alert(isEditing ? "确认删除所选书籍" : "确认删除", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if isEditing {
                    let toDelete = viewModel.books.filter { selectedBookIDs.contains($0.id) && !$0.isBuiltIn }
                    viewModel.deleteBooks(toDelete)
                    selectedBookIDs.removeAll()
                    isEditing = false
                } else if let book = bookToDelete {
                    viewModel.deleteBook(book)
                }
            }
        } message: {
            if isEditing {
                Text("将删除所选书籍，且无法恢复。")
            } else if let book = bookToDelete {
                Text("确定要删除“\(book.title)”吗？该操作无法撤销。")
            }
        }
    }
} 