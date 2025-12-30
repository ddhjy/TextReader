import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: ContentViewModel

    var body: some View {
        NavigationStack {
            ZStack {
                // 背景颜色
                (viewModel.darkModeEnabled ? Color.black : Color(UIColor.systemBackground))
                    .ignoresSafeArea()
                
                // 内容显示区域
                ContentDisplay(viewModel: viewModel)
                    .padding(.bottom, 100) // 留出底部控制栏的空间
                
                // 底部控制面板
                VStack {
                    Spacer()
                    ControlPanel(viewModel: viewModel)
                        .padding(.bottom, 20)
                }
            }
            .navigationTitle(viewModel.currentBookTitle)
            .navigationBarTitleDisplayMode(.inline)
            // 隐藏原有的导航栏背景，让界面更沉浸
            .toolbarBackground(.hidden, for: .navigationBar)
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
