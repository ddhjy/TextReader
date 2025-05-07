import SwiftUI

struct SearchView: View {
    @ObservedObject var viewModel: ContentViewModel
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            SearchBar(text: $searchText, onCommit: {
                viewModel.searchContent(searchText)
            })
            .onChange(of: searchText) { _, newVal in
                if newVal.isEmpty {
                    viewModel.searchContent(newVal)  // 将重置为摘要
                }
            }
            .padding()

            List {
                // ① 有搜索结果 -> 展示搜索结果
                if !viewModel.searchResults.isEmpty {
                    ForEach(viewModel.searchResults, id:\.0) { idx, preview in
                        resultCell(page: idx, preview: preview)
                    }
                }
                // ② 无关键词 -> 展示分页摘要
                else {
                    ForEach(viewModel.pageSummaries, id:\.0) { idx, preview in
                        resultCell(page: idx, preview: preview)
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
    
    /// 共用 Cell
    @ViewBuilder
    private func resultCell(page idx: Int, preview: String) -> some View {
        Button {
            viewModel.jumpToSearchResult(pageIndex: idx)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Page \(idx + 1)").font(.headline)
                Text(preview).font(.subheadline).lineLimit(2)
            }
        }
    }
} 