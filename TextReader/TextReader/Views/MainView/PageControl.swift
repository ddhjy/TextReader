import SwiftUI
import UIKit

struct PageControl: View {
    @ObservedObject var viewModel: ContentViewModel
    
    private let haptic = UISelectionFeedbackGenerator()
    
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
        HStack(spacing: 8) {
            // 上一页按钮
            RepeatButton(
                action: { viewModel.previousPage() },
                longPressAction: { if viewModel.currentPageIndex > 0 { viewModel.previousPage() } }
            ) { 
                Image(systemName: "chevron.left")
                    .font(.title3)
            }
            .disabled(viewModel.currentPageIndex == 0)
            
            // 进度滑杆（保留原 CustomSlider 与 haptic 逻辑）
            if viewModel.pages.count > 1 {
                CustomSlider(
                    value: sliderBinding,
                    range: 0...Double(max(0, viewModel.pages.count - 1)),
                    accentColor: viewModel.currentAccentColor
                )
                .frame(height: 18)
            } else {
                // 如果只有一页或没有内容，显示一个禁用的进度条占位
                ProgressView(value: 0)
                    .progressViewStyle(.linear)
                    .tint(viewModel.currentAccentColor)
                    .disabled(true)
                    .frame(height: 18)
            }
            
            // 下一页按钮
            RepeatButton(
                action: { viewModel.nextPage() },
                longPressAction: { if viewModel.currentPageIndex < viewModel.pages.count - 1 { viewModel.nextPage() } }
            ) { 
                Image(systemName: "chevron.right")
                    .font(.title3)
            }
            .disabled(viewModel.currentPageIndex >= viewModel.pages.count - 1)
        }
        .padding(.horizontal, 8)
        .onAppear {
            haptic.prepare()
        }
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
