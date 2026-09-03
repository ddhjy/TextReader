import SwiftUI

struct SearchView: View {
    @ObservedObject var viewModel: ContentViewModel
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if searchText.isEmpty {
                Section("页面速览") {
                    ForEach(viewModel.pageSummaries, id: \.0) { idx, preview in
                        resultCell(page: idx, preview: preview, shouldHighlight: false)
                    }
                }
            } else if viewModel.searchResults.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                Section("\(viewModel.searchResults.count) 个结果") {
                    ForEach(viewModel.searchResults, id: \.0) { idx, preview in
                        resultCell(page: idx, preview: preview, shouldHighlight: true)
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .searchable(text: $searchText, prompt: "搜索内容")
        .searchFocused($isSearchFocused)
        .onAppear {
            isSearchFocused = true
        }
        .onDisappear {
            isSearchFocused = false
        }
        .onChange(of: searchText) { _, _ in
            viewModel.searchContent(searchText)
        }
        .onSubmit(of: .search) {
            viewModel.searchContent(searchText)
        }
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .close) {
                    isSearchFocused = false
                    dismiss()
                }
                .accessibilityLabel("关闭")
            }
        }
    }
    
    @ViewBuilder
    private func resultCell(page idx: Int, preview: String, shouldHighlight: Bool) -> some View {
        Button {
            isSearchFocused = false
            viewModel.jumpToSearchResult(pageIndex: idx)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("第 \(idx + 1) 页")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if shouldHighlight && !searchText.isEmpty {
                    Text(highlightedAttributedString(preview: preview, searchQuery: searchText))
                        .font(.subheadline)
                        .lineLimit(2)
                } else {
                    Text(preview)
                        .font(.subheadline)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
    
    private func highlightedAttributedString(preview: String, searchQuery: String) -> AttributedString {
        var attributed = AttributedString(preview)
        var searchStart = attributed.startIndex

        while searchStart < attributed.endIndex,
              let range = attributed[searchStart...].range(of: searchQuery, options: [.caseInsensitive]) {
            attributed[range].font = Font.subheadline.weight(.semibold)
            attributed[range].backgroundColor = viewModel.currentAccentColor.opacity(0.25)
            searchStart = range.upperBound
        }

        return attributed
    }
}
