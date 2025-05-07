import Foundation

/// 设置管理器，负责应用程序设置的存储和获取
/// 使用UserDefaults存储用户偏好设置
class SettingsManager {
    /// 用于存储设置的UserDefaults对象
    private let defaults = UserDefaults.standard

    /// 存储键名的枚举
    private enum Keys {
        static let readingSpeed = "readingSpeed"
        static let selectedVoiceIdentifier = "selectedVoiceIdentifier"
        static let lastOpenedBookId = "currentBookID" // 保留旧键名以保持兼容性
        static let isDarkMode = "isDarkMode"
    }

    // MARK: - 朗读速度
    
    /// 保存朗读速度设置
    func saveReadingSpeed(_ speed: Float) {
        defaults.set(speed, forKey: Keys.readingSpeed)
    }

    /// 获取朗读速度，默认值1.0
    func getReadingSpeed() -> Float {
        let speed = defaults.float(forKey: Keys.readingSpeed)
        return speed == 0 ? 1.0 : speed // 如果未设置或无效则返回1.0
    }

    // MARK: - 语音选择
    
    /// 保存选定的语音标识符
    func saveSelectedVoiceIdentifier(_ identifier: String) {
        defaults.set(identifier, forKey: Keys.selectedVoiceIdentifier)
    }

    /// 获取选定的语音标识符
    func getSelectedVoiceIdentifier() -> String? {
        return defaults.string(forKey: Keys.selectedVoiceIdentifier)
    }

    // MARK: - 上次打开的书籍
    
    /// 保存上次打开的书籍ID
    func saveLastOpenedBookId(_ bookFileName: String) {
        defaults.set(bookFileName, forKey: Keys.lastOpenedBookId)
    }

    /// 获取上次打开的书籍ID
    func getLastOpenedBookId() -> String? {
        return defaults.string(forKey: Keys.lastOpenedBookId)
    }
    
    // MARK: - 深色模式
    
    /// 保存深色模式设置
    func saveDarkMode(_ enabled: Bool) {
        defaults.set(enabled, forKey: Keys.isDarkMode)
    }
    
    /// 获取深色模式设置
    func getDarkMode() -> Bool {
        return defaults.bool(forKey: Keys.isDarkMode)
    }
} 