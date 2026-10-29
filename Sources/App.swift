import SwiftUI
import LocalAuthentication
import UIKit
import CoreImage

@MainActor
final class AppState: ObservableObject {
    @Published var booting = true

    @Published var pairApproveCode = ""

    @Published var nearbyDropInvite: NearbyDropInvite?

    @Published var offline = false

    /// 实时事件先上屏的会话摘要；旧列表响应不能用空值把它冲掉。
    private var optimisticChats: [String: Chat] = [:]
    private var optimisticAt: [String: Date] = [:]
    /// 左滑隐藏/删除请求还没落库时，先挡住轮询把旧会话行加回来。
    private var locallyHiddenChats: Set<String> = []
    private var locallyHiddenAt: [String: Date] = [:]
    /// 刚读过的会话会短暂挡住分片旧快照，避免服务端尚未追上阅读游标时红点闪回。
    private var locallyReadAt: [String: Date] = [:]
    private var suspiciousChatDropCount = 0

    init() {

        if let cached = Self.cachedUser(), !cached.id.isEmpty {
            chats = LocalStore.cachedChatList(userId: cached.id)
        }
        applyCachedUIConfig()
    }

    func checkReachability() async {
        await API.shared.ping()
        if offline != API.shared.offline { offline = API.shared.offline }
    }

    @Published var sliderLogin = true
    @Published var me: User? {
        didSet {
            rememberLastUser()

            if me != nil { startDotWatch() } else { dotTask?.cancel() }
        }
    }

    @Published var lastAvatar: String = UserDefaults.standard.string(forKey: "chris.lastAvatar") ?? ""
    @Published var lastName: String = UserDefaults.standard.string(forKey: "chris.lastName") ?? ""

    @Published var needConfirmLogin = false

    @Published var showSavedLogin = false

    @Published var accounts: [SavedAccount] = AccountStore.load()

    @Published var friendRequests = 0
    @Published var localOutgoingFriendRequests: [User] = []

    @Published var badges: [String: String] = [:]

    @Published var forcedUpdate: AppUpdateInfo? = nil

    @Published var optionalUpdate: AppUpdateInfo? = nil

    @Published var noticeAlert: NoticeInfo? = nil

    static var buildNumber: Int {
        let s = AppInfo.build
        guard let r = s.range(of: "B") else { return 0 }
        let digits = s[r.upperBound...].prefix { $0.isNumber }
        return Int(digits) ?? 0
    }

    static func buildNumberOf(_ v: String?) -> Int {
        let s = String(v ?? "")
        guard let r = s.range(of: "B") else { return 0 }
        let digits = s[r.upperBound...].prefix { $0.isNumber }
        return Int(digits) ?? 0
    }

    private static func parseTime(_ s: String?) -> Date? {
        let t = String(s ?? "").trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        for fmt in ["yyyy-MM-dd HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] {
            f.dateFormat = fmt
            if let d = f.date(from: t) { return d }
        }
        return nil
    }

    private static func inWindow(start: String?, end: String?) -> Bool {
        let now = Date()
        if let s = parseTime(start), now < s { return false }
        if let e = parseTime(end), now > e { return false }
        return true
    }

    private static func versionInRange(_ n: NoticeInfo) -> Bool {
        let mine = buildNumber
        let lo = buildNumberOf(n.minVersion)
        let hi = buildNumberOf(n.maxVersion)
        if lo > 0 && mine < lo { return false }
        if hi > 0 && mine > hi { return false }
        return true
    }

    private static func noticeKey(_ n: NoticeInfo) -> String {
        let s = (n.title ?? "") + "|" + (n.content ?? "")
        return String(s.prefix(40)) + "-" + String(s.count)
    }
    private static func dayKey() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    func checkVersionAndNotice() async {
        let (info, notice) = await API.shared.versionInfo()
        if let info = info {
            let want = Self.buildNumberOf(info.version)
            if want > Self.buildNumber {
                if info.force == true {
                    forcedUpdate = info
                } else {
                    let key = "chris.update.seen." + String(want)
                    if !UserDefaults.standard.bool(forKey: key) { optionalUpdate = info }
                }
            }
        }
        if let n = notice, !(n.content ?? "").isEmpty,
           Self.inWindow(start: n.startAt, end: n.endAt), Self.versionInRange(n) {
            let kind = n.kind ?? "popup"
            let key = "chris.notice.seen." + Self.noticeKey(n)
            switch kind {
            case "once":
                if !UserDefaults.standard.bool(forKey: key) { noticeAlert = n }
            case "daily":
                if UserDefaults.standard.string(forKey: key) != Self.dayKey() { noticeAlert = n }
            default:
                noticeAlert = n
            }
        }
    }

    func dismissNotice() {
        if let n = noticeAlert {
            let kind = n.kind ?? "popup"
            let key = "chris.notice.seen." + Self.noticeKey(n)

            if kind == "once" { UserDefaults.standard.set(true, forKey: key) }
            if kind == "daily" { UserDefaults.standard.set(Self.dayKey(), forKey: key) }
        }
        noticeAlert = nil
    }

    func dismissOptionalUpdate() {
        if let u = optionalUpdate {
            let want = Self.buildNumberOf(u.version)
            if want > 0 { UserDefaults.standard.set(true, forKey: "chris.update.seen." + String(want)) }
        }
        optionalUpdate = nil
    }

    func openUpdate(_ u: AppUpdateInfo) {
        let fallback = (u.downloadPage?.isEmpty == false ? u.downloadPage! : (u.url ?? ""))
        Task {

            let signed = await API.shared.appDownloadTicket()
            let s = signed ?? fallback

            if let url = URL(string: s) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
            dismissOptionalUpdate()
        }
    }

    func showDot(_ key: String, auto: Bool) -> Bool {
        switch badges[key] ?? "auto" {
        case "on": return true
        case "off": return false
        default: return auto
        }
    }

    func loadBadges() async {
        badges = await API.shared.badgeConfig()
    }
    @Published var chats: [Chat] = []

    @Published var contacts: [User] = [] {
        didSet { rebuildContactIndex() }
    }
    private var contactIndex: [String: User] = [:]
    private func rebuildContactIndex() {
        var m = [String: User](minimumCapacity: contacts.count)
        for u in contacts { m[u.id] = u }
        contactIndex = m
    }
    @Published var moments: [Moment] = []

    @Published var momentsUnread = 0

    @Published var momentNoticeUnread = 0

    @Published var quickChips: [QuickChip] = QuickChip.defaults

    @Published var plusButton = PlusButtonCfg()

    @Published var langVersion = 0

    @Published var splashDone = false

    @Published var defaultChatBackground = ""

    @Published var splashImage = ""
    @Published var toast: String?

    @Published var payScan: PayScanInfo?

    @Published var payScanText: String = ""

    @Published var scanCardUser: User?
    @Published var scanWebURL: String?
    @Published var scanTextResult: String?

    @Published var openChat: Chat?

    @Published var pendingPushChatId: String?

    @Published var wantChatsTab = false

    func openChatViaList(_ c: Chat) {
        wantChatsTab = true
        pendingPushChatId = c.id
    }

    @Published var openMiniApp: MiniApp?
    /// 从小程序返回时恢复原来的聊天；小程序始终只由一个全屏窗口承载。
    @Published var resumeChatAfterMiniApp: Chat?

