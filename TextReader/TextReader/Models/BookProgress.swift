import Foundation

struct BookProgress: Codable {
    var currentPageIndex: Int
    var totalPages: Int
    var lastAccessed: Date?
    var cachedPages: [String]?  // 保留兼容性，但启动时不再使用
    var lastPageContent: String?  // 缓存上次阅读的页面内容，用于快速启动显示
} 