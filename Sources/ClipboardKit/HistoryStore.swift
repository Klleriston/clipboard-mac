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
        writeOwnerOnly(data, to: url)
    }

    /// Writes `data` to `url` atomically and owner-only. The file is created
    /// with mode 0600 rather than chmod'd afterwards, so its contents are never
    /// readable by anyone else — not even for the instant between write and
    /// rename. Foundation's atomic write cannot do this: it creates its
    /// temporary file under the process umask.
    private func writeOwnerOnly(_ data: Data, to url: URL) {
        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString)")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard descriptor >= 0 else { return }

        var wrote = true
        data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                // write(2) may satisfy only part of a large buffer.
                let written = write(descriptor, buffer.baseAddress! + offset, buffer.count - offset)
                guard written > 0 else { wrote = false; return }
                offset += written
            }
        }
        close(descriptor)

        // rename(2) replaces the destination in one step, so a reader sees
        // either the old file or the new one, never a half-written one.
        guard wrote, rename(temporary.path, url.path) == 0 else {
            unlink(temporary.path)
            return
        }
    }
}
