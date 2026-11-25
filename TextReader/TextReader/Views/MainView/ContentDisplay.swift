import SwiftUI
import UIKit

/// 阅读区里一次按压已经发生过什么。
/// 用引用类型：手势回调里要立刻读到最新值，等不到下一次视图刷新。
private final class ReaderPressTracker {
    var isTracking = false
    /// 这次按压里手指离起点最远到过多远。
    var maxDistance: CGFloat = 0
    var longPressFired = false
    var longPressWorkItem: DispatchWorkItem?

    func reset() {
        longPressWorkItem?.cancel()
        longPressWorkItem = nil
        isTracking = false
        maxDistance = 0
        longPressFired = false
    }
}

private struct ReaderPageIndexKey: LayoutValueKey {
    static let defaultValue = -1
}

enum ReaderPagePlacement {
    /// 正在读的那一页，顶边离阅读区上沿多远。
    ///
    /// 平时居中。阅读区最下面 `bottomReserve` 这么高的一段上面，会浮着「定时停止」「回到第 N 页」
    /// 「导入第一本书」这排按钮；页很高、居中后末尾几行会伸进这一段时，整页往上让，
    /// 让开为止，最多让到顶住阅读区上沿。位置只由页高决定，按钮出现、消失时正文不用跟着挪。
    /// 比阅读区还高的页怎么放都放不下，仍然居中。
    static func focusedPageTop(pageHeight: CGFloat, containerHeight: CGFloat, bottomReserve: CGFloat) -> CGFloat {
        let centered = (containerHeight - pageHeight) / 2
        guard centered > 0 else { return centered }
        let overflow = centered + pageHeight - (containerHeight - bottomReserve)
        guard overflow > 0 else { return centered }
        return centered - min(overflow, centered)
    }
}

/// 阅读区的排版：正在读的那一页放在正中（很高的页略往上，见 `ReaderPagePlacement`），
/// 前后各页按各自量到的高度依次往上、往下排。
///
/// 阅读区从不让手指直接拖动，翻页全是程序定位，所以不用 ScrollView + LazyVStack：
/// 懒加载列表对没排过的行只能估高度，按页定位时会落偏（从后面翻回第一页最明显），
/// 之后每重新排一次版正文就再挪一截，直到滑出屏幕。这里每一页的位置都由实际高度直接算出，没有估算。
private struct ReaderPageColumn: Layout {
    var focusedPage: Int
    var spacing: CGFloat
    var bottomReserve: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let rowProposal = ProposedViewSize(width: bounds.width, height: nil)
        let heights = subviews.map { $0.sizeThatFits(rowProposal).height }

        // 排出来的页总是围着正在读的那一页取的；万一它不在里面，以最接近的一页为准。
        var anchor = 0
        var smallestDistance = Int.max
        for (position, subview) in subviews.enumerated() {
            let distance = abs(subview[ReaderPageIndexKey.self] - focusedPage)
            if distance < smallestDistance {
                smallestDistance = distance
                anchor = position
            }
        }

        var tops = [CGFloat](repeating: 0, count: subviews.count)
        tops[anchor] = bounds.minY + ReaderPagePlacement.focusedPageTop(
            pageHeight: heights[anchor],
            containerHeight: bounds.height,
            bottomReserve: bottomReserve
        )
        for position in stride(from: anchor - 1, through: 0, by: -1) {
            tops[position] = tops[position + 1] - spacing - heights[position]
        }
        for position in subviews.indices where position > anchor {
            tops[position] = tops[position - 1] + heights[position - 1] + spacing
        }

        for (position, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX, y: tops[position]),
                anchor: .topLeading,
                proposal: rowProposal
            )
        }
    }
}

struct ContentDisplay: View {
    @ObservedObject var viewModel: ContentViewModel
    /// 首屏「导入第一本书」打开的导入弹层是否盖在阅读区上（它不归 ViewModel 管，由外面告知）。
    let isCoveredByImportSheet: Bool
    /// 阅读区最下面有多高的一段会被控制栏上方那排浮动按钮盖住。
    let bottomReserve: CGFloat
    @Environment(\.scenePhase) private var scenePhase

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var scaledFontSize: CGFloat = ReaderTypography.baseFontSize

