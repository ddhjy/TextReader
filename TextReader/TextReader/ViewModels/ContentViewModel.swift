import SwiftUI
import Combine
import AVFoundation
import UIKit

class ContentViewModel: ObservableObject {
    static let appDisplayName = "随心读"

    /// 一本书是从哪条路进来的，决定导入后要不要立刻打开它、要不要弹提示。
    enum ImportSource {
        /// App 内「从文件导入」。
        case filePicker
        /// App 内「粘贴文本」。
        case paste
        /// Wi‑Fi 传书：结果显示在传书页面的列表里，不再另外弹提示。
        case wifi
        /// 从别的 App 打开 / 分享进来：用户就是冲着这份内容来的，直接打开。
        case external
    }

    struct WiFiUploadProgress: Equatable {
        let fileName: String?
        /// 0...1；电脑没有告知文件大小时为 nil。
        let fraction: Double?
    }

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
    @Published var pages: [String] = [] {
        didSet {
            if pages != oldValue {
                pagesGeneration &+= 1
            }
        }
    }
    /// 正文整批换过几次（换书、占位预览换成最终分页、重新分页、改正文）。
    /// 阅读区据此给每一批正文换一批全新的行，上一批量到的位置不会混进新的一批里。
    private(set) var pagesGeneration: Int = 0
    @Published private(set) var contentScrollRevision: Int = 0
    @Published var currentPageIndex: Int = 0
    @Published var currentBookTitle: String = ContentViewModel.appDisplayName
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
    @Published var showingBookList = false
    @Published var showingSearchView = false
    @Published var bookProgressText: String?
    @Published var appearanceMode: AppearanceMode = .system
    @Published var accentColorThemeId: String = "blue"
    @Published var showingBigBang = false
    @Published var tokens: [Token] = []
    @Published var selectedTokenIDs: Set<UUID> = []
    /// 选词时第一个点中的词（起点）。之后点别的词，选中的是它和那个词之间的全部。
    @Published private(set) var selectionAnchorTokenID: UUID?
    @Published var templates: [PromptTemplate] = []
    @Published var showingTemplateLibrary = false
    @Published var showingBookEdit = false
    @Published var showingSettings = false
    @Published var bookToEdit: Book?

    /// 当前显示在界面顶部的一条提示（成功 / 说明 / 失败）。
    @Published private(set) var notice: AppNotice?
    private var noticeDismissWorkItem: DispatchWorkItem?

    /// 用滑杆或搜索跳走之前所在的页。非 nil 时界面显示「回到第 N 页」。
    @Published private(set) var returnPageIndex: Int?
    private var returnOfferExpiryWorkItem: DispatchWorkItem?
    /// 正在拖动进度滑杆时，拖动开始前所在的页。
    private var progressScrubOriginPageIndex: Int?
    private static let returnOfferLifetime: TimeInterval = 30

    @Published private(set) var wifiStatus: WiFiTransferService.Status = .stopped
    @Published private(set) var wifiTransferRecords: [WiFiTransferService.TransferRecord] = []
    @Published private(set) var wifiUpload: WiFiUploadProgress?

    private var voicePreviewSynthesizer: AVSpeechSynthesizer?
    static let voicePreviewText = "这是当前语音的朗读效果。"

    /// 当前字号下每页放多少字。只在主线程读写。
    private(set) var pageLayout: ReaderTypography.PageLayout = .standard
    /// 字号变化触发的重新分页可能连续发生，只认最后一次。
    private var repaginationToken: UUID?
    
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
    
    var currentAccentTheme: AccentColorTheme {
        AccentColorTheme.presets.first { $0.id == accentColorThemeId } ?? AccentColorTheme.presets[0]
    }

    var currentAccentColor: Color {
        currentAccentTheme.dynamicColor
    }

    /// 压在强调色底上的文字 / 图标颜色。
    var currentOnAccentColor: Color {
        currentAccentTheme.onAccentDynamicColor
    }

