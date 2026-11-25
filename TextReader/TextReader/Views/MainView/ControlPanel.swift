import SwiftUI
import UIKit

struct ControlPanel: View {
    @ObservedObject var viewModel: ContentViewModel
    
    @Binding var showProgressSlider: Bool
    /// 首屏「导入第一本书」里选了哪种导入方式。
    let onImport: (ImportMethod) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    /// 是否处于「定时选择」状态：长按播放按钮后弹出，松手后退出。
    @State private var sleepPickerActive: Bool = false
    /// 手指按下即为 true：选项在长按判定期间就开始展开，判定完成时已基本到位，避免「等一下才弹出」的迟滞感。
    /// 所有展开相关的视觉变化都由它驱动、在同一时刻开始；
    /// 若等 `sleepPickerActive` 再改动玻璃容器内的视图，会把进行中的展开动画卡住一拍。
    @State private var sleepPickerRevealing: Bool = false
    /// 当前手指悬停命中的定时分钟数。
    @State private var sleepHoveredOption: Int? = nil
    /// 长按激活定时器选择浮层的延迟任务，松手时需取消。
    @State private var sleepActivationWorkItem: DispatchWorkItem? = nil
    /// 手指是否按在播放按钮上。手势被系统打断时不会走 `onEnded`，靠它复位来收尾。
    @GestureState private var isPressingPlayButton = false
    
    /// 播放是这一排里最主要的操作，比其他按钮大一圈。
    private let playButtonSize: CGFloat = 56
    private let secondaryButtonSize: CGFloat = 44
    private static let controlRowHeight: CGFloat = 64
    private static let controlRowBottomPadding: CGFloat = 8
    /// 控制栏和它上方那排小按钮之间的空隙。
    private static let accessorySpacing: CGFloat = 8
    /// 上方那排小按钮里最高的一个（「导入第一本书」）的高度。
    fileprivate static let accessoryRowHeight: CGFloat = 50
    /// 上方那排小按钮只有一排时，它的顶边比控制栏底边高多少。
    /// 这排按钮是浮在阅读区上面的，阅读区靠这个数给正文留出位置。
    static let accessoryRowTop: CGFloat = controlRowBottomPadding + controlRowHeight + accessorySpacing + accessoryRowHeight
    /// 上方那排小按钮被收窄时，里面的字最多缩到多小。按钮两边的留白和图标不跟着缩，
    /// 所以字要比按钮缩得多一些：按钮让出两成宽度时，字大约要缩到七成。
    fileprivate static let accessoryLabelMinimumScale: CGFloat = 0.65
    private let progressRingSize: CGFloat = 36
    private let progressLineWidth: CGFloat = 2
    private let sleepRingLineWidth: CGFloat = 2.5
    private let longPressActivationDelay: TimeInterval = 0.22
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

    /// 显示用百分比：有内容时从 1 开始，仅最后一页显示 100，避免开头显示 0、结尾前提前到 100。
    private var progressPercent: Int {
        let count = viewModel.pages.count
        guard count > 0 else { return 0 }
        if viewModel.currentPageIndex >= count - 1 { return 100 }
        return min(99, max(1, Int((progress * 100).rounded())))
    }

    private var pageCountLabel: String {
        "\(viewModel.currentPageIndex + 1) / \(max(1, viewModel.pages.count))"
    }

    private var pageCountAccessibilityValue: String {
        "第 \(viewModel.currentPageIndex + 1) 页，共 \(max(1, viewModel.pages.count)) 页"
    }
    
    private var sortedSleepOptions: [Int] {
        ContentViewModel.sleepTimerOptions.sorted()
    }

    /// 定时入口只在用得上的时候出现：正在朗读，或者已经定了时。
    private var showsSleepChip: Bool {
        viewModel.isReading || viewModel.sleepTimerActive
    }

