import Foundation

class SettingsManager {
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let readingSpeed = "readingSpeed"
        static let selectedVoiceIdentifier = "selectedVoiceIdentifier"
        static let lastOpenedBookId = "currentBookID" // Keep old key for compatibility or migrate
    }

    // Reading Speed
    func saveReadingSpeed(_ speed: Float) {
        defaults.set(speed, forKey: Keys.readingSpeed)
    }

    func getReadingSpeed() -> Float {
        let speed = defaults.float(forKey: Keys.readingSpeed)
        return speed == 0 ? 1.0 : speed // Return 1.0 if not set or invalid
    }

    // Selected Voice
    func saveSelectedVoiceIdentifier(_ identifier: String) {
        defaults.set(identifier, forKey: Keys.selectedVoiceIdentifier)
    }

    func getSelectedVoiceIdentifier() -> String? {
        return defaults.string(forKey: Keys.selectedVoiceIdentifier)
    }

    // Last Opened Book
    func saveLastOpenedBookId(_ bookId: String) {
        defaults.set(bookId, forKey: Keys.lastOpenedBookId)
    }

    func getLastOpenedBookId() -> String? {
        return defaults.string(forKey: Keys.lastOpenedBookId)
    }
} 