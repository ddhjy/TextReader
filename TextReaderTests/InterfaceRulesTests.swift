import AVFoundation
import CoreGraphics
import Foundation
import Testing
@testable import TextReader

struct AccentColorContrastTests {
    private let lightBackgrounds = ["#FFFFFF", "#F2F2F7"]
    private let darkBackgrounds = ["#000000", "#1C1C1E", "#2C2C2E"]

    /// 强调色会用来画文字、图标和选中标记，必须在它出现的每一种底色上都看得清。
    @Test
    func everyAccentColorIsReadableOnItsBackgrounds() throws {
        for theme in AccentColorTheme.presets {
            for background in lightBackgrounds {
                let ratio = try #require(AccentColorTheme.contrastRatio(theme.lightColor, background))
                #expect(ratio >= 4.5, "\(theme.name) 浅色 \(theme.lightColor) 压在 \(background) 上只有 \(ratio)")
            }
            for background in darkBackgrounds {
                let ratio = try #require(AccentColorTheme.contrastRatio(theme.darkColor, background))
                #expect(ratio >= 4.5, "\(theme.name) 深色 \(theme.darkColor) 压在 \(background) 上只有 \(ratio)")
            }
        }
    }

    /// 压在强调色上的对勾 / 文字：深色模式下「经典黑」的强调色几乎是白色，白对勾会看不见。
    @Test
    func foregroundOnAccentColorIsAlwaysVisible() throws {
        for theme in AccentColorTheme.presets {
            for hex in [theme.lightColor, theme.darkColor] {
                let foreground = AccentColorTheme.prefersDarkForeground(onHex: hex) ? "#000000" : "#FFFFFF"
                let ratio = try #require(AccentColorTheme.contrastRatio(foreground, hex))
                #expect(ratio >= 4.5, "\(theme.name) \(hex) 上的前景色对比度只有 \(ratio)")
            }
        }

        let black = try #require(AccentColorTheme.presets.first { $0.id == "black" })
        #expect(AccentColorTheme.prefersDarkForeground(onHex: black.darkColor))
        #expect(!AccentColorTheme.prefersDarkForeground(onHex: black.lightColor))
    }

    @Test
    func everyAccentColorHasADistinctVisibleName() {
        let names = AccentColorTheme.presets.map(\.name)
        #expect(names.allSatisfy { !$0.isEmpty })
        #expect(Set(names).count == names.count)
        #expect(Set(AccentColorTheme.presets.map(\.id)).count == names.count)
    }

    /// 强调色没换时，每次取到的必须是同一个颜色。不然界面每刷新一次（定时朗读时每秒两次）
    /// 系统都当成换了强调色，开着的菜单会跟着不停重画。
    @Test
    func theSameThemeAlwaysGivesTheSameColor() throws {
        for theme in AccentColorTheme.presets {
            #expect(theme.dynamicColor == theme.dynamicColor, "\(theme.name) 的强调色每次都不一样")
            #expect(theme.onAccentDynamicColor == theme.onAccentDynamicColor, "\(theme.name) 的前景色每次都不一样")
        }

        let blue = try #require(AccentColorTheme.presets.first { $0.id == "blue" })
        let green = try #require(AccentColorTheme.presets.first { $0.id == "green" })
        #expect(blue.dynamicColor != green.dynamicColor)
        // 强调色和压在它上面的前景色不是同一个颜色。
        #expect(blue.dynamicColor != blue.onAccentDynamicColor)
    }

    @Test
    func contrastMathMatchesKnownValues() throws {
        let blackOnWhite = try #require(AccentColorTheme.contrastRatio("#000000", "#FFFFFF"))
        #expect(abs(blackOnWhite - 21) < 0.001)
        #expect(AccentColorTheme.contrastRatio("#FFF", "#FFFFFF") == 1)
        #expect(AccentColorTheme.contrastRatio("不是颜色", "#FFFFFF") == nil)
    }
}

