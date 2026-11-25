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

    private var hasSelection: Bool {
        !vm.selectedTokenIDs.isEmpty
    }

    /// 选择范围的起点：第一个点的那个词。
    private var anchorToken: Token? {
        guard let anchorID = vm.selectionAnchorTokenID else { return nil }
        return vm.tokens.first { $0.id == anchorID }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if vm.tokens.isEmpty {
                    ProgressView("正在分词…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 0) {
                        Text(Self.selectionHint(selectedCount: vm.selectedTokenIDs.count, anchorWord: anchorToken?.value))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                            .padding(.bottom, 4)

                        ScrollView {
                            FlowLayout(vm.tokens, id: \.id, spacing: tokenSpacing) { token in
                                tokenButton(token)
                            }
                            .padding()
                        }
                    }
                }
            }
            .navigationTitle("选词")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                        .accessibilityLabel("关闭")
                }
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        // 「清空」单独放在左边，离「复制」远一些，不容易点错。
                        Button("清空") {
                            vm.clearSelectedTokens()
                            HapticFeedback.shared.impactOccurred()
                        }
                        .disabled(!hasSelection)

                        Spacer()

                        Text(selectionStatusText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .accessibilityLabel(selectionStatusText)

                        Spacer()

                        templateMenu

                        Button("复制") {
                            HapticFeedback.shared.impactOccurred()
                            vm.copySelected()
                            dismiss()
                        }
                        .fontWeight(.semibold)
                        .disabled(!hasSelection)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .sheet(isPresented: $vm.showingTemplateLibrary) {
                NavigationStack {
                    PromptTemplateLibraryView(viewModel: vm, showsCloseButton: true)
                }
                .tint(vm.currentAccentColor)
            }
        }
        .tint(vm.currentAccentColor)
        .onAppear {
            HapticFeedback.shared.impactOccurred()
        }
    }

    /// 「模板」菜单始终能点开：没选词时也看得到有哪些模板，也能从这里去管理模板。
    private var templateMenu: some View {
        Menu("模板") {
            Section(hasSelection ? "把选中的文字套进模板" : "先选词，再用模板") {
                ForEach(vm.templates) { template in
                    templateMenuItem(template)
                }
            }

            Section {
                Button {
                    vm.showingTemplateLibrary = true
                } label: {
                    Label(vm.templates.isEmpty ? "新建模板…" : "管理模板…", systemImage: "slider.horizontal.3")
                }
            }
        }
        .menuOrder(.fixed)
    }

    @ViewBuilder
    private func templateMenuItem(_ template: PromptTemplate) -> some View {
        if let destination = template.destination {
            // 去向定好了的模板点一下直接用，不再多一层选择。
            Button {
                use(template)
            } label: {
                Text(template.name)
                Text(destination.shortName)
            }
            .disabled(!hasSelection)
        } else {
            Menu(template.name) {
                Section("选一次，以后直接用") {
                    ForEach(PromptTemplate.Destination.allCases) { destination in
                        Button(destination.displayName) {
                            use(template, destination: destination)
                        }
                    }
                }
            }
            .disabled(!hasSelection)
        }
    }

    private func use(_ template: PromptTemplate, destination: PromptTemplate.Destination? = nil) {
        HapticFeedback.shared.impactOccurred()
        vm.useTemplate(template, destination: destination)
        dismiss()
    }

    private var selectionStatusText: String {
        let count = vm.selectedTokenIDs.count
        return count == 0 ? "未选词" : "已选 \(count) 个词"
    }

    /// 选词规则写在页面上，不用靠试：选中的总是「起点」到「刚点的词」之间的全部。
    static func selectionHint(selectedCount: Int, anchorWord: String?) -> String {
        guard selectedCount > 0 else {
            return "点一个词开始选。"
        }

        let anchor = anchorWord.map { "「\(ContentViewModel.shortTitle($0, maxLength: 6))」" } ?? "起点"
        if selectedCount == 1 {
            return "再点另一个词，中间的会一起选上。再点一次\(anchor)取消。"
        }
        return "点别的词可以改范围。点起点\(anchor)只留它一个。"
    }

    private func tokenButton(_ token: Token) -> some View {
        let isSelected = vm.selectedTokenIDs.contains(token.id)
        let isAnchor = isSelected && token.id == vm.selectionAnchorTokenID
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
                        .fill(tokenFill(isSelected: isSelected, isAnchor: isAnchor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isSelected ? vm.currentAccentColor : .clear, lineWidth: isAnchor ? 2.5 : 1.5)
                )
                .padding(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isAnchor ? "起点" : "")
    }

    private func tokenFill(isSelected: Bool, isAnchor: Bool) -> Color {
        guard isSelected else { return Color(.secondarySystemBackground) }
        return vm.currentAccentColor.opacity(isAnchor ? 0.4 : 0.22)
    }
}
