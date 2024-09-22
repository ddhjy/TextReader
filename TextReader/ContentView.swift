// ContentView.swift
// TextReader
// Created by zengkai on 2024/9/22.

import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var model = ContentModel()
    @State private var showingBookList = false
    @State private var showingDocumentPicker: Bool = false
    @State private var searchText = ""
    @State private var showingSearchResults = false
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            NavigationView {
                VStack(spacing: 0) {
                    if model.isContentLoaded {
                        // 搜索栏
                        SearchBar(text: $searchText, onCommit: {
                            model.searchContent(searchText)
                            showingSearchResults = true
                        })
                        .padding(.horizontal)
                        .padding(.top)
                        .focused($isSearchFieldFocused)

                        // 内容显示区域
                        ScrollView {
                            Text(model.pages.isEmpty ? "没有内容可显示。" : model.pages[model.currentPageIndex])
                                .padding()
                                .frame(minHeight: geometry.size.height * 0.5)
                                .font(.body)
                                .lineSpacing(6)
                                .transition(.opacity)
                                .id(model.currentPageIndex)
                                .animation(.easeInOut, value: model.currentPageIndex)
                                .accessibility(label: Text(model.pages.isEmpty ? "没有内容可显示。" : model.pages[model.currentPageIndex]))
                            
                            Divider()

                            // 控制面板
                            ControlPanel(model: model, showingBookList: $showingBookList, showingDocumentPicker: $showingDocumentPicker)
                        }
                        .onTapGesture {
                            isSearchFieldFocused = false
                        }
                    } else {
                        ProgressView("加载中...")
                            .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    }
                }
                .navigationTitle(model.currentBook?.title ?? "阅读器")
                .sheet(isPresented: $showingBookList) {
                    BookListView(model: model)
                }
                .sheet(isPresented: $showingDocumentPicker) {
                    DocumentPicker(model: model)
                }
                .sheet(isPresented: $showingSearchResults) {
                    SearchResultsView(results: model.searchResults, onSelect: { index in
                        model.currentPageIndex = index
                        showingSearchResults = false
                    })
                }
            }
        }
        .onDisappear { model.saveCurrentBook() }
    }
}

// 控制面板视图
struct ControlPanel: View {
    @ObservedObject var model: ContentModel
    @Binding var showingBookList: Bool
    @Binding var showingDocumentPicker: Bool

    var body: some View {
        VStack(spacing: 15) {
            // 翻页控制
            PageControl(model: model)

            // 朗读控制
            ReadingControl(model: model)

            // 书本选择和导入按钮
            HStack {
                Button(action: { showingBookList = true }) {
                    Label("选择书本", systemImage: "book")
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                }

                Button(action: { showingDocumentPicker = true }) {
                    Label("从iCloud导入", systemImage: "icloud.and.arrow.down")
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding()
    }
}

// 翻页控制视图
struct PageControl: View {
    @ObservedObject var model: ContentModel

    var body: some View {
        HStack {
            Button(action: { model.previousPage() }) {
                HStack {
                    Image(systemName: "chevron.left")
                    Text("上一页").foregroundColor(.blue).disabled(model.currentPageIndex == 0)
                }
            }

            Spacer()

            Text("第 \(model.currentPageIndex + 1) / \(model.pages.count) 页")
                .font(.footnote)
                .foregroundColor(.gray)

            Spacer()

            Button(action: { model.nextPage() }) {
                HStack {
                    Text("下一页")
                    Image(systemName: "chevron.right").foregroundColor(.blue).disabled(model.currentPageIndex >= model.pages.count - 1)
                }
            }
        }
    }
}

// 朗读控制视图
struct ReadingControl: View {
    @ObservedObject var model: ContentModel

    var body: some View {
        HStack {
            Button(action: { model.readCurrentPage() }) {
                VStack {
                    Image(systemName: "play.fill").foregroundColor(.green)
                    Text("朗读").font(.caption)
                }
            }

            Button(action: { model.stopReading() }) {
                VStack {
                    Image(systemName: "stop.fill").foregroundColor(.red)
                    Text("停止").font(.caption)
                }
            }

            Picker("速度", selection: Binding(get: { self.model.readingSpeed }, set: { self.model.setReadingSpeed($0) })) {
                Text("1x").tag(1.0 as Float)
                Text("2.2x").tag(2.2 as Float)
                Text("3x").tag(3.0 as Float)
            }
            .pickerStyle(SegmentedPickerStyle())
            .frame(width: 150)

            Picker("音色", selection: Binding(get: { self.model.selectedVoice }, set: { self.model.setVoice($0!) })) {
                ForEach(model.availableVoices, id: \.identifier) { voice in
                    Text(voice.name).tag(voice as AVSpeechSynthesisVoice?)
                }
            }
            .pickerStyle(MenuPickerStyle())
        }
    }
}

// 搜索栏视图
struct SearchBar: View {
    @Binding var text: String
    var onCommit: () -> Void

    var body: some View {
        HStack {
            TextField("搜索...", text: $text, onCommit: onCommit)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.trailing, 8)

            if !text.isEmpty {
                Button(action: { self.text = "" }) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.gray).accessibility(label: Text("清除搜索内容"))
                        .buttonStyle(PlainButtonStyle())
                }
            }

            Button(action:onCommit) {
                Image(systemName: "magnifyingglass").foregroundColor(.blue).accessibility(label: Text("执行搜索"))
                    .padding(.vertical, 8)
            }
        }
    }
}

