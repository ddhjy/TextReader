import SwiftUI

struct SearchView: View {
    @ObservedObject var viewModel: ContentViewModel
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if searchText.isEmpty {
                ForEach(viewModel.pageSummaries, id: \.0) { idx, preview in
                    resultCell(page: idx, preview: preview, shouldHighlight: false)
                }
            } else if viewModel.searchResults.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                ForEach(viewModel.searchResults, id: \.0) { idx, preview in
                    resultCell(page: idx, preview: preview, shouldHighlight: true)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .searchable(text: $searchText, prompt: "搜索内容")
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
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("关闭")
            }
        }
    }
    
    @ViewBuilder
    private func resultCell(page idx: Int, preview: String, shouldHighlight: Bool) -> some View {
        Button {
            viewModel.jumpToSearchResult(pageIndex: idx)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                if shouldHighlight && !searchText.isEmpty {
                    highlightedText(preview: preview, searchQuery: searchText)
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
    
    private func highlightedText(preview: String, searchQuery: String) -> Text {
        var attributed = AttributedString(preview)
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return Text(attributed) }

        var searchRange = attributed.startIndex..<attributed.endIndex
        while let range = attributed[searchRange].range(of: query, options: .caseInsensitive) {
            attributed[range].backgroundColor = viewModel.currentAccentColor.opacity(0.25)
            attributed[range].font = .subheadline.weight(.semibold)
            searchRange = range.upperBound..<attributed.endIndex
        }

        return Text(attributed)
    }
}
