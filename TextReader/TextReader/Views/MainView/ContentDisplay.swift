import SwiftUI

/// 内容显示组件，负责显示当前页面的文本内容
struct ContentDisplay: View {
    @ObservedObject var viewModel: ContentViewModel

    var body: some View {
        GeometryReader { geometry in
            Text(currentPageText)
                .font(.system(size: 19))
                .kerning(0.3)
                .lineSpacing(8)
                .multilineTextAlignment(.leading)
                .padding(.horizontal)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
                .id(viewModel.currentPageIndex)
                .transaction { transaction in
                    transaction.animation = nil
                }
                .gesture(
                    LongPressGesture(minimumDuration: 0.3)
                        .onEnded { _ in
                            viewModel.triggerBigBang()
                        }
                )
                .simultaneousGesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            handleTapGesture(at: value.location, containerWidth: geometry.size.width)
                        }
                )
        }
    }
    
    // MARK: - 计算属性
    
    /// 获取当前页面的文本内容，如果页面为空则显示"无内容"
    private var currentPageText: String {
        guard !viewModel.pages.isEmpty, 
              viewModel.currentPageIndex >= 0,
              viewModel.currentPageIndex < viewModel.pages.count else {
            return "无内容"
        }
        return viewModel.pages[viewModel.currentPageIndex]
    }
    
    // MARK: - 私有方法
    
    /// 处理点击手势，根据点击位置决定翻页方向
    /// - Parameter location: 点击位置
    /// - Parameter containerWidth: 容器宽度
    private func handleTapGesture(at location: CGPoint, containerWidth: CGFloat) {
        // 左边 1/3 区域是上一页，右边 2/3 区域是下一页
        let isLeftArea = location.x < containerWidth / 3
        
        if isLeftArea {
            viewModel.previousPage()
        } else {
            viewModel.nextPage()
        }
    }
} 