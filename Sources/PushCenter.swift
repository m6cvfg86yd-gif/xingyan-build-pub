import SwiftUI
import UIKit
import UserNotifications

final class PushCenter: NSObject, ObservableObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let shared = PushCenter()

    private static var supportedOrientations: UIInterfaceOrientationMask = .portrait

    @Published private(set) var token = ""

    @Published private(set) var authorized = false

    @Published private(set) var lastError = "登记时间"
    @Published private(set) var registeredAt = ""

    override init() { super.init() }

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.supportedOrientations
    }

    @MainActor
    static func setMusicLandscape(_ enabled: Bool) {
        supportedOrientations = enabled
            ? [.portrait, .landscapeLeft, .landscapeRight]
            : .portrait

        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first
        else { return }

        scene.requestGeometryUpdate(
            .iOS(interfaceOrientations: enabled
                 ? [.portrait, .landscapeLeft, .landscapeRight]
                 : .portrait)
        )
    }

    @MainActor
    static func forceMusicPortrait() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first
        else { return }

        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
    }

    @MainActor
    static func forceMusicLandscape() {
        supportedOrientations = [.portrait, .landscapeLeft, .landscapeRight]
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first
        else { return }

        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
    }

    func application(_ application: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        guard url.isFileURL else { return false }
        ExternalFileInbox.shared.accept([url])
        return true
    }

    func start() {
        UNUserNotificationCenter.current().getNotificationSettings { s in
            let ok = (s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
                      || s.authorizationStatus == .ephemeral)
            DispatchQueue.main.async { self.authorized = ok }

            self.report(s)
            if s.authorizationStatus == .notDetermined {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    DispatchQueue.main.async { self.authorized = granted }
                    if granted { DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() } }
                    UNUserNotificationCenter.current().getNotificationSettings { s2 in self.report(s2) }
                }
            } else if ok {
                DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
            }
        }
    }

    private func report(_ s: UNNotificationSettings) {
        var status = "unknown"
        switch s.authorizationStatus {
        case .authorized: status = "authorized"
        case .denied: status = "denied"
        case .provisional: status = "provisional"
        case .ephemeral: status = "ephemeral"
        case .notDetermined: status = "not-determined"
        @unknown default: status = "unknown"
        }
        let badgeOn = (s.badgeSetting != .disabled)
        let alertOn = (s.alertSetting != .disabled)
        let soundOn = (s.soundSetting != .disabled)
        Task {
            await API.shared.reportPushSettings(status: status, badge: badgeOn,
                                                alert: alertOn, sound: soundOn,
                                                token: token, sandbox: PushCenter.isSandbox)
        }
    }

    func uploadIfPossible() {
        guard !token.isEmpty else { return }
        Task {
            await API.shared.registerPushToken(token, sandbox: PushCenter.isSandbox)
            await MainActor.run {
                let f = DateFormatter()
                f.dateFormat = "MM-dd HH:mm"
                self.registeredAt = f.string(from: Date())
            }
        }
    }

    static var isSandbox: Bool {
        #if DEBUG
        return true
        #else
        let receipt = Bundle.main.appStoreReceiptURL?.lastPathComponent ?? ""
        return receipt.contains("sandboxReceipt")
        #endif
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        DispatchQueue.main.async {
            self.token = hex
            self.lastError = ""
        }
        uploadIfPossible()
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        DispatchQueue.main.async { self.lastError = error.localizedDescription }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let info = notification.request.content.userInfo
        guard (info["kind"] as? String) == "call",
              let callId = info["callId"] as? String, !callId.isEmpty else {
            completionHandler([.banner, .sound, .list])
            return
        }

        Task { @MainActor in
            let c = CallCenter.shared
            let alreadyRinging = (c.phase == .incoming && c.callId == callId)
            completionHandler(alreadyRinging ? [] : [.banner, .sound, .list])
        }
    }

    func showPairRequest(code: String, device: String) {
        guard !code.isEmpty else { return }
        let c = UNMutableNotificationContent()
        c.title = "登录确认"
        c.body = (device.isEmpty ? "有设备" : "「" + device + "」")
            + "请求登录你的星言账号，点这里确认"
        c.sound = .default
        c.userInfo = ["kind": "pair", "code": code]
        let req = UNNotificationRequest(identifier: "pair-" + code, content: c, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo

        if response.actionIdentifier == "call.answer" {
            let callId = (info["callId"] as? String) ?? ""
            Task { @MainActor in
                for _ in 0..<25 {
                    if UIApplication.shared.applicationState == .active { break }
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
                CallCenter.shared.resumeFromPush(callId: callId, answer: true)
            }
            completionHandler()
            return
        }
        if response.actionIdentifier == "call.reject" {
            let callId = (info["callId"] as? String) ?? ""
            Task { @MainActor in
                CallCenter.shared.rejectFromPush(callId: callId)
            }
            completionHandler()
            return
        }

        if (info["kind"] as? String) == "call" {
            let callId = (info["callId"] as? String) ?? ""
            Task { @MainActor in
                for _ in 0..<25 {
                    if UIApplication.shared.applicationState == .active { break }
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
                try? await Task.sleep(nanoseconds: 800_000_000)
                if callId.isEmpty {
                    CallCenter.shared.restore()
                } else {
                    CallCenter.shared.resumeFromPush(callId: callId, answer: false)
                }
            }
        }

        if (info["kind"] as? String) == "pair",
           let code = info["code"] as? String, !code.isEmpty {
            NotificationCenter.default.post(name: .chrisOpenPair, object: nil, userInfo: ["code": code])
        }
        if let chatId = info["chatId"] as? String, !chatId.isEmpty {
            NotificationCenter.default.post(name: .chrisOpenChat, object: nil, userInfo: ["chatId": chatId])
        }
        completionHandler()
    }
}

extension Notification.Name {

    static let chrisOpenChat = Notification.Name("chris.openChat")

    static let chrisOpenPair = Notification.Name("chris.openPair")
}
