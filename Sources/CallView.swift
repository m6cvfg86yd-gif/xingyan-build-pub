import SwiftUI
import WebRTC

struct CallOverlay: View {
    @ObservedObject private var call = CallCenter.shared

    var body: some View {
        if call.phase != .idle {
            if call.minimized {

                CallMiniWindow()
                    .zIndex(999)
            } else {
                CallView()
                    .zIndex(999)
            }
        }
    }
}

struct CallDialogOverlay: View {
    @ObservedObject private var call = CallCenter.shared

    var body: some View {
        ZStack {
            if let d = call.dialog {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { call.dismissDialog() }

                VStack(spacing: 0) {
                    VStack(spacing: 6) {
                        Text(d.title)
                            .font(pf(16, .medium))
                            .foregroundColor(C.chatTimeInk)
                            .multilineTextAlignment(.center)
                        if !d.detail.isEmpty {
                            Text(d.detail)
                                .font(pf(13))
                                .foregroundColor(C.chatTimeInk.opacity(0.75))
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 22)
                    .padding(.bottom, 18)

                    Rectangle()
                        .fill(C.chatTimeInk.opacity(0.18))
                        .frame(height: 0.5)

                    Button {
                        call.dismissDialog()
                    } label: {
                        Text(d.okText)
                            .font(pf(16, .medium))
                            .foregroundColor(C.chatTimeInk)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                    }
                    .buttonStyle(.plain)
                }
                .frame(width: 268)
                .background(
                    RoundedRectangle(cornerRadius: max(12, L.o("chatTimeRadius", 4) + 8), style: .continuous)
                        .fill(C.chatTimeBg)
                )
                .transition(.scale(scale: 0.94).combined(with: .opacity))
                .zIndex(1000)
            }
        }
        .zIndex(1000)
        .animation(.easeOut(duration: 0.16), value: call.dialog)
    }
}

struct CallView: View {
    @ObservedObject private var call = CallCenter.shared

    @ObservedObject private var trtc = TRTCBridge.shared
    @EnvironmentObject var app: AppState

    private struct CallMsgBanner: Equatable {
        var chatId: String
        var name: String
        var text: String
    }
    @State private var msgBanner: CallMsgBanner? = nil
    @State private var bannerTask: Task<Void, Never>? = nil

    @State private var lastMsgSeen: [String: String] = [:]
    @State private var showInvite = false

    @State private var pipX: CGFloat? = nil
    @State private var pipY: CGFloat? = nil
    @State private var pipDrag: CGSize = .zero

    @State private var showReplies = false

    @State private var audioDevices: [CallAudioRoute] = []
    @State private var showAudioDevices = false
    @State private var showMicAlert = false

    private var blurRadius: CGFloat { UIConfig.num("callBackdropBlur", 60) }
    private var tint: CGFloat { UIConfig.num("callGlassTint", 0.45) }

    private var bgPath: String {
        let v = effectiveGlobalChatBackground(app.me?.chatBackground)
        if v.isEmpty || v == "auto" {
            let def = app.defaultChatBackground
            return (def == "auto") ? "" : def
        }
        return v
    }

