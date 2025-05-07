import Foundation

/// 设置管理器，负责应用程序设置的存储和获取
/// 
/// 使用UserDefaults存储用户偏好设置，包括：
/// - 朗读速度
/// - 选定的语音标识符
/// - 上次打开的书籍ID
/// - 深色模式设置
class SettingsManager {
    /// 用于存储设置的UserDefaults对象
    private let defaults = UserDefaults.standard

    /// 定义存储键名的枚举
    private enum Keys {
        /// 朗读速度的键名
        static let readingSpeed = "readingSpeed"
        /// 选定语音标识符的键名
        static let selectedVoiceIdentifier = "selectedVoiceIdentifier"
        /// 上次打开书籍ID的键名（保留旧键名以保持兼容性）
        static let lastOpenedBookId = "currentBookID" // 保留旧键名以保持兼容性
        /// 深色模式设置的键名
        static let isDarkMode = "isDarkMode"
    }

    // MARK: - 朗读速度
    
    /// 保存朗读速度设置
    /// - Parameter speed: 朗读速度值
    func saveReadingSpeed(_ speed: Float) {
        defaults.set(speed, forKey: Keys.readingSpeed)
    }

    /// 获取朗读速度设置
    /// - Returns: 朗读速度，如果未设置则返回默认值1.0
    func getReadingSpeed() -> Float {
        let speed = defaults.float(forKey: Keys.readingSpeed)
        return speed == 0 ? 1.0 : speed // 如果未设置或无效则返回1.0
    }

    // MARK: - 语音选择
    
    /// 保存选定的语音标识符
    /// - Parameter identifier: 语音标识符
    func saveSelectedVoiceIdentifier(_ identifier: String) {
        defaults.set(identifier, forKey: Keys.selectedVoiceIdentifier)
    }

    /// 获取选定的语音标识符
    /// - Returns: 语音标识符，如果未设置则返回nil
    func getSelectedVoiceIdentifier() -> String? {
        return defaults.string(forKey: Keys.selectedVoiceIdentifier)
    }

    // MARK: - 上次打开的书籍
    
    /// 保存上次打开的书籍ID
    /// - Parameter bookFileName: 书籍文件名，用作ID
    func saveLastOpenedBookId(_ bookFileName: String) {
        defaults.set(bookFileName, forKey: Keys.lastOpenedBookId)
    }

    /// 获取上次打开的书籍ID
    /// - Returns: 书籍ID，如果未设置则返回nil
    func getLastOpenedBookId() -> String? {
        return defaults.string(forKey: Keys.lastOpenedBookId)
    }
    
    // MARK: - 深色模式
    
    /// 保存深色模式设置
    /// - Parameter enabled: 是否启用深色模式
    func saveDarkMode(_ enabled: Bool) {
        defaults.set(enabled, forKey: Keys.isDarkMode)
    }
    
    /// 获取深色模式设置
    /// - Returns: 是否启用深色模式
    func getDarkMode() -> Bool {
        return defaults.bool(forKey: Keys.isDarkMode)
    }
} 