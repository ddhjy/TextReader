import Foundation

class LibraryManager {
    
    private let bookMetadataFile = "library.json"
    private let fileManager = FileManager.default
    
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
    
    // MARK: - Book Management
    
    func loadBooks() -> [Book] {
        var allBooks: [Book] = []
        
        // 1. Load built-in books from bundle
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
        
        // 2. Load imported books from documents directory
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
            print("Error loading books from documents: \(error)")
        }
        
        return allBooks
    }
    
    func loadBookContent(book: Book, completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let url: URL
                
                if book.isBuiltIn {
                    // Load from main bundle
                    guard let bundleURL = Bundle.main.url(forResource: URL(fileURLWithPath: book.fileName).deletingPathExtension().lastPathComponent, withExtension: "txt") else {
                        completion(.failure(LibraryError.fileNotFound))
                        return
                    }
                    url = bundleURL
                } else {
                    // Load from documents directory
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
        // 增加日志：记录开始保存导入的内容
        print("[LibraryManager] Attempting to save imported content to filename: \(fileName)")
        do {
            let documentsURL = try getDocumentsDirectory()
            let fileURL = documentsURL.appendingPathComponent(fileName)
            print("[LibraryManager] Destination path: \(fileURL.path)")

            // 检查文件是否存在，如果存在则先删除（避免写入错误）
            if fileManager.fileExists(atPath: fileURL.path) {
                print("[LibraryManager] Destination file already exists. Removing old version.")
                do {
                    try fileManager.removeItem(at: fileURL)
                    print("[LibraryManager] Successfully removed existing file at destination.")
                } catch {
                    print("[LibraryManager][Error] Failed to remove existing file at \(fileURL.path): \(error.localizedDescription)")
                    // 根据策略决定是否继续（覆盖写入）或失败
                    // 这里选择继续尝试写入
                }
            }

            print("[LibraryManager] Writing content to destination using UTF-8 encoding.")
            // 始终使用 UTF-8 编码保存到应用内部存储，确保一致性
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            print("[LibraryManager] Successfully wrote content to destination.")

            // 使用建议的标题（如果提供）或从文件名中获取标题
            let title: String
            if let suggestedTitle = suggestedTitle {
                title = suggestedTitle
                print("[LibraryManager] Using suggested title: '\(title)'")
            } else {
                title = fileURL.deletingPathExtension().lastPathComponent
                print("[LibraryManager] Using filename-derived title: '\(title)'")
            }
            
            let newBook = Book(title: title, fileName: fileName, isBuiltIn: false)
            print("[LibraryManager] Created Book object: Title='\(title)', FileName='\(fileName)'")

            completion(.success(newBook))
        } catch {
            print("[LibraryManager][Error] Failed to save imported book content for \(fileName): \(error.localizedDescription)")
            completion(.failure(LibraryError.saveError))
        }
    }
    
    func importBookFromURL(_ url: URL, suggestedTitle: String? = nil, completion: @escaping (Result<Book, Error>) -> Void) {
        // 增加日志：记录 LibraryManager 开始处理 URL
        print("[LibraryManager] Starting import process for URL: \(url.absoluteString)")
        print("[LibraryManager] URL scheme: \(url.scheme ?? "nil"), is File URL: \(url.isFileURL)")
        print("[LibraryManager] Suggested title: \(suggestedTitle ?? "none")")

        // 检查是否是应用临时 Inbox 目录中的文件
        let isInInboxDirectory = url.path.contains("/tmp/") && url.path.contains("-Inbox/")
        if isInInboxDirectory {
            print("[LibraryManager] File is in app's Inbox directory, skipping security scope access")
        }

        // 尝试获取安全作用域访问权限（对于非 Inbox 文件）
        var securityAccessGranted = false
        if !isInInboxDirectory {
            securityAccessGranted = url.startAccessingSecurityScopedResource()
            print("[LibraryManager] Attempting to start security access for \(url.lastPathComponent)... Success: \(securityAccessGranted)")
            
            // 如果成功获取权限，确保在函数退出时停止访问
            if securityAccessGranted {
                defer {
                    url.stopAccessingSecurityScopedResource()
                    print("[LibraryManager] Stopped accessing security-scoped resource for: \(url.lastPathComponent)")
                }
            } else {
                print("[LibraryManager] Failed to access as security-scoped resource, will try direct access")
            }
        }

        // 无论安全访问是否成功，都尝试读取文件内容
        do {
            print("[LibraryManager] Attempting to read content from: \(url.path)")

            // 尝试使用多种编码读取文件内容
            var fileContent: String?
            var usedEncoding: String.Encoding?
            // 常用编码顺序：UTF-8，然后是 GBK/GB18030
            let encodingsToTry: [String.Encoding] = [.utf8, .gb_18030_2000] // .gb_18030_2000 兼容 GBK 和 GB2312

            for encoding in encodingsToTry {
                print("[LibraryManager] Trying encoding: \(encoding)")
                if let content = try? String(contentsOf: url, encoding: encoding) {
                    fileContent = content
                    usedEncoding = encoding
                    print("[LibraryManager] Successfully read content using encoding: \(encoding)")
                    break // 找到合适的编码后跳出循环
                } else {
                    print("[LibraryManager] Failed to read with encoding: \(encoding)")
                }
            }

            // 如果所有尝试的编码都失败，尝试复制文件到临时目录再读取
            if fileContent == nil {
                print("[LibraryManager] All direct reading attempts failed. Trying to copy file first...")
                if let (content, encoding) = tryReadingByCopyingFirst(url: url, encodingsToTry: encodingsToTry) {
                    fileContent = content
                    usedEncoding = encoding
                    print("[LibraryManager] Successfully read content after copying. Encoding: \(encoding)")
                }
            }

            // 如果仍然无法读取
            guard let content = fileContent, let encoding = usedEncoding else {
                print("[LibraryManager][Error] Failed to read content from \(url.path) with supported encodings.")
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
                print("[LibraryManager] Using suggested title for filename: \(fileName)")
            } else {
                fileName = originalFileName
                print("[LibraryManager] Using original filename: \(fileName)")
            }
            
            print("[LibraryManager] Successfully read content (Encoding: \(encoding)). Filename to use: \(fileName)")

            // 调用内部方法将内容写入应用文档目录
            importBook(fileName: fileName, content: content, suggestedTitle: suggestedTitle, completion: completion)

        } catch {
            print("[LibraryManager][Error] Unexpected error during file access for \(url.absoluteString): \(error.localizedDescription)")
            completion(.failure(LibraryError.readError("Unexpected error during file access: \(error.localizedDescription)")))
        }
    }
    
    /// 通过先复制文件到临时目录再读取的方式尝试获取内容
    private func tryReadingByCopyingFirst(url: URL, encodingsToTry: [String.Encoding]) -> (String, String.Encoding)? {
        do {
            // 创建临时文件URL
            let tempDirURL = FileManager.default.temporaryDirectory
            let tempFileURL = tempDirURL.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
            
            print("[LibraryManager] Copying file to temporary location: \(tempFileURL.path)")
            
            // 尝试复制文件
            try FileManager.default.copyItem(at: url, to: tempFileURL)
            print("[LibraryManager] File copied successfully")
            
            // 尝试从临时位置读取
            for encoding in encodingsToTry {
                if let content = try? String(contentsOf: tempFileURL, encoding: encoding) {
                    print("[LibraryManager] Successfully read temp file with encoding: \(encoding)")
                    
                    // 完成后删除临时文件
                    try? FileManager.default.removeItem(at: tempFileURL)
                    
                    return (content, encoding)
                }
            }
            
            // 没有成功读取，删除临时文件
            try? FileManager.default.removeItem(at: tempFileURL)
            print("[LibraryManager] Failed to read temp file with any encoding, removed temp file")
            
        } catch {
            print("[LibraryManager] Error copying file to temp location: \(error.localizedDescription)")
        }
        
        return nil
    }
    
    func deleteBook(_ book: Book, completion: @escaping (Bool) -> Void) {
        // Skip built-in books
        if book.isBuiltIn {
            print("Cannot delete built-in book: \(book.title)")
            completion(false)
            return
        }
        
        do {
            let documentsURL = try getDocumentsDirectory()
            let fileURL = documentsURL.appendingPathComponent(book.fileName)
            
            // Delete file if exists
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
            
            // Remove progress information
            removeBookProgress(bookId: book.id)
            
            completion(true)
        } catch {
            print("Error deleting book: \(error)")
            completion(false)
        }
    }
    
    // MARK: - Book Progress Management
    
    /// Returns the progress for a specific book
    func getBookProgress(bookId: String) -> BookProgress? {
        let metadata = loadMetadata()
        return metadata.progress[bookId]
    }
    
    /// Updates the last accessed timestamp for a book
    func updateLastAccessed(bookId: String) {
        var metadata = loadMetadata()
        let now = Date()

        // Check if progress record exists for the book
        if var progress = metadata.progress[bookId] {
            progress.lastAccessed = now
            metadata.progress[bookId] = progress
            print("[LibraryManager] Updated lastAccessed for bookId: \(bookId) to \(now)")
        } else {
            // 创建新的进度记录，而不只是发出警告
            print("[LibraryManager] Creating new progress record with lastAccessed for bookId: \(bookId)")
            metadata.progress[bookId] = BookProgress(
                currentPageIndex: 0,
                totalPages: 0,
                lastAccessed: now
            )
        }

        saveMetadata(metadata)
    }
    
    /// Saves the current page index for a book
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
    
    /// Saves the total number of pages for a book
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
    
    /// Removes progress information for a book
    private func removeBookProgress(bookId: String) {
        var metadata = loadMetadata()
        metadata.progress.removeValue(forKey: bookId)
        saveMetadata(metadata)
    }
    
    // MARK: - Helpers
    
    /// Returns the Documents directory URL
    private func getDocumentsDirectory() throws -> URL {
        return try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }
    
    // MARK: - Metadata Storage
    
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