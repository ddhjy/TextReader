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
            .padding()

            List(viewModel.searchResults, id: \.0) { index, preview in
                Button(action: {
                    viewModel.jumpToSearchResult(pageIndex: index)
                }) {
                    VStack(alignment: .leading) {
                        Text("第 \(index + 1) 页").font(.headline)
                        Text(preview).lineLimit(2)
                    }
                }
            }
        }
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("取消") {
                    dismiss()
                }
            }
        }
    }
} 