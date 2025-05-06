import SwiftUI

struct BigBangView: View {
    @ObservedObject var vm: ContentViewModel
    @Environment(\.dismiss) private var dismiss
    
    // 动态 3~6 列，自动适应横竖屏
    private var columns:[GridItem] {
        Array(repeating: GridItem(.adaptive(minimum: 48), spacing: 8), count: 3)
    }
    
    @State private var startID: UUID?   // 记录滑动起点
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(vm.tokens, id:\.id) { token in
                        Text(token.value)
                            .padding(.horizontal,6).padding(.vertical,4)
                            .background(vm.selectedTokenIDs.contains(token.id) ?
                                        Color.accentColor.opacity(0.8) :
                                        Color(UIColor.secondarySystemBackground))
                            .cornerRadius(4)
                            .foregroundColor(vm.selectedTokenIDs.contains(token.id) ? .white : .primary)
                            .gesture(DragGesture(minimumDistance: 0)
                                     .onChanged{ _ in
                                         if startID == nil { startID = token.id }
                                         vm.slideSelect(from: startID!, to: token.id)
                                     }
                                     .onEnded{ _ in startID = nil })
                            .onTapGesture {
                                vm.toggleToken(token.id)         // 单点
                            }
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
                    Button("复制") { vm.copySelected(); dismiss() }
                        .disabled(vm.selectedTokenIDs.isEmpty)
                }
            }
        }
        .interactiveDismissDisabled()   // 防误触
    }
} 