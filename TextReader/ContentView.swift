// ContentView.swift
// TextReader
// Created by zengkai on 2024/9/22.

import SwiftUI
import AVFoundation
import MediaPlayer

struct ContentView: View {
    @StateObject private var model = ContentModel()
    @State private var showingBookList = false
    @State private var showingDocumentPicker = false
    @State private var showingSearchView = false

    var body: some View {
        NavigationView {
            if model.isContentLoaded {
                VStack(spacing: 0) {
                    ContentDisplay(model: model)
                    ControlPanel(model: model)
                        .background(Color(UIColor.secondarySystemBackground))
                }
                .navigationTitle(model.currentBook?.title ?? "TextReader")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: { showingBookList = true }) {
                            Image(systemName: "book")
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { showingSearchView = true }) {
                            Image(systemName: "magnifyingglass")
                        }
                    }
                }
            } else {
                ProgressView()
                    .scaleEffect(1.5)
                    .navigationTitle("加载中...")
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(isPresented: $showingBookList) {
            NavigationView {
                BookListView(model: model)
            }
        }
        .sheet(isPresented: $showingDocumentPicker) {
            DocumentPicker(model: model)
        }
        .sheet(isPresented: $showingSearchView) {
            NavigationView {
                SearchView(model: model)
            }
        }
        .onDisappear {
            model.saveCurrentBook()
        }
    }
}

struct ContentDisplay: View {
    @ObservedObject var model: ContentModel

    var body: some View {
        ScrollView {
            Text(model.pages.isEmpty ? "无内容" : model.pages[model.currentPageIndex])
                .padding()
                .font(.system(size: 18, weight: .regular, design: .serif))
                .multilineTextAlignment(.leading)
        }
    }
}

struct ControlPanel: View {
    @ObservedObject var model: ContentModel

    var body: some View {
        VStack(spacing: 16) {
            Divider()
            PageControl(model: model)
            Divider()
            ReadingControl(model: model)
        }
        .padding()
    }
}

struct PageControl: View {
    @ObservedObject var model: ContentModel

    var body: some View {
        VStack(spacing: 8) {
            Text("\(model.currentPageIndex + 1) / \(model.pages.count)")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Button(action: { model.previousPage() }) {
                    Image(systemName: "chevron.left")
                        .font(.title)
                }
                .disabled(model.currentPageIndex == 0)

                Spacer()

                Button(action: { model.toggleReading() }) {
                    Image(systemName: model.isReading ? "pause.circle.fill" : "play.circle.fill")
                        .font(.largeTitle)
                }

                Spacer()

                Button(action: { model.nextPage() }) {
                    Image(systemName: "chevron.right")
                        .font(.title)
                }
                .disabled(model.currentPageIndex >= model.pages.count - 1)
            }
            .padding(.horizontal)
        }
    }
}

struct ReadingControl: View {
    @ObservedObject var model: ContentModel

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("音色")
                Spacer()
                Picker("音色", selection: $model.selectedVoice) {
                    ForEach(model.availableVoices, id: \.identifier) { voice in
                        Text(voice.name).tag(voice as AVSpeechSynthesisVoice?)
                    }
                }
                .pickerStyle(MenuPickerStyle())
            }

            HStack {
                Text("速度")
                Spacer()
                Picker("速度", selection: $model.readingSpeed) {
                    Text("1x").tag(1.0 as Float)
                    Text("1.5x").tag(1.5 as Float)
                    Text("2x").tag(2.0 as Float)
                    Text("3x").tag(3.0 as Float)
                }
                .pickerStyle(MenuPickerStyle())
            }
        }
        .padding(.horizontal)
    }
}

struct SearchView: View {
    @ObservedObject var model: ContentModel
    @State private var searchText = ""
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        VStack {
            SearchBar(text: $searchText, onCommit: {
                model.searchContent(searchText)
            })
            .padding()

            List(model.searchResults, id: \.0) { index, preview in
                Button(action: {
                    model.currentPageIndex = index
                    presentationMode.wrappedValue.dismiss()
                }) {
                    VStack(alignment: .leading) {
                        Text("第 \(index + 1) 页").font(.headline)
                        Text(preview).lineLimit(2)
                    }
                }
            }
        }
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("取消") {
                    presentationMode.wrappedValue.dismiss()
                }
            }
        }
    }
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("完成") {
                    presentationMode.wrappedValue.dismiss()
                }
            }
        }
    }
}

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
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                        .accessibility(label: Text("清除搜索内容"))
                }
                .buttonStyle(PlainButtonStyle())
            }

            Button(action: onCommit) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.blue)
                    .accessibility(label: Text("执行搜索"))
                    .padding(.vertical, 8)
            }
        }
        .padding(.horizontal)
    }
}

