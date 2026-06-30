import Testing
@testable import TextReader

/// 验证分页粒度变化后，阅读进度按百分比平滑迁移的纯函数逻辑。
struct ProgressRemapTests {

    @Test
    func identityWhenTotalsAreEqual() {
        for index in [0, 1, 100, 2_184, 13_450] {
            #expect(ContentViewModel.remapPageIndex(index, oldTotal: 13_451, newTotal: 13_451) == index)
        }
    }

    @Test
    func firstPageMapsToFirstPage() {
        #expect(ContentViewModel.remapPageIndex(0, oldTotal: 10, newTotal: 5) == 0)
        #expect(ContentViewModel.remapPageIndex(0, oldTotal: 2_368, newTotal: 1_184) == 0)
    }

    @Test
    func lastPageMapsToLastPage() {
        #expect(ContentViewModel.remapPageIndex(9, oldTotal: 10, newTotal: 5) == 4)
        #expect(ContentViewModel.remapPageIndex(2_367, oldTotal: 2_368, newTotal: 1_184) == 1_183)
    }

    @Test
    func proportionalMappingWhenPagesGrow() {
        // 旧第 5 页（共 10 页，约 55% 处）→ 新 20 页中的第 11 页。
        #expect(ContentViewModel.remapPageIndex(5, oldTotal: 10, newTotal: 20) == 11)
    }

    @Test
    func proportionalMappingWhenPagesShrink() {
        // 旧第 5 页（共 10 页）→ 新 5 页中的第 2 页。
        #expect(ContentViewModel.remapPageIndex(5, oldTotal: 10, newTotal: 5) == 2)
    }

    @Test
    func handlesDegenerateInputsSafely() {
        #expect(ContentViewModel.remapPageIndex(3, oldTotal: 10, newTotal: 0) == 0)
        #expect(ContentViewModel.remapPageIndex(0, oldTotal: 1, newTotal: 5) == 0)
        #expect(ContentViewModel.remapPageIndex(-4, oldTotal: 10, newTotal: 5) == 0)
        // 旧页码越界时也应被收敛到新范围内。
        #expect(ContentViewModel.remapPageIndex(999, oldTotal: 10, newTotal: 5) == 4)
    }
}
