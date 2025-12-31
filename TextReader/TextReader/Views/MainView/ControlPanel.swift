import SwiftUI

struct ControlPanel: View {
    @ObservedObject var viewModel: ContentViewModel
    
    @Binding var showProgressSlider: Bool
    
    private var sliderBinding: Binding<Double> {
        Binding<Double>(
            get: { Double(viewModel.currentPageIndex) },
            set: { newVal in
                let newIndex = Int(newVal.rounded())
                guard newIndex != viewModel.currentPageIndex else { return }
                guard !viewModel.pages.isEmpty,
                      newIndex >= 0,
                      newIndex < viewModel.pages.count else { return }
                
                viewModel.stopReading()
                viewModel.currentPageIndex = newIndex
            }
        )
    }
    
    private var progress: Double {
        guard viewModel.pages.count > 0 else { return 0 }
        return Double(viewModel.currentPageIndex + 1) / Double(viewModel.pages.count)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            if showProgressSlider {
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
            
            HStack(spacing: 16) {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        showProgressSlider.toggle()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .stroke(viewModel.currentAccentColor.opacity(0.2), lineWidth: 2)
                        
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(viewModel.currentAccentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 10))
                            .fontWeight(.medium)
                            .foregroundColor(viewModel.currentAccentColor)
                    }
                    .frame(width: 32, height: 32)
                }
                .buttonStyle(.glass)
                .clipShape(.circle)
                .tint(viewModel.currentAccentColor)
                
                Button {
                    viewModel.showingBookList = true
                } label: {
                    Image(systemName: "books.vertical.fill")
                        .font(.title2)
                }
                .buttonStyle(.glass)
                .clipShape(.circle)
                .tint(viewModel.currentAccentColor)
                
                Button {
                    viewModel.toggleReading()
                } label: {
                    Image(systemName: viewModel.isReading ? "pause.fill" : "play.fill")
                        .font(.title)
                }
                .buttonStyle(.glass)
                .clipShape(.circle)
                .tint(viewModel.currentAccentColor)
                
                Button {
                    viewModel.showingSearchView = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.title2)
                }
                .buttonStyle(.glass)
                .clipShape(.circle)
                .tint(viewModel.currentAccentColor)
                
                Menu {
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
                    Image(systemName: "gearshape.fill")
                        .font(.title2)
                }
                .clipShape(.circle)
                .tint(viewModel.currentAccentColor)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }
}
