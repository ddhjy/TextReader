# Changelog

## [Unreleased]

### Added

* **Big Bang 拆词与滑动选词**
  * 长按阅读页触发「大爆炸」；基于 `NLTokenizer` 智能分词。
  * `BigBangView` 以砖块形式展示 Token，支持拖拽连续高亮并一键复制。
* **WiFi Import Entry in Book List**: Added "WiFi 传输" option to the import menu in `BookListView`, allowing users to start WiFi transfer alongside file and paste import methods.
* **Paste Text Import**: Users can now create a new book by directly pasting plain text.  
  * 支持在书籍列表通过「粘贴文本」输入内容并保存为 TXT。  
  * 标题可手动输入或自动取文本前 10 个字符。
* **File Import Button**: Added an 'Import' button to the `BookListView` to allow users to import `.txt` files using the system's document picker (`DocumentPicker` view).

### Changed

* `ContentDisplay` 支持长按手势，调用 ViewModel 的 `triggerBigBang()`。
* **Removed WiFi Toolbar Button**: Deleted the WiFi transfer button and related sheet from `ContentView`; WiFi transfer can now be initiated only from the book list.

### Refactor

* **Decomposed `ContentModel`**: Split the responsibilities of the monolithic `ContentModel` into dedicated services and managers (`LibraryManager`, `TextPaginator`, `SpeechManager`, `SearchService`, `WiFiTransferService`, `AudioSessionManager`, `SettingsManager`) to adhere to the Single Responsibility Principle.
* **Introduced ViewModel**: Added `ContentViewModel` to mediate between Views and Services/Managers, improving separation of concerns and testability.
* **Organized Code Structure**: Reorganized project files into a more structured directory layout (`Models`, `ViewModels`, `Views`, `Services`, `Managers`, etc.).
* **Separated View Components**: Moved individual SwiftUI views (`ContentDisplay`, `ControlPanel`, `BookListView`, `SearchView`, `SearchBar`, etc.) from `ContentView.swift` into their own respective files under the `./Views/` directory.
* **Encapsulated Business Logic**: Encapsulated text pagination, speech synthesis, search functionality, and WiFi transfer logic within their respective service/manager classes.
* **Improved Persistence**: Refactored data persistence to use JSON for library metadata and progress (handled by `LibraryManager`), while `UserDefaults` (via `SettingsManager`) is now used only for user preferences like voice, speed, and last opened book.
* **Managed Audio Session & Remote Controls**: Centralized `AVAudioSession` and `MPRemoteCommandCenter` configuration and updates within `AudioSessionManager`.
* Removed unused `CocoaAsyncSocket` dependency, relying solely on `Network.framework` for WiFi transfer.

### Fixed

* Improved handling of reading state transitions when changing pages or settings.
* Enhanced robustness of text pagination for edge cases (e.g., very long sentences, text without standard sentence structure).
* Improved background audio task management in `SpeechManager`.
* Correctly saves and restores total page count for books in `LibraryManager`. 