    /// 正文字号跟随系统「文字大小」。每页放多少字由 ViewModel 按同一个字号换算，保证一页放得进一屏。
    private var fontSize: CGFloat { ReaderTypography.clampedFontSize(scaledFontSize) }
    private let segmentSpacing: CGFloat = 22
    private let pageTurnAnimationDuration: TimeInterval = 0.25
    private let readableColumnWidth: CGFloat = 680

    /// 按住这么久算「长按选词」。短于它松手一律算点按翻页，两者不会同时发生。
    private let longPressDuration: TimeInterval = 0.5
    /// 手指挪动超过这个距离就不再算长按。
    private let longPressMovementTolerance: CGFloat = 10
    /// 手指挪动超过这个距离算滑动翻页。
    private let swipeDistance: CGFloat = 24
    /// 「上一页」点按区域的最小高度。当前页很高、顶到阅读区上沿时，上面几乎没有变淡的文字可点，
    /// 这时仍在最上面留出一条能点中的区域。
    private let minimumPreviousTapZone: CGFloat = 64
    private let boundaryBounceDistance: CGFloat = 14

    @State private var press = ReaderPressTracker()
    /// 手指是否按在阅读区上。手势被系统打断时不会走 `onEnded`，靠它复位来收尾。
    @GestureState private var isPressingReader = false
    /// 翻到头时整块阅读区顶一下再弹回的位移。
    @State private var boundaryBounceOffset: CGFloat = 0

    /// 实际排出来的只有正在读的那一页和它前后各这么多页。翻页只在相邻页之间滑动，更远的页不用排。
    private let pageWindowRadius = 5
    private static let readerSpace = "reader"

    /// 阅读区正中摆的是哪一页。和 `viewModel.currentPageIndex` 分开存，
    /// 是为了由这里决定这次换页要不要带滑动动画。
    @State private var displayedPageIndex: Int

    /// 各页在阅读区坐标系中的实测帧。静止时蒙层用当前页帧保证朗读内容不被压暗；
    /// 翻页动画期间不用它直接驱动蒙层，否则清晰窗口会先跳到下一页的当前位置再跟着上移。
    @State private var pageFrames: [Int: CGRect] = [:]
    /// `pageFrames` 是哪一批正文量出来的（见 `ContentViewModel.pagesGeneration`）。
    @State private var pageFramesGeneration = 0

    /// 只认当前这批正文量出来的帧：整批换内容后，上一批的帧在新的一批量好之前一律当作没有。
    private var measuredFrames: [Int: CGRect] {
        pageFramesGeneration == viewModel.pagesGeneration ? pageFrames : [:]
    }

    /// 蒙层清晰窗口在阅读区中的位置。与页码解耦，由翻页动画单独插值：高度上下同时收放，
    /// 窗口本身留在视口中央，正文滑入后再与实测帧对齐。
    @State private var focusMinY: CGFloat = 0
    @State private var focusMaxY: CGFloat = 0
    @State private var hasFocusWindow = false
    @State private var pageTurnInProgress = false
    @State private var pageTurnGeneration = 0

    /// 阅读区是否已揭示。首屏 / 切书时，内容会先经历「占位预览 → 最终分页 + 居中定位」，
    /// 这些过程全部就绪前保持隐藏，就绪后再淡入，避免用户看到错位与跳动。
    @State private var contentRevealed = false

    /// 已完成静默定位、正在等待「当前页几何回传」以便淡入。用于把淡入时机推迟到
    /// 聚焦蒙层能正确计算之后，避免出现「首屏整页全清晰、翻几页才有蒙层」。
    @State private var awaitingReveal = false

    /// 揭示前「布局是否已稳定」的检查轮次。启动过渡期阅读区的高度还会变几次，
    /// 只看当前页已测得就淡入，正文会在淡入过程中整体挪动几点。
    @State private var revealCheckGeneration = 0
    private let revealSettleInterval: TimeInterval = 1.0 / 30
    private let maxRevealSettleChecks = 6

    /// 阅读区的稳定高度，当前页以它的中线为准居中。搜索 sheet / 键盘进出时 GeometryReader
    /// 会短暂给出缩小后的高度；若直接采用，当前页会整体偏移一下再跳回。
    /// 忽略这类瞬时抖动，只在旋转等真实尺寸变化时更新。
    @State private var settledViewportHeight: CGFloat = 0
    @State private var settledViewportWidth: CGFloat = 0
    @State private var settledSafeAreaTop: CGFloat = 0
    @State private var latestProposedHeight: CGFloat = 0
    @State private var latestProposedWidth: CGFloat = 0
    @State private var latestProposedSafeAreaTop: CGFloat = 0

