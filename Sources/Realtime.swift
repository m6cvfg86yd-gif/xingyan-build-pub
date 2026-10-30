import Foundation
import SwiftUI
import Network

struct PushEvent: Equatable {
    var type = ""
    var action = ""
    var userId = ""
    var chatId = ""
    var messageId = ""
    var chat: Chat? = nil
    var message: Message? = nil
    var fromId = ""
    var balance: Double? = nil
    var announce = ""
    var user: User? = nil

    var momentUnread: Int? = nil

    var momentNoticeUnread: Int? = nil

    var burnIds: [String] = []

    var momentNotice: MomentNotice? = nil

    var callLevels: [String: Double] = [:]

    var friendRequests: Int? = nil

    var transferFromId = ""
    var transferStatus = ""
    var transferAmount: Double? = nil
    var callId = ""
    var callAction = ""
    var callMedia = ""
    var callPeerId = ""
    var callOwnerId = ""
    var callPeerName = ""
    var callPeerAvatar = ""
    var callError = ""

    var callPeerMuted = false
    var callPeerCameraOff = false
    var callPeerVideo = false

    var callRoomId = ""
    var callChatId = ""
    var callRoster: [GroupCallMember] = []

    var callSDP: String? = nil

    var callAudioData: String? = nil

    var callCandidate: String? = nil

    var callReason = ""

    var pairCode = ""
    var pairDevice = ""

    var callSameNetwork = false

    var roomId = ""
    var liveAction = ""
    var liveText = ""
    var liveFrom = ""
    var watching = 0
    var likes = 0

    var liveFromId = ""
    var liveSigKind = ""
    var liveSDP = ""
    var liveCandidate = ""

    var patFrom = ""
    var patTo = ""
    var tick = 0

    var callActive: Bool? = nil
}

final class RxClock: @unchecked Sendable {
    private let lock = NSLock()
    private var t = Date()
    func touch() { lock.lock(); t = Date(); lock.unlock() }
    var value: Date { lock.lock(); defer { lock.unlock() }; return t }
}

@MainActor
final class Realtime: ObservableObject {
    static let shared = Realtime()

    @Published private(set) var event = PushEvent()
    @Published private(set) var connected = false

    private var socket: URLSessionWebSocketTask?
    private var socketToken = ""
    private var loop: Task<Void, Never>?
    private var tick = 0

    private var plainFallback = false

    static func isLanHost(_ host: String) -> Bool {
        let h = (host.split(separator: ":").first.map(String.init) ?? host).lowercased()
        if h == "localhost" || h == "127.0.0.1" || h == "::1" { return true }
        if h.hasPrefix("10.") || h.hasPrefix("192.168.") { return true }
        if h.hasPrefix("172.") {
            let second = Int(h.split(separator: ".").dropFirst().first.map(String.init) ?? "") ?? 0
            return second >= 16 && second <= 31
        }
        return false
    }
    private var failCount = 0
    private let pathMonitor = NWPathMonitor()
    private let pathQueue = DispatchQueue(label: "com.chris.chatnative.realtime.path")
    private var pathMonitorStarted = false
    private var pathSatisfied = true
    private var lastPathKind = ""

    private var socketUpAt = Date()

    private var pending: PushEvent?
    private var publishTask: Task<Void, Never>?

    private var heartbeat: Task<Void, Never>?
    private let rxClock = RxClock()

    private var ackPending: [String: Int] = [:]
    private var ackTask: Task<Void, Never>?

