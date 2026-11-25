import SwiftUI
import UIKit

struct SearchView: View {
    @ObservedObject var viewModel: ContentViewModel
    @State private var searchText = ""
    /// 搜索框是否处于激活状态。点搜索框自带的 × 会把它变成 false，这时直接关掉整个搜索页，
    /// 不用再去右上角找第二个 ×。
    @State private var isSearchPresented = true
    /// 拼音等输入法还没选字时，输入框里是一串字母；这期间不拿它去搜。
    @State private var composition = SearchCompositionState()
    /// 已经确定下来、真正拿去搜的词。界面显示结果、高亮、「未找到」都以它为准。
    @State private var committedQuery = ""
    /// 是否收到过输入框本身的改动通知。收不到时退回「文字一变就搜」，保证搜索始终可用。
    @State private var hasFieldEvents = false
    /// 键盘升起来之后是否已经重新对过一次位置。只对第一次，之后用户自己滚到哪儿就停在哪儿。
    @State private var hasPositionedAboveKeyboard = false
    @FocusState private var isSearchFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 「页面速览」里离当前阅读位置最近的那一行（速览是抽样的，不一定正好有当前页）。
    private var currentSummaryPageIndex: Int? {
        viewModel.pageSummaries.last(where: { $0.0 <= viewModel.currentPageIndex })?.0
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if committedQuery.isEmpty {
                    Section("页面速览") {
                        ForEach(viewModel.pageSummaries, id: \.0) { idx, preview in
                            resultCell(
                                page: idx,
                                preview: preview,
                                highlightQuery: nil,
                                isCurrentPosition: idx == currentSummaryPageIndex
                            )
                        }
                    }
                } else if viewModel.searchResults.isEmpty {
                    ContentUnavailableView.search(text: committedQuery)
                } else {
                    Section("\(viewModel.searchResults.count) 个结果") {
                        ForEach(viewModel.searchResults, id: \.0) { idx, preview in
                            resultCell(
                                page: idx,
                                preview: preview,
                                highlightQuery: committedQuery,
                                isCurrentPosition: false
                            )
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onScrollPhaseChange { _, newPhase, context in
                // 列表顶部开始下拉（含交互式关 sheet）时先收起键盘，
                // 避免 sheet 消失后键盘动画再带动后方阅读区。
                guard newPhase == .interacting, isSearchFocused else { return }
                let geometry = context.geometry
                if geometry.contentOffset.y + geometry.contentInsets.top <= 1 {
                    isSearchFocused = false
                }
            }
            .searchable(text: $searchText, isPresented: $isSearchPresented, prompt: "搜索内容")
            .searchFocused($isSearchFocused)
            .background {
                SheetDismissKeyboardObserver {
                    isSearchFocused = false
                }
            }
            .onAppear {
                applyQuery("")
                isSearchFocused = true
                scrollToCurrentPosition(using: proxy)
            }
            .onDisappear {
                isSearchFocused = false
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                // 刚打开时键盘还没升起来，位置是按整页高度对的：读到最后几页时，那一行正好落在键盘后面。
                // 键盘到位后按剩下的高度再对一次。
                guard !hasPositionedAboveKeyboard else { return }
                hasPositionedAboveKeyboard = true
                scrollToCurrentPosition(using: proxy, animated: true)
            }
            .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidChangeNotification)) { notification in
                // 系统搜索框背后有两个输入框对象：手指正在输入的那个，和一个只跟着同步文字的副本。
                // 副本永远没有「拼音还没选字」这个状态，按它判断会把拼音字母当成已经定下来的词去搜。
                guard let field = notification.object as? UISearchTextField, field.isFirstResponder else { return }
                hasFieldEvents = true
                handleTextChange(field.text ?? "", isComposing: field.markedTextRange != nil)
            }
            .onChange(of: searchText) { _, newText in
                // 输入框的通知和这里谁先到不一定，等这一轮事件处理完再看。
                DispatchQueue.main.async {
                    guard newText == searchText else { return }
                    if newText.isEmpty || !hasFieldEvents {
                        handleTextChange(newText, isComposing: false)
                    }
                }
            }
            .onSubmit(of: .search) {
                if let query = composition.commitCurrentText() {
                    applyQuery(query)
                }
            }
            .onChange(of: committedQuery) { _, newQuery in
                if newQuery.isEmpty {
                    scrollToCurrentPosition(using: proxy)
                }
            }
            .onChange(of: isSearchPresented) { _, isPresented in
                guard !isPresented else { return }
                isSearchFocused = false
                dismiss()
            }
        }
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .close) {
                    isSearchFocused = false
                    dismiss()
                }
                .accessibilityLabel("关闭")
            }
        }
    }

    private func handleTextChange(_ text: String, isComposing: Bool) {
        if let query = composition.handleTextChange(text, isComposing: isComposing) {
            applyQuery(query)
        }
    }

    private func applyQuery(_ query: String) {
        committedQuery = query
        viewModel.searchContent(query)
    }

    /// 「页面速览」打开时停在当前读到的位置，而不是每次都从第 1 页开始翻。
    private func scrollToCurrentPosition(using proxy: ScrollViewProxy, animated: Bool = false) {
        DispatchQueue.main.async {
            guard committedQuery.isEmpty, let target = currentSummaryPageIndex, target > 0 else { return }
            if animated && !reduceMotion {
                withAnimation {
                    proxy.scrollTo(target, anchor: .top)
                }
            } else {
                proxy.scrollTo(target, anchor: .top)
            }
        }
    }
    
    @ViewBuilder
    private func resultCell(page idx: Int,
                            preview: String,
                            highlightQuery: String?,
                            isCurrentPosition: Bool) -> some View {
        Button {
            isSearchFocused = false
            viewModel.jumpToSearchResult(pageIndex: idx)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("第 \(idx + 1) 页")
                        .foregroundStyle(.secondary)

                    if isCurrentPosition {
                        Text(currentPositionLabel(forSummaryPage: idx))
                            .fontWeight(.semibold)
                            .foregroundStyle(viewModel.currentAccentColor)
                    }
                }
                .font(.caption)

                if let highlightQuery, !highlightQuery.isEmpty {
                    Text(highlightedAttributedString(preview: preview, searchQuery: highlightQuery))
                        .font(.subheadline)
                        .lineLimit(2)
                } else {
                    Text(preview)
                        .font(.subheadline)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func currentPositionLabel(forSummaryPage idx: Int) -> String {
        idx == viewModel.currentPageIndex
            ? "读到这里"
            : "读到第 \(viewModel.currentPageIndex + 1) 页，在这附近"
    }
    
    private func highlightedAttributedString(preview: String, searchQuery: String) -> AttributedString {
        var attributed = AttributedString(preview)
        var searchStart = attributed.startIndex

        while searchStart < attributed.endIndex,
              let range = attributed[searchStart...].range(of: searchQuery, options: [.caseInsensitive]) {
            attributed[range].font = Font.subheadline.weight(.semibold)
            attributed[range].backgroundColor = viewModel.currentAccentColor.opacity(0.25)
            searchStart = range.upperBound
        }

        return attributed
    }
}
