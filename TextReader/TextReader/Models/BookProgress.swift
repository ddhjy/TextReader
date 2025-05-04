import Foundation

struct BookProgress: Codable {
    let currentPageIndex: Int
    let totalPages: Int
    var lastAccessed: Date?
} 