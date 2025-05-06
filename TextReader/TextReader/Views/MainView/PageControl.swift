import SwiftUI
import UIKit

struct PageControl: View {
    @ObservedObject var viewModel: ContentViewModel
    
    // ① 新增：滑块是否可见
    @State private var showSlider = false
    // ② 隐藏滑块的定时器
    @State private var hideSliderWorkItem: DispatchWorkItem?
    
    // === 新增：震动反馈发生器（Selection 类型适用于离散滑块变动） ===
    private let haptic = UISelectionFeedbackGenerator()
    
    // ③ 把 currentPageIndex ↔︎ Slider 双向绑定抽出来
    private var sliderBinding: Binding<Double> {
        Binding<Double>(
            get: { Double(viewModel.currentPageIndex) },
            set: { newVal in
                let newIndex = Int(newVal.rounded())
                guard newIndex != viewModel.currentPageIndex else { return }
                
                // === 新增：震动反馈 ===
                haptic.selectionChanged()
                haptic.prepare()          // 预加载下一次，手感更跟手
                
                viewModel.stopReading()                 // 先停止朗读
                viewModel.currentPageIndex = newIndex   // 更新页码
            }
        )
    }
    
    var body: some View {
        VStack(spacing: 8) {
            
            // ---------- 进度条区 ----------
            ZStack {
                // 1) 默认只读进度条（始终可见）
                ProgressView(value: pageProgress)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)

                // 2) 可拖动 Slider（仅在 showSlider==true 时可见/可点）
                if viewModel.pages.count > 1 {
                    Slider(value: sliderBinding,
                           in: 0...Double(max(0, viewModel.pages.count - 1)),
                           step: 1) {
                        // onEditingChanged
                        editing in
                        if editing {
                            // 开始拖动：显示滑块 & 取消之前的隐藏定时
                            withAnimation { showSlider = true }
                            hideSliderWorkItem?.cancel()
                        } else {
                            // 结束拖动：启动 1.5s 后自动隐藏
                            scheduleHide()
                        }
                    }
                    .tint(.accentColor)
                    .opacity(showSlider ? 1 : 0)          // 可视
                    .allowsHitTesting(showSlider)         // 控制命中
                }
            }
            // 3) 点击只读进度条可立即显示滑块
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation { showSlider = true }
                scheduleHide()
            }
            // 4) 平滑动画
            .animation(.easeInOut(duration: 0.2), value: showSlider)
            // ----------------------------------
            
            Text("\(viewModel.currentPageIndex + 1) / \(viewModel.pages.count)")
                .font(.caption)
                .monospacedDigit()
                .foregroundColor(.secondary)
            
            // —— 原有翻页 / 播放按钮保持不变 ——
            HStack {
                RepeatButton(
                    action: { viewModel.previousPage() },
                    longPressAction: { if viewModel.currentPageIndex > 0 { viewModel.previousPage() } }
                ) { Image(systemName: "chevron.left").font(.title) }
                .disabled(viewModel.currentPageIndex == 0)
                
                Spacer()
                
                Button(action: { viewModel.toggleReading() }) {
                    Image(systemName: viewModel.isReading ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(Color.accentColor.opacity(0.9)))
                }
                .accessibilityLabel(viewModel.isReading ? "暂停朗读" : "开始朗读")
                
                Spacer()
                
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
        }
    }
    
    // MARK: - Helpers
    private var pageProgress: Double {
        guard viewModel.pages.count > 0 else { return 0 }
        return Double(viewModel.currentPageIndex + 1) / Double(viewModel.pages.count)
    }
    
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
} 