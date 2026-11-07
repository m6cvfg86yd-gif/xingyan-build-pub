import SwiftUI
import AVFoundation
import UIKit

struct FeedPlayerView: View {
    let items: [FeedItem]
    var start: Int = 0

    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var index: Int
    @State private var paused = false
    @State private var progress: Double = 0
    @State private var showHeart = false

    @State private var ui: [String: FeedItemUI] = [:]

    @State private var commentItem: FeedItem?

    @State private var shareItems: [Any] = []
    @State private var showShare = false

    init(items: [FeedItem], start: Int = 0) {
        self.items = items
        self.start = start
        _index = State(initialValue: max(0, min(start, max(0, items.count - 1))))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if items.isEmpty {
                Text(Tr("还没有视频")).foregroundColor(.white)
            } else {
                VerticalPager(index: $index, count: items.count) { i in
                    PlayerPage(item: items[i],
                               active: (i == index),
                               paused: paused,
                               ui: ui[items[i].id] ?? FeedItemUI(items[i]),
                               onTap: { paused.toggle() },
                               onDoubleTap: { like(items[i], fromDoubleTap: true) },
                               onLike: { like(items[i], fromDoubleTap: false) },
                               onComment: { commentItem = items[i] },
                               onFavorite: { favorite(items[i]) },
                               onShare: { share(items[i]) },
                               onFollow: { follow(items[i]) },
                               onAvatar: { openAuthor(items[i]) },
                               progress: (i == index) ? progress : 0)
                }
                .ignoresSafeArea()
            }

            if showHeart {
                Image(systemName: "heart.fill")
                    .font(.system(size: 120))
                    .foregroundColor(Color(hex: 0xFF2D55))
                    .shadow(color: .black.opacity(0.3), radius: 12)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                    .allowsHitTesting(false)
            }

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.black.opacity(0.28)))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                Spacer()
            }
        }
        .statusBarHidden(true)
        .onAppear { seed() }
        .sheet(item: $commentItem) { it in
            FeedCommentSheet(item: it) { n in
                if var s = ui[it.id] { s.comments = n; ui[it.id] = s }
            }
            .environmentObject(app)
            .presentationDetents([.fraction(0.64), .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showShare) { ShareSheet(items: shareItems) }
        .task(id: index) {

            let lo = max(0, index - 1), hi = min(items.count - 1, index + 1)
            if lo <= hi { PlayerPool.shared.keepOnly(Array(items[lo...hi]).map { $0.id }) }

            PlayerPool.shared.currentId = items[safe: index]?.id ?? ""
            await trackProgress()
        }
    }

    private func seed() {
        for it in items where ui[it.id] == nil { ui[it.id] = FeedItemUI(it) }
    }

    private func like(_ item: FeedItem, fromDoubleTap: Bool) {
        var s = ui[item.id] ?? FeedItemUI(item)

        if fromDoubleTap, s.liked { flashHeart(); return }
        let next = !s.liked
        s.liked = next
        s.likes = max(0, s.likes + (next ? 1 : -1))
        ui[item.id] = s
        if fromDoubleTap { flashHeart() }
        Task {
            if let r = try? await API.shared.feedLike(item.id), var cur = ui[item.id] {
                cur.liked = r.liked
                cur.likes = r.likes
                ui[item.id] = cur
            }
        }
    }

    private func flashHeart() {
        withAnimation(.spring(response: 0.26, dampingFraction: 0.55)) { showHeart = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            withAnimation(.easeOut(duration: 0.25)) { showHeart = false }
        }
    }

    private func favorite(_ item: FeedItem) {
        var s = ui[item.id] ?? FeedItemUI(item)
        s.favorited.toggle()
        s.favorites = max(0, s.favorites + (s.favorited ? 1 : -1))
        ui[item.id] = s
        Task {
            if let r = try? await API.shared.feedFavorite(item.id), var cur = ui[item.id] {
                cur.favorited = r.favorited
                cur.favorites = r.favorites
                ui[item.id] = cur
            }
        }
    }

    private func follow(_ item: FeedItem) {
        guard let uid = item.author?.id, !uid.isEmpty else { return }
        var s = ui[item.id] ?? FeedItemUI(item)
        s.followed.toggle()
        ui[item.id] = s
        Task {
            let ok = await API.shared.feedFollow(userId: uid, follow: s.followed)
            if !ok, var cur = ui[item.id] { cur.followed = !s.followed; ui[item.id] = cur }
        }
    }

    private func share(_ item: FeedItem) {
        var arr: [Any] = []
        if let d = item.desc, !d.isEmpty { arr.append(d) }
        if let u = URL(string: API.shared.base) { arr.append(u) }
        shareItems = arr.isEmpty ? ["视频号"] : arr
        showShare = true
    }

    private func openAuthor(_ item: FeedItem) {
        guard let uid = item.author?.id, !uid.isEmpty else { return }
        Task { @MainActor in
            if let u = try? await API.shared.user(id: uid) {
                app.scanCardUser = u
            } else if let n = item.author?.name, !n.isEmpty {
                app.show("@" + n)
            }
        }
    }

    private func trackProgress() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            progress = PlayerPool.shared.progress(of: items[safe: index]?.id ?? "")
        }
    }
}

