import SwiftUI
import UIKit

struct SearchBar: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    var onSubmit: () -> Void = {}
    var accessibilityIdentifier: String?

    func makeUIView(context: Context) -> UISearchBar {
        let searchBar = UISearchBar(frame: .zero)
        searchBar.delegate = context.coordinator
        searchBar.searchBarStyle = .minimal
        searchBar.returnKeyType = .search
        searchBar.enablesReturnKeyAutomatically = false
        searchBar.autocapitalizationType = .none
        searchBar.autocorrectionType = .no
        searchBar.placeholder = placeholder
        searchBar.text = text
        searchBar.searchTextField.autocapitalizationType = .none
        searchBar.searchTextField.autocorrectionType = .no
        searchBar.searchTextField.spellCheckingType = .no
        searchBar.searchTextField.smartQuotesType = .no
        searchBar.searchTextField.smartDashesType = .no
        searchBar.searchTextField.smartInsertDeleteType = .no
        searchBar.searchTextField.clearButtonMode = .whileEditing

        if let accessibilityIdentifier {
            searchBar.searchTextField.accessibilityIdentifier = accessibilityIdentifier
        }

        context.coordinator.state.replaceFromExternal(text)
        return searchBar
    }

    func updateUIView(_ uiView: UISearchBar, context: Context) {
        uiView.placeholder = placeholder

        if let accessibilityIdentifier {
            uiView.searchTextField.accessibilityIdentifier = accessibilityIdentifier
        }

        if text != context.coordinator.state.publishedText {
            context.coordinator.state.replaceFromExternal(text)
        }

        let desiredText = context.coordinator.state.displayText
        if uiView.text != desiredText {
            uiView.text = desiredText
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UISearchBarDelegate {
        var parent: SearchBar
        var state: SearchCompositionState

        init(parent: SearchBar) {
            self.parent = parent
            self.state = SearchCompositionState()
            self.state.replaceFromExternal(parent.text)
        }

        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            let isComposing = searchBar.searchTextField.markedTextRange != nil
            if let confirmedText = state.handleTextChange(searchText, isComposing: isComposing) {
                parent.text = confirmedText
            }
        }

        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            commitCurrentText()
            parent.onSubmit()
            searchBar.resignFirstResponder()
        }

        func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
            commitCurrentText()
        }

        private func commitCurrentText() {
            if let confirmedText = state.commitCurrentText() {
                parent.text = confirmedText
            }
        }
    }
}
