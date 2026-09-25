import ClipboardKit
import Foundation
import Observation

/// Search text, filtered rows and keyboard selection for the popup.
@MainActor
@Observable
final class HistoryViewModel {
    var query: String = "" {
        didSet { refresh() }
    }
    private(set) var items: [ClipItem] = []
    var selection: UUID?

    private let monitor: ClipboardMonitor

    init(monitor: ClipboardMonitor) {
        self.monitor = monitor
        refresh()
    }

    var selectedItem: ClipItem? {
        items.first { $0.id == selection }
    }

    func refresh() {
        items = monitor.history.search(query)
        if selection == nil || !items.contains(where: { $0.id == selection }) {
            selection = items.first?.id
        }
    }

    func moveSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        let current = items.firstIndex { $0.id == selection } ?? 0
        let next = min(max(current + delta, 0), items.count - 1)
        selection = items[next].id
    }

    func delete(id: UUID) {
        monitor.remove(id: id)
        refresh()
    }
}
