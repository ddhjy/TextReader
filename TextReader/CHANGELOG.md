# Changelog

## [Unreleased]

### Refactor

* **Decomposed `ContentModel`**: Split the responsibilities of the monolithic `ContentModel` into dedicated services and managers (`LibraryManager`, `TextPaginator`, `SpeechManager`, `SearchService`, `WiFiTransferService`, `AudioSessionManager`, `SettingsManager`) to adhere to the Single Responsibility Principle.
* **Introduced ViewModel**: Added `ContentViewModel` to mediate between Views and Services/Managers, improving separation of concerns and testability.
* **Organized Code Structure**: Reorganized project files into a more structured directory layout (`Models`, `ViewModels`, `Views`, `Services`, `Managers`, etc.).
* **Separated View Components**: Moved individual SwiftUI views (`ContentDisplay`, `ControlPanel`, `BookListView`, `SearchView`, `SearchBar`, etc.) from `ContentView.swift` into their own respective files under the `./Views/` directory.
* **Encapsulated Business Logic**: Encapsulated text pagination, speech synthesis, search functionality, and WiFi transfer logic within their respective service/manager classes.
* **Improved Persistence**: Refactored data persistence to use JSON for library metadata and progress (handled by `LibraryManager`), while `UserDefaults` (via `SettingsManager`) is now used only for user preferences like voice, speed, and last opened book.
* **Managed Audio Session & Remote Controls**: Centralized `AVAudioSession` and `MPRemoteCommandCenter` configuration and updates within `AudioSessionManager`.
* Removed unused `CocoaAsyncSocket` dependency, relying solely on `Network.framework` for WiFi transfer.

### Added

* **File Import Button**: Added an 'Import' button to the `BookListView` to allow users to import `.txt` files using the system's document picker (`DocumentPicker` view).

### Fixed

* Improved handling of reading state transitions when changing pages or settings.
* Enhanced robustness of text pagination for edge cases (e.g., very long sentences, text without standard sentence structure).
* Improved background audio task management in `SpeechManager`.
* Correctly saves and restores total page count for books in `LibraryManager`. 