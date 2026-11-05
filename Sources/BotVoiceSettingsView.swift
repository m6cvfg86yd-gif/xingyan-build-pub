import SwiftUI
import AVFoundation

struct BotVoiceSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("bot.autoRead") private var autoRead = false
    @AppStorage("bot.voice") private var voiceID = ""
    @AppStorage("bot.rate") private var rate = 0.5

    private var voices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("zh") }
            .sorted { $0.language < $1.language }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(Tr("自动朗读回复"), isOn: $autoRead)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(Tr("语速"))
                            Spacer()
                            Text(rate < 0.45 ? Tr("慢") : (rate > 0.56 ? Tr("快") : Tr("正常")))
                                .foregroundColor(C.subLabel)
                        }
                        Slider(value: $rate, in: 0.3...0.7, step: 0.02)
                    }
                }

                Section(Tr("音色（系统自带 · 离线免费）")) {
                    Button {
                        voiceID = ""
                        apply()
                        Speaker.shared.speak("你好，我是小星")
                    } label: {
                        row(title: Tr("系统默认"), sub: "zh-CN", on: voiceID.isEmpty)
                    }
                    ForEach(voices, id: \.identifier) { v in
                        Button {
                            voiceID = v.identifier
                            apply()
                            Speaker.shared.speak("你好，我是小星")
                        } label: {
                            row(title: v.name, sub: v.language, on: voiceID == v.identifier)
                        }
                    }
                }

                Section {
                    Text(Tr("想更自然的声音（接近元宝那种）需要接云端语音合成——等密钥配好，这里会多出一组「真人音色」。"))
                        .font(pfStyled(size: 13))
                        .foregroundColor(C.subLabel)
                }
            }
            .navigationTitle(Tr("语音设置"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(Tr("完成")) { dismiss() } }
            }
            .onAppear { apply() }
            .onChange(of: rate) { _ in apply() }
        }
    }

    private func row(title: String, sub: String, on: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(pfStyled(size: 15.5)).foregroundColor(C.label)
                Text(sub).font(pfStyled(size: 12)).foregroundColor(C.subLabel)
            }
            Spacer()
            if on { Image(systemName: "checkmark").foregroundColor(C.green) }
        }
    }

    private func apply() {
        Speaker.chosenVoice = voiceID
        Speaker.chosenRate = Float(rate)
    }
}