struct FeedItemUI {
    var liked = false
    var likes = 0
    var comments = 0
    var favorites = 0
    var favorited = false
    var followed = false
    var authorName = ""
    var authorAvatar = ""
    var desc = ""
    var music = ""
    var seriesName = ""
    var ep = ""

    init(_ it: FeedItem) {
        liked = it.liked ?? false
        likes = it.likes ?? 0
        comments = it.comments ?? 0
        favorites = it.favorites ?? 0
        favorited = it.favorited ?? false
        followed = it.followed ?? false
        authorName = it.author?.name ?? ""
        authorAvatar = it.author?.avatar ?? ""
        desc = it.desc ?? ""
        music = it.music ?? ""
        seriesName = it.seriesName ?? ""
        ep = it.ep ?? ""
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { (i >= 0 && i < count) ? self[i] : nil }
}

final class PlayerPool: ObservableObject {
    static let shared = PlayerPool()

    @Published var currentId: String = ""

    @Published private(set) var loading: Set<String> = []

    @Published private(set) var failed: Set<String> = []
    private var players: [String: AVPlayer] = [:]
    private var urls: [String: URL] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]

    private var recent: [String] = []

    private var played: Set<String> = []

    func player(for item: FeedItem) -> AVPlayer? {
        let key = item.id
        touch(key)
        if let p = players[key] { return p }
        guard let u = startURL(item) else { return nil }
        return makePlayer(item: item, url: u, triedMP4: u == mp4URL(item))
    }

    private func touch(_ key: String) {
        recent.removeAll { $0 == key }
        recent.insert(key, at: 0)
        if recent.count > 8 { recent.removeLast(recent.count - 8) }
    }

    func hasPlayed(_ id: String) -> Bool { played.contains(id) }

    private func startURL(_ item: FeedItem) -> URL? {
        if let v = item.video, !v.isEmpty, let u = API.shared.assetURL(v) { return u }
        if let h = item.hls, !h.isEmpty, let u = API.shared.assetURL(h) { return u }
        return API.shared.assetURL(item.playPath)
    }

    private func mp4URL(_ item: FeedItem) -> URL? {
        guard let v = item.video, !v.isEmpty else { return nil }
        return API.shared.assetURL(v)
    }

    @discardableResult
    private func makePlayer(item: FeedItem, url: URL, triedMP4: Bool, fromDownload: Bool = false) -> AVPlayer {
        let key = item.id

        let p = AVPlayer()
        p.actionAtItemEnd = .none

        p.automaticallyWaitsToMinimizeStalling = false
        players[key] = p
        urls[key] = url
        if currentId == key { p.play() }
        CrashCatcher.note("视频号", "开始加载 id=\(key) 源=\(url.absoluteString)")
        loadInto(item: item, player: p, url: url, triedMP4: triedMP4, fromDownload: fromDownload)
        return p
    }