struct PromptTemplateStorageTests {
    @Test
    func templatesSavedByOlderVersionsKeepWorking() throws {
        let legacyJSON = """
        [
          {"id":"0C0260C2-2DCA-490C-8025-70870C0260C2","name":"总结式","content":"请用中文总结以下内容：{selection}"},
          {"id":"0C0260C2-2DCA-490C-8025-70870C0260C3","name":"将来的版本","content":"{page}","destination":"someFutureApp"},
          {"id":"0C0260C2-2DCA-490C-8025-70870C0260C4","name":"搜一下","content":"{selection}","destination":"perplexity"}
        ]
        """

        let templates = try JSONDecoder().decode([PromptTemplate].self, from: Data(legacyJSON.utf8))

        #expect(templates.map(\.name) == ["总结式", "将来的版本", "搜一下"])
        // 没有记录过去向的旧模板：第一次用时再问，而不是整份模板读不出来。
        #expect(templates[0].destination == nil)
        #expect(templates[1].destination == nil)
        #expect(templates[2].destination == .perplexity)
    }

    @Test
    func destinationSurvivesSaveAndLoad() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = TemplateManager(fileManager: .default, documentsDirectoryProvider: { directory })

        let defaults = manager.load()
        #expect(defaults.count == 2)
        // 自带的两条模板不会弹「去哪里」的选择，直接复制。
        #expect(defaults.allSatisfy { $0.destination == .copyOnly })

        var edited = defaults
        edited[0].destination = .raycast
        edited.append(PromptTemplate(name: "解释", content: "解释一下：{selection}"))
        #expect(manager.save(edited))

        let reloaded = manager.load()
        #expect(reloaded == edited)
        #expect(reloaded[0].destination == .raycast)
        #expect(reloaded[2].destination == nil)
    }

    @Test
    func everyDestinationHasAPlainName() {
        for destination in PromptTemplate.Destination.allCases {
            #expect(!destination.displayName.isEmpty)
            #expect(!destination.shortName.isEmpty)
        }
        #expect(PromptTemplate.Destination.copyOnly.displayName == "仅复制")
        #expect(PromptTemplate.Destination.raycast.displayName.contains("Raycast"))
    }
}

@MainActor
struct TokenSelectionRuleTests {
    private let ids = (0..<6).map { _ in UUID() }

    private func tap(_ index: Int, anchor: Int?, selected: [Int]) -> (selected: Set<Int>, anchor: Int?) {
        let result = ContentViewModel.tokenSelection(
            afterTapping: ids[index],
            anchor: anchor.map { ids[$0] },
            selected: Set(selected.map { ids[$0] }),
            orderedIDs: ids
        )
        let selectedIndexes = Set(result.selected.compactMap { ids.firstIndex(of: $0) })
        return (selectedIndexes, result.anchor.flatMap { ids.firstIndex(of: $0) })
    }

    @Test
    func firstTapSelectsOneWordAndMakesItTheStartingPoint() {
        let result = tap(2, anchor: nil, selected: [])
        #expect(result.selected == [2])
        #expect(result.anchor == 2)
    }

    @Test
    func tappingAnotherWordSelectsEverythingInBetween() {
        let forward = tap(4, anchor: 2, selected: [2])
        #expect(forward.selected == [2, 3, 4])
        #expect(forward.anchor == 2)

        let backward = tap(0, anchor: 2, selected: [2])
        #expect(backward.selected == [0, 1, 2])
        #expect(backward.anchor == 2)
    }

    @Test
    func tappingInsideTheRangeShrinksItToThatWord() {
        let result = tap(3, anchor: 1, selected: [1, 2, 3, 4, 5])
        #expect(result.selected == [1, 2, 3])
        #expect(result.anchor == 1)
    }

