import SwiftUI

@main
struct TextReaderApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var rootViewModel = ContentViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: rootViewModel)
                .task {
                    rootViewModel.consumePendingSharedImports()
                }
                .onOpenURL { url in
                    print("[TextReaderApp] openURL: \(url)")
                    rootViewModel.handleImportedURL(url)
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            rootViewModel.consumePendingSharedImports()
        }
    }
}
