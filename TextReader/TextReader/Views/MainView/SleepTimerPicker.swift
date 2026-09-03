import SwiftUI

/// 长按播放按钮触发的「定时播放」选项浮层。
/// 三个选项以扇形排布于播放按钮上方；调用方根据手指拖动位置传入 `hoveredMinutes` 高亮当前命中的选项。
struct SleepTimerPicker: View {
    let options: [Int]
    let hoveredMinutes: Int?
    let accentColor: Color
    
    var body: some View {
        ZStack {
            ForEach(options, id: \.self) { minutes in
                let isHovered = hoveredMinutes == minutes
                
                VStack(spacing: 2) {
                    Text("\(minutes)")
                        .font(.title3)
                        .fontWeight(isHovered ? .semibold : .medium)
                        .monospacedDigit()
                    Text("分钟")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 56, height: 56)
                .foregroundStyle(isHovered ? Color.white : accentColor)
                .background(
                    Circle()
                        .fill(isHovered ? accentColor : Color.clear)
                )
                .glassEffect(.regular.interactive(), in: .circle)
                .shadow(color: accentColor.opacity(isHovered ? 0.35 : 0.0), radius: 10)
                .scaleEffect(isHovered ? 1.12 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isHovered)
                .offset(SleepTimerPicker.offset(forOption: minutes))
            }
        }
        .frame(width: 280, height: 220)
        .allowsHitTesting(false)
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }
    
    // MARK: - Layout helpers
    
    /// 选项相对于（隐含的）播放按钮中心的偏移。
    /// 三个选项位于播放按钮上方的扇形：左上、正上、右上。
    static func offset(forOption minutes: Int) -> CGSize {
        let radius: CGFloat = 96
        let angleDegrees: Double
        switch minutes {
        case let m where m == SleepTimerPicker.sortedOptions.first:
            angleDegrees = 135
        case let m where m == SleepTimerPicker.sortedOptions.last:
            angleDegrees = 45
        default:
            angleDegrees = 90
        }
        let radians = angleDegrees * .pi / 180
        return CGSize(width: cos(radians) * radius, height: -sin(radians) * radius)
    }
    
    private static var sortedOptions: [Int] {
        ContentViewModel.sleepTimerOptions.sorted()
    }
    
    /// 给定手指相对播放按钮中心的偏移，返回命中的选项分钟数；未命中返回 nil。
    /// 命中策略：先用距离做激活判定（避免一动就选中），再按角度落入哪个扇形决定命中项。
    static func hitTest(offsetFromCenter offset: CGSize, options: [Int]) -> Int? {
        let distanceFromCenter = hypot(offset.width, offset.height)
        // 死区：距离播放按钮太近视为未选中。
        guard distanceFromCenter > 28 else { return nil }
        // 仅当手指处于上半区域时才命中（避免向下滑误选）。
        guard offset.height < 0 else { return nil }
        
        // 转换为标准数学角度（向右为 0°，向上为 90°）。
        let fingerAngle = atan2(-Double(offset.height), Double(offset.width)) * 180 / .pi
        
        let sorted = options.sorted()
        let mappedAngles: [(minutes: Int, angle: Double)] = sorted.enumerated().map { idx, minutes in
            let angle: Double
            if idx == 0 {
                angle = 135
            } else if idx == sorted.count - 1 {
                angle = 45
            } else {
                angle = 90
            }
            return (minutes, angle)
        }
        
        var bestMinutes: Int?
        var bestDelta = Double.infinity
        for entry in mappedAngles {
            var delta = abs(fingerAngle - entry.angle)
            if delta > 180 { delta = 360 - delta }
            if delta < bestDelta {
                bestDelta = delta
                bestMinutes = entry.minutes
            }
        }
        // 整个扇形外（>30° 偏差）视为未命中，再松手即取消。
        return bestDelta <= 30 ? bestMinutes : nil
    }
}