    private var chipAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)
    }
    
    var body: some View {
        VStack(spacing: Self.accessorySpacing) {
            accessoryArea

            GlassEffectContainer(spacing: 16) {
                VStack(spacing: 16) {
                    if showProgressSlider && !sleepPickerActive {
                        progressSlider
                    }

                    controlRow
                }
            }
            // 定时选项浮层（仅展示，不参与命中测试）。
            // 必须挂在 GlassEffectContainer 之外：容器内的玻璃视图不会逐帧响应外层的 offset/scale/opacity 动画，
            // 弹出时会先停顿再跳到终点。这里按控制行的布局常量对齐到播放按钮中心。
            .overlay(alignment: .bottom) {
                SleepTimerPicker(
                    options: sortedSleepOptions,
                    // 减弱动态效果时没有渐进展开，等长按判定完成后再直接显示。
                    isPresented: reduceMotion ? sleepPickerActive : sleepPickerRevealing,
                    hoveredMinutes: sleepHoveredOption,
                    accentColor: viewModel.currentAccentColor,
                    onAccentColor: viewModel.currentOnAccentColor
                )
                .frame(width: 0, height: 0)
                .offset(y: -(Self.controlRowBottomPadding + Self.controlRowHeight / 2))
            }
        }
        // 这一排是固定尺寸的圆形按钮，字号再大就会溢出、互相重叠；
        // 更大的字号下改由系统的「大内容查看器」（长按按钮放大显示）来照顾。
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .onAppear {
            pickerHaptic.prepare()
            selectionHaptic.prepare()
        }
        .onChange(of: showProgressSlider) { _, isShown in
            guard !isShown else { return }
            viewModel.endProgressScrub()
            viewModel.extendReturnOffer()
        }
        .onChange(of: isPressingPlayButton) { _, isPressing in
            guard !isPressing else { return }
            // 正常松手时 `onEnded` 已经收过尾，这里什么都不用做；
            // 只有手势被系统打断（来电、系统手势）时才需要把浮层收回去，否则其他按钮会一直隐藏着。
            DispatchQueue.main.async {
                guard !isPressingPlayButton else { return }
                resetSleepPickerInteraction()
            }
        }
    }

    // MARK: - Accessory

    /// 跳转后要回去的那一页。已经自己翻回那一页时就不用再提示了。
    private var returnTargetPageIndex: Int? {
        guard let index = viewModel.returnPageIndex, index != viewModel.currentPageIndex else { return nil }
        return index
    }

    /// 为了让上方那排小按钮排成一排，每个按钮最多让出多少宽度（里面的字跟着缩小）。
    /// 字号调大以后按钮上的字本来就大，可以多让一些；默认字号下只让一点，再不够就换行。
    private var accessoryMaxSqueeze: CGFloat {
        dynamicTypeSize > .large ? 0.2 : 0.1
    }

    /// 控制栏上方的一小排：首屏的「导入第一本书」、跳转后的「回到第 N 页」、朗读时的「定时停止」。
    /// 这排按钮浮在正文上面，占的高度越少越好：一排放得下就并排，差一点就各自收窄一点，
    /// 字号大、页码位数多实在放不下时才换行，不把字截成「回到第 12…」。
    private var accessoryArea: some View {
        AccessoryFlow(spacing: 10, maxSqueeze: accessoryMaxSqueeze) {
            if viewModel.hasOnlyBuiltInBooks {
                importFirstBookButton
                    .transition(.opacity)
            }

            if let pageIndex = returnTargetPageIndex {
                returnChip(pageIndex: pageIndex)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }

            if showsSleepChip {
                sleepChip
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .padding(.horizontal, 16)
        .opacity(sleepPickerRevealing ? 0 : 1)
        .allowsHitTesting(!sleepPickerRevealing)
        .animation(chipAnimation, value: returnTargetPageIndex)
        .animation(chipAnimation, value: showsSleepChip)
        .animation(chipAnimation, value: viewModel.hasOnlyBuiltInBooks)
        .animation(chipAnimation, value: sleepPickerRevealing)
    }

    private var importFirstBookButton: some View {
        ImportFirstBookButton(
            accentThemeId: viewModel.currentAccentTheme.id,
            accentColor: viewModel.currentAccentColor,
            onAccentColor: viewModel.currentOnAccentColor,
            onImport: onImport
        )
        .equatable()
    }

    private func returnChip(pageIndex: Int) -> some View {
        Button {
            viewModel.returnToJumpOrigin()
        } label: {
            ChipLabel(title: "回到第 \(pageIndex + 1) 页", systemImage: "arrow.uturn.backward")
        }
        .buttonStyle(.plain)
        .accessibilityHint("回到跳转之前的位置")
    }

    private var sleepChip: some View {
        SleepTimerChip(
            options: sortedSleepOptions,
            isTimerActive: viewModel.sleepTimerActive,
            remainingMinutes: viewModel.sleepTimerRemainingMinutes,
            onStart: { viewModel.startSleepTimer(minutes: $0) },
            onCancel: { viewModel.cancelSleepTimer() }
        )
        .equatable()
    }

    // MARK: - Slider

    private var progressSlider: some View {
        Slider(
            value: sliderBinding,
            in: 0...Double(max(1, viewModel.pages.count - 1)),
            onEditingChanged: { isEditing in
                if isEditing {
                    viewModel.beginProgressScrub()
                } else {
                    viewModel.endProgressScrub()
                }
            }
        )
        .disabled(viewModel.pages.count < 2)
        .tint(viewModel.currentAccentColor)
        .accessibilityLabel("阅读进度")
        .accessibilityValue(pageCountAccessibilityValue)
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .overlay(alignment: .bottom) {
            Text(pageCountLabel)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.bottom, 5)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .glassEffect(.regular.interactive(), in: .capsule)
        .padding(.horizontal, 16)
        .transition(.blurReplace)
    }

    // MARK: - Buttons

    private var controlRow: some View {
        HStack(spacing: 16) {
            secondaryButton(systemName: "books.vertical.fill", accessibilityLabel: "书架") {
                viewModel.showingBookList = true
            }

            secondaryButton(systemName: "magnifyingglass", accessibilityLabel: "搜索") {
                viewModel.showingSearchView = true
            }

            playButton

            progressButton

            secondaryButton(systemName: "gearshape.fill", accessibilityLabel: "设置") {
                viewModel.showingSettings = true
            }
        }
        .frame(height: Self.controlRowHeight)
        .padding(.horizontal, 16)
        .padding(.bottom, Self.controlRowBottomPadding)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85), value: sleepPickerRevealing)
    }
    
    /// 「除播放外」的按钮的统一构造，便于在定时选择期间整体淡出。
    /// 进度滑杆开着时这些按钮照常可用：先收起滑杆，再做自己的事，不会出现「看着能点、点了只关滑杆」。
    private func secondaryButton(systemName: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button {
            if showProgressSlider {
                animateProgressSlider(false)
            }
            action()
        } label: {
            Image(systemName: systemName)
                .font(.body)
                .frame(width: secondaryButtonSize, height: secondaryButtonSize)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .tint(viewModel.currentAccentColor)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityShowsLargeContentViewer {
            Label(accessibilityLabel, systemImage: systemName)
        }
        .opacity(sleepPickerRevealing ? 0 : 1)
    }
    
    private var progressButton: some View {
        Button {
            animateProgressSlider(!showProgressSlider)
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.15), lineWidth: progressLineWidth)
                    .frame(width: progressRingSize, height: progressRingSize)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        Color.primary,
                        style: StrokeStyle(lineWidth: progressLineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: progressRingSize, height: progressRingSize)

                // 带上 % 才看得出这是阅读进度，而不是页码或别的数字。字号固定：圆环放不下更大的字。
                Text("\(progressPercent)%")
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: progressRingSize - 6)
            }
            .frame(width: secondaryButtonSize, height: secondaryButtonSize)
            .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("阅读进度 \(progressPercent)%")
        .accessibilityValue(pageCountAccessibilityValue)
        .accessibilityHint(showProgressSlider ? "轻点收起进度滑杆" : "轻点打开进度滑杆")
        .accessibilityShowsLargeContentViewer {
            Label("阅读进度 \(progressPercent)%", systemImage: "chart.pie")
        }
        .opacity(sleepPickerRevealing ? 0 : 1)
    }
    
    // MARK: - Play Button
    
    /// 播放按钮：始终显示播放 / 暂停图标，一眼看得出现在点下去是播还是停；
    /// 定了时的话外圈多一道进度环，剩余时间写在上方的「N 分钟后停止」里。
    /// 同时承载长按 → 拖动 → 松手 的「定时选择」交互。
    private var playButton: some View {
        Image(systemName: playIconName)
            .font(.title2)
            .frame(width: playButtonSize, height: playButtonSize)
            .glassEffect(.regular.interactive(), in: .circle)
            .overlay {
                if viewModel.sleepTimerActive {
                    sleepTimerRing
                }
            }
            .tint(viewModel.currentAccentColor)
            .scaleEffect(sleepPickerRevealing ? 1.08 : 1.0)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: sleepPickerRevealing)
            .contentShape(Rectangle())
            .gesture(voiceOverEnabled ? nil : playButtonGesture)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(viewModel.isReading ? "暂停" : "播放")
            .accessibilityValue(viewModel.sleepTimerActive ? "已定时，\(viewModel.sleepTimerRemainingMinutes) 分钟后停止" : "")
            .accessibilityHint(viewModel.isReading ? "轻点暂停朗读" : "轻点开始朗读")
            .accessibilityAction {
                viewModel.handlePlayButtonTap()
            }
            .accessibilityActions {
                ForEach(sortedSleepOptions, id: \.self) { minutes in
                    Button("\(minutes) 分钟后停止朗读") {
                        viewModel.startSleepTimer(minutes: minutes)
                    }
                }

                if viewModel.sleepTimerActive {
                    Button("关闭定时") {
                        viewModel.cancelSleepTimer()
                    }
                }
            }
    }
    
    private var playIconName: String {
        viewModel.isReading ? "pause.fill" : "play.fill"
    }

    /// 定时还剩多少：满圈开始，随时间一点点缩短，缩完即停止朗读。
    private var sleepTimerRing: some View {
        ZStack {
            Circle()
                .stroke(viewModel.currentAccentColor.opacity(0.2), lineWidth: sleepRingLineWidth)

            Circle()
                .trim(from: 0, to: 1 - viewModel.sleepTimerProgress)
                .stroke(
                    viewModel.currentAccentColor,
                    style: StrokeStyle(lineWidth: sleepRingLineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .linear(duration: 0.5), value: viewModel.sleepTimerProgress)
        }
        .padding(3)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
    
    // MARK: - Gesture
    
    /// 单一手势：触按即开始展开定时选项 → 计时 `longPressActivationDelay` 后生效；其后跟踪手指位置。
    /// 延迟内松手视作短按，直接走 `handlePlayButtonTap`，避免长按/短按手势冲突导致的浮层卡死。
    private var playButtonGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .updating($isPressingPlayButton) { _, isPressing, _ in
                isPressing = true
            }
            .onChanged { value in
                if sleepActivationWorkItem == nil && !sleepPickerActive {
                    let work = DispatchWorkItem {
                        activatePickerIfNeeded()
                    }
                    sleepActivationWorkItem = work
                    sleepPickerRevealing = true
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
                let wasPickerActive = sleepPickerActive
                resetSleepPickerInteraction()

                guard wasPickerActive else {
                    viewModel.handlePlayButtonTap()
                    return
                }

                let offset = offsetFromPlayCenter(value.location)
                if let minutes = SleepTimerPicker.hitTest(offsetFromCenter: offset, options: sortedSleepOptions) {
                    selectionHaptic.selectionChanged()
                    viewModel.startSleepTimer(minutes: minutes)
                } else if SleepTimerPicker.isInDeadZone(offsetFromCenter: offset) {
                    // 按得久了一点、手指没挪开：这仍然是一次点按，照常播放 / 暂停，不能什么都不发生。
                    // 手指挪到别处才松开，才算「不选了」。
                    viewModel.handlePlayButtonTap()
                }
            }
    }

    private func resetSleepPickerInteraction() {
        sleepActivationWorkItem?.cancel()
        sleepActivationWorkItem = nil
        sleepPickerRevealing = false
        sleepPickerActive = false
        sleepHoveredOption = nil
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
            animateProgressSlider(false)
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

    private func animateProgressSlider(_ isVisible: Bool) {
        if reduceMotion {
            showProgressSlider = isVisible
        } else {
            withAnimation(.spring(response: 0.3)) {
                showProgressSlider = isVisible
            }
        }
    }
}

// MARK: - 控制栏上方的小按钮

/// 小按钮的排法：一排放得下就并排；只差一点时每个按钮让出一点宽度（里面的字跟着略缩小）；
/// 还放不下才换行。每一行都居中。
///
/// 不用 ViewThatFits 在「并排 / 上下排」之间选：它每种排法各建一份按钮，
/// 换排法时按钮整个被换掉，正开着的菜单会跟着被关掉。
private struct AccessoryFlow: Layout {
    var spacing: CGFloat
    /// 为了排成一排，每个按钮最多让出多少宽度（0.1 就是一成）。再多，里面的字就缩得太小了。
    var maxSqueeze: CGFloat

    private struct Row {
        var items: [(index: Int, size: CGSize)]
        var width: CGFloat
        var height: CGFloat
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, maxWidth: proposal.width ?? .infinity)
        return CGSize(
            width: rows.map(\.width).max() ?? 0,
            height: rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // 按量尺寸时的同一个宽度来排，两次的结果才一定一样。
        var y = bounds.minY
        for row in rows(for: subviews, maxWidth: proposal.width ?? bounds.width) {
            var x = bounds.midX - row.width / 2
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + (row.height - item.size.height) / 2),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func rows(for subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        let ideals = subviews.map { $0.sizeThatFits(.unspecified) }
        if let squeezed = squeezedRow(subviews, ideals: ideals, maxWidth: maxWidth) {
            return [squeezed]
        }

        var rows: [Row] = []
        for (index, size) in ideals.enumerated() {
            if let last = rows.last, last.width + spacing + size.width <= maxWidth {
                rows[rows.count - 1] = Row(
                    items: last.items + [(index, size)],
                    width: last.width + spacing + size.width,
                    height: max(last.height, size.height)
                )
            } else {
                rows.append(Row(items: [(index, size)], width: size.width, height: size.height))
            }
        }
        return rows
    }

    /// 并排只差一点放不下时，把所有按钮按同一比例收窄，仍然排成一排。差得多就返回 nil，交给换行。
    private func squeezedRow(_ subviews: Subviews, ideals: [CGSize], maxWidth: CGFloat) -> Row? {
        guard ideals.count > 1, maxWidth.isFinite else { return nil }
        let gaps = spacing * CGFloat(ideals.count - 1)
        let content = ideals.reduce(0) { $0 + $1.width }
        guard content > 0, content + gaps > maxWidth else { return nil }
        let scale = (maxWidth - gaps) / content
        guard scale >= 1 - maxSqueeze else { return nil }

        var row = Row(items: [], width: gaps, height: 0)
        for (index, ideal) in ideals.enumerated() {
            let width = ideal.width * scale
            let measured = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            let size = CGSize(width: min(measured.width, width), height: measured.height)
            row.items.append((index, size))
            row.width += size.width
            row.height = max(row.height, size.height)
        }
        return row
    }
}

// 定时期间控制栏每半秒刷新一次（进度环在走）。带菜单的两个按钮各自成一个视图，
// 只在自己用到的值变了才刷新，否则菜单开着的时候会跟着每半秒重建一遍。

private struct ChipLabel: View {
    let title: String
    let systemImage: String

    private let height: CGFloat = 44

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.medium).monospacedDigit())
            .foregroundStyle(Color.primary)
            .lineLimit(1)
            .minimumScaleFactor(ControlPanel.accessoryLabelMinimumScale)
            .padding(.horizontal, 16)
            .frame(minHeight: height)
            .glassEffect(.regular.interactive(), in: .capsule)
            .contentShape(Capsule())
    }
}

