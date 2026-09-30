import Foundation

/// Watches the pasteboard and owns the history. Drive it by calling `tick()`
/// from a timer; it does not schedule anything itself.
@MainActor
public final class ClipboardMonitor {
    public private(set) var history: ClipboardHistory
    /// Fired after any change to `history`, so the UI can refresh.
    public var onChange: (() -> Void)?

    private let pasteboard: PasteboardReading
    private let store: HistoryStore
    private var lastChangeCount: Int

    public init(pasteboard: PasteboardReading, store: HistoryStore) {
        self.pasteboard = pasteboard
        self.store = store
        self.history = store.load()
        // Whatever is on the pasteboard at launch predates us; don't claim it.
        self.lastChangeCount = pasteboard.changeCount
    }

    /// Returns true when a new item was recorded.
    @discardableResult
    public func tick(now: Date = Date()) -> Bool {
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return false }
        lastChangeCount = current

        guard !pasteboard.isConcealed, let text = pasteboard.readString() else { return false }
        guard history.record(text, at: now) else { return false }

        persistAndNotify()
        return true
    }

    public func remove(id: UUID) {
        history.remove(id: id)
        persistAndNotify()
    }

    public func clear() {
        history.removeAll()
        persistAndNotify()
    }

    /// Call right after writing to the pasteboard ourselves, so the next tick
    /// does not re-record the text we just pasted.
    public func acknowledgeOwnWrite() {
        lastChangeCount = pasteboard.changeCount
    }

    private func persistAndNotify() {
        store.save(history)
        onChange?()
    }
}
