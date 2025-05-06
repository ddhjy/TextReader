import Foundation

class SearchService {
    func search(query: String, in pages: [String]) -> [(Int, String)] {
        guard !query.isEmpty else { return [] }
        let lowercasedQuery = query.lowercased() // Case-insensitive search

        return pages.enumerated().compactMap { index, page in
            if page.lowercased().contains(lowercasedQuery) {
                // Return page index and a preview snippet
                let preview = generatePreview(for: query, in: page)
                return (index, preview)
            }
            return nil
        }
    }

    // Helper to generate a relevant preview snippet (can be enhanced)
    private func generatePreview(for query: String, in page: String, maxLength: Int = 100) -> String {
        if let range = page.range(of: query, options: .caseInsensitive) {
            let start = page.index(range.lowerBound, offsetBy: -20, limitedBy: page.startIndex) ?? page.startIndex
            let end = page.index(range.upperBound, offsetBy: maxLength - query.count, limitedBy: page.endIndex) ?? page.endIndex
            let snippet = String(page[start..<end])
            return (start == page.startIndex ? "" : "...") + snippet + (end == page.endIndex ? "" : "...")
        }
        // Fallback if range not found (shouldn't happen if called after contains check)
        return String(page.prefix(maxLength)) + (page.count > maxLength ? "..." : "")
    }

    // MARK: - Page Summary
    /// 生成分页摘要；至多 sampleLimit 条
    func pageSummaries(pages: [String],
                       sampleLimit: Int = 100,
                       previewLength: Int = 60) -> [(Int, String)] {
        guard !pages.isEmpty else { return [] }
        let step = max(1, pages.count / sampleLimit)
        
        return stride(from: 0, to: pages.count, by: step).map { index -> (Int, String) in
            let page = pages[index]
            // 截取前 previewLength 个可视字符
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