import Photos
import SwiftUI
import UIKit

@MainActor
final class RecentPhotoStore: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    static let shared = RecentPhotoStore()

    @Published private(set) var assets: [PHAsset] = []

    private let manager = PHCachingImageManager()
    private let thumbCache = NSCache<NSString, UIImage>()
    private var loaded = false
    private var reloadTask: Task<Void, Never>?

    private override init() {
        super.init()
        PHPhotoLibrary.shared().register(self)
    }

    func loadIfNeeded() async {
        guard !loaded else { return }
        loaded = true
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            await reloadAssets()
        case .notDetermined:
            let next = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            if next == .authorized || next == .limited { await reloadAssets() }
        default:
            break
        }
    }

    func thumbnail(for asset: PHAsset, side: CGFloat) async -> UIImage? {
        let pixelSide = max(96, side * UIScreen.main.scale)
        let key = "\(asset.localIdentifier)#\(Int(pixelSide))" as NSString
        if let hit = thumbCache.object(forKey: key) { return hit }

        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        let size = CGSize(width: pixelSide, height: pixelSide)

        let image: UIImage? = await withCheckedContinuation { continuation in
            var resumed = false
            manager.requestImage(for: asset,
                                 targetSize: size,
                                 contentMode: .aspectFill,
                                 options: options) { image, info in
                guard !resumed else { return }
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
                if degraded, image != nil { return }
                resumed = true
                continuation.resume(returning: image)
            }
        }
        if let image { thumbCache.setObject(image, forKey: key) }
        return image
    }

    func preview(for asset: PHAsset) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        let bounds = UIScreen.main.bounds
        let nativeSide = max(bounds.width, bounds.height) * UIScreen.main.scale
        let side = min(2400, max(1200, nativeSide))

        return await withCheckedContinuation { continuation in
            var resumed = false
            manager.requestImage(for: asset,
                                 targetSize: CGSize(width: side, height: side),
                                 contentMode: .aspectFit,
                                 options: options) { image, info in
                guard !resumed else { return }
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
                if degraded, image != nil { return }
                resumed = true
                continuation.resume(returning: image)
            }
        }
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            reloadTask?.cancel()
            reloadTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 180_000_000)
                guard !Task.isCancelled else { return }
                await self?.reloadAssets()
            }
        }
    }

    private func reloadAssets() async {
        let rows = await Task.detached(priority: .userInitiated) {
            Self.fetchRecentAssets()
        }.value
        guard !Task.isCancelled else { return }
        assets = rows
    }

    nonisolated private static func fetchRecentAssets() -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: false)
        ]
        options.fetchLimit = 100
        let result = PHAsset.fetchAssets(with: .image, options: options)
        var rows: [PHAsset] = []
        rows.reserveCapacity(min(60, result.count))
        result.enumerateObjects { asset, index, stop in
            rows.append(asset)
            if rows.count >= 60 || index + 1 >= result.count { stop.pointee = true }
        }
        return rows
    }
}

struct RecentPhotoRail: View {
    @ObservedObject var store: RecentPhotoStore
    var onPick: (UIImage) -> Void

    @State private var loadingId = ""
    private let tile: CGFloat = 58

    var body: some View {
        if !store.assets.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(Tr("最近照片"))
                        .font(pf(13, .semibold))
                        .foregroundColor(C.label)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 6) {
                        ForEach(store.assets, id: \.localIdentifier) { asset in
                            Button {
                                guard loadingId.isEmpty else { return }
                                loadingId = asset.localIdentifier
                                Task {
                                    let image = await store.preview(for: asset)
                                    loadingId = ""
                                    if let image { onPick(image) }
                                }
                            } label: {
                                ZStack {
                                    RecentAssetThumbnail(asset: asset,
                                                         store: store,
                                                         side: tile)
                                    if loadingId == asset.localIdentifier {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(Color.black.opacity(0.34))
                                        ProgressView()
                                            .tint(.white)
                                    }
                                }
                                .frame(width: tile, height: tile)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 10)
            .task { await store.loadIfNeeded() }
        }
    }
}

/// 输入框上方的紧凑照片条。只显示照片本身，不再重复标题或玻璃边框。
struct ChatRecentPhotoStrip: View {
    @ObservedObject var store: RecentPhotoStore
    var onPick: (UIImage) -> Void

    @State private var loadingId = ""
    private let tile: CGFloat = 54

    var body: some View {
        Group {
            if !store.assets.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 5) {
                        ForEach(store.assets, id: \.localIdentifier) { asset in
                            Button {
                                guard loadingId.isEmpty else { return }
                                loadingId = asset.localIdentifier
                                Task {
                                    let image = await store.preview(for: asset)
                                    loadingId = ""
                                    if let image { onPick(image) }
                                }
                            } label: {
                                ZStack {
                                    RecentAssetThumbnail(asset: asset, store: store, side: tile)
                                    if loadingId == asset.localIdentifier {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(Color.black.opacity(0.34))
                                        ProgressView().tint(.white)
                                    }
                                }
                                .frame(width: tile, height: tile)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Tr("最近照片"))
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.vertical, 7)
            }
        }
        .task { await store.loadIfNeeded() }
    }
}

private struct RecentAssetThumbnail: View {
    let asset: PHAsset
    @ObservedObject var store: RecentPhotoStore
    let side: CGFloat

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.dyn(0xE9E9E9, 0x242426)
            }
        }
        .task(id: asset.localIdentifier) {
            image = await store.thumbnail(for: asset, side: side)
        }
    }
}
