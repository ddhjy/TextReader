import SwiftUI
import UIKit

struct ContentDisplay: View {
    @ObservedObject var viewModel: ContentViewModel
    @Environment(\.scenePhase) private var scenePhase

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var scaledFontSize: CGFloat = 19

    private var fontSize: CGFloat { min(scaledFontSize, 24) }
    private let kerning: CGFloat = 0.3
    private let lineSpacing: CGFloat = 8
    private let segmentSpacing: CGFloat = 22
    private let pageTurnAnimationDuration: TimeInterval = 0.25
    private let readableColumnWidth: CGFloat = 680

    /// 阅读区顶部与导航栏安全区之间保留的间隙。
    ///
    /// ScrollView 一旦与容器安全区相接，SwiftUI 就会把背后的 UIScrollView 向上扩进导航栏，
    /// 并依赖 UIKit 的自动内容缩进把内容顶回来；而 `ReaderKeyboardIsolation` 为隔离键盘关掉了
    /// 自动缩进，补偿随之消失——UIKit 实际帧比 SwiftUI 布局帧（蒙层、居中锚点所在）高出整个
    /// 安全区，当前页被「居中」到偏上半个安全区的位置，聚焦蒙层却仍按布局帧计算，于是当前页
    /// 首段被压暗、下一页开头反而清晰。留出 1pt 不相接，UIScrollView 便与布局帧完全一致。
    private let safeAreaClearance: CGFloat = 1

    /// 各页在阅读区坐标系中的实测帧。静止时蒙层用当前页帧保证朗读内容不被压暗；
    /// 翻页动画期间不用它直接驱动蒙层，否则清晰窗口会先跳到下一页的当前位置再跟着上移。
    @State private var pageFrames: [Int: CGRect] = [:]

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

    /// 阅读区滚动位置。用状态而不是一次性 `scrollTo` 命令，回前台后的首次布局
    /// 会按当前页自动落位，避免后台听书推进页码后画面停在离开前的页。
    @State private var scrollPosition: ScrollPosition

    /// 用于计算上下留白的稳定视口高度。搜索 sheet / 键盘进出时 GeometryReader
    /// 会短暂给出缩小后的高度；若直接写进 spacer，当前页会整体偏移，等滚动状态
    /// 再次对齐后才跳回。忽略这类瞬时抖动，只在旋转等真实尺寸变化时更新。
    @State private var settledViewportHeight: CGFloat = 0
    @State private var settledViewportWidth: CGFloat = 0
    @State private var settledSafeAreaTop: CGFloat = 0
    @State private var latestProposedHeight: CGFloat = 0
    @State private var latestProposedWidth: CGFloat = 0
    @State private var latestProposedSafeAreaTop: CGFloat = 0

    init(viewModel: ContentViewModel) {
        self.viewModel = viewModel
        _scrollPosition = State(
            initialValue: ScrollPosition(id: viewModel.currentPageIndex, anchor: .center)
        )
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

        // sheet 盖住阅读区时只记下最新提议高度，不改 spacer / 居中基准。
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
            scrollingContent(geometry: geometry)
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

    private func scrollingContent(geometry: GeometryProxy) -> some View {
        let containerHeight = viewportHeight(from: geometry.size.height) - safeAreaClearance
        return ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear
                    .frame(height: containerHeight * 0.5)

                LazyVStack(alignment: .leading, spacing: segmentSpacing) {
                    ForEach(viewModel.pages.indices, id: \.self) { idx in
                        pageRow(idx: idx)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 20)
                .frame(maxWidth: readableColumnWidth)
                .frame(maxWidth: .infinity)

                Color.clear
                    .frame(height: containerHeight * 0.5)
            }
        }
        .scrollPosition($scrollPosition, anchor: .center)
        .scrollDisabled(true)
        .mask(focusGradient(containerHeight: containerHeight))
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
                    handleTapGesture(at: value.location, containerHeight: containerHeight)
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
            recenterCurrentPage()
        }
        .onChange(of: viewModel.pages.count) { _, _ in
            recenterCurrentPage()
        }
        .onChange(of: isReaderCoveredBySheet) { _, covered in
            // 揭开时只吸收旋转等真实尺寸变化。不要在这里 scrollTo：
            // 该时机常与键盘收起弹簧同一帧，scrollTo 会跟着整段滑下去。
            if !covered {
                adoptViewportHeight(latestProposedHeight)
            }
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
        // 见 `safeAreaClearance`：让 ScrollView 不与顶部安全区相接。
        .padding(.top, safeAreaClearance)
    }

