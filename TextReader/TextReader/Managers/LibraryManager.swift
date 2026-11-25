import Foundation

class LibraryManager {
    
    private let bookMetadataFile = "library.json"
    private let unreadableMetadataBackupFile = "library.unreadable.json"
    private let fileManager: FileManager
    private let documentsDirectoryProvider: () throws -> URL
    private let builtInBooks: [BuiltInBook]
    /// 元数据会被主线程、进度保存队列、删除队列同时「读出 → 修改 → 写回」。
    /// 不加锁时后写回的会盖掉先写回的内容（例如刚改好的书名被一次进度保存冲掉）。
    private let metadataLock = NSLock()

    private static let importableExtensions = ["txt", "md"]
    /// APFS 文件名上限是 255 个 UTF‑8 字节；留出扩展名和重名后缀的余量。
    private static let maxBaseNameUTF8Bytes = 180

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
            title: "随心读示例文本",
            fileName: "__builtin_review_sample__",
            content: """
            随心读是一款面向中文阅读和朗读场景的轻量阅读工具。

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
        case emptyContent
    }

    /// 一次导入的结果。
    struct ImportedBook {
        let book: Book
        /// 书架里已经有同名的书时，这次导入会另存为新名字而不是覆盖原书；
        /// 这里记下原本想用的书名，方便告诉用户「已另存为…」。没有重名时为 nil。
        let conflictingTitle: String?
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
                includingPropertiesForKeys: [.creationDateKey],
                options: .skipsHiddenFiles
            )
            
            let importedFiles = fileURLs.filter { url in
                Self.importableExtensions.contains(url.pathExtension.lowercased())
            }
            let customTitles = readMetadata().titles ?? [:]
            
            let importedBooks = importedFiles.map { url in
                let fileName = url.lastPathComponent
                let title = customTitles[fileName] ?? url.deletingPathExtension().lastPathComponent
                let addedAt = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
                return Book(title: title, fileName: fileName, isBuiltIn: false, addedAt: addedAt)
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
                        DispatchQueue.main.async {
                            completion(.failure(LibraryError.fileNotFound))
                        }
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
                        DispatchQueue.main.async {
                            completion(.failure(LibraryError.fileNotFound))
                        }
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
    
    /// 把一段文本存成书架里的一本书。
    /// - Parameter overwriteExisting: 默认 `false`：书架里已有同名的书时另存为「书名-2」，
    ///   绝不悄悄覆盖原书（原书的内容和阅读进度都会保留）。
    @discardableResult
    func importBook(fileName: String,
                    content: String,
                    suggestedTitle: String? = nil,
                    overwriteExisting: Bool = false) throws -> ImportedBook {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LibraryError.emptyContent
        }

        do {
            return try importBookSynchronously(
                fileName: fileName,
                content: content,
                suggestedTitle: suggestedTitle,
                conflictPolicy: overwriteExisting ? .overwriteExisting : .createUniqueCopy
            )
        } catch {
            print("[LibraryManager][错误] 保存导入的书籍内容失败 \(fileName): \(error.localizedDescription)")
            throw error
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
        ).book
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
    
    @discardableResult
    func importBookFromURL(_ url: URL, suggestedTitle: String? = nil) throws -> ImportedBook {
        print("[LibraryManager] 开始导入URL: \(url.absoluteString)")

        let isInInboxDirectory = url.path.contains("/tmp/") && url.path.contains("-Inbox/")

        var securityAccessGranted = false
        if !isInInboxDirectory {
            securityAccessGranted = url.startAccessingSecurityScopedResource()
        }
        defer {
            if securityAccessGranted {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let data = (try? Data(contentsOf: url)) ?? readDataByCopyingFirst(url: url) else {
            print("[LibraryManager][错误] 无法读取 \(url.path)")
            throw LibraryError.readError(url.lastPathComponent)
        }

        guard let content = ImportedTextDecoder.decode(data) else {
            print("[LibraryManager][错误] 无法使用支持的编码从 \(url.path) 读取内容。")
            throw LibraryError.unsupportedEncoding
        }

        return try importBook(
            fileName: generateSafeFileName(from: url, suggestedTitle: suggestedTitle),
            content: content,
            suggestedTitle: suggestedTitle
        )
    }
    
    private func generateSafeFileName(from url: URL, suggestedTitle: String?) -> String {
        let baseName = trimmedNonEmpty(suggestedTitle)
            ?? url.deletingPathExtension().lastPathComponent
        return normalizedImportFileName("\(baseName).txt")
    }
    
    private func readDataByCopyingFirst(url: URL) -> Data? {
        let tempFile = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        defer { try? fileManager.removeItem(at: tempFile) }

        do {
            try fileManager.copyItem(at: url, to: tempFile)
            return try Data(contentsOf: tempFile)
        } catch {
            print("[LibraryManager][错误] 复制后读取文件失败: \(error.localizedDescription)")
            return nil
        }
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
                
                self.removeBookRecords(bookId: book.id)

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
    
    /// 改书名。文件名（也就是书的 id，阅读进度挂在它上面）保持不变，
    /// 新书名写进元数据，重启后仍然有效。
    @discardableResult
    func updateBookTitle(book: Book, newTitle: String) throws -> Book {
        guard !book.isBuiltIn,
              let title = trimmedNonEmpty(newTitle),
              persistTitle(title, forFileName: book.fileName) else {
            throw LibraryError.saveError
        }

        var updatedBook = book
        updatedBook.title = title
        return updatedBook
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
        readMetadata().progress[bookId]
    }
    
    func updateLastAccessed(bookId: String) {
        let now = Date()
        mutateMetadata { metadata in
            if var progress = metadata.progress[bookId] {
                progress.lastAccessed = now
                metadata.progress[bookId] = progress
            } else {
                metadata.progress[bookId] = BookProgress(
                    currentPageIndex: 0,
                    totalPages: 0,
                    lastAccessed: now,
                    cachedPages: nil
                )
            }
        }
    }
    
    func saveBookProgress(bookId: String, pageIndex: Int, totalPages: Int) {
        mutateMetadata { metadata in
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
        }
    }
    
    func saveTotalPages(bookId: String, totalPages: Int) {
        mutateMetadata { metadata in
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
        }
    }
    
    func getCachedPages(bookId: String) -> [String]? {
        return getBookProgress(bookId: bookId)?.cachedPages
    }
    
    func saveCachedPages(bookId: String, pages: [String]) {
        mutateMetadata { metadata in
            if var progress = metadata.progress[bookId] {
                progress.cachedPages = pages
                progress.totalPages = pages.count
                metadata.progress[bookId] = progress
            } else {
                metadata.progress[bookId] = BookProgress(
                    currentPageIndex: 0,
                    totalPages: pages.count,
                    lastAccessed: Date(),
                    cachedPages: pages
                )
            }
        }
    }
    
    func clearCachedPages(bookId: String) {
        mutateMetadata { metadata in
            if var progress = metadata.progress[bookId] {
                progress.cachedPages = nil
                metadata.progress[bookId] = progress
            }
        }
    }
    
    func saveLastPageContent(bookId: String, content: String) {
        mutateMetadata { metadata in
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
        }
    }

    /// 书的内容被整体替换后，旧内容的单页预览和整本缓存都不再可信。
    func clearContentCaches(bookId: String) {
        mutateMetadata { metadata in
            if var progress = metadata.progress[bookId] {
                progress.cachedPages = nil
                progress.lastPageContent = nil
                metadata.progress[bookId] = progress
            }
        }
    }
    
    private func removeBookRecords(bookId: String) {
        mutateMetadata { metadata in
            metadata.progress.removeValue(forKey: bookId)
            metadata.titles?.removeValue(forKey: bookId)
        }
    }

    /// - Returns: 是否成功写入磁盘。
    @discardableResult
    private func persistTitle(_ title: String?, forFileName fileName: String) -> Bool {
        let defaultTitle = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        return mutateMetadata { metadata in
            var titles = metadata.titles ?? [:]
            if let title, title != defaultTitle {
                titles[fileName] = title
            } else {
                titles.removeValue(forKey: fileName)
            }
            metadata.titles = titles.isEmpty ? nil : titles
        }
    }

    private func importBookSynchronously(fileName: String,
                                         content: String,
                                         suggestedTitle: String?,
                                         conflictPolicy: ImportConflictPolicy) throws -> ImportedBook {
        let documentsURL = try getDocumentsDirectory()
        let requestedFileName = normalizedImportFileName(fileName)
        let requestedBaseName = URL(fileURLWithPath: requestedFileName).deletingPathExtension().lastPathComponent
        let destinationURL = destinationURL(
            for: requestedFileName,
            conflictPolicy: conflictPolicy,
            documentsURL: documentsURL
        )
        let wasRenamed = destinationURL.lastPathComponent != requestedFileName

        if conflictPolicy == .overwriteExisting,
           fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try content.write(to: destinationURL, atomically: true, encoding: .utf8)

        let destinationBaseName = destinationURL.deletingPathExtension().lastPathComponent
        let requestedTitle = trimmedNonEmpty(suggestedTitle) ?? requestedBaseName
        // 被改名的副本用「书名-2」做书名：两本同名的书在书架上必须能分清。
        let resolvedTitle = wasRenamed ? destinationBaseName : requestedTitle
        persistTitle(resolvedTitle, forFileName: destinationURL.lastPathComponent)

        let addedAt = (try? destinationURL.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date()
        let newBook = Book(
            title: resolvedTitle,
            fileName: destinationURL.lastPathComponent,
            isBuiltIn: false,
            addedAt: addedAt
        )
        print("[LibraryManager] 创建书籍对象: 标题='\(resolvedTitle)', 文件名='\(destinationURL.lastPathComponent)'")

        return ImportedBook(book: newBook, conflictingTitle: wasRenamed ? requestedTitle : nil)
    }

    private func destinationURL(for normalizedFileName: String,
                                conflictPolicy: ImportConflictPolicy,
                                documentsURL: URL) -> URL {
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

    /// 导入时实际会用的文件名：去掉不能用的字符、限制长度，扩展名统一成书架认识的 txt / md。
    func normalizedImportFileName(_ fileName: String) -> String {
        let candidateURL = URL(fileURLWithPath: fileName)
        let rawExtension = candidateURL.pathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let baseName: String
        let normalizedExtension: String
        if Self.importableExtensions.contains(rawExtension) {
            baseName = candidateURL.deletingPathExtension().lastPathComponent
            normalizedExtension = rawExtension
        } else {
            // 「第1.5章」这类名字里的点不是扩展名；存成别的扩展名书架会认不出这本书。
            baseName = candidateURL.lastPathComponent
            normalizedExtension = "txt"
        }

        let sanitizedBaseName = Self.truncated(sanitizedImportedTitle(baseName), maxUTF8Bytes: Self.maxBaseNameUTF8Bytes)
        return "\(sanitizedBaseName).\(normalizedExtension)"
    }

    private static func truncated(_ text: String, maxUTF8Bytes: Int) -> String {
        guard text.utf8.count > maxUTF8Bytes else { return text }

        var result = ""
        var byteCount = 0
        for character in text {
            let characterBytes = String(character).utf8.count
            if byteCount + characterBytes > maxUTF8Bytes { break }
            result.append(character)
            byteCount += characterBytes
        }

        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "分享内容" : trimmed
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
        /// 用户改过的书名，键是文件名。必须是可选的：旧版本写的元数据里没有这个字段，
        /// 非可选会让整份元数据解码失败，所有阅读进度随之丢失。
        var titles: [String: String]?
    }

    private func readMetadata() -> LibraryMetadata {
        metadataLock.lock()
        defer { metadataLock.unlock() }
        return loadMetadataUnlocked()
    }

    /// - Returns: 修改后的元数据是否成功写入磁盘。
    @discardableResult
    private func mutateMetadata(_ body: (inout LibraryMetadata) -> Void) -> Bool {
        metadataLock.lock()
        defer { metadataLock.unlock() }
        var metadata = loadMetadataUnlocked()
        body(&metadata)
        return saveMetadataUnlocked(metadata)
    }
    
    private func loadMetadataUnlocked() -> LibraryMetadata {
        let metadataURL: URL
        do {
            metadataURL = try getDocumentsDirectory().appendingPathComponent(bookMetadataFile)
        } catch {
            print("Error locating metadata: \(error). Using empty metadata.")
            return LibraryMetadata()
        }

        guard fileManager.fileExists(atPath: metadataURL.path) else {
            return LibraryMetadata()
        }

        do {
            let data = try Data(contentsOf: metadataURL)
            return try JSONDecoder().decode(LibraryMetadata.self, from: data)
        } catch {
            print("Error loading metadata: \(error). Using empty metadata.")
            // 接下来的保存会用空元数据覆盖这个文件；先留一份副本，读不出来的进度至少还能找回。
            let backupURL = metadataURL.deletingLastPathComponent().appendingPathComponent(unreadableMetadataBackupFile)
            if !fileManager.fileExists(atPath: backupURL.path) {
                try? fileManager.copyItem(at: metadataURL, to: backupURL)
            }
            return LibraryMetadata()
        }
    }
    
    private func saveMetadataUnlocked(_ metadata: LibraryMetadata) -> Bool {
        do {
            let documentsURL = try getDocumentsDirectory()
            let metadataURL = documentsURL.appendingPathComponent(bookMetadataFile)
            
            let data = try JSONEncoder().encode(metadata)
            try data.write(to: metadataURL, options: .atomic)
            return true
        } catch {
            print("Error saving metadata: \(error)")
            return false
        }
    }
} 

extension LibraryManager.LibraryError {
    /// 给用户看的原因，用于界面提示。
    var userMessage: String {
        switch self {
        case .fileNotFound:
            return "找不到这本书的文件"
        case .directoryAccessFailed:
            return "无法访问存储空间"
        case .saveError:
            return "保存失败"
        case .readError(let detail):
            return detail.isEmpty ? "无法读取文件" : "无法读取「\(detail)」"
        case .fileImportError(let detail):
            return detail.isEmpty ? "导入失败" : detail
        case .deleteError:
            return "删除失败"
        case .securityAccessError:
            return "没有读取这个文件的权限"
        case .unsupportedEncoding:
            return "无法识别文件编码，请另存为 UTF‑8 或 GBK 后再试"
        case .emptyContent:
            return "文件里没有文字"
        }
    }
}
