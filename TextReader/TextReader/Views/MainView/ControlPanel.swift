import SwiftUI

/// 控制面板组件，集成页面控制、阅读设置和深色模式切换功能
struct ControlPanel: View {
    @ObservedObject var viewModel: ContentViewModel

    var body: some View {
        VStack(spacing: 16) {
            Divider()
            // 页面导航和进度控制
            PageControl(viewModel: viewModel)
            Divider()
            // 朗读语音和速度控制
            ReadingControl(viewModel: viewModel)
            Divider()
            // 深色模式切换
            HStack {
                Spacer()
                Toggle(isOn: $viewModel.darkModeEnabled) {
                    Image(systemName: viewModel.darkModeEnabled ? "moon.fill" : "sun.max.fill")
                }
                .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                .accessibilityLabel("夜间模式")
            }
            .padding(.horizontal)
        }
        .padding()
    }
} 