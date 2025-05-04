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
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { viewModel.showingSearchView = true }) {
                            Image(systemName: "magnifyingglass")
                        }
                    }
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: {
                            viewModel.toggleWiFiTransfer()
                        }) {
                            Image(systemName: viewModel.isServerRunning ? "wifi.slash" : "wifi")
                        }
                    }
                }
                .overlay(
                    Group {
                        if let address = viewModel.serverAddress {
                            VStack {
                                Text("WiFi 传输已开启")
                                    .font(.headline)
                                Text("请在浏览器中访问：")
                                Text(address)
                                    .font(.system(.body, design: .monospaced))
                            }
                            .padding()
                            .background(Color(.systemBackground))
                            .cornerRadius(10)
                            .shadow(radius: 5)
                            .transition(.move(edge: .top))
                        }
                    }
                )
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
    }
} 