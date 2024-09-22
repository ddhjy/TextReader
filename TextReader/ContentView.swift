//
//  ContentView.swift
//  TextReader
//
//  Created by zengkai on 2024/9/22.
//

import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var model = ContentModel()
    
    var body: some View {
        VStack {
            ScrollView {
                Text(model.pages.isEmpty ? "没有内容可显示。" : model.pages[model.currentPageIndex])
                    .padding()
                    .accessibility(label: Text(model.pages.isEmpty ? "没有内容可显示。" : model.pages[model.currentPageIndex]))
            }
            HStack {
                Button(action: {
                    model.previousPage()
                }) {
                    Text("上一页")
                }
                .disabled(model.currentPageIndex == 0)
                
                Spacer()
                
                Text("第 \(model.currentPageIndex + 1) 页，共 \(model.pages.count) 页")
                
                Spacer()
                
                Button(action: {
                    model.nextPage()
                }) {
                    Text("下一页")
                }
                .disabled(model.currentPageIndex >= model.pages.count - 1)
            }
            .padding()
            .accessibility(hidden: true)
            
            // 朗读控制按钮
            HStack {
                Button(action: {
                    model.readCurrentPage()
                }) {
                    Text("朗读")
                }
                
                Button(action: {
                    model.stopReading()
                }) {
                    Text("停止")
                }
                
                Picker("速度", selection: Binding<Float>(
                    get: { self.model.readingSpeed },
                    set: { self.model.setReadingSpeed($0) }
                )) {
                    Text("1x").tag(1.0 as Float)
                    Text("2x").tag(2.0 as Float)
                    Text("3x").tag(3.0 as Float)
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            .padding()
        }
        .padding()
    }
}

#Preview {
    ContentView()
}


class ContentModel: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var pages: [String] = []
    @Published var currentPageIndex: Int = 0 {
        didSet {
            UserDefaults.standard.set(currentPageIndex, forKey: "currentPageIndex")
        }
    }
    
    @Published var isReading: Bool = false
    
    @Published var readingSpeed: Float = 1.0 // 添加阅读速度属性
    
    private var synthesizer = AVSpeechSynthesizer()
    
    override init() {
        super.init()
        synthesizer.delegate = self
        loadContent()
        loadProgress()
    }
    
    private func loadContent() {
        if let url = Bundle.main.url(forResource: "content", withExtension: "txt") {
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                let characters = Array(content)
                let pageSize = 100
                pages = stride(from: 0, to: characters.count, by: pageSize).map {
                    String(characters[$0..<min($0 + pageSize, characters.count)])
                }
            } catch {
                print("加载内容时出错：\(error.localizedDescription)")
            }
        }
    }
    
    private func loadProgress() {
        currentPageIndex = UserDefaults.standard.integer(forKey: "currentPageIndex")
        if currentPageIndex >= pages.count {
            currentPageIndex = 0
        }
    }
    
    func nextPage() {
        if currentPageIndex < pages.count - 1 {
            stopReading() // 在翻页前停止朗读
            currentPageIndex += 1
            if isReading {
                readCurrentPage() // 如果之前在朗读，则开始朗读新页面
            }
        }
    }
    
    func previousPage() {
        if currentPageIndex > 0 {
            stopReading() // 在翻页前停止朗读
            currentPageIndex -= 1
            if isReading {
                readCurrentPage() // 如果之前在朗读，则开始朗读新页面
            }
        }
    }
    
    func readCurrentPage() {
        if !pages.isEmpty && currentPageIndex < pages.count {
            isReading = true
            let utterance = AVSpeechUtterance(string: pages[currentPageIndex])
            utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
            utterance.rate = readingSpeed * AVSpeechUtteranceDefaultSpeechRate // 设置朗读速度
            synthesizer.speak(utterance)
        }
    }
    
    func stopReading() {
        synthesizer.stopSpeaking(at: .immediate)
        isReading = false
    }
    
    func setReadingSpeed(_ speed: Float) {
        readingSpeed = speed
        if isReading {
            stopReading()
            readCurrentPage()
        }
    }

    // AVSpeechSynthesizerDelegate 方法
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        if isReading {
            nextPage()
            if currentPageIndex < pages.count {
                readCurrentPage()
            } else {
                isReading = false
            }
        }
    }
}
