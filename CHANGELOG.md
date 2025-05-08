## [Unreleased]

### Fixed
* **Removed Loading Title Flicker**: Removed the navigation title ("加载中...") during initial content loading to prevent UI flickering on startup. (Affects `./TextReader/TextReader/Views/ContentView.swift`)

### Refactor
* **Optimized Code Comments**: Removed redundant and outdated comments (including one in `SpeechManager`), clarified important logic with improved documentation comments, and converted remaining Chinese comments to English across multiple files (e.g., `AudioSessionManager`, `SpeechManager`, `ContentViewModel`, `WiFiTransferView`) for better maintainability and internationalization.
* **Decomposed `ContentModel`**: Extracted business logic from `ContentView` into a dedicated `ContentViewModel` to improve separation of concerns and testability.
* **Introduced ViewModel**: Implemented `ContentViewModel` as an `@StateObject` to manage the state and logic for `ContentView`, including text loading, page navigation, settings, search, and Wi-Fi transfer.
* **Moved WiFi UI**: Migrated WiFi transfer UI elements (status display, copy URL button) and controls (start/stop button) from `ContentView` overlay and toolbar to the new `WiFiTransferView`.

### Added
* **Prompt Templates after Big Bang**  
  * 新增 `PromptTemplate` 模型、`TemplateManager` 持久化。  
  * 在 BigBang 选词后，可选择预设/自定义模板，自动替换 `{selection}/{page}/{book}` 并复制。  
  * 提供模板管理界面（增删改）。
* **SearchView 默认分页摘要**  
  * 当搜索框为空时展示分页摘要（≤100 等分），包含页码与预览。
  * 点击摘要可快速跳转至对应页面。
* **Haptic Feedback on Page Slider**: Added `UISelectionFeedbackGenerator` in `PageControl` so that a subtle vibration is fired whenever the user changes pages via the progress slider.
* **Interactive Page Slider**: Default progress bar now transforms into a draggable slider on tap/drag, allowing quick page jumps. The slider auto-hides after 1.5 s of inactivity.
* **Quick Page Jump**: Progress bar upgraded to an interactive slider that supports dragging to jump to any page instantly.
* **Paste Text Import**: Users can now create a new book by directly pasting plain text.  
  * 支持在书籍列表通过「粘贴文本」输入内容并保存为 TXT。  
  * 标题可手动输入或自动取文本前 10 个字符。
* **Share to Import**: Added the ability to import text content shared from other applications (e.g., Notes, Safari) via the iOS Share Sheet. The app now handles URLs pointing to shared text data (`public.plain-text`, `public.text`).
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
* **UI/UX Enhancement**:
  * Paragraph/letter spacing, larger base font.
  * Linear progress bar for page progress.
  * Prominent "Play / Pause" circular button.
  * Segmented speed selector.
  * Manual Dark-Mode toggle with persistence.
* **Big Bang 拆词与滑动选词**
  * 长按阅读页触发「大爆炸」；基于 `NLTokenizer` 智能分词。
  * `BigBangView` 以砖块形式展示 Token，支持拖拽连续高亮并一键复制。

### Changed
* `ContentDisplay` 支持长按手势，调用 ViewModel 的 `triggerBigBang()`。

### Fixed
* **Share Sheet Text Import**  
  * 将 `CFBundleDocumentTypes` 正确添加到主 `Info.plist`，声明 `public.plain-text` / `public.text`，使应用出现在系统分享面板。  
  * 在 `TextReaderApp` 级别集中处理 `.onOpenURL`，保证冷启动时也能接收并导入分享的 TXT/纯文本。
  * 新增 `TextReaderExtension` 分享扩展，可从任意应用中共享文本到 TextReader。
  * 实现了自定义 URL Scheme（`textreader://`）处理，在 `ContentViewModel` 中支持从其他应用接收文本内容。
* **实时更新阅读时间和排序**:
    * 现在翻页 (`nextPage`, `previousPage`) 时也会更新书籍的 `lastAccessed` 时间戳，而不仅仅是在选择书籍时。 (涉及 `ContentViewModel`)
    * 在 `lastAccessed` 时间戳更新后（包括选择书籍和翻页操作），立即对内部书籍列表进行重新排序，确保 `BookListView` 打开时能展示基于最近访问时间的正确顺序，无需重启应用。 (涉及 `ContentViewModel`)
* **修复 iCloud 文件导入失败**: 解决了从"文件"应用或 iCloud Drive 导入文件时因权限问题导致的失败。通过确保在实际读取文件时正确处理安全作用域 URL (`startAccessingSecurityScopedResource`/`stopAccessingSecurityScopedResource`)，并在文件导入流程的关键步骤（选择、权限获取、读取、写入）中添加了详细的调试日志，以帮助诊断未来的相关问题。同时增加了对 GBK/GB18030 编码文件的读取支持。 (涉及 `DocumentPicker`, `ContentViewModel`, `LibraryManager`)
* **朗读翻页卡顿**: 优化了朗读状态下手动或自动翻页的逻辑。移除了翻页操作中不必要的延迟 (`asyncAfter`) 和冗余的朗读停止 (`stopReading`) 调用，显著减少了翻页时的处理时间，改善了卡顿感。 (主要涉及 `ContentViewModel` 的 `nextPage`, `previousPage`, `
* **Removed Play/Pause Button Animation**: Disabled the animation on the play/pause button in `PageControl.swift` for a more direct icon transition when toggling playback state.

### Improved
* **Page Slider UX**
  * Long-pressing the progress bar now immediately reveals the slider **and** allows continuous dragging without lifting the finger, matching natural expectations.

### UI
* `BigBangView` 右上角增加"模板"菜单与管理入口。
* `ContentDisplay` 支持长按手势，调用 ViewModel 的 `triggerBigBang()`。