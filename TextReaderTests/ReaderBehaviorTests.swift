import Foundation
import Testing
@testable import TextReader

/// 阅读器「不让人出错、出了错能回头」的行为。
@MainActor
struct ReaderBehaviorTests {
    // MARK: - 翻页

    @Test
    func turningPastTheEndsStaysPutAndSaysSo() async throws {
        let harness = try ViewModelHarness { try $0.importBook(fileName: "书.txt", content: numberedLines(2)) }
        let viewModel = harness.viewModel
        await harness.waitUntilOpened("书.txt")

        #expect(viewModel.currentPageIndex == 0)
        #expect(!viewModel.turnPage(forward: false))
        #expect(viewModel.currentPageIndex == 0)
        #expect(viewModel.notice?.message == "已经是第一页")
        #expect(viewModel.notice?.kind == .info)

        #expect(viewModel.turnPage(forward: true))
        #expect(viewModel.currentPageIndex == 1)

        #expect(!viewModel.turnPage(forward: true))
        #expect(viewModel.currentPageIndex == 1)
        #expect(viewModel.notice?.message == "已经是最后一页")

        // 锁屏 / 耳机线控翻到头：看不到屏幕，不弹提示。
        viewModel.dismissNotice()
        viewModel.nextPage()
        #expect(viewModel.currentPageIndex == 1)
        #expect(viewModel.notice == nil)
    }

    // MARK: - 回到跳转前的位置

    @Test
    func draggingTheProgressSliderLeavesAWayBack() async throws {
        let harness = try ViewModelHarness { try $0.importBook(fileName: "书.txt", content: numberedLines(10)) }
        let viewModel = harness.viewModel
        await harness.waitUntilOpened("书.txt")

        viewModel.goToPage(3)
        #expect(viewModel.returnPageIndex == nil)

        viewModel.beginProgressScrub()
        viewModel.goToPage(5)
        viewModel.goToPage(8)
        #expect(viewModel.returnPageIndex == nil)
        viewModel.endProgressScrub()
        #expect(viewModel.currentPageIndex == 8)
        #expect(viewModel.returnPageIndex == 3)

        // 没拖准再拖一次：要回的仍然是最初那一页。
        viewModel.beginProgressScrub()
        viewModel.goToPage(9)
        viewModel.endProgressScrub()
        #expect(viewModel.returnPageIndex == 3)

        viewModel.returnToJumpOrigin()
        #expect(viewModel.currentPageIndex == 3)
        // 回去之后入口反过来，点错了还能再回来。
        #expect(viewModel.returnPageIndex == 9)

        viewModel.returnToJumpOrigin()
        #expect(viewModel.currentPageIndex == 9)
        #expect(viewModel.returnPageIndex == 3)
    }

    @Test
    func draggingBackToWhereYouStartedLeavesNoReturnOffer() async throws {
        let harness = try ViewModelHarness { try $0.importBook(fileName: "书.txt", content: numberedLines(10)) }
        let viewModel = harness.viewModel
        await harness.waitUntilOpened("书.txt")

        viewModel.goToPage(4)
        viewModel.beginProgressScrub()
        viewModel.goToPage(7)
        viewModel.goToPage(4)
        viewModel.endProgressScrub()

        #expect(viewModel.returnPageIndex == nil)
    }

    @Test
    func jumpingFromSearchLeavesAWayBackAndClosesSearch() async throws {
        let harness = try ViewModelHarness { library in
            try library.importBook(fileName: "书.txt", content: numberedLines(10))
            try library.importBook(fileName: "另一本.txt", content: numberedLines(3))
        }
        let viewModel = harness.viewModel
        let book = try harness.book("书.txt")
        viewModel.loadBook(book)
        await harness.waitUntilOpened("书.txt")

        viewModel.goToPage(2)
        viewModel.showingSearchView = true
        viewModel.searchContent("第7页")
        #expect(viewModel.searchResults.map { $0.0 } == [6])

        viewModel.jumpToSearchResult(pageIndex: 6)
        #expect(viewModel.currentPageIndex == 6)
        #expect(viewModel.returnPageIndex == 2)
        #expect(!viewModel.showingSearchView)

        // 换了一本书，「回到第 N 页」就没有意义了。
        viewModel.loadBook(try harness.book("另一本.txt"))
        #expect(viewModel.returnPageIndex == nil)
        await harness.waitUntilOpened("另一本.txt")
    }

