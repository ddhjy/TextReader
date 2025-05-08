import SwiftUI
import UIKit // 用于震动反馈

// 自定义FlowLayout视图
struct FlowLayout<Data, ID, Content>: View where Data: RandomAccessCollection, ID: Hashable, Content: View {
    private let data: Data
    private let id: KeyPath<Data.Element, ID>
    private let spacing: CGFloat
    private let content: (Data.Element) -> Content
    
    @State private var availableWidth: CGFloat = 0
    
    init(_ data: Data, id: KeyPath<Data.Element, ID>, spacing: CGFloat, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.id = id
        self.spacing = spacing
        self.content = content
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(height: 1)
                .readSize { size in
                    availableWidth = size.width
                }
            
            FlowLayoutHelper(
                availableWidth: availableWidth,
                data: data,
                id: id,
                spacing: spacing,
                content: content
            )
        }
    }
}

// 帮助视图，负责实际布局
private struct FlowLayoutHelper<Data, ID, Content>: View where Data: RandomAccessCollection, ID: Hashable, Content: View {
    let availableWidth: CGFloat
    let data: Data
    let id: KeyPath<Data.Element, ID>
    let spacing: CGFloat
    let content: (Data.Element) -> Content
    
    var body: some View {
        if availableWidth > 0 {
            _FlowLayoutHelper(
                availableWidth: availableWidth,
                data: data,
                id: id,
                spacing: spacing,
                content: content
            )
        }
    }
}

// 用于表示一行中的元素
private struct RowElement<Element>: Identifiable, Hashable {
    let element: Element
    let id = UUID()
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// 用于表示一行
private struct Row<Element>: Identifiable, Hashable {
    let elements: [RowElement<Element>]
    let id = UUID()
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// 真正的布局实现
private struct _FlowLayoutHelper<Data, ID, Content>: View where Data: RandomAccessCollection, ID: Hashable, Content: View {
    let availableWidth: CGFloat
    let data: Data
    let id: KeyPath<Data.Element, ID>
    let spacing: CGFloat
    let content: (Data.Element) -> Content
    
    @State private var elementsSize: [ID: CGSize] = [:]
    
    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(computeRows()) { row in
                HStack(spacing: spacing) {
                    ForEach(row.elements) { rowElement in
                        content(rowElement.element)
                            .fixedSize()
                            .measureSize { size in
                                let elementID = rowElement.element[keyPath: id]
                                elementsSize[elementID] = size
                            }
                    }
                }
            }
        }
    }
    
    func computeRows() -> [Row<Data.Element>] {
        var rows: [Row<Data.Element>] = []
        var currentRowElements: [RowElement<Data.Element>] = []
        var remainingWidth = availableWidth
        
        for element in data {
            let elementID = element[keyPath: id]
            let elementSize = elementsSize[elementID, default: CGSize(width: availableWidth / 4, height: 1)]
            
            if remainingWidth >= elementSize.width {
                currentRowElements.append(RowElement(element: element))
                remainingWidth -= elementSize.width + spacing
            } else {
                if !currentRowElements.isEmpty {
                    rows.append(Row(elements: currentRowElements))
                    currentRowElements = [RowElement(element: element)]
                    remainingWidth = availableWidth - elementSize.width - spacing
                } else {
                    // 如果当前行为空，强制添加该元素，即使宽度超出
                    currentRowElements.append(RowElement(element: element))
                    remainingWidth = availableWidth - elementSize.width - spacing
                }
            }
        }
        
        // 添加最后一行
        if !currentRowElements.isEmpty {
            rows.append(Row(elements: currentRowElements))
        }
        
        return rows
    }
}

// 用于测量视图大小的修饰器
extension View {
    func measureSize(perform action: @escaping (CGSize) -> Void) -> some View {
        self.background(
            GeometryReader { geometry in
                Color.clear.preference(key: SizePreferenceKey.self, value: geometry.size)
            }
        )
        .onPreferenceChange(SizePreferenceKey.self, perform: action)
    }
    
    func readSize(onChange: @escaping (CGSize) -> Void) -> some View {
        background(
            GeometryReader { geometryProxy in
                Color.clear
                    .preference(key: SizePreferenceKey.self, value: geometryProxy.size)
            }
        )
        .onPreferenceChange(SizePreferenceKey.self, perform: onChange)
    }
}

// 用于传递尺寸数据的PreferenceKey
private struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

