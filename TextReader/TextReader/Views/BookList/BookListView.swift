import SwiftUI

struct BookListView: View {
    @ObservedObject var viewModel: ContentViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteAlert = false
    @State private var bookToDelete: Book?
    @State private var showingPasteImport = false
    @State private var editMode: EditMode = .inactive
    @State private var selectedBookIDs = Set<String>()
    @State private var searchText = ""

    private var isEditing: Bool {
        editMode.isEditing
    }

    private var filteredBooks: [Book] {
        if searchText.isEmpty {
            return viewModel.books
        }
        return viewModel.books.filter { book in
            book.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var deletableFilteredBooks: [Book] {
        filteredBooks.filter { !$0.isBuiltIn }
    }

    var body: some View {
        List(selection: $selectedBookIDs) {
            ForEach(filteredBooks) { book in
                bookRow(book)
                    .tag(book.id)
                    .selectionDisabled(book.isBuiltIn)
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
        .environment(\.editMode, $editMode)
        .navigationTitle("书架")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .searchable(text: $searchText, prompt: "搜索书名")
        .onChange(of: searchText) { _, _ in
            selectedBookIDs = selectedBookIDs.intersection(Set(deletableFilteredBooks.map { $0.id }))
        }
        .overlay {
            if viewModel.books.isEmpty {
                ContentUnavailableView {
                    Label("书架为空", systemImage: "books.vertical")
                } description: {
                    Text("从右上角加号导入 TXT 文件开始阅读。")
                }
            } else if filteredBooks.isEmpty && !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(isEditing ? "完成" : "编辑") {
                    withAnimation {
                        if isEditing {
                            editMode = .inactive
                            selectedBookIDs.removeAll()
                        } else {
                            editMode = .active
                        }
                    }
                }
                .disabled(viewModel.books.isEmpty)
            }
            
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !isEditing {
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
                            Label("Wi‑Fi 传输", systemImage: "wifi")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("导入书籍")

                    Button(role: .close) {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("关闭")
                }
            }

            ToolbarItemGroup(placement: .bottomBar) {
                if isEditing {
                    let allSelected = !deletableFilteredBooks.isEmpty && selectedBookIDs.count >= deletableFilteredBooks.count
                    Button(allSelected ? "取消全选" : "全选") {
                        if allSelected {
                            selectedBookIDs.removeAll()
                        } else {
                            selectedBookIDs = Set(deletableFilteredBooks.map { $0.id })
                        }
                    }
                    .disabled(deletableFilteredBooks.isEmpty)

                    Spacer()

                    Button(role: .destructive) {
                        showingDeleteAlert = true
                    } label: {
                        Text(selectedBookIDs.isEmpty ? "删除" : "删除 (\(selectedBookIDs.count))")
                    }
                    .disabled(selectedBookIDs.isEmpty)
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
        .alert(isEditing ? "删除所选书籍？" : "删除「\(bookToDelete?.title ?? "此书")」？", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if isEditing {
                    let toDelete = viewModel.books.filter { selectedBookIDs.contains($0.id) && !$0.isBuiltIn }
                    viewModel.deleteBooks(toDelete)
                    selectedBookIDs.removeAll()
                    editMode = .inactive
                } else if let book = bookToDelete {
                    viewModel.deleteBook(book)
                    bookToDelete = nil
                }
            }
        } message: {
            Text("此操作无法撤销。")
        }
    }

    @ViewBuilder
    private func bookRow(_ book: Book) -> some View {
        if isEditing {
            bookContent(book)
        } else {
            Button {
                if viewModel.currentBookId != book.id {
                    viewModel.loadBook(book, waitForFullContentBeforeCompletion: true) {
                        dismiss()
                    }
                } else {
                    dismiss()
                }
            } label: {
                bookContent(book)
            }
            .buttonStyle(.plain)
        }
    }

    private func bookContent(_ book: Book) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(book.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                if viewModel.currentBookId == book.id {
                    Text("正在阅读")
                        .font(.subheadline)
                        .foregroundStyle(viewModel.currentAccentColor)
                } else if let lastAccessed = viewModel.getLastAccessedTimeDisplay(book: book) {
                    Text(lastAccessed)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            if let progressText = viewModel.getBookProgressDisplay(book: book) {
                Text(progressText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