    private func loadInto(item: FeedItem, player p: AVPlayer, url: URL, triedMP4: Bool, fromDownload: Bool = false) {
        let key = item.id

        if url.scheme != "http" && url.scheme != "https" {
            attach(item: item, player: p, file: url, remote: url, triedMP4: true)
            return
        }

        if let local = LocalStore.localURL(url.path), FileManager.default.fileExists(atPath: local.path) {
            attach(item: item, player: p, file: local, remote: url, triedMP4: true)
            return
        }

        if url.pathExtension == "m3u8", let pi = StreamPlay.item(url) {
            pi.preferredForwardBufferDuration = 1.5
            p.replaceCurrentItem(with: pi)
            NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                  object: pi, queue: .main) { [weak p] _ in
                p?.seek(to: .zero)
                p?.play()
            }
            urls[key] = url
            if currentId == key { p.play() }
            verify(item: item, player: p, url: url, triedMP4: false)
            return
        }

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let local = await StreamPlay.download(url)
            guard self.players[key] === p else { return }
            guard let file = local else {
                self.loading.remove(key)
                self.failed.insert(key)
                CrashCatcher.note("视频号", "整段下载失败 id=\(key) 源=\(url.absoluteString)")
                return
            }
            self.attach(item: item, player: p, file: file, remote: url, triedMP4: true)
        }
    }

    private func attach(item: FeedItem, player p: AVPlayer, file: URL, remote: URL, triedMP4: Bool) {
        let key = item.id
        let pi = AVPlayerItem(url: file)
        pi.preferredForwardBufferDuration = 2
        p.replaceCurrentItem(with: pi)
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                              object: pi, queue: .main) { [weak p] _ in
            p?.seek(to: .zero)
            p?.play()
        }
        urls[key] = file
        if currentId == key { p.play() }
        verify(item: item, player: p, url: remote, triedMP4: triedMP4)
    }

    private func verify(item: FeedItem, player: AVPlayer, url: URL, triedMP4: Bool) {
        let key = item.id
        tasks[key]?.cancel()
        tasks[key] = Task { @MainActor [weak self] in
            guard let self = self else { return }
            if !self.played.contains(key) { self.loading.insert(key) }
            self.failed.remove(key)

            var moved = false
            var activeWait = 0.0
            for tick in 0..<250 {
                if self.players[key] !== player { return }
                let active = (self.currentId == key)
                if active { player.play() }
                if let it = player.currentItem {
                    if it.status == .failed { break }
                    if it.status == .readyToPlay, CMTimeGetSeconds(player.currentTime()) > 0.05 {
                        moved = true
                        break
                    }
                }

                if tick % 25 == 0 {
                    let st = player.currentItem?.status.rawValue ?? -1
                    let t = CMTimeGetSeconds(player.currentTime())
                    let buf = player.currentItem?.loadedTimeRanges.first?.timeRangeValue.duration.seconds ?? 0
                    CrashCatcher.note("视频号",
                        "诊断 id=\(key) active=\(active) status=\(st) t=\(String(format: "%.2f", t.isFinite ? t : 0))"
                        + " rate=\(player.rate) 缓冲=\(String(format: "%.1f", buf.isFinite ? buf : 0))"
                        + " likely=\(player.currentItem?.isPlaybackLikelyToKeepUp ?? false)")
                }
                if active { activeWait += 0.2 }

                if active, activeWait >= (triedMP4 ? 12 : 3), !(player.currentItem?.isPlaybackLikelyToKeepUp ?? false) {
                    break
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            guard self.players[key] === player else { return }
            if moved {
                self.played.insert(key)
                self.loading.remove(key)
                self.failed.remove(key)
                CrashCatcher.note("视频号", "出画面 id=\(key)")
                return
            }

            if self.currentId != key, player.currentItem?.status != .failed {
                self.loading.remove(key)
                self.tasks[key] = nil
                CrashCatcher.note("视频号", "预加载等画面超时（先不判失败）id=\(key) 源=\(url.absoluteString)")
                return
            }
            let why = player.currentItem?.error?.localizedDescription ?? "没等到画面"
            CrashCatcher.note("视频号", "加载失败 id=\(key) 源=\(url.absoluteString) 原因=\(why)")
            player.pause()
            StreamPlay.cancel(player.currentItem)
            player.replaceCurrentItem(with: nil)
            if self.players[key] === player { self.players.removeValue(forKey: key) }
            self.urls.removeValue(forKey: key)
            if !triedMP4, let u2 = self.mp4URL(item), u2 != url {
                CrashCatcher.note("视频号", "改用整包 MP4（先下后播）id=\(key)")
                self.makePlayer(item: item, url: u2, triedMP4: true, fromDownload: true)
            } else {
                self.loading.remove(key)
                self.failed.insert(key)
            }
        }
    }

    func retry(_ item: FeedItem) {
        let key = item.id
        tasks[key]?.cancel()
        players[key]?.pause()
        StreamPlay.cancel(players[key]?.currentItem)
        players[key]?.replaceCurrentItem(with: nil)
        players.removeValue(forKey: key)
        urls.removeValue(forKey: key)
        played.remove(key)
        failed.remove(key)
        loading.remove(key)
        guard let u = startURL(item) else { failed.insert(key); return }
        CrashCatcher.note("视频号", "手动重试 id=\(key) 源=\(u.absoluteString)")
        makePlayer(item: item, url: u, triedMP4: u == mp4URL(item))
    }

    func play(_ item: FeedItem) {
        guard let p = player(for: item) else { return }
        if p.timeControlStatus != .playing { p.play() }

        if !played.contains(item.id), tasks[item.id] == nil, let u = urls[item.id] {
            verify(item: item, player: p, url: u, triedMP4: (u == mp4URL(item)))
        }
    }

    func pause(_ item: FeedItem) {
        players[item.id]?.pause()
    }

    func progress(of id: String) -> Double {
        guard let p = players[id], let it = p.currentItem else { return 0 }
        let total = CMTimeGetSeconds(it.duration)
        guard total.isFinite, total > 0 else { return 0 }
        return max(0, min(1, CMTimeGetSeconds(p.currentTime()) / total))
    }

    func keepOnly(_ ids: [String]) {

        var keep = Set(ids)
        keep.formUnion(recent)
        if !currentId.isEmpty { keep.insert(currentId) }
        for (k, p) in players where !keep.contains(k) {
            p.pause()
            StreamPlay.cancel(p.currentItem)
            p.replaceCurrentItem(with: nil)
            tasks[k]?.cancel()
            tasks.removeValue(forKey: k)
            players.removeValue(forKey: k)
            urls.removeValue(forKey: k)
            loading.remove(k)
        }
    }
}

private struct PlayerPage: View {
    let item: FeedItem
    let active: Bool
    let paused: Bool
    var ui: FeedItemUI
    var onTap: () -> Void = { }
    var onDoubleTap: () -> Void = { }
    var onLike: () -> Void = { }
    var onComment: () -> Void = { }
    var onFavorite: () -> Void = { }
    var onShare: () -> Void = { }
    var onFollow: () -> Void = { }
    var onAvatar: () -> Void = { }
    var progress: Double = 0

    @ObservedObject private var pool = PlayerPool.shared
    private var isActive: Bool { pool.currentId == item.id }

    var body: some View {
        ZStack {

            if let c = item.cover, !c.isEmpty {
                RemoteImage(path: c, mode: .fill, maxSide: 1600)
                    .ignoresSafeArea()
            }
            PlayerLayerView(player: PlayerPool.shared.player(for: item))
                .ignoresSafeArea()

            if isActive {
                if pool.failed.contains(item.id) {
                    failedBadge
                } else if pool.loading.contains(item.id), !pool.hasPlayed(item.id) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.15)
                        .allowsHitTesting(false)
                }
            }

            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 7) {
                        Button { onAvatar() } label: {
                            Text("@" + (ui.authorName.isEmpty ? Tr("视频号") : ui.authorName))
                                .font(pfStyled(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)

                        if !ui.desc.isEmpty {
                            Text(ui.desc)
                                .font(pfStyled(size: 14))
                                .foregroundColor(.white.opacity(0.94))
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                        }
                        if !ui.ep.isEmpty || !ui.seriesName.isEmpty {
                            Text((ui.seriesName.isEmpty ? "" : ui.seriesName) + (ui.ep.isEmpty ? "" : " · " + ui.ep))
                                .font(pfStyled(size: 12.5))
                                .foregroundColor(.white.opacity(0.9))
                        }
                        if !ui.music.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "music.note")
                                    .font(.system(size: 12))
                                Text(ui.music)
                                    .font(pfStyled(size: 12.5))
                                    .lineLimit(1)
                            }
                            .foregroundColor(.white.opacity(0.92))
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
                .padding(.trailing, 76)
            }

            VStack {
                Spacer()
                VStack(spacing: 18) {
                    ZStack(alignment: .bottom) {
                        Button { onAvatar() } label: {
                            Avatar(path: ui.authorAvatar, size: 46, radius: 23, circle: true)
                                .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        if !ui.followed {
                            Button { onFollow() } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 20, height: 20)
                                    .background(Circle().fill(Color(hex: 0xFE2C55)))
                            }
                            .buttonStyle(.plain)
                            .offset(y: 9)
                        }
                    }
                    .padding(.bottom, ui.followed ? 0 : 8)

                    FeedRailButton(icon: "heart.fill",
                                   color: ui.liked ? Color(hex: 0xFE2C55) : .white,
                                   count: ui.likes, action: onLike)
                    FeedRailButton(icon: "ellipsis.bubble.fill", color: .white,
                                   count: ui.comments, action: onComment)
                    FeedRailButton(icon: "star.fill",
                                   color: ui.favorited ? Color(hex: 0xFFD60A) : .white,
                                   count: ui.favorites, action: onFavorite)
                    FeedRailButton(icon: "arrowshape.turn.up.right.fill", color: .white,
                                   count: 0, action: onShare)
                    MusicDisc()
                }
                .padding(.bottom, 34)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 12)

            VStack {
                Spacer()
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.white.opacity(0.25)).frame(height: 2)
                        Rectangle().fill(Color.white).frame(width: max(0, geo.size.width * progress), height: 2)
                    }
                }
                .frame(height: 2)
                .padding(.bottom, 3)
            }

            if paused {
                Image(systemName: "play.fill")
                    .font(.system(size: 54))
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onDoubleTap() }
        .onTapGesture { onTap() }
        .onAppear { if isActive { PlayerPool.shared.play(item) } }
        .onChange(of: pool.currentId) { _ in
            if isActive { PlayerPool.shared.play(item) } else { PlayerPool.shared.pause(item) }
        }
        .onChange(of: paused) { p in
            if p { PlayerPool.shared.pause(item) } else if isActive { PlayerPool.shared.play(item) }
        }
    }

    private var failedBadge: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 26, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
            Text(Tr("内容暂时不可用"))
                .font(pfStyled(size: 14.5))
                .foregroundColor(.white.opacity(0.92))
            Button {
                PlayerPool.shared.retry(item)
            } label: {
                Text(Tr("重新加载"))
                    .font(pfStyled(size: 14.5, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .frame(height: 34)
                    .background(Capsule().fill(Color.white.opacity(0.2)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.38))
        )
    }
}

