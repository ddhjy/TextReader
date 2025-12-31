import Foundation

class TextPaginator {
    func paginate(text: String, maxPageSize: Int = 100) -> [String] {
        print("开始分页...")
        var sentences = [String]()
        
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.bySentences, .localized]) { substring, _, _, _ in
            if let sentence = substring {
                sentences.append(sentence.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        
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
                if !currentPageContent.isEmpty {
                    currentPageContent += " "
                    currentPageCharCount += 1
                }
                currentPageContent += sentence
                currentPageCharCount += sentenceCharCount
            } else {
                if !currentPageContent.isEmpty {
                    pages.append(currentPageContent)
                }
                currentPageContent = sentence
                currentPageCharCount = sentenceCharCount
            }
        }

        if !currentPageContent.isEmpty {
            pages.append(currentPageContent)
        }
        
        return pages.isEmpty ? ["无内容"] : pages
    }
} 