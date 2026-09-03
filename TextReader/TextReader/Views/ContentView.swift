import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: ContentViewModel
    @ObservedObject var session: AppSessionController
    
    @State private var showProgressSlider = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()
                
                ContentDisplay(viewModel: viewModel)
                    .padding(.bottom, 100)
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
            .preferredColorScheme(viewModel.appearanceMode.colorScheme)
            .ignoresSafeArea(.keyboard)
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
            SettingsView(viewModel: viewModel, session: session)
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
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: viewModel.sharedImportBannerMessage)
        .onChange(of: viewModel.sharedImportBannerMessage) { _, newValue in
            if let newValue {
                AccessibilityNotification.Announcement(newValue).post()
            }
        }
        .tint(viewModel.currentAccentColor)
    }
} 

#Preview {
    ContentView(viewModel: ContentViewModel(), session: AppSessionController())
}
