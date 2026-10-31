import Foundation
import SwiftUI
import AVFoundation
import AudioToolbox
import UIKit
import Combine
import WebRTC
import Network

struct GroupCallMember: Identifiable, Equatable {
    var userId: String
    var name: String
    var avatar: String
    var muted: Bool
    var id: String { userId }
}

struct CallLiveDiag: Equatable {
    var channel = "-"
    var ice = "-"
    var relayUsed = false
    var audioEnabled = false
    var micPermission = "-"
    var audioSession = "-"
    var audioRoute = "-"
    var bytesSent = 0
    var bytesReceived = 0
    var packetsLost = 0
    var jitter = 0.0
    var trtcPeerInRoom = false
    var wsOK = false
    var updatedAt = ""
}

struct CallAudioRoute: Identifiable, Equatable {
    let id: String
    let name: String
    let kind: String

    var icon: String {
        switch kind {
        case "speaker": return "speaker.wave.2.fill"
        case "bluetooth": return "wave.3.right.circle"
        case "headset": return "headphones"
        default: return "phone.fill"
        }
    }
}

@MainActor
final class CallCenter: NSObject, ObservableObject {
    static let shared = CallCenter()

    enum Phase: Equatable {
        case idle, outgoing, incoming, connecting, active
        var isBusy: Bool { self != .idle }
    }

    @Published private(set) var phase: Phase = .idle {
        didSet {

            if phase != oldValue {
                if phase == .active { startLiveDiag() }
                else if phase == .idle { stopLiveDiag() }
            }
        }
    }
    @Published private(set) var peerName = ""
    @Published private(set) var peerAvatar = ""
    @Published private(set) var isVideo = false
    @Published private(set) var muted = false
    @Published private(set) var cameraOff = false
    @Published private(set) var screenSharing = false

    @Published private(set) var speakerOn = false

    @Published private(set) var proximityNear = false

    @Published private(set) var blurBackground = false
    @Published private(set) var seconds = 0
    @Published private(set) var tip = ""

    struct Dialog: Equatable {
        var title = ""
        var detail = ""
        var okText = "确定"
        var auto: Double = 0
    }
    @Published var dialog: Dialog? = nil
    private var dialogTask: Task<Void, Never>?

    private var proximityObserver: NSObjectProtocol?

    private var failTask: Task<Void, Never>?

    private var diag: [String] = []

    @Published private(set) var diagLive = CallLiveDiag()
    private var diagLiveTimer: Timer?

