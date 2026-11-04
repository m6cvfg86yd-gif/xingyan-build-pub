import CarPlay
import UIKit

@objc(CarPlaySceneDelegate)
@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var coordinator: CarPlayCoordinator?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? CPTemplateApplicationScene else { return }
        scene.delegate = self
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        let coordinator = CarPlayCoordinator(interfaceController: interfaceController)
        self.coordinator = coordinator
        coordinator.start()
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        coordinator?.stop()
        coordinator = nil
    }
}

@MainActor
private final class CarPlayCoordinator {
    private let interfaceController: CPInterfaceController
    private let dictation = Dictation()

    private var chats: [Chat] = []
    private var tracks: [MusicTrack] = []
    private var rootTemplate: CPListTemplate?
    private var chatTemplate: CPListTemplate?
    private var voiceTemplate: CPListTemplate?
    private var activeChat: Chat?
    private var voiceText = ""
    private var voiceFinish: DispatchWorkItem?
    private var loading = false
    private var stopped = false

    init(interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
    }

    func start() {
        let template = CPListTemplate(title: "星言", sections: [])
        template.emptyViewTitleVariants = [Tr("正在连接星言")]
        rootTemplate = template
        interfaceController.setRootTemplate(template, animated: false, completion: nil)
        Task { await refresh() }
    }

    func stop() {
        stopped = true
        voiceFinish?.cancel()
        voiceFinish = nil
        dictation.stop()
        Speaker.shared.stop()
    }

    private func refresh() async {
        guard !loading, !stopped else { return }
        loading = true
        defer { loading = false }

        let user = AppState.cachedUser()
        let cachedChats = user.map { LocalStore.cachedChatList(userId: $0.id) } ?? []
        if chats.isEmpty, !cachedChats.isEmpty {
            chats = cachedChats
            updateRoot()
        }

        guard !API.shared.token.isEmpty else {
            chats = []
            tracks = []
            updateRoot()
            return
        }

        async let chatRequest: [Chat]? = try? await API.shared.chats()
        async let trackRequest: [MusicTrack] = API.shared.musicTracks()
        let freshChats = await chatRequest
        let freshTracks = await trackRequest

        if let freshChats, !freshChats.isEmpty {
            chats = freshChats
            if let user {
                LocalStore.saveChatList(freshChats, userId: user.id)
            }
        }
        if !freshTracks.isEmpty {
            tracks = freshTracks
        } else if tracks.isEmpty {
            tracks = MusicLibrary.shared.recents.map { $0.asTrack }
        }
        updateRoot()
    }

    private func updateRoot() {
        guard let rootTemplate, !stopped else { return }
        rootTemplate.updateSections(rootSections())
        rootTemplate.emptyViewTitleVariants = [Tr("暂时没有新消息")]
        rootTemplate.emptyViewSubtitleVariants = [Tr("有新消息时会显示在这里")]
    }

    private func rootSections() -> [CPListSection] {
        guard !API.shared.token.isEmpty else {
            let login = CPListItem(text: Tr("请先在 iPhone 上登录星言"),
                                   detailText: Tr("登录后车载消息和音乐会同步到这里"),
                                   image: carImage("iphone"))
            login.handler = { [weak self] _, completion in
                completion()
                self?.showAlert(title: Tr("需要登录"), message: Tr("请先打开 iPhone 上的星言完成登录"))
            }
            return [CPListSection(items: [login],
                                  header: Tr("账号"),
                                  sectionIndexTitle: nil)]
        }

        var sections: [CPListSection] = []

        var driveRows: [CPListItem] = []
        if let unread = chats.first(where: { $0.unreadCount > 0 }) ?? chats.first {
            let row = CPListItem(text: Tr("语音回复最新消息"),
                                 detailText: unread.name,
                                 image: carImage("waveform"))
            row.accessoryType = .disclosureIndicator
            row.handler = { [weak self] _, completion in
                completion()
                guard let self else { return }
                Task { await self.openChat(unread, startVoice: true) }
            }
            driveRows.append(row)
        }

        let musicDetail = MusicPlayer.shared.current.map {
            "\($0.title) · \($0.artistText)"
        } ?? Tr("打开最近播放和推荐")
        let music = CPListItem(text: Tr("听一听"),
                               detailText: musicDetail,
                               image: carImage("music.note"))
        music.accessoryType = .disclosureIndicator
        music.isPlaying = MusicPlayer.shared.playing
        music.handler = { [weak self] _, completion in
            completion()
            self?.showMusic()
        }
        driveRows.append(music)

        if !driveRows.isEmpty {
            sections.append(CPListSection(items: driveRows,
                                          header: Tr("驾驶模式"),
                                          sectionIndexTitle: nil))
        }

        let visibleChats = Array(chats.prefix(max(0, min(8, CPListTemplate.maximumItemCount - 2))))
        if !visibleChats.isEmpty {
            let rows = visibleChats.map(chatItem)
            sections.append(CPListSection(items: rows,
                                          header: Tr("最近会话"),
                                          sectionIndexTitle: nil))
        }

        if chats.isEmpty {
            let empty = CPListItem(text: Tr("暂时没有新消息"),
                                   detailText: Tr("有新消息时会显示在这里"),
                                   image: carImage("checkmark.circle"))
            empty.handler = { [weak self] _, completion in
                completion()
                Task { await self?.refresh() }
            }
            sections.append(CPListSection(items: [empty],
                                          header: Tr("消息"),
                                          sectionIndexTitle: nil))
        } else {
            let refresh = CPListItem(text: Tr("刷新消息"),
                                     detailText: nil,
                                     image: carImage("arrow.clockwise"))
            refresh.handler = { [weak self] _, completion in
                completion()
                Task { await self?.refresh() }
            }
            sections.append(CPListSection(items: [refresh],
                                          header: nil,
                                          sectionIndexTitle: nil))
        }
        return sections
    }

