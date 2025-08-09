import SwiftUI

/// 简洁的控制面板组件 - 禅意重构版本
struct ControlPanel: View {
    @ObservedObject var viewModel: ContentViewModel
    
    private func speedText(_ v: Float) -> String {
        v == floor(v) ? String(format: "%.0fx", v) : String(format: "%.2fx", v)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // [ ◀  (进度条)  ▶ ]
            PageControl(viewModel: viewModel)
                .frame(height: 36)
            
            // 播放/暂停按钮 - 高频操作，放在外面
            Button(action: {
                viewModel.toggleReading()
            }) {
                Image(systemName: viewModel.isReading ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .foregroundColor(.black)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(PlainButtonStyle())
            
            // [⚙] 速度/语音/强调色/夜间模式归拢到菜单
            Menu {
                // 朗读速度（改为菜单内直接选择）
                Menu {
                    ForEach([0.8, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0], id: \.self) { speed in
                        Button {
                            viewModel.readingSpeed = Float(speed)
                        } label: {
                            HStack {
                                Text(speedText(Float(speed)))
                                if abs(viewModel.readingSpeed - Float(speed)) < 0.01 {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Label("速度: " + speedText(viewModel.readingSpeed), systemImage: "gauge")
                }
                
                Divider()
                
                // 语音选择
                Menu {
                    ForEach(viewModel.availableVoices, id: \.identifier) { voice in
                        Button {
                            viewModel.selectedVoiceIdentifier = voice.identifier
                        } label: {
                            HStack {
                                Text(voice.name)
                                if voice.identifier == viewModel.selectedVoiceIdentifier {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Label("语音", systemImage: "speaker.wave.2")
                }
                
                // 强调色
                Button(action: {
                    viewModel.showingAccentColorPicker = true
                }) {
                    Label("强调色", systemImage: "paintpalette")
                }
                
                // 夜间模式
                Button(action: {
                    viewModel.darkModeEnabled.toggle()
                }) {
                    Label(
                        viewModel.darkModeEnabled ? "日间模式" : "夜间模式",
                        systemImage: viewModel.darkModeEnabled ? "sun.max.fill" : "moon.fill"
                    )
                }
            } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .padding(8)
                    .background(Circle().fill(Color(UIColor.secondarySystemBackground)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(UIColor.secondarySystemBackground))
    }
}

// 删除了原有的 SpeedSheet 结构体与相关弹窗
