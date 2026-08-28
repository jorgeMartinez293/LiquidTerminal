import Foundation

struct SpritePack: Decodable, Identifiable {
    let id: String
    let name: String
    let description: String
    let sprites: [String]
}

struct PackManifest: Decodable {
    let version: Int
    let packs: [SpritePack]
}

/// Fetches the sprite-pack catalog from vidrio's own repo (sereno's is being
/// retired) and downloads packs into the local sprites directory.
@MainActor
class PackStore: ObservableObject {
    enum LoadState { case idle, loading, loaded, failed }
    enum PackState: Equatable {
        case notInstalled
        case downloading(done: Int, total: Int)
        case installed
    }

    @Published var loadState: LoadState = .idle
    @Published var packs: [SpritePack] = []
    @Published var packStates: [String: PackState] = [:]

    static let baseURL = "https://raw.githubusercontent.com/jorgeMartinez293/vidrio/main/sprite-packs"

    func spriteURL(pack: SpritePack, file: String) -> URL {
        URL(string: "\(Self.baseURL)/\(pack.id)/\(file)")!
    }

    func loadManifest() async {
        if case .loading = loadState { return }
        loadState = .loading
        do {
            var request = URLRequest(url: URL(string: "\(Self.baseURL)/packs.json")!)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, _) = try await URLSession.shared.data(for: request)
            packs = try JSONDecoder().decode(PackManifest.self, from: data).packs
            refreshStates()
            loadState = .loaded
        } catch {
            loadState = .failed
        }
    }

    /// A pack counts as installed when every one of its sprites exists locally.
    func refreshStates() {
        let fm = FileManager.default
        for pack in packs {
            if case .downloading = packStates[pack.id] { continue }
            let installed = pack.sprites.allSatisfy {
                fm.fileExists(atPath: SpriteManager.spritesDir.appendingPathComponent($0).path)
            }
            packStates[pack.id] = installed ? .installed : .notInstalled
        }
    }

    func download(_ pack: SpritePack, into manager: SpriteManager) async {
        if case .downloading = packStates[pack.id] { return }
        packStates[pack.id] = .downloading(done: 0, total: pack.sprites.count)

        let fm = FileManager.default
        try? fm.createDirectory(at: SpriteManager.spritesDir, withIntermediateDirectories: true)

        var done = 0
        var failures = 0
        for file in pack.sprites {
            do {
                let (data, _) = try await URLSession.shared.data(from: spriteURL(pack: pack, file: file))
                try data.write(to: SpriteManager.spritesDir.appendingPathComponent(file))
            } catch {
                failures += 1
            }
            done += 1
            packStates[pack.id] = .downloading(done: done, total: pack.sprites.count)
        }

        packStates[pack.id] = failures == 0 ? .installed : .notInstalled
        manager.reload()
    }
}