// 震动反馈辅助类
class HapticFeedback {
    static let shared = HapticFeedback()
    
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)
    
    private init() {
        // 预热反馈生成器，减少第一次使用时的延迟
        selectionFeedback.prepare()
        impactFeedback.prepare()
    }
    
    func selectionChanged() {
        selectionFeedback.selectionChanged()
    }
    
    func impactOccurred() {
        impactFeedback.impactOccurred()
    }
}

struct BigBangView: View {
    @ObservedObject var vm: ContentViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    private let tokenHeight: CGFloat = 28 // 标准高度
    private let tokenSpacing: CGFloat = 6  // 标准间距
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 主内容区
                ScrollView {
                    FlowLayout(vm.tokens, id: \.id, spacing: tokenSpacing) { token in
                        Text(token.value)
                            .lineLimit(1)
                            .font(.system(size: 15, weight: .regular))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .frame(height: tokenHeight)
                            .background(
                                vm.selectedTokenIDs.contains(token.id) ?
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.accentColor) :
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color(.systemGray6))
                            )
                            .foregroundColor(vm.selectedTokenIDs.contains(token.id) ? .white : .primary)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                vm.processTokenTap(tappedTokenID: token.id)
                                HapticFeedback.shared.selectionChanged()
                            }
                    }
                    .padding()
                    .padding(.bottom, 80) // 为底部工具栏留出空间
                }
                
                // 底部工具栏（浮动样式）
                VStack {
                    Spacer()
                    
                    // 使用Material背景的工具栏
                    ToolbarView(vm: vm, dismiss: dismiss)
                        .frame(height: 60)
                        .background(.clear)
                        .cornerRadius(30)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
            }
            .navigationTitle("词组选择")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !vm.selectedTokenIDs.isEmpty {
                        Button("全部清除") {
                            vm.clearSelectedTokens()
                            HapticFeedback.shared.impactOccurred()
                        }
                    }
                }
            }
            .sheet(isPresented: $vm.showingTemplatePicker) {
                PromptTemplatePicker(viewModel: vm)
            }
            .alert(item: $vm.generatedPrompt) { alertMsg in
                Alert(title: Text(alertMsg.message))
            }
        }
        .onAppear {
            HapticFeedback.shared.impactOccurred()
        }
        .interactiveDismissDisabled()
    }
}

// 底部工具栏组件
struct ToolbarView: View {
    @ObservedObject var vm: ContentViewModel
    let dismiss: DismissAction
    
    var body: some View {
        HStack(spacing: 24) {
            Spacer()
            
            // 复制按钮
            ToolbarButton(
                icon: "doc.on.doc.fill",
                title: "复制",
                isDisabled: vm.selectedTokenIDs.isEmpty
            ) {
                HapticFeedback.shared.impactOccurred()
                vm.copySelected()
                dismiss()
            }
            
            // 转发按钮
            ToolbarButton(
                icon: "arrowshape.turn.up.right.fill",
                title: "分享",
                isDisabled: vm.selectedTokenIDs.isEmpty
            ) {
                // 分享功能
            }
            
            // 模板按钮
            Menu {
                ForEach(vm.templates) { tpl in
                    Button(tpl.name) {
                        vm.buildPrompt(using: tpl)
                        HapticFeedback.shared.impactOccurred()
                        dismiss()
                    }
                }
                Divider()
                Button("管理模板") {
                    vm.showingTemplatePicker = true
                }
            } label: {
                ToolbarButtonView(
                    icon: "text.badge.star",
                    title: "模板",
                    isDisabled: vm.selectedTokenIDs.isEmpty
                )
            }
            .disabled(vm.selectedTokenIDs.isEmpty)
            
            // 收藏按钮
            ToolbarButton(
                icon: "bookmark.fill",
                title: "收藏",
                isDisabled: vm.selectedTokenIDs.isEmpty
            ) {
                // 收藏功能
            }
            
            Spacer()
        }
    }
}

// 底部工具栏按钮
struct ToolbarButton: View {
    let icon: String
    let title: String
    let isDisabled: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ToolbarButtonView(icon: icon, title: title, isDisabled: isDisabled)
        }
        .disabled(isDisabled)
    }
}

// 底部工具栏按钮视图
struct ToolbarButtonView: View {
    let icon: String
    let title: String
    let isDisabled: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .symbolRenderingMode(.hierarchical)
                .contentShape(Rectangle())
            
            Text(title)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(isDisabled ? .secondary.opacity(0.5) : .primary)
    }
} 
