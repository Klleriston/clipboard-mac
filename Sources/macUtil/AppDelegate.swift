import AppKit
import ClipboardKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var monitor: ClipboardMonitor!
    private var statusItem: NSStatusItem!
    private var pollTimer: Timer?
    private var hotKey: HotKey?
    private var popup: PopupController?

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

        popup = PopupController(monitor: monitor) { [weak self] item in
            self?.use(item)
        }
        hotKey = HotKey.controlOptionV { [weak self] in
            self?.popup?.toggle()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollTimer?.invalidate()
    }

    /// Puts the chosen text on the pasteboard, hands focus back to the app the
    /// user came from, and pastes there.
    private func use(_ item: ClipItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.text, forType: .string)
        monitor.acknowledgeOwnWrite()

        guard Paster.isTrusted else {
            Paster.requestTrust()
            notifyPasteboardOnly()
            return
        }

        popup?.previousApplication?.activate()
        // The target app needs a moment to become frontmost before it can
        // receive the synthesised keystroke.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            Paster.sendCommandV()
        }
    }

    /// Fallback path when Accessibility permission is missing.
    private func notifyPasteboardOnly() {
        let alert = NSAlert()
        alert.messageText = "Texto copiado para a área de transferência"
        alert.informativeText = """
            Para o macUtil colar automaticamente, permita o acesso em \
            Ajustes do Sistema › Privacidade e Segurança › Acessibilidade. \
            Por enquanto, use Cmd+V para colar.
            """
        alert.alertStyle = .informational
        alert.runModal()
    }

    @objc private func openPopup() {
        popup?.show()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let open = NSMenuItem(title: "Abrir histórico", action: #selector(openPopup), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Sair do macUtil", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }
}
