import AppKit
import ClipboardKit
import SwiftUI

/// Owns the floating panel. Remembers which app was in front so the caller can
/// hand focus back after a pick.
@MainActor
final class PopupController {
    /// The app that was frontmost when the popup opened.
    private(set) var previousApplication: NSRunningApplication?

    private let monitor: ClipboardMonitor
    private let onPick: (ClipItem) -> Void
    private var panel: NSPanel?

    init(monitor: ClipboardMonitor, onPick: @escaping (ClipItem) -> Void) {
        self.monitor = monitor
        self.onPick = onPick
    }

    func toggle() {
        if panel?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    func show() {
        previousApplication = NSWorkspace.shared.frontmostApplication

        let viewModel = HistoryViewModel(monitor: monitor)
        let view = HistoryListView(
            viewModel: viewModel,
            onPick: { [weak self] item in
                self?.hide()
                self?.onPick(item)
            },
            onDismiss: { [weak self] in self?.hide() }
        )

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 420),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: view)
        panel.center()

        // An accessory app must activate for its panel to take keyboard input.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}
