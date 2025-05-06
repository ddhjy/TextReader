import SwiftUI
import Combine
import AVFoundation // For Voice type only

// Inject dependencies (Services/Managers)
class ContentViewModel: ObservableObject {
    // MARK: - Published Properties for UI Binding
    @Published var pages: [String] = []
    @Published var currentPageIndex: Int = 0
    @Published var currentBookTitle: String = "TextReader"
    @Published var isContentLoaded: Bool = false
    @Published var isReading: Bool = false
    @Published var availableVoices: [AVSpeechSynthesisVoice] = []
    @Published var selectedVoiceIdentifier: String? // Used for binding and persistence
    @Published var readingSpeed: Float = 1.0
    @Published var books: [Book] = []
    @Published var currentBookId: String?
    @Published var searchResults: [(Int, String)] = []
    @Published var pageSummaries: [(Int, String)] = []
    @Published var serverAddress: String? = nil
    @Published var isServerRunning = false
    @Published var showingBookList = false
    @Published var showingSearchView = false
    @Published var showingDocumentPicker = false
    @Published var showingWiFiTransferView = false
    @Published var showingPasteImport = false
    @Published var bookProgressText: String?
    @Published var darkModeEnabled: Bool = false
    // BigBang 相关状态
    @Published var showingBigBang = false
    @Published var tokens: [Token] = []
    @Published var selectedTokenIDs: Set<UUID> = []

    // MARK: - Dependencies
    private let libraryManager: LibraryManager
    private let textPaginator: TextPaginator
    private let speechManager: SpeechManager
    private let searchService: SearchService
    private let wiFiTransferService: WiFiTransferService
    private let audioSessionManager: AudioSessionManager
    private let settingsManager: SettingsManager
    // BigBang 工具依赖
    private let tokenizer = Tokenizer()

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization
    init(libraryManager: LibraryManager = LibraryManager(),
         textPaginator: TextPaginator = TextPaginator(),
         speechManager: SpeechManager = SpeechManager(),
         searchService: SearchService = SearchService(),
         wiFiTransferService: WiFiTransferService = WiFiTransferService(),
         audioSessionManager: AudioSessionManager = AudioSessionManager(),
         settingsManager: SettingsManager = SettingsManager()) {

        self.libraryManager = libraryManager
        self.textPaginator = textPaginator
        self.speechManager = speechManager
        self.searchService = searchService
        self.wiFiTransferService = wiFiTransferService
        self.audioSessionManager = audioSessionManager
        self.settingsManager = settingsManager
        self.darkModeEnabled = settingsManager.getDarkMode()

        loadInitialData()
        
        audioSessionManager.registerViewModel(self)
        audioSessionManager.setupAudioSession()
        
        audioSessionManager.setupRemoteCommandCenter(
            playAction: { [weak self] in self?.readCurrentPage() },
            pauseAction: { [weak self] in self?.stopReading() },
            nextAction: { [weak self] in self?.nextPage() },
            previousAction: { [weak self] in self?.previousPage() }
        )
        
        setupBindings()
        setupWiFiTransferCallbacks()
        setupSpeechCallbacks()
        
        $isReading
            .dropFirst() // Ignore initial value
            .sink { [weak self] isReading in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    print("isReading state changed: \(isReading)")
                    self.audioSessionManager.synchronizePlaybackState(force: true)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Loading
    private func loadInitialData() {
        self.books = libraryManager.loadBooks()
        sortBooks()
        
        let lastBookId = settingsManager.getLastOpenedBookId()
        if let bookId = lastBookId, let bookToLoad = books.first(where: { $0.id == bookId }) {
            loadBook(bookToLoad)
        } else if let firstBook = books.first { // Load first book if last book not found
            loadBook(firstBook)
        } else {
            isContentLoaded = true // No book to load
        }
        self.readingSpeed = settingsManager.getReadingSpeed()
        self.availableVoices = speechManager.getAvailableVoices(languagePrefix: "zh")
        self.selectedVoiceIdentifier = settingsManager.getSelectedVoiceIdentifier() ?? availableVoices.first?.identifier
    }

    // MARK: - Bindings & Callbacks
    private func setupBindings() {
        // Save progress when page changes
        $currentPageIndex
            .dropFirst()
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] index in
                guard let self = self, let bookId = self.currentBookId else { return }
                self.libraryManager.saveBookProgress(bookId: bookId, pageIndex: index)
                self.updateNowPlayingInfo()
            }
            .store(in: &cancellables)

        // Save settings when they change
        $readingSpeed
            .dropFirst()
            .sink { [weak self] speed in self?.settingsManager.saveReadingSpeed(speed) }
            .store(in: &cancellables)

        $selectedVoiceIdentifier
            .dropFirst()
            .sink { [weak self] identifier in
                guard let id = identifier else { return }
                self?.settingsManager.saveSelectedVoiceIdentifier(id)
                if self?.isReading == true {
                    self?.restartReading()
                }
            }
            .store(in: &cancellables)
            
        $darkModeEnabled
            .dropFirst()
            .sink { [weak self] enabled in self?.settingsManager.saveDarkMode(enabled) }
            .store(in: &cancellables)
            
        setupSyncTimer()
    }

