//
//  TextReaderApp.swift
//  TextReader
//
//  Created by zengkai on 2024/9/22.
//

import SwiftUI

@main
struct TextReaderApp: App {
    // ① 单例化 ViewModel，保证冷启动也能接收 URL
    @StateObject private var rootViewModel = ContentViewModel()

    var body: some Scene {
        WindowGroup {
            // ② 把同一个 viewModel 注入到根视图
            ContentView(viewModel: rootViewModel)
                // ③ App-level onOpenURL，冷启动/前台均能触发
                .onOpenURL { url in
                    print("[TextReaderApp] openURL: \(url)")
                    rootViewModel.handleImportedURL(url)
                }
        }
    }
}
