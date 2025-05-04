import SwiftUI

struct SearchBar: View {
    @Binding var text: String
    var onCommit: () -> Void

    var body: some View {
        HStack {
            TextField("搜索...", text: $text, onCommit: onCommit)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.trailing, 8)

            if !text.isEmpty {
                Button(action: { self.text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                        .accessibility(label: Text("清除搜索内容"))
                }
                .buttonStyle(PlainButtonStyle())
            }

            Button(action: onCommit) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.blue)
                    .accessibility(label: Text("执行搜索"))
                    .padding(.vertical, 8)
            }
        }
        .padding(.horizontal)
    }
} 