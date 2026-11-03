import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

struct MusicTrack: Decodable, Identifiable, Hashable {
    var id: String
    var title: String
    var artist: String?
    var cover: String?
    var url: String

    var lyrics: String? = nil

    var category: String? = nil

    var likes: [String]? = nil
    var likeCount: Int? = nil
    var shareCount: Int? = nil
    var at: Double?

    var artistText: String { (artist ?? "").isEmpty ? "未知歌手" : (artist ?? "") }

    var categoryText: String {
        let c = (category ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !c.isEmpty { return c }
        return (lyrics ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "纯音乐" : "人声"
    }
}

struct FriendNowPlaying: Decodable, Identifiable {
    var id: String
    var name: String
    var avatar: String?
    var trackId: String
    var title: String
    var artist: String?
    var cover: String?
    var url: String
    var at: Double?

    var asTrack: MusicTrack {
        MusicTrack(id: trackId.isEmpty ? id : trackId, title: title,
                   artist: artist, cover: cover, url: url, at: nil)
    }

    var line: String {
        let a = (artist ?? "").trimmingCharacters(in: .whitespaces)
        return "在听《" + title + "》" + (a.isEmpty ? "" : " · " + a)
    }
}

struct NowPlayingPayload: Decodable { var list: [FriendNowPlaying]? }

struct MusicLyricLine: Identifiable, Equatable {
    var id: Int
    var time: Double
    var text: String
}

enum MusicLyrics {

    static func parse(_ raw: String, duration: Double) -> [MusicLyricLine] {
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let rows = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
        guard !rows.isEmpty else { return [] }

        if let re = try? NSRegularExpression(pattern: "\\[(\\d{1,2}):(\\d{1,2})(?:[.:](\\d{1,3}))?\\]") {
            var out: [MusicLyricLine] = []
            for r in rows {
                let ns = r as NSString
                let ms = re.matches(in: r, options: [], range: NSRange(location: 0, length: ns.length))
                var stamp: Double? = nil
                for m in ms {
                    let mm = Double(ns.substring(with: m.range(at: 1))) ?? 0
                    let ss = Double(ns.substring(with: m.range(at: 2))) ?? 0
                    var frac = 0.0
                    if m.range(at: 3).location != NSNotFound {
                        let raw3 = ns.substring(with: m.range(at: 3))
                        frac = (Double(raw3) ?? 0) / pow(10, Double(max(1, raw3.count)))
                    }
                    if stamp == nil { stamp = mm * 60 + ss + frac }
                }
                guard let t0 = stamp else { continue }
                let last = ms.last
                let body = (last == nil ? ns as String
                            : ns.substring(from: (last!.range.location + last!.range.length)))
                    .trimmingCharacters(in: .whitespaces)
                if body.isEmpty { continue }
                out.append(MusicLyricLine(id: out.count, time: t0, text: body))
            }
            if !out.isEmpty { return out.sorted { $0.time < $1.time } }
        }

        let plain = rows.filter { !$0.isEmpty && !$0.hasPrefix("[") }
        guard !plain.isEmpty else { return [] }
        let span = duration > 1 ? duration : Double(plain.count) * 4
        let lead = span * 0.08
        let step = (span - lead) / Double(plain.count)
        return plain.enumerated().map { i, s in
            MusicLyricLine(id: i, time: lead + step * Double(i), text: s)
        }
    }

    static func current(_ lines: [MusicLyricLine], at t: Double) -> Int {
        guard !lines.isEmpty else { return -1 }
        var idx = 0
        for (i, l) in lines.enumerated() {
            if l.time <= t + 0.2 { idx = i } else { break }
        }
        return idx
    }
}

struct MusicLyricsView: View {
    let track: MusicTrack?

    var onClose: () -> Void = { }
    @ObservedObject private var player = MusicPlayer.shared

    @State private var lastLyricLine = -1

    private var lines: [MusicLyricLine] { MusicLyrics.parse(track?.lyrics ?? "", duration: player.total) }
    private var cur: Int { MusicLyrics.current(lines, at: player.seconds) }

    private func seekTo(_ t: Double) {
        guard player.total > 1 else { return }
        player.seek(min(max(0, t / player.total), 1))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button { onClose() } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(C.label)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                VStack(spacing: 2) {
                    Text(track?.title ?? "").font(pf(15, .semibold)).foregroundColor(C.label).lineLimit(1)
                    Text(track?.artistText ?? "").font(pf(12)).foregroundColor(C.subLabel).lineLimit(1)
                }
                Spacer(minLength: 0)
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.top, 6)

            if lines.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 30)).foregroundColor(C.subLabel)
                    Text(Tr("这首歌还没有歌词")).font(pf(15)).foregroundColor(C.label)
                    Text(Tr("后台「音乐（听一听）」里，每首歌后面点「歌词」就能贴上去"))
                        .font(pf(12.5)).foregroundColor(C.subLabel)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 30)
                .padding(.top, 60)
                Spacer(minLength: 0)
            } else {
                ScrollViewReader { sp in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 18) {
                            Color.clear.frame(height: 130)
                            ForEach(lines) { l in
                                Text(l.text)
                                    .font(pf(l.id == cur ? 17.5 : 15, l.id == cur ? .semibold : .regular))
                                    .foregroundColor(l.id == cur ? C.green : C.label.opacity(0.72))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .id(l.id)

                                    .contentShape(Rectangle())
                                    .onTapGesture { seekTo(l.time) }
                            }
                            Color.clear.frame(height: 180)
                        }
                        .padding(.horizontal, 26)
                    }
                    .onChange(of: cur) { i in
                        guard i >= 0 else { return }

                        let jump = lastLyricLine < 0 || abs(i - lastLyricLine) > 3
                        lastLyricLine = i
                        if jump { sp.scrollTo(i, anchor: .center) }
                        else { withAnimation(.easeInOut(duration: 0.55)) { sp.scrollTo(i, anchor: .center) } }
                    }
                }
            }
        }
        .background(C.cardBg.ignoresSafeArea())
        .swipeBack { onClose() }
    }
}

struct MusicCardInfo {
    var id = ""
    var title = ""
    var artist = ""
    var cover = ""
    var url = ""

    init?(json: String) {
        guard let d = json.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        id = (o["id"] as? String) ?? ""
        title = (o["title"] as? String) ?? ""
        artist = (o["artist"] as? String) ?? ""
        cover = (o["cover"] as? String) ?? ""
        url = (o["url"] as? String) ?? ""
        guard !title.isEmpty, !url.isEmpty else { return nil }
    }

    var asTrack: MusicTrack { MusicTrack(id: id, title: title, artist: artist, cover: cover, url: url, at: nil) }
}

