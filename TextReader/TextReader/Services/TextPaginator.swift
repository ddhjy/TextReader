import Foundation

/// 将整本书文本切分为「页」。
///
/// 设计目标（生产级）：
/// - 保留段落结构：段落之间以空行（`\n\n`）分隔，绝不把多段落揉成连续一坨。
/// - 中文友好：句子之间不再插入半角空格，完全保留原文字符（旧实现会在每两句之间
///   插入一个空格，导致中文排版被污染、朗读韵律异常）。
/// - 边界安全：优先在句末标点处断页；必须硬切超长无标点串时，回退到最近的空格 /
///   中日韩字符边界，避免把英文单词、数字、URL 从中间切断（如 `PayPal` 被切成 `Pay`+`Pal`）。
/// - 线性性能：对每个段落仅做一次字符化与单次遍历，避免旧实现里反复创建子串
///   （`String(remaining[index...])`）在超长句子上造成的 O(n²) 退化。
/// - 稳定可测：纯函数、无副作用、无调试日志。
///
/// 注意：`paginate(text:maxPageSize:)` 的方法签名需保持稳定，测试中存在子类覆写。
class TextPaginator {

    /// 每页目标最大字符数（按 Swift `Character`/字素簇计）。
    ///
    /// 取值兼顾三方面：单屏可读性（本 App 为聚焦卡片式阅读、单页不可滚动）、单页朗读
    /// 时长（每页对应一次 TTS 朗读单元）、以及总页数 / 进度条精度。旧值 100 偏小，
    /// 会让长书页数爆炸（出现过上万页）。调用方可按需覆盖该值。
    static let defaultMaxPageSize = 200

    func paginate(text: String, maxPageSize: Int = TextPaginator.defaultMaxPageSize) -> [String] {
        let pageLimit = max(1, maxPageSize)
        let paragraphs = Self.splitIntoParagraphs(text)
        guard !paragraphs.isEmpty else { return ["无内容"] }

        var pages: [String] = []
        var current = ""
        var currentCount = 0

        func flushCurrent() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { pages.append(trimmed) }
            current = ""
            currentCount = 0
        }

        // 把一个（已确认超过页上限的）段落拆成若干页：除最后一块外直接成页，
        // 末块留作 `current` 以便后续短段落继续拼接，提升装箱利用率。
        func appendSplitParagraph(_ paragraph: String) {
            let chunks = Self.splitLongParagraph(paragraph, pageLimit: pageLimit)
            for chunk in chunks.dropLast() { pages.append(chunk) }
            if let tail = chunks.last {
                current = tail
                currentCount = tail.count
            }
        }

        for paragraph in paragraphs {
            let paraCount = paragraph.count

            if currentCount == 0 {
                if paraCount <= pageLimit {
                    current = paragraph
                    currentCount = paraCount
                } else {
                    appendSplitParagraph(paragraph)
                }
                continue
            }

            // 当前页已有内容：优先把整段接到当前页（用空行分隔，保留段落结构）。
            let separatorCount = 2 // "\n\n"
            if currentCount + separatorCount + paraCount <= pageLimit {
                current += "\n\n" + paragraph
                currentCount += separatorCount + paraCount
            } else {
                flushCurrent()
                if paraCount <= pageLimit {
                    current = paragraph
                    currentCount = paraCount
                } else {
                    appendSplitParagraph(paragraph)
                }
            }
        }