    // MARK: - 导入

    @Test
    func wifiUploadDoesNotReplaceTheBookBeingRead() async throws {
        let harness = try ViewModelHarness { try $0.importBook(fileName: "正在读.txt", content: numberedLines(5)) }
        let viewModel = harness.viewModel
        await harness.waitUntilOpened("正在读.txt")
        viewModel.goToPage(2)

        let receive = try #require(harness.wiFiTransferService.onFileReceived)

        guard case .saved(let title, let conflictingTitle) = receive("新书.txt", "新书的正文") else {
            Issue.record("第一次上传应该保存成功")
            return
        }
        #expect(title == "新书")
        #expect(conflictingTitle == nil)

        // 一次常常传好几本：正在读的书和读到的位置都不能动，也不另外弹提示（结果在传书页的列表里）。
        #expect(viewModel.currentBookId == "正在读.txt")
        #expect(viewModel.currentPageIndex == 2)
        #expect(viewModel.notice == nil)
        #expect(viewModel.books.contains { $0.fileName == "新书.txt" })

        guard case .saved(let secondTitle, let secondConflict) = receive("新书.txt", "同名的另一本") else {
            Issue.record("同名上传应该另存，而不是失败")
            return
        }
        #expect(secondTitle == "新书-2")
        #expect(secondConflict == "新书")
        let firstCopy = harness.documentsDirectory.appendingPathComponent("新书.txt")
        #expect(try String(contentsOf: firstCopy, encoding: .utf8) == "新书的正文")

        guard case .rejected(let reason) = receive("空.txt", "  \n ") else {
            Issue.record("空文件不应该进书架")
            return
        }
        #expect(reason == "文件里没有文字")
        #expect(viewModel.books.count == 3)
        #expect(viewModel.currentBookId == "正在读.txt")
    }

    @Test
    func wifiUploadOpensTheBookWhenOnlyTheGuideIsOpen() async throws {
        let guide = LibraryManager.BuiltInBook.reviewSample
        let harness = try ViewModelHarness(builtInBooks: [guide])
        let viewModel = harness.viewModel
        await harness.waitUntilOpened(guide.fileName)
        #expect(viewModel.hasOnlyBuiltInBooks)

        let receive = try #require(harness.wiFiTransferService.onFileReceived)
        guard case .saved = receive("第一本书.txt", numberedLines(4)) else {
            Issue.record("上传应该保存成功")
            return
        }

        await harness.waitUntilOpened("第一本书.txt")
        #expect(viewModel.currentBookTitle == "第一本书")
        #expect(viewModel.pages.count == 4)
        #expect(!viewModel.hasOnlyBuiltInBooks)
    }

    @Test
    func pastedTextNeedsContentAndGetsItsTitleFromTheFirstLine() async throws {
        let harness = try ViewModelHarness()
        let viewModel = harness.viewModel

        #expect(!viewModel.importPastedText("  \n\t ", title: nil))
        #expect(viewModel.notice?.kind == .error)
        #expect(viewModel.notice?.message == "还没有正文，先粘贴或输入一段文字")
        #expect(viewModel.books.isEmpty)

        #expect(viewModel.importPastedText("一个故事\n很久很久以前", title: ""))
        #expect(viewModel.currentBookId == "一个故事.txt")
        #expect(viewModel.currentBookTitle == "一个故事")
        #expect(viewModel.notice?.kind == .success)
        #expect(viewModel.notice?.message == "已导入《一个故事》")
        await harness.waitUntilOpened("一个故事.txt")

        // 同样的内容再贴一次：另存一本，并且说清楚。
        #expect(viewModel.importPastedText("一个故事\n很久很久以前", title: nil))
        #expect(viewModel.currentBookId == "一个故事-2.txt")
        #expect(viewModel.notice?.message == "书架里已有《一个故事》，新导入的已另存为《一个故事-2》")
        await harness.waitUntilOpened("一个故事-2.txt")

        #expect(viewModel.importPastedText("正文", title: "  我起的名字 "))
        #expect(viewModel.currentBookTitle == "我起的名字")
        await harness.waitUntilOpened("我起的名字.txt")
        #expect(viewModel.books.count == 3)
    }

