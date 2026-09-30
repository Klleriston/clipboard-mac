import Foundation

/// One piece of text captured from the pasteboard.
public struct ClipItem: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let text: String
    /// Last time this exact text was copied. Re-copying an existing item bumps it.
    public var copiedAt: Date

    public init(id: UUID = UUID(), text: String, copiedAt: Date = Date()) {
        self.id = id
        self.text = text
        self.copiedAt = copiedAt
    }

    /// Single-line, length-capped label for the popup list.
    public var preview: String {
        let collapsed = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard collapsed.count > 80 else { return collapsed }
        return String(collapsed.prefix(79)) + "…"
    }
}
