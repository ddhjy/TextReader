import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()

    var body: some View {
        NavigationStack {
            if viewModel.isContentLoaded {
                VStack(spacing: 0) {
                    ContentDisplay(viewModel: viewModel)
                    ControlPanel(viewModel: viewModel)
                        .background(Color(UIColor.secondarySystemBackground))
                }
                .navigationTitle(viewModel.currentBookTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Color(UIColor.systemGray6), for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: { viewModel.showingBookList = true }) {
                            Image(systemName: "book")
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { viewModel.showingSearchView = true }) {
                            Image(systemName: "magnifyingglass")
                        }
                    }
                }
                .preferredColorScheme(viewModel.darkModeEnabled ? .dark : .light)
            } else {
                ProgressView()
                    .scaleEffect(1.5)
                    .navigationTitle("加载中...")
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onOpenURL { url in
            print("[ContentView] Received URL via onOpenURL: \(url.absoluteString)")
            // 调用 ViewModel 处理接收到的 URL
            viewModel.handleImportedURL(url)
        }
        .sheet(isPresented: $viewModel.showingBookList) {
            NavigationStack {
                BookListView(viewModel: viewModel)
            }
        }
        .sheet(isPresented: $viewModel.showingSearchView) {
            NavigationStack {
                SearchView(viewModel: viewModel)
            }
        }
        .sheet(isPresented: $viewModel.showingDocumentPicker) {
            DocumentPicker(viewModel: viewModel)
        }
    }
} 