    func startLiveDiag() {
        diagLiveTimer?.invalidate()
        diagLiveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshLiveDiag()
        }
        refreshLiveDiag()
    }
    func stopLiveDiag() {
        diagLiveTimer?.invalidate()
        diagLiveTimer = nil
    }

    private func refreshLiveDiag() {
        var d = CallLiveDiag()
        d.channel = usingTRTC ? "TRTC（腾讯）" : (serverAudioOn ? "服务器转发" : "WebRTC")
        d.ice = pc.map { String(describing: $0.iceConnectionState) } ?? "-"
        d.audioEnabled = audioTrack?.isEnabled ?? false
        d.trtcPeerInRoom = trtcPeerInRoom
        d.wsOK = Realtime.shared.connected
        let s = AVAudioSession.sharedInstance()
        switch s.recordPermission {
        case .granted: d.micPermission = "granted"
        case .denied: d.micPermission = "denied"
        default: d.micPermission = "undetermined"
        }
        d.audioSession = s.category.rawValue + " / " + s.mode.rawValue
        d.audioRoute = (s.currentRoute.outputs.first?.portType.rawValue) ?? "-"
        let fmt = DateFormatter(); fmt.dateFormat = "HH:mm:ss"
        d.updatedAt = fmt.string(from: Date())
        self.diagLive = d
        guard let conn = pc else { return }
        conn.statistics { report in
            var nd = d
            for (_, st) in report.statistics {
                if st.type == "outbound-rtp" {
                    if let v = st.values["bytesSent"] as? NSNumber { nd.bytesSent = v.intValue }
                }
                if st.type == "inbound-rtp" {
                    if let v = st.values["bytesReceived"] as? NSNumber { nd.bytesReceived = v.intValue }
                    if let v = st.values["packetsLost"] as? NSNumber { nd.packetsLost = v.intValue }
                    if let v = st.values["jitter"] as? NSNumber { nd.jitter = v.doubleValue }
                }
                if st.type == "candidate-pair", (st.values["nominated"] as? NSNumber)?.boolValue == true {
                    if let lid = st.values["localCandidateId"] as? String,
                       let lc = report.statistics[lid],
                       let ct = lc.values["candidateType"] as? String, ct == "relay" {
                        nd.relayUsed = true
                    }
                }
            }
            DispatchQueue.main.async { self.diagLive = nd }

            if self.diag.count < 20, Int(Date().timeIntervalSince1970) % 5 == 0 {
                self.diag.append("[live] " + nd.channel
                    + " ice=" + nd.ice + " relay=" + (nd.relayUsed ? "Y" : "N")
                    + " mic=" + nd.micPermission + " route=" + nd.audioRoute
                    + " audioOn=" + (nd.audioEnabled ? "Y" : "N")
                    + " tx=" + String(nd.bytesSent) + " rx=" + String(nd.bytesReceived)
                    + " lost=" + String(nd.packetsLost) + " jitter=" + String(format: "%.3f", nd.jitter))
            }
        }
    }

    private var serverAudioOn = false

    @Published private(set) var usingTRTC = false

    private var trtcJoined = false

    var trtcRemoteView: UIView? { TRTCBridge.shared.remoteView }
    var trtcLocalView: UIView? { TRTCBridge.shared.localView }

    var trtcPeerInRoom: Bool { TRTCBridge.shared.peerInRoom }

    func dismissDialog() {
        dialogTask?.cancel()
        dialogTask = nil
        dialog = nil
        rosterHydrationTask?.cancel()
        rosterHydrationTask = nil
    }

    func showDialog(_ title: String, detail: String = "", auto: Double = 0) {
        guard !title.isEmpty else { return }
        dialogTask?.cancel()
        dialog = Dialog(title: title, detail: detail, auto: auto)
        guard auto > 0 else { return }
        dialogTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(auto * 1_000_000_000))
            guard let self = self, !Task.isCancelled else { return }
            self.dialog = nil
        }
    }

    @Published private(set) var remoteVideo: RTCVideoTrack?
    @Published private(set) var localVideo: RTCVideoTrack?

    @Published var errorText: String?

    @Published var minimized = false

    @Published var relayOK = false

    @Published private(set) var micBlocked = false

    @Published private(set) var peerMuted = false
    @Published private(set) var peerCameraOff = false

    @Published private(set) var weakNet = false

    @Published private(set) var isGroupCall = false
    @Published private(set) var roomId = ""
    @Published private(set) var groupChatId = ""
    @Published private(set) var groupTitle = ""
    @Published private(set) var roster: [GroupCallMember] = []

    private var factory: RTCPeerConnectionFactory?
    private var pc: RTCPeerConnection?

    private(set) var callId = ""
    private var accountToken = ""
    private var callOwnerId = ""

    private(set) var peerId = ""
    private var iAmCaller = false
    private var remoteOfferSDP: String?
    private var pendingIce: [RTCIceCandidate] = []

    private var netWaiters: [String: CheckedContinuation<Bool, Never>] = [:]

    private var pendingPushCallId = ""
    private var pendingPushAnswer = false
    private var pendingPushTask: Task<Void, Never>?
    private var rosterHydrationTask: Task<Void, Never>?

    private var blurDelegate: BlurCapturer?

    func askSameNetwork(peerUserId: String) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            netWaiters[peerUserId] = cont
            Realtime.shared.sendJSON(["type": "call", "action": "net", "peerId": peerUserId])
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                if let c = netWaiters.removeValue(forKey: peerUserId) {
                    c.resume(returning: false)
                }
            }
        }
    }
    private var audioTrack: RTCAudioTrack?
    private var localVideoTrack: RTCVideoTrack?
    private var videoSource: RTCVideoSource?
    private var capturer: RTCCameraVideoCapturer?
    private let screenCapturer = ScreenShareCapturer()
    private var screenSharePending = false
    private var ticker: Timer?

    private var micDownTicks = 0

    private var ringTimer: Timer?

    private var connectTimer: Timer?
    private var inviteRetryTask: Task<Void, Never>?
    private var lastOutgoingInvite: [String: Any]?
    private var inviteAcked = false
    private var pendingGroupInviteUserId = ""
    private var sub: AnyCancellable?

    private var iceServers: [RTCIceServer] = [
        RTCIceServer(urlStrings: ["stun:stun.miwifi.com:3478", "stun:stun.cloudflare.com:3478"]),
        RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"]),
        RTCIceServer(urlStrings: ["turn:openrelay.metered.ca:80", "turn:openrelay.metered.ca:443"],
                     username: "openrelayproject", credential: "openrelayproject")
    ]

    private override init() {
        super.init()

        sub = Realtime.shared.$event
            .receive(on: RunLoop.main)
            .sink { [weak self] ev in

                guard ev.type == "call" || ev.type == "call-error" || ev.type == "ready" else { return }
                self?.handle(ev)
            }
        Task { await loadIce() }
        startPathMonitor()

        _ = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                                   object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.phase != .idle else { return }
                let trtcWarning = self.usingTRTC && TRTCBridge.shared.microphoneWarning
                guard self.micBlocked || trtcWarning else { return }
                if await Permission.ask(.audio) {
                    self.micBlocked = false
                    self.errorText = nil
                    if self.usingTRTC {
                        TRTCBridge.shared.retryMicrophone()
                    } else {
                        CallAudioPipe.shared.repairAudioNow()
                    }
                    self.note("麦克风权限已开，重新抢麦")
                }
            }
        }
    }

    func openMicSettings() {
        guard let u = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(u)
    }

    func retryMic() {
        micBlocked = false
        errorText = nil
        if usingTRTC {
            TRTCBridge.shared.retryMicrophone()
        } else {
            CallAudioPipe.shared.repairAudioNow()
        }
    }

    func start(peerId: String, name: String, avatar: String, video: Bool) {

        resetIfStale()
        guard phase == .idle else { errorText = "正在通话中"; return }
        guard !peerId.isEmpty else { errorText = "找不到对方账号"; return }
        resetInviteRetry()
        dismissDialog()
        minimized = false
        self.peerId = peerId
        accountToken = API.shared.token
        peerName = name
        peerAvatar = avatar
        isVideo = video
        iAmCaller = true
        relayOK = false
        muted = false
        micBlocked = false
        cameraOff = false
        seconds = 0
        tip = video ? "正在等待对方接受邀请…" : "正在呼叫…"
        callId = "call" + String(Int(Date().timeIntervalSince1970 * 1000)) + String(UUID().uuidString.prefix(4))
        callOwnerId = AppState.cachedUser()?.id ?? ""
        phase = .outgoing
        startRingTimeout()
        Ringtone.shared.startRingback()
        Realtime.shared.start()
        Task { await beginMedia() }

        Task { await startTRTCIfPossible() }
    }

    func accept(asAudio: Bool = false) {
        guard phase == .incoming else { return }
        if asAudio, isVideo {
            isVideo = false
            sendCall(["action": "media", "media": "audio"])
        }
        Ringtone.shared.stop()
        relayOK = false

        muted = false
        micBlocked = false
        phase = .connecting
        tip = "正在接通…"
        Task { await beginMedia() }
        Task { await startTRTCIfPossible() }
        startConnectWatch()

    }

    func reject() {
        guard !callId.isEmpty else { return }
        sendCall(["action": "reject"])
        finish(tip: "已拒绝")
    }

    func reject(withReply text: String) {
        let say = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !callId.isEmpty else { return }

        if say.isEmpty { sendCall(["action": "reject"]) }
        else { sendCall(["action": "reject", "text": say]) }
        finish(tip: "已拒绝")
    }

    @Published var speakerLevels: [String: Double] = [:]

    private var lastLevelSent: Double = -1
    private var levelTask: Task<Void, Never>?

    func upgradeToVideo() {
        guard phase == .active, !isVideo, !isGroupCall else { return }
        isVideo = true
        sendCall(["action": "media", "media": "video"])
        note("切到视频通话")
        Task { await startTRTCIfPossible() }
    }

    func requestScreenShare(peerId: String, name: String, avatar: String) {
        if screenSharing {
            stopScreenSharing()
            return
        }
        if phase == .idle {
            screenSharePending = true
            start(peerId: peerId, name: name, avatar: avatar, video: true)
            return
        }
        guard !isGroupCall else {
            errorText = "群通话请先以视频通话方式进入"
            return
        }
        screenSharePending = true
        if phase != .active {
            tip = "接通后会自动共享屏幕"
        } else if !isVideo {
            switchVideo()
        } else {
            startScreenSharingNow()
        }
    }

    func requestGroupScreenShare(chatId: String, title: String) {
        if screenSharing {
            stopScreenSharing()
            return
        }
        if phase == .idle {
            screenSharePending = true
            startGroupCall(chatId: chatId, title: title, video: true)
            return
        }
        guard isGroupCall, isVideo else {
            errorText = "请先进入群视频通话"
            return
        }
        if phase == .active {
            startScreenSharingNow()
        } else {
            screenSharePending = true
            tip = "接通后会自动共享屏幕"
        }
    }

    func toggleScreenSharing() {
        if screenSharing {
            stopScreenSharing()
        } else {
            screenSharePending = true
            if phase == .active, isVideo {
                startScreenSharingNow()
            }
        }
    }

    private func startScreenSharingNow() {
        guard phase != .idle, isVideo, !screenSharing else { return }
        screenSharePending = false
        if usingTRTC {
            screenSharing = TRTCBridge.shared.startInAppScreenShare()
            tip = screenSharing ? "正在共享屏幕" : "屏幕共享没启动"
        } else if let source = videoSource {
            capturer?.stopCapture()
            screenCapturer.start(source: source) { [weak self] error in
                guard let self else { return }
                self.screenSharing = error == nil
                self.tip = error == nil ? "正在共享屏幕" : (error ?? "屏幕共享没启动")
                if let error {
                    self.errorText = error
                    self.capturer?.stopCapture()
                    self.startCapture(source)
                }
                self.sendCall(["action": "state", "muted": self.muted,
                               "camOff": self.cameraOff, "screen": self.screenSharing])
            }
        } else {
            tip = "视频通道还没准备好，请稍后重试"
        }
    }

    func stopScreenSharing() {
        guard screenSharing || screenSharePending else { return }
        screenSharePending = false
        screenCapturer.stop()
        if usingTRTC {
            TRTCBridge.shared.stopInAppScreenShare()
        } else if let source = videoSource {
            capturer?.stopCapture()
            startCapture(source)
        }
        screenSharing = false
        if phase != .idle {
            tip = isVideo ? "视频通话中" : "通话中"
            sendCall(["action": "state", "muted": muted,
                      "camOff": cameraOff, "screen": false])
        }
    }

    func inviteToCall(_ userId: String) {
        guard !userId.isEmpty else { return }

        guard !roomId.isEmpty else {
            // group-ready 可能比重连后的首帧晚到。先记住这次邀请，
            // 房间号一回执就自动发出，避免误报“还没建好”。
            pendingGroupInviteUserId = userId
            tip = "正在建立群通话…"
            note("群通话房间未就绪，邀请已排队")
            return
        }

        guard roster.count < 9 else {
            showDialog("通话人数已满", detail: "一个通话最多 9 个人。")
            return
        }
        sendCall(["action": "group-invite", "roomId": roomId, "toUserId": userId])
        note("邀请 " + userId + " 加入通话")
    }

    var groupCallFull: Bool { isGroupCall && roster.count >= 9 }

    private func startLevelReporting() {
        levelTask?.cancel()
        levelTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000)
                if Task.isCancelled { break }
                guard phase.isBusy, isGroupCall else { continue }
                let lv = Double(CallAudioPipe.shared.lastLevel)
                if abs(lv - lastLevelSent) < 0.02 { continue }
                lastLevelSent = lv
                sendCall(["action": "level", "level": max(0, min(1, lv))])
            }
        }
    }

    private func applyLevels(_ ev: PushEvent) {
        guard isGroupCall else { return }
        speakerLevels = ev.callLevels
    }

    func hangup() {
        guard phase.isBusy else { return }
        if isGroupCall { leaveGroupCall(); return }
        failTask?.cancel()
        failTask = nil
        let started = (phase == .active)
        if !callId.isEmpty {
            sendCall(["action": started ? "hangup" : (iAmCaller ? "cancel" : "reject")])
        }
        finish(tip: started ? "通话结束" : "已取消")
    }

    /// 账号切换前结束旧账号的通话，禁止旧信令和媒体状态带进新账号。
    func resetForAccountChange() {
        pendingPushTask?.cancel()
        pendingPushTask = nil
        pendingPushCallId = ""
        pendingPushAnswer = false
        dialogTask?.cancel()
        dialogTask = nil
        dialog = nil
        let oldCallKey = isGroupCall ? roomId : callId
        if phase.isBusy {
            hangup()
        }
        if !oldCallKey.isEmpty {
            LocalNotify.clearCall(callId: oldCallKey)
        }
        accountToken = ""
        minimized = false
    }

    func toggleMute() {
        let next = !muted
        withAnimation(.easeOut(duration: 0.12)) { muted = next }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // 先完成按钮反馈，再切换可能阻塞的音频线程。
        Task { @MainActor in
            await Task.yield()
            audioTrack?.isEnabled = !next
            if usingTRTC { TRTCBridge.shared.setMuted(next) }
            sendCall(["action": "state", "muted": next, "camOff": cameraOff])
        }
    }

    func toggleCamera() {
        guard isVideo else { return }
        cameraOff.toggle()
        localVideoTrack?.isEnabled = !cameraOff
        if usingTRTC { TRTCBridge.shared.setCameraOff(cameraOff) }
        sendCall(["action": "state", "muted": muted, "camOff": cameraOff])
    }

    func switchVideo() {
        guard phase == .active || phase == .connecting || phase == .outgoing else { return }
        isVideo.toggle()

        sendCall(["action": "media", "media": isVideo ? "video" : "audio"])
        if isVideo {
            stopProximity()
            Task {
                await beginMedia()
                await startTRTCIfPossible()
            }
            tip = "正在切换为视频通话…"
        } else {
            localVideoTrack?.isEnabled = false
            if usingTRTC { TRTCBridge.shared.setCameraOff(true) }
            tip = "已切换为语音通话"
        }
    }

    func toggleSpeaker() {
        let next = !speakerOn
        withAnimation(.easeOut(duration: 0.12)) { speakerOn = next }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task { @MainActor in
            await Task.yield()
            applySpeaker()
            if usingTRTC { TRTCBridge.shared.setSpeaker(next) }
        }
    }

    func minimize() { minimized = true }
    func restore() { minimized = false }

    func resumeFromPush(callId: String, answer: Bool) {
        guard !callId.isEmpty else { return }
        if phase == .incoming, self.callId == callId {
            minimized = false
            if answer { accept() }
            return
        }
        guard phase == .idle else { return }
        recoverPendingCall(expectedCallId: callId, answer: answer)
    }

    func rejectFromPush(callId: String) {
        guard !callId.isEmpty else { return }
        if phase == .incoming, self.callId == callId {
            reject()
            return
        }
        Task { @MainActor in
            Realtime.shared.start()
            for _ in 0..<25 {
                if Realtime.shared.connected { break }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            guard Realtime.shared.connected else { return }
            Realtime.shared.sendJSON(["type": "call", "action": "reject", "callId": callId])
            LocalNotify.clearCall(callId: callId)
        }
    }

    func restorePendingAfterActivation() {
        guard phase == .idle, pendingPushTask == nil else { return }
        recoverPendingCall(expectedCallId: "", answer: false)
    }

    private func recoverPendingCall(expectedCallId: String, answer: Bool) {
        pendingPushTask?.cancel()
        pendingPushCallId = expectedCallId
        pendingPushAnswer = answer
        minimized = false
        Realtime.shared.start()
        pendingPushTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            var info: PendingCallInfo? = nil

            for attempt in 0..<12 {
                if Task.isCancelled { self.pendingPushTask = nil; return }
                if !expectedCallId.isEmpty, self.phase == .incoming, self.callId == expectedCallId {
                    self.pendingPushTask = nil
                    self.pendingPushCallId = ""
                    self.minimized = false
                    if self.pendingPushAnswer { self.accept() }
                    return
                }
                guard self.phase == .idle else {
                    self.pendingPushTask = nil
                    self.pendingPushCallId = ""
                    return
                }
                if !API.shared.token.isEmpty {
                    info = await API.shared.pendingCall()
                    if let c = info {
                        if expectedCallId.isEmpty || c.callId == expectedCallId { break }
                        info = nil
                    }
                }
                if attempt < 11 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }
            guard !Task.isCancelled, self.phase == .idle else {
                self.pendingPushTask = nil
                self.pendingPushCallId = ""
                return
            }
            guard let call = info,
                  expectedCallId.isEmpty || call.callId == expectedCallId else {

                self.pendingPushTask = nil
                self.pendingPushCallId = ""
                return
            }
            let shouldAnswer = self.pendingPushAnswer
            var ev = PushEvent()
            ev.type = "call"
            ev.callAction = "incoming"
            ev.callId = call.callId
            ev.callMedia = call.media
            ev.callPeerId = call.peerId
            ev.callPeerName = call.peerName
            ev.callPeerAvatar = call.peerAvatar
            ev.callSDP = call.sdp
            self.pendingPushTask = nil
            self.pendingPushCallId = ""
            self.handle(ev)
            guard shouldAnswer else {
                self.minimized = false
                return
            }

            for _ in 0..<30 {
                if Task.isCancelled { return }
                if Realtime.shared.connected {
                    if self.phase == .incoming, self.callId == call.callId {
                        self.accept()
                    }
                    return
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    func startGroupCall(chatId: String, title: String, video: Bool = false) {

        Task { await API.shared.callDiag("群通话点了 chat=\(chatId) video=\(video) phase=\(phase)") }

        if phase != .idle { resetIfStale() }
        guard phase == .idle else {
            errorText = "你正在通话中"
            Task { await API.shared.callDiag("群通话被挡：phase=\(phase)") }
            return
        }
        isGroupCall = true
        accountToken = API.shared.token
        callOwnerId = ""
        isVideo = video
        groupChatId = chatId
        groupTitle = title
        roomId = ""
        roster = []
        peerName = title
        peerAvatar = ""
        muted = false
        cameraOff = false
        seconds = 0
        tip = "正在邀请群成员…"
        phase = .outgoing
        iAmCaller = true

        if !video { startGroupAudio() }
        Realtime.shared.sendJSON(["type": "call", "action": "group-start", "chatId": chatId,
                                  "media": video ? "video" : "audio"])
        startConnectWatch()
    }

    func acceptGroupCall() {
        guard phase == .incoming || phase == .outgoing else { return }
        Ringtone.shared.stop()
        muted = false
        micBlocked = false
        tip = "正在接通…"
        phase = .connecting
        iAmCaller = false
        if isVideo {

        } else {
            startGroupAudio()
        }
        Realtime.shared.sendJSON(["type": "call", "action": "group-join",
                                  "roomId": roomId, "media": isVideo ? "video" : "audio"])
        if isVideo { Task { await joinGroupTRTC() } }
        startConnectWatch()
    }

    private func joinGroupTRTC() async {
        guard isGroupCall, isVideo, !roomId.isEmpty, !trtcJoined, !usingTRTC else { return }
        let bridge = TRTCBridge.shared
        bridge.onJoined = { [weak self] ok in
            guard let self = self, ok else { return }
            guard self.phase != .idle else { return }
            self.trtcJoined = true
            self.usingTRTC = true

            bridge.activate()
            self.note("群视频：TRTC 已进房并开始采集")
        }
        if await bridge.start(roomSeed: roomId, video: true) {
            note("群视频：正在进 TRTC 房间")
        } else {
            note("群视频：TRTC 进不去，退回语音转发")
            if !serverAudioOn { startGroupAudio() }
        }
    }

    private func hydrateGroupRoster() {
        rosterHydrationTask?.cancel()
        let chatId = groupChatId
        let token = accountToken
        guard !chatId.isEmpty, !token.isEmpty else { return }
        rosterHydrationTask = Task { @MainActor [weak self] in
            guard let result = try? await API.shared.chatMembers(chatId: chatId) else { return }
            guard let self = self, !Task.isCancelled,
                  self.accountToken == token, self.groupChatId == chatId else { return }
            var profiles: [String: User] = [:]
            for user in result.members { profiles[user.id] = user }
            self.roster = self.roster.map { member in
                guard let user = profiles[member.userId] else { return member }
                var fixed = member
                if fixed.name.isEmpty { fixed.name = user.groupName }
                if fixed.avatar.isEmpty { fixed.avatar = user.avatarPath }
                return fixed
            }
        }
    }

    func leaveGroupCall() {
        rosterHydrationTask?.cancel()
        rosterHydrationTask = nil
        if !roomId.isEmpty {
            Realtime.shared.sendJSON(["type": "call", "action": "group-leave", "roomId": roomId])
        }

        if isVideo || TRTCBridge.shared.joined {
            TRTCBridge.shared.stopMeetingViews()
            TRTCBridge.shared.stop()
        }
        CallAudioPipe.shared.onFrame = nil
        CallAudioPipe.shared.stop()
        serverAudioOn = false
        isGroupCall = false
        roomId = ""
        groupChatId = ""
        pendingGroupInviteUserId = ""
        roster = []
        finish(tip: "通话结束")
    }

    private func startGroupAudio() {
        guard !serverAudioOn else { return }
        CallAudioPipe.shared.prepareForGroupCall()
        serverAudioOn = true
        audioTrack?.isEnabled = false

        // 群语音以前绕过了单聊的权限申请，全新安装后会直接把
        // AVCaptureSession 启动失败误报成“麦克风没开”。先等权限结果，
        // 再启动采集；音频帧处理本身不变。
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let granted = await Permission.ask(.audio)
            guard self.isGroupCall, self.phase != .idle, self.serverAudioOn else { return }
            guard granted else {
                self.micBlocked = true
                self.tip = "麦克风权限没开：设置 → 本 App → 麦克风"
                self.note("群语音麦克风权限没开")
                return
            }
            self.micBlocked = false
            self.beginGroupAudioCapture()
        }
    }

    private func beginGroupAudioCapture() {
        CallAudioPipe.shared.onFrame = { [weak self] data in
            guard let self = self, !self.muted, !self.roomId.isEmpty else { return }
            Realtime.shared.sendJSON(["type": "call", "action": "group-audio",
                                      "roomId": self.roomId,
                                      "data": data.base64EncodedString()])
        }
        CallAudioPipe.shared.start()
        reportMicState(prefix: "群语音麦克风")
    }

    func invite(userId: String, name: String) async -> String {
        do {
            let chat = try await API.shared.directChat(userId: userId)
            _ = try await API.shared.send(chatId: chat.id, kind: "text",
                                          content: "邀请你加入语音通话，点这条消息回拨给我")
            return "已邀请 \(name)"
        } catch {
            return (error as? APIError)?.errorDescription ?? "邀请失败"
        }
    }

    private func applySpeaker() {
        if usingTRTC { return }
        let s = AVAudioSession.sharedInstance()

        try? s.overrideOutputAudioPort((speakerOn && !proximityNear) ? .speaker : .none)
    }

    func audioDevices() -> [CallAudioRoute] {
        let s = AVAudioSession.sharedInstance()
        var list: [CallAudioRoute] = [
            CallAudioRoute(id: "receiver", name: "iPhone", kind: "receiver")
        ]

        for p in (s.availableInputs ?? []) {
            switch p.portType {
            case .bluetoothHFP, .bluetoothLE, .bluetoothA2DP:
                list.append(CallAudioRoute(id: p.uid, name: p.portName, kind: "bluetooth"))
            case .headsetMic, .headphones:
                list.append(CallAudioRoute(id: p.uid, name: p.portName, kind: "headset"))
            default:
                break
            }
        }
        list.append(CallAudioRoute(id: "speaker", name: "扬声器", kind: "speaker"))
        return list
    }

    var currentAudioDeviceName: String {
        let outs = AVAudioSession.sharedInstance().currentRoute.outputs
        if outs.contains(where: { $0.portType == .builtInSpeaker }) { return "扬声器" }
        if let b = outs.first(where: { $0.portType == .bluetoothHFP || $0.portType == .bluetoothLE
            || $0.portType == .bluetoothA2DP }) { return b.portName }
        if let h = outs.first(where: { $0.portType == .headphones || $0.portType == .headsetMic }) {
            return h.portName
        }
        return "iPhone"
    }

    func selectAudioDevice(_ r: CallAudioRoute) {
        let s = AVAudioSession.sharedInstance()
        switch r.kind {
        case "speaker":
            speakerOn = true
            try? s.overrideOutputAudioPort(.speaker)
            if usingTRTC { TRTCBridge.shared.setSpeaker(true) }
        case "receiver":
            speakerOn = false
            try? s.overrideOutputAudioPort(.none)
            if usingTRTC { TRTCBridge.shared.setSpeaker(false) }
        default:
            if let p = (s.availableInputs ?? []).first(where: { $0.uid == r.id }) {
                try? s.setPreferredInput(p)
                speakerOn = false
                try? s.overrideOutputAudioPort(.none)
                if usingTRTC { TRTCBridge.shared.setSpeaker(false) }
            }
        }
    }

    func startProximity() {
        guard !isVideo else { return }
        guard proximityObserver == nil else { return }
        UIDevice.current.isProximityMonitoringEnabled = true
        proximityObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.proximityStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applyProximity() }
        }
    }

    func stopProximity() {
        if let ob = proximityObserver {
            NotificationCenter.default.removeObserver(ob)
            proximityObserver = nil
        }
        UIDevice.current.isProximityMonitoringEnabled = false
        proximityNear = false
    }

    private func applyProximity() {
        guard phase.isBusy, !isVideo else { return }
        proximityNear = UIDevice.current.proximityState
        applySpeaker()
        if usingTRTC { TRTCBridge.shared.setSpeaker(speakerOn && !proximityNear) }
    }

    func setBlurBackground(_ on: Bool) {
        VideoBlur.shared.enabled = on
        blurBackground = on
        TRTCBridge.shared.setBackgroundBlur(on)
    }

    func toggleBlurBackground() {
        setBlurBackground(!blurBackground)
    }

    func flipCamera() {
        if usingTRTC { TRTCBridge.shared.flipCamera(); return }
        guard isVideo, let capturer = capturer else { return }
        let front = capturer.captureSession.isRunning
        let devices = RTCCameraVideoCapturer.captureDevices()
        guard let dev = devices.first(where: { $0.position == (front ? .back : .front) }) ?? devices.first else { return }
        guard let fmt = bestFormat(for: dev) else { return }
        capturer.startCapture(with: dev, format: fmt, fps: 30)
    }

    private func sendCall(_ body: [String: Any]) {
        var msg: [String: Any] = ["type": "call", "callId": callId]
        if !isGroupCall, !callOwnerId.isEmpty {
            msg["ownerId"] = callOwnerId
        }
        body.forEach { msg[$0.key] = $0.value }
        let action = (body["action"] as? String) ?? ""
        if action == "invite", iAmCaller {
            lastOutgoingInvite = msg
            inviteAcked = false
            startInviteRetry()
        }
        Realtime.shared.sendJSON(msg)
    }

    private func startInviteRetry() {
        guard inviteRetryTask == nil else { return }
        inviteRetryTask = Task { @MainActor [weak self] in
            let delays: [UInt64] = [1_500_000_000, 3_000_000_000,
                                    6_000_000_000, 10_000_000_000]
            for delay in delays {
                try? await Task.sleep(nanoseconds: delay)
                guard let self = self, !Task.isCancelled,
                      self.iAmCaller, !self.inviteAcked,
                      self.phase == .outgoing,
                      let invite = self.lastOutgoingInvite else { return }
                if Realtime.shared.connected {
                    self.note("通话邀请尚未确认，自动补发")
                    Realtime.shared.sendJSON(invite)
                }
            }
            self?.inviteRetryTask = nil
        }
    }

    private func resetInviteRetry() {
        inviteRetryTask?.cancel()
        inviteRetryTask = nil
        lastOutgoingInvite = nil
        inviteAcked = false
    }

    private func acknowledgeInvite() {
        inviteAcked = true
        inviteRetryTask?.cancel()
        inviteRetryTask = nil
    }

    private func startServerAudioIfVoice() {
        guard !isVideo else { return }
        guard !usingTRTC else { return }
        guard !serverAudioOn else { return }
        serverAudioOn = true
        audioTrack?.isEnabled = false
        CallAudioPipe.shared.onFrame = { [weak self] data in
            guard let self = self, !self.muted else { return }
            self.sendCall(["action": "audio", "data": data.base64EncodedString()])
        }
        CallAudioPipe.shared.start()

        if phase != .active {
            Ringtone.shared.stop()
            phase = .active
            tip = "通话中"
            ringTimer?.invalidate()
            ringTimer = nil
            startTimer()
        }

        reportMicState(prefix: "App 语音走服务器转发")
    }

    private func reportMicState(prefix: String) {
        let p = CallAudioPipe.shared

        p.onStateChange = { [weak self] ok in
            guard let self = self else { return }
            p.onStateChange = nil
            self.micReported(ok, prefix: prefix)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 7.0) { [weak self] in
            guard let self = self, p.onStateChange != nil else { return }
            p.onStateChange = nil
            self.micReported(p.isRunning, prefix: prefix)
        }
    }

    private func micReported(_ ok: Bool, prefix: String) {

        if usingTRTC || CallAudioPipe.shared.hasHandedOver { return }
        let reason = CallAudioPipe.shared.lastError
        Task { await API.shared.callDiag(prefix + " 采集=" + (ok ? "ok" : "失败")
            + (ok ? "" : " 原因: " + reason)) }
        if ok {
            micBlocked = false
            note("语音走服务器转发 ✓")

            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                guard let self = self, !self.callId.isEmpty, !self.isVideo else { return }
                let p = CallAudioPipe.shared
                guard self.serverAudioOn || p.framesIn > 0 else { return }
                await API.shared.callDiag("语音 6 秒自检 " + p.playDiag)
            }
        } else {

            micBlocked = true
            note("麦克风没起来")
            tip = reason.contains("权限") ? "麦克风权限没开：设置 → 本 App → 麦克风"
                                         : "麦克风没起来，对方可能听不到你说话"
        }
    }

    private func handle(_ ev: PushEvent) {

        if !accountToken.isEmpty, accountToken != API.shared.token {
            resetForAccountChange()
            return
        }
        if ev.type == "ready" {
            if phase == .outgoing, iAmCaller, !inviteAcked,
               let invite = lastOutgoingInvite {
                Realtime.shared.sendJSON(invite)
            }
            if phase == .idle, pendingPushTask == nil, !API.shared.token.isEmpty {
                recoverPendingCall(expectedCallId: "", answer: false)
            }
            if phase != .idle, phase != .active, ev.callActive == false {
                finish(tip: "通话已结束")
            }
            return
        }
        if ev.type == "call-error" {
            if ev.callId == callId { acknowledgeInvite() }
            if !ev.callError.isEmpty { errorText = ev.callError }

            if ev.callId == callId, phase != .active {
                failLater(ev.callError)
            }
            return
        }
        let action = ev.callAction
        switch action {
        case "net":
            if let c = netWaiters.removeValue(forKey: ev.callPeerId) { c.resume(returning: ev.callSameNetwork) }
        case "incoming":

            if ev.callId == callId, !iAmCaller, !callId.isEmpty {
                return
            }
            if phase != .idle { resetIfStale() }
            guard phase == .idle else {
                let why = "自动拒绝来电 phase=\(phase) callId=\(callId) pipe=\(CallAudioPipe.shared.isRunning)"
                Task { await API.shared.callDiag(why) }
                Realtime.shared.sendJSON(["type": "call", "action": "reject", "callId": ev.callId])
                return
            }
            accountToken = API.shared.token
            callId = ev.callId
            peerId = ev.callPeerId
            callOwnerId = ev.callOwnerId.isEmpty ? ev.callPeerId : ev.callOwnerId
            peerName = ev.callPeerName.isEmpty ? "对方" : ev.callPeerName
            peerAvatar = ev.callPeerAvatar
            isVideo = (ev.callMedia == "video")
            iAmCaller = false
            muted = false
            cameraOff = false
            peerMuted = false
            peerCameraOff = false
            seconds = 0
            remoteOfferSDP = ev.callSDP
            tip = isVideo ? "邀请你视频通话…" : "邀请你语音通话…"
            phase = .incoming
            startRingTimeout()

            if UIApplication.shared.applicationState != .active {
                LocalNotify.incomingCall(callId: callId, peerName: peerName, video: isVideo)
            }
            Ringtone.shared.startIncoming()
            UINotification.buzz()

        case "ringing":
            guard ev.callId == callId else { return }
            acknowledgeInvite()
            tip = isVideo ? "正在等待对方接受邀请…" : "正在呼叫…"

        case "state":
            guard ev.callId == callId else { return }
            peerMuted = ev.callPeerMuted
            peerCameraOff = ev.callPeerCameraOff

        case "switch":
            guard ev.callId == callId else { return }
            if ev.callPeerVideo != isVideo {
                isVideo = ev.callPeerVideo
                tip = isVideo ? "对方切换成了视频通话" : "对方切换成了语音通话"
                if isVideo { Task { await startTRTCIfPossible() } }
            }

        case "media":
            guard ev.callId == callId else { return }
            let wantVideo = (ev.callMedia == "video")
            if wantVideo != isVideo {
                isVideo = wantVideo
                tip = wantVideo ? "对方切换成了视频通话" : "对方切换成了语音通话"
                if wantVideo {
                    Task {
                        await beginMedia()
                        await startTRTCIfPossible()
                    }
                } else {
                    localVideoTrack?.isEnabled = false
                    if usingTRTC { TRTCBridge.shared.setCameraOff(true) }
                }
            }

        case "group-incoming":

            guard phase == .idle else { return }
            accountToken = API.shared.token
            isGroupCall = true
            isVideo = ev.callPeerVideo
            roomId = ev.callRoomId
            groupChatId = ev.callChatId
            groupTitle = ev.callPeerName.isEmpty ? (isVideo ? "群视频通话" : "群语音通话") : ev.callPeerName
            peerName = groupTitle
            peerAvatar = ev.callPeerAvatar
            roster = ev.callRoster
            hydrateGroupRoster()
            muted = false
            cameraOff = false
            seconds = 0
            tip = isVideo ? "邀请你加入群视频通话…" : "邀请你加入群语音通话…"
            phase = .incoming
            startRingTimeout()
            if UIApplication.shared.applicationState != .active {
                LocalNotify.incomingCall(callId: roomId,
                                         peerName: groupTitle + (isVideo ? "（群视频）" : "（群语音）"),
                                         video: isVideo)
            }
            Ringtone.shared.startIncoming()
            UINotification.buzz()

        case "levels":

            applyLevels(ev)
            return

        case "group-ready":

            guard isGroupCall else { return }
            roomId = ev.callRoomId.isEmpty ? roomId : ev.callRoomId
            groupChatId = ev.callChatId.isEmpty ? groupChatId : ev.callChatId
            if !ev.callRoster.isEmpty { roster = ev.callRoster }
            hydrateGroupRoster()
            Ringtone.shared.stop()
            ringTimer?.invalidate(); ringTimer = nil
            connectTimer?.invalidate(); connectTimer = nil
            if phase != .active {
                phase = .active
                tip = "通话中"
                startTimer()
            }

            if isVideo, !trtcJoined { Task { await joinGroupTRTC() } }
            if !pendingGroupInviteUserId.isEmpty {
                let target = pendingGroupInviteUserId
                pendingGroupInviteUserId = ""
                Realtime.shared.sendJSON(["type": "call", "action": "group-invite",
                                          "roomId": roomId, "toUserId": target])
                note("群通话房间就绪，补发邀请 " + target)
            }

        case "group-joined", "group-left":
            guard isGroupCall, ev.callRoomId == roomId else { return }
            roster = ev.callRoster
            hydrateGroupRoster()

            startLevelReporting()
            if action == "group-joined", !ev.callPeerName.isEmpty {
                tip = ev.callPeerName + " 加入了通话"
            }

        case "group-audio":
            guard isGroupCall, let b64 = ev.callAudioData, let d = Data(base64Encoded: b64) else { return }
            CallAudioPipe.shared.play(d)

        case "accepted":
            guard ev.callId == callId else { return }
            acknowledgeInvite()
            Ringtone.shared.stop()
            startConnectWatch()
            if isVideo {
                phase = .connecting
                tip = "正在接通…"
            } else {

                if !serverAudioOn { startServerAudioIfVoice() }
                scheduleAudioTRTCTakeover()
                if phase != .active {
                    phase = .active
                    tip = "通话中"
                    ringTimer?.invalidate()
                    ringTimer = nil
                    connectTimer?.invalidate()
                    connectTimer = nil
                    startTimer()
                }
                reportMicState(prefix: "App 语音走服务器转发（对方已接）")
                Task { await startTRTCIfPossible() }
            }

        case "audio":

            guard !usingTRTC else { return }
            guard let b64 = ev.callAudioData, let d = Data(base64Encoded: b64) else { return }
            CallAudioPipe.shared.play(d)

        case "sdp":
            guard ev.callId == callId, let sdp = ev.callSDP else { return }
            let desc = RTCSessionDescription(type: .answer, sdp: sdp)
            pc?.setRemoteDescription(desc) { [weak self] err in
                Task { @MainActor in
                    guard let self = self else { return }
                    if let err = err { self.errorText = "接通失败：\(err.localizedDescription)" }
                    self.flushIce()
                }
            }

        case "ice":
            guard ev.callId == callId, let json = ev.callCandidate else { return }
            guard let data = json.data(using: .utf8),
                  let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            let sdp = (o["candidate"] as? String) ?? ""
            let mid = (o["sdpMid"] as? String) ?? "0"
            let idx = (o["sdpMLineIndex"] as? Int) ?? 0
            let cand = RTCIceCandidate(sdp: sdp, sdpMLineIndex: Int32(idx), sdpMid: mid)
            if pc?.remoteDescription == nil { pendingIce.append(cand) } else { pc?.add(cand) { _ in } }

        case "end":
            if ev.callId == callId || callId.isEmpty {
                acknowledgeInvite()
                let why: String
                switch ev.callReason {
                case "rejected":     why = "对方已拒绝"
                case "cancel":       why = iAmCaller ? "已取消" : "对方已取消"
                case "timeout":      why = iAmCaller ? "对方无应答" : "未接听"
                case "offline":      why = "对方不在线"
                case "disconnected": why = "对方已断开"
                case "hangup":       why = "通话已结束"
                default:             why = "通话已结束"
                }
                finish(tip: why)
            }

        default:
            break
        }
    }

    private func loadIce() async {

        let hostOnly = API.shared.server.split(separator: ":").first.map(String.init) ?? ""
        if !hostOnly.isEmpty {

            iceServers.insert(RTCIceServer(urlStrings: ["turn:\(hostOnly):3478?transport=tcp",
                                                       "turn:\(hostOnly):3478?transport=udp"],
                                           username: "chris", credential: "chris1234"), at: 0)
        }
        guard let b = await API.shared.branding(),
              let raw = b.iceServers?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return }

        if let data = raw.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            var out: [RTCIceServer] = []
            for it in arr {
                var urls: [String] = []
                if let one = it["urls"] as? String { urls = [one] }
                else if let many = it["urls"] as? [String] { urls = many }
                if urls.isEmpty { continue }
                out.append(RTCIceServer(urlStrings: urls,
                                        username: it["username"] as? String,
                                        credential: it["credential"] as? String))
            }
            if !out.isEmpty { iceServers = out }
            return
        }
        let list = raw.split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if !list.isEmpty { iceServers = list.map { RTCIceServer(urlStrings: [$0]) } }
    }

    private let pathMonitor = NWPathMonitor()
    private var lastPathStatus: NWPath.Status? = nil
    private var lastPathKind: String? = nil

    private func pathKind(_ path: NWPath) -> String {
        if path.usesInterfaceType(.wifi) { return "wifi" }
        if path.usesInterfaceType(.cellular) { return "cellular" }
        if path.usesInterfaceType(.wiredEthernet) { return "wired" }
        return "other"
    }

    private func startPathMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self = self else { return }
                let prev = self.lastPathStatus
                let prevKind = self.lastPathKind
                let kind = self.pathKind(path)
                self.lastPathStatus = path.status
                self.lastPathKind = kind
                let interfaceChanged = path.status == .satisfied
                    && prevKind != nil && prevKind != kind
                guard prev != nil, prev != path.status || interfaceChanged else { return }
                guard self.phase == .active else { return }
                let routeText = (prevKind ?? "unknown") + " → " + kind
                self.note("网络切换（" + (path.status == .satisfied ? routeText : "断开") + "）→ 自动重连")
                self.weakNet = true
                if self.tip != "通话中" && self.tip != "视频通话中" { self.tip = "网络切换，正在重连…" }
                if self.usingTRTC {
                    TRTCBridge.shared.recoverAudioAfterNetworkChange()
                } else {
                    await self.startTRTCIfPossible()
                }
                if !self.usingTRTC {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    guard self.phase == .active else { return }
                    if self.usingTRTC {
                        TRTCBridge.shared.recoverAudioAfterNetworkChange()
                    } else {
                        CallAudioPipe.shared.repairAudioNow()
                    }
                }
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    guard let self = self, self.phase == .active else { return }
                    if self.usingTRTC || self.pc?.connectionState == .connected
                        || (self.pc == nil && Realtime.shared.connected) {
                        self.weakNet = false
                        if self.tip == "网络切换，正在重连…" { self.tip = "通话中" }
                    }
                }
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "chris.call.path"))
    }

    private func makeFactory() -> RTCPeerConnectionFactory {
        if let f = factory { return f }
        let f = RTCPeerConnectionFactory(encoderFactory: RTCDefaultVideoEncoderFactory(),
                                        decoderFactory: RTCDefaultVideoDecoderFactory())
        factory = f
        return f
    }

    private func beginMedia() async {
        CallAudioPipe.shared.resetHandOver()

        CallAudioPipe.shared.prepareForNewCall()
        let mic = await Permission.ask(.audio)

        if !mic {
            micBlocked = true
            note("麦克风权限没开")
            Task { await API.shared.callDiag("App 麦克风权限没开（界面已提示）") }
        } else {
            micBlocked = false
        }
        if isVideo {
            let cam = await Permission.ask(.video)
            if !cam { errorText = "没有摄像头权限，去「设置 → CHRIS聊天」里打开"; finish(tip: "没有摄像头权限"); return }
        }
        activateAudioSession()
        speakerOn = isVideo
        applySpeaker()

        if iAmCaller, phase == .outgoing {
            Ringtone.shared.startRingback()
        }

        if !isVideo {
            if iAmCaller, phase == .outgoing {
                if !Realtime.shared.ready {
                    tip = "正在建立通话连接…"
                    _ = await Realtime.shared.waitUntilReady(timeout: 6)
                    guard phase == .outgoing else { return }
                }
                sendCall(["action": "invite", "toUserId": peerId, "media": "audio"])
                tip = "正在呼叫…"
                return
            }

            serverAudioOn = true
            CallAudioPipe.shared.onFrame = { [weak self] data in
                guard let self = self, !self.muted else { return }
                self.sendCall(["action": "audio", "data": data.base64EncodedString()])
            }
            CallAudioPipe.shared.start()
            scheduleAudioTRTCTakeover()
            if iAmCaller {

                sendCall(["action": "invite", "toUserId": peerId, "media": "audio"])
                tip = "正在呼叫…"
            } else {

                sendCall(["action": "accept"])

                Ringtone.shared.stop()
                phase = .active
                tip = "通话中"
                ringTimer?.invalidate()
                ringTimer = nil
                connectTimer?.invalidate()
                connectTimer = nil
                startTimer()
            }
            reportMicState(prefix: "App 语音走服务器转发")
            return
        }

        let f = makeFactory()
        let cfg = RTCConfiguration()
        cfg.iceServers = iceServers

        let sameNet = await askSameNetwork(peerUserId: peerId)
        _ = sameNet
        let host = API.shared.server.split(separator: ":").first.map(String.init) ?? ""
        let isLan = host == "localhost" || host.hasPrefix("127.") || host.hasPrefix("10.")
            || host.hasPrefix("192.168.") || host.hasPrefix("172.16") || host.hasPrefix("172.17")
            || host.hasPrefix("172.18") || host.hasPrefix("172.19") || host.hasPrefix("172.2")
            || host.hasPrefix("172.30") || host.hasPrefix("172.31")

        cfg.iceTransportPolicy = .all
        note("配置 iceServers=" + iceServers.map { ($0.urlStrings.first ?? "") }.joined(separator: ",")
             + " policy=all lan=" + (isLan ? "1" : "0"))
        cfg.sdpSemantics = .unifiedPlan
        let pc = f.peerConnection(with: cfg,
                                  constraints: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil),
                                  delegate: self)
        self.pc = pc
        guard let pc = pc else { errorText = "初始化通话失败"; finish(tip: "初始化通话失败"); return }

        let audioSource = f.audioSource(with: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
        let at = f.audioTrack(with: audioSource, trackId: "audio0")
        audioTrack = at
        pc.add(at, streamIds: ["chris"])

        if isVideo {
            let src = f.videoSource()
            videoSource = src
            let vt = f.videoTrack(with: src, trackId: "video0")
            localVideoTrack = vt
            pc.add(vt, streamIds: ["chris"])
            localVideo = vt
            startCapture(src)
        }

        if iAmCaller {
            pc.offer(for: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)) { [weak self] sdp, err in
                Task { @MainActor in
                    guard let self = self, let sdp = sdp else {
                        self?.errorText = err?.localizedDescription ?? "无法发起通话"
                        self?.finish(tip: "无法发起通话")
                        return
                    }
                    pc.setLocalDescription(sdp) { _ in
                        Task { @MainActor in
                            let local = pc.localDescription
                            self.sendCall(["action": "invite", "toUserId": self.peerId,
                                           "media": self.isVideo ? "video" : "audio",
                                           "sdp": ["type": local?.type.rawValue ?? "offer",
                                                   "sdp": local?.sdp ?? sdp.sdp]])
                        }
                    }
                }
            }
        } else {
            guard let offerSDP = remoteOfferSDP else { errorText = "来电信息不完整"; finish(tip: "来电信息不完整"); return }
            let offer = RTCSessionDescription(type: .offer, sdp: offerSDP)
            pc.setRemoteDescription(offer) { [weak self] err in
                Task { @MainActor in
                    guard let self = self else { return }
                    if let err = err { self.errorText = "接通失败：\(err.localizedDescription)"; self.finish(tip: "接通失败"); return }
                    self.flushIce()
                    pc.answer(for: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)) { sdp, _ in
                        Task { @MainActor in
                            guard let sdp = sdp else { self.finish(tip: "接通失败"); return }
                            pc.setLocalDescription(sdp) { _ in
                                Task { @MainActor in
                                    let local = pc.localDescription
                                    self.sendCall(["action": "accept",
                                                   "sdp": ["type": local?.type.rawValue ?? "answer",
                                                           "sdp": local?.sdp ?? sdp.sdp]])
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func flushIce() {
        guard let pc = pc, pc.remoteDescription != nil else { return }
        pendingIce.forEach { pc.add($0) { _ in } }
        pendingIce.removeAll()
    }

    private func startCapture(_ source: RTCVideoSource) {

        let blur = BlurCapturer(inner: source)
        blurDelegate = blur
        let cap = RTCCameraVideoCapturer(delegate: blur)
        capturer = cap
        guard let dev = RTCCameraVideoCapturer.captureDevices().first(where: { $0.position == .front })
            ?? RTCCameraVideoCapturer.captureDevices().first,
              let fmt = bestFormat(for: dev) else { return }
        cap.startCapture(with: dev, format: fmt, fps: 30)
    }

    private func bestFormat(for dev: AVCaptureDevice) -> AVCaptureDevice.Format? {
        let formats = RTCCameraVideoCapturer.supportedFormats(for: dev)
        return formats.min(by: { a, b in
            let da = CMVideoFormatDescriptionGetDimensions(a.formatDescription)
            let db = CMVideoFormatDescriptionGetDimensions(b.formatDescription)
            return abs(Int(da.width) - 1280) + abs(Int(da.height) - 720)
                 < abs(Int(db.width) - 1280) + abs(Int(db.height) - 720)
        }) ?? formats.last
    }

    private func activateAudioSession() {
        let s = AVAudioSession.sharedInstance()

        try? s.setCategory(.playAndRecord, mode: .voiceChat,
                           options: [.allowBluetooth])
        try? s.setActive(true)
    }

    func resetIfStale() {
        guard phase != .idle else { return }
        let busy = (pc != nil) || usingTRTC || TRTCBridge.shared.joined
            || CallAudioPipe.shared.isRunning || !callId.isEmpty
        if busy { return }
        phase = .idle
        tip = ""
        errorText = nil
    }

    private func stopMedia() {
        screenCapturer.stop()
        capturer?.stopCapture()
        capturer = nil
        blurDelegate = nil
        if let pc = pc {
            pc.close()
        }
        pc = nil
        audioTrack = nil
        localVideoTrack = nil
        videoSource = nil
        screenSharing = false
        screenSharePending = false
        remoteVideo = nil
        localVideo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func finish(tip: String) {
        let wasIdle = (phase == .idle)
        let secs = seconds

        LocalNotify.clearCall(callId: callId)

        if UIApplication.shared.applicationState != .active {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 600_000_000)
                KeepAlive.shared.start()
            }
        }
        failTask?.cancel()
        failTask = nil
        self.tip = tip
        Ringtone.shared.stop()
        ticker?.invalidate()
        ticker = nil
        ringTimer?.invalidate()
        ringTimer = nil
        connectTimer?.invalidate()
        connectTimer = nil
        pendingGroupInviteUserId = ""

        if !wasIdle || seconds > 0 { diag.append(CallAudioPipe.shared.playDiag) }
        CallAudioPipe.shared.onFrame = nil
        CallAudioPipe.shared.stop()
        serverAudioOn = false

        stopProximity()
        if blurBackground { setBlurBackground(false) }

        if usingTRTC || TRTCBridge.shared.joined {
            diag.append(TRTCBridge.shared.diagSummary)
            TRTCBridge.shared.stop()
        }

        TRTCBridge.shared.onJoined = nil
        TRTCBridge.shared.onPeerChanged = nil
        TRTCBridge.shared.onRemoteAudioReady = nil
        usingTRTC = false
        trtcJoined = false
        stopMedia()
        resetInviteRetry()

        if !diag.isEmpty {
            let line = (iAmCaller ? "主叫" : "被叫") + (isVideo ? " 视频" : " 语音")
                + " 结果=" + (tip.isEmpty ? "结束" : tip) + " | " + diag.joined(separator: " ")
            diag.removeAll()
            Task { await API.shared.callDiag(line) }
        }
        callId = ""
        callOwnerId = ""
        peerId = ""
        remoteOfferSDP = nil
        pendingIce.removeAll()
        seconds = 0
        muted = false
        micBlocked = false
        cameraOff = false
        screenSharing = false
        screenSharePending = false
        minimized = false
        if !wasIdle {
            phase = .idle

        }
    }

    private func failLater(_ tip: String, hold: Double = 8) {
        guard phase != .idle else { return }
        let text = tip.isEmpty ? "对方没有接听" : tip
        errorText = text
        self.tip = text
        failTask?.cancel()
        failTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(hold * 1_000_000_000))
            guard let self = self, !Task.isCancelled else { return }
            self.finish(tip: text)
        }
    }

    private func note(_ s: String) {
        diag.append(s)
        if diag.count > 20 { diag.removeFirst() }
    }

    private func startConnectWatch() {
        connectTimer?.invalidate()
        connectTimer = Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                guard self.phase == .connecting else { return }
                self.errorText = "声音一直连不上：① 两边都打开「设置 → CHRIS聊天 → 本地网络」；② 两台设备最好在同一个 Wi-Fi"
                self.tip = self.errorText ?? ""
            }
        }
    }

    private static func iceName(_ s: RTCIceConnectionState) -> String {
        switch s {
        case .new: return "new"
        case .checking: return "checking"
        case .connected: return "connected"
        case .completed: return "completed"
        case .failed: return "failed"
        case .disconnected: return "disconnected"
        case .closed: return "closed"
        case .count: return "count"
        @unknown default: return "?"
        }
    }

    private static func gatherName(_ s: RTCIceGatheringState) -> String {
        switch s {
        case .new: return "new"
        case .gathering: return "gathering"
        case .complete: return "complete"
        @unknown default: return "?"
        }
    }

    private func startTimer() {
        seconds = 0
        micDownTicks = 0

        startProximity()
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.seconds += 1
                self.checkMicAlive()
            }
        }
    }

    private func checkMicAlive() {
        guard phase != .idle, !isVideo, !usingTRTC else { return }
        if CallAudioPipe.shared.isRunning {
            micDownTicks = 0
            if micBlocked { micBlocked = false }
        } else {
            micDownTicks += 1
            if micDownTicks >= 5, !micBlocked { micBlocked = true }
        }
    }

    private func startRingTimeout() {
        ringTimer?.invalidate()
        ringTimer = Timer.scheduledTimer(withTimeInterval: 65, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                guard self.phase == .outgoing || self.phase == .incoming else { return }
                if !self.callId.isEmpty && self.iAmCaller {
                    self.sendCall(["action": "cancel", "reason": "timeout"])
                }
                self.finish(tip: self.iAmCaller ? "对方无应答" : "未接听")
            }
        }
    }
}