    func launchMiniApp(_ mini: MiniApp, returningTo chat: Chat? = nil) {
        resumeChatAfterMiniApp = chat
        if openChat != nil {
            openChat = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) { [weak self] in
                self?.openMiniApp = mini
            }
        } else {
            openMiniApp = mini
        }
    }

    func miniAppDidClose() {
        openMiniApp = nil
        guard let chat = resumeChatAfterMiniApp else { return }
        resumeChatAfterMiniApp = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            self?.openChat = chat
        }
    }
    @Published var loadingChats = false
    @Published var loadError: String?

    @Published var uiVersion = 0
    /// 登录成功时单独推进根视图身份，避免依赖回到前台后的配置刷新。
    @Published private(set) var authVersion = 0

    @Published var tabBarDepth = 0

    @Published var floorFull = false
    var tabBarHidden: Bool { tabBarDepth > 0 || floorFull }

    @Published var appearance: String = UserDefaults.standard.string(forKey: "chris.appearance") ?? "auto"
    func setAppearance(_ v: String) {
        appearance = v
        UserDefaults.standard.set(v, forKey: "chris.appearance")
    }
    var preferredScheme: ColorScheme? {
        appearance == "light" ? .light : (appearance == "dark" ? .dark : nil)
    }
    private var lastUIConfig = ""
    private var refreshTask: Task<Void, Never>?
    private var accountEpoch = 0

    private var uiRetryScheduled = false

    private static let uiCacheKey = "chris.uiConfigJSON"
    private static let uiIconCacheKey = "chris.uiIconsJSON"

    private func coalesce(_ work: @escaping () async -> Void) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled { return }
            await work()
            self?.refreshTask = nil
        }
    }

    /// 切号时先清掉账号作用域的数据和旧任务，避免旧账号响应落到新账号界面。
    private func beginAccountTransition() {
        accountEpoch += 1
        refreshTask?.cancel()
        refreshTask = nil
        syncInFlight = false
        syncing = false
        syncText = ""
        loadingChats = false
        loadError = nil
        optimisticChats.removeAll()
        optimisticAt.removeAll()
        locallyHiddenChats.removeAll()
        locallyHiddenAt.removeAll()
        suspiciousChatDropCount = 0
        prefetched.removeAll()
        chats = []
        contacts = []
        moments = []
        momentsUnread = 0
        momentNoticeUnread = 0
        friendRequests = 0
        localOutgoingFriendRequests = []
        openChat = nil
        pendingPushChatId = nil
        wantChatsTab = false
        resumeChatAfterMiniApp = nil
        openMiniApp = nil
        scanCardUser = nil
        scanWebURL = nil
        scanTextResult = nil
        payScan = nil
        payScanText = ""
        tabBarDepth = 0
        floorFull = false
        OtherLogin.shared.reset()
        CallCenter.shared.resetForAccountChange()
        GrowthStore.shared.stop()
        Realtime.shared.stop()
        KeepAlive.shared.stop()
        syncIconBadge()
    }

    private func isCurrentAccount(_ epoch: Int) -> Bool {
        epoch == accountEpoch && me != nil && !API.shared.token.isEmpty
    }

    func handle(_ ev: PushEvent) {
        guard me != nil else { return }

        if let u = ev.user, u.id == me?.id {
            me = u
            coalesce { [weak self] in
                await self?.loadChats()
                await self?.loadContacts()
            }
            return
        }
        if let b = ev.balance, var me = me {
            me.balance = b
            self.me = me
        }
        if !ev.announce.isEmpty && ev.type == "announce" {
            show("系统公告：" + ev.announce)
        }
        if let n = ev.momentUnread { momentsUnread = n }
        if let n = ev.momentNoticeUnread { momentNoticeUnread = n }
        if let n = ev.friendRequests {

            let changed = n != friendRequests
            friendRequests = n
            if changed { coalesce { [weak self] in await self?.loadContacts() } }
        }
        switch ev.type {
        case "message", "chat":
            if ev.type == "chat", ev.action == "removed" || ev.action == "deleted" {
                hideChatLocally(ev.chatId)
            }

            if let incoming = ev.chat {
                applyRealtimeChat(incoming)
            } else if let message = ev.message {
                applyRealtimeMessage(message, chatId: ev.chatId)
            }
            let cid = ev.chatId
            coalesce { [weak self] in
                await self?.loadChats()
                guard let self = self else { return }
                if !cid.isEmpty, let c = self.chats.first(where: { $0.id == cid }) {
                    if c.muted == true { return }

                    let mid = c.lastMessage?.id ?? ""
                    guard LocalNotify.shouldNotify(chatId: c.id, msgId: mid,
                                                   at: c.lastMessage?.createdAt) else { return }
                    LocalNotify.incoming(title: c.name,
                                         body: c.lastMessage?.preview ?? "你收到一条新消息",
                                         chatId: c.id,
                                         msgId: mid,
                                         badge: unreadForIcon)
                } else {
                    LocalNotify.incoming(title: "新消息", body: "你收到一条新消息", badge: unreadForIcon)
                }
            }
        case "transfer":

            if ev.transferStatus == "received", ev.transferFromId == me?.id,
               let a = ev.transferAmount {
                show("对方已收款 ¥" + money(a))
            }
            coalesce { [weak self] in await self?.loadChats() }
        case "moment":
            momentsUnread = max(1, momentsUnread)
            coalesce { [weak self] in await self?.loadMoments() }
        case "moment-notice":

            if let n = ev.momentNoticeUnread { momentNoticeUnread = n }
            else if ev.momentNotice != nil { momentNoticeUnread += 1 }
            if let nt = ev.momentNotice {
                let who = nt.name ?? "有人"
                let what: String
                switch nt.kind ?? "" {
                case "like": what = "赞了你的朋友圈"
                case "reply": what = "回复了你"
                default: what = "评论了你的朋友圈"
                }
                LocalNotify.incoming(title: Tr("生活圈"), body: who + what, badge: unreadForIcon)
            }
        case "friend", "presence", "profile":
            if ev.type == "friend", ev.action == "accepted", let user = ev.user {
                applyFriendAccepted(user)
                refreshTask?.cancel()
                refreshTask = Task { [weak self] in
                    await self?.loadContacts()
                    await self?.loadChats()
                    self?.refreshTask = nil
                }
            } else if ev.type == "friend", ev.action == "removed", !ev.userId.isEmpty {
                applyFriendRemoved(userId: ev.userId)
                coalesce { [weak self] in
                    await self?.loadContacts()
                    await self?.loadChats()
                }
            } else {
                if ev.type == "profile", let user = ev.user {
                    applyProfileUpdate(user)
                }
                coalesce { [weak self] in await self?.loadContacts() }
            }
        case "toast":

            if !ev.announce.isEmpty { show(ev.announce) }
        case "ui":
            /* 后台改标题、行文案和界面样式后会发送 ui 事件。
               以前这里被忽略，必须杀进程重开才能看到；现在当场重拉配置。 */
            Task { [weak self] in await self?.refreshUI(force: true) }
        case "transferRemind":

            show(ev.announce.isEmpty ? "对方提醒你确认收款" : ev.announce)
            coalesce { [weak self] in await self?.loadChats() }
        case "ready":

            coalesce { [weak self] in
                await self?.refreshUI(force: true)
                await self?.loadChats()
                await self?.syncRecentMessages(chatCount: 20, limit: 50)
            }
        default:
            break
        }
    }

    private var toastTask: Task<Void, Never>?

    func show(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_900_000_000)
            if !Task.isCancelled { self?.toast = nil }
        }
    }

    func boot() async {
        guard !didInitialBoot else { return }
        didInitialBoot = true
        CrashCatcher.note("启动", "3 boot 开始")
        // 本地已有账号时先放行到上次账号页，网络校验放到后台完成。
        applyCachedUIConfig()
        let activeName = UserDefaults.standard.string(forKey: "chris.activeUsername") ?? ""
        let savedUser = activeName.isEmpty
            ? AppState.cachedUser()
            : AppState.cachedUser(username: activeName)
        if !API.shared.token.isEmpty, savedUser != nil {
            me = savedUser
            showSavedLogin = false
            needConfirmLogin = false
            booting = false
        } else if API.shared.token.isEmpty {
            booting = false
            return
        }

            let watchdog = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled, booting else { return }
            if me == nil, let cached = AppState.cachedUser() {
                me = cached
                needConfirmLogin = false
            }
            booting = false
        }
        defer { watchdog.cancel() }
        await refreshUI(force: true)
        CrashCatcher.note("启动", "4 界面配置就绪")
        await loadBadges()

        await checkVersionAndNotice()
        if API.shared.token.isEmpty {
            showSavedLogin = false
            booting = false
            return
        }
        do {
            let s = try await API.shared.session()
            CrashCatcher.note("启动", "5 会话查询返回")
            if s.ok, let user = s.user {
                me = user
                rememberLastUser()
                Task { await API.shared.touchCurrentDevice() }

                needConfirmLogin = false
                booting = false
                Task {
                await refreshAll()
                Realtime.shared.start()
            }
        } else {
            API.shared.clearToken()
            me = nil
                needConfirmLogin = false
                showSavedLogin = false
            }
        } catch {

            if let cached = AppState.cachedUser() {
                me = cached
                needConfirmLogin = false
                booting = false
            }

            Task { await refreshAll() }
        }
        booting = false
    }

    static func cachedUser(username: String? = nil) -> User? {
        let key: String
        if let username, !username.isEmpty {
            key = "chris.lastUserJSON." + username.lowercased()
        } else {
            key = "chris.lastUserJSON"
        }
        guard let s = UserDefaults.standard.string(forKey: key),
              let d = s.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(User.self, from: d)
    }

    func refreshUI(force: Bool = false) async {
        let cfg = await API.shared.uiConfig()

        if cfg.ui.isEmpty && cfg.icons.isEmpty {
            applyCachedUIConfig()
            scheduleUIRetry()
            return
        }
        let stamp = String(describing: cfg.ui.sorted { $0.key < $1.key })
            + "|icons:" + String(describing: cfg.icons.sorted { $0.key < $1.key })
        if force || stamp != lastUIConfig {
            lastUIConfig = stamp
            UIConfig.apply(cfg.ui)
            IconOverrides.map = cfg.icons
            cacheUIConfig(cfg.ui, cfg.icons)
            uiVersion += 1
        }

        if let b = await API.shared.branding() {
            defaultChatBackground = b.chatBackground ?? ""
            splashImage = b.splash ?? ""
        }

        await loadChatQuick()

        await API.shared.loadEndpointList()
    }

    private func cacheUIConfig(_ ui: [String: Any], _ icons: [String: String]) {
        if let d = try? JSONSerialization.data(withJSONObject: ui),
           let s = String(data: d, encoding: .utf8) {
            UserDefaults.standard.set(s, forKey: Self.uiCacheKey)
        }
        if !icons.isEmpty,
           let d = try? JSONSerialization.data(withJSONObject: icons),
           let s = String(data: d, encoding: .utf8) {
            UserDefaults.standard.set(s, forKey: Self.uiIconCacheKey)
        }
    }

    func applyCachedUIConfig() {
        if let s = UserDefaults.standard.string(forKey: Self.uiCacheKey),
           let d = s.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: d),
           let ui = obj as? [String: Any],
           !ui.isEmpty {
            UIConfig.apply(ui)
        }
        if let s = UserDefaults.standard.string(forKey: Self.uiIconCacheKey),
           let d = s.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: d),
           let icons = obj as? [String: String],
           !icons.isEmpty {
            IconOverrides.map = icons
        }
    }

    private func scheduleUIRetry() {
        guard !uiRetryScheduled else { return }
        uiRetryScheduled = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self = self else { return }
            self.uiRetryScheduled = false
            await self.refreshUI()
        }
    }

    func login(username: String, password: String) async throws {
        let user = try await API.shared.login(username: username, password: password, sliderTicket: "")
        beginAccountTransition()
        me = user
        finishLoginTransition()
        rememberLastUser()
        Realtime.shared.start()
        Task { await refreshAll(); await syncRecentMessages() }
    }

    func login(username: String, password: String, sliderTicket: String) async throws {
        let user = try await API.shared.login(username: username, password: password, sliderTicket: sliderTicket)
        beginAccountTransition()
        me = user
        finishLoginTransition()
        rememberLastUser()
        Realtime.shared.start()
        Task { await refreshAll(); await syncRecentMessages() }
    }

    func adoptRegistered(_ user: User) async {
        beginAccountTransition()
        me = user
        finishLoginTransition()
        rememberLastUser()
        Realtime.shared.start()
        Task { await refreshAll(); await syncRecentMessages() }
    }

    func finishNewUserOnboarding(avatar: String, interests: [String]) async throws {
        let updated = try await API.shared.completeOnboarding(avatar: avatar, interests: interests)
        me = updated
        rememberLastUser()
        await loadContacts()
        await loadChats()
    }

    func login(phone: String, code: String) async throws {
        let user = try await API.shared.loginPhone(phone: phone, code: code)
        beginAccountTransition()
        me = user
        finishLoginTransition()
        rememberLastUser()
        Realtime.shared.start()
        Task { await refreshAll(); await syncRecentMessages() }
    }

    func finishLogin(_ user: User) async {
        beginAccountTransition()
        me = user
        finishLoginTransition()
        rememberLastUser()
        Realtime.shared.start()
        Task { await refreshAll(); await syncRecentMessages() }
    }

    func finishLoginTransition() {
        booting = false
        needConfirmLogin = false
        showSavedLogin = false
        if me != nil {
            authVersion += 1
        }
    }

    private var didInitialBoot = false
    private var dotTask: Task<Void, Never>?
    func startDotWatch() {
        dotTask?.cancel()
        dotTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 25_000_000_000)
                if Task.isCancelled { break }
                await self?.refreshDotCounts()
            }
        }
    }
    func refreshDotCounts() async {
        let epoch = accountEpoch
        guard isCurrentAccount(epoch), let d = await API.shared.badgeCounts() else { return }
        guard isCurrentAccount(epoch) else { return }
        if d.friendRequests != friendRequests {
            friendRequests = d.friendRequests
            await loadContacts()
        }
        if d.momentUnread != momentsUnread { momentsUnread = d.momentUnread }
    }

    func rememberLastUser() {
        guard let me = me else { return }
        let previousUsername = UserDefaults.standard.string(forKey: "chris.activeUsername") ?? ""
        lastAvatar = me.avatar ?? ""
        lastName = me.nickname ?? me.username ?? ""
        UserDefaults.standard.set(lastAvatar, forKey: "chris.lastAvatar")
        UserDefaults.standard.set(lastName, forKey: "chris.lastName")

        if let d = try? JSONEncoder().encode(me), let s = String(data: d, encoding: .utf8) {
            UserDefaults.standard.set(s, forKey: "chris.lastUserJSON")
            if let username = me.username, !username.isEmpty {
                if !previousUsername.isEmpty,
                   previousUsername.caseInsensitiveCompare(username) != .orderedSame,
                   AppState.cachedUser(username: previousUsername)?.id == me.id {
                    accounts = AccountStore.rename(from: previousUsername,
                                                   to: username,
                                                   nickname: me.nickname ?? username,
                                                   avatar: me.avatar ?? "",
                                                   token: API.shared.token)
                }
                UserDefaults.standard.set(s, forKey: "chris.lastUserJSON." + username.lowercased())
                UserDefaults.standard.set(username, forKey: "chris.activeUsername")
            }
        }

        if let u = me.username, !u.isEmpty, !API.shared.token.isEmpty {
            accounts = AccountStore.upsert(username: u,
                                           nickname: me.nickname ?? u,
                                           avatar: me.avatar ?? "",
                                           token: API.shared.token)
        }
    }

    func refreshAll() async {
        let epoch = accountEpoch
        guard isCurrentAccount(epoch) else { return }
        CrashCatcher.install()
        LocalNotify.prepare()
        PushCenter.shared.start()
        PushCenter.shared.uploadIfPossible()

        OtherLogin.shared.reset()

        EyesStore.shared.primeFromCache()

        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard self.accountEpoch == epoch else { return }
            await EyesStore.shared.refresh()
        }

        AppLog.info("启动 " + AppInfo.build + " · " + AppInfo.deviceKind + " · " + API.shared.server)
        Task { await API.shared.touchCurrentDevice() }
        await LocalNotify.refresh()
        await loadHomeDataParallel()
    }

    private func loadHomeDataParallel() async {
        let epoch = accountEpoch
        loadingChats = true
        async let chatsRequest = API.shared.chats()
        async let contactsRequest = API.shared.contactsFull()
        async let momentsRequest = API.shared.momentsFeed()

        do {
            let fresh = try await chatsRequest
            guard isCurrentAccount(epoch) else { return }
            let merged = mergeServerChats(fresh)
            if !AppState.sameChats(chats, merged) { chats = merged }
            loadError = nil
        } catch {
            loadError = nil
        }

        if let r = try? await contactsRequest {
            guard isCurrentAccount(epoch) else { return }
            let friends = applyLocalRemarksToContacts(r.friends)
            let sameOrder = contacts.map { $0.id } == friends.map { $0.id }
            let sameLook = contacts.count == friends.count
                && zip(contacts, friends).allSatisfy { $0.avatarPath == $1.avatarPath && $0.name == $1.name }
            if !(sameOrder && sameLook) { contacts = friends }
            friendRequests = r.incoming.count
        }

        if let feed = try? await momentsRequest {
            guard isCurrentAccount(epoch) else { return }
            moments = feed.moments
            momentsUnread = feed.unread
            momentNoticeUnread = feed.noticeUnread
        }

        loadingChats = false
        syncIconBadge()
    }

    @Published var syncing = false
    @Published var syncText = ""

    var prefetched: [String: [Message]] = [:]
    private var syncInFlight = false

    private var syncHintKey: String {
        "chris.syncHintShown." + (me?.id ?? "")
    }

    func touchCurrentDevice() async {
        guard me != nil, !API.shared.token.isEmpty else { return }
        await API.shared.touchCurrentDevice()
    }

    func syncRecentMessages(chatCount: Int = 20, limit: Int = 50) async {
        guard !syncInFlight else { return }
        let epoch = accountEpoch
        guard isCurrentAccount(epoch) else { return }
        syncInFlight = true
        let showHint = !UserDefaults.standard.bool(forKey: syncHintKey)
        var completed = false
        let hintStarted = Date()

        if showHint {
            syncing = true
            syncText = "正在同步最近的聊天记录…"
        }
        defer {
            if epoch == accountEpoch {
                syncInFlight = false
                syncing = false
                syncText = ""
                if completed && showHint {
                    UserDefaults.standard.set(true, forKey: syncHintKey)
                }
            }
        }
        do {
            let r = try await API.shared.chatsWithRecentMessages(chats: chatCount, limit: limit)
            guard isCurrentAccount(epoch) else { return }
            let merged = mergeServerChats(r.chats)
            if !AppState.sameChats(chats, merged) { chats = merged }
            var total = 0
            for c in r.synced {
                if let msgs = c.messages, !msgs.isEmpty {
                    prefetched[c.id] = msgs
                    total += msgs.count
                }
            }
            completed = true
            if showHint {
                let remain = max(0, 0.7 - Date().timeIntervalSince(hintStarted))
                if remain > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(remain * 1_000_000_000))
                }
                syncText = "同步完成"
                try? await Task.sleep(nanoseconds: 550_000_000)
            }
        } catch {
        }
    }

    func loadChats() async {
        let epoch = accountEpoch
        loadingChats = true
        defer { if epoch == accountEpoch { loadingChats = false } }
        do {
            let fresh = try await API.shared.chats()
            guard let userId = me?.id, !userId.isEmpty, isCurrentAccount(epoch) else { return }
            let merged = mergeServerChats(fresh)
            let suspiciousDrop = !chats.isEmpty
                && (merged.isEmpty || merged.count < max(1, chats.count / 2))
            if suspiciousDrop {
                suspiciousChatDropCount += 1
                if suspiciousChatDropCount < 2 {
                    loadError = nil
                    syncIconBadge()
                    return
                }
            } else {
                suspiciousChatDropCount = 0
            }

            if !AppState.sameChats(chats, merged) { chats = merged }
            LocalStore.saveChatList(chats, userId: userId)
            loadError = nil
        } catch {
            loadError = nil
        }
        syncIconBadge()
    }

    private func mergeServerChats(_ fresh: [Chat]) -> [Chat] {
        let now = Date()
        Array(locallyHiddenAt.keys).forEach { id in
            if now.timeIntervalSince(locallyHiddenAt[id] ?? .distantPast) > 3 {
                locallyHiddenAt[id] = nil
                locallyHiddenChats.remove(id)
            }
        }
        Array(locallyReadAt.keys).forEach { id in
            if now.timeIntervalSince(locallyReadAt[id] ?? .distantPast) > 120 {
                locallyReadAt[id] = nil
            }
        }
        let visibleFresh = fresh.filter { !locallyHiddenChats.contains($0.id) }
        var current: [String: Chat] = [:]
        for chat in chats { current[chat.id] = chat }
        var merged = visibleFresh.map { server -> Chat in
            let stamp = optimisticAt[server.id]
            if let stamp, now.timeIntervalSince(stamp) >= 86_400 {
                optimisticChats[server.id] = nil
                optimisticAt[server.id] = nil
            }
            guard let local = optimisticChats[server.id] ?? current[server.id] else { return server }
            var out = mergeServerChat(server, local: local)
            /* 阅读请求发出后，其他分片可能还会短暂返回同一条消息的未读快照。
               只压掉“最后一条完全相同”的旧计数；真正的新消息仍会正常亮红点。 */
            if let readAt = locallyReadAt[server.id],
               now.timeIntervalSince(readAt) < 120,
               local.unreadCount == 0,
               server.lastMessage?.id == local.lastMessage?.id,
               out.unreadCount > 0 {
                out.unread = 0
                out.flagged = false
            }
            /* 实时消息先把未读数加上，随后 400ms 的列表刷新可能拿到尚未追上
               阅读游标的旧快照。短时间内必须保留本地较大的未读数，否则红点会闪一下消失。 */
            if let stamp, now.timeIntervalSince(stamp) < 90,
               local.unreadCount > out.unreadCount {
                out.unread = local.unreadCount
            }
            if let stamp = optimisticAt[server.id], now.timeIntervalSince(stamp) < 86_400,
               serverCaughtUp(server, local: local) {
                optimisticChats[server.id] = nil
                optimisticAt[server.id] = nil
                out = server
            }
            return out
        }

        let freshIds = Set(visibleFresh.map(\.id))
        var staleOptimisticIds: [String] = []
        for (id, local) in optimisticChats where !freshIds.contains(id) {
            if let stamp = optimisticAt[id], now.timeIntervalSince(stamp) < 86_400 {
                if local.unreadCount > 0 { merged.insert(local, at: 0) }
            } else {
                staleOptimisticIds.append(id)
            }
        }
        for id in staleOptimisticIds {
            optimisticChats[id] = nil
            optimisticAt[id] = nil
        }
        // 刷新只更新原行内容，保持当前屏幕上的行顺序，避免会话互相换位。
        var byId: [String: Chat] = [:]
        for row in merged { byId[row.id] = row }
        var ordered: [Chat] = []
        var seen = Set<String>()
        for row in chats {
            if let next = byId[row.id], seen.insert(row.id).inserted {
                ordered.append(next)
            }
        }
        for row in merged where seen.insert(row.id).inserted {
            ordered.append(row)
        }
        return applyLocalRemarksToChats(ordered.isEmpty ? merged : ordered)
    }

    private func mergeServerChat(_ server: Chat, local: Chat) -> Chat {
        guard let localLast = local.lastMessage else { return server }
        var out = server
        let sameMessage = !(server.lastMessage?.id ?? "").isEmpty
            && server.lastMessage?.id == localLast.id
        let serverNewer: Bool
        if let serverLast = server.lastMessage {
            serverNewer = (serverLast.createdAt ?? "") > (localLast.createdAt ?? "")
        } else {
            serverNewer = false
        }

        if sameMessage {
            if (server.lastMessage?.preview ?? "").isEmpty,
               !(localLast.preview ?? "").isEmpty {
                out.lastMessage = localLast
            }
        } else if !serverNewer {
            out.lastMessage = localLast
        }

        if !serverNewer, local.unreadCount > out.unreadCount {
            out.unread = local.unreadCount
        }
        if !serverNewer {
            out.updatedAt = max(out.updatedAt ?? "", local.updatedAt ?? "")
        }
        return out
    }

    private func serverCaughtUp(_ server: Chat, local: Chat) -> Bool {
        guard let serverLast = server.lastMessage,
              let localLast = local.lastMessage else {
            return local.lastMessage == nil
        }
        if serverLast.id == localLast.id {
            let serverHasPreview = !(serverLast.preview ?? "").isEmpty
            let localHasPreview = !(localLast.preview ?? "").isEmpty
            return server.unreadCount >= local.unreadCount
                && (serverHasPreview || !localHasPreview)
        }
        return (serverLast.createdAt ?? "") > (localLast.createdAt ?? "")
            && server.unreadCount >= local.unreadCount
    }

    func markChatReadLocally(_ chatId: String) {
        optimisticChats[chatId] = nil
        optimisticAt[chatId] = nil
        locallyReadAt[chatId] = Date()
        if let i = chats.firstIndex(where: { $0.id == chatId }) {
            var c = chats[i]
            c.unread = 0
            c.flagged = false
            chats[i] = c
        }
        syncIconBadge()
    }

    func setChatUnreadLocally(_ chatId: String, unread: Int?, flagged: Bool?) {
        guard let index = chats.firstIndex(where: { $0.id == chatId }) else { return }
        if (unread ?? 0) > 0 || flagged == true {
            locallyReadAt[chatId] = nil
        }
        chats[index].unread = unread
        chats[index].flagged = flagged
        syncIconBadge()
    }

    func dropOptimisticSummary(_ chatId: String) {
        optimisticChats[chatId] = nil
        optimisticAt[chatId] = nil
    }

    func hideChatLocally(_ chatId: String) {
        locallyHiddenChats.insert(chatId)
        locallyHiddenAt[chatId] = Date()
        optimisticChats[chatId] = nil
        optimisticAt[chatId] = nil
        chats.removeAll { $0.id == chatId }
        syncIconBadge()
    }

    func revealChatLocally(_ chatId: String) {
        locallyHiddenChats.remove(chatId)
        locallyHiddenAt.removeValue(forKey: chatId)
    }

    /// 从联系人发出第一条消息时，服务端会话摘要可能比消息接口晚一拍。
    /// 先在本地补上会话，列表才不会短暂或长期漏掉新聊天。
    func ensureChatVisible(_ chat: Chat, latest: Message? = nil) {
        guard let myId = me?.id, !myId.isEmpty else { return }
        if let members = chat.memberIds, !members.isEmpty, !members.contains(myId) {
            return
        }
        locallyHiddenChats.remove(chat.id)
        var row = chats.first(where: { $0.id == chat.id }) ?? chat
        if let latest {
            row.lastMessage = LastMessage(
                id: latest.id,
                senderId: latest.senderId,
                senderName: latest.senderName,
                kind: latest.kind,
                preview: previewText(for: latest),
                createdAt: latest.createdAt,
                mentionMe: false
            )
            row.updatedAt = latest.createdAt ?? row.updatedAt
        }
        row.unread = 0
        chats.removeAll { $0.id == chat.id }
        let firstUnpinned = chats.firstIndex { $0.pinned != true } ?? chats.count
        chats.insert(row, at: firstUnpinned)
        if let userId = me?.id, !userId.isEmpty {
            LocalStore.saveChatList(chats, userId: userId)
        }
        syncIconBadge()
    }

    func noteFriendRequestSent(_ user: User, note: String) {
        var row = user
        row.requestMessage = note
        localOutgoingFriendRequests.removeAll { $0.id == user.id }
        localOutgoingFriendRequests.insert(row, at: 0)
    }

    private func previewText(for message: Message) -> String {
        switch message.kindName {
        case "text": return message.body
        case "image", "images": return "[图片]"
        case "video", "livephoto": return "[视频]"
        case "audio", "voice": return "[语音]"
        case "file": return "[文件]"
        case "location": return "[位置]"
        case "card": return "[名片]"
        case "transfer": return "[转账]"
        case "redpacket": return "[红包]"
        case "call", "voicecall": return "[语音通话]"
        case "videocall": return "[视频通话]"
        default: return message.body.isEmpty ? "[消息]" : message.body
        }
    }

    func applyPinnedLocally(chatId: String, pinned: Bool) {
        guard let i = chats.firstIndex(where: { $0.id == chatId }) else { return }
        chats[i].pinned = pinned
        let top = chats.filter { $0.pinned == true }
        let rest = chats.filter { $0.pinned != true }.sorted {
            let ra = $0.botRank ?? 9, rb = $1.botRank ?? 9
            if ra != rb { return ra < rb }
            return ($0.updatedAt ?? "") > ($1.updatedAt ?? "")
        }
        chats = top + rest
    }

    func applyMutedLocally(chatId: String, muted: Bool) {
        guard let i = chats.firstIndex(where: { $0.id == chatId }) else { return }
        chats[i].muted = muted
    }

    func applyFriendRemarkLocally(userId: String, displayName: String, remark: String? = nil) {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var remarks = localFriendRemarkMap
        let stored = (remark ?? name).trimmingCharacters(in: .whitespacesAndNewlines)
        if stored.isEmpty {
            remarks.removeValue(forKey: userId)
        } else {
            remarks[userId] = stored
        }
        UserDefaults.standard.set(remarks, forKey: localFriendRemarksKey)
        for i in contacts.indices where contacts[i].id == userId {
            if (contacts[i].realNickname ?? "").isEmpty {
                contacts[i].realNickname = contacts[i].nickname
            }
            contacts[i].nickname = name
            contacts[i].remark = remark ?? name
        }
        for i in chats.indices where (chats[i].type ?? "direct") == "direct"
            && chats[i].memberIds?.contains(userId) == true {
            chats[i].title = name
        }
    }

    private var localFriendRemarksKey: String {
        "chris.localFriendRemarks.v1." + (me?.id ?? "guest")
    }

    private var localFriendRemarkMap: [String: String] {
        let raw = UserDefaults.standard.dictionary(forKey: localFriendRemarksKey) ?? [:]
        return raw.reduce(into: [:]) { out, pair in
            if let value = pair.value as? String, !value.isEmpty { out[pair.key] = value }
        }
    }

    private func applyLocalRemarksToContacts(_ users: [User]) -> [User] {
        let remarks = localFriendRemarkMap
        guard !remarks.isEmpty else { return users }
        return users.map { user in
            guard let remark = remarks[user.id], !remark.isEmpty else { return user }
            var out = user
            if (out.realNickname ?? "").isEmpty { out.realNickname = out.nickname }
            out.remark = remark
            out.nickname = remark
            return out
        }
    }

    private func applyLocalRemarksToChats(_ rows: [Chat]) -> [Chat] {
        let remarks = localFriendRemarkMap
        guard !remarks.isEmpty else { return rows }
        return rows.map { chat in
            guard (chat.type ?? "direct") == "direct" else { return chat }
            guard let peer = (chat.memberIds ?? []).first(where: { remarks[$0] != nil }),
                  let remark = remarks[peer] else { return chat }
            var out = chat
            out.title = remark
            return out
        }
    }

    func applyFriendAccepted(_ user: User) {
        var merged = user
        merged.relation = "friend"
        if let index = contacts.firstIndex(where: { $0.id == user.id }) {
            let old = contacts[index]
            merged.avatar = merged.avatar ?? old.avatar
            merged.nickname = merged.nickname ?? old.nickname
            merged.realNickname = merged.realNickname ?? old.realNickname
            merged.remark = merged.remark ?? old.remark
            contacts[index] = applyLocalRemarksToContacts([merged]).first ?? merged
        } else {
            contacts.append(applyLocalRemarksToContacts([merged]).first ?? merged)
        }
    }

    func applyFriendRemoved(userId: String) {
        guard !userId.isEmpty else { return }
        contacts.removeAll { $0.id == userId }
        let removed = chats.filter {
            ($0.type ?? "direct") == "direct" && ($0.memberIds ?? []).contains(userId)
        }
        for chat in removed {
            hideChatLocally(chat.id)
        }
    }

    func applyProfileUpdate(_ user: User) {
        guard let index = contacts.firstIndex(where: { $0.id == user.id }) else { return }
        let old = contacts[index]
        var merged = user
        merged.avatar = merged.avatar ?? old.avatar
        merged.nickname = merged.nickname ?? old.nickname
        merged.realNickname = merged.realNickname ?? old.realNickname
        merged.remark = merged.remark ?? old.remark
        merged.relation = merged.relation ?? old.relation
        merged.momentCover = merged.momentCover ?? old.momentCover
        let updated = applyLocalRemarksToContacts([merged]).first ?? merged
        contacts[index] = updated
        for i in chats.indices where (chats[i].type ?? "direct") == "direct"
            && chats[i].memberIds?.contains(user.id) == true {
            chats[i].avatar = updated.avatarPath
            if let remark = updated.remark?.trimmingCharacters(in: .whitespacesAndNewlines),
               !remark.isEmpty {
                chats[i].title = remark
            } else {
                chats[i].title = updated.name
            }
        }
    }

    func applyMyProfileFields(_ fields: [String: Any]) {
        guard var me = me else { return }
        func text(_ key: String) -> String? { fields[key] as? String }
        if let value = text("nickname") { me.nickname = value }
        if let value = text("bio") { me.bio = value }
        if let value = text("region") { me.region = value }
        if let value = text("gender") { me.gender = value }
        if let value = text("birthday") { me.birthday = value }
        if let value = text("patText") { me.patText = value }
        if let value = text("phone") { me.phone = value }
        if let value = text("username") { me.username = value }
        if let value = text("avatar") { me.avatar = value }
        if let value = text("momentCover") { me.momentCover = value }
        if let value = text("chatBackground") { me.chatBackground = value }
        self.me = me
        rememberLastUser()
    }

    /// 资料保存后以服务端返回值作为唯一真源，避免只改本地状态、
    /// 下一次轮询又从旧用户行覆盖回来。
    func applyMyProfileUser(_ user: User) {
        guard var merged = me else {
            me = user
            rememberLastUser()
            return
        }
        merged.nickname = user.nickname ?? merged.nickname
        merged.bio = user.bio ?? merged.bio
        merged.region = user.region ?? merged.region
        merged.gender = user.gender ?? merged.gender
        merged.birthday = user.birthday ?? merged.birthday
        merged.patText = user.patText ?? merged.patText
        merged.phone = user.phone ?? merged.phone
        merged.username = user.username ?? merged.username
        merged.avatar = user.avatar ?? merged.avatar
        merged.momentCover = user.momentCover ?? merged.momentCover
        merged.chatBackground = user.chatBackground ?? merged.chatBackground
        me = merged
        rememberLastUser()
    }

    /// WebSocket 已带会话摘要时先更新预览与红点，再等后台全量校准。
    private func applyRealtimeChat(_ incoming: Chat) {
        locallyHiddenChats.remove(incoming.id)
        locallyHiddenAt.removeValue(forKey: incoming.id)
        var rows = chats
        if let index = rows.firstIndex(where: { $0.id == incoming.id }) {
            let current = rows[index]
            let currentMid = current.lastMessage?.id ?? ""
            let incomingMid = incoming.lastMessage?.id ?? ""
            var merged = incoming
            if let sender = incoming.lastMessage?.senderId, sender != me?.id,
               !incomingMid.isEmpty, incomingMid != currentMid,
               incoming.unreadCount <= current.unreadCount {
                merged.unread = current.unreadCount + 1
            } else {
                merged.unread = max(current.unreadCount, incoming.unreadCount)
            }
            rows[index] = merged
            if let sender = incoming.lastMessage?.senderId, sender != me?.id {
                optimisticChats[incoming.id] = merged
                optimisticAt[incoming.id] = Date()
            }
        } else {
            rows.insert(incoming, at: 0)
            if let sender = incoming.lastMessage?.senderId, sender != me?.id {
                optimisticChats[incoming.id] = incoming
                optimisticAt[incoming.id] = Date()
            }
        }
        chats = rows
        syncIconBadge()
    }

    /// 兼容只带 message、没有 chat 摘要的实时事件。
    private func applyRealtimeMessage(_ message: Message, chatId: String) {
        let ids = [message.chatId ?? "", chatId]
        guard let id = ids.first(where: { !$0.isEmpty }),
              let index = chats.firstIndex(where: { $0.id == id }) else { return }
        var row = chats[index]
        if row.lastMessage?.id != message.id, message.senderId != me?.id {
            row.unread = row.unreadCount + 1
        }
        var preview = Self.realtimePreview(message)
        if row.type == "group", message.senderId != me?.id,
           let sender = message.senderName, !sender.isEmpty, !preview.isEmpty {
            preview = sender + "：" + preview
        }
        row.lastMessage = LastMessage(
            id: message.id,
            senderId: message.senderId,
            senderName: message.senderName,
            kind: message.kindName,
            preview: preview,
            createdAt: message.createdAt,
            mentionMe: message.mentionsUser(me?.id ?? "")
        )
        row.updatedAt = message.createdAt ?? row.updatedAt
        var rows = chats
        rows[index] = row
        chats = rows
        optimisticChats[id] = row
        optimisticAt[id] = Date()
        syncIconBadge()
    }

    private static func realtimePreview(_ message: Message) -> String {
        switch message.kindName {
        case "text", "":
            let text = message.body.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? "消息" : String(text.prefix(80))
        case "image", "images": return "[图片]"
        case "video", "livephoto": return "[视频]"
        case "audio", "voice": return "[语音]"
        case "file": return "[文件]"
        case "link", "oa": return "[链接]"
        case "music": return "[音乐]"
        case "location": return "[位置]"
        case "card": return "[名片]"
        case "transfer": return "[转账]"
        case "redpacket": return "[红包]"
        case "gift": return "[礼物]"
        case "miniapp", "mini", "app", "mall": return "[小程序]"
        case "channels", "channel", "feed", "shortvideo": return "[视频号]"
        case "call", "voicecall": return "[语音通话]"
        case "videocall": return "[视频通话]"
        case "system": return "消息"
        default: return "[消息]"
        }
    }

    /// 清空聊天记录后立即丢掉列表预览、预取缓存和本机底稿。
    /// 不能等下一次 loadChats：否则会短暂显示旧预览，重新进会话还会从本机缓存“复活”。
    func forgetChatHistory(_ chatId: String, notify: Bool = true) {
        if let i = chats.firstIndex(where: { $0.id == chatId }) {
            var c = chats[i]
            c.lastMessage = nil
            c.unread = 0
            c.flagged = false
            chats[i] = c
        }
        prefetched[chatId] = nil
        optimisticChats[chatId] = nil
        optimisticAt[chatId] = nil
        LocalStore.clearChat(chatId)
        if notify {
            NotificationCenter.default.post(name: .chrisChatCleared, object: chatId)
        }
    }

    static func sameChats(_ a: [Chat], _ b: [Chat]) -> Bool {
        if a.count != b.count { return false }
        for i in 0..<a.count {
            let x = a[i], y = b[i]
            if x.id != y.id { return false }
            if x.unreadCount != y.unreadCount { return false }
            if (x.pinned ?? false) != (y.pinned ?? false) { return false }
            if (x.muted ?? false) != (y.muted ?? false) { return false }

            if (x.flagged ?? false) != (y.flagged ?? false) { return false }
            if (x.title ?? "") != (y.title ?? "") { return false }
            if (x.avatar ?? "") != (y.avatar ?? "") { return false }
            if (x.moodIcon ?? "") != (y.moodIcon ?? "") { return false }
            if (x.lastMessage?.preview ?? "") != (y.lastMessage?.preview ?? "") { return false }
            if (x.lastMessage?.createdAt ?? "") != (y.lastMessage?.createdAt ?? "") { return false }
        }
        return true
    }

    var unreadForIcon: Int {
        var n = 0
        for c in chats where c.muted != true { n += c.unreadCount }
        return min(999, max(0, n))
    }

    func syncIconBadge() {
        let v = unreadForIcon
        DispatchQueue.main.async {
            UIApplication.shared.applicationIconBadgeNumber = v
        }
    }

    func loadContacts() async {
        let epoch = accountEpoch
        if let r = try? await API.shared.contactsFull() {
            guard isCurrentAccount(epoch) else { return }

            let friends = applyLocalRemarksToContacts(r.friends)
            let sameOrder = contacts.map { $0.id } == friends.map { $0.id }
            let sameLook = contacts.count == friends.count
                && zip(contacts, friends).allSatisfy {
                    $0.avatarPath == $1.avatarPath && $0.name == $1.name
                        && ($0.remark ?? "") == ($1.remark ?? "")
                }
            if !(sameOrder && sameLook) { contacts = friends }
            friendRequests = r.incoming.count
        }
    }

    func loadMoments() async {
        let epoch = accountEpoch
        if let feed = try? await API.shared.momentsFeed() {
            guard isCurrentAccount(epoch) else { return }
            moments = feed.moments
            momentsUnread = feed.unread
            momentNoticeUnread = feed.noticeUnread
        }
    }

    func loadChatQuick() async {
        guard let c = try? await API.shared.plusConfig() else { return }
        if !c.quick.isEmpty { quickChips = c.quick }
        plusButton = c.plus
    }

    func logout(keepSavedAccount: Bool = true) async {
        if let userId = me?.id, !userId.isEmpty {
            UserDefaults.standard.removeObject(forKey: "chris.syncHintShown." + userId)
        }
        beginAccountTransition()

        KeepAlive.shared.stop()
        OtherLogin.shared.reset()

        if !keepSavedAccount {
            Realtime.shared.stop()
            API.shared.clearToken()
            me = nil
            chats = []
            locallyHiddenChats.removeAll()
            contacts = []
            moments = []
            showSavedLogin = false
            needConfirmLogin = false
            syncIconBadge()
            return
        }

        CallCenter.shared.resetForAccountChange()
        Realtime.shared.stop()
        await API.shared.unregisterPushToken(PushCenter.shared.token)
        await API.shared.logout()
        Realtime.shared.stop()
        me = nil
        chats = []
        locallyHiddenChats.removeAll()
        contacts = []
        moments = []
        showSavedLogin = true
        needConfirmLogin = false
        syncIconBadge()
    }

    func quickLogin(token: String? = nil, username: String? = nil,
                    switchingAccount: Bool = false) async -> Bool {
        let nextToken = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? API.shared.token
        guard !nextToken.isEmpty else { return false }
        if switchingAccount {
            guard let token, !token.isEmpty else { return false }
        }
        beginAccountTransition()
        if let username, !username.isEmpty {
            UserDefaults.standard.set(username, forKey: "chris.activeUsername")
        }
        API.shared.setToken(nextToken)
        guard !API.shared.token.isEmpty else { return false }
        let epoch = accountEpoch
        do {
            let s = try await API.shared.session()
            guard epoch == accountEpoch else { return false }
            guard s.ok, let user = s.user else {
                API.shared.clearToken()
                return false
            }
            if let username, !username.isEmpty,
               user.username?.caseInsensitiveCompare(username) != .orderedSame {
                API.shared.clearToken()
                return false
            }
            me = user
            let cachedChats = LocalStore.cachedChatList(userId: user.id)
            if !cachedChats.isEmpty { chats = cachedChats }
        } catch {
            /* 网络短暂失败不能删登录令牌，否则用户会被错误地要求重新输账号密码。 */
            guard epoch == accountEpoch,
                  let cached = AppState.cachedUser(username: username) else { return false }
            if let username, !username.isEmpty,
               cached.username?.caseInsensitiveCompare(username) != .orderedSame { return false }
            me = cached
        }
        finishLoginTransition()
        rememberLastUser()
        await refreshAll()
        Realtime.shared.start()
        GrowthStore.shared.start()
        Task { await syncRecentMessages() }
        return true
    }

    func contact(for id: String) -> User? {
        if me?.id == id { return me }

        if let hit = contactIndex[id] { return hit }
        if contactIndex.isEmpty { return contacts.first { $0.id == id } }
        return nil
    }
}

