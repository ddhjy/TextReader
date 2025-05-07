import Foundation

/// 书籍阅读进度模型，用于保存和恢复阅读位置
struct BookProgress: Codable {
    /// 当前页码索引
    let currentPageIndex: Int
    /// 书籍总页数
    let totalPages: Int
    /// 最后访问时间
    var lastAccessed: Date?
} 