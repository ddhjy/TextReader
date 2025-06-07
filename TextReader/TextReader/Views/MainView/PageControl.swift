import SwiftUI
import UIKit

struct PageControl: View {
    @ObservedObject var viewModel: ContentViewModel
    
    private let haptic = UISelectionFeedbackGenerator()
    private let buttonHaptic = UIImpactFeedbackGenerator(style: .medium)
    
    // sliderBinding 保持不变，它将 ViewModel 的 Int 索引安全地绑定到 Slider 的 Double 值
    private var sliderBinding: Binding<Double> {
        Binding<Double>(
            get: { Double(viewModel.currentPageIndex) },
            set: { newVal in
                let newIndex = Int(newVal.rounded())
                guard newIndex != viewModel.currentPageIndex else { return }
                
                guard !viewModel.pages.isEmpty,
                      newIndex >= 0,
                      newIndex < viewModel.pages.count else { return }
                
                haptic.selectionChanged()
                haptic.prepare()
                
                viewModel.stopReading()
                viewModel.currentPageIndex = newIndex
            }
        )
    }
    
    var body: some View {
        VStack(spacing: 8) {
            
            // 直接使用 Slider，替换原有的 GeometryReader 和 progressStack
            if viewModel.pages.count > 1 {
                Slider(value: sliderBinding,
                       in: 0...Double(max(0, viewModel.pages.count - 1)),
                       step: 1)
                .tint(.accentColor)
                .padding(.horizontal) // 为 Slider 添加一些边距
            } else {
                // 如果只有一页或没有内容，显示一个禁用的进度条占位
                ProgressView(value: 0)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                    .disabled(true)
                    .padding(.horizontal)
            }
            
            Text("\(viewModel.currentPageIndex + 1) / \(viewModel.pages.count)")
                .font(.caption)
                .monospacedDigit()
                .foregroundColor(.secondary)
            HStack {
                // 上一页按钮
                RepeatButton(
                    action: { viewModel.previousPage() },
                    longPressAction: { if viewModel.currentPageIndex > 0 { viewModel.previousPage() } }
                ) { Image(systemName: "chevron.left").font(.title) }
                .disabled(viewModel.currentPageIndex == 0)
                
                Spacer()
                
                // 播放/暂停按钮
                Button(action: { 
                    viewModel.toggleReading()
                    buttonHaptic.impactOccurred()
                }) { Image(systemName: viewModel.isReading ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(Color.accentColor.opacity(0.9)))
                        .animation(nil, value: viewModel.isReading)
                }
                .buttonStyle(NoDimButtonStyle())
                .accessibilityLabel(viewModel.isReading ? "暂停朗读" : "开始朗读")
                
                Spacer()
                
                // 下一页按钮
                RepeatButton(
                    action: { viewModel.nextPage() },
                    longPressAction: { if viewModel.currentPageIndex < viewModel.pages.count - 1 { viewModel.nextPage() } }
                ) { Image(systemName: "chevron.right").font(.title) }
                .disabled(viewModel.currentPageIndex >= viewModel.pages.count - 1)
            }
            .padding(.horizontal)
        }
        .onAppear {
            haptic.prepare()
            buttonHaptic.prepare()
        }
    }
}

private struct NoDimButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label

    }
} 