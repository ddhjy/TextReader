import SwiftUI

struct BookListView: View {
    @ObservedObject var viewModel: ContentViewModel
    @ObservedObject var session: AppSessionController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingDeleteAlert = false
    /// 确认框问的是哪几本。弹出时记下来，之后选择怎么变，确认框里的书名和删掉的书都以它为准。
    @State private var pendingDeletion: [Book] = []
    @State private var deleteAlertMessage = ""
    @State private var importMethod: ImportMethod?
    @State private var editMode: EditMode = .inactive
    @State private var selectedBookIDs = Set<String>()
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

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

    private func confirmDeletion(of books: [Book]) {
        let targets = books.filter { !$0.isBuiltIn }
        guard !targets.isEmpty else { return }
        pendingDeletion = targets
        deleteAlertMessage = Self.deleteConfirmationMessage(for: targets, currentBookId: viewModel.currentBookId)
        showingDeleteAlert = true
    }

    var body: some View {
        List(selection: $selectedBookIDs) {
            // 审核样例状态下书架里只有示例文本，看上去像是书全丢了。
            // 在「发现书不见了」的这个地方直接说清楚，并给出一步切回去的入口。
            if session.activeProfile == .reviewSample && searchText.isEmpty {
                Section {
                    Label("现在看到的是审核样例数据，你的日常书架还在", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .selectionDisabled(true)

                    Button {
                        session.switchProfile(to: .personal)
                        dismiss()
                    } label: {
                        Label("切回日常状态", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(isEditing)
                    .selectionDisabled(true)
                }
            }

            ForEach(filteredBooks) { book in
                bookRow(book)
                    .tag(book.id)
                    .selectionDisabled(book.isBuiltIn)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        // 内置的使用说明删不掉，就不摆一个点了没用的「删除」。
                        if !isEditing && !book.isBuiltIn {
                            Button(role: .destructive) {
                                confirmDeletion(of: [book])
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            // 整个界面套了强调色，不单独指定的话「删除」会跟着变成蓝色。
                            .tint(.red)

                            Button {
                                viewModel.bookToEdit = book
                                viewModel.showingBookEdit = true
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                            .tint(.gray)
                        }
                    }
            }
        }
        .environment(\.editMode, $editMode)
        .noticeBanner(
            viewModel.notice,
            edge: .bottom,
            isCovered: importMethod != nil || viewModel.showingBookEdit,
            onShown: viewModel.noticeDidAppear,
            onDismiss: viewModel.dismissNotice
        )
        .navigationTitle("书架")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .onScrollPhaseChange { _, newPhase, context in
            guard newPhase == .interacting, isSearchFocused else { return }
            let geometry = context.geometry
            if geometry.contentOffset.y + geometry.contentInsets.top <= 1 {
                isSearchFocused = false
            }
        }
        // 搜索框一直完整显示，不跟着列表滚动收起。让它自动收起的话，系统字号调大后它一出现就停在
        // 「收了一半」的状态：只剩一条灰底，放大镜和「搜索书名」都看不见。
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "搜索书名"
        )
        .searchFocused($isSearchFocused)
        .background {
            SheetDismissKeyboardObserver {
                isSearchFocused = false
            }
        }
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
                // 这里是「多选后删除」，叫「选择」；改书名、改正文在左滑的「编辑」里，两者不重名。
                Button(isEditing ? "完成" : "选择") {
                    if isEditing {
                        editMode = .inactive
                        selectedBookIDs.removeAll()
                    } else {
                        editMode = .active
                    }
                }
                .disabled(!isEditing && deletableFilteredBooks.isEmpty)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ImportMenuItems { method in
                        importMethod = method
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .menuOrder(.fixed)
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

                    Button(selectedBookIDs.isEmpty ? "删除" : "删除 \(selectedBookIDs.count) 本", role: .destructive) {
                        confirmDeletion(of: viewModel.books.filter { selectedBookIDs.contains($0.id) })
                    }
                    .tint(.red)
                    .disabled(selectedBookIDs.isEmpty)
                }
            }
        }
        .importSheet($importMethod, viewModel: viewModel)
        .sheet(isPresented: $viewModel.showingBookEdit) {
            if let book = viewModel.bookToEdit {
                BookEditView(viewModel: viewModel, book: book)
            }
        }
        .alert(
            Self.deleteConfirmationTitle(for: pendingDeletion),
            isPresented: $showingDeleteAlert
        ) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                viewModel.deleteBooks(pendingDeletion)
                if isEditing {
                    selectedBookIDs.removeAll()
                    editMode = .inactive
                }
            }
        } message: {
            Text(deleteAlertMessage)
        }
    }

    private var allDeletableSelected: Bool {
        !deletableFilteredBooks.isEmpty && selectedBookIDs == Set(deletableFilteredBooks.map(\.id))
    }

    /// 确认框标题：说清楚要删几本。
    static func deleteConfirmationTitle(for books: [Book]) -> String {
        switch books.count {
        case 0:
            return "删除这本书？"
        case 1:
            return "删除《\(ContentViewModel.shortTitle(books[0].title))》？"
        default:
            return "删除 \(books.count) 本书？"
        }
    }

    /// 确认框正文：多选时列出是哪几本（最多三个书名），并提醒删的是不是正在读的那本。
    static func deleteConfirmationMessage(for books: [Book], currentBookId: String?) -> String {
        var sentences: [String] = []

        if books.count > 1 {
            let names = books.prefix(3)
                .map { "《\(ContentViewModel.shortTitle($0.title, maxLength: 12))》" }
                .joined(separator: "、")
            sentences.append(books.count > 3 ? "\(names)等 \(books.count) 本。" : "\(names)。")
        }

        if books.contains(where: { $0.id == currentBookId }) {
            sentences.append(books.count > 1 ? "其中有正在读的书。" : "这是正在读的书。")
        }

        sentences.append("删除后无法恢复。")
        return sentences.joined(separator: "\n")
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

    private func subtitle(for book: Book) -> String? {
        if book.id == viewModel.currentBookId {
            return "正在阅读"
        }
        if let lastAccessed = viewModel.getLastAccessedTimeDisplay(book: book) {
            return lastAccessed
        }
        return book.isBuiltIn ? nil : "还没读过"
    }

    private func bookRowContent(_ book: Book) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // 字号调到「辅助功能」那几档时，进度挪到书名下面，把整行的宽度都留给书名。
                VStack(alignment: .leading, spacing: 4) {
                    titleLine(for: book, lineLimit: 3)

                    HStack(alignment: .firstTextBaseline) {
                        subtitleText(for: book)
                        Spacer(minLength: 8)
                        progressText(for: book)
                    }
                }
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        titleLine(for: book, lineLimit: 2)
                        subtitleText(for: book)
                    }

                    Spacer()

                    progressText(for: book)
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// 书名放不下时省略中间、留住结尾：同名的书靠结尾的「-2」「-3」区分，结尾被省掉就分不出是哪一本。
    private func titleLine(for book: Book, lineLimit: Int) -> some View {
        HStack(spacing: 6) {
            Text(book.title)
                .foregroundStyle(Color.primary)
                .font(.body)
                .lineLimit(lineLimit)
                .truncationMode(.middle)

            if book.isBuiltIn {
                Text("内置")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                    .fixedSize()
            }
        }
    }

    @ViewBuilder
    private func subtitleText(for book: Book) -> some View {
        if let subtitle = subtitle(for: book) {
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
        }
    }

    @ViewBuilder
    private func progressText(for book: Book) -> some View {
        if let progress = viewModel.getBookProgressDisplay(book: book) {
            Text(progress)
                .font(.caption.monospacedDigit())
                .foregroundStyle(Color.secondary)
                .lineLimit(1)
        }
    }
}
