import Foundation

/// 书籍库管理器，负责书籍的加载、导入、存储和删除等操作
///
/// 该类处理以下功能：
/// - 加载内置书籍和用户导入的书籍
/// - 从文件系统读取书籍内容
/// - 导入新书籍（从文本内容或URL）
/// - 保存和管理阅读进度
/// - 书籍删除功能
class LibraryManager {
    
    private let bookMetadataFile = "library.json"
    private let fileManager = FileManager.default
    
    /// 书籍库操作可能出现的错误类型
    enum LibraryError: Error {
        /// 文件未找到
        case fileNotFound
        /// 目录访问失败
        case directoryAccessFailed
        /// 保存错误
        case saveError
        /// 读取错误
        case readError(String)
        /// 文件导入错误
        case fileImportError(String)
        /// 删除错误
        case deleteError
        /// 安全访问权限错误
        case securityAccessError
        /// 不支持的编码
        case unsupportedEncoding
    }
    
    func loadBooks() -> [Book] {
        var allBooks: [Book] = []
        
        let bundleBookFiles = [
            ("使用说明", "使用说明"),
        ]
        
        let bundleBooks = bundleBookFiles.compactMap { (title, fileName) in
            if Bundle.main.url(forResource: fileName, withExtension: "txt") != nil {
                return Book(title: title, fileName: fileName, isBuiltIn: true)
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
                    guard let bundleURL = Bundle.main.url(forResource: URL(fileURLWithPath: book.fileName).deletingPathExtension().lastPathComponent, withExtension: "txt") else {
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
    
    func importBook(fileName: String, content: String, suggestedTitle: String? = nil, completion: @escaping (Result<Book, Error>) -> Void) {
        print("[LibraryManager] 尝试将导入的内容保存到文件: \(fileName)")
        do {
            let documentsURL = try getDocumentsDirectory()
            let fileURL = documentsURL.appendingPathComponent(fileName)
            print("[LibraryManager] 目标路径: \(fileURL.path)")

            if fileManager.fileExists(atPath: fileURL.path) {
                print("[LibraryManager] 目标文件已存在。删除旧版本。")
                do {
                    try fileManager.removeItem(at: fileURL)
                    print("[LibraryManager] 成功删除目标位置的现有文件。")
                } catch {
                    print("[LibraryManager][错误] 删除现有文件失败 \(fileURL.path): \(error.localizedDescription)")
                }
            }

            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            print("[LibraryManager] 成功将内容写入目标。")

            let title: String
            if let suggestedTitle = suggestedTitle {
                title = suggestedTitle
                print("[LibraryManager] 使用建议标题: '\(title)'")
            } else {
                title = fileURL.deletingPathExtension().lastPathComponent
                print("[LibraryManager] 使用从文件名派生的标题: '\(title)'")
            }
            
            let newBook = Book(title: title, fileName: fileName, isBuiltIn: false)
            print("[LibraryManager] 创建书籍对象: 标题='\(title)', 文件名='\(fileName)'")

            completion(.success(newBook))
        } catch {
            print("[LibraryManager][错误] 保存导入的书籍内容失败 \(fileName): \(error.localizedDescription)")
            completion(.failure(LibraryError.saveError))
        }
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
            
            if securityAccessGranted {
                url.stopAccessingSecurityScopedResource()
                print("[LibraryManager] 停止访问安全作用域资源: \(url.lastPathComponent)")
            } else {
                print("[LibraryManager] 无法作为安全作用域资源访问，将尝试直接访问")
            }
        }

        do {
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
            importBook(fileName: fileName, content: content, suggestedTitle: suggestedTitle, completion: completion)
            
        }
    }
    
    private func generateSafeFileName(from url: URL, suggestedTitle: String?) -> String {
        let baseName: String
        if let suggestedTitle = suggestedTitle {
            baseName = suggestedTitle
        } else {
            baseName = url.deletingPathExtension().lastPathComponent
        }
        
        // 确保文件名合法并添加.txt扩展名
        let safeName = baseName.replacingOccurrences(of: "[^a-zA-Z0-9_\\-\\.]", with: "_", options: .regularExpression)
        return safeName.hasSuffix(".txt") ? safeName : safeName + ".txt"
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
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw LibraryError.directoryAccessFailed
        }
        return documentsDirectory
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
            // Create updated book object
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
    
    func saveBookProgress(bookId: String, pageIndex: Int) {
        var metadata = loadMetadata()
        
        if var progress = metadata.progress[bookId] {
            progress.currentPageIndex = pageIndex
            metadata.progress[bookId] = progress
        } else {
            metadata.progress[bookId] = BookProgress(
                currentPageIndex: pageIndex,
                totalPages: 0,
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