    var body: some View {
        ZStack {
            backdrop

            if call.isGroupCall {

                if call.isVideo { groupVideoLayer } else { groupLayer }
            } else if call.isVideo && call.phase == .active {
                videoLayer
            } else {
                avatarLayer
            }

            VStack(spacing: 0) {
                topBar
                if let b = msgBanner { msgBannerView(b) }
                Spacer(minLength: 0)

                if micUnavailable { micBanner }
                bottomBar
            }
        }
        .sheet(isPresented: $showInvite) {
            inviteSheet
        }

        .confirmationDialog(Tr("拒绝并回复"), isPresented: $showReplies, titleVisibility: .visible) {
            Button(Tr("在忙，稍后联系你")) { call.reject(withReply: "在忙，稍后联系你") }
            Button(Tr("不方便接听，稍后回你")) { call.reject(withReply: "不方便接听，稍后回你") }
            Button(Tr("在开车，晚点回你")) { call.reject(withReply: "在开车，晚点回你") }
            Button(Tr("取消"), role: .cancel) { }
        }

        .confirmationDialog(Tr("声音输出") + "（" + call.currentAudioDeviceName + "）",
                            isPresented: $showAudioDevices, titleVisibility: .visible) {
            ForEach(audioDevices) { d in
                Button((d.name == call.currentAudioDeviceName ? "✓ " : "") + d.name) {
                    call.selectAudioDevice(d)
                }
            }
            Button(Tr("取消"), role: .cancel) { }
        }
        .alert(Tr("麦克风没有开启"), isPresented: $showMicAlert) {
            Button(Tr("去设置")) { call.openMicSettings() }
            Button(Tr("继续通话"), role: .cancel) { }
        } message: {
            Text(Tr("对方现在听不到你的声音。请在系统设置里允许麦克风，或检查是否被其他通话占用。"))
        }
        .onChange(of: micUnavailable) { blocked in
            if blocked, call.phase != .idle { showMicAlert = true }
        }

        .task(id: call.callId) {

            VideoBlur.shared.onAutoOff = { msg in app.show(msg) }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if Task.isCancelled { break }
                scanNewMessages()
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onAppear {

            DispatchQueue.main.async {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil, from: nil, for: nil
                )
                if micUnavailable, call.phase != .idle { showMicAlert = true }
            }
        }
    }

    private var micUnavailable: Bool {
        guard !call.muted else { return false }
        if call.micBlocked { return true }
        return call.usingTRTC && trtc.microphoneWarning
    }

    private func scanNewMessages() {
        switch call.phase {
        case .idle: return
        default: break
        }
        let mine = app.me?.id ?? ""
        for c in app.chats {
            guard let lm = c.lastMessage, let mid = lm.id, !mid.isEmpty else { continue }
            let sender = lm.senderId ?? ""
            if sender == mine || sender.isEmpty { lastMsgSeen[c.id] = mid; continue }
            let old = lastMsgSeen[c.id]
            lastMsgSeen[c.id] = mid
            guard let old = old, old != mid else { continue }
            if c.muted == true { continue }
            let t = (lm.preview ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            showBanner(chatId: c.id, name: c.title ?? Tr("新消息"),
                       text: t.isEmpty ? Tr("[新消息]") : t)
            return
        }
    }

    private func showBanner(chatId: String, name: String, text: String) {
        withAnimation(.easeOut(duration: 0.18)) {
            msgBanner = CallMsgBanner(chatId: chatId, name: name, text: String(text.prefix(30)))
        }
        bannerTask?.cancel()
        bannerTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled { withAnimation(.easeOut(duration: 0.18)) { msgBanner = nil } }
        }
    }

    private func msgBannerView(_ b: CallMsgBanner) -> some View {
        Button {
            msgBanner = nil
            call.minimize()
            if let c = app.chats.first(where: { $0.id == b.chatId }) { app.openChatViaList(c) }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "message.fill").font(.system(size: 12, weight: .semibold))
                Text(b.name).font(pf(13, .medium)).lineLimit(1)
                Text(b.text).font(pf(13)).lineLimit(1).foregroundColor(.white.opacity(0.82))
                Spacer(minLength: 0)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Capsule().fill(Color.black.opacity(0.55)))
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var backdrop: some View {
        ZStack {
            Color(red: 0.10, green: 0.11, blue: 0.10)

            if !call.peerAvatar.isEmpty {
                RemoteImage(path: call.peerAvatar)
                    .blur(radius: blurRadius)
                    .scaleEffect(1.35)
            } else if !bgPath.isEmpty {
                RemoteImage(path: bgPath)
                    .blur(radius: blurRadius)
                    .scaleEffect(1.25)
            }
            Color.black.opacity(tint)
        }
        .ignoresSafeArea()
    }

