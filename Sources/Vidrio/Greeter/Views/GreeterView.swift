import SwiftUI
import AppKit

/// The Greeter panel: a translucent "liquid glass" sidebar — the list of
/// available sprites — driving an opaque dark detail column with the live
/// terminal preview and controls. The sidebar picks up a subtle tint from
/// the selected sprite's dominant color. Nothing is written to disk until
/// "Guardar" is pressed — picking a sprite only updates the live preview.
struct GreeterView: View {
    @StateObject private var spriteManager = SpriteManager()

    @State private var config = GreeterConfigStore.load()
    @State private var selectedSprite: Sprite?
    @State private var isRandomMode = false
    @State private var searchText = ""
    @State private var saveStatus = SaveStatus.idle
    @State private var isOnBattery = SystemInfo.isOnBattery()
    @State private var accentColor = Color(red: 0.85, green: 0.55, blue: 0.55)
    @State private var showPackStore = false
    @State private var showFieldsPicker = false

    /// What's currently on disk (config.json), so we can tell whether the live selection
    /// still matches it — drives the "Cambios sin guardar" indicator and the Guardar button.
    @State private var savedSelectedFilename: String?
    @State private var savedDisplayMode: DisplayMode = .auto
    @State private var savedFields: [InfoField] = InfoField.defaults
    @State private var savedBulletColorHex: String?

    enum SaveStatus { case idle, error }

    private var isDirty: Bool {
        let currentSprite = isRandomMode ? nil : selectedSprite?.filename
        return currentSprite != savedSelectedFilename
            || config.displayMode != savedDisplayMode
            || config.enabledFields != savedFields
            || config.bulletColorHex != savedBulletColorHex
    }

    /// The color picker's binding: the active bullet/prompt color right now,
    /// whether that's the user's override or the sprite's dominant color.
    private var bulletColorBinding: Binding<Color> {
        Binding(
            get: { accentColor },
            set: { newColor in
                config.bulletColorHex = Self.hex(from: newColor)
                withAnimation(.easeInOut(duration: 0.2)) { accentColor = newColor }
            }
        )
    }

