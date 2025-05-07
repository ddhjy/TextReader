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
    
    /// 书籍元数据文件名
    private let bookMetadataFile = "library.json"
    /// 文件管理器实例
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
        // 增加日志：记录开始保存导入的内容
        print("[LibraryManager] 尝试将导入的内容保存到文件: \(fileName)")
        do {
            let documentsURL = try getDocumentsDirectory()
            let fileURL = documentsURL.appendingPathComponent(fileName)
            print("[LibraryManager] 目标路径: \(fileURL.path)")

            // 检查文件是否存在，如果存在则先删除（避免写入错误）
            if fileManager.fileExists(atPath: fileURL.path) {
                print("[LibraryManager] 目标文件已存在。删除旧版本。")
                do {
                    try fileManager.removeItem(at: fileURL)
                    print("[LibraryManager] 成功删除目标位置的现有文件。")
                } catch {
                    print("[LibraryManager][错误] 删除现有文件失败 \(fileURL.path): \(error.localizedDescription)")
                    // 根据策略决定是否继续（覆盖写入）或失败
                    // 这里选择继续尝试写入
                }
            }

            print("[LibraryManager] 使用UTF-8编码将内容写入目标。")
            // 始终使用 UTF-8 编码保存到应用内部存储，确保一致性
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            print("[LibraryManager] 成功将内容写入目标。")

            // 使用建议的标题（如果提供）或从文件名中获取标题
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
        // 增加日志：记录 LibraryManager 开始处理 URL
        print("[LibraryManager] 开始导入URL: \(url.absoluteString)")
        print("[LibraryManager] URL方案: \(url.scheme ?? "nil"), 是否为文件URL: \(url.isFileURL)")
        print("[LibraryManager] 建议标题: \(suggestedTitle ?? "无")")

        // 检查是否是应用临时 Inbox 目录中的文件
        let isInInboxDirectory = url.path.contains("/tmp/") && url.path.contains("-Inbox/")
        if isInInboxDirectory {
            print("[LibraryManager] 文件位于应用的Inbox目录中，跳过安全作用域访问")
        }

        // 尝试获取安全作用域访问权限（对于非 Inbox 文件）
        var securityAccessGranted = false
        if !isInInboxDirectory {
            securityAccessGranted = url.startAccessingSecurityScopedResource()
            print("[LibraryManager] 尝试为 \(url.lastPathComponent) 启动安全访问... 成功: \(securityAccessGranted)")
            
            // 如果成功获取权限，确保在函数退出时停止访问
            if securityAccessGranted {
                defer {
                    url.stopAccessingSecurityScopedResource()
                    print("[LibraryManager] 停止访问安全作用域资源: \(url.lastPathComponent)")
                }
            } else {
                print("[LibraryManager] 无法作为安全作用域资源访问，将尝试直接访问")
            }
        }

        // 无论安全访问是否成功，都尝试读取文件内容
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
                    break // 找到合适的编码后跳出循环
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
            guard let content = fileContent, let encoding = usedEncoding else {
                print("[LibraryManager][错误] 无法使用支持的编码从 \(url.path) 读取内容。")
                completion(.failure(LibraryError.unsupportedEncoding))
                return
            }

            // 获取文件名，但使用建议的标题（如果有）
            let originalFileName = url.lastPathComponent
            let fileName: String
            
            if let suggestedTitle = suggestedTitle {
                // 确保文件名以.txt结尾
                if suggestedTitle.hasSuffix(".txt") {
                    fileName = suggestedTitle
                } else {
                    fileName = suggestedTitle + ".txt"
                }
                print("[LibraryManager] 使用建议标题作为文件名: \(fileName)")
            } else {
                fileName = originalFileName
                print("[LibraryManager] 使用原始文件名: \(fileName)")
            }
            
            print("[LibraryManager] 成功读取内容（编码: \(encoding)）。要使用的文件名: \(fileName)")

            // 调用内部方法将内容写入应用文档目录
            importBook(fileName: fileName, content: content, suggestedTitle: suggestedTitle, completion: completion)

        } catch {
            print("[LibraryManager][错误] 访问文件 \(url.absoluteString) 时发生意外错误: \(error.localizedDescription)")
            completion(.failure(LibraryError.readError("文件访问过程中发生意外错误: \(error.localizedDescription)")))
        }
    }
    
    /// 通过先复制文件到临时目录再读取的方式尝试获取内容
    /// - Parameters:
    ///   - url: 原始文件URL
    ///   - encodingsToTry: 要尝试的编码数组
    /// - Returns: 文件内容和成功的编码，如果失败则返回nil
    private func tryReadingByCopyingFirst(url: URL, encodingsToTry: [String.Encoding]) -> (String, String.Encoding)? {
        do {
            // 创建临时文件URL
            let tempDirURL = FileManager.default.temporaryDirectory
            let tempFileURL = tempDirURL.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
            
            print("[LibraryManager] 将文件复制到临时位置: \(tempFileURL.path)")
            
            // 尝试复制文件
            try FileManager.default.copyItem(at: url, to: tempFileURL)
            print("[LibraryManager] 文件复制成功")
            
            // 尝试从临时位置读取
            for encoding in encodingsToTry {
                if let content = try? String(contentsOf: tempFileURL, encoding: encoding) {
                    print("[LibraryManager] 成功使用编码读取临时文件: \(encoding)")
                    
                    // 完成后删除临时文件
                    try? FileManager.default.removeItem(at: tempFileURL)
                    
                    return (content, encoding)
                }
            }
            
            // 没有成功读取，删除临时文件
            try? FileManager.default.removeItem(at: tempFileURL)
            print("[LibraryManager] 无法使用任何编码读取临时文件，已删除临时文件")
            
        } catch {
            print("[LibraryManager] 将文件复制到临时位置时出错: \(error.localizedDescription)")
        }
        
        return nil
    }
    
    /// 删除指定的书籍
    /// - Parameters:
    ///   - book: 要删除的书籍
    ///   - completion: 完成回调，返回是否成功
    func deleteBook(_ book: Book, completion: @escaping (Bool) -> Void) {
        // 跳过内置书籍
        if book.isBuiltIn {
            print("无法删除内置书籍: \(book.title)")
            completion(false)
            return
        }
        
        do {
            let documentsURL = try getDocumentsDirectory()
            let fileURL = documentsURL.appendingPathComponent(book.fileName)
            
            // 如果文件存在则删除
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
            
            // 删除进度信息
            removeBookProgress(bookId: book.id)
            
            completion(true)
        } catch {
            print("删除书籍时出错: \(error)")
            completion(false)
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
                lastAccessed: now
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
        
        let totalPages = metadata.progress[bookId]?.totalPages ?? 0
        let lastAccessed = metadata.progress[bookId]?.lastAccessed
        
        metadata.progress[bookId] = BookProgress(
            currentPageIndex: pageIndex,
            totalPages: totalPages,
            lastAccessed: lastAccessed
        )
        
        saveMetadata(metadata)
    }
    
    /// 保存书籍的总页数
    /// - Parameters:
    ///   - bookId: 书籍ID
    ///   - totalPages: 总页数
    func saveTotalPages(bookId: String, totalPages: Int) {
        var metadata = loadMetadata()
        
        let currentPage = metadata.progress[bookId]?.currentPageIndex ?? 0
        let lastAccessed = metadata.progress[bookId]?.lastAccessed
        
        metadata.progress[bookId] = BookProgress(
            currentPageIndex: currentPage,
            totalPages: totalPages,
            lastAccessed: lastAccessed
        )
        
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
    
    /// 获取文档目录URL
    /// - Returns: 文档目录URL，如果无法获取则抛出错误
    private func getDocumentsDirectory() throws -> URL {
        return try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }
    
    // MARK: - 元数据存储
    
    /// Structure for storing book progress information
    private struct LibraryMetadata: Codable {
        var progress: [String: BookProgress] = [:]
    }
    
    /// Loads metadata from disk, returns empty metadata if file doesn't exist
    private func loadMetadata() -> LibraryMetadata {
        do {
            let documentsURL = try getDocumentsDirectory()
            let metadataURL = documentsURL.appendingPathComponent(bookMetadataFile)
            
            // If file doesn't exist, return empty metadata
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
    
    /// Saves metadata to disk
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