import SwiftUI

/// 往书架里加书的三条路。
enum ImportMethod: String, Identifiable, CaseIterable {
    case file
    case paste
    case wifi

    var id: String { rawValue }

    var title: String {
        switch self {
        case .file:
            return "从文件导入"
        case .paste:
            return "粘贴文本"
        case .wifi:
            return "Wi‑Fi 传书"
        }
    }

    var systemImage: String {
        switch self {
        case .file:
            return "doc"
        case .paste:
            return "doc.on.clipboard"
        case .wifi:
            return "wifi"
        }
    }
}

/// 「导入」菜单里的三个选项。首屏的「导入第一本书」和书架右上角的加号共用，说法保持一致。
struct ImportMenuItems: View {
    let onSelect: (ImportMethod) -> Void

    var body: some View {
        ForEach(ImportMethod.allCases) { method in
            Button {
                onSelect(method)
            } label: {
                Label(method.title, systemImage: method.systemImage)
            }
        }
    }
}

extension View {
    func importSheet(_ method: Binding<ImportMethod?>, viewModel: ContentViewModel) -> some View {
        sheet(item: method) { method in
            switch method {
            case .file:
                DocumentPicker(viewModel: viewModel)
            case .paste:
                PasteImportView(viewModel: viewModel)
            case .wifi:
                WiFiTransferView(viewModel: viewModel)
            }
        }
    }
}
