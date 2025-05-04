## [Unreleased]

### Refactor
* **Decomposed `ContentModel`**: Extracted business logic from `ContentView` into a dedicated `ContentViewModel` to improve separation of concerns and testability.
* **Introduced ViewModel**: Implemented `ContentViewModel` as an `@StateObject` to manage the state and logic for `ContentView`, including text loading, page navigation, settings, search, and Wi-Fi transfer.

### Added
* **File Import Button**: Added an 'Import' button to the `BookListView` to allow users to import `.txt` files using the system's document picker (`DocumentPicker` view).
* **Copy WiFi URL**: Added a button to the Wi-Fi transfer overlay to allow users to copy the server URL directly to the clipboard.

### Fixed
* Improved handling of reading state transitions when changing pages or settings.
* Corrected issues with page calculation and display when font size or other settings are modified.
* Enhanced error handling for file loading and processing. 