    /// 书架里还没有用户自己的书（只有内置的使用说明）。这时首屏要把「导入」摆在明处。
    var hasOnlyBuiltInBooks: Bool {
        !books.contains { !$0.isBuiltIn }
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
        self.pageLayout = ReaderTypography.pageLayout(forFontSize: ReaderTypography.currentFontSize())

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
            self.currentBookTitle = settingsManager.getLastBookTitle() ?? Self.appDisplayName
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
                self.paginateInBackground(content) { paginatedPages, summaries in
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
            case .failure(let error):
                DispatchQueue.main.async {
                    print("后台加载书籍内容失败: \(error)")
                    guard self.currentBookId == book.id else { return }
                    self.isContentLoaded = true
                    self.showNotice("《\(Self.shortTitle(book.title))》的内容没能读出来，请稍后再试", kind: .error)
                }
            }
        }
    }

    // MARK: - 分页

    private func paginate(_ text: String, layout: ReaderTypography.PageLayout) -> [String] {
        let pages = textPaginator.paginate(text: text, maxPageSize: layout.characterLimit)
        guard let budget = layout.lineBudget else { return pages }
        return ReaderTypography.fit(pages, to: budget)
    }

    /// 在后台分页并生成页面速览，完成后回到主线程。
    /// 分页期间字号变了（每页字数随之变化）就按新字号重来，保证交给界面的总是当前字号下的结果。
    private func paginateInBackground(_ content: String,
                                      completion: @escaping (_ pages: [String], _ summaries: [(Int, String)]) -> Void) {
        let layout = pageLayout
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let pages = self.paginate(content, layout: layout)
            let summaries = self.searchService.pageSummaries(pages: pages)

            DispatchQueue.main.async {
                guard layout == self.pageLayout else {
                    self.paginateInBackground(content, completion: completion)
                    return
                }
                completion(pages, summaries)
            }
        }
    }

    /// 系统「文字大小」变化后调用：字号变了，每页能放的字数也要跟着变，否则一页会高出屏幕。
    private func handleContentSizeCategoryChange() {
        let newLayout = ReaderTypography.pageLayout(forFontSize: ReaderTypography.currentFontSize())
        guard newLayout != pageLayout else { return }
        pageLayout = newLayout
        repaginateCurrentBook()
    }

    private func repaginateCurrentBook() {
        // 正在加载中的书不用管：它的分页会在完成时发现字号变了并自动重来。
        guard isContentLoaded, isContentSettled,
              let bookId = currentBookId,
              let book = books.first(where: { $0.id == bookId }) else { return }

        let token = UUID()
        repaginationToken = token

        libraryManager.loadBookContent(book: book) { [weak self] result in
            guard let self = self,
                  self.currentBookId == bookId,
                  self.repaginationToken == token,
                  case .success(let content) = result else { return }

            self.paginateInBackground(content) { newPages, summaries in
                guard self.currentBookId == bookId,
                      self.repaginationToken == token,
                      self.isContentSettled else { return }
                self.repaginationToken = nil
                self.replaceCurrentPages(for: book, pages: newPages, summaries: summaries)
            }
        }
    }

    /// 同一本书换了一套分页（字号变化、正文被编辑）：按阅读百分比停在相近的位置，正在朗读就接着读。
    private func replaceCurrentPages(for book: Book, pages newPages: [String], summaries: [(Int, String)]) {
        let shouldResume = suspendSpeechKeepingReadingIntent()
        let oldIndex = currentPageIndex
        let oldTotal = pages.count

        clearReturnOffer()
        applyLoadedPages(
            for: book,
            pages: newPages,
            targetPageIndex: oldIndex,
            previousTotalPages: oldTotal,
            summaries: summaries
        )

        if shouldResume {
            scheduleResumeAfterManualTurn()
        }
    }

    private func setupBindings() {
        $currentPageIndex
            .dropFirst()
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] index in
                guard let self = self, let bookId = self.currentBookId else { return }
                // 内容没读出来时 pages 是空的，这时的「第 0 页」不是读者的进度，不能写回去盖掉原来的进度。
                let totalPages = self.pages.count
                guard totalPages > 0 else { return }
                self.saveCurrentPageToCache()
                self.updateNowPlayingInfo()
                DispatchQueue.global(qos: .utility).async {
                    self.libraryManager.saveBookProgress(bookId: bookId, pageIndex: index, totalPages: totalPages)
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
            guard let self = self else {
                return .rejected(reason: "暂时无法保存，请重试")
            }
            return self.handleReceivedFile(fileName: fileName, content: content)
        }

        // 用主队列而不是 RunLoop.main：后者在列表滚动期间不投递，传书页面上的状态会卡住不动。
        wiFiTransferService.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in self?.wifiStatus = status }
            .store(in: &cancellables)

        wiFiTransferService.$records
            .receive(on: DispatchQueue.main)
            .sink { [weak self] records in self?.wifiTransferRecords = records }
            .store(in: &cancellables)

        wiFiTransferService.$uploadState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self else { return }
                guard let state = state else {
                    self.wifiUpload = nil
                    return
                }

                var fraction: Double?
                if let total = state.totalBytes, total > 0 {
                    let received = max(0, state.receivedBytes)
                    fraction = min(1.0, max(0.0, Double(received) / Double(total)))
                }
                self.wifiUpload = WiFiUploadProgress(fileName: state.fileName, fraction: fraction)
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

        NotificationCenter.default.publisher(for: UIContentSizeCategory.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.handleContentSizeCategoryChange() }
            .store(in: &cancellables)
    }

    /// 书架顺序：最近打开过的在前；还没打开过的新书按导入时间算，所以刚导入的书会排在最上面。
    private func sortBooks() {
        refreshBookProgressCache()
        
        let sortedBooks = books.sorted { book1, book2 in
            let lastAccessed1 = bookProgressCache[book1.id]?.lastAccessed ?? book1.addedAt
            let lastAccessed2 = bookProgressCache[book2.id]?.lastAccessed ?? book2.addedAt

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
    
    // MARK: - 导入

    /// 把粘贴 / 手动输入的文字存成一本书。
    /// - Returns: 是否导入成功。失败时已经提示了原因，调用方应保留用户输入的内容。
    @discardableResult
    func importPastedText(_ rawText: String, title customTitle: String?) -> Bool {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            showNotice("还没有正文，先粘贴或输入一段文字", kind: .error)
            return false
        }

        let title = libraryManager.resolveSharedImportTitle(
            preferredTitle: customTitle,
            sourceFileName: nil,
            content: text
        )

        do {
            let imported = try libraryManager.importBook(
                fileName: "\(title).txt",
                content: text,
                suggestedTitle: title
            )
            finishImport(imported, source: .paste)
            return true
        } catch {
            print("粘贴导入失败: \(error)")
            showNotice(Self.importFailureMessage(for: error), kind: .error)
            return false
        }
    }

    /// 导入成功后的统一收尾：刷新书架、决定要不要打开新书、告诉用户结果。
    private func finishImport(_ imported: LibraryManager.ImportedBook, source: ImportSource) {
        let book = imported.book
        books = libraryManager.loadBooks()
        sortBooks()

        // Wi‑Fi 传书常常一次传好几本，不能每传完一本就把正在读的书换掉；
        // 只有当前没在读自己的书（没有书，或停在内置的使用说明上）时才直接打开。
        if source != .wifi || isCurrentBookReplaceable {
            loadBook(book)
        }

        guard source != .wifi else { return }
        showNotice(Self.importSuccessMessage(for: imported), kind: .success)
    }

    private var isCurrentBookReplaceable: Bool {
        guard let currentBookId = currentBookId,
              let currentBook = books.first(where: { $0.id == currentBookId }) else {
            return true
        }
        return currentBook.isBuiltIn
    }

    static func importSuccessMessage(for imported: LibraryManager.ImportedBook) -> String {
        let title = shortTitle(imported.book.title)
        if let conflictingTitle = imported.conflictingTitle {
            return "书架里已有《\(shortTitle(conflictingTitle))》，新导入的已另存为《\(title)》"
        }
        return "已导入《\(title)》"
    }

    static func importFailureMessage(for error: Error) -> String {
        if let libraryError = error as? LibraryManager.LibraryError {
            return "导入失败：\(libraryError.userMessage)"
        }
        return "导入失败，请重试"
    }

    /// 提示里用的书名：太长时截短，避免一条提示占掉半屏。
    static func shortTitle(_ title: String, maxLength: Int = 20) -> String {
        guard title.count > maxLength else { return title }
        return String(title.prefix(maxLength)) + "…"
    }
    
    func loadBook(_ book: Book,
                  waitForFullContentBeforeCompletion: Bool = false,
                  completion: (() -> Void)? = nil) {
        stopReading()
        clearReturnOffer()
        repaginationToken = nil
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
                    self.paginateInBackground(content) { paginatedPages, summaries in
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
                case .failure(let error):
                    DispatchQueue.main.async {
                        guard self.currentBookId == book.id else { return }
                        print("后台加载书籍内容失败: \(error)")
                        self.showNotice("《\(Self.shortTitle(book.title))》的内容没能读出来，请稍后再试", kind: .error)
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
                self.paginateInBackground(content) { paginatedPages, summaries in
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
            case .failure(let error):
                DispatchQueue.main.async {
                    guard self.currentBookId == book.id else { return }
                    print("加载书籍内容失败: \(error)")
                    // 读不出来时不能把「无法加载」这句话当成正文塞进阅读区（会被当成书的内容朗读、缓存）。
                    self.setCurrentPageIndex(0, silent: true)
                    self.pages = []
                    self.pageSummaries = []
                    self.searchResults = []
                    self.isContentLoaded = true
                    self.requestContentScrollRefresh()
                    self.updateNowPlayingInfo()
                    self.showNotice("《\(Self.shortTitle(book.title))》的内容没能读出来，请稍后再试", kind: .error)
                    completion?()
                }
            }
        }
    }

    // MARK: - 删除

    func deleteBook(_ book: Book) {
        deleteBooks([book])
    }

    /// 内置书（使用说明）不能删除，传进来也会被忽略。
    func deleteBooks(_ booksToDelete: [Book]) {
        let targets = booksToDelete.filter { !$0.isBuiltIn }
        guard !targets.isEmpty else { return }

        let deletingCurrent = targets.contains { $0.id == currentBookId }
        if deletingCurrent {
            stopReading()
        }

        let group = DispatchGroup()
        // 删除的回调都回到主线程，这个数组不会被并发修改。
        var failedTitles: [String] = []
        for book in targets {
            group.enter()
            libraryManager.deleteBook(book) { result in
                if case .failure(let error) = result {
                    print("删除书籍失败: \(book.title), 错误: \(error)")
                    failedTitles.append(book.title)
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.books = self.libraryManager.loadBooks()
            self.sortBooks()

            var nowOpenTitle: String?
            let currentIsGone = !self.books.contains { $0.id == self.currentBookId }
            if deletingCurrent && currentIsGone {
                if let nextBook = self.books.first {
                    self.loadBook(nextBook)
                    nowOpenTitle = nextBook.title
                } else {
                    self.resetToEmptyLibrary()
                }
            }

            let deletedTitles = targets.map(\.title).filter { !failedTitles.contains($0) }
            if let message = Self.deletionFailureMessage(failedTitles: failedTitles) {
                self.showNotice(message, kind: .error)
            } else if let message = Self.deletionMessage(deletedTitles: deletedTitles, nowOpenTitle: nowOpenTitle) {
                self.showNotice(message, kind: .info)
            }
        }
    }

    private func resetToEmptyLibrary() {
        pages = []
        pageSummaries = []
        searchResults = []
        setCurrentPageIndex(0, silent: true)
        currentBookId = nil
        currentBookTitle = Self.appDisplayName
        isContentLoaded = true
        clearReturnOffer()
    }

    static func deletionFailureMessage(failedTitles: [String]) -> String? {
        switch failedTitles.count {
        case 0:
            return nil
        case 1:
            return "《\(shortTitle(failedTitles[0]))》没能删除，请重试"
        default:
            return "有 \(failedTitles.count) 本书没能删除，请重试"
        }
    }

    /// 删除成功后要不要说点什么：
    /// - 删掉的是正在读的书时，阅读器会换成另一本，必须说清楚现在打开的是哪本；
    /// - 一次删了好几本时，报一下数量；
    /// - 只删了一本别的书时，那一行从书架上消失就是反馈，不再多说。
    static func deletionMessage(deletedTitles: [String], nowOpenTitle: String?) -> String? {
        guard !deletedTitles.isEmpty else { return nil }

        let deletedDescription = deletedTitles.count == 1
            ? "已删除《\(shortTitle(deletedTitles[0]))》"
            : "已删除 \(deletedTitles.count) 本书"

        if let nowOpenTitle = nowOpenTitle {
            return "\(deletedDescription)，现在打开的是《\(shortTitle(nowOpenTitle))》"
        }
        return deletedTitles.count == 1 ? nil : deletedDescription
    }

    // MARK: - 导入（文件 / Wi‑Fi / 外部）

    /// Wi‑Fi 传书收到一个文件。在主线程上同步保存，结果直接回给电脑上的网页。
    private func handleReceivedFile(fileName: String, content: String) -> WiFiTransferService.ReceiveResult {
        do {
            let imported = try libraryManager.importBook(fileName: fileName, content: content)
            finishImport(imported, source: .wifi)
            return .saved(title: imported.book.title, conflictingTitle: imported.conflictingTitle)
        } catch {
            print("处理接收文件失败: \(error)")
            let reason = (error as? LibraryManager.LibraryError)?.userMessage ?? "保存失败，请重试"
            return .rejected(reason: reason)
        }
    }

    /// 从一个文件导入一本书。
    /// - Parameter source: App 内「从文件导入」传 `.filePicker`；从别的 App 打开文件传 `.external`。
    func importBookFromURL(_ url: URL, suggestedTitle: String? = nil, source: ImportSource = .external) {
        print("[ContentViewModel] 从URL导入书籍: \(url.absoluteString)")
        print("[ContentViewModel] 建议标题: \(suggestedTitle ?? "无")")

        // 读文件、识别编码都可能要一点时间，放到后台做，界面不卡。
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let result = Result { try self.libraryManager.importBookFromURL(url, suggestedTitle: suggestedTitle) }

            DispatchQueue.main.async {
                switch result {
                case .success(let imported):
                    print("[ContentViewModel] 成功导入书籍: \(imported.book.title)")
                    self.finishImport(imported, source: source)
                case .failure(let error):
                    print("[ContentViewModel] 导入书籍失败: \(error)")
                    self.showNotice(Self.importFailureMessage(for: error), kind: .error)
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
            // 没存进书架的会留在收件箱里，下次回到 App 时再试。
            var failedCount = 0

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
                        failedCount += 1
                        return false
                    }
                }
            } catch {
                print("[ContentViewModel] 消费共享导入失败: \(error)")
            }

            DispatchQueue.main.async {
                self.isConsumingSharedImports = false

                guard !importedBooks.isEmpty else {
                    if failedCount > 0 {
                        self.showNotice("分享过来的内容没能存进书架，下次打开时会再试一次", kind: .error)
                    }
                    completion?([])
                    return
                }

                self.books = self.libraryManager.loadBooks()
                self.sortBooks()

                if let latestBook = importedBooks.last {
                    self.loadBook(latestBook)
                    self.showNotice(
                        Self.sharedImportMessage(
                            importedCount: importedBooks.count,
                            failedCount: failedCount,
                            openedTitle: latestBook.title
                        ),
                        kind: failedCount > 0 ? .error : .success
                    )
                }

                completion?(importedBooks)
            }
        }
    }

    static func sharedImportMessage(importedCount: Int, failedCount: Int, openedTitle: String) -> String {
        let title = shortTitle(openedTitle)
        var message = importedCount == 1
            ? "已导入《\(title)》"
            : "已导入 \(importedCount) 本，现在打开的是《\(title)》"
        if failedCount > 0 {
            message += "。另有 \(failedCount) 份没能存进书架，下次打开时会再试一次"
        }
        return message
    }

    func getBookProgressDisplay(book: Book) -> String? {
        // 正在读的这本直接按当前页算：存下来的进度要等下次整理书架才刷新，会一直停在旧数字上。
        if book.id == currentBookId, isContentLoaded, !pages.isEmpty {
            return Self.formatBookProgressDisplay(
                BookProgress(
                    currentPageIndex: currentPageIndex,
                    totalPages: pages.count,
                    lastAccessed: nil,
                    cachedPages: nil
                )
            )
        }
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

    // MARK: - 提示

    /// 在界面顶部显示一条提示。成功 / 说明在显示出来几秒后自动消失；失败会一直留着，直到用户点掉。
    func showNotice(_ message: String, kind: AppNotice.Kind = .info) {
        if let existing = notice, existing.message == message, existing.kind == kind {
            // 同一句话已经在显示时不换新实例，避免横幅重新弹一次；只把消失的时间往后顺延。
            if noticeDismissWorkItem != nil {
                scheduleNoticeDismissal(for: existing)
            }
            return
        }

        noticeDismissWorkItem?.cancel()
        noticeDismissWorkItem = nil
        notice = AppNotice(kind: kind, message: message)
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    /// 某一层界面真的把这条提示显示出来了。
    ///
    /// 会自动消失的提示从这一刻才开始计时：提示出现时如果正被没有提示位的面板（设置、搜索…）盖着，
    /// 就先留着，等用户回到能看见它的界面再显示，免得还没看到就没了。
    func noticeDidAppear(_ shown: AppNotice) {
        guard notice?.id == shown.id, noticeDismissWorkItem == nil else { return }
        scheduleNoticeDismissal(for: shown)
    }

    private func scheduleNoticeDismissal(for target: AppNotice) {
        noticeDismissWorkItem?.cancel()
        noticeDismissWorkItem = nil

        guard let delay = target.autoDismissDelay else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, self.notice?.id == target.id else { return }
            self.noticeDismissWorkItem = nil
            self.notice = nil
        }
        noticeDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func dismissNotice() {
        noticeDismissWorkItem?.cancel()
        noticeDismissWorkItem = nil
        notice = nil
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
    
    // MARK: - 编辑书籍

    /// 改书名。新书名会存下来，重启后仍然有效。
    /// - Returns: 是否保存成功。
    @discardableResult
    func updateBookTitle(book: Book, newTitle: String) -> Bool {
        do {
            let updatedBook = try libraryManager.updateBookTitle(book: book, newTitle: newTitle)
            if let index = books.firstIndex(where: { $0.id == book.id }) {
                books[index] = updatedBook
            }
            if book.id == currentBookId {
                currentBookTitle = updatedBook.title
                // 下次启动时先显示的是缓存里的书名，要一起更新。
                saveCurrentPageToCache()
                updateNowPlayingInfo()
            }
            return true
        } catch {
            print("Failed to update book title: \(error)")
            return false
        }
    }

    /// 改正文。正在读的书改完之后停在原来的阅读百分比附近，不会被送回第一页。
    func updateBookContent(book: Book, newContent: String, completion: @escaping (Bool) -> Void) {
        libraryManager.updateBookContent(book: book, newContent: newContent) { [weak self] result in
            guard let self = self else {
                completion(false)
                return
            }

            switch result {
            case .success:
                // 旧正文的单页预览和整本缓存都不能再用了。
                self.libraryManager.clearContentCaches(bookId: book.id)

                guard book.id == self.currentBookId else {
                    completion(true)
                    return
                }

                self.repaginationToken = nil
                self.paginateInBackground(newContent) { newPages, summaries in
                    if book.id == self.currentBookId {
                        self.replaceCurrentPages(for: book, pages: newPages, summaries: summaries)
                    }
                    completion(true)
                }

            case .failure(let error):
                print("Failed to update book content: \(error)")
                completion(false)
            }
        }
    }

    // MARK: - 翻页

    /// 锁屏 / 耳机线控的下一页。到头时什么都不做，也不提示。
    func nextPage() {
        goToPage(currentPageIndex + 1)
    }

    func previousPage() {
        goToPage(currentPageIndex - 1)
    }

    /// 用户在阅读区点按 / 滑动翻页。
    /// - Returns: 是否真的翻了页。已经在第一页 / 最后一页时返回 `false` 并提示，由界面做「到头了」的回弹。
    @discardableResult
    func turnPage(forward: Bool) -> Bool {
        guard !pages.isEmpty else { return false }

        let target = currentPageIndex + (forward ? 1 : -1)
        guard pages.indices.contains(target) else {
            showNotice(forward ? "已经是最后一页" : "已经是第一页", kind: .info)
            return false
        }

        goToPage(target)
        return true
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
        // 后台（如锁屏 / 控制中心远程翻页）期间静默推进，避免回前台时补播滚动动画。
        movePage(to: index, silent: isAppInBackground)
    }

    private func movePage(to index: Int, silent: Bool) {
        guard !pages.isEmpty, pages.indices.contains(index) else { return }
        guard index != currentPageIndex else { return }

        let shouldResume = suspendSpeechKeepingReadingIntent()
        setCurrentPageIndex(index, silent: silent)

        if shouldResume {
            scheduleResumeAfterManualTurn()
        } else {
            updateNowPlayingInfo()
        }
    }

    /// 停下正在读的这一段，但保留「继续朗读」的意图。
    /// - Returns: 之后是否需要调用 `scheduleResumeAfterManualTurn()` 接着读。
    private func suspendSpeechKeepingReadingIntent() -> Bool {
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
        return shouldResume
    }

    // MARK: - 回到跳转前的位置

    /// 开始拖动进度滑杆。
    func beginProgressScrub() {
        guard progressScrubOriginPageIndex == nil else { return }
        // 已经有「回到第 N 页」时接着拖，要回的仍然是最初那一页。
        progressScrubOriginPageIndex = returnPageIndex ?? currentPageIndex
    }

    /// 松开进度滑杆。
    func endProgressScrub() {
        guard let origin = progressScrubOriginPageIndex else { return }
        progressScrubOriginPageIndex = nil
        offerReturn(to: origin)
    }

    /// 跳到远处之后，留一个「回到第 N 页」的入口：拖过头、点错搜索结果都能一步回去。
    private func offerReturn(to origin: Int) {
        guard pages.indices.contains(origin), origin != currentPageIndex else {
            clearReturnOffer()
            return
        }
        returnPageIndex = origin
        scheduleReturnOfferExpiry()
    }

    /// 进度滑杆收起时调用：重新计时，别让入口被滑杆挡了半天、刚露面就消失。
    func extendReturnOffer() {
        guard returnPageIndex != nil else { return }
        scheduleReturnOfferExpiry()
    }

    private func scheduleReturnOfferExpiry() {
        returnOfferExpiryWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.returnOfferExpiryWorkItem = nil
            self?.returnPageIndex = nil
        }
        returnOfferExpiryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.returnOfferLifetime, execute: workItem)
    }

    /// 回到跳转前的那一页。回去之后入口换成反方向的，点错了还能再回来。
    func returnToJumpOrigin() {
        guard let origin = returnPageIndex, pages.indices.contains(origin) else {
            clearReturnOffer()
            return
        }
        let jumpedFrom = currentPageIndex
        movePage(to: origin, silent: true)
        offerReturn(to: jumpedFrom)
    }

    func clearReturnOffer() {
        returnOfferExpiryWorkItem?.cancel()
        returnOfferExpiryWorkItem = nil
        progressScrubOriginPageIndex = nil
        returnPageIndex = nil
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
        stopVoicePreview()
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
        stopVoicePreview()
        cancelSleepTimer()
        wiFiTransferService.stopServer()
        dismissNotice()
        clearReturnOffer()
        showingBookList = false
        showingSearchView = false
        showingBigBang = false
        showingTemplateLibrary = false
        showingBookEdit = false
        showingSettings = false
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
        let origin = returnPageIndex ?? currentPageIndex
        // 搜索面板会立刻关闭，跨度通常较大；用户视线刚从搜索弹层切回主界面，
        // 这里直接静默定位，避免一段长距离的滚动动画造成视觉打扰。
        // 点回当前页时页码不变，仍要刷新滚动，否则 sheet/键盘收起后的失位不会被纠正。
        if pageIndex == currentPageIndex {
            requestContentScrollRefresh()
        } else {
            setCurrentPageIndex(pageIndex, silent: true)
        }
        offerReturn(to: origin)
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

    // MARK: - Wi‑Fi 传书

    /// 进入传书页面：清掉上一次的结果列表，直接开始接收，不需要再点「开始」。
    func beginWiFiTransferSession() {
        wiFiTransferService.clearRecords()
        wiFiTransferService.startServer()
    }

    /// 开始接收失败后的「重试」。
    func retryWiFiTransfer() {
        wiFiTransferService.stopServer()
        wiFiTransferService.startServer()
    }

    /// 离开传书页面。
    func endWiFiTransferSession() {
        wiFiTransferService.stopServer()
    }

    // MARK: - 语音试听

    /// 选中一种朗读语音。没在朗读时顺便念一句样例，让人听得出选的是什么声音；
    /// 正在朗读时会直接用新语音接着读，不需要另外试听。
    func selectVoice(identifier: String) {
        // 先记下来：换语音会让正在进行的朗读先停再重读，中途 isReading 会短暂变成 false。
        let wasReading = isReading || pendingResumeAfterManualTurn
        selectedVoiceIdentifier = identifier
        guard !wasReading else { return }
        previewVoice(identifier: identifier)
    }

    private func previewVoice(identifier: String) {
        guard let voice = availableVoices.first(where: { $0.identifier == identifier }) else { return }

        let synthesizer = voicePreviewSynthesizer ?? AVSpeechSynthesizer()
        voicePreviewSynthesizer = synthesizer
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: Self.voicePreviewText)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * readingSpeed
        synthesizer.speak(utterance)
    }

    func stopVoicePreview() {
        guard let synthesizer = voicePreviewSynthesizer else { return }
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
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
    
    /// 别的 App 让随心读导入文字、但链接里没带着能导入的东西时说的话。
    static let unrecognizedImportLinkMessage = "没有找到能导入的文字，什么都没有加进书架"

    private func handleCustomSchemeURL(_ url: URL) {
        print("[ContentViewModel] 处理自定义scheme URL: \(url.absoluteString)")
        
        // 不是「导入」的链接只是把 App 打开，不算失败，不用提示。
        guard let host = url.host, host == "import" else {
            print("[ContentViewModel][警告] 不支持的URL主机: \(url.host ?? "nil")")
            return
        }
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let queryItems = components.queryItems else {
            print("[ContentViewModel][警告] URL中没有查询项")
            showNotice(Self.unrecognizedImportLinkMessage, kind: .error)
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
                showNotice("导入失败，请重试", kind: .error)
            }
        } else {
            print("[ContentViewModel][警告] URL中未找到有效的text参数")
            showNotice(Self.unrecognizedImportLinkMessage, kind: .error)
        }
    }

    // MARK: - 选词

    func triggerBigBang() {
        guard !pages.isEmpty,
              currentPageIndex >= 0,
              currentPageIndex < pages.count else { return }
        let text = pages[currentPageIndex]
        tokenizer.tokenize(text: text) { [weak self] tokens in
            self?.tokens = tokens
        }
        clearSelectedTokens()
        showingBigBang = true
    }

    func processTokenTap(tappedTokenID: UUID) {
        let result = Self.tokenSelection(
            afterTapping: tappedTokenID,
            anchor: selectionAnchorTokenID,
            selected: selectedTokenIDs,
            orderedIDs: tokens.map(\.id)
        )
        selectedTokenIDs = result.selected
        selectionAnchorTokenID = result.anchor
    }

    /// 选词只有一条规则：选中的总是「第一个点的词（起点）」到「刚点的词」之间的全部。
    /// - 还没选：点哪个选哪个，它就是起点。
    /// - 点别的词：选中起点到它之间的全部；点在已选范围里面，就是把范围缩到这里。
    /// - 点起点：范围缩回只剩起点；已经只剩起点时再点一次，取消选择。
    static func tokenSelection(
        afterTapping tapped: UUID,
        anchor: UUID?,
        selected: Set<UUID>,
        orderedIDs: [UUID]
    ) -> (selected: Set<UUID>, anchor: UUID?) {
        guard let tappedIndex = orderedIDs.firstIndex(of: tapped) else {
            return (selected, anchor)
        }
        guard let anchor = anchor, let anchorIndex = orderedIDs.firstIndex(of: anchor) else {
            return ([tapped], tapped)
        }
        if tapped == anchor {
            return selected.count > 1 ? ([anchor], anchor) : ([], nil)
        }
        let range = min(anchorIndex, tappedIndex)...max(anchorIndex, tappedIndex)
        return (Set(orderedIDs[range]), anchor)
    }

    func clearSelectedTokens() {
        selectedTokenIDs.removeAll()
        selectionAnchorTokenID = nil
    }

    var selectedTokenText: String {
        tokens.filter { selectedTokenIDs.contains($0.id) }.map(\.value).joined()
    }

    func copySelected() {
        let text = selectedTokenText
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
        showingBigBang = false
        showNotice("已复制", kind: .success)
    }

    func addTemplate(_ t: PromptTemplate) {
        templates.append(t)
        persistTemplates()
    }

    func updateTemplate(_ t: PromptTemplate) {
        guard let idx = templates.firstIndex(where: { $0.id == t.id }) else { return }
        templates[idx] = t
        persistTemplates()
    }

    func deleteTemplate(_ t: PromptTemplate) {
        templates.removeAll { $0.id == t.id }
        persistTemplates()
    }

    /// 模板的改动没写进磁盘时要说出来：否则现在看着改好了，下次打开又变回去。
    private func persistTemplates() {
        guard !templateManager.save(templates) else { return }
        showNotice("模板的改动没能保存，下次打开时可能会变回原样", kind: .error)
    }
    
    /// 用模板生成提示词并复制到剪贴板，再按模板的去向决定要不要打开别的 App。
    /// - Parameter destination: 模板还没设去向时，用户当场选的去向。会记到模板上，下次不用再选。
    func useTemplate(_ template: PromptTemplate, destination: PromptTemplate.Destination? = nil) {
        let resolved = destination ?? template.destination ?? .copyOnly
        if template.destination == nil, let chosen = destination {
            var remembered = template
            remembered.destination = chosen
            updateTemplate(remembered)
        }

        let prompt = buildPrompt(using: template)
        UIPasteboard.general.string = prompt

        switch resolved {
        case .copyOnly:
            showNotice("已复制提示词", kind: .success)
        case .perplexity:
            openExternalApp(Self.perplexityURL(query: prompt), name: "Perplexity")
        case .raycast:
            openExternalApp(URL(string: "raycast://extensions/"), name: "Raycast")
        }
    }

    func buildPrompt(using template: PromptTemplate) -> String {
        var contextContent: [String] = []
        if currentPageIndex > 0, pages.indices.contains(currentPageIndex - 1) {
            contextContent.append(pages[currentPageIndex - 1])
        }
        if pages.indices.contains(currentPageIndex) {
            contextContent.append(pages[currentPageIndex])
        }
        if pages.indices.contains(currentPageIndex + 1) {
            contextContent.append(pages[currentPageIndex + 1])
        }
        let page = contextContent.joined(separator: "\n\n---\n\n")

        var result = template.content
        result = result.replacingOccurrences(of: "{selection}", with: selectedTokenText)
        result = result.replacingOccurrences(of: "{page}", with: page)
        result = result.replacingOccurrences(of: "{book}", with: currentBookTitle)
        return result
    }

    static func perplexityURL(query: String) -> URL? {
        // 提示词里的 & = + # 都要转义，否则会被当成网址的分隔符，后半段提示词就丢了。
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+#?")
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "https://www.perplexity.ai/search/new?q=\(encodedQuery)")
    }

    /// 打开别的 App。打不开（比如没有安装）时要说出来，不能点了没反应。
    private func openExternalApp(_ url: URL?, name: String) {
        let failureMessage = "没有打开 \(name)，提示词已复制，可以手动粘贴"
        guard let url = url else {
            showNotice(failureMessage, kind: .error)
            return
        }
        UIApplication.shared.open(url, options: [:]) { [weak self] opened in
            guard !opened else { return }
            DispatchQueue.main.async {
                self?.showNotice(failureMessage, kind: .error)
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
    
    /// 关闭定时：只清除计时，朗读照常继续。
    func cancelSleepTimer() {
        sleepTimerTicker?.invalidate()
        sleepTimerTicker = nil
        sleepTimerStopPendingAfterCurrentUtterance = false
        sleepTimerActive = false
        sleepTimerEndDate = nil
        sleepTimerRemaining = 0
        sleepTimerDuration = 0
    }
    
    /// 定时到点时调用：清除定时并停止朗读。
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
    
    /// 点击播放按钮：只切换播放 / 暂停。
    /// 定时不会因为暂停而被悄悄取消，要关定时用 `cancelSleepTimer()`。
    func handlePlayButtonTap() {
        toggleReading()
    }
    
    deinit {
        stopReading()
        stopVoicePreview()
        sleepTimerTicker?.invalidate()
        sleepTimerTicker = nil
        noticeDismissWorkItem?.cancel()
        returnOfferExpiryWorkItem?.cancel()
        wiFiTransferService.stopServer()
        cancellables.forEach { $0.cancel() }
    }
} 
