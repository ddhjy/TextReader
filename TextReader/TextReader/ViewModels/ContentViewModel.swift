import SwiftUI
import Combine
import AVFoundation
import UIKit

/// 内容视图模型，负责管理应用的核心功能和状态
/// 管理文本分页与显示、朗读控制、书籍库、搜索、WiFi传输等功能
class ContentViewModel: ObservableObject {
    // MARK: - UI绑定的发布属性
    @Published var pages: [String] = []
    @Published var currentPageIndex: Int = 0
    @Published var currentBookTitle: String = "TextReader"
    @Published var isContentLoaded: Bool = false
    @Published var isReading: Bool = false
    @Published var isSwitchingPlayState: Bool = false // 添加播放状态切换标志
    @Published var availableVoices: [AVSpeechSynthesisVoice] = []
    @Published var selectedVoiceIdentifier: String? // 用于绑定和持久化
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
    // 强调色相关状态
    @Published var accentColorThemeId: String = "blue"
    @Published var showingAccentColorPicker = false
    // BigBang 相关状态
    @Published var showingBigBang = false
    @Published var tokens: [Token] = []
    @Published var selectedTokenIDs: Set<UUID> = []
    private var firstTapInSequence: UUID? = nil
    // 模板相关状态
    @Published var templates: [PromptTemplate] = []
    @Published var showingTemplatePicker = false
    @Published var generatedPrompt: AlertMessage?
    // Add edit-related states
    @Published var showingBookEdit = false
    @Published var bookToEdit: Book?
    
    // 添加手动翻页标志，用于区分手动翻页和自动翻页
    private var isManualPageTurn = false

    // MARK: - Dependencies
    let libraryManager: LibraryManager  // Remove private to allow access by BookEditView
    private let textPaginator: TextPaginator
    private let speechManager: SpeechManager
    private let searchService: SearchService
    private let wiFiTransferService: WiFiTransferService
    private let audioSessionManager: AudioSessionManager
    private let settingsManager: SettingsManager
    // BigBang 工具依赖
    private let tokenizer = Tokenizer()
    // 模板管理依赖
    private let templateManager = TemplateManager()

    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - 计算属性
    var currentAccentColor: Color {
        let theme = AccentColorTheme.presets.first { $0.id == accentColorThemeId } ?? AccentColorTheme.presets[0]
        return theme.color(for: darkModeEnabled ? .dark : .light)
    }

