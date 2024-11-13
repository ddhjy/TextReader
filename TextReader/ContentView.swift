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
        NavigationStack {
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
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: { showingDocumentPicker = true }) {
                            Image(systemName: "square.and.arrow.down")
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { showingSearchView = true }) {
                            Image(systemName: "magnifyingglass")
                        }
                    }
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: {
                            if model.isServerRunning {
                                model.stopWiFiTransfer()
                            } else {
                                model.startWiFiTransfer()
                            }
                        }) {
                            Image(systemName: model.isServerRunning ? "wifi.slash" : "wifi")
                        }
                    }
                }
                .overlay(
                    Group {
                        if let address = model.serverAddress {
                            VStack {
                                Text("WiFi 传输已开启")
                                    .font(.headline)
                                Text("请在浏览器中访问：")
                                Text(address)
                                    .font(.system(.body, design: .monospaced))
                            }
                            .padding()
                            .background(Color(.systemBackground))
                            .cornerRadius(10)
                            .shadow(radius: 5)
                            .transition(.move(edge: .top))
                        }
                    }
                )
            } else {
                ProgressView()
                    .scaleEffect(1.5)
                    .navigationTitle("加载中...")
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(isPresented: $showingBookList) {
            NavigationStack {
                BookListView(model: model)
            }
        }
        .sheet(isPresented: $showingDocumentPicker) {
            DocumentPicker(model: model)
        }
        .sheet(isPresented: $showingSearchView) {
            NavigationStack {
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
        VStack {
            Text(model.pages.isEmpty ? "无内容" : model.pages[model.currentPageIndex])
                .padding()
                .font(.system(size: 18, weight: .regular, design: .serif))
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

// RepeatButton 组件
struct RepeatButton<Label: View>: View {
    let action: () -> Void
    let longPressAction: () -> Void
    let label: () -> Label

    @State private var isPressed = false
    @State private var timer: Timer?

    var body: some View {
        label()
            .buttonStyle(PressableButtonStyle())
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .onLongPressGesture(minimumDuration: 0.2, pressing: { pressing in
                self.isPressed = pressing
                if pressing {
                    // 开始定时器，每0.1秒调用一次长按操作
                    self.timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                        self.longPressAction()
                    }
                } else {
                    // 停止定时器
                    self.timer?.invalidate()
                    self.timer = nil
                }
            }, perform: {
                // 长按手势完成后的操作（可留空）
            })
            .simultaneousGesture(
                TapGesture()
                    .onEnded {
                        self.action()
                    }
            )
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
                // 上一页按钮
                RepeatButton(
                    action: { model.previousPage() },
                    longPressAction: {
                        // 长按时持续调用 previousPage
                        if model.currentPageIndex > 0 {
                            model.previousPage()
                        }
                    },
                    label: {
                        Image(systemName: "chevron.left")
                            .font(.title)
                    }
                )
                .disabled(model.currentPageIndex == 0)

                Spacer()

                Button(action: { model.toggleReading() }) {
                    Image(systemName: model.isReading ? "pause.circle.fill" : "play.circle.fill")
                        .font(.largeTitle)
                }

                Spacer()

                // 下一页按钮
                RepeatButton(
                    action: { model.nextPage() },
                    longPressAction: {
                        // 长按时持续调用 nextPage
                        if model.currentPageIndex < model.pages.count - 1 {
                            model.nextPage()
                        }
                    },
                    label: {
                        Image(systemName: "chevron.right")
                            .font(.title)
                    }
                )
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
                    Text("1.75").tag(1.75 as Float)
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            SearchBar(text: $searchText, onCommit: {
                model.searchContent(searchText)
            })
            .padding()

            List(model.searchResults, id: \.0) { index, preview in
                Button(action: {
                    model.currentPageIndex = index
                    dismiss()
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
                    dismiss()
                }
            }
        }
    }
}

struct BookListView: View {
    @ObservedObject var model: ContentModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteAlert = false
    @State private var bookToDelete: Book?

    var body: some View {
        List {
            ForEach(model.books) { book in
                Button(action: {
                    model.loadBook(book)
                    dismiss()
                }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(book.title)
                                .foregroundColor(.primary)
                            if let progress = model.getBookProgress(book) {
                                Text("已读 \(progress.currentPage + 1)/\(progress.totalPages) 页")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        if model.currentBook?.id == book.id {
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
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("完成") {
                    dismiss()
                }
            }
        }
        .alert("确认删除", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if let book = bookToDelete {
                    model.deleteBook(book)
                }
            }
        } message: {
            if let book = bookToDelete {
                Text("确定要删除《\(book.title)》吗？此操作不可恢复。")
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

    private var webServer: WebServer?
    @Published var serverAddress: String?
    @Published var isServerRunning = false

    override init() {
        super.init()
        synthesizer.delegate = self
        loadBooks()
        loadSavedSettings()
        loadAvailableVoices()
        
        // 设置音频会话和远程控制
        setupAudioSession()
        setupRemoteCommandCenter()
    }

    private func loadBooks() {
        var allBooks: [Book] = []
        // 从文档目录加载 WiFi 导入的书籍
        do {
            let documentsURL = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: documentsURL,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
            
            // 只处理 .txt 文件
            let txtFiles = fileURLs.filter { $0.pathExtension.lowercased() == "txt" }
            let importedBooks = txtFiles.map { url in
                let title = URL(fileURLWithPath: url.path).deletingPathExtension().lastPathComponent
                let fileName = url.lastPathComponent
                return Book(title: title, fileName: fileName, isBuiltIn: false)
            }
            allBooks.append(contentsOf: importedBooks)
        } catch {
            print("读取文档目录失败: \(error)")
        }
        
        // 3. 更新 books 数组
        books = allBooks
        
        // 4. 加载上次阅读的书籍
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
        if book.isBuiltIn {
            // 从主包加载预置书籍
            if let url = Bundle.main.url(forResource: URL(fileURLWithPath: book.fileName).deletingPathExtension().lastPathComponent, withExtension: "txt") {
                loadContent(from: url)
            }
        } else {
            // 从文档目录加载导入书籍
            do {
                let documentsURL = try FileManager.default.url(
                    for: .documentDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
                let fileURL = documentsURL.appendingPathComponent(book.fileName)
                loadContent(from: fileURL)
            } catch {
                print("加载导入书籍失败: \(error)")
            }
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
        
        updateNowPlayingInfo()
    }

    func stopReading() {
        synthesizer.stopSpeaking(at: .immediate)
        isReading = false
        endBackgroundTask()
        updateNowPlayingInfo()
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
        stopReading()
        currentBook = book
        isContentLoaded = false
        loadBookProgress(for: book)
        loadBookContent(book)
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
        // 确保在主线程处理 UI 相关操作
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            do {
                // 1. 检查文件是否可访问
                guard url.startAccessingSecurityScopedResource() else {
                    print("无法访问文件：权限被拒绝")
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }
                
                // 2. 读取文件内容
                let content = try String(contentsOf: url, encoding: .utf8)
                let fileName = url.lastPathComponent
                let bookTitle = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
                
                // 3. 保存到应用沙盒
                let documentsURL = try FileManager.default.url(
                    for: .documentDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
                let savedURL = documentsURL.appendingPathComponent(fileName)
                
                // 4. 如果文件已存在，先删除
                if FileManager.default.fileExists(atPath: savedURL.path) {
                    try FileManager.default.removeItem(at: savedURL)
                }
                
                // 5. 写入新文件
                try content.write(to: savedURL, atomically: true, encoding: .utf8)
                
                // 6. 创建新书本
                let newBook = Book(title: bookTitle, fileName: fileName, isBuiltIn: false)
                
                // 7. 更新 UI
                self.books.append(newBook)
                self.currentBook = newBook
                self.isContentLoaded = false
                
                // 8. 加载新书本内容
                self.loadContent(from: savedURL)
                
                print("成功导入书本：\(bookTitle)")
                
            } catch let error {
                print("导入书本时出错：\(error.localizedDescription)")
                // 可以在这里添加错误提示UI
            }
        }
    }
    
    private func loadContent(from url: URL) {
        print("开始加载内容：\(url.lastPathComponent)")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                // 优化分页逻辑，避免句子开头是标点符号
                var sentences = [String]()
                var currentSentence = ""
                for char in content {
                    currentSentence.append(char)
                    if "。！？.!?；;：:\"\"''\\\"\\\"“”‘’".contains(char) {
                        // 当前句子结束，添加到数组中
                        sentences.append(currentSentence.trimmingCharacters(in: .whitespacesAndNewlines))
                        currentSentence = ""
                    }
                }
                // 添加剩余的内容
                if !currentSentence.isEmpty {
                    sentences.append(currentSentence.trimmingCharacters(in: .whitespacesAndNewlines))
                }

                var pages = [String]()
                var currentPage = ""
                var currentPageSize = 0
                let maxPageSize = 100

                for sentence in sentences {
                    let sentenceSize = sentence.count

                    // 如果当前句子超过最大页面大小，单独作为一页
                    if sentenceSize > maxPageSize {
                        if !currentPage.isEmpty {
                            pages.append(currentPage.trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                        pages.append(sentence.trimmingCharacters(in: .whitespacesAndNewlines))
                        currentPage = ""
                        currentPageSize = 0
                        continue
                    }

                    // 如果加上当前句子会超过页面大小，创建新页面
                    if currentPageSize + sentenceSize > maxPageSize && !currentPage.isEmpty {
                        pages.append(currentPage.trimmingCharacters(in: .whitespacesAndNewlines))
                        currentPage = sentence
                        currentPageSize = sentenceSize
                    } else {
                        currentPage += sentence
                        currentPageSize += sentenceSize
                    }
                }

                // 添加最后一页
                if !currentPage.isEmpty {
                    pages.append(currentPage.trimmingCharacters(in: .whitespacesAndNewlines))
                }

                DispatchQueue.main.async {
                    print("内容处理完成，页数：\(pages.count)")
                    self?.pages = pages
                    self?.isContentLoaded = true

                    // 在内容加载完成后设置正确的页面索引
                    if let savedIndex = self?.savedPageIndex, savedIndex < pages.count {
                        self?.currentPageIndex = savedIndex
                    } else {
                        self?.currentPageIndex = 0
                    }
                    self?.savedPageIndex = nil

                    // 在这里添加保存总页数的调用
                    self?.saveTotalPages()
                }
            } catch {
                print("加载内容失败：\(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.isContentLoaded = true  // 即使失败也要更新状态
                    self?.pages = []  // 清空页面
                    self?.showErrorAlert(message: "加载内容时出错：\(error.localizedDescription)")
                }
            }
        }
    }

    func showErrorAlert(message: String) {
        // 这里实现显示错误警告的逻辑
        // 例如，您可以使用通知或绑定一个 @Published 属性来触发视图中的 Alert
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
            MPMediaItemPropertyArtist: "TextReader",
            MPMediaItemPropertyPlaybackDuration: 0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    private func setupAudioSession() {
        do {
            // 设置音频会话类别为 playback,允许后台播放
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.allowAirPlay, .allowBluetooth]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("设置音频会话失败: \(error)")
        }
    }

    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // 启用播放/暂停命令
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        
        // 处理暂停命令
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.stopReading()
            return .success
        }
        
        // 处理播放命令
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.readCurrentPage()
            return .success
        }
    }

    func startWiFiTransfer() {
        webServer = WebServer()
        webServer?.onFileReceived = { [weak self] (fileName, content) in
            self?.handleReceivedFile(fileName: fileName, content: content)
        }
        
        if let address = webServer?.start() {
            serverAddress = "http://\(address):8080"
            isServerRunning = true
        }
    }
    
    func stopWiFiTransfer() {
        webServer?.stop()
        serverAddress = nil
        isServerRunning = false
    }
    
    private func handleReceivedFile(fileName: String, content: String) {
        // 处理接收到的文件
        let bookTitle = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        let newBook = Book(title: bookTitle, fileName: fileName, isBuiltIn: false)
        
        // 保存文件到本地
        do {
            let documentsURL = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let fileURL = documentsURL.appendingPathComponent(fileName)
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            
            DispatchQueue.main.async {
                // 检查是否已存在相同 ID 的书籍
                if !self.books.contains(where: { $0.id == newBook.id }) {
                    self.books.append(newBook)
                }
                self.currentBook = newBook
                self.loadContent(from: fileURL)
            }
        } catch {
            print("保存文件失败: \(error)")
        }
    }

    func deleteBook(_ book: Book) {
        // 如果是当前正在阅读的书，先停止朗读
        if book.id == currentBook?.id {
            stopReading()
            currentBook = nil
            pages = []
            currentPageIndex = 0
        }
        
        do {
            // 删除文件
            let documentsURL = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let fileURL = documentsURL.appendingPathComponent(book.fileName)
            try FileManager.default.removeItem(at: fileURL)
            
            // 删除进度记录
            let progressKey = "bookProgress_\(book.id)"
            UserDefaults.standard.removeObject(forKey: progressKey)
            
            // 从书籍列表中移除
            books.removeAll { $0.id == book.id }
            
            // 如果删除的是当前书籍，加载第一本可用的书
            if currentBook == nil, let firstBook = books.first {
                loadBook(firstBook)
            }
            
        } catch {
            print("删除书籍失败: \(error)")
        }
    }

    struct BookProgress {
        let currentPage: Int
        let totalPages: Int
    }
    
    func getBookProgress(_ book: Book) -> BookProgress? {
        let key = "bookProgress_\(book.id)"
        let currentPage = UserDefaults.standard.integer(forKey: key)
        
        // 如果是当前加载的书，使用实时页数
        if book.id == currentBook?.id {
            return BookProgress(currentPage: currentPageIndex, totalPages: pages.count)
        }
        
        // 否则从缓存中获取总页数
        let totalPagesKey = "totalPages_\(book.id)"
        if let totalPages = UserDefaults.standard.object(forKey: totalPagesKey) as? Int {
            return BookProgress(currentPage: currentPage, totalPages: totalPages)
        }
        
        return nil
    }
    
    // 在加载内容完成后保存总页数
    private func saveTotalPages() {
        if let book = currentBook {
            let key = "totalPages_\(book.id)"
            UserDefaults.standard.set(pages.count, forKey: key)
        }
    }
}

struct Book: Identifiable {
    var id: String { fileName }
    let title: String
    let fileName: String
    let isBuiltIn: Bool
}

// 新 DocumentPicker 视图
struct DocumentPicker: UIViewControllerRepresentable {
    @ObservedObject var model: ContentModel
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // 修改为支持所有文类型
        let supportedTypes: [UTType] = [.text, .plainText]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: supportedTypes, asCopy: true)
        picker.delegate = context.coordinator
        picker.shouldShowFileExtensions = true
        // 允许多选
        picker.allowsMultipleSelection = false
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
