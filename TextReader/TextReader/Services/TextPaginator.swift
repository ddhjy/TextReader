import Foundation

class TextPaginator {
    /// Splits text into pages based on character count.
    /// - Parameters:
    ///   - text: The text content to paginate
    ///   - maxPageSize: Maximum number of characters per page (default: 100)
    /// - Returns: Array of string pages
    func paginate(text: String, maxPageSize: Int = 100) -> [String] { // Default kept for consistency, maybe make configurable later
        print("Paginating text...")
        var sentences = [String]()
        var currentSentence = ""
        
        // Use String.enumerateSubstrings for more robust sentence splitting
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.bySentences, .localized]) { substring, _, _, _ in
            if let sentence = substring {
                sentences.append(sentence.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        
        // Handle case where enumeration finds no sentences (e.g., no punctuation)
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
                // Handle very long sentences by splitting them across multiple pages
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
                // Add sentence to the current page
                if !currentPageContent.isEmpty {
                    // Add spacing between sentences
                    currentPageContent += " "
                    currentPageCharCount += 1
                }
                currentPageContent += sentence
                currentPageCharCount += sentenceCharCount
            } else {
                // Current page is full, start a new page
                if !currentPageContent.isEmpty {
                    pages.append(currentPageContent)
                }
                currentPageContent = sentence
                currentPageCharCount = sentenceCharCount
            }
        }

        // Add the last page if it has content
        if !currentPageContent.isEmpty {
            pages.append(currentPageContent)
        }
        
        print("Pagination complete. \(pages.count) pages.")
        return pages.isEmpty ? ["无内容"] : pages // Ensure there's always at least one element for the UI
    }
} 