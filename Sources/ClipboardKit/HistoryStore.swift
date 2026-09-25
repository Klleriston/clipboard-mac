import Darwin
import Foundation

/// Where the history is kept between launches.
public protocol HistoryStore {
    func load() -> ClipboardHistory
    func save(_ history: ClipboardHistory)
}

/// Single pretty-printed JSON file. Failures are swallowed on purpose: losing
/// history is acceptable, crashing a background menu-bar app is not.
public struct JSONHistoryStore: HistoryStore {
    public let url: URL
    private let fileManager: FileManager

    public init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    public static func defaultURL(fileManager: FileManager = .default) -> URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support
            .appendingPathComponent("macUtil", isDirectory: true)
            .appendingPathComponent("history.json")
    }

    public func load() -> ClipboardHistory {
        guard let data = try? Data(contentsOf: url),
              let history = try? JSONDecoder().decode(ClipboardHistory.self, from: data)
        else { return ClipboardHistory() }
        return history
    }

    public func save(_ history: ClipboardHistory) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(history) else { return }

        try? fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // A file created by an atomic write inherits the process umask, so it
        // would be world-readable for the moment before the chmod below.
        // Narrow the umask across the write instead: the file is never
        // readable by anyone else, not even briefly.
        let previousMask = Darwin.umask(0o077)
        let wrote = (try? data.write(to: url, options: .atomic)) != nil
        _ = Darwin.umask(previousMask)
        guard wrote else { return }
        // Clipboard text is sensitive; keep it out of other accounts' reach.
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
