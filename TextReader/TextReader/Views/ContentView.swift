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
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
            }
            .preferredColorScheme(viewModel.darkModeEnabled ? .dark : .light)
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
        .sheet(isPresented: $viewModel.showingBigBang) {
            BigBangView(vm: viewModel)
        }
        .sheet(isPresented: $viewModel.showingSettings) {
            SettingsView(viewModel: viewModel)
        }
        .overlay(alignment: .top) {
            if let bannerMessage = viewModel.sharedImportBannerMessage {
                Text(bannerMessage)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: viewModel.sharedImportBannerMessage)
        .alert("结束定时播放？", isPresented: $viewModel.showingSleepTimerStopAlert) {
            Button("取消", role: .cancel) { }
            Button("结束", role: .destructive) {
                viewModel.endSleepTimerAndStop()
            }
        } message: {
            Text("当前已开启定时播放，确认结束当前播放吗？")
        }
        .tint(viewModel.currentAccentColor)
    }
} 

#Preview {
    ContentView(viewModel: ContentViewModel())
} 
