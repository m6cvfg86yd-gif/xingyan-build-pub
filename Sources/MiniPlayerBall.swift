import SwiftUI
import UIKit
import MediaPlayer
import AVFoundation

@MainActor
final class MusicDockState: ObservableObject {
    static let shared = MusicDockState()

    @Published private(set) var owners = 0
    @Published private(set) var foregroundTab = 0
    var active: Bool { owners > 0 }
    var foregroundActive: Bool { owners > 0 && foregroundTab == 2 }

    private init() {}

    func attach() { owners += 1 }
    func detach() { owners = max(0, owners - 1) }
    func setForegroundTab(_ value: Int) { foregroundTab = value }
}

struct MusicDockedPlayerBar: View {
    @ObservedObject private var player = MusicPlayer.shared

    var body: some View {
        HStack(spacing: 12) {
            MusicCover(path: player.current?.cover ?? "", size: 40, radius: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(player.current?.title ?? "")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(player.current?.artistText ?? "")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button {
                if let track = player.current { player.toggle(track) }
            } label: {
                if !player.loadingId.isEmpty && player.loadingId == (player.current?.id ?? "") {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: player.playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(height: 64)
        .background(.thinMaterial,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            if let track = player.current { MusicSheet.shared.open(track) }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    if value.translation.height < -44,
                       abs(value.translation.height) > abs(value.translation.width) {
                        if let track = player.current { MusicSheet.shared.open(track) }
                    } else if abs(value.translation.width) > 52,
                              abs(value.translation.width) > abs(value.translation.height) {
                        if value.translation.width < 0 { player.next() }
                        else { player.prev() }
                    }
                }
        )
    }
}

struct MiniPlayerBall: View {
    @ObservedObject private var player = MusicPlayer.shared

    private var barStyle: Bool { UIConfig.num("miniBallStyle", 1) > 0 }

    var hidden: Bool = false

    @AppStorage("miniBallSide") private var side: Int = 1
    @AppStorage("miniBallBottom") private var storedBottom: Double = -1

    @State private var dx: CGFloat = 0
    @State private var dy: CGFloat = 0
    @State private var dragging = false

    private var dia: CGFloat { max(42, min(76, UIConfig.num("miniBallSize", 54))) }
    private var on: Bool { UIConfig.num("miniBallOn", 1) > 0 }
    private var showing: Bool { on && !hidden && player.current != nil }

    var body: some View {
        if barStyle {
            miniBar
        } else {
            ballBody
        }
    }

    private var miniBar: some View {
        VStack {
            Spacer(minLength: 0)
            MusicDockedPlayerBar()
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 10).onEnded { v in

                if v.translation.height > 40 { MusicPlayer.shared.stop() }
            })
            .padding(.horizontal, 10)
            .padding(.bottom, L.safeBottom + L.tabH + 8)
        }
        .ignoresSafeArea()
        .opacity(showing ? 1 : 0)
        .allowsHitTesting(showing)
        .transition(.move(edge: .bottom))
        .animation(.easeOut(duration: 0.2), value: showing)
    }

    private var ballBody: some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1), h = max(geo.size.height, 1)
            let pad = dia / 2 + 6
            let restX = side == 0 ? pad : w - pad
            let restY = h - (storedBottom < 0 ? defaultBottom : CGFloat(storedBottom))
            let cx = min(max(restX + dx, pad), w - pad)
            let cy = min(max(restY + dy, L.safeTop + pad), h - pad)

            ball
                .contentShape(Circle())

                .onTapGesture { openPlayer() }

