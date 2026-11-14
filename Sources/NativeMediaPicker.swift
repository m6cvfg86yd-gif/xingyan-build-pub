import AVFoundation
import Photos
import SwiftUI
import UIKit

struct NativeMediaPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    var onVideo: (URL) -> Void
    var onLive: (UIImage, URL) -> Void
    var maxImages = 1
    var videosOnly = false
    var onImages: (([UIImage]) -> Void)?
    var onNotice: ((String) -> Void)?

    func makeUIViewController(context: Context) -> UINavigationController {
        let grid = NativeMediaGridController()
        grid.maxImages = max(1, maxImages)
        grid.videosOnly = videosOnly
        grid.onImage = onImage
        grid.onVideo = onVideo
        grid.onLive = onLive
        grid.onImages = onImages
        grid.onNotice = onNotice
        let nav = UINavigationController(rootViewController: grid)
        nav.modalPresentationStyle = .fullScreen
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController,
                                context: Context) { }
}

private final class NativeMediaGridController: UIViewController,
    UICollectionViewDataSource, UICollectionViewDelegate, PHPhotoLibraryChangeObserver {

    var maxImages = 1
    var videosOnly = false
    var onImage: ((UIImage) -> Void)!
    var onVideo: ((URL) -> Void)!
    var onLive: ((UIImage, URL) -> Void)!
    var onImages: (([UIImage]) -> Void)?
    var onNotice: ((String) -> Void)?

    private let manager = PHCachingImageManager()
    private var assets: [PHAsset] = []
    private var selected: [PHAsset] = []
    private var collection: UICollectionView!
    private var doneItem: UIBarButtonItem!
    private var loading = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = Tr("照片")

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancel)
        )
        doneItem = UIBarButtonItem(
            title: Tr("添加"),
            style: .done,
            target: self,
            action: #selector(done)
        )
        navigationItem.rightBarButtonItem = doneItem
        doneItem.isEnabled = false

        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 2
        layout.minimumLineSpacing = 2
        layout.sectionInset = UIEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)
        collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collection.backgroundColor = .systemBackground
        collection.dataSource = self
        collection.delegate = self
        collection.allowsMultipleSelection = maxImages > 1
        collection.register(NativeMediaCell.self,
                            forCellWithReuseIdentifier: NativeMediaCell.reuseID)
        view.addSubview(collection)
        collection.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            collection.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collection.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collection.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collection.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        PHPhotoLibrary.shared().register(self)
        requestAccessAndLoad()
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let layout = collection.collectionViewLayout as? UICollectionViewFlowLayout else { return }
        let columns: CGFloat = 4
        let totalGap = layout.minimumInteritemSpacing * (columns - 1)
            + layout.sectionInset.left + layout.sectionInset.right
        let side = floor((view.bounds.width - totalGap) / columns)
        if layout.itemSize.width != side {
            layout.itemSize = CGSize(width: side, height: side)
            layout.invalidateLayout()
        }
    }

    private func requestAccessAndLoad() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            reloadAssets()
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] next in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if next == .authorized || next == .limited {
                        self.reloadAssets()
                    } else {
                        self.showPermissionError()
                    }
                }
            }
        default:
            showPermissionError()
        }
    }

    private func reloadAssets() {
        let options = PHFetchOptions()
        options.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: false)
        ]
        options.predicate = videosOnly
            ? NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
            : NSPredicate(format: "mediaType == %d OR mediaType == %d",
                          PHAssetMediaType.image.rawValue,
                          PHAssetMediaType.video.rawValue)
        let result = PHAsset.fetchAssets(with: options)
        var rows: [PHAsset] = []
        rows.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in rows.append(asset) }
        assets = rows
        collection.reloadData()
        warmThumbnails()
    }

    private func warmThumbnails() {
        let side = max(120, (view.bounds.width / 4) * UIScreen.main.scale)
        manager.startCachingImages(
            for: assets,
            targetSize: CGSize(width: side, height: side),
            contentMode: .aspectFill,
            options: thumbnailOptions(network: false)
        )
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.main.async { [weak self] in
            self?.reloadAssets()
        }
    }

    private func thumbnailOptions(network: Bool) -> PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = network
        return options
    }

    func collectionView(_ collectionView: UICollectionView,
                        numberOfItemsInSection section: Int) -> Int {
        assets.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: NativeMediaCell.reuseID,
            for: indexPath
        ) as! NativeMediaCell
        let asset = assets[indexPath.item]
        cell.configure(asset: asset,
                       manager: manager,
                       order: selected.firstIndex(where: { $0.localIdentifier == asset.localIdentifier })
                        .map { $0 + 1 } ?? 0)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView,
                        didSelectItemAt indexPath: IndexPath) {
        let asset = assets[indexPath.item]
        if maxImages == 1 {
            selected = [asset]
        } else if let index = selected.firstIndex(where: {
            $0.localIdentifier == asset.localIdentifier
        }) {
            selected.remove(at: index)
        } else if selected.count < maxImages {
            selected.append(asset)
        } else {
            onNotice?(Tr("最多选择 \(maxImages) 张"))
            collectionView.deselectItem(at: indexPath, animated: true)
            return
        }
        updateDone()
        collectionView.reloadData()
    }

    func collectionView(_ collectionView: UICollectionView,
                        didDeselectItemAt indexPath: IndexPath) {
        let id = assets[indexPath.item].localIdentifier
        selected.removeAll { $0.localIdentifier == id }
        updateDone()
    }

    private func updateDone() {
        doneItem.isEnabled = !selected.isEmpty
        title = selected.isEmpty ? Tr("照片") : "\(Tr("已选择")) \(selected.count)"
    }

    @objc private func cancel() {
        dismiss(animated: true)
    }

    @objc private func done() {
        guard !selected.isEmpty, !loading else { return }
        loading = true
        doneItem.isEnabled = false
        let chosen = selected
        let liveCount = chosen.filter {
            $0.mediaSubtypes.contains(.photoLive)
        }.count
        if chosen.count > 1, liveCount > 0 {
            onNotice?(Tr("多选时实况会作为静态照片发送；想保留动效请单张选择"))
        }

        if chosen.count > 1 {
            loadImages(chosen) { [weak self] images in
                guard let self else { return }
                self.loading = false
                guard !images.isEmpty else { self.updateDone(); return }
                self.dismiss(animated: true) {
                    if let multi = self.onImages {
                        multi(images)
                    } else if let first = images.first {
                        self.onImage(first)
                    }
                }
            }
            return
        }

        guard let asset = chosen.first else { return }
        if asset.mediaType == .video {
            loadVideo(asset) { [weak self] url in
                guard let self else { return }
                self.loading = false
                guard let url else {
                    self.updateDone()
                    self.onNotice?(Tr("视频读取失败"))
                    return
                }
                self.dismiss(animated: true) { self.onVideo(url) }
            }
            return
        }

        if asset.mediaSubtypes.contains(.photoLive) {
            loadImage(asset) { [weak self] image in
                guard let self, let image else {
                    self?.loading = false
                    self?.updateDone()
                    return
                }
                self.loadLiveMovie(asset) { [weak self] url in
                    guard let self else { return }
                    self.loading = false
                    self.dismiss(animated: true) {
                        if let url {
                            self.onLive(image, url)
                        } else {
                            self.onImage(image)
                        }
                    }
                }
            }
            return
        }

        loadImage(asset) { [weak self] image in
            guard let self else { return }
            self.loading = false
            guard let image else {
                self.updateDone()
                self.onNotice?(Tr("照片读取失败"))
                return
            }
            self.dismiss(animated: true) { self.onImage(image) }
        }
    }

    private func loadImages(_ list: [PHAsset], done: @escaping ([UIImage]) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var images: [UIImage] = []
        for asset in list where asset.mediaType == .image {
            group.enter()
            loadImage(asset) { image in
                if let image {
                    lock.lock(); images.append(image); lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { done(images) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { done(images) }
    }

    private func loadImage(_ asset: PHAsset, done: @escaping (UIImage?) -> Void) {
        let side = max(1600, max(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
            * UIScreen.main.scale)
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        manager.requestImage(
            for: asset,
            targetSize: CGSize(width: side, height: side),
            contentMode: .aspectFit,
            options: options
        ) { image, info in
            if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
            DispatchQueue.main.async { done(image) }
        }
    }

    private func loadLiveMovie(_ asset: PHAsset, done: @escaping (URL?) -> Void) {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let video = resources.first(where: {
            $0.type == .fullSizeVideo || $0.type == .pairedVideo
        }) else {
            done(nil)
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("live-\(UUID().uuidString).mov")
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        PHAssetResourceManager.default().writeData(
            for: video,
            toFile: url,
            options: options
        ) { error in
            DispatchQueue.main.async {
                done(error == nil && FileManager.default.fileExists(atPath: url.path) ? url : nil)
            }
        }
    }

    private func loadVideo(_ asset: PHAsset, done: @escaping (URL?) -> Void) {
        let options = PHVideoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        manager.requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
            guard let avAsset else {
                DispatchQueue.main.async { done(nil) }
                return
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("media-\(UUID().uuidString).mov")
            guard let export = AVAssetExportSession(
                asset: avAsset,
                presetName: AVAssetExportPresetHighestQuality
            ) else {
                DispatchQueue.main.async { done(nil) }
                return
            }
            export.outputURL = url
            export.outputFileType = .mov
            export.shouldOptimizeForNetworkUse = true
            export.exportAsynchronously {
                DispatchQueue.main.async {
                    done(export.status == .completed ? url : nil)
                }
            }
        }
    }

    private func showPermissionError() {
        let alert = UIAlertController(
            title: Tr("无法读取照片"),
            message: Tr("请到系统设置里允许星言访问照片"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: Tr("取消"), style: .cancel) { [weak self] _ in
            self?.dismiss(animated: true)
        })
        alert.addAction(UIAlertAction(title: Tr("打开设置"), style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        present(alert, animated: true)
    }
}

private final class NativeMediaCell: UICollectionViewCell {
    static let reuseID = "NativeMediaCell"

    private let imageView = UIImageView()
    private let liveBadge = UIView()
    private let liveIcon = UIImageView()
    private let liveLabel = UILabel()
    private let duration = UILabel()
    private let selection = UILabel()
    private let dim = UIView()
    private var represented = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .secondarySystemBackground
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        contentView.addSubview(imageView)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        liveBadge.backgroundColor = UIColor.black.withAlphaComponent(0.40)
        liveBadge.layer.cornerRadius = 10
        liveBadge.layer.cornerCurve = .continuous
        liveBadge.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(liveBadge)

        liveIcon.image = UIImage(systemName: "livephoto")?
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        liveIcon.contentMode = .scaleAspectFit
        liveIcon.translatesAutoresizingMaskIntoConstraints = false
        liveBadge.addSubview(liveIcon)

        liveLabel.text = "LIVE"
        liveLabel.textColor = .white
        liveLabel.font = .systemFont(ofSize: 9, weight: .bold)
        liveLabel.translatesAutoresizingMaskIntoConstraints = false
        liveBadge.addSubview(liveLabel)

        duration.textColor = .white
        duration.font = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        duration.textAlignment = .right
        duration.translatesAutoresizingMaskIntoConstraints = false
        duration.layer.shadowColor = UIColor.black.cgColor
        duration.layer.shadowOpacity = 0.55
        duration.layer.shadowRadius = 2
        duration.layer.shadowOffset = CGSize(width: 0, height: 1)
        contentView.addSubview(duration)

        selection.textColor = .white
        selection.font = .systemFont(ofSize: 11, weight: .bold)
        selection.textAlignment = .center
        selection.backgroundColor = UIColor.systemBlue
        selection.layer.cornerRadius = 11
        selection.layer.borderWidth = 1.5
        selection.layer.borderColor = UIColor.white.cgColor
        selection.clipsToBounds = true
        selection.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(selection)

        dim.backgroundColor = UIColor.black.withAlphaComponent(0.20)
        dim.isUserInteractionEnabled = false
        dim.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(dim)

        NSLayoutConstraint.activate([
            liveBadge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            liveBadge.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 5),
            liveBadge.heightAnchor.constraint(equalToConstant: 20),
            liveIcon.leadingAnchor.constraint(equalTo: liveBadge.leadingAnchor, constant: 5),
            liveIcon.centerYAnchor.constraint(equalTo: liveBadge.centerYAnchor),
            liveIcon.widthAnchor.constraint(equalToConstant: 11),
            liveIcon.heightAnchor.constraint(equalToConstant: 11),
            liveLabel.leadingAnchor.constraint(equalTo: liveIcon.trailingAnchor, constant: 3),
            liveLabel.trailingAnchor.constraint(equalTo: liveBadge.trailingAnchor, constant: -6),
            liveLabel.centerYAnchor.constraint(equalTo: liveBadge.centerYAnchor),
            duration.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),
            duration.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5),
            selection.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            selection.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -5),
            selection.widthAnchor.constraint(equalToConstant: 22),
            selection.heightAnchor.constraint(equalToConstant: 22),
            dim.topAnchor.constraint(equalTo: contentView.topAnchor),
            dim.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            dim.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            dim.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(asset: PHAsset,
                   manager: PHCachingImageManager,
                   order: Int) {
        represented = asset.localIdentifier
        imageView.image = nil
        manager.requestImage(
            for: asset,
            targetSize: CGSize(width: cellSide * UIScreen.main.scale,
                               height: cellSide * UIScreen.main.scale),
            contentMode: .aspectFill,
            options: {
                let options = PHImageRequestOptions()
                options.deliveryMode = .opportunistic
                options.resizeMode = .fast
                options.isNetworkAccessAllowed = true
                return options
            }()
        ) { [weak self] image, _ in
            guard let self, self.represented == asset.localIdentifier else { return }
            DispatchQueue.main.async {
                guard self.represented == asset.localIdentifier else { return }
                self.imageView.image = image
            }
        }
        liveBadge.isHidden = !asset.mediaSubtypes.contains(.photoLive)
        if asset.mediaType == .video {
            let seconds = Int(asset.duration.rounded())
            duration.text = String(format: "%d:%02d", seconds / 60, seconds % 60)
            duration.isHidden = false
        } else {
            duration.isHidden = true
        }
        selection.text = order > 0 ? "\(order)" : ""
        selection.isHidden = order == 0
        dim.isHidden = order == 0
    }

    private var cellSide: CGFloat {
        max(64, UIScreen.main.bounds.width / 4)
    }
}
