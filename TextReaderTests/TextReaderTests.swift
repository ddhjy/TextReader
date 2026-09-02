import Testing
import Foundation
@testable import TextReader

struct TextReaderTests {

    @Test
    func settingsManagersUseSeparateProfileNamespaces() throws {
        let defaultsSuite = "TextReaderTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsSuite))
        defer {
            defaults.removePersistentDomain(forName: defaultsSuite)
        }

        let personalSettings = SettingsManager(defaults: defaults)
        let reviewSettings = SettingsManager(
            defaults: defaults,
            keyPrefix: AppDataProfile.reviewSample.settingsKeyPrefix
        )

        personalSettings.saveLastBookTitle("真实书籍")
        personalSettings.saveReadingSpeed(1.25)
        personalSettings.saveDarkMode(true)
        personalSettings.saveAccentColorThemeId("green")
        reviewSettings.saveLastBookTitle("审核样例")
        reviewSettings.saveReadingSpeed(2.0)

        #expect(personalSettings.getLastBookTitle() == "真实书籍")
        #expect(personalSettings.getReadingSpeed() == 1.25)
        #expect(reviewSettings.getLastBookTitle() == "审核样例")
        #expect(reviewSettings.getReadingSpeed() == 2.0)
        #expect(reviewSettings.getDarkMode())
        #expect(reviewSettings.getAppearanceMode() == .dark)
        #expect(reviewSettings.getAccentColorThemeId() == "green")

        reviewSettings.saveDarkMode(false)
        reviewSettings.saveAccentColorThemeId("red")

        #expect(!personalSettings.getDarkMode())
        #expect(personalSettings.getAppearanceMode() == .light)
        #expect(personalSettings.getAccentColorThemeId() == "red")

        personalSettings.saveAppearanceMode(.system)
        #expect(reviewSettings.getAppearanceMode() == .system)
        #expect(!reviewSettings.getDarkMode())

        reviewSettings.saveAppearanceMode(.dark)
        #expect(personalSettings.getAppearanceMode() == .dark)
        #expect(personalSettings.getDarkMode())

        reviewSettings.saveAppearanceMode(.light)
        #expect(personalSettings.getAppearanceMode() == .light)
        #expect(!personalSettings.getDarkMode())

        reviewSettings.removeAllManagedValues()

        #expect(personalSettings.getLastBookTitle() == "真实书籍")
        #expect(personalSettings.getReadingSpeed() == 1.25)
        #expect(reviewSettings.getLastBookTitle() == nil)
        #expect(reviewSettings.getReadingSpeed() == 1.0)
        #expect(!reviewSettings.getDarkMode())
        #expect(reviewSettings.getAccentColorThemeId() == "red")
    }

    @Test
    func libraryManagersKeepPersonalAndReviewSampleDataSeparate() throws {
        let rootDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let reviewDirectory = try AppDataProfile.reviewSample.documentsDirectory(
            baseDocumentsDirectory: rootDirectory
        )
        let personalLibrary = LibraryManager(
            documentsDirectoryProvider: { rootDirectory },
            builtInBooks: []
        )
        let reviewLibrary = LibraryManager(
            documentsDirectoryProvider: { reviewDirectory },
            builtInBooks: AppDataProfile.reviewSample.builtInBooks
        )

        let personalBook = try personalLibrary.importSharedText("真实书籍内容", preferredTitle: "真实书籍")
        let reviewBook = try reviewLibrary.importSharedText("审核导入内容", preferredTitle: "审核导入")

        personalLibrary.saveBookProgress(bookId: personalBook.id, pageIndex: 3, totalPages: 10)
        reviewLibrary.saveBookProgress(bookId: reviewBook.id, pageIndex: 1, totalPages: 4)

        let personalBooks = personalLibrary.loadBooks()
        let reviewBooks = reviewLibrary.loadBooks()

        #expect(personalBooks.contains { $0.fileName == personalBook.fileName })
        #expect(!personalBooks.contains { $0.fileName == reviewBook.fileName })
        #expect(!personalBooks.contains { $0.title == "读书派示例文本" })

        #expect(reviewBooks.contains { $0.title == "读书派示例文本" && $0.isBuiltIn })
        #expect(reviewBooks.contains { $0.fileName == reviewBook.fileName })
        #expect(!reviewBooks.contains { $0.fileName == personalBook.fileName })

        #expect(personalLibrary.getBookProgress(bookId: reviewBook.id) == nil)
        #expect(reviewLibrary.getBookProgress(bookId: personalBook.id) == nil)
    }

    @Test
    func resetReviewSampleDataDoesNotDeletePersonalData() throws {
        let rootDirectory = try makeTemporaryDirectory()
        let defaultsSuite = "TextReaderTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsSuite))

        defer {
            defaults.removePersistentDomain(forName: defaultsSuite)
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let personalURL = rootDirectory.appendingPathComponent("真实书籍.txt")
        try "真实内容".write(to: personalURL, atomically: true, encoding: .utf8)

        let reviewDirectory = try AppDataProfile.reviewSample.documentsDirectory(
            baseDocumentsDirectory: rootDirectory
        )
        let reviewURL = reviewDirectory.appendingPathComponent("审核导入.txt")
        try "审核内容".write(to: reviewURL, atomically: true, encoding: .utf8)

        let personalSettings = SettingsManager(defaults: defaults)
        let reviewSettings = SettingsManager(
            defaults: defaults,
            keyPrefix: AppDataProfile.reviewSample.settingsKeyPrefix
        )
        personalSettings.saveLastBookTitle("真实书籍")
        personalSettings.saveAccentColorThemeId("purple")
        reviewSettings.saveLastBookTitle("审核导入")

        try AppDataProfile.reviewSample.clearPersistedData(
            baseDocumentsDirectory: rootDirectory,
            defaults: defaults
        )

        #expect(FileManager.default.fileExists(atPath: personalURL.path))
        #expect(!FileManager.default.fileExists(atPath: reviewDirectory.path))
        #expect(personalSettings.getLastBookTitle() == "真实书籍")
        #expect(reviewSettings.getLastBookTitle() == nil)
        #expect(reviewSettings.getAccentColorThemeId() == "purple")
    }
}

private func makeTemporaryDirectory() throws -> URL {
    let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    return directoryURL
}
