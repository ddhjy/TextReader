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
    @State private var showingBookList = false
    @State private var showingDocumentPicker: Bool = false
    
    var body: some View {
        NavigationView {
            VStack {
                if model.isContentLoaded {
                    ScrollView {
                        Text(model.pages.isEmpty ? "没有内容可显示。" : model.pages[model.currentPageIndex])
                            .padding()
                            .accessibility(label: Text(model.pages.isEmpty ? "没有内容可显示。" : model.pages[model.currentPageIndex]))
                    }
                    
                    Spacer()
                    
                    // 所有操作按钮都放在这里
                    VStack {
                        // 翻页控制
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
                                Text("2.2x").tag(2.2 as Float)
                                Text("3x").tag(3.0 as Float)
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            
                            Picker("音色", selection: Binding<AVSpeechSynthesisVoice?>(
                                get: { self.model.selectedVoice },
                                set: { self.model.setVoice($0!) }
                            )) {
                                ForEach(model.availableVoices, id: \.identifier) { voice in
                                    Text(voice.name).tag(voice as AVSpeechSynthesisVoice?)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                        }
                        .padding()
                        
                        // 书本选择和导入按钮
                        HStack {
                            Button(action: {
                                showingBookList = true
                            }) {
                                Text("选择书本")
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                showingDocumentPicker = true
                            }) {
                                Text("从 iCloud 导入")
                            }
                        }
                        .padding()
                    }
                } else {
                    ProgressView("加载中...")
                }
            }
            .padding()
            .navigationTitle(model.currentBook?.title ?? "阅读器")
            .sheet(isPresented: $showingBookList) {
                BookListView(model: model)
            }
            .sheet(isPresented: $showingDocumentPicker) {
                DocumentPicker(model: model)
            }
        }
        .onDisappear {
            model.saveCurrentBook()
        }
    }
}

#Preview {
    ContentView()
}


