import Foundation

class LibraryManager {
    
    private let bookMetadataFile = "library.json"
    private let fileManager = FileManager.default
    
    enum LibraryError: Error {
        case fileNotFound
        case directoryAccessFailed
        case saveError
        case readError
        case fileImportError
        case deleteError
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
    
    func importBook(fileName: String, content: String, completion: @escaping (Result<Book, Error>) -> Void) {
        do {
            let documentsURL = try getDocumentsDirectory()
            let fileURL = documentsURL.appendingPathComponent(fileName)
            
            // Check if file exists and remove if needed
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
            
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            
            let title = fileURL.deletingPathExtension().lastPathComponent
            let newBook = Book(title: title, fileName: fileName, isBuiltIn: false)
            
            completion(.success(newBook))
        } catch {
            completion(.failure(error))
        }
    }
    
    func importBookFromURL(_ url: URL, completion: @escaping (Result<Book, Error>) -> Void) {
        guard url.startAccessingSecurityScopedResource() else {
            completion(.failure(LibraryError.fileImportError))
            return
        }
        
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let fileName = url.lastPathComponent
            
            importBook(fileName: fileName, content: content, completion: completion)
        } catch {
            completion(.failure(error))
        }
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
            print("Updated lastAccessed for bookId: \(bookId) to \(now)")
        } else {
            // For robustness, handle the case where no progress record exists yet
            print("Warning: Attempting to update lastAccessed for bookId (\(bookId)) with no existing progress record. Timestamp not saved.")
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