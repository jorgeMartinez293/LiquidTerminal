import Cocoa
import SwiftUI

/// Hosts the SwiftUI `GreeterView` in its own window. Single instance.
@MainActor
final class GreeterWindowController: NSWindowController {
    convenience init() {
        let hosting = NSHostingController(rootView: GreeterView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Greeter"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
    }
}
