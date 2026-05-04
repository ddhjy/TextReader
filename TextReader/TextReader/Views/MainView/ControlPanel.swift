import SwiftUI
import UIKit

struct ControlPanel: View {
    @ObservedObject var viewModel: ContentViewModel
    
    @Binding var showProgressSlider: Bool
    
    /// 是否处于「定时选择」状态：长按播放按钮后弹出，松手后退出。
    @State private var sleepPickerActive: Bool = false
    /// 当前手指悬停命中的定时分钟数。
    @State private var sleepHoveredOption: Int? = nil
    /// 长按激活定时器选择浮层的延迟任务，松手时需取消。
    @State private var sleepActivationWorkItem: DispatchWorkItem? = nil
    
    private let playButtonSize: CGFloat = 44
    private let longPressActivationDelay: TimeInterval = 0.35
    private let pickerHaptic = UIImpactFeedbackGenerator(style: .medium)
    private let selectionHaptic = UISelectionFeedbackGenerator()
    
    private var sliderBinding: Binding<Double> {
        Binding<Double>(
            get: { Double(viewModel.currentPageIndex) },
            set: { newVal in
                let newIndex = Int(newVal.rounded())
                guard newIndex != viewModel.currentPageIndex else { return }
                guard !viewModel.pages.isEmpty,
                      newIndex >= 0,
                      newIndex < viewModel.pages.count else { return }
                
                viewModel.goToPage(newIndex)
            }
        )
    }
    
    private var progress: Double {
        guard viewModel.pages.count > 0 else { return 0 }
        return Double(viewModel.currentPageIndex + 1) / Double(viewModel.pages.count)
    }
    
    private var sortedSleepOptions: [Int] {
        ContentViewModel.sleepTimerOptions.sorted()
    }
    
