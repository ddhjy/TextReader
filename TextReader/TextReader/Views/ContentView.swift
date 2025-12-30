import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: ContentViewModel
    
    // 控制进度条显示状态
    @State private var showProgressSlider = false

    var body: some View {
        NavigationStack {
            ZStack {
                // 背景颜色
                (viewModel.darkModeEnabled ? Color.black : Color(UIColor.systemBackground))
                    .ignoresSafeArea()
                
                // 内容显示区域
                ContentDisplay(viewModel: viewModel)
                    .padding(.bottom, 100) // 留出底部控制栏的空间
                
                // 蒙层（进度条显示时出现，点击关闭进度条）
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
                
                // 底部控制面板
                VStack {
                    Spacer()
                    ControlPanel(viewModel: viewModel, showProgressSlider: $showProgressSlider)
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
