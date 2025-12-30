import SwiftUI

/// 液体玻璃风格控制面板
struct ControlPanel: View {
    @ObservedObject var viewModel: ContentViewModel
    
    // 是否显示临时的进度条（长按播放键触发）
    @State private var showProgressSlider = false
    
    // 进度条的值（用于拖拽）
    private var sliderBinding: Binding<Double> {
        Binding<Double>(
            get: { Double(viewModel.currentPageIndex) },
            set: { newVal in
                let newIndex = Int(newVal.rounded())
                guard newIndex != viewModel.currentPageIndex else { return }
                guard !viewModel.pages.isEmpty,
                      newIndex >= 0,
                      newIndex < viewModel.pages.count else { return }
                
                // 拖动时暂停阅读
                viewModel.stopReading()
                viewModel.currentPageIndex = newIndex
            }
        )
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // 临时进度条层
            if showProgressSlider {
                VStack {
                    Text("\(viewModel.currentPageIndex + 1) / \(max(1, viewModel.pages.count))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                    
                    Slider(value: sliderBinding, in: 0...Double(max(0, viewModel.pages.count - 1)))
                        .tint(viewModel.currentAccentColor)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                        .cornerRadius(16)
                        .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.horizontal)
            }
            
            // 底部按钮栏
            HStack(spacing: 24) {
                // 1. 选择书籍
                LiquidButton(action: {
                    viewModel.showingBookList = true
                }) {
                    Image(systemName: "books.vertical.fill")
                        .font(.title2)
                        .foregroundColor(viewModel.currentAccentColor)
                }
                
                // 2. 播放/暂停 (带进度环)
                CircularProgressButton(
                    progress: Double(viewModel.currentPageIndex + 1) / Double(max(1, viewModel.pages.count)),
                    isPlaying: viewModel.isReading,
                    color: viewModel.currentAccentColor,
                    action: {
                        viewModel.toggleReading()
                    },
                    longPressAction: {
                        withAnimation(.spring()) {
                            showProgressSlider.toggle()
                        }
                        
                        // 3秒后自动隐藏进度条
                        if showProgressSlider {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                withAnimation {
                                    showProgressSlider = false
                                }
                            }
                        }
                    }
                )
                .offset(y: -10) // 稍微突出一点
                
                // 3. 查询
                LiquidButton(action: {
                    viewModel.showingSearchView = true
                }) {
                    Image(systemName: "magnifyingglass")
                        .font(.title2)
                        .foregroundColor(viewModel.currentAccentColor)
                }
                
                // 4. 设置
                Menu {
                    // 原 ReadingControl 中的设置项
                    Section("阅读设置") {
                        Menu("语速") {
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
                        }
                        
                        Menu("语音") {
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
                        }
                    }
                    
                    Section("外观") {
                        Menu("强调色") {
                            ForEach(AccentColorTheme.presets) { theme in
                                Button {
                                    viewModel.accentColorThemeId = theme.id
                                } label: {
                                    HStack {
                                        Text(theme.name)
                                        if viewModel.accentColorThemeId == theme.id {
                                            Image(systemName: "checkmark")
                                        }
                                        Circle()
                                            .fill(theme.color(for: .light))
                                            .frame(width: 12, height: 12)
                                    }
                                }
                            }
                        }
                        
                        Button {
                            viewModel.darkModeEnabled.toggle()
                        } label: {
                            Label(
                                viewModel.darkModeEnabled ? "切换到日间模式" : "切换到夜间模式",
                                systemImage: viewModel.darkModeEnabled ? "sun.max" : "moon"
                            )
                        }
                    }

                } label: {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                        
                        Image(systemName: "gearshape.fill")
                            .font(.title2)
                            .foregroundColor(viewModel.currentAccentColor)
                    }
                    .frame(width: 64, height: 64)
                }
                .buttonStyle(ScaleButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }
}
