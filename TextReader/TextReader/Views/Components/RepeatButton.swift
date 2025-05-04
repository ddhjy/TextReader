import SwiftUI

struct RepeatButton<Label: View>: View {
    let action: () -> Void
    let longPressAction: () -> Void
    let label: () -> Label

    @State private var isPressed = false
    @State private var timer: Timer?

    var body: some View {
        label()
            .buttonStyle(PressableButtonStyle())
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .onLongPressGesture(minimumDuration: 0.2, pressing: { pressing in
                self.isPressed = pressing
                if pressing {
                    // 开始定时器，每0.1秒调用一次长按操作
                    self.timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                        self.longPressAction()
                    }
                } else {
                    // 停止定时器
                    self.timer?.invalidate()
                    self.timer = nil
                }
            }, perform: {
                // 长按手势完成后的操作（可留空）
            })
            .simultaneousGesture(
                TapGesture()
                    .onEnded {
                        self.action()
                    }
            )
    }
} 