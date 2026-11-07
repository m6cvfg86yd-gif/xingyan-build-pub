import Foundation
import SwiftUI

struct RemoteStickerPack: Decodable, Hashable, Identifiable {
    var id: String
    var name: String
    var category: String

    var dir: String

    var icon: String
    var files: [String]

    var paths: [String] { files.map { dir + "/" + $0 } }
}

struct StickerCategory: Decodable, Hashable, Identifiable {
    var id: String
    var name: String
}

private struct StickerCatalogPayload: Decodable {
    var categories: [StickerCategory]?
    var packs: [RemoteStickerPack]?
}

@MainActor
final class StickerCatalog: ObservableObject {
    static let shared = StickerCatalog()

    @Published private(set) var categories: [StickerCategory] = []
    @Published private(set) var packs: [RemoteStickerPack] = []
    @Published private(set) var loading = false
    private var loaded = false

    func loadIfNeeded() async {
        if loaded || loading { return }
        loading = true
        defer { loading = false }

        var didLoad = false

        // The first-party pack ships inside the app. Load it before any network
        // request so opening the emoji panel never waits for or depends on the
        // production server.
        if let url = Bundle.main.url(forResource: "pack",
                                     withExtension: "json",
                                     subdirectory: "emoji/star-orbit"),
           let data = try? Data(contentsOf: url),
            let payload = try? JSONDecoder().decode(StickerCatalogPayload.self, from: data) {
            merge(payload)
            StickerLib.removeBundledStarPackIfNeeded()
            didLoad = true
        }

        if let url = API.shared.assetURL("emoji/packs.json"),
           let data = try? await API.shared.assetData(url),
           let payload = try? JSONDecoder().decode(StickerCatalogPayload.self, from: data) {
            merge(payload)
            didLoad = true
        }

        // Keep first-party packs in a separate catalog so deploying them can never
        // overwrite the existing live sticker catalog.
        if let url = API.shared.assetURL("emoji/star-orbit/pack.json"),
           let data = try? await API.shared.assetData(url),
           let payload = try? JSONDecoder().decode(StickerCatalogPayload.self, from: data) {
            merge(payload)
            didLoad = true
        }

        loaded = didLoad
    }

    private func merge(_ payload: StickerCatalogPayload) {
        for category in payload.categories ?? [] where !categories.contains(where: { $0.id == category.id }) {
            categories.append(category)
        }
        for pack in payload.packs ?? []
            where pack.id != "star-orbit-daily"
            && !packs.contains(where: { $0.id == pack.id }) {
            packs.append(pack)
        }
    }

    func packs(in category: String) -> [RemoteStickerPack] {
        packs.filter { $0.category == category }
    }

    func search(_ keyword: String) -> [RemoteStickerPack] {
        let k = keyword.trimmingCharacters(in: .whitespaces)
        guard !k.isEmpty else { return packs }
        return packs.filter { $0.name.localizedCaseInsensitiveContains(k) }
    }
}

struct PanelPack: Identifiable {
    let id: String
    let name: String

    let icon: String

    let stickers: [String]
    let isImage: Bool
}