final class PlayerLayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
}

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer?

    func makeUIView(context: Context) -> PlayerLayerUIView {
        let v = PlayerLayerUIView()
        v.backgroundColor = .black
        let l = v.layer as? AVPlayerLayer
        l?.player = player
        l?.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ v: PlayerLayerUIView, context: Context) {
        let l = v.layer as? AVPlayerLayer
        if l?.player !== player { l?.player = player }
    }
}

struct VerticalPager<Content: View>: UIViewControllerRepresentable {
    @Binding var index: Int
    let count: Int
    let content: (Int) -> Content

    func makeUIViewController(context: Context) -> UIPageViewController {
        let vc = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .vertical, options: nil)
        vc.dataSource = context.coordinator
        vc.delegate = context.coordinator
        vc.setViewControllers([context.coordinator.host(index)], direction: .forward, animated: false)
        return vc
    }

    func updateUIViewController(_ vc: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.current != index, let target = context.coordinator.host(index) as UIViewController? {
            let dir: UIPageViewController.NavigationDirection = index > context.coordinator.current ? .forward : .reverse
            vc.setViewControllers([target], direction: dir, animated: true)
            context.coordinator.current = index
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: VerticalPager
        var current: Int = 0

        private var map: [ObjectIdentifier: Int] = [:]
        init(_ p: VerticalPager) { parent = p; current = p.index }

        func host(_ i: Int) -> UIHostingController<AnyView> {
            let vc = UIHostingController(rootView: AnyView(parent.content(i)))
            map[ObjectIdentifier(vc)] = i
            return vc
        }

        func pageViewController(_ vc: UIPageViewController, viewControllerBefore v: UIViewController) -> UIViewController? {
            guard let i = map[ObjectIdentifier(v)], i > 0 else { return nil }
            return host(i - 1)
        }
        func pageViewController(_ vc: UIPageViewController, viewControllerAfter v: UIViewController) -> UIViewController? {
            guard let i = map[ObjectIdentifier(v)], i + 1 < parent.count else { return nil }
            return host(i + 1)
        }
        func pageViewController(_ vc: UIPageViewController, didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            guard completed, let v = vc.viewControllers?.first,
                  let i = map[ObjectIdentifier(v)] else { return }
            current = i
            parent.index = i
        }
    }
}

