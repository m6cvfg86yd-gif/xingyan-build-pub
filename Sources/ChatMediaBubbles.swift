import SwiftUI
import AVFoundation
import AVKit

private func jsonDict(_ s: String) -> [String: Any] {
    guard let d = s.data(using: .utf8),
          let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [:] }
    return o
}

struct UserCardInfo {
    var userId: String = ""
    var name: String = ""
    var avatar: String = ""
    var username: String = ""

    static func decodePct(_ s: String) -> String {
        guard s.contains("%") else { return s }
        return s.removingPercentEncoding ?? s
    }

    init?(json: String) {
        let o = jsonDict(json)

        userId = ((o["userId"] as? String) ?? (o["id"] as? String)) ?? ""
        name = UserCardInfo.decodePct((o["name"] as? String) ?? "")
        avatar = (o["avatar"] as? String) ?? ""
        username = UserCardInfo.decodePct((o["username"] as? String) ?? "")
        guard !userId.isEmpty else { return nil }
    }
}

struct UserCardBubble: View {
    let info: UserCardInfo
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        PremiumGlassCard(radius: 18,
                         tint: scheme == .dark ? C.green.opacity(0.045)
                                               : Color.white.opacity(0.03)) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(C.green.opacity(scheme == .dark ? 0.14 : 0.10))
                        RemoteImage(path: info.avatar, icon: "person.fill")
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                    .frame(width: 56, height: 56)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(Tr("星言联系人"))
                            .font(pf(9.5, .semibold))
                            .tracking(1.1)
                            .foregroundColor(C.green)
                        Text(info.name.isEmpty ? Tr("星言联系人") : info.name)
                            .font(pf(16.5, .semibold))
                            .foregroundColor(C.label)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        HStack(spacing: 5) {
                            Text(Tr("星言号"))
                                .font(pf(10.5))
                                .foregroundColor(C.subLabel)
                            Text(info.username.isEmpty ? "—" : info.username)
                                .font(pfStyled(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(C.label.opacity(0.76))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 12)

                Rectangle()
                    .fill(C.hairline)
                    .frame(height: 0.5)
                    .padding(.horizontal, 13)

                HStack(spacing: 5) {
                    Image(systemName: "person.text.rectangle")
                        .font(.system(size: 11, weight: .semibold))
                    Text(Tr("星言身份卡"))
                        .font(pf(11.5, .medium))
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundColor(C.subLabel)
                .padding(.horizontal, 13)
                .frame(height: 31)
            }
        }
        .frame(width: 258)
    }
}

struct AnnounceBubble: View {
    let text: String

    var onOpen: (() -> Void)? = nil

    var body: some View {
        WeChatMessageCard(width: 250, padding: 0) {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "megaphone.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(C.subLabel)
                Text(Tr("群公告"))
                    .font(pf(12.5, .medium))
                    .foregroundColor(C.label)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)

            Text(text)
                .font(pf(14))
                .foregroundColor(C.label)
                .lineSpacing(3)
                .lineLimit(5)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)

            HairLine(inset: 0)

            HStack(spacing: 4) {
                Text(Tr("查看详情"))
                    .font(pf(12))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundColor(C.green)
            .padding(.horizontal, 12)
            .frame(height: 32)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpen?() }
    }
}

func videoBubbleSize(w: Int, h: Int) -> CGSize {
    let fw = CGFloat(w), fh = CGFloat(h)
    guard fw > 0, fh > 0 else { return CGSize(width: 160, height: 205) }
    let aspect = fw / fh
    let maxW: CGFloat = aspect >= 1 ? 250 : 190
    let maxH: CGFloat = aspect >= 1 ? 170 : 250
    var cw = maxW
    var ch = cw / aspect
    if ch > maxH { ch = maxH; cw = ch * aspect }

    if min(cw, ch) < 110 {
        let k = 110 / min(cw, ch)
        cw *= k; ch *= k
        if cw > maxW { let k2 = maxW / cw; cw *= k2; ch *= k2 }
        if ch > maxH { let k2 = maxH / ch; cw *= k2; ch *= k2 }
    }
    return CGSize(width: cw.rounded(), height: ch.rounded())
}

struct VideoBubble: View {
    let message: Message
    let mine: Bool
    var onOpen: (URL, UIImage?) -> Void = { _, _ in }

    private var info: (url: String, cover: String, seconds: Int, w: Int, h: Int) {
        let o = jsonDict(message.body)
        return ((o["url"] as? String) ?? "",
                (o["cover"] as? String) ?? "",
                (o["seconds"] as? Int) ?? 0,
                (o["w"] as? Int) ?? 0,
                (o["h"] as? Int) ?? 0)
    }

    private var size: CGSize { videoBubbleSize(w: info.w, h: info.h) }

