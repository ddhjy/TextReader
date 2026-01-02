import SwiftUI

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
    
    private var currentPageText: String {
        guard !viewModel.pages.isEmpty, 
              viewModel.currentPageIndex >= 0,
              viewModel.currentPageIndex < viewModel.pages.count else {
            return "无内容"
        }
        return viewModel.pages[viewModel.currentPageIndex]
    }

    private func handleTapGesture(at location: CGPoint, containerWidth: CGFloat) {
        let isLeftArea = location.x < containerWidth / 3
        
        if isLeftArea {
            viewModel.previousPage()
        } else {
            viewModel.nextPage()
        }
    }
}
