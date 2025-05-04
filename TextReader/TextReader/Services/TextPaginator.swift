import Foundation

class TextPaginator {
    // Keep the existing logic, but encapsulated
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
        
        if sentences.isEmpty && !text.isEmpty { // Handle case where enumeration finds no sentences (e.g., no punctuation)
            sentences = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }


        var pages = [String]()
        var currentPageContent = ""
        var currentPageCharCount = 0

        for sentence in sentences {
            guard !sentence.isEmpty else { continue }
            let sentenceCharCount = sentence.count

            if sentenceCharCount > maxPageSize {
                // If a single sentence is too long, add the current page (if any) and then add the long sentence as its own page(s)
                if !currentPageContent.isEmpty {
                    pages.append(currentPageContent)
                    currentPageContent = ""
                    currentPageCharCount = 0
                }
                // Simple split for very long sentences (could be improved)
                var remainingSentence = sentence
                while remainingSentence.count > maxPageSize {
                    let splitIndex = remainingSentence.index(remainingSentence.startIndex, offsetBy: maxPageSize)
                    pages.append(String(remainingSentence[..<splitIndex]))
                    remainingSentence = String(remainingSentence[splitIndex...])
                }
                if !remainingSentence.isEmpty {
                    pages.append(remainingSentence) // Add the remainder
                }

            } else if currentPageCharCount + sentenceCharCount <= maxPageSize {
                // Add sentence to the current page
                if !currentPageContent.isEmpty {
                    // Add spacing if needed (consider if sentences already end with space/newline)
                    currentPageContent += " " // Or potentially "\n" depending on desired formatting
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