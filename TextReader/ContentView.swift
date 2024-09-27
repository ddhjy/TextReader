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
            ZStack {
                Color(UIColor.systemBackground).edgesIgnoringSafeArea(.all)

                if model.isContentLoaded {
                    VStack(spacing: 0) {
                        TopBar(showingBookList: $showingBookList, showingSearchView: $showingSearchView)
                            .background(Color(UIColor.secondarySystemBackground))
                        ContentDisplay(model: model)
                        ControlPanel(model: model, showingBookList: $showingBookList, showingDocumentPicker: $showingDocumentPicker)
                            .background(Color(UIColor.secondarySystemBackground))
                    }
                } else {
                    ProgressView()
                        .scaleEffect(1.5)
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingBookList) {
                BookListView(model: model)
            }
            .sheet(isPresented: $showingDocumentPicker) {
                DocumentPicker(model: model)
            }
            .sheet(isPresented: $showingSearchView) {
                SearchView(model: model)
            }
            .onDisappear {
                model.saveCurrentBook()
            }
        }
    }
}

// 分离顶栏视图
struct TopBar: View {
    @Binding var showingBookList: Bool
    @Binding var showingSearchView: Bool

    var body: some View {
        HStack {
            Button(action: { showingBookList = true }) {
                Image(systemName: "book")
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(22)
            }
            Spacer()
            Button(action: { showingSearchView = true }) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(22)
            }
        }
        .padding()
    }
}

// 分离内容显示视图
struct ContentDisplay: View {
    @ObservedObject var model: ContentModel

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                Text(model.pages.isEmpty ? "无内容" : model.pages[model.currentPageIndex])
                    .padding()
                    .font(.system(size: 18, weight: .regular, design: .serif))
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
                    .id(model.currentPageIndex)
            }
        }
    }
}

// 新增 SearchView
struct SearchView: View {
    @ObservedObject var model: ContentModel
    @State private var searchText = ""
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
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
            .navigationBarItems(trailing: Button("取消") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}

// 控制面板视图
struct ControlPanel: View {
    @ObservedObject var model: ContentModel
    @Binding var showingBookList: Bool
    @Binding var showingDocumentPicker: Bool

    var body: some View {
        VStack(spacing: 20) {
            PageControl(model: model)
            ReadingControl(model: model)
        }
        .padding()
    }
}

struct PageControl: View {
    @ObservedObject var model: ContentModel

    var body: some View {
        Text("\(model.currentPageIndex + 1) / \(model.pages.count)")
            .font(.caption)
            .foregroundColor(.secondary)
            .padding()
        HStack {
            Button(action: { model.previousPage() }) {
                Image(systemName: "chevron.left")
                    .foregroundColor(.primary)
                    .frame(width: 60, height: 60)
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(30)
            }
            .disabled(model.currentPageIndex == 0)

            Spacer()

            Button(action: {
                model.toggleReading()
            }) {
                Image(systemName: model.isReading ? "stop.fill" : "play.fill")
                    .foregroundColor(.white)
                    .frame(width: 60, height: 60)
                    .background(model.isReading ? Color.red : Color.green)
                    .clipShape(Circle())
            }

            Spacer()

            Button(action: { model.nextPage() }) {
                Image(systemName: "chevron.right")
                    .foregroundColor(.primary)
                    .frame(width: 60, height: 60)
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(30)
            }
            .disabled(model.currentPageIndex >= model.pages.count - 1)
        }
        .padding()
    }
}

struct ReadingControl: View {
    @ObservedObject var model: ContentModel

    var body: some View {
        HStack {
            Picker("音色", selection: $model.selectedVoice) {
                ForEach(model.availableVoices, id: \.identifier) { voice in
                    Text(voice.name).tag(voice as AVSpeechSynthesisVoice?)
                }
            }
            .pickerStyle(MenuPickerStyle())

            Picker("速度", selection: $model.readingSpeed) {
                Text("1x").tag(1.0 as Float)
                Text("1.5x").tag(1.5 as Float)
                Text("2x").tag(2.0 as Float)
                Text("3x").tag(3.0 as Float)
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
