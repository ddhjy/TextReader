import SwiftUI

struct ContentDisplay: View {
    @ObservedObject var viewModel: ContentViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ScaledMetric(relativeTo: .body) private var scaledFontSize: CGFloat = 19
    private var effectiveFontSize: CGFloat {
        min(max(scaledFontSize, 15), 24)
    }
    private let kerning: CGFloat = 0.3
    private let lineSpacing: CGFloat = 8
    private let segmentSpacing: CGFloat = 22
    private let pageTurnAnimationDuration: TimeInterval = 0.25

    /// 各页实际渲染高度（按页索引缓存）。用于让聚焦遮罩的清晰窗口动态匹配当前页高度。
    @State private var pageHeights: [Int: CGFloat] = [:]

    /// 阅读区是否已揭示。首屏 / 切书时，内容会先经历「占位预览 → 最终分页 + 居中定位」，
    /// 这些过程全部就绪前保持隐藏，就绪后再淡入，避免用户看到错位与跳动。
    @State private var contentRevealed = false

    /// 已完成静默定位、正在等待「当前页几何回传」以便淡入。用于把淡入时机推迟到
    /// 聚焦蒙层能正确计算之后，避免出现「首屏整页全清晰、翻几页才有蒙层」。
    @State private var awaitingReveal = false

    /// 阅读区滚动位置。用状态而不是一次性 `scrollTo` 命令，回前台后的首次布局
    /// 会按当前页自动落位，避免后台听书推进页码后画面停在离开前的页。
    @State private var scrollPosition: ScrollPosition

    init(viewModel: ContentViewModel) {
        self.viewModel = viewModel
        _scrollPosition = State(
            initialValue: ScrollPosition(id: viewModel.currentPageIndex, anchor: .center)
        )
    }

