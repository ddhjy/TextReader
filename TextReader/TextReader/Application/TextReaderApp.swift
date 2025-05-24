//
//  TextReaderApp.swift
//  TextReader
//
//  Created by zengkai on 2024/9/22.
//

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