@main
struct CHRISApp: App {
    @StateObject private var app = AppState()
    @StateObject private var externalFiles = ExternalFileInbox.shared

    @UIApplicationDelegateAdaptor(PushCenter.self) private var push

    init() {

        CrashCatcher.install()
        AppMetrics.shared.start()

        CrashCatcher.note("启动", "1 App init")

        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024,
                                   diskCapacity: 512 * 1024 * 1024,
                                   diskPath: "chris-media-cache")
    }

    var body: some Scene {
        WindowGroup {

            ZStack {
                RootView()
                    .environmentObject(app)
                    .environmentObject(externalFiles)
                    .preferredColorScheme(app.preferredScheme)
                    .onOpenURL { url in
                        if url.isFileURL { ExternalFileInbox.shared.accept([url]) }
                    }
                    .sheet(isPresented: $externalFiles.present) {
                        ExternalFileSendView()
                            .environmentObject(app)
                            .environmentObject(externalFiles)
                    }

                Color.clear
                    .frame(width: 0, height: 0)
                    .sheet(isPresented: Binding(
                        get: { !app.pairApproveCode.isEmpty },
                        set: { if !$0 { app.pairApproveCode = "" } }
                    )) {
                        PairApproveView(startCode: app.pairApproveCode) { app.pairApproveCode = "" }
                            .environmentObject(app)
                    }
                if !app.splashDone {
                    SplashView(remote: app.splashImage)
                        .transition(.opacity)
                        .zIndex(9)
                }

                if let n = app.noticeAlert {
                    CenterCard(title: (n.title?.isEmpty == false ? n.title! : Tr("公告")),
                               text: n.content ?? "",
                               primary: Tr("我知道了"),
                               onPrimary: { app.dismissNotice() })
                        .transition(.opacity)
                        .zIndex(12)
                }
                if let u = app.optionalUpdate {
                    CenterCard(title: Tr("发现新版本") + " " + (u.version ?? ""),
                               text: u.notes ?? "",
                               primary: Tr("立即更新"),
                               onPrimary: { app.openUpdate(u) },
                               secondary: Tr("以后再说"),
                               onSecondary: { app.dismissOptionalUpdate() })
                        .transition(.opacity)
                        .zIndex(13)
                }
                if let u = app.forcedUpdate {
                    ForceUpdateView(info: u)
                        .transition(.opacity)
                        .zIndex(20)
                }
            }
        }
    }
}

