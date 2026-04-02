import Testing
@testable import TextReader

struct SearchCompositionStateTests {

    @Test
    func englishTypingPublishesEveryConfirmedChange() {
        var state = SearchCompositionState()

        #expect(state.handleTextChange("n", isComposing: false) == "n")
        #expect(state.handleTextChange("ni", isComposing: false) == "ni")
        #expect(state.handleTextChange("ni", isComposing: false) == nil)
    }

    @Test
    func chineseCompositionDoesNotPublishBeforeConfirmation() {
        var state = SearchCompositionState()

        #expect(state.handleTextChange("n", isComposing: true) == nil)
        #expect(state.handleTextChange("ni", isComposing: true) == nil)
        #expect(state.publishedText.isEmpty)
    }

    @Test
    func confirmedCandidatePublishesOnlyOnce() {
        var state = SearchCompositionState()

        #expect(state.handleTextChange("ni", isComposing: true) == nil)
        #expect(state.handleTextChange("你", isComposing: false) == "你")
        #expect(state.handleTextChange("你", isComposing: false) == nil)
    }

    @Test
    func clearingSearchPublishesEmptyText() {
        var state = SearchCompositionState()
        _ = state.handleTextChange("你好", isComposing: false)

        #expect(state.handleTextChange("", isComposing: false) == "")
    }

    @Test
    func endingEditingCommitsCurrentDisplayText() {
        var state = SearchCompositionState()
        state.replaceFromExternal("旧内容")

        #expect(state.handleTextChange("xin", isComposing: true) == nil)
        #expect(state.commitCurrentText() == "xin")
        #expect(state.publishedText == "xin")
    }
}
