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

    /// What's currently on disk (config.json), so we can tell whether the live selection
    /// still matches it — drives the "Cambios sin guardar" indicator and the Guardar button.
    @State private var savedSelectedFilename: String?
    @State private var savedDisplayMode: DisplayMode = .auto

    enum SaveStatus { case idle, error }

    private var isDirty: Bool {
        let currentSprite = isRandomMode ? nil : selectedSprite?.filename
        return currentSprite != savedSelectedFilename || config.displayMode != savedDisplayMode
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
        .onAppear(perform: restoreSelection)
        .onChange(of: selectedSprite) { poke in
            if let poke { computeColor(for: poke) }
        }
        .onChange(of: isRandomMode) { random in
            if random { accentColor = Color(red: 0.85, green: 0.55, blue: 0.55) }
        }
    }

    // MARK: - Detail

    private var detail: some View {
        VStack(spacing: 0) {
            PreviewView(
                sprite: isRandomMode ? spriteManager.sprites.randomElement() : selectedSprite,
                displayMode: config.displayMode,
                isOnBattery: isOnBattery
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
        if config.selectedSprite == nil {
            isRandomMode = true
            accentColor = Color(red: 0.85, green: 0.55, blue: 0.55)
        } else if let saved = config.selectedSprite,
                  let poke = spriteManager.sprites.first(where: { $0.filename == saved }) {
            selectedSprite = poke
            computeColor(for: poke)
        }
    }

    private func computeColor(for poke: Sprite) {
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
        } catch {
            withAnimation { saveStatus = .error }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation { if saveStatus == .error { saveStatus = .idle } }
            }
        }
    }
}
