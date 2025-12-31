import Foundation

struct PromptTemplate: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var content: String
    
    init(id: UUID = .init(), name: String, content: String) {
        self.id = id; self.name = name; self.content = content
    }
}

struct AlertMessage: Identifiable {
    let id = UUID()
    let message: String
} 