    var body: some View {
        Button {
            let u = info.url
            let full = u.hasPrefix("http") ? u : API.shared.base + u
            if let url = URL(string: full) { onOpen(url, nil) }
        } label: {
            ZStack {
                coverLayer
                playIcon
                if info.seconds > 0 { timeBadge }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Tr("查看视频"))
    }

    @ViewBuilder
    private var coverLayer: some View {
        if !info.cover.isEmpty {
            RemoteImage(path: info.cover, mode: .fill, maxSide: 1280)
        } else {
            Color.dyn(0xDDDDDD, 0x333333)
        }
    }

    private var playIcon: some View {
        Image(systemName: "play.circle.fill")
            .font(.system(size: 42))
            .foregroundColor(.white.opacity(0.92))
            .shadow(color: .black.opacity(0.35), radius: 6)
    }

    private var timeBadge: some View {
        VStack {
            Spacer(minLength: 0)
            HStack {
                Spacer(minLength: 0)
                Text(String(format: "%02d:%02d", info.seconds / 60, info.seconds % 60))
                    .font(pfStyled(size: 11.5, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
            }
        }
        .padding(7)
    }

}

struct LivePhotoBubble: View {
    let message: Message
    var onPlay: (URL) -> Void = { _ in }

    private var info: (image: String, video: String) {
        let o = jsonDict(message.body)
        return ((o["image"] as? String) ?? "", (o["video"] as? String) ?? "")
    }

    var body: some View {
        Button {
            let v = info.video
            let full = v.hasPrefix("http") ? v : API.shared.base + v
            if let url = URL(string: full) { onPlay(url) }
        } label: {
            ZStack(alignment: .topLeading) {
                RemoteImage(path: info.image, mode: .fill, maxSide: 1600)
                Text(Tr("实况"))
                    .font(pfStyled(size: 11.5, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.black.opacity(0.42)))
                    .padding(7)
            }
            .frame(width: 150, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Tr("查看实况照片"))
    }
}

struct VideoPlayerSheet: View {
    let url: URL

    var forwardContent: String = ""
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    @StateObject private var pip = PiPBox()

    @State private var note = ""

    @State private var now: Double = 0
    @State private var total: Double = 0
    @State private var dragging = false
    @State private var timeObs: Any?

    @State private var controls = true
    @State private var playing = true
    @State private var hideTask: Task<Void, Never>?
    @State private var showForward = false
    @State private var showShare = false

    @State private var speed: Double = 1

    @State private var lastHaptic = 0.0

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
                .onTapGesture { toggleControls() }
            if let p = player {
                PiPHostView(player: p, box: pip)
                    .ignoresSafeArea()
                    .onTapGesture { toggleControls() }
            }

            if pip.active {
                Color.black.ignoresSafeArea()
                VStack(spacing: 10) {
                    Image(systemName: "pip.fill")
                        .font(.system(size: 34))
                        .foregroundColor(.white.opacity(0.85))
                    Text(Tr("正在画中画播放"))
                        .font(pf(14)).foregroundColor(.white.opacity(0.8))
                    Text(Tr("点左上角按钮收回这一页"))
                        .font(pf(12)).foregroundColor(.white.opacity(0.55))
                }
                .allowsHitTesting(false)
            }
            if !note.isEmpty {
                Text(note)
                    .font(pf(14))
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(14)
                    .background {
                        GlassBackground(
                            shape: RoundedRectangle(cornerRadius: 14, style: .continuous),
                            shadow: true
                        )
                    }
                    .padding(30)
            }

            if controls && !pip.active {
                Button(action: togglePlayback) {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 64, height: 64)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .background { NativeGlassCircleBackground() }
                .transition(.scale(scale: 0.86).combined(with: .opacity))
                .accessibilityLabel(Text(playing ? Tr("暂停") : Tr("播放")))
            }

            VStack(spacing: 0) {

                if controls {
                    HStack(spacing: 10) {
                        Text(Self.fmt(now))
                            .font(pfStyled(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.88))
                            .frame(width: 40, alignment: .leading)
                        scrubBar

                        Menu {
                            ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { value in
                                Button {
                                    setPlaybackSpeed(value)
                                } label: {
                                    if abs(speed - value) < 0.01 {
                                        Label(Self.speedLabel(value), systemImage: "checkmark")
                                    } else {
                                        Text(Self.speedLabel(value))
                                    }
                                }
                            }
                        } label: {
                            Text(Self.speedLabel(speed))
                                .font(pfStyled(size: 12, weight: .semibold))
                                .foregroundColor(abs(speed - 1) > 0.01
                                                 ? Color(hex: 0x0A84FF) : .white)
                                .frame(width: 42, height: 24)
                                .background {
                                    GlassBackground(
                                        shape: Capsule(style: .continuous),
                                        shadow: false,
                                        tint: abs(speed - 1) > 0.01
                                            ? Color(hex: 0x0A84FF).opacity(0.18) : nil
                                    )
                                }
                        }
                        .menuStyle(.button)
                        .accessibilityLabel(Tr("播放速度"))
                        Text(Self.fmt(total))
                            .font(pfStyled(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.88))
                            .frame(width: 40, alignment: .trailing)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background {
                        GlassBackground(shape: Capsule(style: .continuous), shadow: true)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                HStack {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                        .background { NativeGlassCircleBackground() }
                        .highPriorityGesture(TapGesture().onEnded { dismiss() })
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel(Tr("关闭"))
                        .zIndex(30)

                    Button { pip.toggle() } label: {
                        Image(systemName: pip.active ? "pip.exit" : "pip.enter")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background { NativeGlassCircleBackground() }
                    }
                    .buttonStyle(.plain)
                    .opacity(pip.possible || pip.active ? 1 : 0.4)
                    .disabled(!(pip.possible || pip.active))
                    Spacer(minLength: 0)
                }
                .padding(12)
                .opacity(controls ? 1 : 0)

                Spacer(minLength: 0)

                if controls {

                    HStack(spacing: 46) {
                        action("转发", "arrowshape.turn.up.right.fill") { showForward = true }
                        action("分享", "square.and.arrow.up") { showShare = true }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background {
                        GlassBackground(shape: Capsule(style: .continuous), shadow: true)
                    }
                    .padding(.bottom, 30)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .onAppear {
            Task { await start() }
            autoHideControls()
        }
        .onDisappear {
            if let o = timeObs, let p = player { p.removeTimeObserver(o) }
            timeObs = nil
            hideTask?.cancel()
            player?.pause()
            player = nil
        }
        .sheet(isPresented: $showForward) {
            VideoForwardPicker(link: url.absoluteString, videoContent: forwardContent)
                .environmentObject(app)
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: shareItems)
        }
    }

    private var shareItems: [Any] {
        if let local = LocalStore.localURL(url.path), FileManager.default.fileExists(atPath: local.path) {
            return [local]
        }
        return [url.absoluteString]
    }

    private var frac: Double {
        guard total > 0.05 else { return 0 }
        return min(1, max(0, now / total))
    }

    private var scrubBar: some View {
        GeometryReader { geo in
            let w = max(1, geo.size.width)
            let dot: CGFloat = dragging ? 15 : 11
            let barH: CGFloat = dragging ? 5 : 3
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.24)).frame(height: barH)
                Capsule().fill(Color.white).frame(width: max(0, w * frac), height: barH)
                Circle()
                    .fill(Color.white)
                    .frame(width: dot, height: dot)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    .offset(x: min(max(0, w * frac - dot / 2), max(0, w - dot)))
            }
            .frame(height: 26)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: dragging)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if !dragging { dragging = true; lastHaptic = 0 }
                        let f = min(1, max(0, Double(v.location.x / w)))
                        now = f * max(total, 0.1)

                        if abs(f - lastHaptic) >= 0.03 {
                            lastHaptic = f
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                    }
                    .onEnded { _ in
                        dragging = false
                        if let p = player {
                            p.seek(to: CMTime(seconds: now, preferredTimescale: 600),
                                   toleranceBefore: .zero, toleranceAfter: .zero)
                            p.play()
                            p.rate = Float(speed)
                        }
                    }
            )
        }
        .frame(height: 26)
    }

    private static func speedLabel(_ value: Double) -> String {
        value == floor(value)
            ? "\(Int(value))×"
            : String(format: "%.1f×", value)
    }

    private func setPlaybackSpeed(_ value: Double) {
        speed = value
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let p = player {
            if p.rate > 0 {
                p.rate = Float(value)
            }
        }
    }

    private func togglePlayback() {
        guard let p = player else { return }
        if p.rate > 0 {
            p.pause()
            playing = false
            hideTask?.cancel()
        } else {
            p.play()
            p.rate = Float(speed)
            playing = true
            autoHideControls()
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func action(_ title: String, _ symbol: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 46, height: 46)
                Text(Tr(title))
                    .font(pf(12))
                    .foregroundColor(.white.opacity(0.92))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggleControls() {
        withAnimation(.easeOut(duration: 0.18)) { controls.toggle() }
        autoHideControls()
    }

    private func autoHideControls() {
        hideTask?.cancel()
        guard controls else { return }
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: 0.2)) { controls = false }
        }
    }

    static func fmt(_ s: Double) -> String {
        guard s.isFinite, s > 0 else { return "00:00" }
        let t = Int(s.rounded())
        return String(format: "%02d:%02d", t / 60, t % 60)
    }

    private func start() async {

        if url.scheme == "http" || url.scheme == "https",
           let local = LocalStore.localURL(url.path),
           FileManager.default.fileExists(atPath: local.path) {
            mount(AVPlayer(url: local))
            return
        }
        if url.scheme == "http" || url.scheme == "https" {

            if let p = StreamPlay.player(url) {
                mount(p)

                let ok = await waitForPicture(p)
                if ok { return }
                CrashCatcher.note("视频", "边下边播 3 秒没画面，改用整段下载：" + url.absoluteString.suffix(40))
                p.pause()
                if player === p { player = nil }
                timeObs = nil
            }

            guard let data = try? await API.shared.assetData(url), !data.isEmpty else {
                note = "取不到视频文件\n（网络不通或证书没过）\n地址：" + url.absoluteString.suffix(40)
                return
            }
            let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
            let dst = FileManager.default.temporaryDirectory
                .appendingPathComponent("play-\(UUID().uuidString).\(ext)")
            guard (try? data.write(to: dst)) != nil else { note = "视频写不进临时文件"; return }

            LocalStore.keep(url.path, data: data)
            mount(AVPlayer(url: dst))
            return
        }
        mount(AVPlayer(url: url))
    }

    private func mount(_ p: AVPlayer) {
        p.actionAtItemEnd = .none
        if let item = p.currentItem {
            NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                   object: item, queue: .main) { _ in
                p.seek(to: .zero); p.play()
            }
        }
        player = p
        p.play()
        playing = true
        if speed > 1.5 { p.rate = Float(speed) }

        timeObs = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
                                            queue: .main) { t in
            if !dragging { now = max(0, t.seconds) }
        }
        Task {
            if let item = p.currentItem, let d = try? await item.asset.load(.duration) {
                total = max(0.1, d.seconds)
            }
        }
    }

