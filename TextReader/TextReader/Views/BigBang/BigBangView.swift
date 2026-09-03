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
    
    private let tokenHeight: CGFloat = 40
    private let tokenSpacing: CGFloat = 8
    
    var body: some View {
        NavigationStack {
            Group {
                if vm.tokens.isEmpty {
                    ProgressView("正在分词…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        FlowLayout(vm.tokens, id: \.id, spacing: tokenSpacing) { token in
                            tokenButton(token)
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("选词")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                        .accessibilityLabel("关闭")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("清空") {
                        if !vm.selectedTokenIDs.isEmpty {
                            vm.clearSelectedTokens()
                            HapticFeedback.shared.impactOccurred()
                        }
                    }
                    .disabled(vm.selectedTokenIDs.isEmpty)
                }
                ToolbarItem(placement: .bottomBar) {
                    HStack {
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
                        .disabled(vm.selectedTokenIDs.isEmpty)

                        Spacer()

                        Text(selectionStatusText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(selectionStatusText)

                        Spacer()

                        Button("复制") {
                            HapticFeedback.shared.impactOccurred()
                            vm.copySelected()
                            dismiss()
                        }
                        .disabled(vm.selectedTokenIDs.isEmpty)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .sheet(isPresented: $vm.showingTemplatePicker) {
                PromptTemplatePicker(viewModel: vm)
            }
            .alert(
                vm.generatedPrompt?.message ?? "",
                isPresented: Binding(
                    get: { vm.generatedPrompt != nil },
                    set: { if !$0 { vm.generatedPrompt = nil } }
                )
            ) {
                Button("好") {
                    vm.generatedPrompt = nil
                }
            }
        }
        .tint(vm.currentAccentColor)
        .onAppear {
            HapticFeedback.shared.impactOccurred()
        }
    }

    private var selectionStatusText: String {
        let count = vm.selectedTokenIDs.count
        return count == 0 ? "未选词" : "已选 \(count) 个词"
    }

    private func tokenButton(_ token: Token) -> some View {
        let isSelected = vm.selectedTokenIDs.contains(token.id)
        return Button {
            vm.processTokenTap(tappedTokenID: token.id)
            HapticFeedback.shared.selectionChanged()
        } label: {
            Text(token.value)
                .font(isSelected ? .body.weight(.semibold) : .body)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .fixedSize(horizontal: true, vertical: false)
                .frame(height: tokenHeight)
                .foregroundStyle(.primary)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? vm.currentAccentColor.opacity(0.22) : Color(.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isSelected ? vm.currentAccentColor : .clear, lineWidth: 1.5)
                )
                .padding(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
