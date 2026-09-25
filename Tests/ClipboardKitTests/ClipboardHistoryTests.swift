import Foundation
import Testing
@testable import ClipboardKit

@Test func recordPutsNewestItemFirst() {
    var history = ClipboardHistory()
    history.record("primeiro")
    history.record("segundo")
    #expect(history.items.map(\.text) == ["segundo", "primeiro"])
}

@Test func recordMovesDuplicateToFrontWithoutGrowing() {
    var history = ClipboardHistory()
    history.record("a")
    history.record("b")
    history.record("a")
    #expect(history.items.map(\.text) == ["a", "b"])
}

@Test func recordUpdatesTimestampOfDuplicate() {
    let old = Date(timeIntervalSince1970: 0)
    let recent = Date(timeIntervalSince1970: 100)
    var history = ClipboardHistory()
    history.record("a", at: old)
    history.record("a", at: recent)
    #expect(history.items.first?.copiedAt == recent)
}

@Test func recordIgnoresBlankText() {
    var history = ClipboardHistory()
    #expect(history.record("") == false)
    #expect(history.record("   \n\t ") == false)
    #expect(history.items.isEmpty)
}

@Test func recordDropsOldestBeyondCapacity() {
    var history = ClipboardHistory(capacity: 3)
    for text in ["1", "2", "3", "4"] { history.record(text) }
    #expect(history.items.map(\.text) == ["4", "3", "2"])
}

@Test func removeDeletesOnlyTheGivenItem() throws {
    var history = ClipboardHistory()
    history.record("a")
    history.record("b")
    let target = try #require(history.items.first)
    history.remove(id: target.id)
    #expect(history.items.map(\.text) == ["a"])
}

@Test func removeAllEmptiesHistory() {
    var history = ClipboardHistory()
    history.record("a")
    history.removeAll()
    #expect(history.items.isEmpty)
}

@Test func searchIsCaseInsensitiveSubstringMatch() {
    var history = ClipboardHistory()
    history.record("Hello World")
    history.record("outra coisa")
    #expect(history.search("hello").map(\.text) == ["Hello World"])
    #expect(history.search("  ").count == 2)
}

@Test func previewCollapsesNewlinesAndTruncates() {
    let item = ClipItem(text: "linha um\n  linha dois  \n\nlinha três")
    #expect(item.preview == "linha um linha dois linha três")

    let long = ClipItem(text: String(repeating: "x", count: 200))
    #expect(long.preview.count == 80)
    #expect(long.preview.hasSuffix("…"))
}

@Test func historySurvivesJSONRoundTrip() throws {
    var history = ClipboardHistory(capacity: 5)
    history.record("a")
    history.record("b")
    let data = try JSONEncoder().encode(history)
    let decoded = try JSONDecoder().decode(ClipboardHistory.self, from: data)
    #expect(decoded == history)
}
