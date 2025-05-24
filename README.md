# TextReader for iOS

TextReader is a SwiftUI-based iOS application designed for an enhanced text reading and narration experience. It offers a comprehensive suite of features for importing, managing, reading, and listening to text-based content, with a focus on usability and customization.

## Features

### Core Reading & Narration
* **Paginated Reading:** Text content is automatically divided into easily navigable pages.
* **Text-to-Speech (TTS):** Utilizes `AVSpeechSynthesizer` for audio narration of book content, with play/pause capabilities.
* **Customizable Narration:**
    * **Voice Selection:** Choose from various available system voices (primarily focused on Chinese voices).
    * **Speed Control:** Adjust narration speed to your preference (options include 1.0x, 1.5x, 1.75x, 2.0x, 3.0x).
* **Background Playback:** Continue listening to narration even when the app is in the background or the device is locked.
* **Remote Controls:** Manage playback (play/pause, next/previous page) via headphones or the Control Center.
* **Now Playing Integration:** Displays current book title, page, and playback controls on the lock screen and Control Center.
* **Dark Mode:** Switch between light and dark themes for comfortable reading, with persistence.

### Book Management & Import
* **Multiple Import Methods:**
    * **File Import:** Import `.txt` files directly using the system document picker (from local storage or iCloud Drive). Supports UTF-8 and GBK/GB18030 encodings.
    * **Paste Text:** Create new books by pasting text directly into the app. Titles can be manually set or automatically generated from the first 10 characters.
    * **Share Sheet Import:** Import text content shared from other applications (e.g., Notes, Safari) via the iOS Share Sheet (handles `public.plain-text`, `public.text`).
    * **Wi-Fi Transfer:** Transfer `.txt` files to the app from a computer on the same Wi-Fi network via a web browser interface.
* **Book Library:**
    * View a list of all imported and built-in books.
    * Sorts books by the last accessed time, showing the most recently opened book first.
    * Displays last accessed time in a user-friendly format (e.g., "Read just now", "Read 5 minutes ago").
* **Progress Persistence:** Automatically saves reading progress (current page) and total pages for each book.
* **Built-in Book:** Includes a "User Guide" (使用说明.txt) as a default book.

### Search & Navigation
* **Full-Text Search:** Search within the currently open book.
    * **Live Search:** Results update palavras-chave.
    * **Keyword Highlighting:** Matched keywords are highlighted (yellow background, bold) in search results for better visibility. Search box empty means no highlighting in summaries.
    * **Contextual Preview:** Search results show a preview snippet with context around the matched keyword.
    * **No Results Found:** Clear "No relevant content found" message when search yields no results.
* **Page Summaries:** When the search bar is empty, displays summaries for quick navigation (up to 100 equally spaced page snippets).
* **Interactive Page Slider:**
    * Tap or drag the progress bar to reveal an interactive slider for quick page jumps.
    * The slider auto-hides after 1.5 seconds of inactivity.
    * Long-pressing the progress bar also activates the slider for continuous dragging.
* **Haptic Feedback:** Subtle vibrations on page changes via the slider and for other interactions.

### Advanced Text Interaction
* **"Big Bang" Word Segmentation:**
    * Long-press on the reading view to trigger "Big Bang" word segmentation based on `NLTokenizer`.
    * `BigBangView` displays tokens as selectable blocks.
    * Supports drag-to-select continuous tokens for copying.
* **Prompt Templates:**
    * After selecting text in "Big Bang" view, choose from preset or custom templates.
    * Placeholders `{selection}`, `{page}`, and `{book}` are automatically replaced.
    * Generated prompt is copied to the clipboard and can optionally open a Perplexity AI search.
    * Manage templates (add, delete, edit).

### UI/UX Enhancements
* Optimized paragraph/letter spacing and a larger base font for readability.
* Linear progress bar for visual page progress.
* Prominent circular Play/Pause button.
* Segmented speed selector for quick adjustments.
* Removed loading title flicker on startup for a smoother experience.

## Requirements

* **iOS:** 14.0 or later
* **Xcode:** 12.0 or later (for development)
* **macOS:** 11.0 or later (for development with Xcode)

## Installation

1.  **Clone or Download:** Get the project files onto your local machine.
    ```bash
    git clone [https://github.com/your-repository-url/TextReader.git](https://github.com/your-repository-url/TextReader.git)
    ```
2.  **Open Project:** Open `TextReader.xcodeproj` in Xcode.
3.  **Select Target:** Choose an iOS device or simulator.
4.  **Run:** Build and run the application.

## Usage Overview

* **Book List:** Tap the book icon in the navigation bar to open the book list. Select a book to start reading.
* **Importing:** Use the "+" icon in the book list to import books via Files, Paste Text, or Wi-Fi Transfer.
* **Reading:**
    * Swipe left/right or use the arrow buttons in the control panel to navigate pages.
    * Use the progress slider for quick page jumps.
* **Narration:**
    * Tap the Play/Pause button to start or stop narration.
    * Adjust voice and speed from the control panel.
* **Search:** Tap the magnifying glass icon to search within the current book.
* **Big Bang & Prompts:** Long-press text in the reader view to segment words. Select words and use the "Templates" menu.
* **Dark Mode:** Toggle dark mode from the control panel.

## Key Technologies

* **SwiftUI:** For the entire user interface and application structure.
* **AVFoundation:** `AVSpeechSynthesizer` for text-to-speech, `AVAudioSession` for audio management.
* **MediaPlayer:** `MPRemoteCommandCenter` and `MPNowPlayingInfoCenter` for background audio control and lock screen integration.
* **NaturalLanguage Framework:** `NLTokenizer` for "Big Bang" word segmentation.
* **Network Framework:** For the Wi-Fi file transfer service.
* **Combine Framework:** For managing asynchronous events and state changes.
* **Core iOS Frameworks:** For file management, persistence (`UserDefaults`, JSON for library metadata), and UI components.

## Architecture & Refactoring Highlights

The application has undergone significant refactoring to improve code structure, maintainability, and adherence to software design principles:

* **MVVM Design:** `ContentViewModel` acts as the central orchestrator for views and business logic.
* **Decomposition:** The original monolithic `ContentModel` has been broken down into dedicated managers and services:
    * **Managers:** `LibraryManager`, `SpeechManager`, `SettingsManager`, `AudioSessionManager`, `TemplateManager`.
    * **Services:** `SearchService`, `TextPaginator`, `WiFiTransferService`.
* **Single Responsibility Principle:** Each manager and service now has a clearly defined responsibility.
* **Improved Persistence:** `LibraryManager` handles library metadata and progress using JSON, while `SettingsManager` (using `UserDefaults`) manages user preferences.
* **Organized Code Structure:** Project files are organized into logical directories (Models, ViewModels, Views, Services, Managers, etc.).

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

Copyright (c) 2024 KAI