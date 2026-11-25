import UIKit

/// 阅读区的字号，以及「这个字号下一页放多少字才不会超出一屏」。
///
/// 阅读区是聚焦卡片式的：当前页居中、不能在页内滚动，所以一页必须整页放得进屏幕。
/// 字号跟随系统「文字大小」放大后，200 字一页会高出屏幕，首尾几行被裁掉看不到，
/// 因此字号变大时每页的字数要跟着变少。
enum ReaderTypography {
    static let baseFontSize: CGFloat = 19
    /// 正文字号上限。再大时一行只剩六七个字，断行太碎，反而更难读。
    static let maxFontSize: CGFloat = 40
    static let kerning: CGFloat = 0.3
    static let lineSpacing: CGFloat = 8

    /// 估算用的参考阅读区：按支持的最小机型（375×667 pt）取，
    /// 这样算出的每页字数在所有机型上都放得下，而且同一字号下分页结果与机型、横竖屏无关。
    private static let referenceColumnWidth: CGFloat = 335
    private static let referenceUsableHeight: CGFloat = 456
    /// 中文字体（苹方）的行高约为字号的 1.4 倍。
    private static let lineHeightFactor: CGFloat = 1.4
    private static let minimumCharacterLimit = 24
    /// 拉丁字母、数字、半角标点的宽度约为汉字的一半多一点。
    private static let narrowCharacterWidth = 0.6

    struct LineBudget: Equatable {
        let charactersPerLine: Int
        let maxLines: Int
    }

    struct PageLayout: Equatable {
        /// 传给分页器的每页字数上限。
        let characterLimit: Int
        /// 分页后还要满足的行数上限；为 nil 表示不再按行数拆页。
        let lineBudget: LineBudget?

        static let standard = PageLayout(
            characterLimit: TextPaginator.defaultMaxPageSize,
            lineBudget: nil
        )
    }

    static func clampedFontSize(_ scaledFontSize: CGFloat) -> CGFloat {
        min(max(scaledFontSize, 1), maxFontSize)
    }

    /// 系统当前「文字大小」对应的正文字号，与阅读区里 `@ScaledMetric` 得到的值一致。
    static func currentFontSize() -> CGFloat {
        let traits = UITraitCollection(
            preferredContentSizeCategory: UIApplication.shared.preferredContentSizeCategory
        )
        let scaled = UIFontMetrics(forTextStyle: .body).scaledValue(for: baseFontSize, compatibleWith: traits)
        return clampedFontSize(scaled)
    }

    static func pageLayout(forFontSize fontSize: CGFloat) -> PageLayout {
        // 默认及更小的字号沿用一直以来的 200 字分页：已有读者的页码和进度完全不变。
        guard fontSize > baseFontSize + 0.5 else { return .standard }

        let size = clampedFontSize(fontSize)
        let charactersPerLine = max(4, Int(referenceColumnWidth / (size + kerning)))
        let lineAdvance = size * lineHeightFactor + lineSpacing
        let maxLines = max(3, Int(referenceUsableHeight / lineAdvance))
        // 留一行余量：行尾标点避头尾、英文单词不拆开都会让实际行数比「字数 ÷ 每行字数」多一点。
        let fittedLimit = max(minimumCharacterLimit, (maxLines - 1) * charactersPerLine)

        return PageLayout(
            characterLimit: min(TextPaginator.defaultMaxPageSize, fittedLimit),
            lineBudget: LineBudget(charactersPerLine: charactersPerLine, maxLines: maxLines)
        )
    }

    /// 把行数超出一屏的页（多半是很多短段落、每段之间又隔着空行）在段落之间拆开。
    /// 不改动任何文字，只调整在哪里断页。
    static func fit(_ pages: [String], to budget: LineBudget) -> [String] {
        var result: [String] = []
        result.reserveCapacity(pages.count)

        for page in pages {
            if estimatedLineCount(of: page, charactersPerLine: budget.charactersPerLine) <= budget.maxLines {
                result.append(page)
            } else {
                result.append(contentsOf: split(page, budget: budget))
            }
        }
        return result
    }

    static func estimatedLineCount(of text: String, charactersPerLine: Int) -> Int {
        let perLine = Double(max(1, charactersPerLine))
        var lines = 0
        for segment in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let width = segment.reduce(0.0) { $0 + displayWidth(of: $1) }
            lines += max(1, Int((width / perLine).rounded(.up)))
        }
        return lines
    }

    private static func displayWidth(of character: Character) -> Double {
        guard let scalar = character.unicodeScalars.first else { return 1 }
        return scalar.value < 0x1100 ? narrowCharacterWidth : 1
    }

    private static func split(_ page: String, budget: LineBudget) -> [String] {
        var chunks: [String] = []
        var current: [String] = []
        var currentLines = 0

        func flush() {
            guard !current.isEmpty else { return }
            chunks.append(current.joined(separator: "\n\n"))
            current = []
            currentLines = 0
        }

        for paragraph in page.components(separatedBy: "\n\n") {
            guard !paragraph.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let lines = estimatedLineCount(of: paragraph, charactersPerLine: budget.charactersPerLine)

            if lines > budget.maxLines {
                flush()
                chunks.append(contentsOf: splitParagraphByLine(paragraph, budget: budget))
                continue
            }

            // 段落之间的空行也占一行。
            let needed = current.isEmpty ? lines : currentLines + 1 + lines
            if needed > budget.maxLines {
                flush()
                current = [paragraph]
                currentLines = lines
            } else {
                current.append(paragraph)
                currentLines = needed
            }
        }

        flush()
        return chunks.isEmpty ? [page] : chunks
    }

    /// 单个段落内部全是硬换行（诗歌、歌词、逐行排版的文本）时，只能在换行处拆。
    private static func splitParagraphByLine(_ paragraph: String, budget: LineBudget) -> [String] {
        var chunks: [String] = []
        var current: [String] = []
        var currentLines = 0

        func flush() {
            guard !current.isEmpty else { return }
            chunks.append(current.joined(separator: "\n"))
            current = []
            currentLines = 0
        }

        for line in paragraph.split(separator: "\n", omittingEmptySubsequences: true) {
            let lines = estimatedLineCount(of: String(line), charactersPerLine: budget.charactersPerLine)
            if currentLines + lines > budget.maxLines {
                flush()
            }
            current.append(String(line))
            currentLines += lines
        }

        flush()
        return chunks.isEmpty ? [paragraph] : chunks
    }
}
