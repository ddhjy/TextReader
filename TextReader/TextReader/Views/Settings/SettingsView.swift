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
    @State private var advancedDebugUnlocked = false
    @State private var aboutTapCount = 0
    @State private var pendingDebugAction: DebugProfileAction?

    private let unlockTapThreshold = 7
    private let speedOptions: [Float] = [0.8, 1.0, 1.25, 1.5, 1.75, 2.0, 3.0]

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return build.isEmpty ? version : "\(version) (\(build))"
    }

    private func speedLabel(_ speed: Float) -> String {
        speed == floor(speed) ? "\(Int(speed))x" : String(format: "%.2gx", speed)
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section("阅读设置") {
                    Picker(selection: $viewModel.readingSpeed) {
                        ForEach(speedOptions, id: \.self) { speed in
                            Text(speedLabel(speed)).tag(speed)
                        }
                    } label: {
                        Label("语速", systemImage: "speedometer")
                    }
                    .pickerStyle(.menu)
                    
                    Picker(selection: $viewModel.selectedVoiceIdentifier) {
                        ForEach(viewModel.availableVoices, id: \.identifier) { voice in
                            Text(voice.name).tag(Optional(voice.identifier))
                        }
                    } label: {
                        Label("语音", systemImage: "waveform")
                    }
                    .pickerStyle(.navigationLink)
                }
                
                Section("外观") {
                    Picker("外观", selection: $viewModel.appearanceMode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Label("强调色", systemImage: "paintpalette")
                            .font(.body)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 12) {
                            ForEach(AccentColorTheme.presets) { theme in
                                Button {
                                    viewModel.accentColorThemeId = theme.id
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(theme.dynamicColor)
                                            .frame(width: 36, height: 36)
                                        
                                        if viewModel.accentColorThemeId == theme.id {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 15, weight: .bold))
                                                .foregroundStyle(.white)
                                                .shadow(color: .black.opacity(0.35), radius: 2)
                                        }
                                    }
                                    .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(theme.name)
                                .accessibilityAddTraits(viewModel.accentColorThemeId == theme.id ? [.isButton, .isSelected] : .isButton)
                            }
                        }
                        .padding(.vertical, 4)
                    }
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

                if advancedDebugUnlocked {
                    Section {
                        LabeledContent {
                            Text(session.activeProfile.displayName)
                                .foregroundStyle(.secondary)
                        } label: {
                            Label("当前状态", systemImage: "switch.2")
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
                    } header: {
                        Text("高级调试")
                    } footer: {
                        Text("审核样例状态使用独立书架、阅读记录、缓存、模板和偏好，不会读写日常状态的数据。")
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        closeSettings()
                    }
                }
            }
        }
        .alert(
            debugAlertTitle(for: pendingDebugAction),
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
            switch action {
            case .switchProfile(let profile):
                Text(profile == .reviewSample
                     ? "App 会立即切到独立的审核样例数据空间。你的日常书架、阅读记录和偏好不会被修改。"
                     : "App 会立即恢复日常数据空间，审核样例状态的数据会保留，之后仍可切回。")
            case .resetReviewSample:
                Text("这会删除审核样例状态里的导入书籍、阅读记录、缓存、模板和偏好，并恢复为仅包含示例文本。日常状态不会受影响。")
            }
        }
        .onDisappear {
            lockAdvancedDebug()
        }
        .tint(viewModel.currentAccentColor)
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

    private func handleAboutTap() {
        guard !advancedDebugUnlocked else { return }
        aboutTapCount += 1
        if aboutTapCount >= unlockTapThreshold {
            advancedDebugUnlocked = true
            aboutTapCount = 0
        }
    }

    private func debugAlertTitle(for action: DebugProfileAction?) -> String {
        guard let action else { return "" }
        switch action {
        case .switchProfile(let profile):
            return profile == .reviewSample ? "切换到审核样例状态？" : "切回日常状态？"
        case .resetReviewSample:
            return "重置审核样例状态？"
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
