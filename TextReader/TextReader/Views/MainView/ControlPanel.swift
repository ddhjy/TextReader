import SwiftUI

struct ControlPanel: View {
    @ObservedObject var viewModel: ContentViewModel

    var body: some View {
        VStack(spacing: 16) {
            Divider()
            PageControl(viewModel: viewModel)
            Divider()
            ReadingControl(viewModel: viewModel)
        }
        .padding()
    }
} 