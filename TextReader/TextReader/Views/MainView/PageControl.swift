import SwiftUI
import UIKit

struct PageControl: View {
    @ObservedObject var viewModel: ContentViewModel
    
    @State private var showSlider = false
    @State private var hideSliderWorkItem: DispatchWorkItem?
    @State private var dragWidth: CGFloat = 0
    
    private let haptic = UISelectionFeedbackGenerator()
    private let buttonHaptic = UIImpactFeedbackGenerator(style: .medium)
    private var sliderBinding: Binding<Double> {
        Binding<Double>(
            get: { Double(viewModel.currentPageIndex) },
            set: { newVal in
                let newIndex = Int(newVal.rounded())
                guard newIndex != viewModel.currentPageIndex else { return }
                
                // 确保新索引在有效范围内
                guard !viewModel.pages.isEmpty,
                      newIndex >= 0,
                      newIndex < viewModel.pages.count else { return }
                
                // 触发震动反馈
                haptic.selectionChanged()
                haptic.prepare()
                
                viewModel.stopReading()
                viewModel.currentPageIndex = newIndex
            }
        )
    }
    
    var body: some View {
        VStack(spacing: 8) {
            
            GeometryReader { geo in
                progressStack(geo: geo)
                    .onAppear { dragWidth = geo.size.width }
            }
            .frame(height: 24)
            
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
    private var pageProgress: Double {
        guard viewModel.pages.count > 0 else { return 0 }
        return Double(viewModel.currentPageIndex + 1) / Double(viewModel.pages.count)
    }
    
    private func scheduleHide() {
        hideSliderWorkItem?.cancel()
        let work = DispatchWorkItem {
            withAnimation { showSlider = false }
        }
        hideSliderWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }
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
                .onChanged { _ in
                    if !showSlider {
                        withAnimation { showSlider = true }
                        hideSliderWorkItem?.cancel()
                    }
                }
                .simultaneously(with: DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard showSlider, dragWidth > 0, !viewModel.pages.isEmpty else { return }
                        // 计算拖动百分比转换为页码
                        let pct = max(0, min(1, value.location.x / dragWidth))
                        let newIndex = Int(round(pct * Double(max(0, viewModel.pages.count - 1))))
                        
                        // 确保新索引在有效范围内
                        guard newIndex >= 0, newIndex < viewModel.pages.count,
                              newIndex != viewModel.currentPageIndex else { return }
                        
                        haptic.selectionChanged()
                        viewModel.stopReading()
                        viewModel.currentPageIndex = newIndex
                    }
                    .onEnded { _ in
                        scheduleHide()
                    }
                )
        )
        .animation(.easeInOut(duration: 0.2), value: showSlider)
    }
}

private struct NoDimButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label

    }
} 