struct SavedLoginConfirm: View {
    @EnvironmentObject var app: AppState
    @State private var appear = false
    @State private var busy = false

    private var savedAccount: SavedAccount? {
        if let a = app.accounts.first(where: { $0.avatar == app.lastAvatar }) {
            let t = AccountStore.token(for: a.username)
            if !t.isEmpty { return a }
        }
        for a in app.accounts {
            let t = AccountStore.token(for: a.username)
            if !t.isEmpty { return a }
        }
        return nil
    }

    private var savedToken: String {
        guard let account = savedAccount else { return "" }
        return AccountStore.token(for: account.username)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 16) {
                Avatar(path: app.lastAvatar, size: 88, radius: 12, circle: false)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(C.hairline, lineWidth: 0.6))
                    .shadow(color: Color.black.opacity(0.14), radius: 14, y: 6)

                VStack(spacing: 5) {
                    Text(app.lastName.isEmpty ? Tr("星言用户") : app.lastName)
                        .font(pf(20, .semibold))
                        .foregroundColor(C.label)
                        .lineLimit(1)
                    Text(Tr("上次登录的账号"))
                        .font(pf(12.5))
                        .foregroundColor(C.subLabel)
                }
            }
            .scaleEffect(appear ? 1 : 0.94)
            .opacity(appear ? 1 : 0)

            Spacer(minLength: 0)

            VStack(spacing: 14) {
                Button {
                    go()
                } label: {
                    Text(Tr("登录"))
                        .font(pf(16, .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Capsule().fill(LinearGradient(
                            colors: [C.green, C.green.opacity(0.78)],
                            startPoint: .topLeading, endPoint: .bottomTrailing)))
                }
                .buttonStyle(.plain)

                Button {

                    API.shared.clearToken()
                    app.me = nil
                    app.needConfirmLogin = false
                    app.showSavedLogin = false
                } label: {
                    Text(Tr("切换账号"))
                        .font(pf(15))
                        .foregroundColor(C.subLabel)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 44)
            .opacity(appear ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(C.pageBg.ignoresSafeArea())
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { appear = true }
        }
    }

    private func go() {
        if app.me != nil {
            withAnimation(.easeOut(duration: 0.18)) { app.finishLoginTransition() }
            return
        }
        guard !busy else { return }
        busy = true
        Task {
            let ok = await app.quickLogin(token: savedToken,
                                          username: savedAccount?.username,
                                          switchingAccount: savedAccount != nil)
            busy = false
            if ok {
                app.showSavedLogin = false
            } else {
                app.showSavedLogin = false
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var realtime = Realtime.shared
    /// 二级登录确认默认关闭；保留 SavedLoginConfirm，后续可通过该开关恢复。
    @AppStorage("chris.savedLoginConfirmEnabled") private var savedLoginConfirmEnabled = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if app.booting {
                    LaunchView()
                } else if savedLoginConfirmEnabled && (app.needConfirmLogin || app.showSavedLogin) {

                    SavedLoginConfirm()
                } else if app.me == nil {

                    HarmonyLoginView()
                } else if app.me?.needsOnboarding == true {
                    NewUserOnboardingView()
                        .environmentObject(app)
                } else {
                    MainTabView()
                }

                if let text = app.toast {
                    VStack {
                        Spacer()
                        Text(text)
                            .font(pf(14))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.78)))
                            .padding(.bottom, L.tabH + L.safeBottom + 40)
                    }
                    .allowsHitTesting(false)
                }
            }
            // UI 配置刷新只应重绘界面，不能重建主 Tab 容器；否则当前 Tab、
            // 导航栈和滚动位置都会被重置。账号登录完成仍可通过 authVersion
            // 重建一次根视图，确保新账号从干净的首页开始。
            .id(app.authVersion)

            .background(C.pageBg.ignoresSafeArea())
            .onAppear { L.width = geo.size.width }
            .onChange(of: geo.size.width) { w in L.width = w }
        }
        .task { await app.boot() }
        .task {
            // 后台改图标等界面配置时实时事件可能被弱网丢掉；前台定时校准一次。
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard !Task.isCancelled else { break }
                if scenePhase == .active && app.me != nil {
                    await app.refreshUI()
                }
            }
        }
        .onAppear {

            guard !app.splashDone else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.easeOut(duration: 0.22)) { app.splashDone = true }
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active && app.me != nil {
                KeepAlive.shared.stop()
                Task {
                    GrowthStore.shared.start()
                    Task { await app.touchCurrentDevice() }
                    await app.refreshUI()
                    await app.loadChats()
                    await app.loadContacts()
                    await app.refreshDotCounts()
                    await app.syncRecentMessages()
                    Realtime.shared.start()

                    CallCenter.shared.restorePendingAfterActivation()
                }
            } else if phase == .background {
                GrowthStore.shared.stop()

                KeepAlive.shared.start()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .chrisChatRead)) { note in
            if let id = note.object as? String, !id.isEmpty {
                Task { @MainActor in app.markChatReadLocally(id) }
            }
        }
        .onChange(of: realtime.event) { ev in

            if ev.type == "ui" {
                Task { await app.refreshUI(force: true) }
                return
            }

            if ev.type == "growth" {
                Task { await GrowthStore.shared.refresh() }
                return
            }
            app.handle(ev)
        }
    }
}

