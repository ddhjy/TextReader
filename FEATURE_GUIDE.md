# 多选批量删除功能 - 用户指南

## 🎯 功能概述
允许用户在书籍列表中同时选择多本书籍，然后批量删除它们。提供清晰的 UI 反馈和内置书籍保护。

## 👤 用户使用指南

### 进入多选模式
1. 打开应用后，点击"Select Book"进入书籍列表
2. 在导航栏的右上角，点击新增的「多选」按钮（□ 图标）
3. 界面进入多选模式

### 多选模式的外观变化

#### 导航栏变化
| 位置 | 非多选模式 | 多选模式 |
|------|----------|--------|
| **左侧** | + 号菜单（导入书籍） | 取消 按钮 |
| **右侧 1** | Done 按钮 | 删除 按钮（红色） |
| **右侧 2** | 多选 按钮 | *隐藏* |

#### 列表变化
- **选择框**：每行书籍前出现选择框
  - 未选中：白色空心方框 ☐
  - 已选中：实心蓝色方框 ☑
  - 内置书籍：灰色禁用 ◻

- **滑动操作**：编辑、删除按钮被隐藏

- **当前书籍指示**：勾号被隐藏

### 选择书籍
#### 方式 1：点击选择框
- 直接点击行左侧的选择框切换选中状态
- 内置书籍的选择框置灰且无法点击

#### 方式 2：点击书籍行
- 点击书籍行的任意地方也能切换选中状态
- 内置书籍行点击无反应

### 删除选中的书籍

#### 步骤 1：选择书籍
- 选中一个或多个非内置书籍

#### 步骤 2：确认删除
1. 点击右上角红色「删除」按钮
2. 弹框显示"将删除 N 本书籍，此操作无法撤销"
3. 点击「删除」确认

#### 步骤 3：自动完成
- 书籍被删除
- 书籍列表自动更新
- 多选模式自动退出

### 退出多选模式

#### 方式 1：点击"取消"
- 点击左上角「取消」按钮
- 所有选中状态被清除
- 返回正常模式

#### 方式 2：删除后自动退出
- 批量删除完成后自动返回正常模式

### ⚠️ 内置书籍保护
- 内置书籍**无法被选中**
- 内置书籍**无法被删除**
- 即使选了内置书籍，删除时也会被自动过滤掉

## 🔧 开发者技术指南

### 核心实现原理

#### 1. Book 结构体扩展
```swift
struct Book: Identifiable, Hashable, Equatable
```
- **Hashable**：支持放入 Set 集合
- **Equatable**：支持相等性比较
- 用 `fileName` 作为唯一标识

#### 2. 状态管理
```swift
@Published var selectedBooks: Set<Book> = []
```
- 使用 Set 而非数组，O(1) 查询性能
- 自动去重，防止重复选择
- @Published 自动触发 UI 更新

#### 3. 核心方法

##### toggleBookSelection
```swift
func toggleBookSelection(_ book: Book) {
    if selectedBooks.contains(book) {
        selectedBooks.remove(book)
    } else {
        selectedBooks.insert(book)
    }
}
```

##### clearSelectedBooks
```swift
func clearSelectedBooks() {
    selectedBooks.removeAll()
}
```

##### deleteSelectedBooks
```swift
func deleteSelectedBooks() {
    let nonBuiltInBooks = selectedBooks.filter { !$0.isBuiltIn }
    for book in nonBuiltInBooks {
        deleteBook(book)
    }
    clearSelectedBooks()
}
```

### 关键 UI 实现

#### 多选模式状态
```swift
@State private var isMultiSelectMode = false
```

#### 条件渲染选择框
```swift
if isMultiSelectMode {
    Button {
        if !book.isBuiltIn {
            viewModel.toggleBookSelection(book)
        }
    } {
        Image(systemName: viewModel.selectedBooks.contains(book) 
            ? "checkmark.square.fill" 
            : "square")
    }
    .disabled(book.isBuiltIn)
}
```

#### 导航栏动态切换
```swift
if isMultiSelectMode {
    // 显示取消和删除按钮
} else {
    // 显示加号菜单和 Done 按钮
}
```

### 扩展建议

#### 1. 全选/反选
```swift
// 在导航栏添加"全选"按钮
Button(action: {
    for book in viewModel.books where !book.isBuiltIn {
        viewModel.selectedBooks.insert(book)
    }
}) {
    Text("全选")
}
```

#### 2. 删除结果反馈
```swift
@State private var deleteResultMessage: String?

// 在删除后显示 toast
viewModel.deleteSelectedBooks()
deleteResultMessage = "已删除 \(count) 本书籍"
```

#### 3. 选中行的视觉高亮
```swift
.background(Color.blue.opacity(
    viewModel.selectedBooks.contains(book) ? 0.1 : 0
))
```

#### 4. 编辑前的批量操作
```swift
// 支持在多选模式下进行其他批量操作
// 如：标记已读、修改标签等
```

## 📊 状态流转图

```
初始状态: 正常模式
    ↓ 点击多选按钮
多选模式 (selectedBooks = {})
    ↓ 点击书籍
多选模式 (selectedBooks = {book1})
    ↓ 多次点击选择
多选模式 (selectedBooks = {book1, book3, book5})
    ↓ 点击删除
确认删除弹框
    ├─ 确认 → 执行删除 → 自动返回正常模式
    └─ 取消 → 保持多选模式
    
多选模式
    ↓ 点击取消
正常模式 (selectedBooks = {})
```

## 🧪 测试检查清单

- [ ] 进入多选模式显示选择框
- [ ] 非多选模式点击书籍加载书籍
- [ ] 多选模式点击书籍切换选中状态
- [ ] 内置书籍的选择框置灰不可点击
- [ ] 滑动操作在多选模式下隐藏
- [ ] 导航栏按钮正确切换
- [ ] 删除弹框显示正确的数量
- [ ] 删除后书籍列表更新
- [ ] 自动过滤内置书籍，只删除非内置书籍
- [ ] 删除后自动退出多选模式
- [ ] 点击取消清空选择并退出

## 📝 版本信息

- **实施日期**：2025-10-17
- **编译状态**：✅ 通过
- **兼容性**：向后兼容 iOS 14+
- **文件修改**：3 个文件，总计 161 行代码修改
