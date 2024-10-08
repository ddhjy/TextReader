# TextReader

TextReader 是一个基于 SwiftUI 开发的文本阅读器应用，支持阅读和朗读文本文件。该应用提供了丰富的功能，包括分页显示、语音朗读、语音设置、全文搜索以及从 iCloud 导入书籍等。

## 功能特性

- **分页阅读**：自动将文本内容分割成页，方便用户逐页阅读。
- **语音朗读**：利用 `AVSpeechSynthesizer` 实现文本语音朗读，支持暂停和继续。
- **语音设置**：
  - **音色选择**：支持多种中文语音音色，用户可根据喜好选择。
  - **朗读速度**：提供多档朗读速度供用户调节。
- **搜索功能**：支持全文搜索，快速定位到指定的页面和内容。
- **书籍管理**：
  - **内置书籍**：预置了《思考快与慢》、《罗素作品集》、《哲学研究》等书籍。
  - **书籍列表**：方便地在不同书籍之间切换。
  - **导入书籍**：支持从 iCloud 或本地文件导入新的文本文件。
- **阅读进度保存**：自动保存每本书的阅读进度，方便下次继续阅读。
- **后台播放**：支持后台朗读，用户可在锁屏或使用其他应用时继续聆听。
- **远程控制**：集成了系统的播放控制中心，支持通过耳机或控制中心控制播放。

## 安装和运行

1. **环境要求**

   - **操作系统**：macOS 11.0 或更高版本
   - **Xcode 版本**：Xcode 12 或更高版本
   - **目标设备**：iOS 14 或更高版本的设备或模拟器

2. **获取项目**

   - 将项目文件下载或克隆到本地。

3. **打开项目**

   - 使用 Xcode 打开 `TextReader.xcodeproj` 文件。

4. **运行项目**

   - 在 Xcode 中选择目标设备或模拟器。
   - 点击运行按钮即可构建并启动应用。

## 使用指南

### 1. 选择书籍

- 点击导航栏左侧的 **书本图标** 📖，打开书籍列表。
- 从列表中选择一本书，应用会自动加载并显示内容。

### 2. 阅读和翻页

- 应用会自动将内容分页显示。
- 使用底部的 **左右箭头按钮** 可以前后翻页。
- 当前页码和总页数会显示在控制面板上方。

### 3. 语音朗读

- 点击底部中间的 **播放/暂停按钮** 开始或暂停朗读当前页面的内容。
- 朗读过程中可以切换页面，语音会自动更新。
- **音色和速度设置**：
  - 在控制面板中，选择 **音色** 选项来更改语音音色。
  - 选择 **速度** 选项来调整朗读速度。

### 4. 搜索内容

- 点击导航栏右侧的 **放大镜图标** 🔍，进入搜索界面。
- 输入要搜索的关键词，点击搜索按钮。
- 搜索结果会以列表形式显示，点击结果可跳转到对应页面。

### 5. 导入书籍

- 在书籍列表界面（点击 📖 图标），可以看到已有的书籍。
- 要导入新的文本文件，点击 **导入** 按钮（如果已实现该功能）。
- 通过文件选择器，从 iCloud 或本地文件中选择要导入的 `.txt` 文件。
- 导入成功后，新的书籍会出现在书籍列表中。

## 技术细节

- **SwiftUI**：全界面使用 SwiftUI 构建，支持响应式和声明式编程。
- **AVFoundation**：使用 `AVSpeechSynthesizer` 实现文本转语音功能。
- **MediaPlayer**：集成 `MPRemoteCommandCenter`，支持后台播放和远程控制。
- **文件处理**：支持从应用内和 iCloud 导入文本文件，使用安全的沙盒访问。
- **数据持久化**：利用 `UserDefaults` 保存用户设置和阅读进度。

## 文件结构

- **ContentView.swift**：主界面，包括内容显示和控制面板。
- **TextReaderApp.swift**：应用入口，设置了主视图。
- **其他组件**：
  - **ContentModel**：负责数据处理和业务逻辑，包括文本分页、语音朗读控制等。
  - **SearchView**、**BookListView**、**DocumentPicker** 等：辅助界面和功能组件。

## 注意事项

- **权限设置**：如果需要从 iCloud 导入文件，请确保在项目的 **Signing & Capabilities** 中启用了 **iCloud** 功能。
- **语音资源**：应用使用系统内置的语音音色，确保设备已下载所需的中文语音包。

## 贡献

如果您对该项目有任何建议或改进，欢迎提交 Pull Request 或 Issue。

## 许可证

该项目采用 MIT 许可证进行分发。详细信息请参阅 [LICENSE](LICENSE) 文件。