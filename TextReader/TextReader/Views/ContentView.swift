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
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: { viewModel.showingBookList = true }) {
                            Image(systemName: "book")
                        }
                    }
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: {
                            viewModel.showingWiFiTransferView = true
                        }) {
                            Image(systemName: "wifi")
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { viewModel.showingSearchView = true }) {
                            Image(systemName: "magnifyingglass")
                        }
                    }
                }
            } else {
                ProgressView()
                    .scaleEffect(1.5)
                    .navigationTitle("加载中...")
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
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
        .sheet(isPresented: $viewModel.showingWiFiTransferView) {
            WiFiTransferView(viewModel: viewModel)
        }
    }
} 