// 按钮样式
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
            }
        }
    }
    private var savedPageIndex: Int?

    @Published var isReading = false

    @Published var readingSpeed: Float = UserDefaults.standard.float(forKey: "readingSpeed") {
        didSet {
            UserDefaults.standard.set(readingSpeed, forKey: "readingSpeed")
            if isReading {
                restartReading()
            }
        }
    }

    @Published var selectedVoice: AVSpeechSynthesisVoice? {
        didSet {
            if let identifier = selectedVoice?.identifier {
                UserDefaults.standard.set(identifier, forKey: "selectedVoiceIdentifier")
            }
            if isReading {
                restartReading()
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

    @Published var isContentLoaded = false

    @Published var searchResults: [(Int, String)] = []

    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    override init() {
        super.init()
        synthesizer.delegate = self
        loadBooks()
        loadSavedSettings()
        loadAvailableVoices()
        setupAudioSession()
        setupRemoteCommandCenter()
    }

    private func loadBooks() {
        // 从 main bundle 中加载已有的书本
        let bookFiles = [
            ("思考快与慢", "思考快与慢"),
            ("罗素作品集", "罗素作品集"),
            ("哲学研究", "哲学研究")
        ]

        books = bookFiles.compactMap { (title, fileName) in
            if Bundle.main.url(forResource: fileName, withExtension: "txt") != nil {
                return Book(title: title, fileName: fileName)
            }
            return nil
        }

        // 加载上次阅读的书籍
        if let savedBookFileName = UserDefaults.standard.string(forKey: "currentBookID"),
           let savedBook = books.first(where: { $0.id == savedBookFileName }) {
            currentBook = savedBook
            loadBookContent(savedBook)
        } else if let firstBook = books.first {
            currentBook = firstBook
            loadBookContent(firstBook)
        }
    }

    private func loadBookContent(_ book: Book) {
        if let url = Bundle.main.url(forResource: book.fileName, withExtension: "txt") {
            loadContent(from: url)
        }
    }

    private func loadSavedSettings() {
        let speed = UserDefaults.standard.float(forKey: "readingSpeed")
        readingSpeed = speed == 0 ? 1.0 : speed

        if let savedVoiceIdentifier = UserDefaults.standard.string(forKey: "selectedVoiceIdentifier"),
           let savedVoice = AVSpeechSynthesisVoice(identifier: savedVoiceIdentifier) {
            selectedVoice = savedVoice
        } else {
            selectedVoice = AVSpeechSynthesisVoice(language: "zh-CN")
        }
    }

    private func loadAvailableVoices() {
        availableVoices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.starts(with: "zh") }
        if selectedVoice == nil {
            selectedVoice = availableVoices.first
        }
    }

    func nextPage() {
        guard currentPageIndex < pages.count - 1 else { return }
        stopReading()
        currentPageIndex += 1
        saveBookProgress()
        if isReading {
            readCurrentPage()
        }
    }

    func previousPage() {
        guard currentPageIndex > 0 else { return }
        stopReading()
        currentPageIndex -= 1
        saveBookProgress()
        if isReading {
            readCurrentPage()
        }
    }

    func toggleReading() {
        isReading ? stopReading() : readCurrentPage()
    }

    func readCurrentPage() {
        guard !pages.isEmpty, currentPageIndex < pages.count else { return }
        isReading = true
        let utterance = AVSpeechUtterance(string: pages[currentPageIndex])
        utterance.voice = selectedVoice ?? AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = readingSpeed * AVSpeechUtteranceDefaultSpeechRate

        startBackgroundTask()
        synthesizer.speak(utterance)
    }

    func stopReading() {
        synthesizer.stopSpeaking(at: .immediate)
        isReading = false
        endBackgroundTask()
    }

    private func restartReading() {
        stopReading()
        readCurrentPage()
    }

    private func startBackgroundTask() {
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }

    func loadBook(_ book: Book) {
        currentBook = book
        isContentLoaded = false
        loadBookProgress(for: book)
        if let url = Bundle.main.url(forResource: book.fileName, withExtension: "txt") {
            loadContent(from: url)
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
                endBackgroundTask()
            }
        } else {
            endBackgroundTask()
        }
    }

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
                self.showErrorAlert(message: "导入书本时出错：\(error.localizedDescription)")
            }
        }
    }

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

                    // 在内容加载完成后设置正确的页面索引
                    if let savedIndex = self?.savedPageIndex, savedIndex < pages.count {
                        self?.currentPageIndex = savedIndex
                    } else {
                        self?.currentPageIndex = 0
                    }
                    self?.savedPageIndex = nil
                }
            } catch {
                print("加载内容时出错：\(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.showErrorAlert(message: "加载内容时出错：\(error.localizedDescription)")
                }
            }
        }
    }

    func showErrorAlert(message: String) {
        // 在这里实现显示错误警告的逻辑
    }

    private func loadBookProgress(for book: Book) {
        let key = "bookProgress_\(book.id)"
        savedPageIndex = UserDefaults.standard.integer(forKey: key)
    }

    private func saveBookProgress() {
        if let book = currentBook {
            let key = "bookProgress_\(book.id)"
            UserDefaults.standard.set(currentPageIndex, forKey: key)
        }
    }

    func saveCurrentBook() {
        if let book = currentBook {
            UserDefaults.standard.set(book.id, forKey: "currentBookID")
            saveBookProgress()
        }
    }

    func searchContent(_ query: String) {
        searchResults = pages.enumerated().compactMap { index, page in
            if page.contains(query) {
                return (index, page)
            }
            return nil
        }
    }

    func updateNowPlayingInfo() {
        guard let bookTitle = currentBook?.title else { return }
        let nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: bookTitle,
            MPNowPlayingInfoPropertyPlaybackRate: isReading ? 1.0 : 0.0,
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("设置音频会话失败: \(error)")
        }
    }

    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.stopReading()
            self?.updateNowPlayingInfo()
            return .success
        }

        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.readCurrentPage()
            self?.updateNowPlayingInfo()
            return .success
        }
    }
}

struct Book: Identifiable {
    var id: String { fileName }
    let title: String
    let fileName: String
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
