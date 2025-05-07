import SwiftUI

struct RepeatButton<Label: View>: View, @unchecked Sendable {
    let action: () -> Void
    let longPressAction: () -> Void
    let label: () -> Label

    @State private var isPressed = false
    @State private var timer: Timer?

    var body: some View {
        label()
            .frame(minWidth: 44, minHeight: 44)        // ① HIG 建议
            .contentShape(Rectangle())                 // ② 扩大热区
            .buttonStyle(PressableButtonStyle())
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .onLongPressGesture(minimumDuration: 0.2, pressing: { pressing in
                self.isPressed = pressing
                if pressing {
                    // Start timer, call longPressAction every 0.1 seconds
                    self.timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                        self.longPressAction()
                    }
                } else {
                    // Stop timer
                    self.timer?.invalidate()
                    self.timer = nil
                }
            }, perform: {
                // Action after long press gesture completes (can be empty)
            })
            .simultaneousGesture(
                TapGesture()
                    .onEnded {
                        self.action()
                    }
            )
    }
} 