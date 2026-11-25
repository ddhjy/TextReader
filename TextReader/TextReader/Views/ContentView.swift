import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: ContentViewModel
    @ObservedObject var session: AppSessionController
    
    @State private var showProgressSlider = false
    @State private var importMethod: ImportMethod?

    /// 阅读区底边、控制栏底边各自离屏幕下沿（安全区）多远。
    private let readerBottomInset: CGFloat = 100
    private let controlPanelBottomInset: CGFloat = 20

    /// 控制栏上方那排浮动按钮伸进阅读区多高，外加一点空隙。很高的页会让开这一段，免得最后一行被按钮挡住。
    private var readerBottomReserve: CGFloat {
        max(0, ControlPanel.accessoryRowTop + controlPanelBottomInset - readerBottomInset) + 4
    }

    private var isCoveredBySheet: Bool {
        viewModel.showingBookList
            || viewModel.showingSearchView
            || viewModel.showingSettings
            || viewModel.showingBigBang
            || importMethod != nil
    }

    var body: some View {
        NavigationStack {
            // 直接放在这一层的自定义视图 / 修饰器不要再自己观察 viewModel，需要的值由这里读出来传进去。
            // 原因见 NoticeBanner.swift：否则点「书架」「设置」会偶尔没反应。
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()
                
                ContentDisplay(
                    viewModel: viewModel,
                    isCoveredByImportSheet: importMethod != nil,
                    bottomReserve: readerBottomReserve
                )
                .padding(.bottom, readerBottomInset)
                .ignoresSafeArea(.keyboard)
                
                if showProgressSlider {
                    Color.clear
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3)) {
                                showProgressSlider = false
                            }
                        }
                        .accessibilityHidden(true)
                }
                
                VStack {
                    Spacer()
                    ControlPanel(
                        viewModel: viewModel,
                        showProgressSlider: $showProgressSlider,
                        onImport: { importMethod = $0 }
                    )
                    .padding(.bottom, controlPanelBottomInset)
                }
            }
            .noticeBanner(
                viewModel.notice,
                isCovered: isCoveredBySheet,
                onShown: viewModel.noticeDidAppear,
                onDismiss: viewModel.dismissNotice
            )
            .navigationTitle(viewModel.currentBookTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .ignoresSafeArea(.keyboard)
            .background {
                ReaderKeyboardIsolation()
            }
        }
        .ignoresSafeArea(.keyboard)
        .sheet(isPresented: $viewModel.showingBookList) {
            NavigationStack {
                BookListView(viewModel: viewModel, session: session)
            }
        }
        .sheet(isPresented: $viewModel.showingSearchView) {
            NavigationStack {
                SearchView(viewModel: viewModel)
            }
        }
        .sheet(isPresented: $viewModel.showingBigBang) {
            BigBangView(vm: viewModel)
        }
        .sheet(isPresented: $viewModel.showingSettings) {
            SettingsView(viewModel: viewModel, session: session)
        }
        .importSheet($importMethod, viewModel: viewModel)
        .tint(viewModel.currentAccentColor)
        .onAppear {
            viewModel.appearanceMode.applyToWindows()
        }
        .onChange(of: viewModel.appearanceMode) { _, newValue in
            newValue.applyToWindows()
        }
    }
} 

#Preview {
    ContentView(viewModel: ContentViewModel(), session: AppSessionController())
}
