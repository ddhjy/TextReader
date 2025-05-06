import SwiftUI

struct ControlPanel: View {
    @ObservedObject var viewModel: ContentViewModel

    var body: some View {
        VStack(spacing: 16) {
            Divider()
            PageControl(viewModel: viewModel)
            Divider()
            ReadingControl(viewModel: viewModel)
            Divider()
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