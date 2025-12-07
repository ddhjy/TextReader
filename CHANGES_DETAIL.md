# 多选批量删除功能 - 详细代码修改

## 文件 1: Book.swift
### 修改位置：`./TextReader/TextReader/Models/Book.swift`

#### 变化 1：协议声明
```swift
// 修改前
struct Book: Identifiable {

// 修改后
struct Book: Identifiable, Hashable, Equatable {
```

#### 变化 2：新增 Hashable 实现
```swift
// 新增代码
// 实现 Hashable
func hash(into hasher: inout Hasher) {
    hasher.combine(fileName)
}
```

#### 变化 3：新增 Equatable 实现
```swift
// 新增代码
// 实现 Equatable
static func == (lhs: Book, rhs: Book) -> Bool {
    lhs.fileName == rhs.fileName
}
```

**说明**：
- `Hashable` 和 `Equatable` 协议使 `Book` 能够放入 `Set` 集合
- 以 `fileName` 作为唯一标识符（已经是 `id` 的来源）
- 保证了选中状态的正确追踪和高效查询

---

## 文件 2: ContentViewModel.swift
### 修改位置：`./TextReader/TextReader/ViewModels/ContentViewModel.swift`

#### 新增属性（第 54 行）
```swift
// 新增：多选状态（保存选中的书籍）
@Published var selectedBooks: Set<Book> = []
```

#### 新增方法组（第 476-502 行）

##### 方法 1：toggleBookSelection
```swift
/// 切换书籍的选中状态
/// - Parameter book: 要切换的书籍
func toggleBookSelection(_ book: Book) {
    if selectedBooks.contains(book) {
        selectedBooks.remove(book)
    } else {
        selectedBooks.insert(book)
    }
}
```

##### 方法 2：clearSelectedBooks
```swift
/// 清除所有选中的书籍
func clearSelectedBooks() {
    selectedBooks.removeAll()
}
```

##### 方法 3：deleteSelectedBooks
```swift
/// 删除所有选中的书籍（过滤掉内置书籍）
func deleteSelectedBooks() {
    // 过滤掉内置书籍（不可删除）
    let nonBuiltInBooks = selectedBooks.filter { !$0.isBuiltIn }
    for book in nonBuiltInBooks {
        deleteBook(book) // 复用原有单条删除逻辑
    }
    clearSelectedBooks()
}
```

**说明**：
- `toggleBookSelection`：切换个别书籍的选中状态（内置书籍在 UI 层被禁用）
- `clearSelectedBooks`：清空所有选中状态，用于取消多选模式
- `deleteSelectedBooks`：执行批量删除，自动过滤掉内置书籍

---

## 文件 3: BookListView.swift
### 修改位置：`./TextReader/TextReader/Views/BookList/BookListView.swift`

#### 新增状态（第 10-12 行）
```swift
// 新增：多选模式状态
@State private var isMultiSelectMode = false
@State private var batchDeleteCount: Int = 0
@State private var showingBatchDeleteAlert = false
```

#### 修改 1：列表项结构（第 17-70 行）

##### 修改前
```swift
Button(action: {
    viewModel.loadBook(book)
    dismiss()
}) {
    HStack {
        VStack(alignment: .leading, spacing: 4) {
            Text(book.title)
                .foregroundColor(.primary)
                .font(.headline)
                .lineLimit(1)
            
            VStack(alignment: .leading, spacing: 2) {
                if let progressText = viewModel.getBookProgressDisplay(book: book) {
                    Text(progressText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                if let lastAccessedText = viewModel.getLastAccessedTimeDisplay(book: book) {
                    Text(lastAccessedText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        Spacer()
        if viewModel.currentBookId == book.id {
            Image(systemName: "checkmark")
                .foregroundColor(viewModel.currentAccentColor)
        }
    }
}
```

##### 修改后（添加多选框和条件逻辑）
```swift
HStack(alignment: .top, spacing: 8) {
    // 新增：多选模式下显示选择框
    if isMultiSelectMode {
        Button(action: {
            if !book.isBuiltIn {
                viewModel.toggleBookSelection(book)
            }
        }) {
            Image(systemName: viewModel.selectedBooks.contains(book) ? "checkmark.square.fill" : "square")
                .foregroundColor(book.isBuiltIn ? .gray : viewModel.currentAccentColor)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(book.isBuiltIn)
    }

    // 原有书籍内容按钮
    Button(action: {
        if isMultiSelectMode {
            if !book.isBuiltIn {
                viewModel.toggleBookSelection(book)
            }
        } else {
            viewModel.loadBook(book)
            dismiss()
        }
    }) {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .foregroundColor(.primary)
                    .font(.headline)
                    .lineLimit(1)
                
                VStack(alignment: .leading, spacing: 2) {
                    if let progressText = viewModel.getBookProgressDisplay(book: book) {
                        Text(progressText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    if let lastAccessedText = viewModel.getLastAccessedTimeDisplay(book: book) {
                        Text(lastAccessedText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
            if viewModel.currentBookId == book.id && !isMultiSelectMode {
                Image(systemName: "checkmark")
                    .foregroundColor(viewModel.currentAccentColor)
            }
        }
    }
}
```

#### 修改 2：滑动操作（第 76-90 行）

