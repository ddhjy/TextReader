import Foundation

struct BookProgress: Codable {
    var currentPageIndex: Int
    var totalPages: Int
    var lastAccessed: Date?
    var cachedPages: [String]?
    var lastPageContent: String?
} 