import Foundation
import AppKit

struct Sprite: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let filename: String
    let url: URL
    let isGIF: Bool

    func hash(into hasher: inout Hasher) { hasher.combine(filename) }
    static func == (lhs: Sprite, rhs: Sprite) -> Bool { lhs.filename == rhs.filename }
}

class SpriteManager: ObservableObject {
    @Published var sprites: [Sprite] = []

    static let spritesDir: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/sereno/sprites")
    }()

    /// Sprites left behind by an old pokefetch install; read-only fallback until
    /// migrated (mirrors sereno's own install.sh migration).
    static let legacySpritesDir: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/fastfetch/pokemons")
    }()

    init() { reload() }

    func reload() {
        let fm = FileManager.default
        let dir = fm.fileExists(atPath: Self.spritesDir.path) ? Self.spritesDir : Self.legacySpritesDir
        guard let files = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { return }

        let valid = Set(["gif", "png", "jpg", "jpeg", "webp"])
        sprites = files
            .filter { valid.contains($0.pathExtension.lowercased()) }
            .map { url in
                let filename = url.lastPathComponent
                let name = url.deletingPathExtension().lastPathComponent
                    .replacingOccurrences(of: "_", with: " ")
                    .replacingOccurrences(of: "-", with: " ")
                    .capitalized
                return Sprite(name: name, filename: filename, url: url,
                               isGIF: url.pathExtension.lowercased() == "gif")
            }
            .sorted { $0.name < $1.name }
    }

    /// Copies image files into the sprites directory (renaming on collision)
    /// and reloads. Returns how many files were imported.
    @discardableResult
    func importSprites(from urls: [URL]) -> Int {
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.spritesDir, withIntermediateDirectories: true)

        let valid = Set(["gif", "png", "jpg", "jpeg", "webp"])
        var copied = 0
        for src in urls where valid.contains(src.pathExtension.lowercased()) {
            let base = src.deletingPathExtension().lastPathComponent
            let ext = src.pathExtension
            var dest = Self.spritesDir.appendingPathComponent(src.lastPathComponent)
            var i = 2
            while fm.fileExists(atPath: dest.path) {
                dest = Self.spritesDir.appendingPathComponent("\(base)-\(i).\(ext)")
                i += 1
            }
            if (try? fm.copyItem(at: src, to: dest)) != nil { copied += 1 }
        }
        if copied > 0 { reload() }
        return copied
    }

    /// Removes a sprite's file from disk and reloads.
    func deleteSprite(_ sprite: Sprite) {
        try? FileManager.default.removeItem(at: sprite.url)
        reload()
    }
}
