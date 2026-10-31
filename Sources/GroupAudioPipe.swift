import AVFoundation
import CoreMedia
import Foundation
import UIKit

/// Group calls use their own capture/playback graph so they cannot corrupt
/// the single-call audio engine or inherit a previous TRTC handover state.
final class GroupAudioPipe: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    static let shared = GroupAudioPipe()

    private let sampleRate: Double = 16_000
    private let frameSamples = 640

    private let capture = AVCaptureSession()
    private let audioOut = AVCaptureAudioDataOutput()
    private let captureQueue = DispatchQueue(label: "chris.group.call.capture")

    private let player = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let playQueue = DispatchQueue(label: "chris.group.call.play")

    private var wired = false
    private var playerReady = false
    private var started = false
    private var pending = Data()
    private var sequence: UInt16 = 0

    private(set) var framesOut = 0
    private(set) var framesIn = 0
    private(set) var framesScheduled = 0
    private(set) var framesDropped = 0
    private(set) var lastLevel = 0.0
    private(set) var lastError = ""

    var onFrame: ((Data) -> Void)?

    var isRunning: Bool { started && capture.isRunning }

    var playDiag: String {
        "群语音播放端 收到=\(framesIn) 排播=\(framesScheduled) 丢=\(framesDropped)"
            + " 采集端 发出=\(framesOut)帧"
            + " 引擎=\(player.isRunning ? "跑" : "停")"
            + " 播放器=\(playerReady ? (playerNode.isPlaying ? "跑" : "停") : "没起")"
            + (lastError.isEmpty ? "" : " 错误=\(lastError)")
    }

    private var captureFormat: AVAudioFormat? {
        AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate,
                      channels: 1, interleaved: true)
    }

    private var playFormat: AVAudioFormat? {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                      channels: 1, interleaved: false)
    }

    func start() {
        stop()
        started = true
        framesOut = 0
        framesIn = 0
        framesScheduled = 0
        framesDropped = 0
        lastLevel = 0
        sequence = 0
        pending.removeAll()
        lastError = ""

        playQueue.sync {
            configureSession()
            startPlaybackLocked()
        }
        captureQueue.sync {
            startCaptureLocked()
        }
        if !capture.isRunning {
            lastError = "群语音采集没有启动"
        }
    }

    func stop() {
        started = false
        captureQueue.sync {
            if capture.isRunning { capture.stopRunning() }
        }
        playQueue.sync {
            playerNode.stop()
            player.stop()
            playerNode.reset()
            player.reset()
            if wired {
                player.disconnectNodeOutput(playerNode)
                player.detach(playerNode)
                wired = false
            }
            playerReady = false
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func repairAudioNow() {
        guard started else { return }
        captureQueue.sync {
            if capture.isRunning { capture.stopRunning() }
            startCaptureLocked()
        }
        playQueue.sync {
            playerReady = false
            startPlaybackLocked()
        }
    }

    func play(_ data: Data) {
        guard !data.isEmpty else { return }
        framesIn += 1
        playQueue.async { [weak self] in
            guard let self = self, self.started else { return }
            if !self.playerReady || !self.player.isRunning || !self.playerNode.isPlaying {
                self.startPlaybackLocked()
            }
            guard self.playerReady, self.player.isRunning, self.playerNode.isPlaying,
                  let format = self.playFormat else {
                self.framesDropped += 1
                return
            }
            let count = data.count / 2
            guard count > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                                frameCapacity: AVAudioFrameCount(count)) else {
                self.framesDropped += 1
                return
            }
            buffer.frameLength = AVAudioFrameCount(count)
            guard let channel = buffer.floatChannelData else {
                self.framesDropped += 1
                return
            }
            data.withUnsafeBytes { raw in
                guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                for index in 0..<count {
                    let low = UInt16(base[index * 2])
                    let high = UInt16(base[index * 2 + 1]) << 8
                    let sample = Int16(bitPattern: low | high)
                    channel[0][index] = Float(sample) / 32_768.0
                }
            }
            self.playerNode.scheduleBuffer(buffer, completionHandler: nil)
            self.framesScheduled += 1
        }
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat,
                                    options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: [])
        } catch {
            lastError = "群语音音频会话: \(error.localizedDescription)"
        }
    }

    private func startPlaybackLocked() {
        guard started, let format = playFormat else { return }
        if playerReady, player.isRunning, playerNode.isPlaying { return }
        do {
            if !wired {
                player.attach(playerNode)
                player.connect(playerNode, to: player.mainMixerNode, format: format)
                wired = true
            }
            _ = try AVAudioSession.sharedInstance().setActive(true, options: [])
            player.prepare()
            if !player.isRunning { try player.start() }
            if !playerNode.isPlaying { playerNode.play() }
            playerReady = player.isRunning && playerNode.isPlaying
            if !playerReady { lastError = "群语音播放器没有启动" }
        } catch {
            playerReady = false
            lastError = "群语音播放引擎: \(error.localizedDescription)"
        }
    }

    private func startCaptureLocked() {
        guard started else { return }
        capture.beginConfiguration()
        if capture.canSetSessionPreset(.high) { capture.sessionPreset = .high }
        if capture.inputs.isEmpty {
            guard let device = AVCaptureDevice.default(for: .audio),
                  let input = try? AVCaptureDeviceInput(device: device),
                  capture.canAddInput(input) else {
                capture.commitConfiguration()
                lastError = "群语音拿不到麦克风"
                return
            }
            capture.addInput(input)
        }
        if capture.outputs.isEmpty {
            if capture.canAddOutput(audioOut) {
                capture.addOutput(audioOut)
                audioOut.setSampleBufferDelegate(self, queue: captureQueue)
            }
        }
        capture.commitConfiguration()
        if !capture.isRunning { capture.startRunning() }
        if !capture.isRunning { lastError = "群语音采集没有启动" }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard started,
              let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(description) else {
            return
        }
        var inputDescription = streamDescription.pointee
        guard let inputFormat = AVAudioFormat(streamDescription: &inputDescription),
              let outputFormat = captureFormat,
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            return
        }
        let inputFrames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard inputFrames > 0,
              let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat,
                                                 frameCapacity: inputFrames) else {
            return
        }
        inputBuffer.frameLength = inputFrames
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(inputFrames),
            into: inputBuffer.mutableAudioBufferList
        ) == noErr else {
            return
        }
        let capacity = AVAudioFrameCount(Double(inputFrames) * sampleRate / inputFormat.sampleRate + 32)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat,
                                                  frameCapacity: capacity) else {
            return
        }
        var provided = false
        var conversionError: NSError?
        converter.convert(to: outputBuffer, error: &conversionError) { _, status in
            if provided {
                status.pointee = .noDataNow
                return nil
            }
            provided = true
            status.pointee = .haveData
            return inputBuffer
        }
        guard conversionError == nil, outputBuffer.frameLength > 0,
              let channel = outputBuffer.int16ChannelData else {
            return
        }
        var peak = 0
        let samples = Int(outputBuffer.frameLength)
        for index in 0..<samples {
            peak = max(peak, abs(Int(channel[0][index])))
        }
        lastLevel = max(0, min(1, Double(peak) / (32_767.0 * 0.35)))
        pending.append(Data(bytes: channel[0], count: Int(outputBuffer.frameLength) * 2))
        let frameBytes = frameSamples * 2
        while pending.count >= frameBytes {
            let chunk = Data(pending.prefix(frameBytes))
            pending.removeFirst(frameBytes)
            framesOut += 1
            sequence &+= 1
            var frame = Data([UInt8((sequence >> 8) & 0xFF), UInt8(sequence & 0xFF)])
            frame.append(chunk)
            onFrame?(frame)
        }
    }
}