@MainActor
final class MusicPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = MusicPlayer()

    @Published private(set) var current: MusicTrack?

    @Published var playing = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var seconds: Double = 0
    @Published private(set) var total: Double = 0
    @Published private(set) var loadingId = ""

    var player: AVAudioPlayer?

    var stream: AVPlayer?

    private var endObserver: NSObjectProtocol?
    var timer: Timer?
    private var cache: [String: Data] = [:]

    private var remoteReady = false

    private var syncedSecond: Int = -1

    private var nowId = ""
    private var nowAt = Date.distantPast

    var queue: [MusicTrack] = []

    func applyLike(id: String, myId: String, liked: Bool, count: Int) {
        func patch(_ t: MusicTrack) -> MusicTrack {
            var x = t
            var list = x.likes ?? []
            if liked {
                if !list.contains(myId) { list.append(myId) }
            } else {
                list = list.filter { $0 != myId }
            }
            x.likes = list
            x.likeCount = count
            return x
        }
        if var c = current, c.id == id {
            c = patch(c)
            current = c
        }
        queue = queue.map { $0.id == id ? patch($0) : $0 }
    }
    func setQueue(_ list: [MusicTrack]) { queue = list }

    var loopOne = false

    var playMode = 0

    private var sleepLeftSec: Double = 0

    private var sleepTickAt: Date? = nil

    private var sleepStopped = false

    var sleepLeft: Int { max(0, Int(sleepLeftSec.rounded())) }

    func setSleep(minutes: Int) {
        sleepLeftSec = minutes > 0 ? Double(minutes) * 60 : 0
        sleepTickAt = minutes > 0 ? Date() : nil
    }

    private func sleepElapsed() -> Bool {
        guard sleepLeftSec > 0 else { return false }
        let now = Date()
        if playing, let last = sleepTickAt {
            sleepLeftSec = max(0, sleepLeftSec - now.timeIntervalSince(last))
        }
        sleepTickAt = now
        if sleepLeftSec <= 0 { sleepLeftSec = 0; sleepTickAt = nil; return true }
        return false
    }

    @Published private(set) var rate: Float = 1

    func setRate(_ r: Float) {
        let v = min(max(0.5, r), 2.0)
        rate = v
        if let p = player { p.enableRate = true; p.rate = v }
        if let st = stream, playing { st.rate = v }
    }

    func next() {
        guard let cur = current, let i = queue.firstIndex(where: { $0.id == cur.id }) else { return }
        let n = queue[(i + 1) % queue.count]
        play(n)
    }

    func prev() {
        guard let cur = current, let i = queue.firstIndex(where: { $0.id == cur.id }) else { return }
        let n = queue[(i - 1 + queue.count) % queue.count]
        play(n)
    }

    private func reportNow(_ t: MusicTrack) {
        if nowId == t.id, Date().timeIntervalSince(nowAt) < 60 { return }
        nowId = t.id
        nowAt = Date()
        Task { await API.shared.musicNow(t) }
    }

    func ensureRemote() {
        guard !remoteReady else { return }
        remoteReady = true
        setupRemoteControls()
    }

    func isPlaying(_ id: String) -> Bool { playing && current?.id == id }

    func toggle(_ t: MusicTrack) {
        if current?.id == t.id, let p = player {
            if p.isPlaying {
                p.pause(); playing = false; stopTimer()
            } else {

                try? AVAudioSession.sharedInstance().setActive(true)
                sleepStopped = false
                p.play(); p.rate = rate; playing = true; startTimer()
            }
            syncNowPlaying()
            return
        }

        if current?.id == t.id, let st = stream {
            if playing {
                st.pause(); playing = false; stopTimer()
            } else {
                try? AVAudioSession.sharedInstance().setActive(true)
                sleepStopped = false
                st.play(); st.rate = rate; playing = true; startTimer()
            }
            syncNowPlaying()
            return
        }
        play(t)
    }

    private func cacheCover(_ t: MusicTrack) {
        guard let cover = t.cover, !cover.isEmpty else { return }
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let dir = caches.appendingPathComponent("musiccover", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let to = dir.appendingPathComponent(t.id)
        if FileManager.default.fileExists(atPath: to.path) { return }
        guard let url = API.shared.assetURL(cover) else { return }
        Task {
            if let d = try? await API.shared.assetData(url) {
                try? d.write(to: to, options: .atomic)
                await MainActor.run { self.syncNowPlaying() }
            }
        }
    }

    func localURL(_ t: MusicTrack) -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = caches.appendingPathComponent("music", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let raw = (t.url as NSString).pathExtension
        let ext = (raw.isEmpty || raw.count > 5) ? "mp3" : raw
        return dir.appendingPathComponent("\(t.id).\(ext)")
    }

    func play(_ t: MusicTrack) {

        guard let url = API.shared.assetURL(t.url) else { return }
        ensureRemote()
        cacheCover(t)
        current = t
        reportNow(t)

        MusicLibrary.shared.markPlayed(t)

        sleepStopped = false

        player?.stop()
        player = nil
        stopStream()

        if let local = localURL(t), FileManager.default.fileExists(atPath: local.path),
           let p = try? AVAudioPlayer(contentsOf: local) {
            stopTimer()
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try? AVAudioSession.sharedInstance().setActive(true)
            player = p
            p.delegate = self
            p.enableRate = true
            p.prepareToPlay()
            p.play()
            p.rate = rate
            playing = true
            seconds = 0
            progress = 0
            total = p.duration
            startTimer()
            syncNowPlaying()
            return
        }
        if let d = cache[t.id] {
            start(data: d, track: t)
            return
        }

        startStream(t, httpsURL: url)
    }

    private func startStream(_ t: MusicTrack, httpsURL: URL) {
        guard let p = StreamPlay.player(httpsURL) else {

            startDownloadFallback(t, url: httpsURL)
            return
        }
        stopTimer()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        stream = p
        watchEnd(p)
        playing = true
        loadingId = ""
        seconds = 0
        progress = 0
        total = 0
        p.play()
        p.rate = rate
        startTimer()
        syncNowPlaying()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard self.stream === p else { return }
            let advanced = CMTimeGetSeconds(p.currentTime()) > 0.15
            if !advanced, p.currentItem?.status != .readyToPlay {
                self.stopStream()
                self.startDownloadFallback(t, url: httpsURL)
            }
        }

        Task {
            var req = URLRequest(url: httpsURL)
            req.timeoutInterval = 120
            if !API.shared.token.isEmpty {
                req.setValue("Bearer \(API.shared.token)", forHTTPHeaderField: "Authorization")
            }
            guard let (tmp, resp) = try? await API.shared.session.download(for: req),
                  !((resp as? HTTPURLResponse).map { $0.statusCode >= 400 } ?? false),
                  let local = self.localURL(t) else { return }
            try? FileManager.default.removeItem(at: local)
            try? FileManager.default.moveItem(at: tmp, to: local)
        }
    }

    private func watchEnd(_ p: AVPlayer) {
        dropEndObserver()
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: p.currentItem, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.finished() }
        }
    }

    private func dropEndObserver() {
        if let o = endObserver { NotificationCenter.default.removeObserver(o); endObserver = nil }
    }

    private func stopStream() {
        stream?.pause()
        StreamPlay.cancel(stream?.currentItem)
        dropEndObserver()
        stream = nil
    }

    private func startDownloadFallback(_ t: MusicTrack, url: URL) {
        loadingId = t.id
        Task {
            do {
                let data = try await API.shared.assetData(url)
                await MainActor.run {
                    self.loadingId = ""
                    self.cache[t.id] = data
                    if let local = self.localURL(t) { try? data.write(to: local, options: .atomic) }
                    self.start(data: data, track: t)
                }
            } catch {
                await MainActor.run {
                    self.loadingId = ""
                    self.current = nil
                    self.playing = false
                }
            }
        }
    }

    private func start(data: Data, track: MusicTrack) {
        stopTimer()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        player = try? AVAudioPlayer(data: data)
        player?.delegate = self
        player?.enableRate = true
        player?.prepareToPlay()
        player?.play()
        player?.rate = rate
        playing = true
        seconds = 0
        progress = 0
        total = player?.duration ?? 0
        startTimer()
        syncNowPlaying()
    }

    func pause() {
        player?.pause()
        stream?.pause()
        playing = false
        stopTimer()
        syncNowPlaying()
    }

    func stop() {
        player?.stop()
        player = nil
        stopStream()
        playing = false
        current = nil
        progress = 0
        seconds = 0
        total = 0
        stopTimer()
        syncNowPlaying()
    }

    func seek(_ ratio: Double) {
        let r = min(max(0, ratio), 1)
        if let p = player, p.duration > 0 {
            let v = r * p.duration
            p.currentTime = v
            seconds = v
            progress = r
            syncNowPlaying()
            return
        }

        if let st = stream, total > 0 {
            let v = r * total
            st.seek(to: CMTime(seconds: v, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
            seconds = v
            progress = r
            syncNowPlaying()
        }
    }

    func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            Task { @MainActor in self.tick() }
        }
    }
    func stopTimer() { timer?.invalidate(); timer = nil }
    func tick() {

        if sleepElapsed() {
            sleepStopped = true
            pause()
            return
        }
        if let p = player {
            seconds = p.currentTime
            total = p.duration
            progress = p.duration > 0 ? min(1, p.currentTime / p.duration) : 0
        } else if let st = stream {

            let cur = CMTimeGetSeconds(st.currentTime())
            let dur = CMTimeGetSeconds(st.currentItem?.duration ?? .invalid)
            seconds = cur.isFinite ? max(0, cur) : 0
            if dur.isFinite, dur > 0 { total = dur }
            progress = (dur.isFinite && dur > 0) ? min(1, max(0, seconds / dur)) : 0
        } else {
            return
        }

        let s = Int(seconds)
        if s != syncedSecond { syncedSecond = s; syncNowPlaying() }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.finished()
        }
    }

    private func finished() {
        playing = false
        progress = 0
        seconds = 0
        stopTimer()
        syncNowPlaying()

        if sleepStopped { sleepStopped = false; return }
        if loopOne || playMode == 1, let t = current { play(t); return }
        guard let t = current else { return }
        if playMode == 2, queue.count > 1 {
            let others = queue.filter { $0.id != t.id }
            if let n = others.randomElement() { play(n) }
            return
        }
        if let i = queue.firstIndex(where: { $0.id == t.id }), i + 1 < queue.count {
            play(queue[i + 1])
        }
    }
}

