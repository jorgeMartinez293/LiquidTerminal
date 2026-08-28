import SwiftUI
import AppKit

// MARK: - Sidebar chrome helpers (ported from vaho's settings window, via sereno)

extension View {
    /// System Settings has no sidebar-collapse chevron; drop ours where the API exists.
    @ViewBuilder
    func hideSidebarToggle() -> some View {
        if #available(macOS 14.0, *) {
            toolbar(removing: .sidebarToggle)
        } else {
            self
        }
    }
}

/// Invisible helper that walks up from its own NSView to the ancestor NSSplitView
/// (NavigationSplitView's AppKit backing) and disables `canCollapse` on every split
/// item, so dragging the divider can't collapse the sidebar to zero width.
struct SplitViewCollapseDisabler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { Self.disableCollapse(startingAt: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { Self.disableCollapse(startingAt: nsView) }
    }

    private static func disableCollapse(startingAt view: NSView) {
        var current: NSView? = view
        while let v = current {
            if let splitView = v as? NSSplitView,
               let controller = splitView.delegate as? NSSplitViewController {
                for item in controller.splitViewItems {
                    item.canCollapse = false
                }
                return
            }
            current = v.superview
        }
    }
}

// MARK: - Window chrome

/// Reaches the Greeter window and gives it the same chrome as vaho's/sereno's
/// settings windows: full-size content + transparent titlebar so the translucent
/// sidebar material runs up behind the traffic lights, a real unified toolbar
/// (needed for the tall titlebar and large window corner radius on macOS 26),
/// hidden title, pinned dark.
struct WindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        if window.toolbar == nil {
            let toolbar = NSToolbar()
            toolbar.showsBaselineSeparator = false
            window.toolbar = toolbar
        }
        window.toolbarStyle = .unified
        window.appearance = NSAppearance(named: .darkAqua)
    }
}
