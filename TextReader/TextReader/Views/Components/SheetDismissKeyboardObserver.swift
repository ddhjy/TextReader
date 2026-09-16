import SwiftUI
import UIKit

/// 交互式下拉关闭 sheet 一开始就收起键盘。
/// 系统默认要等 sheet 完全消失才 resign，键盘弹簧会落在主页已经露出来之后。
struct SheetDismissKeyboardObserver: UIViewControllerRepresentable {
    var onInteractiveDismiss: () -> Void

    func makeUIViewController(context: Context) -> Observer {
        Observer(onInteractiveDismiss: onInteractiveDismiss)
    }

    func updateUIViewController(_ uiViewController: Observer, context: Context) {
        uiViewController.onInteractiveDismiss = onInteractiveDismiss
    }

    final class Observer: UIViewController {
        var onInteractiveDismiss: () -> Void
        private let attachedGestures = NSHashTable<UIGestureRecognizer>.weakObjects()
        private var didResignForCurrentDismiss = false

        init(onInteractiveDismiss: @escaping () -> Void) {
            self.onInteractiveDismiss = onInteractiveDismiss
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) {
            nil
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
            view.isOpaque = false
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            didResignForCurrentDismiss = false
            attachSheetDismissGestures()
            DispatchQueue.main.async { [weak self] in
                self?.attachSheetDismissGestures()
            }
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            attachSheetDismissGestures()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if isSheetDismissing {
                resignKeyboard()
            }
        }

        private var isSheetDismissing: Bool {
            var current: UIViewController? = self
            while let viewController = current {
                if viewController.isBeingDismissed {
                    return true
                }
                current = viewController.parent
            }
            return false
        }

        private func sheetHost() -> UIViewController? {
            var current: UIViewController? = self
            while let viewController = current {
                if viewController.presentingViewController != nil {
                    return viewController
                }
                current = viewController.parent
            }
            return nil
        }

        private func attachSheetDismissGestures() {
            guard let host = sheetHost() else { return }
            // 只挂 sheet 容器自己的手势，不深入 List / 搜索框，避免打字时误收键盘。
            let targets = [host.view, host.presentationController?.presentedView].compactMap { $0 }
            for view in targets {
                for gesture in view.gestureRecognizers ?? [] where gesture is UIPanGestureRecognizer {
                    guard !attachedGestures.contains(gesture) else { continue }
                    gesture.addTarget(self, action: #selector(handleSheetGesture(_:)))
                    attachedGestures.add(gesture)
                }
            }
        }

        @objc private func handleSheetGesture(_ gesture: UIGestureRecognizer) {
            guard let pan = gesture as? UIPanGestureRecognizer else { return }
            switch pan.state {
            case .began, .changed:
                if pan.translation(in: pan.view).y > 8 {
                    resignKeyboard()
                }
            case .cancelled, .failed:
                didResignForCurrentDismiss = false
            default:
                break
            }
        }

        private func resignKeyboard() {
            guard !didResignForCurrentDismiss else { return }
            didResignForCurrentDismiss = true
            onInteractiveDismiss()
            view.window?.endEditing(true)
        }
    }
}
