import Foundation
import Testing
@testable import TextReader

/// 导入、改名、元数据：这些地方出错会丢书或丢进度。
struct LibraryImportSafetyTests {
    private func makeLibrary(at directory: URL,
                             builtInBooks: [LibraryManager.BuiltInBook] = []) -> LibraryManager {
        LibraryManager(
            fileManager: .default,
            documentsDirectoryProvider: { directory },
            builtInBooks: builtInBooks
        )
    }

    private func fileContent(_ fileName: String, in directory: URL) throws -> String {
        try String(contentsOf: directory.appendingPathComponent(fileName), encoding: .utf8)
    }

    // MARK: - 同名导入不覆盖原书

    @Test
    func importingSameNameKeepsOriginalBookAndItsProgress() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = makeLibrary(at: directory)

        let first = try library.importBook(fileName: "三体.txt", content: "读了一半的那一本")
        library.saveBookProgress(bookId: first.book.id, pageIndex: 120, totalPages: 300)

        let second = try library.importBook(fileName: "三体.txt", content: "后来又传进来的另一本")

        #expect(first.conflictingTitle == nil)
        #expect(first.book.fileName == "三体.txt")
        #expect(second.book.fileName == "三体-2.txt")
        #expect(second.book.title == "三体-2")
        #expect(second.conflictingTitle == "三体")

        #expect(try fileContent("三体.txt", in: directory) == "读了一半的那一本")
        #expect(try fileContent("三体-2.txt", in: directory) == "后来又传进来的另一本")
        #expect(library.getBookProgress(bookId: "三体.txt")?.currentPageIndex == 120)
        #expect(library.getBookProgress(bookId: "三体-2.txt") == nil)