        flushCurrent()
        return pages.isEmpty ? ["无内容"] : pages
    }

    // MARK: - 段落切分

    /// 按空行把文本切成段落；段落内部的单换行予以保留，行尾空白被清理。
    private static func splitIntoParagraphs(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }

        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var paragraphs: [String] = []
        var buffer: [String] = []

        func flushParagraph() {
            guard !buffer.isEmpty else { return }
            let joined = buffer.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { paragraphs.append(joined) }
            buffer.removeAll(keepingCapacity: true)
        }

        for rawLine in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            if rawLine.allSatisfy({ $0 == " " || $0 == "\t" }) {
                // 空行（或纯空白行）→ 段落分隔
                flushParagraph()
            } else {
                var line = String(rawLine)
                while let last = line.last, last == " " || last == "\t" {
                    line.removeLast()
                }
                buffer.append(line)
            }
        }
        flushParagraph()
        return paragraphs
    }

    // MARK: - 超长段落切分

    /// 把单个超过页上限的段落，按「句子优先、软边界其次、硬切兜底」拆成多页。
    /// 返回的每一块都已去除首尾空白，且长度均不超过 `pageLimit`。
    private static func splitLongParagraph(_ paragraph: String, pageLimit: Int) -> [String] {
        let sentences = scanSentences(paragraph)
        var chunks: [String] = []
        var current = ""
        var currentCount = 0

        func flush() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { chunks.append(trimmed) }
            current = ""
            currentCount = 0
        }

        for sentence in sentences {
            let sentenceCount = sentence.count

            if sentenceCount > pageLimit {
                // 单句仍超限：必须硬切，但尽量落在安全边界。
                flush()
                let pieces = hardSplit(sentence, pageLimit: pageLimit)
                for piece in pieces.dropLast() {
                    let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { chunks.append(trimmed) }
                }
                if let tail = pieces.last {
                    current = tail
                    currentCount = tail.count
                }
            } else if currentCount + sentenceCount <= pageLimit {
                current += sentence
                currentCount += sentenceCount
            } else {
                flush()
                current = sentence
                currentCount = sentenceCount
            }
        }

        flush()
        if chunks.isEmpty {
            let fallback = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            return fallback.isEmpty ? [] : [fallback]
        }
        return chunks
    }

    /// 将段落扫描为「句子」序列：完整覆盖原文、不丢字符、不新增字符。
    /// 断句点为中文/英文句末标点（含其后的成对收尾符号与尾随空格）以及换行。
    private static func scanSentences(_ paragraph: String) -> [String] {
        let chars = Array(paragraph)
        let n = chars.count
        guard n > 0 else { return [] }

        var result: [String] = []
        var start = 0
        var i = 0

        while i < n {
            if isSentenceTerminator(chars, i) {
                var j = i + 1
                while j < n && isClosingPunctuation(chars[j]) { j += 1 }
                while j < n && (chars[j] == " " || chars[j] == "\t") { j += 1 }
                result.append(String(chars[start..<j]))
                start = j
                i = j
            } else if chars[i] == "\n" {
                let j = i + 1
                result.append(String(chars[start..<j]))
                start = j
                i = j
            } else {
                i += 1
            }
        }

        if start < n { result.append(String(chars[start..<n])) }
        return result
    }

    /// 对没有可用断句点的超长串做硬切：在 `[start, start+limit)` 内回退到最近的空格 /
    /// 制表 / 换行 / 中日韩字符边界，避免切断英文单词或数字；找不到才在上限处硬切。
    private static func hardSplit(_ sentence: String, pageLimit: Int) -> [String] {
        let chars = Array(sentence)
        let n = chars.count
        guard n > pageLimit else { return [sentence] }

        var pieces: [String] = []
        var start = 0

        while n - start > pageLimit {
            let limit = start + pageLimit
            var cut = limit - 1
            var k = limit - 1
            while k > start {
                let c = chars[k]
                if c == " " || c == "\t" || c == "\n" || isCJK(c) {
                    cut = k
                    break
                }
                k -= 1
            }
            pieces.append(String(chars[start...cut]))
            start = cut + 1
        }

        if start < n { pieces.append(String(chars[start..<n])) }
        return pieces
    }

    // MARK: - 字符分类

    private static let cjkTerminators: Set<Character> = ["。", "！", "？", "…", "；"]
    private static let asciiTerminators: Set<Character> = [".", "!", "?", ";"]
    private static let closingPunctuation: Set<Character> = [
        "”", "’", "）", "》", "】", "」", "』", "〕", "〉",
        "\"", "'", ")", "]", "}"
    ]

    private static func isSentenceTerminator(_ chars: [Character], _ i: Int) -> Bool {
        let c = chars[i]
        if cjkTerminators.contains(c) { return true }
        if asciiTerminators.contains(c) {
            // ASCII 句点等仅在其后为空白/换行/文末时才视为句末，
            // 避免误切 "3.07"、"U.S."、"Web2.0" 这类内部点号。
            let next: Character = (i + 1 < chars.count) ? chars[i + 1] : " "
            return next == " " || next == "\n" || next == "\t"
        }
        return false
    }

    private static func isClosingPunctuation(_ c: Character) -> Bool {
        closingPunctuation.contains(c)
    }

    /// 判断是否为「可在其后断行」的中日韩字符（含中日韩标点 / 全角符号 / 假名 / 谚文）。
    private static func isCJK(_ c: Character) -> Bool {
        guard let scalar = c.unicodeScalars.first else { return false }
        let v = scalar.value
        return (0x4E00...0x9FFF).contains(v)   // CJK 统一表意文字
            || (0x3400...0x4DBF).contains(v)   // 扩展 A
            || (0xF900...0xFAFF).contains(v)   // 兼容表意文字
            || (0x3040...0x30FF).contains(v)   // 平假名 / 片假名
            || (0x3000...0x303F).contains(v)   // 中日韩符号与标点
            || (0xFF00...0xFFEF).contains(v)   // 全角 ASCII / 半角片假名
            || (0xAC00...0xD7AF).contains(v)   // 谚文音节
    }
}
