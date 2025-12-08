import Foundation

class SearchService {
    func search(query: String, in pages: [String]) -> [(Int, String)] {
        guard !query.isEmpty else { return [] }
        let lowercasedQuery = query.lowercased()

        return pages.enumerated().compactMap { index, page in
            if page.lowercased().contains(lowercasedQuery) {
                let preview = generatePreview(for: query, in: page)
                return (index, preview)
            }
            return nil
        }
    }

    private func generatePreview(for query: String, in page: String, maxLength: Int = 100) -> String {
        if let range = page.range(of: query, options: .caseInsensitive) {
            let contextPadding = 30
            let start = page.index(range.lowerBound, offsetBy: -contextPadding, limitedBy: page.startIndex) ?? page.startIndex
            let end = page.index(range.upperBound, offsetBy: maxLength - query.count + contextPadding, limitedBy: page.endIndex) ?? page.endIndex
            
            var snippet = String(page[start..<end])
            
            snippet = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
            
            let prefix = start == page.startIndex ? "" : "..."
            let suffix = end == page.endIndex ? "" : "..."
            
            return prefix + snippet + suffix
        }
        
        let previewEnd = page.index(page.startIndex, offsetBy: maxLength, limitedBy: page.endIndex) ?? page.endIndex
        return String(page[page.startIndex..<previewEnd]) + (page.count > maxLength ? "..." : "")
    }

    func pageSummaries(pages: [String],
                       sampleLimit: Int = 100,
                       previewLength: Int = 60) -> [(Int, String)] {
        guard !pages.isEmpty else { return [] }
        let step = max(1, pages.count / sampleLimit)
        
        return stride(from: 0, to: pages.count, by: step).map { index -> (Int, String) in
            let page = pages[index]
            let preview: String
            if page.count <= previewLength {
                preview = page
            } else {
                let endIdx = page.index(page.startIndex,
                                         offsetBy: previewLength,
                                         limitedBy: page.endIndex) ?? page.endIndex
                preview = String(page[..<endIdx]) + "..."
            }
            return (index, preview)
        }
    }
} 