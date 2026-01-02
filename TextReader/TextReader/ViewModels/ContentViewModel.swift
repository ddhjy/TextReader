import SwiftUI
import Combine
import AVFoundation
import UIKit

class ContentViewModel: ObservableObject {
    private static let dateFormatterMonthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter
    }()
    
    private static let dateFormatterFull: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter
    }()
    
    private var bookProgressCache: [String: BookProgress] = [:]
    private var bookDisplayCache: [String: (progress: String?, lastAccessed: String?)] = [:]
    @Published var pages: [String] = []
    @Published var currentPageIndex: Int = 0
    @Published var currentBookTitle: String = "TextReader"
    @Published var isContentLoaded: Bool = false
    @Published var isReading: Bool = false
    @Published var isSwitchingPlayState: Bool = false
    @Published var availableVoices: [AVSpeechSynthesisVoice] = []
    @Published var selectedVoiceIdentifier: String?
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
    @Published var accentColorThemeId: String = "blue"
    @Published var showingBigBang = false
    @Published var tokens: [Token] = []
    @Published var selectedTokenIDs: Set<UUID> = []
    private var firstTapInSequence: UUID? = nil
    @Published var templates: [PromptTemplate] = []
    @Published var showingTemplatePicker = false
    @Published var generatedPrompt: AlertMessage?
    @Published var showingBookEdit = false
    @Published var showingSettings = false
    @Published var bookToEdit: Book?
    
    @Published var wifiUploadProgress: Double?
    @Published var wifiUploadFilename: String?
    @Published var wifiUploadError: String?
    
    private var isAutoAdvancing = false
    private var activeUtteranceId: UUID?
    private var activeUtterancePageIndex: Int?
    private var pendingResumeAfterManualTurn: Bool = false
    private var manualTurnResumeWorkItem: DispatchWorkItem?

    let libraryManager: LibraryManager
    private let textPaginator: TextPaginator
    private let speechManager: SpeechManager
    private let searchService: SearchService
    private let wiFiTransferService: WiFiTransferService
    private let audioSessionManager: AudioSessionManager
    private let settingsManager: SettingsManager
    private let tokenizer = Tokenizer()
    private let templateManager = TemplateManager()

    private var cancellables = Set<AnyCancellable>()
    
    var currentAccentColor: Color {
        let theme = AccentColorTheme.presets.first { $0.id == accentColorThemeId } ?? AccentColorTheme.presets[0]
        return theme.color(for: darkModeEnabled ? .dark : .light)
    }

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
            .dropFirst()
            .sink { [weak self] isReading in
                guard let self = self else { return }
                print("isReading状态变化: \(isReading)")
                self.updateNowPlayingInfo()
            }
            .store(in: &cancellables)
    }

    private func loadInitialData() {
        if let cachedContent = settingsManager.getLastPageContent(), !cachedContent.isEmpty,
           let lastBookId = settingsManager.getLastOpenedBookId() {
            let cachedPageIndex = settingsManager.getLastPageIndex()
            let cachedTotalPages = settingsManager.getLastTotalPages()
            if cachedTotalPages > 0 {
                self.pages = Array(repeating: "", count: cachedTotalPages)
                self.pages[cachedPageIndex] = cachedContent
                self.currentPageIndex = cachedPageIndex
            } else {
                self.pages = [cachedContent]
                self.currentPageIndex = 0
            }
            self.currentBookId = lastBookId
            self.currentBookTitle = settingsManager.getLastBookTitle() ?? "TextReader"
            self.isContentLoaded = true
            print("[ContentViewModel] 从 UserDefaults 快速启动，显示缓存内容，页 \(cachedPageIndex + 1)/\(cachedTotalPages)")
        }
        
        self.readingSpeed = settingsManager.getReadingSpeed()
        self.availableVoices = speechManager.getAvailableVoices(languagePrefix: "zh")
        self.selectedVoiceIdentifier = settingsManager.getSelectedVoiceIdentifier() ?? availableVoices.first?.identifier
        self.accentColorThemeId = settingsManager.getAccentColorThemeId()
        self.darkModeEnabled = settingsManager.getDarkMode()
        
        DispatchQueue.main.async {
            self.books = self.libraryManager.loadBooks()
            self.sortBooks()
            self.templates = self.templateManager.load()
            
            let lastBookId = self.settingsManager.getLastOpenedBookId()
            if let bookId = lastBookId, let bookToLoad = self.books.first(where: { $0.id == bookId }) {
                self.currentBookId = bookToLoad.id
                self.currentBookTitle = bookToLoad.title
                self.loadFullBookContent(bookToLoad)
            } else if let firstBook = self.books.first {
                self.loadBook(firstBook)
            } else {
                self.isContentLoaded = true
            }
        }
    }
    
    private func loadFullBookContent(_ book: Book) {
        let savedPageIndex = settingsManager.getLastPageIndex()
        
        libraryManager.loadBookContent(book: book) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let content):
                DispatchQueue.global(qos: .userInitiated).async {
                    let paginatedPages = self.textPaginator.paginate(text: content)
                    let summaries = self.searchService.pageSummaries(pages: paginatedPages)
                    
                    DispatchQueue.main.async {
                        guard self.currentBookId == book.id else { return }
                        self.pages = paginatedPages
                        self.currentPageIndex = min(max(0, savedPageIndex), max(0, paginatedPages.count - 1))
                        self.pageSummaries = summaries
                        self.searchResults = []
                        self.saveCurrentPageToCache()
                        self.isContentLoaded = true
                        self.updateNowPlayingInfo()
                        print("[ContentViewModel] 完整内容加载完成，共 \(paginatedPages.count) 页，当前页 \(self.currentPageIndex)")
                    }
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    print("后台加载书籍内容失败: \(error)")
                    self.isContentLoaded = true
                }
            }
        }
    }

    private func setupBindings() {
        $currentPageIndex
            .dropFirst()
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] index in
                guard let self = self, let bookId = self.currentBookId else { return }
                self.saveCurrentPageToCache()
                self.updateNowPlayingInfo()
                DispatchQueue.global(qos: .utility).async {
                    self.libraryManager.saveBookProgress(bookId: bookId, pageIndex: index)
                }
            }
            .store(in: &cancellables)

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
            
        $accentColorThemeId
            .dropFirst()
            .sink { [weak self] id in 
                self?.settingsManager.saveAccentColorThemeId(id) 
            }
            .store(in: &cancellables)
            
        setupSyncTimer()
    }

    private func setupSyncTimer() {
        Timer.publish(every: 2.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                
                let speechManagerActive = speechManager.isSpeaking
                
                if self.isAutoAdvancing || self.pendingResumeAfterManualTurn {
                    return
                }
                
                if self.isReading != speechManagerActive {
                    print("检测到状态不一致: UI=\(self.isReading), Speech=\(speechManagerActive)")
                    
                    if !self.isReading && speechManagerActive {
                        print("强制停止播放")
                        self.speechManager.stopReading()
                    } else if self.isReading && !speechManagerActive {
                        print("状态同步：更新为已停止")
                        self.isReading = false
                        self.updateNowPlayingInfo()
                    }
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
        
        wiFiTransferService.$uploadState
            .receive(on: RunLoop.main)
            .sink { [weak self] s in
                guard let self = self else { return }
                guard let state = s else {
                    self.wifiUploadProgress = nil
                    self.wifiUploadFilename = nil
                    self.wifiUploadError = nil
                    return
                }
                if let total = state.totalBytes, total > 0 {
                    let received = max(0, state.receivedBytes)
                    self.wifiUploadProgress = min(1.0, max(0.0, Double(received) / Double(total)))
                } else {
                    self.wifiUploadProgress = nil
                }
                self.wifiUploadFilename = state.fileName
                self.wifiUploadError = state.errorMessage
            }
            .store(in: &cancellables)
    }

    private func setupSpeechCallbacks() {
        speechManager.onSpeechFinish = { [weak self] utteranceId in
            guard let self = self else { return }

            guard self.isReading else { return }
            guard utteranceId == self.activeUtteranceId else { return }
            // 如果用户在本轮朗读期间手动翻页（或拖动进度条）改变了 currentPageIndex，
            // 该 finish 不应再触发自动翻页，否则会出现“手动翻页翻两页”的问题。
            guard self.activeUtterancePageIndex == self.currentPageIndex else { return }
            
            self.isAutoAdvancing = true
            
            if !self.pages.isEmpty && self.currentPageIndex < self.pages.count - 1 {
                self.currentPageIndex += 1
                self.readCurrentPage()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.isAutoAdvancing = false
                }
            } else {
                self.isReading = false
                self.isAutoAdvancing = false
                self.updateNowPlayingInfo()
            }
        }
        
        speechManager.onSpeechStart = { [weak self] utteranceId in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard utteranceId == self.activeUtteranceId else { return }
                if !self.isReading {
                    self.isReading = true
                    self.updateNowPlayingInfo()
                }
            }
        }
        
        speechManager.onSpeechPause = { [weak self] utteranceId in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard utteranceId == self.activeUtteranceId else { return }
                if self.isReading {
                    self.isReading = false
                    self.updateNowPlayingInfo()
                }
            }
        }
        
        speechManager.onSpeechResume = { [weak self] utteranceId in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard utteranceId == self.activeUtteranceId else { return }
                if !self.isReading {
                    self.isReading = true
                    self.updateNowPlayingInfo()
                }
            }
        }
        
        speechManager.onSpeechError = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if self.isReading {
                    self.isReading = false
                    self.updateNowPlayingInfo()
                    print("语音合成错误，播放已停止")
                }
            }
        }
    }

    private func sortBooks() {
        refreshBookProgressCache()
        
        let sortedBooks = books.sorted { book1, book2 in
            let lastAccessed1 = bookProgressCache[book1.id]?.lastAccessed
            let lastAccessed2 = bookProgressCache[book2.id]?.lastAccessed

            switch (lastAccessed1, lastAccessed2) {
            case (let date1?, let date2?):
                return date1 > date2
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return book1.title.localizedCompare(book2.title) == .orderedAscending
            }
        }
        self.books = sortedBooks
    }
    
    private func refreshBookProgressCache() {
        bookProgressCache.removeAll()
        bookDisplayCache.removeAll()
        
        for book in books {
            if let progress = libraryManager.getBookProgress(bookId: book.id) {
                bookProgressCache[book.id] = progress
                
                let progressText = "已读 \(progress.currentPageIndex + 1)/\(progress.totalPages) 页"
                let lastAccessedText = formatLastAccessedTime(progress.lastAccessed)
                bookDisplayCache[book.id] = (progressText, lastAccessedText)
            }
        }
    }
    
    private func formatLastAccessedTime(_ lastAccessed: Date?) -> String? {
        guard let lastAccessed = lastAccessed else { return nil }
        
        let now = Date()
        let calendar = Calendar.current
        
        if calendar.isDateInToday(lastAccessed) {
            let components = calendar.dateComponents([.minute, .hour], from: lastAccessed, to: now)
            let totalMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            
            if totalMinutes < 5 {
                return "刚刚"
            } else if totalMinutes < 60 {
                return "\(totalMinutes)分钟前"
            } else {
                return "\(components.hour ?? 0)小时前"
            }
        } else if calendar.isDateInYesterday(lastAccessed) {
            return "昨天"
        } else {
            let currentYear = calendar.component(.year, from: now)
            let accessedYear = calendar.component(.year, from: lastAccessed)
            
            if currentYear == accessedYear {
                return Self.dateFormatterMonthDay.string(from: lastAccessed)
            } else {
                return Self.dateFormatterFull.string(from: lastAccessed)
            }
        }
    }
    
    func importPastedText(_ rawText: String, title customTitle: String?) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        var title = (customTitle?.trimmingCharacters(in: .whitespacesAndNewlines)).nilIfEmpty()
                   ?? String(text.replacingOccurrences(of: "\n", with: " ").prefix(10))

        let invalidSet = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        title = title.components(separatedBy: invalidSet).joined()

        let fileName = "\(title).txt"

        libraryManager.importBook(fileName: fileName, content: text) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success(let newBook):
                    self.books = self.libraryManager.loadBooks()
                    self.sortBooks()
                    self.loadBook(newBook)
                case .failure(let err):
                    print("粘贴导入失败: \(err)")
                }
            }
        }
    }
    
    func loadBook(_ book: Book) {
        stopReading()
        isContentLoaded = false
        currentPageIndex = 0
        currentBookId = book.id
        currentBookTitle = book.title
        settingsManager.saveLastOpenedBookId(book.id)
        
        libraryManager.updateLastAccessed(bookId: book.id)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.sortBooks()
            print("[ContentViewModel] 加载书籍后重新排序: \(book.title)")
        }

        let savedProgress = self.libraryManager.getBookProgress(bookId: book.id)
        let savedPageIndex = savedProgress?.currentPageIndex ?? 0
        
        if let lastPageContent = savedProgress?.lastPageContent, !lastPageContent.isEmpty {
            print("[ContentViewModel] 使用缓存的单页内容快速启动")
            self.pages = [lastPageContent]
            self.currentPageIndex = 0
            self.isContentLoaded = true
            self.updateNowPlayingInfo()
            
            libraryManager.loadBookContent(book: book) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self = self, self.currentBookId == book.id else { return }
                    switch result {
                    case .success(let content):
                        self.pages = self.textPaginator.paginate(text: content)
                        self.currentPageIndex = min(max(0, savedPageIndex), max(0, self.pages.count - 1))
                        self.saveCurrentPageToCache()
                        self.pageSummaries = self.searchService.pageSummaries(pages: self.pages)
                        self.searchResults = []
                        self.updateNowPlayingInfo()
                        print("[ContentViewModel] 完整内容加载完成，共 \(self.pages.count) 页")
                    case .failure(let error):
                        print("后台加载书籍内容失败: \(error)")
                    }
                }
            }
            return
        }

        print("[ContentViewModel] 无缓存，从文件加载书籍内容")
        libraryManager.loadBookContent(book: book) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let content):
                    self.pages = self.textPaginator.paginate(text: content)
                    self.currentPageIndex = min(max(0, savedPageIndex), max(0, self.pages.count - 1))
                    
                    self.saveCurrentPageToCache()
                    
                    self.pageSummaries = self.searchService.pageSummaries(pages: self.pages)
                    self.searchResults = []
                    
                    self.isContentLoaded = true
                    self.updateNowPlayingInfo()
                case .failure(let error):
                    print("加载书籍内容失败: \(error)")
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

        libraryManager.deleteBook(book) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success:
                self.books = self.libraryManager.loadBooks()
                self.sortBooks()
                
                if wasCurrentBook {
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
                
            case .failure(let error):
                print("删除书籍失败: \(book.title), 错误: \(error)")
            }
        }
    }

    func deleteBooks(_ booksToDelete: [Book]) {
        let deletingCurrent = booksToDelete.contains { $0.id == currentBookId }
        if deletingCurrent {
            stopReading()
        }

        let group = DispatchGroup()
        for book in booksToDelete {
            group.enter()
            libraryManager.deleteBook(book) { _ in
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.books = self.libraryManager.loadBooks()
            self.sortBooks()

            if deletingCurrent {
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

    private func handleReceivedFile(fileName: String, content: String) {
        libraryManager.importBook(fileName: fileName, content: content) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let newBook):
                self.books = self.libraryManager.loadBooks()
                self.sortBooks()
                self.loadBook(newBook)
            case .failure(let error):
                print("处理接收文件失败: \(error)")
            }
        }
    }

    func importBookFromURL(_ url: URL, suggestedTitle: String? = nil) {
        print("[ContentViewModel] 从URL导入书籍: \(url.absoluteString)")
        print("[ContentViewModel] 建议标题: \(suggestedTitle ?? "无")")
        
        libraryManager.importBookFromURL(url, suggestedTitle: suggestedTitle) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                switch result {
                case .success(let book):
                    print("[ContentViewModel] 成功导入书籍: \(book.title)")
                    self.books = self.libraryManager.loadBooks()
                    self.sortBooks()
                    self.loadBook(book)
                    
                case .failure(let error):
                    print("[ContentViewModel] 导入书籍失败: \(error)")
                }
            }
        }
    }

    func getBookProgressDisplay(book: Book) -> String? {
        if let cached = bookDisplayCache[book.id] {
            return cached.progress
        }
        if let progress = libraryManager.getBookProgress(bookId: book.id) {
            return "已读 \(progress.currentPageIndex + 1)/\(progress.totalPages) 页"
        }
        return nil
    }

    func getLastAccessedTimeDisplay(book: Book) -> String? {
        if let cached = bookDisplayCache[book.id] {
            return cached.lastAccessed
        }
        guard let progress = libraryManager.getBookProgress(bookId: book.id),
              let lastAccessed = progress.lastAccessed else {
            return nil
        }
        return formatLastAccessedTime(lastAccessed)
    }

    func updateBookTitle(book: Book, newTitle: String) {
        libraryManager.updateBookTitle(book: book, newTitle: newTitle) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let updatedBook):
                if let index = self.books.firstIndex(where: { $0.id == book.id }) {
                    self.books[index] = updatedBook
                }
                
                if book.id == self.currentBookId {
                    self.currentBookTitle = newTitle
                }
                
            case .failure(let error):
                print("Failed to update book title: \(error)")
            }
        }
    }
    
    func updateBookContent(book: Book, newContent: String, completion: @escaping (Bool) -> Void) {
        libraryManager.updateBookContent(book: book, newContent: newContent) { [weak self] result in
            guard let self = self else {
                completion(false)
                return
            }
            
            switch result {
            case .success:
                if book.id == self.currentBookId {
                    self.pages = self.textPaginator.paginate(text: newContent)
                    self.currentPageIndex = 0
                    self.pageSummaries = self.searchService.pageSummaries(pages: self.pages)
                    self.searchResults = []
                    
                    self.libraryManager.saveCachedPages(bookId: book.id, pages: self.pages)
                } else {
                    self.libraryManager.clearCachedPages(bookId: book.id)
                }
                completion(true)
                
            case .failure(let error):
                print("Failed to update book content: \(error)")
                completion(false)
            }
        }
    }

    func nextPage() {
        goToPage(currentPageIndex + 1)
    }

    func previousPage() {
        goToPage(currentPageIndex - 1)
    }

    private func cancelPendingManualResume() {
        manualTurnResumeWorkItem?.cancel()
        manualTurnResumeWorkItem = nil
        pendingResumeAfterManualTurn = false
    }

    private func scheduleResumeAfterManualTurn() {
        manualTurnResumeWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.manualTurnResumeWorkItem = nil
            guard self.pendingResumeAfterManualTurn else { return }
            self.pendingResumeAfterManualTurn = false
            self.readCurrentPage()
        }

        manualTurnResumeWorkItem = workItem
        // 轻微去抖：快速连翻时只朗读最终停下的那一页，避免因回调时序导致“读停了”
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    /// 手动跳转到指定页。若当前正在朗读（或处于手动连翻的续读状态），会在短暂去抖后继续朗读目标页。
    func goToPage(_ index: Int) {
        guard !pages.isEmpty, pages.indices.contains(index) else { return }
        guard index != currentPageIndex else { return }

        let shouldResume = pendingResumeAfterManualTurn || isReading || speechManager.isSpeaking
        pendingResumeAfterManualTurn = shouldResume

        if shouldResume {
            // 维持“继续朗读”的意图，避免快速连翻时 isReading 被异步 pause/cancel 改成 false
            if !isReading {
                isReading = true
                updateNowPlayingInfo()
            }
            speechManager.stopReading()
        }

        currentPageIndex = index

        if shouldResume {
            scheduleResumeAfterManualTurn()
        } else {
            updateNowPlayingInfo()
        }
    }

    func toggleReading() {
        guard !isSwitchingPlayState else { 
            print("正在切换播放状态，忽略新的切换请求")
            return 
        }
        
        isSwitchingPlayState = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.isSwitchingPlayState = false
        }
        
        if isReading {
            stopReading()
        } else {
            readCurrentPage()
        }
    }

    func readCurrentPage() {
        // 若是手动连翻后的去抖续读，进入朗读时清掉待执行任务，避免重复触发
        manualTurnResumeWorkItem?.cancel()
        manualTurnResumeWorkItem = nil
        pendingResumeAfterManualTurn = false

        guard !pages.isEmpty, 
              currentPageIndex >= 0,
              currentPageIndex < pages.count else { return }
        
        print("开始朗读当前页面")
        let textToRead = pages[currentPageIndex]
        let voice = availableVoices.first { $0.identifier == selectedVoiceIdentifier }
        
        isReading = true
        activeUtterancePageIndex = currentPageIndex
        
        updateNowPlayingInfo()
        
        activeUtteranceId = speechManager.startReading(text: textToRead, voice: voice, rate: readingSpeed)
    }

    func stopReading() {
        cancelPendingManualResume()
        activeUtteranceId = nil
        activeUtterancePageIndex = nil
        speechManager.stopReading()
        isReading = false
        updateNowPlayingInfo()
    }

    private func restartReading() {
        if isReading {
            print("重新开始朗读")
            stopReading()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.readCurrentPage()
            }
        }
    }

    func searchContent(_ query: String) {
        guard !query.isEmpty else {
            searchResults = []
            pageSummaries = searchService.pageSummaries(pages: pages)
            return
        }
        searchResults = searchService.search(query: query, in: pages)
    }

    func jumpToSearchResult(pageIndex: Int) {
        guard pageIndex >= 0 && pageIndex < pages.count else { return }
        stopReading()
        currentPageIndex = pageIndex
        showingSearchView = false
    }
    
    private func saveCurrentPageToCache() {
        guard !pages.isEmpty,
              currentPageIndex >= 0,
              currentPageIndex < pages.count else { return }
        let currentContent = pages[currentPageIndex]
        settingsManager.saveLastPageContent(currentContent)
        settingsManager.saveLastPageIndex(currentPageIndex)
        settingsManager.saveLastBookTitle(currentBookTitle)
        settingsManager.saveLastTotalPages(pages.count)
    }

    func toggleWiFiTransfer() {
        if isServerRunning {
            wiFiTransferService.stopServer()
        } else {
            let _ = wiFiTransferService.startServer()
        }
    }

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

    func handleImportedURL(_ url: URL) {
        print("[ContentViewModel] 处理导入的URL: \(url.absoluteString)")

        if url.scheme == "textreader" {
            handleCustomSchemeURL(url)
            return
        }
        
        guard url.isFileURL else {
            print("[ContentViewModel][警告] 接收的URL不是文件URL。Scheme: \(url.scheme ?? "nil")。忽略。")
            return
        }

        print("[ContentViewModel] URL是文件URL，尝试通过importBookFromURL导入...")
        importBookFromURL(url)
    }
    
    private func handleCustomSchemeURL(_ url: URL) {
        print("[ContentViewModel] 处理自定义scheme URL: \(url.absoluteString)")
        
        guard let host = url.host, host == "import" else {
            print("[ContentViewModel][警告] 不支持的URL主机: \(url.host ?? "nil")")
            return
        }
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let queryItems = components.queryItems else {
            print("[ContentViewModel][警告] URL中没有查询项")
            return
        }
        
        if let textItem = queryItems.first(where: { $0.name == "text" }),
           let encodedText = textItem.value,
           let decodedText = encodedText.removingPercentEncoding,
           !decodedText.isEmpty {
            
            print("[ContentViewModel] 找到text参数，长度: \(decodedText.count)")
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
            let timestamp = dateFormatter.string(from: Date())
            
            var title = "分享_\(timestamp)"
            let contentPreview = decodedText.prefix(10).trimmingCharacters(in: .whitespacesAndNewlines)
            if !contentPreview.isEmpty {
                title = contentPreview + "..."
            }
            
            do {
                let tempDir = FileManager.default.temporaryDirectory
                let tempFile = tempDir.appendingPathComponent("\(title)_\(timestamp).txt")
                
                try decodedText.write(to: tempFile, atomically: true, encoding: .utf8)
                print("[ContentViewModel] 已将共享文本保存到临时文件: \(tempFile.path)")
                
                importBookFromURL(tempFile, suggestedTitle: title)
            } catch {
                print("[ContentViewModel][错误] 保存共享文本到临时文件失败: \(error.localizedDescription)")
            }
        } else {
            print("[ContentViewModel][警告] URL中未找到有效的text参数")
        }
    }

    func triggerBigBang() {
        guard !pages.isEmpty,
              currentPageIndex >= 0,
              currentPageIndex < pages.count else { return }
        let text = pages[currentPageIndex]
       tokenizer.tokenize(text: text) { [weak self] tokens in
           self?.tokens = tokens
       }
        self.selectedTokenIDs = []
        self.firstTapInSequence = nil
        self.showingBigBang = true
    }

    func processTokenTap(tappedTokenID: UUID) {
        if let firstTapped = firstTapInSequence {
            if tappedTokenID == firstTapped {
                selectedTokenIDs.removeAll()
                firstTapInSequence = nil
            } else {
                selectedTokenIDs.removeAll()
                selectTokenRange(from: firstTapped, to: tappedTokenID)
            }
        } else {
            selectedTokenIDs.removeAll()
            selectedTokenIDs.insert(tappedTokenID)
            firstTapInSequence = tappedTokenID
        }
    }

    private func selectTokenRange(from startID: UUID, to endID: UUID) {
        guard let sIndex = tokens.firstIndex(where: { $0.id == startID }),
              let eIndex = tokens.firstIndex(where: { $0.id == endID }) else {
            if tokens.contains(where: { $0.id == startID }) {
                selectedTokenIDs.insert(startID)
            } else if tokens.contains(where: { $0.id == endID }) {
                selectedTokenIDs.insert(endID)
            }
            return
        }

        let range = min(sIndex, eIndex)...max(sIndex, eIndex)
        for i in range {
            selectedTokenIDs.insert(tokens[i].id)
        }
    }

    func clearSelectedTokens() {
        selectedTokenIDs.removeAll()
        firstTapInSequence = nil
    }

    func copySelected() {
        let text = tokens.filter { selectedTokenIDs.contains($0.id) }
                         .map(\.value).joined()
        UIPasteboard.general.string = text
        showingBigBang = false
    }

    func addTemplate(_ t: PromptTemplate) {
        templates.append(t)
        templateManager.save(templates)
    }

    func updateTemplate(_ t: PromptTemplate) {
        guard let idx = templates.firstIndex(where: { $0.id == t.id }) else { return }
        templates[idx] = t
        templateManager.save(templates)
    }

    func deleteTemplate(_ t: PromptTemplate) {
        templates.removeAll { $0.id == t.id }
        templateManager.save(templates)
    }
    
    enum PromptDestination {
        case copyOnly
        case perplexity
        case raycast
    }
    
    func buildPrompt(using template: PromptTemplate, destination: PromptDestination = .perplexity) {
        let selection = tokens.filter { selectedTokenIDs.contains($0.id) }.map(\.value).joined()
        
        var contextContent: [String] = []
        if currentPageIndex > 0 {
            contextContent.append(pages[currentPageIndex - 1])
        }
        if pages.indices.contains(currentPageIndex) {
            contextContent.append(pages[currentPageIndex])
        }
        if currentPageIndex < pages.count - 1 {
            contextContent.append(pages[currentPageIndex + 1])
        }
        let page = contextContent.joined(separator: "\n\n---\n\n")

        var result = template.content
        result = result.replacingOccurrences(of: "{selection}", with: selection)
        result = result.replacingOccurrences(of: "{page}", with: page)
        result = result.replacingOccurrences(of: "{book}", with: currentBookTitle)
        UIPasteboard.general.string = result
        
        switch destination {
        case .copyOnly:
            break
        case .perplexity:
            if let encodedQuery = result.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let url = URL(string: "https://www.perplexity.ai/search/new?q=\(encodedQuery)") {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        case .raycast:
            if let url = URL(string: "raycast://extensions/") {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
    }

    deinit {
        stopReading()
        wiFiTransferService.stopServer()
        cancellables.forEach { $0.cancel() }
    }
} 