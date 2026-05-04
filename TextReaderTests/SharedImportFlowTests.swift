import AVFoundation
import Foundation
import Testing
@testable import TextReader

struct SharedImportFlowTests {
    @Test
    func sharedImportStoreEnqueueAndConsumeDeletesFiles() throws {
        let tempContainer = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempContainer) }

        let store = SharedImportStore(
            fileManager: .default,
            containerURLProvider: { tempContainer }
        )

        let createdAt = Date(timeIntervalSince1970: 1_234_567)
        let item = try store.enqueueTextImport(
            text: "第一段\n第二段",
            title: "分享标题",
            sourceType: .text,
            createdAt: createdAt
        )

        #expect(try store.pendingImports() == [item])

        let consumedItems = try store.consumePendingImports { pendingItem, text in
            #expect(pendingItem == item)
            #expect(text == "第一段\n第二段")
            return true
        }

        #expect(consumedItems == [item])
        #expect(try store.pendingImports().isEmpty)
    }

    @Test
    func libraryManagerSharedImportUsesFallbacksAndUniqueFileNames() throws {
        let tempDocuments = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDocuments) }

        let libraryManager = LibraryManager(
            fileManager: .default,
            documentsDirectoryProvider: { tempDocuments }
        )

        let fallbackDate = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(
            libraryManager.resolveSharedImportTitle(
                preferredTitle: " 自定义标题 ",
                sourceFileName: "原始文件.txt",
                content: "正文第一行",
                createdAt: fallbackDate
            ) == "自定义标题"
        )
        #expect(
            libraryManager.resolveSharedImportTitle(
                preferredTitle: nil,
                sourceFileName: "原始文件.md",
                content: "正文第一行",
                createdAt: fallbackDate
            ) == "原始文件"
        )
        #expect(
            libraryManager.resolveSharedImportTitle(
                preferredTitle: nil,
                sourceFileName: nil,
                content: "\n\n第一行会变成标题\n第二行",
                createdAt: fallbackDate
            ) == "第一行会变成标题"
        )
        #expect(
            libraryManager.resolveSharedImportTitle(
                preferredTitle: nil,
                sourceFileName: nil,
                content: "   \n\t",
                createdAt: fallbackDate
            ) == "分享_20231114_221320"
        )

        let firstBook = try libraryManager.importSharedText("第一本内容", preferredTitle: "同名标题")
        let secondBook = try libraryManager.importSharedText("第二本内容", preferredTitle: "同名标题")

        #expect(firstBook.fileName == "同名标题.txt")
        #expect(secondBook.fileName == "同名标题-2.txt")
        #expect(FileManager.default.fileExists(atPath: tempDocuments.appendingPathComponent(firstBook.fileName).path))
        #expect(FileManager.default.fileExists(atPath: tempDocuments.appendingPathComponent(secondBook.fileName).path))
    }

    @Test
    func contentViewModelConsumesPendingSharedImportsAndOpensLatestBook() async throws {
        let tempDocuments = try makeTemporaryDirectory()
        let tempContainer = try makeTemporaryDirectory()
        let defaultsSuite = "TextReaderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuite)!

        defer {
            defaults.removePersistentDomain(forName: defaultsSuite)
            try? FileManager.default.removeItem(at: tempDocuments)
            try? FileManager.default.removeItem(at: tempContainer)
        }

        let libraryManager = LibraryManager(
            fileManager: .default,
            documentsDirectoryProvider: { tempDocuments }
        )
        let sharedImportStore = SharedImportStore(
            fileManager: .default,
            containerURLProvider: { tempContainer }
        )
        let templateManager = TemplateManager(
            fileManager: .default,
            documentsDirectoryProvider: { tempDocuments }
        )

        try sharedImportStore.enqueueTextImport(
            text: "第一本内容",
            title: "第一本",
            sourceType: .text,
            createdAt: Date(timeIntervalSince1970: 10)
        )
        try sharedImportStore.enqueueTextImport(
            text: "第二本内容",
            title: "第二本",
            sourceType: .text,
            createdAt: Date(timeIntervalSince1970: 20)
        )

        let viewModel = ContentViewModel(
            libraryManager: libraryManager,
            speechManager: MockSpeechManager(),
            wiFiTransferService: WiFiTransferService(),
            audioSessionManager: MockAudioSessionManager(),
            settingsManager: SettingsManager(defaults: defaults),
            sharedImportStore: sharedImportStore,
            templateManager: templateManager
        )

        viewModel.consumePendingSharedImports()
        try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            viewModel.currentBookId == "第二本.txt"
        }

        #expect(viewModel.currentBookTitle == "第二本")
        #expect(viewModel.books.contains(where: { $0.fileName == "第一本.txt" }))
        #expect(viewModel.books.contains(where: { $0.fileName == "第二本.txt" }))
        #expect(viewModel.sharedImportBannerMessage == "已导入《第二本》")
        #expect(try sharedImportStore.pendingImports().isEmpty)
    }

    @Test
    func sleepTimerExpiryWaitsForCurrentSegmentToFinish() throws {
        let tempDocuments = try makeTemporaryDirectory()
        let tempContainer = try makeTemporaryDirectory()
        let defaultsSuite = "TextReaderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuite)!

        defer {
            defaults.removePersistentDomain(forName: defaultsSuite)
            try? FileManager.default.removeItem(at: tempDocuments)
            try? FileManager.default.removeItem(at: tempContainer)
        }

        let speechManager = MockSpeechManager()
        let viewModel = ContentViewModel(
            libraryManager: LibraryManager(
                fileManager: .default,
                documentsDirectoryProvider: { tempDocuments }
            ),
            speechManager: speechManager,
            wiFiTransferService: WiFiTransferService(),
            audioSessionManager: MockAudioSessionManager(),
            settingsManager: SettingsManager(defaults: defaults),
            sharedImportStore: SharedImportStore(
                fileManager: .default,
                containerURLProvider: { tempContainer }
            ),
            templateManager: TemplateManager(
                fileManager: .default,
                documentsDirectoryProvider: { tempDocuments }
            )
        )

        viewModel.pages = ["第一段刚开始读", "第二段不应继续"]
        viewModel.currentPageIndex = 0

        viewModel.startSleepTimer(minutes: 1)
        #expect(viewModel.isReading)
        #expect(viewModel.sleepTimerActive)
        #expect(speechManager.startedTexts == ["第一段刚开始读"])

        viewModel.handleSleepTimerExpired()
        #expect(viewModel.isReading)
        #expect(viewModel.sleepTimerActive)
        #expect(viewModel.sleepTimerRemaining == 0)
        #expect(speechManager.stopCallCount == 0)

        speechManager.finishLastUtterance()
        #expect(!viewModel.isReading)
        #expect(!viewModel.sleepTimerActive)
        #expect(viewModel.currentPageIndex == 0)
        #expect(speechManager.startedTexts == ["第一段刚开始读"])
    }
}

private final class MockAudioSessionManager: AudioSessionManager {
    override func registerViewModel(_ viewModel: ContentViewModel) {}

    override func setupAudioSession() {}

    override func setupRemoteCommandCenter(playAction: @escaping () -> Void,
                                           pauseAction: @escaping () -> Void,
                                           nextAction: (() -> Void)? = nil,
                                           previousAction: (() -> Void)? = nil) {}

    override func updateNowPlayingInfo(title: String?, isPlaying: Bool, currentPage: Int? = nil, totalPages: Int? = nil) {}
}

private final class MockSpeechManager: SpeechManager, @unchecked Sendable {
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
        stopCallCount += 1
    }

    func finishLastUtterance() {
        guard let id = lastUtteranceId else {
            Issue.record("No utterance was started")
            return
        }

        onSpeechFinish?(id)
    }
}

private func makeTemporaryDirectory() throws -> URL {
    let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    return directoryURL
}

private func waitUntil(timeoutNanoseconds: UInt64,
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