    init(viewModel: ContentViewModel, isCoveredByImportSheet: Bool = false, bottomReserve: CGFloat = 0) {
        self.viewModel = viewModel
        self.isCoveredByImportSheet = isCoveredByImportSheet
        self.bottomReserve = bottomReserve
        _displayedPageIndex = State(initialValue: viewModel.currentPageIndex)
    }

    var body: some View {
        GeometryReader { geometry in
            content(geometry: geometry)
                .frame(
                    width: geometry.size.width,
                    height: viewportHeight(from: geometry.size.height),
                    alignment: .top
                )
                .onAppear {
                    rememberProposedGeometry(geometry)
                    adoptViewportHeight(geometry.size.height)
                }
                .onChange(of: geometry.size) { _, _ in
                    rememberProposedGeometry(geometry)
                    adoptViewportHeight(geometry.size.height)
                }
                .onChange(of: geometry.safeAreaInsets) { _, _ in
                    rememberProposedGeometry(geometry)
                    adoptViewportHeight(geometry.size.height)
                }
        }
        .ignoresSafeArea(.keyboard)
        .background {
            ReaderKeyboardIsolation()
        }
        .transaction { transaction in
            // sheet / 键盘进出时禁止阅读区跟系统弹簧一起做动画。
            if isReaderCoveredBySheet {
                transaction.disablesAnimations = true
                transaction.animation = nil
            }
        }
    }

    private var isReaderCoveredBySheet: Bool {
        viewModel.showingSearchView
            || viewModel.showingBookList
            || viewModel.showingSettings
            || viewModel.showingBigBang
            || isCoveredByImportSheet
    }

    private func viewportHeight(from proposed: CGFloat) -> CGFloat {
        settledViewportHeight > 1 ? settledViewportHeight : proposed
    }

    private func rememberProposedGeometry(_ geometry: GeometryProxy) {
        latestProposedWidth = geometry.size.width
        latestProposedHeight = geometry.size.height
        latestProposedSafeAreaTop = geometry.safeAreaInsets.top
    }

    private func settleViewport(height: CGFloat) {
        settledViewportHeight = height
        if latestProposedWidth > 1 {
            settledViewportWidth = latestProposedWidth
        }
        settledSafeAreaTop = latestProposedSafeAreaTop
    }

    private func adoptViewportHeight(_ proposed: CGFloat) {
        guard proposed > 1 else { return }

        // sheet 盖住阅读区时只记下最新提议高度，不改居中基准。
        if isReaderCoveredBySheet {
            if settledViewportHeight <= 1 {
                settleViewport(height: proposed)
            }
            return
        }

        if settledViewportHeight <= 1 {
            settleViewport(height: proposed)
            return
        }

        // 顶部安全区（导航栏）变化引起的高度变化是真实布局变化：键盘只影响底部，
        // 而启动过渡期导航栏会从过渡高度收敛到最终高度。此时必须跟随，
        // 否则阅读区会被永久锁在首帧的过渡尺寸上（比实际可用区域矮几十点）。
        let safeAreaTopChanged = abs(latestProposedSafeAreaTop - settledSafeAreaTop) > 0.5
        if safeAreaTopChanged {
            settleViewport(height: proposed)
            recenterCurrentPage()
            return
        }

        // 宽度没变时的高度变化来自键盘，不是旋转 / 分屏。
        if latestProposedWidth > 1, settledViewportWidth > 1,
           abs(latestProposedWidth - settledViewportWidth) < 1 {
            return
        }

        // 搜索 sheet 转场时高度常抖十几到几十点。小于 8% 视为瞬时抖动并忽略；
        // 旋转 / 分屏会明显超过这个比例，再更新并重新居中。
        let heightDelta = abs(proposed - settledViewportHeight)
        let widthDelta = (latestProposedWidth > 1 && settledViewportWidth > 1)
            ? abs(latestProposedWidth - settledViewportWidth) / settledViewportWidth
            : 0
        guard heightDelta / settledViewportHeight > 0.08 || widthDelta > 0.08 else { return }
        settleViewport(height: proposed)
        recenterCurrentPage()
    }

