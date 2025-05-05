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

// 添加对 GB18030 编码的支持
extension String.Encoding {
    static let gb_18030_2000 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
} 