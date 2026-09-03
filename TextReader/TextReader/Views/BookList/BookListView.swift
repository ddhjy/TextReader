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

    private var isEditing: Bool {
        editMode.isEditing
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
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "搜索书名"
        )
        .onChange(of: searchText) { _, _ in
            selectedBookIDs = selectedBookIDs.intersection(Set(deletableFilteredBooks.map(\.id)))
        }
        .onChange(of: editMode) { _, newMode in
            if !newMode.isEditing {
                selectedBookIDs.removeAll()
            }
        }
        .overlay {
            if filteredBooks.isEmpty && !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(isEditing ? "完成" : "编辑") {
                    if isEditing {
                        editMode = .inactive
                        selectedBookIDs.removeAll()
                    } else {
                        editMode = .active
                    }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
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
                .accessibilityLabel("导入")
            }

            ToolbarSpacer(.fixed, placement: .topBarTrailing)

            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .close) {
                    dismiss()
                }
                .accessibilityLabel("关闭")
            }

            if isEditing {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button(allDeletableSelected ? "取消全选" : "全选") {
                        if allDeletableSelected {
                            selectedBookIDs.removeAll()
                        } else {
                            selectedBookIDs = Set(deletableFilteredBooks.map(\.id))
                        }
                    }
                    .disabled(deletableFilteredBooks.isEmpty)

                    Spacer()

                    Button("删除", role: .destructive) {
                        showingDeleteAlert = true
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
        .alert(isEditing ? "删除所选书籍？" : deleteSingleTitle, isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if isEditing {
                    let toDelete = viewModel.books.filter { selectedBookIDs.contains($0.id) && !$0.isBuiltIn }
                    viewModel.deleteBooks(toDelete)
                    selectedBookIDs.removeAll()
                    editMode = .inactive
                } else if let book = bookToDelete {
                    viewModel.deleteBook(book)
                }
            }
        } message: {
            Text("此操作无法撤销。")
        }
    }

    private var allDeletableSelected: Bool {
        !deletableFilteredBooks.isEmpty && selectedBookIDs == Set(deletableFilteredBooks.map(\.id))
    }

    private var deleteSingleTitle: String {
        if let book = bookToDelete {
            return "删除「\(book.title)」？"
        }
        return "删除这本书？"
    }

    @ViewBuilder
    private func bookRow(_ book: Book) -> some View {
        if isEditing {
            bookRowContent(book)
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
                bookRowContent(book)
            }
        }
    }

    private func bookRowContent(_ book: Book) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .foregroundStyle(.primary)
                    .font(.body)
                    .lineLimit(1)

                if book.id == viewModel.currentBookId {
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
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
    }
}
