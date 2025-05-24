import Foundation

/// 文本分页器，负责将长文本分割成适合阅读的页面
class TextPaginator {
    /// 根据字符数将文本分割成页面
    /// - Parameters:
    ///   - text: 要分页的文本
    ///   - maxPageSize: 每页最大字符数
    /// - Returns: 分页后的字符串数组
    func paginate(text: String, maxPageSize: Int = 100) -> [String] {
        print("开始分页...")
        var sentences = [String]()
        
        // 使用String.enumerateSubstrings进行更可靠的句子分割
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.bySentences, .localized]) { substring, _, _, _ in
            if let sentence = substring {
                sentences.append(sentence.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        
        // 处理枚举未找到句子的情况（例如，没有标点符号）
        if sentences.isEmpty && !text.isEmpty {
            sentences = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }

        var pages = [String]()
        var currentPageContent = ""
        var currentPageCharCount = 0

        for sentence in sentences {
            guard !sentence.isEmpty else { continue }
            let sentenceCharCount = sentence.count

            if sentenceCharCount > maxPageSize {
                // 处理非常长的句子，将其拆分到多个页面
                if !currentPageContent.isEmpty {
                    pages.append(currentPageContent)
                    currentPageContent = ""
                    currentPageCharCount = 0
                }
                
                var remainingSentence = sentence
                while remainingSentence.count > maxPageSize {
                    let splitIndex = remainingSentence.index(remainingSentence.startIndex, offsetBy: maxPageSize)
                    pages.append(String(remainingSentence[..<splitIndex]))
                    remainingSentence = String(remainingSentence[splitIndex...])
                }
                if !remainingSentence.isEmpty {
                    pages.append(remainingSentence)
                }

            } else if currentPageCharCount + sentenceCharCount <= maxPageSize {
                // 将句子添加到当前页面
                if !currentPageContent.isEmpty {
                    // 在句子之间添加空格
                    currentPageContent += " "
                    currentPageCharCount += 1
                }
                currentPageContent += sentence
                currentPageCharCount += sentenceCharCount
            } else {
                // 当前页面已满，开始新页面
                if !currentPageContent.isEmpty {
                    pages.append(currentPageContent)
                }
                currentPageContent = sentence
                currentPageCharCount = sentenceCharCount
            }
        }

        // 如果最后一页有内容，则添加
        if !currentPageContent.isEmpty {
            pages.append(currentPageContent)
        }
        
        print("分页完成，共 \(pages.count) 页。")
        return pages.isEmpty ? ["无内容"] : pages // 确保UI至少有一个元素
    }
} 