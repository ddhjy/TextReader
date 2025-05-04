import Foundation

struct Book: Identifiable {
    var id: String { fileName }
    let title: String
    let fileName: String
    let isBuiltIn: Bool
    
    init(title: String, fileName: String, isBuiltIn: Bool) {
        self.title = title
        self.fileName = fileName
        self.isBuiltIn = isBuiltIn
    }
} 