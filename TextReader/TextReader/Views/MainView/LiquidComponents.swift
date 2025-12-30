import SwiftUI

/// 液体玻璃风格按钮
struct LiquidButton<Content: View>: View {
    let action: () -> Void
    let content: Content
    
    init(action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.action = action
        self.content = content()
    }
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
                
                content
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

/// 缩放按钮样式
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// 带有进度的圆形按钮 (用于播放/暂停)
struct CircularProgressButton: View {
    let progress: Double
    let isPlaying: Bool
    let color: Color
    let action: () -> Void
    let longPressAction: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        ZStack {
            // 背景模糊
            Circle()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
            
            // 进度条背景
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 4)
                .padding(4)
            
            // 进度条
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(4)
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: progress)
            
            // 图标
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.title2)
                .foregroundColor(color)
        }
        .frame(width: 64, height: 64)
        .scaleEffect(isPressed ? 0.92 : 1.0)
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.3)
                .onEnded { _ in
                    let impact = UIImpactFeedbackGenerator(style: .medium)
                    impact.impactOccurred()
                    longPressAction()
                }
        )
        .simultaneousGesture(
            TapGesture()
                .onEnded {
                    action()
                }
        )
        // 用于缩放效果
        .onLongPressGesture(minimumDuration: 100, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}
