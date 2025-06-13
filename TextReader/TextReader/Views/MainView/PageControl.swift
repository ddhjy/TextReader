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
            // 使用自定义 Slider 以支持透明 thumb
            if viewModel.pages.count > 1 {
                CustomSlider(
                    value: sliderBinding,
                    range: 0...Double(max(0, viewModel.pages.count - 1)),
                    accentColor: viewModel.currentAccentColor
                )
                .frame(height: 20) // 设置合适的高度
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
                }) { 
                    Image(systemName: viewModel.isReading ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(
                            Circle()
                                .fill(Color.accentColor.opacity(viewModel.isSwitchingPlayState ? 0.6 : 0.9))
                                .animation(.easeInOut(duration: 0.15), value: viewModel.isSwitchingPlayState)
                        )
                        .scaleEffect(viewModel.isSwitchingPlayState ? 0.95 : 1.0)
                        .animation(.easeInOut(duration: 0.15), value: viewModel.isSwitchingPlayState)
                }
                .buttonStyle(NoDimButtonStyle())
                .accessibilityLabel(viewModel.isSwitchingPlayState ? "切换中..." : (viewModel.isReading ? "暂停朗读" : "开始朗读"))
                
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
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(1.0) // 确保按钮永远不变灰
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// 自定义 Slider 支持透明的 thumb
private struct CustomSlider: UIViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let accentColor: Color
    
    func makeUIView(context: Context) -> UISlider {
        let slider = UISlider()
        
        // 设置滑块范围
        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)
        
        // 设置外观
        slider.tintColor = UIColor(accentColor) // 进度条颜色
        slider.thumbTintColor = UIColor.clear // 设置 thumb 为透明色
        slider.minimumTrackTintColor = UIColor(accentColor) // 已滑过的轨道颜色
        slider.maximumTrackTintColor = UIColor.systemGray4 // 未滑过的轨道颜色
        
        // 添加事件监听
        slider.addTarget(
            context.coordinator,
            action: #selector(Coordinator.valueChanged(_:)),
            for: .valueChanged
        )
        
        return slider
    }
    
    func updateUIView(_ uiView: UISlider, context: Context) {
        uiView.value = Float(value)
        // 动态更新颜色以响应强调色变化
        uiView.tintColor = UIColor(accentColor)
        uiView.minimumTrackTintColor = UIColor(accentColor)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: CustomSlider
        
        init(_ parent: CustomSlider) {
            self.parent = parent
        }
        
        @objc func valueChanged(_ sender: UISlider) {
            parent.value = Double(sender.value)
        }
    }
} 
