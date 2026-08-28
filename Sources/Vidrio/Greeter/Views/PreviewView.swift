import SwiftUI
import AppKit
import SwiftTerm

struct PreviewView: View {
    let sprite: Sprite?
    let displayMode: DisplayMode
    let isOnBattery: Bool

    private var showGIF: Bool {
        switch displayMode {
        case .gif: return true
        case .image: return false
        case .auto: return !isOnBattery
        }
    }

    // SF Mono 11pt line height (px) used to estimate terminal rows from view height
    private static let lineHeight: CGFloat = 15.0
    // Expected greeting height in rows (logo + info side-by-side, box height 15 + margins)
    private static let outputRows = 17

    var body: some View {
        ZStack {
            Color(red: 0.10, green: 0.10, blue: 0.13)

            if sprite != nil {
                GeometryReader { geo in
                    let terminalRows = Int(geo.size.height / Self.lineHeight)
                    let topPadding = max(0, (terminalRows - Self.outputRows) / 2)
                    TerminalPreviewView(
                        sprite: sprite,
                        displayMode: displayMode,
                        topPadding: topPadding,
                        size: geo.size
                    )
                }
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 52)).foregroundColor(.white.opacity(0.18))
                    Text("Selecciona un sprite →")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                }
            }

            VStack {
                HStack {
                    Spacer()
                    Label(showGIF ? "GIF animado" : "Imagen estática",
                          systemImage: showGIF ? "play.circle.fill" : "photo.fill")
                        .font(.caption.monospaced())
                        .foregroundColor(.white.opacity(0.65))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.ultraThinMaterial.opacity(0.6))
                        .cornerRadius(6)
                        .padding(12)
                }
                Spacer()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .padding(16)
    }
}

/// Renders the greeting straight into the buffer with `feed(byteArray:)` — no
/// subprocess, no `.zshrc` cooperation, updates instantly as the picker changes.
struct TerminalPreviewView: NSViewRepresentable {
    let sprite: Sprite?
    let displayMode: DisplayMode
    let topPadding: Int
    /// The view's laid-out size from the caller's GeometryReader. SwiftTerm computes its
    /// column/row count from the view's frame at the moment content is fed, so this must be
    /// applied before rendering — an initial `.zero` frame (fixed up only later by
    /// SwiftUI's own layout pass) leaves the greeting rendered for a near-zero-width
    /// terminal, clamping every cursor move and stacking the info block under the sprite.
    let size: CGSize

    class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func processTerminated(source: TerminalView, exitCode: Int32?) {}
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let tv = LocalProcessTerminalView(frame: NSRect(origin: .zero, size: size))
        tv.processDelegate = context.coordinator
        tv.scrollerEnabled = false
        tv.nativeBackgroundColor = NSColor(red: 0.10, green: 0.10, blue: 0.13, alpha: 1.0)
        tv.nativeForegroundColor = .white
        tv.caretColor = .white
        tv.font = NSFont(name: "SF Mono", size: 11) ?? NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        renderGreeting(in: tv)
        return tv
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        nsView.frame = NSRect(origin: .zero, size: size)
        renderGreeting(in: nsView)
    }

    static func dismantleNSView(_ nsView: LocalProcessTerminalView, coordinator: Coordinator) {
        nsView.processDelegate = nil
    }

    private func renderGreeting(in tv: LocalProcessTerminalView) {
        guard let sprite else { return }
        tv.terminal.resetToInitialState()
        var bytes: [UInt8] = topPadding > 0 ? Array(String(repeating: "\n", count: topPadding).utf8) : []
        bytes += GreetingRenderer.render(spriteURL: sprite.url, displayMode: displayMode, shellExecutable: "/bin/zsh")
        bytes += Self.promptPreview(spriteURL: sprite.url)
        tv.feed(byteArray: bytes[...])
    }

    /// A static stand-in for the real, dynamic zsh prompt (applied to actual shells via
    /// `ZshPromptShim`, which the preview has no shell to run) — same colored bullet +
    /// home-directory path as sereno's old `sereno_prompt()`, so the picker shows what a
    /// real new terminal's prompt line will look like.
    private static func promptPreview(spriteURL: URL) -> [UInt8] {
        let color = ColorExtractor.dominantColor(for: spriteURL)
        let path = FileManager.default.homeDirectoryForCurrentUser.path
        let fg = String(decoding: color.ansiForeground, as: UTF8.self)
        return Array("\(fg)\u{25CF}\u{1B}[0m \(fg)\(path)\u{1B}[0m ".utf8)
    }
}
