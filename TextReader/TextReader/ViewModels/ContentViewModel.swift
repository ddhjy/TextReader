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
        setupBindings()
        setupWiFiTransferCallbacks()
        setupSpeechCallbacks()
        audioSessionManager.setupAudioSession()
        audioSessionManager.setupRemoteCommandCenter(
            playAction: { [weak self] in self?.readCurrentPage() },
            pauseAction: { [weak self] in self?.stopReading() },
            nextAction: { [weak self] in self?.nextPage() },
            previousAction: { [weak self] in self?.previousPage() }
        )
    }

    // --- Loading ---
    private func loadInitialData() {
        self.books = libraryManager.loadBooks()
        let lastBookId = settingsManager.getLastOpenedBookId() ?? books.first?.id
        if let bookId = lastBookId, let bookToLoad = books.first(where: { $0.id == bookId }) {
            loadBook(bookToLoad)
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
            guard let self = self, self.isReading else { return }
            // Auto-advance to next page
            if self.currentPageIndex < self.pages.count - 1 {
                self.currentPageIndex += 1
                self.readCurrentPage()
            } else {
                self.isReading = false // Reached end of book
                self.audioSessionManager.updateNowPlayingInfo(title: self.currentBookTitle, isPlaying: false)
            }
        }
        speechManager.onSpeechStart = { [weak self] in
            // Optional: Handle speech start event if needed
        }
        speechManager.onSpeechPause = { [weak self] in
            // Optional: Handle speech pause event if needed
        }
        speechManager.onSpeechResume = { [weak self] in
            // Optional: Handle speech resume event if needed
        }
    }

    // --- Book Management ---
    func loadBook(_ book: Book) {
        stopReading() // Stop reading before changing book
        isContentLoaded = false
        currentBookId = book.id
        currentBookTitle = book.title
        settingsManager.saveLastOpenedBookId(book.id) // Save as last opened

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
        let textToRead = pages[currentPageIndex]
        let voice = availableVoices.first { $0.identifier == selectedVoiceIdentifier }
        speechManager.startReading(text: textToRead, voice: voice, rate: readingSpeed)
        isReading = true
        updateNowPlayingInfo()
    }

    func stopReading() {
        speechManager.stopReading()
        isReading = false
        updateNowPlayingInfo()
    }

    private func restartReading() {
        if isReading {
            stopReading()
            // Add a small delay before restarting to ensure synthesizer is fully stopped
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
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
        audioSessionManager.updateNowPlayingInfo(title: currentBookTitle, isPlaying: isReading, currentPage: currentPageIndex + 1, totalPages: pages.count)
    }

    // --- Cleanup ---
    deinit {
        // Cancel any ongoing operations if needed
        stopReading()
        wiFiTransferService.stopServer()
        cancellables.forEach { $0.cancel() }
    }
} 