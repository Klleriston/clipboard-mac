import Foundation

/// Newest-first list of copied texts, deduplicated and capped.
public struct ClipboardHistory: Codable, Equatable, Sendable {
    public static let defaultCapacity = 200

    public private(set) var items: [ClipItem]
    public let capacity: Int

    public init(items: [ClipItem] = [], capacity: Int = ClipboardHistory.defaultCapacity) {
        self.capacity = max(1, capacity)
        self.items = Array(items.prefix(self.capacity))
    }

    /// Inserts `text` at the front, moving an existing copy instead of duplicating it.
    /// Returns false when the text was blank and nothing changed.
    @discardableResult
    public mutating func record(_ text: String, at date: Date = Date()) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        if let index = items.firstIndex(where: { $0.text == text }) {
            var existing = items.remove(at: index)
            existing.copiedAt = date
            items.insert(existing, at: 0)
            return true
        }

        items.insert(ClipItem(text: text, copiedAt: date), at: 0)
        if items.count > capacity {
            items.removeLast(items.count - capacity)
        }
        return true
    }

    public mutating func remove(id: UUID) {
        items.removeAll { $0.id == id }
    }

    public mutating func removeAll() {
        items.removeAll()
    }

    /// Case-insensitive substring filter. A blank query returns everything.
    public func search(_ query: String) -> [ClipItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        return items.filter { $0.text.localizedCaseInsensitiveContains(trimmed) }
    }
}