// 搜索结果视图
struct SearchResultsView: View {
    let results: [(Int, String)]
    let onSelect: (Int) -> Void
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        List(results, id:\.0) { index, preview in
            Button(action:{ 
                onSelect(index)
                presentationMode.wrappedValue.dismiss()
            }) {
                VStack(alignment:.leading) {
                    Text("第 \(index + 1) 页").font(.headline)
                    Text(preview).lineLimit(2)
                }
            }
        }
        .navigationTitle("搜索结果")
    }
}

// 在 ContentView 结构体外部添加这个按钮样式
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

class ContentModel: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var pages: [String] = []
    @Published var currentPageIndex: Int = 0 {
        didSet {
            if isContentLoaded, let currentBook = currentBook {
                let key = "bookProgress_\(currentBook.id)"
                UserDefaults.standard.set(currentPageIndex, forKey: key)
                print("保存进度: \(currentPageIndex) 到 \(key)") // 调试信息
            }
        }
    }
    private var savedPageIndex: Int?

    @Published var isReading: Bool = false

    @Published var readingSpeed: Float = UserDefaults.standard.float(forKey: "readingSpeed") {
        didSet {
            UserDefaults.standard.set(readingSpeed, forKey: "readingSpeed")
        }
    }

    @Published var selectedVoice: AVSpeechSynthesisVoice? {
        didSet {
            if let identifier = selectedVoice?.identifier {
                UserDefaults.standard.set(identifier, forKey: "selectedVoiceIdentifier")
            }
        }
    }

    @Published var availableVoices: [AVSpeechSynthesisVoice] = []

    private var synthesizer = AVSpeechSynthesizer()

    @Published var books: [Book] = []
    @Published var currentBook: Book? {
        didSet {
            if let book = currentBook {
                UserDefaults.standard.set(book.id, forKey: "currentBookID")
                loadBookProgress(for: book)
            }
        }
    }

    @Published var isContentLoaded: Bool = false

    @Published var searchResults: [(Int, String)] = []

    override init() {
        super.init()
        synthesizer.delegate = self
        loadBooks()
        loadSavedSettings()
        loadAvailableVoices()
    }

    private func loadBooks() {
        // 从 main bundle 中加载已有的书本
        let bookFiles = [
            ("思考快与慢", "思考快与慢"),
            ("罗素作品集", "罗素作品集")
        ]

        books = bookFiles.compactMap { (title, fileName) in
            if Bundle.main.url(forResource: fileName, withExtension: "txt") != nil {
                return Book(title: title, fileName: fileName)
            }
            return nil
        }

        // 修改这部分来加载上次阅读的书籍
        if let savedBookFileName = UserDefaults.standard.string(forKey: "currentBookID"),
           let savedBook = books.first(where: { $0.id == savedBookFileName }) {
            currentBook = savedBook
            loadBookContent(savedBook)
            print("加载上次阅读的书籍: \(savedBook.title)") // 调试信息
        } else if let firstBook = books.first {
            currentBook = firstBook
            loadBookContent(firstBook)
            print("加载第一本书籍: \(firstBook.title)") // 调试信息
        }
    }

    // 新增方法来加载书籍内容
    private func loadBookContent(_ book: Book) {
        if let url = Bundle.main.url(forResource: book.fileName, withExtension: "txt") {
            loadContent(from: url)
        }
    }

    private func loadSavedSettings() {
        readingSpeed = UserDefaults.standard.float(forKey: "readingSpeed")
        if readingSpeed == 0 {
            readingSpeed = 1.0 // 默认速度
        }

        if let savedVoiceIdentifier = UserDefaults.standard.string(forKey: "selectedVoiceIdentifier"),
           let savedVoice = AVSpeechSynthesisVoice(identifier: savedVoiceIdentifier) {
            selectedVoice = savedVoice
        } else if let defaultVoice = AVSpeechSynthesisVoice(language: "zh-CN") {
            selectedVoice = defaultVoice
        }
    }

    private func loadAvailableVoices() {
        availableVoices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.starts(with: "zh") }
        if let defaultVoice = AVSpeechSynthesisVoice(language: "zh-CN") {
            selectedVoice = defaultVoice
        }
    }

    func nextPage() {
        if currentPageIndex < pages.count - 1 {
            stopReading()
            currentPageIndex += 1
            saveBookProgress()
            if isReading {
                readCurrentPage()
            }
        }
    }

    func previousPage() {
        if currentPageIndex > 0 {
            stopReading()
            currentPageIndex -= 1
            saveBookProgress()
            if isReading {
                readCurrentPage()
            }
        }
    }

    func readCurrentPage() {
        if !pages.isEmpty && currentPageIndex < pages.count {
            isReading = true
            let utterance = AVSpeechUtterance(string: pages[currentPageIndex])
            utterance.voice = selectedVoice ?? AVSpeechSynthesisVoice(language: "zh-CN")
            utterance.rate = readingSpeed * AVSpeechUtteranceDefaultSpeechRate // 设置朗读速度
            synthesizer.speak(utterance)
        }
    }

    func stopReading() {
        synthesizer.stopSpeaking(at: .immediate)
        isReading = false
    }

    func setReadingSpeed(_ speed: Float) {
        readingSpeed = speed
        if isReading {
            stopReading()
            readCurrentPage()
        }
    }

    func setVoice(_ voice: AVSpeechSynthesisVoice) {
        selectedVoice = voice
        if isReading {
            stopReading()
            readCurrentPage()
        }
    }

    func loadBook(_ book: Book) {
        currentBook = book
        isContentLoaded = false
        loadBookProgress(for: book) // 先加载进度
        if let url = Bundle.main.url(forResource: book.fileName, withExtension: "txt") {
            loadContent(from: url) // 然后加载内容
        }
    }

    // AVSpeechSynthesizerDelegate 方法
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        if isReading {
            nextPage()
            if currentPageIndex < pages.count {
                readCurrentPage()
            } else {
                isReading = false
            }
        }
    }

    // 新增方法
    func importBookFromiCloud(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            print("无法访问文件")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let fileName = url.lastPathComponent
            let bookTitle = url.deletingPathExtension().lastPathComponent

            // 保存文件到应用的文档目录
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let savedURL = documentsURL.appendingPathComponent(fileName)
            try content.write(to: savedURL, atomically: true, encoding: .utf8)

            // 创建新书本并添加到列表
            let newBook = Book(title: bookTitle, fileName: fileName)
            DispatchQueue.main.async {
                self.books.append(newBook)
                self.currentBook = newBook
            }

            // 加载新书本内容
            loadContent(from: savedURL)

            print("成功导入书本：\(bookTitle)")
        } catch {
            print("导入书本时出错：\(error.localizedDescription)")
            DispatchQueue.main.async {
                // 显示错误警告（这需要在 UI 中实现）
                self.showErrorAlert(message: "导入书本时出错：\(error.localizedDescription)")
            }
        }
    }

    // 修改 loadContent 方法以接受 URL 参数
    private func loadContent(from url: URL) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                let sentences = content.components(separatedBy: CharacterSet(charactersIn: "。！？.!?"))
                                       .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

                var pages = [String]()
                var currentPage = ""
                var currentPageSize = 0
                let maxPageSize = 100

                for sentence in sentences {
                    let sentenceSize = sentence.count

                    if currentPageSize + sentenceSize > maxPageSize && !currentPage.isEmpty {
                        pages.append(currentPage.trimmingCharacters(in: .whitespacesAndNewlines))
                        currentPage = ""
                        currentPageSize = 0
                    }

                    currentPage += sentence + "。"
                    currentPageSize += sentenceSize + 1

                    if currentPageSize >= maxPageSize {
                        pages.append(currentPage.trimmingCharacters(in: .whitespacesAndNewlines))
                        currentPage = ""
                        currentPageSize = 0
                    }
                }

                if !currentPage.isEmpty {
                    pages.append(currentPage.trimmingCharacters(in: .whitespacesAndNewlines))
                }

                DispatchQueue.main.async {
                    self?.pages = pages
                    self?.isContentLoaded = true
                    self?.objectWillChange.send()
                    
                    // 在内容加载完成后设置正确的页面索引
                    if let savedIndex = self?.savedPageIndex, savedIndex < pages.count {
                        self?.currentPageIndex = savedIndex
                    } else {
                        self?.currentPageIndex = 0
                    }
                    
                    self?.savedPageIndex = nil // 清除临时保存的索引
                    print("内容加载完成，当前页面索引: \(self?.currentPageIndex ?? 0)") // 调试信息
                }
            } catch {
                print("加载内容时出错：\(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.showErrorAlert(message: "加载内容时出错：\(error.localizedDescription)")
                }
            }
        }
    }

    // 添加这个方法来显示错误警告
    func showErrorAlert(message: String) {
        // 在这里实现显示错误警告的逻辑
        // 例如，你可以设置一个 @Published 属性来触发 SwiftUI 视图中的警告显示
    }

    // 修改后的 loadBookProgress 方法
    private func loadBookProgress(for book: Book) {
        let key = "bookProgress_\(book.id)"
        savedPageIndex = UserDefaults.standard.integer(forKey: key)
        print("从 UserDefaults 加载进度: \(savedPageIndex ?? 0)") // 调试信息
    }

    // 修改后的 saveBookProgress 方法
    private func saveBookProgress() {
        if let book = currentBook {
            let key = "bookProgress_\(book.id)"
            UserDefaults.standard.set(currentPageIndex, forKey: key)
        }
    }

    // 修改后的 saveCurrentBook 方法
    func saveCurrentBook() {
        if let book = currentBook {
            UserDefaults.standard.set(book.id, forKey: "currentBookID")
            saveBookProgress()
        }
    }

    func searchContent(_ query: String) {
        searchResults = pages.enumerated().compactMap { index, page in
            if page.lowercased().contains(query.lowercased()) {
                return (index, page)
            }
            return nil
        }
    }
}

struct Book: Identifiable {
    var id: String { fileName }
    let title: String
    let fileName: String
}


struct BookListView: View {
    @ObservedObject var model: ContentModel
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        List(model.books) { book in
            Button(action: {
                model.loadBook(book)
                presentationMode.wrappedValue.dismiss()
            }) {
                Text(book.title)
            }
        }
        .navigationTitle("选择书本")
    }
}

// 新增 DocumentPicker 视图
struct DocumentPicker: UIViewControllerRepresentable {
    @ObservedObject var model: ContentModel
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.text], asCopy: true)
        picker.delegate = context.coordinator
        picker.shouldShowFileExtensions = true
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: DocumentPicker
        
        init(_ parent: DocumentPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            parent.model.importBookFromiCloud(url)
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}
