import NaturalLanguage

struct Token {
    let id = UUID()
    let value: String
}

class Tokenizer {
    private let zhTokenizer = NLTokenizer(unit: .word)

    /// 返回包含字/词的 Token，已经去掉空白符
    func tokenize(text: String) -> [Token] {
        zhTokenizer.string = text
        var results:[Token] = []
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