private struct FeedRailButton: View {
    let icon: String
    var color: Color = .white
    var count: Int = 0
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 27))
                    .foregroundColor(color)
                    .shadow(color: .black.opacity(0.35), radius: 4)
                if count > 0 {
                    Text(FeedCount.text(count))
                        .font(pfStyled(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.35), radius: 3)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

enum FeedCount {

    static func text(_ n: Int) -> String {
        if n >= 10000 { return String(format: "%.1f万", Double(n) / 10000.0) }
        return String(n)
    }
}

private struct MusicDisc: View {
    @State private var spin = false

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(white: 0.24), Color(white: 0.06)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().stroke(Color.white.opacity(0.18), lineWidth: 1)
            Image(systemName: "music.note")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
        }
        .frame(width: 42, height: 42)
        .rotationEffect(.degrees(spin ? 360 : 0))
        .animation(.linear(duration: 6).repeatForever(autoreverses: false), value: spin)
        .onAppear { spin = true }
    }
}

struct FeedCommentSheet: View {
    let item: FeedItem
    var onCount: (Int) -> Void

    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var list: [FeedCommentItem] = []
    @State private var draft = ""
    @State private var sending = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(list.isEmpty ? Tr("还没有评论") : "\(list.count) " + Tr("条评论"))
                    .font(pf(15, .semibold))
                    .foregroundColor(C.label)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(C.subLabel)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(list) { c in
                        HStack(alignment: .top, spacing: 10) {
                            Avatar(path: c.avatar ?? "", size: 34, radius: 17, circle: true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(c.name ?? "").font(pf(13)).foregroundColor(C.subLabel)
                                Text(c.text ?? "").font(pf(15)).foregroundColor(C.label)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 14)
            }

            Divider()

            HStack(spacing: 10) {
                TextField(Tr("说点什么…"), text: $draft)
                    .focused($focused)
                    .font(pf(15))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 18).fill(C.searchBg))
                Button { send() } label: {
                    Text(Tr("发送"))
                        .font(pf(15, .semibold))
                        .foregroundColor(draft.trimmingCharacters(in: .whitespaces).isEmpty ? C.subLabel : C.green)
                }
                .buttonStyle(.plain)
                .disabled(sending || draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(C.cardBg)
        .task { await load() }
    }

    private func load() async {
        list = (try? await API.shared.feedComments(item.id)) ?? []
        onCount(list.count)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sending = true
        Task {
            if let n = try? await API.shared.feedComment(item.id, text: text) {
                draft = ""
                focused = false
                onCount(n)
                await load()
            } else {
                app.show(Tr("评论失败"))
            }
            sending = false
        }
    }
}