class ContentModel: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var pages: [String] = []
    @Published var currentPageIndex: Int = 0 {
        didSet {
            let key = "bookProgress_\(currentBook?.id ?? "")"
            UserDefaults.standard.set(currentPageIndex, forKey: key)
            print("保存进度: \(currentPageIndex) 到 \(key)") // 调试信息
        }
    }

    @Published var isReading: Bool = false

    @Published var readingSpeed: Float = UserDefaults.standard.float(forKey: "readingSpeed") {
        didSet {
            UserDefaults.standard.set(readingSpeed, forKey: "readingSpeed")
        }
    }

    @Published var selectedVoice: AVSpeechSynthesisVoice? {
        didSet {
            if let identifier = selectedVoice?.identifier {
                UserDefaults.standard.set(identifier, forKey: "selectedVoiceIdentifier")
            }
        }
    }

    @Published var availableVoices: [AVSpeechSynthesisVoice] = []

    private var synthesizer = AVSpeechSynthesizer()

    @Published var books: [Book] = []
    @Published var currentBook: Book? {
        didSet {
            if let book = currentBook {
                UserDefaults.standard.set(book.id, forKey: "currentBookID")
                loadBookProgress(for: book)
            }
        }
    }

    @Published var isContentLoaded: Bool = false

    override init() {
        super.init()
        synthesizer.delegate = self
        loadBooks()
        loadSavedSettings()
        loadAvailableVoices()
    }

    private func loadBooks() {
        // 从 main bundle 中加载已有的书本
        let bookFiles = [
            ("思考快与慢", "思考快与慢"),
            ("罗素作品集", "罗素作品集")
        ]

        books = bookFiles.compactMap { (title, fileName) in
            if Bundle.main.url(forResource: fileName, withExtension: "txt") != nil {
                return Book(title: title, fileName: fileName)
            }
            return nil
        }

        // 修改这部分来加载上次阅读的书籍
        if let savedBookFileName = UserDefaults.standard.string(forKey: "currentBookID"),
           let savedBook = books.first(where: { $0.id == savedBookFileName }) {
            currentBook = savedBook
            loadBookContent(savedBook)
            print("加载上次阅读的书籍: \(savedBook.title)") // 调试信息
        } else if let firstBook = books.first {
            currentBook = firstBook
            loadBookContent(firstBook)
            print("加载第一本书籍: \(firstBook.title)") // 调试信息
        }
    }

    // 新增方法来加载书籍内容
    private func loadBookContent(_ book: Book) {
        if let url = Bundle.main.url(forResource: book.fileName, withExtension: "txt") {
            loadContent(from: url)
        }
    }

    private func loadSavedSettings() {
        readingSpeed = UserDefaults.standard.float(forKey: "readingSpeed")
        if readingSpeed == 0 {
            readingSpeed = 1.0 // 默认速度
        }

        if let savedVoiceIdentifier = UserDefaults.standard.string(forKey: "selectedVoiceIdentifier"),
           let savedVoice = AVSpeechSynthesisVoice(identifier: savedVoiceIdentifier) {
            selectedVoice = savedVoice
        } else if let defaultVoice = AVSpeechSynthesisVoice(language: "zh-CN") {
            selectedVoice = defaultVoice
        }
    }

    private func loadAvailableVoices() {
        availableVoices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.starts(with: "zh") }
        if let defaultVoice = AVSpeechSynthesisVoice(language: "zh-CN") {
            selectedVoice = defaultVoice
        }
    }

    func nextPage() {
        if currentPageIndex < pages.count - 1 {
            stopReading()
            currentPageIndex += 1
            saveBookProgress()
            if isReading {
                readCurrentPage()
            }
        }
    }

    func previousPage() {
        if currentPageIndex > 0 {
            stopReading()
            currentPageIndex -= 1
            saveBookProgress()
            if isReading {
                readCurrentPage()
            }
        }
    }

    func readCurrentPage() {
        if !pages.isEmpty && currentPageIndex < pages.count {
            isReading = true
            let utterance = AVSpeechUtterance(string: pages[currentPageIndex])
            utterance.voice = selectedVoice ?? AVSpeechSynthesisVoice(language: "zh-CN")
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

    func setVoice(_ voice: AVSpeechSynthesisVoice) {
        selectedVoice = voice
        if isReading {
            stopReading()
            readCurrentPage()
        }
    }

    func loadBook(_ book: Book) {
        currentBook = book
        isContentLoaded = false
        if let url = Bundle.main.url(forResource: book.fileName, withExtension: "txt") {
            loadContent(from: url)
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

    // 新增方法
    func importBookFromiCloud(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            print("无法访问文件")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let fileName = url.lastPathComponent
            let bookTitle = url.deletingPathExtension().lastPathComponent

            // 保存文件到应用的文档目录
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let savedURL = documentsURL.appendingPathComponent(fileName)
            try content.write(to: savedURL, atomically: true, encoding: .utf8)

            // 创建新书本并添加到列表
            let newBook = Book(title: bookTitle, fileName: fileName)
            DispatchQueue.main.async {
                self.books.append(newBook)
                self.currentBook = newBook
            }

            // 加载新书本内容
            loadContent(from: savedURL)

            print("成功导入书本：\(bookTitle)")
        } catch {
            print("导入书本时出错：\(error.localizedDescription)")
            DispatchQueue.main.async {
                // 显示错误警告（这需要在 UI 中实现）
                self.showErrorAlert(message: "导入书本时出错：\(error.localizedDescription)")
            }
        }
    }

    // 修改 loadContent 方法以接受 URL 参数
    private func loadContent(from url: URL) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                let sentences = content.components(separatedBy: CharacterSet(charactersIn: "。！？.!?"))
                                       .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

                var pages = [String]()
                var currentPage = ""
                var currentPageSize = 0
                let maxPageSize = 100

                for sentence in sentences {
                    let sentenceSize = sentence.count

                    if currentPageSize + sentenceSize > maxPageSize && !currentPage.isEmpty {
                        pages.append(currentPage.trimmingCharacters(in: .whitespacesAndNewlines))
                        currentPage = ""
                        currentPageSize = 0
                    }

                    currentPage += sentence + "。"
                    currentPageSize += sentenceSize + 1

                    if currentPageSize >= maxPageSize {
                        pages.append(currentPage.trimmingCharacters(in: .whitespacesAndNewlines))
                        currentPage = ""
                        currentPageSize = 0
                    }
                }

                if !currentPage.isEmpty {
                    pages.append(currentPage.trimmingCharacters(in: .whitespacesAndNewlines))
                }

                DispatchQueue.main.async {
                    self?.pages = pages
                    self?.isContentLoaded = true
                    self?.objectWillChange.send()
                    // 在内容加载完成后加载书本进度
                    if let book = self?.currentBook {
                        self?.loadBookProgress(for: book)
                        print("加载进度完成: \(self?.currentPageIndex ?? 0)") // 调试信息
                    }
                }
            } catch {
                print("加载内容时出错：\(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.showErrorAlert(message: "加载内容时出错：\(error.localizedDescription)")
                }
            }
        }
    }

    // 添加这个方法来显示错误警告
    func showErrorAlert(message: String) {
        // 在这里实现显示错误警告的逻辑
        // 例如，你可以设置一个 @Published 属性来触发 SwiftUI 视图中的警告显示
    }

    // 修改后的 loadBookProgress 方法
    private func loadBookProgress(for book: Book) {
        let key = "bookProgress_\(book.id)"
        let savedIndex = UserDefaults.standard.integer(forKey: key)
        if isContentLoaded && savedIndex < pages.count {
            currentPageIndex = savedIndex
            print("从 UserDefaults 加载进度: \(savedIndex)") // 调试信息
        } else {
            currentPageIndex = 0
            print("保存的进度无效或内容未加载完成，重置为第一页") // 调试信息
        }
    }

    // 修改后的 saveBookProgress 方法
    private func saveBookProgress() {
        if let book = currentBook {
            let key = "bookProgress_\(book.id)"
            UserDefaults.standard.set(currentPageIndex, forKey: key)
        }
    }

    // 修改后的 saveCurrentBook 方法
    func saveCurrentBook() {
        if let book = currentBook {
            UserDefaults.standard.set(book.id, forKey: "currentBookID")
            saveBookProgress()
        }
    }
}

struct Book: Identifiable {
    var id: String { fileName }
    let title: String
    let fileName: String
}


struct BookListView: View {
    @ObservedObject var model: ContentModel
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        List(model.books) { book in
            Button(action: {
                model.loadBook(book)
                presentationMode.wrappedValue.dismiss()
            }) {
                Text(book.title)
            }
        }
        .navigationTitle("选择书本")
    }
}

// 新增 DocumentPicker 视图
struct DocumentPicker: UIViewControllerRepresentable {
    @ObservedObject var model: ContentModel
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.text], asCopy: true)
        picker.delegate = context.coordinator
        picker.shouldShowFileExtensions = true
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: DocumentPicker
        
        init(_ parent: DocumentPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            parent.model.importBookFromiCloud(url)
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}