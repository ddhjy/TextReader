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
            .accentColor(viewModel.currentAccentColor)
            .onChange(of: searchText) { _, _ in
                performSearch()
            }
            .padding()

            List {
                if searchText.isEmpty {
                    ForEach(viewModel.pageSummaries, id:\.0) { idx, preview in
                        resultCell(page: idx, preview: preview, shouldHighlight: false)
                    }
                } else if viewModel.searchResults.isEmpty {
                    Text("未找到 \"\(searchText)\" 相关内容")
                        .foregroundColor(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(viewModel.searchResults, id:\.0) { idx, preview in
                        resultCell(page: idx, preview: preview, shouldHighlight: true)
                    }
                    
                }
            }
        }
        .navigationTitle("查询")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("取消") {
                    dismiss()
                }
                .foregroundColor(viewModel.currentAccentColor)
            }
        }
    }
    
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
                Text("第 \(idx + 1) 页")
                    .font(.headline)
                    .foregroundColor(.primary)
                
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
    
    private func createHighlightedAttributedString(text: String, searchQuery: String) -> NSAttributedString? {
        guard !searchQuery.isEmpty else { return nil }
        
        let attributedString = NSMutableAttributedString(string: text)
        
        attributedString.addAttribute(
            .foregroundColor,
            value: UIColor.secondaryLabel,
            range: NSRange(location: 0, length: text.count)
        )
        
        let ranges = text.ranges(of: searchQuery, options: [.caseInsensitive])
        
        guard !ranges.isEmpty else { return nil }
        
        for range in ranges {
            let nsRange = NSRange(range, in: text)
            
            attributedString.addAttribute(
                .backgroundColor,
                value: UIColor(viewModel.currentAccentColor).withAlphaComponent(0.2),
                range: nsRange
            )
            
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