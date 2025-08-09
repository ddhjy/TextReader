import SwiftUI

struct RepeatButton<Label: View>: View, @unchecked Sendable {
    let action: () -> Void
    let longPressAction: () -> Void
    let label: () -> Label

    @State private var isPressed = false
    @State private var timer: Timer?

    var body: some View {
        label()
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .buttonStyle(PressableButtonStyle())
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .onLongPressGesture(minimumDuration: 0.2, pressing: { pressing in
                self.isPressed = pressing
                if pressing {
                    self.timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                        self.longPressAction()
                    }
                } else {
                    self.timer?.invalidate()
                    self.timer = nil
                }
            }, perform: {})
            .simultaneousGesture(
                TapGesture()
                    .onEnded {
                        self.action()
                    }
            )
    }
} 