struct LaunchView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 14) {
                if let img = AppIconImage.image {
                    Image(uiImage: img)
                        .resizable()
                        .frame(width: 66, height: 66)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                Text(Tr("正在连接…")).font(pf(13)).foregroundColor(C.loginGray)
            }
        }
    }
}

struct LoginViewOld: View {
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @FocusState private var focus: Field?

    private enum Field: Hashable { case phone, code, user, pass }

    @State private var usePassword = false
    @State private var country = "中国大陆 (+86)"

    @State private var phone = UserDefaults.standard.string(forKey: "chris.lastPhone") ?? ""
    @State private var code = ""
    @State private var username = ""
    @State private var password = ""
    @State private var syncHistory = true
    @State private var busy = false
    @State private var error: String?
    @State private var codeSent = false
    @State private var showServer = false
    @State private var server = API.shared.server

    var body: some View {
        ZStack {

            LoginTheme.bg(scheme).ignoresSafeArea()
            VStack(spacing: 0) {
                nav
                ScrollView {
                    VStack(spacing: 0) {
                        panel
                        if let error = error {
                            Text(error)
                                .font(pf(13.5))
                                .foregroundColor(LoginTheme.pageBg == nil ? C.red : Color(hex: 0xFF8E8E))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 18)
                                .padding(.top, 12)
                        }
                        if !usePassword {
                            Text(Tr("仅上述手机号用于登录验证"))
                                .font(pf(13.5))
                                .foregroundColor(LoginTheme.onBgSub(scheme))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 18)
                                .padding(.top, 11)
                        }
                        Spacer(minLength: 30)
                    }
                    .padding(.top, 14)
                    .frame(minHeight: 660, alignment: .top)
                }
                foot
            }
        }
        .onAppear {

            if phone.isEmpty, let last = UserDefaults.standard.string(forKey: "chris.lastPhone"), !last.isEmpty {
                phone = last
            }
        }
        .sheet(isPresented: $showServer) {
            ServerSheet(server: $server) {
                API.shared.setServer(server)
                server = API.shared.server
                showServer = false
                app.show("服务器已改成 \(server)")
            }
        }
    }

    private var switchLink: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Button {
                withAnimation(.easeInOut(duration: 0.16)) { usePassword.toggle() }
                error = nil
                focus = nil
            } label: {
                HStack(spacing: 3) {
                    Text(Tr(usePassword ? "用手机号登录" : "账号密码登录"))
                        .font(pf(14))
                    Image(systemName: "chevron.right")
                        .font(pf(11, .semibold))
                }
                .foregroundColor(LoginTheme.onBg(scheme))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 11)
    }

    private var nav: some View {
        ZStack {
            Text(usePassword ? "账号密码登录" : "手机号登录")
                .font(pf(18, .semibold))
                .foregroundColor(LoginTheme.onBg(scheme))
            HStack {
                Button {
                    focus = nil
                } label: {
                    Image(systemName: "chevron.left")
                        .font(pf(22, .regular))
                        .foregroundColor(LoginTheme.onBg(scheme))
                        .frame(width: 44, height: 52)
                }
                Spacer()
            }
        }
        .frame(height: 52)
    }

    private var panel: some View {
        VStack(spacing: 0) {
            if !usePassword {
                loginRow(label: "国家/地区") {
                    Spacer()
                    Text(country).font(pf(16)).foregroundColor(LoginTheme.inkSub(scheme))
                    Chevron(size: 9, line: 1.6, color: LoginTheme.inkSub(scheme))
                }
                HairLine(color: LoginTheme.ink(scheme).opacity(0.09))
                loginRow(label: "手机号") {
                    Text("+86").font(pf(17)).foregroundColor(LoginTheme.ink(scheme))
                    TextField("", text: $phone)
                        .focused($focus, equals: .phone)
                        .keyboardType(.numberPad)
                        .textContentType(.telephoneNumber)
                        .font(pf(17.5))
                        .foregroundColor(LoginTheme.ink(scheme))
                        .frame(height: 46)
                }
                HairLine(color: LoginTheme.ink(scheme).opacity(0.09))
                loginRow(label: "验证码") {
                    TextField("", text: $code)
                        .focused($focus, equals: .code)
                        .keyboardType(.numberPad)

                        .textContentType(.oneTimeCode)
                        .font(pf(17.5))
                        .foregroundColor(LoginTheme.ink(scheme))
                        .frame(height: 46)
                    Button {
                        sendCode()
                    } label: {
                        Text(codeSent ? "已发送" : "获取验证码")
                            .font(pf(15, .medium))
                            .foregroundColor(codeSent ? LoginTheme.inkSub(scheme) : LoginTheme.accent)
                            .padding(.vertical, 6)
                    }
                }
            } else {
                loginRow(label: "账号") {
                    TextField("", text: $username)
                        .focused($focus, equals: .user)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .font(pf(17.5))
                        .foregroundColor(LoginTheme.ink(scheme))
                        .frame(height: 46)
                }
                HairLine(color: LoginTheme.ink(scheme).opacity(0.09))
                loginRow(label: "密码") {
                    SecureField("", text: $password)
                        .focused($focus, equals: .pass)

                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                        .privacySensitive()
                        .font(pf(17.5))
                        .foregroundColor(LoginTheme.ink(scheme))
                        .frame(height: 46)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(LoginTheme.cardBg(scheme)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(LoginTheme.ink(scheme).opacity(0.06), lineWidth: 0.8))
        .shadow(color: Color.black.opacity(LoginTheme.pageBg == nil ? 0 : 0.12), radius: 12, y: 5)
        .padding(.horizontal, 16)
    }

    private func loginRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10.9) {
            Text(label)
                .font(pf(17))
                .foregroundColor(LoginTheme.ink(scheme))
                .frame(width: 74, alignment: .leading)
            content()
        }
        .padding(.horizontal, 18)
        .frame(height: 60)
    }

    private var foot: some View {
        VStack(spacing: 0) {
            Button {
                syncHistory.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: syncHistory ? "checkmark.circle.fill" : "circle")
                        .font(pf(15))
                        .foregroundColor(syncHistory ? LoginTheme.accent : LoginTheme.onBgSub(scheme))
                    Text(Tr("登录后同步最近的聊天记录"))
                        .font(pf(13.5))
                        .foregroundColor(LoginTheme.onBgSub(scheme))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .padding(.bottom, 12.6)

            switchLink

            Button {
                submit()
            } label: {
                Text(busy ? "登录中…" : "同意并继续")
                    .font(pf(17, .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: 8)
                        .fill(busy ? LoginTheme.accent.opacity(0.6) : LoginTheme.accent))
            }
            .disabled(busy)

            Button {
                showServer = true
            } label: {
                Text("服务器 \(server)（长按可改）")
                    .font(pf(11))
                    .foregroundColor(LoginTheme.onBgSub(scheme).opacity(0.7))
            }
            .padding(.top, 10)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, max(16, L.safeBottom))
        .background(LoginTheme.bg(scheme))
    }

    private func sendCode() {
        let p = phone.trimmingCharacters(in: .whitespaces)
        if p.count < 5 { error = "请填写手机号"; return }
        error = nil
        Task {
            do {
                let dev = try await API.shared.phoneCode(phone: p)
                codeSent = true
                if let c = dev { code = c; app.show("验证码：\(c)") } else { app.show(Tr("验证码已发送")) }
            } catch {
                self.error = (error as? APIError)?.errorDescription ?? "发送失败"
            }
        }
    }

    private func submit() {
        busy = true
        error = nil
        Task {
            do {
                if usePassword {
                    let u = username.trimmingCharacters(in: .whitespaces)
                    if u.isEmpty || password.isEmpty { throw APIError.message("请填写账号和密码") }
                    try await app.login(username: u, password: password)
                } else {
                    let p = phone.trimmingCharacters(in: .whitespaces)
                    if p.isEmpty || code.isEmpty { throw APIError.message("请填写手机号和验证码") }
                    try await app.login(phone: p, code: code)

                    UserDefaults.standard.set(p, forKey: "chris.lastPhone")
                }
            } catch {
                self.error = (error as? APIError)?.errorDescription ?? "登录失败"
            }
            busy = false
        }
    }
}

struct ServerSheet: View {
    @Binding var server: String
    var onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text(Tr("电脑的局域网地址（IP:端口）"))) {
            TextField("aa.x8iu.com（加密）", text: $server)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .keyboardType(.numbersAndPunctuation)
                }
                Section(footer: Text(Tr("电脑上运行 CHRIS聊天，手机连同一个 Wi-Fi，用电脑的 IP 填这里。"))) {
                    EmptyView()
                }
            }
            .navigationTitle(Tr("服务器"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button(Tr("取消")) { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) { Button(Tr("保存")) { onSave() } }
            }
        }
    }
}

