import Foundation
import Testing
@testable import ClipboardKit

/// Hand-driven stand-in for NSPasteboard.
private final class FakePasteboard: PasteboardReading {
    var changeCount: Int = 0
    var isConcealed: Bool = false
    var contents: String?

    func readString() -> String? { contents }

    /// Mimics a real copy: new content plus a bumped change count.
    func copy(_ text: String?, concealed: Bool = false) {
        contents = text
        isConcealed = concealed
        changeCount += 1
    }
}

private final class SpyStore: HistoryStore {
    var saved: [ClipboardHistory] = []
    var stored = ClipboardHistory()

    func load() -> ClipboardHistory { stored }
    func save(_ history: ClipboardHistory) {
        saved.append(history)
        stored = history
    }
}

@Test @MainActor func tickRecordsNewPasteboardText() {
    let pasteboard = FakePasteboard()
    let store = SpyStore()
    let monitor = ClipboardMonitor(pasteboard: pasteboard, store: store)

    pasteboard.copy("olá")

    #expect(monitor.tick() == true)
    #expect(monitor.history.items.map(\.text) == ["olá"])
    #expect(store.saved.count == 1)
}

@Test @MainActor func tickDoesNothingWhenChangeCountIsUnchanged() {
    let pasteboard = FakePasteboard()
    let monitor = ClipboardMonitor(pasteboard: pasteboard, store: SpyStore())

    pasteboard.copy("olá")
    monitor.tick()

    #expect(monitor.tick() == false)
    #expect(monitor.history.items.count == 1)
}

@Test @MainActor func tickSkipsConcealedContent() {
    let pasteboard = FakePasteboard()
    let monitor = ClipboardMonitor(pasteboard: pasteboard, store: SpyStore())

    pasteboard.copy("senha-do-banco", concealed: true)

    #expect(monitor.tick() == false)
    #expect(monitor.history.items.isEmpty)
}

@Test @MainActor func tickSkipsNonTextContent() {
    let pasteboard = FakePasteboard()
    let monitor = ClipboardMonitor(pasteboard: pasteboard, store: SpyStore())

    pasteboard.copy(nil)

    #expect(monitor.tick() == false)
    #expect(monitor.history.items.isEmpty)
}

@Test @MainActor func monitorStartsFromPersistedHistory() {
    let store = SpyStore()
    var persisted = ClipboardHistory()
    persisted.record("antigo")
    store.stored = persisted

    let monitor = ClipboardMonitor(pasteboard: FakePasteboard(), store: store)

    #expect(monitor.history.items.map(\.text) == ["antigo"])
}

@Test @MainActor func monitorIgnoresWhateverWasOnThePasteboardAtLaunch() {
    let pasteboard = FakePasteboard()
    pasteboard.copy("já estava aqui")

    let monitor = ClipboardMonitor(pasteboard: pasteboard, store: SpyStore())

    #expect(monitor.tick() == false)
    #expect(monitor.history.items.isEmpty)
}

@Test @MainActor func acknowledgeOwnWritePreventsEchoingOurOwnPaste() {
    let pasteboard = FakePasteboard()
    let monitor = ClipboardMonitor(pasteboard: pasteboard, store: SpyStore())

    pasteboard.copy("nosso próprio texto")
    monitor.acknowledgeOwnWrite()

    #expect(monitor.tick() == false)
    #expect(monitor.history.items.isEmpty)
}

@Test @MainActor func removeAndClearPersistAndNotify() throws {
    let pasteboard = FakePasteboard()
    let store = SpyStore()
    let monitor = ClipboardMonitor(pasteboard: pasteboard, store: store)
    var notifications = 0
    monitor.onChange = { notifications += 1 }

    pasteboard.copy("a")
    monitor.tick()
    pasteboard.copy("b")
    monitor.tick()
    let target = try #require(monitor.history.items.first)

    monitor.remove(id: target.id)
    #expect(monitor.history.items.map(\.text) == ["a"])

    monitor.clear()
    #expect(monitor.history.items.isEmpty)
    #expect(store.stored.items.isEmpty)
    #expect(notifications == 4) // 2 ticks + remove + clear
}