    @ViewBuilder
    private func content(geometry: GeometryProxy) -> some View {
        if viewModel.pages.isEmpty {
            emptyState(width: geometry.size.width, height: geometry.size.height)
        } else {
            readerContent(geometry: geometry)
        }
    }

    private func emptyState(width: CGFloat, height: CGFloat) -> some View {
        ContentUnavailableView {
            Label("开始阅读", systemImage: "books.vertical")
        } description: {
            Text("从书架选择一本书，或导入文本开始阅读。")
        } actions: {
            Button("打开书架") {
                viewModel.showingBookList = true
            }
        }
        .frame(width: width, height: height)
    }

    /// 实际排出来的页：正在读的那一页和它前后各几页。
    private var pageWindow: Range<Int> {
        let count = viewModel.pages.count
        guard count > 0 else { return 0..<0 }
        let center = min(max(displayedPageIndex, 0), count - 1)
        return max(0, center - pageWindowRadius)..<min(count, center + pageWindowRadius + 1)
    }

    private func readerContent(geometry: GeometryProxy) -> some View {
        let containerHeight = viewportHeight(from: geometry.size.height)
        let generation = viewModel.pagesGeneration
        return ReaderPageColumn(
            focusedPage: displayedPageIndex,
            spacing: segmentSpacing,
            bottomReserve: bottomReserve
        ) {
            ForEach(pageWindow, id: \.self) { idx in
                pageRow(idx: idx, generation: generation)
                    .layoutValue(key: ReaderPageIndexKey.self, value: idx)
            }
        }
        // 每换一批正文就换一批全新的行，上一批量到的位置不会混进这一批里。
        .id(generation)
        .padding(.horizontal, 20)
        .frame(maxWidth: readableColumnWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(.named(Self.readerSpace))
        // 前后几页会排到阅读区外面（导航栏、控制栏的位置上，只是被蒙层遮掉了看不见），
        // 不能让它们接住手指；点按统一由下面那层与阅读区等大的透明底来接。
        .allowsHitTesting(false)
        .mask(focusGradient(containerHeight: containerHeight))
        .offset(y: boundaryBounceOffset)
        .animation(revealAnimation) { content in
            content.opacity(contentRevealed ? 1 : 0)
        }
        .background {
            Color.clear
                .contentShape(Rectangle())
                .gesture(readerGesture(containerHeight: containerHeight))
        }
        .onChange(of: isPressingReader) { _, isPressing in
            guard !isPressing else { return }
            // 正常松手时 `onEnded` 已经收过尾；这里只处理手势被系统打断的情况，
            // 否则没取消掉的长按计时会在手指离开之后还弹出选词。
            DispatchQueue.main.async {
                guard !isPressingReader else { return }
                press.reset()
            }
        }
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
                contentRevealed = false
            }
        }
        .onChange(of: viewModel.currentPageIndex) { _, _ in
            // 切换书籍、加载/恢复内容、删除、搜索跳转等"非阅读语境"会通过
            // ViewModel 设置一次性标志；后台听书续页也会标静默。再叠加 scenePhase，
            // 避免回前台时把累计翻页补成一段滑动动画。
            let silent = viewModel.consumePendingSilentPageScroll()
            scrollToCurrentPage(animated: !silent && scenePhase == .active)
        }
        .onChange(of: viewModel.contentScrollRevision) { _, _ in
            recenterCurrentPage()
        }
        .onChange(of: viewModel.pages.count) { _, _ in
            recenterCurrentPage()
        }
        .onChange(of: isReaderCoveredBySheet) { _, covered in
            // 揭开时只吸收旋转等真实尺寸变化。
            if !covered {
                adoptViewportHeight(latestProposedHeight)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // 回到前台：若画面仍停在离开前的页，无动画地对齐到当前朗读页。
            // 同时丢掉后台「前进又后退」净变化为零时残留的静默标志，避免下次手动翻页丢动画。
            guard newPhase == .active else { return }
            _ = viewModel.consumePendingSilentPageScroll()
            if displayedPageIndex != viewModel.currentPageIndex {
                scrollToCurrentPage(animated: false)
            }
        }
    }

