import Testing
import Foundation
@testable import TextReader

struct TextPaginatorTests {

    private let paginator = TextPaginator()

    private func stripWhitespace(_ s: String) -> String {
        String(s.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) })
    }

    // MARK: - 空 / 退化输入

    @Test
    func emptyTextYieldsPlaceholder() {
        #expect(paginator.paginate(text: "") == ["无内容"])
    }

    @Test
    func whitespaceOnlyTextYieldsPlaceholder() {
        #expect(paginator.paginate(text: "   \n\n\t  \n") == ["无内容"])
    }

    // MARK: - 中文排版：不再插入半角空格

    @Test
    func chineseSentencesAreNotJoinedWithSpaces() {
        let input = "你好世界。今天天气不错。我们去散步吧。"
        let pages = paginator.paginate(text: input, maxPageSize: 100)
        #expect(pages.count == 1)
        #expect(pages[0] == input)
        #expect(!pages[0].contains(" "))
    }

    @Test
    func multiPageChineseHasNoStraySpaces() {
        let input = String(repeating: "这是一段用于测试的中文句子。", count: 40)
        let pages = paginator.paginate(text: input, maxPageSize: 30)
        #expect(pages.count > 1)
        for page in pages {
            #expect(!page.contains(" "))
        }
    }

    // MARK: - 段落结构保留

    @Test
    func paragraphsArePreservedWithBlankLine() {
        let input = "第一段的内容。\n\n第二段的内容。"
        let pages = paginator.paginate(text: input, maxPageSize: 100)
        #expect(pages.count == 1)
        #expect(pages[0].contains("\n\n"))
        #expect(pages[0] == "第一段的内容。\n\n第二段的内容。")
    }

    @Test
    func shortChapterTitleMergesWithFollowingParagraph() {
        let input = "第一章\n\n正文开始的内容在这里。"
        let pages = paginator.paginate(text: input, maxPageSize: 100)
        #expect(pages.count == 1)
        #expect(pages[0].contains("第一章"))
        #expect(pages[0].contains("正文开始"))
    }

    // MARK: - 断页边界：句末优先

    @Test
    func breaksPreferSentenceBoundaries() {
        let input = "一二三。四五六。七八九。"
        let pages = paginator.paginate(text: input, maxPageSize: 4)
        #expect(pages == ["一二三。", "四五六。", "七八九。"])
    }

    @Test
    func everyPageRespectsMaxSize() {
        let input = String(repeating: "测试句子内容甲乙丙丁。", count: 60)
        let maxPageSize = 25
        let pages = paginator.paginate(text: input, maxPageSize: maxPageSize)
        for page in pages {
            #expect(page.count <= maxPageSize)
        }
    }

    // MARK: - 英文 / 数字不被从中间切断

    @Test
    func latinWordsAreNotSplitMidWord() {
        let pages = paginator.paginate(text: "Hello world foo", maxPageSize: 8)
        #expect(pages == ["Hello", "world", "foo"])
    }

    @Test
    func asciiDecimalPointIsNotTreatedAsSentenceEnd() {
        let input = "康柏在1999年以3.07亿美元的价格收购了这家公司。"
        let pages = paginator.paginate(text: input, maxPageSize: 100)
        #expect(pages.count == 1)
        #expect(pages[0].contains("3.07"))
    }

    // MARK: - 字符完整性：不丢字符、不新增字符（空白除外）

    @Test
    func paginationPreservesAllNonWhitespaceCharacters() {
        let input = """
        第一章

        他在1995年创立Zip2，后来以3.07亿美元卖给Compaq，赚到了第一桶金。

        接着他把钱投入 PayPal、SpaceX 和 Tesla 这些公司。失败的风险极高。
        """
        for maxPageSize in [8, 17, 50, 200] {
            let pages = paginator.paginate(text: input, maxPageSize: maxPageSize)
            let recombined = pages.map(stripWhitespace).joined()
            #expect(recombined == stripWhitespace(input))
            for page in pages {
                #expect(page.count <= maxPageSize)
            }
        }
    }

    // MARK: - 大输入：稳定且线性（不应退化/卡死）

    @Test
    func largeInputIsHandledEfficiently() {
        let paragraph = "这是用于压力测试的一段中文文本，包含标点、数字123以及英文单词example。"
        let input = String(repeating: paragraph + "\n\n", count: 1_500) // ~5 万字符量级
        let maxPageSize = 200

        let start = Date()
        let pages = paginator.paginate(text: input, maxPageSize: maxPageSize)
        let elapsed = Date().timeIntervalSince(start)

        #expect(pages.count > 1)
        #expect(pages.allSatisfy { $0.count <= maxPageSize })
        #expect(stripWhitespace(pages.map(stripWhitespace).joined()) == stripWhitespace(input))
        // 线性算法应在很短时间内完成；给一个宽松上限以避免 CI 抖动误报。
        #expect(elapsed < 5.0)
    }
}
