import SwiftUI

private enum DebugProfileAction: Identifiable {
    case switchProfile(AppDataProfile)
    case resetReviewSample

    var id: String {
        switch self {
        case .switchProfile(let profile):
            return "switch-\(profile.rawValue)"
        case .resetReviewSample:
            return "reset-review-sample"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var viewModel: ContentViewModel
    @ObservedObject var session: AppSessionController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var advancedDebugUnlocked = false
    @State private var aboutTapCount = 0
    @State private var pendingDebugAction: DebugProfileAction?

    private let unlockTapThreshold = 7
    private let speedOptions: [Double] = [0.8, 1.0, 1.25, 1.5, 1.75, 2.0, 3.0]

    private var versionText: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    /// 语速的显示文字。保留到够用的小数位：1.25 不能显示成「1.2x」，1.75 不能显示成「1.8x」。
    static func speedLabel(_ speed: Double) -> String {
        var text = String(format: "%.2f", speed)
        if text.hasSuffix("0") {
            text.removeLast()
        }
        return "\(text)x"
    }

    private var isReviewSampleActive: Bool {
        session.activeProfile == .reviewSample
    }

    private var currentVoiceSummary: String {
        guard let voice = viewModel.availableVoices.first(where: { $0.identifier == viewModel.selectedVoiceIdentifier }) else {
            return "未选择"
        }
        return VoiceCatalog.summary(for: voice)
    }
    
    var body: some View {
        NavigationStack {
            List {
                // 处在审核样例状态时，这一组始终摆在最上面：一眼看得出现在不是日常数据，也能一步切回去，
                // 不需要记得「再连点 7 次版本号」。
                if isReviewSampleActive {
                    dataProfileSection
                }

                Section("朗读") {
                    Picker(selection: $viewModel.readingSpeed) {
                        ForEach(speedOptions, id: \.self) { speed in
                            Text(Self.speedLabel(speed))
                                .tag(Float(speed))
                        }
                    } label: {
                        Label("语速", systemImage: "speedometer")
                    }
                    // 菜单样式的 Picker 不会随 tint 变化刷新，强调色变化时重建
                    .id(viewModel.accentColorThemeId)

                    NavigationLink {
                        VoicePickerView(viewModel: viewModel)
                    } label: {
                        LabeledContent {
                            Text(currentVoiceSummary)
                        } label: {
                            Label("语音", systemImage: "waveform")
                        }
                    }
                }
                
                Section("外观") {
                    Picker("外观", selection: $viewModel.appearanceMode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))

                    accentColorPalette
                }

                Section {
                    NavigationLink {
                        PromptTemplateLibraryView(viewModel: viewModel, showsCloseButton: false)
                    } label: {
                        LabeledContent {
                            Text("\(viewModel.templates.count) 个")
                        } label: {
                            Label("提示词模板", systemImage: "text.quote")
                        }
                    }
                } header: {
                    Text("选词")
                } footer: {
                    Text("在正文上按住约半秒可以选词，选好后复制，或套进模板。")
                }

                Section("关于") {
                    LabeledContent {
                        Text(versionText)
                            .foregroundStyle(.secondary)
                    } label: {
                        Label("版本", systemImage: "info.circle")
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        handleAboutTap()
                    }
                }

                if advancedDebugUnlocked && !isReviewSampleActive {
                    dataProfileSection
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) {
                        closeSettings()
                    }
                    .accessibilityLabel("关闭")
                }
            }
        }
        .alert(
            debugAlertTitle,
            isPresented: Binding(
                get: { pendingDebugAction != nil },
                set: { if !$0 { pendingDebugAction = nil } }
            ),
            presenting: pendingDebugAction
        ) { action in
            switch action {
            case .switchProfile(let profile):
                Button(profile == .reviewSample ? "切换" : "切回") {
                    session.switchProfile(to: profile)
                    closeSettings()
                }
                Button("取消", role: .cancel) {}
            case .resetReviewSample:
                Button("重置", role: .destructive) {
                    session.resetReviewSampleProfile()
                    closeSettings()
                }
                Button("取消", role: .cancel) {}
            }
        } message: { action in
            Text(debugAlertMessage(for: action))
        }
        .onDisappear {
            viewModel.stopVoicePreview()
            lockAdvancedDebug()
        }
        .tint(viewModel.currentAccentColor)
    }

