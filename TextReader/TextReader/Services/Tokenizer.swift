import NaturalLanguage

/// 表示文本中的一个标记（词语或字符）
struct Token {
    /// 唯一标识符
    let id = UUID()
    /// 标记的文本值
    let value: String
}

/// 文本分词器，负责将文本内容拆分为可识别的标记单元（词语/字符）
/// 主要用于BigBang功能，支持中文分词
class Tokenizer {
    /// 中文分词器，使用NL框架的词语单元
    private let zhTokenizer = NLTokenizer(unit: .word)

    /// 将输入文本分割成标记数组
    func tokenize(text: String) -> [Token] {
        zhTokenizer.string = text
        var results:[Token] = []
        
        // 枚举所有标记并创建Token对象
        zhTokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let t = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty {
                results.append(Token(value: t))
            }
            return true
        }
        
        return results
    }
} 