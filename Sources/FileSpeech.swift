import Foundation
import Speech

enum NativeSpeech {
    static var localeIdentifier: String {
        switch Lang.code {
        case "en": return "en-US"
        case "ru": return "ru-RU"
        default: return "zh-CN"
        }
    }

    static func recognizer() -> SFSpeechRecognizer? {
        let preferred = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
        if let preferred, preferred.isAvailable { return preferred }
        let current = SFSpeechRecognizer(locale: .current)
        if let current, current.isAvailable { return current }
        return SFSpeechRecognizer()
    }

    static func configure(_ request: SFSpeechRecognitionRequest,
                          recognizer: SFSpeechRecognizer,
                          partial: Bool) {
        request.shouldReportPartialResults = partial
        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }
        // 原生设备端识别优先；只有当前语言没有离线模型时才让系统选择在线识别。
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
    }
}

enum FileSpeech {

    static func requestAuth() {
        SFSpeechRecognizer.requestAuthorization { _ in }
    }

    static func authorize() async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { st in
                cont.resume(returning: st == .authorized)
            }
        }
    }

    static func recognize(url: URL, timeout: TimeInterval = 12) async -> String {
        guard let rec = NativeSpeech.recognizer(),
              rec.isAvailable else { return "" }
        let req = SFSpeechURLRecognitionRequest(url: url)
        NativeSpeech.configure(req, recognizer: rec, partial: false)
        return await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            var finished = false
            let done: (String) -> Void = { text in
                if finished { return }
                finished = true
                cont.resume(returning: text)
            }
            rec.recognitionTask(with: req) { result, err in
                if let r = result, r.isFinal {
                    done(r.bestTranscription.formattedString)
                } else if err != nil {
                    done("")
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { done("") }
        }
    }
}