##### 修改前
```swift
.swipeActions(edge: .trailing, allowsFullSwipe: false) {
    Button(role: .destructive) {
        bookToDelete = book
        showingDeleteAlert = true
    } label: {
        Label("Delete", systemImage: "trash")
    }
    
    if !book.isBuiltIn {
        Button {
            viewModel.bookToEdit = book
            viewModel.showingBookEdit = true
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        .tint(viewModel.currentAccentColor)
    }
}
```

##### 修改后（多选模式下隐藏）
```swift
.swipeActions(edge: .trailing, allowsFullSwipe: false) {
    // 多选模式下隐藏滑动操作按钮
    if !isMultiSelectMode {
        Button(role: .destructive) {
            bookToDelete = book
            showingDeleteAlert = true
        } label: {
            Label("Delete", systemImage: "trash")
        }
        
        if !book.isBuiltIn {
            Button {
                viewModel.bookToEdit = book
                viewModel.showingBookEdit = true
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(viewModel.currentAccentColor)
        }
    }
}
```

#### 修改 3：导航栏（第 101-160 行）

##### 修改前
```swift
.toolbar {
    ToolbarItem(placement: .navigationBarLeading) { 
        Menu {
            Button {
                viewModel.showingDocumentPicker = true
            } label: {
                Label("从文件导入", systemImage: "doc")
            }

            Button {
                showingPasteImport = true
            } label: {
                Label("粘贴文本", systemImage: "doc.on.clipboard")
            }
            
            Button {
                viewModel.showingWiFiTransferView = true
            } label: {
                Label("WiFi 传输", systemImage: "wifi")
            }
        } label: {
            Image(systemName: "plus.circle")
                .foregroundColor(viewModel.currentAccentColor)
        }
    }
    
    ToolbarItem(placement: .navigationBarTrailing) {
        Button("Done") {
            dismiss()
        }
        .foregroundColor(viewModel.currentAccentColor)
    }
}
```

##### 修改后（多选/非多选模式切换）
```swift
.toolbar {
    // 左侧：条件显示加号菜单或取消按钮
    ToolbarItem(placement: .navigationBarLeading) { 
        if isMultiSelectMode {
            Button("取消") {
                isMultiSelectMode = false
                viewModel.clearSelectedBooks()
            }
            .foregroundColor(viewModel.currentAccentColor)
        } else {
            Menu {
                Button {
                    viewModel.showingDocumentPicker = true
                } label: {
                    Label("从文件导入", systemImage: "doc")
                }

                Button {
                    showingPasteImport = true
                } label: {
                    Label("粘贴文本", systemImage: "doc.on.clipboard")
                }
                
                Button {
                    viewModel.showingWiFiTransferView = true
                } label: {
                    Label("WiFi 传输", systemImage: "wifi")
                }
            } label: {
                Image(systemName: "plus.circle")
                    .foregroundColor(viewModel.currentAccentColor)
            }
        }
    }
    
    // 右侧：条件显示删除或Done按钮
    ToolbarItem(placement: .navigationBarTrailing) {
        if isMultiSelectMode {
            Button(role: .destructive) {
                batchDeleteCount = viewModel.selectedBooks.count
                showingBatchDeleteAlert = true
            } label: {
                Text("删除")
            }
            .foregroundColor(.red)
            .disabled(viewModel.selectedBooks.isEmpty)
        } else {
            Button("Done") {
                dismiss()
            }
            .foregroundColor(viewModel.currentAccentColor)
        }
    }
    
    // 新增右侧多选按钮
    if !isMultiSelectMode {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button(action: { isMultiSelectMode = true }) {
                Image(systemName: "checkmark.square")
                    .foregroundColor(viewModel.currentAccentColor)
            }
        }
    }
}
```

#### 修改 4：新增批量删除弹框（第 191-196 行）

```swift
.alert("批量删除确认", isPresented: $showingBatchDeleteAlert) {
    Button("取消", role: .cancel) {}
    Button("删除", role: .destructive) {
        viewModel.deleteSelectedBooks()
        isMultiSelectMode = false
    }
} message: {
    Text("将删除 \(batchDeleteCount) 本书籍，此操作无法撤销。")
}
```

---

## 功能交互流程

```
用户进入书籍列表
    ↓
[正常模式]
  - 点击「多选」按钮 → 进入多选模式
  - 点击书籍 → 加载书籍，返回阅读页面
  - 长按/滑动 → 显示编辑、删除单个书籍的选项
    ↓
[多选模式]
  - 每行前显示选择框（内置书籍置灰）
  - 点击选择框或书籍行 → 切换选中状态（内置书籍无反应）
  - 滑动操作 → 隐藏
  - 左侧「取消」按钮 → 退出多选模式，清空选择
  - 右侧「删除」按钮 → 确认删除选中书籍
    ↓
[删除确认弹框]
  - 显示将删除的书籍数量
  - 「删除」按钮 → 执行批量删除，自动过滤内置书籍，退出多选模式
  - 「取消」按钮 → 保持多选模式
```

---

## 代码行数统计

| 文件 | 新增行数 | 修改行数 | 总计 |
|------|---------|---------|------|
| Book.swift | 12 | 1 | 13 |
| ContentViewModel.swift | 28 | 0 | 28 |
| BookListView.swift | 73 | 47 | 120 |
| **总计** | **113** | **48** | **161** |

---

## 编译和测试状态

✅ **编译通过**：无错误、无警告
✅ **向后兼容**：所有现有功能保持不变
✅ **内置书籍保护**：实现完整的内置书籍保护机制
