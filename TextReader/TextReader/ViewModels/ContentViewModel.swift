import SwiftUI
import Combine
import AVFoundation // 仅用于 Voice 类型

// 依赖注入各个 Service/Manager
class ContentViewModel: ObservableObject {
    // --- Published Properties for UI Binding ---
    @Published var pages: [String] = []
    @Published var currentPageIndex: Int = 0
    @Published var currentBookTitle: String = "TextReader"
    @Published var isContentLoaded: Bool = false
    @Published var isReading: Bool = false
    @Published var availableVoices: [AVSpeechSynthesisVoice] = []
    @Published var selectedVoiceIdentifier: String? // 使用 Identifier 进行绑定和持久化
    @Published var readingSpeed: Float = 1.0
    @Published var books: [Book] = []
    @Published var currentBookId: String? // Track current book by ID
    @Published var searchResults: [(Int, String)] = []
    @Published var serverAddress: String? = nil
    @Published var isServerRunning = false
    @Published var showingBookList = false // State for sheets/navigation
    @Published var showingSearchView = false
    @Published var showingDocumentPicker = false // For file import
    @Published var showingWiFiTransferView = false // 控制 WiFi 传输页面的显示状态
    @Published var bookProgressText: String? // For display in BookListView

    // --- Dependencies ---
    private let libraryManager: LibraryManager
    private let textPaginator: TextPaginator
    private let speechManager: SpeechManager
    private let searchService: SearchService
    private let wiFiTransferService: WiFiTransferService
    private let audioSessionManager: AudioSessionManager
    private let settingsManager: SettingsManager

    private var cancellables = Set<AnyCancellable>()

    // --- Initialization ---
    init(libraryManager: LibraryManager = LibraryManager(), // Use default instances or inject mocks for testing
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

        // --- Setup Bindings & Load Initial Data ---
        loadInitialData()
        
        // 注册viewModel到audioSessionManager以处理中断
        audioSessionManager.registerViewModel(self)
        
        // 设置音频会话
        audioSessionManager.setupAudioSession()
        
        // 设置远程控制中心
        audioSessionManager.setupRemoteCommandCenter(
            playAction: { [weak self] in self?.readCurrentPage() },
            pauseAction: { [weak self] in self?.stopReading() },
            nextAction: { [weak self] in self?.nextPage() },
            previousAction: { [weak self] in self?.previousPage() }
        )
        
        setupBindings()
        setupWiFiTransferCallbacks()
        setupSpeechCallbacks()
        
        // 添加isReading状态变化的监听，确保系统状态始终同步
        $isReading
            .dropFirst() // 忽略初始值
            .sink { [weak self] isReading in
                guard let self = self else { return }
                // 状态发生变化时，强制同步
                DispatchQueue.main.async {
                    print("isReading状态变化: \(isReading)")
                    self.audioSessionManager.synchronizePlaybackState(force: true)
                }
            }
            .store(in: &cancellables)
    }

    // --- Loading ---
    private func loadInitialData() {
        self.books = libraryManager.loadBooks()
        sortBooks() // 对书籍列表进行排序
        
        let lastBookId = settingsManager.getLastOpenedBookId()
        if let bookId = lastBookId, let bookToLoad = books.first(where: { $0.id == bookId }) {
            loadBook(bookToLoad)
        } else if let firstBook = books.first { // 如果找不到上次的书，加载排序后的第一本
            loadBook(firstBook)
        } else {
            isContentLoaded = true // No book to load
        }
        self.readingSpeed = settingsManager.getReadingSpeed()
        self.availableVoices = speechManager.getAvailableVoices(languagePrefix: "zh")
        self.selectedVoiceIdentifier = settingsManager.getSelectedVoiceIdentifier() ?? availableVoices.first?.identifier
    }

    // --- Bindings & Callbacks ---
    private func setupBindings() {
        // Save progress when page changes
        $currentPageIndex
            .dropFirst() // Ignore initial value
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main) // Avoid saving on rapid changes
            .sink { [weak self] index in
                guard let self = self, let bookId = self.currentBookId else { return }
                self.libraryManager.saveBookProgress(bookId: bookId, pageIndex: index)
                self.updateNowPlayingInfo() // Update page info in control center
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
                // If reading, restart with new voice
                if self?.isReading == true {
                    self?.restartReading()
                }
            }
            .store(in: &cancellables)
            
