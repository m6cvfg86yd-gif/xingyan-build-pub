import Foundation
import AVFoundation
import CoreMedia
import UIKit

final class CallAudioPipe: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    static let shared = CallAudioPipe()

    private(set) var lastLevel: Double = 0

    private var outSeq: UInt16 = 0

    private var expectSeq: UInt16? = nil

    private(set) var plcFilled = 0
    private(set) var outOfOrder = 0

    private var bufferTarget: Int = 4
    private var lastPlcAt: Date = .distantPast

    private var lastPlayedFrame: Data? = nil

    private let sampleRate: Double = 16000
    private let frameSamples = 640

    private let capture = AVCaptureSession()
    private let audioOut = AVCaptureAudioDataOutput()
    private let captureQueue = DispatchQueue(label: "chris.call.capture")

    private let player = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var playerReady = false

    private var wired = false

    private let playQueue = DispatchQueue(label: "chris.call.play")

    private var watchdog: DispatchSourceTimer?

    private(set) var framesIn = 0
    private(set) var framesScheduled = 0
    private(set) var framesDropped = 0

    private(set) var framesOut = 0

    private var repairing = false
    private let repairQueue = DispatchQueue(label: "chris.call.repair")
    private var observers: [NSObjectProtocol] = []

    private var pendingFrames: [Data] = []

    private var framesInFlight: Int = 0
    private var queuedUntil = Date.distantPast

    private var latencyPeak = 0.0

    private var lastCapturePeak = 0
    private var lastPlayPeak = 0

    private(set) var captureStalls = 0

    private var lastCaptureGain = 1.0

    var playDiag: String {
        "播放端 收到=\(framesIn) 排播=\(framesScheduled) 丢=\(framesDropped)"
            + " 采集端 发出=\(framesOut)帧"

            + " 补帧=\(plcFilled) 乱序=\(outOfOrder) 缓冲=\(bufferTarget)帧"
            + " 延迟峰值=\(String(format: "%.1f", latencyPeak))s"
            + " 引擎=\(player.isRunning ? "跑" : "停")"
            + " 播放器=\(playerReady ? (playerNode.isPlaying ? "跑" : "停") : "没起")"
            + " 采集电平=\(lastCapturePeak) 播放电平=\(lastPlayPeak)"
            + " 采集增益=\(String(format: "%.1f", lastCaptureGain))"
            + " 重抢麦=\(captureStalls)次"
            + (lastError.isEmpty ? "" : " 错误=\(lastError)")
    }

    private func peakOfInt16(_ data: Data) -> Int {
        var mx = 0
        let bytes = [UInt8](data)
        var i = 0
        while i + 1 < bytes.count {
            let raw = UInt16(bytes[i]) | (UInt16(bytes[i + 1]) << 8)
            let a = abs(Int(Int16(bitPattern: raw)))
            if a > mx { mx = a }
            i += 2
        }
        return mx
    }

    private var started = false
    private let lifecycleLock = NSLock()
    private var starting = false

    private var startTask: Task<Void, Never>?

    private var handedOver = false
    var hasHandedOver: Bool { handedOver }

    var isRunning: Bool { started && capture.isRunning }

    private(set) var lastError = ""
    private var pending = Data()

    var onFrame: ((Data) -> Void)?

    var onStateChange: ((Bool) -> Void)?

    private var captureFormat: AVAudioFormat? {
        AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true)
    }

    private var playFormat: AVAudioFormat? {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)
    }

    private func claimStart() -> Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        guard !handedOver, !started, !starting else { return false }
        starting = true
        return true
    }

    private func finishStart(_ ok: Bool) {
        lifecycleLock.lock()
        started = ok
        starting = false
        lifecycleLock.unlock()
    }

    private func cleanupAudioResources() {
        startTask?.cancel()
        startTask = nil
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers.removeAll()
        watchdog?.cancel()
        watchdog = nil
        captureQueue.async { [capture] in if capture.isRunning { capture.stopRunning() } }
        playQueue.sync {
            playerNode.stop()
            player.stop()
            player.reset()
            playerNode.reset()
            if wired {
                player.disconnectNodeOutput(playerNode)
                player.detach(playerNode)
                wired = false
            }
            playerReady = false
            queuedUntil = Date.distantPast
            pendingFrames.removeAll()
            framesInFlight = 0
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func start() {
        guard claimStart() else { return }

        cleanupAudioResources()
        lastError = ""

        outSeq = 0
        expectSeq = nil
        plcFilled = 0
        outOfOrder = 0
        lastPlayedFrame = nil
        bufferTarget = 4
        lastPlcAt = .distantPast
        lastCapturePeak = 0
        lastPlayPeak = 0
        lastCaptureGain = 1.0
        captureStalls = 0
        lastLevel = 0
        pending.removeAll()
        framesIn = 0
        framesScheduled = 0
        framesDropped = 0
        framesOut = 0
        queuedUntil = Date.distantPast
        latencyPeak = 0
        pendingFrames.removeAll()
        framesInFlight = 0
        startWatchdog()
        observeSessionEvents()

        startTask = Task.detached { [weak self] in
            guard let self = self else { return }
            for attempt in 0..<6 {
                if Task.isCancelled || self.handedOver {
                    self.finishStart(false)
                    return
                }
                self.configureSession()
                self.startPlayback()
                if self.startCaptureBlocking() {
                    self.finishStart(true)
                    self.lastError = ""

                    self.startPlayback()
                    DispatchQueue.main.async { self.onStateChange?(true) }
                    return
                }

                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                try? await Task.sleep(nanoseconds: 700_000_000)
                if Task.isCancelled {
                    self.finishStart(false)
                    return
                }
            }
            self.finishStart(false)
            DispatchQueue.main.async { self.onStateChange?(false) }
        }
    }

    func prepareForNewCall() {
        stop()
        lastError = ""
        outSeq = 0
        expectSeq = nil
        plcFilled = 0
        outOfOrder = 0
        lastPlayedFrame = nil
        bufferTarget = 4
        lastPlcAt = .distantPast
        lastCapturePeak = 0
        lastPlayPeak = 0
        lastCaptureGain = 1.0
        captureStalls = 0
        lastLevel = 0
        framesInFlight = 0
        pendingFrames.removeAll()
        queuedUntil = Date.distantPast
        latencyPeak = 0
    }

    func stop() {
        finishStart(false)
        cleanupAudioResources()
    }

    func handOverToTRTC() {
        handedOver = true
        onFrame = nil
        onStateChange = nil
        finishStart(false)
        startTask?.cancel()
        startTask = nil
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers.removeAll()
        watchdog?.cancel()
        watchdog = nil

        captureQueue.sync {
            if capture.isRunning { capture.stopRunning() }
            capture.stopRunning()
        }
        playQueue.sync {
            playerNode.stop()
            player.stop()
            player.reset()
            playerNode.reset()
            if wired {
                player.disconnectNodeOutput(playerNode)
                player.detach(playerNode)
                wired = false
            }
            playerReady = false
            queuedUntil = Date.distantPast
            pendingFrames.removeAll()
            framesInFlight = 0
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func resetHandOver() { handedOver = false }

    private func startWatchdog() {
        guard watchdog == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: playQueue)
        t.schedule(deadline: .now() + 1.5, repeating: 2.0)

        var lastOut = -1
        var stalledTicks = 0
        var lastIn = -1
        var lastScheduled = -1
        var playbackStallTicks = 0
        t.setEventHandler { [weak self] in
            guard let self = self, self.started, !self.handedOver else { return }
            self.startPlaybackOnQueue()

            if !self.capture.isRunning {
                self.repairNow()
                return
            }
            if self.framesOut == lastOut {
                stalledTicks += 1
                if stalledTicks >= 2 {
                    stalledTicks = 0
                    self.captureStalls += 1
                    self.lastError = "采集不出帧，已自动重抢麦克风"
                    self.repairNow(force: true)
                }
            } else {
                stalledTicks = 0
                lastOut = self.framesOut
            }

            let receivedNewAudio = self.framesIn > lastIn || !self.pendingFrames.isEmpty
            let scheduledNothing = self.framesScheduled == lastScheduled
            if receivedNewAudio && scheduledNothing {
                playbackStallTicks += 1
                if playbackStallTicks >= 2 {
                    playbackStallTicks = 0
                    self.lastError = "播放队列停住，已自动重建音频引擎"
                    self.restartPlaybackOnQueue()
                }
            } else {
                playbackStallTicks = 0
            }
            lastIn = self.framesIn
            lastScheduled = self.framesScheduled
        }
        watchdog = t
        t.resume()
    }

    private func observeSessionEvents() {
        guard observers.isEmpty else { return }
        let c = NotificationCenter.default
        observers.append(c.addObserver(forName: AVAudioSession.interruptionNotification,
                                       object: nil, queue: nil) { [weak self] note in
            guard let self = self else { return }
            let raw = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) ?? 0
            if raw == AVAudioSession.InterruptionType.began.rawValue { return }
            self.repairNow(force: true)
        })
        observers.append(c.addObserver(forName: AVAudioSession.routeChangeNotification,
                                       object: nil, queue: nil) { [weak self] _ in

            self?.repairNow(force: true)
        })
        observers.append(c.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                       object: nil, queue: nil) { [weak self] _ in

            self?.repairNow(force: true)
        })
    }

    private func repairNow(force: Bool = false) {
        guard started, !handedOver, !repairing else { return }
        repairing = true
        repairQueue.async { [weak self] in
            guard let self = self else { return }
            defer { self.repairing = false }
            guard self.started, !self.handedOver else { return }
            self.configureSession()
            if force {

                self.captureQueue.sync { if self.capture.isRunning { self.capture.stopRunning() } }
            }
            if force || !self.capture.isRunning {
                _ = self.startCaptureBlocking()
            }
            guard self.started, !self.handedOver else { return }
            self.startPlayback()
            if self.capture.isRunning { DispatchQueue.main.async { self.onStateChange?(true) } }
        }
    }

    func repairAudioNow() { repairNow(force: true) }

    private func startPlayback() {
        playQueue.sync { startPlaybackOnQueue() }
    }

    private func startPlaybackOnQueue() {
        guard !handedOver, let fmt = playFormat else { return }

        if playerReady, player.isRunning, playerNode.isPlaying { return }
        framesInFlight = 0
        for attempt in 0..<5 {
            if playerReady, player.isRunning, playerNode.isPlaying { return }
            do {

                if attempt > 0 {
                    player.stop()
                    player.reset()
                    playerNode.reset()
                    if wired {
                        player.disconnectNodeOutput(playerNode)
                        player.detach(playerNode)
                        wired = false
                    }
                }
                if !wired {
                    player.attach(playerNode)
                    player.connect(playerNode, to: player.mainMixerNode, format: fmt)
                    wired = true
                }
                _ = try AVAudioSession.sharedInstance().setActive(true, options: [])
                player.prepare()
                if !player.isRunning { try player.start() }
                guard player.isRunning else {
                    lastError = (lastError.isEmpty ? "" : lastError + " / ") + "播放引擎未运行"
                    continue
                }
                let output = playerNode.outputFormat(forBus: 0)
                guard output.sampleRate > 0, output.channelCount > 0 else {
                    lastError = (lastError.isEmpty ? "" : lastError + " / ") + "播放节点未接入"
                    continue
                }
                if !playerNode.isPlaying { playerNode.play() }
                if player.isRunning, playerNode.isPlaying {
                    playerReady = true
                    lastError = ""
                    return
                }
            } catch {
                lastError = (lastError.isEmpty ? "" : lastError + " / ") + "播放引擎: \(error.localizedDescription)"
            }
            if attempt < 4 { Thread.sleep(forTimeInterval: 0.12) }
        }

        playerReady = false
        if !lastError.contains("播放引擎没起来") {
            lastError = (lastError.isEmpty ? "" : lastError + " / ") + "播放引擎没起来"
        }
    }

    private func restartPlaybackOnQueue() {
        guard !handedOver, started else { return }
        framesInFlight = 0
        pendingFrames.removeAll()
        queuedUntil = .distantPast
        playerReady = false
        playerNode.stop()
        player.stop()
        playerNode.reset()
        player.reset()
        if wired {
            player.disconnectNodeOutput(playerNode)
            player.detach(playerNode)
            wired = false
        }
        startPlaybackOnQueue()
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        do {

            try session.setCategory(.playAndRecord, mode: .voiceChat,
                                    options: [.defaultToSpeaker, .allowBluetooth])
        } catch {
            lastError = "setCategory 失败: \(error.localizedDescription)"
        }
        do { try session.setActive(true, options: []) } catch {
            lastError = (lastError.isEmpty ? "" : lastError + " / ") + "setActive 失败: \(error.localizedDescription)"
        }
    }

    private func startCaptureBlocking() -> Bool {

        var ok = false
        captureQueue.sync {
            if capture.isRunning { ok = true; return }
            capture.beginConfiguration()
            if capture.canSetSessionPreset(.high) { capture.sessionPreset = .high }
            if capture.inputs.isEmpty {
                guard let dev = AVCaptureDevice.default(for: .audio) else {
                    capture.commitConfiguration()
                    lastError = "找不到麦克风设备"
                    return
                }
                guard let input = try? AVCaptureDeviceInput(device: dev), capture.canAddInput(input) else {
                    capture.commitConfiguration()

                    let st = AVCaptureDevice.authorizationStatus(for: .audio)
                    lastError = st == .denied ? "麦克风权限被拒绝（去 设置→本 App→麦克风 打开）"
                        : (st == .notDetermined ? "麦克风权限还没授予（弹窗还没点）"
                           : "拿不到麦克风输入（可能被上一通/别的引擎占着）")
                    return
                }
                capture.addInput(input)
            }
            if capture.outputs.isEmpty {
                if capture.canAddOutput(audioOut) { capture.addOutput(audioOut) }
                audioOut.setSampleBufferDelegate(self, queue: captureQueue)
            }
            capture.commitConfiguration()
            if !capture.isRunning { capture.startRunning() }
            ok = capture.isRunning
        }
        if !ok { lastError = "AVCaptureSession 没能启动" }
        return ok
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let fmtDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmtDesc) else { return }
        var streamDesc = asbd.pointee
        guard let inFormat = AVAudioFormat(streamDescription: &streamDesc),
              let target = captureFormat,
              let converter = AVAudioConverter(from: inFormat, to: target) else { return }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0, let inBuf = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: frames) else { return }
        inBuf.frameLength = frames
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0,
                                                          frameCount: Int32(frames),
                                                          into: inBuf.mutableAudioBufferList) == noErr else { return }
        let outCap = AVAudioFrameCount(Double(frames) * target.sampleRate / inFormat.sampleRate + 32)
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outCap) else { return }
        var done = false
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if done { status.pointee = .noDataNow; return nil }
            done = true
            status.pointee = .haveData
            return inBuf
        }
        guard err == nil, out.frameLength > 0, let ch = out.int16ChannelData else { return }
        let chunk0 = Data(bytes: ch[0], count: Int(out.frameLength) * 2)
        let peak = peakOfInt16(chunk0)
        lastCapturePeak = peak

        lastLevel = max(0, min(1, Double(peak) / (32767.0 * 0.35)))

        var out0 = chunk0
        if peak > 0, peak < 4000 {

            let gain = min(6.0, max(0.5, 6000.0 / Double(peak)))
            lastCaptureGain = gain
            if gain > 1.05 {
                var bytes = [UInt8](chunk0)
                var i = 0
                while i + 1 < bytes.count {
                    let raw = Int16(bitPattern: UInt16(bytes[i]) | (UInt16(bytes[i + 1]) << 8))
                    let v = Int(Double(raw) * gain)
                    let clamped = Int16(max(-32768, min(32767, v)))
                    let u = UInt16(bitPattern: clamped)
                    bytes[i] = UInt8(u & 0xff)
                    bytes[i + 1] = UInt8((u >> 8) & 0xff)
                    i += 2
                }
                out0 = Data(bytes)
            }
        }
        pending.append(out0)
        let frameBytes = frameSamples * 2
        while pending.count >= frameBytes {
            let chunk = pending.prefix(frameBytes)
            pending.removeFirst(frameBytes)
            framesOut += 1

            outSeq = (outSeq &+ 1) & 0xFFFF
            var frame = Data()
            frame.append(UInt8((outSeq >> 8) & 0xFF))
            frame.append(UInt8(outSeq & 0xFF))
            frame.append(Data(chunk))
            onFrame?(frame)
        }
    }

    func play(_ data: Data) {

        guard !handedOver else { return }
        guard !data.isEmpty else { return }
        framesIn += 1

        var payload = data
        if data.count == frameSamples * 2 + 2 {
            let hi = UInt16(data[data.startIndex])
            let lo = UInt16(data[data.startIndex + 1])
            let seq = (hi << 8) | lo
            payload = data.subdata(in: (data.startIndex + 2)..<data.endIndex)
            if let exp = expectSeq {
                let diff = Int((seq &- exp) & 0xFFFF)
                if diff == 0 || diff > 0x8000 {

                    if diff == 0 || diff < 0x8000 { outOfOrder += 1 }
                    return
                }
                if diff > 1 && diff < 20 {

                    if let last = lastPlayedFrame {
                        let fill = min(diff - 1, 6)
                        for k in 0..<fill {
                            let att: Double = max(0.15, 0.55 - 0.08 * Double(k))
                            pendingFrames.append(attenuate(last, att))
                            plcFilled += 1
                        }
                    }
                    lastPlcAt = Date()

                }
            }
            expectSeq = (seq &+ 1) & 0xFFFF
            lastPlayedFrame = payload
        } else {
            lastPlayedFrame = payload
        }
        lastPlayPeak = peakOfInt16(payload)
        playQueue.async { [weak self] in self?.playOnQueue(payload) }
    }

    private func attenuate(_ data: Data, _ k: Double) -> Data {
        var out = data
        out.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: Int16.self) else { return }
            let n = raw.count / 2
            for i in 0..<n {
                base[i] = Int16(max(-32768, min(32767, Int(Double(base[i]) * k))))
            }
        }
        return out
    }

    private func playOnQueue(_ data: Data) {
        guard !handedOver else {
            framesDropped += 1
            pendingFrames.removeAll()
            framesInFlight = 0
            return
        }

        if !(playerReady && player.isRunning && playerNode.isPlaying) { startPlaybackOnQueue() }
        guard !handedOver, playerReady, player.isRunning, playerNode.isPlaying,
              let fmt = playFormat else {
            framesDropped += 1
            return
        }
        pendingFrames.append(data)

        if pendingFrames.count > bufferTarget, bufferTarget < 6 {
            bufferTarget += 1
        }
        while pendingFrames.count > bufferTarget {
            pendingFrames.removeFirst()
            framesDropped += 1
        }
        pumpPending(fmt)
    }

    private func drainPending(_ fmt: AVAudioFormat) {
        var until = max(Date(), queuedUntil)

        let backlog = until.timeIntervalSinceNow

        if Date().timeIntervalSince(lastPlcAt) > 8, bufferTarget > 3 {
            bufferTarget -= 1
            lastPlcAt = Date()
        }
        let cushion = bufferTarget

        if backlog > 0.4, pendingFrames.count > cushion {
            let hard = backlog > 1.5
            while pendingFrames.count > cushion {
                let now = until.timeIntervalSinceNow
                if hard ? (now <= 0.2) : (now <= 0.25) { break }
                pendingFrames.removeFirst()
                framesDropped += 1
                until = until.addingTimeInterval(-0.04)
            }
        }
        while !pendingFrames.isEmpty {
            let d = pendingFrames.removeFirst()
            let frames = d.count / 2
            guard frames > 0,
                  let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(frames)) else {
                framesDropped += 1
                continue
            }
            buf.frameLength = AVAudioFrameCount(frames)
            guard let ch = buf.floatChannelData else {
                framesDropped += 1
                continue
            }
            d.withUnsafeBytes { raw in
                guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                for i in 0..<frames {
                    let lo = UInt16(base[i * 2])
                    let hi = UInt16(base[i * 2 + 1]) << 8
                    let sample = Int16(bitPattern: lo | hi)
                    ch[0][i] = Float(sample) / 32768.0
                }
            }
            playerNode.scheduleBuffer(buf, completionHandler: nil)
            framesScheduled += 1
            until = until.addingTimeInterval(0.04)
        }
        queuedUntil = until
        let now = queuedUntil.timeIntervalSinceNow
        if now > latencyPeak { latencyPeak = now }
    }

    private func pumpPending(_ fmt: AVAudioFormat) {
        while framesInFlight < bufferTarget, !pendingFrames.isEmpty {
            guard !handedOver, playerReady, player.isRunning, playerNode.isPlaying else {
                pendingFrames.removeAll()
                framesInFlight = 0
                playerReady = false
                return
            }
            let d = pendingFrames.removeFirst()
            let frames = d.count / 2
            guard frames > 0,
                  let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(frames)) else {
                framesDropped += 1
                continue
            }
            buf.frameLength = AVAudioFrameCount(frames)
            guard let ch = buf.floatChannelData else {
                framesDropped += 1
                continue
            }
            d.withUnsafeBytes { raw in
                guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                for i in 0..<frames {
                    let lo = UInt16(base[i * 2])
                    let hi = UInt16(base[i * 2 + 1]) << 8
                    let sample = Int16(bitPattern: lo | hi)
                    ch[0][i] = Float(sample) / 32768.0
                }
            }
            framesInFlight += 1
            playerNode.scheduleBuffer(buf) { [weak self] in
                guard let self = self else { return }
                self.playQueue.async {
                    if self.framesInFlight > 0 { self.framesInFlight -= 1 }
                    self.pumpPending(fmt)
                }
            }
            framesScheduled += 1
        }
        let estimated = Double(framesInFlight + pendingFrames.count) * 0.04
        if estimated > latencyPeak { latencyPeak = estimated }
    }

}
