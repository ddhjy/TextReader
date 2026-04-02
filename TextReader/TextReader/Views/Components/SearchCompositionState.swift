struct SearchCompositionState {
    private(set) var displayText = ""
    private(set) var publishedText = ""

    mutating func handleTextChange(_ text: String, isComposing: Bool) -> String? {
        displayText = text

        guard !isComposing else {
            return nil
        }

        return publishIfNeeded(text)
    }

    mutating func commitCurrentText() -> String? {
        publishIfNeeded(displayText)
    }

    mutating func replaceFromExternal(_ text: String) {
        displayText = text
        publishedText = text
    }

    private mutating func publishIfNeeded(_ text: String) -> String? {
        guard publishedText != text else {
            return nil
        }

        publishedText = text
        return text
    }
}
