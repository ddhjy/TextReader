import SwiftUI

struct ContentDisplay: View {
    @ObservedObject var viewModel: ContentViewModel

    private let fontSize: CGFloat = 19
    private let kerning: CGFloat = 0.3
    private let lineSpacing: CGFloat = 8
    private let segmentSpacing: CGFloat = 22
    private let dimmedAlpha: CGFloat = 0.30

    var body: some View {
        GeometryReader { geometry in
            content(geometry: geometry)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    @ViewBuilder
    private func content(geometry: GeometryProxy) -> some View {
        if viewModel.pages.isEmpty {
            emptyState(width: geometry.size.width, height: geometry.size.height)
        } else {
            scrollingContent(geometry: geometry)
        }
    }

    private func emptyState(width: CGFloat, height: CGFloat) -> some View {
        Text("轻触书架，开始阅读")
            .font(.system(size: fontSize))
            .foregroundStyle(Color.primary.opacity(0.5))
            .frame(width: width, height: height)
    }

    private func scrollingContent(geometry: GeometryProxy) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear
                        .frame(height: geometry.size.height * 0.5)

                    LazyVStack(alignment: .leading, spacing: segmentSpacing) {
                        ForEach(viewModel.pages.indices, id: \.self) { idx in
                            Text(viewModel.pages[idx])
                                .font(.system(size: fontSize))
                                .kerning(kerning)
                                .lineSpacing(lineSpacing)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .id(idx)
                                .accessibilityHidden(idx != viewModel.currentPageIndex)
                        }
                    }
                    .padding(.horizontal)

                    Color.clear
                        .frame(height: geometry.size.height * 0.5)
                }
            }
            .scrollDisabled(true)
            .mask(focusGradient)
            .contentShape(Rectangle())
            .gesture(
                LongPressGesture(minimumDuration: 0.3)
                    .onEnded { _ in
                        viewModel.triggerBigBang()
                    }
            )
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        handleTapGesture(at: value.location, containerHeight: geometry.size.height)
                    }
            )
            .onAppear {
                DispatchQueue.main.async {
                    proxy.scrollTo(viewModel.currentPageIndex, anchor: .center)
                }
            }
            .onChange(of: viewModel.currentPageIndex) { _, newIndex in
                withAnimation(.easeInOut(duration: 0.45)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
            .onChange(of: viewModel.pages.count) { _, _ in
                DispatchQueue.main.async {
                    proxy.scrollTo(viewModel.currentPageIndex, anchor: .center)
                }
            }
        }
    }

    private var focusGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color.black.opacity(0.0),         location: 0.00),
                .init(color: Color.black.opacity(dimmedAlpha), location: 0.10),
                .init(color: Color.black.opacity(dimmedAlpha), location: 0.32),
                .init(color: Color.black,                       location: 0.42),
                .init(color: Color.black,                       location: 0.58),
                .init(color: Color.black.opacity(dimmedAlpha), location: 0.68),
                .init(color: Color.black.opacity(dimmedAlpha), location: 0.90),
                .init(color: Color.black.opacity(0.0),         location: 1.00)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func handleTapGesture(at location: CGPoint, containerHeight: CGFloat) {
        let isUpperArea = location.y < containerHeight / 2
        if isUpperArea {
            viewModel.previousPage()
        } else {
            viewModel.nextPage()
        }
    }
}