    @Test
    func tappingOnTheOtherSideOfTheStartFlipsTheRange() {
        let result = tap(0, anchor: 2, selected: [2, 3, 4])
        #expect(result.selected == [0, 1, 2])
        #expect(result.anchor == 2)
    }

    @Test
    func tappingTheStartingPointKeepsOnlyItThenClears() {
        let collapsed = tap(2, anchor: 2, selected: [2, 3, 4])
        #expect(collapsed.selected == [2])
        #expect(collapsed.anchor == 2)

        let cleared = tap(2, anchor: 2, selected: [2])
        #expect(cleared.selected.isEmpty)
        #expect(cleared.anchor == nil)
    }

    @Test
    func unknownWordChangesNothing() {
        let result = ContentViewModel.tokenSelection(
            afterTapping: UUID(),
            anchor: ids[1],
            selected: [ids[1], ids[2]],
            orderedIDs: ids
        )
        #expect(result.selected == [ids[1], ids[2]])
        #expect(result.anchor == ids[1])
    }

    @Test
    func theRuleIsWrittenOnThePage() {
        #expect(BigBangView.selectionHint(selectedCount: 0, anchorWord: nil) == "点一个词开始选。")
        #expect(BigBangView.selectionHint(selectedCount: 1, anchorWord: "勇气")
                == "再点另一个词，中间的会一起选上。再点一次「勇气」取消。")
        #expect(BigBangView.selectionHint(selectedCount: 4, anchorWord: "勇气")
                == "点别的词可以改范围。点起点「勇气」只留它一个。")
        #expect(BigBangView.selectionHint(selectedCount: 2, anchorWord: "Supercalifragilistic")
                .contains("「Superc…」"))
    }
}

@MainActor
struct InterfaceWordingTests {
    @Test
    func speedLabelsShowTheRealValue() {
        let labels = [0.8, 1.0, 1.25, 1.5, 1.75, 2.0, 3.0].map(SettingsView.speedLabel)
        #expect(labels == ["0.8x", "1.0x", "1.25x", "1.5x", "1.75x", "2.0x", "3.0x"])
        // Float 存下来的语速不是精确的小数，标签不能因此变样。
        #expect(SettingsView.speedLabel(Double(Float(0.8))) == "0.8x")
        #expect(SettingsView.speedLabel(Double(Float(1.25))) == "1.25x")
    }

    @Test
    func progressAlwaysCarriesAPercentSign() {
        func display(_ index: Int, _ total: Int) -> String? {
            ContentViewModel.formatBookProgressDisplay(
                BookProgress(currentPageIndex: index, totalPages: total, lastAccessed: nil, cachedPages: nil)
            )
        }

        #expect(display(0, 300) == "1%")
        #expect(display(149, 300) == "50%")
        #expect(display(298, 300) == "99%")
        #expect(display(299, 300) == "100%")
        #expect(display(0, 0) == nil)
        #expect(display(999, 300) == "100%")
    }