private struct SleepTimerChip: View, Equatable {
    let options: [Int]
    let isTimerActive: Bool
    let remainingMinutes: Int
    let onStart: (Int) -> Void
    let onCancel: () -> Void

    static func == (lhs: SleepTimerChip, rhs: SleepTimerChip) -> Bool {
        lhs.options == rhs.options
            && lhs.isTimerActive == rhs.isTimerActive
            && lhs.remainingMinutes == rhs.remainingMinutes
    }

    private var title: String {
        isTimerActive ? "\(remainingMinutes) 分钟后停止" : "定时停止"
    }

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { minutes in
                Button("\(minutes) 分钟后停止朗读") {
                    onStart(minutes)
                }
            }

            if isTimerActive {
                Divider()

                Button {
                    onCancel()
                } label: {
                    Label("关闭定时", systemImage: "xmark")
                }
            }
        } label: {
            ChipLabel(title: title, systemImage: isTimerActive ? "moon.zzz.fill" : "moon.zzz")
        }
        .menuOrder(.fixed)
        .buttonStyle(.plain)
        .accessibilityLabel(isTimerActive ? "定时停止，\(title)" : "定时停止")
        .accessibilityHint("选择多久之后自动停止朗读")
    }
}

private struct ImportFirstBookButton: View, Equatable {
    /// 是否换了强调色以主题 id 为准，两个颜色都是跟着主题走的。
    let accentThemeId: String
    let accentColor: Color
    let onAccentColor: Color
    let onImport: (ImportMethod) -> Void

    static func == (lhs: ImportFirstBookButton, rhs: ImportFirstBookButton) -> Bool {
        lhs.accentThemeId == rhs.accentThemeId
    }

    var body: some View {
        Menu {
            ImportMenuItems(onSelect: onImport)
        } label: {
            Label("导入第一本书", systemImage: "plus")
                .font(.headline)
                .foregroundStyle(onAccentColor)
                .lineLimit(1)
                .minimumScaleFactor(ControlPanel.accessoryLabelMinimumScale)
                .padding(.horizontal, 24)
                .frame(minHeight: ControlPanel.accessoryRowHeight)
                .background(accentColor, in: Capsule())
                .contentShape(Capsule())
        }
        .menuOrder(.fixed)
        .buttonStyle(.plain)
        .accessibilityHint("可以从文件导入、粘贴文本，或用 Wi‑Fi 传书")
    }
}
