import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import UIKit

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

extension MusicTrack {
    var displayCategory: String {
        let explicit = (category ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicit.isEmpty { return Tr(explicit) }
        if (lyrics ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Tr("纯音乐")
        }
        let text = title + " " + artistText + " " + String((lyrics ?? "").prefix(240))
        if text.unicodeScalars.contains(where: {
            (0x1100...0x11FF).contains($0.value) || (0xAC00...0xD7AF).contains($0.value)
        }) {
            return Tr("韩语")
        }
        if text.unicodeScalars.contains(where: { (0x3040...0x30FF).contains($0.value) }) {
            return Tr("日语")
        }
        if text.unicodeScalars.contains(where: {
            (0x3400...0x9FFF).contains($0.value) || (0xF900...0xFAFF).contains($0.value)
        }) {
            return Tr("华语")
        }
        return Tr("欧美")
    }
}

private func recommendedMusicQueue(_ tracks: [MusicTrack],
                                   mode: CopyMode,
                                   myId: String,
                                   recentIds: [String]) -> [MusicTrack] {
    let liked = myId.isEmpty ? [] : tracks.filter { ($0.likes ?? []).contains(myId) }
    let recentSet = Set(recentIds)
    let recentTracks = tracks.filter { recentSet.contains($0.id) }
    let tasteTracks = liked + recentTracks
    let likedIds = Set(liked.map(\.id))

    var artistAffinity: [String: Int] = [:]
    var categoryAffinity: [String: Int] = [:]
    var recentWeight: [String: Int] = [:]
    var userTracks: [String: Set<String>] = [:]
    var neighborAffinity: [String: Int] = [:]

    for track in liked where track.artistText != "未知歌手" {
        artistAffinity[track.artistText, default: 0] += 32
    }
    for track in liked where !track.displayCategory.isEmpty {
        categoryAffinity[track.displayCategory, default: 0] += 15
    }
    for (index, id) in recentIds.prefix(80).enumerated() {
        recentWeight[id] = max(16, 128 - index * 2)
        if let track = recentTracks.first(where: { $0.id == id }) {
            if track.artistText != "未知歌手" {
                artistAffinity[track.artistText, default: 0] += max(4, 26 - index / 3)
            }
            if !track.displayCategory.isEmpty {
                categoryAffinity[track.displayCategory, default: 0] += max(2, 12 - index / 6)
            }
        }
    }

    for track in tracks {
        for userId in Set(track.likes ?? []) where !userId.isEmpty {
            userTracks[userId, default: []].insert(track.id)
        }
    }
    if !myId.isEmpty, !likedIds.isEmpty {
        for (userId, ids) in userTracks where userId != myId {
            let overlap = ids.intersection(likedIds).count
            guard overlap > 0 else { continue }
            let strength = min(90, overlap * overlap * 18)
            for id in ids.subtracting(likedIds) {
                neighborAffinity[id, default: 0] += strength
            }
        }
    }

    let profileReady = !liked.isEmpty || !recentIds.isEmpty

    func score(_ track: MusicTrack) -> Int {
        let likedTrack = !myId.isEmpty && (track.likes ?? []).contains(myId)
        let recent = recentWeight[track.id] ?? 0
        let artist = artistAffinity[track.artistText] ?? 0
        let category = categoryAffinity[track.displayCategory] ?? 0
        let neighbor = neighborAffinity[track.id] ?? 0
        let learned = RecommendationEventStore.shared.score(track.id)
        let poolQuality = RecommendationEventStore.shared.quality(track.id)
        let exposure = RecommendationEventStore.shared.exposureCount(track.id)
        let globalHeat = (track.likeCount ?? (track.likes ?? []).count) * 4
            + (track.shareCount ?? 0) * 7

        switch mode {
        case .standard:
            return globalHeat
                + Int(learned * 14)
                + Int(poolQuality * 220)
                + (exposure == 0 ? 70 : 0)
                + neighbor * 18
                + artist * 10
                + category * 7
                + recent * 4
                + (likedTrack ? 420 : 0)
        case .fresh:
            return globalHeat
                + Int(learned * 11)
                + Int(poolQuality * 160)
                + (exposure == 0 ? 280 : 0)
                + neighbor * 34
                + artist * 16
                + category * 10
                + (likedTrack ? -1_100 : 220)
                + (recent > 0 ? -recent * 4 : 190)
        case .familiar:
            return globalHeat * 2
                + Int(learned * 22)
                + Int(poolQuality * 300)
                + (exposure < 2 ? 45 : 0)
                + neighbor * 24
                + artist * 18
                + category * 11
                + recent * 9
                + (likedTrack ? 1_800 : 0)
                + (profileReady ? 1 : 0)
        }
    }

    let ranked = tracks.enumerated()
        .map { (offset: $0.offset, track: $0.element, base: score($0.element)) }
        .sorted { lhs, rhs in
            if lhs.base != rhs.base { return lhs.base > rhs.base }
            let la = lhs.track.at ?? 0
            let ra = rhs.track.at ?? 0
            return la == ra ? lhs.offset < rhs.offset : la > ra
        }

    var remaining = ranked
    var output: [MusicTrack] = []
    output.reserveCapacity(remaining.count)
    let artistPenalty = mode == .familiar ? 82 : 180
    let categoryPenalty = mode == .familiar ? 26 : 58

    while !remaining.isEmpty {
        let window = min(14, remaining.count)
        var bestIndex = 0
        var bestScore = Int.min
        for index in 0..<window {
            let candidate = remaining[index]
            let artistRepeats = output.suffix(4).filter {
                $0.artistText == candidate.track.artistText
            }.count
            let categoryRepeats = output.suffix(6).filter {
                $0.displayCategory == candidate.track.displayCategory
            }.count
            let adjusted = candidate.base
                - artistRepeats * artistPenalty
                - categoryRepeats * categoryPenalty
            if adjusted > bestScore {
                bestScore = adjusted
                bestIndex = index
            }
        }
        output.append(remaining.remove(at: bestIndex).track)
    }
    return output
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

private struct KaraokeLyricText: View {
    let text: String
    let progress: CGFloat
    let font: Font
    let baseColor: Color
    let activeColor: Color

    var body: some View {
        ZStack(alignment: .leading) {
            Text(text)
                .font(font)
                .foregroundColor(baseColor)

            if progress > 0 {
                Text(text)
                    .font(font)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [activeColor.opacity(0.92), activeColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .shadow(color: activeColor.opacity(0.20), radius: 4)
                    .mask(alignment: .leading) {
                        LinearGradient(
                            stops: [
                                .init(color: .white, location: 0),
                                .init(color: .white,
                                      location: max(0, min(progress, 1) - 0.045)),
                                .init(color: .clear, location: min(progress, 1)),
                                .init(color: .clear, location: 1)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    }
            }
        }
        .animation(.linear(duration: 0.32), value: progress)
    }
}

private struct MusicPulseBars: View {
    let level: CGFloat
    let playing: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08, paused: !playing)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2.4) {
                ForEach(0..<7, id: \.self) { index in
                    let wave = CGFloat((sin(time * 4.4 + Double(index) * 1.16) + 1) / 2)
                    let energy: CGFloat = playing
                        ? (0.16 + level * 0.84) * (0.42 + wave * 0.58)
                        : 0.10
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [OrbitTheme.jade.opacity(0.50),
                                         OrbitTheme.jade],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: 2.2, height: 2.5 + energy * 13.5)
                }
            }
            .frame(width: 34, height: 18)
            .accessibilityHidden(true)
        }
    }
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
    private var activeProgress: CGFloat {
        guard lines.indices.contains(cur) else { return 0 }
        let start = lines[cur].time
        let end = lines.indices.contains(cur + 1)
            ? lines[cur + 1].time
            : min(player.total, start + 5)
        let span = max(0.35, end - start)
        return CGFloat(min(max((player.seconds - start) / span, 0), 1))
    }

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
                                KaraokeLyricText(
                                    text: l.text,
                                    progress: l.id == cur ? activeProgress : 0,
                                    font: pf(l.id == cur ? 20.5 : 17,
                                             l.id == cur ? .semibold : .regular),
                                    baseColor: l.id == cur
                                        ? C.label.opacity(0.32)
                                        : C.label.opacity(0.72),
                                    activeColor: C.green
                                )
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
    @Published private(set) var level: CGFloat = 0

    var player: AVAudioPlayer?

    var stream: AVPlayer?

    private var endObserver: NSObjectProtocol?
    var timer: Timer?
    private var cache: [String: Data] = [:]

    private var remoteReady = false

    private var syncedSecond: Int = -1

    private var nowId = ""
    private var nowAt = Date.distantPast
    private var listenedSeconds: Double = 0

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

    func recordPlaybackOutcome() {
        guard let current else { return }
        if listenedSeconds >= 10, progress >= 0.78 {
            RecommendationEventStore.shared.record(current.id, .complete)
        } else if listenedSeconds < 10 {
            RecommendationEventStore.shared.record(current.id, .skip, weight: 2)
        }
    }

    func next() {
        recordPlaybackOutcome()
        guard let cur = current, let i = queue.firstIndex(where: { $0.id == cur.id }) else { return }
        if playMode == 2, queue.count > 1,
           let n = queue.filter({ $0.id != cur.id }).randomElement() {
            play(n)
            return
        }
        let n = queue[(i + 1) % queue.count]
        play(n)
    }

