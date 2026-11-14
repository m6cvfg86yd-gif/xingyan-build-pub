import SwiftUI
import AVFoundation
import Speech

@MainActor
final class VoiceEngine: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    @Published var listening = false
    @Published var heard = ""
    @Published var status = "点一下麦克风开始说话"
    @Published var level: CGFloat = 0
    @Published var outputting = false
    var aiVoice = ""

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let synth = AVSpeechSynthesizer()
    private var onSpokenDone: (() -> Void)?
    private var cloudPlayer: AVAudioPlayer?
    private var meterTimer: Timer?
    private var meterPhase: CGFloat = 0
    private var autoStop: Task<Void, Never>?
    private var onText: ((String) -> Void)?

    override init() {
        super.init()
        synth.delegate = self
    }

    func authorize(_ done: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { st in
            DispatchQueue.main.async { done(st == .authorized) }
        }
    }

    func start(_ onText: @escaping (String) -> Void) {
        stop()
        self.onText = onText
        heard = ""
        guard let recognizer = NativeSpeech.recognizer(), recognizer.isAvailable else {
            status = "系统语音识别暂时不可用"
            return
        }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default,
                                 options: [.defaultToSpeaker, .allowBluetooth])
        try? session.setActive(true, options: [])

        let req = SFSpeechAudioBufferRecognitionRequest()
        NativeSpeech.configure(req, recognizer: recognizer, partial: true)
        request = req

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        guard format.sampleRate > 0, format.channelCount > 0 else {
            status = "麦克风还没准备好，再点一次"
            return
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buf, _ in
            req.append(buf)
            guard let channels = buf.floatChannelData, buf.frameLength > 0 else { return }
            let count = Int(buf.frameLength)
            var sum: Float = 0
            for i in 0..<count {
                let sample = channels[0][i]
                sum += sample * sample
            }
            let rms = sqrt(sum / Float(max(1, count)))
            let raw = min(1, max(0, CGFloat(rms) * 9))
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.level = self.level * 0.58 + raw * 0.42
            }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            status = "麦克风打不开（检查权限）"
            return
        }
        listening = true
        status = "我在听…"

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let result = result {
                    self.heard = result.bestTranscription.formattedString
                    if result.isFinal { self.finishSpeaking() }
                }
                if error != nil { self.finishSpeaking() }
            }
        }

        autoStop = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 9_000_000_000)
            guard let self = self, !Task.isCancelled else { return }
            if self.listening { self.finishSpeaking() }
        }
    }

    private func finishSpeaking() {
        let text = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        stop()
        if !text.isEmpty { onText?(text) }
    }

    func stop() {
        autoStop?.cancel()
        autoStop = nil
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        listening = false
        level = 0
    }

    func speak(_ text: String, done: @escaping () -> Void) {
        stopSpeech()
        onSpokenDone = done
        outputting = true
        let clean = text.replacingOccurrences(of: "```", with: " ")
            .replacingOccurrences(of: "#", with: "")
        let u = AVSpeechUtterance(string: String(clean.prefix(220)))
        u.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        u.rate = 0.5
        u.pitchMultiplier = 0.72
        startSyntheticMeter()
        synth.speak(u)
    }

    func speakCloud(_ text: String, done: @escaping () -> Void) {
        stopSpeech()
        onSpokenDone = done
        outputting = true
        let requestedVoice = aiVoice
        Task {
            do {
                let result = try await API.shared.aiSpeech(String(text.prefix(500)))
                guard let data = Data(base64Encoded: result.audio), !data.isEmpty else {
                    throw APIError.message("语音数据不完整")
                }
                let session = AVAudioSession.sharedInstance()
                try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
                try? session.setActive(true)
                let player = try AVAudioPlayer(data: data)
                player.delegate = self
                player.isMeteringEnabled = true
                player.prepareToPlay()
                guard player.play() else { throw APIError.message("语音播放失败") }
                cloudPlayer = player
                startOutputMeter(player)
                _ = requestedVoice
            } catch {
                speak(text, done: done)
            }
        }
    }

    func stopSpeech() {
        cloudPlayer?.stop()
        cloudPlayer = nil
        meterTimer?.invalidate()
        meterTimer = nil
        level = 0
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        onSpokenDone = nil
        outputting = false
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.outputting = false
            self.meterTimer?.invalidate()
            self.meterTimer = nil
            self.level = 0
            let cb = self.onSpokenDone
            self.onSpokenDone = nil
            cb?()
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.cloudPlayer = nil
            self.outputting = false
            self.meterTimer?.invalidate()
            self.meterTimer = nil
            self.level = 0
            let cb = self.onSpokenDone
            self.onSpokenDone = nil
            cb?()
        }
    }

    private func startOutputMeter(_ player: AVAudioPlayer) {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.055, repeats: true) {
            [weak self, weak player] _ in
            guard let self = self, let player = player, player.isPlaying else { return }
            player.updateMeters()
            let power = player.averagePower(forChannel: 0)
            let raw = min(1, max(0, CGFloat((power + 48) / 48)))
            self.level = self.level * 0.42 + raw * 0.58
        }
    }

    private func startSyntheticMeter() {
        meterTimer?.invalidate()
        meterPhase = 0
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.075, repeats: true) {
            [weak self] _ in
            guard let self = self, self.outputting else { return }
            self.meterPhase += 0.72
            let wave = 0.32 + abs(sin(self.meterPhase)) * 0.28
            let flutter = CGFloat.random(in: 0.88...1.12)
            self.level = self.level * 0.34 + wave * flutter * 0.66
        }
    }
}

