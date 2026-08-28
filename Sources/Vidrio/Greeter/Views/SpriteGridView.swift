import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SpriteGridView: View {
    @ObservedObject var spriteManager: SpriteManager
    @Binding var selectedSprite: Sprite?
    @Binding var isRandomMode: Bool
    @Binding var searchText: String
    let accentColor: Color

    @State private var isDropTargeted = false

    var sprites: [Sprite] { spriteManager.sprites }

    var filtered: [Sprite] {
        searchText.isEmpty ? sprites
        : sprites.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private let columns = [GridItem(.adaptive(minimum: 88, maximum: 110), spacing: 8)]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    if searchText.isEmpty {
                        RandomCard(isSelected: isRandomMode, accentColor: accentColor)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.2)) {
                                    isRandomMode = true
                                    selectedSprite = nil
                                }
                            }
                    }

                    ForEach(filtered) { poke in
                        SpriteCell(
                            sprite: poke,
                            isSelected: !isRandomMode && selectedSprite == poke,
                            accentColor: accentColor
                        )
                        .onTapGesture {
                            withAnimation(.spring(response: 0.2)) {
                                isRandomMode = false
                                selectedSprite = poke
                            }
                        }
                    }
                }
                .padding(10)

                if filtered.isEmpty && !searchText.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "questionmark.diamond")
                            .font(.system(size: 36)).foregroundColor(.secondary)
                        Text("Sin resultados para \"\(searchText)\"")
                            .foregroundColor(.secondary).font(.callout)
                    }
                    .padding(.top, 40)
                }
            }
            .scrollContentBackground(.hidden)

            Divider()
            HStack {
                Text("\(filtered.count) sprites").font(.caption).foregroundColor(.secondary)
                Spacer()
                Text("Arrastra .gif aquí").font(.caption2).foregroundColor(Color.secondary.opacity(0.7))
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .overlay {
            if isDropTargeted {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(accentColor.opacity(0.12))
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(accentColor, style: StrokeStyle(lineWidth: 2, dash: [7]))
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.system(size: 30)).foregroundColor(accentColor)
                        Text("Suelta para añadir sprites")
                            .font(.callout).fontWeight(.medium)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.thickMaterial))
                }
                .padding(6)
                .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let urlProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !urlProviders.isEmpty else { return false }

        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()

        for provider in urlProviders {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                defer { group.leave() }
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let u = item as? URL {
                    url = u
                }
                if let url {
                    lock.lock(); urls.append(url); lock.unlock()
                }
            }
        }

        group.notify(queue: .main) {
            spriteManager.importSprites(from: urls)
        }
        return true
    }
}

// MARK: - Random card
struct RandomCard: View {
    let isSelected: Bool
    let accentColor: Color
    @State private var hovered = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? accentColor.opacity(0.15) : Color.primary.opacity(hovered ? 0.07 : 0.03))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? accentColor.opacity(0.9) : Color.clear, lineWidth: 2))
                    .shadow(color: isSelected ? accentColor.opacity(0.3) : .clear, radius: 8)

                Image(systemName: "dice.fill")
                    .font(.system(size: 32))
                    .foregroundColor(isSelected ? accentColor : .secondary)
                    .frame(width: 58, height: 58)
                    .padding(8)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(accentColor).font(.system(size: 12)).padding(4)
                }
            }
            .frame(width: 88, height: 78)

            Text("Aleatorio")
                .font(.caption2)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? accentColor : .primary)
                .lineLimit(1).frame(maxWidth: .infinity)
        }
        .onHover { h in withAnimation(.easeInOut(duration: 0.15)) { hovered = h } }
    }
}

// MARK: - Sprite cell
struct SpriteCell: View {
    let sprite: Sprite
    let isSelected: Bool
    let accentColor: Color
    @State private var hovered = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? accentColor.opacity(0.15) : Color.primary.opacity(hovered ? 0.07 : 0.03))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? accentColor.opacity(0.9) : Color.clear, lineWidth: 2))
                    .shadow(color: isSelected ? accentColor.opacity(0.3) : .clear, radius: 8)

                StaticGIFThumbnail(url: sprite.url)
                    .frame(width: 58, height: 58).padding(8)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(accentColor).font(.system(size: 12)).padding(4)
                }
            }
            .frame(width: 88, height: 78)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(sprite.name)
                .font(.caption2)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? accentColor : .primary)
                .lineLimit(1).frame(maxWidth: .infinity)
        }
        .onHover { h in withAnimation(.easeInOut(duration: 0.15)) { hovered = h } }
    }
}

// MARK: - Static thumbnail (no animation)
struct StaticGIFThumbnail: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> NSImageView {
        let iv = NSImageView()
        iv.animates = false
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.imageFrameStyle = .none
        iv.wantsLayer = true
        iv.layer?.masksToBounds = true
        iv.setContentHuggingPriority(.defaultLow, for: .horizontal)
        iv.setContentHuggingPriority(.defaultLow, for: .vertical)
        iv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        iv.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        iv.image = NSImage(contentsOf: url)
        return iv
    }
    func updateNSView(_ nsView: NSImageView, context: Context) {
        nsView.image = NSImage(contentsOf: url)
    }
}
