import SwiftUI

extension View {
    /// 在这一层界面上显示一条提示。
    ///
    /// sheet 会盖住下面的界面，所以每一层（阅读页、书架、粘贴导入…）各挂一次，
    /// 由最上面、没被盖住的那一层负责显示。
    ///
    /// 默认贴在顶部。内容从顶部第一行就开始的列表（书架、模板）贴在底部：
    /// 贴在顶部会正好盖住第一行，而提示说的往往就是那一行（刚导入的书、现在打开的书）。
    ///
    /// 提示由调用方读出 `viewModel.notice` 后按值传进来，这里不再自己观察 viewModel。
    /// 挂在 NavigationStack 根内容上的修饰器和外层视图算在同一个界面宿主里，两处同时观察同一个对象时，
    /// SwiftUI 有时会在值还没写进去的那一刻就重算外层视图，这次变化就丢了：
    /// 点「书架」「设置」没反应，要再点一次才打开。
    /// - Parameters:
    ///   - notice: 当前的提示，没有时传 nil。
    ///   - edge: 贴在这一层的顶部还是底部。
    ///   - isCovered: 这一层上面是否还盖着别的 sheet。
    ///   - errorsOnly: 只显示失败提示。用于成功后会立刻关闭的界面，避免提示跟着界面一起滑走。
    ///   - onShown: 这一层真的把提示显示出来了。会自动消失的提示从这时才开始计时。
    ///   - onDismiss: 用户点了提示，要把它收起来。
    func noticeBanner(
        _ notice: AppNotice?,
        edge: VerticalEdge = .top,
        isCovered: Bool = false,
        errorsOnly: Bool = false,
        onShown: @escaping (AppNotice) -> Void,
        onDismiss: @escaping () -> Void
    ) -> some View {
        modifier(
            NoticeBannerModifier(
                notice: notice,
                edge: edge,
                isCovered: isCovered,
                errorsOnly: errorsOnly,
                onShown: onShown,
                onDismiss: onDismiss
            )
        )
    }
}

private struct NoticeBannerModifier: ViewModifier {
    let notice: AppNotice?
    let edge: VerticalEdge
    let isCovered: Bool
    let errorsOnly: Bool
    let onShown: (AppNotice) -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var visibleNotice: AppNotice? {
        guard !isCovered, let notice else { return nil }
        if errorsOnly && notice.kind != .error { return nil }
        return notice
    }

    private var alignment: Alignment {
        edge == .top ? .top : .bottom
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: alignment) {
                // 动画只管这条提示自己的进出。挂在整层界面上的话，和提示同一时刻发生的其他变化
                // （换书后的定位、到头时的回弹）都会被带成同一段弹簧动画。
                ZStack(alignment: alignment) {
                    if let notice = visibleNotice {
                        NoticeBanner(notice: notice, onDismiss: onDismiss)
                            .padding(.horizontal, 16)
                            .padding(edge == .top ? .top : .bottom, 8)
                            .transition(
                                reduceMotion
                                    ? .opacity
                                    : .move(edge: edge == .top ? .top : .bottom).combined(with: .opacity)
                            )
                            .onAppear { onShown(notice) }
                            .id(notice.id)
                    }
                }
                .animation(.spring(response: 0.32, dampingFraction: 0.85), value: visibleNotice)
            }
            // 以「出现了一条新提示」为准，只由当时显示它的那一层震一下，不会每层各震一次。
            .sensoryFeedback(trigger: notice?.id) { _, _ in
                switch visibleNotice?.kind {
                case .error:
                    return .error
                case .success:
                    return .success
                case .info, .none:
                    return nil
                }
            }
    }
}

private struct NoticeBanner: View {
    let notice: AppNotice
    let onDismiss: () -> Void

    private let cornerRadius: CGFloat = 20

    var body: some View {
        Button(action: onDismiss) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: iconName)
                    .foregroundStyle(iconColor)

                Text(notice.message)
                    .foregroundStyle(Color.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)

                if notice.autoDismissDelay == nil {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.secondary)
                }
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            .contentShape(.rect(cornerRadius: cornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(notice.message)
        .accessibilityHint("轻点关闭")
        .accessibilityAddTraits(.isButton)
    }

    private var iconName: String {
        switch notice.kind {
        case .info:
            return "info.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        switch notice.kind {
        case .info:
            return .secondary
        case .success:
            return .green
        case .error:
            return .red
        }
    }
}
