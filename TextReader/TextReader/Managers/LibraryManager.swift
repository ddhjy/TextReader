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
    
    // MARK: - 书籍管理
    
    /// 加载所有可用的书籍，包括内置书籍和用户导入的书籍
    /// - Returns: 书籍对象数组
    func loadBooks() -> [Book] {
        var allBooks: [Book] = []
        
        // 1. 从程序包加载内置书籍
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
        
        // 2. 从文档目录加载导入的书籍
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
    
    /// 加载指定书籍的内容
    /// - Parameters:
    ///   - book: 要加载的书籍对象
    ///   - completion: 完成回调，返回书籍内容或错误
    func loadBookContent(book: Book, completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let url: URL
                
                if book.isBuiltIn {
                    // 从主程序包加载
                    guard let bundleURL = Bundle.main.url(forResource: URL(fileURLWithPath: book.fileName).deletingPathExtension().lastPathComponent, withExtension: "txt") else {
                        completion(.failure(LibraryError.fileNotFound))
                        return
                    }
                    url = bundleURL
                } else {
                    // 从文档目录加载
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
    
    /// 导入书籍内容
    /// - Parameters:
    ///   - fileName: 文件名
    ///   - content: 书籍内容
    ///   - suggestedTitle: 建议标题（可选）
    ///   - completion: 完成回调，返回新书籍对象或错误
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
    
    /// 从URL导入书籍
    /// - Parameters:
    ///   - url: 书籍文件URL
    ///   - suggestedTitle: 建议标题（可选）
    ///   - completion: 完成回调，返回新书籍对象或错误
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

            // 尝试使用多种编码读取文件内容
            var fileContent: String?
            var usedEncoding: String.Encoding?
            // 常用编码顺序：UTF-8，然后是 GBK/GB18030
            let encodingsToTry: [String.Encoding] = [.utf8, .gb_18030_2000] // .gb_18030_2000 兼容 GBK 和 GB2312

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

            // 如果所有尝试的编码都失败，尝试复制文件到临时目录再读取
            if fileContent == nil {
                print("[LibraryManager] 所有直接读取尝试都失败。尝试先复制文件...")
                if let (content, encoding) = tryReadingByCopyingFirst(url: url, encodingsToTry: encodingsToTry) {
                    fileContent = content
                    usedEncoding = encoding
                    print("[LibraryManager] 复制后成功读取内容。编码: \(encoding)")
                }
            }

            // 如果仍然无法读取
            guard let content = fileContent, let _ = usedEncoding else {
                print("[LibraryManager][错误] 无法使用支持的编码从 \(url.path) 读取内容。")
                completion(.failure(LibraryError.unsupportedEncoding))
                return
            }

            // 使用文件名或建议的标题作为书籍标题
            let fileName = generateSafeFileName(from: url, suggestedTitle: suggestedTitle)
            
            // 导入内容创建新书籍
            importBook(fileName: fileName, content: content, suggestedTitle: suggestedTitle, completion: completion)
            
        }
    }
    
    /// 生成安全的文件名
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
    
    /// 通过先复制到临时目录尝试读取文件内容
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
        
        // 尝试使用各种编码读取
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
    
    /// 获取文档目录
    func getDocumentsDirectory() throws -> URL {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw LibraryError.directoryAccessFailed
        }
        return documentsDirectory
    }
    
    /// 删除指定的书籍
    /// - Parameters:
    ///   - book: 要删除的书籍
    ///   - completion: 完成回调，返回是否成功
    func deleteBook(_ book: Book, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !book.isBuiltIn else {
            // 内置书籍不能删除
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
    
    /// 检查是否存在指定文件名的书籍
    func bookExists(withFileName fileName: String) -> Bool {
        do {
            let documentsURL = try getDocumentsDirectory()
            let fileURL = documentsURL.appendingPathComponent(fileName)
            return fileManager.fileExists(atPath: fileURL.path)
        } catch {
            return false
        }
    }
    
    /// Update book title
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
    
    /// Update book content
    func updateBookContent(book: Book, newContent: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !book.isBuiltIn else {
            // Built-in books cannot be modified
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
    
    // MARK: - 书籍进度管理
    
    /// 获取指定书籍的阅读进度
    /// - Parameter bookId: 书籍ID
    /// - Returns: 书籍进度对象，如果不存在则返回nil
    func getBookProgress(bookId: String) -> BookProgress? {
        let metadata = loadMetadata()
        return metadata.progress[bookId]
    }
    
    /// 更新书籍的最后访问时间戳
    /// - Parameter bookId: 书籍ID
    func updateLastAccessed(bookId: String) {
        var metadata = loadMetadata()
        let now = Date()

        // 检查书籍的进度记录是否存在
        if var progress = metadata.progress[bookId] {
            progress.lastAccessed = now
            metadata.progress[bookId] = progress
            print("[LibraryManager] 已更新书籍ID: \(bookId) 的最后访问时间为 \(now)")
        } else {
            // 创建新的进度记录，而不只是发出警告
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
    
    /// 保存书籍当前的页码索引
    /// - Parameters:
    ///   - bookId: 书籍ID
    ///   - pageIndex: 当前页码索引
    func saveBookProgress(bookId: String, pageIndex: Int) {
        var metadata = loadMetadata()
        
        // 保留现有的缓存和其他字段
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
    
    /// 保存书籍的总页数
    /// - Parameters:
    ///   - bookId: 书籍ID
    ///   - totalPages: 总页数
    func saveTotalPages(bookId: String, totalPages: Int) {
        var metadata = loadMetadata()
        
        // 保留现有的缓存和其他字段
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
    
    /// 获取缓存的页面数据
    /// - Parameter bookId: 书籍ID
    /// - Returns: 缓存的页面数组，如果不存在则返回nil
    func getCachedPages(bookId: String) -> [String]? {
        return getBookProgress(bookId: bookId)?.cachedPages
    }
    
    /// 保存页面缓存
    /// - Parameters:
    ///   - bookId: 书籍ID
    ///   - pages: 分页后的页面数组
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
    
    /// 清除页面缓存
    /// - Parameter bookId: 书籍ID
    func clearCachedPages(bookId: String) {
        var metadata = loadMetadata()
        
        if var progress = metadata.progress[bookId] {
            progress.cachedPages = nil
            metadata.progress[bookId] = progress
            print("[LibraryManager] 已清除书籍 \(bookId) 的页面缓存")
        }
        
        saveMetadata(metadata)
    }
    
    /// 保存当前页内容缓存，用于快速启动
    /// - Parameters:
    ///   - bookId: 书籍ID
    ///   - content: 当前页内容
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
    
    /// 删除书籍的进度信息
    /// - Parameter bookId: 书籍ID
    private func removeBookProgress(bookId: String) {
        var metadata = loadMetadata()
        metadata.progress.removeValue(forKey: bookId)
        saveMetadata(metadata)
    }
    
    // MARK: - 辅助方法
    
    // MARK: - 元数据存储
    
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
