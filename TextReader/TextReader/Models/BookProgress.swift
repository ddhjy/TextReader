import Foundation

struct BookProgress: Codable {
    var currentPageIndex: Int
    var totalPages: Int
    var lastAccessed: Date?
    var cachedPages: [String]?  // 缓存的分页结果，避免重复分页
} 