    private var avatarLayer: some View {
        VStack(spacing: 0) {

            Spacer().frame(height: max(30, 132 - L.safeTop))
            Avatar(path: call.peerAvatar, size: 70, radius: 10)
            Text(call.peerName)
                .font(pfExact(17, .medium))
                .foregroundColor(.white)
                .padding(.top, 12)
            Text(statusText)
                .font(pfExact(13.5))
                .foregroundColor(.white.opacity(0.7))
                .padding(.top, 5)
                .opacity(call.phase == .outgoing ? 0 : 1)
            if call.phase == .outgoing {

                if let err = call.errorText, !err.isEmpty {
                    Text(err)
                        .font(pfExact(15, .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.top, 6)
                } else {

                    MarqueeText(text: "正在等待对方接受邀请…")
                        .padding(.top, 6)
                }
            }
            if !hintText.isEmpty {
                Text(hintText)
                    .font(pfExact(15))
                    .foregroundColor(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.top, 142)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var videoLayer: some View {
        ZStack {

            if call.usingTRTC {
                TRTCVideoView(view: trtc.remoteView)
                    .ignoresSafeArea()
            } else {
                VideoSurface(track: call.remoteVideo)
                    .ignoresSafeArea()
            }
            if call.usingTRTC ? (trtc.remoteView == nil) : (call.remoteVideo == nil) {
                VStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text(Tr("正在连接画面…"))
                        .font(pfExact(14))
                        .foregroundColor(.white.opacity(0.75))
                }
            }
            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(call.peerName)
                            .font(pfExact(17, .medium))
                            .foregroundColor(.white)
                        Text(statusText)
                            .font(pfExact(13))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                Spacer()

                GeometryReader { geo in
                    let w: CGFloat = 104
                    let h: CGFloat = 148
                    let maxX = max(8, geo.size.width - w - 12)
                    let minY: CGFloat = 74
                    let maxY = max(minY, geo.size.height - h - 150)
                    let homeX = geo.size.width - w - 16
                    let homeY = geo.size.height - h - 150
                    let x = min(max((pipX ?? homeX) + pipDrag.width, 8), maxX)
                    let y = min(max((pipY ?? homeY) + pipDrag.height, minY), maxY)
                    pipBody(w: w, h: h)
                        .position(x: x + w / 2, y: y + h / 2)
                        .gesture(
                            DragGesture(minimumDistance: 5)
                                .onChanged { v in pipDrag = v.translation }
                                .onEnded { v in
                                    let nx = (pipX ?? homeX) + v.translation.width
                                    let ny = (pipY ?? homeY) + v.translation.height

                                    pipX = nx + w / 2 < geo.size.width / 2 ? 8 : maxX
                                    pipY = min(max(ny, minY), maxY)
                                    pipDrag = .zero
                                }
                        )
                }
            }

            VStack {
                HStack {
                    Spacer(minLength: 0)
                    HStack(spacing: 8) {
                        topPill(symbol: "arrow.triangle.2.circlepath.camera",
                                on: false,
                                hint: "翻转") { call.flipCamera() }
                        topPill(symbol: call.cameraOff ? "video.slash.fill" : "video.fill",
                                on: call.cameraOff,
                                hint: call.cameraOff ? "摄像头已关" : "摄像头已开") { call.toggleCamera() }
                    }
                    .padding(.trailing, 14)
                }
                .padding(.top, L.navH + 52)
                Spacer(minLength: 0)
            }
        }
    }

    private func pipBody(w: CGFloat, h: CGFloat) -> some View {
        Group {
            if call.usingTRTC {
                TRTCVideoView(view: trtc.localView)
            } else {
                VideoSurface(track: call.localVideo)
            }
        }
        .frame(width: w, height: h)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(Color.white.opacity(0.22), lineWidth: 1))

        .overlay {
            if call.cameraOff {
                ZStack {
                    Color.black.opacity(0.72)
                    Image(systemName: "video.slash.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.9))
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { call.flipCamera() }
    }

    private func topPill(symbol: String, on: Bool, hint: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(on ? .black : .white)
                .frame(width: 30, height: 52)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(on ? Color.white : Color.black.opacity(0.28)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(hint))
    }

    private var groupVideoLayer: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                    GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(call.roster.filter { $0.userId != app.me?.id }) { m in
                        VStack(spacing: 4) {
                            TRTCVideoView(view: TRTCBridge.shared.meetingView(for: m.userId))
                                .frame(height: 152)
                                .background(Color.black)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            HStack(spacing: 4) {
                                if m.muted {
                                    Image(systemName: "mic.slash.fill")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                Text(m.name.isEmpty ? Tr("成员") : m.name)
                                    .font(pf(12.5))
                                    .foregroundColor(.white.opacity(0.88))
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, 140)
            }

            TRTCVideoView(view: TRTCBridge.shared.localView)
                .frame(width: 96, height: 130)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1))
                .padding(.trailing, 14)
                .padding(.bottom, 96)
        }
    }

    private var groupLayer: some View {
        VStack(spacing: 14) {
            Text(call.groupTitle.isEmpty ? Tr("群语音通话") : call.groupTitle)
                .font(pf(17, .semibold))
                .foregroundColor(.white.opacity(0.92))
                .lineLimit(1)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3),
                      spacing: 16) {
                ForEach(call.roster) { m in
                    VStack(spacing: 6) {
                        ZStack {
                            Avatar(path: m.avatar, size: 62, radius: 12)

                            if speakOn(m) {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(C.green, lineWidth: 2.5)
                                    .frame(width: 68, height: 68)
                                    .shadow(color: C.green.opacity(0.65), radius: 8)
                            }
                            if m.muted {
                                Image(systemName: "mic.slash.fill")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(4)
                                    .background(Circle().fill(Color.black.opacity(0.55)))
                                    .offset(x: 23, y: 23)
                            }
                        }
                        Text(m.name.isEmpty ? Tr("成员") : m.name)
                            .font(pf(12.5))
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 34)
            Text("\(call.roster.count) " + Tr("人在通话中"))
                .font(pf(12.5))
                .foregroundColor(.white.opacity(0.6))
        }
    }

    private func speakOn(_ m: GroupCallMember) -> Bool {
        let lv = call.speakerLevels[m.userId] ?? 0
        guard lv > 0.10 else { return false }
        let top = call.speakerLevels.values.max() ?? 0
        return lv >= top
    }

    private var statusText: String {
        if call.isGroupCall {
            switch call.phase {
            case .incoming:   return "邀请你加入群语音通话…"
            case .outgoing:   return "正在邀请群成员…"
            case .connecting: return "正在接通…"
            case .active:     return timeText
            case .idle:       return ""
            }
        }
        switch call.phase {
        case .incoming:   return call.isVideo ? "邀请你视频通话…" : "邀请你语音通话…"
        case .outgoing:   return "正在等待对方接受邀请…"
        case .connecting: return "正在接通…"
        case .active:     return timeText
        case .idle:       return ""
        }
    }

    private var hintText: String {
        let t = call.tip
        if call.phase == .idle { return "" }
        if t == "未接听" || t == "对方已拒绝" || t == "对方不在线" { return t + "，建议稍后尝试" }
        if t.contains("失败") || t.contains("断开") { return t }

        if call.weakNet { return "网络不太稳定，正在重连…" }

        if call.peerCameraOff { return "对方已关闭摄像头" }
        if call.peerMuted { return "对方已静音" }
        return ""
    }

    private var timeText: String {
        String(format: "%02d:%02d", call.seconds / 60, call.seconds % 60)
    }

    private var bottomBar: some View {
        Group {
            if call.phase == .incoming {
                VStack(spacing: 16) {
                    HStack(spacing: 51) {
                        roundKey(label: "拒绝", bg: Color(hex: 0xFA5151)) { call.reject() }
                        roundKey(label: "接听", bg: Color(hex: 0x19A47A), ink: .white,
                                 action: {
                                     if call.isGroupCall { call.acceptGroupCall() } else { call.accept() }
                                 }) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 27, weight: .medium))
                        }
                    }

                    Button { showReplies = true } label: {
                        Text(Tr("拒绝并回复"))
                            .font(pf(14))
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 16).frame(height: 34)
                            .background(Capsule().fill(Color.white.opacity(0.16)))
                    }
                    .buttonStyle(.plain)

                    if call.isVideo && !call.isGroupCall {
                        Button { call.accept(asAudio: true) } label: {
                            Text(Tr("语音接听"))
                                .font(pf(15, .medium))
                                .foregroundColor(.white.opacity(0.92))
                                .padding(.horizontal, 18)
                                .frame(height: 34)
                                .background(Capsule().fill(Color.white.opacity(0.16)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 54)
            } else if call.isVideo {

                VStack(spacing: 16) {
                    HStack(spacing: 0) {
                        if call.phase == .active {
                            micKey
                            Spacer(minLength: 0)
                            speakerKey
                        } else {
                            HStack(spacing: 0) {
                                micKey
                                Spacer(minLength: 0)
                                flipKey
                                Spacer(minLength: 0)
                                cameraKey
                            }
                        }
                    }
                    .padding(.horizontal, call.phase == .active ? 48 : 16)
                    hangupKey
                    if call.phase == .active && !call.isGroupCall {
                        Button { call.switchVideo() } label: { switchLabel }
                            .buttonStyle(.plain)
                            .padding(.top, 10)
                    }

                    if call.phase == .active {
                        Button { call.toggleBlurBackground() } label: {
                            Text(call.blurBackground ? Tr("关闭背景模糊") : Tr("模糊背景"))
                                .font(pf(14))
                                .foregroundColor(.white.opacity(0.9))
                                .padding(.horizontal, 16)
                                .frame(height: 32)
                                .background(Capsule().fill(Color.white.opacity(call.blurBackground ? 0.34 : 0.16)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 40)
            } else {
                if call.phase == .active {

                    VStack(spacing: 14) {
                        HStack(spacing: 51) {
                            micKey
                            hangupKey
                            speakerKey
                        }

                        if !call.isGroupCall {
                            Button { call.switchVideo() } label: { switchLabel }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 54)
                } else {

                    HStack(spacing: 72) {
                        micKey
                        hangupKey
                    }
                    .padding(.bottom, 54)
                }
            }
        }
    }

    private var switchLabel: some View {
        Text(call.isVideo ? Tr("切换为语音通话") : Tr("切换为视频通话"))
            .font(pf(14))
            .foregroundColor(.white.opacity(0.9))
            .padding(.horizontal, 16)
            .frame(height: 32)
            .background(Capsule().fill(Color.white.opacity(0.16)))
    }

    private var micKey: some View {
        roundKey(key: call.muted ? "ui.callMicOff" : "ui.callMic",
                 symbol: call.muted ? "mic.slash.fill" : "mic.fill",
                 builtin: call.muted ? I.callMicOff : I.callMic,
                 label: call.muted ? "麦克风已关" : "麦克风已开",
                 engaged: call.muted) { call.toggleMute() }
    }

    private var micBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "mic.slash.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
            Text(Tr("麦克风没开，对方听不到你"))
                .font(pfExact(13.5))
                .foregroundColor(.white)
                .lineLimit(2)
            Spacer(minLength: 6)
            Button { call.retryMic() } label: {
                Text(Tr("重试"))
                    .font(pfExact(13.5, .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .overlay(Capsule().stroke(Color.white.opacity(0.75), lineWidth: 1))
            }
            .buttonStyle(.plain)
            Button { call.openMicSettings() } label: {
                Text(Tr("去开启"))
                    .font(pfExact(13.5, .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(hex: 0xE08A10).opacity(0.95)))
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var speakerKey: some View {
        roundKey(key: call.speakerOn ? "ui.callSpeaker" : "ui.callSpeakerOff",
                 symbol: call.speakerOn ? "speaker.wave.2.fill" : "speaker.slash.fill",
                 builtin: call.speakerOn ? I.callSpeaker : I.callSpeakerOff,
                 label: call.speakerOn ? "扬声器已开" : "扬声器已关",
                 engaged: call.speakerOn) { call.toggleSpeaker() }

            .onLongPressGesture(minimumDuration: 0.35) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                audioDevices = call.audioDevices()
                showAudioDevices = true
            }
    }

    private var hangupKey: some View {
        roundKey(label: call.phase == .active ? "挂断" : "取消",
                 bg: Color(hex: 0xFA5151)) { call.hangup() }
    }

    private var flipKey: some View {
        roundKey(label: "翻转",
                 bg: Color.white.opacity(0.18),
                 ink: .white,
                 action: { call.flipCamera() }) {
            Image(systemName: "arrow.triangle.2.circlepath.camera")
                .font(.system(size: 26, weight: .medium))
        }
    }

    private var cameraKey: some View {
        roundKey(label: call.cameraOff ? "摄像头已关" : "摄像头已开",
                 bg: call.cameraOff ? Color.white : Color.white.opacity(0.18),
                 ink: call.cameraOff ? .black : .white,
                 action: { call.toggleCamera() }) {
            Image(systemName: call.cameraOff ? "video.slash.fill" : "video.fill")
                .font(.system(size: 26, weight: .medium))
        }
    }

    private func roundKey(key: String, symbol: String, builtin: String,
                          label: String, engaged: Bool,
                          action: @escaping () -> Void) -> some View {
        let ink: Color = engaged ? .black : .white
        return
        roundKey(label: label,
                 bg: engaged ? Color.white : Color.white.opacity(0.18),
                 ink: ink,
                 action: action) {
            CallIcon(key: key, symbol: symbol, builtin: builtin, size: 30, color: ink)
        }
    }

    private func roundKey(label: String, bg: Color,
                          action: @escaping () -> Void) -> some View {
        roundKey(label: label, bg: bg, ink: .white, action: action) {
            CallIcon(key: "ui.callHangup", symbol: "phone.down.fill", builtin: I.callHangup, size: 72)
        }
    }

    private func roundKey<Icon: View>(label: String, bg: Color, ink: Color,
                                      action: @escaping () -> Void,
                                      @ViewBuilder icon: () -> Icon) -> some View {
        VStack(spacing: 14) {
            Button(action: action) {
                icon()
                    .foregroundColor(ink)
                    .frame(width: 72, height: 72)
                    .background(Circle().fill(bg))
            }
            .buttonStyle(.plain)
            Text(label)
                .font(pfExact(14))
                .foregroundColor(.white.opacity(0.92))
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                call.minimize()
            } label: {
                CallIcon(key: "ui.callMinimize", symbol: "rectangle.inset.bottomright.filled",
                         builtin: I.callMinimize, size: 20)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 16)

            Spacer()

            Button {
                showInvite = true
            } label: {
                CallIcon(key: "ui.callAdd", symbol: "plus", builtin: I.callAdd, size: 17)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
        }
        .padding(.top, 19)
    }

    private var miniBarOld: some View {
        HStack(spacing: 8) {
            Circle().fill(C.green).frame(width: 8, height: 8)
            Text(call.phase == .active ? "通话中 \(timeText)" : call.tip)
                .font(pfExact(14))
                .foregroundColor(.white)
            Spacer(minLength: 0)
            Button {
                call.restore()
            } label: {
                Text(Tr("回到通话")).font(pfExact(14)).foregroundColor(Color(hex: 0x19A47A))
            }
            .buttonStyle(.plain)
            Button {
                call.hangup()
            } label: {
                CallIcon(key: "ui.callHangup", symbol: "phone.down.fill", builtin: I.callHangup, size: 24)
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(Capsule().fill(Color.black.opacity(0.72)))
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @State private var groupMembers: [User] = []

    private var inviteList: [User] {
        if call.isGroupCall && !call.groupChatId.isEmpty {
            let mine = app.me?.id ?? ""
            return groupMembers.filter { u in
                u.id != mine && !call.roster.contains(where: { $0.userId == u.id })
            }
        }
        return app.contacts
    }

    private var inviteSheet: some View {
        NavigationStack {
            List {
                Section {
                    if inviteList.isEmpty {
                        Text(call.isGroupCall
                             ? Tr("这个群里没有可以再拉的人了（要么已经在通话里，要么只有你自己）。想拉别人先把人加进群。")
                             : Tr("还没有好友可以邀请"))
                            .font(pf(13.5)).foregroundColor(C.subLabel)
                    }
                    ForEach(inviteList) { u in
                        Button {
                            showInvite = false
                            let name = u.nickname ?? u.username ?? "好友"
                            Task {

                                if call.isGroupCall {
                                    call.inviteToCall(u.id)
                                    app.show(Tr("已邀请 ") + name + Tr(" 加入通话"))
                                } else {
                                    let msg = await call.invite(userId: u.id, name: name)
                                    app.show(msg)
                                }
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Avatar(path: u.avatar ?? "", size: 36, radius: 6)
                                Text(u.nickname ?? u.username ?? "好友").foregroundColor(C.label)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(call.groupCallFull
                         ? Tr("通话人数已满（最多 9 人）")
                         : Tr("邀请好友加入通话") + "（" + String(call.roster.count) + "/9）")
                } footer: {
                    Text(call.isGroupCall
                         ? Tr("群通话只能邀请**本群成员**（对方会看到群通话来电，接听即入会）。不是群成员的，先拉进群再来邀请。")
                         : Tr("对方会收到一条邀请消息，点那条消息就能回拨给你。"))
                }
            }
            .navigationTitle(Tr("添加通话"))
            .navigationBarTitleDisplayMode(.inline)
        }

        .task {
            guard call.isGroupCall, !call.groupChatId.isEmpty, groupMembers.isEmpty else { return }
            if let r = try? await API.shared.chatMembers(chatId: call.groupChatId) {
                groupMembers = r.members
            }
        }
    }
}

struct CallMiniWindow: View {
    @ObservedObject private var call = CallCenter.shared
    @ObservedObject private var trtc = TRTCBridge.shared

    @State private var miniX: CGFloat? = nil
    @State private var miniY: CGFloat? = nil
    @State private var dragging: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let w: CGFloat = call.isVideo ? 108 : 146
            let h: CGFloat = call.isVideo ? 144 : 48

            let topSafe = max(geo.safeAreaInsets.top, 24)
            let minY = topSafe - 6
            let maxX = max(8, geo.size.width - w - 8)
            let maxY = max(minY, geo.size.height - h - 90)
            let homeX = geo.size.width - w - 10
            let homeY = topSafe + 4
            let x = min(max((miniX ?? homeX) + dragging.width, 8), maxX)
            let y = min(max((miniY ?? homeY) + dragging.height, minY), maxY)
            windowBody(w: w, h: h)
                .position(x: x + w / 2, y: y + h / 2)
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { v in dragging = v.translation }
                        .onEnded { v in
                            let nx = (miniX ?? homeX) + v.translation.width
                            let ny = (miniY ?? homeY) + v.translation.height

                            miniX = nx + w / 2 < geo.size.width / 2 ? 8 : maxX
                            miniY = min(max(ny, minY), maxY)
                            dragging = .zero
                        }
                )
        }
    }

    private func windowBody(w: CGFloat, h: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if call.isVideo {
                    ZStack {
                        if call.usingTRTC {
                            TRTCVideoView(view: trtc.remoteView)
                        } else {
                            VideoSurface(track: call.remoteVideo)
                        }
                        if call.usingTRTC ? (trtc.remoteView == nil) : (call.remoteVideo == nil) {
                            Avatar(path: call.peerAvatar, size: 44, radius: 8)
                        }
                    }
                } else {
                    HStack(spacing: 9) {
                        Avatar(path: call.peerAvatar, size: 28, radius: 14)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(call.peerName)
                                .font(pfExact(13, .medium))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text(call.phase == .active ? miniTimeText : (call.tip.isEmpty ? "通话中" : call.tip))
                                .font(pfExact(11))
                                .foregroundColor(.white.opacity(0.72))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .background(Color(hex: 0x19A47A))
                }
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.black.opacity(0.18), lineWidth: 0.5))
            .contentShape(Rectangle())
            .onTapGesture { call.restore() }

            Button {
                call.hangup()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.black.opacity(0.55)))
            }
            .buttonStyle(.plain)
            .padding(5)
        }
        .shadow(color: .black.opacity(0.28), radius: 8, y: 3)
    }

    private var miniTimeText: String {
        let s = call.seconds
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%02d:%02d", m, sec)
    }
}

struct HangUpIcon: View {
    var width: CGFloat = 66
    var body: some View {
        let h = width * 0.25
        let s = width / 66
        return Path { p in
            p.move(to: CGPoint(x: 3 * s, y: 5.4 * s))
            p.addQuadCurve(to: CGPoint(x: 63 * s, y: 5.4 * s),
                           control: CGPoint(x: 33 * s, y: 0.4 * s))
            p.addLine(to: CGPoint(x: 63 * s, y: 9.2 * s))
            p.addQuadCurve(to: CGPoint(x: 43 * s, y: 13.2 * s),
                           control: CGPoint(x: 53 * s, y: 13.4 * s))
            p.addLine(to: CGPoint(x: 23 * s, y: 13.2 * s))
            p.addQuadCurve(to: CGPoint(x: 3 * s, y: 9.2 * s),
                           control: CGPoint(x: 13 * s, y: 13.4 * s))
            p.closeSubpath()
        }
        .fill(Color.white)
        .frame(width: width, height: max(8, h))
    }
}

struct PipIcon: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let line = max(1.4, w * 0.09)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: w * 0.16, style: .continuous)
                    .stroke(Color.white, lineWidth: line)
                    .frame(width: w * 0.86, height: h * 0.86)
                RoundedRectangle(cornerRadius: w * 0.12, style: .continuous)
                    .fill(Color.black.opacity(0.35))
                    .overlay(RoundedRectangle(cornerRadius: w * 0.12, style: .continuous)
                        .stroke(Color.white, lineWidth: line))
                    .frame(width: w * 0.52, height: h * 0.40)
                    .offset(x: w * 0.48, y: h * 0.60)
            }
        }
    }
}

struct PlusIcon: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            Path { p in
                p.move(to: CGPoint(x: 0, y: w / 2))
                p.addLine(to: CGPoint(x: w, y: w / 2))
                p.move(to: CGPoint(x: w / 2, y: 0))
                p.addLine(to: CGPoint(x: w / 2, y: w))
            }
            .stroke(Color.white, style: StrokeStyle(lineWidth: max(1.6, w * 0.11), lineCap: .round))
        }
    }
}

struct CallIcon: View {
    let key: String
    var symbol: String = "circle"
    var builtin: String? = nil
    var size: CGFloat = 24
    var color: Color = .white

