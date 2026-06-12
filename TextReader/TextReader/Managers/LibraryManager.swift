import Foundation

class LibraryManager {
    
    private let bookMetadataFile = "library.json"
    private let fileManager: FileManager
    private let documentsDirectoryProvider: () throws -> URL
    private let builtInBooks: [BuiltInBook]

    struct BuiltInBook: Equatable {
        let title: String
        let fileName: String
        let resourceName: String?
        let content: String?

        init(title: String,
             fileName: String,
             resourceName: String? = nil,
             content: String? = nil) {
            self.title = title
            self.fileName = fileName
            self.resourceName = resourceName
            self.content = content
        }

        static let userGuide = BuiltInBook(
            title: "使用说明",
            fileName: "使用说明",
            resourceName: "使用说明"
        )

        static let reviewSample = BuiltInBook(
            title: "读书派示例文本",
            fileName: "__builtin_review_sample__",
            content: """
            读书派是一款面向中文阅读和朗读场景的轻量阅读工具。

            你可以导入 txt 或 md 文本，把长文、资料、笔记和电子书放进书架中管理。打开一本书后，App 会自动分页，记录阅读进度，并支持翻页、搜索和语音朗读。

            典型使用流程：
            1. 在书架中导入一份文本。
            2. 打开文本开始阅读。
            3. 点击播放按钮朗读当前页。
            4. 使用搜索定位关键词。
            5. 下次打开时继续上一次的阅读进度。

            这份示例文本用于演示审核流程，不包含用户个人数据。
            """
        )
    }
    
    enum LibraryError: Error {
        case fileNotFound
        case directoryAccessFailed
        case saveError
        case readError(String)
        case fileImportError(String)
        case deleteError
        case securityAccessError
        case unsupportedEncoding
    }

    private enum ImportConflictPolicy {
        case overwriteExisting
        case createUniqueCopy
    }

