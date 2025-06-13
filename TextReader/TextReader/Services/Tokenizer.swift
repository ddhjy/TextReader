import NaturalLanguage

/// 表示文本中的一个标记（词语或字符）
struct Token {
    let id = UUID()
    let value: String
}

/// 文本分词器，负责将文本内容拆分为可识别的标记单元（词语/字符）
/// 主要用于BigBang功能，支持中文分词
class Tokenizer {
    /// 中文分词器，使用NL框架的词语单元
    private let zhTokenizer = NLTokenizer(unit: .word)

    /// 在后台线程中执行分词操作
    private let backgroundQueue = DispatchQueue(label: "com.textreader.tokenizer", qos: .userInitiated)

    /// 将输入文本分割成标记数组
    func tokenize(text: String, completion: @escaping ([Token]) -> Void) {
        backgroundQueue.async {
            var allTokens: [(token: Token, range: Range<String.Index>)] = []
            
            // 1. 先进行词语分词
            self.zhTokenizer.string = text
            self.zhTokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
                let value = String(text[range])
                if !value.isEmpty {
                    allTokens.append((Token(value: value), range))
                }
                return true
            }
            
            // 2. 找出被忽略的标点符号和其他字符
            var currentIndex = text.startIndex
            let sortedTokenRanges = allTokens.sorted(by: { $0.range.lowerBound < $1.range.lowerBound })
            
            for (_, tokenRange) in sortedTokenRanges {
                // 检查当前位置到下一个token之间的内容
                if currentIndex < tokenRange.lowerBound {
                    let gapRange = currentIndex..<tokenRange.lowerBound
                    let gapText = String(text[gapRange])
                    
                    // 将间隙中的每个非空白字符作为独立token
                    var gapIndex = gapRange.lowerBound
                    for char in gapText {
                        let charStr = String(char)
                        if !charStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            let charRange = gapIndex..<text.index(after: gapIndex)
                            allTokens.append((Token(value: charStr), charRange))
                        }
                        gapIndex = text.index(after: gapIndex)
                    }
                }
                currentIndex = tokenRange.upperBound
            }
            
            // 处理最后一个token之后的内容
            if currentIndex < text.endIndex {
                let gapText = String(text[currentIndex..<text.endIndex])
                var gapIndex = currentIndex
                for char in gapText {
                    let charStr = String(char)
                    if !charStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        let charRange = gapIndex..<text.index(after: gapIndex)
                        allTokens.append((Token(value: charStr), charRange))
                    }
                    gapIndex = text.index(after: gapIndex)
                }
            }
            
            // 3. 按照在原文中的位置排序
            let sortedTokens = allTokens
                .sorted { $0.range.lowerBound < $1.range.lowerBound }
                .map { $0.token }
            
            DispatchQueue.main.async {
                completion(sortedTokens)
            }
        }
    }
} 