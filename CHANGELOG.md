## [Unreleased]

### Refactor
* **Decomposed `ContentModel`**: Extracted business logic from `ContentView` into a dedicated `ContentViewModel` to improve separation of concerns and testability.
* **Introduced ViewModel**: Implemented `ContentViewModel` as an `@StateObject` to manage the state and logic for `ContentView`, including text loading, page navigation, settings, search, and Wi-Fi transfer.
* **Moved WiFi UI**: Migrated WiFi transfer UI elements (status display, copy URL button) and controls (start/stop button) from `ContentView` overlay and toolbar to the new `WiFiTransferView`.

### Added
* **File Import Button**: Added an 'Import' button to the `BookListView` to allow users to import `.txt` files using the system's document picker (`DocumentPicker` view).
* **Copy WiFi URL**: Added a button to the Wi-Fi transfer overlay to allow users to copy the server URL directly to the clipboard.
* **WiFi Transfer Page**: Created a dedicated page (`WiFiTransferView`) for managing WiFi file transfers, accessible via a toolbar button. Allows users to start/stop the transfer service and view/copy the access URL.

### Fixed
* Improved handling of reading state transitions when changing pages or settings.
* Corrected issues with page calculation and display when font size or other settings are modified.
* Enhanced error handling for file loading and processing. 