    private func waitForPicture(_ p: AVPlayer) async -> Bool {
        for _ in 0..<15 {
            if player !== p { return true }
            if let item = p.currentItem {
                if item.status == .failed { return false }
                if item.status == .readyToPlay, CMTimeGetSeconds(p.currentTime()) > 0.05 { return true }
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return false
    }
}

struct SendingVideoBubble: View {
    var cover: UIImage?
    var progress: Double

    private var size: CGSize {
        guard let c = cover, c.size.width > 0, c.size.height > 0 else {
            return videoBubbleSize(w: 0, h: 0)
        }
        return videoBubbleSize(w: Int(c.size.width), h: Int(c.size.height))
    }

    var body: some View {
        ZStack {
            if let c = cover {
                Image(uiImage: c)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.dyn(0xDDDDDD, 0x333333)
            }
            Color.black.opacity(0.42)

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.30), lineWidth: 4)
                    .frame(width: 54, height: 54)

                Circle()
                    .trim(from: 0, to: max(0.04, min(1, progress)))
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 54, height: 54)
                if progress > 0.01 {
                    Text("\(Int(min(1, progress) * 100))%")
                        .font(pfStyled(size: 13.5, weight: .semibold))
                        .foregroundColor(.white)
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.95))
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct SendingFileBubble: View {
    let name: String
    let bytes: Int
    let progress: Double

    private var value: Double { min(1, max(0, progress)) }
    private var look: (symbol: String, color: Color, badge: String) {
        FileKind.look(name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                VStack(spacing: 1) {
                    Image(systemName: look.symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(look.color)
                    Text(look.badge)
                        .font(pfExact(7.5, .bold))
                        .foregroundColor(look.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(look.color.opacity(0.13)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(look.color.opacity(0.18), lineWidth: 0.6))

                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(pf(14))
                        .foregroundColor(C.label)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 6) {
                        Text(byteText(bytes))
                            .font(pf(11))
                            .foregroundColor(C.subLabel)
                        Spacer(minLength: 4)
                        Text(value >= 0.995
                             ? Tr("服务器处理中…")
                             : Tr("上传中") + " \(Int(value * 100))%")
                            .font(pf(10.5, .medium))
                            .foregroundColor(look.color)
                    }
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(C.fieldBg)
                    Capsule()
                        .fill(look.color)
                        .frame(width: max(CGFloat(value > 0 ? 4 : 0),
                                          geo.size.width * CGFloat(value)))
                }
            }
            .frame(height: 3)
            .animation(.linear(duration: 0.16), value: value)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(width: 218)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(C.cardBg)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(C.hairline.opacity(0.78), lineWidth: 0.6)
                }
                .shadow(color: Color.black.opacity(0.10),
                        radius: 6, x: 0, y: 3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Tr("上传中") + " " + name))
        .accessibilityValue(Text("\(Int(value * 100))%"))
    }

    private func byteText(_ n: Int) -> String {
        if n > 1024 * 1024 { return String(format: "%.1f MB", Double(n) / 1024 / 1024) }
        if n > 1024 { return "\(n / 1024) KB" }
        return "\(n) B"
    }
}