        // 设置定期同步定时器
        setupSyncTimer()
    }

    // 定期检查和同步系统状态
    private func setupSyncTimer() {
        // 创建一个每秒触发一次的定时器，用于同步状态
        Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                
                // 检查语音管理器状态
                let speechManagerActive = speechManager.isSpeaking
                
                // 如果状态不一致，进行修正
                if self.isReading != speechManagerActive {
                    print("检测到状态不一致: UI=\(self.isReading), Speech=\(speechManagerActive)")
                    
                    // 如果UI显示已停止但语音管理器仍在播放，强制停止
                    if !self.isReading && speechManagerActive {
                        print("强制停止播放")
                        DispatchQueue.main.async {
                            self.speechManager.stopReading()
                        }
                    }
                    // 移除尝试恢复播放的逻辑，因为它会与 onSpeechFinish 冲突
                    /*
                    if self.isReading && !speechManagerActive {
                        print("尝试恢复播放")
                        // 在某些情况下可能需要重新开始播放
                        DispatchQueue.main.async {
                            self.speechManager.retryLastReading()
                        }
                    } 
                    */
                }
                
                // 每5秒强制同步一次控制中心状态
                let now = Date().timeIntervalSince1970
                if Int(now) % 5 == 0 {
                    // 可以考虑减少日志频率或移除 "定期同步控制中心状态" 的打印
                    // print("定期同步控制中心状态")
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
            
            // 保存完成朗读时的页面索引，用于后续校验
            let finishedPageIndex = self.currentPageIndex
            
            DispatchQueue.main.async {
                guard self.isReading else { return }
                
                // 添加页面索引校验，确保当前页面索引与完成朗读时的页面索引一致
                // 这可以防止用户手动翻页与自动翻页产生竞态条件
                guard self.currentPageIndex == finishedPageIndex else {
                    print("页面已经改变，不执行自动翻页")
                    return
                }
                
                // Auto-advance to next page
                if self.currentPageIndex < self.pages.count - 1 {
                    self.currentPageIndex += 1
                    self.readCurrentPage()
                } else {
                    self.isReading = false // Reached end of book
                    // 确保最后一页播放完成后更新状态
                    self.updateNowPlayingInfo()
                }
            }
        }
        
        speechManager.onSpeechStart = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                // 确保语音开始时状态为正在播放
                if !self.isReading {
                    self.isReading = true
                    self.updateNowPlayingInfo()
                }
            }
        }
        
        speechManager.onSpeechPause = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                // 确保语音暂停时状态为暂停
                if self.isReading {
                    self.isReading = false
                    self.updateNowPlayingInfo()
                }
            }
        }
        
        speechManager.onSpeechResume = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                // 确保语音恢复时状态为播放
                if !self.isReading {
                    self.isReading = true
                    self.updateNowPlayingInfo()
                }
            }
        }
        
        // 处理语音合成错误
        speechManager.onSpeechError = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                // 发生错误时重置状态
                if self.isReading {
                    self.isReading = false
                    self.updateNowPlayingInfo()
                    // 可以在这里添加错误提示
                    print("语音合成出错，已停止播放")
                }
            }
        }
    }

    // --- Book Management ---
    
    // 添加排序方法
    private func sortBooks() {
        let sortedBooks = books.sorted { book1, book2 in
            // 获取两本书的最后访问时间
            let lastAccessed1 = libraryManager.getBookProgress(bookId: book1.id)?.lastAccessed
            let lastAccessed2 = libraryManager.getBookProgress(bookId: book2.id)?.lastAccessed

            // 排序逻辑：
            // 1. 如果 book1 有访问时间，book2 没有，则 book1 在前
            // 2. 如果 book1 没有，book2 有，则 book2 在前
            // 3. 如果都有，按时间降序排列（最近的在前）
            // 4. 如果都没有，保持原始相对顺序（或按标题等其他方式排序，这里保持稳定）
            switch (lastAccessed1, lastAccessed2) {
            case (let date1?, let date2?):
                return date1 > date2 // 按时间降序
            case (.some, .none):
                return true // 有时间的在前
            case (.none, .some):
                return false // 没时间的在后
            case (.none, .none):
                // 两者都没有访问时间，可以按标题排序以保持稳定
                return book1.title.localizedCompare(book2.title) == .orderedAscending
            }
        }
        // 更新 @Published 属性以触发 UI 刷新
        self.books = sortedBooks
    }
    
    func loadBook(_ book: Book) {
        stopReading() // Stop reading before changing book
        isContentLoaded = false
        currentBookId = book.id
        currentBookTitle = book.title
        settingsManager.saveLastOpenedBookId(book.id) // Save as last opened
        
        // 更新最后访问时间
        libraryManager.updateLastAccessed(bookId: book.id)

        libraryManager.loadBookContent(book: book) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let content):
                    self.pages = self.textPaginator.paginate(text: content) // Use TextPaginator
                    let savedProgress = self.libraryManager.getBookProgress(bookId: book.id)
                    self.currentPageIndex = savedProgress?.currentPageIndex ?? 0
                    self.libraryManager.saveTotalPages(bookId: book.id, totalPages: self.pages.count) // Save total pages after pagination
                    self.isContentLoaded = true
                    self.updateNowPlayingInfo() // Initial info update
                case .failure(let error):
                    print("Error loading book content: \(error)")
                    self.pages = ["加载书籍内容失败: \(error.localizedDescription)"]
                    self.currentPageIndex = 0
                    self.isContentLoaded = true
                    // TODO: Show error alert to user
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
                // TODO: Show error to user
                return
            }
            // Update the books list
            self.books = self.libraryManager.loadBooks()
            self.sortBooks() // 对书籍列表进行排序

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

    // Called when a file is received via WiFi
    private func handleReceivedFile(fileName: String, content: String) {
        libraryManager.importBook(fileName: fileName, content: content) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let newBook):
                // Update book list and load the new book
                self.books = self.libraryManager.loadBooks()
                self.sortBooks() // 对书籍列表进行排序
                self.loadBook(newBook)
                // Optional: Show success message
            case .failure(let error):
                print("Error handling received file: \(error)")
                // TODO: Show error to user
            }
        }
    }

    // Called from DocumentPicker
    func importBookFromURL(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            print("Permission denied for URL: \(url)")
            // TODO: Show error to user
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        libraryManager.importBookFromURL(url) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success(let newBook):
                    self.books = self.libraryManager.loadBooks()
                    self.sortBooks() // 对书籍列表进行排序
                    self.loadBook(newBook)
                    // Optional: Show success message
                case .failure(let error):
                    print("Error importing from URL: \(error)")
                    // TODO: Show error to user
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

    func getLastAccessedTimeDisplay(book: Book) -> String? {
        guard let progress = libraryManager.getBookProgress(bookId: book.id),
              let lastAccessed = progress.lastAccessed else {
            return nil
        }
        
        let now = Date()
        let calendar = Calendar.current
        
        // 判断日期
        if calendar.isDateInToday(lastAccessed) {
            // 今天内的时间
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
            // 获取今年的范围
            let currentYear = calendar.component(.year, from: now)
            let accessedYear = calendar.component(.year, from: lastAccessed)
            
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            
            if currentYear == accessedYear {
                // 如果是今年，只显示月和日
                formatter.dateFormat = "M月d日阅读"
            } else {
                // 不是今年，显示年月日
                formatter.dateFormat = "yyyy年M月d日阅读"
            }
            
            return formatter.string(from: lastAccessed)
        }
    }

    // --- Reading Control ---
    func nextPage() {
        guard currentPageIndex < pages.count - 1 else { return }
        stopReadingIfActive() // Stop before changing page if reading
        currentPageIndex += 1
        startReadingIfWasActive() // Restart reading on new page if it was active
    }

    func previousPage() {
        guard currentPageIndex > 0 else { return }
        stopReadingIfActive()
        currentPageIndex -= 1
        startReadingIfWasActive()
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
        
        print("开始朗读当前页")
        let textToRead = pages[currentPageIndex]
        let voice = availableVoices.first { $0.identifier == selectedVoiceIdentifier }
        
        // 先设置状态为播放
        isReading = true
        
        // 确保状态同步
        DispatchQueue.main.async {
            // 立即更新播放信息
            self.updateNowPlayingInfo()
            
            // 然后开始语音播放
            self.speechManager.startReading(text: textToRead, voice: voice, rate: self.readingSpeed)
        }
    }

    func stopReading() {
        print("停止朗读")
        
        // 确保语音合成器立即停止
        speechManager.stopReading()
        
        // 先设置状态为停止
        isReading = false
        
        // 确保状态同步 - 强制执行两次更新以确保控制中心状态更新
        DispatchQueue.main.async {
            // 立即更新播放信息
            self.updateNowPlayingInfo()
            
            // 额外再次清空播放信息
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.audioSessionManager.clearNowPlayingInfo()
            }
            
            // 再次更新播放信息确保状态为暂停
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.updateNowPlayingInfo()
            }
        }
    }

    private func restartReading() {
        if isReading {
            print("重新开始朗读")
            stopReading()
            // Add a small delay before restarting to ensure synthesizer is fully stopped
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.readCurrentPage()
            }
        }
    }

    // Helper methods to manage reading state during page turns
    private var wasReadingBeforePageTurn: Bool = false
    private func stopReadingIfActive() {
        if isReading {
            wasReadingBeforePageTurn = true
            stopReading()
        } else {
            wasReadingBeforePageTurn = false
        }
    }
    private func startReadingIfWasActive() {
        if wasReadingBeforePageTurn {
            // Add a small delay before starting on the new page
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.readCurrentPage()
            }
        }
        wasReadingBeforePageTurn = false // Reset flag
    }

    // --- Search ---
    func searchContent(_ query: String) {
        guard !query.isEmpty, !pages.isEmpty else {
            searchResults = []
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

    // --- WiFi Transfer ---
    func toggleWiFiTransfer() {
        if isServerRunning {
            wiFiTransferService.stopServer()
        } else {
            let _ = wiFiTransferService.startServer()
        }
    }

    // --- Now Playing Info ---
    private func updateNowPlayingInfo() {
        // 在主线程更新Now Playing信息并确保状态同步
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

    // --- Cleanup ---
    deinit {
        // Cancel any ongoing operations if needed
        stopReading()
        wiFiTransferService.stopServer()
        cancellables.forEach { $0.cancel() }
    }
} 