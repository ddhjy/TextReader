## [Unreleased]

### Refactor
* **Decomposed `ContentModel`**: Extracted business logic from `ContentView` into a dedicated `ContentViewModel` to improve separation of concerns and testability.
* **Introduced ViewModel**: Implemented `ContentViewModel` as an `@StateObject` to manage the state and logic for `ContentView`, including text loading, page navigation, settings, search, and Wi-Fi transfer.
* **Moved WiFi UI**: Migrated WiFi transfer UI elements (status display, copy URL button) and controls (start/stop button) from `ContentView` overlay and toolbar to the new `WiFiTransferView`.

### Added
* **Book List Sorting**: Books in the list are now sorted by the last accessed time, with the most recently opened book appearing first. Unopened books appear at the end.
* **Track Last Accessed Time**: The application now records when each book was last opened.
* **Last Access Display**: Shows the last time a book was accessed in a user-friendly format (e.g., "刚刚阅读", "5分钟前阅读", "昨天阅读").
* **File Import Button**: Added an 'Import' button to the `BookListView` to allow users to import `.txt` files using the system's document picker (`DocumentPicker` view).
* **Copy WiFi URL**: Added a button to the Wi-Fi transfer overlay to allow users to copy the server URL directly to the clipboard.
* **WiFi Transfer Page**: Created a dedicated page (`WiFiTransferView`) for managing WiFi file transfers, accessible via a toolbar button. Allows users to start/stop the transfer service and view/copy the access URL.
* **File Import**: Users can now import `.txt` files via the Files app or AirDrop.
* **WiFi Transfer**: Added functionality to transfer `.txt` files over WiFi directly to the app.
* **Search**: Implemented full-text search within the current book.
* **Settings**: Added options to adjust reading speed and select different voices.
* **Built-in Book**: Included "三体" as a default book.
* **Basic UI**: Created the main reading view, book list, and settings panel.
* **Persistence**: Book progress and settings are now saved across app launches.
* **Now Playing Info**: Displays current book title, page, and playback controls on the lock screen and control center.
* **Remote Controls**: Added support for controlling playback (play/pause, next/previous page) via remote controls (e.g., headphones, Control Center).

### Fixed
* Improved handling of reading state transitions when changing pages or settings.
* Corrected issues with page calculation and display when font size or other settings are modified.
* Enhanced error handling for file loading and processing.
* **Reading Progress Loss**: Fixed an issue where reading progress was lost after restarting the app. This was caused by unstable book identifiers (UUIDs generated on each launch). The fix implements stable identifiers based on filenames, ensuring progress is correctly associated with each book and persists across sessions.

### Changed
* Refactored core components like `LibraryManager`, `SpeechManager`, and `ContentViewModel` for better separation of concerns.
* **Book List Sorting Mechanism**: Implemented sorting logic within `ContentViewModel` based on the new `lastAccessed` timestamp managed by `LibraryManager`.

## [0.1.0] - 2024-07-20

### Added
* Initial project setup.
* Basic text display functionality.
* Core data structures for Book and Library. 