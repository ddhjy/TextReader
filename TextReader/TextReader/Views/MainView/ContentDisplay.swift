import SwiftUI

struct ContentDisplay: View {
    @ObservedObject var viewModel: ContentViewModel

    var body: some View {
        VStack {
            Text(viewModel.pages.isEmpty ? "无内容" : viewModel.pages[viewModel.currentPageIndex])
                .padding()
                .font(.system(size: 18, weight: .regular, design: .serif))
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
} 