import SwiftUI
import Speech
import AVFoundation

@MainActor
final class Dictation: NSObject, ObservableObject {
    @Published var listening = false
    @Published var text = ""
    @Published var error = ""

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var onText: ((String) -> Void)?
    private var silence: Timer?
    private var started = false
    private var tapInstalled = false
    private var generation = 0

    private var settled = ""
    private var lastEmitted = ""
    private var beganAt = Date()
    private var lastRollover = Date.distantPast

    func toggle(_ onText: @escaping (String) -> Void) {
        if listening || started { stop() } else { start(onText) }
    }

    func start(_ onText: @escaping (String) -> Void) {
        generation += 1
        let token = generation
        self.onText = onText
        text = ""
        error = ""
        settled = ""
        lastEmitted = ""
        beganAt = Date()
        SFSpeechRecognizer.requestAuthorization { [weak self] st in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard token == self.generation else { return }
                guard st == .authorized else {
                    self.error = "没给语音识别权限：设置 → 隐私 → 语音识别 里打开"
                    return
                }
                AVAudioSession.sharedInstance().requestRecordPermission { ok in
                    DispatchQueue.main.async {
                        guard token == self.generation else { return }
                        guard ok else {
                            self.error = "没给麦克风权限：设置 → 隐私 → 麦克风 里打开"
                            return
                        }
                        self.begin()
                    }
                }
            }
        }
    }

    private func begin() {
        guard let recognizer = NativeSpeech.recognizer(), recognizer.isAvailable else {
            self.error = "系统语音识别暂时不可用"
            return
        }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record, mode: .default, options: [.duckOthers])
        do {
            try session.setActive(true, options: [])
        } catch {
            self.error = "麦克风被别的 App 占着，等一下再点一次"
            return
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.taskHint = .dictation
        NativeSpeech.configure(req, recognizer: recognizer, partial: true)
        request = req

        let node = engine.inputNode
        let fmt = node.outputFormat(forBus: 0)

        guard fmt.sampleRate > 0, fmt.channelCount > 0 else {
            self.error = "麦克风还没准备好，再点一次话筒"
            return
        }
        if tapInstalled { node.removeTap(onBus: 0); tapInstalled = false }
        node.installTap(onBus: 0, bufferSize: 1024, format: fmt) { buf, _ in req.append(buf) }
        tapInstalled = true
        engine.prepare()
        do { try engine.start() } catch {
            if tapInstalled { node.removeTap(onBus: 0); tapInstalled = false }
            try? session.setActive(false, options: [.notifyOthersOnDeactivation])
            self.error = "麦克风打不开，等一下再试"
            return
        }
        listening = true
        started = true
        bumpSilence()

        task = recognizer.recognitionTask(with: req) { [weak self] result, err in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let result = result {
                    let piece = result.bestTranscription.formattedString
                    let full = self.settled.isEmpty ? piece : (self.settled + piece)
                    if full != self.lastEmitted {
                        self.lastEmitted = full
                        self.text = full
                        self.onText?(full)
                        self.bumpSilence()
                    }
                    if result.isFinal {
                        self.settled = full
                        self.rollover()
                    }
                }
                if err != nil {

                    if self.listening {
                        self.settled = self.lastEmitted
                        self.rollover()
                    }
                }
            }
        }
    }

    private func bumpSilence() {
        silence?.invalidate()
        silence = Timer.scheduledTimer(withTimeInterval: 2.4, repeats: false) { _ in
            Task { @MainActor in self.stop() }
        }
    }

    private func rollover() {
        guard listening else { return }
        guard Date().timeIntervalSince(beganAt) < 300 else { stop(); return }

        if Date().timeIntervalSince(lastRollover) < 0.6 { stop(); return }
        lastRollover = Date()
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if engine.isRunning { engine.stop() }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self = self, self.listening else { return }
            self.begin()
        }
    }

    func stop() {
        generation += 1
        silence?.invalidate()
        silence = nil
        if engine.isRunning { engine.stop() }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        listening = false
        started = false
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