    @Test
    func importMessagesSayWhatHappenedToTheBook() {
        let plain = LibraryManager.ImportedBook(
            book: Book(title: "三体", fileName: "三体.txt", isBuiltIn: false),
            conflictingTitle: nil
        )
        #expect(ContentViewModel.importSuccessMessage(for: plain) == "已导入《三体》")

        let renamed = LibraryManager.ImportedBook(
            book: Book(title: "三体-2", fileName: "三体-2.txt", isBuiltIn: false),
            conflictingTitle: "三体"
        )
        #expect(ContentViewModel.importSuccessMessage(for: renamed) == "书架里已有《三体》，新导入的已另存为《三体-2》")

        #expect(ContentViewModel.importFailureMessage(for: LibraryManager.LibraryError.emptyContent)
                == "导入失败：文件里没有文字")
        #expect(ContentViewModel.importFailureMessage(for: LibraryManager.LibraryError.unsupportedEncoding)
                == "导入失败：无法识别文件编码，请另存为 UTF‑8 或 GBK 后再试")
        #expect(ContentViewModel.importFailureMessage(for: LibraryManager.LibraryError.readError("a.txt"))
                == "导入失败：无法读取「a.txt」")
        #expect(ContentViewModel.importFailureMessage(for: CocoaError(.fileNoSuchFile)) == "导入失败，请重试")
    }

    @Test
    func sharedImportMessagesCountWhatArrivedAndWhatDidNot() {
        #expect(ContentViewModel.sharedImportMessage(importedCount: 1, failedCount: 0, openedTitle: "文章")
                == "已导入《文章》")
        #expect(ContentViewModel.sharedImportMessage(importedCount: 3, failedCount: 0, openedTitle: "文章")
                == "已导入 3 本，现在打开的是《文章》")
        #expect(ContentViewModel.sharedImportMessage(importedCount: 1, failedCount: 2, openedTitle: "文章")
                == "已导入《文章》。另有 2 份没能存进书架，下次打开时会再试一次")
    }

    @Test
    func deletionMessagesNameTheBookThatIsNowOpen() {
        // 只删了一本别的书：那一行消失就是反馈。
        #expect(ContentViewModel.deletionMessage(deletedTitles: ["甲"], nowOpenTitle: nil) == nil)
        #expect(ContentViewModel.deletionMessage(deletedTitles: [], nowOpenTitle: nil) == nil)
        #expect(ContentViewModel.deletionMessage(deletedTitles: ["甲"], nowOpenTitle: "使用说明")
                == "已删除《甲》，现在打开的是《使用说明》")
        #expect(ContentViewModel.deletionMessage(deletedTitles: ["甲", "乙", "丙"], nowOpenTitle: nil)
                == "已删除 3 本书")
        #expect(ContentViewModel.deletionMessage(deletedTitles: ["甲", "乙"], nowOpenTitle: "丙")
                == "已删除 2 本书，现在打开的是《丙》")

        #expect(ContentViewModel.deletionFailureMessage(failedTitles: []) == nil)
        #expect(ContentViewModel.deletionFailureMessage(failedTitles: ["甲"]) == "《甲》没能删除，请重试")
        #expect(ContentViewModel.deletionFailureMessage(failedTitles: ["甲", "乙"]) == "有 2 本书没能删除，请重试")
    }

    @Test
    func deleteConfirmationSaysHowManyAndWhich() {
        func book(_ title: String) -> Book {
            Book(title: title, fileName: "\(title).txt", isBuiltIn: false)
        }

        #expect(BookListView.deleteConfirmationTitle(for: [book("三体")]) == "删除《三体》？")
        #expect(BookListView.deleteConfirmationTitle(for: [book("甲"), book("乙"), book("丙")]) == "删除 3 本书？")

        #expect(BookListView.deleteConfirmationMessage(for: [book("三体")], currentBookId: nil) == "删除后无法恢复。")
        #expect(BookListView.deleteConfirmationMessage(for: [book("三体")], currentBookId: "三体.txt")
                == "这是正在读的书。\n删除后无法恢复。")
        #expect(BookListView.deleteConfirmationMessage(for: [book("甲"), book("乙")], currentBookId: nil)
                == "《甲》、《乙》。\n删除后无法恢复。")
        #expect(BookListView.deleteConfirmationMessage(
            for: [book("甲"), book("乙"), book("丙"), book("丁"), book("戊")],
            currentBookId: "丁.txt"
        ) == "《甲》、《乙》、《丙》等 5 本。\n其中有正在读的书。\n删除后无法恢复。")
    }

    @Test
    func longTitlesAreShortenedInMessages() {
        let longTitle = String(repeating: "很长的书名", count: 10)
        #expect(ContentViewModel.shortTitle("三体") == "三体")
        #expect(ContentViewModel.shortTitle(longTitle) == String(longTitle.prefix(20)) + "…")
        #expect(ContentViewModel.shortTitle(longTitle, maxLength: 6) == "很长的书名很…")
    }

    @Test
    func wifiResultSummaryCountsSuccessesAndFailures() {
        func record(_ succeeded: Bool) -> WiFiTransferService.TransferRecord {
            WiFiTransferService.TransferRecord(
                id: UUID(), fileName: "a.txt", succeeded: succeeded, detail: "", date: Date()
            )
        }

        #expect(WiFiTransferView.recordsSummary(for: []) == "本次传书")
        #expect(WiFiTransferView.recordsSummary(for: [record(true), record(true)]) == "已收到 2 本")
        #expect(WiFiTransferView.recordsSummary(for: [record(false)]) == "1 个没传成功")
        #expect(WiFiTransferView.recordsSummary(for: [record(true), record(false), record(true)])
                == "已收到 2 本，1 个没传成功")
    }

    @Test
    func voicesAreGroupedByRegionWithMandarinFirst() {
        #expect(VoiceCatalog.sortedLanguages(["zh-HK", "zh-TW", "zh-CN", "zh-HK", "zh-SG"])
                == ["zh-CN", "zh-TW", "zh-HK", "zh-SG"])
        #expect(VoiceCatalog.regionTitle(forLanguage: "zh-CN") == "普通话（中国大陆）")
        #expect(VoiceCatalog.regionTitle(forLanguage: "zh-TW") == "国语（台湾）")
        #expect(VoiceCatalog.regionTitle(forLanguage: "zh-HK") == "粤语（香港）")
        #expect(VoiceCatalog.shortRegionTitle(forLanguage: "zh-HK") == "粤语")
        #expect(!VoiceCatalog.regionTitle(forLanguage: "zh-SG").isEmpty)
        #expect(VoiceCatalog.qualityTitle(for: .default) == nil)
        #expect(VoiceCatalog.qualityTitle(for: .enhanced) == "增强音质")
        #expect(VoiceCatalog.qualityTitle(for: .premium) == "高级音质")
    }

    @Test
    func perplexityLinkKeepsTheWholePrompt() throws {
        let prompt = "解释 a&b=c+d #1？What is 50% of x?"
        let url = try #require(ContentViewModel.perplexityURL(query: prompt))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(components.host == "www.perplexity.ai")
        #expect(components.path == "/search/new")
        #expect(components.fragment == nil)
        #expect(components.queryItems?.count == 1)
        #expect(components.queryItems?.first?.name == "q")
        #expect(components.percentEncodedQueryItems?.first?.value?.removingPercentEncoding == prompt)
    }
}

