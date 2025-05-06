import SwiftUI

struct ContentDisplay: View {
    @ObservedObject var viewModel: ContentViewModel

    var body: some View {
        ScrollView {
            Text(currentPageText)
                .font(.system(size: 19))
                .kerning(0.3)
                .lineSpacing(8)
                .multilineTextAlignment(.leading)
                .padding(.horizontal)
                .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(
            LongPressGesture(minimumDuration: 0.3)
                .onEnded { _ in
                    viewModel.triggerBigBang()
                })
    }
    
    private var currentPageText: String {
        viewModel.pages.isEmpty ? "无内容" : viewModel.pages[viewModel.currentPageIndex]
    }
} 