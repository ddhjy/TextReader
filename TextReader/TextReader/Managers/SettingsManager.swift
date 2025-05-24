import Foundation

class SettingsManager {
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let readingSpeed = "readingSpeed"
        static let selectedVoiceIdentifier = "selectedVoiceIdentifier"
        static let lastOpenedBookId = "currentBookID"
        static let isDarkMode = "isDarkMode"
    }

    // MARK: - 朗读速度
    
    func saveReadingSpeed(_ speed: Float) {
        defaults.set(speed, forKey: Keys.readingSpeed)
    }

    func getReadingSpeed() -> Float {
        let speed = defaults.float(forKey: Keys.readingSpeed)
        return speed == 0 ? 1.0 : speed
    }

    // MARK: - 语音选择
    
    func saveSelectedVoiceIdentifier(_ identifier: String) {
        defaults.set(identifier, forKey: Keys.selectedVoiceIdentifier)
    }

    func getSelectedVoiceIdentifier() -> String? {
        return defaults.string(forKey: Keys.selectedVoiceIdentifier)
    }

    // MARK: - 上次打开的书籍
    
    func saveLastOpenedBookId(_ bookFileName: String) {
        defaults.set(bookFileName, forKey: Keys.lastOpenedBookId)
    }

    func getLastOpenedBookId() -> String? {
        return defaults.string(forKey: Keys.lastOpenedBookId)
    }
    
    // MARK: - 深色模式
    
    func saveDarkMode(_ enabled: Bool) {
        defaults.set(enabled, forKey: Keys.isDarkMode)
    }
    
    func getDarkMode() -> Bool {
        return defaults.bool(forKey: Keys.isDarkMode)
    }
} 