extension CallCenter: RTCPeerConnectionDelegate {
    nonisolated func peerConnection(_ pc: RTCPeerConnection, didChange state: RTCSignalingState) { }

    nonisolated func peerConnection(_ pc: RTCPeerConnection, didChange state: RTCIceConnectionState) {
        Task { @MainActor in self.note("ice=" + CallCenter.iceName(state)) }
    }

    nonisolated func peerConnection(_ pc: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        Task { @MainActor in self.note("gathering=" + CallCenter.gatherName(newState)) }
    }

    nonisolated func peerConnection(_ pc: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        let isRelay = candidate.sdp.contains("typ relay")
        let isSrflx = candidate.sdp.contains("typ srflx")

        let parts = candidate.sdp.split(separator: " ")
        let typ = parts.count > 7 ? String(parts[7]) : "?"
        let proto = parts.count > 2 ? String(parts[2]) : "?"
        let addr = parts.count > 5 ? "\(parts[4]):\(parts[5])" : ""
        let brief = "\(typ)/\(proto) \(addr)"
        if isRelay || isSrflx {
            Task { @MainActor in
                if isRelay { self.relayOK = true }
                self.note("cand=" + brief)
            }
        } else {
            Task { @MainActor in self.note("cand=" + brief) }
        }
        let body: [String: Any] = ["action": "ice",
                                   "candidate": ["candidate": candidate.sdp,
                                                 "sdpMid": candidate.sdpMid ?? "0",
                                                 "sdpMLineIndex": Int(candidate.sdpMLineIndex)]]
        Task { @MainActor in self.sendCall(body) }
    }