        let third = try library.importBook(fileName: "三体.txt", content: "第三本")
        #expect(third.book.fileName == "三体-3.txt")
        #expect(library.loadBooks().count == 3)
    }

    @Test
    func overwritingOnlyHappensWhenExplicitlyRequested() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = makeLibrary(at: directory)

        try library.importBook(fileName: "笔记.txt", content: "旧内容")
        let replaced = try library.importBook(fileName: "笔记.txt", content: "新内容", overwriteExisting: true)

        #expect(replaced.book.fileName == "笔记.txt")
        #expect(replaced.conflictingTitle == nil)
        #expect(try fileContent("笔记.txt", in: directory) == "新内容")
        #expect(library.loadBooks().count == 1)
    }

    @Test
    func emptyContentIsRejectedInsteadOfCreatingAnEmptyBook() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = makeLibrary(at: directory)

        #expect(throws: LibraryManager.LibraryError.self) {
            try library.importBook(fileName: "空.txt", content: "  \n\t ")
        }
        #expect(library.loadBooks().isEmpty)
    }

    // MARK: - 改书名

    @Test
    func renamedTitleSurvivesRelaunchAndKeepsProgress() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = makeLibrary(at: directory)

        let imported = try library.importBook(fileName: "download(3).txt", content: "正文")
        library.saveBookProgress(bookId: imported.book.id, pageIndex: 7, totalPages: 20)

        let renamed = try library.updateBookTitle(book: imported.book, newTitle: "  活着  ")
        #expect(renamed.title == "活着")
        #expect(renamed.fileName == "download(3).txt")

        // 新建一个书库对象，相当于重启 App。
        let relaunched = makeLibrary(at: directory)
        let books = relaunched.loadBooks()
        #expect(books.map(\.title) == ["活着"])
        #expect(books.first?.fileName == "download(3).txt")
        #expect(relaunched.getBookProgress(bookId: "download(3).txt")?.currentPageIndex == 7)
    }

    @Test
    func progressSavedAfterRenameDoesNotLoseTheTitle() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = makeLibrary(at: directory)

        let imported = try library.importBook(fileName: "a.txt", content: "正文")
        _ = try library.updateBookTitle(book: imported.book, newTitle: "改过的名字")
        library.saveBookProgress(bookId: "a.txt", pageIndex: 3, totalPages: 9)
        library.updateLastAccessed(bookId: "a.txt")
        library.saveLastPageContent(bookId: "a.txt", content: "某一页")

        #expect(makeLibrary(at: directory).loadBooks().first?.title == "改过的名字")
    }

    @Test
    func blankTitleAndBuiltInBooksCannotBeRenamed() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = makeLibrary(at: directory, builtInBooks: [.reviewSample])

        let imported = try library.importBook(fileName: "a.txt", content: "正文")
        #expect(throws: LibraryManager.LibraryError.self) {
            try library.updateBookTitle(book: imported.book, newTitle: "   ")
        }

        let builtIn = try #require(library.loadBooks().first { $0.isBuiltIn })
        #expect(throws: LibraryManager.LibraryError.self) {
            try library.updateBookTitle(book: builtIn, newTitle: "新名字")
        }
    }

    @Test
    func deletingABookAlsoForgetsItsCustomTitle() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = makeLibrary(at: directory)

        let imported = try library.importBook(fileName: "a.txt", content: "正文")
        let renamed = try library.updateBookTitle(book: imported.book, newTitle: "改过的名字")

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            library.deleteBook(renamed) { _ in continuation.resume() }
        }
        #expect(library.loadBooks().isEmpty)

        let again = try library.importBook(fileName: "a.txt", content: "另一本同文件名的书")
        #expect(again.book.title == "a")
        #expect(library.loadBooks().first?.title == "a")
    }

    // MARK: - 元数据兼容

    @Test
    func metadataWrittenByOlderVersionsStillLoads() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        // 旧版本的 library.json 只有 progress，没有 titles。
        let legacyJSON = #"{"progress":{"旧书.txt":{"currentPageIndex":41,"totalPages":90}}}"#
        try Data(legacyJSON.utf8).write(to: directory.appendingPathComponent("library.json"))
        try "旧书正文".write(to: directory.appendingPathComponent("旧书.txt"), atomically: true, encoding: .utf8)

        let library = makeLibrary(at: directory)
        let book = try #require(library.loadBooks().first)
        #expect(book.title == "旧书")
        #expect(library.getBookProgress(bookId: "旧书.txt")?.currentPageIndex == 41)

        _ = try library.updateBookTitle(book: book, newTitle: "新名字")
        #expect(library.getBookProgress(bookId: "旧书.txt")?.currentPageIndex == 41)
        #expect(makeLibrary(at: directory).loadBooks().first?.title == "新名字")
    }

    @Test
    func unreadableMetadataIsBackedUpBeforeBeingReplaced() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let broken = Data("这不是 JSON".utf8)
        try broken.write(to: directory.appendingPathComponent("library.json"))

        let library = makeLibrary(at: directory)
        library.saveBookProgress(bookId: "a.txt", pageIndex: 1, totalPages: 2)

        let backup = directory.appendingPathComponent("library.unreadable.json")
        #expect(try Data(contentsOf: backup) == broken)
        #expect(library.getBookProgress(bookId: "a.txt")?.currentPageIndex == 1)
    }

    // MARK: - 文件名

    @Test
    func importFileNamesAreSafeAndKeepARecognizedExtension() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = makeLibrary(at: directory)

        #expect(library.normalizedImportFileName("三体.txt") == "三体.txt")
        #expect(library.normalizedImportFileName("笔记.MD") == "笔记.md")
        // 名字里的点不是扩展名，书架只认 txt / md。
        #expect(library.normalizedImportFileName("第1.5章") == "第1.5章.txt")
        #expect(library.normalizedImportFileName("报告.docx") == "报告.docx.txt")
        #expect(library.normalizedImportFileName("a:b?c.txt") == "a_b_c.txt")

        let longName = String(repeating: "很长的书名", count: 40) + ".txt"
        let normalized = library.normalizedImportFileName(longName)
        #expect(normalized.hasSuffix(".txt"))
        #expect(normalized.utf8.count <= 184)

        let imported = try library.importBook(fileName: longName, content: "正文")
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent(imported.book.fileName).path))
        #expect(library.loadBooks().count == 1)
    }

    // MARK: - 编码

    @Test
    func importingAGBKFileFromDiskStoresReadableText() throws {
        let directory = try makeTemporaryDirectory()
        let sourceDirectory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: sourceDirectory)
        }
        let library = makeLibrary(at: directory)

        let text = "第一章 风雪山神庙\n话说林冲……"
        let sourceURL = sourceDirectory.appendingPathComponent("水浒传.txt")
        try #require(text.data(using: .gb_18030_2000)).write(to: sourceURL)

        let imported = try library.importBookFromURL(sourceURL)

        #expect(imported.book.title == "水浒传")
        #expect(try fileContent(imported.book.fileName, in: directory) == text)
    }

    @Test
    func importingABinaryFileFailsWithAReadableReason() throws {
        let directory = try makeTemporaryDirectory()
        let sourceDirectory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: sourceDirectory)
        }
        let library = makeLibrary(at: directory)

        let sourceURL = sourceDirectory.appendingPathComponent("图片.txt")
        try Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x00, 0xFF, 0xD8, 0x00, 0x10]).write(to: sourceURL)

        do {
            _ = try library.importBookFromURL(sourceURL)
            Issue.record("二进制文件不应该被当成书导入")
        } catch let error as LibraryManager.LibraryError {
            #expect(ContentViewModel.importFailureMessage(for: error).contains("无法识别文件编码"))
        }
        #expect(library.loadBooks().isEmpty)
    }
}
