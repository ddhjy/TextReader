import Foundation

struct Book: Identifiable {
    var id: String { fileName }
    var title: String
    let fileName: String
    let isBuiltIn: Bool
    /// 导入到书架的时间（取文件创建时间）。从未打开过的书按它排序，新导入的书会排在最前面。
    var addedAt: Date?
    
    init(title: String, fileName: String, isBuiltIn: Bool, addedAt: Date? = nil) {
        self.title = title
        self.fileName = fileName
        self.isBuiltIn = isBuiltIn
        self.addedAt = addedAt
    }
} 

extension String.Encoding {
    static let gb_18030_2000 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
} 
