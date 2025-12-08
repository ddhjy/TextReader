import Foundation

class SettingsManager {
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let readingSpeed = "readingSpeed"
        static let selectedVoiceIdentifier = "selectedVoiceIdentifier"
        static let lastOpenedBookId = "currentBookID"
        static let isDarkMode = "isDarkMode"
        static let accentColorThemeId = "accentColorThemeId"
        static let lastPageContent = "lastPageContent"
        static let lastPageIndex = "lastPageIndex"
        static let lastBookTitle = "lastBookTitle"
        static let lastTotalPages = "lastTotalPages"
    }

    func saveReadingSpeed(_ speed: Float) {
        defaults.set(speed, forKey: Keys.readingSpeed)
    }

    func getReadingSpeed() -> Float {
        let speed = defaults.float(forKey: Keys.readingSpeed)
        return speed == 0 ? 1.0 : speed
    }

    func saveSelectedVoiceIdentifier(_ identifier: String) {
        defaults.set(identifier, forKey: Keys.selectedVoiceIdentifier)
    }

    func getSelectedVoiceIdentifier() -> String? {
        return defaults.string(forKey: Keys.selectedVoiceIdentifier)
    }

    func saveLastOpenedBookId(_ bookFileName: String) {
        defaults.set(bookFileName, forKey: Keys.lastOpenedBookId)
    }

    func getLastOpenedBookId() -> String? {
        return defaults.string(forKey: Keys.lastOpenedBookId)
    }
    
    func saveDarkMode(_ enabled: Bool) {
        defaults.set(enabled, forKey: Keys.isDarkMode)
    }
    
    func getDarkMode() -> Bool {
        return defaults.bool(forKey: Keys.isDarkMode)
    }
    
    func saveAccentColorThemeId(_ id: String) {
        defaults.set(id, forKey: Keys.accentColorThemeId)
    }

    func getAccentColorThemeId() -> String {
        return defaults.string(forKey: Keys.accentColorThemeId) ?? "blue"
    }
    
    func saveLastPageContent(_ content: String) {
        defaults.set(content, forKey: Keys.lastPageContent)
    }
    
    func getLastPageContent() -> String? {
        return defaults.string(forKey: Keys.lastPageContent)
    }
    
    func saveLastPageIndex(_ index: Int) {
        defaults.set(index, forKey: Keys.lastPageIndex)
    }
    
    func getLastPageIndex() -> Int {
        return defaults.integer(forKey: Keys.lastPageIndex)
    }
    
    func saveLastBookTitle(_ title: String) {
        defaults.set(title, forKey: Keys.lastBookTitle)
    }
    
    func getLastBookTitle() -> String? {
        return defaults.string(forKey: Keys.lastBookTitle)
    }
    
    func saveLastTotalPages(_ count: Int) {
        defaults.set(count, forKey: Keys.lastTotalPages)
    }
    
    func getLastTotalPages() -> Int {
        return defaults.integer(forKey: Keys.lastTotalPages)
    }
} 