    var body: some View {
        GeometryReader { geometry in
            content(geometry: geometry)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    @ViewBuilder
    private func content(geometry: GeometryProxy) -> some View {
        if viewModel.pages.isEmpty {
            emptyState(width: geometry.size.width, height: geometry.size.height)
        } else {
            scrollingContent(geometry: geometry)
        }
    }

    private func emptyState(width: CGFloat, height: CGFloat) -> some View {
        ContentUnavailableView {
            Label("开始阅读", systemImage: "books.vertical")
        } description: {
            Text("轻触书架选择书籍，或导入新的文本。")
        } actions: {
            Button("打开书架") {
                viewModel.showingBookList = true
            }
            .buttonStyle(.borderedProminent)
            .tint(viewModel.currentAccentColor)
        }
        .frame(width: width, height: height)
    }

    private func scrollingContent(geometry: GeometryProxy) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear
                    .frame(height: geometry.size.height * 0.5)

                LazyVStack(alignment: .leading, spacing: segmentSpacing) {
                    ForEach(viewModel.pages.indices, id: \.self) { idx in
                        PageTextView(
                            index: idx,
                            text: viewModel.pages[idx],
                            fontSize: effectiveFontSize,
                            kerning: kerning,
                            lineSpacing: lineSpacing,
                            isCurrentPage: idx == viewModel.currentPageIndex,
                            totalPages: viewModel.pages.count,
                            onPrevious: { viewModel.previousPage() },
                            onNext: { viewModel.nextPage() },
                            onBigBang: { viewModel.triggerBigBang() },
                            onHeightChange: { height in
                                if pageHeights[idx] != height {
                                    pageHeights[idx] = height
                                }
                                if idx == viewModel.currentPageIndex {
                                    revealIfCurrentPageMeasured()
                                }
                            }
                        )
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 24)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)

                Color.clear
                    .frame(height: geometry.size.height * 0.5)
            }
        }
        .scrollPosition($scrollPosition, anchor: .center)
        .scrollDisabled(true)
        .mask(focusGradient(containerHeight: geometry.size.height))
        .contentShape(Rectangle())
        .opacity(contentRevealed ? 1 : 0)
        .gesture(
            LongPressGesture(minimumDuration: 0.3)
                .onEnded { _ in
                    viewModel.triggerBigBang()
                }
        )
        .simultaneousGesture(
            SpatialTapGesture()
                .onEnded { value in
                    handleTapGesture(at: value.location, containerHeight: geometry.size.height)
                }
        )
        .onAppear {
            // 清除「静默翻页」残留标志：init / 缓存恢复阶段若把页码从 0 改到上次停留的
            // 非首页，会置位该标志；但首屏定位由下方 positionAndPrepareReveal 无动画完成、
            // 并不依赖它，且首屏 currentPageIndex 的基线已是目标页，不会触发 onChange 去
            // 消费它。若不在此清除，它会残留到用户「第一次手动翻页」时才被消费，导致首次
            // 翻页被误判为静默而丢失动画，要翻到第二页才恢复。
            _ = viewModel.consumePendingSilentPageScroll()
            positionAndPrepareReveal()
            // 兜底：极端情况下当前页几何始终未回传，超时后也强制定位并显示，避免永久留白。
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                forceReveal()
            }
        }
        .onChange(of: viewModel.isContentSettled) { _, settled in
            if settled {
                positionAndPrepareReveal()
            } else {
                // 切换书籍等场景回到占位预览：先淡出，待新内容就位后再淡入。
                awaitingReveal = false
                if reduceMotion {
                    contentRevealed = false
                } else {
                    withAnimation(.easeOut(duration: 0.18)) {
                        contentRevealed = false
                    }
                }
            }
        }
        .onChange(of: viewModel.currentPageIndex) { _, _ in
            // 切换书籍、加载/恢复内容、删除、搜索跳转等"非阅读语境"会通过
            // ViewModel 设置一次性标志；后台听书续页也会标静默。再叠加 scenePhase，
            // 避免回前台时把累计翻页补成一段滚动动画。
            let silent = viewModel.consumePendingSilentPageScroll()
            scrollToCurrentPage(animated: !silent && scenePhase == .active)
        }
        .onChange(of: viewModel.contentScrollRevision) { _, _ in
            scrollToCurrentPage(animated: false)
        }
        .onChange(of: viewModel.pages.count) { _, _ in
            scrollToCurrentPage(animated: false)
        }
        .onChange(of: scenePhase) { _, newPhase in
            // 回到前台：若滚动状态仍停在离开前的页，而无动画地对齐到当前朗读页。
            // 同时丢掉后台「前进又后退」净变化为零时残留的静默标志，避免下次手动翻页丢动画。
            guard newPhase == .active else { return }
            _ = viewModel.consumePendingSilentPageScroll()
            if scrollPosition.viewID(type: Int.self) != viewModel.currentPageIndex {
                scrollToCurrentPage(animated: false)
            }
        }
    }

    /// 把阅读区定位到当前页（居中）。滚动位置是视图状态，回前台后的首次布局会自动按它落位。
    private func scrollToCurrentPage(animated: Bool) {
        let target = viewModel.currentPageIndex
        if animated && !reduceMotion {
            withAnimation(.easeInOut(duration: pageTurnAnimationDuration)) {
                scrollPosition.scrollTo(id: target, anchor: .center)
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                scrollPosition.scrollTo(id: target, anchor: .center)
            }
        }
    }

    /// 内容进入「最终分页」后：先在隐藏状态下静默居中定位，随后等待当前页几何回传、
    /// 聚焦蒙层可正确计算时再淡入（见 `revealIfCurrentPageMeasured`），既消除首屏抖动，
    /// 又避免「整页全清晰、翻几页后蒙层才生效」。
    private func positionAndPrepareReveal() {
        guard viewModel.isContentSettled, !contentRevealed else { return }
        awaitingReveal = true
        DispatchQueue.main.async {
            scrollToCurrentPage(animated: false)
            // 当前页若已测得高度则立即淡入，否则等待其 onGeometryChange 回传后触发。
            revealIfCurrentPageMeasured()
        }
    }

    /// 当前页高度就绪后执行淡入（此刻聚焦蒙层才能正确罩住当前页）。
    private func revealIfCurrentPageMeasured() {
        guard awaitingReveal, !contentRevealed, viewModel.isContentSettled else { return }
        guard let height = pageHeights[viewModel.currentPageIndex], height > 1 else { return }
        awaitingReveal = false
        if reduceMotion {
            contentRevealed = true
        } else {
            withAnimation(.easeOut(duration: 0.22)) {
                contentRevealed = true
            }
        }
    }

    /// 兜底淡入：当前页几何迟迟未回传时也确保内容显示，避免永久留白。
    private func forceReveal() {
        guard !contentRevealed else { return }
        awaitingReveal = false
        DispatchQueue.main.async {
            scrollToCurrentPage(animated: false)
            DispatchQueue.main.async {
                guard !contentRevealed else { return }
                if reduceMotion {
                    contentRevealed = true
                } else {
                    withAnimation(.easeOut(duration: 0.22)) {
                        contentRevealed = true
                    }
                }
            }
        }
    }

    /// 聚焦遮罩：让「完全清晰」的窗口在垂直方向上动态等于当前页的实际高度
    /// （当前页通过 `scrollTo(anchor: .center)` 居中显示），当前页之外的上一页 /
    /// 下一页保持半透明，并在阅读区边缘自然淡出。
    ///
    /// 这样无论分页大小如何变化，清晰区都恰好罩住当前页：既保留聚焦渐隐效果，
    /// 又不会像固定百分比窗口那样把当前页自身的首尾行压暗。
    private func focusGradient(containerHeight: CGFloat) -> LinearGradient {
        // 当前页高度优先用实测值；尚未测得时（刚启动 / 切书后的个别帧）退化到已测页的
        // 参考高度，保证聚焦蒙层即时生效，避免出现「整页全清晰、翻几页后才有蒙层」。
        let measuredHeight = pageHeights[viewModel.currentPageIndex] ?? 0
        let pageHeight = measuredHeight > 1 ? measuredHeight : (representativePageHeight() ?? 0)

        // 连参考高度都没有时才退化为整屏清晰（随即会被测量结果修正）。
        guard containerHeight > 1, pageHeight > 1 else {
            return LinearGradient(colors: [.black], startPoint: .top, endPoint: .bottom)
        }

        let dimmed: CGFloat = 0.30        // 相邻页的半透明程度
        let clearPadding: CGFloat = 0.02  // 让当前页首尾行也完全清晰的额外余量
        let fade: CGFloat = 0.10          // 清晰 ↔ 半透明 的过渡带
        let edgeFade: CGFloat = 0.08      // 半透明 → 透明 的阅读区边缘渐隐

        let pageHalf = min(0.5, (pageHeight / containerHeight) / 2)
        let clearHalf = min(0.5, pageHalf + clearPadding)

        let clearTop = 0.5 - clearHalf
        let clearBottom = 0.5 + clearHalf
        let dimTop = max(0, clearTop - fade)
        let dimBottom = min(1, clearBottom + fade)
        let edgeTop = max(0, dimTop - edgeFade)
        let edgeBottom = min(1, dimBottom + edgeFade)

        return LinearGradient(
            stops: [
                .init(color: Color.black.opacity(0.0),    location: 0.0),
                .init(color: Color.black.opacity(dimmed), location: edgeTop),
                .init(color: Color.black.opacity(dimmed), location: dimTop),
                .init(color: Color.black,                 location: clearTop),
                .init(color: Color.black,                 location: clearBottom),
                .init(color: Color.black.opacity(dimmed), location: dimBottom),
                .init(color: Color.black.opacity(dimmed), location: edgeBottom),
                .init(color: Color.black.opacity(0.0),    location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// 当前页高度尚未测得时的参考高度：取已测各页高度的中位数作为「典型页高」，
    /// 让蒙层在当前页几何回传前也能给出接近正确的清晰窗口。
    private func representativePageHeight() -> CGFloat? {
        let measured = pageHeights.values.filter { $0 > 1 }.sorted()
        guard !measured.isEmpty else { return nil }
        return measured[measured.count / 2]
    }

    private func handleTapGesture(at location: CGPoint, containerHeight: CGFloat) {
        let isUpperArea = location.y < containerHeight / 2
        if isUpperArea {
            viewModel.previousPage()
        } else {
            viewModel.nextPage()
        }
    }
}

private struct PageTextView: View {
    let index: Int
    let text: String
    let fontSize: CGFloat
    let kerning: CGFloat
    let lineSpacing: CGFloat
    let isCurrentPage: Bool
    let totalPages: Int
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onBigBang: () -> Void
    let onHeightChange: (CGFloat) -> Void

    var body: some View {
        Text(text)
            .font(.system(size: fontSize))
            .kerning(kerning)
            .lineSpacing(lineSpacing)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .id(index)
            .accessibilityHidden(!isCurrentPage)
            .accessibilityLabel("书籍正文")
            .accessibilityValue("第 \(index + 1) 页，共 \(max(1, totalPages)) 页")
            .accessibilityAction(named: "上一页", onPrevious)
            .accessibilityAction(named: "下一页", onNext)
            .accessibilityAction(named: "分词与模板", onBigBang)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                onHeightChange(height)
            }
    }
}
