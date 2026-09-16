import SwiftUI
import UIKit

/// 切断阅读区与键盘安全区的 UIKit 耦合。
/// SwiftUI 的 `.ignoresSafeArea(.keyboard)` 拦不住背后 UIScrollView 的
/// `adjustedContentInset`，也不一定改得到 `UIHostingController.safeAreaRegions`；
/// sheet 收起时键盘弹簧仍会把正文拽走。
struct ReaderKeyboardIsolation: UIViewRepresentable {
    func makeUIView(context: Context) -> ProbeView {
        ProbeView()
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.applyIsolation()
    }

    final class ProbeView: UIView {
        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
            isOpaque = false
        }

        required init?(coder: NSCoder) {
            nil
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            applyIsolation()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            applyIsolation()
        }

        func applyIsolation() {
            disableKeyboardSafeAreaOnHostingControllers()
            isolateReaderScrollViews()
        }

        private func readerHostView() -> UIView? {
            var current: UIView? = self
            var host: UIView = self
            while let parent = current?.superview {
                if parent is UIWindow {
                    break
                }
                host = parent
                current = parent
            }
            return host
        }

        private func disableKeyboardSafeAreaOnHostingControllers() {
            var responder: UIResponder? = self
            while let current = responder {
                if let viewController = current as? UIViewController {
                    applyContainerSafeArea(to: viewController)
                    var ancestor = viewController.parent
                    while let parent = ancestor {
                        applyContainerSafeArea(to: parent)
                        ancestor = parent.parent
                    }
                }
                responder = current.next
            }
        }

        private func applyContainerSafeArea(to viewController: UIViewController) {
            let className = NSStringFromClass(type(of: viewController))
            guard className.contains("HostingController") else { return }

            let selector = NSSelectorFromString("setSafeAreaRegions:")
            guard viewController.responds(to: selector),
                  let method = class_getInstanceMethod(type(of: viewController), selector) else {
                return
            }

            typealias Setter = @convention(c) (AnyObject, Selector, UInt) -> Void
            let setter = unsafeBitCast(method_getImplementation(method), to: Setter.self)
            setter(viewController, selector, SafeAreaRegions.container.rawValue)
        }

        private func isolateReaderScrollViews() {
            guard let host = readerHostView() else { return }
            var stack = [host]
            while let view = stack.popLast() {
                if let scrollView = view as? UIScrollView {
                    scrollView.contentInsetAdjustmentBehavior = .never
                    scrollView.keyboardDismissMode = .none
                    scrollView.automaticallyAdjustsScrollIndicatorInsets = false
                }
                stack.append(contentsOf: view.subviews)
            }
        }
    }
}
