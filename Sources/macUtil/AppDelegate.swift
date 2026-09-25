import AppKit
import ClipboardKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var monitor: ClipboardMonitor!
    private var statusItem: NSStatusItem!
    private var pollTimer: Timer?

    /// macOS gives no pasteboard-change notification; 0.5 s is the usual compromise
    /// between catching every copy and staying idle.
    private let pollInterval: TimeInterval = 0.5

    func applicationDidFinishLaunching(_ notification: Notification) {
        monitor = ClipboardMonitor(
            pasteboard: NSPasteboard.general,
            store: JSONHistoryStore(url: JSONHistoryStore.defaultURL())
        )

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "list.clipboard",
            accessibilityDescription: "macUtil clipboard history"
        )
        statusItem.menu = makeMenu()

        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            // The timer fires on the main run loop, so main-actor state is safe here.
            _ = MainActor.assumeIsolated { self?.monitor.tick() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollTimer?.invalidate()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Sair do macUtil", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }
}
