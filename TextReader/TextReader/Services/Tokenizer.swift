import NaturalLanguage

struct Token {
    let id = UUID()
    let value: String
}

class Tokenizer {
    private let zhTokenizer = NLTokenizer(unit: .word)

    private let backgroundQueue = DispatchQueue(label: "com.textreader.tokenizer", qos: .userInitiated)

    func tokenize(text: String, completion: @escaping ([Token]) -> Void) {
        backgroundQueue.async {
            var allTokens: [(token: Token, range: Range<String.Index>)] = []
            
            self.zhTokenizer.string = text
            self.zhTokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
                let value = String(text[range])
                if !value.isEmpty {
                    allTokens.append((Token(value: value), range))
                }
                return true
            }
            
            var currentIndex = text.startIndex
            let sortedTokenRanges = allTokens.sorted(by: { $0.range.lowerBound < $1.range.lowerBound })
            
            for (_, tokenRange) in sortedTokenRanges {
                if currentIndex < tokenRange.lowerBound {
                    let gapRange = currentIndex..<tokenRange.lowerBound
                    let gapText = String(text[gapRange])
                    
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
            
            let sortedTokens = allTokens
                .sorted { $0.range.lowerBound < $1.range.lowerBound }
                .map { $0.token }
            
            DispatchQueue.main.async {
                completion(sortedTokens)
            }
        }
    }
} 