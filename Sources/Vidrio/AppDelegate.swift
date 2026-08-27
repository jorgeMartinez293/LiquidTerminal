import Cocoa
import Sparkle

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    /// Sparkle auto-updates: checks the appcast on the vidrio-releases repo's gh-pages.
    private let updaterController = SPUStandardUpdaterController(startingUpdater: true,
                                                                 updaterDelegate: nil,
                                                                 userDriverDelegate: nil)
    
    // Keep strong references to windows to prevent deallocation
    var windows: Set<NSWindow> = []
    // Monotonically increasing counter for window cascade offset
    private var windowCount = 0
    // Set to true when Launch Services hands us files at startup so we don't
    // also create an empty default window.
    private var didReceiveOpenFiles = false
    private lazy var settingsWindowController = SettingsWindowController()
    /// Watches ~/.config so already-open windows can react live when sereno saves a
    /// sprite/color choice, or vaho pushes a theme — both of which today are plain file
    /// writes to config.json/settings.json with no other signal.
    private var configWatcher: ConfigWatcher?

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("Application did finish launching")

        setupMenu()
        if !didReceiveOpenFiles {
            createNewWindow()
        }
        startConfigWatcher()

        // async activation
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Exact suffixes only — NOT a directory-prefix check. sereno's greet.sh writes
    /// current_color under ~/.config/sereno/ every time it runs; if refreshSerenoGreeter()
    /// re-ran on any change under that directory it would re-trigger itself forever
    /// (save → inject sereno_greet → greet.sh writes current_color → watcher fires → inject
    /// again → ...).
    private static let serenoConfigSuffix = ".config/sereno/config.json"
    private static let vidrioSettingsSuffix = ".config/vidrio/settings.json"

    private func startConfigWatcher() {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config").path
        configWatcher = ConfigWatcher(path: configDir) { [weak self] changedPaths in
            self?.handleConfigChange(changedPaths)
        }
        configWatcher?.start()
    }

    private func handleConfigChange(_ paths: [String]) {
        if paths.contains(where: { $0.hasSuffix(Self.serenoConfigSuffix) }) {
            for window in windows {
                (window.contentViewController as? TerminalHosting)?.refreshSerenoGreeter()
            }
        }
        if paths.contains(where: { $0.hasSuffix(Self.vidrioSettingsSuffix) }) {
            SettingsStore.shared.reload()
            let settings = SettingsStore.shared.current
            for window in windows {
                (window.contentViewController as? TerminalHosting)?.applySettings(settings)
            }
        }
    }

    // Called by Launch Services when the app is opened with one or more files
    // (e.g. `open -a vidrio foo.sh` or double-clicking a script). Each
    // file is executed in its own window via `/bin/bash <path>`.
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        didReceiveOpenFiles = true
        for path in filenames {
            createNewWindow(scriptPath: path)
        }
        sender.reply(toOpenOrPrint: .success)
    }
    
    func setupMenu() {
        let menu = NSMenu()
        
        // App Menu
        let appMenuItem = NSMenuItem()
        menu.addItem(appMenuItem)
        let appMenu = NSMenu()
        let settingsItem = NSMenuItem(title: "Ajustes…", action: #selector(openSettings(_:)), keyEquivalent: ",")
        appMenu.addItem(settingsItem)
        let updateItem = NSMenuItem(title: "Buscar actualizaciones…",
                                    action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
                                    keyEquivalent: "")
        updateItem.target = updaterController
        appMenu.addItem(updateItem)
        appMenu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu
        
        // File Menu
        let fileMenuItem = NSMenuItem()
        menu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        
        let newWindowItem = NSMenuItem(title: "New Window", action: #selector(newWindow(_:)), keyEquivalent: "n")
        fileMenu.addItem(newWindowItem)

        // Routed through the responder chain: a grid window's GridViewController
        // closes just the focused pane; anywhere else it falls back to
        // closeFocusedTerminal(_:) below, which closes the key window.
        let closeWindowItem = NSMenuItem(title: "Close Window", action: #selector(closeFocusedTerminal(_:)), keyEquivalent: "w")
        fileMenu.addItem(closeWindowItem)

        fileMenuItem.submenu = fileMenu

        // Pane Menu — tiling controls for a grid window. Each item's action
        // is only implemented by GridViewController, so AppKit's automatic
        // responder-chain validation disables them in a plain (non-grid)
        // window instead of doing nothing silently.
        let paneMenuItem = NSMenuItem()
        menu.addItem(paneMenuItem)
        let paneMenu = NSMenu(title: "Pane")

        let newPaneItem = NSMenuItem(title: "New Pane", action: #selector(GridViewController.addGridPane(_:)), keyEquivalent: "n")
        newPaneItem.keyEquivalentModifierMask = [.command, .shift]
        paneMenu.addItem(newPaneItem)
        paneMenu.addItem(NSMenuItem.separator())

        let focusUpItem = NSMenuItem(title: "Focus Pane Above", action: #selector(GridViewController.moveGridFocusUp(_:)), keyEquivalent: String(UnicodeScalar(NSUpArrowFunctionKey)!))
        focusUpItem.keyEquivalentModifierMask = [.command]
        paneMenu.addItem(focusUpItem)

        let focusDownItem = NSMenuItem(title: "Focus Pane Below", action: #selector(GridViewController.moveGridFocusDown(_:)), keyEquivalent: String(UnicodeScalar(NSDownArrowFunctionKey)!))
        focusDownItem.keyEquivalentModifierMask = [.command]
        paneMenu.addItem(focusDownItem)

        let focusLeftItem = NSMenuItem(title: "Focus Pane Left", action: #selector(GridViewController.moveGridFocusLeft(_:)), keyEquivalent: String(UnicodeScalar(NSLeftArrowFunctionKey)!))
        focusLeftItem.keyEquivalentModifierMask = [.command]
        paneMenu.addItem(focusLeftItem)

        let focusRightItem = NSMenuItem(title: "Focus Pane Right", action: #selector(GridViewController.moveGridFocusRight(_:)), keyEquivalent: String(UnicodeScalar(NSRightArrowFunctionKey)!))
        focusRightItem.keyEquivalentModifierMask = [.command]
        paneMenu.addItem(focusRightItem)

        paneMenuItem.submenu = paneMenu

        // Edit Menu
        let editMenuItem = NSMenuItem()
        menu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        
        editMenu.addItem(withTitle: "Undo", action: Selector("undo:"), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector("redo:"), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        
        editMenuItem.submenu = editMenu
        
        NSApp.mainMenu = menu
    }
    
    @objc func newWindow(_ sender: Any?) {
        createNewWindow()
    }

    @objc func openSettings(_ sender: Any?) {
        settingsWindowController.showWindow(nil)
        settingsWindowController.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func createNewWindow(scriptPath: String? = nil) {
        let settings = SettingsStore.shared.current
        let font = NSFont(name: settings.fontName, size: CGFloat(settings.fontSize))
            ?? .monospacedSystemFont(ofSize: CGFloat(settings.fontSize), weight: .regular)

        let screenSize = NSScreen.main?.frame.size ?? CGSize(width: 800, height: 600)
        let windowSize = WindowSizeCalculator.windowSize(cols: settings.cols, rows: settings.rows, font: font)

        // Offset new windows with an ever-increasing counter so windows
        // don't overlap even after previous ones have been closed
        let offset = CGFloat(windowCount * 20)
        windowCount += 1

        let initialX = (screenSize.width - windowSize.width) / 2
        let initialY = (screenSize.height - windowSize.height) / 2

        let rect = NSRect(
            x: initialX + offset,
            y: initialY - offset, // Move down-right
            width: windowSize.width,
            height: windowSize.height
        )

        let newWindow = TransparentWindow(contentRect: rect)
        newWindow.delegate = self // Track closing

        if let scriptPath {
            // A one-off script window isn't a session to tile — it runs
            // /bin/bash <path> and is expected to close on its own, so it
            // keeps the original plain single-terminal controller.
            let viewController = TerminalViewController()
            viewController.settings = settings
            viewController.scriptPath = scriptPath
            newWindow.contentViewController = viewController
        } else {
            // Every interactive window is a grid that starts with a single
            // pane — visually identical to the old single-terminal window,
            // but ⌘⇧N/⌘+arrow can grow it into a tiled multi-session grid.
            let gridViewController = GridViewController()
            gridViewController.settings = settings
            newWindow.contentViewController = gridViewController
        }

        // Add to our set to keep alive
        windows.insert(newWindow)

        newWindow.makeKeyAndOrderFront(nil)
    }

    /// Fallback for ⌘W outside a grid window (e.g. a script-launched
    /// window). GridViewController implements the same selector to close
    /// just the focused pane instead; AppKit's responder chain always tries
    /// the key window's view controller before falling back to the app
    /// delegate, so this only fires when that implementation isn't there.
    @objc func closeFocusedTerminal(_ sender: Any?) {
        NSApp.keyWindow?.performClose(nil)
    }
    
    // MARK: - Window Close Handling
    //
    // CRITICAL: We NEVER let NSWindow.close() run. Its internal CA layer
    // teardown triggers a use-after-free crash in SwiftTerm's notification
    // observers (which use [unowned self]). Instead, we intercept the close
    // request, hide the window, and release it on a delay.
    
    func windowShouldClose(_ window: NSWindow) -> Bool {
        dismissWindow(window)
        return false // Prevent NSWindow.close() from running
    }
    
    /// Hides and releases a window without going through NSWindow.close().
    func dismissWindow(_ window: NSWindow) {
        // Clean up terminal process(es)
        if let host = window.contentViewController as? TerminalHosting {
            host.cleanup()
        }
        
        // Remove delegate to prevent further callbacks
        window.delegate = nil
        
        // Hide the window immediately
        window.orderOut(nil)
        
        // Release after a delay so CA can finish any pending transactions
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.windows.remove(window)
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep app running like standard Terminal, or close?
        // User said "open several times", maybe implies standard app behavior.
        // Let's return false so Cmd+N works even if all windows closed (if app is running).
        return false
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            createNewWindow()
        }
        return true
    }
}
