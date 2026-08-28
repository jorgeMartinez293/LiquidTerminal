import Cocoa

/// Common interface for whatever a `TransparentWindow`'s `contentViewController`
/// is, so `AppDelegate` can clean up / live-reload settings without caring
/// whether the window holds a single terminal or a pane grid.
@MainActor
protocol TerminalHosting: AnyObject {
    func cleanup()
    func refreshSerenoGreeter()
    func applySettings(_ newSettings: TerminalSettings)
}

extension TerminalViewController: TerminalHosting {}

/// Hosts any number of `TerminalViewController` panes tiled to fill the
/// window, like a tiling window manager: an auto grid sized to the pane
/// count, with the focused pane's row and column enlarged. `⌘⇧N` adds a
/// pane, `⌘`+arrow moves focus between panes, and `⌘W` closes the focused
/// pane (or the window itself once only one pane is left).
class GridViewController: NSViewController, TerminalHosting {
    private struct Pane {
        let controller: TerminalViewController
        /// Clipping container the pane actually tiles into (see `relayout`).
        let cell: NSView
        /// Blur backdrop filling `cell`, behind `controller.view`. A
        /// collapsed pane's terminal never resizes (see `relayout`), so if
        /// its cell grows past its last real size, this is what shows in
        /// the leftover area instead of a bare gap.
        let cellBackdrop: NSVisualEffectView
        var isClosing = false
    }

    private var panes: [Pane] = []
    private var focusedIndex = 0
    private var hasAddedInitialPane = false
    /// Applied to every pane as it's created, and live-reloaded onto all
    /// existing panes via `applySettings`.
    var settings: TerminalSettings = .defaults

    private let spacing: CGFloat = 8
    private let focusWeight: CGFloat = 1.7