    var body: some View {
        if let v = IconOverrides.custom(key), !v.isEmpty {
            if v.hasPrefix("<svg") {
                SVGIcon(markup: v, size: size, color: color)
            } else if v.hasPrefix("http") || v.hasPrefix("/uploads") || v.hasPrefix("data:") {
                RemoteImage(path: v).frame(width: size, height: size)
            } else {
                Text(v)
                    .font(.system(size: size * 0.9))
                    .foregroundColor(color)
                    .frame(width: size, height: size)
            }
        } else if let b = builtin {
            SVGIcon(markup: b, size: size, color: color)
        } else {
            Image(systemName: symbol)
                .font(.system(size: size * 0.9, weight: .medium))
                .foregroundColor(color)
                .frame(width: size, height: size)
        }
    }
}

struct MarqueeText: View {
    let text: String
    var size: CGFloat = 15
    var duration: Double = 7
    @State private var x: CGFloat = 0
    @State private var ready = false

    var body: some View {
        GeometryReader { geo in
            Text(text)
                .font(pfExact(size))
                .foregroundColor(.white.opacity(0.72))
                .fixedSize()
                .offset(x: x)
                .onAppear {
                    guard !ready else { return }
                    ready = true
                    x = geo.size.width
                    withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                        x = -geo.size.width
                    }
                }
        }
        .frame(height: size + 6)
    }
}

struct VideoSurface: UIViewRepresentable {
    let track: RTCVideoTrack?

    final class Holder {
        var attached: RTCVideoTrack?
    }

    func makeCoordinator() -> Holder { Holder() }

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let v = RTCMTLVideoView()
        v.videoContentMode = .scaleAspectFill
        v.clipsToBounds = true
        v.backgroundColor = .black
        return v
    }

    func updateUIView(_ view: RTCMTLVideoView, context: Context) {
        if context.coordinator.attached === track { return }
        context.coordinator.attached?.remove(view)
        context.coordinator.attached = track
        track?.add(view)
    }

    static func dismantleUIView(_ view: RTCMTLVideoView, coordinator: Holder) {
        coordinator.attached?.remove(view)
    }
}