    nonisolated func peerConnection(_ pc: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) { }

    nonisolated func peerConnection(_ pc: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) { }

    nonisolated func peerConnectionShouldNegotiate(_ pc: RTCPeerConnection) { }

    nonisolated func peerConnection(_ pc: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        guard let track = stream.videoTracks.first else { return }
        Task { @MainActor in self.remoteVideo = track }
    }

    nonisolated func peerConnection(_ pc: RTCPeerConnection, didAdd receiver: RTCRtpReceiver, streams: [RTCMediaStream]) {
        guard let track = receiver.track as? RTCVideoTrack else { return }
        Task { @MainActor in self.remoteVideo = track }
    }

    nonisolated func peerConnection(_ pc: RTCPeerConnection, didRemove receiver: RTCRtpReceiver, streams: [RTCMediaStream]) { }

    nonisolated func peerConnection(_ pc: RTCPeerConnection, didRemove stream: RTCMediaStream) { }

    nonisolated func peerConnection(_ pc: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        Task { @MainActor in
            switch newState {
            case .connected:
                self.weakNet = false
                if self.phase != .active {
                    Ringtone.shared.stop()
                    self.phase = .active
                    self.tip = self.isVideo ? "视频通话中" : "通话中"
                    self.ringTimer?.invalidate()
                    self.ringTimer = nil
                    self.startTimer()
                    if self.screenSharePending { self.startScreenSharingNow() }

                    self.showDialog(self.isVideo ? "视频通话已接通" : "语音通话已接通",
                                    detail: "", auto: 2)
                }
            case .failed:

                if !self.isVideo {
                    self.weakNet = true
                    if self.tip != "通话中" { self.tip = "网络不太稳定，正在重连…" }
                    self.note("WebRTC failed（语音走转发通道，通话继续）")
                    CallAudioPipe.shared.resetHandOver()
                } else {
                    self.weakNet = true
                    if self.tip != "视频通话中" { self.tip = "网络不太稳定，正在重连…" }
                    self.note("WebRTC failed → 兜底切 TRTC")
                    if !self.usingTRTC { await self.startTRTCIfPossible() }
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    if self.phase == .active && !self.usingTRTC && self.pc?.connectionState == .failed {
                        self.failLater("通话连接失败，可能是网络挡住了", hold: 5)
                    }
                }
            case .disconnected:

                self.weakNet = true
                if self.tip != "通话中" && self.tip != "视频通话中" { self.tip = "网络不太稳定，正在重连…" }
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                if self.phase == .active && self.pc?.connectionState == .disconnected {
                    if self.isVideo && !self.usingTRTC {
                        self.note("视频断线 8 秒 → 兜底切 TRTC")
                        await self.startTRTCIfPossible()
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                    }
                    if self.phase == .active && !self.usingTRTC && self.pc?.connectionState == .disconnected {
                        self.finish(tip: "通话已断开")
                    }
                }
            default:
                break
            }
        }
    }

