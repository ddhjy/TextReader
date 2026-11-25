import SwiftUI
import UIKit

struct AccentColorTheme: Identifiable, Codable {
    let id: String
    let name: String
    let lightColor: String
    let darkColor: String
    
    func color(for colorScheme: ColorScheme) -> Color {
        let hex = colorScheme == .dark ? darkColor : lightColor
        return Color(hex: hex) ?? .accentColor
    }

    var dynamicColor: Color {
        let lightColor = lightColor
        let darkColor = darkColor
        return Self.dynamicColors.color(forKey: "accent|\(lightColor)|\(darkColor)") {
            Color(uiColor: UIColor { traits in
                let hex = traits.userInterfaceStyle == .dark ? darkColor : lightColor
                return UIColor(Color(hex: hex) ?? .accentColor)
            })
        }
    }

    /// 压在强调色底上的文字 / 图标颜色：黑白里取对比度更高的那个。
    /// 深色模式下强调色都偏亮，白字压上去会看不清（「经典黑」的深色值几乎就是白色）。
    var onAccentDynamicColor: Color {
        let lightColor = lightColor
        let darkColor = darkColor
        return Self.dynamicColors.color(forKey: "onAccent|\(lightColor)|\(darkColor)") {
            Color(uiColor: UIColor { traits in
                let hex = traits.userInterfaceStyle == .dark ? darkColor : lightColor
                return Self.prefersDarkForeground(onHex: hex) ? .black : .white
            })
        }
    }

    /// 同一套配色每次都给出同一个颜色对象。
    /// 跟随深浅色变化的颜色只和它自己相等：每次都新建的话，界面每刷新一次系统都以为强调色换了，
    /// 所有用到强调色的地方（包括正开着的菜单）都跟着重画一遍。
    private static let dynamicColors = DynamicColorCache()

    /// 每个颜色都满足正文对比度 4.5:1：浅色值压在白底和分组灰底（#F2F2F7）上，
    /// 深色值压在黑底和弹层的两级深灰底（#1C1C1E、#2C2C2E）上。由单元测试守住。
    static let presets: [AccentColorTheme] = [
        AccentColorTheme(id: "blue", name: "默认蓝", lightColor: "#0A60E0", darkColor: "#409CFF"),
        AccentColorTheme(id: "green", name: "护眼绿", lightColor: "#1F7A36", darkColor: "#30D158"),
        AccentColorTheme(id: "orange", name: "温暖橙", lightColor: "#B24A00", darkColor: "#FF9F0A"),
        AccentColorTheme(id: "purple", name: "优雅紫", lightColor: "#8A3FC2", darkColor: "#C774F5"),
        AccentColorTheme(id: "red", name: "活力红", lightColor: "#CC1F1A", darkColor: "#FF6961"),
        AccentColorTheme(id: "teal", name: "清新青", lightColor: "#00708F", darkColor: "#64D2FF"),
        AccentColorTheme(id: "sky-blue", name: "天蓝色", lightColor: "#2A66C0", darkColor: "#6FA5EE"),
        AccentColorTheme(id: "obsidian", name: "Obsidian", lightColor: "#6652C9", darkColor: "#9B8CEB"),
        AccentColorTheme(id: "black", name: "经典黑", lightColor: "#1C1C1E", darkColor: "#F2F2F7")
    ]

    /// WCAG 相对亮度，取值 0（黑）到 1（白）。
    static func relativeLuminance(hex: String) -> Double? {
        guard let components = Color.rgbComponents(hex: hex) else { return nil }

        func linearized(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * linearized(components.red)
            + 0.7152 * linearized(components.green)
            + 0.0722 * linearized(components.blue)
    }

    /// WCAG 对比度，取值 1 到 21。
    static func contrastRatio(_ firstHex: String, _ secondHex: String) -> Double? {
        guard let first = relativeLuminance(hex: firstHex),
              let second = relativeLuminance(hex: secondHex) else {
            return nil
        }
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    static func prefersDarkForeground(onHex hex: String) -> Bool {
        guard let luminance = relativeLuminance(hex: hex) else { return false }
        let contrastWithWhite = 1.05 / (luminance + 0.05)
        let contrastWithBlack = (luminance + 0.05) / 0.05
        return contrastWithBlack > contrastWithWhite
    }
}

private final class DynamicColorCache: @unchecked Sendable {
    private let lock = NSLock()
    private var colors: [String: Color] = [:]

    func color(forKey key: String, make: () -> Color) -> Color {
        lock.lock()
        defer { lock.unlock() }
        if let cached = colors[key] {
            return cached
        }
        let color = make()
        colors[key] = color
        return color
    }
}

extension Color {
    fileprivate static func rgbComponents(hex: String) -> (red: Double, green: Double, blue: Double, opacity: Double)? {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var int: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&int)
        
        let a, r, g, b: UInt64
        switch hexSanitized.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }

        return (Double(r) / 255, Double(g) / 255, Double(b) / 255, Double(a) / 255)
    }

    init?(hex: String) {
        guard let components = Color.rgbComponents(hex: hex) else { return nil }
        
        self.init(
            .sRGB,
            red: components.red,
            green: components.green,
            blue: components.blue,
            opacity: components.opacity
        )
    }
}
