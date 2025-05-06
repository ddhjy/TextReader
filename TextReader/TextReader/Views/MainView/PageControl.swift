import SwiftUI
import UIKit

struct PageControl: View {
    @ObservedObject var viewModel: ContentViewModel
    
    // ① 新增：滑块是否可见
    @State private var showSlider = false
    // ② 隐藏滑块的定时器
    @State private var hideSliderWorkItem: DispatchWorkItem?
    // 新增状态
    @State private var dragWidth: CGFloat = 0
    
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
            GeometryReader { geo in
                progressStack(geo: geo)
                    .onAppear { dragWidth = geo.size.width }
            }
            .frame(height: 24) // 给进度条区固定高度即可
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

    private func progressStack(geo: GeometryProxy) -> some View {
        ZStack {
            // ① 只读进度条
            ProgressView(value: pageProgress)
                .progressViewStyle(.linear)
                .tint(.accentColor)

            // ② Slider（与原来一致）
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
        // --- ⬇︎ 改动核心：把"长按 + 拖动"组合起来 ----------------
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
                        // 计算拖动百分比 → 页码
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
        // ----------------------------------------------------------
        .animation(.easeInOut(duration: 0.2), value: showSlider)
    }
} 