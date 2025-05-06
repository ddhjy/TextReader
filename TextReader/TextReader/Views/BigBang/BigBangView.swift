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
    
    @State private var startID: UUID?   // 记录滑动起点
    @State private var lastSelectedID: UUID? // 记录上一次选中的ID，避免重复震动
    
    private let tokenHeight: CGFloat = 32
    private let tokenSpacing: CGFloat = 8  // 字块之间的统一间距
    
    var body: some View {
        NavigationStack {
            ScrollView {
                FlowLayout(vm.tokens, id: \.id, spacing: tokenSpacing) { token in
                    Text(token.value)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.vertical, 4)
                        .frame(height: tokenHeight)
                        .background(vm.selectedTokenIDs.contains(token.id) ?
                                    Color.accentColor.opacity(0.8) :
                                    Color(UIColor.secondarySystemBackground))
                        .cornerRadius(4)
                        .foregroundColor(vm.selectedTokenIDs.contains(token.id) ? .white : .primary)
                        .gesture(DragGesture(minimumDistance: 0)
                                 .onChanged{ _ in
                                     if startID == nil { 
                                         startID = token.id 
                                         HapticFeedback.shared.impactOccurred() // 滑动开始时震动
                                     }
                                     
                                     // 如果之前没有选中这个token，则触发震动
                                     let initialSelectionState = vm.selectedTokenIDs.contains(token.id)
                                     
                                     // 执行选择
                                     vm.slideSelect(from: startID!, to: token.id)
                                     
                                     // 如果是新加入选中的token并且不是刚刚震动过的，触发震动
                                     if !initialSelectionState && vm.selectedTokenIDs.contains(token.id) && lastSelectedID != token.id {
                                         lastSelectedID = token.id
                                         HapticFeedback.shared.selectionChanged()
                                     }
                                 }
                                 .onEnded{ _ in 
                                     startID = nil
                                     lastSelectedID = nil  // 重置
                                 })
                        .onTapGesture {
                            // 单点选择时也触发震动
                            vm.toggleToken(token.id)
                            HapticFeedback.shared.selectionChanged()
                        }
                }
                .padding()
            }
            .navigationTitle("大爆炸")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button("清空") {
                            if !vm.selectedTokenIDs.isEmpty {
                                vm.clearSelectedTokens()
                                HapticFeedback.shared.impactOccurred() // 清空选择时震动
                            }
                        }
                        .disabled(vm.selectedTokenIDs.isEmpty)
                        
                        Button("复制") { 
                            HapticFeedback.shared.impactOccurred() // 复制时震动
                            vm.copySelected()
                            dismiss() 
                        }
                        .disabled(vm.selectedTokenIDs.isEmpty)
                    }
                }
            }
        }
        .interactiveDismissDisabled()
    }
} 