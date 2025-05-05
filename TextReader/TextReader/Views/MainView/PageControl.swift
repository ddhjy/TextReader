import SwiftUI

struct PageControl: View {
    @ObservedObject var viewModel: ContentViewModel

    var body: some View {
        VStack(spacing: 8) {
            Text("\(viewModel.currentPageIndex + 1) / \(viewModel.pages.count)")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                // Previous page button
                RepeatButton(
                    action: { viewModel.previousPage() },
                    longPressAction: {
                        // Continuously call previousPage on long press
                        if viewModel.currentPageIndex > 0 {
                            viewModel.previousPage()
                        }
                    },
                    label: {
                        Image(systemName: "chevron.left")
                            .font(.title)
                    }
                )
                .disabled(viewModel.currentPageIndex == 0)

                Spacer()

                Button(action: { viewModel.toggleReading() }) {
                    Image(systemName: viewModel.isReading ? "pause.circle.fill" : "play.circle.fill")
                        .font(.largeTitle)
                }

                Spacer()

                // Next page button
                RepeatButton(
                    action: { viewModel.nextPage() },
                    longPressAction: {
                        // Continuously call nextPage on long press
                        if viewModel.currentPageIndex < viewModel.pages.count - 1 {
                            viewModel.nextPage()
                        }
                    },
                    label: {
                        Image(systemName: "chevron.right")
                            .font(.title)
                    }
                )
                .disabled(viewModel.currentPageIndex >= viewModel.pages.count - 1)
            }
            .padding(.horizontal)
        }
    }
} 