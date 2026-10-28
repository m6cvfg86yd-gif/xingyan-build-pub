import SwiftUI
import UIKit
import PhotosUI
import Photos
import UniformTypeIdentifiers
import AVFoundation

final class MultiPick {
    private let lock = NSLock()
    private var imgs: [UIImage?]
    private var done = false

    init(count: Int) { imgs = [UIImage?](repeating: nil, count: count) }

    func put(_ img: UIImage?, at i: Int) {
        lock.lock()
        if i >= 0, i < imgs.count { imgs[i] = img }
        lock.unlock()
    }

    func take() -> [UIImage]? {
        lock.lock(); defer { lock.unlock() }
        if done { return nil }
        done = true
        return imgs.compactMap { $0 }
    }
}

struct MediaPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    var onVideo: (URL) -> Void
    var onLive: (UIImage, URL) -> Void

    var videosOnly: Bool = false

    var maxImages: Int = 1

    var onImages: (([UIImage]) -> Void)? = nil

    var onNotice: ((String) -> Void)? = nil

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var cfg = PHPickerConfiguration(photoLibrary: .shared())
        cfg.filter = videosOnly ? .videos : .any(of: [.images, .videos, .livePhotos])
        cfg.selectionLimit = videosOnly ? 1 : max(1, maxImages)
        cfg.preferredAssetRepresentationMode = .current
        let vc = PHPickerViewController(configuration: cfg)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) { }
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let parent: MediaPicker
        init(_ p: MediaPicker) { parent = p }

        private static let liveBundleType = "com.apple.live-photo-bundle"

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            if results.count > 1 {
                let group = DispatchGroup()
                let box = MultiPick(count: results.count)
                CrashCatcher.note("选图", "一次选了 \(results.count) 张")

                let liveCount = results.filter {
                    $0.itemProvider.hasItemConformingToTypeIdentifier(Self.liveBundleType)
                        || $0.itemProvider.hasItemConformingToTypeIdentifier(UTType.livePhoto.identifier)
                }.count
                if liveCount > 0 {
                    CrashCatcher.note("选图", "多选里含 \(liveCount) 张实况（多选只能当静图发）")
                    DispatchQueue.main.async {
                        self.parent.onNotice?(liveCount == results.count
                            ? "实况照片一次只能发一张：想发动效就单张选，多选会按静态图发"
                            : "里面有 \(liveCount) 张实况：多选会按静态图发，想发动效请单张选")
                    }
                }

                for (i, r) in results.enumerated() {
                    let p = r.itemProvider
                    guard p.canLoadObject(ofClass: UIImage.self) else { continue }
                    group.enter()
                    loadImage(p) { img in
                        box.put(img, at: i)
                        group.leave()
                    }
                }

                let deliver = {
                    guard let list = box.take() else { return }
                    CrashCatcher.note("选图", "拿到 \(list.count) 张，交给发送")
                    guard !list.isEmpty else { return }
                    if list.count > 1, let multi = self.parent.onImages {
                        multi(list)
                    } else if let one = list.first {
                        self.parent.onImage(one)
                    }
                }
                group.notify(queue: .main, execute: deliver)

                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: deliver)
                return
            }
            guard let provider = results.first?.itemProvider else { return }
            let hasMovie = provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
            let hasImage = provider.canLoadObject(ofClass: UIImage.self) ||
                provider.hasItemConformingToTypeIdentifier(UTType.image.identifier)

            let isLive = provider.hasItemConformingToTypeIdentifier(Self.liveBundleType)
                || provider.hasItemConformingToTypeIdentifier(UTType.livePhoto.identifier)

                || provider.registeredTypeIdentifiers.contains { $0.lowercased().contains("live") }

            CrashCatcher.note("选图",
                "types=[\(provider.registeredTypeIdentifiers.joined(separator: ","))]"
                + " live=\(isLive) movie=\(hasMovie) image=\(hasImage)"
                + " hasBundle=\(provider.hasItemConformingToTypeIdentifier(Self.liveBundleType))"
                + " hasLiveType=\(provider.hasItemConformingToTypeIdentifier(UTType.livePhoto.identifier))")

            if isLive || (hasMovie && hasImage) {
                loadImage(provider) { img in
                    guard let img = img else {
                        CrashCatcher.note("实况", "静态图没取到，放弃")
                        return
                    }
                    self.loadLiveMovie(provider) { url in
                        if let url = url {
                            CrashCatcher.note("实况", "动效取到了：\(url.lastPathComponent)")
                            DispatchQueue.main.async { self.parent.onLive(img, url) }
                            return
                        }

                        CrashCatcher.note("实况", "PHPicker 没给动效 → 试 PHAsset 兜底")
                        self.loadLiveViaAsset(results.first?.assetIdentifier) { url2 in
                            if let url2 = url2 {
                                DispatchQueue.main.async { self.parent.onLive(img, url2) }
                            } else {
                                CrashCatcher.note("实况", "兜底也没拿到 → 退回发静态图")
                                DispatchQueue.main.async { self.parent.onImage(img) }
                            }
                        }
                    }
                }
                return
            }

            if hasMovie {
                loadMovie(provider) { url in
                    guard let url = url else { return }
                    DispatchQueue.main.async { self.parent.onVideo(url) }
                }
                return
            }

            loadImage(provider) { img in
                guard let img = img else { return }
                DispatchQueue.main.async { self.parent.onImage(img) }
            }
        }

        private func loadImage(_ p: NSItemProvider, _ done: @escaping (UIImage?) -> Void) {
            if p.canLoadObject(ofClass: UIImage.self) {
                p.loadObject(ofClass: UIImage.self) { obj, _ in done(obj as? UIImage) }
                return
            }
            p.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                done(data.flatMap { UIImage(data: $0) })
            }
        }

        private func loadMovie(_ p: NSItemProvider, _ done: @escaping (URL?) -> Void) {
            p.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, _ in
                guard let url = url else { done(nil); return }
                let dst = FileManager.default.temporaryDirectory
                    .appendingPathComponent("chris-video-\(UUID().uuidString).mov")
                do {
                    try? FileManager.default.removeItem(at: dst)
                    try FileManager.default.copyItem(at: url, to: dst)
                    done(dst)
                } catch { done(nil) }
            }
        }

        private func loadLiveMovie(_ p: NSItemProvider, _ done: @escaping (URL?) -> Void) {
            if p.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                loadMovie(p) { url in
                    if let url = url { done(url) } else { self.loadLiveBundle(p, done) }
                }
                return
            }
            loadLiveBundle(p, done)
        }

        private func loadLiveBundle(_ p: NSItemProvider, _ done: @escaping (URL?) -> Void) {
            let type: String
            if p.hasItemConformingToTypeIdentifier(Self.liveBundleType) {
                type = Self.liveBundleType
            } else if p.hasItemConformingToTypeIdentifier(UTType.livePhoto.identifier) {
                type = UTType.livePhoto.identifier
            } else {
                done(nil); return
            }
            p.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
                guard let url = url else {
                    CrashCatcher.note("实况", "loadFileRepresentation 没给 url（type=\(type)）")
                    done(nil); return
                }

                var src: URL? = nil
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    let items = (try? FileManager.default.contentsOfDirectory(
                        at: url, includingPropertiesForKeys: nil)) ?? []
                    src = items.first { ["mov", "mp4", "m4v"].contains($0.pathExtension.lowercased()) }
                } else if ["mov", "mp4", "m4v"].contains(url.pathExtension.lowercased()) {
                    src = url
                }
                guard let from = src else {
                    CrashCatcher.note("实况", "包里没找到视频：\(url.lastPathComponent)")
                    done(nil); return
                }
                let dst = FileManager.default.temporaryDirectory
                    .appendingPathComponent("chris-live-\(UUID().uuidString).mov")
                do {
                    try? FileManager.default.removeItem(at: dst)
                    try FileManager.default.copyItem(at: from, to: dst)
                    done(dst)
                } catch { done(nil) }
            }
        }

        private func loadLiveViaAsset(_ assetId: String?, _ done: @escaping (URL?) -> Void) {
            guard let assetId = assetId, !assetId.isEmpty else { done(nil); return }
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            guard status == .authorized || status == .limited else {

                CrashCatcher.note("实况", "相册未授权，PHAsset 兜底跳过（status=\(status.rawValue)）")
                done(nil); return
            }
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil).firstObject else {
                CrashCatcher.note("实况", "PHAsset 按 id 找不到资源")
                done(nil); return
            }
            let resources = PHAssetResource.assetResources(for: asset)
            guard let video = resources.first(where: { $0.type == .fullSizeVideo || $0.type == .video }) else {
                CrashCatcher.note("实况", "PHAsset 里没有视频资源（只有 \(resources.count) 个资源）")
                done(nil); return
            }
            let dst = FileManager.default.temporaryDirectory
                .appendingPathComponent("chris-live-\(UUID().uuidString).mov")
            try? FileManager.default.removeItem(at: dst)
            let opts = PHAssetResourceRequestOptions()
            opts.isNetworkAccessAllowed = true
            PHAssetResourceManager.default().writeData(for: video, toFile: dst, options: opts) { err in
                if err == nil, FileManager.default.fileExists(atPath: dst.path) {
                    CrashCatcher.note("实况", "PHAsset 兜底成功（type=\(video.type.rawValue)）")
                    done(dst)
                } else {
                    CrashCatcher.note("实况", "PHAsset 兜底失败：\(err?.localizedDescription ?? "未知错误")")
                    done(nil)
                }
            }
        }
    }
}

