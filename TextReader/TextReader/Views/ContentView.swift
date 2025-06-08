import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: ContentViewModel

    var body: some View {
        NavigationStack {
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
                            .foregroundColor(viewModel.currentAccentColor)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { viewModel.showingSearchView = true }) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(viewModel.currentAccentColor)
                    }
                }
            }
            .preferredColorScheme(viewModel.darkModeEnabled ? .dark : .light)
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
        .sheet(isPresented: $viewModel.showingBigBang) {
            BigBangView(vm: viewModel)
        }
        .sheet(isPresented: $viewModel.showingAccentColorPicker) {
            AccentColorPicker(viewModel: viewModel)
        }
        .accentColor(viewModel.currentAccentColor)
    }
} 
