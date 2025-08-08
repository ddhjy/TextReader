import SwiftUI

/// 简洁的控制面板组件 - 禅意重构版本
struct ControlPanel: View {
    @ObservedObject var viewModel: ContentViewModel
    @State private var showSpeedSheet = false
    
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
                // 朗读速度（低频操作，收进菜单）
                Button(action: {
                    showSpeedSheet = true
                }) {
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
        .sheet(isPresented: $showSpeedSheet) {
            SpeedSheet(readingSpeed: $viewModel.readingSpeed, accent: viewModel.currentAccentColor)
        }
    }
}

// 轻量速度弹层：滑杆 + 常用预设
private struct SpeedSheet: View {
    @Binding var readingSpeed: Float
    let accent: Color
    @Environment(\.presentationMode) var presentationMode
    
    private func speedText(_ v: Float) -> String {
        v == floor(v) ? String(format: "%.0fx", v) : String(format: "%.2fx", v)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // 当前速度显示
                Text(speedText(readingSpeed))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(accent)
                    .padding(.top, 20)
                
                // 速度滑杆
                VStack(alignment: .leading, spacing: 8) {
                    Text("朗读速度")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Slider(
                        value: Binding(
                            get: { Double(readingSpeed) },
                            set: { readingSpeed = Float($0) }
                        ),
                        in: 0.8...3.0,
                        step: 0.05
                    )
                    .tint(accent)
                    
                    HStack {
                        Text("0.8x")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("3.0x")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
                
                // 常用预设
                VStack(alignment: .leading, spacing: 8) {
                    Text("常用速度")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                    
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        ForEach([1.0, 1.25, 1.5, 1.75, 2.0, 2.5], id: \.self) { speed in
                            Button(action: {
                                readingSpeed = Float(speed)
                            }) {
                                Text(speedText(Float(speed)))
                                    .font(.subheadline.weight(.medium))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(readingSpeed == Float(speed) ? accent : Color(UIColor.tertiarySystemFill))
                                    )
                                    .foregroundColor(readingSpeed == Float(speed) ? .white : .primary)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal)
                }
                
                Spacer()
            }
            .navigationTitle("朗读速度")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