enum MomentPickResult {
    case images([UIImage])
    case video(URL)
}

struct MomentPicker: UIViewControllerRepresentable {

    var limit: Int = 9
    var onResult: (MomentPickResult) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var cfg = PHPickerConfiguration(photoLibrary: .shared())
        cfg.filter = .any(of: [.images, .videos])
        cfg.selectionLimit = max(1, limit)
        cfg.preferredAssetRepresentationMode = .current
        let vc = PHPickerViewController(configuration: cfg)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) { }
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let parent: MomentPicker
        init(_ p: MomentPicker) { parent = p }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard !results.isEmpty else { return }

            let movie = results.first { r in
                let p = r.itemProvider
                return p.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
                    && !p.hasItemConformingToTypeIdentifier(UTType.livePhoto.identifier)
            }
            if let mv = movie {
                loadMovie(mv.itemProvider) { url in
                    guard let url = url else { return }
                    DispatchQueue.main.async { self.parent.onResult(.video(url)) }
                }
                return
            }
            loadImages(results) { imgs in
                guard !imgs.isEmpty else { return }
                DispatchQueue.main.async { self.parent.onResult(.images(imgs)) }
            }
        }

        private func loadImage(_ p: NSItemProvider, _ done: @escaping (UIImage?) -> Void) {
            if p.canLoadObject(ofClass: UIImage.self) {
                p.loadObject(ofClass: UIImage.self) { obj, _ in done(obj as? UIImage) }
                return
            }
            p.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                done(data.flatMap { UIImage(data: $0) })
            }
        }

        private func loadImages(_ results: [PHPickerResult], _ done: @escaping ([UIImage]) -> Void) {
            var out = [UIImage?](repeating: nil, count: results.count)
            let group = DispatchGroup()
            for (i, r) in results.enumerated() {
                group.enter()
                loadImage(r.itemProvider) { img in
                    out[i] = img
                    group.leave()
                }
            }
            group.notify(queue: .main) { done(out.compactMap { $0 }) }
        }

        private func loadMovie(_ p: NSItemProvider, _ done: @escaping (URL?) -> Void) {
            p.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, _ in
                guard let url = url else { done(nil); return }
                let dst = FileManager.default.temporaryDirectory
                    .appendingPathComponent("chris-moment-\(UUID().uuidString).mov")
                do {
                    try? FileManager.default.removeItem(at: dst)
                    try FileManager.default.copyItem(at: url, to: dst)
                    done(dst)
                } catch { done(nil) }
            }
        }
    }
}

