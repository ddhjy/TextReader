import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()
    @State private var isCopied = false

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
                .overlay(alignment: .top) {
                    Group {
                        if let address = viewModel.serverAddress {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("WiFi 传输已开启")
                                    .font(.headline)
                                Text("请在浏览器中访问：")
                                    .font(.subheadline)
                                HStack {
                                    Text(address)
                                        .font(.system(.body, design: .monospaced))
                                        .lineLimit(1)
                                        .truncationMode(.middle)

                                    Spacer()

                                    Button {
                                        UIPasteboard.general.string = address
                                        print("地址已复制: \(address)")
                                        withAnimation {
                                            isCopied = true
                                        }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                            withAnimation {
                                                isCopied = false
                                            }
                                        }
                                    } label: {
                                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                            .foregroundColor(.accentColor)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding()
                            .background(.thinMaterial)
                            .cornerRadius(10)
                            .shadow(radius: 5)
                            .padding(.horizontal)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .animation(.spring(), value: viewModel.serverAddress != nil)
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
    }
} 