    private func chatItem(_ chat: Chat) -> CPListItem {
        let last = chat.lastMessage
        let who = (last?.senderName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let body = safePreview(last?.preview, kind: last?.kind)
        let prefix = who.isEmpty || who == chat.name ? "" : "\(who)："
        let unread = chat.unreadCount > 0 ? "\(chat.unreadCount) \(Tr("条未读"))" : ""
        let detailParts = [unread, prefix + body].filter { !$0.isEmpty }
        let row = CPListItem(text: chat.name,
                             detailText: detailParts.joined(separator: " · "),
                             image: carImage(chat.type == "group" ? "person.2" : "person.crop.circle"))
        row.accessoryType = .disclosureIndicator
        row.handler = { [weak self] _, completion in
            completion()
            guard let self else { return }
            Task { await self.openChat(chat, startVoice: false) }
        }
        return row
    }

    private func openChat(_ chat: Chat, startVoice: Bool) async {
        guard !stopped else { return }
        activeChat = chat

        let cached = LocalStore.cachedChat(chat.id)
        let loaded = try? await API.shared.messages(chatId: chat.id, limit: 12)
        let messages = loaded?.messages ?? cached
        if let fresh = loaded?.messages, !fresh.isEmpty {
            LocalStore.saveChat(chat.id, fresh)
        }

        let template = CPListTemplate(title: chat.name, sections: chatSections(chat, messages: messages))
        chatTemplate = template
        interfaceController.pushTemplate(template, animated: true, completion: nil)

        if startVoice {
            startVoiceReply(chat)
        } else if let latest = messages.last(where: { !$0.isRecalled }) {
            let text = readout(latest)
            if !text.isEmpty {
                Speaker.shared.speak(text)
            }
        }
    }

    private func chatSections(_ chat: Chat, messages: [Message]) -> [CPListSection] {
        var sections: [CPListSection] = []
        let visible = Array(messages.suffix(max(0, min(8, CPListTemplate.maximumItemCount - 5))))
        if !visible.isEmpty {
            let items = visible.map { message -> CPListItem in
                let body = safeMessageText(message)
                let sender = message.senderName?.isEmpty == false
                    ? message.senderName!
                    : (message.senderId == AppState.cachedUser()?.id ? Tr("我") : chat.name)
                let row = CPListItem(text: sender,
                                     detailText: body,
                                     image: carImage(message.senderId == AppState.cachedUser()?.id
                                                     ? "arrow.up.message"
                                                     : "bubble.left"))
                row.handler = { [weak self] _, completion in
                    completion()
                    self?.speakMessage(message, sender: sender)
                }
                return row
            }
            sections.append(CPListSection(items: items,
                                          header: Tr("最近消息"),
                                          sectionIndexTitle: nil))
        }

        let voice = CPListItem(text: Tr("语音回复"),
                               detailText: Tr("说完会自动识别，确认后再发送"),
                               image: carImage("mic.fill"))
        voice.accessoryType = .disclosureIndicator
        voice.handler = { [weak self] _, completion in
            completion()
            self?.startVoiceReply(chat)
        }

        var replyRows = [voice]
        for text in quickReplies(for: messages.last) {
            let row = CPListItem(text: text,
                                 detailText: Tr("快捷回复"),
                                 image: carImage("arrowshape.turn.up.left"))
            row.handler = { [weak self] _, completion in
                completion()
                guard let self else { return }
                Task { await self.send(text, in: chat) }
            }
            replyRows.append(row)
        }
        sections.append(CPListSection(items: replyRows,
                                      header: Tr("回复"),
                                      sectionIndexTitle: nil))
        return sections
    }

    private func startVoiceReply(_ chat: Chat) {
        guard !stopped else { return }
        voiceFinish?.cancel()
        voiceText = ""
        activeChat = chat
        Speaker.shared.stop()

        let listening = CPListItem(text: Tr("正在听你说"),
                                   detailText: Tr("说完停顿一下，确认后再发送"),
                                   image: carImage("waveform"))
        let template = CPListTemplate(title: Tr("语音回复"),
                                      sections: [CPListSection(items: [listening],
                                                               header: chat.name,
                                                               sectionIndexTitle: nil)])
        voiceTemplate = template
        interfaceController.pushTemplate(template, animated: true, completion: nil)

        dictation.start { [weak self] text in
            guard let self, !self.stopped else { return }
            Task { @MainActor in self.updateVoiceText(text) }
        }
    }

    private func updateVoiceText(_ text: String) {
        guard !stopped else { return }
        voiceText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = CPListItem(text: voiceText.isEmpty ? Tr("正在听你说") : voiceText,
                              detailText: voiceText.isEmpty
                                ? Tr("说完停顿一下，确认后再发送")
                                : Tr("识别结果 · 稍后自动完成"),
                              image: carImage("waveform"))
        voiceTemplate?.updateSections([
            CPListSection(items: [item],
                          header: activeChat?.name ?? Tr("语音回复"),
                          sectionIndexTitle: nil)
        ])

        voiceFinish?.cancel()
        let finish = DispatchWorkItem { [weak self] in
            guard let self, !self.stopped else { return }
            Task { @MainActor in self.finishVoiceReply() }
        }
        voiceFinish = finish
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: finish)
    }