    private static func hex(from color: Color) -> String {
        let ns = (NSColor(color).usingColorSpace(.deviceRGB)) ?? NSColor(color)
        let r = UInt8((max(0, min(1, ns.redComponent)) * 255).rounded())
        let g = UInt8((max(0, min(1, ns.greenComponent)) * 255).rounded())
        let b = UInt8((max(0, min(1, ns.blueComponent)) * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: Binding(get: { .all }, set: { _ in })) {
            SpriteGridView(
                spriteManager: spriteManager,
                selectedSprite: $selectedSprite,
                isRandomMode: $isRandomMode,
                searchText: $searchText,
                accentColor: accentColor
            )
            .navigationSplitViewColumnWidth(min: 260, ideal: 460, max: 640)
            .background(SplitViewCollapseDisabler())
            .searchable(text: $searchText, placement: .sidebar, prompt: "Buscar")
            .hideSidebarToggle()
        } detail: {
            detail
        }
        .frame(minWidth: 900, minHeight: 580)
        .preferredColorScheme(.dark)
        .background(WindowChromeConfigurator())
        .toolbarBackground(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showPackStore = true } label: {
                    Image(systemName: "plus")
                }
                .help("Descargar packs de sprites")
            }
        }
        .sheet(isPresented: $showPackStore) {
            PackStoreView(spriteManager: spriteManager, accentColor: accentColor)
        }
        .sheet(isPresented: $showFieldsPicker) {
            InfoFieldsPickerView(enabledFields: $config.enabledFields, accentColor: accentColor)
        }
        .onAppear(perform: restoreSelection)
        .onChange(of: selectedSprite) { _ in applyColor() }
        .onChange(of: isRandomMode) { _ in applyColor() }
    }

    // MARK: - Detail

    private var detail: some View {
        VStack(spacing: 0) {
            PreviewView(
                sprite: isRandomMode ? spriteManager.sprites.randomElement() : selectedSprite,
                displayMode: config.displayMode,
                isOnBattery: isOnBattery,
                fields: config.enabledFields,
                bulletColorHex: config.bulletColorHex
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            controlBar
        }
    }

    private var controlBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Modo de visualización")
                    .font(.caption).foregroundColor(.secondary)
                Picker("Modo", selection: $config.displayMode) {
                    ForEach(DisplayMode.allCases, id: \.self) { mode in
                        Label(mode.label, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 310)
            }

            Button {
                showFieldsPicker = true
            } label: {
                Label("Información", systemImage: "list.bullet.rectangle")
            }
            .help("Elige qué datos del sistema se muestran junto al sprite")

            VStack(alignment: .leading, spacing: 3) {
                Text("Color del punto")
                    .font(.caption).foregroundColor(.secondary)
                HStack(spacing: 6) {
                    ColorPicker("", selection: bulletColorBinding, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 28)
                    if config.bulletColorHex != nil {
                        Button {
                            config.bulletColorHex = nil
                            applyColor()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                        .help("Usar el color del sprite")
                    }
                }
            }

            Spacer()

            selectionIndicator

            Divider().frame(height: 34)

            saveIndicator

            Button {
                persist()
            } label: {
                Label("Guardar", systemImage: "checkmark.icloud")
            }
            .buttonStyle(.borderedProminent)
            .tint(accentColor)
            .disabled(!isDirty)
            .help("Aplica el sprite y color actuales, incluidas las ventanas de vidrio ya abiertas")
        }
        .animation(.easeInOut(duration: 0.2), value: saveStatus)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.bar)
    }

    @ViewBuilder
    private var selectionIndicator: some View {
        if isRandomMode {
            Label("Sprite aleatorio", systemImage: "dice.fill")
                .font(.caption).foregroundColor(.secondary)
        } else if let poke = selectedSprite {
            Label(poke.name, systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundColor(.secondary)
        } else {
            Text("Ningún sprite seleccionado").font(.caption).foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var saveIndicator: some View {
        switch saveStatus {
        case .error:
            Label("Error al guardar", systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundColor(.orange)
        case .idle:
            if isDirty {
                Label("Cambios sin guardar", systemImage: "circle.fill")
                    .font(.caption).foregroundColor(.orange)
            } else {
                Label("Guardado", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundColor(.green)
            }
        }
    }

    // MARK: - State

    private func restoreSelection() {
        savedSelectedFilename = config.selectedSprite
        savedDisplayMode = config.displayMode
        savedFields = config.enabledFields
        savedBulletColorHex = config.bulletColorHex
        if config.selectedSprite == nil {
            isRandomMode = true
        } else if let saved = config.selectedSprite,
                  let poke = spriteManager.sprites.first(where: { $0.filename == saved }) {
            selectedSprite = poke
        }
        applyColor()
    }

    /// Resolves the color driving the UI accent, the info-line bullets, and the prompt:
    /// the user's override if set, otherwise the current sprite's dominant color — same
    /// default as before this override existed.
    private func applyColor() {
        if let hex = config.bulletColorHex, let custom = SpriteColor(hex: hex) {
            withAnimation(.easeInOut(duration: 0.35)) { accentColor = custom.color }
            return
        }
        guard !isRandomMode, let poke = selectedSprite else {
            withAnimation(.easeInOut(duration: 0.35)) { accentColor = Color(red: 0.85, green: 0.55, blue: 0.55) }
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let color = ColorExtractor.dominantColor(for: poke.url).color
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.35)) { accentColor = color }
            }
        }
    }

    /// Save button: writes the selection to config.json. Already-open vidrio windows watch
    /// that file (AppDelegate's ConfigWatcher) and pick the change up on their own within
    /// about half a second — nothing else to do here.
    private func persist() {
        config.selectedSprite = isRandomMode ? nil : selectedSprite?.filename
        do {
            try GreeterConfigStore.save(config)
            savedSelectedFilename = config.selectedSprite
            savedDisplayMode = config.displayMode
            savedFields = config.enabledFields
            savedBulletColorHex = config.bulletColorHex
        } catch {
            withAnimation { saveStatus = .error }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation { if saveStatus == .error { saveStatus = .idle } }
            }
        }
    }
}