    @Test
    func importingAFileReportsSuccessConflictAndFailure() async throws {
        let harness = try ViewModelHarness()
        let viewModel = harness.viewModel
        let sourceDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: sourceDirectory) }

        let textURL = sourceDirectory.appendingPathComponent("讲义.txt")
        try numberedLines(3).write(to: textURL, atomically: true, encoding: .utf8)
        let binaryURL = sourceDirectory.appendingPathComponent("照片.txt")
        try Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00]).write(to: binaryURL)

        viewModel.importBookFromURL(textURL, source: .filePicker)
        await harness.waitUntilOpened("讲义.txt")
        #expect(viewModel.notice?.kind == .success)
        #expect(viewModel.notice?.message == "已导入《讲义》")

        viewModel.importBookFromURL(textURL, source: .filePicker)
        await harness.waitUntilOpened("讲义-2.txt")
        #expect(viewModel.notice?.message == "书架里已有《讲义》，新导入的已另存为《讲义-2》")
        #expect(viewModel.books.count == 2)

        viewModel.importBookFromURL(binaryURL, source: .filePicker)
        await waitOnMain { viewModel.notice?.kind == .error }
        #expect(viewModel.notice?.message == "导入失败：无法识别文件编码，请另存为 UTF‑8 或 GBK 后再试")
        #expect(viewModel.books.count == 2)
        #expect(viewModel.currentBookId == "讲义-2.txt")
    }

    @Test
    func aBookThatCannotBeReadShowsANoticeNotFakeText() async throws {
        let harness = try ViewModelHarness { library in
            // 没经过导入、直接放进文档目录的 GBK 文件：按 UTF‑8 读不出来。
            let url = try library.getDocumentsDirectory().appendingPathComponent("外来文件.txt")
            try #require("这是一份 GBK 编码的文本".data(using: .gb_18030_2000)).write(to: url)
        }
        let viewModel = harness.viewModel

        await waitOnMain { viewModel.isContentLoaded && viewModel.notice != nil }

        #expect(viewModel.currentBookId == "外来文件.txt")
        #expect(viewModel.pages.isEmpty)
        #expect(viewModel.notice?.kind == .error)
        #expect(viewModel.notice?.message == "《外来文件》的内容没能读出来，请稍后再试")
        // 没有正文可读时，播放键不应该念出一句错误提示。
        viewModel.readCurrentPage()
        #expect(harness.speechManager.startedTexts.isEmpty)
    }

    // MARK: - 改名、改正文

    @Test
    func renamingAndEditingKeepTheReadingPosition() async throws {
        let harness = try ViewModelHarness { try $0.importBook(fileName: "长文.txt", content: numberedLines(10)) }
        let viewModel = harness.viewModel
        await harness.waitUntilOpened("长文.txt")
        viewModel.goToPage(5)
        let book = try harness.book("长文.txt")

        #expect(!viewModel.updateBookTitle(book: book, newTitle: "   "))
        #expect(viewModel.currentBookTitle == "长文")

        #expect(viewModel.updateBookTitle(book: book, newTitle: "新名字"))
        #expect(viewModel.currentBookTitle == "新名字")
        #expect(viewModel.books.first?.title == "新名字")
        #expect(viewModel.currentPageIndex == 5)
        // 重启后书名还在。
        #expect(harness.libraryManager.loadBooks().first?.title == "新名字")

        var saved: Bool?
        viewModel.updateBookContent(book: book, newContent: numberedLines(30, prefix: "新第")) { saved = $0 }
        await waitOnMain { saved != nil }

        #expect(saved == true)
        #expect(viewModel.pages.count == 30)
        #expect(viewModel.pages.first == "新第1页")
        // 原来在 10 页里的第 6 页（55%），改完后停在 30 页里相近的位置，而不是被送回第 1 页。
        #expect(viewModel.currentPageIndex == 16)
        #expect(viewModel.currentBookTitle == "新名字")
    }

    @Test
    func editingABookThatIsNotOpenLeavesTheOpenOneAlone() async throws {
        let harness = try ViewModelHarness { library in
            try library.importBook(fileName: "甲.txt", content: numberedLines(6))
            try library.importBook(fileName: "乙.txt", content: numberedLines(6))
        }
        let viewModel = harness.viewModel
        viewModel.loadBook(try harness.book("甲.txt"))
        await harness.waitUntilOpened("甲.txt")
        viewModel.goToPage(3)

        var saved: Bool?
        viewModel.updateBookContent(book: try harness.book("乙.txt"), newContent: numberedLines(2)) { saved = $0 }
        await waitOnMain { saved != nil }

        #expect(saved == true)
        #expect(viewModel.currentBookId == "甲.txt")
        #expect(viewModel.currentPageIndex == 3)
        #expect(viewModel.pages.count == 6)
    }

    // MARK: - 删除

    @Test
    func deletingTheOpenBookSaysWhichBookIsOpenNow() async throws {
        let guide = LibraryManager.BuiltInBook.reviewSample
        let harness = try ViewModelHarness(builtInBooks: [guide]) {
            try $0.importBook(fileName: "我的书.txt", content: numberedLines(3))
        }
        let viewModel = harness.viewModel
        let mine = try harness.book("我的书.txt")
        let builtIn = try harness.book(guide.fileName)
        viewModel.loadBook(mine)
        await harness.waitUntilOpened("我的书.txt")

        // 内置的使用说明删不掉：单独删它什么都不发生。
        viewModel.deleteBook(builtIn)
        #expect(viewModel.books.count == 2)
        #expect(viewModel.notice == nil)

        viewModel.deleteBooks([mine, builtIn])
        await harness.waitUntilOpened(guide.fileName)

        #expect(viewModel.books.map(\.fileName) == [guide.fileName])
        #expect(viewModel.notice?.kind == .info)
        #expect(viewModel.notice?.message == "已删除《我的书》，现在打开的是《\(guide.title)》")
        #expect(!FileManager.default.fileExists(atPath: harness.documentsDirectory.appendingPathComponent("我的书.txt").path))
    }

    @Test
    func deletingTheLastBookLeavesAnEmptyReaderNotAStalePage() async throws {
        let harness = try ViewModelHarness { try $0.importBook(fileName: "唯一的书.txt", content: numberedLines(3)) }
        let viewModel = harness.viewModel
        await harness.waitUntilOpened("唯一的书.txt")

        viewModel.deleteBook(try harness.book("唯一的书.txt"))
        await waitOnMain { viewModel.books.isEmpty }

        #expect(viewModel.currentBookId == nil)
        #expect(viewModel.pages.isEmpty)
        #expect(viewModel.currentBookTitle == ContentViewModel.appDisplayName)
        #expect(viewModel.hasOnlyBuiltInBooks)
    }

    // MARK: - 书架进度

    @Test
    func shelfShowsTheLivePositionOfTheOpenBook() async throws {
        let harness = try ViewModelHarness { try $0.importBook(fileName: "书.txt", content: numberedLines(10)) }
        let viewModel = harness.viewModel
        await harness.waitUntilOpened("书.txt")
        let book = try harness.book("书.txt")

        #expect(viewModel.getBookProgressDisplay(book: book) == "10%")
        viewModel.goToPage(4)
        // 不用等进度落盘，书架上立刻就是新的数字。
        #expect(viewModel.getBookProgressDisplay(book: book) == "50%")
        viewModel.goToPage(9)
        #expect(viewModel.getBookProgressDisplay(book: book) == "100%")
    }

    // MARK: - 定时与播放键

    @Test
    func pausingKeepsTheSleepTimerAndCancellingItKeepsReading() async throws {
        let harness = try ViewModelHarness { try $0.importBook(fileName: "书.txt", content: numberedLines(3)) }
        let viewModel = harness.viewModel
        await harness.waitUntilOpened("书.txt")

        viewModel.startSleepTimer(minutes: 15)
        #expect(viewModel.isReading)
        #expect(viewModel.sleepTimerActive)
        #expect(harness.speechManager.startedTexts == ["第1页"])

        // 点播放键只是暂停，定时不会被悄悄取消。
        viewModel.handlePlayButtonTap()
        #expect(!viewModel.isReading)
        #expect(viewModel.sleepTimerActive)
        #expect(viewModel.sleepTimerRemainingMinutes == 15)

        await waitOnMain { !viewModel.isSwitchingPlayState }
        viewModel.handlePlayButtonTap()
        #expect(viewModel.isReading)
        #expect(viewModel.sleepTimerActive)

        // 关掉定时只关定时，朗读照常继续。
        viewModel.cancelSleepTimer()
        #expect(!viewModel.sleepTimerActive)
        #expect(viewModel.isReading)
        #expect(viewModel.sleepTimerRemainingMinutes == 0)

        viewModel.stopReading()
    }

    // MARK: - 选词与模板

    @Test
    func pageVariableCoversThePreviousCurrentAndNextPage() async throws {
        let harness = try ViewModelHarness { try $0.importBook(fileName: "书.txt", content: numberedLines(5)) }
        let viewModel = harness.viewModel
        await harness.waitUntilOpened("书.txt")

        let template = PromptTemplate(name: "测试", content: "《{book}》选中：{selection}｜{page}")
        let separator = "\n\n---\n\n"

        #expect(viewModel.buildPrompt(using: template) == "《书》选中：｜第1页\(separator)第2页")

        viewModel.goToPage(2)
        viewModel.tokens = [Token(value: "第"), Token(value: "3"), Token(value: "页")]
        viewModel.processTokenTap(tappedTokenID: viewModel.tokens[0].id)
        viewModel.processTokenTap(tappedTokenID: viewModel.tokens[2].id)
        #expect(viewModel.selectedTokenText == "第3页")
        #expect(viewModel.buildPrompt(using: template)
                == "《书》选中：第3页｜第2页\(separator)第3页\(separator)第4页")

        viewModel.clearSelectedTokens()
        #expect(viewModel.selectedTokenIDs.isEmpty)
        #expect(viewModel.selectionAnchorTokenID == nil)

        viewModel.goToPage(4)
        #expect(viewModel.buildPrompt(using: template) == "《书》选中：｜第4页\(separator)第5页")
    }

    @Test
    func templateChangesAreSaved() async throws {
        let harness = try ViewModelHarness()
        let viewModel = harness.viewModel
        func stored() -> [PromptTemplate] {
            TemplateManager(fileManager: .default, documentsDirectoryProvider: { harness.documentsDirectory }).load()
        }

        #expect(viewModel.templates.count == 2)

        var template = PromptTemplate(name: "解释", content: "解释：{selection}", destination: .copyOnly)
        viewModel.addTemplate(template)
        #expect(stored().count == 3)

        template.destination = .perplexity
        template.name = "查一下"
        viewModel.updateTemplate(template)
        #expect(stored().last == template)

        viewModel.deleteTemplate(template)
        #expect(viewModel.templates.count == 2)
        #expect(stored().count == 2)
    }

    @Test
    func aTemplateChangeThatCannotBeSavedSaysSo() throws {
        let harness = try ViewModelHarness()
        let viewModel = harness.viewModel
        #expect(viewModel.notice == nil)

        // 把模板文件换成一个装着东西的文件夹：之后怎么写都写不进去。
        let templateFile = harness.documentsDirectory.appendingPathComponent("templates.json")
        try FileManager.default.removeItem(at: templateFile)
        try FileManager.default.createDirectory(at: templateFile, withIntermediateDirectories: true)
        try Data("占位".utf8).write(to: templateFile.appendingPathComponent("占位.txt"))

        viewModel.addTemplate(PromptTemplate(name: "解释", content: "解释：{selection}", destination: .copyOnly))

        // 这一次打开期间照常能用，但要告诉用户它没存下来。
        #expect(viewModel.templates.count == 3)
        #expect(viewModel.notice?.kind == .error)
        #expect(viewModel.notice?.message == "模板的改动没能保存，下次打开时可能会变回原样")
    }

    // MARK: - 别的 App 发来的链接

    @Test
    func anImportLinkWithNothingToImportSaysSo() throws {
        let harness = try ViewModelHarness()
        let viewModel = harness.viewModel

        viewModel.handleImportedURL(try #require(URL(string: "textreader://import")))
        #expect(viewModel.notice?.kind == .error)
        #expect(viewModel.notice?.message == ContentViewModel.unrecognizedImportLinkMessage)

        viewModel.dismissNotice()
        viewModel.handleImportedURL(try #require(URL(string: "textreader://import?text=")))
        #expect(viewModel.notice?.message == ContentViewModel.unrecognizedImportLinkMessage)
        #expect(viewModel.books.isEmpty)
    }

    @Test
    func aLinkThatOnlyOpensTheAppIsNotAFailure() throws {
        let harness = try ViewModelHarness()
        let viewModel = harness.viewModel

        viewModel.handleImportedURL(try #require(URL(string: "textreader://open")))
        viewModel.handleImportedURL(try #require(URL(string: "https://example.com/book.txt")))
        #expect(viewModel.notice == nil)
        #expect(viewModel.books.isEmpty)
    }

    // MARK: - 换了一批正文

    @Test
    func everyNewBatchOfPagesIsTold() async throws {
        let harness = try ViewModelHarness { library in
            try library.importBook(fileName: "甲.txt", content: numberedLines(4))
            try library.importBook(fileName: "乙.txt", content: numberedLines(4, prefix: "乙"))
        }
        let viewModel = harness.viewModel
        viewModel.loadBook(try harness.book("甲.txt"))
        await harness.waitUntilOpened("甲.txt")

        // 翻页不换正文，阅读区不用重来。
        let whileReading = viewModel.pagesGeneration
        viewModel.goToPage(2)
        #expect(viewModel.pagesGeneration == whileReading)

        // 换书就是换了一批正文。
        viewModel.loadBook(try harness.book("乙.txt"))
        await harness.waitUntilOpened("乙.txt")
        #expect(viewModel.pages.first == "乙1页")
        #expect(viewModel.pagesGeneration != whileReading)
    }

    // MARK: - 提示

    @Test
    func failuresStayUntilDismissedWhileConfirmationsFadeOut() {
        #expect(AppNotice(kind: .error, message: "导入失败").autoDismissDelay == nil)
        #expect(AppNotice(kind: .success, message: "已导入").autoDismissDelay != nil)
        #expect(AppNotice(kind: .info, message: "已经是第一页").autoDismissDelay != nil)
    }

    /// 一句短话 3 秒够看；长句要给够读完的时间，但也不会一直挂着。
    @Test
    func longerConfirmationsStayLonger() throws {
        let short = try #require(AppNotice(kind: .info, message: "已经是第一页").autoDismissDelay)
        let long = try #require(AppNotice(
            kind: .success,
            message: "书架里已有《很长很长的书名》，新导入的已另存为《很长很长的书名-2》"
        ).autoDismissDelay)
        let endless = try #require(AppNotice(
            kind: .info,
            message: String(repeating: "很长的一句话", count: 30)
        ).autoDismissDelay)

        #expect(short == 3)
        #expect(long > 6)
        #expect(endless == 8)
    }

    @Test
    func aNewNoticeReplacesTheOldOneAndCanBeDismissed() throws {
        let harness = try ViewModelHarness()
        let viewModel = harness.viewModel

        viewModel.showNotice("第一条", kind: .info)
        let first = try #require(viewModel.notice)
        viewModel.showNotice("第一条", kind: .info)
        // 同一句话不会重新弹一次。
        #expect(viewModel.notice?.id == first.id)

        viewModel.showNotice("第二条", kind: .error)
        #expect(viewModel.notice?.message == "第二条")
        #expect(viewModel.notice?.id != first.id)

        viewModel.dismissNotice()
        #expect(viewModel.notice == nil)
    }

    @Test
    func aConfirmationOnlyStartsFadingOnceItIsOnScreen() async throws {
        let harness = try ViewModelHarness()
        let viewModel = harness.viewModel

        viewModel.showNotice("已导入《一本书》", kind: .success)
        let raised = try #require(viewModel.notice)
        let lifetime = try #require(raised.autoDismissDelay)

        // 被设置、搜索这类面板盖着、还没显示出来的时候不计时，等多久都还在。
        try await Task.sleep(for: .seconds(lifetime + 0.4))
        #expect(viewModel.notice?.id == raised.id)

        // 显示出来之后才开始计时，到点自己消失。
        viewModel.noticeDidAppear(raised)
        #expect(viewModel.notice?.id == raised.id)
        await waitOnMain(timeout: lifetime + 2) { viewModel.notice == nil }
        #expect(viewModel.notice == nil)
    }
}