func musicTime(_ s: Double) -> String {
    guard s.isFinite, s > 0 else { return "00:00" }
    let t = Int(s.rounded())
    return String(format: "%02d:%02d", t / 60, t % 60)
}

struct MusicCover: View {
    var path: String
    var size: CGFloat
    var radius: CGFloat = 8

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xB98CFF), Color(hex: 0x7A45D6)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "music.note")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundColor(.white.opacity(0.92))
            if !path.isEmpty {
                RemoteImage(path: path, icon: "music.note")
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            }
        }
        .frame(width: size, height: size)
    }
}

struct MusicPlayButton: View {
    var playing: Bool
    var loading: Bool
    var size: CGFloat = 30
    var tint: Color = .white
    var bg: Color = Color.black.opacity(0.35)

    var body: some View {
        ZStack {
            Circle().fill(bg)
            if loading {
                ProgressView().tint(tint).scaleEffect(0.7)
            } else {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: size * 0.36, weight: .bold))
                    .foregroundColor(tint)
                    .offset(x: playing ? 0 : size * 0.03)
            }
        }
        .frame(width: size, height: size)
    }
}

struct MusicBubble: View {
    let info: MusicCardInfo

    var onOpen: () -> Void
    @ObservedObject private var player = MusicPlayer.shared

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                MusicCover(path: info.cover, size: 52, radius: 8)
                MusicPlayButton(playing: player.isPlaying(info.id),
                                loading: player.loadingId == info.id, size: 22)
                    .offset(x: 3, y: 3)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(info.title)
                    .font(pf(15))
                    .foregroundColor(C.label)
                    .lineLimit(1)
                Text(info.artist.isEmpty ? "未知歌手" : info.artist)
                    .font(pf(12))
                    .foregroundColor(C.subLabel)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(width: 232, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(C.cardBg))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(C.hairline, lineWidth: 0.5))
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
    }
}