    var body: some View {
        VStack(spacing: 16) {
            if showProgressSlider && !sleepPickerActive {
                VStack(spacing: 4) {
                    Slider(value: sliderBinding, in: 0...Double(max(0, viewModel.pages.count - 1)))
                        .tint(viewModel.currentAccentColor)
                    
                    Text("\(viewModel.currentPageIndex + 1) / \(max(1, viewModel.pages.count))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .glassEffect(.regular.interactive(), in: .capsule)
                .padding(.horizontal, 16)
                .transition(.blurReplace)
            }
            
            ZStack {
                HStack(spacing: 16) {
                    secondaryButton(systemName: "books.vertical.fill") {
                        viewModel.showingBookList = true
                    }
                    
                    secondaryButton(systemName: "magnifyingglass") {
                        viewModel.showingSearchView = true
                    }
                    
                    playButton
                    
                    progressButton
                    
                    secondaryButton(systemName: "gearshape.fill") {
                        viewModel.showingSettings = true
                    }
                }
                // 仅在进度调节弹出时禁用整排命中。
                // 定时选择期间，长按手势已绑定到播放按钮上，单指交互不会触发其他按钮。
                .allowsHitTesting(!showProgressSlider)
                
                if showProgressSlider && !sleepPickerActive {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3)) {
                                showProgressSlider = false
                            }
                        }
                }
            }
            .frame(height: 56)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: sleepPickerActive)
        }
        .onAppear {
            pickerHaptic.prepare()
            selectionHaptic.prepare()
        }
    }
    
    // MARK: - Buttons
    
    /// 「除播放外」的按钮的统一构造，便于在定时选择期间整体淡出。
    private func secondaryButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .tint(viewModel.currentAccentColor)
        .opacity(sleepPickerActive ? 0 : 1)
    }
    
    private var progressButton: some View {
        Button {
            withAnimation(.spring(response: 0.3)) {
                showProgressSlider.toggle()
            }
        } label: {
            ZStack {
                Circle()
                    .stroke(viewModel.currentAccentColor.opacity(0.2), lineWidth: 2)
                    .frame(width: 22, height: 22)
                
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(viewModel.currentAccentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 22, height: 22)
                
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 8))
                    .fontWeight(.medium)
                    .foregroundStyle(viewModel.currentAccentColor)
            }
            .frame(width: 44, height: 44)
            .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .tint(viewModel.currentAccentColor)
        .opacity(sleepPickerActive ? 0 : 1)
    }
    
    // MARK: - Play Button
    
    /// 播放按钮：常态显示播放/暂停图标；定时播放时显示进度环和剩余分钟。
    /// 同时承载长按 → 拖动 → 松手 的「定时选择」交互。
    private var playButton: some View {
        ZStack {
            if viewModel.sleepTimerActive {
                Circle()
                    .stroke(viewModel.currentAccentColor.opacity(0.18), lineWidth: 2)
                    .frame(width: 36, height: 36)
                
                Circle()
                    .trim(from: 0, to: viewModel.sleepTimerProgress)
                    .stroke(
                        viewModel.currentAccentColor,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 36, height: 36)
                    .animation(.linear(duration: 0.5), value: viewModel.sleepTimerProgress)
                
                sleepCountdownLabel
            } else {
                Image(systemName: playIconName)
                    .font(.title3)
            }
        }
        .frame(width: playButtonSize, height: playButtonSize)
        .glassEffect(.regular.interactive(), in: .circle)
        .tint(viewModel.currentAccentColor)
        .scaleEffect(sleepPickerActive ? 1.08 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: sleepPickerActive)
        // 选项浮层（仅展示，不参与命中测试）
        .overlay(alignment: .center) {
            if sleepPickerActive {
                SleepTimerPicker(
                    options: sortedSleepOptions,
                    hoveredMinutes: sleepHoveredOption,
                    accentColor: viewModel.currentAccentColor
                )
            }
        }
        .contentShape(Rectangle())
        .gesture(playButtonGesture)
    }
    
    private var playIconName: String {
        viewModel.isReading ? "pause.fill" : "play.fill"
    }
    
    private var sleepCountdownLabel: some View {
        VStack(spacing: 0) {
            Text("\(viewModel.sleepTimerRemainingMinutes)")
                .font(.system(size: 16, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(viewModel.currentAccentColor)
            Text("分")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(viewModel.currentAccentColor.opacity(0.8))
        }
    }
    
    // MARK: - Gesture
    
    /// 单一手势：触按 → 计时 0.35s → 弹出定时选项；其后跟踪手指位置。
    /// 0.35s 内松手视作短按，直接走 `handlePlayButtonTap`，避免长按/短按手势冲突导致的浮层卡死。
    private var playButtonGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if sleepActivationWorkItem == nil && !sleepPickerActive {
                    let work = DispatchWorkItem {
                        activatePickerIfNeeded()
                    }
                    sleepActivationWorkItem = work
                    DispatchQueue.main.asyncAfter(
                        deadline: .now() + longPressActivationDelay,
                        execute: work
                    )
                }
                if sleepPickerActive {
                    updateHoveredOption(forLocation: value.location)
                }
            }
            .onEnded { value in
                let activation = sleepActivationWorkItem
                sleepActivationWorkItem = nil
                activation?.cancel()
                
                if sleepPickerActive {
                    let offset = offsetFromPlayCenter(value.location)
                    let chosen = SleepTimerPicker.hitTest(
                        offsetFromCenter: offset,
                        options: sortedSleepOptions
                    )
                    if let minutes = chosen {
                        selectionHaptic.selectionChanged()
                        viewModel.startSleepTimer(minutes: minutes)
                    }
                    sleepPickerActive = false
                    sleepHoveredOption = nil
                } else {
                    viewModel.handlePlayButtonTap()
                }
            }
    }
    
    private func offsetFromPlayCenter(_ location: CGPoint) -> CGSize {
        CGSize(
            width: location.x - playButtonSize / 2,
            height: location.y - playButtonSize / 2
        )
    }
    
    private func activatePickerIfNeeded() {
        guard !sleepPickerActive else { return }
        sleepPickerActive = true
        sleepHoveredOption = nil
        pickerHaptic.impactOccurred()
        if showProgressSlider {
            withAnimation(.spring(response: 0.3)) {
                showProgressSlider = false
            }
        }
    }
    
    private func updateHoveredOption(forLocation location: CGPoint) {
        let newOption = SleepTimerPicker.hitTest(
            offsetFromCenter: offsetFromPlayCenter(location),
            options: sortedSleepOptions
        )
        if newOption != sleepHoveredOption {
            sleepHoveredOption = newOption
            if newOption != nil {
                selectionHaptic.selectionChanged()
                selectionHaptic.prepare()
            }
        }
    }
}
