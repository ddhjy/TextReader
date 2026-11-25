import Foundation

/// 全局提示：导入、删除、保存等操作的结果统一从这里告诉用户，不再只写进控制台。
struct AppNotice: Identifiable, Equatable {
    enum Kind: Equatable {
        case info
        case success
        case error
    }

    let id: UUID
    let kind: Kind
    let message: String

    init(id: UUID = UUID(), kind: Kind, message: String) {
        self.id = id
        self.kind = kind
        self.message = message
    }

    /// 自动消失前停留的秒数。失败提示不自动消失，必须由用户点掉，避免没看清就没了。
    /// 其余的按字数给时间：一句短话 3 秒，句子越长停得越久，最多 8 秒。
    /// 「书架里已有《…》，新导入的已另存为《…》」这样的长句 3 秒读不完。
    var autoDismissDelay: TimeInterval? {
        switch kind {
        case .error:
            return nil
        case .info, .success:
            return min(8, max(3, 1.5 + 0.18 * Double(message.count)))
        }
    }
}
