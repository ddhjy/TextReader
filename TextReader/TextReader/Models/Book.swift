import Foundation

/// 书籍模型，表示应用中的一本书
struct Book: Identifiable {
    /// 书籍唯一标识符，使用文件名作为ID
    var id: String { fileName }
    /// 书籍标题
    let title: String
    /// 书籍文件名
    let fileName: String
    /// 是否是内置书籍
    let isBuiltIn: Bool
    
    /// 初始化书籍模型
    /// - Parameters:
    ///   - title: 书籍标题
    ///   - fileName: 书籍文件名，同时作为唯一标识符
    ///   - isBuiltIn: 是否是内置书籍
    init(title: String, fileName: String, isBuiltIn: Bool) {
        self.title = title
        self.fileName = fileName
        self.isBuiltIn = isBuiltIn
    }
} 

/// 添加对 GB18030 编码的支持（中文文本常用编码）
extension String.Encoding {
    /// GB18030-2000 中文编码标准
    static let gb_18030_2000 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
} 