    private func pageRow(idx: Int) -> some View {
        Text(viewModel.pages[idx])
            .font(.system(size: fontSize))
            .kerning(kerning)
            .lineSpacing(lineSpacing)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .id(idx)
            .accessibilityHidden(idx != viewModel.currentPageIndex)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(viewModel.pages[idx])
            .accessibilityValue("第 \(idx + 1) 页，共 \(viewModel.pages.count) 页")
            .accessibilityAction(named: "上一页") {
                viewModel.previousPage()
            }
            .accessibilityAction(named: "下一页") {
                viewModel.nextPage()
            }
            .accessibilityAction(named: "选词") {
                viewModel.triggerBigBang()
            }
            // 记录该页在阅读区中的实测帧。静止时用来校正蒙层；翻页动画期间只更新缓存，
            // 不把清晰窗口拽到正在移动的那一页上。
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .scrollView) } action: { frame in
                if pageFrames[idx] != frame {
                    pageFrames[idx] = frame
                }
                if idx == viewModel.currentPageIndex {
                    if !pageTurnInProgress {
                        adoptSettledFocusWindow(from: frame)
                    }
                    revealIfCurrentPageMeasured()
                }
            }
            // 懒加载回收后帧已失效，及时清掉，避免远距离跳页时蒙层短暂套用陈旧位置。
            .onDisappear {
                pageFrames[idx] = nil
            }
    }

    /// 覆盖层关闭或视口抖动后，连续两帧无动画居中，避开转场中途的中间尺寸。
    private func recenterCurrentPage() {
        scrollToCurrentPage(animated: false)
        DispatchQueue.main.async {
            scrollToCurrentPage(animated: false)
        }
    }

    /// 把阅读区定位到当前页（居中）。滚动位置是视图状态，回前台后的首次布局会自动按它落位。
    ///
    /// 有动画时：清晰窗口留在视口中央，只插值高度（上下同时收放），正文滑进这个窗口。
    /// 不能让蒙层跟着下一页的当前位置走，否则会先「标出高亮」再整块上移，闪一下。
    private func scrollToCurrentPage(animated: Bool) {
        let target = viewModel.currentPageIndex
        let readerHeight = max(0, settledViewportHeight - safeAreaClearance)
        let applyScroll = {
            scrollPosition.scrollTo(id: target, anchor: .center)
        }

        if animated && !reduceMotion {
            pageTurnInProgress = true
            pageTurnGeneration += 1
            let generation = pageTurnGeneration
            withAnimation(.easeInOut(duration: pageTurnAnimationDuration)) {
                applyCenteredFocusWindow(for: target, containerHeight: readerHeight)
                applyScroll()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + pageTurnAnimationDuration + 0.05) {
                guard generation == pageTurnGeneration else { return }
                pageTurnInProgress = false
                if let frame = pageFrames[target], frame.height > 1 {
                    adoptSettledFocusWindow(from: frame)
                }
            }
            return
        }

        pageTurnInProgress = false
        pageTurnGeneration += 1
        if let frame = pageFrames[target], frame.height > 1 {
            adoptSettledFocusWindow(from: frame)
        } else {
            applyCenteredFocusWindow(for: target, containerHeight: readerHeight)
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        UIView.performWithoutAnimation {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            withTransaction(transaction, applyScroll)
            CATransaction.commit()
        }
    }

    /// 翻页动画的目标窗口：始终以阅读区中线为轴，高度取目标页实测值（没有则沿用当前窗口）。
    private func applyCenteredFocusWindow(for pageIndex: Int, containerHeight: CGFloat) {
        guard containerHeight > 1 else { return }
        let height = resolvedPageHeight(for: pageIndex)
        guard height > 1 else { return }
        let mid = containerHeight / 2
        let half = height / 2
        focusMinY = mid - half
        focusMaxY = mid + half
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
        if let height = pageFrames[pageIndex]?.height, height > 1 {
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

    /// 当前页帧就绪后执行淡入（此刻聚焦蒙层才能正确罩住当前页）。
    private func revealIfCurrentPageMeasured() {
        guard awaitingReveal, !contentRevealed, viewModel.isContentSettled else { return }
        guard let frame = pageFrames[viewModel.currentPageIndex], frame.height > 1 else { return }
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
            let clearHalf = pageHeight / 2 + clearPadding
            clearRange = (containerHeight / 2 - clearHalf)...(containerHeight / 2 + clearHalf)
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
        let measured = pageFrames.values.map(\.height).filter { $0 > 1 }.sorted()
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
