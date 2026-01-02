import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: ContentViewModel
    @Environment(\.dismiss) private var dismiss
    
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
                                .foregroundColor(.secondary)
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
                                    .foregroundColor(.secondary)
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
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // 夜间模式切换
                    Toggle(isOn: $viewModel.darkModeEnabled) {
                        Label("夜间模式", systemImage: viewModel.darkModeEnabled ? "moon.fill" : "sun.max.fill")
                    }
                    .tint(viewModel.currentAccentColor)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
        .accentColor(viewModel.currentAccentColor)
        .preferredColorScheme(viewModel.darkModeEnabled ? .dark : .light)
    }
}

#Preview {
    SettingsView(viewModel: ContentViewModel())
}