struct ListenView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var sendTo: Chat? = nil
    var onSend: ((MusicTrack) -> Void)? = nil

    @State private var tracks: [MusicTrack] = []
    @State private var loading = true
    @State private var query = ""

    @State private var tab = 0

    @State private var mine: MusicMineKind? = nil

    @State private var cat = ""

    @State private var batch = 0

    @State private var friends: [FriendNowPlaying] = []
    @State private var friendsLoaded = false

    @State private var iconPickFor = ""
    @State private var showIconPick = false

    @State private var manageMode = false
    @State private var pickedTracks: Set<String> = []
    @State private var showBatchPick = false
    @State private var showFolderPick = false
    @State private var busyText = ""
    @ObservedObject private var player = MusicPlayer.shared
    @ObservedObject private var musicLibrary = MusicLibrary.shared
    @ObservedObject private var musicSheet = MusicSheet.shared
    @ObservedObject private var musicDock = MusicDockState.shared

    private var sendMode: Bool { sendTo != nil }

    private var matched: [MusicTrack] {
        let q = query.trimmingCharacters(in: .whitespaces)
        var list = tracks
        if !cat.isEmpty { list = list.filter { $0.categoryText == cat } }
        guard !q.isEmpty else { return list }

        return list.filter { $0.title.localizedCaseInsensitiveContains(q)
            || ($0.artist ?? "").localizedCaseInsensitiveContains(q)
            || $0.categoryText.localizedCaseInsensitiveContains(q) }
    }

    private var cats: [String] {
        Array(Set(tracks.map { $0.categoryText })).sorted()
    }

    private var recommend: [MusicTrack] {
        var list = tracks
        if !query.trimmingCharacters(in: .whitespaces).isEmpty { return matched }

        list.sort { recRank($0.id) < recRank($1.id) }
        return Array(list.prefix(12))
    }

    private func recRank(_ id: String) -> UInt64 {
        var h = UInt64(truncatingIfNeeded: batch &* 2654435761) &+ 1469598103934665603
        for b in id.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return h
    }

    private var artists: [(String, String)] {
        var seen: [String: String] = [:]
        tracks.forEach { t in
            let a = (t.artist ?? "").isEmpty ? "未知歌手" : t.artist!
            if seen[a] == nil { seen[a] = t.cover ?? "" }
        }
        return seen.map { ($0.key, $0.value) }.sorted { $0.0 < $1.0 }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()
            topAmbientGlow

            VStack(spacing: 0) {
                if !sendMode {
                    Picker(Tr("内容"), selection: $tab) {
                        Text(Tr("推荐")).tag(0)
                        Text(Tr("歌曲")).tag(1)
                        Text(Tr("朋友推荐")).tag(2)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                }

                musicList
            }
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(Tr(sendMode ? "选择音乐" : "听一听"))
        .navigationBarTitleDisplayMode(.large)
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: Text(Tr("搜索歌名 / 歌手 / 分类"))
        )
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar { musicToolbar }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !sendMode && player.current != nil {
                MusicDockedPlayerBar()
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }
        }
        .hidesTabBar()
        .swipeBack { dismiss() }
        .task {
            tracks = await API.shared.musicTracks()
            loading = false
        }

        .fullScreenCover(item: $mine) { k in
            ZStack {
                NavigationStack {
                    MusicMinePage(kind: k).environmentObject(app)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if player.current != nil {
                        MusicDockedPlayerBar()
                            .padding(.horizontal, 10)
                            .padding(.bottom, 8)
                    }
                }

                if musicSheet.open {
                    MusicPlayingView()
                        .transition(.move(edge: .bottom))
                        .zIndex(60)
                }
            }
            .animation(.easeOut(duration: 0.22), value: musicSheet.open)
        }
        .overlay {
            if !sendMode && musicSheet.open {
                MusicPlayingView()
                    .transition(.move(edge: .bottom))
                    .zIndex(60)
            }
        }
        .animation(.easeOut(duration: 0.22), value: musicSheet.open)
        .onAppear {
            if !sendMode { musicDock.attach() }
        }
        .onDisappear {
            if !sendMode { musicDock.detach() }
        }
        .sheet(isPresented: $showIconPick) {
            PhotoPicker { img in
                let id = iconPickFor
                Task {
                    if let url = try? await API.shared.upload(image: img) {
                        try? await API.shared.manageSetIcon(kind: "music", id: id, cover: url)
                        tracks = await API.shared.musicTracks()
                    }
                }
            }
        }
        .fileImporter(isPresented: $showBatchPick, allowedContentTypes: [.item],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { importFiles(urls) }
        }
        .fileImporter(isPresented: $showFolderPick, allowedContentTypes: [.folder],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let dir = urls.first { importFolder(dir) }
        }
    }

    private var ambientCover: String {
        if let cover = player.current?.cover, !cover.isEmpty { return cover }
        if let cover = recommend.first?.cover, !cover.isEmpty { return cover }
        return tracks.first?.cover ?? ""
    }

    private var topAmbientGlow: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                if !ambientCover.isEmpty {
                    RemoteImage(path: ambientCover, mode: .fill, maxSide: 520)
                        .frame(width: geo.size.width * 1.18,
                               height: 330)
                        .blur(radius: 72, opaque: false)
                        .saturation(1.08)
                        .opacity(scheme == .dark ? 0.34 : 0.28)
                } else {
                    RadialGradient(
                        colors: [OrbitTheme.jade.opacity(0.24), .clear],
                        center: .top,
                        startRadius: 8,
                        endRadius: 240
                    )
                }

                LinearGradient(
                    stops: [
                        .init(color: OrbitTheme.jade.opacity(scheme == .dark ? 0.08 : 0.05),
                              location: 0),
                        .init(color: Color.clear, location: 0.46),
                        .init(color: Color(uiColor: .systemGroupedBackground), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: geo.size.width, height: 330)
        }
        .frame(height: 330)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.45), value: ambientCover)
    }

    @ViewBuilder
    private var musicList: some View {
        Group {
            if loading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(Tr("正在加载…"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if tracks.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(OrbitTheme.jade)
                    Text(Tr("曲库还没有歌（后台「音乐（听一听）」里传一首）"))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 34)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        if !sendMode {
                            musicTabRail
                                .padding(.top, 8)
                                .padding(.bottom, 18)
                        }

                        if manageMode {
                            musicManagePanel
                                .padding(.horizontal, 16)
                                .padding(.bottom, 18)
                            musicSectionHeader(Tr("全部歌曲"))
                            ForEach(matched) { track in
                                premiumTrackRow(track)
                            }
                        } else if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            musicSectionHeader(Tr("搜索结果"))
                            ForEach(matched) { track in
                                premiumTrackRow(track)
                            }
                        } else if sendMode {
                            musicSectionHeader(Tr("全部歌曲"))
                            ForEach(matched) { track in
                                premiumTrackRow(track)
                            }
                        } else if tab == 0 {
                            musicHomeContent
                        } else if tab == 1 {
                            musicCatalogContent
                        } else {
                            musicFriendsContent
                        }

                        Color.clear.frame(height: 34)
                    }
                }
                .refreshable {
                    tracks = await API.shared.musicTracks()
                    if tab == 2 { await loadFriends() }
                }
            }
        }
    }

    private var musicTabRail: some View {
        HStack(spacing: 4) {
            ForEach(Array([Tr("推荐"), Tr("歌曲"), Tr("朋友推荐")].enumerated()), id: \.offset) { index, title in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { tab = index }
                } label: {
                    Text(title)
                        .font(.subheadline.weight(tab == index ? .semibold : .medium))
                        .foregroundStyle(tab == index ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background {
                            if tab == index {
                                Capsule()
                                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                                    .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.08),
                                            radius: 7, y: 2)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(.thinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.06), lineWidth: 0.6))
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var musicHomeContent: some View {
        if let lead = recommend.first {
            Button {
                MusicPlayer.shared.setQueue(tracks)
                MusicPlayer.shared.toggle(lead)
            } label: {
                ZStack(alignment: .bottomLeading) {
                    RemoteImage(path: lead.cover ?? "", mode: .fill, maxSide: 900)
                        .frame(height: 270)
                        .clipped()

                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.02), location: 0),
                            .init(color: .black.opacity(0.22), location: 0.45),
                            .init(color: .black.opacity(0.86), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 7) {
                            Text(Tr("今日精选"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.92))
                                .padding(.horizontal, 10)
                                .frame(height: 26)
                                .background(.ultraThinMaterial, in: Capsule())

                            if !lead.categoryText.isEmpty {
                                Text(lead.categoryText)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.78))
                            }
                        }

                        Spacer(minLength: 0)

                        Text(lead.title)
                            .font(.system(size: 27, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
                        Text(lead.artistText)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.78))
                            .lineLimit(1)
                    }
                    .padding(20)
                    .padding(.bottom, 8)

                    MusicPlayButton(
                        playing: player.isPlaying(lead.id),
                        loading: player.loadingId == lead.id,
                        size: 58,
                        tint: .white,
                        bg: OrbitTheme.jade.opacity(0.96)
                    )
                    .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
                    .padding(18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
                .frame(height: 270)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 0.7)
                }
                .shadow(color: .black.opacity(scheme == .dark ? 0.28 : 0.16),
                        radius: 22, y: 12)
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .buttonStyle(.plain)
        }

        musicLibraryCards
            .padding(.horizontal, 16)
            .padding(.bottom, 26)

        musicSectionHeader(Tr("今日推荐"), refresh: true)

        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 14) {
                ForEach(Array(recommend.prefix(10).enumerated()), id: \.element.id) { index, track in
                    musicMixCard(track, rank: index + 1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }

        musicSectionHeader(Tr("全部歌曲"))
        ForEach(Array(recommend.prefix(8).enumerated()), id: \.element.id) { index, track in
            premiumTrackRow(track, rank: index + 1)
        }

        if artists.count > 1 {
            musicSectionHeader(Tr("推荐音乐人"))
                .padding(.top, 22)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(Array(artists.prefix(12).enumerated()), id: \.offset) { _, artist in
                        VStack(spacing: 8) {
                            MusicCover(path: artist.1, size: 72, radius: 36)
                                .overlay(Circle().stroke(Color.white.opacity(0.75), lineWidth: 1))
                                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                            Text(artist.0)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .frame(width: 82)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
    }

    private var musicLibraryCards: some View {
        HStack(spacing: 10) {
            ForEach(MusicMineKind.allCases) { kind in
                Button { mine = kind } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: kind.icon)
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(
                                LinearGradient(
                                    colors: libraryColors(kind),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                            .shadow(color: libraryColors(kind).last?.opacity(0.24) ?? .clear,
                                    radius: 8, y: 4)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(Tr(kind.title))
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(libraryCount(kind))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .frame(minHeight: 128)
                    .background(.regularMaterial,
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 0.6)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func libraryColors(_ kind: MusicMineKind) -> [Color] {
        switch kind {
        case .likes:
            return [Color(hex: 0xFF6B8B), Color(hex: 0xF43F5E)]
        case .recents:
            return [Color(hex: 0x60A5FA), Color(hex: 0x2563EB)]
        case .playlists:
            return [Color(hex: 0xB98CFF), Color(hex: 0x7A45D6)]
        }
    }

    private func libraryCount(_ kind: MusicMineKind) -> String {
        let count: Int
        switch kind {
        case .likes:
            let mine = app.me?.id ?? ""
            count = tracks.filter { ($0.likes ?? []).contains(mine) }.count
        case .recents:
            count = musicLibrary.recents.count
        case .playlists:
            count = musicLibrary.playlists.count
        }
        return "\(count) " + Tr("首")
    }

    private func musicSectionHeader(_ title: String, refresh: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            if refresh {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { batch += 1 }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text(Tr("换一批"))
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(OrbitTheme.jade)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func musicMixCard(_ track: MusicTrack, rank: Int) -> some View {
        Button { choose(track) } label: {
            VStack(alignment: .leading, spacing: 9) {
                ZStack(alignment: .bottomTrailing) {
                    MusicCover(path: track.cover ?? "", size: 164, radius: 18)
                        .shadow(color: .black.opacity(0.14), radius: 12, y: 7)

                    MusicPlayButton(
                        playing: player.isPlaying(track.id),
                        loading: player.loadingId == track.id,
                        size: 38,
                        tint: .white,
                        bg: .black.opacity(0.38)
                    )
                    .padding(9)
                }

                Text(track.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(track.artistText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 164, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var musicCatalogContent: some View {
        if cats.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    categoryChip(Tr("全部"), selected: cat.isEmpty) { cat = "" }
                    ForEach(cats, id: \.self) { value in
                        categoryChip(value, selected: cat == value) { cat = value }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 18)
        }

        musicSectionHeader(Tr("全部歌曲"))
        ForEach(matched) { track in
            premiumTrackRow(track)
        }
    }

    private func categoryChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) { action() }
        } label: {
            Text(title)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? .white : Color.primary)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(
                    selected ? OrbitTheme.jade : Color(uiColor: .secondarySystemGroupedBackground),
                    in: Capsule()
                )
                .overlay(Capsule().stroke(Color.primary.opacity(selected ? 0 : 0.06), lineWidth: 0.6))
        }
        .buttonStyle(.plain)
    }

    private func premiumTrackRow(_ track: MusicTrack, rank: Int? = nil) -> some View {
        Button {
            choose(track)
        } label: {
            HStack(spacing: 12) {
                if manageMode {
                    checkDot(track)
                        .frame(width: 24)
                } else if let rank {
                    Text(String(format: "%02d", rank))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(rank <= 3 ? OrbitTheme.jade : Color.secondary)
                        .frame(width: 26, alignment: .leading)
                }

                ZStack(alignment: .bottomTrailing) {
                    MusicCover(path: track.cover ?? "", size: 56, radius: 11)
                    if player.isPlaying(track.id) {
                        Circle()
                            .fill(OrbitTheme.jade)
                            .frame(width: 18, height: 18)
                            .overlay {
                                Image(systemName: "waveform")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .offset(x: 3, y: 3)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(track.artistText)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if !manageMode {
                    MusicPlayButton(
                        playing: player.isPlaying(track.id),
                        loading: player.loadingId == track.id,
                        size: 36,
                        tint: player.isPlaying(track.id) ? .white : OrbitTheme.jade,
                        bg: player.isPlaying(track.id)
                            ? OrbitTheme.jade : OrbitTheme.jade.opacity(0.11)
                    )
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 72)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if app.me?.ops == true && !manageMode {
                Button {
                    iconPickFor = track.id
                    showIconPick = true
                } label: {
                    Label(Tr("更换封面"), systemImage: "photo.badge.plus")
                }
            }
        }
    }

    @ViewBuilder
    private var musicFriendsContent: some View {
        if friends.isEmpty {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(OrbitTheme.jade.opacity(0.10))
                        .frame(width: 84, height: 84)
                    Image(systemName: "person.2.wave.2.fill")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(OrbitTheme.jade)
                }
                Text(Tr("朋友推荐还没有内容"))
                    .font(.headline)
                Text(Tr("你在这一页放一首歌，好友的「朋友推荐」里就会看到你在听什么；\n反过来，好友在听的时候这里也会出现。"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 36)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 46)
        } else {
            musicSectionHeader(Tr("朋友正在听"))
            LazyVStack(spacing: 10) {
                ForEach(friends) { friend in
                    premiumFriendCard(friend)
                }
            }
            .padding(.horizontal, 16)
            Text(Tr("好友最近 2 小时在听的歌"))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 14)
        }
    }

    private func premiumFriendCard(_ friend: FriendNowPlaying) -> some View {
        let track = friend.asTrack
        return Button {
            MusicPlayer.shared.toggle(track)
        } label: {
            HStack(spacing: 14) {
                ZStack(alignment: .bottomLeading) {
                    MusicCover(path: track.cover ?? "", size: 68, radius: 14)
                    Avatar(path: friend.avatar ?? "", size: 28, radius: 14)
                        .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 2))
                        .offset(x: -6, y: 6)
                }
                .padding(.leading, 4)

                VStack(alignment: .leading, spacing: 5) {
                    Text(friend.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(track.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(track.artistText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)
                MusicPlayButton(
                    playing: player.isPlaying(track.id),
                    loading: player.loadingId == track.id,
                    size: 38,
                    tint: player.isPlaying(track.id) ? .white : OrbitTheme.jade,
                    bg: player.isPlaying(track.id)
                        ? OrbitTheme.jade : OrbitTheme.jade.opacity(0.11)
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.regularMaterial,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.6)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var musicManagePanel: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                manageAction(Tr("导入文件"), icon: "doc.badge.plus") {
                    showBatchPick = true
                }
                manageAction(Tr("导入文件夹"), icon: "folder.badge.plus") {
                    showFolderPick = true
                }
            }
            Button {
                Task { await deletePicked() }
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text(Tr("删除选中") + " (\(pickedTracks.count))")
                    Spacer()
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.red)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Color.red.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(pickedTracks.isEmpty)

            if !busyText.isEmpty {
                Text(busyText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.6)
        }
    }

    private func manageAction(_ title: String, icon: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(OrbitTheme.jade)
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 82)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var nativeMineRow: some View {
        HStack(spacing: 0) {
            ForEach(MusicMineKind.allCases) { kind in
                Button {
                    mine = kind
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: kind.icon)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(OrbitTheme.jade)
                        Text(Tr(kind.title))
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if kind != MusicMineKind.allCases.last {
                    Divider().frame(height: 34)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func nativeTrackRow(_ track: MusicTrack) -> some View {
        Button {
            choose(track)
        } label: {
            HStack(spacing: 12) {
                if manageMode {
                    Image(systemName: pickedTracks.contains(track.id)
                          ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(pickedTracks.contains(track.id)
                                         ? OrbitTheme.jade : Color(uiColor: .secondaryLabel))
                }

                MusicCover(path: track.cover ?? "", size: 54, radius: 8)

                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(track.artistText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if !manageMode {
                    MusicPlayButton(
                        playing: player.isPlaying(track.id),
                        loading: player.loadingId == track.id,
                        size: 32,
                        tint: player.isPlaying(track.id) ? .white : OrbitTheme.jade,
                        bg: player.isPlaying(track.id)
                            ? OrbitTheme.jade : OrbitTheme.jade.opacity(0.10)
                    )
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if app.me?.ops == true && !manageMode {
                Button {
                    iconPickFor = track.id
                    showIconPick = true
                } label: {
                    Label(Tr("更换封面"), systemImage: "photo.badge.plus")
                }
            }
        }
    }

    private func nativeFriendRow(_ friend: FriendNowPlaying) -> some View {
        let track = friend.asTrack
        return Button {
            MusicPlayer.shared.toggle(track)
        } label: {
            HStack(spacing: 12) {
                Avatar(path: friend.avatar ?? "", size: 46, radius: 23)
                VStack(alignment: .leading, spacing: 3) {
                    Text(friend.name)
                        .font(.body)
                    Text(friend.line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                MusicPlayButton(
                    playing: player.isPlaying(track.id),
                    loading: player.loadingId == track.id,
                    size: 32,
                    tint: player.isPlaying(track.id) ? .white : OrbitTheme.jade,
                    bg: player.isPlaying(track.id)
                        ? OrbitTheme.jade : OrbitTheme.jade.opacity(0.10)
                )
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func choose(_ track: MusicTrack) {
        if manageMode {
            if pickedTracks.contains(track.id) {
                pickedTracks.remove(track.id)
            } else {
                pickedTracks.insert(track.id)
            }
        } else if let onSend, sendMode {
            onSend(track)
            dismiss()
        } else {
            MusicPlayer.shared.setQueue(tracks)
            MusicPlayer.shared.toggle(track)
        }
    }

    @ToolbarContentBuilder
    private var musicToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack(spacing: 10) {
                if !sendMode && tab == 1 && cats.count > 1 {
                    Menu {
                        Button {
                            cat = ""
                        } label: {
                            if cat.isEmpty { Label(Tr("全部"), systemImage: "checkmark") }
                            else { Text(Tr("全部")) }
                        }
                        ForEach(cats, id: \.self) { value in
                            Button {
                                cat = value
                            } label: {
                                if cat == value { Label(value, systemImage: "checkmark") }
                                else { Text(value) }
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel(Tr("筛选分类"))
                }

                if manageMode {
                    Button(Tr("完成")) {
                        manageMode = false
                        pickedTracks = []
                    }
                } else if app.me?.ops == true && !sendMode {
                    Button {
                        manageMode = true
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel(Tr("管理音乐"))
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {

        Group {
        if loading {
            HStack(spacing: 10) { ProgressView(); Text(Tr("正在加载…")).font(pf(15)).foregroundColor(C.subLabel) }
                .frame(maxWidth: .infinity).frame(height: 100)
            Spacer(minLength: 0)
        } else if tracks.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 30, weight: .light)).foregroundColor(C.subLabel)
                Text(Tr("曲库还没有歌（后台「音乐（听一听）」里传一首）"))
                    .font(pf(14)).foregroundColor(C.subLabel)
                    .multilineTextAlignment(.center).padding(.horizontal, 30)
            }
            .frame(maxWidth: .infinity).padding(.top, 60)
            Spacer(minLength: 0)
        } else {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if tab == 0 {

                        HStack(spacing: 8) {
                            Text(Tr("今日推荐")).font(pf(17, .semibold)).foregroundColor(C.label)
                            Spacer(minLength: 0)
                            Button { batch += 1 } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 12))
                                    Text(Tr("换一批")).font(pf(13))
                                }
                                .foregroundColor(C.subLabel)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)

                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                            GridItem(.flexible(), spacing: 12)], spacing: 14) {
                            ForEach(Array(recommend.enumerated()), id: \.element.id) { i, t in
                                bigCard(t, rank: i + 1, wide: true)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)

                        if artists.count > 1 {
                            HStack {
                                Text(Tr("推荐音乐人")).font(pf(17, .semibold)).foregroundColor(C.label)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 10)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(Array(artists.enumerated()), id: \.offset) { _, a in
                                        VStack(spacing: 6) {
                                            MusicCover(path: a.1, size: 58, radius: 29)
                                            Text(a.0).font(pf(12.5)).foregroundColor(C.label).lineLimit(1)
                                                .frame(width: 68)
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                            .padding(.bottom, 10)
                        }
                    } else if tab == 1 {

                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                            GridItem(.flexible(), spacing: 12)], spacing: 14) {
                            ForEach(Array(matched.enumerated()), id: \.offset) { _, t in
                                bigCard(t, rank: nil, wide: true)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                    } else {

                        if !friends.isEmpty {
                            ForEach(Array(friends.enumerated()), id: \.element.id) { _, f in
                                friendRow(f)
                            }
                            Text(Tr("好友最近 2 小时在听的歌"))
                                .font(pf(12)).foregroundColor(C.subLabel.opacity(0.8))
                                .frame(maxWidth: .infinity)
                                .padding(.top, 14)
                        } else {
                            VStack(spacing: 8) {
                                Text(Tr("朋友推荐还没有内容")).font(pf(14)).foregroundColor(C.subLabel)
                                Text(Tr("你在这一页放一首歌，好友的「朋友推荐」里就会看到你在听什么；\n反过来，好友在听的时候这里也会出现。"))
                                    .font(pf(12.5)).foregroundColor(C.subLabel.opacity(0.8))
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity).padding(.top, 50)
                        }
                    }
                    Spacer().frame(height: 24)
                }
            }
            .background(C.pageBg)
        }
        }

        .task { await loadFriends() }
        .onChange(of: tab) { t in if t == 2 { Task { await loadFriends() } } }

        .sheet(isPresented: $showIconPick) {
            PhotoPicker { img in
                let id = iconPickFor
                Task {
                    if let url = try? await API.shared.upload(image: img) {
                        try? await API.shared.manageSetIcon(kind: "music", id: id, cover: url)
                        tracks = await API.shared.musicTracks()
                    }
                }
            }
        }

        .fileImporter(isPresented: $showBatchPick, allowedContentTypes: [.item],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { importFiles(urls) }
        }
        .fileImporter(isPresented: $showFolderPick, allowedContentTypes: [.folder],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let dir = urls.first { importFolder(dir) }
        }
    }

    private let audioExts: Set<String> = ["mp3", "m4a", "flac", "wav", "aac", "ogg", "oga",
                                          "opus", "ape", "wma", "aiff", "aif", "amr", "mka", "mp4"]

    private func deletePicked() async {
        let ids = Array(pickedTracks)
        guard !ids.isEmpty else { return }
        do {
            try await API.shared.manageRemoveMusic(ids: ids)
            pickedTracks = []
            busyText = Tr("已删除 ") + "\(ids.count)" + Tr(" 首")
            tracks = await API.shared.musicTracks()
        } catch {
            busyText = (error as? APIError)?.errorDescription ?? "删除失败"
        }
    }

    private func importFolder(_ dir: URL) {
        let ok = dir.startAccessingSecurityScopedResource()
        if !ok { busyText = Tr("读不到这个文件夹"); return }
        var files: [URL] = []
        if let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) {
            for case let u as URL in e where audioExts.contains(u.pathExtension.lowercased()) {
                files.append(u)
            }
        }
        guard !files.isEmpty else {
            dir.stopAccessingSecurityScopedResource()
            busyText = Tr("这个文件夹里没找到音频文件")
            return
        }
        importFiles(files, holding: dir)
    }

    private func importFiles(_ urls: [URL], holding: URL? = nil) {
        let list = urls.filter { audioExts.contains($0.pathExtension.lowercased()) }
        guard !list.isEmpty else {
            holding?.stopAccessingSecurityScopedResource()
            busyText = Tr("没找到能导入的音频文件")
            return
        }
        Task {
            defer { holding?.stopAccessingSecurityScopedResource() }
            var done = 0
            for u in list {
                let scoped = u.startAccessingSecurityScopedResource()
                defer { if scoped { u.stopAccessingSecurityScopedResource() } }
                do {
                    let raw = try Data(contentsOf: u)
                    if raw.count > 60 * 1024 * 1024 { done += 1; continue }
                    let payload: [String: Any] = [
                        "dataUrl": "data:" + musicMimeFor(u.lastPathComponent) + ";base64," + raw.base64EncodedString(),
                        "filename": u.lastPathComponent
                    ]
                    let r = try await API.shared.rawUpload(payload)
                    try await API.shared.manageSaveMusic(id: "",
                                                         title: u.deletingPathExtension().lastPathComponent,
                                                         artist: "", cover: "", url: r.url, lyrics: "")
                } catch { }
                done += 1
                busyText = Tr("正在导入 ") + "\(done)/\(list.count)"
            }
            busyText = Tr("导入完成 ") + "\(done)/\(list.count)"
            tracks = await API.shared.musicTracks()
        }
    }

    private func musicMimeFor(_ name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "mp3": return "audio/mpeg"
        case "m4a", "m4r", "mp4", "aac": return "audio/mp4"
        case "wav": return "audio/wav"
        case "flac": return "audio/flac"
        case "ogg", "oga", "opus": return "audio/ogg"
        case "aiff", "aif": return "audio/aiff"
        default: return "application/octet-stream"
        }
    }

    private func friendRow(_ f: FriendNowPlaying) -> some View {
        let t = f.asTrack
        return Button { MusicPlayer.shared.toggle(t) } label: {
            HStack(spacing: 12) {
                Avatar(path: f.avatar ?? "", size: 52, radius: 12)
                VStack(alignment: .leading, spacing: 4) {
                    Text(f.name).font(pf(16, .medium)).foregroundColor(C.label).lineLimit(1)
                    Text(f.line)
                        .font(pf(12.5)).foregroundColor(C.subLabel).lineLimit(1)
                }
                Spacer(minLength: 6)
                playDot(playing: player.isPlaying(t.id), loading: player.loadingId == t.id)
            }
            .padding(.horizontal, 12).frame(height: 78)
            .background(cardFace)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16).padding(.vertical, 5)
    }

    private var cardFace: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(C.cardBg)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(C.hairline.opacity(scheme == .dark ? 1 : 0.65), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.06), radius: 7, x: 0, y: 2)
    }

    private func playDot(playing: Bool, loading: Bool) -> some View {
        MusicPlayButton(playing: playing, loading: loading, size: 34,
                        tint: playing ? .white : C.green,
                        bg: playing ? C.green : C.green.opacity(0.12))
    }

    private func rankBadge(_ n: Int) -> some View {
        let c: Color = n == 1 ? Color(hex: 0xFA3B4B)
            : (n == 2 ? Color(hex: 0xFF8A00) : (n == 3 ? Color(hex: 0xF7B500) : Color.black.opacity(0.45)))
        return Text("\(n)")
            .font(pf(11, .bold))
            .foregroundColor(.white)
            .frame(width: 19, height: 19)
            .background(Circle().fill(c))
            .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.2))
            .offset(x: -5, y: -5)
    }

    private func checkDot(_ t: MusicTrack) -> some View {
        Image(systemName: pickedTracks.contains(t.id) ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 21))
            .foregroundColor(pickedTracks.contains(t.id) ? C.green : C.subLabel)
    }

    private func iconPickDot(_ t: MusicTrack) -> some View {
        Button {
            iconPickFor = t.id
            showIconPick = true
        } label: {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 17))
                .foregroundColor(C.green)
                .frame(width: 34, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func loadFriends() async {
        friends = await API.shared.friendsNowPlaying()
        friendsLoaded = true
    }

    private func row(_ t: MusicTrack, rank: Int? = nil) -> some View {
        rowBody(t, rank: rank)
    }

    private func bigCard(_ t: MusicTrack, rank: Int? = nil, wide: Bool = false) -> some View {

        let gridSide: CGFloat = max(120, (L.width - 16 * 2 - 12) / 2)
        let side: CGFloat = wide ? gridSide : 186
        return Button {
            if manageMode {
                if pickedTracks.contains(t.id) { pickedTracks.remove(t.id) }
                else { pickedTracks.insert(t.id) }
            } else if let onSend, sendMode {
                onSend(t)
                dismiss()
            } else {
                MusicPlayer.shared.setQueue(tracks)
                MusicPlayer.shared.toggle(t)
            }
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                ZStack(alignment: .topLeading) {
                    MusicCover(path: t.cover ?? "", size: side, radius: 14)
                    if let rank { rankBadge(rank) }

                    MusicPlayButton(playing: player.isPlaying(t.id), loading: player.loadingId == t.id,
                                    size: 38, tint: .white, bg: Color.black.opacity(0.42))
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
                Text(t.title).font(pf(15, .medium)).foregroundColor(C.label).lineLimit(1)
                Text(t.artistText).font(pf(12.5)).foregroundColor(C.subLabel).lineLimit(1)
            }
            .frame(width: side, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func rowBody(_ t: MusicTrack, rank: Int? = nil) -> some View {
        Button {
            if manageMode {
                if pickedTracks.contains(t.id) { pickedTracks.remove(t.id) }
                else { pickedTracks.insert(t.id) }
            } else if let onSend, sendMode {
                onSend(t)
                dismiss()
            } else {

                MusicPlayer.shared.setQueue(tracks)
                MusicPlayer.shared.toggle(t)
            }
        } label: {
            HStack(spacing: 12) {
                if manageMode { checkDot(t) }
                ZStack(alignment: .topLeading) {
                    MusicCover(path: t.cover ?? "", size: 58, radius: 12)

                    if let rank, !manageMode { rankBadge(rank) }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(t.title).font(pf(16, .medium)).foregroundColor(C.label).lineLimit(1)
                    Text(t.artistText).font(pf(12.5)).foregroundColor(C.subLabel).lineLimit(1)
                }
                Spacer(minLength: 8)
                playDot(playing: player.isPlaying(t.id), loading: player.loadingId == t.id)

                if app.me?.ops == true && !manageMode { iconPickDot(t) }
            }
            .padding(.horizontal, 12).frame(height: 78)
            .background(cardFace)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16).padding(.vertical, 5)
    }

}

@MainActor
final class MusicSheet: ObservableObject {
    static let shared = MusicSheet()
    @Published var open = false
    @Published var track: MusicTrack?
    func open(_ t: MusicTrack) { track = t; open = true }
    func close() { open = false }

    func applyLike(id: String, myId: String, liked: Bool, count: Int) {
        guard var t = track, t.id == id else { return }
        var list = t.likes ?? []
        if liked {
            if !list.contains(myId) { list.append(myId) }
        } else {
            list = list.filter { $0 != myId }
        }
        t.likes = list
        t.likeCount = count
        track = t
    }
}

struct MusicPlayingView: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject private var player = MusicPlayer.shared
    @ObservedObject private var sheet = MusicSheet.shared
    @Environment(\.dismiss) private var dismiss
    @State private var dragging = false
    @State private var dragValue: Double = 0

    @State private var showLyrics = false

    @State private var flipped = false

    @State private var aiText = ""
    @State private var aiBusy = false

    @State private var lastLyricLine = -1

    @State private var likedNow: Bool? = nil
    @State private var likeCountNow: Int? = nil
    @State private var shareTo = false
    @State private var shareSystem = false

    @State private var showQueue = false

    @State private var loopTick = false

    private var t: MusicTrack? { sheet.track ?? player.current }

    private func closeMe() {
        MusicSheet.shared.close()
    }

    private var liked: Bool {
        if let v = likedNow { return v }
        return (t?.likes ?? []).contains(app.me?.id ?? "")
    }
    private var likeCount: Int {
        if let n = likeCountNow { return n }
        return t?.likeCount ?? (t?.likes ?? []).count
    }

    private func playerAction(icon: String, name: String, count: Int?,
                              tint: Color, tap: @escaping () -> Void) -> some View {
        Button { tap() } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 21)).foregroundColor(tint)
                if let c = count, c > 0 {
                    Text("\(c)").font(pf(11.5)).foregroundColor(C.subLabel)
                }
                Text(name).font(pf(12)).foregroundColor(C.subLabel)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func likeIt() {
        guard let track = t else { return }
        let now = !liked
        likedNow = now
        likeCountNow = max(0, likeCount + (now ? 1 : -1))
        Task {
            if let r = await API.shared.musicLike(track.id) {
                likedNow = r.liked
                likeCountNow = r.count

                let mine = app.me?.id ?? ""
                MusicSheet.shared.applyLike(id: track.id, myId: mine, liked: r.liked, count: r.count)
                MusicPlayer.shared.applyLike(id: track.id, myId: mine, liked: r.liked, count: r.count)
            }
        }
    }

    private func refreshLike() async {
        guard let id = t?.id else { return }
        guard let fresh = await API.shared.musicTracks().first(where: { $0.id == id }) else { return }
        let mine = app.me?.id ?? ""
        likedNow = (fresh.likes ?? []).contains(mine)
        likeCountNow = fresh.likeCount ?? (fresh.likes ?? []).count
    }

    private var shareText: String {
        let title = t?.title ?? ""
        let artist = t?.artistText ?? ""
        return artist.isEmpty ? title : title + " — " + artist
    }

    private var modeIcon: String {
        let m = MusicPlayer.shared.playMode
        return m == 1 ? "repeat.1" : (m == 2 ? "shuffle" : "repeat")
    }
    private var modeName: String {
        let m = MusicPlayer.shared.playMode
        return m == 1 ? "单曲循环" : (m == 2 ? "随机播放" : "顺序播放")
    }
    private func toggleMode() {
        MusicPlayer.shared.playMode = (MusicPlayer.shared.playMode + 1) % 3
        loopTick.toggle()
    }

    private func rateText(_ v: Double) -> String {
        let s = v == floor(v) ? String(format: "%.1f", v) : String(format: "%.2f", v)
        return s + "x"
    }

    private var sleepText: String {
        let left = player.sleepLeft
        guard left > 0 else { return Tr("定时") }
        return String(format: "%02d:%02d", left / 60, left % 60)
    }

    private var playbackMenu: some View {
        Menu {
            Button {
                toggleMode()
            } label: {
                Label(Tr(modeName), systemImage: modeIcon)
            }

            Menu {
                ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { value in
                    Button {
                        MusicPlayer.shared.setRate(Float(value))
                        loopTick.toggle()
                    } label: {
                        if abs(player.rate - Float(value)) < 0.01 {
                            Label(rateText(value), systemImage: "checkmark")
                        } else {
                            Text(rateText(value))
                        }
                    }
                }
            } label: {
                Label(Lang.isEnglish
                      ? "Playback speed · \(rateText(Double(player.rate)))"
                      : "播放速度 · \(rateText(Double(player.rate)))",
                      systemImage: "gauge.with.needle")
            }

            Menu {
                ForEach([10, 20, 30, 60], id: \.self) { minutes in
                    Button("\(minutes) " + Tr("分钟")) {
                        MusicPlayer.shared.setSleep(minutes: minutes)
                        loopTick.toggle()
                    }
                }
                if player.sleepLeft > 0 {
                    Button(Tr("关闭定时"), role: .destructive) {
                        MusicPlayer.shared.setSleep(minutes: 0)
                        loopTick.toggle()
                    }
                }
            } label: {
                Label(Lang.isEnglish ? "Sleep timer · \(sleepText)"
                                     : "定时关闭 · \(sleepText)",
                      systemImage: "timer")
            }

            Divider()

            Button {
                showLyrics = true
            } label: {
                Label(Tr("查看歌词"), systemImage: "quote.bubble")
            }

            Button {
                showQueue = true
            } label: {
                Label(Tr("播放列表"), systemImage: "list.bullet")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    private func seekTo(_ sec: Double) {
        let total = player.total
        guard total > 1 else { return }
        MusicPlayer.shared.seek(min(max(0, sec / total), 1))
    }

    private var coverLyricSwitch: some View {
        Picker(Tr("显示内容"), selection: $flipped) {
            Text(Tr("封面")).tag(false)
            Text(Tr("歌词")).tag(true)
        }
        .pickerStyle(.segmented)
        .frame(width: 184)
    }

    private var queueSheet: some View {
        NavigationStack {
            List {
                if player.queue.isEmpty {
                    Section {
                        VStack(spacing: 8) {
                            Image(systemName: "music.note.list")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text(Tr("还没有播放列表"))
                                .font(.body)
                            Text(Tr("去「听一听」里点一首歌，就能在这里切上一首/下一首"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 150)
                    }
                } else {
                    Section {
                        ForEach(player.queue) { track in
                            Button {
                                MusicPlayer.shared.play(track)
                            } label: {
                                HStack(spacing: 12) {
                                    MusicCover(path: track.cover ?? "", size: 44, radius: 7)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(track.title)
                                            .font(.body)
                                            .lineLimit(1)
                                        Text(track.artistText)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 8)
                                    if player.current?.id == track.id {
                                        Image(systemName: "waveform")
                                            .foregroundStyle(OrbitTheme.jade)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(Tr("播放列表"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(Tr("完成")) { showQueue = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var musicCardJSON: String {
        guard let track = t else { return "" }
        var d: [String: Any] = ["id": track.id, "title": track.title, "url": track.url]
        if let v = track.artist, !v.isEmpty { d["artist"] = v }
        if let v = track.cover, !v.isEmpty { d["cover"] = v }
        guard let data = try? JSONSerialization.data(withJSONObject: d),
              let s = String(data: data, encoding: .utf8) else { return "" }
        return s
    }

    private var artworkSide: CGFloat {
        min(304, L.width - 64, L.height * 0.38)
    }

    private var artworkPanel: some View {
        ZStack {
            if flipped {
                backFace
                    .padding(18)
                    .frame(width: artworkSide, height: artworkSide)
                    .background {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.regularMaterial)
                    }
                    .transition(.opacity)
            } else {
                MusicCover(path: t?.cover ?? "", size: artworkSide, radius: 18)
                    .shadow(color: .black.opacity(0.14), radius: 22, y: 12)
                    .transition(.opacity)
            }
        }
        .frame(width: artworkSide, height: artworkSide)
        .animation(.easeInOut(duration: 0.20), value: flipped)
    }

    private var backFace: some View {
        let raw = (t?.lyrics ?? "").isEmpty ? aiText : (t?.lyrics ?? "")
        return VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "text.alignleft").font(.system(size: 11)).foregroundColor(C.subLabel)
                Text(t?.title ?? "").font(pf(12.5, .medium)).foregroundColor(C.label).lineLimit(1)
                Spacer(minLength: 0)
                if aiBusy {
                    ProgressView().scaleEffect(0.6)
                } else {
                    Button { aiRecognize() } label: {
                        Text(aiText.isEmpty ? Tr("AI 识别歌词") : Tr("重新识别"))
                            .font(pf(11.5)).foregroundColor(C.green)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 6)

            LyricsView(raw: raw, seconds: player.seconds, duration: player.total) { sec in
                seekTo(sec)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func aiRecognize() {
        guard let track = t, !aiBusy else { return }
        aiBusy = true
        Task {
            guard await FileSpeech.authorize() else {
                aiText = Tr("需要先允许「语音识别」权限")
                aiBusy = false
                return
            }
            guard let url = MusicPlayer.shared.localURL(track) ?? API.shared.assetURL(track.url) else {
                aiText = Tr("拿不到这首歌的音频")
                aiBusy = false
                return
            }
            if !FileManager.default.fileExists(atPath: url.path), let remote = API.shared.assetURL(track.url),
               let data = try? await API.shared.assetData(remote), let local = MusicPlayer.shared.localURL(track) {
                try? data.write(to: local, options: .atomic)
            }
            let file = MusicPlayer.shared.localURL(track) ?? url
            let text = await FileSpeech.recognize(url: file, timeout: 90)
            aiText = text.isEmpty ? Tr("没识别出来（歌曲背景音太吵时识别会比较难）") : text
            if !text.isEmpty, app.me?.ops == true {
                try? await API.shared.manageSaveMusic(id: track.id, title: track.title,
                                                      artist: track.artist ?? "", cover: track.cover ?? "",
                                                      url: track.url, lyrics: text)
            }
            aiBusy = false
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    artworkPanel
                        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                flipped.toggle()
                            }
                        }

                    VStack(spacing: 5) {
                        Text(t?.title ?? "")
                            .font(.title2.weight(.bold))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                        Text(t?.artistText ?? "")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 2) {
                        Slider(value: Binding(
                            get: { dragging ? dragValue : player.progress },
                            set: { dragValue = $0 }
                        ), in: 0...1, onEditingChanged: { editing in
                            dragging = editing
                            if !editing { MusicPlayer.shared.seek(dragValue) }
                        })
                        .tint(OrbitTheme.jade)

                        HStack {
                            Text(musicTime(dragging ? dragValue * player.total : player.seconds))
                            Spacer()
                            Text(musicTime(player.total))
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 34) {
                        Button {
                            MusicPlayer.shared.prev()
                        } label: {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 28, weight: .semibold))
                        }
                        .foregroundStyle(player.queue.count > 1
                                         ? Color.primary : Color.secondary.opacity(0.45))
                        .accessibilityLabel(Tr("上一首"))

                        Button {
                            if let t { MusicPlayer.shared.toggle(t) }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(OrbitTheme.jade)
                                    .frame(width: 70, height: 70)
                                if player.loadingId == (t?.id ?? "") {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: player.playing ? "pause.fill" : "play.fill")
                                        .font(.system(size: 28, weight: .bold))
                                        .foregroundStyle(.white)
                                        .offset(x: player.playing ? 0 : 2)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(player.playing ? Tr("暂停") : Tr("播放"))

                        Button {
                            MusicPlayer.shared.next()
                        } label: {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 28, weight: .semibold))
                        }
                        .foregroundStyle(player.queue.count > 1
                                         ? Color.primary : Color.secondary.opacity(0.45))
                        .accessibilityLabel(Tr("下一首"))
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 0) {
                        playerAction(
                            icon: liked ? "heart.fill" : "heart",
                            name: Tr("赞"),
                            count: likeCount,
                            tint: liked ? Color(hex: 0xFF5A5A) : Color.primary
                        ) {
                            likeIt()
                        }
                        playerAction(
                            icon: "arrowshape.turn.up.right",
                            name: Tr("转发"),
                            count: t?.shareCount ?? 0,
                            tint: Color.primary
                        ) {
                            shareTo = true
                        }
                        playerAction(
                            icon: "list.bullet",
                            name: Tr("播放列表"),
                            count: player.queue.count,
                            tint: Color.primary
                        ) {
                            showQueue = true
                        }
                        playerAction(
                            icon: "square.and.arrow.up",
                            name: Tr("分享"),
                            count: nil,
                            tint: Color.primary
                        ) {
                            shareSystem = true
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, max(28, L.safeBottom + 16))
            }
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        closeMe()
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .accessibilityLabel(Tr("关闭"))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            showLyrics = true
                        } label: {
                            Image(systemName: "quote.bubble")
                        }
                        .accessibilityLabel(Tr("查看歌词"))
                        playbackMenu
                    }
                }
            }
            .simultaneousGesture(DragGesture(minimumDistance: 12).onEnded { value in
                if value.translation.height > 90,
                   abs(value.translation.height) > abs(value.translation.width) * 1.2 {
                    closeMe()
                }
            })
            .sheet(isPresented: $shareTo) {
                ForwardPickerView(items: [ForwardItem(kind: "music", content: musicCardJSON)]) {
                    if let track = t { Task { await API.shared.musicShareCount(track.id) } }
                }
                .environmentObject(app)
            }
            .sheet(isPresented: $shareSystem) {
                ShareSheet(items: [shareText])
            }
            .sheet(isPresented: $showQueue) {
                queueSheet
            }
            .fullScreenCover(isPresented: $showLyrics) {
                MusicLyricsView(track: t) { showLyrics = false }
                    .environmentObject(app)
            }
            .onAppear {
                if let t, player.current?.id != t.id { MusicPlayer.shared.play(t) }
                Task { await refreshLike() }
            }
            .onDisappear { MusicSheet.shared.close() }
            .tint(OrbitTheme.jade)
        }
        .swipeBack { closeMe() }
    }
}
