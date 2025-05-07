import SwiftUI
import UIKit

/// 页面控制组件，用于显示阅读进度、页码和控制页面导航
struct PageControl: View {
    @ObservedObject var viewModel: ContentViewModel
    
    // MARK: - 状态属性
    // 控制滑块是否可见
    @State private var showSlider = false
    // 隐藏滑块的定时器
    @State private var hideSliderWorkItem: DispatchWorkItem?
    // 拖动区域宽度
    @State private var dragWidth: CGFloat = 0
    
    // MARK: - 反馈生成器
    // 滑块变动时的震动反馈发生器（Selection类型适用于离散滑块变动）
    private let haptic = UISelectionFeedbackGenerator()
    // 播放/暂停按钮的震动反馈发生器
    private let buttonHaptic = UIImpactFeedbackGenerator(style: .medium)
    
    // MARK: - 计算属性
    // 创建currentPageIndex与Slider的双向绑定
    private var sliderBinding: Binding<Double> {
        Binding<Double>(
            get: { Double(viewModel.currentPageIndex) },
            set: { newVal in
                let newIndex = Int(newVal.rounded())
                guard newIndex != viewModel.currentPageIndex else { return }
                
                // 触发震动反馈
                haptic.selectionChanged()
                haptic.prepare()  // 预加载下一次，提升响应速度
                
                viewModel.stopReading()                 // 先停止朗读
                viewModel.currentPageIndex = newIndex   // 更新页码
            }
        )
    }
    
    var body: some View {
        VStack(spacing: 8) {
            
            // MARK: - 进度条区域
            GeometryReader { geo in
                progressStack(geo: geo)
                    .onAppear { dragWidth = geo.size.width }
            }
            .frame(height: 24) // 给进度条区固定高度
            
            // MARK: - 页码显示
            Text("\(viewModel.currentPageIndex + 1) / \(viewModel.pages.count)")
                .font(.caption)
                .monospacedDigit()
                .foregroundColor(.secondary)
            
            // MARK: - 控制按钮区域
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
                    buttonHaptic.impactOccurred() // 点击时触发震动
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
            buttonHaptic.prepare() // 预热按钮震动器
        }
    }
    
    // MARK: - 辅助方法
    
    /// 计算当前阅读进度百分比
    private var pageProgress: Double {
        guard viewModel.pages.count > 0 else { return 0 }
        return Double(viewModel.currentPageIndex + 1) / Double(viewModel.pages.count)
    }
    
    /// 安排隐藏滑块的定时任务
    private func scheduleHide() {
        // 取消旧任务
        hideSliderWorkItem?.cancel()
        // 新建任务
        let work = DispatchWorkItem {
            withAnimation { showSlider = false }
        }
        hideSliderWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    /// 创建进度栈视图，包含进度条和滑块
    private func progressStack(geo: GeometryProxy) -> some View {
        ZStack {
            // 只读进度条
            ProgressView(value: pageProgress)
                .progressViewStyle(.linear)
                .tint(.accentColor)

            // 可交互滑块
            if viewModel.pages.count > 1 {
                Slider(value: sliderBinding,
                       in: 0...Double(max(0, viewModel.pages.count - 1)),
                       step: 1,
                       onEditingChanged: { editing in
                           if editing {
                               withAnimation { showSlider = true }
                               hideSliderWorkItem?.cancel()
                           } else {
                               scheduleHide()
                           }
                       })
                .tint(.accentColor)
                .opacity(showSlider ? 1 : 0)
                .allowsHitTesting(showSlider)
            }
        }
        .contentShape(Rectangle())
        // 长按和拖动手势
        .gesture(
            LongPressGesture(minimumDuration: 0.2)
                .onChanged { _ in                   // 触发阈值后立即显示滑块
                    if !showSlider {
                        withAnimation { showSlider = true }
                        hideSliderWorkItem?.cancel()
                    }
                }
                .simultaneously(with: DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard showSlider, dragWidth > 0 else { return }
                        // 计算拖动百分比转换为页码
                        let pct = max(0, min(1, value.location.x / dragWidth))
                        let newIndex = Int(round(pct * Double(max(0, viewModel.pages.count - 1))))
                        if newIndex != viewModel.currentPageIndex {
                            haptic.selectionChanged()
                            viewModel.stopReading()
                            viewModel.currentPageIndex = newIndex
                        }
                    }
                    .onEnded { _ in
                        scheduleHide()
                    }
                )
        )
        .animation(.easeInOut(duration: 0.2), value: showSlider)
    }
}

// MARK: - 自定义按钮样式

/// 无暗淡效果的按钮样式，避免按下时的视觉变化
private struct NoDimButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
        // 不根据configuration.isPressed状态改变外观，避免按下时的暗淡或缩放效果
    }
} 