import Foundation

struct Book: Identifiable {
    let id: String
    let title: String
    let fileName: String
    let isBuiltIn: Bool
    
    init(title: String, fileName: String, isBuiltIn: Bool) {
        self.id = UUID().uuidString
        self.title = title
        self.fileName = fileName
        self.isBuiltIn = isBuiltIn
    }
} 