    private func startTRTCIfPossible() async {

        // 被叫必须停在响铃页，等用户明确接听后才能进媒体房间。
        // 提前进房会让双方被 onPeerChanged 误判成“已接通”，接听按钮随之消失。
        guard phase != .incoming, !trtcJoined, !usingTRTC, !callId.isEmpty else { return }
        let bridge = TRTCBridge.shared
        bridge.onJoined = { [weak self] ok in
            guard let self = self else { return }
            guard ok else { return }

            guard self.phase != .idle, self.phase != .incoming, !self.callId.isEmpty else { return }
            self.trtcJoined = true
            self.note("TRTC 已进房（等对端）")

            if TRTCBridge.shared.peerInRoom { self.switchMediaToTRTC() }
        }
        bridge.onPeerChanged = { [weak self] inRoom in
            guard let self = self else { return }
            guard inRoom else { return }
            guard self.phase != .idle, !self.callId.isEmpty else { return }
            if self.phase == .incoming { return }
            if self.trtcJoined {
                if self.isVideo {
                    self.switchMediaToTRTC()
                } else {
                    self.scheduleAudioTRTCTakeover()
                }
            }
            if self.phase != .active {
                Ringtone.shared.stop()
                self.phase = .active
                self.tip = "通话中"
                self.ringTimer?.invalidate()
                self.ringTimer = nil
                self.connectTimer?.invalidate()
                self.connectTimer = nil
                self.startTimer()
                if self.screenSharePending { self.startScreenSharingNow() }
            }
        }
        bridge.onRemoteAudioReady = { [weak self] in
            guard let self = self, self.phase != .idle, !self.callId.isEmpty else { return }
            self.note("TRTC 首音已就绪")
        }
        let ok = await bridge.start(roomSeed: callId, video: isVideo)
        if !ok {
            note("TRTC 用不了：" + bridge.lastError + "（继续走老路）")
        } else {
            note("TRTC 已请求进房（room=" + callId + "）")

            TRTCBridge.shared.standByForLocalMedia()

            let b = TRTCBridge.shared
            Task { await API.shared.callDiag("TRTC 进房 room=" + self.callId
                + " 我方ID=" + b.userId
                + " 对端在房里=" + (b.peerInRoom ? "是" : "否")
                + (b.lastError.isEmpty ? "" : " 错误=" + b.lastError)) }

            if isVideo {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 6_000_000_000)
                    guard let self = self, self.trtcJoined, !self.usingTRTC,
                          self.phase != .idle, !self.callId.isEmpty else { return }
                    self.note("6 秒没等到对端进房，直接切 TRTC（对端可能是旧版本）")
                    self.switchMediaToTRTC()
                }
            }

            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                guard let self = self, !self.usingTRTC, !Task.isCancelled else { return }
                self.note("对端没进 TRTC 房间（可能是旧版本）→ 继续走服务器转发/WebRTC")
            }
        }
    }

    private func scheduleAudioTRTCTakeover() {
        guard !isVideo, !usingTRTC, serverAudioOn, trtcJoined,
              TRTCBridge.shared.peerInRoom, phase != .incoming else { return }
        Task { @MainActor [weak self] in
            /* 对端进房后给 TRTC 媒体路由一个稳定窗口。PCM 继续兜底，
               但不在远端音轨未就绪时立刻拆掉可听的通道。 */
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard let self = self, !Task.isCancelled, !self.isVideo,
                  !self.usingTRTC, self.serverAudioOn, self.trtcJoined,
                  TRTCBridge.shared.peerInRoom, self.phase != .incoming else { return }
            self.switchMediaToTRTC()
        }
    }

    private func switchMediaToTRTC() {
        guard !usingTRTC, phase != .idle, phase != .incoming, !callId.isEmpty else { return }
        usingTRTC = true
        note(isVideo ? "对端也在腾讯云房间里 → 媒体切到 TRTC ✓"
                     : "对端也在腾讯云房间里 → 语音切到 TRTC ✓")

        CallAudioPipe.shared.handOverToTRTC()
        serverAudioOn = false
        audioTrack?.isEnabled = false
        localVideoTrack?.isEnabled = false
        capturer?.stopCapture()
        if screenSharing {
            screenCapturer.stop()
            _ = TRTCBridge.shared.startInAppScreenShare()
        }

        /* handOverToTRTC 返回时 PCM 已同步停止，立即拉起 TRTC；
           不再额外等待 300ms，也不再轮询最长 2 秒。 */
        TRTCBridge.shared.activate()
        TRTCBridge.shared.setMuted(muted)
        TRTCBridge.shared.setSpeaker(speakerOn)
        if phase != .active {
            Ringtone.shared.stop()
            phase = .active
            tip = "通话中"
            ringTimer?.invalidate()
            ringTimer = nil
            connectTimer?.invalidate()
            connectTimer = nil
            startTimer()
        }
    }
}

enum Permission {

    static func ask(_ kind: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: kind) {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { cont in
                AVCaptureDevice.requestAccess(for: kind) { ok in cont.resume(returning: ok) }
            }
        default: return false
        }
    }
}

enum UINotification {

    static func buzz() {
        let gen = UIImpactFeedbackGenerator(style: .heavy)
        gen.impactOccurred()
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }

    static func lightTap() {
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.prepare()
        gen.impactOccurred(intensity: 0.7)
    }
}