    private func finishVoiceReply() {
        dictation.stop()
        guard let chat = activeChat, let template = voiceTemplate else { return }
        let text = voiceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            let retry = CPListItem(text: Tr("没有听清，再说一次"),
                                   detailText: Tr("点一下重新开始"),
                                   image: carImage("mic.fill"))
            retry.handler = { [weak self] _, completion in
                completion()
                self?.startVoiceReply(chat)
            }
            template.updateSections([CPListSection(items: [retry],
                                                  header: chat.name,
                                                  sectionIndexTitle: nil)])
            return
        }

        let transcript = CPListItem(text: text,
                                    detailText: Tr("确认要发送的内容"),
                                    image: carImage("text.quote"))
        transcript.handler = { _, completion in
            completion()
            Speaker.shared.speak(text)
        }

        let send = CPListItem(text: Tr("发送"),
                              detailText: nil,
                              image: carImage("paperplane.fill"))
        send.handler = { [weak self] _, completion in
            completion()
            guard let self else { return }
            Task { await self.send(text, in: chat, popVoice: true) }
        }

        let retry = CPListItem(text: Tr("重新说"),
                               detailText: nil,
                               image: carImage("mic.fill"))
        retry.handler = { [weak self] _, completion in
            completion()
            self?.startVoiceReply(chat)
        }

        let cancel = CPListItem(text: Tr("取消"),
                                detailText: nil,
                                image: carImage("xmark"))
        cancel.handler = { [weak self] _, completion in
            completion()
            self?.dictation.stop()
            self?.interfaceController.popTemplate(animated: true, completion: nil)
        }

