import SwiftUI

struct AccentColorTheme: Identifiable, Codable {
    let id: String
    let name: String
    let lightColor: String  // 浅色模式下的颜色
    let darkColor: String   // 深色模式下的颜色
    
    func color(for colorScheme: ColorScheme) -> Color {
        let hex = colorScheme == .dark ? darkColor : lightColor
        return Color(hex: hex) ?? .accentColor
    }
    
    // 预设主题
    static let presets: [AccentColorTheme] = [
        AccentColorTheme(id: "blue", name: "默认蓝", lightColor: "#007AFF", darkColor: "#0A84FF"),
        AccentColorTheme(id: "green", name: "护眼绿", lightColor: "#34C759", darkColor: "#30D158"),
        AccentColorTheme(id: "orange", name: "温暖橙", lightColor: "#FF9500", darkColor: "#FF9F0A"),
        AccentColorTheme(id: "purple", name: "优雅紫", lightColor: "#AF52DE", darkColor: "#BF5AF2"),
        AccentColorTheme(id: "red", name: "活力红", lightColor: "#FF3B30", darkColor: "#FF453A"),
        AccentColorTheme(id: "teal", name: "清新青", lightColor: "#5AC8FA", darkColor: "#64D2FF"),
        AccentColorTheme(id: "sky-blue", name: "天蓝色", lightColor: "#4C8CE6", darkColor: "#4C8CE6"),
        AccentColorTheme(id: "obsidian", name: "Obsidian", lightColor: "#705dcf", darkColor: "#705dcf")
    ]
}

// Color扩展支持hex字符串
extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
} 