    func ackDelivery(chatId: String, seq: Int) {
        guard !chatId.isEmpty, seq > 0 else { return }
        if let cur = ackPending[chatId], cur >= seq { return }
        ackPending[chatId] = seq
        if ackTask != nil { return }
        ackTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self = self else { return }
            self.flushAcks()
            self.ackTask = nil
        }
    }

    private func flushAcks() {
        let batch = ackPending
        ackPending.removeAll()
        for (chatId, seq) in batch {
            sendJSON(["type": "ack", "chatId": chatId, "seq": seq])
        }
    }

    func start() {
        ensurePathMonitor()

        let currentToken = API.shared.token
        if socket != nil, connected, socketToken == currentToken { return }
        stop()
        guard !currentToken.isEmpty else { return }
        socketToken = currentToken

        let host = API.shared.server

        let plainHost = host.replacingOccurrences(of: ":5443", with: ":5180")
        let lanOnly = Self.isLanHost(host)
        let raw = (plainFallback && lanOnly) ? "ws://\(plainHost)" : "wss://\(host)"
        guard let url = URL(string: "\(raw)/?token=\(API.shared.token)") else { return }

        var req = URLRequest(url: url)
        req.setValue(AppInfo.build, forHTTPHeaderField: "X-App-Build")

        req.setValue(AppInfo.deviceKind, forHTTPHeaderField: "X-Device-Kind")
        req.setValue(AppInfo.deviceId, forHTTPHeaderField: "X-Device-Id")
        req.setValue(AppInfo.deviceModel, forHTTPHeaderField: "X-Device-Model")
        let task = API.shared.session.webSocketTask(with: req)
        socket = task
        socketUpAt = Date()
        task.resume()

        let clock = rxClock
        loop = Task.detached { [weak self] in
            while !Task.isCancelled {
                do {
                    let message = try await task.receive()
                    var text = ""
                    switch message {
                    case .string(let t): text = t
                    case .data(let d): text = String(data: d, encoding: .utf8) ?? ""
                    @unknown default: break
                    }
                    if !text.isEmpty {
                        clock.touch()

                        if Self.consumeCallAudioIfAny(text) { continue }

                        if let self = self {
                            let t = text
                            let expectedToken = currentToken
                            Task { @MainActor in
                                guard self.socketToken == expectedToken,
                                      API.shared.token == expectedToken else { return }
                                self.handle(t)
                            }
                        }
                    } else {
                        clock.touch()
                    }
                } catch {

                    if Task.isCancelled { break }
                    guard let self = self else { break }
                    await self.onSocketDown(lanOnly: lanOnly)
                    return
                }
            }
        }
        connected = true
        API.shared.markOnline()
        rxClock.touch()

        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                if Task.isCancelled { return }
                guard let self = self else { return }
                if Date().timeIntervalSince(self.rxClock.value) > 35 {
                    self.connected = false
                    self.start()
                    return
                }
                self.sendJSON(["type": "ping"])
            }
        }
    }

    private nonisolated static func consumeCallAudioIfAny(_ text: String) -> Bool {
        guard text.contains("audio") else { return false }
        guard let d = text.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let action = o["action"] as? String,
              action == "audio" || action == "group-audio",
              let b64 = o["data"] as? String,
              let ad = Data(base64Encoded: b64) else { return false }
        CallAudioPipe.shared.play(ad)
        return true
    }

    private func onSocketDown(lanOnly: Bool) async {
        connected = false
        AppLog.info("实时长连接断了（第 " + String(failCount + 1) + " 次），准备重连", net: true)

        if Date().timeIntervalSince(socketUpAt) > 10 { failCount = 0 }

        failCount += 1
        if failCount % 3 == 0, lanOnly { plainFallback.toggle() }

        if failCount % 3 == 0 { _ = API.shared.rotateEndpoint() }

        let ceiling = min(15.0, 1.0 + Double(failCount) * 1.8)
        let wait = Double.random(in: 0.35...ceiling)
        AppLog.info("实时重连 " + String(format: "%.2f", wait) + " 秒后开始", net: true)
        try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        if Task.isCancelled { return }
        start()
    }

    func sendJSON(_ obj: [String: Any]) {
        guard let socket = socket,
              let data = try? JSONSerialization.data(withJSONObject: obj),
              let text = String(data: data, encoding: .utf8) else { return }
        socket.send(.string(text)) { _ in }
    }

    func stop() {
        socketToken = ""
        heartbeat?.cancel()
        heartbeat = nil
        loop?.cancel()
        loop = nil
        publishTask?.cancel()
        publishTask = nil
        pending = nil
        ackTask?.cancel()
        ackTask = nil
        ackPending.removeAll()
        event = PushEvent()
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        connected = false
    }

    private func ensurePathMonitor() {
        guard !pathMonitorStarted else { return }
        pathMonitorStarted = true
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let ok = path.status == .satisfied
            let kind: String
            if path.usesInterfaceType(.wifi) { kind = "wifi" }
            else if path.usesInterfaceType(.cellular) { kind = "cellular" }
            else if path.usesInterfaceType(.wiredEthernet) { kind = "wired" }
            else { kind = "other" }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let recovered = ok && !self.pathSatisfied
                let switched = ok && !self.lastPathKind.isEmpty && kind != self.lastPathKind
                self.pathSatisfied = ok
                self.lastPathKind = kind
                if switched, !API.shared.token.isEmpty {
                    AppLog.info("网络线路已切换，重新探测并建立长连接", net: true)
                    self.failCount = 0
                    self.socket?.cancel(with: .goingAway, reason: nil)
                    self.socket = nil
                    let probe = await API.shared.probe("/api/version")
                    if !probe.hasPrefix("成功 HTTP 2") {
                        _ = API.shared.rotateEndpoint(force: true)
                    }
                    self.start()
                    return
                }
                if recovered, !API.shared.token.isEmpty, !self.connected {
                    AppLog.info("网络已恢复，立即重建实时连接", net: true)
                    self.failCount = 0
                    self.socket?.cancel(with: .goingAway, reason: nil)
                    self.socket = nil
                    self.start()
                }
            }
        }
        pathMonitor.start(queue: pathQueue)
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        var ev = PushEvent()
        ev.type = (obj["type"] as? String) ?? ""
        if ev.type == "ready" { API.shared.markOnline() }
        ev.action = (obj["action"] as? String) ?? ""
        ev.userId = (obj["userId"] as? String) ?? ""
        ev.chatId = (obj["chatId"] as? String) ?? ""
        ev.messageId = (obj["messageId"] as? String) ?? ""
        if let rawChat = obj["chat"] as? [String: Any],
           let chatData = try? JSONSerialization.data(withJSONObject: rawChat),
           let decodedChat = try? JSONDecoder().decode(Chat.self, from: chatData) {
            ev.chat = decodedChat
        }
        if let m = obj["message"] as? [String: Any] {
            ev.fromId = (m["senderId"] as? String) ?? ""
            if let messageData = try? JSONSerialization.data(withJSONObject: m) {
                ev.message = try? JSONDecoder().decode(Message.self, from: messageData)
            }

            if ev.chatId.isEmpty { ev.chatId = (m["chatId"] as? String) ?? "" }

            if let cid = m["chatId"] as? String ?? obj["chatId"] as? String,
               let sq = (m["seq"] as? NSNumber)?.intValue {
                ackDelivery(chatId: cid, seq: sq)
            }
        }
        if let b = obj["balance"] as? Double { ev.balance = b }
        else if let b = obj["balance"] as? Int { ev.balance = Double(b) }

        if let u = obj["user"] as? [String: Any],
           let d = try? JSONSerialization.data(withJSONObject: u),
           let decoded = try? JSONDecoder().decode(User.self, from: d) {
            ev.user = decoded
        }
        ev.announce = (obj["text"] as? String) ?? ""

        ev.patFrom = (obj["userId"] as? String) ?? ""
        ev.patTo = (obj["targetId"] as? String) ?? ""

        if let ids = obj["ids"] as? [String] { ev.burnIds = ids }

        if let lv = obj["levels"] as? [String: Any] {
            var out: [String: Double] = [:]
            lv.forEach { k, v in if let n = v as? NSNumber { out[k] = n.doubleValue } }
            ev.callLevels = out
        }

        ev.pairCode = (obj["pairCode"] as? String) ?? ""
        ev.pairDevice = (obj["pairDevice"] as? String) ?? ""
        if ev.type == "pair", !ev.pairCode.isEmpty {
            PushCenter.shared.showPairRequest(code: ev.pairCode, device: ev.pairDevice)
        }

        if ev.type == "kick" {
            let dev = (obj["device"] as? String) ?? ""
            let at = (obj["at"] as? Double) ?? 0
            OtherLogin.shared.trigger(device: dev, atMillis: at)
        }
        if let ca = obj["callActive"] as? Bool { ev.callActive = ca }
        if let n = obj["momentUnread"] as? Int { ev.momentUnread = n }
        if let n = obj["momentNoticeUnread"] as? Int { ev.momentNoticeUnread = n }

        if let n = obj["notice"] as? [String: Any] { ev.momentNotice = MomentNotice(json: n) }
        if let n = obj["friendRequests"] as? Int { ev.friendRequests = n }

        if let t = obj["transfer"] as? [String: Any] {
            ev.transferFromId = (t["fromId"] as? String) ?? ""
            ev.transferStatus = (t["status"] as? String) ?? ""
            if let a = t["amount"] as? Double { ev.transferAmount = a }
            else if let a = t["amount"] as? Int { ev.transferAmount = Double(a) }
        }

        ev.callId = (obj["callId"] as? String) ?? ""
        ev.callAction = (obj["action"] as? String) ?? ""
        ev.callMedia = (obj["media"] as? String) ?? ""
        ev.callPeerId = (obj["peerId"] as? String) ?? ""
        ev.callOwnerId = (obj["ownerId"] as? String) ?? ""
        ev.callPeerName = (obj["peerName"] as? String) ?? ""
        ev.callPeerAvatar = (obj["peerAvatar"] as? String) ?? ""
        ev.callError = (obj["error"] as? String) ?? ""
        ev.callPeerMuted = (obj["muted"] as? Bool) ?? false
        ev.callPeerCameraOff = (obj["camOff"] as? Bool) ?? false
        ev.callPeerVideo = (obj["video"] as? Bool) ?? false
        ev.callRoomId = (obj["roomId"] as? String) ?? ""
        ev.callChatId = (obj["chatId"] as? String) ?? ""
        if let arr = obj["roster"] as? [[String: Any]] {
            ev.callRoster = arr.map {
                GroupCallMember(userId: ($0["userId"] as? String) ?? "",
                                name: ($0["name"] as? String) ?? "",
                                avatar: ($0["avatar"] as? String) ?? "",
                                muted: ($0["muted"] as? Bool) ?? false)
            }
        }
        ev.callReason = (obj["reason"] as? String) ?? ""
        if let same = obj["same"] as? Bool { ev.callSameNetwork = same }

        ev.roomId = (obj["roomId"] as? String) ?? ""
        ev.liveAction = (obj["action"] as? String) ?? ""
        ev.liveText = (obj["text"] as? String) ?? ""
        ev.liveFrom = (obj["from"] as? String) ?? ""
        if let w = obj["watching"] as? Int { ev.watching = w }
        if let l = obj["likes"] as? Int { ev.likes = l }
        ev.liveFromId = (obj["from"] as? String) ?? ""
        ev.liveSigKind = (obj["sigKind"] as? String) ?? ""
        if let sdp = obj["sdp"] as? [String: Any] { ev.liveSDP = (sdp["sdp"] as? String) ?? "" }
        if let cand = obj["candidate"] as? [String: Any],
           let d2 = try? JSONSerialization.data(withJSONObject: cand),
           let t2 = String(data: d2, encoding: .utf8) { ev.liveCandidate = t2 }

        if let sdp = obj["sdp"] as? [String: Any] { ev.callSDP = (sdp["sdp"] as? String) ?? "" }
        if let audio = obj["data"] as? String, !audio.isEmpty { ev.callAudioData = audio }
        if let cand = obj["candidate"] as? [String: Any],
           let data = try? JSONSerialization.data(withJSONObject: cand),
           let text = String(data: data, encoding: .utf8) {
            ev.callCandidate = text
        }

        let important = ["ui", "friend", "call", "transfer", "transferRemind",
                         "toast", "moment", "profile", "pair"]
        if important.contains(ev.type) {
            pending = nil
            tick += 1
            ev.tick = tick
            event = ev
            return
        }
        if publishTask == nil {
            tick += 1
            ev.tick = tick
            event = ev
            publishTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let self = self, !Task.isCancelled else { return }
                self.publishTask = nil
                if let p = self.pending {
                    self.pending = nil
                    self.tick += 1
                    var merged = p
                    merged.tick = self.tick
                    self.event = merged
                }
            }
        } else {
            pending = ev
        }
    }
}
