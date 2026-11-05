import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct AIWorkspaceView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var realtime = Realtime.shared
    @AppStorage("bot.autoRead") private var autoRead = false
    @AppStorage("bot.voice") private var voiceID = ""
    @AppStorage("bot.rate") private var voiceRate = 0.5

    @State private var wallet: AIWalletStatus?
    @State private var chat: Chat?
    @State private var messages: [Message] = []
    @State private var prompt = ""
    @State private var loading = true
    @State private var loadingMessages = false
    @State private var sending = false
    @State private var waitingReply = false
    @State private var uploading = false
    @State private var loadError = ""

    @State private var showCamera = false
    @State private var showPhotos = false
    @State private var showFiles = false
    @State private var showAttachMenu = false
    @State private var showRecharge = false
    @State private var showProfile = false
    @State private var showTopClearConfirm = false
    @State private var callChat: Chat?
    @State private var web: WebURL?
    @State private var spoken = Set<String>()

    @FocusState private var inputFocused: Bool

    private let accent = Color(hex: 0x356FF4)

    private var aiName: String {
        let value = wallet?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "小星" : value
    }

    private var myId: String { app.me?.id ?? "" }
    private var workspaceClearSeqKey: String {
        "ai.workspace.clearSeq." + (myId.isEmpty ? "default" : myId)
    }
    private var canSend: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !sending && !uploading
    }
    private var cloudSpeechAvailable: Bool {
        guard let current = wallet else { return false }
        return current.tier != "starter" && !(current.voices ?? []).isEmpty
    }
    private var voiceCallAvailable: Bool {
        guard let current = wallet else { return false }
        return current.voiceCall == true && current.tier != "starter"
    }
    private var tierName: String {
        let name = wallet?.tierName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "轻量包" : name
    }

    var body: some View {
        VStack(spacing: 0) {
            navBar

            if loading && wallet == nil {
                VStack(spacing: 12) {
                    ProgressView().tint(accent)
                    Text(Tr("正在进入 AI 工作台"))
                        .font(pf(12.5))
                        .foregroundColor(C.subLabel)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if wallet == nil {
                unavailable
            } else {
                workspace
            }
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .task {
            await load()
            await poll()
        }
        .onChange(of: realtime.event) { _ in
            guard chat != nil else { return }
            Task { await loadMessages(silent: true) }
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker { image in
                sendImage(image)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showPhotos) {
            PhotoPicker { image in
                sendImage(image)
            }
        }
        .sheet(isPresented: $showProfile, onDismiss: {
            Task { await load(showLoading: false) }
        }) {
            if let current = wallet {
                AIProfileSheet(wallet: current, onClearChat: clearWorkspaceChat)
                    .environmentObject(app)
            }
        }
        .fullScreenCover(isPresented: $showRecharge, onDismiss: {
            Task { await load(showLoading: false) }
        }) {
            if let current = wallet {
                AIRechargeView(wallet: current) { updated in
                    wallet = updated
                }
                .environmentObject(app)
            }
        }
        .fullScreenCover(item: $callChat) {
            AICallView(chat: $0)
                .environmentObject(app)
        }
        .sheet(item: $web) {
            SafariSheet(url: $0.url)
        }
        .fileImporter(isPresented: $showFiles,
                      allowedContentTypes: [.item],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { sendFile(url) }
            case .failure:
                app.show(Tr("没有选中文件"))
            }
        }
        .confirmationDialog(Tr("添加内容"), isPresented: $showAttachMenu, titleVisibility: .visible) {
            Button(Tr("拍照")) { showCamera = true }
            Button(Tr("相册")) { showPhotos = true }
            Button(Tr("文件")) { showFiles = true }
            Button(Tr("取消"), role: .cancel) { }
        }
        .overlay {
            if uploading {
                ZStack {
                    Color.black.opacity(0.18).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView().tint(accent)
                        Text(Tr("正在上传…"))
                            .font(pf(13, .medium))
                            .foregroundColor(C.label)
                    }
                    .padding(.horizontal, 26)
                    .padding(.vertical, 20)
                    .background(C.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.16), radius: 20, y: 8)
                }
            }
        }
    }

    private var navBar: some View {
        let titleView = AnyView(
            HStack(spacing: 7) {
                Text("✦")
                    .font(pfStyled(size: 15, weight: .semibold))
                    .foregroundColor(accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(aiName)
                        .font(pf(16, .semibold))
                        .foregroundColor(C.label)
                        .lineLimit(1)
                    Text((messages.isEmpty ? Tr("快速回答") : Tr("正在对话"))
                         + " · " + tierName)
                        .font(pf(9.5))
                        .foregroundColor(C.subLabel)
                        .lineLimit(1)
                }
            }
        )
        return NavBar(title: aiName, back: { dismiss() }, titleView: titleView) {
            HStack(spacing: 7) {
                Button {
                    showProfile = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(C.subLabel)
                        .frame(width: 34, height: 34)
                        .background { GlassBackground(shape: Circle(), shadow: true, seed: 0.38) }
                }
                .buttonStyle(.plain)

                Button {
                    openCall()
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(voiceCallAvailable ? accent : C.subLabel)
                        if !voiceCallAvailable {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(Color(hex: 0xB27C37))
                                .offset(x: 1, y: -1)
                        }
                    }
                    .frame(width: 34, height: 34)
                    .background { GlassBackground(shape: Circle(), shadow: true, seed: 0.54) }
                }
                .buttonStyle(.plain)

                Button {
                    showAttachMenu = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(C.label)
                        .frame(width: 34, height: 34)
                        .background {
                            GlassBackground(shape: Circle(),
                                            shadow: true,
                                            seed: 0.70,
                                            tint: Color(hex: 0xEEF2F8).opacity(0.45))
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var unavailable: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 30, weight: .medium))
                .foregroundColor(accent)
            Text(Tr("AI 工作台暂时不可用"))
                .font(pf(17, .semibold))
                .foregroundColor(C.label)
            Text(loadError.isEmpty ? Tr("请检查网络后再试") : loadError)
                .font(pf(13))
                .foregroundColor(C.subLabel)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Button(Tr("重新加载")) {
                Task { await load() }
            }
            .font(pf(14, .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .frame(height: 40)
            .background(Capsule().fill(accent))
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var workspace: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if messages.isEmpty && !loadingMessages {
                        emptyState
                    } else {
                        ForEach(messages) { message in
                            messageRow(message)
                                .id(message.id)
                        }
                        if waitingReply {
                            typingRow.id("ai-working")
                        }
                    }
                    Color.clear.frame(height: 1).id("ai-bottom")
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(TapGesture().onEnded {
                inputFocused = false
            })
            .onChange(of: messages.count) { _ in
                scrollBottom(proxy)
            }
            .onChange(of: waitingReply) { _ in
                scrollBottom(proxy)
            }
            .onChange(of: inputFocused) { focused in
                if focused { scrollBottom(proxy) }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composer
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("Hi，" + displayName)
                .font(pf(27, .bold))
                .foregroundColor(C.label)
                .multilineTextAlignment(.center)

            Text(wallet?.tier == "starter"
                 ? Tr("我是") + aiName + Tr("，现在可以陪你简单聊聊，回答日常问题")
                 : Tr("我是") + aiName + Tr("，聊天、写作、搜索、文件和办公都能帮你"))
                .font(pf(14.5))
                .foregroundColor(C.subLabel)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 310)

            if wallet?.tier == "starter" {
                VStack(spacing: 4) {
                    Text(Tr("轻量包为纯聊天模式"))
                        .font(pf(11.5, .medium))
                        .foregroundColor(C.label)
                    Text(Tr("写作、搜索、文件、办公、代码和语音需要升级标准包"))
                        .font(pf(10))
                        .foregroundColor(C.subLabel)
                        .multilineTextAlignment(.center)
                    Button(Tr("查看标准包")) {
                        showRecharge = true
                    }
                    .font(pf(10.5))
                    .foregroundColor(accent)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(C.fieldBg.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if wallet?.tier != "starter" {
                HStack(spacing: 8) {
                    officeQuickButton(
                        title: Tr("Word 文档"),
                        symbol: "doc.text.fill",
                        prompt: Tr("请帮我用 Word 写一份工作文档，主题是：")
                    )
                    officeQuickButton(
                        title: Tr("Excel 表格"),
                        symbol: "tablecells.fill",
                        prompt: Tr("请帮我用 Excel 做一份表格，内容包括：")
                    )
                    if wallet?.tier == "pro" {
                        officeQuickButton(
                            title: Tr("网页 H5"),
                            symbol: "safari.fill",
                            prompt: Tr("请直接做一个完整、可打开、可交互的网页或小程序，需求是：")
                        )
                    }
                }
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 32)
        .padding(.bottom, 24)
    }

    private var displayName: String {
        let nickname = app.me?.nickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !nickname.isEmpty { return nickname }
        let username = app.me?.username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return username.isEmpty ? Tr("你好") : username
    }

    private func officeQuickButton(title: String, symbol: String,
                                   prompt text: String) -> some View {
        Button {
            prompt = text
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                inputFocused = true
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(accent)
                Text(title)
                    .font(pf(12, .medium))
                    .foregroundColor(C.label)
                    .lineLimit(1)
            }
            .padding(.horizontal, 13)
            .frame(height: 38)
            .background {
                GlassBackground(shape: Capsule(), opacity: 0.78,
                                shadow: true, seed: 0.58)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func messageRow(_ message: Message) -> some View {
        let mine = message.senderId == myId
        let isImage = message.kindName.lowercased() == "image"
        if mine {
            HStack(alignment: .top, spacing: 8) {
                Spacer(minLength: 42)
                if isImage {
                    messageContent(message, mine: true)
                } else {
                    messageContent(message, mine: true)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 10)
                        .background(accent)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                Avatar(path: app.me?.avatarPath ?? "", size: 32, radius: 11)
            }
            .padding(.bottom, 14)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 8) {
                    AIWorkspaceMark()
                    if isImage {
                        messageContent(message, mine: false)
                            .frame(maxWidth: 330, alignment: .leading)
                    } else {
                        messageContent(message, mine: false)
                            .frame(maxWidth: 330, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background {
                                GlassBackground(shape: RoundedRectangle(cornerRadius: 15,
                                                                        style: .continuous),
                                                opacity: 0.72,
                                                shadow: false,
                                                seed: 0.24)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .stroke(C.hairline.opacity(0.55), lineWidth: 0.5))
                    }
                    Spacer(minLength: 12)
                }

                if !isImage, !speechText(message).isEmpty {
                    HStack(spacing: 0) {
                        Spacer().frame(width: 40)
                        Button {
                            speak(speechText(message))
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "speaker.wave.2")
                                Text(Tr("朗读"))
                            }
                            .font(pf(10.5, .medium))
                            .foregroundColor(C.subLabel)
                            .padding(.horizontal, 8)
                            .frame(height: 26)
                            .background(Capsule().fill(C.fieldBg.opacity(0.82)))
                        }
                        .buttonStyle(.plain)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.bottom, 17)
        }
    }

    @ViewBuilder
    private func messageContent(_ message: Message, mine: Bool) -> some View {
        if message.isRecalled {
            Text(Tr("这条消息已撤回"))
                .font(pf(12.5))
                .foregroundColor(mine ? Color.white.opacity(0.72) : C.subLabel)
        } else {
            switch message.kindName.lowercased() {
            case "link":
                if let link = linkPayload(message.body) {
                    AIWorkspaceLinkCard(payload: link, accent: accent) {
                        open(link)
                    }
                } else {
                    messageText(message, mine: mine)
                }
            case "image":
                RemoteImage(path: message.imagePath, mode: .fill, maxSide: 1000)
                    .frame(width: 220, height: 164)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            case "file":
                fileCard(message, mine: mine)
            default:
                if !mine, let target = firstWebLink(message.body) {
                    VStack(alignment: .leading, spacing: 9) {
                        messageText(message, mine: false)
                        AIWorkspacePlainLinkCard(url: target, accent: accent) {
                            web = WebURL(url: target)
                        }
                    }
                } else {
                    messageText(message, mine: mine)
                }
            }
        }
    }

    private func messageText(_ message: Message, mine: Bool) -> some View {
        let body = message.body.trimmingCharacters(in: .whitespacesAndNewlines)
        return Text(RichText.lines(body.isEmpty ? "[" + message.kindName + "]" : body, size: 15.5))
            .font(pf(15.5))
            .lineSpacing(4)
            .foregroundColor(mine ? .white : C.label)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func fileCard(_ message: Message, mine: Bool) -> some View {
        let info = filePayload(message.body)
        return Button {
            if let url = info.url, let target = URL(string: url) {
                web = WebURL(url: target)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(mine ? .white : accent)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(mine ? Color.white.opacity(0.15) : accent.opacity(0.10)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.name)
                        .font(pf(13.5, .medium))
                        .foregroundColor(mine ? .white : C.label)
                        .lineLimit(1)
                    Text(Tr("点击查看文件"))
                        .font(pf(10.5))
                        .foregroundColor(mine ? Color.white.opacity(0.7) : C.subLabel)
                }
                Spacer(minLength: 4)
            }
            .padding(10)
            .frame(width: 220, alignment: .leading)
            .background(mine ? Color.white.opacity(0.10) : C.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var typingRow: some View {
        HStack(alignment: .center, spacing: 8) {
            AIWorkspaceMark()
            HStack(spacing: 7) {
                ProgressView()
                    .controlSize(.small)
                    .tint(accent)
                Text(aiName + Tr("正在整理回答"))
                    .font(pf(13))
                    .foregroundColor(C.subLabel)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background {
                GlassBackground(shape: RoundedRectangle(cornerRadius: 15,
                                                        style: .continuous),
                                opacity: 0.68,
                                shadow: false,
                                seed: 0.44)
            }
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            Spacer(minLength: 12)
        }
        .padding(.bottom, 16)
    }

    private var composer: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                if wallet?.tier != "starter" {
                    Button {
                        showAttachMenu = true
                    } label: {
                        Image(systemName: "camera")
                            .font(.system(size: 19, weight: .regular))
                            .foregroundColor(C.label)
                            .frame(width: 42, height: 42)
                    }
                    .buttonStyle(.plain)
                }

                TextField(wallet?.tier == "starter"
                          ? Tr("和小星简单聊聊")
                          : Tr("开启一天的工作之旅吧..."),
                          text: $prompt, axis: .vertical)
                    .font(pf(15.5))
                    .foregroundColor(C.label)
                    .tint(accent)
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .padding(.vertical, 9)

                Button {
                    submit(prompt)
                } label: {
                    Image(systemName: waitingReply ? "hourglass" : "arrow.up")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(canSend
                                                  ? accent
                                                  : Color.dyn(0xF1F2F4, 0x262C35)))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(3)
            .background { AIChatSystemGlass() }

            tokenBar

            Text(Tr("内容由 AI 生成，仅供参考"))
                .font(pf(9.5))
                .foregroundColor(C.subLabel)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 4)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private var tokenBar: some View {
        HStack(spacing: 8) {
            Text(Tr("约 ") + wordText(wallet?.tokens ?? 0) + Tr(" 可用"))
            Text("·")
            Text(Tr("已用约 ") + wordText(wallet?.used ?? 0))
            Button {
                showRecharge = true
            } label: {
                Text(Tr("购买"))
                    .font(pf(10.5, .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 11)
                    .frame(height: 25)
                    .background(Capsule().fill(accent))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .font(pf(10.5))
        .foregroundColor(C.subLabel)
        .frame(maxWidth: .infinity)
        .padding(.top, 7)
        .padding(.bottom, 2)
    }

    private func scrollBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("ai-bottom", anchor: .bottom)
            }
        }
    }

    private func load(showLoading: Bool = true) async {
        if showLoading { loading = true }
        do {
            wallet = try await API.shared.aiWallet()
            loadError = ""
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
        await prepareChat()
    }

    private func prepareChat() async {
        if chat == nil {
            await app.loadChats()
            chat = workspaceChat(in: app.chats)
        }
        if chat != nil { await loadMessages(silent: false) }
    }

    private func loadMessages(silent: Bool) async {
        guard let chat = chat else { return }
        if !silent { loadingMessages = true }
        if let result = try? await API.shared.messages(chatId: chat.id, limit: 60) {
            let clearSeq = UserDefaults.standard.integer(forKey: workspaceClearSeqKey)
            messages = result.messages.filter { ($0.seq ?? 0) > clearSeq }
            if let last = messages.last, last.senderId != myId {
                waitingReply = false
            }
            if let last = messages.last, last.senderId != myId {
                autoReadLatest(last)
            }
        }
        loadingMessages = false
    }

    private func poll() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            if Task.isCancelled { return }
            if chat != nil { await loadMessages(silent: true) }
        }
    }

    private func submit(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending, !uploading else { return }
        prompt = ""
        inputFocused = false
        Task {
            guard let target = await resolveChat() else { return }
            await deliverText(text, chat: target)
        }
    }

    private func deliverText(_ text: String, chat target: Chat) async {
        sending = true
        waitingReply = true
        do {
            _ = try await API.shared.send(chatId: target.id,
                                          kind: "text",
                                          content: text,
                                          clientId: UUID().uuidString.lowercased())
            await loadMessages(silent: true)
            sending = false
            await waitForReply()
        } catch {
            sending = false
            waitingReply = false
            app.show((error as? LocalizedError)?.errorDescription ?? "发送失败，请检查网络")
        }
    }

    private func waitForReply() async {
        for _ in 0..<45 {
            if Task.isCancelled || !waitingReply { return }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if Task.isCancelled { return }
            await loadMessages(silent: true)
        }
        if waitingReply {
            waitingReply = false
            app.show(Tr("小星还在处理，回复到了会自动显示"))
        }
    }

    private func sendImage(_ image: UIImage) {
        guard !uploading else { return }
        let ask = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        prompt = ""
        uploading = true
        waitingReply = true
        Task {
            do {
                let target = await resolveChat()
                guard let target = target else {
                    uploading = false
                    waitingReply = false
                    return
                }
                let uploaded = try await API.shared.uploadImageForSend(image, original: false)
                _ = try await API.shared.send(chatId: target.id,
                                              kind: "image",
                                              content: uploaded.url,
                                              clientId: UUID().uuidString.lowercased(),
                                              imgW: Int(image.size.width * image.scale),
                                              imgH: Int(image.size.height * image.scale))
                uploading = false
                await loadMessages(silent: true)
                await deliverText(ask.isEmpty ? Tr("请看看这张图片，告诉我里面有什么重点。") : ask,
                                  chat: target)
            } catch {
                uploading = false
                waitingReply = false
                app.show((error as? LocalizedError)?.errorDescription ?? "图片发送失败")
            }
        }
    }

    private func sendFile(_ url: URL) {
        guard !uploading else { return }
        let ask = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        prompt = ""
        uploading = true
        waitingReply = true
        Task {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let target = await resolveChat()
                guard let target = target else {
                    uploading = false
                    waitingReply = false
                    return
                }
                let staged = try await Task.detached(priority: .userInitiated) {
                    try FileUploadStaging.copyToTemporary(url)
                }.value
                defer { try? FileManager.default.removeItem(at: staged.deletingLastPathComponent()) }
                let values = try staged.resourceValues(forKeys: [.fileSizeKey, .nameKey])
                let bytes = values.fileSize ?? 0
                guard bytes > 0 else { throw APIError.message("读不到这个文件") }
                guard bytes <= 100 * 1024 * 1024 else {
                    throw APIError.message("文件超过 100MB，请先压缩再发")
                }
                let name = values.name ?? (staged.lastPathComponent.isEmpty ? "file" : staged.lastPathComponent)
                let uploadedURL = try await API.shared.uploadBinaryFile(
                    staged, mime: "application/octet-stream",
                    skipTranscode: true, onProgress: { _ in })
                let safeName = name.replacingOccurrences(of: "\"", with: "")
                    .replacingOccurrences(of: "\\", with: "")
                let content = "{\"url\":\"\(uploadedURL)\",\"name\":\"\(safeName)\",\"bytes\":\(bytes),\"mime\":\"\(UTType(filenameExtension: staged.pathExtension)?.preferredMIMEType ?? "application/octet-stream")\"}"
                _ = try await API.shared.send(chatId: target.id,
                                              kind: "file",
                                              content: content,
                                              clientId: UUID().uuidString.lowercased())
                uploading = false
                await loadMessages(silent: true)
                await deliverText(ask.isEmpty ? Tr("请阅读这份文件并提炼重点。") : ask,
                                  chat: target)
            } catch {
                uploading = false
                waitingReply = false
                app.show((error as? LocalizedError)?.errorDescription ?? "文件发送失败")
            }
        }
    }

    private func resolveChat() async -> Chat? {
        if let chat = chat { return chat }
        await app.loadChats()
        let found = workspaceChat(in: app.chats)
        chat = found
        if found == nil { app.show(Tr("小星正在准备中，请稍后再试")) }
        return found
    }

    private func workspaceChat(in chats: [Chat]) -> Chat? {
        chats.first(where: { $0.bot == "housekeeper" })
            ?? chats.first(where: { $0.botRank == 0 && $0.type != "group" })
    }

    private func openCall() {
        guard voiceCallAvailable else {
            app.show(Tr("语音通话需标准包，已为你打开补充页"))
            showRecharge = true
            return
        }
        Task {
            if let target = await resolveChat() { callChat = target }
        }
    }

    private func clearWorkspaceChat() async -> String? {
        let target: Chat
        if let chat = chat {
            target = chat
        } else if let found = await resolveChat() {
            target = found
        } else {
            return "小星会话还没有准备好"
        }
        if let error = await API.shared.clearChat(chatId: target.id) {
            return error
        }
        let clearSeq = messages.compactMap { $0.seq }.max() ?? 0
        if clearSeq > 0 {
            UserDefaults.standard.set(clearSeq, forKey: workspaceClearSeqKey)
        }
        LocalStore.clearChat(target.id)
        LocalNotify.clearChat(target.id)
        await MainActor.run {
            messages = []
            waitingReply = false
            spoken = []
        }
        return nil
    }

    private func autoReadLatest(_ message: Message) {
        guard autoRead, !spoken.contains(message.id) else { return }
        let text = speechText(message)
        guard !text.isEmpty else { return }
        spoken.insert(message.id)
        speak(text)
    }

    private func speechText(_ message: Message) -> String {
        guard !message.isRecalled else { return "" }
        let text = message.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.hasPrefix("{") else { return "" }
        return text
    }

    private func speak(_ text: String) {
        Speaker.chosenVoice = voiceID
        Speaker.chosenRate = Float(voiceRate)
        Speaker.shared.speak(text)
        app.show(Tr("正在朗读…"))
    }

    private func open(_ link: AIWorkspaceLinkPayload) {
        if let raw = link.scheme, !raw.isEmpty, let target = URL(string: raw),
           UIApplication.shared.canOpenURL(target) {
            UIApplication.shared.open(target)
            return
        }
        if let target = URL(string: link.url), ["http", "https"].contains(target.scheme?.lowercased() ?? "") {
            if ExternalLinkRouter.openIfNeeded(target) { return }
            web = WebURL(url: target)
            return
        }
        app.show(Tr("这个链接暂时打不开"))
    }

    private func linkPayload(_ body: String) -> AIWorkspaceLinkPayload? {
        guard let data = body.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AIWorkspaceLinkPayload.self, from: data)
    }

    private func filePayload(_ body: String) -> (name: String, url: String?) {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (body.isEmpty ? "文件" : body, nil)
        }
        let name = (object["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "文件"
        let path = object["url"] as? String
        return (name.isEmpty ? "文件" : name,
                path.flatMap { API.shared.assetURL($0)?.absoluteString })
    }

    private func firstWebLink(_ body: String) -> URL? {
        guard let regex = try? NSRegularExpression(pattern: "https?://[^\\s<>]+",
                                                   options: [.caseInsensitive]) else { return nil }
        let source = body as NSString
        guard let match = regex.firstMatch(in: body, range: NSRange(location: 0, length: source.length))
        else { return nil }
        var raw = source.substring(with: match.range)
        while let last = raw.last, ".,，。!！?？;；)".contains(last) {
            raw.removeLast()
        }
        return URL(string: raw)
    }

    private func compactTokens(_ value: Int) -> String {
        let n = max(0, value)
        if n >= 1_000_000 {
            let v = Double(n) / 1_000_000
            return String(format: v >= 10 ? "%.0fM" : "%.1fM", v)
        }
        if n >= 1_000 {
            let v = Double(n) / 1_000
            return String(format: v >= 100 ? "%.0fK" : "%.1fK", v)
        }
        return String(n)
    }

    private func wordText(_ value: Int) -> String {
        let n = max(0, value)
        if n >= 10_000 {
            let v = Double(n) / 10_000
            return String(format: v >= 100 ? "%.0f万字" : "%.1f万字", v)
        }
        return "\(n)字"
    }
}

private struct AIWorkspaceLinkPayload: Decodable {
    var title: String?
    var sub: String?
    var url: String
    var scheme: String?
    var image: String?
    var cardType: String?
    var badge: String?
    var action: String?
    var keyword: String?
    var meta: String?
    var reviews: String?
}

private struct AIWorkspaceLinkCard: View {
    let payload: AIWorkspaceLinkPayload
    let accent: Color
    let onTap: () -> Void

    private var title: String {
        let value = payload.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "打开链接" : value
    }

    private var subtitle: String {
        let value = payload.sub?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !value.isEmpty { return value }
        return payload.meta ?? payload.url
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                if let image = payload.image, !image.isEmpty {
                    RemoteImage(path: image, mode: .fill, maxSide: 500)
                        .frame(height: 108)
                }
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(title)
                                .font(pf(14.5, .semibold))
                                .foregroundColor(C.label)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            if !subtitle.isEmpty {
                                Text(subtitle)
                                    .font(pf(11.5))
                                    .foregroundColor(C.subLabel)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(accent)
                            .frame(width: 25, height: 25)
                            .background(Circle().fill(accent.opacity(0.09)))
                    }
                    if let badge = payload.badge, !badge.isEmpty {
                        Text(badge)
                            .font(pf(9.5, .medium))
                            .foregroundColor(accent)
                            .padding(.horizontal, 7)
                            .frame(height: 19)
                            .background(Capsule().fill(accent.opacity(0.09)))
                    }
                }
                .padding(12)
            }
            .frame(width: 280, alignment: .leading)
            .background(C.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(C.hairline, lineWidth: 0.7))
        }
        .buttonStyle(.plain)
    }
}

private struct AIWorkspacePlainLinkCard: View {
    let url: URL
    let accent: Color
    let onTap: () -> Void

    private var host: String {
        let value = url.host ?? url.absoluteString
        return value.hasPrefix("www.") ? String(value.dropFirst(4)) : value
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 9) {
                Image(systemName: "safari.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(accent)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(accent.opacity(0.09)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(host)
                        .font(pf(12.5, .medium))
                        .foregroundColor(C.label)
                        .lineLimit(1)
                    Text(Tr("在星言内打开链接"))
                        .font(pf(10.5))
                        .foregroundColor(C.subLabel)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(C.subLabel)
            }
            .padding(10)
            .background(C.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(C.hairline, lineWidth: 0.7))
        }
        .buttonStyle(.plain)
    }
}

private struct AIRechargeView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var wallet: AIWalletStatus
    @State private var selectedPlan: AITokenPlan?

    let onUpdate: (AIWalletStatus) -> Void
    private let accent = Color(hex: 0x356FF4)

    private var plans: [AITokenPlan] {
        if !wallet.plans.isEmpty {
            return wallet.plans
        }
        return [
            AITokenPlan(id: "starter", name: "轻量包", tokens: 1_000_000,
                        bonus: 0, price: 15.90, tag: "入门",
                        desc: "只支持简单文字对话；不含办公、代码和语音"),
            AITokenPlan(id: "standard", name: "标准包", tokens: 5_000_000,
                        bonus: 500_000, price: 59.90, tag: "推荐",
                        desc: "写作、联网、文件、办公、长上下文和语音通话"),
            AITokenPlan(id: "pro", name: "专业包", tokens: 20_000_000,
                        bonus: 3_000_000, price: 199, tag: "高用量",
                        desc: "代码、完整代办、最高输出上限和超长对话")
        ]
    }

    init(wallet: AIWalletStatus, onUpdate: @escaping (AIWalletStatus) -> Void) {
        _wallet = State(initialValue: wallet)
        self.onUpdate = onUpdate
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("购买 AI 套餐"), back: { dismiss() }) { }
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(Tr("当前方案"))
                                    .font(pf(11.5))
                                    .foregroundColor(C.subLabel)
                                Text(wallet.tierName ?? "轻量包")
                                    .font(pf(18, .semibold))
                                    .foregroundColor(C.label)
                            }
                            Spacer()
                            HStack(spacing: 5) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 10, weight: .bold))
                                Text(compact(wallet.tokens) + " Token")
                                    .font(pf(12.5, .semibold))
                            }
                            .foregroundColor(accent)
                        }
                        Text(Tr("按使用量计费。充值后立即到账，可在工作台查看消耗。"))
                            .font(pf(12))
                            .foregroundColor(C.subLabel)
                            .lineSpacing(3)
                    }
                    .padding(16)
                    .background(C.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(C.hairline, lineWidth: 0.7))

                    Text(Tr("选择套餐"))
                        .font(pf(16, .semibold))
                        .foregroundColor(C.label)

                    ForEach(plans) { plan in
                        planCard(plan)
                    }

                    Text(Tr("Token 用于 AI 问答、文件理解和代办任务。套餐功能以实际账号权限为准。"))
                        .font(pf(10.5))
                        .foregroundColor(C.subLabel)
                        .lineSpacing(3)
                        .padding(.top, 2)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $selectedPlan) { plan in
            AIPaymentSheet(plan: plan, accent: accent) { result in
                var current = wallet
                current.tokens = result.tokens
                wallet = current
                onUpdate(current)
                app.show(Tr("Token 已到账"))
                Task { await refresh() }
            }
            .environmentObject(app)
        }
    }

    private func planCard(_ plan: AITokenPlan) -> some View {
        let recommended = plan.tag == "推荐" || plan.id == "standard"
        return Button {
            selectedPlan = plan
        } label: {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 8) {
                    Text(plan.name)
                        .font(pf(17, .semibold))
                        .foregroundColor(C.label)
                    if recommended {
                        Text(Tr("推荐"))
                            .font(pf(9, .medium))
                            .foregroundColor(accent)
                            .padding(.horizontal, 7)
                            .frame(height: 19)
                            .background(Capsule().fill(accent.opacity(0.10)))
                    }
                    Spacer()
                    Text("¥" + moneyFmt(plan.price))
                        .font(pfMoney(22, .bold))
                        .foregroundColor(C.label)
                }

                HStack(spacing: 6) {
                    Text(compact(plan.granted) + " Token")
                        .font(pf(12.5, .semibold))
                        .foregroundColor(accent)
                    if plan.bonus > 0 {
                        Text(Tr("含赠送") + compact(plan.bonus))
                            .font(pf(10.5))
                            .foregroundColor(C.subLabel)
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    ForEach(features(for: plan), id: \.self) { feature in
                        HStack(spacing: 7) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(accent)
                                .frame(width: 16, height: 16)
                                .background(Circle().fill(accent.opacity(0.09)))
                            Text(feature)
                                .font(pf(12))
                                .foregroundColor(C.subLabel)
                        }
                    }
                }

                HStack {
                    if let desc = plan.desc, !desc.isEmpty {
                        Text(desc)
                            .font(pf(10.5))
                            .foregroundColor(C.subLabel)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    Text(Tr("购买"))
                        .font(pf(12, .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 15)
                        .frame(height: 31)
                        .background(Capsule().fill(accent))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(C.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(recommended ? accent.opacity(0.46) : C.hairline,
                        lineWidth: recommended ? 1 : 0.7))
        }
        .buttonStyle(.plain)
    }

    private func features(for plan: AITokenPlan) -> [String] {
        switch plan.id {
        case "pro":
            return [
                Tr("写作、联网检索、文件与图片理解"),
                Tr("Word / Excel / PPT 与代码工作"),
                Tr("复杂网页 / H5 / 小程序成品直接打开"),
                Tr("语音通话、代码排查和完整代办"),
                Tr("AI 点外卖、购物与消息代办")
            ]
        case "standard":
            return [
                Tr("写作、联网检索、文件与图片理解"),
                Tr("Word / Excel / PPT 办公"),
                Tr("语音通话与长上下文"),
                Tr("提醒、天气与消息代办")
            ]
        default:
            return [
                Tr("简单文字对话"),
                Tr("基础问答与灵感"),
                Tr("不包含文件和代码服务"),
                Tr("不包含语音通话")
            ]
        }
    }

    private func refresh() async {
        guard let updated = try? await API.shared.aiWallet() else { return }
        wallet = updated
        onUpdate(updated)
    }

    private func compact(_ value: Int) -> String {
        let n = max(0, value)
        if n >= 1_000_000 {
            let v = Double(n) / 1_000_000
            return String(format: v >= 10 ? "%.0fM" : "%.1fM", v)
        }
        if n >= 1_000 {
            let v = Double(n) / 1_000
            return String(format: v >= 100 ? "%.0fK" : "%.1fK", v)
        }
        return String(n)
    }
}

private struct AIPaymentSheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    let plan: AITokenPlan
    let accent: Color
    let onPaid: (AITokenPurchaseResult) -> Void

    @State private var password = ""
    @State private var requestId = UUID().uuidString.lowercased()
    @State private var paying = false
    @State private var errorText = ""
    @FocusState private var focused: Bool

    private var valid: Bool { password.count == 6 && !paying }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(Tr("确认充值"))
                    .font(pf(18, .semibold))
                    .foregroundColor(C.label)
                Spacer()
                Button(Tr("关闭")) { dismiss() }
                    .font(pf(13))
                    .foregroundColor(C.subLabel)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .frame(height: 58)

            VStack(alignment: .leading, spacing: 7) {
                Text(plan.name)
                    .font(pf(16, .semibold))
                    .foregroundColor(C.label)
                Text(compact(plan.granted) + " Token · ¥" + moneyFmt(plan.price))
                    .font(pf(13, .medium))
                    .foregroundColor(accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .background(accent.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 20)

            SecureField(Tr("输入 6 位支付密码"), text: $password)
                .keyboardType(.numberPad)
                .textContentType(.password)
                .focused($focused)
                .font(pf(17, .medium))
                .padding(.horizontal, 14)
                .frame(height: 50)
                .background(C.fieldBg)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .onChange(of: password) { value in
                    let clean = String(value.filter { $0 >= "0" && $0 <= "9" }.prefix(6))
                    if clean != value { password = clean }
                    errorText = ""
                }

            if !errorText.isEmpty {
                Text(errorText)
                    .font(pf(12.5))
                    .foregroundColor(C.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 9)
            }

            Button {
                pay()
            } label: {
                HStack(spacing: 8) {
                    if paying { ProgressView().tint(.white) }
                    Text(paying ? Tr("处理中…") : Tr("确认支付"))
                        .font(pf(14.5, .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(valid ? accent : accent.opacity(0.35)))
            }
            .buttonStyle(.plain)
            .disabled(!valid)
            .padding(.horizontal, 20)
            .padding(.top, 18)

            Text(Tr("Token 为虚拟数字权益，购买后立即到账，不支持退款。"))
                .font(pf(10.5))
                .foregroundColor(C.subLabel)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 26)
                .padding(.top, 12)

            Spacer(minLength: 20)
        }
        .background(C.cardBg.ignoresSafeArea())
        .onAppear { focused = true }
    }

    private func pay() {
        guard valid else { return }
        paying = true
        errorText = ""
        Task {
            do {
                let result = try await API.shared.buyAITokens(planId: plan.id,
                                                              password: password,
                                                              requestId: requestId)
                await MainActor.run {
                    paying = false
                    onPaid(result)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    paying = false
                    errorText = (error as? LocalizedError)?.errorDescription ?? "充值失败，请稍后再试"
                }
            }
        }
    }

    private func compact(_ value: Int) -> String {
        let n = max(0, value)
        if n >= 1_000_000 {
            let v = Double(n) / 1_000_000
            return String(format: v >= 10 ? "%.0fM" : "%.1fM", v)
        }
        if n >= 1_000 {
            let v = Double(n) / 1_000
            return String(format: v >= 100 ? "%.0fK" : "%.1fK", v)
        }
        return String(n)
    }
}

private struct AIProfileSheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @AppStorage("bot.autoRead") private var autoRead = false

    let wallet: AIWalletStatus
    let onClearChat: () async -> String?

    @State private var name = ""
    @State private var selectedVoice = ""
    @State private var learning = true
    @State private var learned = 0
    @State private var savingName = false
    @State private var showResetConfirm = false
    @State private var showClearChatConfirm = false
    @State private var showVoiceSettings = false
    @State private var clearingChat = false
    private let accent = Color(hex: 0x356FF4)

    private var voices: [AIVoiceOption] { wallet.voices ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(Tr("小星设置"))
                    .font(pf(18, .semibold))
                    .foregroundColor(C.label)
                Spacer()
                Button(Tr("完成")) { dismiss() }
                    .font(pf(13.5, .medium))
                    .foregroundColor(accent)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .frame(height: 58)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    settingBlock(Tr("AI 名字")) {
                        HStack(spacing: 9) {
                            TextField(Tr("小星"), text: $name)
                                .font(pf(15))
                                .foregroundColor(C.label)
                                .padding(.horizontal, 12)
                                .frame(height: 44)
                                .background(C.fieldBg)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            Button {
                                saveName()
                            } label: {
                                Text(savingName ? Tr("保存中") : Tr("保存"))
                                    .font(pf(12.5, .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 66, height: 44)
                                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(savingName ? accent.opacity(0.4) : accent))
                            }
                            .buttonStyle(.plain)
                            .disabled(savingName)
                        }
                    }

                    settingBlock(Tr("习惯学习")) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(Tr("越用越懂你的表达和偏好"))
                                    .font(pf(13))
                                    .foregroundColor(C.label)
                                Text(Tr("已记录 ") + "\(learned)" + Tr(" 条偏好"))
                                    .font(pf(11))
                                    .foregroundColor(C.subLabel)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(get: { learning }, set: { value in
                                learning = value
                                setLearning(value)
                            }))
                            .labelsHidden()
                            .tint(accent)
                        }
                        Button {
                            showResetConfirm = true
                        } label: {
                            Text(Tr("清除学习记录"))
                                .font(pf(12))
                                .foregroundColor(C.red)
                        }
                        .buttonStyle(.plain)
                        .disabled(!learning || learned == 0)
                    }

                    settingBlock(Tr("音色")) {
                        if voices.isEmpty {
                            HStack(spacing: 9) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(C.subLabel)
                                Text(Tr("音色和语音通话需要标准包及以上"))
                                    .font(pf(12))
                                    .foregroundColor(C.subLabel)
                            }
                        } else {
                            ForEach(voices) { voice in
                                Button {
                                    chooseVoice(voice.id)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: selectedVoice == voice.id
                                              ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 17, weight: .medium))
                                            .foregroundColor(selectedVoice == voice.id ? accent : C.subLabel)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(voice.name)
                                                .font(pf(13.5, .medium))
                                                .foregroundColor(C.label)
                                            if let desc = voice.desc, !desc.isEmpty {
                                                Text(desc)
                                                    .font(pf(10.5))
                                                    .foregroundColor(C.subLabel)
                                            }
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    settingBlock(Tr("朗读")) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(Tr("自动朗读回复"))
                                    .font(pf(13.5, .medium))
                                    .foregroundColor(C.label)
                                Text(Tr("每条回答下方也可以手动点「朗读」"))
                                    .font(pf(10.5))
                                    .foregroundColor(C.subLabel)
                            }
                            Spacer(minLength: 4)
                            Toggle("", isOn: $autoRead)
                                .labelsHidden()
                                .tint(accent)
                        }
                        Button {
                            showVoiceSettings = true
                        } label: {
                            HStack {
                                Text(Tr("语音与语速"))
                                    .font(pf(13))
                                    .foregroundColor(accent)
                                Spacer()
                                Chevron(size: 8, line: 1.4, color: C.subLabel)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    settingBlock(Tr("对话记录")) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(Tr("清除 AI 工作台对话"))
                                    .font(pf(13.5, .medium))
                                    .foregroundColor(C.label)
                                Text(Tr("只清空你和小星的工作台聊天，不影响其他会话"))
                                    .font(pf(10.5))
                                    .foregroundColor(C.subLabel)
                            }
                            Spacer(minLength: 4)
                            Button {
                                showClearChatConfirm = true
                            } label: {
                                if clearingChat {
                                    ProgressView().controlSize(.small).tint(C.red)
                                } else {
                                    Text(Tr("清除"))
                                        .font(pf(12, .medium))
                                        .foregroundColor(C.red)
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(clearingChat)
                        }
                    }

                    if wallet.tier == "starter" {
                        Text(Tr("轻量包只支持简单文字对话。需要写作、文件、语音或代办时，可在充值页升级。"))
                            .font(pf(11.5))
                            .foregroundColor(C.subLabel)
                            .lineSpacing(3)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 32)
            }
        }
        .background(C.cardBg.ignoresSafeArea())
        .confirmationDialog(Tr("确定清除小星的学习记录吗？"),
                            isPresented: $showResetConfirm,
                            titleVisibility: .visible) {
            Button(Tr("清除"), role: .destructive) {
                resetLearning()
            }
            Button(Tr("取消"), role: .cancel) { }
        }
        .alert(Tr("确定清除 AI 工作台的对话吗？"), isPresented: $showClearChatConfirm) {
            Button(Tr("清除对话"), role: .destructive) { clearChat() }
            Button(Tr("取消"), role: .cancel) { }
        } message: {
            Text(Tr("只清空你和小星的工作台聊天，不影响其他会话。"))
        }
        .sheet(isPresented: $showVoiceSettings) {
            BotVoiceSettingsView()
        }
        .onAppear {
            let clean = wallet.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            name = clean.isEmpty ? "小星" : clean
            selectedVoice = wallet.voice ?? ""
            learning = wallet.learning ?? true
            learned = wallet.learned ?? 0
        }
    }

    private func settingBlock<Content: View>(_ title: String,
                                             @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(title)
                .font(pf(14, .semibold))
                .foregroundColor(C.label)
            content()
        }
        .padding(15)
        .background(C.pageBg)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
            .stroke(C.hairline, lineWidth: 0.7))
    }

    private func saveName() {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        savingName = true
        Task {
            do {
                let saved = try await API.shared.setAIName(clean)
                await MainActor.run {
                    name = saved.isEmpty ? "小星" : saved
                    savingName = false
                    app.show(Tr("名字已更新"))
                }
            } catch {
                await MainActor.run {
                    savingName = false
                    app.show((error as? LocalizedError)?.errorDescription ?? "名字保存失败")
                }
            }
        }
    }

    private func setLearning(_ enabled: Bool) {
        Task {
            do {
                let result = try await API.shared.setAILearning(enabled)
                await MainActor.run {
                    learning = result.learning
                    learned = result.learned
                    app.show(enabled ? Tr("已开启习惯学习") : Tr("已关闭习惯学习"))
                }
            } catch {
                await MainActor.run {
                    learning = !enabled
                    app.show((error as? LocalizedError)?.errorDescription ?? "设置失败")
                }
            }
        }
    }

    private func resetLearning() {
        Task {
            do {
                let result = try await API.shared.resetAILearning()
                await MainActor.run {
                    learning = result.learning
                    learned = result.learned
                    app.show(Tr("学习记录已清除"))
                }
            } catch {
                await MainActor.run {
                    app.show((error as? LocalizedError)?.errorDescription ?? "清除失败")
                }
            }
        }
    }

    private func clearChat() {
        guard !clearingChat else { return }
        clearingChat = true
        Task {
            let error = await onClearChat()
            await MainActor.run {
                clearingChat = false
                if let error = error {
                    app.show(error)
                } else {
                    app.show(Tr("工作台对话已清除"))
                    dismiss()
                }
            }
        }
    }

    private func chooseVoice(_ id: String) {
        guard selectedVoice != id else { return }
        let old = selectedVoice
        selectedVoice = id
        Task {
            do {
                selectedVoice = try await API.shared.setAIVoice(id)
                await MainActor.run { app.show(Tr("音色已切换")) }
            } catch {
                await MainActor.run {
                    selectedVoice = old
                    app.show((error as? LocalizedError)?.errorDescription ?? "音色切换失败")
                }
            }
        }
    }
}
private struct AIWorkspaceMark: View {
    var body: some View {
        Text("✦")
            .font(pfStyled(size: 13, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 32, height: 32)
            .background(
                LinearGradient(colors: [Color(hex: 0x4A8BFF),
                                        Color(hex: 0x7B61FF)],
                               startPoint: .topLeading,
                               endPoint: .bottomTrailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .shadow(color: Color(hex: 0x356FF4).opacity(0.16), radius: 8, y: 3)
    }
}

private struct AIChatSystemGlass: View {
    private let shape = RoundedRectangle(cornerRadius: 29, style: .continuous)

    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(.regular, in: shape)
                .shadow(color: .black.opacity(0.10), radius: 12, y: 6)
                .allowsHitTesting(false)
        } else {
            fallback
        }
        #else
        fallback
        #endif
    }

    private var fallback: some View {
        shape
            .fill(.ultraThinMaterial)
            .overlay(shape.stroke(Color.white.opacity(0.42), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.10), radius: 12, y: 6)
            .allowsHitTesting(false)
    }
}
