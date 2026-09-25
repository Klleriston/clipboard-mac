import AppKit
import ApplicationServices

/// Synthesises Cmd+V into whichever app has focus. Requires the app to be
/// trusted for Accessibility, because it drives another process.
enum Paster {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Opens the system prompt that sends the user to
    /// System Settings › Privacy & Security › Accessibility.
    ///
    /// Uses the literal key instead of the `kAXTrustedCheckOptionPrompt` global:
    /// that global is imported as a non-Sendable `var`, which Swift 6 strict
    /// concurrency flags as unsafe shared mutable state even though it never
    /// actually changes. Its value is stable API (confirmed at runtime against
    /// the ApplicationServices framework) — "AXTrustedCheckOptionPrompt".
    static func requestTrust() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Returns false when permission is missing; the caller should tell the user
    /// the text is on the pasteboard and they can paste it themselves.
    @discardableResult
    static func sendCommandV() -> Bool {
        guard isTrusted else { return false }

        let source = CGEventSource(stateID: .combinedSessionState)
        let v = CGKeyCode(0x09) // kVK_ANSI_V
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: false)
        else { return false }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
        return true
    }
}
