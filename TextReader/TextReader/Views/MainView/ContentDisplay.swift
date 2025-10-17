import SwiftUI

/// 内容显示组件，负责显示当前页面的文本内容
struct ContentDisplay: View {
    @ObservedObject var viewModel: ContentViewModel

    var body: some View {
        Text(currentPageText)
            .font(.system(size: 19))
            .kerning(0.3)
            .lineSpacing(8)
            .multilineTextAlignment(.leading)
            .padding(.horizontal)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                LongPressGesture(minimumDuration: 0.3)
                    .onEnded { _ in
                        viewModel.triggerBigBang()
                    }
            )
            .onTapGesture {
                viewModel.nextPage()
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
} 