import Foundation

class SettingsManager {
    private let defaults: UserDefaults
    private let keyPrefix: String

    init(defaults: UserDefaults = .standard, keyPrefix: String = "") {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

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

        static let profileScoped = [
            readingSpeed,
            selectedVoiceIdentifier,
            lastOpenedBookId,
            lastPageContent,
            lastPageIndex,
            lastBookTitle,
            lastTotalPages
        ]

        static let sharedAppearance = [
            isDarkMode,
            accentColorThemeId
        ]
    }

    private func key(_ name: String) -> String {
        if Keys.sharedAppearance.contains(name) {
            return name
        }
        return keyPrefix + name
    }

    func saveReadingSpeed(_ speed: Float) {
        defaults.set(speed, forKey: key(Keys.readingSpeed))
    }

    func getReadingSpeed() -> Float {
        let speed = defaults.float(forKey: key(Keys.readingSpeed))
        return speed == 0 ? 1.0 : speed
    }

    func saveSelectedVoiceIdentifier(_ identifier: String) {
        defaults.set(identifier, forKey: key(Keys.selectedVoiceIdentifier))
    }

    func getSelectedVoiceIdentifier() -> String? {
        return defaults.string(forKey: key(Keys.selectedVoiceIdentifier))
    }

    func saveLastOpenedBookId(_ bookFileName: String) {
        defaults.set(bookFileName, forKey: key(Keys.lastOpenedBookId))
    }

    func getLastOpenedBookId() -> String? {
        return defaults.string(forKey: key(Keys.lastOpenedBookId))
    }
    
    func saveDarkMode(_ enabled: Bool) {
        defaults.set(enabled, forKey: key(Keys.isDarkMode))
    }
    
    func getDarkMode() -> Bool {
        return defaults.bool(forKey: key(Keys.isDarkMode))
    }
    
    func saveAccentColorThemeId(_ id: String) {
        defaults.set(id, forKey: key(Keys.accentColorThemeId))
    }

    func getAccentColorThemeId() -> String {
        return defaults.string(forKey: key(Keys.accentColorThemeId)) ?? "blue"
    }
    
    func saveLastPageContent(_ content: String) {
        defaults.set(content, forKey: key(Keys.lastPageContent))
    }
    
    func getLastPageContent() -> String? {
        return defaults.string(forKey: key(Keys.lastPageContent))
    }
    
    func saveLastPageIndex(_ index: Int) {
        defaults.set(index, forKey: key(Keys.lastPageIndex))
    }
    
    func getLastPageIndex() -> Int {
        return defaults.integer(forKey: key(Keys.lastPageIndex))
    }
    
    func saveLastBookTitle(_ title: String) {
        defaults.set(title, forKey: key(Keys.lastBookTitle))
    }
    
    func getLastBookTitle() -> String? {
        return defaults.string(forKey: key(Keys.lastBookTitle))
    }
    
    func saveLastTotalPages(_ count: Int) {
        defaults.set(count, forKey: key(Keys.lastTotalPages))
    }
    
    func getLastTotalPages() -> Int {
        return defaults.integer(forKey: key(Keys.lastTotalPages))
    }

    func removeAllManagedValues() {
        for managedKey in Keys.profileScoped {
            defaults.removeObject(forKey: key(managedKey))
        }
        if keyPrefix.isEmpty {
            for managedKey in Keys.sharedAppearance {
                defaults.removeObject(forKey: key(managedKey))
            }
        }
    }
} 