private struct LegacyAICallView: View {
    let chat: Chat

    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var voice = VoiceEngine()

    @State private var phase = "正在接通…"
    @State private var reply = ""
    @State private var busy = false
    @State private var denyReason = ""

    @State private var showCard = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x1B1B1F), Color(hex: 0x0B0B0D)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer().frame(height: 70)
                Button { showCard = true } label: {
                    Avatar(path: chat.avatar ?? "", size: 96, radius: 16)
                }
                .buttonStyle(.plain)
                Text(chat.name)
                    .font(pf(22, .medium))
                    .foregroundColor(.white)
                    .padding(.top, 16)
                Text(phase)
                    .font(pf(14))
                    .foregroundColor(Color.white.opacity(0.7))
                    .padding(.top, 8)

                if !voice.heard.isEmpty {
                    Text(Lang.isEnglish ? "You: \(voice.heard)" : "你说：\(voice.heard)")
                        .font(pf(15))
                        .foregroundColor(Color.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                        .padding(.top, 20)
                }

                if !reply.isEmpty {
                    ScrollView {
                        Text(reply)
                            .font(pf(15))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                    }
                    .frame(maxHeight: 210)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
                }

                if !denyReason.isEmpty {
                    Text(denyReason)
                        .font(pf(13))
                        .foregroundColor(Color(hex: 0xFFB3B3))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                        .padding(.top, 14)
                }

                Spacer()

                Button {
                    if voice.listening { voice.stop() }
                    else { startListening() }
                } label: {
                    ZStack {
                        Circle()
                            .fill(voice.listening ? Color(hex: 0x19A47A) : Color.white.opacity(0.16))
                            .frame(width: 84, height: 84)
                        SVGIcon(markup: I.voice, size: 38, color: .white)
                    }
                }
                .buttonStyle(.plain)
                .disabled(busy)

                Text(voice.status)
                    .font(pf(13))
                    .foregroundColor(Color.white.opacity(0.7))
                    .padding(.top, 12)

                Button {
                    voice.stop()
                    dismiss()
                } label: {
                    Text(Tr("挂断"))
                        .font(pf(17))
                        .foregroundColor(.white)
                        .frame(width: 150, height: 48)
                        .background(RoundedRectangle(cornerRadius: 24).fill(Color(hex: 0xFA5151)))
                }
                .buttonStyle(.plain)
                .padding(.top, 26)
                .padding(.bottom, 40)
            }
        }
        .task {
            voice.authorize { ok in
                if ok {
                    phase = "已接通"
                    startListening()
                } else {
                    phase = "没给语音识别权限"
                }
            }
        }
        .onDisappear { voice.stop() }
        .sheet(isPresented: $showCard) {
            BotCardView(chat: chat).environmentObject(app)
        }
    }

    private func startListening() {
        guard !busy else { return }
        voice.start { text in
            ask(text)
        }
    }

    private func ask(_ text: String) {
        busy = true
        phase = "AI助手在想…"
        reply = ""
        denyReason = ""
        Task {
            let before = (try? await API.shared.messages(chatId: chat.id, limit: 4))?.messages.last?.id ?? ""
            _ = try? await API.shared.send(chatId: chat.id, kind: "text", content: text)
            var answer: Message?
            for _ in 0..<24 {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                guard let list = (try? await API.shared.messages(chatId: chat.id, limit: 6))?.messages else { continue }
                if let last = list.last, last.id != before, last.senderId != app.me?.id {
                    answer = last
                    break
                }
            }
            busy = false
            if let answer = answer {
                reply = answer.body
                if answer.body.contains("余额") || answer.body.contains("额度不足") {
                    denyReason = answer.body
                }
                phase = "AI助手在说话…"
                voice.speak(answer.body) {
                    phase = "已接通"
                    startListening()
                }
            } else {
                phase = "他还没回，再说一次试试"
                denyReason = "没等到回复（可能是 AI 余额不足或网络卡了）"
            }
            await app.loadChats()
        }
    }
}
