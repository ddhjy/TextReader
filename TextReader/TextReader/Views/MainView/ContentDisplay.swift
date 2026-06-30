import SwiftUI

struct ContentDisplay: View {
    @ObservedObject var viewModel: ContentViewModel

    private let fontSize: CGFloat = 19
    private let kerning: CGFloat = 0.3
    private let lineSpacing: CGFloat = 8
    private let segmentSpacing: CGFloat = 22
    private let pageTurnAnimationDuration: TimeInterval = 0.25

    /// 各页实际渲染高度（按页索引缓存）。用于让聚焦遮罩的清晰窗口动态匹配当前页高度。
    @State private var pageHeights: [Int: CGFloat] = [:]

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
        Text("轻触书架，开始阅读")
            .font(.system(size: fontSize))
            .foregroundStyle(Color.primary.opacity(0.5))
            .frame(width: width, height: height)
    }

    private func scrollingContent(geometry: GeometryProxy) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear
                        .frame(height: geometry.size.height * 0.5)

                    LazyVStack(alignment: .leading, spacing: segmentSpacing) {
                        ForEach(viewModel.pages.indices, id: \.self) { idx in
                            Text(viewModel.pages[idx])
                                .font(.system(size: fontSize))
                                .kerning(kerning)
                                .lineSpacing(lineSpacing)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .id(idx)
                                .accessibilityHidden(idx != viewModel.currentPageIndex)
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                                    if pageHeights[idx] != height {
                                        pageHeights[idx] = height
                                    }
                                }
                        }
                    }
                    .padding(.horizontal)

                    Color.clear
                        .frame(height: geometry.size.height * 0.5)
                }
            }
            .scrollDisabled(true)
            .mask(focusGradient(containerHeight: geometry.size.height))
            .contentShape(Rectangle())
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
                DispatchQueue.main.async {
                    proxy.scrollTo(viewModel.currentPageIndex, anchor: .center)
                }
            }
            .onChange(of: viewModel.currentPageIndex) { _, newIndex in
                // 切换书籍、加载/恢复内容、删除、搜索跳转等"非阅读语境"会通过
                // ViewModel 设置一次性标志，这里据此跳过动画，让目标内容直接呈现，
                // 只有用户阅读/朗读自动续页时才看到翻页动画。
                if viewModel.consumePendingSilentPageScroll() {
                    proxy.scrollTo(newIndex, anchor: .center)
                } else {
                    withAnimation(.easeInOut(duration: pageTurnAnimationDuration)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
            .onChange(of: viewModel.contentScrollRevision) { _, _ in
                DispatchQueue.main.async {
                    proxy.scrollTo(viewModel.currentPageIndex, anchor: .center)
                }
            }
            .onChange(of: viewModel.pages.count) { _, _ in
                DispatchQueue.main.async {
                    proxy.scrollTo(viewModel.currentPageIndex, anchor: .center)
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
        let pageHeight = pageHeights[viewModel.currentPageIndex] ?? 0

        // 尺寸尚未测得时退化为整屏清晰，避免误盖当前页（随即会被测量结果修正）。
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

    private func handleTapGesture(at location: CGPoint, containerHeight: CGFloat) {
        let isUpperArea = location.y < containerHeight / 2
        if isUpperArea {
            viewModel.previousPage()
        } else {
            viewModel.nextPage()
        }
    }
}