struct CaptchaView: View {
    let svg: String
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 160.0, sy = size.height / 64.0
            let groups = CaptchaView.parseGroups(svg)
            for g in groups {
                let color = Color(hexString: g.fill)
                for r in g.rects {
                    var p = Path(roundedRect: CGRect(x: r.x * sx, y: r.y * sy,
                                                     width: r.w * sx, height: r.h * sy),
                                 cornerRadius: r.rx * min(sx, sy))
                    if g.angle != 0 {
                        var t = CGAffineTransform(translationX: g.cx * sx, y: g.cy * sy)
                        t = t.rotated(by: g.angle * .pi / 180)
                        t = t.translatedBy(x: -g.cx * sx, y: -g.cy * sy)
                        p = p.applying(t)
                    }
                    ctx.fill(p, with: .color(color))
                }
            }
        }
        .background(Color.white)
    }

    struct Rect { var x, y, w, h, rx: CGFloat }
    struct Group { var fill: String; var angle: CGFloat; var cx, cy: CGFloat; var rects: [Rect] }

    static func parseGroups(_ svg: String) -> [Group] {
        var out: [Group] = []
        let ns = svg as NSString
        guard let gRe = try? NSRegularExpression(pattern: "<g\\s+fill=\"([^\"]+)\"([^>]*)>([\\s\\S]*?)</g>") else { return out }
        let rRe = try? NSRegularExpression(pattern: "<rect\\s+x=\"([-\\d.]+)\"\\s+y=\"([-\\d.]+)\"\\s+width=\"([-\\d.]+)\"\\s+height=\"([-\\d.]+)\"(?:\\s+rx=\"([-\\d.]+)\")?")
        let tRe = try? NSRegularExpression(pattern: "rotate\\(\\s*([-\\d.]+)\\s+([-\\d.]+)\\s+([-\\d.]+)\\s*\\)")
        gRe.enumerateMatches(in: svg, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m = m else { return }
            let fill = ns.substring(with: m.range(at: 1))
            let attrs = ns.substring(with: m.range(at: 2))
            let body = ns.substring(with: m.range(at: 3))
            var angle: CGFloat = 0, cx: CGFloat = 0, cy: CGFloat = 0
            if let tRe = tRe, let tm = tRe.firstMatch(in: attrs, range: NSRange(location: 0, length: (attrs as NSString).length)) {
                let a = attrs as NSString
                angle = CGFloat(Double(a.substring(with: tm.range(at: 1))) ?? 0)
                cx = CGFloat(Double(a.substring(with: tm.range(at: 2))) ?? 0)
                cy = CGFloat(Double(a.substring(with: tm.range(at: 3))) ?? 0)
            }
            var rects: [Rect] = []
            let bs = body as NSString
            rRe?.enumerateMatches(in: body, range: NSRange(location: 0, length: bs.length)) { rm, _, _ in
                guard let rm = rm else { return }
                func num(_ i: Int, _ d: Double) -> CGFloat { CGFloat(Double(bs.substring(with: rm.range(at: i))) ?? d) }
                rects.append(Rect(x: num(1, 0), y: num(2, 0), w: num(3, 0), h: num(4, 0), rx: num(5, 0)))
            }
            if !rects.isEmpty { out.append(Group(fill: fill, angle: angle, cx: cx, cy: cy, rects: rects)) }
        }
        return out
    }
}

struct LoginView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @FocusState private var focus: Field?

    private enum Field: Hashable { case phone, code, user, pass, regUser, regNick, regPass, regCap }

    @State private var isAgree = false
    @State private var showPair = false
    @State private var showTerms = false
    @State private var termsKind = 0
    @State private var sheet: Way? = nil
    @State private var appName = "我的App"
    @State private var logoPath: String?

    @State private var bgImage = ""

    @State private var themeTick = 0

    @State private var quickBusy = false

    @State private var error: String?

    @State private var avatarIndex = 0

    @State private var showVoiceLock = false

    @State private var showMoreWays = false

    @State private var diag = ""

    enum Way: String, Identifiable { case phone, password; var id: String { rawValue } }

    var body: some View {
        ZStack {
            loginBackground

            VStack(spacing: 0) {

                avatarPager
                    .padding(.top, 64)
                    .padding(.horizontal, 20)
                    ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                    Text(appName)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(LoginTheme.ink(colorScheme))
                        .padding(.top, 16)
                    Text(Tr("登录后同步最近的聊天记录"))
                        .font(.system(size: 13))
                        .foregroundColor(LoginTheme.inkSub(colorScheme))
                        .padding(.top, 18)

                    Spacer(minLength: 44)

                    Button {
                        guard requireAgree() else { return }
                        let last = app.accounts.first(where: { $0.avatar == app.lastAvatar }) ?? app.accounts.first
                        if let acc = last {
                            quickLogin(account: acc)
                        } else {
                            showMoreWays = true
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "message.fill")
                                .resizable()
                                .frame(width: 22, height: 22)
                            Text(Tr("星言登录"))
                                .font(.system(size: 16, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)

                        .background {
                            ZStack {
                                GlassBackground(shape: RoundedRectangle(cornerRadius: 16, style: .continuous),
                                                opacity: 1, seed: 0.28)
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(LoginTheme.accent.opacity(isAgree ? 0.88 : 0.38))
                            }
                        }
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(isAgree ? 0.50 : 0.25), lineWidth: 0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    Button { showMoreWays = true } label: {
                        HStack(spacing: 4) {
                            Text(Tr("更多登录方式"))
                                .font(.system(size: 13.5))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10.5, weight: .semibold))
                        }
                        .foregroundColor(LoginTheme.inkSub(colorScheme))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 18)

                    .sheet(isPresented: $showMoreWays) {
                        LoginWaysSheet(

                            onPhone: { openWay(.phone) },
                            onPassword: { openWay(.password) },
                            onFace: { if requireAgree() { showMoreWays = false; afterSheet { faceLogin() } } },
                            onVoice: { if requireAgree() { showMoreWays = false; afterSheet { voiceLogin() } } })

                    }

                    if let e = error {
                        Text(e)
                            .font(.system(size: 13))
                            .foregroundColor(C.red)
                            .multilineTextAlignment(.center)
                            .padding(.top, 12)
                    }

                    Spacer(minLength: 26)

                    HStack(alignment: .top, spacing: 8) {
                        Button { isAgree.toggle() } label: {
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(isAgree ? LoginTheme.accent : LoginTheme.disabledGray, lineWidth: 1.4)
                                .background(RoundedRectangle(cornerRadius: 3)
                                    .fill(isAgree ? LoginTheme.accent : Color.clear))
                                .frame(width: 16, height: 16)
                                .overlay(isAgree
                                         ? Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundColor(.white)
                                         : nil)
                        }
                        .padding(.top, 1)

                        Text(.init("我已阅读并同意 [《用户协议》](terms://0) 和 [《隐私政策》](terms://1)"))
                            .font(.system(size: 12))
                            .foregroundColor(LoginTheme.ink(colorScheme))
                            .tint(LoginTheme.accent2)
                            .environment(\.openURL, OpenURLAction { url in
                                if url.scheme == "terms" {
                                    termsKind = Int(url.host ?? "0") ?? 0
                                    showTerms = true
                                }
                                return .handled
                            })
                    }

                    Button {
                        diag = "诊断中…"
                        Task {
                            var lines: [String] = []
                            let saved = UserDefaults.standard.string(forKey: "chris.server") ?? "(空)"
                            lines.append("缓存地址: \(saved)")
                            lines.append("主入口: \(API.shared.server)")
                            lines.append("候选: " + API.shared.diagCandidates.joined(separator: " → "))
                            let host = String(API.shared.server.split(separator: ":").first ?? "")
                            let ips = API.resolve(host)
                            lines.append("DNS(\(host)): " + (ips.isEmpty ? "解析不出来" : ips.joined(separator: ", ")))
                            lines.append("请求: " + (await API.shared.probe("/api/version")))
                            lines.append("公网 apple: " + (await API.shared.probeAbsolute("https://www.apple.com/")))
                            lines.append("明文 8899: " + (await API.shared.probeAbsolute("http://43.242.194.89:8899/api/version")))

                            let br = await API.shared.probeText(API.shared.base + "/api/branding", 1500)
                            if let r = br.range(of: "iceServers") {
                                lines.append("ICE: " + String(String(br[r.lowerBound...]).prefix(110)))
                            } else {
                                lines.append("ICE: " + String(br.prefix(80)))
                            }
                            let hls = "dy_7687095302297945786-tmuo257g7"
                            lines.append("HLS列表: " + (await API.shared.probeAbsolute(API.shared.base + "/hls/\(hls)/index.m3u8")))
                            lines.append("HLS切片: " + (await API.shared.probeAbsolute(API.shared.base + "/hls/\(hls)/seg_00000.ts")))
                            diag = lines.joined(separator: "\n")
                        }
                    } label: {
                        Text(Tr("连接诊断"))
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(LoginTheme.accent)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(Capsule().stroke(LoginTheme.accent.opacity(0.5), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 16)

                    if !diag.isEmpty {
                        Text(diag)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(LoginTheme.ink(colorScheme))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.06)))
                            .padding(.top, 8)
                    }

                    HStack(spacing: 5) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                        Text(Tr("全程 HTTPS 加密传输，密码只以加密哈希保存"))
                            .font(.system(size: 11.5))
                    }
                    .foregroundColor(LoginTheme.inkSub(colorScheme))
                    .padding(.top, 14)

                    Spacer()

                    Text("V1.0.0")
                        .font(.system(size: 11))
                        .foregroundColor(LoginTheme.inkSub(colorScheme))
                        .padding(.top, 60)
                        .padding(.bottom, 20)
                }
                .padding(.horizontal, 20)
                .frame(minHeight: UIScreen.main.bounds.height - 170, alignment: .top)
            }
            .background(Color.clear)
            .scrollContentBackground(.hidden)
        }
        .sheet(isPresented: $showPair) { PairSheet() }
        .sheet(isPresented: $showTerms) { TermsSheet(kind: termsKind) }
        .sheet(isPresented: $showVoiceLock) {

            VoiceUnlockView { voiceLoginPassed() }
        }
        .sheet(item: $sheet) { w in
            if w == .phone { PhoneLoginView() } else { AccountLoginSheet(mode: w) }
        }
        .onAppear {
            Task {
                await loadLoginBranding()
            }
        }
        }
    }

    private func loadLoginBranding() async {
        for attempt in 0..<4 {
            if let b = await API.shared.branding() {
                LoginTheme.apply(b)

                app.sliderLogin = b.sliderLogin ?? true
                if let n = b.harmonyLogin?.appName ?? b.login?.appName ?? b.appName, !n.isEmpty { appName = n }
                if let lg = b.harmonyLogin?.logo ?? b.login?.logo ?? b.logo, !lg.isEmpty { logoPath = lg }
                bgImage = b.login?.bgImage ?? ""
                themeTick += 1
                return
            }
            if attempt < 3 { try? await Task.sleep(nanoseconds: 1_500_000_000) }
        }
    }

    private var avatarPager: some View {
        VStack(spacing: 8) {
            if app.accounts.isEmpty {

                Group {
                    if let p = logoPath {
                        RemoteImage(path: p, icon: "message.fill", mode: .fill)
                    } else if let img = AppIconImage.image {
                        Image(uiImage: img).resizable()
                    } else {
                        Circle().foregroundColor(.gray.opacity(0.2))
                    }
                }
                .frame(width: 80, height: 80)
                .clipShape(Circle())
            } else {
                HStack(spacing: 6) {
                    if app.accounts.count > 1 {
                        Button { withAnimation { avatarIndex = max(0, avatarIndex - 1) } } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(avatarIndex > 0 ? LoginTheme.accent : LoginTheme.disabledGray)
                                .frame(width: 30, height: 60)
                        }
                        .disabled(avatarIndex <= 0)
                    }
                    TabView(selection: $avatarIndex) {
                    ForEach(Array(app.accounts.enumerated()), id: \.element.id) { idx, acc in
                        Group {
                            if !acc.avatar.isEmpty {
                                RemoteImage(path: acc.avatar, icon: "person.fill", mode: .fill)
                            } else {
                                Circle().fill(LoginTheme.accent.opacity(0.25))
                                    .overlay(Text(String(acc.nickname.prefix(1)))
                                        .font(.system(size: 30, weight: .semibold))
                                        .foregroundColor(LoginTheme.accent))
                            }
                        }
                        .frame(width: 80, height: 80)
                        .clipShape(Circle())
                        .contentShape(Circle())
                        .onTapGesture { quickLogin(account: acc) }
                        .tag(idx)
                    }
                }
                    .tabViewStyle(.page(indexDisplayMode: app.accounts.count > 1 ? .always : .never))
                    .frame(height: 108)
                    .frame(maxWidth: app.accounts.count > 1 ? .infinity : 96)
                    if app.accounts.count > 1 {
                        Button { withAnimation { avatarIndex = min(app.accounts.count - 1, avatarIndex + 1) } } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(avatarIndex < app.accounts.count - 1 ? LoginTheme.accent : LoginTheme.disabledGray)
                                .frame(width: 30, height: 60)
                        }
                        .disabled(avatarIndex >= app.accounts.count - 1)
                    }
                }

                if app.accounts.count > 1 {
                    Text(Tr("← 左右滑动切换账号，点头像直接登录 →"))
                        .font(.system(size: 11))
                        .foregroundColor(LoginTheme.sub ?? .secondary)
                } else {
                    Text(quickBusy ? "正在登录…" : "点一下头像，快捷登录")
                        .font(.system(size: 12))
                        .foregroundColor(LoginTheme.accent)
                }
                Text(app.accounts[min(avatarIndex, app.accounts.count - 1)].nickname)
                    .font(.system(size: 13))
                    .foregroundColor(LoginTheme.sub ?? .secondary)
            }
        }
        .onChange(of: app.accounts.count) { _ in clampAvatarIndex() }
    }

    private func clampAvatarIndex() {
        let maxIdx = max(0, app.accounts.count - 1)
        if avatarIndex > maxIdx { avatarIndex = maxIdx }
    }

    private var loginBackground: some View {
        ZStack {
            if !bgImage.isEmpty {
                RemoteImage(path: bgImage, icon: "photo", mode: .fill)
                    .ignoresSafeArea()
                Color(.systemBackground).opacity(0.30).ignoresSafeArea()
            } else {
                Color(.systemBackground).ignoresSafeArea()
            }
        }
        .id(themeTick)
    }

    func loginWithWechat() {

        showPair = true
    }

    @discardableResult
    private func requireAgree() -> Bool {
        if isAgree { return true }
        error = "请先勾选并同意《用户协议》和《隐私政策》"
        return false
    }

    private func afterSheet(_ run: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { run() }
    }

    private func openWay(_ w: Way) {
        guard requireAgree() else { return }
        showMoreWays = false
        afterSheet { sheet = w }
    }

    private var hasSavedLogin: Bool {
        !API.shared.token.isEmpty || !app.lastAvatar.isEmpty
    }

    private func faceLogin() {
        guard !quickBusy else { return }
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else {
            error = "这台设备还不能用人脸识别（要先在密码登录里登过一次，且手机支持 Face ID）"
            return
        }
        let list = app.accounts
        guard !list.isEmpty else {
            error = "先用密码或手机号登录一次，之后就能刷脸进"
            return
        }
        let acc = list[min(avatarIndex, list.count - 1)]
        quickBusy = true
        error = nil
        ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                           localizedReason: "刷脸登录 CHRIS") { ok, _ in
            DispatchQueue.main.async {
                quickBusy = false
                if ok { quickLogin(account: acc) }
                else { error = "人脸没认出来，或者你取消了" }
            }
        }
    }

    private func quickLogin(account: SavedAccount? = nil) {
        guard requireAgree() else { return }
        guard !quickBusy else { return }
        quickBusy = true
        error = nil
        Task {
            let saved = account.map { AccountStore.token(for: $0.username) } ?? ""
            let ok = await app.quickLogin(token: saved.isEmpty ? nil : saved,
                                          username: account?.username,
                                          switchingAccount: account != nil)
            quickBusy = false
            if !ok { error = "登录状态已过期，请重新输入密码登录" }
        }
    }

    private func voiceLogin() {
        guard !quickBusy else { return }
        guard VoiceLockStore.enabled else {
            error = "这台手机还没开通声音锁：先用密码登录一次，再到 我 → 设置 → 账号与安全 → 声音锁 里开通"
            return
        }
        guard !app.accounts.isEmpty else {
            error = "先用密码登录一次，之后就能用声音锁进"
            return
        }
        error = nil
        showVoiceLock = true
    }

    private func voiceLoginPassed() {
        let list = app.accounts
        guard !list.isEmpty else { return }
        let bound = VoiceLockStore.boundUser
        let acc = list.first(where: { $0.username == bound }) ?? list[min(avatarIndex, list.count - 1)]
        if let i = list.firstIndex(where: { $0.username == acc.username }) { avatarIndex = i }
        quickLogin(account: acc)
    }
}