                .highPriorityGesture(drag(w: w, h: h))
                .position(x: cx, y: cy)
        }
        .ignoresSafeArea()
        .opacity(showing ? 1 : 0)
        .allowsHitTesting(showing)
    }

    private var defaultBottom: CGFloat { dia / 2 + L.tabH + L.safeBottom + 10 }

    private var ball: some View {
        ZStack {
            MusicCover(path: player.current?.cover ?? "", size: dia, radius: dia / 2)
                .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1))

            Circle()
                .trim(from: 0, to: max(0.02, min(1, player.progress)))
                .stroke(C.green, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: dia - 1.5, height: dia - 1.5)

            MusicPlayButton(playing: player.playing,
                            loading: !player.loadingId.isEmpty && player.loadingId == (player.current?.id ?? ""),
                            size: dia * 0.44)
                .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.2))
                .offset(x: dia * 0.33, y: dia * 0.33)
                .onTapGesture {
                    guard let t = MusicPlayer.shared.current else { return }
                    MusicPlayer.shared.toggle(t)
                }

            ZStack {
                Circle().fill(Color.black.opacity(0.55))
                Image(systemName: "xmark")
                    .font(.system(size: dia * 0.17, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: dia * 0.36, height: dia * 0.36)
            .offset(x: -dia * 0.33, y: -dia * 0.33)
            .onTapGesture { MusicPlayer.shared.stop() }
        }
        .frame(width: dia, height: dia)
        .shadow(color: .black.opacity(0.24), radius: 10, y: 4)

        .scaleEffect(dragging ? 1.1 : 1)
        .animation(.easeOut(duration: 0.12), value: dragging)
    }

    private func openPlayer() {
        guard let t = MusicPlayer.shared.current else { return }
        MusicSheet.shared.open(t)
    }

    private func drag(w: CGFloat, h: CGFloat) -> some Gesture {

        DragGesture(minimumDistance: 5)
            .onChanged { v in
                dragging = true
                dx = v.translation.width
                dy = v.translation.height
            }
            .onEnded { v in
                let pad = dia / 2 + 6
                let restX = side == 0 ? pad : w - pad
                let restY = h - (storedBottom < 0 ? defaultBottom : CGFloat(storedBottom))

                if v.translation.height > 96 && abs(v.translation.height) > abs(v.translation.width) * 1.4 {
                    dx = 0; dy = 0; dragging = false
                    MusicPlayer.shared.stop()
                    return
                }

                let nx = min(max(restX + v.translation.width, pad), w - pad)
                let ny = min(max(restY + v.translation.height, L.safeTop + pad), h - pad)
                withAnimation(.easeOut(duration: 0.16)) {
                    side = nx < w / 2 ? 0 : 1
                    storedBottom = Double(min(max(h - ny, pad + 4), h - L.safeTop - pad))
                    dx = 0; dy = 0
                }
                dragging = false
            }
    }
}

extension MusicPlayer {

    func setupRemoteControls() {
        let c = MPRemoteCommandCenter.shared()

        c.playCommand.removeTarget(nil)
        c.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.remotePlay() }
            return .success
        }

        c.pauseCommand.removeTarget(nil)
        c.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.remotePause() }
            return .success
        }

        c.togglePlayPauseCommand.removeTarget(nil)
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let t = self?.current else { return }
                self?.toggle(t)
            }
            return .success
        }

        c.nextTrackCommand.removeTarget(nil)
        c.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        c.previousTrackCommand.removeTarget(nil)
        c.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.prev() }
            return .success
        }

        c.changePlaybackPositionCommand.removeTarget(nil)
        c.changePlaybackPositionCommand.addTarget { [weak self] ev in
            guard let e = ev as? MPChangePlaybackPositionCommandEvent, let self else { return .commandFailed }
            Task { @MainActor in

                guard self.total > 0 else { return }
                self.seek(e.positionTime / self.total)
                self.syncNowPlaying()
            }
            return .success
        }
    }

    private func remotePlay() {
        guard let t = current else { return }
        if let p = player {
            try? AVAudioSession.sharedInstance().setActive(true)
            p.play(); playing = true; startTimer(); syncNowPlaying()
        } else if let st = stream {

            try? AVAudioSession.sharedInstance().setActive(true)
            st.play(); playing = true; startTimer(); syncNowPlaying()
        } else {
            play(t)
        }
    }

    private func remotePause() {
        player?.pause()
        stream?.pause()
        playing = false
        stopTimer()
        syncNowPlaying()
    }

    func syncNowPlaying() {

        let c = MPRemoteCommandCenter.shared()
        let canSkip = queue.count > 1
        if c.nextTrackCommand.isEnabled != canSkip { c.nextTrackCommand.isEnabled = canSkip }
        if c.previousTrackCommand.isEnabled != canSkip { c.previousTrackCommand.isEnabled = canSkip }
        guard let t = current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = t.title
        info[MPMediaItemPropertyArtist] = t.artistText
        info[MPMediaItemPropertyPlaybackDuration] = total
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = seconds
        info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? 1.0 : 0.0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
        if let art = MusicPlayer.cachedArtwork(t) {
            info[MPMediaItemPropertyArtwork] =
                MPMediaItemArtwork(boundsSize: art.size) { _ in art }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = playing ? .playing : .paused
    }

    static func cachedArtwork(_ t: MusicTrack) -> UIImage? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let p = caches.appendingPathComponent("musiccover").appendingPathComponent("\(t.id)")
        return UIImage(contentsOfFile: p.path)
    }
}
