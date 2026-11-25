import AVFoundation
import Foundation
import Testing
@testable import TextReader

final class MockAudioSessionManager: AudioSessionManager {
    override func registerViewModel(_ viewModel: ContentViewModel) {}

    override func setupAudioSession() {}

    override func setupRemoteCommandCenter(playAction: @escaping () -> Void,
                                           pauseAction: @escaping () -> Void,
                                           nextAction: (() -> Void)? = nil,
                                           previousAction: (() -> Void)? = nil) {}

    override func updateNowPlayingInfo(title: String?, isPlaying: Bool, currentPage: Int? = nil, totalPages: Int? = nil, deactivateSessionWhenStopped: Bool = true) {}
}

final class MockSpeechManager: SpeechManager, @unchecked Sendable {
    private(set) var startedTexts: [String] = []
    private(set) var stopCallCount = 0
    private var lastUtteranceId: UUID?

    override func getAvailableVoices(languagePrefix: String = "zh") -> [AVSpeechSynthesisVoice] {
        []
    }

    override func startReading(text: String, voice: AVSpeechSynthesisVoice?, rate: Float) -> UUID? {
        let id = UUID()
        startedTexts.append(text)
        lastUtteranceId = id
        return id
    }

    override func stopReading() {
        guard lastUtteranceId != nil else { return }
        stopCallCount += 1
        lastUtteranceId = nil
    }

    func finishLastUtterance() {
        guard let id = lastUtteranceId else {
            Issue.record("No utterance was started")
            return
        }
        lastUtteranceId = nil

        onSpeechFinish?(id)
    }
}

final class MockTextPaginator: TextPaginator {
    private let pagesToReturn: [String]

    init(pages: [String]) {
        self.pagesToReturn = pages
    }

    override func paginate(text: String, maxPageSize: Int = 100) -> [String] {
        pagesToReturn
    }
}

/// 每个非空行算一页：页数完全由测试文本决定，不受模拟器字号设置影响。
final class LinePaginator: TextPaginator {
    override func paginate(text: String, maxPageSize: Int = 100) -> [String] {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.isEmpty ? ["无内容"] : lines
    }
}

func makeTemporaryDirectory() throws -> URL {
    let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    return directoryURL
}

func waitUntil(timeoutNanoseconds: UInt64,
               pollIntervalNanoseconds: UInt64 = 50_000_000,
               condition: @escaping @Sendable () -> Bool) async throws {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

    while DispatchTime.now().uptimeNanoseconds < deadline {
        if condition() {
            return
        }
        try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
    }

    Issue.record("Condition was not satisfied before timeout")
}

/// 在主线程上轮询，直到条件成立。ViewModel 的状态只在主线程上改，所以也在主线程上读。
@MainActor
func waitOnMain(timeout: TimeInterval = 3,
                sourceLocation: SourceLocation = #_sourceLocation,
                until condition: () -> Bool) async {
    let deadline = Date().addingTimeInterval(timeout)

    while Date() < deadline {
        if condition() {
            return
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }

    Issue.record("Condition was not satisfied before timeout", sourceLocation: sourceLocation)
}

/// 一套互相隔离的临时目录、偏好和假语音，用来搭一个不碰真实数据的 `ContentViewModel`。
final class ViewModelHarness {
    let documentsDirectory: URL
    let sharedContainer: URL
    let defaults: UserDefaults
    let libraryManager: LibraryManager
    let speechManager = MockSpeechManager()
    let wiFiTransferService = WiFiTransferService()
    let viewModel: ContentViewModel

    private let defaultsSuite: String

    /// - Parameters:
    ///   - builtInBooks: 书架自带的内置书。默认没有。
    ///   - paginator: 默认一行一页，方便写与页码有关的断言。
    ///   - prepare: 在创建 ViewModel 之前往书库里放东西。
    init(builtInBooks: [LibraryManager.BuiltInBook] = [],
         paginator: TextPaginator = LinePaginator(),
         prepare: (LibraryManager) throws -> Void = { _ in }) throws {
        let documentsDirectory = try makeTemporaryDirectory()
        let sharedContainer = try makeTemporaryDirectory()
        let defaultsSuite = "TextReaderTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsSuite))

        self.documentsDirectory = documentsDirectory
        self.sharedContainer = sharedContainer
        self.defaultsSuite = defaultsSuite
        self.defaults = defaults

        let libraryManager = LibraryManager(
            fileManager: .default,
            documentsDirectoryProvider: { documentsDirectory },
            builtInBooks: builtInBooks
        )
        self.libraryManager = libraryManager
        try prepare(libraryManager)

        viewModel = ContentViewModel(
            libraryManager: libraryManager,
            textPaginator: paginator,
            speechManager: speechManager,
            wiFiTransferService: wiFiTransferService,
            audioSessionManager: MockAudioSessionManager(),
            settingsManager: SettingsManager(defaults: defaults),
            sharedImportStore: SharedImportStore(
                fileManager: .default,
                containerURLProvider: { sharedContainer }
            ),
            templateManager: TemplateManager(
                fileManager: .default,
                documentsDirectoryProvider: { documentsDirectory }
            )
        )
    }

    deinit {
        defaults.removePersistentDomain(forName: defaultsSuite)
        try? FileManager.default.removeItem(at: documentsDirectory)
        try? FileManager.default.removeItem(at: sharedContainer)
    }

    func book(_ fileName: String) throws -> Book {
        try #require(viewModel.books.first { $0.fileName == fileName })
    }

    /// 等一本书分页完成（内容就位、不再是占位预览）。
    @MainActor
    func waitUntilOpened(_ bookId: String, sourceLocation: SourceLocation = #_sourceLocation) async {
        let viewModel = self.viewModel
        await waitOnMain(sourceLocation: sourceLocation) {
            viewModel.currentBookId == bookId && viewModel.isContentLoaded && viewModel.isContentSettled
        }
    }
}

/// 生成「前缀1、前缀2…」这样一行一页的正文。
func numberedLines(_ count: Int, prefix: String = "第", suffix: String = "页") -> String {
    (1...count).map { "\(prefix)\($0)\(suffix)" }.joined(separator: "\n")
}
