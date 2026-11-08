import Foundation

extension Notification.Name {
    static let chrisStickersChanged = Notification.Name("chris.stickersChanged")
}

enum StickerLib {
    private static let key = "sticker.installed.builtin"

    static var ids: [String] {
        get { (UserDefaults.standard.array(forKey: key) as? [String]) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func isIn(_ id: String) -> Bool { ids.contains(id) }

    static func add(_ id: String) {
        var list = ids
        if !list.contains(id) { list.append(id) }
        ids = list
    }

    static func remove(_ id: String) {
        ids = ids.filter { $0 != id }
    }

    static func toggle(_ id: String) {
        if isIn(id) { remove(id) } else { add(id) }
    }

    static var mine: [BuiltinPack] {
        let order = ids
        return order.compactMap { id in BuiltinPacks.all.first(where: { $0.id == id }) }
    }

    static var shop: [BuiltinPack] {
        BuiltinPacks.all.filter { !isIn($0.id) }
    }

    private static let remoteKey = "sticker.installed.remote"
    private static let bundledStarRemovalKey = "sticker.starOrbit.removed.v2"

    static var remoteIds: [String] {
        get { (UserDefaults.standard.array(forKey: remoteKey) as? [String]) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: remoteKey) }
    }

    static func isRemoteIn(_ id: String) -> Bool { remoteIds.contains(id) }

    static func addRemote(_ id: String) {
        var list = remoteIds
        if !list.contains(id) { list.append(id) }
        remoteIds = list
    }

    static func removeRemote(_ id: String) {
        remoteIds = remoteIds.filter { $0 != id }
    }

    static func removeBundledStarPackIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: bundledStarRemovalKey) else { return }
        removeRemote("star-orbit-daily")
        UserDefaults.standard.set(true, forKey: bundledStarRemovalKey)
    }

}