    private func pageRow(idx: Int, generation: Int) -> some View {
        Text(viewModel.pages[idx])
            .font(.system(size: fontSize))
            .kerning(ReaderTypography.kerning)
            .lineSpacing(ReaderTypography.lineSpacing)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(viewModel.pages[idx])
            .accessibilityValue("第 \(idx + 1) 页，共 \(viewModel.pages.count) 页")
            .accessibilityAction(named: "上一页") {
                turnPage(forward: false)
            }
            .accessibilityAction(named: "下一页") {
                turnPage(forward: true)
            }
            .accessibilityAction(named: "选词") {
                viewModel.triggerBigBang()
            }
            // 放在最后：要藏的是上面合成出来的这一整个元素。写在前面只会藏掉里面的文字，
            // 前后几页变淡的内容仍会被旁白逐页读到。
            .accessibilityHidden(idx != viewModel.currentPageIndex)
            // 记录该页在阅读区中的实测帧。静止时用来校正蒙层；翻页动画期间只更新缓存，
            // 不把清晰窗口拽到正在移动的那一页上。
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.readerSpace)) } action: { frame in
                // 整批换内容时，上一批的页可能在新的一批量好之后才报告，不能让它们盖掉新量到的帧。
                guard generation == viewModel.pagesGeneration else { return }
                if pageFramesGeneration != generation {
                    pageFramesGeneration = generation
                    pageFrames = [idx: frame]
                } else if pageFrames[idx] != frame {
                    pageFrames[idx] = frame
                }
                if idx == viewModel.currentPageIndex {
                    if !pageTurnInProgress {
                        adoptSettledFocusWindow(from: frame)
                    }
                    revealIfCurrentPageMeasured()
                }
            }
            // 排到窗口外的页帧已失效，及时清掉，避免远距离跳页时蒙层短暂套用陈旧位置。
            .onDisappear {
                guard generation == viewModel.pagesGeneration, pageFramesGeneration == generation else { return }
                pageFrames[idx] = nil
            }
    }

    private func recenterCurrentPage() {
        scrollToCurrentPage(animated: false)
    }

    /// 把当前页摆到阅读区正中。
    ///
    /// 有动画时：清晰窗口留在视口中央，只插值高度（上下同时收放），正文滑进这个窗口。
    /// 不能让蒙层跟着下一页的当前位置走，否则会先「标出高亮」再整块上移，闪一下。
    private func scrollToCurrentPage(animated: Bool) {
        let target = viewModel.currentPageIndex
        let readerHeight = max(0, settledViewportHeight)

        if animated && !reduceMotion {
            pageTurnInProgress = true
            pageTurnGeneration += 1
            let generation = pageTurnGeneration
            withAnimation(.easeInOut(duration: pageTurnAnimationDuration)) {
                applyCenteredFocusWindow(for: target, containerHeight: readerHeight)
                displayedPageIndex = target
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + pageTurnAnimationDuration + 0.05) {
                guard generation == pageTurnGeneration else { return }
                pageTurnInProgress = false
                if let frame = measuredFrames[target], frame.height > 1 {
                    adoptSettledFocusWindow(from: frame)
                }
            }
            return
        }

        pageTurnInProgress = false
        pageTurnGeneration += 1

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            applyCenteredFocusWindow(for: target, containerHeight: readerHeight)
            displayedPageIndex = target
        }
    }

    /// 翻页动画的目标窗口：就是目标页排好之后所在的位置，高度取目标页实测值（没有则沿用当前窗口）。
    private func applyCenteredFocusWindow(for pageIndex: Int, containerHeight: CGFloat) {
        guard containerHeight > 1 else { return }
        let height = resolvedPageHeight(for: pageIndex)
        guard height > 1 else { return }
        let top = ReaderPagePlacement.focusedPageTop(
            pageHeight: height,
            containerHeight: containerHeight,
            bottomReserve: bottomReserve
        )
        focusMinY = top
        focusMaxY = top + height
        hasFocusWindow = true
    }

    /// 静止后把清晰窗口锁到当前页实测帧，避免朗读内容被压到半透明带里。
    private func adoptSettledFocusWindow(from frame: CGRect) {
        guard frame.height > 1 else { return }
        focusMinY = frame.minY
        focusMaxY = frame.maxY
        hasFocusWindow = true
    }

    private func resolvedPageHeight(for pageIndex: Int) -> CGFloat {
        if let height = measuredFrames[pageIndex]?.height, height > 1 {
            return height
        }
        if hasFocusWindow {
            return max(1, focusMaxY - focusMinY)
        }
        return representativePageHeight() ?? 0
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

    /// 淡入 / 淡出只作用于透明度：揭示那一帧若正文还在重新排版，不能被带成一段位移。
    private var revealAnimation: Animation? {
        guard !reduceMotion else { return nil }
        return .easeOut(duration: contentRevealed ? 0.22 : 0.18)
    }

    /// 当前页帧就绪后，等当前页及相邻页的帧连续两次采样一致再淡入
    /// （此刻聚焦蒙层才能正确罩住当前页，正文也不会在淡入途中再挪动）。
    private func revealIfCurrentPageMeasured() {
        guard awaitingReveal, !contentRevealed, viewModel.isContentSettled else { return }
        guard let frame = measuredFrames[viewModel.currentPageIndex], frame.height > 1 else { return }
        revealCheckGeneration += 1
        revealAfterLayoutSettles(generation: revealCheckGeneration, previous: nil, attempt: 0)
    }

    private func revealAfterLayoutSettles(generation: Int, previous: [Int: CGRect]?, attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + revealSettleInterval) {
            guard generation == revealCheckGeneration,
                  awaitingReveal, !contentRevealed, viewModel.isContentSettled else { return }
            let snapshot = measuredFrames.filter { abs($0.key - viewModel.currentPageIndex) <= 1 }
            guard let current = snapshot[viewModel.currentPageIndex], current.height > 1 else { return }
            if snapshot == previous || attempt >= maxRevealSettleChecks {
                awaitingReveal = false
                contentRevealed = true
            } else {
                revealAfterLayoutSettles(generation: generation, previous: snapshot, attempt: attempt + 1)
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
                contentRevealed = true
            }
        }
    }

    /// 聚焦遮罩：清晰窗口取自独立的 `focusMinY...focusMaxY`（首尾各留少量余量）。
    /// 翻页时这个窗口在视口中央插值高度，正文滑入其中；静止后再与当前页实测帧对齐。
    private func focusGradient(containerHeight: CGFloat) -> LinearGradient {
        guard containerHeight > 1 else {
            return LinearGradient(colors: [.black], startPoint: .top, endPoint: .bottom)
        }

        let clearPadding: CGFloat = 6  // 让当前页首尾行的字形完全落在清晰区内的余量

        let clearRange: ClosedRange<CGFloat>
        if hasFocusWindow, focusMaxY > focusMinY {
            clearRange = (focusMinY - clearPadding)...(focusMaxY + clearPadding)
        } else if let pageHeight = representativePageHeight() {
            let top = ReaderPagePlacement.focusedPageTop(
                pageHeight: pageHeight,
                containerHeight: containerHeight,
                bottomReserve: bottomReserve
            )
            clearRange = (top - clearPadding)...(top + pageHeight + clearPadding)
        } else {
            return LinearGradient(colors: [.black], startPoint: .top, endPoint: .bottom)
        }

        return focusGradient(clearRange: clearRange, containerHeight: containerHeight)
    }

    /// 依据以点为单位的清晰区间构造渐变。清晰区内恒为完全不透明（当前页优先于边缘渐隐，
    /// 即便页面高到贴近阅读区边缘也不会把首尾行压暗）；清晰区外先在 `fade` 内过渡到
    /// 半透明，再在阅读区上下边缘 `edgeFade` 内淡出为透明。
    private func focusGradient(clearRange: ClosedRange<CGFloat>, containerHeight: CGFloat) -> LinearGradient {
        let dimmed: CGFloat = 0.30   // 相邻页的半透明程度
        let fade: CGFloat = 36       // 清晰 ↔ 半透明 的过渡带
        let edgeFade: CGFloat = 48   // 半透明 → 透明 的阅读区边缘渐隐

        func opacity(at y: CGFloat) -> CGFloat {
            if clearRange.contains(y) { return 1 }
            let distance = y < clearRange.lowerBound
                ? clearRange.lowerBound - y
                : y - clearRange.upperBound
            let focus = dimmed + (1 - dimmed) * max(0, 1 - distance / fade)
            let edge = min(1, y / edgeFade, (containerHeight - y) / edgeFade)
            return focus * max(0, edge)
        }

        // 只需在各折点处采样：不透明度在折点之间近似线性，交给渐变插值。
        let breakpoints: [CGFloat] = [
            0,
            edgeFade,
            clearRange.lowerBound - fade,
            clearRange.lowerBound,
            clearRange.upperBound,
            clearRange.upperBound + fade,
            containerHeight - edgeFade,
            containerHeight
        ]
        let locations = Set(breakpoints.map { min(max($0, 0), containerHeight) }).sorted()
        let stops = locations.map { y in
            Gradient.Stop(color: Color.black.opacity(opacity(at: y)), location: y / containerHeight)
        }
        return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }

    /// 当前页帧尚未测得时的参考高度：取已渲染各页高度的中位数作为「典型页高」，
    /// 让蒙层在当前页几何回传前也能给出接近正确的清晰窗口。
    private func representativePageHeight() -> CGFloat? {
        let measured = measuredFrames.values.map(\.height).filter { $0 > 1 }.sorted()
        guard !measured.isEmpty else { return nil }
        return measured[measured.count / 2]
    }

    // MARK: - 点按 / 滑动 / 长按

    /// 阅读区只用一个手势，由它自己判断这次按压是点按、滑动还是长按，三者互斥。
    /// 分成几个手势各判各的，会出现按得稍慢时「既弹出选词、又翻了一页」。
    private func readerGesture(containerHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .updating($isPressingReader) { _, isPressing, _ in
                isPressing = true
            }
            .onChanged { value in
                if !press.isTracking {
                    press.reset()
                    press.isTracking = true
                    scheduleLongPress()
                }

                let distance = hypot(value.translation.width, value.translation.height)
                press.maxDistance = max(press.maxDistance, distance)
                if distance > longPressMovementTolerance {
                    press.longPressWorkItem?.cancel()
                    press.longPressWorkItem = nil
                }
            }
            .onEnded { value in
                let longPressFired = press.longPressFired
                let maxDistance = press.maxDistance
                press.reset()

                // 已经弹出选词了，松手不再翻页。
                guard !longPressFired else { return }

                handlePressEnded(
                    startLocation: value.startLocation,
                    translation: value.translation,
                    maxDistance: maxDistance,
                    containerHeight: containerHeight
                )
            }
    }

    private func scheduleLongPress() {
        let workItem = DispatchWorkItem {
            guard press.isTracking, press.maxDistance <= longPressMovementTolerance else { return }
            press.longPressWorkItem = nil
            press.longPressFired = true
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            viewModel.triggerBigBang()
        }
        press.longPressWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + longPressDuration, execute: workItem)
    }

    private func handlePressEnded(startLocation: CGPoint,
                                  translation: CGSize,
                                  maxDistance: CGFloat,
                                  containerHeight: CGFloat) {
        let horizontal = translation.width
        let vertical = translation.height

        if max(abs(horizontal), abs(vertical)) >= swipeDistance {
            // 滑动翻页，按主方向算：往上 / 往左推是看后面，往下 / 往右拉是回前面。
            let forward = abs(vertical) >= abs(horizontal) ? vertical < 0 : horizontal < 0
            turnPage(forward: forward)
            return
        }

        // 滑出去又拖回原处：当作反悔，不翻页。
        guard maxDistance < swipeDistance else { return }

        turnPage(forward: !isPreviousPageZone(y: startLocation.y, containerHeight: containerHeight))
    }

    /// 点按分区：只有当前页上方那片变淡的文字（上一页）算「上一页」，当前页和它下面的都算「下一页」。
    /// 分界线不能从当前页中间穿过，否则点正在读的这段话，有一半位置会往回翻。
    private func isPreviousPageZone(y: CGFloat, containerHeight: CGFloat) -> Bool {
        guard hasFocusWindow, focusMaxY > focusMinY else {
            return y < containerHeight / 2
        }
        let currentPageTop = focusMinY - segmentSpacing / 2
        let boundary = min(max(currentPageTop, minimumPreviousTapZone), containerHeight / 2)
        return y < boundary
    }

    private func turnPage(forward: Bool) {
        guard !viewModel.pages.isEmpty else { return }
        if !viewModel.turnPage(forward: forward) {
            playBoundaryFeedback(forward: forward)
        }
    }

    /// 已经在第一页 / 最后一页：朝翻页的方向顶一下再弹回来，加一次震动，
    /// 让人知道「点到了，只是后面没有了」，而不是以为没点中。
    private func playBoundaryFeedback(forward: Bool) {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        guard !reduceMotion else { return }

        withAnimation(.easeOut(duration: 0.12)) {
            boundaryBounceOffset = forward ? -boundaryBounceDistance : boundaryBounceDistance
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) {
                boundaryBounceOffset = 0
            }
        }
    }
}
