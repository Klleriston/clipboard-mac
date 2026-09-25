import Foundation
import Testing
@testable import ClipboardKit

/// Fresh empty directory per test, removed at the end.
private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("macUtilTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory)
}

@Test func loadReturnsEmptyHistoryWhenFileMissing() throws {
    try withTemporaryDirectory { directory in
        let store = JSONHistoryStore(url: directory.appendingPathComponent("history.json"))
        #expect(store.load().items.isEmpty)
    }
}

@Test func saveThenLoadRoundTripsItems() throws {
    try withTemporaryDirectory { directory in
        let store = JSONHistoryStore(url: directory.appendingPathComponent("history.json"))
        var history = ClipboardHistory()
        history.record("um")
        history.record("dois")

        store.save(history)

        #expect(store.load().items.map(\.text) == ["dois", "um"])
    }
}

@Test func loadReturnsEmptyHistoryWhenFileIsCorrupt() throws {
    try withTemporaryDirectory { directory in
        let url = directory.appendingPathComponent("history.json")
        try Data("not json at all".utf8).write(to: url)
        let store = JSONHistoryStore(url: url)
        #expect(store.load().items.isEmpty)
    }
}

@Test func saveCreatesMissingParentDirectory() throws {
    try withTemporaryDirectory { directory in
        let url = directory
            .appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent("history.json")
        let store = JSONHistoryStore(url: url)
        var history = ClipboardHistory()
        history.record("um")

        store.save(history)

        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}

@Test func savedFileIsReadableOnlyByOwner() throws {
    try withTemporaryDirectory { directory in
        let url = directory.appendingPathComponent("history.json")
        let store = JSONHistoryStore(url: url)
        var history = ClipboardHistory()
        history.record("segredo")

        store.save(history)

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
        #expect(permissions.int16Value == 0o600)
    }
}

@Test func defaultURLLivesUnderApplicationSupport() {
    let url = JSONHistoryStore.defaultURL()
    #expect(url.lastPathComponent == "history.json")
    #expect(url.deletingLastPathComponent().lastPathComponent == "macUtil")
    #expect(url.path.contains("Application Support"))
}
