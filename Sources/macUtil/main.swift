import AppKit

// No SwiftUI App lifecycle here: a plain NSApplication in accessory mode keeps
// the app out of the Dock and out of the app switcher.
let delegate = AppDelegate()
let application = NSApplication.shared
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