    // MARK: - 初始化
    /// 初始化视图模型并设置各项依赖和回调
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
                // 卡马克式简单方案：状态变化时直接更新媒体信息即可
                self.updateNowPlayingInfo()
            }
            .store(in: &cancellables)
    }

    // MARK: - 数据加载
    private func loadInitialData() {
        self.books = libraryManager.loadBooks()
        sortBooks()
        
        let lastBookId = settingsManager.getLastOpenedBookId()
        if let bookId = lastBookId, let bookToLoad = books.first(where: { $0.id == bookId }) {
            loadBook(bookToLoad)
        } else if let firstBook = books.first {
            loadBook(firstBook)
        } else {
            isContentLoaded = true
        }
        self.readingSpeed = settingsManager.getReadingSpeed()
        self.availableVoices = speechManager.getAvailableVoices(languagePrefix: "zh")
        self.selectedVoiceIdentifier = settingsManager.getSelectedVoiceIdentifier() ?? availableVoices.first?.identifier
        self.templates = templateManager.load()
        self.accentColorThemeId = settingsManager.getAccentColorThemeId()
    }

    // MARK: - 绑定与回调
    /// 设置数据绑定，监听状态变化并保存相关设置
    private func setupBindings() {
        // 页面改变时保存进度
        $currentPageIndex
            .dropFirst()
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] index in
                guard let self = self, let bookId = self.currentBookId else { return }
                self.libraryManager.saveBookProgress(bookId: bookId, pageIndex: index)
                self.updateNowPlayingInfo()
            }
            .store(in: &cancellables)

        // 设置改变时保存
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

    /// 设置定时器，定期检查并同步系统播放状态
    private func setupSyncTimer() {
        // 卡马克式简单方案：减少复杂的同步，只做最基本的状态检查
        Timer.publish(every: 2.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                
                let speechManagerActive = speechManager.isSpeaking
                
                // 只修正明显不一致的状态
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

    /// 设置WiFi传输服务的回调函数
    private func setupWiFiTransferCallbacks() {
        wiFiTransferService.onFileReceived = { [weak self] fileName, content in
            self?.handleReceivedFile(fileName: fileName, content: content)
        }
        wiFiTransferService.$serverAddress
            .assign(to: &$serverAddress)
        wiFiTransferService.$isRunning
            .assign(to: &$isServerRunning)
    }

    /// 设置语音回调函数
    private func setupSpeechCallbacks() {
        speechManager.onSpeechFinish = { [weak self] in
            guard let self = self else { return }
            
            // 如果是手动翻页，重置标志并返回，不自动翻页
            if self.isManualPageTurn {
                self.isManualPageTurn = false
                return
            }
            
            // 保存语音结束时的页面索引，以便稍后验证
            let finishedPageIndex = self.currentPageIndex
            
            DispatchQueue.main.async {
                guard self.isReading else { return }
                
                // 验证当前页面索引与语音结束时的索引是否匹配
                // 这可以防止手动翻页和自动前进之间的竞争条件
                guard self.currentPageIndex == finishedPageIndex else {
                    print("页面已更改，跳过自动前进")
                    return
                }
                
                // 自动前进到下一页
                if !self.pages.isEmpty && self.currentPageIndex < self.pages.count - 1 {
                    self.currentPageIndex += 1
                    self.readCurrentPage()
                } else {
                    self.isReading = false // 到达书籍末尾
                    self.updateNowPlayingInfo()
                }
            }
        }
        
        speechManager.onSpeechStart = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                // 确保语音开始时播放状态一致
                if !self.isReading {
                    self.isReading = true
                    self.updateNowPlayingInfo()
                }
                // 语音真正开始播放，重置切换状态标志
                self.isSwitchingPlayState = false
            }
        }
        
        speechManager.onSpeechPause = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                // 确保语音暂停时播放状态一致
                if self.isReading {
                    self.isReading = false
                    self.updateNowPlayingInfo()
                }
            }
        }
        
        speechManager.onSpeechResume = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                // 确保语音恢复时播放状态一致
                if !self.isReading {
                    self.isReading = true
                    self.updateNowPlayingInfo()
                }
            }
        }
        
        speechManager.onSpeechError = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                // 发生语音合成错误时重置状态
                if self.isReading {
                    self.isReading = false
                    self.updateNowPlayingInfo()
                    print("语音合成错误，播放已停止")
                }
                // 发生错误时也要重置切换状态标志
                self.isSwitchingPlayState = false
            }
        }
    }

    // MARK: - 书籍管理
    
    /// 对书籍进行排序，最近访问的排在前面
    private func sortBooks() {
        let sortedBooks = books.sorted { book1, book2 in
            let lastAccessed1 = libraryManager.getBookProgress(bookId: book1.id)?.lastAccessed
            let lastAccessed2 = libraryManager.getBookProgress(bookId: book2.id)?.lastAccessed

            // 排序逻辑:
            // 1. 如果book1有访问时间但book2没有，book1排在前面
            // 2. 如果book1没有访问时间但book2有，book2排在前面
            // 3. 如果两者都有访问时间，按照最近的时间排在前面
            // 4. 如果两者都没有访问时间，按标题排序保持稳定性
            switch (lastAccessed1, lastAccessed2) {
            case (let date1?, let date2?):
                return date1 > date2 // 按时间降序排列
            case (.some, .none):
                return true // 有访问时间的书籍排在前面
            case (.none, .some):
                return false // 没有访问时间的书籍排在后面
            case (.none, .none):
                return book1.title.localizedCompare(book2.title) == .orderedAscending
            }
        }
        self.books = sortedBooks
    }
    
    /// 导入粘贴的文本内容为新书籍
    /// - Parameters:
    ///   - rawText: 原始文本内容
    ///   - customTitle: 自定义标题，如果为nil则从文本内容自动生成
    func importPastedText(_ rawText: String, title customTitle: String?) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // 若未输入标题，取前10个字符；去掉换行
        var title = (customTitle?.trimmingCharacters(in: .whitespacesAndNewlines)).nilIfEmpty()
                   ?? String(text.replacingOccurrences(of: "\n", with: " ").prefix(10))

        // 过滤文件名非法字符，避免写文件失败
        let invalidSet = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        title = title.components(separatedBy: invalidSet).joined()

        // 移除时间戳后缀，直接使用标题作为文件名
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
    
    /// 加载指定的书籍
    /// - Parameter book: 要加载的书籍
    func loadBook(_ book: Book) {
        stopReading() // 加载新书前停止朗读
        isContentLoaded = false
        // 在加载新书时立即重置页面索引，防止在异步加载过程中出现越界访问
        currentPageIndex = 0
        currentBookId = book.id
        currentBookTitle = book.title
        settingsManager.saveLastOpenedBookId(book.id) // 保存为上次打开的书籍
        
        // 更新最后访问时间
        libraryManager.updateLastAccessed(bookId: book.id)

        sortBooks() // 更新后立即重新排序books数组
        print("[ContentViewModel] 加载书籍后重新排序: \(book.title)")

        libraryManager.loadBookContent(book: book) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let content):
                    self.pages = self.textPaginator.paginate(text: content)
                    let savedProgress = self.libraryManager.getBookProgress(bookId: book.id)
                    let savedPageIndex = savedProgress?.currentPageIndex ?? 0
                    // 确保恢复的页面索引不会越界
                    self.currentPageIndex = min(max(0, savedPageIndex), max(0, self.pages.count - 1))
                    self.libraryManager.saveTotalPages(bookId: book.id, totalPages: self.pages.count)
                    
                    // 确保生成页面摘要
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

    /// 删除指定的书籍
    /// - Parameter book: 要删除的书籍
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
                    // 如果删除的是当前正在阅读的书籍，加载第一本可用书籍或清空视图
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

    /// 处理通过WiFi传输接收到的文件
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

    /// 从URL导入书籍（与文档选择器配合使用）
    func importBookFromURL(_ url: URL, suggestedTitle: String? = nil) {
        print("[ContentViewModel] 从URL导入书籍: \(url.absoluteString)")
        print("[ContentViewModel] 建议标题: \(suggestedTitle ?? "无")")
        
        libraryManager.importBookFromURL(url, suggestedTitle: suggestedTitle) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                switch result {
                case .success(let book):
                    print("[ContentViewModel] 成功导入书籍: \(book.title)")
                    // 更新书籍列表并加载
                    self.books = self.libraryManager.loadBooks()
                    self.sortBooks()
                    self.loadBook(book)
                    
                case .failure(let error):
                    print("[ContentViewModel] 导入书籍失败: \(error)")
                    // 这里可以添加错误处理逻辑，例如显示错误提示等
                }
            }
        }
    }

    /// 获取书籍阅读进度的显示文本
    func getBookProgressDisplay(book: Book) -> String? {
        if let progress = libraryManager.getBookProgress(bookId: book.id) {
            return "已读 \(progress.currentPageIndex + 1)/\(progress.totalPages) 页"
        }
        return nil
    }

    /// 获取书籍最后访问时间的用户友好描述
    func getLastAccessedTimeDisplay(book: Book) -> String? {
        guard let progress = libraryManager.getBookProgress(bookId: book.id),
              let lastAccessed = progress.lastAccessed else {
            return nil
        }
        
        let now = Date()
        let calendar = Calendar.current
        
        // 根据距离上次访问的时间长短决定合适的格式
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
                // 如果是今年，只显示月日
                formatter.dateFormat = "M月d日阅读"
            } else {
                // 否则显示完整日期（年月日）
                formatter.dateFormat = "yyyy年M月d日阅读"
            }
            
            return formatter.string(from: lastAccessed)
        }
    }

    // MARK: - Book Editing
    
    /// Update book title
    func updateBookTitle(book: Book, newTitle: String) {
        libraryManager.updateBookTitle(book: book, newTitle: newTitle) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let updatedBook):
                // Update local book list
                if let index = self.books.firstIndex(where: { $0.id == book.id }) {
                    self.books[index] = updatedBook
                }
                
                // If this is the currently opened book, update the title
                if book.id == self.currentBookId {
                    self.currentBookTitle = newTitle
                }
                
            case .failure(let error):
                print("Failed to update book title: \(error)")
            }
        }
    }
    
    /// Update book content
    func updateBookContent(book: Book, newContent: String, completion: @escaping (Bool) -> Void) {
        libraryManager.updateBookContent(book: book, newContent: newContent) { [weak self] result in
            guard let self = self else {
                completion(false)
                return
            }
            
            switch result {
            case .success:
                // If this is the currently opened book, reload content
                if book.id == self.currentBookId {
                    self.pages = self.textPaginator.paginate(text: newContent)
                    self.currentPageIndex = 0
                    self.pageSummaries = self.searchService.pageSummaries(pages: self.pages)
                    self.searchResults = []
                }
                completion(true)
                
            case .failure(let error):
                print("Failed to update book content: \(error)")
                completion(false)
            }
        }
    }

    // MARK: - 阅读控制
    
    func nextPage() {
        guard currentPageIndex < pages.count - 1 else { return }
        
        let wasReading = self.isReading
        
        // 设置手动翻页标志
        isManualPageTurn = true

        if wasReading {
            speechManager.stopReading()
        }

        currentPageIndex += 1

        if let bookId = self.currentBookId {
            libraryManager.updateLastAccessed(bookId: bookId)
            sortBooks()
        }

        if wasReading {
            DispatchQueue.main.async {
                self.readCurrentPage()
            }
        } else {
            updateNowPlayingInfo()
        }
    }

    func previousPage() {
        guard currentPageIndex > 0 else { return }
        
        let wasReading = self.isReading
        
        // 设置手动翻页标志
        isManualPageTurn = true

        if wasReading {
            speechManager.stopReading()
        }

        currentPageIndex -= 1

        if let bookId = self.currentBookId {
            libraryManager.updateLastAccessed(bookId: bookId)
            sortBooks()
        }

        if wasReading {
            DispatchQueue.main.async {
                self.readCurrentPage()
            }
        } else {
            updateNowPlayingInfo()
        }
    }

    /// 切换朗读状态（播放/暂停）
    func toggleReading() {
        // 如果正在切换状态，则忽略新的切换请求
        guard !isSwitchingPlayState else { 
            print("正在切换播放状态，忽略新的切换请求")
            return 
        }
        
        if isReading {
            stopReading()
        } else {
            readCurrentPage()
        }
    }

    /// 朗读当前页面
    func readCurrentPage() {
        guard !pages.isEmpty, 
              currentPageIndex >= 0,
              currentPageIndex < pages.count else { return }
        
        // 如果正在切换状态，则忽略新的播放请求
        guard !isSwitchingPlayState else { 
            print("正在切换播放状态，忽略播放请求")
            return 
        }
        
        print("开始朗读当前页面")
        let textToRead = pages[currentPageIndex]
        let voice = availableVoices.first { $0.identifier == selectedVoiceIdentifier }
        
        // 设置切换状态标志
        isSwitchingPlayState = true
        
        // 先设置状态为播放中
        isReading = true
        
        DispatchQueue.main.async {
            // 立即更新Now Playing信息
            self.updateNowPlayingInfo()
            
            // 然后开始语音播放
            self.speechManager.startReading(text: textToRead, voice: voice, rate: self.readingSpeed)
        }
    }

    /// 停止朗读
    func stopReading() {
        // 如果正在切换状态，则忽略新的停止请求
        guard !isSwitchingPlayState else { 
            print("正在切换播放状态，忽略停止请求")
            return 
        }
        
        // 设置切换状态标志
        isSwitchingPlayState = true
        
        // 重置手动翻页标志
        isManualPageTurn = false
        // 卡马克式简单方案：直接停止，直接更新，不要复杂的异步调用
        speechManager.stopReading()
        isReading = false
        updateNowPlayingInfo()
        
        // 停止操作相对简单，可以立即重置切换状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.isSwitchingPlayState = false
        }
    }

    /// 重新开始朗读，添加轻微延迟确保合成器重置
    private func restartReading() {
        if isReading && !isSwitchingPlayState {
            print("重新开始朗读")
            stopReading()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.readCurrentPage()
            }
        }
    }

    // MARK: - 搜索
    
    /// 搜索内容中的指定关键词
    func searchContent(_ query: String) {
        guard !query.isEmpty else {
            searchResults = []
            // 显示默认摘要
            pageSummaries = searchService.pageSummaries(pages: pages)
            return
        }
        searchResults = searchService.search(query: query, in: pages)
    }

    /// 跳转到搜索结果页面
    func jumpToSearchResult(pageIndex: Int) {
        guard pageIndex >= 0 && pageIndex < pages.count else { return }
        stopReading()
        currentPageIndex = pageIndex
        showingSearchView = false
    }

    // MARK: - WiFi传输
    
    /// 切换WiFi传输服务状态（开启/关闭）
    func toggleWiFiTransfer() {
        if isServerRunning {
            wiFiTransferService.stopServer()
        } else {
            let _ = wiFiTransferService.startServer()
        }
    }

    // MARK: - Now Playing信息
    
    /// 更新控制中心的Now Playing信息
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

    // MARK: - URL处理
    
    /// 处理通过onOpenURL传入的URL，用于文件导入或自定义URL Scheme
    func handleImportedURL(_ url: URL) {
        print("[ContentViewModel] 处理导入的URL: \(url.absoluteString)")

        // 处理自定义Scheme (textreader://)
        if url.scheme == "textreader" {
            handleCustomSchemeURL(url)
            return
        }
        
        // 基本检查：确保是文件URL (file:// scheme)
        // 系统分享的临时文件通常也是file URL
        guard url.isFileURL else {
            print("[ContentViewModel][警告] 接收的URL不是文件URL。Scheme: \(url.scheme ?? "nil")。忽略。")
            // 这里可以根据需要添加对其他scheme的处理逻辑
            return
        }

        // 复用现有的导入逻辑
        // importBookFromURL内部已经处理了安全作用域、文件读取（包括编码检测）和书籍保存
        print("[ContentViewModel] URL是文件URL，尝试通过importBookFromURL导入...")
        importBookFromURL(url)
    }
    
    /// 处理自定义URL Scheme，如textreader://import?text=xxx
    private func handleCustomSchemeURL(_ url: URL) {
        print("[ContentViewModel] 处理自定义scheme URL: \(url.absoluteString)")
        
        // 检查主机部分 - 例如textreader://import表示要导入文本
        guard let host = url.host, host == "import" else {
            print("[ContentViewModel][警告] 不支持的URL主机: \(url.host ?? "nil")")
            return
        }
        
        // 提取查询参数
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let queryItems = components.queryItems else {
            print("[ContentViewModel][警告] URL中没有查询项")
            return
        }
        
        // 查找text参数
        if let textItem = queryItems.first(where: { $0.name == "text" }),
           let encodedText = textItem.value,
           let decodedText = encodedText.removingPercentEncoding,
           !decodedText.isEmpty {
            
            print("[ContentViewModel] 找到text参数，长度: \(decodedText.count)")
            
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
                print("[ContentViewModel] 已将共享文本保存到临时文件: \(tempFile.path)")
                
                // 使用已有的导入逻辑
                importBookFromURL(tempFile, suggestedTitle: title)
            } catch {
                print("[ContentViewModel][错误] 保存共享文本到临时文件失败: \(error.localizedDescription)")
            }
        } else {
            print("[ContentViewModel][警告] URL中未找到有效的text参数")
        }
    }

    // MARK: - BigBang功能
    
    /// 触发BigBang功能，对当前页面文本进行分词
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

    /// 处理大爆炸视图中的词语点击
    func processTokenTap(tappedTokenID: UUID) {
        if let firstTapped = firstTapInSequence {
            // 这不是序列的第一次点击
            if tappedTokenID == firstTapped {
                // 点击了序列的第一个词 -> 取消所有选中
                selectedTokenIDs.removeAll()
                firstTapInSequence = nil
            } else {
                // 点击了其他词 -> 清除当前选择，然后选择从 firstTapped 到 tappedTokenID
                selectedTokenIDs.removeAll()
                selectTokenRange(from: firstTapped, to: tappedTokenID)
                // firstTapInSequence 保持不变
            }
        } else {
            // 这是序列的第一次点击
            selectedTokenIDs.removeAll()
            selectedTokenIDs.insert(tappedTokenID)
            firstTapInSequence = tappedTokenID
        }
    }

    /// 辅助方法：选择指定范围内的词块
    private func selectTokenRange(from startID: UUID, to endID: UUID) {
        guard let sIndex = tokens.firstIndex(where: { $0.id == startID }),
              let eIndex = tokens.firstIndex(where: { $0.id == endID }) else {
            // 如果有一个ID无效，尝试选中单个有效的ID
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

    /// 清空所有选中的词语
    func clearSelectedTokens() {
        selectedTokenIDs.removeAll()
        firstTapInSequence = nil
    }

    /// 复制选中的词语
    func copySelected() {
        let text = tokens.filter { selectedTokenIDs.contains($0.id) }
                         .map(\.value).joined()
        UIPasteboard.general.string = text
        showingBigBang = false
    }

    // MARK: - 模板管理

    /// 添加新模板
    func addTemplate(_ t: PromptTemplate) {
        templates.append(t)
        templateManager.save(templates)
    }

    /// 更新已有模板
    func updateTemplate(_ t: PromptTemplate) {
        guard let idx = templates.firstIndex(where: { $0.id == t.id }) else { return }
        templates[idx] = t
        templateManager.save(templates)
    }

    /// 删除模板
    func deleteTemplate(_ t: PromptTemplate) {
        templates.removeAll { $0.id == t.id }
        templateManager.save(templates)
    }
    
    /// 生成提示词并复制到剪贴板
    func buildPrompt(using template: PromptTemplate) {
        let selection = tokens.filter { selectedTokenIDs.contains($0.id) }.map(\.value).joined()
        let page = pages.indices.contains(currentPageIndex) ? pages[currentPageIndex] : ""
        var result = template.content
        result = result.replacingOccurrences(of: "{selection}", with: selection)
        result = result.replacingOccurrences(of: "{page}", with: page)
        result = result.replacingOccurrences(of: "{book}", with: currentBookTitle)
        UIPasteboard.general.string = result
        
        // 构建Perplexity AI搜索URL
        if let encodedQuery = result.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "https://www.perplexity.ai/search/new?q=\(encodedQuery)") {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    // MARK: - 清理
    
    /// 在视图模型被释放时执行清理
    deinit {
        stopReading()
        wiFiTransferService.stopServer()
        cancellables.forEach { $0.cancel() }
    }
} 