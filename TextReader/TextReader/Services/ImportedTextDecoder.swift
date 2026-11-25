import Foundation

/// 把导入文件的原始字节解码成文本。
///
/// 中文 TXT 最常见的三种存法都要认：UTF‑8、GBK / GB18030（Windows 记事本「ANSI」），
/// 以及带 BOM 的 UTF‑16（记事本「Unicode」）。
enum ImportedTextDecoder {
    static func decode(_ data: Data) -> String? {
        guard !data.isEmpty else { return "" }

        if data.starts(with: [0xFF, 0xFE, 0x00, 0x00]) || data.starts(with: [0x00, 0x00, 0xFE, 0xFF]) {
            return String(data: data, encoding: .utf32)
        }
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            return String(data: data.dropFirst(3), encoding: .utf8)
        }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16)
        }

        if let text = String(data: data, encoding: .utf8) {
            return text
        }

        // 文本文件里不会出现 0 字节；有的话是二进制文件，按 GB18030 硬解只会得到乱码。
        guard !data.contains(0) else { return nil }
        return String(data: data, encoding: .gb_18030_2000)
    }
}
