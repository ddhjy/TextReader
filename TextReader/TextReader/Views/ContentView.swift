import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: ContentViewModel
    
    @State private var showProgressSlider = false

    var body: some View {
        NavigationStack {
            ZStack {
                (viewModel.darkModeEnabled ? Color.black : Color(UIColor.systemBackground))
                    .ignoresSafeArea()
                
                ContentDisplay(viewModel: viewModel)
                    .padding(.bottom, 100)
                
                if showProgressSlider {
                    Color.clear
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3)) {
                                showProgressSlider = false
                            }
                        }
                }
                
                VStack {
                    Spacer()
                    ControlPanel(viewModel: viewModel, showProgressSlider: $showProgressSlider)
                        .padding(.bottom, 20)
                }
            }
            .navigationTitle(viewModel.currentBookTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(viewModel.currentBookTitle)
                        .foregroundColor(.secondary)
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
        .accentColor(viewModel.currentAccentColor)
    }
} 

#Preview {
    ContentView(viewModel: ContentViewModel())
} 