    /// Periodically checks and synchronizes system playback state
    private func setupSyncTimer() {
        Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                
                let speechManagerActive = speechManager.isSpeaking
                
                // Correct inconsistent states
                if self.isReading != speechManagerActive {
                    print("Detected inconsistent state: UI=\(self.isReading), Speech=\(speechManagerActive)")
                    
                    // Force stop if UI shows stopped but speech manager is still playing
                    if !self.isReading && speechManagerActive {
                        print("Forcing playback to stop")
                        DispatchQueue.main.async {
                            self.speechManager.stopReading()
                        }
                    }
                    // Logic to resume playback was removed to avoid conflicts with onSpeechFinish
                }
                
                // Periodically synchronize control center state every 5 seconds
                let now = Date().timeIntervalSince1970
                if Int(now) % 5 == 0 {
                    self.audioSessionManager.synchronizePlaybackState()
                }
            }
            .store(in: &cancellables)
    }

    private func setupWiFiTransferCallbacks() {
        wiFiTransferService.onFileReceived = { [weak self] fileName, content in
            self?.handleReceivedFile(fileName: fileName, content: content)
        }
        wiFiTransferService.$serverAddress
            .assign(to: &$serverAddress)
        wiFiTransferService.$isRunning
            .assign(to: &$isServerRunning)
    }

    private func setupSpeechCallbacks() {
        speechManager.onSpeechFinish = { [weak self] in
            guard let self = self else { return }
            
            // Save page index when speech finishes to verify later
            let finishedPageIndex = self.currentPageIndex
            
            DispatchQueue.main.async {
                guard self.isReading else { return }
                
                // Verify current page index matches the one when speech finished
                // This prevents race conditions between manual page turns and auto-advancement
                guard self.currentPageIndex == finishedPageIndex else {
                    print("Page has changed, skipping auto-advancement")
                    return
                }
                
                // Auto-advance to next page
                if self.currentPageIndex < self.pages.count - 1 {
                    self.currentPageIndex += 1
                    self.readCurrentPage()
                } else {
                    self.isReading = false // Reached end of book
                    self.updateNowPlayingInfo()
                }
            }
        }
        
        speechManager.onSpeechStart = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                // Ensure playback state is consistent when speech starts
                if !self.isReading {
                    self.isReading = true
                    self.updateNowPlayingInfo()
                }
            }
        }
        
        speechManager.onSpeechPause = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                // Ensure playback state is consistent when speech pauses
                if self.isReading {
                    self.isReading = false
                    self.updateNowPlayingInfo()
                }
            }
        }
        
        speechManager.onSpeechResume = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                // Ensure playback state is consistent when speech resumes
                if !self.isReading {
                    self.isReading = true
                    self.updateNowPlayingInfo()
                }
            }
        }
        
        speechManager.onSpeechError = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                // Reset state on speech synthesis error
                if self.isReading {
                    self.isReading = false
                    self.updateNowPlayingInfo()
                    print("Speech synthesis error, playback stopped")
                }
            }
        }
    }

    // MARK: - Book Management
    
    /// Sorts books by last accessed time, with most recently accessed first
    private func sortBooks() {
        let sortedBooks = books.sorted { book1, book2 in
            let lastAccessed1 = libraryManager.getBookProgress(bookId: book1.id)?.lastAccessed
            let lastAccessed2 = libraryManager.getBookProgress(bookId: book2.id)?.lastAccessed

            // Sort logic:
            // 1. If book1 has access time but book2 doesn't, book1 comes first
            // 2. If book1 doesn't have access time but book2 does, book2 comes first
            // 3. If both have access times, sort by most recent first
            // 4. If neither has access time, sort by title for stability
            switch (lastAccessed1, lastAccessed2) {
            case (let date1?, let date2?):
                return date1 > date2 // Descending by time
            case (.some, .none):
                return true // Books with access time first
            case (.none, .some):
                return false // Books without access time last
            case (.none, .none):
                return book1.title.localizedCompare(book2.title) == .orderedAscending
            }
        }
        self.books = sortedBooks
    }
    
    // 直接粘贴文本导入
    func importPastedText(_ rawText: String, title customTitle: String?) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // 若未输入标题，取前 10 个字符；去掉换行
        var title = (customTitle?.trimmingCharacters(in: .whitespacesAndNewlines)).nilIfEmpty()
                   ?? String(text.replacingOccurrences(of: "\n", with: " ").prefix(10))

        // 过滤文件名非法字符，避免写文件失败
        let invalidSet = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        title = title.components(separatedBy: invalidSet).joined()

        // 避免重名，可加时间戳
        let fileName = "\(title)-\(Int(Date().timeIntervalSince1970)).txt"

        libraryManager.importBook(fileName: fileName, content: text) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success(let newBook):
                    self.books = self.libraryManager.loadBooks()
                    self.sortBooks()
                    self.loadBook(newBook)
                case .failure(let err):
                    print("Paste import failed: \(err)")
                }
            }
        }
    }
    
    func loadBook(_ book: Book) {
        stopReading() // Stop reading before changing book
        isContentLoaded = false
        currentBookId = book.id
        currentBookTitle = book.title
        settingsManager.saveLastOpenedBookId(book.id) // Save as last opened
        
        // Update last accessed time
        libraryManager.updateLastAccessed(bookId: book.id)

        sortBooks() // 更新后立即重新排序 books 数组
        print("[ContentViewModel] Sorted books after loading book: \(book.title)")

        libraryManager.loadBookContent(book: book) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let content):
                    self.pages = self.textPaginator.paginate(text: content)
                    let savedProgress = self.libraryManager.getBookProgress(bookId: book.id)
                    self.currentPageIndex = savedProgress?.currentPageIndex ?? 0
                    self.libraryManager.saveTotalPages(bookId: book.id, totalPages: self.pages.count)
                    self.pageSummaries = self.searchService.pageSummaries(pages: self.pages)
                    self.isContentLoaded = true
                    self.updateNowPlayingInfo()
                case .failure(let error):
                    print("Error loading book content: \(error)")
                    self.pages = ["加载书籍内容失败: \(error.localizedDescription)"]
                    self.currentPageIndex = 0
                    self.isContentLoaded = true
                }
            }
        }
    }

    func deleteBook(_ book: Book) {
        let wasCurrentBook = (book.id == currentBookId)
        if wasCurrentBook {
            stopReading()
        }

        libraryManager.deleteBook(book) { [weak self] success in
            guard let self = self, success else {
                print("Failed to delete book \(book.title)")
                return
            }
            self.books = self.libraryManager.loadBooks()
            self.sortBooks()

            if wasCurrentBook {
                // If the deleted book was the current one, load the first available book or clear the view
                if let firstBook = self.books.first {
                    self.loadBook(firstBook)
                } else {
                    self.pages = []
                    self.currentPageIndex = 0
                    self.currentBookId = nil
                    self.currentBookTitle = "TextReader"
                    self.isContentLoaded = true
                }
            }
        }
    }

    /// Handles a file received via WiFi transfer
    private func handleReceivedFile(fileName: String, content: String) {
        libraryManager.importBook(fileName: fileName, content: content) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let newBook):
                self.books = self.libraryManager.loadBooks()
                self.sortBooks()
                self.loadBook(newBook)
            case .failure(let error):
                print("Error handling received file: \(error)")
            }
        }
    }

    /// Imports a book from a URL (used with DocumentPicker)
    func importBookFromURL(_ url: URL, suggestedTitle: String? = nil) {
        print("[ContentViewModel] Importing book from URL: \(url.absoluteString)")
        print("[ContentViewModel] Suggested title: \(suggestedTitle ?? "none")")
        
        libraryManager.importBookFromURL(url, suggestedTitle: suggestedTitle) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                switch result {
                case .success(let book):
                    print("[ContentViewModel] Successfully imported book: \(book.title)")
                    // 更新书籍列表并加载
                    self.books = self.libraryManager.loadBooks()
                    self.sortBooks()
                    self.loadBook(book)
                    
                case .failure(let error):
                    print("[ContentViewModel] Failed to import book: \(error)")
                    // 这里可以添加错误处理逻辑，例如显示错误提示等
                }
            }
        }
    }

    func getBookProgressDisplay(book: Book) -> String? {
        if let progress = libraryManager.getBookProgress(bookId: book.id) {
            return "已读 \(progress.currentPageIndex + 1)/\(progress.totalPages) 页"
        }
        return nil
    }

    /// Returns a user-friendly string describing when the book was last accessed
    func getLastAccessedTimeDisplay(book: Book) -> String? {
        guard let progress = libraryManager.getBookProgress(bookId: book.id),
              let lastAccessed = progress.lastAccessed else {
            return nil
        }
        
        let now = Date()
        let calendar = Calendar.current
        
        // Determine appropriate format based on how long ago the book was accessed
        if calendar.isDateInToday(lastAccessed) {
            let components = calendar.dateComponents([.minute, .hour], from: lastAccessed, to: now)
            let totalMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            
            if totalMinutes < 5 {
                return "刚刚阅读"
            } else if totalMinutes < 60 {
                return "\(totalMinutes)分钟前阅读"
            } else {
                return "\(components.hour ?? 0)小时前阅读"
            }
        } else if calendar.isDateInYesterday(lastAccessed) {
            return "昨天阅读"
        } else {
            let currentYear = calendar.component(.year, from: now)
            let accessedYear = calendar.component(.year, from: lastAccessed)
            
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            
            if currentYear == accessedYear {
                // If this year, show only month and day
                formatter.dateFormat = "M月d日阅读"
            } else {
                // Otherwise show full date with year
                formatter.dateFormat = "yyyy年M月d日阅读"
            }
            
            return formatter.string(from: lastAccessed)
        }
    }

    // MARK: - Reading Control
    func nextPage() {
        guard currentPageIndex < pages.count - 1 else { return }
        
        let wasReading = self.isReading // 记录翻页前的朗读状态

        if wasReading {
            // 如果在朗读，立即停止当前页的朗读，但不需要完全执行 stopReading() 中的所有 UI 更新和延迟操作
            // 只需要停止 SpeechManager 即可
            speechManager.stopReading()
            // 不立即设置 isReading = false，因为马上可能就要开始读下一页
            // 也不在这里调用 updateNowPlayingInfo，因为 index 还没更新
        }

        currentPageIndex += 1 // 更新页面索引

        if let bookId = self.currentBookId {
            libraryManager.updateLastAccessed(bookId: bookId) // 更新访问时间
            sortBooks() // 更新后立即重新排序 books 数组
            print("[ContentViewModel] Updated lastAccessed and sorted books after nextPage.")
        }

        if wasReading {
            // 如果翻页前在朗读，立即开始朗读新页面
            // 使用 DispatchQueue.main.async 确保在 UI 更新后执行朗读，避免潜在冲突
            DispatchQueue.main.async {
                self.readCurrentPage() // readCurrentPage 内部会设置 isReading = true 并更新 NowPlayingInfo
            }
        } else {
            // 如果翻页前没有朗读，只需要更新 NowPlayingInfo 的页码信息
            updateNowPlayingInfo()
        }
    }

    func previousPage() {
        guard currentPageIndex > 0 else { return }
        
        let wasReading = self.isReading // 记录翻页前的朗读状态

        if wasReading {
            // 同 nextPage 的逻辑
            speechManager.stopReading()
        }

        currentPageIndex -= 1 // 更新页面索引

        if let bookId = self.currentBookId {
            libraryManager.updateLastAccessed(bookId: bookId) // 更新访问时间
            sortBooks() // 更新后立即重新排序 books 数组
            print("[ContentViewModel] Updated lastAccessed and sorted books after previousPage.")
        }

        if wasReading {
            // 同 nextPage 的逻辑
            DispatchQueue.main.async {
                self.readCurrentPage()
            }
        } else {
            updateNowPlayingInfo()
        }
    }

    func toggleReading() {
        if isReading {
            stopReading()
        } else {
            readCurrentPage()
        }
    }

    func readCurrentPage() {
        guard !pages.isEmpty, currentPageIndex < pages.count else { return }
        
        print("Starting reading current page")
        let textToRead = pages[currentPageIndex]
        let voice = availableVoices.first { $0.identifier == selectedVoiceIdentifier }
        
        // Set state to playing first
        isReading = true
        
        DispatchQueue.main.async {
            // Update Now Playing info immediately
            self.updateNowPlayingInfo()
            
            // Then start speech playback
            self.speechManager.startReading(text: textToRead, voice: voice, rate: self.readingSpeed)
        }
    }

    func stopReading() {
        print("Stopping reading")
        
        // Stop speech synthesizer immediately
        speechManager.stopReading()
        
        // Set state to stopped
        let needsUpdate = isReading // Only update NowPlaying if state actually changes
        if needsUpdate {
            isReading = false
            // Update Now Playing info ONCE immediately to reflect the stopped state
            // The AudioSessionManager's periodic sync will handle further consistency checks.
            updateNowPlayingInfo()
        }
    }

    /// Restarts reading with a slight delay to ensure synthesizer is reset
    private func restartReading() {
        if isReading {
            print("Restarting reading")
            stopReading()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.readCurrentPage()
            }
        }
    }

    // MARK: - Search
    func searchContent(_ query: String) {
        guard !query.isEmpty else {
            searchResults = []
            // 显示默认摘要
            pageSummaries = searchService.pageSummaries(pages: pages)
            return
        }
        searchResults = searchService.search(query: query, in: pages)
    }

    func jumpToSearchResult(pageIndex: Int) {
        guard pageIndex >= 0 && pageIndex < pages.count else { return }
        stopReading()
        currentPageIndex = pageIndex
        showingSearchView = false // Dismiss search view
    }

    // MARK: - WiFi Transfer
    func toggleWiFiTransfer() {
        if isServerRunning {
            wiFiTransferService.stopServer()
        } else {
            let _ = wiFiTransferService.startServer()
        }
    }

    // MARK: - Now Playing Info
    private func updateNowPlayingInfo() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.audioSessionManager.updateNowPlayingInfo(
                title: self.currentBookTitle,
                isPlaying: self.isReading,
                currentPage: self.currentPageIndex + 1,
                totalPages: self.pages.count
            )
        }
    }

    // MARK: - URL Handling
    /**
     * 处理通过 onOpenURL 传入的 URL，通常来自文件应用、AirDrop 或其他应用的分享。
     * 对于分享的纯文本，系统可能会将其保存为临时文件并通过 URL 传递。
     * 也可能来自我们自定义的URL Scheme，例如textreader://import?text=xxx
     */
    func handleImportedURL(_ url: URL) {
        print("[ContentViewModel] Handling imported URL: \(url.absoluteString)")

        // 处理自定义Scheme (textreader://)
        if url.scheme == "textreader" {
            handleCustomSchemeURL(url)
            return
        }
        
        // 基本检查：确保是文件 URL (file:// scheme)
        // 系统分享的临时文件通常也是 file URL
        guard url.isFileURL else {
            print("[ContentViewModel][Warning] Received URL is not a file URL. Scheme: \(url.scheme ?? "nil"). Ignoring.")
            // 这里可以根据需要添加对其他 scheme 的处理逻辑
            return
        }

        // 复用现有的导入逻辑
        // importBookFromURL 内部已经处理了安全作用域、文件读取（包括编码检测）和书籍保存
        print("[ContentViewModel] URL is a file URL, attempting to import via importBookFromURL...")
        importBookFromURL(url)
    }
    
    /**
     * 处理自定义URL Scheme，如 textreader://import?text=xxx
     */
    private func handleCustomSchemeURL(_ url: URL) {
        print("[ContentViewModel] Handling custom scheme URL: \(url.absoluteString)")
        
        // 检查主机部分 - 例如textreader://import表示要导入文本
        guard let host = url.host, host == "import" else {
            print("[ContentViewModel][Warning] Unsupported URL host: \(url.host ?? "nil")")
            return
        }
        
        // 提取查询参数
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let queryItems = components.queryItems else {
            print("[ContentViewModel][Warning] No query items in URL")
            return
        }
        
        // 查找text参数
        if let textItem = queryItems.first(where: { $0.name == "text" }),
           let encodedText = textItem.value,
           let decodedText = encodedText.removingPercentEncoding,
           !decodedText.isEmpty {
            
            print("[ContentViewModel] Found text parameter with length: \(decodedText.count)")
            
            // 从分享的文本创建一个新书籍
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
            let timestamp = dateFormatter.string(from: Date())
            
            // 为书籍生成一个标题 - 从内容的前10个字符
            var title = "分享_\(timestamp)"
            let contentPreview = decodedText.prefix(10).trimmingCharacters(in: .whitespacesAndNewlines)
            if !contentPreview.isEmpty {
                title = contentPreview + "..."
            }
            
            // 临时将内容保存为文件
            do {
                let tempDir = FileManager.default.temporaryDirectory
                let tempFile = tempDir.appendingPathComponent("\(title)_\(timestamp).txt")
                
                try decodedText.write(to: tempFile, atomically: true, encoding: .utf8)
                print("[ContentViewModel] Saved shared text to temporary file: \(tempFile.path)")
                
                // 使用已有的导入逻辑
                importBookFromURL(tempFile, suggestedTitle: title)
            } catch {
                print("[ContentViewModel][Error] Failed to save shared text to temporary file: \(error.localizedDescription)")
            }
        } else {
            print("[ContentViewModel][Warning] No valid text parameter found in URL")
        }
    }

    // MARK: - Big Bang
    func triggerBigBang() {
        guard currentPageIndex < pages.count else { return }
        let text = pages[currentPageIndex]
        self.tokens = tokenizer.tokenize(text: text)
        self.selectedTokenIDs = []          // reset
        self.showingBigBang = true
    }

    func toggleToken(_ id: UUID) {          // 供单点选择
        if selectedTokenIDs.contains(id) { selectedTokenIDs.remove(id) }
        else { selectedTokenIDs.insert(id) }
    }

    func slideSelect(from startID: UUID, to endID: UUID) {   // 供滑动选择
        guard let s = tokens.firstIndex(where: {$0.id == startID}),
              let e = tokens.firstIndex(where: {$0.id == endID}) else { return }
        let range = s <= e ? s...e : e...s
        selectedTokenIDs.formUnion(tokens[range].map(\.id))
    }

    func clearSelectedTokens() {            // 清空所有选中的Token
        selectedTokenIDs.removeAll()
    }

    func copySelected() {
        let text = tokens.filter { selectedTokenIDs.contains($0.id) }
                         .map(\.value).joined()
        UIPasteboard.general.string = text
        showingBigBang = false
    }

    // MARK: - Cleanup
    deinit {
        stopReading()
        wiFiTransferService.stopServer()
        cancellables.forEach { $0.cancel() }
    }
} 