import Foundation
import Testing
@testable import TextReader

struct ImportedTextDecoderTests {
    private let sample = "第一章\n中文、English 和 123 混排。"

    @Test
    func decodesUTF8WithAndWithoutByteOrderMark() {
        #expect(ImportedTextDecoder.decode(Data(sample.utf8)) == sample)

        var withBOM = Data([0xEF, 0xBB, 0xBF])
        withBOM.append(Data(sample.utf8))
        #expect(ImportedTextDecoder.decode(withBOM) == sample)
    }

    @Test
    func decodesGBKAndGB18030() throws {
        let data = try #require(sample.data(using: .gb_18030_2000))
        #expect(String(data: data, encoding: .utf8) == nil)
        #expect(ImportedTextDecoder.decode(data) == sample)
    }

    @Test
    func decodesUTF16SavedByWindowsNotepad() throws {
        var littleEndian = Data([0xFF, 0xFE])
        littleEndian.append(try #require(sample.data(using: .utf16LittleEndian)))
        #expect(ImportedTextDecoder.decode(littleEndian) == sample)

        var bigEndian = Data([0xFE, 0xFF])
        bigEndian.append(try #require(sample.data(using: .utf16BigEndian)))
        #expect(ImportedTextDecoder.decode(bigEndian) == sample)
    }

    @Test
    func emptyFileIsEmptyTextAndBinaryIsRejected() {
        #expect(ImportedTextDecoder.decode(Data()) == "")
        // PNG 文件头：不是任何一种文本编码，不能硬解成乱码当书读。
        #expect(ImportedTextDecoder.decode(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D])) == nil)
    }
}

struct ReaderTypographyTests {
    @Test
    func defaultFontSizeKeepsTheLongStandingPagination() {
        #expect(ReaderTypography.pageLayout(forFontSize: ReaderTypography.baseFontSize) == .standard)
        #expect(ReaderTypography.pageLayout(forFontSize: 14) == .standard)
        #expect(ReaderTypography.PageLayout.standard.characterLimit == 200)
        #expect(ReaderTypography.PageLayout.standard.lineBudget == nil)
    }

    @Test
    func largerFontsPutFewerCharactersOnAPage() throws {
        var previousLimit = ReaderTypography.PageLayout.standard.characterLimit
        for fontSize in stride(from: CGFloat(21), through: 40, by: 1) {
            let layout = ReaderTypography.pageLayout(forFontSize: fontSize)
            let budget = try #require(layout.lineBudget)

            #expect(layout.characterLimit <= previousLimit)
            #expect(layout.characterLimit >= 24)
            // 一页的字数按「每行字数 × 行数」算下来必须放得进一屏。
            #expect(layout.characterLimit <= budget.charactersPerLine * budget.maxLines)
            previousLimit = layout.characterLimit
        }

        #expect(ReaderTypography.pageLayout(forFontSize: 40).characterLimit < 100)
        // 字号有上限：系统字号调到再大，也按上限来分页。
        #expect(ReaderTypography.pageLayout(forFontSize: 80) == ReaderTypography.pageLayout(forFontSize: 40))
    }

    @Test
    func fontSizeIsClampedToAReadableRange() {
        #expect(ReaderTypography.clampedFontSize(19) == 19)
        #expect(ReaderTypography.clampedFontSize(53) == ReaderTypography.maxFontSize)
        #expect(ReaderTypography.clampedFontSize(0) == 1)
        #expect(ReaderTypography.maxFontSize > 24)
    }

    @Test
    func pagesWithTooManyShortParagraphsAreSplitWithoutChangingText() {
        let budget = ReaderTypography.LineBudget(charactersPerLine: 8, maxLines: 6)
        let paragraphs = (1...9).map { "第\($0)段" }
        let page = paragraphs.joined(separator: "\n\n")

        #expect(ReaderTypography.estimatedLineCount(of: page, charactersPerLine: 8) > budget.maxLines)

        let fitted = ReaderTypography.fit([page], to: budget)
        #expect(fitted.count > 1)
        for piece in fitted {
            #expect(ReaderTypography.estimatedLineCount(of: piece, charactersPerLine: 8) <= budget.maxLines)
        }
        #expect(fitted.joined(separator: "\n\n") == page)
    }

    @Test
    func pagesThatAlreadyFitAreLeftAlone() {
        let budget = ReaderTypography.LineBudget(charactersPerLine: 10, maxLines: 8)
        let pages = ["短短的一页。", "第二页也放得下。\n\n它有两段。"]
        #expect(ReaderTypography.fit(pages, to: budget) == pages)
    }

    @Test
    func aSingleParagraphOfHardLineBreaksIsSplitAtLineBreaks() {
        let budget = ReaderTypography.LineBudget(charactersPerLine: 10, maxLines: 4)
        let lines = (1...10).map { "第\($0)行诗" }
        let poem = lines.joined(separator: "\n")

        let fitted = ReaderTypography.fit([poem], to: budget)
        #expect(fitted.count == 3)
        #expect(fitted.joined(separator: "\n") == poem)
        for piece in fitted {
            #expect(ReaderTypography.estimatedLineCount(of: piece, charactersPerLine: 10) <= budget.maxLines)
        }
    }

    @Test
    func latinTextCountsAsNarrowerThanChinese() {
        #expect(ReaderTypography.estimatedLineCount(of: String(repeating: "字", count: 20), charactersPerLine: 10) == 2)
        #expect(ReaderTypography.estimatedLineCount(of: String(repeating: "a", count: 20), charactersPerLine: 10) == 2)
        #expect(ReaderTypography.estimatedLineCount(of: String(repeating: "a", count: 16), charactersPerLine: 10) == 1)
        #expect(ReaderTypography.estimatedLineCount(of: "一\n\n二", charactersPerLine: 10) == 3)
    }
}

/// 阅读区最下面一段上面浮着「定时停止」这排按钮，很高的页要让开它。
struct ReaderPagePlacementTests {
    private func top(_ pageHeight: CGFloat) -> CGFloat {
        ReaderPagePlacement.focusedPageTop(pageHeight: pageHeight, containerHeight: 500, bottomReserve: 50)
    }

    @Test
    func aPageThatStaysClearOfTheButtonsIsCentered() {
        #expect(top(300) == 100)
        #expect(top(400) == 50)
    }

    @Test
    func aTallPageMovesUpJustEnoughToClearTheButtons() {
        #expect(top(420) == 30)
        #expect(top(420) + 420 == 450)
        #expect(top(450) == 0)
    }

    @Test
    func aPageNeverMovesAboveTheTopEdgeToMakeRoom() {
        #expect(top(480) == 0)
        #expect(top(500) == 0)
    }

    @Test
    func aPageTallerThanTheScreenStaysCentered() {
        #expect(top(600) == -50)
    }

    @Test
    func withoutButtonsEveryPageIsCentered() {
        #expect(ReaderPagePlacement.focusedPageTop(pageHeight: 480, containerHeight: 500, bottomReserve: 0) == 10)
    }
}

struct UserGuideTests {
    /// 内置《使用说明》是新用户看到的第一屏，每一步要单独成页，不能挤成一整屏说明书。
    @Test
    func bundledGuideIsFivePagesOneStepPerPage() throws {
        let url = try #require(Bundle.main.url(forResource: "使用说明", withExtension: "txt"))
        let guide = try String(contentsOf: url, encoding: .utf8)
        let pages = TextPaginator().paginate(text: guide)

        #expect(pages.count == 5)
        #expect(pages[0].hasPrefix("欢迎使用随心读"))
        #expect(pages[1].hasPrefix("第一步：放一本书进来"))
        #expect(pages[2].hasPrefix("第二步：读"))
        #expect(pages[3].hasPrefix("第三步：听"))
        #expect(pages[4].hasPrefix("还可以这样用"))
        #expect(pages.allSatisfy { $0.count <= TextPaginator.defaultMaxPageSize })

        // 说明里的叫法要和界面一致。
        #expect(guide.contains("Wi‑Fi 传书"))
        #expect(!guide.contains("wifi"))
        #expect(!guide.contains("WiFi"))
        #expect(!guide.contains("读书派"))
    }

    @Test
    func readersOfTheOldOnePageGuideStartAtTheFirstPageOfTheNewOne() {
        #expect(ContentViewModel.remapPageIndex(0, oldTotal: 1, newTotal: 5) == 0)
    }
}
