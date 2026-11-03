import Foundation
import AVFoundation
import Combine
import UIKit

@MainActor
final class VoiceRecorder: NSObject, ObservableObject {
    static let shared = VoiceRecorder()

    @Published private(set) var recording = false
    @Published private(set) var seconds = 0
    @Published private(set) var level: CGFloat = 0
    @Published private(set) var willCancel = false

    @Published private(set) var willTranscribe = false

    let maxSeconds = 60

    private var rec: AVAudioRecorder?
    private var ticker: Timer?
    private var fileURL: URL?
    private var startedAt = Date()

    private var ampSmooth: Double = 0
    private var waveformSamples: [CGFloat] = []

    private let haptic = UIImpactFeedbackGenerator(style: .medium)
    private let hapticLight = UIImpactFeedbackGenerator(style: .light)

    private override init() { super.init() }

    func begin() async -> Bool {
        guard !recording else { return true }
        guard await Permission.ask(.audio) else { return false }

        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playAndRecord, mode: .default,
                           options: [.defaultToSpeaker, .allowBluetooth])
        try? s.setActive(true)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-\(Int(Date().timeIntervalSince1970 * 1000)).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        guard let r = try? AVAudioRecorder(url: url, settings: settings) else { return false }
        r.isMeteringEnabled = true
        r.record()
        rec = r
        fileURL = url
        startedAt = Date()
        seconds = 0
        level = 0
        waveformSamples = []
        willCancel = false
        recording = true

        haptic.prepare()
        haptic.impactOccurred()
        ticker?.invalidate()

        ticker = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in self.tick() }
        }
        return true
    }

    private func tick() {
        guard let r = rec else { return }
        seconds = Int(Date().timeIntervalSince(startedAt))

        if Date().timeIntervalSince(startedAt) > Double(maxSeconds) + 2 {
            CrashCatcher.note("录音", "看门狗触发：超过 \(maxSeconds + 2) 秒还在录，强制结束")
            _ = end()
            return
        }

        r.updateMeters()
        let db = r.averagePower(forChannel: 0)
        let raw = Double(max(0.0, min(1, (db + 55) / 55)))

        let attack = Double(UIConfig.num("voiceOrbAttack", 0.55))
        let release = Double(UIConfig.num("voiceOrbRelease", 0.16))
        ampSmooth += (raw - ampSmooth) * (raw > ampSmooth ? attack : release)
        level = CGFloat(max(0.04, min(1, ampSmooth)))
        waveformSamples.append(level)
    }

    var stale: Bool {
        recording && Date().timeIntervalSince(startedAt) > Double(maxSeconds) + 2
    }

    func forceStop() {
        guard recording else { return }
        rec?.stop()
        rec = nil
        ticker?.invalidate()
        ticker = nil
        recording = false
        seconds = 0
        level = 0
        ampSmooth = 0
        waveformSamples = []
        willCancel = false
        willTranscribe = false
    }

    func drag(_ dy: CGFloat) {
        let t = dy < -60 && dy > -140
        let c = dy <= -140

        if t != willTranscribe || c != willCancel {
            hapticLight.impactOccurred()
        }
        willTranscribe = t
        willCancel = c
    }

    func end() -> (url: URL, seconds: Int, waveform: [CGFloat])? {
        guard let r = rec, let url = fileURL else {
            recording = false
            return nil
        }
        let secs = Int(Date().timeIntervalSince(startedAt).rounded())
        let cancelled = willCancel || secs < 1
        let waveform = compactWaveform(waveformSamples)
        r.stop()
        rec = nil
        ticker?.invalidate()
        ticker = nil
        recording = false
        level = 0
        ampSmooth = 0
        waveformSamples = []
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if cancelled {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        hapticLight.impactOccurred()
        return (url, max(1, secs), waveform)
    }

    func cancel() {
        willCancel = true
        _ = end()
    }

    private func compactWaveform(_ samples: [CGFloat], target: Int = 36) -> [CGFloat] {
        guard !samples.isEmpty else { return [] }
        let compact: [CGFloat]
        if samples.count <= target {
            compact = samples
        } else {
            let bucket = Double(samples.count) / Double(target)
            compact = (0..<target).map { i in
                let start = min(samples.count - 1, Int(Double(i) * bucket))
                let end = min(samples.count, max(start + 1, Int(Double(i + 1) * bucket)))
                return samples[start..<end].max() ?? 0.08
            }
        }
        let peak = max(0.08, compact.max() ?? 0.08)
        return compact.map { max(0.10, min(1, $0 / peak)) }
    }
}

@MainActor
final class VoicePlayer: NSObject, ObservableObject {
    static let shared = VoicePlayer()

    @Published private(set) var playingID = ""

    @Published private(set) var progress: Double = 0

    @Published private(set) var elapsed: Double = 0
    @Published private(set) var total: Double = 0

    @Published private(set) var rate: Float = VoicePlayer.savedRate

    static var savedRate: Float {
        UserDefaults.standard.double(forKey: "chris.voiceRate") > 1.5 ? 2 : 1
    }

    func toggleRate() {
        rate = rate > 1.5 ? 1 : 2
        UserDefaults.standard.set(Double(rate), forKey: "chris.voiceRate")
        applyRate()
    }

    private func applyRate() {
        guard let p = player else { return }
        p.enableRate = true
        p.rate = rate
    }

    private var player: AVAudioPlayer?

    private var cache: [String: Data] = [:]

    private var ticker: Timer?

    private var pendingFraction: Double?

    private override init() { super.init() }

    func toggle(id: String, url: URL) {
        if playingID == id { stop(); return }
        stop()
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .default)
        try? s.setActive(true)
        playingID = id

        let key = url.absoluteString
        if let hit = cache[key], let p = try? AVAudioPlayer(data: hit) {
            p.delegate = self
            p.prepareToPlay()
            p.enableRate = true
            p.rate = rate
            applyPending(to: p)
            p.play()
            player = p
            startTicker()
            return
        }
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                let data = try await API.shared.assetData(url)
                guard !data.isEmpty else { self.playingID = ""; return }
                self.cache[key] = data
                if self.cache.count > 24 { self.cache.removeValue(forKey: self.cache.keys.first ?? "") }

                guard self.playingID == id else { return }
                let p = try AVAudioPlayer(data: data)
                p.delegate = self
                p.prepareToPlay()
                p.enableRate = true
                p.rate = self.rate
                self.applyPending(to: p)
                p.play()
                self.player = p
                self.startTicker()
            } catch {
                self.playingID = ""
            }
        }
    }

    func seek(to fraction: Double) {
        let f = min(1, max(0, fraction))
        guard let p = player else {
            pendingFraction = f
            progress = f
            if total > 0 { elapsed = total * f }
            return
        }
        let d = max(0.01, p.duration)
        p.currentTime = d * f
        progress = f
        elapsed = p.currentTime
    }

    private func applyPending(to p: AVAudioPlayer) {
        total = p.duration
        if let f = pendingFraction {
            p.currentTime = max(0.01, p.duration) * f
            progress = f
            elapsed = p.currentTime
            pendingFraction = nil
        } else {
            progress = 0
            elapsed = 0
        }
    }

    private func startTicker() {
        ticker?.invalidate()

        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in VoicePlayer.shared.syncProgress() }
        }
    }

    func syncProgress() {
        guard let p = player else { return }
        total = p.duration
        elapsed = p.currentTime
        progress = p.duration > 0 ? min(1, max(0, p.currentTime / p.duration)) : 0
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        player?.stop()
        player = nil
        playingID = ""
        progress = 0
        elapsed = 0
        pendingFraction = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

extension VoicePlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }
}
