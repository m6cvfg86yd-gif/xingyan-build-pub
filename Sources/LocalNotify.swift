import SwiftUI
import UIKit
import UserNotifications
import AudioToolbox

enum LocalNotify {
    static var settings = NotifySettings()
    private static var messageSoundID: SystemSoundID = 0
    private static let messageSoundName = "xingyan_message.wav"

    static func prepare() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        prepareCallCategory()
    }

    static let callCategory = "chris.call"

    static func prepareCallCategory() {
        let answer = UNNotificationAction(identifier: "call.answer", title: "接听", options: [.foreground])
        let reject = UNNotificationAction(identifier: "call.reject", title: "拒绝", options: [.destructive])
        let cat = UNNotificationCategory(identifier: callCategory, actions: [answer, reject],
                                         intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([cat])
    }

    static func incomingCall(callId: String, peerName: String, video: Bool) {
        let c = UNMutableNotificationContent()
        c.title = video ? "视频通话" : "语音通话"
        c.body = (peerName.isEmpty ? "有人" : peerName) + "邀请你" + (video ? "视频" : "语音") + "通话"
        c.sound = .default
        c.categoryIdentifier = callCategory
        c.userInfo = ["callId": callId, "kind": "call"]
        if #available(iOS 15.0, *) { c.interruptionLevel = .timeSensitive }
        let req = UNNotificationRequest(identifier: "call-" + callId, content: c, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    static func clearCall(callId: String) {
        guard !callId.isEmpty else { return }
        let ids = ["call-" + callId]
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    static func refresh() async {
        settings = await API.shared.notifySettings()
    }

    static func mutedNow() -> Bool {
        let a = settings.muteStart, b = settings.muteEnd
        guard !a.isEmpty, !b.isEmpty else { return false }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        guard let s = f.date(from: a), let e = f.date(from: b) else { return false }
        let cal = Calendar.current
        let now = cal.dateComponents([.hour, .minute], from: Date())
        let cur = (now.hour ?? 0) * 60 + (now.minute ?? 0)
        let sv = cal.dateComponents([.hour, .minute], from: s)
        let ev = cal.dateComponents([.hour, .minute], from: e)
        let start = (sv.hour ?? 0) * 60 + (sv.minute ?? 0)
        let end = (ev.hour ?? 0) * 60 + (ev.minute ?? 0)
        if start == end { return false }
        return start < end ? (cur >= start && cur < end) : (cur >= start || cur < end)
    }

    static func incoming(title: String,
                         body: String,
                         chatId: String = "",
                         msgId: String = "",
                         badge: Int = 0,
                         count: Int = 1,
                         isGroup: Bool = false,
                         sender: String = "") {
        guard settings.on else { return }
        guard !mutedNow() else { return }
        if settings.sound { playMessageSound() }
        if settings.vibrate { AudioServicesPlaySystemSound(kSystemSoundID_Vibrate) }
        let iconBadge = max(1, min(999, badge))
        DispatchQueue.main.async {
            UIApplication.shared.applicationIconBadgeNumber = iconBadge
        }
        // 微信在前台只更新会话与角标，不连续弹三条系统横幅。
        guard UIApplication.shared.applicationState != .active else { return }
        let mergedCount = max(1, min(999, count))
        let shownTitle = mergedCount > 1
            ? title + " · \(mergedCount) " + Tr("条新消息")
            : title
        let cleanBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let senderPrefix = sender + "："
        let shownBody = isGroup && !sender.isEmpty
            && !cleanBody.hasPrefix(senderPrefix)
            ? senderPrefix + cleanBody
            : cleanBody
        let c = UNMutableNotificationContent()
        c.title = shownTitle
        c.body = settings.showDetail ? shownBody : Tr("你收到一条新消息")
        if settings.sound {
            c.sound = UNNotificationSound(
                named: UNNotificationSoundName(messageSoundName)
            )
        }

        c.badge = NSNumber(value: iconBadge)
        c.summaryArgument = sender.isEmpty ? title : sender
        c.summaryArgumentCount = mergedCount

        if !chatId.isEmpty {
            c.userInfo = ["chatId": chatId, "messageId": msgId]
        }

        if !chatId.isEmpty { c.threadIdentifier = chatId }
        let id: String
        if !chatId.isEmpty { id = "chat-" + chatId }
        else if !msgId.isEmpty { id = "msg-" + msgId }
        else { id = UUID().uuidString }
        let req = UNNotificationRequest(identifier: id, content: c, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    private static func playMessageSound() {
        if messageSoundID == 0,
           let url = Bundle.main.url(forResource: "xingyan_message",
                                     withExtension: "wav") {
            AudioServicesCreateSystemSoundID(url as CFURL, &messageSoundID)
        }
        if messageSoundID != 0 {
            AudioServicesPlaySystemSound(messageSoundID)
        } else {
            AudioServicesPlaySystemSound(1007)
        }
    }

    private static var lastNotified: [String: String] = [:]
    private static var lastNotifiedLoaded = false

    private static func loadLastNotified() {
        guard !lastNotifiedLoaded else { return }
        lastNotifiedLoaded = true
        if let d = UserDefaults.standard.dictionary(forKey: "chris.lastNotified") as? [String: String] {
            lastNotified = d
        }
    }

    private static func saveLastNotified() {
        UserDefaults.standard.set(lastNotified, forKey: "chris.lastNotified")
    }

    static func shouldNotify(chatId: String, msgId: String, at: String?) -> Bool {
        loadLastNotified()
        guard !chatId.isEmpty else { return true }
        if !msgId.isEmpty, lastNotified[chatId] == msgId { return false }
        if let d = TimeFmt.date(at), Date().timeIntervalSince(d) > 120 { return false }
        if !msgId.isEmpty { lastNotified[chatId] = msgId; saveLastNotified() }
        return true
    }

    static func clearChat(_ chatId: String) {
        guard !chatId.isEmpty else { return }
        UNUserNotificationCenter.current().getDeliveredNotifications { list in
            let ids = list.filter { ($0.request.content.userInfo["chatId"] as? String) == chatId }
                .map { $0.request.identifier }
            if !ids.isEmpty {
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
            }
        }
        loadLastNotified()
        lastNotified[chatId] = nil
        saveLastNotified()
    }
}