struct AccountLoginSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focus: Field?

    private enum Field: Hashable { case phone, code, user, pass }

    var mode: LoginView.Way

    @State private var phone = ""
    @State private var code = ""
    @State private var username = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @State private var showReg = false
    @State private var showUnfreeze = false
    @State private var showReset = false

    @State private var sliderTicket = ""
    @State private var captchaKey = 0

    @State private var showSlider = false

    @State private var showPassword = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if mode == .phone {
                        row { TextField("手机号", text: $phone).keyboardType(.numberPad).focused($focus, equals: .phone)
                            .foregroundColor(LoginTheme.ink(colorScheme)) }
                        HairLine(color: C.navLine)
                        row {
                            TextField("验证码", text: $code).keyboardType(.numberPad).focused($focus, equals: .code)
                                .foregroundColor(LoginTheme.ink(colorScheme))
                            Button(Tr("获取验证码")) { sendCode() }
                                .font(.system(size: 14)).foregroundColor(C.loginGreen)
                        }
                    } else {
                        row { TextField("账号 / 用户名", text: $username).focused($focus, equals: .user)
                            .foregroundColor(LoginTheme.ink(colorScheme))
                            .textInputAutocapitalization(.never).autocorrectionDisabled(true) }
                        HairLine(color: C.navLine)

                        row {
                            Group {
                                if showPassword {
                                    TextField("密码", text: $password)
                                } else {
                                    SecureField("密码", text: $password)
                                }
                            }
                            .focused($focus, equals: .pass)
                            .autocorrectionDisabled(true)
                            .textInputAutocapitalization(.never)
                            .privacySensitive()
                            .foregroundColor(LoginTheme.ink(colorScheme))

                            Button {
                                let wasFocus = (focus == .pass)
                                showPassword.toggle()
                                if wasFocus {
                                    DispatchQueue.main.async { focus = .pass }
                                }
                            } label: {
                                Image(systemName: showPassword ? "eye.slash" : "eye")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(LoginTheme.ink(colorScheme).opacity(0.45))
                                    .frame(width: 34, height: 34)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if let e = error {
                        Text(e).font(.system(size: 13)).foregroundColor(C.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 12)
                    }

                    if isBanned {
                        Button {
                            app.show(error ?? Tr("该账号已被限制登录，请通过客服提交申诉"))
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.shield.fill")
                                Text(Tr("账号已被限制登录 · 查看处罚说明"))
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(LoginTheme.accent2)
                            .cornerRadius(14)
                        }
                        .padding(.top, 12)
                    }

                    if isFrozen {
                        Button {
                            showUnfreeze = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "snowflake")
                                Text(Tr("账号被冻结了？点这里自助解冻"))
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(LoginTheme.accent2)
                            .cornerRadius(14)
                        }
                        .padding(.top, 12)
                    }
                    Button { submit() } label: {
                        HStack(spacing: 8) {
                            if busy { ProgressView().progressViewStyle(.circular).tint(.white) }
                            Text(busy ? "请稍候…" : "登 录").font(.system(size: 16, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(LoginTheme.accent)
                        .cornerRadius(16)
                    }
                    .disabled(busy)
                    .padding(.top, 20)

                    if mode == .password {
                        HStack(spacing: 16) {

                            Button(Tr("忘记密码？")) { showReset = true }
                            Text("·").foregroundColor(C.subLabel)
                            Button(Tr("还没有账号？去注册")) { showReg = true }
                        }
                        .font(.system(size: 13)).foregroundColor(LoginTheme.accent2)
                        .padding(.top, 16)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
            }
            .background(Color(.systemBackground).ignoresSafeArea())
            .navigationTitle(mode == .phone ? "手机号登录" : "账号密码登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button(Tr("取消")) { dismiss() } }
            }
            .sheet(isPresented: $showReg) { RegisterSheet() }

            .sheet(isPresented: $showSlider) {
                SliderSheet(freshKey: captchaKey, onPass: { t in
                    sliderTicket = t
                    error = nil
                    submit()
                })
            }
            .sheet(isPresented: $showReset) { ResetPasswordSheet() }
            .sheet(isPresented: $showUnfreeze) {
                UnfreezeSheet().environmentObject(app)
            }
        }
    }

    private var isBanned: Bool {
        let e = error ?? ""
        return e.contains("禁用") || e.contains("封禁")
    }

    private var isFrozen: Bool {
        (error ?? "").contains("冻结")
    }

    private func row<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        HStack(spacing: 8) { c() }
            .font(.system(size: 15))
            .frame(height: 54).padding(.horizontal, 14)
            .background(Color.dyn(0xFFFFFF, 0x1C1C1E))
    }

    private func sendCode() {
        let p = phone.trimmingCharacters(in: .whitespaces)
        if p.count < 5 { error = "请填写手机号"; return }
        error = nil
        Task {
            do {
                if let dev = try await API.shared.phoneCode(phone: p) {
                    code = dev; app.show("验证码：\(dev)")
                } else { app.show(Tr("验证码已发送")) }
            } catch { self.error = (error as? APIError)?.errorDescription ?? "发送失败" }
        }
    }

    private func submit() {
        busy = true; error = nil
        Task {
            do {
                if mode == .phone {
                    let p = phone.trimmingCharacters(in: .whitespaces)
                    if p.isEmpty || code.isEmpty { throw APIError.message("请填写手机号和验证码") }
                    try await app.login(phone: p, code: code)
                } else {
                    let u = username.trimmingCharacters(in: .whitespaces)
                    if u.isEmpty || password.isEmpty { throw APIError.message("请填写账号和密码") }

                    try await app.login(username: u, password: password, sliderTicket: sliderTicket)
                }
                dismiss()
            } catch APIError.needSlider {

                sliderTicket = ""
                captchaKey += 1
                showSlider = true
                error = nil
            } catch {
                let msg = (error as? APIError)?.errorDescription ?? "登录失败"
                self.error = msg

                if msg.contains("滑动验证") || msg.contains("安全验证") {
                    sliderTicket = ""
                    captchaKey += 1
                }
            }
            busy = false
        }
    }
}

struct UnbanSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    let preUser: String
    let prePass: String

    @State private var username = ""
    @State private var password = ""
    @State private var idCard = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(Tr("账号被管理员禁用后，可以在这里用身份证号自己解开。号码要真实合法（18 位，最后一位可能是 X）。同一张身份证只能绑定一个账号，解封动作会写进后台审计日志。"))
                        .font(.system(size: 12.5))
                        .foregroundColor(.secondary)
                        .padding(.bottom, 14)

                    field { TextField("被封的账号（用户名 / 手机号）", text: $username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled(true) }
                    HairLine(color: C.navLine)
                    field { SecureField("该账号的密码", text: $password)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                        .privacySensitive() }
                    HairLine(color: C.navLine)
                    field { TextField("身份证号（18 位）", text: $idCard)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled(true) }

                    if let e = error {
                        Text(e).font(.system(size: 13)).foregroundColor(C.red)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
                    }

                    Button { submit() } label: {
                        HStack(spacing: 8) {
                            if busy { ProgressView().progressViewStyle(.circular).tint(.white) }
                            Text(busy ? "正在核验…" : "提交并解封").font(.system(size: 16, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(LoginTheme.accent)
                        .cornerRadius(16)
                    }
                    .disabled(busy)
                    .padding(.top, 20)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
            .background(Color(.systemBackground).ignoresSafeArea())
            .navigationTitle(Tr("身份证自助解封"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button(Tr("取消")) { dismiss() } }
            }
        }
        .onAppear {
            if username.isEmpty { username = preUser }
            if password.isEmpty { password = prePass }
        }
    }

    private func field<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        HStack(spacing: 8) { c() }
            .font(.system(size: 15))
            .frame(height: 54).padding(.horizontal, 14)
            .background(Color.dyn(0xFFFFFF, 0x1C1C1E))
    }

    private func submit() {
        let u = username.trimmingCharacters(in: .whitespaces)
        let idc = idCard.trimmingCharacters(in: .whitespaces).uppercased()
        if u.isEmpty { error = "请填写被封的账号"; return }
        if password.isEmpty { error = "请填写账号密码"; return }
        if idc.count != 18 { error = "身份证要 18 位，最后一位可以是 X"; return }
        busy = true; error = nil
        Task {
            do {
                let user = try await API.shared.unban(username: u, password: password, idCard: idc)
                await app.finishLogin(user)
                app.show(Tr("解封成功，已登录"))
                dismiss()
            } catch { self.error = (error as? APIError)?.errorDescription ?? "解封失败" }
            busy = false
        }
    }
}

struct RegisterSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    private enum Field: Hashable { case phone, code }

    @State private var phone = UserDefaults.standard.string(forKey: "chris.lastPhone") ?? ""
    @State private var code = ""
    @State private var countdown = 0
    @State private var codeSent = false
    @State private var busy = false
    @State private var error: String?
    @State private var sliderTicket = ""
    @State private var sliderSeed = 0
    @State private var showSlider = false
    @State private var countdownTask: Task<Void, Never>?
    @FocusState private var focus: Field?

    private var validPhone: Bool {
        phone.range(of: #"^1[3-9]\d{9}$"#, options: .regularExpression) != nil
    }

    private var canSubmit: Bool {
        validPhone && codeSent && code.count == 6 && !busy
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    registrationHero

                    Text("创建你的星言账号")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(C.label)
                    Text("手机号验证后自动生成星言号，之后统一用绑定手机号登录。")
                        .font(.system(size: 13))
                        .foregroundColor(C.subLabel)

                    VStack(spacing: 0) {
                        TextField("手机号", text: $phone)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                            .focused($focus, equals: .phone)
                            .font(.system(size: 16.5))
                            .padding(.horizontal, 14)
                            .frame(height: 54)
                            .onChange(of: phone) { value in
                                phone = String(value.filter(\.isNumber).prefix(11))
                                error = nil
                            }

                        HairLine(color: C.navLine)

                        HStack(spacing: 10) {
                            TextField("6 位短信验证码", text: $code)
                                .keyboardType(.numberPad)
                                .textContentType(.oneTimeCode)
                                .focused($focus, equals: .code)
                                .font(.system(size: 16.5))
                                .onChange(of: code) { value in
                                    code = String(value.filter(\.isNumber).prefix(6))
                                    error = nil
                                }
                            Button(countdown > 0 ? "\(countdown) 秒" : (codeSent ? "重新获取" : "获取验证码")) {
                                requestCode()
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(canRequestCode ? C.green : C.subLabel)
                            .disabled(!canRequestCode)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 54)
                    }
                    .background(C.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(C.navLine, lineWidth: 0.6))
                    .shadow(color: Color.black.opacity(scheme == .dark ? 0.18 : 0.055),
                            radius: 12, y: 5)

                    if let e = error {
                        Text(e)
                            .font(.system(size: 13))
                            .foregroundColor(C.red)
                    }

                    Button { submit() } label: {
                        HStack(spacing: 8) {
                            if busy { ProgressView().tint(.white).scaleEffect(0.85) }
                            Text(busy ? "请稍候…" : "注册并登录")
                                .font(.system(size: 16, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(canSubmit ? LoginTheme.accent : LoginTheme.disabledGray.opacity(0.75))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit)

                    HStack(spacing: 7) {
                        Image(systemName: "lock.shield.fill")
                        Text("验证码仅用于本次注册 · 加密传输")
                    }
                    .font(.system(size: 11.5))
                    .foregroundColor(C.subLabel)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 3)
                }
                .padding(20)
            }
            .background(Color(.systemBackground).ignoresSafeArea())
            .navigationTitle(Tr("手机号注册"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button(Tr("取消")) { dismiss() } } }
        }
        .sheet(isPresented: $showSlider) {
            SliderSheet(freshKey: sliderSeed) { ticket in
                sliderTicket = ticket
                showSlider = false
                requestCode()
            }
        }
        .onDisappear { countdownTask?.cancel() }
    }

    private var canRequestCode: Bool {
        validPhone && countdown == 0 && !busy
    }

    private var registrationHero: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(OrbitTheme.jade.opacity(0.28), lineWidth: 1)
                    .frame(width: 58, height: 58)
                Circle()
                    .trim(from: 0.12, to: 0.78)
                    .stroke(OrbitTheme.gold,
                            style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                    .frame(width: 68, height: 68)
                    .rotationEffect(.degrees(-28))
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(OrbitTheme.jade)
            }
            .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 4) {
                Text("加入星言")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(C.label)
                Text("真实、克制、只属于你的通讯空间")
                    .font(.system(size: 12.5))
                    .foregroundColor(C.subLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(C.navLine, lineWidth: 0.6))
        .padding(.bottom, 2)
    }

    private func requestCode() {
        guard canRequestCode else { return }
        busy = true
        error = nil
        Task {
            do {
                let dev = try await API.shared.phoneCode(phone: phone,
                                                          sliderTicket: sliderTicket)
                sliderTicket = ""
                codeSent = true
                startCountdown()
                if let dev, !dev.isEmpty {
                    code = dev
                    focus = .code
                }
            } catch APIError.needSlider {
                sliderTicket = ""
                sliderSeed += 1
                showSlider = true
            } catch {
                self.error = (error as? APIError)?.errorDescription ?? "验证码没发出去"
            }
            busy = false
        }
    }

    private func submit() {
        guard canSubmit else {
            if !codeSent { requestCode() }
            return
        }
        busy = true
        error = nil
        Task { @MainActor in
            do {
                try await app.login(phone: phone, code: code)
                UserDefaults.standard.set(phone, forKey: "chris.lastPhone")
                app.show(Tr("注册成功"))
                dismiss()
            } catch {
                self.error = (error as? APIError)?.errorDescription ?? "注册失败"
            }
            busy = false
        }
    }

    private func startCountdown() {
        countdownTask?.cancel()
        countdown = 60
        countdownTask = Task { @MainActor in
            while countdown > 0, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                countdown -= 1
            }
        }
    }
}

