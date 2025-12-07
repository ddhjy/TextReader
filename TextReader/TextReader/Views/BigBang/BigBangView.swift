import SwiftUI
import UIKit
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
                    currentRowElements.append(RowElement(element: element))
                    remainingWidth = availableWidth - elementSize.width - spacing
                }
            }
        }
        
        if !currentRowElements.isEmpty {
            rows.append(Row(elements: currentRowElements))
        }
        
        return rows
    }
}

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

private struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

class HapticFeedback {
    static let shared = HapticFeedback()
    
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)
    
    private init() {
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
    
    private let tokenHeight: CGFloat = 32
    private let tokenSpacing: CGFloat = 8
    
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
                                    vm.currentAccentColor.opacity(0.8) :
                                    Color(UIColor.secondarySystemBackground))
                        .cornerRadius(4)
                        .foregroundColor(vm.selectedTokenIDs.contains(token.id) ? .white : .primary)
                        .gesture(DragGesture(minimumDistance: 0)
                                 .onEnded{ _ in 
                                     vm.processTokenTap(tappedTokenID: token.id)
                                     HapticFeedback.shared.selectionChanged()
                                 })
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                        .foregroundColor(vm.currentAccentColor)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button("清空") {
                            if !vm.selectedTokenIDs.isEmpty {
                                vm.clearSelectedTokens()
                                HapticFeedback.shared.impactOccurred()
                            }
                        }
                        .foregroundColor(vm.selectedTokenIDs.isEmpty ? .gray : vm.currentAccentColor)
                        .disabled(vm.selectedTokenIDs.isEmpty)
                        
                        Button("复制") { 
                            HapticFeedback.shared.impactOccurred()
                            vm.copySelected()
                            dismiss() 
                        }
                        .foregroundColor(vm.selectedTokenIDs.isEmpty ? .gray : vm.currentAccentColor)
                        .disabled(vm.selectedTokenIDs.isEmpty)
                        
                        Menu("模板") {
                            ForEach(vm.templates) { tpl in
                                Menu(tpl.name) {
                                    Button {
                                        vm.buildPrompt(using: tpl, destination: .perplexity)
                                        HapticFeedback.shared.impactOccurred()
                                        dismiss()
                                    } label: {
                                        Label("打开 Perplexity", systemImage: "safari")
                                    }
                                    Button {
                                        vm.buildPrompt(using: tpl, destination: .raycast)
                                        HapticFeedback.shared.impactOccurred()
                                        dismiss()
                                    } label: {
                                        Label("打开 Raycast", systemImage: "command")
                                    }
                                    Button {
                                        vm.buildPrompt(using: tpl, destination: .copyOnly)
                                        HapticFeedback.shared.impactOccurred()
                                        dismiss()
                                    } label: {
                                        Label("仅复制", systemImage: "doc.on.doc")
                                    }
                                }
                            }
                            Divider()
                            Button("管理模板…") {
                                vm.showingTemplatePicker = true
                            }
                        }
                        .foregroundColor(vm.selectedTokenIDs.isEmpty ? .gray : vm.currentAccentColor)
                        .disabled(vm.selectedTokenIDs.isEmpty)
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
    }
} 