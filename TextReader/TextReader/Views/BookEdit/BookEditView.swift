import SwiftUI

struct BookEditView: View {
    @ObservedObject var viewModel: ContentViewModel
    @Environment(\.dismiss) private var dismiss
    
    let book: Book
    @State private var editedTitle: String
    @State private var editedContent: String
    @State private var isLoading = true
    @State private var showingSaveAlert = false
    @State private var saveError: String?
    
    init(viewModel: ContentViewModel, book: Book) {
        self.viewModel = viewModel
        self.book = book
        self._editedTitle = State(initialValue: book.title)
        self._editedContent = State(initialValue: "")
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                // Title editing
                TextField("Book Title", text: $editedTitle)
                    .textFieldStyle(.roundedBorder)
                    .padding()
                
                // Content editing
                TextEditor(text: $editedContent)
                    .padding(.horizontal)
                    .overlay(
                        Group {
                            if isLoading {
                                ProgressView("Loading...")
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(Color.black.opacity(0.3))
                            }
                        }
                    )
            }
            .navigationTitle("Edit Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(viewModel.currentAccentColor)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveChanges()
                    }
                    .foregroundColor(viewModel.currentAccentColor)
                    .disabled(editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("Save Successful", isPresented: $showingSaveAlert) {
                Button("OK") { dismiss() }
            } message: {
                Text("Book has been successfully updated")
            }
            .alert("Save Failed", isPresented: .init(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK") { }
            } message: {
                Text(saveError ?? "Unknown error")
            }
        }
        .onAppear {
            loadBookContent()
        }
    }
    
    private func loadBookContent() {
        viewModel.libraryManager.loadBookContent(book: book) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let content):
                    self.editedContent = content
                    self.isLoading = false
                case .failure(let error):
                    self.editedContent = "Loading failed: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    private func saveChanges() {
        let trimmedTitle = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        
        // If content hasn't changed, only update title
        let titleChanged = trimmedTitle != book.title
        let contentChanged = editedContent != viewModel.pages.joined(separator: " ")
        
        if titleChanged {
            viewModel.updateBookTitle(book: book, newTitle: trimmedTitle)
        }
        
        if contentChanged {
            viewModel.updateBookContent(book: book, newContent: editedContent) { success in
                if success && titleChanged {
                    // If title also changed, show alert after content save succeeds
                    self.showingSaveAlert = true
                } else if success {
                    self.showingSaveAlert = true
                } else {
                    self.saveError = "Save failed, please try again"
                }
            }
        } else if titleChanged {
            // Only title changed
            showingSaveAlert = true
        } else {
            // No changes, close directly
            dismiss()
        }
    }
} 