func qrImage(_ text: String, size: CGFloat) -> UIImage? {
    guard !text.isEmpty, let f = CIFilter(name: "CIQRCodeGenerator") else { return nil }
    f.setValue(Data(text.utf8), forKey: "inputMessage")
    f.setValue("M", forKey: "inputCorrectionLevel")
    guard let out = f.outputImage else { return nil }
    let scale = size / max(out.extent.width, 1)
    let scaled = out.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let ctx = CIContext(options: nil)
    guard let cg = ctx.createCGImage(scaled, from: scaled.extent) else { return nil }
    return UIImage(cgImage: cg)
}

struct PairSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var status = "正在生成…"
    @State private var fail = false
    @State private var timer: Timer?

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Text(Tr("用已登录的手机确认，这台设备就能进入"))
                    .font(.system(size: 14)).foregroundColor(.secondary)
                    .multilineTextAlignment(.center).padding(.top, 20)

                if let q = qrImage("xingyan://pair?code=" + code, size: 190) {
                    Image(uiImage: q)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 190, height: 190)
                        .padding(10)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 0.5))
                        .opacity(code.isEmpty || fail ? 0.22 : 1)
                } else {
                    ProgressView().frame(width: 190, height: 190)
                }

                Text(code.isEmpty ? "······" : code)
                    .font(.system(size: 24, weight: .semibold, design: .monospaced))
                    .tracking(6)

                Text(fail
                     ? "这个码过期了，点下面重新生成"
                     : "另一台已登录的手机：星言 → 扫一扫；或者 我 → 设置 → 登录设备管理 → 确认新设备登录，把这 6 位数字填进去")
                    .font(.system(size: 12.5)).foregroundColor(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 24)

                if fail {
                    Button(Tr("重新生成")) { start() }
                        .font(.system(size: 15, weight: .semibold)).foregroundColor(C.loginGreen)
                } else {
                    ProgressView()
                    Text(status).font(.system(size: 12)).foregroundColor(.secondary)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(Color(.systemBackground).ignoresSafeArea())
            .navigationTitle(Tr("星言登录"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button(Tr("取消")) { stop(); dismiss() } } }
        }
        .onAppear { start() }
        .onDisappear { stop() }
    }

    private func start() {
        fail = false; status = "正在生成…"
        Task {
            do {

                let dev = AppInfo.deviceModel + " · " + AppInfo.deviceOs
                let r = try await API.shared.pairStart(device: dev)
                code = r.code; status = "等待确认…"
                timer?.invalidate()
                timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in poll() }
            } catch {
                fail = true
                status = (error as? APIError)?.errorDescription ?? "生成失败"
            }
        }
    }
    private func poll() {
        guard !code.isEmpty else { return }
        Task {
            guard let r = try? await API.shared.pairStatus(code: code) else { return }
            switch r.status {
            case "approved":
                stop()
                if let t = r.token, !t.isEmpty { API.shared.setToken(t) }
                await app.refreshAll(); Realtime.shared.start(); dismiss()
            case "expired":
                stop(); fail = true
            default:
                status = "等待确认…"
            }
        }
    }
    private func stop() { timer?.invalidate(); timer = nil }
}

struct TermsSheet: View {
    @Environment(\.dismiss) private var dismiss
    var kind: Int

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(kind == 0 ? "用户协议" : "隐私政策").font(.system(size: 19, weight: .semibold))

                    Text(LoginTheme.text(kind: kind))
                    .font(.system(size: 14)).lineSpacing(6)
                }
                .padding(20)
            }
            .background(Color(.systemBackground).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button(Tr("好")) { dismiss() } } }
        }
    }
}

struct DialRegion: Identifiable, Hashable {
    let id: String
    let flag: String
    let name: String
    let dial: String
}

let dialRegions: [DialRegion] = [
    .init(id: "CN", flag: "🇨🇳", name: "中国大陆", dial: "86"),
    .init(id: "HK", flag: "🇭🇰", name: "中国香港", dial: "852"),
    .init(id: "MO", flag: "🇲🇴", name: "中国澳门", dial: "853"),
    .init(id: "US", flag: "🇺🇸", name: "美国 / 加拿大", dial: "1"),
    .init(id: "JP", flag: "🇯🇵", name: "日本", dial: "81"),
    .init(id: "KR", flag: "🇰🇷", name: "韩国", dial: "82"),
    .init(id: "SG", flag: "🇸🇬", name: "新加坡", dial: "65"),
    .init(id: "MY", flag: "🇲🇾", name: "马来西亚", dial: "60"),
    .init(id: "TH", flag: "🇹🇭", name: "泰国", dial: "66"),
    .init(id: "GB", flag: "🇬🇧", name: "英国", dial: "44"),
    .init(id: "AU", flag: "🇦🇺", name: "澳大利亚", dial: "61")
]

struct CountryPickerView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var index: Int
    @State private var q = ""

    private var list: [Int] {
        dialRegions.indices.filter { i in
            let r = dialRegions[i]
            return q.isEmpty
                || r.name.contains(q)
                || r.dial.contains(q)
                || r.id.lowercased().contains(q.lowercased())
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(list, id: \.self) { i in
                    let r = dialRegions[i]
                    Button {
                        index = i
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Text(r.flag).font(.system(size: 20))
                            Text(r.name).foregroundColor(C.label)
                            Spacer(minLength: 0)
                            Text("+" + r.dial).foregroundColor(C.subLabel)
                            if i == index {
                                Image(systemName: "checkmark").foregroundColor(C.green)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .searchable(text: $q, prompt: Tr("搜索国家或区号"))
            .navigationTitle(Tr("选择国家和地区"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button(Tr("取消")) { dismiss() } } }
        }
    }
}

struct PhoneLoginView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) var dismiss

    @Environment(\.colorScheme) private var colorScheme
    @State private var phone = ""
    @State private var code = ""
    @State private var isAgree = false
    @State private var countDown = 0
    @State private var timer: Timer?
    @State private var error: String?
    @State private var busy = false
    @State private var showTerms = false
    @State private var termsKind = 0
    @State private var sliderTicket = ""
    @State private var sliderSeed = 0
    @State private var showSlider = false
    @FocusState private var focused: Bool

    @State private var showCountryPicker = false
    @State private var dialIdx = 0
    private var dial: DialRegion { dialRegions[min(max(dialIdx, 0), dialRegions.count - 1)] }

    private var fullPhone: String { dial.dial == "86" ? phone : ("+" + dial.dial + phone) }

    private var phoneLenOK: Bool {
        dial.dial == "86" ? phone.count == 11 : (phone.count >= 5 && phone.count <= 15)
    }
    private var hairline: some View {
        Rectangle().fill(Color.dyn(0xE2E2E6, 0x2C2C2E)).frame(height: 1.2)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Spacer(minLength: 30)
                    Text(Tr("手机号登录"))
                        .font(.system(size: 24, weight: .semibold))

                    VStack(spacing: 0) {
                        Button { showCountryPicker = true } label: {
                            HStack(spacing: 10) {
                                Text(dial.flag).font(.system(size: 19))
                                Text(dial.name)
                                    .font(.system(size: 16.5))
                                    .foregroundColor(C.label)
                                Spacer(minLength: 0)
                                Text("+" + dial.dial)
                                    .font(.system(size: 15.5))
                                    .foregroundColor(C.subLabel)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(Color.dyn(0xC0C0C6, 0x6B6B70))
                            }
                            .frame(height: 54)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .bottom) { hairline }

                        TextField("请输入手机号", text: $phone)
                            .keyboardType(.numberPad)
                            .font(.system(size: 16.5))
                            .frame(height: 54)
                            .focused($focused)
                            .overlay(alignment: .bottom) { hairline }

                        HStack(spacing: 10) {
                            TextField("请输入验证码", text: $code)
                                .keyboardType(.numberPad)
                                .font(.system(size: 16.5))
                            Button { sendCode() } label: {
                                Text(countDown > 0 ? "\(countDown)s" : Tr("获取验证码"))
                                    .font(.system(size: 14.5, weight: .semibold))
                                    .foregroundColor(countDown > 0 || !phoneLenOK
                                                     ? LoginTheme.disabledGray : LoginTheme.accent2)
                            }
                            .buttonStyle(.plain)
                            .disabled(countDown > 0 || !phoneLenOK)
                        }
                        .frame(height: 54)
                        .overlay(alignment: .bottom) { hairline }
                    }

                    Text(Tr("获取验证码后会收到一条短信，把 6 位数字填在上面"))
                        .font(.system(size: 12))
                        .foregroundColor(LoginTheme.inkSub(colorScheme))

                    Button {
                        phoneLogin()
                    } label: {
                        HStack(spacing: 8) {
                            if busy { ProgressView().progressViewStyle(.circular).tint(.white) }
                            Text(Tr("登录"))
                                .font(.system(size: 16, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(canSubmit ? LoginTheme.accent2 : LoginTheme.disabledGray)
                        .cornerRadius(16)
                    }
                    .disabled(!canSubmit)

                    if let e = error {
                        Text(e).font(.system(size: 13)).foregroundColor(C.red)
                    }

                    HStack(alignment: .top, spacing: 8) {
                        Button { isAgree.toggle() } label: {
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(isAgree ? LoginTheme.accent2 : LoginTheme.disabledGray, lineWidth: 1.4)
                                .background(RoundedRectangle(cornerRadius: 3)
                                    .fill(isAgree ? LoginTheme.accent2 : Color.clear))
                                .frame(width: 16, height: 16)
                                .overlay(isAgree
                                         ? Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundColor(.white)
                                         : nil)
                        }
                        .padding(.top, 1)

                        Text(.init("我已阅读并同意 [《用户协议》](terms://0) 和 [《隐私政策》](terms://1)"))
                            .font(.system(size: 12))
                            .tint(LoginTheme.accent2)
                            .environment(\.openURL, OpenURLAction { url in
                                if url.scheme == "terms" {
                                    termsKind = Int(url.host ?? "0") ?? 0
                                    showTerms = true
                                }
                                return .handled
                            })
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "chevron.left") }
                }
            }
        }
        .sheet(isPresented: $showTerms) { TermsSheet(kind: termsKind) }
        .sheet(isPresented: $showCountryPicker) { CountryPickerView(index: $dialIdx) }
        .sheet(isPresented: $showSlider) {
            SliderSheet(freshKey: sliderSeed) { ticket in
                sliderTicket = ticket
                showSlider = false
                sendCode()
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    var canSubmit: Bool {
        isAgree && phoneLenOK && code.count >= 4 && !busy
    }

    func sendCode() {
        error = nil
        Task {
            do {
                let dev = try await API.shared.phoneCode(phone: fullPhone,
                                                          sliderTicket: sliderTicket)
                sliderTicket = ""
                if let dev {
                    code = dev
                    app.show("验证码：\(dev)")
                } else {
                    app.show(Tr("验证码已发送"))
                }
            } catch APIError.needSlider {
                sliderTicket = ""
                sliderSeed += 1
                showSlider = true
            } catch {
                self.error = (error as? APIError)?.errorDescription ?? "发送失败"
            }
        }
        countDown = 60
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
            if countDown > 0 {
                countDown -= 1
            } else {
                t.invalidate()
            }
        }
    }

    func phoneLogin() {
        busy = true
        error = nil
        Task {
            do {
                try await app.login(phone: fullPhone, code: code)
                dismiss()
            } catch {
                self.error = (error as? APIError)?.errorDescription ?? "登录失败"
            }
            busy = false
        }
    }
}