@MainActor
struct SleepTimerPickerGestureTests {
    private let options = ContentViewModel.sleepTimerOptions

    /// 按住播放键、手指没挪开就松手：这是一次点按，不能落进「什么都不发生」的缝里。
    @Test
    func releasingNearThePlayButtonCountsAsNotHavingMoved() {
        #expect(SleepTimerPicker.isInDeadZone(offsetFromCenter: .zero))
        #expect(SleepTimerPicker.isInDeadZone(offsetFromCenter: CGSize(width: 12, height: -18)))
        #expect(!SleepTimerPicker.isInDeadZone(offsetFromCenter: CGSize(width: 0, height: -60)))
        #expect(SleepTimerPicker.hitTest(offsetFromCenter: CGSize(width: 5, height: -10), options: options) == nil)
    }

    @Test
    func slidingOntoAnOptionSelectsIt() {
        for minutes in options {
            let offset = SleepTimerPicker.offset(forOption: minutes)
            #expect(SleepTimerPicker.hitTest(offsetFromCenter: offset, options: options) == minutes)
        }
        #expect(SleepTimerPicker.hitTest(offsetFromCenter: CGSize(width: 0, height: 80), options: options) == nil)
        #expect(SleepTimerPicker.hitTest(offsetFromCenter: CGSize(width: 96, height: -4), options: options) == nil)
    }
}
