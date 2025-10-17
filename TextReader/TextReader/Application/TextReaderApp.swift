import SwiftUI

@main
struct TextReaderApp: App {
    @StateObject private var rootViewModel = ContentViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: rootViewModel)
                .onOpenURL { url in
                    print("[TextReaderApp] openURL: \(url)")
                    rootViewModel.handleImportedURL(url)
                }
        }
    }
}
