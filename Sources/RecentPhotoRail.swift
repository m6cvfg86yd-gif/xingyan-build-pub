import Photos
import SwiftUI
import UIKit

@MainActor
final class RecentPhotoStore: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    static let shared = RecentPhotoStore()

    @Published private(set) var assets: [PHAsset] = []
    @Published private(set) var isLoading = false
    @Published private(set) var accessState =
        PHPhotoLibrary.authorizationStatus(for: .readWrite)

    private let manager = PHCachingImageManager()
    private let thumbCache = NSCache<NSString, UIImage>()
    private var loaded = false
    private var reloadTask: Task<Void, Never>?

    private override init() {
        super.init()
        PHPhotoLibrary.shared().register(self)
    }

    func loadIfNeeded(force: Bool = false, requestAccess: Bool = false) async {
        guard !isLoading, force || !loaded else { return }
        isLoading = true
        defer { isLoading = false }
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        accessState = status
        switch status {
        case .authorized, .limited:
            await reloadAssets()
            loaded = true
        case .notDetermined:
            guard requestAccess else {
                assets = []
                loaded = false
                return
            }
            let next = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            accessState = next
            if next == .authorized || next == .limited {
                await reloadAssets()
                loaded = true
            } else {
                loaded = false
            }
        default:
            assets = []
            loaded = false
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
                // 很多 iCloud / HEIC 照片会先给一张低清图，再等待数秒才给高清图。
                // 先把低清图交出去，行里立刻有内容；下一次任务命中缓存时会继续更新。
                if degraded, let image {
                    resumed = true
                    continuation.resume(returning: image)
                    return
                }
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

        let image: UIImage? = await withCheckedContinuation { continuation in
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
        if let image { return image }

        let dataOptions = PHImageRequestOptions()
        dataOptions.version = .current
        dataOptions.deliveryMode = .highQualityFormat
        dataOptions.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            manager.requestImageDataAndOrientation(for: asset,
                                                   options: dataOptions) { data, _, _, _ in
                continuation.resume(returning: data.flatMap { UIImage(data: $0) })
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

/// 输入框上方的紧凑照片条。只显示照片本身，不再重复标题或玻璃边框。
struct ChatRecentPhotoStrip: View {
    @ObservedObject var store: RecentPhotoStore
    var onPick: (UIImage) -> Void
    var onOpenLibrary: () -> Void

    @State private var loadingId = ""
    private let tile: CGFloat = 54

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 5) {
                Button(action: onOpenLibrary) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.065))
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Color.primary.opacity(0.72))
                    }
                    .frame(width: tile, height: tile)
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Tr("打开相册"))

                if store.isLoading && store.assets.isEmpty {
                    ForEach(0..<7, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.10))
                            .frame(width: tile, height: tile)
                    }
                } else if store.assets.isEmpty {
                    if store.accessState == .denied || store.accessState == .restricted {
                        Button(action: openPhotoSettings) {
                            HStack(spacing: 9) {
                                Image(systemName: "lock.shield.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(Color.primary.opacity(0.64))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Tr("照片访问已关闭"))
                                        .font(.system(size: 12.5, weight: .semibold))
                                        .foregroundStyle(Color.primary.opacity(0.82))
                                    Text(Tr("去系统设置允许"))
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(Color.primary.opacity(0.48))
                                }
                            }
                            .padding(.horizontal, 12)
                            .frame(height: tile)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.primary.opacity(0.075))
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Tr("照片访问已关闭，去系统设置允许"))
                    } else if store.accessState == .limited {
                        Button(action: presentLimitedLibraryPicker) {
                            HStack(spacing: 9) {
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(Color.primary.opacity(0.64))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Tr("选择可访问照片"))
                                        .font(.system(size: 12.5, weight: .semibold))
                                        .foregroundStyle(Color.primary.opacity(0.82))
                                    Text(Tr("仅显示你在系统中选中的照片"))
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(Color.primary.opacity(0.48))
                                }
                            }
                            .padding(.horizontal, 12)
                            .frame(height: tile)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.primary.opacity(0.075))
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Tr("选择可访问照片"))
                    } else {
                        ForEach(0..<5, id: \.self) { _ in
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.primary.opacity(0.075))
                                Image(systemName: "photo")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Color.primary.opacity(0.38))
                            }
                            .frame(width: tile, height: tile)
                        }
                    }
                } else {
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
                        .accessibilityLabel(Tr("照片"))
                    }
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: tile + 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await store.loadIfNeeded(requestAccess: true) }
    }

    private func openPhotoSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func presentLimitedLibraryPicker() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              var top = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
                ?? scene.windows.first?.rootViewController else { return }
        while let presented = top.presentedViewController {
            top = presented
        }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: top)
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
                ZStack {
                    LinearGradient(
                        colors: [
                            Color.primary.opacity(0.10),
                            Color.primary.opacity(0.045)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "photo.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.34))
                }
            }
        }
        .task(id: asset.localIdentifier) {
            image = await store.thumbnail(for: asset, side: side)
        }
    }
}
