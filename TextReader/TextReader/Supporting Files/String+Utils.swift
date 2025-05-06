import Foundation

extension Optional where Wrapped == String {
    func nilIfEmpty() -> String? {
        guard let s = self, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return s
    }
} 