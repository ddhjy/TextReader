import SwiftUI

struct AccentColorPicker: View {
    @ObservedObject var viewModel: ContentViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(AccentColorTheme.presets) { theme in
                    HStack {
                        Circle()
                            .fill(theme.color(for: colorScheme))
                            .frame(width: 30, height: 30)
                        
                        Text(theme.name)
                            .font(.body)
                        
                        Spacer()
                        
                        if viewModel.accentColorThemeId == theme.id {
                            Image(systemName: "checkmark")
                                .foregroundColor(theme.color(for: colorScheme))
                                .font(.body.weight(.semibold))
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.accentColorThemeId = theme.id
                    }
                }
            }
            .navigationTitle("强调色")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                        .foregroundColor(viewModel.currentAccentColor)
                }
            }
        }
    }
} 