        template.updateSections([
            CPListSection(items: [transcript], header: Tr("识别结果"), sectionIndexTitle: nil),
            CPListSection(items: [send, retry, cancel], header: Tr("操作"), sectionIndexTitle: nil)
        ])
    }

    private func send(_ text: String, in chat: Chat, popVoice: Bool = false) async {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        do {
            _ = try await API.shared.send(chatId: chat.id, text: value)
            if popVoice {
                interfaceController.popTemplate(animated: true, completion: nil)
            }
            Speaker.shared.speak(Tr("已发送"))
            showAlert(title: Tr("已发送"), message: chat.name)
        } catch {
            showAlert(title: Tr("发送失败"), message: Tr("请检查网络后重试"))
        }
    }

    private func showMusic() {
        var rows: [CPListItem] = []
        if let current = MusicPlayer.shared.current {
            let now = CPListItem(text: current.title,
                                 detailText: "\(current.artistText) · \(Tr("打开播放器"))",
                                 image: carImage("play.circle.fill"))
            now.isPlaying = MusicPlayer.shared.playing
            now.accessoryType = .disclosureIndicator
            now.handler = { [weak self] _, completion in
                completion()
                self?.showNowPlaying()
            }
            rows.append(now)
        }

        let queue = tracks.isEmpty ? MusicLibrary.shared.recents.map { $0.asTrack } : tracks
        for track in queue.prefix(max(1, CPListTemplate.maximumItemCount - 2)) {
            let row = CPListItem(text: track.title,
                                 detailText: track.artistText,
                                 image: carImage("music.note"))
            row.isPlaying = MusicPlayer.shared.playing && MusicPlayer.shared.current?.id == track.id
            row.handler = { [weak self] _, completion in
                completion()
                MusicPlayer.shared.setQueue(queue)
                MusicPlayer.shared.play(track)
                self?.showNowPlaying()
            }
            rows.append(row)
        }

        if rows.isEmpty {
            let empty = CPListItem(text: Tr("暂时没有歌曲"),
                                   detailText: Tr("在 iPhone 的听一听中添加音乐后会自动同步"),
                                   image: carImage("music.note"))
            empty.handler = { [weak self] _, completion in
                completion()
                Task { await self?.refresh() }
            }
            rows.append(empty)
        }

        let template = CPListTemplate(title: Tr("听一听"),
                                      sections: [CPListSection(items: rows,
                                                               header: Tr("驾驶播放"),
                                                               sectionIndexTitle: nil)])
        interfaceController.pushTemplate(template, animated: true, completion: nil)
    }

    private func showNowPlaying() {
        guard !(interfaceController.topTemplate is CPNowPlayingTemplate) else { return }
        interfaceController.pushTemplate(CPNowPlayingTemplate.shared,
                                         animated: true,
                                         completion: nil)
    }

    private func speakMessage(_ message: Message, sender: String) {
        guard !message.isRecalled else {
            Speaker.shared.speak(Tr("这条消息已撤回"))
            return
        }
        let body = safeMessageText(message)
        guard !body.isEmpty else { return }
        Speaker.shared.speak("\(sender)。\(body)")
    }

    private func readout(_ message: Message) -> String {
        guard !message.isRecalled else { return Tr("最新消息已撤回") }
        let sender = message.senderName?.isEmpty == false
            ? message.senderName!
            : (message.senderId == AppState.cachedUser()?.id ? Tr("我") : Tr("对方"))
        let body = safeMessageText(message)
        return body.isEmpty ? "" : "\(sender)。\(body)"
    }

    private func safeMessageText(_ message: Message) -> String {
        guard !message.isRecalled else { return Tr("消息已撤回") }
        let value = safePreview(message.body, kind: message.kindName)
        return String(value.prefix(180))
    }

    private func safePreview(_ raw: String?, kind: String?) -> String {
        switch (kind ?? "text").lowercased() {
        case "text", "notice":
            break
        case "image", "photo":
            return Tr("发来一张图片")
        case "video":
            return Tr("发来一段视频")
        case "voice", "audio":
            return Tr("发来一段语音")
        case "file":
            return Tr("发来一个文件")
        case "music":
            return Tr("分享了一首歌")
        case "call":
            return Tr("发起过通话")
        case "card":
            return Tr("分享了一张名片")
        case "redpacket":
            return Tr("发来一个红包")
        case "pat":
            return Tr("拍了拍你")
        default:
            return Tr("发来一条消息")
        }

        var text = String(raw ?? "")
        if text.hasPrefix("{"), let data = text.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let inner = object["text"] as? String {
            text = inner
        }
        text = text.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? Tr("发来一条消息") : text
    }

    private func quickReplies(for message: Message?) -> [String] {
        let text = safePreview(message?.body, kind: message?.kindName)
        if text.contains("?") || text.contains("？") {
            return [Tr("我在开车，稍后回复你"), Tr("收到，晚点说"), Tr("好")]
        }
        return [Tr("收到"), Tr("我在开车，稍后回复"), Tr("好")]
    }

    private func showAlert(title: String, message: String) {
        let done = CPAlertAction(title: Tr("知道了"), style: .default) { [weak self] _ in
            self?.interfaceController.dismissTemplate(animated: true, completion: nil)
        }
        let alert = CPAlertTemplate(titleVariants: [title], actions: [done])
        interfaceController.presentTemplate(alert, animated: true, completion: nil)
        let spoken = [title, message].filter { !$0.isEmpty }.joined(separator: "。")
        Speaker.shared.speak(spoken)
    }

    private func carImage(_ name: String) -> UIImage? {
        UIImage(systemName: name)?.withRenderingMode(.alwaysTemplate)
    }
}