    override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        self.view = view
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if let window = view.window as? TransparentWindow {
            window.onFirstResponderChange = { [weak self] responder in
                self?.handleFirstResponderChange(responder)
            }
        }
        // Deferred from viewDidLoad so the first pane's PTY is sized against
        // the window's real, final frame rather than the placeholder one
        // above.
        guard !hasAddedInitialPane else { return }
        hasAddedInitialPane = true
        addPane()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        relayout()
    }

    // MARK: - Pane lifecycle

    @discardableResult
    private func addPane() -> TerminalViewController {
        let controller = TerminalViewController()
        controller.settings = settings
        controller.onProcessExit = { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.closePane(controller)
        }

        // Each pane tiles as `cell`, whose frame always exactly matches its
        // grid slot. `controller.view` sits inside it but, unlike `cell`,
        // is only ever resized while this pane is focused (see `relayout`)
        // — a collapsed pane's terminal geometry is left completely alone,
        // so its already-drawn output (notably a startup greeter with a
        // Kitty-protocol image, which doesn't survive a reflow intact)
        // never gets touched. `cellBackdrop` covers whatever part of a
        // collapsed, since-grown cell that leaves uncovered instead of a
        // bare gap.
        let cell = NSView()
        cell.wantsLayer = true
        cell.layer?.masksToBounds = true

        let cellBackdrop = NSVisualEffectView()
        cellBackdrop.blendingMode = .behindWindow
        cellBackdrop.state = .active
        cell.addSubview(cellBackdrop)

        panes.append(Pane(controller: controller, cell: cell, cellBackdrop: cellBackdrop))
        focusedIndex = panes.count - 1
        applyChrome()

        // Chrome (corner radius/insets) is set before controller.view is ever
        // touched, so setupTerminal() builds its layers/constraints with the
        // right values the first time instead of via a redundant live-patch.
        cell.addSubview(controller.view)
        addChild(controller)
        view.addSubview(cell)
        relayout(animated: true)
        return controller
    }

    private func handleFirstResponderChange(_ responder: NSResponder?) {
        guard let idx = panes.firstIndex(where: { $0.controller.owns(responder) }),
              idx != focusedIndex else { return }
        focusedIndex = idx
        applyChrome()
        relayout(animated: true)
    }

    private func closePane(_ controller: TerminalViewController) {
        guard let idx = panes.firstIndex(where: { $0.controller === controller }),
              !panes[idx].isClosing else { return }

        guard panes.count > 1 else {
            // Last pane left: behave like closing a normal terminal window.
            view.window?.performClose(nil)
            return
        }

        panes[idx].isClosing = true
        controller.cleanup()
        let closedCell = panes[idx].cell
        closedCell.isHidden = true
        panes.remove(at: idx)
        focusedIndex = min(focusedIndex, panes.count - 1)
        applyChrome()
        relayout(animated: true)
        focusFocusedPane()

        // Mirrors AppDelegate.dismissWindow: SwiftTerm's [unowned self]
        // observers make removing its view from the hierarchy unsafe while
        // any of its CA transactions might still be in flight, so the
        // actual removal is deferred.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak controller] in
            controller?.removeFromParent()
            controller?.view.removeFromSuperview()
            closedCell.removeFromSuperview()
        }
    }

    // MARK: - Actions (wired via the File menu's responder chain)

    /// Closes the focused pane, or the window itself if it's the only pane
    /// left.
    @objc func closeFocusedTerminal(_ sender: Any?) {
        guard focusedIndex < panes.count else { return }
        if panes.count == 1 {
            view.window?.performClose(nil)
        } else {
            closePane(panes[focusedIndex].controller)
        }
    }

    @objc func addGridPane(_ sender: Any?) {
        addPane()
        focusFocusedPane()
    }

    @objc func moveGridFocusUp(_ sender: Any?) { moveFocus(.up) }
    @objc func moveGridFocusDown(_ sender: Any?) { moveFocus(.down) }
    @objc func moveGridFocusLeft(_ sender: Any?) { moveFocus(.left) }
    @objc func moveGridFocusRight(_ sender: Any?) { moveFocus(.right) }

    private func moveFocus(_ direction: GridLayout.Direction) {
        guard panes.count > 1 else { return }
        let layout = GridLayout.compute(
            count: panes.count, focusedIndex: focusedIndex, bounds: view.bounds,
            spacing: spacing, focusWeight: focusWeight
        )
        let newIndex = GridLayout.move(from: focusedIndex, direction: direction, layout: layout)
        guard newIndex != focusedIndex else { return }
        focusedIndex = newIndex
        applyChrome()
        relayout(animated: true)
        focusFocusedPane()
    }

    private func focusFocusedPane() {
        guard focusedIndex < panes.count else { return }
        panes[focusedIndex].controller.focusTerminal()
    }

    // MARK: - Layout

    /// Window resize skips the animation, since it already fires
    /// continuously — everything else (focus change, pane add/remove)
    /// asks for `animated: true`, so a pane's cell slides into its new
    /// slot instead of jumping there.
    private func relayout(animated: Bool = false) {
        guard !panes.isEmpty else { return }
        // No spacing to reserve with nothing to space between — a single
        // pane fills the window edge-to-edge exactly like the original
        // single-window look, instead of sitting inset with a visible gap
        // that throws off how its 28pt corner radius reads.
        let layout = GridLayout.compute(
            count: panes.count, focusedIndex: focusedIndex, bounds: view.bounds,
            spacing: panes.count > 1 ? spacing : 0, focusWeight: focusWeight
        )
        let applyFrames = {
            for (idx, pane) in self.panes.enumerated() {
                let target = layout.frames[idx]
                if animated {
                    pane.cell.animator().frame = target
                    pane.cellBackdrop.animator().frame = NSRect(origin: .zero, size: target.size)
                } else {
                    pane.cell.frame = target
                    pane.cellBackdrop.frame = NSRect(origin: .zero, size: target.size)
                }
                // Only the focused pane's terminal actually resizes (and so
                // reflows) — a collapsed pane keeps whatever geometry it had
                // the last time it was focused; `cellBackdrop`, not a resize,
                // is what covers its cell if that leaves it short.
                if idx == self.focusedIndex {
                    let focusedTarget = NSRect(origin: .zero, size: target.size)
                    if animated {
                        pane.controller.view.animator().frame = focusedTarget
                    } else {
                        pane.controller.view.frame = focusedTarget
                    }
                }
            }
        }
        guard animated else {
            applyFrames()
            return
        }
        // Sped up well past macOS's default 0.25s so darting between panes
        // reads as a quick slide rather than a laggy animation.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.09
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            applyFrames()
        }
    }

    /// A single pane keeps the app's original chrome (28pt radius, 50pt top
    /// inset to clear the window's traffic lights). Once there's more than
    /// one, every pane shrinks to a tighter uniform inset. The grid isn't
    /// margined out from under the window's traffic lights — like the
    /// original single-window look, the top-left pane's card sits behind
    /// them, and its own top inset (30pt, enough to clear the button row)
    /// keeps its terminal text from running under them. Only the focused
    /// pane forwards its shell's OSC title to the window.
    private func applyChrome() {
        let single = panes.count == 1
        for (idx, pane) in panes.enumerated() {
            let radius: CGFloat = single ? 28 : 16
            pane.controller.cornerRadius = radius
            pane.controller.topInset = single ? 50 : 30
            pane.controller.sideInset = single ? 10 : 8
            pane.controller.bottomInset = single ? 10 : 8
            pane.controller.forwardsTitleToWindow = idx == focusedIndex

            // `cell` itself clips a collapsed pane's oversized, stale-framed
            // `controller.view` (see `relayout`) — without its own radius
            // here, that clip lands on a bare rectangular edge instead of
            // matching cellBackdrop's rounded corner.
            pane.cell.layer?.cornerRadius = radius

            pane.cellBackdrop.wantsLayer = true
            pane.cellBackdrop.layer?.masksToBounds = true
            pane.cellBackdrop.layer?.cornerRadius = radius
            if let material = settings.blurMaterial.material {
                pane.cellBackdrop.material = material
                pane.cellBackdrop.isHidden = false
            } else {
                pane.cellBackdrop.isHidden = true
            }
        }
    }

    // MARK: - TerminalHosting

    func cleanup() {
        for pane in panes {
            pane.controller.cleanup()
        }
    }

    func refreshSerenoGreeter() {
        for pane in panes {
            pane.controller.refreshSerenoGreeter()
        }
    }

    func applySettings(_ newSettings: TerminalSettings) {
        settings = newSettings
        for pane in panes {
            pane.controller.applySettings(newSettings)
        }
        applyChrome()
    }
}
