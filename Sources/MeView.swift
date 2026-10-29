import SwiftUI

struct MeView: View {
    @ObservedObject private var lang = LangStore.shared
    @State private var showMyQR = false
    @EnvironmentObject var app: AppState
    @State private var path = NavigationPath()

    @State private var items: [DiscoverItem] = []
    @State private var loaded = false
    @ObservedObject private var realtime = Realtime.shared

    @ObservedObject private var growth = GrowthStore.shared

    @ObservedObject private var member = MemberStore.shared

    @Environment(\.colorScheme) private var scheme

    @State private var teenOn = false
    @State private var showTeenCard = false

    @State private var statusPanel: StatusPanelKind? = nil

    private var memberActive: Bool { (app.me?.memberTier ?? "").isEmpty == false }
    private var gold: Color { Color(hexString: (app.me?.memberColor?.isEmpty == false) ? app.me!.memberColor! : "#E0B44A") }
    private var gold2: Color { Color(hexString: (app.me?.memberColor2?.isEmpty == false) ? app.me!.memberColor2! : "#B8862A") }

    private var friendCount: Int { app.contacts.count }

    private var daysText: String {
        let v = growth.totalDays
        let r = (v * 10).rounded() / 10
        return abs(r - r.rounded()) < 0.001 ? String(Int(r)) : String(format: "%.1f", r)
    }

