import SwiftUI

struct SearchView: View {
    @ObservedObject var viewModel: ContentViewModel
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            SearchBar(text: $searchText, onCommit: {
                performSearch()
            })
            .onChange(of: searchText) { _, newVal in
                // 实时搜索
                performSearch()
            }
            .padding()

            List {
                // 根据搜索状态显示不同内容
                if searchText.isEmpty {
                    // 无搜索词：显示分页摘要，不高亮
                    ForEach(viewModel.pageSummaries, id:\.0) { idx, preview in
                        resultCell(page: idx, preview: preview, shouldHighlight: false)
                    }
                } else if viewModel.searchResults.isEmpty {
                    // 有搜索词但无结果
                    Text("未找到 \"\(searchText)\" 相关内容")
                        .foregroundColor(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    // 有搜索结果：显示搜索结果，高亮关键词
                    ForEach(viewModel.searchResults, id:\.0) { idx, preview in
                        resultCell(page: idx, preview: preview, shouldHighlight: true)
                    }
                    
                }
            }
        }
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
    }
    
    // 执行搜索的方法
    private func performSearch() {
        viewModel.searchContent(searchText)
    }
    
    /// 共用 Cell，支持关键词高亮控制
    @ViewBuilder
    private func resultCell(page idx: Int, preview: String, shouldHighlight: Bool) -> some View {
        Button {
            viewModel.jumpToSearchResult(pageIndex: idx)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Page \(idx + 1)")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                // 根据shouldHighlight参数决定是否高亮
                if shouldHighlight && !searchText.isEmpty {
                    highlightedText(preview: preview, searchQuery: searchText)
                        .font(.subheadline)
                        .lineLimit(2)
                } else {
                    Text(preview)
                        .font(.subheadline)
                        .lineLimit(2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    /// 生成带高亮的文本
    @ViewBuilder
    private func highlightedText(preview: String, searchQuery: String) -> some View {
        let attributedString = createHighlightedAttributedString(
            text: preview,
            searchQuery: searchQuery
        )
        
        if let attributedString = attributedString {
            Text(AttributedString(attributedString))
        } else {
            Text(preview)
        }
    }
    
    /// 创建带高亮的 NSAttributedString
    private func createHighlightedAttributedString(text: String, searchQuery: String) -> NSAttributedString? {
        // 如果搜索词为空，直接返回nil，使用普通文本
        guard !searchQuery.isEmpty else { return nil }
        
        let attributedString = NSMutableAttributedString(string: text)
        
        // 设置默认文本颜色为次要颜色，与非搜索态保持一致
        attributedString.addAttribute(
            .foregroundColor,
            value: UIColor.secondaryLabel,
            range: NSRange(location: 0, length: text.count)
        )
        
        // 查找所有匹配的搜索词位置
        let ranges = text.ranges(of: searchQuery, options: [.caseInsensitive])
        
        // 如果没有找到匹配项，返回nil使用普通文本
        guard !ranges.isEmpty else { return nil }
        
        // 为每个匹配的搜索词添加高亮
        for range in ranges {
            let nsRange = NSRange(range, in: text)
            
            // 添加高亮背景色
            attributedString.addAttribute(
                .backgroundColor,
                value: UIColor.systemYellow.withAlphaComponent(0.3),
                range: nsRange
            )
            
            // 添加粗体效果
            attributedString.addAttribute(
                .font,
                value: UIFont.boldSystemFont(ofSize: UIFont.systemFontSize),
                range: nsRange
            )
        }
        
        return attributedString
    }
}

// MARK: - String Extension for Range Finding
extension String {
    func ranges(of searchString: String, options: String.CompareOptions = []) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var searchStartIndex = self.startIndex
        
        while searchStartIndex < self.endIndex {
            if let range = self.range(of: searchString, options: options, range: searchStartIndex..<self.endIndex) {
                ranges.append(range)
                searchStartIndex = range.upperBound
            } else {
                break
            }
        }
        
        return ranges
    }
} 