import Foundation

struct PromptTemplate: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var content: String      // 可包含 {selection}/{page}/{book}
    
    init(id: UUID = .init(), name: String, content: String) {
        self.id = id; self.name = name; self.content = content
    }
}

// 用于警告消息的可识别包装器
struct AlertMessage: Identifiable {
    let id = UUID()
    let message: String
} 