    private var orbitMeTop: some View {
        VStack(spacing: 13) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("我的")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(OrbitTheme.ink)
                    Text(Tr("把生活留在这里"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(OrbitTheme.secondary)
                }

                Spacer(minLength: 8)

                Button { showMyQR = true } label: {
                    Image(systemName: "qrcode")
                        .font(.system(size: 15.5, weight: .semibold))
                        .foregroundStyle(OrbitTheme.ink)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(OrbitTheme.field))
                        .overlay(Circle().stroke(OrbitTheme.divider, lineWidth: 0.6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Tr("我的二维码"))

                Button { path.append("settings") } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(OrbitTheme.ink)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(OrbitTheme.field))
                        .overlay(Circle().stroke(OrbitTheme.divider, lineWidth: 0.6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Tr("设置"))
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                Button { path.append("profile") } label: {
                    HStack(spacing: 14) {
                        Avatar(path: app.me?.avatarPath ?? "", size: 66, radius: 22,
                               level: growth.shownLevel)

                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                if teenOn {
                                    UmbrellaIcon(color: Color(hex: 0x3E9BF0), size: 15)
                                }
                                Text(app.me?.name ?? Tr("星言用户"))
                                    .font(.system(size: 21, weight: .bold))
                                    .foregroundStyle(OrbitTheme.ink)
                                    .lineLimit(1)
                                if growthShow {
                                    QQLevelBadge(level: growth.shownLevel, size: 14, maxIcons: 3)
                                        .fixedSize()
                                }
                                MemberBadge(tier: app.me?.memberTier,
                                            short: app.me?.memberShort,
                                            color: app.me?.memberColor,
                                            color2: app.me?.memberColor2,
                                            height: 13)
                                    .fixedSize()
                            }

                            Text(Tr("星言号") + "：" + (app.me?.username ?? "-"))
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(OrbitTheme.secondary)
                                .lineLimit(1)
                                .copyOnLongPress(app.me?.username ?? "") { app.show($0) }

                            let note = ((app.me?.bio ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
                            Text(note.isEmpty ? Tr("点击编辑个人资料") : note)
                                .font(.system(size: 12))
                                .foregroundStyle(OrbitTheme.tertiary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(OrbitTheme.tertiary)
                    }
                    .padding(15)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Rectangle().fill(OrbitTheme.divider).frame(height: 0.5)

                HStack(spacing: 0) {
                    orbitMeStat(value: "\(friendCount)", title: Tr("朋友")) {
                        statusPanel = .friends
                    }
                    orbitMeDivider
                    orbitMeStat(value: daysText, title: Tr("活跃天")) {
                        path.append("level")
                    }
                    orbitMeDivider
                    orbitMeStat(value: "\(app.me?.momentCount ?? 0)", title: Tr("动态")) {
                        path.append("moments")
                    }
                }
                .padding(.vertical, 12)

                Rectangle().fill(OrbitTheme.divider).frame(height: 0.5)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        memberPill
                        statusChip
                        friendsStatusChip
                        if app.me?.ops == true {
                            manageChip
                        }
                    }
                    .padding(.horizontal, 14)
                }
                .frame(height: 48)
            }
            .background(OrbitTheme.cardBackground())
        }
        .padding(.top, L.safeTop + 10)
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private func orbitMeStat(value: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(value)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(OrbitTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(OrbitTheme.tertiary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var orbitMeDivider: some View {
        Rectangle()
            .fill(OrbitTheme.divider)
            .frame(width: 0.5, height: 28)
    }

    private var nativeMeList: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    NavigationLink(value: "profile") {
                        HStack(spacing: 12) {
                            Avatar(path: app.me?.avatarPath ?? "", size: 58, radius: 18,
                                   level: growth.shownLevel)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(app.me?.name ?? Tr("星言用户"))
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    if growthShow {
                                        QQLevelBadge(level: growth.shownLevel, size: 14, maxIcons: 2)
                                            .fixedSize()
                                    }
                                }
                                Text(Tr("星言号") + "：" + (app.me?.username ?? "-"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                let bio = (app.me?.bio ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                                Text(bio.isEmpty ? Tr("点击编辑个人资料") : bio)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    compactStatusActions
                }
                .padding(.vertical, 3)
            }

            ForEach(grouped.indices, id: \.self) { gi in
                Section {
                    ForEach(grouped[gi]) { item in
                        NavigationLink(value: routeKey(for: item)) {
                            nativeMeItemRow(item)
                        }
                    }
                }
            }

            if app.me?.ops == true {
                Section(header: Text(Tr("管理"))) {
                    NavigationLink(value: "manage") {
                        nativeSettingsIconRow(Tr("用户管理"),
                                              symbol: "person.2.badge.gearshape.fill",
                                              color: .indigo)
                    }
                    NavigationLink(value: "faces") {
                        nativeSettingsIconRow(Tr("人脸比对"),
                                              symbol: "face.smiling",
                                              color: C.green)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Tr("我的"))
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            app.me = try? await API.shared.me()
            await app.loadContacts()
            await MemberStore.shared.refresh()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showMyQR = true } label: {
                    Image(systemName: "qrcode")
                }
                .accessibilityLabel(Tr("我的二维码"))
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { path.append("settings") } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel(Tr("设置"))
            }
        }
    }

    private func nativeStat(value: String, title: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(value)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var compactStatusActions: some View {
        HStack(spacing: 9) {
            Button {
                statusPanel = .status
            } label: {
                Image(systemName: "face.smiling")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(moodOn ? Color.white : .primary)
                    .frame(width: 38, height: 38)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(moodOn
                                  ? AnyShapeStyle(LinearGradient(
                                      colors: [Color(hexString: moodC1), Color(hexString: moodC2)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
                                  : AnyShapeStyle(.thinMaterial))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(moodOn ? Color.white.opacity(0.30) : C.hairline, lineWidth: 0.6)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Tr("当前状态"))

            Button {
                statusPanel = .friends
            } label: {
                Image(systemName: "person.2.wave.2")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 38, height: 38)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.thinMaterial)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(C.hairline, lineWidth: 0.6)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Tr("朋友的状态"))
        }
        .fixedSize()
    }

    private func nativeMeItemRow(_ item: DiscoverItem) -> some View {
        let symbol = RowIcon.sf(action: item.action, label: item.label)
        let color = Color(hexString: item.color ?? "#4A90D9", fallback: 0x4A90D9)
        return nativeSettingsIconRow(Tr(item.label), symbol: symbol, color: color)
    }

    private func nativeSettingsIconRow(_ title: String, symbol: String,
                                       color: Color) -> some View {
        Label {
            Text(title)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(color)
                )
        }
    }

    private func routeKey(for item: DiscoverItem) -> String {
        let action = item.action ?? "soon"
        switch action {
        case "cards", "shop", "service", "favorites", "moments", "works",
             "stickers", "settings", "channels", "plugins":
            return action
        default:
            return "soon:" + item.label
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            nativeMeList

            .sheet(isPresented: $showMyQR) { MyQRView() }

            .sheet(item: $statusPanel) { k in
                Group {
                    if k == .friends {

                        FriendsStatusView().bottomPanel([.height(320), .medium, .large], open: .medium)
                    } else if (app.me?.moodIcon ?? "").isEmpty && (app.me?.moodText ?? "").isEmpty {
                        StatusView().bottomPanel([.height(340), .height(600), .large], open: .height(600))
                    } else {
                        StatusDetailView().bottomPanel([.height(340), .height(600), .large], open: .height(600))
                    }
                }
                .environmentObject(app)
            }

            .sheet(isPresented: $showTeenCard) {
                TeenModeView().environmentObject(app)
            }
            .navigationDestination(for: String.self) { key in
                if key == "settings" {
                    AppleSettingsView()
                } else if key == "moments" {

                    MomentsView(mineOnly: true)
                } else if key == "profile" {
                    ProfileEditView()
                } else if key == "member" {
                    MemberCenterView()
                } else if key == "service" {
                    ServiceView()
                } else if key == "favorites" {
                    FavoritesView()
                } else if key == "stickers" {
                    StickerView()
                } else if key == "works" {
                    WorksView()
                } else if key == "channels" {

                    ChannelsView()
                } else if key == "status" {

                    if (app.me?.moodIcon ?? "").isEmpty && (app.me?.moodText ?? "").isEmpty {
                        StatusView()
                    } else {
                        StatusDetailView()
                    }
                } else if key == "friendsStatus" {

                    FriendsStatusView()
                } else if key == "manage" {

                    UserManageView()
                } else if key == "faces" {

                    FaceReviewView()
                } else if key == "paypwd" {
                    PayPasswordView()
                } else if key == "gesture" {
                    GestureSetupView()
                } else if key == "voicelock" {
                    VoiceLockSetupView()
                } else if key == "level" {
                    MyLevelView()
                } else if key == "score" {
                    SecurityScoreView()
                } else if key == "switch" {
                    SwitchAccountView()
                } else if key == "realname" {
                    RealNameView()
                } else if key == "account" {
                    AccountSecurityView()
                } else if key == "pair" {
                    PairApproveView()
                } else if key == "devices" {

                    LoginDevicesView()
                } else if key == "devices.faq" {
                    DevicesFaqView()
                } else if key == "teen" {
                    TeenModeView()
                } else if key == "care" {
                    CareModeView()
                } else if key == "notify" {
                    NotifyView()
                } else if key == "privacy" {
                    PrivacyView()
                } else if key == "general" {
                    GeneralView()
                } else if key == "storage" {
                    StorageView()
                } else if key == "feedback" {
                    FeedbackView()
                } else if key == "about" {
                    AboutView()
                } else if key == "cards" {

                    CardsView()
                } else if key == "shop" {

                    MallAuthGate { MallNativeView() }
                } else if key == "eyes" {

                    EyesSettingsView()
                } else if key == "plugins" {

                    PluginsView()
                } else if key == "health" {

                    HealthCheckView()
                } else if key == "selfperm" {

                    SelfPermView()
                } else if key == "more" {

                    MoreSettingsView()
                } else if key == "setchat" {

                    ChatSettingsView()
                } else if key == "setcall" {

                    CallSettingsView()
                } else if key == "chatbg" {
                    ChatBackgroundSheet()
                } else if key == "changepwd" {
                    ChangePasswordSheet()
                } else if key == "g.theme" {
                    AppearanceView()
                } else if key == "g.lang" {
                    LanguageView()
                } else if key == "g.chatbg" {
                    ChatBackgroundSheet()
                } else if key == "g.storage" {
                    StorageView()
                } else if key == "g.history" {
                    ChatHistoryView()
                } else if key == "g.voice" {
                    VoiceChangerView()
                } else if key == "storage.manage" {
                    ChatHistoryView()
                } else if key == "feedback.history" {
                    FeedbackHistoryView()
                } else {
                    ComingSoonView(title: String(key.dropFirst(5)))
                }
            }
        }

        .onChange(of: realtime.event) { ev in
            if ev.user != nil || ev.type == "profile" {
                Task { app.me = try? await API.shared.me() }
            }
            if ev.type == "ui" { Task { await loadItems() } }
        }
        .task {
            if !loaded { await loadItems() }

            if let fresh = try? await API.shared.me(), fresh.ops != app.me?.ops {
                app.me = fresh
            }
            await MemberStore.shared.refresh()

            if let t = try? await API.shared.teen() { teenOn = t.enabled == true }
        }
    }

    private var grouped: [[DiscoverItem]] {
        var out: [[DiscoverItem]] = []
        var last: Int? = nil

        let serviceOff = UIConfig.num("serviceShow", 1) <= 0
        for it in items {
            if serviceOff, it.action == "service" { continue }
            let g = it.group ?? 1
            if last == nil || g != last! { out.append([]); last = g }
            out[out.count - 1].append(it)
        }
        return out
    }

    private func loadItems() async {
        if let list = try? await API.shared.mePage(), !list.isEmpty {
            items = list
            loaded = true
        } else if items.isEmpty {
            items = DiscoverItem.builtinMe
        }
    }

    private func open(_ item: DiscoverItem) {
        switch item.action ?? "soon" {
        case "cards": path.append("cards")
        case "shop": path.append("shop")
        case "service": path.append("service")
        case "favorites": path.append("favorites")
        case "moments": path.append("moments")
        case "works": path.append("works")
        case "stickers": path.append("stickers")
        case "settings": path.append("settings")

        case "channels": path.append("channels")

        case "plugins": path.append("plugins")
        default: path.append("soon:" + item.label)
        }
    }

    private var gap: some View {
        Rectangle().fill(OrbitTheme.canvas).frame(height: 10)
    }

    private var meGap: some View {
        Color.clear.frame(height: 10)
    }

    private var rowLine: some View {
        Rectangle()
            .fill(OrbitTheme.divider)
            .frame(height: 0.5)
            .padding(.leading, L.menuLineInset)
    }

    private var growthShow: Bool { UIConfig.num("growthShow", 1) > 0 }

    private var moodOn: Bool {
        !((app.me?.moodText ?? "").isEmpty && (app.me?.moodIcon ?? "").isEmpty)
            && !MoodColor.clean(app.me?.moodColor).isEmpty
    }
    private var moodC1: String { MoodColor.clean(app.me?.moodColor) }
    private var moodC2: String {
        let c2 = MoodColor.clean(app.me?.moodColor2)
        if !c2.isEmpty { return c2 }
        let s = MoodColor.shift(moodC1, to: true)
        return s.isEmpty ? moodC1 : s
    }

    private var topInk: Color {
        if moodOn { return MoodColor.isDark(moodC1) ? .white : C.label }
        return .white
    }

    private var topInk2: Color {
        if moodOn { return MoodColor.isDark(moodC1) ? Color.white.opacity(0.82) : C.label.opacity(0.55) }

        return Color.white.opacity(0.82)
    }

    private var stripC1: String {

        if !moodOn { return scheme == .dark ? "#9BB4D3" : "#C9DEF4" }
        return moodC1
    }
    private var stripC2: String {
        if !moodOn { return scheme == .dark ? "#687C94" : "#9BB4D3" }
        return moodC2.isEmpty ? moodC1 : moodC2
    }

    private var profileTopBg: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(hexString: stripC1, fallback: 0xE8F1FB),
                                    Color(hexString: stripC2, fallback: 0xC9DEF4)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)

            if !moodOn && scheme == .dark {
                LinearGradient(colors: [Color.black.opacity(0.10), Color.clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: L.safeTop + 44)
            }
            if !moodOn && scheme == .light {

                RadialGradient(colors: [Color.white.opacity(0.55), Color.clear],
                               center: UnitPoint(x: 0.84, y: 0.08),
                               startRadius: 4, endRadius: 220)
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    private var coverH: CGFloat { L.safeTop + UIConfig.num("meCoverH", 76) }

    private var cardTopY: CGFloat { coverH - UIConfig.num("meCardOverlap", 39) }
    private var topAvatar: CGFloat { L.v(58, 15.6, 66) }

    @ViewBuilder private var meCover: some View {
        if moodOn {

            profileTopBg
                .frame(maxWidth: .infinity)
        } else {

            ZStack(alignment: .top) {
                if scheme == .dark {
                    Color(hex: 0x131315)
                    LinearGradient(colors: [Color.white.opacity(0.05), Color.clear],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: L.safeTop + 64)
                } else {
                    Color(hex: 0xFFFFFF)
                    Rectangle().fill(.ultraThinMaterial)
                    LinearGradient(colors: [Color.white.opacity(0.60), Color.clear],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: L.safeTop + 64)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var profileTop: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: cardTopY)
            meProfileCard
                .padding(.horizontal, UIConfig.num("meGlassInset", 12))
            Color.clear.frame(height: 12)
        }
        .background(alignment: .top) {

            if moodOn {
                meCover
            } else {
                meCover.frame(height: coverH)
            }
        }
    }

    private var meLayout: Int { Int(UIConfig.num("meLayout", 0)) }

    @ViewBuilder private var meTop: some View {
        if meLayout == 1 { wechatProfileTop } else { profileTop }
    }

    private var wechatProfileTop: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: cardTopY)
            wechatProfileRow
                .padding(.horizontal, UIConfig.num("meGlassInset", 12))
            Color.clear.frame(height: 12)
        }
        .background(alignment: .top) {

            if moodOn { profileTopBg } else { Color.clear }
        }
    }

    private var wechatProfileRow: some View {
        HStack(spacing: 14) {
            Button { path.append("profile") } label: {
                HStack(spacing: 14) {
                    Avatar(path: app.me?.avatarPath ?? "", size: topAvatar,
                           radius: 6, level: growth.shownLevel)
                        .frame(width: topAvatar, height: topAvatar)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            if teenOn {
                                Button { showTeenCard = true } label: {
                                    UmbrellaIcon(color: Color(hex: 0x3E9BF0), size: 15)
                                }
                                .buttonStyle(.plain)
                            }
                            Text(app.me?.name ?? "")
                                .font(pf(20, .semibold))
                                .foregroundColor(C.label)
                                .lineLimit(1)
                            if growthShow {
                                QQLevelBadge(level: growth.shownLevel, size: 14, maxIcons: 3)
                                    .fixedSize()
                            }
                            MemberBadge(tier: app.me?.memberTier,
                                        short: app.me?.memberShort,
                                        color: app.me?.memberColor,
                                        color2: app.me?.memberColor2,
                                        height: 13)
                                .fixedSize()
                        }
                        Text(Tr("星言号") + "：" + (app.me?.username ?? "-"))
                            .font(pf(13.5))
                            .foregroundColor(C.subLabel)
                            .lineLimit(1)

                            .copyOnLongPress(app.me?.username ?? "") { app.show($0) }
                        if moodOn {
                            Text((app.me?.moodIcon ?? "") + " " + (app.me?.moodText ?? ""))
                                .font(pf(12.5))
                                .foregroundColor(C.subLabel)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button { showMyQR = true } label: {
                SVGIcon(markup: I.qr, size: 20, color: C.label)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

        }
        .padding(.horizontal, 16)
        .frame(height: 96)
        .frame(maxWidth: .infinity)
        .background(C.meCardBg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var meProfileCard: some View {
        VStack(spacing: 0) {

            HStack(spacing: 6) {

                if teenOn {
                    Button { showTeenCard = true } label: {
                        UmbrellaIcon(color: Color(hex: 0x3E9BF0), size: 16)
                    }
                    .buttonStyle(.plain)
                }
                Text(app.me?.name ?? "")
                    .font(pf(L.v(17, 4.8, 19.5), .semibold))
                    .foregroundColor(C.label)
                    .lineLimit(1)
                if growthShow {
                    QQLevelBadge(level: growth.shownLevel,
                                 size: L.v(15, 4.2, 17), maxIcons: 3)
                        .fixedSize()
                }
                MemberBadge(tier: app.me?.memberTier,
                            short: app.me?.memberShort,
                            color: app.me?.memberColor,
                            color2: app.me?.memberColor2,
                            height: L.v(12.5, 3.5, 14))
                    .fixedSize()
            }
            .padding(.top, topAvatar / 2 + 8)
            .padding(.horizontal, 46)

            Text(Tr("星言号") + "：" + (app.me?.username ?? "-"))
                .font(pf(13))
                .foregroundColor(C.subLabel)
                .padding(.top, 5)
                .copyOnLongPress(app.me?.username ?? "") { app.show($0) }

            HStack(spacing: 0) {
                statCell("\(friendCount)", Tr("朋友"), tap: false)

                if growthShow {
                    statLine
                    statCell("Lv." + String(growth.shownLevel), Tr("等级"), tap: true)
                    statLine
                    statCell(daysText, Tr("活跃天"), tap: true)
                }
            }
            .padding(.top, 14)
            .padding(.horizontal, 10)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    memberPill
                    statusChip
                    friendsStatusChip
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(minWidth: max(1, L.width))
            }
            .padding(.top, 14)

            Color.clear.frame(height: 16)
        }
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                GlassBackground(shape: RoundedRectangle(cornerRadius: 20, style: .continuous),
                                opacity: UIConfig.num("meGlassAlpha", 0.62),
                                edgeAlpha: UIConfig.num("meGlassEdge", 0.55),
                                shadow: true,
                                seed: 0.42,
                                native: true)
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(C.meCardBg.opacity(0.42))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

        .overlay(alignment: .top) {
            Button { path.append("profile") } label: {
                Avatar(path: app.me?.avatarPath ?? "", size: topAvatar,
                       circle: true, level: growth.shownLevel)
                    .frame(width: topAvatar, height: topAvatar)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .offset(y: -topAvatar / 2)
        }

        .overlay(alignment: .topTrailing) {
            Button { showMyQR = true } label: {
                SVGIcon(markup: I.qr, size: L.v(19, 5.4, 21), color: C.label)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
            .padding(.top, topAvatar / 2 + 2)
        }
    }

    @ViewBuilder
    private func statCell(_ value: String, _ label: String, tap: Bool) -> some View {
        let body = VStack(spacing: 2) {
            Text(value)
                .font(pf(16, .semibold))
                .foregroundColor(C.label)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(pf(11))
                .foregroundColor(C.subLabel)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())

        if tap {
            Button { path.append("level") } label: { body }.buttonStyle(.plain)
        } else {
            body
        }
    }

    private var statLine: some View {
        Rectangle().fill(C.hairline).frame(width: 0.5, height: 26)
    }

    private var memberPill: some View {
        Button { path.append("member") } label: {
            HStack(spacing: 5) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(memberActive ? .white : Color(hex: 0x8A5B12))
                Text(memberActive
                     ? ((app.me?.memberShort ?? "VIP") + Tr(" · 剩余 ") + "\(MemberStore.shared.me?.daysLeft ?? 0)" + Tr(" 天"))
                     : Tr("开通会员"))
                    .font(pf(11.5, .medium))
                    .foregroundColor(memberActive ? .white : Color(hex: 0x8A5B12))
                    .lineLimit(1)
            }
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(
                Capsule().fill(LinearGradient(
                    colors: memberActive ? [gold, gold2]
                                         : [Color(hex: 0xFCE9BC), Color(hex: 0xF0C978)],
                    startPoint: .leading, endPoint: .trailing))
            )
            .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 0.7))
        }
        .buttonStyle(.plain)
    }

    private var levelRow: some View {
        Button { path.append("level") } label: {
            HStack(spacing: 6) {
                QQLevelBadge(level: growth.level, size: L.v(15, 4.2, 17), maxIcons: 3)
                    .fixedSize()
                Text("Lv." + String(growth.shownLevel))
                    .font(pf(L.v(13.5, 3.6, 14.5), .semibold))
                    .foregroundColor(C.label)
                Text(Tr("活跃 ") + daysText + Tr(" 天"))
                    .font(pf(L.v(12.5, 3.4, 13.5)))
                    .foregroundColor(C.subLabel)
            }
            .padding(.horizontal, L.v(10, 3.2, 13))
            .frame(height: L.v(26, 7.5, 30))
            .background { CardGlassBox(radius: 999) }
            .overlay(Capsule().stroke(C.hairline, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private var friendsStatusChip: some View {
        chip {
            Text("👥")
            Text(Tr("朋友的状态"))
        } action: {
            statusPanel = .friends
        }
    }

    private var manageChip: some View {
        chip {
            Text("🛠")
            Text(Tr("管理"))
        } action: {
            path.append("manage")
        }
    }

    private var facesChip: some View {
        chip {
            Text("🙂")
            Text(Tr("人脸比对"))
        } action: {
            path.append("faces")
        }
    }

    private var statusChip: some View {
        let mood = app.me?.moodText ?? ""
        let c1 = app.me?.moodColor ?? ""
        let c2 = app.me?.moodColor2 ?? ""
        let hasColor = !mood.isEmpty && !c1.isEmpty
        return Button {
            statusPanel = .status
        } label: {
            HStack(spacing: L.v(2, 1, 4)) {
                if !mood.isEmpty {
                    Text(app.me?.moodIcon ?? "")
                    Text(mood)
                } else {
                    Text("＋").foregroundColor(C.subLabel)
                    Text(Tr("状态"))
                }
            }

            .font(pf(11.5, .medium))
            .foregroundColor(hasColor ? .white : C.label)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(
                Capsule().fill(hasColor
                    ? AnyShapeStyle(LinearGradient(colors: [Color(hexString: c1),
                                                            Color(hexString: c2.isEmpty ? c1 : c2)],
                                                   startPoint: .leading, endPoint: .trailing))
                    : AnyShapeStyle(Color.clear))
            )
            .overlay(
                Capsule().stroke(hasColor ? Color.white.opacity(0.35)
                                          : Color.dyn(0xE5E5E5, 0x333335), lineWidth: 0.6)
            )
        }
        .buttonStyle(.plain)
    }

    private func chip<Content: View>(@ViewBuilder content: () -> Content, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: L.v(2, 1, 4)) { content() }
                .font(pf(L.v(12.5, 3.4, 13.5)))
                .foregroundColor(Color.dyn(0x191919, 0xF2F2F7))
                .padding(.horizontal, L.v(10, 3.2, 13))
                .frame(height: L.v(28, 8, 32))
                .overlay(
                    Capsule().stroke(Color.dyn(0xE5E5E5, 0x333335), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    private var promoRow: some View {
        Button {
            app.show(Tr("推荐位排在下一批"))
        } label: {
            HStack(spacing: L.v(10, 3.2, 13)) {
                SVGIcon(markup: I.coke, size: L.v(38, 11, 46), color: .white)
                    .frame(width: L.v(26, 7.6, 32), height: L.v(38, 11, 46))
                VStack(alignment: .leading, spacing: L.v(3, 1.2, 5)) {
                    Text(Tr("热卖 5000+"))
                        .font(pf(L.v(10.5, 2.9, 11.5)))
                        .foregroundColor(Color.dyn(0xE0393B, 0xFF8A8D))
                        .padding(.horizontal, L.v(5, 1.6, 7))
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.dyn(0xFFECEB, 0x4A1F20)))
                    Text(Tr("添加第1个作品"))
                        .font(pf(L.v(14, 3.9, 15.5)))
                        .foregroundColor(C.label)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, L.v(16, 5, 19))
            .padding(.trailing, L.v(14, 4, 16))
            .frame(height: L.menuH)
            .background(Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuPressStyle())
    }
}

fileprivate enum StatusPanelKind: String, Identifiable {
    case status, friends
    var id: String { rawValue }
}

fileprivate struct BottomPanelModifier: ViewModifier {
    var detents: Set<PresentationDetent>

    var open: PresentationDetent
    @State private var sel: PresentationDetent? = nil

    @ViewBuilder
    func body(content: Content) -> some View {
        let pick = Binding(get: { sel ?? open }, set: { sel = $0 })
        if #available(iOS 16.4, *) {
            content
                .presentationDetents(detents, selection: pick)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(18)
                .presentationBackgroundInteraction(.enabled(upThrough: .large))
        } else {
            content
                .presentationDetents(detents, selection: pick)
                .presentationDragIndicator(.visible)
        }
    }
}

fileprivate extension View {

    func bottomPanel(_ detents: Set<PresentationDetent>,
                     open: PresentationDetent) -> some View {
        modifier(BottomPanelModifier(detents: detents, open: open))
    }
}

struct SettingsView: View {
    @ObservedObject private var lang = LangStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var confirmLogout = false
    @State private var busy = false
    @State private var showBg = false
    @State private var showBgPick = false
    @State private var showTheme = false

    @State private var hasPay = false
    @State private var showFeedback = false
    @State private var showTeen = false
    @State private var showCare = false
    @State private var showAbout = false
    @State private var showLang = false
    @State private var showPairApprove = false
    @State private var showSwitchAccount = false

    @State private var realNameText = ""

    private var accountSubtitle: String {
        let p = (app.me?.phone ?? "").trimmingCharacters(in: .whitespaces)
        if !p.isEmpty { return maskPhone(p) }
        return app.me?.username ?? ""
    }
    @State private var showRealName = false
    @State private var showMyQR = false
    @State private var showPrivacy = false
    @State private var showNotify = false
    @State private var showGeneral = false
    @State private var showStorage = false

    @State private var storageText = ""
    @State private var showProfileEdit = false

    @State private var showDiag = false
    @State private var momentsOn = MomentsPref.isOn
    @State private var careOn = CareMode.on

    @State private var query = ""
    @State private var searchActive = false
    @FocusState private var searchFocus: Bool

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("设置"), back: { dismiss() })
            settingsSearchBar
            ScrollView {
                VStack(spacing: 0) {

                    settingsGroupHeader(Tr("账号"))
                    GroupCard {
                        settingLink(Tr("个人资料"), "", key: "profile")
                        HairLine(inset: 16)
                        settingLink(Tr("账号安全"), accountSubtitle, key: "account")
                        HairLine(inset: 16)
                        settingLink(Tr("个人信息与权限"), "", key: "selfperm")
                    }

                    settingsGroupHeader(Tr("通用"))
                    GroupCard {
                        settingLink(Tr("通知"), "", key: "notify")
                        HairLine(inset: 16)

                        settingLink(Tr("界面与显示"), "", key: "general")
                        HairLine(inset: 16)

                        HStack(spacing: 12) {
                            Text(Tr("朋友圈")).font(pf(16)).foregroundColor(C.label)
                            Spacer(minLength: 0)
                            Toggle("", isOn: Binding(
                                get: { momentsOn },
                                set: { v in
                                    momentsOn = v
                                    MomentsPref.set(v)
                                    app.show(v ? Tr("朋友圈已开启：去「发现」里就能看到")
                                               : Tr("朋友圈已关闭"))
                                }))
                                .labelsHidden()
                                .tint(C.green)
                        }
                        .padding(.horizontal, 16).frame(height: 52)
                        HairLine(inset: 16)

                        settingLink(Tr("朋友权限"), "", key: "privacy")
                        HairLine(inset: 16)

                        settingLink(Tr("存储空间"), storageText, key: "storage")
                        HairLine(inset: 16)

                        settingLink(Tr("更多"), "", key: "more")
                    }

                    settingsGroupHeader(Tr("功能"))
                    GroupCard {
                        settingLink(Tr("聊天"), "", key: "setchat")
                        HairLine(inset: 16)
                        settingLink(Tr("音视频通话"), "", key: "setcall")
                        HairLine(inset: 16)
                        settingLink(Tr("聊天记录管理"), "", key: "g.history")
                    }

                    settingsGroupHeader(Tr("帮助与关于"))

                    GroupCard {
                        settingLink(Tr("帮助与反馈"), "", key: "feedback")
                        HairLine(inset: 16)

                        Button { showDiag = true } label: {
                            HStack(spacing: 12) {
                                Text(Tr("诊断工具")).font(pf(17)).foregroundColor(C.label)
                                Spacer(minLength: 0)
                                Chevron(size: 9, line: 1.6).padding(.trailing, 3)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 56)
                            .background(C.meCardBg)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        HairLine(inset: 16)

                        settingLink(Tr("关于我们 · 版本更新"), AppInfo.displayVersion + " · " + AppInfo.build, key: "about")
                    }

                    NavigationLink(value: "switch") {
                        HStack {
                            Text(Tr("切换账号"))
                                .font(pf(17))
                                .foregroundColor(C.label)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(C.subLabel)
                        }
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(C.meCardBg)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)

                    Button {
                        confirmLogout = true
                    } label: {
                        Text(busy ? "退出中…" : "退出登录")
                            .font(pf(17))
                            .foregroundColor(C.red)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(C.meCardBg)
                    }
                    .disabled(busy)
                    .padding(.top, 8)

                    Spacer().frame(height: 30)
                }
            }
            .background(C.pageBg)

            .overlay {
                if !trimmedQuery.isEmpty {
                    searchResultList
                        .background(C.pageBg)
                }
            }
        }
        .background(C.pageBg.ignoresSafeArea(edges: .bottom))
        .background(C.pageBg.ignoresSafeArea(edges: .top))
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()

        .confirmationDialog(Tr("外观"), isPresented: $showTheme, titleVisibility: .visible) {
            Button(Tr("跟随系统")) { app.setAppearance("auto") }
            Button(Tr("浅色")) { app.setAppearance("light") }
            Button(Tr("深色")) { app.setAppearance("dark") }
            Button(Tr("取消"), role: .cancel) { }
        }
        .sheet(isPresented: $showBgPick) {
            PhotoPicker { image in changeBg(image) }
        }
        .sheet(isPresented: $showDiag) {
            DiagView().environmentObject(app)
        }

        .confirmationDialog(Tr("界面语言"), isPresented: $showLang, titleVisibility: .visible) {
            Button(Tr("简体中文")) { setLang("zh") }
            Button("English") { setLang("en") }
            Button(Tr("取消"), role: .cancel) { }
        }
        .task {
            hasPay = await API.shared.hasPayPassword()

            let rn = await API.shared.realNameStatus()
            realNameText = rn.verified ? Tr("已实名") : Tr("未实名")

            let used = await Task.detached(priority: .utility) {
                LocalStore.text(LocalStore.totalUsage())
            }.value
            storageText = used
        }
        .onAppear {
            momentsOn = MomentsPref.isOn
            careOn = CareMode.on
        }
        .onReceive(NotificationCenter.default.publisher(for: .chrisUIPrefsChanged)) { _ in
            momentsOn = MomentsPref.isOn
            careOn = CareMode.on
        }
        .confirmationDialog(Tr("确定退出登录？"), isPresented: $confirmLogout, titleVisibility: .visible) {
            Button(Tr("退出登录"), role: .destructive) {
                busy = true
                Task {
                    await app.logout()
                    busy = false
                }
            }
            Button(Tr("取消"), role: .cancel) { }
        }
    }

    private func setLang(_ code: String) {
        Lang.code = code
        app.show(code == "en" ? "Language switched to English" : "界面语言已切成中文")
        dismiss()

    }

    private func changeBg(_ image: UIImage) {
        busy = true
        Task {
            if let url = try? await API.shared.uploadOriginal(image: image) {
                do {
                    try await API.shared.updateMeChecked(["chatBackground": url])
                    app.applyMyProfileFields(["chatBackground": url])
                } catch {
                    busy = false
                    app.show(Tr("聊天背景设置失败"))
                    return
                }
                app.show(Tr("聊天背景换好了"))
            }
            busy = false
        }
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    private struct SettingSearchItem: Identifiable {
        let id = UUID()
        let title: String
        let sub: String
        let keywords: String
        var key: String? = nil
        var run: (() -> Void)? = nil
    }

    private var searchItems: [SettingSearchItem] {
        let items: [SettingSearchItem] = [
            SettingSearchItem(title: Tr("个人资料"), sub: "",
                              keywords: "个人资料 头像 昵称 名字 个人信息 资料", key: "profile"),
            SettingSearchItem(title: Tr("账号安全"), sub: accountSubtitle,
                              keywords: "账号 安全 账号与安全 手机号 手机 实名 认证 支付密码 支付 密码 安全锁 手势 声音锁 登录设备 设备 安全分 个人信息 资料",
                              key: "account"),
            SettingSearchItem(title: Tr("个人信息与权限"), sub: "",
                              keywords: "个人信息 权限 系统权限 授权 相册 相机 麦克风 位置", key: "selfperm"),
            SettingSearchItem(title: Tr("实名认证"), sub: realNameText,
                              keywords: "实名 认证 身份证 实名制", key: "realname"),
            SettingSearchItem(title: Tr("支付密码"), sub: hasPay ? Tr("已设置") : Tr("未设置"),
                              keywords: "支付密码 密码 设置密码 改密码 重置", key: "paypwd"),
            SettingSearchItem(title: Tr("安全锁（手势密码）"), sub: "",
                              keywords: "安全锁 手势密码 手势 锁", key: "gesture"),
            SettingSearchItem(title: Tr("声音锁"), sub: "",
                              keywords: "声音锁 声纹 声音", key: "voicelock"),
            SettingSearchItem(title: Tr("我的等级"), sub: "",
                              keywords: "等级 活跃天 成长 升级 图标", key: "level"),
            SettingSearchItem(title: Tr("安全分"), sub: "",
                              keywords: "安全分 评分 安全", key: "score"),
            SettingSearchItem(title: Tr("登录设备管理"), sub: "",
                              keywords: "登录设备 设备 手机 电脑 退出设备", key: "devices"),
            SettingSearchItem(title: Tr("未成年人模式"), sub: "",
                              keywords: "未成年人 青少年 防沉迷 伞 模式", key: "teen"),
            SettingSearchItem(title: Tr("关怀模式"), sub: careOn ? Tr("已开启") : Tr("未开启"),
                              keywords: "关怀 大字 字号 老年人 模式", key: "care"),
            SettingSearchItem(title: Tr("通知"), sub: "",
                              keywords: "新消息 通知 提醒 铃声 震动 免打扰", key: "notify"),
            SettingSearchItem(title: Tr("朋友权限"), sub: "",
                              keywords: "朋友权限 隐私 加我 好友 验证 朋友圈 通讯录", key: "privacy"),
            SettingSearchItem(title: Tr("界面与显示"), sub: "",
                              keywords: "界面与显示 通用 外观 深色 浅色 主题 界面语言 中文 英文", key: "general"),
            SettingSearchItem(title: Tr("更多"), sub: "",
                              keywords: "更多 未成年人 关怀 等级 安全分 登录设备 诊断", key: "more"),
            SettingSearchItem(title: Tr("聊天"), sub: "",
                              keywords: "聊天 聊天背景 语音变声 聊天记录 存储", key: "setchat"),
            SettingSearchItem(title: Tr("音视频通话"), sub: "",
                              keywords: "音视频通话 视频 语音 通话 来电", key: "setcall"),
            SettingSearchItem(title: Tr("聊天背景"), sub: "",
                              keywords: "聊天背景 背景 壁纸 图片", key: "chatbg"),
            SettingSearchItem(title: Tr("外观"), sub: "",
                              keywords: "外观 深色 浅色 跟随系统 主题", run: { showTheme = true }),
            SettingSearchItem(title: Tr("界面语言"), sub: "",
                              keywords: "界面语言 语言 中文 英文 language", run: { showLang = true }),
            SettingSearchItem(title: Tr("帮助与反馈"), sub: "",
                              keywords: "帮助 反馈 意见 客服 投诉", key: "feedback"),
            SettingSearchItem(title: Tr("关于我们 · 版本更新"), sub: AppInfo.displayVersion + " · " + AppInfo.build,
                              keywords: "关于 版本 更新 检查更新 当前版本", key: "about"),
            SettingSearchItem(title: Tr("诊断工具"), sub: "",
                              keywords: "诊断 上报 日志 崩溃 机型 内存 缓存 网络", run: { showDiag = true }),
            SettingSearchItem(title: Tr("切换账号"), sub: "",
                              keywords: "切换账号 换号 登录 账号", key: "switch"),
            SettingSearchItem(title: Tr("退出登录"), sub: "",
                              keywords: "退出登录 退出 注销 登出", run: { confirmLogout = true })
        ]

        return UIConfig.num("growthShow", 1) > 0 ? items : items.filter { $0.key != "level" }
    }

    private var matches: [SettingSearchItem] {
        let q = trimmedQuery.lowercased()
        guard !q.isEmpty else { return [] }
        return searchItems.filter {
            $0.title.lowercased().contains(q) || $0.keywords.lowercased().contains(q)
        }
    }

    private var settingsSearchBar: some View {
        HStack(spacing: 9) {

            ZStack {
                if !searchActive && query.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14.5, weight: .medium))
                            .foregroundColor(C.searchIcon)
                        Text(Tr("搜索"))
                            .font(pf(15))
                            .foregroundColor(C.searchIcon)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { searchFocus = true }
                }
                HStack(spacing: 8) {
                    if searchActive || !query.isEmpty {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14.5, weight: .medium))
                            .foregroundColor(C.searchIcon)
                    }
                    TextField("", text: $query)
                        .font(pf(15))
                        .focused($searchFocus)
                        .submitLabel(.search)
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundColor(C.searchIcon2)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background {
                GlassBackground(shape: RoundedRectangle(cornerRadius: 12, style: .continuous),
                                opacity: 0.88,
                                edgeAlpha: 0.55,
                                shadow: false,
                                seed: 0.28,
                                native: true)
            }

            if searchActive {
                Button {
                    query = ""
                    searchFocus = false
                } label: {
                    Text(Tr("取消")).font(pf(15)).foregroundColor(C.label)
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(C.pageBg)
        .animation(.easeOut(duration: 0.16), value: searchActive)
        .onChange(of: searchFocus) { f in searchActive = f }
    }

    private var searchResultList: some View {
        ScrollView {
            VStack(spacing: 0) {
                if matches.isEmpty {
                    Text(Tr("没有找到") + "「\(trimmedQuery)」")
                        .font(pf(14))
                        .foregroundColor(C.subLabel)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 44)
                } else {
                    GroupCard {
                        ForEach(Array(matches.enumerated()), id: \.element.id) { idx, item in
                            searchResultRow(item)
                            if idx < matches.count - 1 { HairLine(inset: 16) }
                        }
                    }
                    .padding(.top, 4)
                }
                Spacer().frame(height: 30)
            }
        }
        .background(C.pageBg)
    }

    @ViewBuilder
    private func searchResultRow(_ item: SettingSearchItem) -> some View {
        if let key = item.key {
            NavigationLink(value: key) { searchRowLabel(item) }
                .buttonStyle(MenuPressStyle())
        } else {
            Button {
                searchFocus = false
                item.run?()
            } label: {
                searchRowLabel(item)
            }
            .buttonStyle(MenuPressStyle())
        }
    }

    private func searchRowLabel(_ item: SettingSearchItem) -> some View {
        HStack(spacing: 12) {
            Text(item.title).font(pf(17)).foregroundColor(C.label)
            Spacer(minLength: 0)
            if !item.sub.isEmpty {
                Text(item.sub).font(pf(15)).foregroundColor(C.subLabel).lineLimit(1)
            }
            Chevron(size: 9, line: 1.6).padding(.trailing, 3)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(C.meCardBg)
        .contentShape(Rectangle())
    }

    private func settingRow(_ title: String, _ value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title).font(pf(17)).foregroundColor(C.label)
                Spacer(minLength: 0)
                if !value.isEmpty {
                    Text(value).font(pf(15)).foregroundColor(C.subLabel)
                }
                Chevron(size: 9, line: 1.6).padding(.trailing, 3)
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(C.meCardBg)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuPressStyle())
    }

    private func settingsGroupHeader(_ text: String) -> some View {
        Text(text)
            .font(pf(13.5))
            .foregroundColor(Color.dyn(0x767676, 0x8F8F8F))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 7)
    }

    private func settingLink(_ title: String, _ value: String, key: String) -> some View {
        NavigationLink(value: key) {
            HStack(spacing: 12) {
                Text(title).font(pf(17)).foregroundColor(C.label)
                Spacer(minLength: 0)
                if !value.isEmpty {
                    Text(value).font(pf(15)).foregroundColor(C.subLabel)
                }
                Chevron(size: 9, line: 1.6).padding(.trailing, 3)
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(C.meCardBg)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuPressStyle())
    }
}
