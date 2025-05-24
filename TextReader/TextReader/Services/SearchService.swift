import Foundation

/// 搜索服务，提供文本内容搜索和页面摘要功能
class SearchService {
    /// 在页面数组中搜索指定查询文本
    func search(query: String, in pages: [String]) -> [(Int, String)] {
        guard !query.isEmpty else { return [] }
        let lowercasedQuery = query.lowercased() // 不区分大小写搜索

        return pages.enumerated().compactMap { index, page in
            if page.lowercased().contains(lowercasedQuery) {
                // 返回页面索引和预览片段
                let preview = generatePreview(for: query, in: page)
                return (index, preview)
            }
            return nil
        }
    }

    /// 为匹配的搜索结果生成预览片段
    private func generatePreview(for query: String, in page: String, maxLength: Int = 100) -> String {
        if let range = page.range(of: query, options: .caseInsensitive) {
            // 计算起始位置，确保有足够的上下文
            let contextPadding = 30  // 增加上下文长度
            let start = page.index(range.lowerBound, offsetBy: -contextPadding, limitedBy: page.startIndex) ?? page.startIndex
            let end = page.index(range.upperBound, offsetBy: maxLength - query.count + contextPadding, limitedBy: page.endIndex) ?? page.endIndex
            
            var snippet = String(page[start..<end])
            
            // 清理预览文本，去除多余的空白
            snippet = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // 添加省略号
            let prefix = start == page.startIndex ? "" : "..."
            let suffix = end == page.endIndex ? "" : "..."
            
            return prefix + snippet + suffix
        }
        
        // 如果找不到范围，返回页面开头的文本
        let previewEnd = page.index(page.startIndex, offsetBy: maxLength, limitedBy: page.endIndex) ?? page.endIndex
        return String(page[page.startIndex..<previewEnd]) + (page.count > maxLength ? "..." : "")
    }

    // MARK: - 页面摘要
    /// 生成分页摘要，用于页面概览
    func pageSummaries(pages: [String],
                       sampleLimit: Int = 100,
                       previewLength: Int = 60) -> [(Int, String)] {
        guard !pages.isEmpty else { return [] }
        let step = max(1, pages.count / sampleLimit)
        
        return stride(from: 0, to: pages.count, by: step).map { index -> (Int, String) in
            let page = pages[index]
            // 截取前previewLength个可视字符作为摘要
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