import Foundation

/// 搜索服务，提供文本内容搜索和页面摘要功能
class SearchService {
    /// 在页面数组中搜索指定查询文本
    /// - Parameters:
    ///   - query: 搜索关键词
    ///   - pages: 要搜索的页面数组
    /// - Returns: 包含匹配页面索引和预览文本的元组数组
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
    /// - Parameters:
    ///   - query: 搜索关键词
    ///   - page: 页面内容
    ///   - maxLength: 预览最大长度，默认100个字符
    /// - Returns: 包含关键词上下文的预览文本
    private func generatePreview(for query: String, in page: String, maxLength: Int = 100) -> String {
        if let range = page.range(of: query, options: .caseInsensitive) {
            let start = page.index(range.lowerBound, offsetBy: -20, limitedBy: page.startIndex) ?? page.startIndex
            let end = page.index(range.upperBound, offsetBy: maxLength - query.count, limitedBy: page.endIndex) ?? page.endIndex
            let snippet = String(page[start..<end])
            return (start == page.startIndex ? "" : "...") + snippet + (end == page.endIndex ? "" : "...")
        }
        // 如果找不到范围（在包含检查后调用不应发生）则返回默认预览
        return String(page.prefix(maxLength)) + (page.count > maxLength ? "..." : "")
    }

    // MARK: - 页面摘要
    /// 生成分页摘要，用于页面概览
    /// - Parameters:
    ///   - pages: 页面数组
    ///   - sampleLimit: 最大摘要数量，默认100条
    ///   - previewLength: 每条摘要的最大长度，默认60个字符
    /// - Returns: 包含页面索引和摘要文本的元组数组
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