    init(fileManager: FileManager = .default,
         documentsDirectoryProvider: (() throws -> URL)? = nil,
         builtInBooks: [BuiltInBook] = [.userGuide]) {
        self.fileManager = fileManager
        self.builtInBooks = builtInBooks
        self.documentsDirectoryProvider = documentsDirectoryProvider ?? {
            guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                throw LibraryError.directoryAccessFailed
            }
            return documentsDirectory
        }
    }
    
    func loadBooks() -> [Book] {
        var allBooks: [Book] = []
        
        let bundleBooks = builtInBooks.compactMap { builtInBook in
            if builtInBook.content != nil {
                return Book(title: builtInBook.title, fileName: builtInBook.fileName, isBuiltIn: true)
            }

            let resourceName = builtInBook.resourceName
                ?? URL(fileURLWithPath: builtInBook.fileName).deletingPathExtension().lastPathComponent

            if Bundle.main.url(forResource: resourceName, withExtension: "txt") != nil {
                return Book(title: builtInBook.title, fileName: builtInBook.fileName, isBuiltIn: true)
            }
            return nil
        }
        allBooks.append(contentsOf: bundleBooks)
        
        do {
            let documentsURL = try getDocumentsDirectory()
            let fileURLs = try fileManager.contentsOfDirectory(
                at: documentsURL,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
            
            let allowedExtensions = ["txt", "md"]
            let importedFiles = fileURLs.filter { url in
                allowedExtensions.contains(url.pathExtension.lowercased())
            }
            
            let importedBooks = importedFiles.map { url in
                let title = url.deletingPathExtension().lastPathComponent
                let fileName = url.lastPathComponent
                return Book(title: title, fileName: fileName, isBuiltIn: false)
            }
            allBooks.append(contentsOf: importedBooks)
        } catch {
            print("加载文档目录书籍失败: \(error)")
        }
        
        return allBooks
    }
    
    func loadBookContent(book: Book, completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let url: URL
                
                if book.isBuiltIn {
                    guard let builtInBook = self.builtInBooks.first(where: { $0.fileName == book.fileName }) else {
                        completion(.failure(LibraryError.fileNotFound))
                        return
                    }

                    if let content = builtInBook.content {
                        DispatchQueue.main.async {
                            completion(.success(content))
                        }
                        return
                    }

                    let resourceName = builtInBook.resourceName
                        ?? URL(fileURLWithPath: builtInBook.fileName).deletingPathExtension().lastPathComponent

                    guard let bundleURL = Bundle.main.url(forResource: resourceName, withExtension: "txt") else {
                        completion(.failure(LibraryError.fileNotFound))
                        return
                    }
                    url = bundleURL
                } else {
                    let documentsURL = try self.getDocumentsDirectory()
                    url = documentsURL.appendingPathComponent(book.fileName)
                }
                
                let content = try String(contentsOf: url, encoding: .utf8)
                DispatchQueue.main.async {
                    completion(.success(content))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    func importBook(fileName: String,
                    content: String,
                    suggestedTitle: String? = nil,
                    overwriteExisting: Bool = true,
                    completion: @escaping (Result<Book, Error>) -> Void) {
        do {
            let conflictPolicy: ImportConflictPolicy = overwriteExisting ? .overwriteExisting : .createUniqueCopy
            let book = try importBookSynchronously(
                fileName: fileName,
                content: content,
                suggestedTitle: suggestedTitle,
                conflictPolicy: conflictPolicy
            )
            completion(.success(book))
        } catch {
            print("[LibraryManager][错误] 保存导入的书籍内容失败 \(fileName): \(error.localizedDescription)")
            completion(.failure(error))
        }
    }

    func importSharedText(_ content: String,
                          preferredTitle: String?,
                          sourceFileName: String? = nil,
                          createdAt: Date = Date()) throws -> Book {
        let resolvedTitle = resolveSharedImportTitle(
            preferredTitle: preferredTitle,
            sourceFileName: sourceFileName,
            content: content,
            createdAt: createdAt
        )

        return try importBookSynchronously(
            fileName: "\(resolvedTitle).txt",
            content: content,
            suggestedTitle: resolvedTitle,
            conflictPolicy: .createUniqueCopy
        )
    }

    func resolveSharedImportTitle(preferredTitle: String?,
                                  sourceFileName: String?,
                                  content: String,
                                  createdAt: Date = Date()) -> String {
        if let preferredTitle = trimmedNonEmpty(preferredTitle) {
            return sanitizedImportedTitle(preferredTitle)
        }

        if let sourceFileName = trimmedNonEmpty(sourceFileName) {
            let baseName = URL(fileURLWithPath: sourceFileName).deletingPathExtension().lastPathComponent
            if let normalizedBaseName = Optional(baseName).nilIfEmpty() {
                return sanitizedImportedTitle(normalizedBaseName)
            }
        }

        if let firstLine = firstMeaningfulLine(in: content) {
            return sanitizedImportedTitle(String(firstLine.prefix(20)))
        }

        return fallbackSharedImportTitle(createdAt: createdAt)
    }
    
    func importBookFromURL(_ url: URL, suggestedTitle: String? = nil, completion: @escaping (Result<Book, Error>) -> Void) {
        print("[LibraryManager] 开始导入URL: \(url.absoluteString)")
        print("[LibraryManager] URL方案: \(url.scheme ?? "nil"), 是否为文件URL: \(url.isFileURL)")
        print("[LibraryManager] 建议标题: \(suggestedTitle ?? "无")")

        let isInInboxDirectory = url.path.contains("/tmp/") && url.path.contains("-Inbox/")
        if isInInboxDirectory {
            print("[LibraryManager] 文件位于应用的Inbox目录中，跳过安全作用域访问")
        }

        var securityAccessGranted = false
        if !isInInboxDirectory {
            securityAccessGranted = url.startAccessingSecurityScopedResource()
            print("[LibraryManager] 尝试为 \(url.lastPathComponent) 启动安全访问... 成功: \(securityAccessGranted)")

            if !securityAccessGranted {
                print("[LibraryManager] 无法作为安全作用域资源访问，将尝试直接访问")
            }
        }
        defer {
            if securityAccessGranted {
                url.stopAccessingSecurityScopedResource()
                print("[LibraryManager] 停止访问安全作用域资源: \(url.lastPathComponent)")
            }
        }

        print("[LibraryManager] 尝试从以下位置读取内容: \(url.path)")

        var fileContent: String?
        var usedEncoding: String.Encoding?
        let encodingsToTry: [String.Encoding] = [.utf8, .gb_18030_2000]

        for encoding in encodingsToTry {
            print("[LibraryManager] 尝试编码: \(encoding)")
            if let content = try? String(contentsOf: url, encoding: encoding) {
                fileContent = content
                usedEncoding = encoding
                print("[LibraryManager] 使用编码成功读取内容: \(encoding)")
                break
            } else {
                print("[LibraryManager] 使用编码读取失败: \(encoding)")
            }
        }

        if fileContent == nil {
            print("[LibraryManager] 所有直接读取尝试都失败。尝试先复制文件...")
            if let (content, encoding) = tryReadingByCopyingFirst(url: url, encodingsToTry: encodingsToTry) {
                fileContent = content
                usedEncoding = encoding
                print("[LibraryManager] 复制后成功读取内容。编码: \(encoding)")
            }
        }

        guard let content = fileContent, let _ = usedEncoding else {
            print("[LibraryManager][错误] 无法使用支持的编码从 \(url.path) 读取内容。")
            completion(.failure(LibraryError.unsupportedEncoding))
            return
        }

        let fileName = generateSafeFileName(from: url, suggestedTitle: suggestedTitle)
        importBook(
            fileName: fileName,
            content: content,
            suggestedTitle: suggestedTitle,
            overwriteExisting: true,
            completion: completion
        )
    }
    
    private func generateSafeFileName(from url: URL, suggestedTitle: String?) -> String {
        let baseName = trimmedNonEmpty(suggestedTitle)
            ?? url.deletingPathExtension().lastPathComponent
        return normalizeImportFileName("\(baseName).txt")
    }
    
    private func tryReadingByCopyingFirst(url: URL, encodingsToTry: [String.Encoding]) -> (String, String.Encoding)? {
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(UUID().uuidString + ".txt")
        
        do {
            try FileManager.default.copyItem(at: url, to: tempFile)
            print("[LibraryManager] 文件已复制到临时位置: \(tempFile.path)")
        } catch let error {
            print("[LibraryManager][错误] 复制文件到临时位置失败: \(error.localizedDescription)")
            return nil
        }
        
        for encoding in encodingsToTry {
            if let content = try? String(contentsOf: tempFile, encoding: encoding) {
                print("[LibraryManager] 复制后成功使用编码读取: \(encoding)")
                
                try? FileManager.default.removeItem(at: tempFile)
                return (content, encoding)
            }
        }
        
        try? FileManager.default.removeItem(at: tempFile)
        return nil
    }
    
    func getDocumentsDirectory() throws -> URL {
        try documentsDirectoryProvider()
    }
    
    func deleteBook(_ book: Book, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !book.isBuiltIn else {
            print("[LibraryManager] 无法删除内置书籍: \(book.title)")
            DispatchQueue.main.async {
                completion(.success(()))
            }
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let documentsURL = try self.getDocumentsDirectory()
                let fileURL = documentsURL.appendingPathComponent(book.fileName)
                
                if self.fileManager.fileExists(atPath: fileURL.path) {
                    try self.fileManager.removeItem(at: fileURL)
                    print("[LibraryManager] 成功删除书籍文件: \(fileURL.path)")
                } else {
                    print("[LibraryManager] 要删除的文件不存在: \(fileURL.path)")
                }
                
                self.removeBookProgress(bookId: book.id)

                DispatchQueue.main.async {
                    completion(.success(()))
                }
            } catch {
                print("[LibraryManager][错误] 删除书籍失败: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(.failure(LibraryError.deleteError))
                }
            }
        }
    }
    
    func bookExists(withFileName fileName: String) -> Bool {
        do {
            let documentsURL = try getDocumentsDirectory()
            let fileURL = documentsURL.appendingPathComponent(fileName)
            return fileManager.fileExists(atPath: fileURL.path)
        } catch {
            return false
        }
    }
    
    func updateBookTitle(book: Book, newTitle: String, completion: @escaping (Result<Book, Error>) -> Void) {
        guard !book.isBuiltIn else {
            completion(.failure(LibraryError.saveError))
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            var updatedBook = book
            updatedBook.title = newTitle
            
            DispatchQueue.main.async {
                completion(.success(updatedBook))
            }
        }
    }
    
    func updateBookContent(book: Book, newContent: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !book.isBuiltIn else {
            print("[LibraryManager] Cannot modify built-in book: \(book.title)")
            DispatchQueue.main.async {
                completion(.failure(LibraryError.saveError))
            }
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let documentsURL = try self.getDocumentsDirectory()
                let fileURL = documentsURL.appendingPathComponent(book.fileName)
                
                try newContent.write(to: fileURL, atomically: true, encoding: .utf8)
                print("[LibraryManager] Successfully updated book content: \(book.title)")
                
                DispatchQueue.main.async {
                    completion(.success(()))
                }
            } catch {
                print("[LibraryManager][Error] Failed to update book content: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    func getBookProgress(bookId: String) -> BookProgress? {
        let metadata = loadMetadata()
        return metadata.progress[bookId]
    }
    
    func updateLastAccessed(bookId: String) {
        var metadata = loadMetadata()
        let now = Date()

        if var progress = metadata.progress[bookId] {
            progress.lastAccessed = now
            metadata.progress[bookId] = progress
            print("[LibraryManager] 已更新书籍ID: \(bookId) 的最后访问时间为 \(now)")
        } else {
            print("[LibraryManager] 为书籍ID: \(bookId) 创建带有最后访问时间的新进度记录")
            metadata.progress[bookId] = BookProgress(
                currentPageIndex: 0,
                totalPages: 0,
                lastAccessed: now,
                cachedPages: nil
            )
        }

        saveMetadata(metadata)
    }
    
    func saveBookProgress(bookId: String, pageIndex: Int, totalPages: Int) {
        var metadata = loadMetadata()
        
        if var progress = metadata.progress[bookId] {
            progress.currentPageIndex = pageIndex
            progress.totalPages = totalPages
            metadata.progress[bookId] = progress
        } else {
            metadata.progress[bookId] = BookProgress(
                currentPageIndex: pageIndex,
                totalPages: totalPages,
                lastAccessed: nil,
                cachedPages: nil
            )
        }
        
        saveMetadata(metadata)
    }
    
    func saveTotalPages(bookId: String, totalPages: Int) {
        var metadata = loadMetadata()
        
        if var progress = metadata.progress[bookId] {
            progress.totalPages = totalPages
            metadata.progress[bookId] = progress
        } else {
            metadata.progress[bookId] = BookProgress(
                currentPageIndex: 0,
                totalPages: totalPages,
                lastAccessed: nil,
                cachedPages: nil
            )
        }
        
        saveMetadata(metadata)
    }
    
    func getCachedPages(bookId: String) -> [String]? {
        return getBookProgress(bookId: bookId)?.cachedPages
    }
    
    func saveCachedPages(bookId: String, pages: [String]) {
        var metadata = loadMetadata()
        
        if var progress = metadata.progress[bookId] {
            progress.cachedPages = pages
            progress.totalPages = pages.count
            metadata.progress[bookId] = progress
            print("[LibraryManager] 已缓存书籍 \(bookId) 的 \(pages.count) 页内容")
        } else {
            metadata.progress[bookId] = BookProgress(
                currentPageIndex: 0,
                totalPages: pages.count,
                lastAccessed: Date(),
                cachedPages: pages
            )
            print("[LibraryManager] 为新书籍 \(bookId) 创建缓存，共 \(pages.count) 页")
        }
        
        saveMetadata(metadata)
    }
    
    func clearCachedPages(bookId: String) {
        var metadata = loadMetadata()
        
        if var progress = metadata.progress[bookId] {
            progress.cachedPages = nil
            metadata.progress[bookId] = progress
            print("[LibraryManager] 已清除书籍 \(bookId) 的页面缓存")
        }
        
        saveMetadata(metadata)
    }
    
    func saveLastPageContent(bookId: String, content: String) {
        var metadata = loadMetadata()
        
        if var progress = metadata.progress[bookId] {
            progress.lastPageContent = content
            metadata.progress[bookId] = progress
        } else {
            metadata.progress[bookId] = BookProgress(
                currentPageIndex: 0,
                totalPages: 0,
                lastAccessed: Date(),
                cachedPages: nil,
                lastPageContent: content
            )
        }
        
        saveMetadata(metadata)
    }
    
    private func removeBookProgress(bookId: String) {
        var metadata = loadMetadata()
        metadata.progress.removeValue(forKey: bookId)
        saveMetadata(metadata)
    }

    private func importBookSynchronously(fileName: String,
                                         content: String,
                                         suggestedTitle: String?,
                                         conflictPolicy: ImportConflictPolicy) throws -> Book {
        let documentsURL = try getDocumentsDirectory()
        let destinationURL = try destinationURL(
            for: fileName,
            conflictPolicy: conflictPolicy,
            documentsURL: documentsURL
        )

        print("[LibraryManager] 尝试将导入的内容保存到文件: \(destinationURL.lastPathComponent)")
        print("[LibraryManager] 目标路径: \(destinationURL.path)")

        if conflictPolicy == .overwriteExisting,
           fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
            print("[LibraryManager] 成功删除目标位置的现有文件。")
        }

        try content.write(to: destinationURL, atomically: true, encoding: .utf8)
        print("[LibraryManager] 成功将内容写入目标。")

        let resolvedTitle = trimmedNonEmpty(suggestedTitle)
            ?? destinationURL.deletingPathExtension().lastPathComponent
        let newBook = Book(title: resolvedTitle, fileName: destinationURL.lastPathComponent, isBuiltIn: false)
        print("[LibraryManager] 创建书籍对象: 标题='\(resolvedTitle)', 文件名='\(destinationURL.lastPathComponent)'")

        return newBook
    }

    private func destinationURL(for fileName: String,
                                conflictPolicy: ImportConflictPolicy,
                                documentsURL: URL) throws -> URL {
        let normalizedFileName = normalizeImportFileName(fileName)
        let normalizedURL = URL(fileURLWithPath: normalizedFileName)
        let baseName = normalizedURL.deletingPathExtension().lastPathComponent
        let pathExtension = normalizedURL.pathExtension.lowercased()

        var candidateFileName = normalizedFileName
        var candidateURL = documentsURL.appendingPathComponent(candidateFileName)
        var suffix = 2

        while conflictPolicy == .createUniqueCopy,
              fileManager.fileExists(atPath: candidateURL.path) {
            candidateFileName = "\(baseName)-\(suffix).\(pathExtension)"
            candidateURL = documentsURL.appendingPathComponent(candidateFileName)
            suffix += 1
        }

        return candidateURL
    }

    private func normalizeImportFileName(_ fileName: String) -> String {
        let candidateURL = URL(fileURLWithPath: fileName)
        let rawExtension = candidateURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedExtension = rawExtension.isEmpty ? "txt" : rawExtension.lowercased()
        let baseName = candidateURL.deletingPathExtension().lastPathComponent
        let sanitizedBaseName = sanitizedImportedTitle(baseName)
        return "\(sanitizedBaseName).\(normalizedExtension)"
    }

    func sanitizedImportedTitle(_ title: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
            .union(.illegalCharacters)
            .union(.controlCharacters)
            .union(.newlines)

        let sanitizedScalars = title.unicodeScalars.map { scalar in
            invalidCharacters.contains(scalar) ? "_" : scalar
        }
        var sanitizedTitle = String(String.UnicodeScalarView(sanitizedScalars))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        while sanitizedTitle.contains("__") {
            sanitizedTitle = sanitizedTitle.replacingOccurrences(of: "__", with: "_")
        }

        return Optional(sanitizedTitle).nilIfEmpty() ?? "分享内容"
    }

    private func firstMeaningfulLine(in content: String) -> String? {
        content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }

    private func trimmedNonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func fallbackSharedImportTitle(createdAt: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return "分享_\(formatter.string(from: createdAt))"
    }
    
    
    private struct LibraryMetadata: Codable {
        var progress: [String: BookProgress] = [:]
    }
    
    private func loadMetadata() -> LibraryMetadata {
        do {
            let documentsURL = try getDocumentsDirectory()
            let metadataURL = documentsURL.appendingPathComponent(bookMetadataFile)
            
            guard fileManager.fileExists(atPath: metadataURL.path) else {
                return LibraryMetadata()
            }
            
            let data = try Data(contentsOf: metadataURL)
            return try JSONDecoder().decode(LibraryMetadata.self, from: data)
        } catch {
            print("Error loading metadata: \(error). Using empty metadata.")
            return LibraryMetadata()
        }
    }
    
    private func saveMetadata(_ metadata: LibraryMetadata) {
        do {
            let documentsURL = try getDocumentsDirectory()
            let metadataURL = documentsURL.appendingPathComponent(bookMetadataFile)
            
            let data = try JSONEncoder().encode(metadata)
            try data.write(to: metadataURL, options: .atomic)
        } catch {
            print("Error saving metadata: \(error)")
        }
    }
} 
