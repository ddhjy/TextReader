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
    @Published private(set) var contentScrollRevision: Int = 0
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
    @Published var appearanceMode: AppearanceMode = .system
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
    @Published var sharedImportBannerMessage: String?
    
    @Published var wifiUploadProgress: Double?
    @Published var wifiUploadFilename: String?
    @Published var wifiUploadError: String?
    
    // MARK: - 定时播放（Sleep Timer）
    /// 定时播放可选时长（分钟）。
    static let sleepTimerOptions: [Int] = [5, 15, 25]
    /// 是否处于定时播放中。
    @Published var sleepTimerActive: Bool = false
    /// 当前定时播放总时长（秒）。
    @Published var sleepTimerDuration: TimeInterval = 0
    /// 当前定时播放剩余时长（秒）。
    @Published var sleepTimerRemaining: TimeInterval = 0
    private var sleepTimerEndDate: Date?
    private var sleepTimerTicker: Timer?
    /// 定时已到点，但仍需等待当前朗读段落自然结束后再停止。
    private var sleepTimerStopPendingAfterCurrentUtterance = false
    
    private var isAutoAdvancing = false
    /// 自动续页保护的兜底解除任务：正常情况由 didStart/onSpeechError 解除，
    /// 仅在语音引擎既不回调开始也不回调失败（引擎卡死）时按超时强制解除，
    /// 避免对账定时器被 isAutoAdvancing 永久挡住。
    private var autoAdvanceFallbackWorkItem: DispatchWorkItem?
    /// 对账定时器连续检测到「UI 在播但引擎无声」的次数。
    private var syncMismatchTickCount = 0
    private var activeUtteranceId: UUID?
    private var activeUtterancePageIndex: Int?
    private var pendingResumeAfterManualTurn: Bool = false
    private var manualTurnResumeWorkItem: DispatchWorkItem?
    private var sharedImportBannerDismissWorkItem: DispatchWorkItem?
    private var isConsumingSharedImports = false
    /// 用于告知视图层：本次 currentPageIndex 的变化属于"非阅读语境"（如切换书籍、
    /// 加载/恢复内容、删除、搜索跳转等），不应触发翻页动画。
    /// 由视图层在 onChange 中调用 `consumePendingSilentPageScroll()` 消费一次。
    private var pendingSilentPageScrollFlag = false

    /// App 是否处于后台。后台朗读自动续页 / 远程控制翻页期间，屏幕并未实际渲染滚动，
    /// 若仍按非静默推进页码，回到前台时 SwiftUI 会把这段累计的翻页以一段"补偿滚动动画"
    /// 集中播放出来，与用户预期（打开即停在当前朗读页）不符。故后台期间的翻页一律静默。
    private var isAppInBackground = false

    let libraryManager: LibraryManager
    private let textPaginator: TextPaginator
    private let speechManager: SpeechManager
    private let searchService: SearchService
    private let wiFiTransferService: WiFiTransferService
    private let audioSessionManager: AudioSessionManager
    private let settingsManager: SettingsManager
    private let sharedImportStore: SharedImportStore
    private let tokenizer = Tokenizer()
    private let templateManager: TemplateManager

    private var cancellables = Set<AnyCancellable>()
    
    var currentAccentColor: Color {
        let theme = AccentColorTheme.presets.first { $0.id == accentColorThemeId } ?? AccentColorTheme.presets[0]
        return theme.dynamicColor
    }

    /// 当前 `pages` 是否已是「最终分页结果」。
    ///
    /// `TextPaginator` 产出的每一页都是非空文本；而快速启动 / 切换书籍时为了即时占位，
    /// 会先放入「仅当前页有内容、其余为空串」的预览数组（见 `loadInitialData` 与
    /// `applyCachedPagePreview`）。视图层据此在占位预览阶段保持留白，待最终分页就位后
    /// 再一次性居中定位并淡入，从而消除首屏「先错位、后跳正 + 预览→完整重排」的抖动。
    var isContentSettled: Bool {
        !pages.isEmpty && !pages.contains(where: { $0.isEmpty })
    }

    init(libraryManager: LibraryManager = LibraryManager(),
         textPaginator: TextPaginator = TextPaginator(),
         speechManager: SpeechManager = SpeechManager(),
         searchService: SearchService = SearchService(),
         wiFiTransferService: WiFiTransferService = WiFiTransferService(),
         audioSessionManager: AudioSessionManager = AudioSessionManager(),
         settingsManager: SettingsManager = SettingsManager(),
         sharedImportStore: SharedImportStore = SharedImportStore(),
         templateManager: TemplateManager = TemplateManager()) {

        self.libraryManager = libraryManager
        self.textPaginator = textPaginator
        self.speechManager = speechManager
        self.searchService = searchService
        self.wiFiTransferService = wiFiTransferService
        self.audioSessionManager = audioSessionManager
        self.settingsManager = settingsManager
        self.sharedImportStore = sharedImportStore
        self.templateManager = templateManager
        self.appearanceMode = settingsManager.getAppearanceMode()

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
        setupAppLifecycleObservers()
        
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
                // 防御性 clamp：UserDefaults 中的页码与总页数理论上一致，
                // 但一旦因历史写入顺序等原因不一致，直接下标会崩溃。
                let safeIndex = min(max(0, cachedPageIndex), cachedTotalPages - 1)
                self.pages = Array(repeating: "", count: cachedTotalPages)
                self.pages[safeIndex] = cachedContent
                self.setCurrentPageIndex(safeIndex, silent: true)
            } else {
                self.pages = [cachedContent]
                self.setCurrentPageIndex(0, silent: true)
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
        self.appearanceMode = settingsManager.getAppearanceMode()
        
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
    
    private func loadFullBookContent(_ book: Book) {
        let savedPageIndex = settingsManager.getLastPageIndex()
        let savedTotalPages = settingsManager.getLastTotalPages()
        
        libraryManager.loadBookContent(book: book) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let content):
                DispatchQueue.global(qos: .userInitiated).async {
                    let paginatedPages = self.textPaginator.paginate(text: content)
                    let summaries = self.searchService.pageSummaries(pages: paginatedPages)
                    
                    DispatchQueue.main.async {
                        guard self.currentBookId == book.id else { return }
                        self.applyLoadedPages(
                            for: book,
                            pages: paginatedPages,
                            targetPageIndex: savedPageIndex,
                            previousTotalPages: savedTotalPages,
                            summaries: summaries
                        )
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
                    self.libraryManager.saveBookProgress(bookId: bookId, pageIndex: index, totalPages: self.pages.count)
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
            
        $appearanceMode
            .dropFirst()
            .sink { [weak self] mode in self?.settingsManager.saveAppearanceMode(mode) }
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
                    self.syncMismatchTickCount = 0
                    return
                }
                
                guard self.isReading != speechManagerActive else {
                    self.syncMismatchTickCount = 0
                    return
                }
                
                print("检测到状态不一致: UI=\(self.isReading), Speech=\(speechManagerActive)")
                
                if !self.isReading && speechManagerActive {
                    print("强制停止播放")
                    self.syncMismatchTickCount = 0
                    self.speechManager.stopReading()
                } else if self.isReading && !speechManagerActive {
                    // 页与页衔接时 didStart 可能迟到（后台 CPU 受限、合成首块音频慢），
                    // 单次采样不足以判定播放已停止；连续两次（约 4 秒）不一致才纠偏，
                    // 避免误杀正常的自动续页。
                    self.syncMismatchTickCount += 1
                    guard self.syncMismatchTickCount >= 2 else { return }
                    
                    print("状态同步：连续确认无声，更新为已停止")
                    self.syncMismatchTickCount = 0
                    self.isReading = false
                    // 不在纠偏路径释放音频会话：若属误判，迟到的 didStart 仍可把
                    // isReading 拉回并继续播放；释放会话会直接掐断正在准备发声的合成器。
                    self.updateNowPlayingInfo(deactivateSessionWhenStopped: false)
                }
            }
            .store(in: &cancellables)
    }
    
    /// 开始自动续页保护：期间对账定时器不做状态纠偏。
    /// 由 didStart/onSpeechError 解除；若两者都未到来（引擎卡死），10 秒后兜底解除。
    private func beginAutoAdvanceProtection() {
        isAutoAdvancing = true
        autoAdvanceFallbackWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.autoAdvanceFallbackWorkItem = nil
            self.isAutoAdvancing = false
        }
        autoAdvanceFallbackWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0, execute: work)
    }
    
    private func endAutoAdvanceProtection() {
        autoAdvanceFallbackWorkItem?.cancel()
        autoAdvanceFallbackWorkItem = nil
        isAutoAdvancing = false
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

            if self.sleepTimerStopPendingAfterCurrentUtterance {
                self.completeSleepTimerStopAfterCurrentUtterance()
                return
            }
            
            if !self.pages.isEmpty && self.currentPageIndex < self.pages.count - 1 {
                // 保护持续到下一页 didStart 真正回来（见 onSpeechStart/onSpeechError），
                // 固定时长的保护窗在后台合成变慢时不够用，会被对账定时器误杀。
                self.beginAutoAdvanceProtection()
                // 后台续页静默推进：避免回到前台时补播一段"翻好几页"的滚动动画。
                self.setCurrentPageIndex(self.currentPageIndex + 1, silent: self.isAppInBackground)
                self.readCurrentPage()
            } else {
                if self.sleepTimerActive {
                    self.cancelSleepTimer()
                }
                self.activeUtteranceId = nil
                self.activeUtterancePageIndex = nil
                self.isReading = false
                self.endAutoAdvanceProtection()
                self.updateNowPlayingInfo()
            }
        }
        
        speechManager.onSpeechStart = { [weak self] utteranceId in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard utteranceId == self.activeUtteranceId else { return }
                self.endAutoAdvanceProtection()
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
                self.endAutoAdvanceProtection()
                if self.isReading {
                    self.isReading = false
                    self.updateNowPlayingInfo()
                    print("语音合成错误，播放已停止")
                }
            }
        }
    }

    /// 监听前后台切换，维护 `isAppInBackground`。
    /// 用 willEnterForeground 而非 didBecomeActive 解除后台标记：前者更早（视图恢复渲染前），
    /// 能确保回到前台后的第一次翻页恢复正常动画，同时不影响后台期间已设好的静默标志。
    private func setupAppLifecycleObservers() {
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in self?.isAppInBackground = true }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in self?.isAppInBackground = false }
            .store(in: &cancellables)
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
                
                let progressText = Self.formatBookProgressDisplay(progress)
                let lastAccessedText = formatLastAccessedTime(progress.lastAccessed)
                bookDisplayCache[book.id] = (progressText, lastAccessedText)
            }
        }
    }

    static func formatBookProgressDisplay(_ progress: BookProgress) -> String? {
        guard progress.totalPages > 0 else { return nil }

        let currentPage = min(max(progress.currentPageIndex + 1, 1), progress.totalPages)
        let rawPercentage = Double(currentPage) / Double(progress.totalPages) * 100
        var percentage = max(1, Int(rawPercentage.rounded()))

        if percentage >= 100 && currentPage < progress.totalPages {
            percentage = 99
        }

        return "\(min(percentage, 100))%"
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
    
    func loadBook(_ book: Book,
                  waitForFullContentBeforeCompletion: Bool = false,
                  completion: (() -> Void)? = nil) {
        stopReading()
        isContentLoaded = false
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
            if !waitForFullContentBeforeCompletion {
                self.applyCachedPagePreview(
                    for: book,
                    content: lastPageContent,
                    targetPageIndex: savedPageIndex,
                    knownTotalPages: savedProgress?.totalPages ?? 0
                )
                completion?()
            }
            
            libraryManager.loadBookContent(book: book) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let content):
                    DispatchQueue.global(qos: .userInitiated).async {
                        let paginatedPages = self.textPaginator.paginate(text: content)
                        let summaries = self.searchService.pageSummaries(pages: paginatedPages)

                        DispatchQueue.main.async {
                            guard self.currentBookId == book.id else { return }
                            self.applyLoadedPages(
                                for: book,
                                pages: paginatedPages,
                                targetPageIndex: savedPageIndex,
                                previousTotalPages: savedProgress?.totalPages ?? 0,
                                summaries: summaries
                            )
                            print("[ContentViewModel] 完整内容加载完成，共 \(paginatedPages.count) 页")
                            if waitForFullContentBeforeCompletion {
                                completion?()
                            }
                        }
                    }
                case .failure(let error):
                    DispatchQueue.main.async {
                        guard self.currentBookId == book.id else { return }
                        print("后台加载书籍内容失败: \(error)")
                        if waitForFullContentBeforeCompletion {
                            self.applyCachedPagePreview(
                                for: book,
                                content: lastPageContent,
                                targetPageIndex: savedPageIndex,
                                knownTotalPages: savedProgress?.totalPages ?? 0
                            )
                            completion?()
                        }
                    }
                }
            }
            return
        }

        print("[ContentViewModel] 无缓存，从文件加载书籍内容")
        libraryManager.loadBookContent(book: book) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let content):
                DispatchQueue.global(qos: .userInitiated).async {
                    let paginatedPages = self.textPaginator.paginate(text: content)
                    let summaries = self.searchService.pageSummaries(pages: paginatedPages)

                    DispatchQueue.main.async {
                        guard self.currentBookId == book.id else { return }
                        self.applyLoadedPages(
                            for: book,
                            pages: paginatedPages,
                            targetPageIndex: savedPageIndex,
                            previousTotalPages: savedProgress?.totalPages ?? 0,
                            summaries: summaries
                        )
                        completion?()
                    }
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    guard self.currentBookId == book.id else { return }
                    print("加载书籍内容失败: \(error)")
                    self.setCurrentPageIndex(0, silent: true)
                    self.pages = ["无法加载此书内容"]
                    self.pageSummaries = []
                    self.searchResults = []
                    self.isContentLoaded = true
                    self.requestContentScrollRefresh()
                    self.updateNowPlayingInfo()
                    completion?()
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
                        self.setCurrentPageIndex(0, silent: true)
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
                    self.setCurrentPageIndex(0, silent: true)
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

    func consumePendingSharedImports(completion: (([Book]) -> Void)? = nil) {
        guard !isConsumingSharedImports else {
            completion?([])
            return
        }

        isConsumingSharedImports = true

        DispatchQueue.global(qos: .userInitiated).async {
            var importedBooks: [Book] = []

            do {
                _ = try self.sharedImportStore.consumePendingImports { item, text in
                    do {
                        let importedBook = try self.libraryManager.importSharedText(
                            text,
                            preferredTitle: item.title,
                            createdAt: item.createdAt
                        )
                        importedBooks.append(importedBook)
                        return true
                    } catch {
                        print("[ContentViewModel] 共享导入写入书库失败: \(error)")
                        return false
                    }
                }
            } catch {
                print("[ContentViewModel] 消费共享导入失败: \(error)")
            }

            DispatchQueue.main.async {
                self.isConsumingSharedImports = false

                guard !importedBooks.isEmpty else {
                    completion?([])
                    return
                }

                self.books = self.libraryManager.loadBooks()
                self.sortBooks()

                if let latestBook = importedBooks.last {
                    self.loadBook(latestBook)
                    self.showSharedImportBanner("已导入《\(latestBook.title)》")
                }

                completion?(importedBooks)
            }
        }
    }

    func getBookProgressDisplay(book: Book) -> String? {
        if let cached = bookDisplayCache[book.id] {
            return cached.progress
        }
        if let progress = libraryManager.getBookProgress(bookId: book.id) {
            return Self.formatBookProgressDisplay(progress)
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

    private func showSharedImportBanner(_ message: String) {
        sharedImportBannerDismissWorkItem?.cancel()
        sharedImportBannerMessage = message

        let dismissWorkItem = DispatchWorkItem { [weak self] in
            self?.sharedImportBannerMessage = nil
            self?.sharedImportBannerDismissWorkItem = nil
        }

        sharedImportBannerDismissWorkItem = dismissWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: dismissWorkItem)
    }

    private func clampedPageIndex(_ index: Int, pageCount: Int) -> Int {
        min(max(0, index), max(0, pageCount - 1))
    }

    /// 当分页粒度变化（例如升级了分页算法 / 每页字符数）导致总页数改变时，
    /// 按「阅读百分比」把旧页码映射到新页码，保持读者停留在相近的内容位置，
    /// 避免直接沿用旧页码而跳到完全不同的地方（甚至被 clamp 到书末）。
    ///
    /// 采用页中点比例 `(oldIndex + 0.5) / oldTotal`，保证：
    /// - 旧总页数与新总页数相同时为恒等映射（不影响正常的重复加载）；
    /// - 首页映射到首页、末页映射到末页。
    static func remapPageIndex(_ oldIndex: Int, oldTotal: Int, newTotal: Int) -> Int {
        guard newTotal > 0 else { return 0 }
        guard oldTotal > 1, oldIndex > 0 else {
            return min(max(0, oldIndex), newTotal - 1)
        }
        let fraction = (Double(oldIndex) + 0.5) / Double(oldTotal)
        let mapped = Int((fraction * Double(newTotal)).rounded(.down))
        return min(max(0, mapped), newTotal - 1)
    }

    private func requestContentScrollRefresh() {
        contentScrollRevision &+= 1
    }

    private func makeCachedPagePreview(content: String, targetPageIndex: Int, knownTotalPages: Int) -> [String] {
        let pageCount = max(1, knownTotalPages, targetPageIndex + 1)
        let targetIndex = clampedPageIndex(targetPageIndex, pageCount: pageCount)
        var previewPages = Array(repeating: "", count: pageCount)
        previewPages[targetIndex] = content
        return previewPages
    }

    private func applyCachedPagePreview(for book: Book,
                                        content: String,
                                        targetPageIndex: Int,
                                        knownTotalPages: Int) {
        let previewPages = makeCachedPagePreview(
            content: content,
            targetPageIndex: targetPageIndex,
            knownTotalPages: knownTotalPages
        )
        let targetIndex = clampedPageIndex(targetPageIndex, pageCount: previewPages.count)

        setCurrentPageIndex(targetIndex, silent: true)
        pages = previewPages
        pageSummaries = []
        searchResults = []
        isContentLoaded = true
        saveCurrentPageToCache()
        requestContentScrollRefresh()
        updateNowPlayingInfo()
        print("[ContentViewModel] 使用缓存单页预览: \(book.title)，页 \(targetIndex + 1)/\(previewPages.count)")
    }

    private func applyLoadedPages(for book: Book,
                                  pages loadedPages: [String],
                                  targetPageIndex: Int,
                                  previousTotalPages: Int = 0,
                                  summaries: [(Int, String)]) {
        let remappedIndex = Self.remapPageIndex(
            targetPageIndex,
            oldTotal: previousTotalPages,
            newTotal: loadedPages.count
        )
        let targetIndex = clampedPageIndex(remappedIndex, pageCount: loadedPages.count)

        setCurrentPageIndex(targetIndex, silent: true)
        pages = loadedPages
        pageSummaries = summaries
        searchResults = []
        saveCurrentPageToCache()
        libraryManager.saveBookProgress(
            bookId: book.id,
            pageIndex: targetIndex,
            totalPages: loadedPages.count
        )
        isContentLoaded = true
        requestContentScrollRefresh()
        updateNowPlayingInfo()
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
                    self.setCurrentPageIndex(0, silent: true)
                    self.pages = self.textPaginator.paginate(text: newContent)
                    self.pageSummaries = self.searchService.pageSummaries(pages: self.pages)
                    self.searchResults = []
                    self.saveCurrentPageToCache()
                    self.requestContentScrollRefresh()
                    
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

    /// 视图层消费一次「静默翻页」标志。
    /// - Returns: `true` 表示本次 `currentPageIndex` 变化不应使用翻页动画。
    func consumePendingSilentPageScroll() -> Bool {
        let value = pendingSilentPageScrollFlag
        pendingSilentPageScrollFlag = false
        return value
    }

    /// 设置当前页索引。
    /// - Parameters:
    ///   - index: 新的页码索引。
    ///   - silent: 是否抑制视图层翻页动画。默认 `false`：适用于用户手动翻页、滑块跳页、
    ///     以及朗读自动续页等"用户正在关注阅读区"的场景。
    ///     传 `true` 用于切换书籍、加载/恢复缓存、删除、内容刷新、搜索跳转等
    ///     "用户视线尚未聚焦阅读区"的场景，避免视觉打扰。
    private func setCurrentPageIndex(_ index: Int, silent: Bool = false) {
        if silent && index != currentPageIndex {
            pendingSilentPageScrollFlag = true
        }
        currentPageIndex = index
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

        // 后台（如锁屏 / 控制中心远程翻页）期间静默推进，避免回前台时补播滚动动画。
        setCurrentPageIndex(index, silent: isAppInBackground)

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
        endAutoAdvanceProtection()
        activeUtteranceId = nil
        activeUtterancePageIndex = nil
        speechManager.stopReading()
        isReading = false
        updateNowPlayingInfo()
    }

    func prepareForDataProfileSwitch() {
        stopReading()
        cancelSleepTimer()
        wiFiTransferService.stopServer()
        sharedImportBannerDismissWorkItem?.cancel()
        sharedImportBannerDismissWorkItem = nil
        sharedImportBannerMessage = nil
        showingBookList = false
        showingSearchView = false
        showingDocumentPicker = false
        showingWiFiTransferView = false
        showingPasteImport = false
        showingBigBang = false
        showingTemplatePicker = false
        showingBookEdit = false
        showingSettings = false
        generatedPrompt = nil
        bookToEdit = nil
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
        // 搜索面板会立刻关闭，跨度通常较大；用户视线刚从搜索弹层切回主界面，
        // 这里直接静默定位，避免一段长距离的滚动动画造成视觉打扰。
        setCurrentPageIndex(pageIndex, silent: true)
        showingSearchView = false
    }
    
    private func saveCurrentPageToCache() {
        guard !pages.isEmpty,
              currentPageIndex >= 0,
              currentPageIndex < pages.count else { return }
        let currentContent = pages[currentPageIndex]
        if let bookId = currentBookId {
            libraryManager.saveLastPageContent(bookId: bookId, content: currentContent)
        }
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

    private func updateNowPlayingInfo(deactivateSessionWhenStopped: Bool = true) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.audioSessionManager.updateNowPlayingInfo(
                title: self.currentBookTitle,
                isPlaying: self.isReading,
                currentPage: self.currentPageIndex + 1,
                totalPages: self.pages.count,
                deactivateSessionWhenStopped: deactivateSessionWhenStopped
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

    // MARK: - 定时播放控制
    
    /// 开启定时播放。到点后会等当前朗读段落自然结束，再停止朗读。
    /// - 若当前未在朗读则会自动开始朗读当前页。
    /// - 若已存在计时则重置为新值。
    func startSleepTimer(minutes: Int) {
        let clamped = max(1, minutes)
        let duration = TimeInterval(clamped * 60)
        sleepTimerStopPendingAfterCurrentUtterance = false
        sleepTimerDuration = duration
        sleepTimerRemaining = duration
        sleepTimerEndDate = Date().addingTimeInterval(duration)
        sleepTimerActive = true
        
        if !isReading {
            readCurrentPage()
        }
        
        sleepTimerTicker?.invalidate()
        // 0.5s 节奏刷新即可，UI 仅按分钟显示，避免后台时漏跳秒。
        let ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tickSleepTimer()
        }
        RunLoop.main.add(ticker, forMode: .common)
        sleepTimerTicker = ticker
    }
    
    /// 取消定时（不停止朗读，仅清除计时）。当前未使用，保留备用。
    func cancelSleepTimer() {
        sleepTimerTicker?.invalidate()
        sleepTimerTicker = nil
        sleepTimerStopPendingAfterCurrentUtterance = false
        sleepTimerActive = false
        sleepTimerEndDate = nil
        sleepTimerRemaining = 0
        sleepTimerDuration = 0
    }
    
    /// 用户点击「确认结束」或自然到点时调用：清除定时并停止朗读。
    func endSleepTimerAndStop() {
        let wasActive = sleepTimerActive
        sleepTimerStopPendingAfterCurrentUtterance = false
        cancelSleepTimer()
        if wasActive || isReading {
            stopReading()
        }
    }
    
    private func tickSleepTimer() {
        guard sleepTimerActive, let endDate = sleepTimerEndDate else { return }
        let remaining = endDate.timeIntervalSinceNow
        if remaining <= 0 {
            handleSleepTimerExpired()
        } else {
            sleepTimerRemaining = remaining
        }
    }

    func handleSleepTimerExpired() {
        sleepTimerRemaining = 0
        sleepTimerEndDate = nil
        sleepTimerTicker?.invalidate()
        sleepTimerTicker = nil

        guard isReading, activeUtteranceId != nil else {
            endSleepTimerAndStop()
            return
        }

        sleepTimerStopPendingAfterCurrentUtterance = true
    }

    private func completeSleepTimerStopAfterCurrentUtterance() {
        cancelSleepTimer()
        activeUtteranceId = nil
        activeUtterancePageIndex = nil
        endAutoAdvanceProtection()
        isReading = false
        updateNowPlayingInfo()
    }
    
    /// 0...1 的进度，表示已经播放过的比例。
    var sleepTimerProgress: Double {
        guard sleepTimerDuration > 0 else { return 0 }
        let elapsed = sleepTimerDuration - sleepTimerRemaining
        return min(1.0, max(0.0, elapsed / sleepTimerDuration))
    }
    
    /// 剩余分钟（按分钟向上取整，剩余 1s~59s 仍显示 1 分钟）。
    var sleepTimerRemainingMinutes: Int {
        guard sleepTimerActive else { return 0 }
        return max(0, Int(ceil(sleepTimerRemaining / 60.0)))
    }
    
    /// 点击播放按钮的统一入口：
    /// - 若处于定时播放中则直接结束并恢复常态；
    /// - 否则切换播放状态。
    func handlePlayButtonTap() {
        if sleepTimerActive {
            endSleepTimerAndStop()
        } else {
            toggleReading()
        }
    }
    
    deinit {
        stopReading()
        sleepTimerTicker?.invalidate()
        sleepTimerTicker = nil
        wiFiTransferService.stopServer()
        cancellables.forEach { $0.cancel() }
    }
} 
