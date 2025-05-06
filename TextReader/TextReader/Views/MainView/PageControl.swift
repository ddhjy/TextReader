import SwiftUI

struct PageControl: View {
    @ObservedObject var viewModel: ContentViewModel

    var body: some View {
        VStack(spacing: 8) {
            // 新增进度条
            ProgressView(value: pageProgress)
                .progressViewStyle(.linear)
                .tint(.accentColor)
                .animation(.easeInOut, value: pageProgress)
            
            Text("\(viewModel.currentPageIndex + 1) / \(viewModel.pages.count)")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                // Previous page button
                RepeatButton(
                    action: { viewModel.previousPage() },
                    longPressAction: {
                        // Continuously call previousPage on long press
                        if viewModel.currentPageIndex > 0 {
                            viewModel.previousPage()
                        }
                    },
                    label: {
                        Image(systemName: "chevron.left")
                            .font(.title)
                    }
                )
                .disabled(viewModel.currentPageIndex == 0)

                Spacer()

                // 优化播放按钮
                Button(action: { viewModel.toggleReading() }) {
                    Image(systemName: viewModel.isReading ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(Color.accentColor.opacity(0.9)))
                }
                .accessibilityLabel(viewModel.isReading ? "暂停朗读" : "开始朗读")

                Spacer()

                // Next page button
                RepeatButton(
                    action: { viewModel.nextPage() },
                    longPressAction: {
                        // Continuously call nextPage on long press
                        if viewModel.currentPageIndex < viewModel.pages.count - 1 {
                            viewModel.nextPage()
                        }
                    },
                    label: {
                        Image(systemName: "chevron.right")
                            .font(.title)
                    }
                )
                .disabled(viewModel.currentPageIndex >= viewModel.pages.count - 1)
            }
            .padding(.horizontal)
        }
    }
    
    private var pageProgress: Double {
        guard viewModel.pages.count > 0 else { return 0 }
        return Double(viewModel.currentPageIndex + 1) / Double(viewModel.pages.count)
    }
} 