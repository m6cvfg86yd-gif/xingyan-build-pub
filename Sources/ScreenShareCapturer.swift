import CoreMedia
import Foundation
import ReplayKit
import WebRTC

@MainActor
final class ScreenShareCapturer {
    private let recorder = RPScreenRecorder.shared()
    private let capturer = RTCVideoCapturer()
    private weak var source: RTCVideoSource?
    private var running = false
    private var lastTimeStampNs: Int64 = 0

    func start(source: RTCVideoSource, completion: @escaping (String?) -> Void) {
        guard RPScreenRecorder.isAvailable else {
            completion("这台设备暂时不能共享屏幕")
            return
        }
        guard !running, !recorder.isRecording else {
            completion(nil)
            return
        }
        self.source = source
        running = true
        recorder.isMicrophoneEnabled = false
        recorder.startCapture { [weak self] sampleBuffer, sampleType, error in
            guard let self else { return }
            if let error {
                Task { @MainActor in
                    self.running = false
                    completion(error.localizedDescription)
                }
                return
            }
            guard sampleType == .video else { return }
            Task { @MainActor in self.consume(sampleBuffer) }
        } completionHandler: { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.running = false
                    self.source = nil
                    completion(error.localizedDescription)
                } else {
                    completion(nil)
                }
            }
        }
    }

    func stop(completion: (() -> Void)? = nil) {
        guard running else {
            completion?()
            return
        }
        running = false
        source = nil
        recorder.stopCapture { _ in
            Task { @MainActor in completion?() }
        }
    }

    private func consume(_ sampleBuffer: CMSampleBuffer) {
        guard running, let source,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let presentation = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        var timestamp = Int64(presentation.seconds * 1_000_000_000)
        if !presentation.isValid || timestamp <= lastTimeStampNs {
            timestamp = max(lastTimeStampNs + 1, Int64(Date().timeIntervalSince1970 * 1_000_000_000))
        }
        lastTimeStampNs = timestamp
        let buffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
        let frame = RTCVideoFrame(buffer: buffer, rotation: ._0, timeStampNs: timestamp)
        source.capturer(capturer, didCapture: frame)
    }
}