    private var dataProfileSection: some View {
        Section {
            if isReviewSampleActive {
                Label("现在看到的是审核样例数据，不是你的日常书架", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else {
                LabeledContent {
                    Text(session.activeProfile.displayName)
                        .foregroundStyle(.secondary)
                } label: {
                    Label("当前状态", systemImage: "switch.2")
                }
            }

            Button {
                pendingDebugAction = .switchProfile(targetProfileForSwitch)
            } label: {
                Label(switchProfileButtonTitle, systemImage: "arrow.triangle.2.circlepath")
            }

            Button(role: .destructive) {
                pendingDebugAction = .resetReviewSample
            } label: {
                Label("重置审核样例状态", systemImage: "arrow.counterclockwise")
            }
            .tint(.red)
        } header: {
            Text(isReviewSampleActive ? "当前为审核样例状态" : "高级调试")
        } footer: {
            Text("审核样例状态使用独立书架、阅读记录、缓存、模板和偏好，不会读写日常状态的数据。")
        }
    }

    private var accentColorPalette: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("强调色", systemImage: "paintpalette")

            // 字号调到「辅助功能」那几档时一排放两个，名字才写得全（三个一排时「Obsidian」只剩「Obsi…」）。
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 8),
                    count: dynamicTypeSize.isAccessibilitySize ? 2 : 3
                ),
                spacing: 8
            ) {
                ForEach(AccentColorTheme.presets) { theme in
                    accentColorCell(theme)
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// 每个颜色带上名字；选中的那个外面多一圈，对勾用和底色对比最强的黑或白。
    private func accentColorCell(_ theme: AccentColorTheme) -> some View {
        let isSelected = viewModel.accentColorThemeId == theme.id
        return Button {
            viewModel.accentColorThemeId = theme.id
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(theme.dynamicColor)
                        .frame(width: 32, height: 32)

                    if isSelected {
                        // 圆点大小是固定的，对勾也用固定大小：跟着字号放大会撑出圆点，变成一团看不出是对勾的白块。
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(theme.onAccentDynamicColor)
                    }
                }
                .padding(4)
                .overlay {
                    Circle()
                        .strokeBorder(isSelected ? theme.dynamicColor : Color.clear, lineWidth: 2)
                }

                Text(theme.name)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 68)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var targetProfileForSwitch: AppDataProfile {
        session.activeProfile == .personal ? .reviewSample : .personal
    }

    private var switchProfileButtonTitle: String {
        switch targetProfileForSwitch {
        case .personal:
            return "切回日常状态"
        case .reviewSample:
            return "切换到审核样例状态"
        }
    }

    private var debugAlertTitle: String {
        switch pendingDebugAction {
        case .switchProfile(let profile):
            return profile == .reviewSample ? "切换到审核样例状态？" : "切回日常状态？"
        case .resetReviewSample:
            return "重置审核样例状态？"
        case .none:
            return ""
        }
    }

    private func debugAlertMessage(for action: DebugProfileAction) -> String {
        switch action {
        case .switchProfile(let profile):
            return profile == .reviewSample
                ? "App 会立即切到独立的审核样例数据空间。你的日常书架、阅读记录和偏好不会被修改。要切回来，打开「设置」，最上面就是。"
                : "App 会立即恢复日常数据空间，审核样例状态的数据会保留，之后仍可切回。"
        case .resetReviewSample:
            return "这会删除审核样例状态里的导入书籍、阅读记录、缓存、模板和偏好，并恢复为仅包含示例文本。日常状态不会受影响。"
        }
    }

    private func handleAboutTap() {
        guard !advancedDebugUnlocked else { return }
        aboutTapCount += 1
        if aboutTapCount >= unlockTapThreshold {
            advancedDebugUnlocked = true
            aboutTapCount = 0
        }
    }

    private func closeSettings() {
        lockAdvancedDebug()
        dismiss()
    }

    private func lockAdvancedDebug() {
        advancedDebugUnlocked = false
        aboutTapCount = 0
        pendingDebugAction = nil
    }
}

#Preview {
    SettingsView(viewModel: ContentViewModel(), session: AppSessionController())
}