    func prev() {
        recordPlaybackOutcome()
        guard let cur = current, let i = queue.firstIndex(where: { $0.id == cur.id }) else { return }
        if playMode == 2, queue.count > 1,
           let n = queue.filter({ $0.id != cur.id }).randomElement() {
            play(n)
            return
        }
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
        recordPlaybackOutcome()
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
        listenedSeconds = 0
        RecommendationEventStore.shared.record(t.id, .play)
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
            p.isMeteringEnabled = true
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
        player?.isMeteringEnabled = true
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
        level = 0
        stopTimer()
        syncNowPlaying()
    }

    func stop() {
        recordPlaybackOutcome()
        player?.stop()
        player = nil
        stopStream()
        playing = false
        level = 0
        current = nil
        progress = 0
        seconds = 0
        total = 0
        listenedSeconds = 0
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
        if playing {
            listenedSeconds += 0.3
        }

        if sleepElapsed() {
            sleepStopped = true
            pause()
            return
        }
        if let p = player {
            seconds = p.currentTime
            total = p.duration
            progress = p.duration > 0 ? min(1, p.currentTime / p.duration) : 0
            p.updateMeters()
            let db = p.averagePower(forChannel: 0)
            let normalized = CGFloat(max(0, min(1, (db + 48) / 48)))
            level = level * 0.54 + normalized * 0.46
        } else if let st = stream {

            let cur = CMTimeGetSeconds(st.currentTime())
            let dur = CMTimeGetSeconds(st.currentItem?.duration ?? .invalid)
            seconds = cur.isFinite ? max(0, cur) : 0
            if dur.isFinite, dur > 0 { total = dur }
            progress = (dur.isFinite && dur > 0) ? min(1, max(0, seconds / dur)) : 0
            level = 0
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
        if let current {
            RecommendationEventStore.shared.record(current.id, .complete)
        }
        playing = false
        level = 0
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
        WeChatMessageCard {
            HStack(spacing: 10) {
                ZStack(alignment: .bottomTrailing) {
                    MusicCover(path: info.cover, size: 56, radius: 12)
                    MusicPlayButton(playing: player.isPlaying(info.id),
                                    loading: player.loadingId == info.id, size: 21)
                        .offset(x: 3, y: 3)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(info.title)
                        .font(pfStyled(size: 16, weight: .semibold))
                        .foregroundColor(C.label)
                        .lineLimit(2)
                    Text(info.artist.isEmpty ? Tr("未知歌手") : info.artist)
                        .font(pfStyled(size: 12.5))
                        .foregroundColor(C.subLabel)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            Rectangle()
                .fill(Color.primary.opacity(0.065))
                .frame(height: 0.5)
                .padding(.vertical, 10)

            WeChatMessageCardFooter(symbol: "music.note", title: Tr("星言听一听"),
                                    trailing: Tr("音乐"))
        }
        .onTapGesture { onOpen() }
    }
}

struct ListenView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase

    var sendTo: Chat? = nil
    var onSend: ((MusicTrack) -> Void)? = nil
    var onLeave: (() -> Void)? = nil

    @State private var tracks: [MusicTrack] = []
    @State private var loading = true
    @State private var query = ""
    @State private var lastTracksRefresh = Date.distantPast

    @State private var tab = 0

    @State private var mine: MusicMineKind? = nil

    @State private var cat = ""

    @State private var batch = 0

    @State private var friends: [FriendNowPlaying] = []
    @State private var friendsLoaded = false

    @State private var iconPickFor = ""
    @State private var showIconPick = false
    @State private var showKTVSearch = false

    @State private var manageMode = false
    @State private var pickedTracks: Set<String> = []
    @State private var showBatchPick = false
    @State private var showFolderPick = false
    @State private var busyText = ""
    @ObservedObject private var player = MusicPlayer.shared
    @ObservedObject private var musicLibrary = MusicLibrary.shared
    @ObservedObject private var musicSheet = MusicSheet.shared
    @ObservedObject private var musicDock = MusicDockState.shared
    @ObservedObject private var copyVoice = CopyVoiceStore.shared

    private var sendMode: Bool { sendTo != nil }
    private var isAdmin: Bool { app.me?.ops == true }

    private var matched: [MusicTrack] {
        let q = query.trimmingCharacters(in: .whitespaces)
        var list = tracks
        if !cat.isEmpty { list = list.filter { musicCategory($0) == cat } }
        guard !q.isEmpty else { return list }

        return list.filter { $0.title.localizedCaseInsensitiveContains(q)
            || ($0.artist ?? "").localizedCaseInsensitiveContains(q)
            || musicCategory($0).localizedCaseInsensitiveContains(q) }
    }

    private var cats: [String] {
        let present = Set(tracks.map { musicCategory($0) })
        let preferred = [Tr("华语"), Tr("欧美"), Tr("日语"), Tr("韩语"), Tr("纯音乐"), Tr("其他")]
        var out = preferred.filter { present.contains($0) }
        out.append(contentsOf: present.subtracting(Set(out)).sorted())
        return out
    }

    private func musicCategory(_ track: MusicTrack) -> String {
        track.displayCategory
    }

    private var recommend: [MusicTrack] {
        var list = tracks
        if !query.trimmingCharacters(in: .whitespaces).isEmpty { return matched }

        list.sort { recRank($0.id) < recRank($1.id) }
        return Array(list.prefix(12))
    }

    private var homeLead: MusicTrack? {
        player.current ?? recommend.first
    }

    private var artists: [(String, String)] {
        var seen: [String: String] = [:]
        tracks.forEach { t in
            let name = (t.artist ?? "").isEmpty ? "未知歌手" : t.artist!
            if seen[name] == nil { seen[name] = t.cover ?? "" }
        }
        return seen.map { ($0.key, $0.value) }.sorted { $0.0 < $1.0 }
    }

    private func recRank(_ id: String) -> UInt64 {
        var h = UInt64(truncatingIfNeeded: batch &* 2654435761) &+ 1469598103934665603
        for b in id.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return h
    }

    var body: some View {
        if sendMode {
            libraryBody
        } else {
            playerOnlyBody
        }
    }

    private var playerOnlyBody: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            if loading && tracks.isEmpty && player.current == nil {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                    Text(Tr("正在准备音乐…"))
                        .font(pf(14, .medium))
                        .foregroundStyle(.white.opacity(0.72))
                }
            } else if tracks.isEmpty && player.current == nil {
                VStack(spacing: 12) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(.white.opacity(0.72))
                    Text(Tr("曲库暂时没有音乐"))
                        .font(pf(17, .semibold))
                        .foregroundStyle(.white)
                    Button {
                        leaveListen()
                    } label: {
                        Text(Tr("返回"))
                            .font(pf(14, .medium))
                            .foregroundStyle(.white.opacity(0.82))
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(.white.opacity(0.10), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Button {
                        Task { await refreshTracks(force: true) }
                    } label: {
                        Text(Tr("重新加载"))
                            .font(pf(14, .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 18)
                            .frame(height: 38)
                            .background(.white, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            } else {
                MusicPlayingView(onExit: leaveListen,
                                 onModeChange: selectCopyMode)
                    .transition(.opacity)
            }

            if (loading && tracks.isEmpty && player.current == nil)
                || (tracks.isEmpty && player.current == nil) {
                Button {
                    leaveListen()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(.white.opacity(0.10), in: Circle())
                        .frame(width: 48, height: 48)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 10)
                .padding(.top, 6)
                .accessibilityLabel(Tr("返回"))
            }
        }
        .task { await refreshTracks(force: true) }
    }

    private var libraryBody: some View {
        ZStack(alignment: .top) {
            if !sendMode && tab == 0 {
                immersiveMusicBackdrop
            } else {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()
                topAmbientGlow
            }

            musicList
        }
        .background((tab == 0 && !sendMode
                     ? Color.black
                     : Color(uiColor: .systemGroupedBackground)).ignoresSafeArea())
        .navigationTitle(Tr(sendMode ? "选择音乐" : "听一听"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .modifier(MusicAdminSearchModifier(enabled: isAdmin, text: $query))
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(tab == 0 && !sendMode ? .dark : nil, for: .navigationBar)
        .toolbar { musicToolbar }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !sendMode && player.current != nil {
                MusicDockedPlayerBar(fadesBackgroundWhilePlaying: !isAdmin)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }
        }
        .hidesTabBar()
        .swipeBack { leaveListen() }
        .task {
            await refreshTracks(force: true)
        }

        .fullScreenCover(item: $mine) { k in
            ZStack {
                NavigationStack {
                    MusicMinePage(kind: k).environmentObject(app)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if player.current != nil {
                        MusicDockedPlayerBar(fadesBackgroundWhilePlaying: !isAdmin)
                            .padding(.horizontal, 10)
                            .padding(.bottom, 8)
                    }
                }

                if musicSheet.open {
                    MusicPlayingView(onExit: leaveMineAndListen)
                        .transition(.move(edge: .bottom))
                        .zIndex(60)
                }
            }
            .animation(.easeOut(duration: 0.22), value: musicSheet.open)
        }
        .overlay {
            if !sendMode && musicSheet.open && mine == nil {
                MusicPlayingView(onExit: leaveListen)
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
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            Task { await refreshTracks() }
            if tab == 2 { Task { await loadFriends() } }
        }
        .task(id: tab) {
            guard tab == 2 else { return }
            while !Task.isCancelled {
                await loadFriends()
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
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
        .fullScreenCover(isPresented: $showKTVSearch) {
            KTVSongPickerView(tracks: tracks, mode: copyVoice.mode,
                              myId: app.me?.id ?? "",
                              recentIds: musicLibrary.recents.map(\.id))
        }
    }

    private func leaveListen() {
        MusicSheet.shared.close()
        if let onLeave {
            onLeave()
        } else {
            dismiss()
        }
    }

    private func leaveMineAndListen() {
        MusicSheet.shared.close()
        mine = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            leaveListen()
        }
    }

    @MainActor
    private func refreshTracks(force: Bool = false) async {
        if !force, Date().timeIntervalSince(lastTracksRefresh) < 15 { return }
        let fresh = await API.shared.musicTracks()
        if !fresh.isEmpty || tracks.isEmpty {
            tracks = fresh
        }
        lastTracksRefresh = Date()
        loading = false
        autoPlayCurrentModeIfNeeded()
    }

    private func autoPlayCurrentModeIfNeeded() {
        guard !sendMode, player.current == nil else { return }
        switch copyVoice.mode {
        case .standard:
            MusicPlayer.shared.playMode = 0
        case .fresh:
            MusicPlayer.shared.playMode = 2
        case .familiar:
            MusicPlayer.shared.playMode = 0
        }
        let selected = queue(for: copyVoice.mode)
        guard let first = selected.first else { return }
        MusicPlayer.shared.setQueue(selected)
        MusicPlayer.shared.play(first)
    }

    private var topAmbientGlow: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                RadialGradient(
                    colors: [OrbitTheme.jade.opacity(scheme == .dark ? 0.20 : 0.24), .clear],
                    center: .top,
                    startRadius: 8,
                    endRadius: 240
                )

                LinearGradient(
                    stops: [
                        .init(color: OrbitTheme.jade.opacity(scheme == .dark ? 0.06 : 0.05),
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
    }

    private var immersiveMusicBackdrop: some View {
        ZStack {
            Color.black
            if let cover = homeLead?.cover, !cover.isEmpty {
                RemoteImage(path: cover, mode: .fill, maxSide: 900)
                    .blur(radius: 64, opaque: true)
                    .scaleEffect(1.18)
                    .opacity(0.62)
            } else {
                RadialGradient(
                    colors: [OrbitTheme.jade.opacity(0.44), Color.black],
                    center: .topLeading,
                    startRadius: 20,
                    endRadius: 520
                )
            }
            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.10), location: 0),
                    .init(color: Color.black.opacity(0.42), location: 0.42),
                    .init(color: Color.black.opacity(0.78), location: 0.76),
                    .init(color: Color.black, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var musicList: some View {
        Group {
            if loading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(Tr("正在加载…"))
                        .font(pfStyled(size: 15))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if tracks.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(OrbitTheme.jade)
                    Text(Tr("曲库还没有歌（后台「音乐（听一听）」里传一首）"))
                        .font(pfStyled(size: 17))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 34)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        if !sendMode {
                            if tab != 0 {
                                musicTabRail
                                    .padding(.top, 8)
                                    .padding(.bottom, 18)
                            }
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
        HStack(spacing: 28) {
            ForEach(Array([Tr("推荐"), Tr("音乐"), Tr("朋友")].enumerated()), id: \.offset) { index, title in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { tab = index }
                } label: {
                    VStack(spacing: 5) {
                        Text(title)
                            .font(pfStyled(size: 17, weight: tab == index ? .semibold : .regular))
                            .foregroundStyle(tab == index ? Color.primary : Color.secondary)
                        Capsule()
                            .fill(tab == index ? OrbitTheme.jade : Color.clear)
                            .frame(width: 18, height: 2.5)
                    }
                    .frame(height: 38, alignment: .bottom)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var musicHomeContent: some View {
        musicHomeContentHero
            .environment(\.colorScheme, .dark)
    }

    private var immersiveTabRail: some View {
        HStack(spacing: 3) {
            ForEach(Array([Tr("推荐"), Tr("音乐"), Tr("朋友")].enumerated()), id: \.offset) { index, title in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                        tab = index
                    }
                } label: {
                    Text(title)
                        .font(pfStyled(size: 13.5, weight: tab == index ? .semibold : .medium))
                        .foregroundStyle(tab == index ? Color.black : Color.white.opacity(0.82))
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background {
                            if tab == index {
                                Capsule(style: .continuous).fill(.white)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous).stroke(.white.opacity(0.16), lineWidth: 0.6)
        }
    }

    private var discoveryArtworkSide: CGFloat {
        max(128, (L.width - 50) / 2)
    }

    private func discoveryCard(_ track: MusicTrack) -> some View {
        Button {
            choose(track)
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                ZStack(alignment: .bottomTrailing) {
                    MusicCover(path: track.cover ?? "",
                               size: discoveryArtworkSide,
                               radius: 16)
                    if player.isPlaying(track.id) {
                        Image(systemName: "waveform")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(.black.opacity(0.34), in: Circle())
                            .padding(8)
                    }
                }

                Text(track.title)
                    .font(pfStyled(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(track.artistText)
                    .font(pfStyled(size: 12.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(track.displayCategory)
                    .font(pfStyled(size: 10.5, weight: .medium))
                    .foregroundStyle(OrbitTheme.jade.opacity(0.9))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var recommendationCardWidth: CGFloat {
        max(238, L.width - 72)
    }

    private func playRecommended(_ track: MusicTrack) {
        var queue = recommend
        if let index = queue.firstIndex(where: { $0.id == track.id }) {
            queue.swapAt(0, index)
        } else if queue.isEmpty {
            queue = [track]
        }
        MusicPlayer.shared.setQueue(queue)
        MusicPlayer.shared.play(track)
        MusicSheet.shared.open(track)
    }

    private func recommendationHeroCard(_ track: MusicTrack) -> some View {
        let width = recommendationCardWidth
        let height = width * 0.75
        return Button {
            playRecommended(track)
        } label: {
            ZStack(alignment: .bottomLeading) {
                if (track.cover ?? "").isEmpty {
                    LinearGradient(
                        colors: [OrbitTheme.jade.opacity(0.92), Color(hex: 0x145E42)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                } else {
                    RemoteImage(path: track.cover ?? "", mode: .fill, maxSide: 1400)
                }

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.46),
                        .init(color: .black.opacity(0.18), location: 0.68),
                        .init(color: .black.opacity(0.78), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(track.displayCategory)
                        .font(pfStyled(size: 10.5, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(.white.opacity(0.68))
                        .textCase(.uppercase)
                    Text(track.title)
                        .font(pfStyled(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(track.artistText)
                        .font(pfStyled(size: 14, weight: .regular))
                        .foregroundStyle(.white.opacity(0.70))
                        .lineLimit(1)
                }
                .padding(16)
                .frame(width: width * 0.74, alignment: .leading)

                ZStack {
                    Circle().fill(.ultraThinMaterial)
                    Image(systemName: player.isPlaying(track.id) ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .offset(x: player.isPlaying(track.id) ? 0 : 1)
                }
                .frame(width: 44, height: 44)
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: .bottomTrailing)
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 0.6)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func recentPlaybackCard(_ track: MusicTrack) -> some View {
        Button {
            playRecommended(track)
        } label: {
            HStack(spacing: 10) {
                MusicCover(path: track.cover ?? "", size: 48, radius: 8)
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(pfStyled(size: 16, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(track.artistText)
                        .font(pfStyled(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(width: 142, alignment: .leading)
            }
            .padding(.horizontal, 9)
            .frame(width: 224, height: 64)
            .background(.thinMaterial,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var largeMusicCardSide: CGFloat {
        min(286, max(226, L.width * 0.68))
    }

    private var categoryGridSide: CGFloat {
        max(124, (L.width - 56) / 2)
    }

    private func categoryTracks(_ value: String) -> [MusicTrack] {
        value.isEmpty ? tracks : tracks.filter { musicCategory($0) == value }
    }

    private func categoryCover(_ value: String) -> String {
        categoryTracks(value).first(where: {
            !($0.cover ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })?.cover ?? ""
    }

    private func openCategory(_ value: String) {
        cat = value
        withAnimation(.easeOut(duration: 0.18)) { tab = 1 }
        let list = categoryTracks(value)
        guard !list.isEmpty else { return }
        var shuffled = list.shuffled()
        if let first = shuffled.first {
            MusicPlayer.shared.setQueue(shuffled)
            MusicPlayer.shared.playMode = 2
            MusicPlayer.shared.play(first)
        }
    }

    private func playCategoryTrack(_ track: MusicTrack) {
        let list = categoryTracks(cat)
        var queue = list.shuffled()
        if let index = queue.firstIndex(where: { $0.id == track.id }) {
            queue.swapAt(0, index)
        } else if queue.isEmpty {
            queue = [track]
        }
        MusicPlayer.shared.setQueue(queue)
        MusicPlayer.shared.playMode = 2
        MusicPlayer.shared.play(track)
        MusicSheet.shared.open(track)
    }

    private func categoryLargeCard(_ value: String) -> some View {
        let cover = categoryCover(value)
        let count = categoryTracks(value).count
        return Button {
            openCategory(value)
        } label: {
            ZStack(alignment: .bottomLeading) {
                if cover.isEmpty {
                    LinearGradient(
                        colors: [OrbitTheme.jade.opacity(0.92),
                                 Color(hex: 0x126B48)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                } else {
                    RemoteImage(path: cover, mode: .fill, maxSide: 720)
                }

                LinearGradient(
                    colors: [.clear, .black.opacity(0.68)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(value)
                        .font(pfStyled(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                    Text("\(count) " + Tr("首"))
                        .font(pfStyled(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                }
                .padding(13)

                if let current = player.current, musicCategory(current) == value {
                    Image(systemName: "waveform")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(.black.opacity(0.30), in: Circle())
                        .padding(10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: .topTrailing)
                }
            }
            .frame(width: categoryGridSide, height: categoryGridSide)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.13), lineWidth: 0.6)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func largeSongCard(_ track: MusicTrack) -> some View {
        let side = largeMusicCardSide
        return Button {
            playCategoryTrack(track)
        } label: {
            ZStack(alignment: .bottomLeading) {
                MusicCover(path: track.cover ?? "", size: side, radius: 22)

                LinearGradient(
                    colors: [.clear, .black.opacity(0.10), .black.opacity(0.78)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text(track.displayCategory)
                        .font(pfStyled(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                        .textCase(.uppercase)
                    Text(track.title)
                        .font(pfStyled(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(track.artistText)
                        .font(pfStyled(size: 13.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                }
                .padding(16)

                ZStack {
                    Circle().fill(.ultraThinMaterial)
                    Image(systemName: player.isPlaying(track.id) ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .offset(x: player.isPlaying(track.id) ? 0 : 1)
                }
                .frame(width: 42, height: 42)
                .padding(13)
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: .topTrailing)
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.15), lineWidth: 0.7)
            }
            .shadow(color: .black.opacity(0.16), radius: 20, y: 10)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var musicHomeContentHero: some View {
        if let lead = homeLead {
            let heroHeight = isAdmin
                ? min(max(500, L.height * 0.58), 660)
                : min(max(610, L.height * 0.76), 780)
            let heroStops: [Gradient.Stop] = isAdmin
                ? [
                    .init(color: .black.opacity(0.08), location: 0),
                    .init(color: .clear, location: 0.30),
                    .init(color: .black.opacity(0.30), location: 0.58),
                    .init(color: .black.opacity(0.94), location: 1)
                ]
                : [
                    .init(color: .black.opacity(0.30), location: 0),
                    .init(color: .clear, location: 0.26),
                    .init(color: .black.opacity(0.12), location: 0.46),
                    .init(color: .black.opacity(0.48), location: 0.65),
                    .init(color: .black.opacity(0.96), location: 1)
                ]
            let isCurrent = player.current?.id == lead.id
            let lyrics = MusicLyrics.parse(
                lead.lyrics ?? "",
                duration: isCurrent ? player.total : 0
            )
            let lyricIndex = MusicLyrics.current(lyrics, at: isCurrent ? player.seconds : 0)
            let currentLyric = lyrics.indices.contains(lyricIndex) ? lyrics[lyricIndex].text : ""
            let nextLyric = lyrics.indices.contains(lyricIndex + 1) ? lyrics[lyricIndex + 1].text : ""

            Button {
                MusicPlayer.shared.setQueue(isAdmin ? tracks : queue(for: copyVoice.mode))
                if !player.isPlaying(lead.id) { player.toggle(lead) }
                MusicSheet.shared.open(lead)
            } label: {
                ZStack(alignment: .bottomLeading) {
                    RemoteImage(path: lead.cover ?? "", mode: .fill, maxSide: 1600)
                        .frame(maxWidth: .infinity)
                        .frame(height: heroHeight)
                        .scaleEffect(isAdmin ? 1 : 1.035)
                        .clipped()

                    if !isAdmin {
                        HeroAtmosphere()
                            .frame(height: heroHeight)
                            .allowsHitTesting(false)
                    }

                    LinearGradient(
                        stops: heroStops,
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(isCurrent ? Tr("正在播放")
                                           : (isAdmin ? Tr("为你推荐") : copyVoice.mode.name))
                                .font(pfStyled(size: 11.5, weight: .semibold))
                                .tracking(0.8)
                                .foregroundStyle(.white.opacity(0.86))
                                .textCase(.uppercase)
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.84))
                                .frame(width: 34, height: 34)
                                .background(.black.opacity(0.20), in: Circle())
                        }

                        Spacer(minLength: 24)

                        if !currentLyric.isEmpty {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(currentLyric)
                                    .font(pfStyled(size: 16.5, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text(nextLyric.isEmpty ? " " : nextLyric)
                                    .font(pfStyled(size: 13.5, weight: .regular))
                                    .foregroundStyle(.white.opacity(0.62))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 18)
                        }

                        HStack(alignment: .bottom, spacing: 18) {
                            VStack(alignment: .leading, spacing: 7) {
                                Text(lead.title)
                                    .font(pfStyled(size: 34, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.36), radius: 18, y: 6)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.76)
                                Text(lead.artistText)
                                    .font(pfStyled(size: 15, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.72))
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 6)

                            ZStack {
                                Circle().fill(.white.opacity(0.94))
                                if player.loadingId == lead.id {
                                    ProgressView().tint(.black)
                                } else {
                                    Image(systemName: player.isPlaying(lead.id) ? "pause.fill" : "play.fill")
                                        .font(.system(size: 19, weight: .bold))
                                        .foregroundStyle(.black)
                                        .offset(x: player.isPlaying(lead.id) ? 0 : 1.5)
                                }
                            }
                            .frame(width: 58, height: 58)
                            .shadow(color: .black.opacity(0.24), radius: 16, y: 8)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 64)
                    .padding(.bottom, 24)
                }
                .frame(height: heroHeight)
                .clipped()
            }
            .buttonStyle(.plain)
            .overlay(alignment: .top) {
                immersiveTabRail
                    .padding(.top, 12)
            }
        }

        if isAdmin {
            let editorial = recommend.filter { $0.id != homeLead?.id }
            if !editorial.isEmpty {
                musicSectionHeader(Tr("为你精选"), refresh: true)
                    .padding(.top, 14)
                immersiveEditorialRail(Array(editorial.prefix(8)))
            }

            musicSectionHeader(Tr("我的音乐"))
            musicLibraryCards
                .padding(.horizontal, 18)
                .padding(.bottom, 30)

            musicSectionHeader(Tr("继续播放"))
            LazyVStack(spacing: 0) {
                ForEach(Array(recommend.filter { $0.id != homeLead?.id }.prefix(6))) { track in
                    premiumTrackRow(track)
                }
            }
        }

        Button {
            withAnimation(.easeOut(duration: 0.18)) { tab = 1 }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(OrbitTheme.jade)
                    .frame(width: 30, height: 30)
                    .background(OrbitTheme.jade.opacity(0.10), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(Tr("全部歌曲"))
                        .font(pfStyled(size: 15.5, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("\(tracks.count) " + Tr("首"))
                        .font(pfStyled(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .frame(height: 62)
            .background(Color.primary.opacity(0.035),
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 34)
    }

    @ViewBuilder
    private var musicHomeContentLegacy: some View {
        if let lead = homeLead {
            Button {
                if player.current?.id == lead.id {
                    player.toggle(lead)
                } else {
                    player.setQueue(tracks)
                    player.toggle(lead)
                }
                MusicSheet.shared.open(lead)
            } label: {
                ZStack(alignment: .bottomLeading) {
                    RemoteImage(path: lead.cover ?? "", mode: .fill, maxSide: 900)
                        .frame(height: 420)
                        .clipped()

                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.16), location: 0),
                            .init(color: .clear, location: 0.33),
                            .init(color: .black.opacity(0.34), location: 0.62),
                            .init(color: .black.opacity(0.94), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    RadialGradient(
                        colors: [Color.white.opacity(0.10), .clear],
                        center: .topTrailing,
                        startRadius: 6,
                        endRadius: 240
                    )

                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 8) {
                            Text(Tr(player.current == nil ? "今日精选" : "正在播放"))
                                .font(pfStyled(size: 12, weight: .semibold))
                                .tracking(0.8)
                                .foregroundStyle(.white.opacity(0.94))
                                .padding(.horizontal, 12)
                                .frame(height: 28)
                                .background(.black.opacity(0.22), in: Capsule())
                                .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 0.7))

                            if !lead.displayCategory.isEmpty {
                                Text(lead.displayCategory)
                                    .font(pfStyled(size: 12, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.76))
                            }
                        }

                        Spacer(minLength: 24)

                        HStack(alignment: .bottom, spacing: 16) {
                            VStack(alignment: .leading, spacing: 7) {
                                Spacer(minLength: 0)
                                Text(lead.title)
                                    .font(pfStyled(size: 32, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.78)
                                    .shadow(color: .black.opacity(0.30), radius: 10, y: 4)
                                Text(lead.artistText)
                                    .font(pfStyled(size: 15, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.76))
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 8)

                            MusicPlayButton(
                                playing: player.isPlaying(lead.id),
                                loading: player.loadingId == lead.id,
                                size: 62,
                                tint: .white,
                                bg: OrbitTheme.jade.opacity(0.96)
                            )
                            .shadow(color: OrbitTheme.jade.opacity(0.34), radius: 18, y: 8)
                        }
                    }
                    .padding(24)
                }
                .frame(height: 420)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                }
                .shadow(color: .black.opacity(scheme == .dark ? 0.32 : 0.18),
                        radius: 28, y: 16)
                .padding(.horizontal, 16)
                .padding(.bottom, 26)
            }
            .buttonStyle(.plain)
        }

        musicLibraryCards
            .padding(.horizontal, 20)
            .padding(.bottom, 34)

        Button {
            withAnimation(.easeOut(duration: 0.18)) { tab = 1 }
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Tr("全部歌曲"))
                        .font(pfStyled(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("\(tracks.count) " + Tr("首") + " · " + Tr("查看完整曲库"))
                        .font(pfStyled(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .frame(height: 66)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.6)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.bottom, 38)
    }

    private var editorialCardWidth: CGFloat {
        min(340, max(272, L.width * 0.78))
    }

    private func immersiveEditorialRail(_ list: [MusicTrack]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 14) {
                ForEach(Array(list.enumerated()), id: \.element.id) { index, track in
                    immersiveEditorialCard(track, index: index)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 2)
        }
        .padding(.bottom, 30)
    }

    private func immersiveEditorialCard(_ track: MusicTrack, index: Int) -> some View {
        let width = editorialCardWidth
        let height = min(332, width * 0.94)
        return Button {
            playRecommended(track)
        } label: {
            ZStack(alignment: .bottomLeading) {
                if (track.cover ?? "").isEmpty {
                    LinearGradient(
                        colors: [OrbitTheme.jade.opacity(0.92), Color(hex: 0x101713)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                } else {
                    RemoteImage(path: track.cover ?? "", mode: .fill, maxSide: 1000)
                }

                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.04), location: 0),
                        .init(color: .clear, location: 0.34),
                        .init(color: .black.opacity(0.24), location: 0.64),
                        .init(color: .black.opacity(0.88), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Text(String(format: "%02d", index + 1))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.74))
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .background(.black.opacity(0.24), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 0.6))
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: .topLeading)

                VStack(alignment: .leading, spacing: 8) {
                    Text(track.displayCategory.isEmpty ? Tr("精选") : track.displayCategory)
                        .font(pfStyled(size: 11, weight: .semibold))
                        .tracking(0.7)
                        .foregroundStyle(.white.opacity(0.64))
                        .textCase(.uppercase)

                    HStack(alignment: .bottom, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(track.title)
                                .font(pfStyled(size: 25, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .minimumScaleFactor(0.78)
                            Text(track.artistText)
                                .font(pfStyled(size: 14, weight: .medium))
                                .foregroundStyle(.white.opacity(0.70))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        MusicPlayButton(
                            playing: player.isPlaying(track.id),
                            loading: player.loadingId == track.id,
                            size: 48,
                            tint: .black,
                            bg: .white.opacity(0.94)
                        )
                    }
                }
                .padding(20)
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(.white.opacity(0.16), lineWidth: 0.7)
            }
            .shadow(color: .black.opacity(0.34), radius: 24, y: 14)
            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var musicLibraryCards: some View {
        HStack(spacing: 8) {
            ForEach(MusicMineKind.allCases) { kind in
                Button { mine = kind } label: {
                    VStack(alignment: .leading, spacing: 9) {
                        Image(systemName: kind.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(OrbitTheme.jade)
                            .frame(width: 32, height: 32)
                            .background(OrbitTheme.jade.opacity(0.10), in: Circle())

                        Text(Tr(kind.title))
                            .font(pfStyled(size: 12.5, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(libraryCount(kind))
                            .font(pfStyled(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .frame(height: 104)
                    .background(Color.primary.opacity(0.035),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.primary.opacity(0.045), lineWidth: 0.5)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                .font(pfStyled(size: 20, weight: .bold))
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
                    .font(pfStyled(size: 12, weight: .medium))
                    .foregroundStyle(OrbitTheme.jade)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    private func musicMixCard(_ track: MusicTrack, rank: Int) -> some View {
        Button { choose(track) } label: {
            VStack(alignment: .leading, spacing: 9) {
                ZStack(alignment: .bottomTrailing) {
                    MusicCover(path: track.cover ?? "", size: 184, radius: 20)
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
                    .font(pfStyled(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(track.artistText)
                    .font(pfStyled(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 184, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var musicCatalogContent: some View {
        if cats.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    categoryChip(Tr("全部"), selected: cat.isEmpty) {
                        openCategory("")
                    }
                    ForEach(cats, id: \.self) { value in
                        categoryChip(value, selected: cat == value) {
                            openCategory(value)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 18)
        }

        HStack(spacing: 10) {
            Text(cat.isEmpty ? Tr("全部歌曲") : cat)
                .font(pfStyled(size: 19, weight: .bold))
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            Button {
                openCategory(cat)
            } label: {
                Label(Tr("随机播放"), systemImage: "shuffle")
                    .font(pfStyled(size: 12.5, weight: .semibold))
                    .foregroundStyle(OrbitTheme.jade)
                    .padding(.horizontal, 11)
                    .frame(height: 31)
                    .background(OrbitTheme.jade.opacity(0.10), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)

        if matched.isEmpty {
            Text(Tr("这个分类还没有歌曲"))
                .font(pfStyled(size: 14))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 50)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(Array(matched.prefix(40))) { track in
                        largeSongCard(track)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 4)
            }
            .padding(.bottom, 28)
        }
    }

    private func categoryChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) { action() }
        } label: {
            VStack(spacing: 5) {
                Text(title)
                    .font(pfStyled(size: 14.5, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                Capsule()
                    .fill(selected ? OrbitTheme.jade : Color.clear)
                    .frame(width: 14, height: 2)
            }
            .frame(height: 34)
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
                        .font(pfStyled(size: 14, weight: .bold, design: .rounded))
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
                        .font(pfStyled(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(track.artistText)
                        .font(pfStyled(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(track.displayCategory)
                        .font(pfStyled(size: 10.5, weight: .medium))
                        .foregroundStyle(OrbitTheme.jade.opacity(0.86))
                }

                Spacer(minLength: 8)

                if !manageMode {
                    if player.loadingId == track.id {
                        ProgressView().scaleEffect(0.72)
                    } else {
                        Image(systemName: player.isPlaying(track.id) ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(player.isPlaying(track.id) ? OrbitTheme.jade : Color.secondary)
                            .frame(width: 30, height: 30)
                    }
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
                    .font(pfStyled(size: 17, weight: .semibold))
                Text(Tr("你在这一页放一首歌，好友的「朋友推荐」里就会看到你在听什么；\n反过来，好友在听的时候这里也会出现。"))
                    .font(pfStyled(size: 13))
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
                .font(pfStyled(size: 12))
                .foregroundStyle(.tertiary)
                .padding(.top, 14)
        }
    }

    private func premiumFriendCard(_ friend: FriendNowPlaying) -> some View {
        let track = friend.asTrack
        return Button {
            MusicPlayer.shared.toggle(track)
            MusicSheet.shared.open(track)
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
                        .font(pfStyled(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(track.title)
                        .font(pfStyled(size: 17, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(track.artistText)
                        .font(pfStyled(size: 12))
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
                .font(pfStyled(size: 15, weight: .medium))
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
                    .font(pfStyled(size: 13))
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
                    .font(pfStyled(size: 12, weight: .medium))
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
                            .font(pfStyled(size: 12))
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
                        .font(pfStyled(size: 17))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(track.artistText)
                        .font(pfStyled(size: 12))
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
            MusicSheet.shared.open(track)
        } label: {
            HStack(spacing: 12) {
                Avatar(path: friend.avatar ?? "", size: 46, radius: 23)
                VStack(alignment: .leading, spacing: 3) {
                    Text(friend.name)
                        .font(pfStyled(size: 17))
                    Text(friend.line)
                        .font(pfStyled(size: 12))
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
            MusicSheet.shared.open(track)
        }
    }

    @ToolbarContentBuilder
    private var musicToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            HStack(spacing: 2) {
                Button {
                    leaveListen()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 38, height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Tr("返回"))

                if !sendMode && !isAdmin {
                    Button {
                        showKTVSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 36, height: 38)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Tr("点歌台"))
                }
            }
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            HStack(spacing: 10) {
                if !sendMode && !isAdmin {
                    copyModeMenu
                }

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

    private var copyModeMenu: some View {
        Menu {
            Section(Tr("语言模式")) {
                ForEach(CopyMode.allCases) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selectCopyMode(mode)
                        }
                    } label: {
                        Label((copyVoice.mode == mode ? "✓ " : "") + mode.name,
                              systemImage: mode.symbol)
                    }
                }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.16), OrbitTheme.jade.opacity(0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [.white.opacity(0.50), OrbitTheme.jade.opacity(0.48),
                                     .white.opacity(0.16), .white.opacity(0.50)],
                            center: .center
                        ),
                        lineWidth: 0.8
                    )
                Image(systemName: copyVoice.mode.symbol)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .shadow(color: OrbitTheme.jade.opacity(0.28), radius: 4)
            }
            .frame(width: 34, height: 34)
            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
            .contentShape(Circle())
        }
        .accessibilityLabel(Tr("语言模式"))
        .accessibilityValue(copyVoice.mode.name)
    }

    private func selectCopyMode(_ mode: CopyMode) {
        MusicPlayer.shared.recordPlaybackOutcome()
        copyVoice.mode = mode
        guard !sendMode, !tracks.isEmpty else { return }

        switch mode {
        case .standard:
            MusicPlayer.shared.playMode = 0
        case .fresh:
            MusicPlayer.shared.playMode = 2
        case .familiar:
            MusicPlayer.shared.playMode = 0
        }
        let selected = queue(for: mode)
        guard let first = selected.first else { return }
        MusicPlayer.shared.setQueue(selected)
        MusicPlayer.shared.play(first)
    }

    private func queue(for mode: CopyMode) -> [MusicTrack] {
        recommendedMusicQueue(tracks, mode: mode, myId: app.me?.id ?? "",
                              recentIds: musicLibrary.recents.map(\.id))
    }

    @ViewBuilder
    private var content: some View {

        Group {
        if loading {
            HStack(spacing: 10) { ProgressView(); Text(Tr("正在加载…")).font(pf(15)).foregroundColor(C.subLabel) }
                .frame(maxWidth: .infinity).frame(height: 100)
            Spacer(minLength: 0)
        } else if tracks.isEmpty {
            VStack(spacing: 7) {
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
                            Text(Tr("全部歌曲")).font(pf(17, .semibold)).foregroundColor(C.label)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)

                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                            GridItem(.flexible(), spacing: 12)], spacing: 14) {
                            ForEach(Array(tracks.enumerated()), id: \.element.id) { i, t in
                                bigCard(t, rank: i + 1, wide: true)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)

                        if artists.count > 1 {
                            HStack {
                                Text(Tr("音乐人")).font(pf(17, .semibold)).foregroundColor(C.label)
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
        return Button {
            MusicPlayer.shared.toggle(t)
            MusicSheet.shared.open(t)
        } label: {
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
        if let fresh = await API.shared.friendsNowPlaying() {
            friends = fresh
            friendsLoaded = true
        }
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
                MusicSheet.shared.open(t)
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
                MusicSheet.shared.open(t)
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

private struct MusicAdminSearchModifier: ViewModifier {
    let enabled: Bool
    @Binding var text: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.searchable(
                text: $text,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: Text(Tr("搜索歌名 / 歌手 / 分类"))
            )
        } else {
            content
        }
    }
}

private struct HeroAtmosphere: View {
    @State private var drifting = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [OrbitTheme.jade.opacity(0.30), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: max(geo.size.width, geo.size.height) * 0.46
                        )
                    )
                    .frame(width: geo.size.width * 1.28,
                           height: geo.size.width * 1.28)
                    .blur(radius: 34)
                    .offset(
                        x: drifting ? geo.size.width * 0.18 : geo.size.width * -0.14,
                        y: drifting ? -geo.size.height * 0.16 : -geo.size.height * 0.03
                    )

                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [Color(hex: 0xFFB45B).opacity(0.16), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: geo.size.width * 0.46
                        )
                    )
                    .frame(width: geo.size.width * 0.94,
                           height: geo.size.height * 0.42)
                    .blur(radius: 44)
                    .offset(
                        x: drifting ? -geo.size.width * 0.20 : geo.size.width * 0.20,
                        y: geo.size.height * 0.18
                    )
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .blendMode(.screen)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 11).repeatForever(autoreverses: true)) {
                drifting = true
            }
        }
    }
}

struct KTVSongPickerView: View {
    let tracks: [MusicTrack]
    let mode: CopyMode
    let myId: String
    let recentIds: [String]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var query = ""
    @State private var category = ""
    @State private var selected: MusicTrack?
    @State private var exposedIds = Set<String>()
    @FocusState private var searchFocused: Bool

    private var categories: [String] {
        var seen = Set<String>()
        return tracks.compactMap {
            let value = $0.displayCategory
            return !value.isEmpty && seen.insert(value).inserted ? value : nil
        }
        .sorted()
    }

    private var results: [MusicTrack] {
        let key = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return tracks.filter { track in
            let categoryOK = category.isEmpty || track.displayCategory == category
            guard categoryOK else { return false }
            guard !key.isEmpty else { return true }
            return track.title.localizedCaseInsensitiveContains(key)
                || track.artistText.localizedCaseInsensitiveContains(key)
                || track.displayCategory.localizedCaseInsensitiveContains(key)
        }
    }

    var body: some View {
        ZStack {
            ktvBackdrop

            VStack(spacing: 0) {
                header
                searchField
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                categoryRail
                    .padding(.top, 12)

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 9) {
                        if results.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "music.note.list")
                                    .font(.system(size: 34, weight: .light))
                                Text(Tr("没有找到歌曲"))
                                    .font(pfStyled(size: 17, weight: .semibold))
                                Text(Tr("换个关键词试试"))
                                    .font(pfStyled(size: 13.5))
                                    .foregroundStyle(.secondary)
                            }
                            .foregroundStyle(.white.opacity(0.72))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 90)
                        } else {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, track in
                                songRow(track, index: index + 1)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 120)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            selectionDock
        }
        .statusBarHidden(false)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                searchFocused = true
            }
        }
    }

    private var ktvBackdrop: some View {
        ZStack {
            Color(hex: 0x070B0A)
            RadialGradient(
                colors: [OrbitTheme.jade.opacity(scheme == .dark ? 0.34 : 0.26), .clear],
                center: .topLeading,
                startRadius: 16,
                endRadius: 430
            )
            RadialGradient(
                colors: [Color(hex: 0xFFB45B).opacity(0.12), .clear],
                center: .bottomTrailing,
                startRadius: 8,
                endRadius: 360
            )
            LinearGradient(
                colors: [.black.opacity(0.04), .black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Tr("关闭"))

            VStack(alignment: .leading, spacing: 2) {
                Text(Tr("点歌台"))
                    .font(pfStyled(size: 23, weight: .bold, design: .rounded))
                Text("\(mode.name) · \(tracks.count) " + Tr("首"))
                    .font(pfStyled(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.56))
            }
            Spacer(minLength: 0)
            Image(systemName: "mic.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(OrbitTheme.jade)
                .frame(width: 38, height: 38)
                .background(OrbitTheme.jade.opacity(0.12), in: Circle())
                .overlay(Circle().stroke(OrbitTheme.jade.opacity(0.24), lineWidth: 0.7))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.top, max(8, L.safeTop + 2))
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.52))
            TextField("", text: $query,
                      prompt: Text(Tr("搜索歌名、歌手或分类"))
                        .foregroundColor(.white.opacity(0.42)))
                .focused($searchFocused)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .foregroundStyle(.white)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.42))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 13)
        .frame(height: 46)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 0.7)
        }
    }

    private var categoryRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip("", Tr("全部"))
                ForEach(categories, id: \.self) { value in
                    categoryChip(value, value)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 3)
        }
    }

    private func categoryChip(_ value: String, _ title: String) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) { category = value }
        } label: {
            Text(title)
                .font(pfStyled(size: 13, weight: category == value ? .semibold : .medium))
                .foregroundStyle(category == value ? Color.black : Color.white.opacity(0.72))
                .padding(.horizontal, 13)
                .frame(height: 31)
                .background(
                    category == value ? Color.white : Color.white.opacity(0.08),
                    in: Capsule(style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }

    private func songRow(_ track: MusicTrack, index: Int) -> some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                selected = track
            }
            RecommendationEventStore.shared.record(track.id, .click)
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                RecommendationEventStore.shared.record(track.id, .search)
            }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(spacing: 12) {
                Text(String(format: "%02d", index))
                    .font(pfStyled(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(selected?.id == track.id ? OrbitTheme.jade : .white.opacity(0.34))
                    .frame(width: 22)

                MusicCover(path: track.cover ?? "", size: 54, radius: 10)

                VStack(alignment: .leading, spacing: 5) {
                    Text(track.title)
                        .font(pfStyled(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(track.artistText)
                            .lineLimit(1)
                        Text("·")
                        Text(track.displayCategory)
                            .lineLimit(1)
                    }
                    .font(pfStyled(size: 12))
                    .foregroundStyle(.white.opacity(0.52))
                }

                Spacer(minLength: 8)
                Image(systemName: selected?.id == track.id ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(selected?.id == track.id ? OrbitTheme.jade : .white.opacity(0.32))
            }
            .padding(.horizontal, 12)
            .frame(height: 74)
            .background(
                selected?.id == track.id ? OrbitTheme.jade.opacity(0.10) : Color.white.opacity(0.045),
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(selected?.id == track.id
                            ? OrbitTheme.jade.opacity(0.42)
                            : Color.white.opacity(0.07),
                            lineWidth: 0.7)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear {
            if exposedIds.insert(track.id).inserted {
                RecommendationEventStore.shared.record(track.id, .exposure)
            }
        }
    }

    private var selectionDock: some View {
        HStack(spacing: 12) {
            if let selected {
                MusicCover(path: selected.cover ?? "", size: 44, radius: 9)
                VStack(alignment: .leading, spacing: 3) {
                    Text(selected.title)
                        .font(pfStyled(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(selected.artistText)
                        .font(pfStyled(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Button {
                    startSinging(selected)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "mic.fill")
                        Text(Tr("开始演唱"))
                    }
                    .font(pfStyled(size: 14.5, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .frame(height: 42)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: 0xDDF7B7), OrbitTheme.jade],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Capsule(style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "hand.tap.fill")
                    .foregroundStyle(OrbitTheme.jade)
                Text(Tr("先选一首歌"))
                    .font(pfStyled(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 64)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.13), lineWidth: 0.7)
        }
        .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
        .padding(.horizontal, 10)
        .padding(.bottom, max(8, L.safeBottom * 0.32))
    }

    private func startSinging(_ track: MusicTrack) {
        MusicPlayer.shared.recordPlaybackOutcome()
        switch mode {
        case .standard:
            MusicPlayer.shared.playMode = 0
        case .fresh:
            MusicPlayer.shared.playMode = 2
        case .familiar:
            MusicPlayer.shared.playMode = 0
        }
        var queue = recommendedMusicQueue(tracks, mode: mode, myId: myId,
                                          recentIds: recentIds)
        queue.removeAll { $0.id == track.id }
        queue.insert(track, at: 0)
        MusicPlayer.shared.setQueue(queue)
        MusicPlayer.shared.play(track)
        dismiss()
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

private struct FullPlayerAmbient: View {
    let track: MusicTrack?
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var player = MusicPlayer.shared
    @State private var drifting = false

    private var ambientCover: String {
        return track?.cover ?? ""
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(uiColor: .systemBackground)

                if !ambientCover.isEmpty {
                    RemoteImage(path: ambientCover, mode: .fill, maxSide: 1400)
                        .frame(width: max(640, geo.size.width * 1.52),
                               height: max(760, geo.size.height * 1.52))
                        .scaleEffect((drifting ? 1.30 : 1.18) + player.level * 0.08)
                        .offset(x: drifting ? geo.size.width * 0.075 : -geo.size.width * 0.055,
                                y: drifting ? -geo.size.height * 0.035 : geo.size.height * 0.055)
                        .blur(radius: 76, opaque: false)
                        .saturation(scheme == .dark ? 1.52 : 1.36)
                        .brightness(scheme == .dark ? 0.015 : 0.055)
                        .opacity((scheme == .dark ? 0.64 : 0.52)
                                 + Double(player.level) * 0.08)
                        .id(ambientCover)
                        .transition(.opacity)

                    RemoteImage(path: ambientCover, mode: .fill, maxSide: 820)
                        .frame(width: max(420, geo.size.width * 0.92),
                               height: max(420, geo.size.height * 0.78))
                        .offset(x: geo.size.width * 0.20, y: -geo.size.height * 0.22)
                        .blur(radius: 110, opaque: false)
                        .saturation(1.46)
                        .blendMode(scheme == .dark ? .screen : .softLight)
                        .opacity((scheme == .dark ? 0.24 : 0.18)
                                 + Double(player.level) * 0.10)
                        .id("detail-\(ambientCover)")
                        .transition(.opacity)
                }

                RadialGradient(
                    colors: [
                        OrbitTheme.jade.opacity(scheme == .dark ? 0.22 : 0.14),
                        Color.clear
                    ],
                    center: .topTrailing,
                    startRadius: 10,
                    endRadius: max(geo.size.width, geo.size.height) * 0.82
                )

                LinearGradient(
                    colors: [
                        Color.white.opacity(scheme == .dark ? 0.06 : 0.20),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                LinearGradient(
                    stops: [
                        .init(color: Color(uiColor: .systemBackground).opacity(0.01), location: 0),
                        .init(color: Color(uiColor: .systemBackground)
                            .opacity(scheme == .dark ? 0.08 : 0.10), location: 0.42),
                        .init(color: Color(uiColor: .systemBackground)
                            .opacity(scheme == .dark ? 0.42 : 0.46), location: 0.78),
                        .init(color: Color(uiColor: .systemBackground)
                            .opacity(scheme == .dark ? 0.76 : 0.78), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear { drifting = true }
        .animation(.easeInOut(duration: 14).repeatForever(autoreverses: true),
                   value: drifting)
        .animation(.linear(duration: 0.28), value: player.level)
        .animation(.easeInOut(duration: 0.4), value: player.playing)
        .animation(.easeInOut(duration: 0.8), value: ambientCover)
    }
}

struct MusicPlayingView: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject private var player = MusicPlayer.shared
    @ObservedObject private var sheet = MusicSheet.shared
    @ObservedObject private var copyVoice = CopyVoiceStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    var onExit: (() -> Void)? = nil
    var onModeChange: ((CopyMode) -> Void)? = nil
    @State private var dragging = false
    @State private var dragValue: Double = 0

    @State private var flipped = false

    @State private var aiText = ""
    @State private var aiBusy = false

    @State private var lastLyricLine = -1

    @State private var likedNow: Bool? = nil
    @State private var likeCountNow: Int? = nil
    @State private var heartBurst = false
    @State private var shareTo = false
    @State private var shareSystem = false

    @State private var showQueue = false

    @State private var loopTick = false
    @State private var isLandscape = false

    private var t: MusicTrack? { player.current ?? sheet.track }
    private var lyricLines: [MusicLyricLine] {
        MusicLyrics.parse(t?.lyrics ?? "", duration: player.total)
    }
    private var lyricIndex: Int {
        let index = MusicLyrics.current(lyricLines, at: player.seconds)
        return index < 0 ? 0 : index
    }
    private var currentLyricProgress: CGFloat {
        guard lyricLines.indices.contains(lyricIndex) else { return 0 }
        let start = lyricLines[lyricIndex].time
        let end = lyricLines.indices.contains(lyricIndex + 1)
            ? lyricLines[lyricIndex + 1].time
            : min(player.total, start + 5)
        let span = max(0.35, end - start)
        return CGFloat(min(max((player.seconds - start) / span, 0), 1))
    }

    private func closeMe() {
        PushCenter.setMusicLandscape(false)
        MusicSheet.shared.close()
        onExit?()
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
                              tint: Color, burst: Bool = false, compact: Bool = false,
                              tap: @escaping () -> Void) -> some View {
        Button { tap() } label: {
            VStack(spacing: compact ? 1 : 3) {
                ZStack {
                    if burst { HeartBurst(intensity: 1.35) }
                    Image(systemName: icon)
                        .font(.system(size: compact ? 17.5 : 21, weight: .semibold))
                        .foregroundColor(tint)
                }
                if let c = count, c > 0 {
                    Text("\(c)")
                        .font(pf(compact ? 10 : 11.5))
                        .foregroundColor(.white.opacity(0.50))
                }
                Text(name)
                    .font(pf(compact ? 10.5 : 12))
                    .foregroundColor(.white.opacity(0.64))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func likeIt() {
        guard let track = t else { return }
        let now = !liked
        RecommendationEventStore.shared.record(track.id, now ? .like : .unlike)
        likedNow = now
        likeCountNow = max(0, likeCount + (now ? 1 : -1))
        if now {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            heartBurst = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                heartBurst = false
            }
        }
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

    private var lyricsViewport: some View {
        Group {
            if lyricLines.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 24, weight: .light))
                    Text(Tr("这首歌还没有歌词"))
                        .font(pfStyled(size: 14, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 13) {
                            Color.clear.frame(height: 42)
                            ForEach(lyricLines) { line in
                                KaraokeLyricText(
                                    text: line.text,
                                    progress: line.id == lyricIndex ? currentLyricProgress : 0,
                                    font: .system(
                                        size: line.id == lyricIndex ? 22 : 17,
                                        weight: line.id == lyricIndex ? .semibold : .regular
                                    ),
                                    baseColor: line.id == lyricIndex
                                        ? Color.primary.opacity(0.30)
                                        : Color.primary.opacity(0.62),
                                    activeColor: OrbitTheme.jade
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .id(line.id)
                                .contentShape(Rectangle())
                                .onTapGesture { seekTo(line.time) }
                            }
                            Color.clear.frame(height: 48)
                        }
                        .padding(.horizontal, 12)
                    }
                    .onAppear {
                        proxy.scrollTo(lyricIndex, anchor: .center)
                    }
                    .onChange(of: lyricIndex) { index in
                        withAnimation(.easeInOut(duration: 0.46)) {
                            proxy.scrollTo(index, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var landscapeControlStrip: some View {
        HStack(spacing: 0) {
            transportControls(playSize: 54, iconSize: 21, spacing: 25)

            Spacer(minLength: 14)

            Button {
                likeIt()
            } label: {
                ZStack {
                    if heartBurst { HeartBurst(intensity: 1.15) }
                    Image(systemName: liked ? "heart.fill" : "heart")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(liked ? Color(hex: 0xFF4868) : Color.primary)
                }
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(liked ? Tr("取消赞") : Tr("赞"))

            Button {
                showQueue = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Tr("播放列表"))

            Button {
                shareSystem = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Tr("分享"))
        }
        .padding(.horizontal, 16)
        .frame(height: 60)
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
                                .font(pfStyled(size: 17))
                            Text(Tr("去「听一听」里点一首歌，就能在这里切上一首/下一首"))
                                .font(pfStyled(size: 13))
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
                                            .font(pfStyled(size: 17))
                                            .lineLimit(1)
                                        Text(track.artistText)
                                            .font(pfStyled(size: 12))
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

    private var portraitArtworkSide: CGFloat {
        min(360, L.width - 40, L.height * 0.43)
    }

    private func artworkSize(in size: CGSize) -> CGFloat {
        if size.width > size.height {
            return min(size.height - 44, size.width * 0.38)
        }
        return portraitArtworkSide
    }

    private func artworkPanel(side: CGFloat) -> some View {
        ZStack {
            if flipped {
                backFace
                    .padding(18)
                    .frame(width: side, height: side)
                    .background {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.regularMaterial)
                    }
                    .transition(.opacity)
            } else {
                MusicCover(path: t?.cover ?? "", size: side, radius: 24)
                    .scaleEffect(player.playing ? 1 + player.level * 0.012 : 1)
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(.white.opacity(0.18), lineWidth: 0.7)
                    }
                    .shadow(color: .black.opacity(0.22), radius: 34, y: 18)
                    .transition(.opacity)
            }
        }
        .frame(width: side, height: side)
        .background {
            if !flipped, let cover = t?.cover, !cover.isEmpty {
                RemoteImage(path: cover, mode: .fill, maxSide: 520)
                    .frame(width: side * 0.92, height: side * 0.92)
                    .scaleEffect(1.18 + player.level * 0.16)
                    .blur(radius: 40, opaque: false)
                    .saturation(1.2)
                    .opacity(player.playing
                             ? 0.18 + Double(player.level) * 0.18
                             : 0.10)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.20), value: flipped)
        .animation(.linear(duration: 0.28), value: player.level)
    }

    private var artworkPanel: some View {
        artworkPanel(side: portraitArtworkSide)
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

    private func chromeCircle<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .shadow(color: .black.opacity(0.24), radius: 5, y: 2)
    }

    private var playerModeMenu: some View {
        Menu {
            Section(Tr("推荐模式")) {
                ForEach(CopyMode.allCases) { mode in
                    Button {
                        choosePlayerMode(mode)
                    } label: {
                        Label(
                            (copyVoice.mode == mode ? "✓ " : "") + mode.name,
                            systemImage: mode.symbol
                        )
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: copyVoice.mode.symbol)
                    .font(.system(size: 9.5, weight: .semibold))
                Text(copyVoice.mode.name)
                    .font(pf(10.5, .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .opacity(0.68)
            }
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 8)
            .frame(height: 23)
            .background(.white.opacity(0.10), in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Tr("推荐模式"))
        .accessibilityValue(copyVoice.mode.name)
    }

    private func choosePlayerMode(_ mode: CopyMode) {
        if let onModeChange {
            onModeChange(mode)
            return
        }
        MusicPlayer.shared.recordPlaybackOutcome()
        copyVoice.mode = mode
        switch mode {
        case .standard, .familiar:
            MusicPlayer.shared.playMode = 0
        case .fresh:
            MusicPlayer.shared.playMode = 2
        }
    }

    private func playerTopBar(landscape: Bool) -> some View {
        let artist = (t?.artistText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        return HStack(spacing: 10) {
            Button {
                closeMe()
            } label: {
                chromeCircle {
                    Image(systemName: "chevron.down")
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Tr("关闭"))

            VStack(alignment: .leading, spacing: 3) {
                Text(t?.title ?? Tr("听一听"))
                    .font(pf(14.5, .semibold))
                    .foregroundStyle(.white.opacity(0.90))
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 5) {
                    if !artist.isEmpty {
                        Text(artist)
                            .font(pf(11.5, .regular))
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)
                    }

                    playerModeMenu
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if landscape {
                Button {
                    PushCenter.forceMusicPortrait()
                } label: {
                    Label(Tr("退出横屏"), systemImage: "rectangle.portrait")
                        .font(pfStyled(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .frame(height: 32)
                        .background(.black.opacity(0.20), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Tr("退出横屏"))
            } else {
                Button {
                    PushCenter.forceMusicLandscape()
                } label: {
                    Image(systemName: "rectangle.landscape.rotate")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(.white.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Tr("横版"))
            }

            playbackMenu
                .font(pfStyled(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .shadow(color: .black.opacity(0.24), radius: 5, y: 2)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 6)
        .background {
            LinearGradient(
                colors: [
                    .black.opacity(scheme == .dark ? 0.12 : 0.19),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t?.title ?? "")
                .font(pfStyled(size: 22, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.leading)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Text(t?.artistText ?? "")
                .font(pfStyled(size: 13.5, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compactTitleBlock: some View {
        VStack(spacing: 3) {
            Text(t?.title ?? "")
                .font(pfStyled(size: 20, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Text(t?.artistText ?? "")
                .font(pfStyled(size: 15, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func progressBlock(compact: Bool) -> some View {
        VStack(spacing: compact ? 1 : 3) {
            GeometryReader { geo in
                let value = min(max(dragging ? dragValue : player.progress, 0), 1)
                let width = max(geo.size.width, 1)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.20))
                        .frame(height: 2)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.70), Color.white],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, width * value),
                               height: 2)
                        .shadow(color: Color.white.opacity(0.30),
                                radius: dragging ? 7 : 3)

                    if dragging {
                        Capsule()
                            .fill(Color.white)
                            .frame(width: 1.5, height: 18)
                            .shadow(color: .white.opacity(0.42), radius: 5)
                            .offset(x: min(max(width * value - 0.75, 0),
                                          max(0, width - 1.5)))
                    }
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            if !dragging {
                                dragging = true
                                UISelectionFeedbackGenerator().selectionChanged()
                            }
                            dragValue = min(max(gesture.location.x / width, 0), 1)
                        }
                        .onEnded { gesture in
                            dragValue = min(max(gesture.location.x / width, 0), 1)
                            MusicPlayer.shared.seek(dragValue)
                            dragging = false
                        }
                )
                .accessibilityElement()
                .accessibilityLabel(Tr("播放进度"))
                .accessibilityValue("\(Int(value * 100))%")
                .accessibilityAdjustableAction { direction in
                    let step = 0.05
                    switch direction {
                    case .increment:
                        MusicPlayer.shared.seek(min(1, player.progress + step))
                    case .decrement:
                        MusicPlayer.shared.seek(max(0, player.progress - step))
                    @unknown default:
                        break
                    }
                }
            }
            .frame(height: 44)

            HStack {
                Text(musicTime(dragging ? dragValue * player.total : player.seconds))
                    .foregroundStyle(.primary.opacity(0.72))
                Spacer()
                Text(musicTime(player.total))
                    .foregroundStyle(.secondary)
            }
            .font(pfStyled(size: compact ? 13 : 14,
                          weight: .medium,
                          design: .monospaced))
            .padding(.horizontal, 3)
        }
        .animation(.linear(duration: 0.24), value: player.progress)
    }

    private func transportControls(playSize: CGFloat,
                                   iconSize: CGFloat,
                                   spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            Button {
                MusicPlayer.shared.prev()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: iconSize, weight: .semibold))
            }
            .foregroundStyle(player.queue.count > 1
                             ? Color.white : Color.white.opacity(0.34))
            .accessibilityLabel(Tr("上一首"))

            Button {
                if let t { MusicPlayer.shared.toggle(t) }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: playSize, height: playSize)
                        .shadow(color: .black.opacity(0.20),
                                radius: 10, y: 4)
                    if player.loadingId == (t?.id ?? "") {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: player.playing ? "pause.fill" : "play.fill")
                            .font(.system(size: playSize * 0.40, weight: .bold))
                            .foregroundStyle(.black)
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
                    .font(.system(size: iconSize, weight: .semibold))
            }
            .foregroundStyle(player.queue.count > 1
                             ? Color.white : Color.white.opacity(0.34))
            .accessibilityLabel(Tr("下一首"))
        }
        .buttonStyle(.plain)
    }

    private func playerActions(compact: Bool) -> some View {
        HStack(spacing: 0) {
            playerAction(
                icon: liked ? "heart.fill" : "heart",
                name: Tr("赞"),
                count: likeCount,
                tint: liked ? Color(hex: 0xFF5A72) : Color.white,
                burst: heartBurst,
                compact: compact
            ) {
                likeIt()
            }
            playerAction(
                icon: "arrowshape.turn.up.right",
                name: Tr("转发"),
                count: t?.shareCount ?? 0,
                tint: Color.white,
                compact: compact
            ) {
                shareTo = true
            }
            playerAction(
                icon: "list.bullet",
                name: Tr("播放列表"),
                count: player.queue.count,
                tint: Color.white,
                compact: compact
            ) {
                showQueue = true
            }
            playerAction(
                icon: "square.and.arrow.up",
                name: Tr("分享"),
                count: nil,
                tint: Color.white,
                compact: compact
            ) {
                shareSystem = true
            }
        }
    }

    private func controlDock(compact: Bool) -> some View {
        VStack(spacing: compact ? 7 : 9) {
            progressBlock(compact: compact)

            transportControls(
                playSize: compact ? 56 : 64,
                iconSize: compact ? 21 : 23,
                spacing: compact ? 30 : 34
            )
            .frame(maxWidth: .infinity)

            playerActions(compact: true)
        }
        .padding(.horizontal, compact ? 14 : 18)
        .padding(.vertical, compact ? 9 : 10)
    }

    private func portraitPlayer(size: CGSize) -> some View {
        let lyricHeight = min(152, max(96, size.height * 0.23))
        let coverSide = max(160, min(size.width - 44,
                                     size.height - lyricHeight - 108))
        return VStack(spacing: 10) {
            artworkPanel(side: coverSide)
                .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        flipped.toggle()
                    }
                }

            titleBlock
                .padding(.horizontal, 2)

            lyricsViewport
                .frame(height: lyricHeight)
        }
        .padding(.horizontal, 24)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func landscapePlayer(size: CGSize) -> some View {
        let side = artworkSize(in: size)
        return HStack(spacing: max(20, min(38, size.width * 0.035))) {
            artworkPanel(side: side)
                .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        flipped.toggle()
                    }
                }

            VStack(spacing: 8) {
                compactTitleBlock
                lyricsViewport
                progressBlock(compact: true)
                landscapeControlStrip
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, max(20, size.width * 0.04))
        .padding(.top, 2)
        .padding(.bottom, max(10, L.safeBottom))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let landscape = geo.size.width > geo.size.height
                let contentSize = CGSize(
                    width: geo.size.width,
                    height: max(1, geo.size.height - 52)
                )
                let portraitStageHeight = max(
                    300,
                    contentSize.height - max(226, L.safeBottom + 198)
                )
                ZStack {
                    FullPlayerAmbient(track: t)

                    VStack(spacing: 0) {
                        playerTopBar(landscape: landscape)

                        Group {
                            if landscape {
                                landscapePlayer(size: contentSize)
                                    .transition(.opacity)
                            } else {
                                VStack(spacing: 0) {
                                    portraitPlayer(size: CGSize(
                                        width: contentSize.width,
                                        height: portraitStageHeight
                                    ))
                                    controlDock(compact: false)
                                        .padding(.horizontal, 22)
                                        .padding(.bottom, max(8, L.safeBottom))
                                }
                                .transition(.opacity)
                            }
                        }
                        .animation(.easeInOut(duration: 0.38), value: landscape)
                    }
                }
                .onAppear { isLandscape = landscape }
                .onChange(of: landscape) { value in isLandscape = value }
            }
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $shareTo) {
                ForwardPickerView(items: [ForwardItem(kind: "music", content: musicCardJSON)]) {
                    if let track = t {
                        RecommendationEventStore.shared.record(track.id, .share)
                        Task { await API.shared.musicShareCount(track.id) }
                    }
                }
                .environmentObject(app)
            }
            .sheet(isPresented: $shareSystem) {
                ShareSheet(items: [shareText])
            }
            .sheet(isPresented: $showQueue) {
                queueSheet
            }
            .onAppear {
                PushCenter.setMusicLandscape(true)
                if let t, player.current?.id != t.id { MusicPlayer.shared.play(t) }
                Task { await refreshLike() }
            }
            .onDisappear {
                PushCenter.setMusicLandscape(false)
            }
            .tint(OrbitTheme.jade)
        }
        .swipeBack { closeMe() }
        .statusBar(hidden: !isLandscape)
        .persistentSystemOverlays(isLandscape ? .automatic : .hidden)
    }
}
