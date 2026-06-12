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

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return build.isEmpty ? version : "\(version) (\(build))"
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section("阅读设置") {
                    // 语速选择
                    Menu {
                        ForEach([0.8, 1.0, 1.25, 1.5, 1.75, 2.0, 3.0], id: \.self) { speed in
                            Button {
                                viewModel.readingSpeed = Float(speed)
                            } label: {
                                if abs(viewModel.readingSpeed - Float(speed)) < 0.01 {
                                    Label(String(format: "%.1fx", speed), systemImage: "checkmark")
                                } else {
                                    Text(String(format: "%.1fx", speed))
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Label("语速", systemImage: "speedometer")
                            Spacer()
                            Text(String(format: "%.1fx", viewModel.readingSpeed))
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // 语音选择
                    Menu {
                        ForEach(viewModel.availableVoices, id: \.identifier) { voice in
                            Button {
                                viewModel.selectedVoiceIdentifier = voice.identifier
                            } label: {
                                if voice.identifier == viewModel.selectedVoiceIdentifier {
                                    Label(voice.name, systemImage: "checkmark")
                                } else {
                                    Text(voice.name)
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Label("语音", systemImage: "waveform")
                            Spacer()
                            if let selectedId = viewModel.selectedVoiceIdentifier,
                               let voice = viewModel.availableVoices.first(where: { $0.identifier == selectedId }) {
                                Text(voice.name)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                
                Section("外观") {
                    // 强调色选择
                    Menu {
                        ForEach(AccentColorTheme.presets) { theme in
                            Button {
                                viewModel.accentColorThemeId = theme.id
                            } label: {
                                HStack {
                                    Text(theme.name)
                                    if viewModel.accentColorThemeId == theme.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Label("强调色", systemImage: "paintpalette")
                            Spacer()
                            Circle()
                                .fill(viewModel.currentAccentColor)
                                .frame(width: 20, height: 20)
                            if let theme = AccentColorTheme.presets.first(where: { $0.id == viewModel.accentColorThemeId }) {
                                Text(theme.name)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    // 夜间模式切换
                    Toggle(isOn: $viewModel.darkModeEnabled) {
                        Label("夜间模式", systemImage: viewModel.darkModeEnabled ? "moon.fill" : "sun.max.fill")
                    }
                    .tint(viewModel.currentAccentColor)
                }

                Section("关于") {
                    HStack {
                        Label("版本", systemImage: "info.circle")
                        Spacer()
                        Text(versionText)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        handleAboutTap()
                    }
                }

                if advancedDebugUnlocked {
                    Section {
                        HStack {
                            Label("当前状态", systemImage: "switch.2")
                            Spacer()
                            Text(session.activeProfile.displayName)
                                .foregroundStyle(.secondary)
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
        .alert(item: $pendingDebugAction) { action in
            debugAlert(for: action)
        }
        .onDisappear {
            lockAdvancedDebug()
        }
        .tint(viewModel.currentAccentColor)
        .preferredColorScheme(viewModel.darkModeEnabled ? .dark : .light)
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

    private func debugAlert(for action: DebugProfileAction) -> Alert {
        let primaryButton: Alert.Button

        switch action {
        case .switchProfile(let profile):
            primaryButton = .default(Text(profile == .reviewSample ? "切换" : "切回")) {
                session.switchProfile(to: profile)
                closeSettings()
            }
            return Alert(
                title: Text(profile == .reviewSample ? "切换到审核样例状态？" : "切回日常状态？"),
                message: Text(profile == .reviewSample
                              ? "App 会立即切到独立的审核样例数据空间。你的日常书架、阅读记录和偏好不会被修改。"
                              : "App 会立即恢复日常数据空间，审核样例状态的数据会保留，之后仍可切回。"),
                primaryButton: primaryButton,
                secondaryButton: .cancel(Text("取消"))
            )

        case .resetReviewSample:
            primaryButton = .destructive(Text("重置")) {
                session.resetReviewSampleProfile()
                closeSettings()
            }
            return Alert(
                title: Text("重置审核样例状态？"),
                message: Text("这会删除审核样例状态里的导入书籍、阅读记录、缓存、模板和偏好，并恢复为仅包含示例文本。日常状态不会受影响。"),
                primaryButton: primaryButton,
                secondaryButton: .cancel(Text("取消"))
            )
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