enum MediaTool {

    static func upload(_ url: URL) async -> String? {
        let ext = url.pathExtension.lowercased()
        let mime = (ext == "mov") ? "video/quicktime" : "video/mp4"

        return try? await API.shared.uploadBinaryFile(url, mime: mime) { _ in }
    }

    static func upload(_ url: URL, onProgress: @escaping (Double) -> Void,
                       skipServerTranscode: Bool = false) async -> String? {
        let ext = url.pathExtension.lowercased()
        let mime = (ext == "mov") ? "video/quicktime" : "video/mp4"
        return try? await API.shared.uploadBinaryFile(url, mime: mime,
                                                     skipTranscode: skipServerTranscode,
                                                     onProgress: onProgress)
    }

    static func seconds(_ url: URL) async -> Int {
        let asset = AVURLAsset(url: url)
        let d = (try? await asset.load(.duration))?.seconds ?? 0
        return max(1, Int(d.rounded()))
    }

    static func aspect(_ url: URL) async -> (w: Int, h: Int)? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let sz = try? await track.load(.naturalSize),
              let tx = try? await track.load(.preferredTransform) else { return nil }
        let t = sz.applying(tx)
        let w = Int(abs(t.width).rounded())
        let h = Int(abs(t.height).rounded())
        guard w > 0, h > 0 else { return nil }
        return (w, h)
    }

    static func firstFrame(_ url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 720, height: 1280)
        guard let cg = try? await gen.image(at: CMTime(seconds: 0.2, preferredTimescale: 600)).image else { return nil }
        return UIImage(cgImage: cg)
    }

    static func needsCompress(_ url: URL) async -> Bool {
        let size = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? 0
        let asset = AVURLAsset(url: url)
        let secs = (try? await asset.load(.duration))?.seconds ?? 0
        var longSide = 0
        if let tracks = try? await asset.loadTracks(withMediaType: .video),
           let track = tracks.first,
           let sz = try? await track.load(.naturalSize) {
            longSide = Int(max(abs(sz.width), abs(sz.height)))
        }

        if size > 0, size <= 8 * 1024 * 1024,
           secs > 0, secs <= 60,
           longSide > 0, longSide <= 1280 {
            return false
        }
        return true
    }

    static func compress(_ url: URL, onProgress: ((Double) -> Void)? = nil) async -> URL? {
        let asset = AVURLAsset(url: url)
        guard let export = AVAssetExportSession(asset: asset,
                                                presetName: AVAssetExportPreset1280x720) else {
            return nil
        }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("chris-send-\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: out)
        export.outputURL = out
        export.outputFileType = .mp4
        export.shouldOptimizeForNetworkUse = true
        export.fileLengthLimit = 16 * 1024 * 1024

        let t0 = Date()
        let secs = (try? await asset.load(.duration))?.seconds ?? 10
        let guessSpan = max(1.5, min(60, secs * 0.5))
        let poll = Task {
            while !Task.isCancelled {
                let real = Double(export.progress)
                let elapsed = Date().timeIntervalSince(t0)
                let guess = min(0.95, elapsed / guessSpan)
                onProgress?(max(real, guess))
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously { cont.resume() }
        }
        poll.cancel()
        onProgress?(1)
        return export.status == .completed ? out : nil
    }
}

struct MediaSendSheet: View {
    enum Payload {
        case image(UIImage)

        case images([UIImage])
        case video(URL, UIImage?)
        case live(UIImage, URL)
    }

    let payload: Payload

    var onSend: (Bool, Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var liveOn = true
    @State private var originalOn = false

    private var isLive: Bool { if case .live = payload { return true }; return false }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                preview
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 12) {
                if isLive {
                    toggleRow(Tr("实况"), sub: Tr("打开后对方长按可以看这段动效（两边都是 iPhone 才有效）"), on: $liveOn)
                }
                toggleRow(Tr("原视频"),
                          sub: Tr("不压缩，画质最好但发送和加载都会慢很多"),
                          on: $originalOn)

                HStack(spacing: 12) {
                    Button { dismiss() } label: {
                        Text(Tr("取消"))
                            .font(.system(size: 16))
                            .foregroundColor(C.label)
                            .frame(maxWidth: .infinity).frame(height: 46)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.dyn(0xEFEFF1, 0x2C2C2E)))
                    }
                    .buttonStyle(.plain)

                    Button {
                        onSend(liveOn, originalOn)
                        dismiss()
                    } label: {
                        Text(Tr("发送"))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: 46)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(C.green))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .background(Color.dyn(0xFFFFFF, 0x1C1C1E))
        }
        .ignoresSafeArea(edges: .top)
    }

    @ViewBuilder
    private var preview: some View {
        switch payload {
        case .image(let img):
            Image(uiImage: img).resizable().scaledToFit()
        case .images(let list):

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3),
                          spacing: 3) {
                    ForEach(Array(list.enumerated()), id: \.offset) { _, img in
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 112)
                            .clipped()
                    }
                }
                .padding(10)
            }
        case .video(_, let cover):
            if let c = cover {
                Image(uiImage: c).resizable().scaledToFit()
                    .overlay(Image(systemName: "play.circle.fill").font(.system(size: 46)).foregroundColor(.white.opacity(0.9)))
            } else {
                Image(systemName: "video.fill").font(.system(size: 54)).foregroundColor(.white.opacity(0.8))
            }
        case .live(let img, _):
            Image(uiImage: img).resizable().scaledToFit()
                .overlay(alignment: .topLeading) {
                    Text(Tr("实况")).font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Color.black.opacity(0.45)))
                        .padding(12)
                }
        }
    }

    private func toggleRow(_ title: String, sub: String, on: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15)).foregroundColor(C.label)
                Text(sub).font(.system(size: 12)).foregroundColor(C.subLabel)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: on).labelsHidden()
        }
    }
}
