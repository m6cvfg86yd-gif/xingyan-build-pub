import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ManageData: Decodable {
    var music: [MusicTrack]?
    var games: [MiniApp]?
    var apps: [MiniApp]?
}

private struct DarkPagePreset: Identifiable {
    let id: String
    let name: String
    let hex: UInt32
    let surface: UInt32
    let line: UInt32
}

struct UserManageView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var data: ManageData? = nil
    @State private var loading = true
    @State private var busy = ""
    @State private var msg = ""

    @State private var title = ""
    @State private var artist = ""
    @State private var lyrics = ""
    @State private var audioURL = ""
    @State private var audioName = ""
    @State private var newCoverURL = ""
    @State private var showAudioPick = false

    @State private var showBatchPick = false
    @State private var showFolderPick = false
    @State private var batchTotal = 0
    @State private var batchDone = 0

    @State private var pickFor = ""
    @State private var showCoverPick = false

    @State private var editing: MiniApp? = nil

    @State private var snOn = true
    @State private var snTypes: [String: Bool] = [:]

    @State private var officials: [API.OfficialAccount] = []
    @State private var editingOfficial: API.OfficialAccount? = nil

    @State private var pickingMusic = false
    @State private var pickedMusic: Set<String> = []

    @State private var shopItems: [API.ShopItem] = []
    @State private var shopLoading = false
    @State private var editShopItem: API.ShopItem? = nil
    @State private var newShopItem = false

    @State private var cardQuery = ""
    @State private var cardUsers: [API.OpsUserRow] = []
    @State private var cardUser: API.OpsUserRow? = nil
    @State private var cardSearching = false
    @State private var cardMsg = ""

    @State private var logTotal = 0
    @State private var logKinds: [API.AppLogKind] = []
    @State private var logRows: [API.AppLogRow] = []
    @State private var logKind = ""
    @State private var logLoading = false
    @State private var logDetail: API.AppLogRow? = nil

    @State private var rpCovers: [API.RPCover] = []
    @State private var rpDefault = ""
    @State private var rpEdit: API.RPCover? = nil
    @State private var rpNew = false

    @State private var faceForRealName = UIConfig.num("realnameFace", 1) > 0
    @State private var chatFilterBar = UIConfig.num("chatFilterBar", 1) > 0
    @State private var chatsCardStyle = UIConfig.num("chatsCardStyle", 1) > 0
    @State private var roundAvatars = UIConfig.avatarCircle

    @State private var meLayout = Int(UIConfig.num("meLayout", 0))

    @State private var multiDevice = UIConfig.num("multiDevice", 0) > 0

    @State private var activeDarkPagePreset = ""
    private let darkPagePresets: [DarkPagePreset] = [
        DarkPagePreset(id: "standard", name: "星言黑", hex: 0x191919,
                       surface: 0x191919, line: 0x2C2C2E),
        DarkPagePreset(id: "whatsapp", name: "墨蓝黑", hex: 0x0B141A,
                       surface: 0x111B21, line: 0x22343D),
        DarkPagePreset(id: "obsidian", name: "曜石黑", hex: 0x090A0C,
                       surface: 0x121316, line: 0x26282D),
        DarkPagePreset(id: "pure", name: "纯黑", hex: 0x000000,
                       surface: 0x111112, line: 0x262628),
        DarkPagePreset(id: "graphite", name: "石墨灰", hex: 0x121417,
                       surface: 0x1C1F24, line: 0x30353C),
        DarkPagePreset(id: "forest", name: "深林青", hex: 0x07120F,
                       surface: 0x0F1B17, line: 0x22352F)
    ]

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("管理"), back: { dismiss() })
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {

                    groupTitle(Tr("商城"))
                    hubCard {
                        linkRow(icon: "cart.fill", tint: Color(hex: 0xE02A0F),
                                title: Tr("商城后台"),
                                sub: Tr("商品上架 / 轮播图 / 广告位 / 商城名 / 小店")) {
                            MallAdminSection()
                            shopSection
                        }
                        HairLine(inset: 52)
                        linkRow(icon: "square.grid.2x2.fill", tint: Color(hex: 0x2E6BFF),
                                title: Tr("小程序 / 小游戏"),
                                sub: Tr("后台加的小程序、换名字图标和入口地址")) {
                            miniappsSection
                        }
                    }

                    groupTitle(Tr("内容"))
                    hubCard {
                        linkRow(icon: "music.note", tint: Color(hex: 0x8E44AD),
                                title: Tr("音乐与图标"),
                                sub: Tr("上新歌、换音乐图标、换游戏图标")) {
                            addSection
                            musicIcons
                            gameIcons
                        }
                        HairLine(inset: 52)
                        linkRow(icon: "bolt.fill", tint: C.green,
                                title: Tr("聊天快捷"),
                                sub: Tr("输入框上面那排按钮、「＋」按钮的外观")) {
                            ChatQuickAdminSection().environmentObject(app)
                        }
                    }

                    groupTitle(Tr("用户与资金"))
                    hubCard {
                        linkRow(icon: "creditcard.fill", tint: Color(hex: 0x217346),
                                title: Tr("卡券"),
                                sub: Tr("给某个人发卡 / 删卡 / 查他手里的卡")) {
                            cardsSection
                        }
                        HairLine(inset: 52)
                        linkRow(icon: "gift.fill", tint: Color(hex: 0xE2567A),
                                title: Tr("红包封面"),
                                sub: Tr("换封面图、设默认、加一张新的")) {
                            rpCoversSection
                        }
                        HairLine(inset: 52)
                        linkRow(icon: "person.crop.circle.badge.exclamationmark", tint: Color(hex: 0xC0392B),
                                title: Tr("账号状态"),
                                sub: Tr("冻结 / 解冻 / 封禁 / 解封")) {
                            AccountOpsSection().environmentObject(app)
                        }
                    }

                    groupTitle(Tr("通知与系统"))
                    hubCard {
                        linkRow(icon: "bell.fill", tint: Color(hex: 0x3457D5),
                                title: Tr("通知与官方号"),
                                sub: Tr("系统通知、官方号的名字和头像")) {
                            sysNoticeSection
                            officialSection
                        }
                        HairLine(inset: 52)
                        linkRow(icon: "switch.2", tint: Color(hex: 0x5B6673),
                                title: Tr("开关与配置"),
                                sub: Tr("我页排版、实名要人脸、多设备在线这些")) {
                            switchSection
                        }
                        HairLine(inset: 52)
                        linkRow(icon: "stethoscope", tint: Color(hex: 0x8A8A8E),
                                title: Tr("日志与崩溃"),
                                sub: Tr("App 汇上来的日志、崩溃堆栈")) {
                            logsSection
                        }
                    }

                    if !msg.isEmpty {
                        Text(msg).font(pf(12.5)).foregroundColor(C.subLabel)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                    }
                    Spacer().frame(height: 30)
                }
                .padding(.top, 10)
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea(edges: .top))
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .task { await load() }

        .fileImporter(isPresented: $showAudioPick,

                      allowedContentTypes: [.item],
                      allowsMultipleSelection: false) { result in
            uploadAudio(result)
        }

        .fileImporter(isPresented: $showBatchPick, allowedContentTypes: [.item],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { importFiles(urls) }
        }

        .fileImporter(isPresented: $showFolderPick, allowedContentTypes: [.folder],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let dir = urls.first { importFolder(dir) }
        }
        .sheet(isPresented: $showCoverPick) {
            PhotoPicker { img in uploadPic(img) }
        }

        .sheet(item: $editing) { g in
            MiniAppEditSheet(item: g) { await load() }
                .environmentObject(app)
        }

        .sheet(item: $editingOfficial) { o in
            OfficialEditSheet(item: o) { await load() }
        }

        .sheet(item: $editShopItem) { it in
            ShopItemEditSheet(item: it, onSaved: refreshShopSoon)
                .environmentObject(app)
        }

        .sheet(isPresented: $newShopItem) {
            ShopItemEditSheet(item: nil, onSaved: refreshShopSoon)
                .environmentObject(app)
        }

        .sheet(item: $cardUser) { u in
            CardAdminSheet(user: u)
                .environmentObject(app)
        }

        .sheet(item: $logDetail) { r in
            AppLogDetailSheet(row: r)
        }

        .sheet(item: $rpEdit) { c in
            RPCoverEditSheet(cover: c, isDefault: rpDefault == c.id) { r in
                applyRpEdit(r, editing: c)
            }
            .environmentObject(app)
        }

        .sheet(isPresented: $rpNew) {
            RPCoverEditSheet(cover: nil, isDefault: false) { r in
                applyRpEdit(r, editing: nil)
            }
            .environmentObject(app)
        }
    }

    @ViewBuilder private func hubCard<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        GroupCard { content() }
            .padding(.horizontal, 12)
    }

    private func linkRow<D: View>(icon: String, tint: Color, title: String, sub: String,
                                  @ViewBuilder dest: @escaping () -> D) -> some View {
        NavigationLink {
            ManageSubPage(title: title, content: dest)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint)
                    Image(systemName: icon)
                        .font(.system(size: 15.5, weight: .semibold))
                        .foregroundColor(.white)
                }
                .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(pf(16)).foregroundColor(C.label)
                    Text(sub).font(pf(12)).foregroundColor(C.subLabel).lineLimit(2)
                }
                Spacer(minLength: 0)
                Chevron(size: 9, line: 1.6)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var shopSection: some View {
        card(Tr("小店（商品 / 价格 / 库存 / 上架）")) {
            if shopLoading && shopItems.isEmpty {
                hint(Tr("正在加载…"))
            } else if shopItems.isEmpty {
                hint(Tr("还没有商品，下面点「上架一件新商品」"))
            } else {
                ForEach(Array(shopItems.enumerated()), id: \.element.id) { i, it in
                    if i > 0 { HairLine(inset: 70) }
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(C.pageBg)
                            if let img = it.img, !img.isEmpty {
                                RemoteImage(path: img).frame(width: 46, height: 46)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            } else {
                                Image(systemName: "shippingbox.fill")
                                    .font(.system(size: 18)).foregroundColor(C.subLabel)
                            }
                        }
                        .frame(width: 46, height: 46)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(it.name).font(pf(15.5)).foregroundColor(C.label).lineLimit(1)
                            Text(shopRowSub(it))
                                .font(pf(12)).foregroundColor(C.subLabel).lineLimit(1)
                        }
                        Spacer(minLength: 4)

                        Toggle("", isOn: Binding(
                            get: { it.on != false },
                            set: { v in Task { await shopSetOn(it, v) } }))
                            .labelsHidden()
                            .tint(C.green)
                        Button { editShopItem = it } label: {
                            Text(Tr("编辑")).font(pf(13)).foregroundColor(C.green)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14).frame(height: 62)
                }
            }
            HairLine(inset: 16)
            row(Tr("上架一件新商品"), Tr("点这里")) { newShopItem = true }
        }
    }

    private func loadShop() async {
        shopLoading = true
        if let list = try? await API.shared.opsShopItems() { shopItems = list }
        shopLoading = false
    }

    private func shopRowSub(_ it: API.ShopItem) -> String {
        let a = "¥" + moneyFmt(it.price)
        let b = Tr("库存 ") + String(it.stock ?? 0)
        let c = Tr("排序 ") + String(it.sort ?? 0)
        return a + " · " + b + " · " + it.kindName + " · " + c
    }

    private func refreshShopSoon() {
        Task { await loadShop() }
    }

    private func shopSetOn(_ item: API.ShopItem, _ on: Bool) async {
        do {
            shopItems = try await API.shared.opsShopSave(item: ["id": item.id, "on": on], newItem: nil)
            msg = Tr("已") + (on ? Tr("上架 ") : Tr("下架 ")) + item.name
        } catch {
            msg = (error as? APIError)?.errorDescription ?? "改上架状态失败"
        }
    }

    private var cardsSection: some View {
        card(Tr("卡包（找人 → 发券 / 删卡）")) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14)).foregroundColor(C.subLabel)
                TextField(Tr("按用户名 / 昵称找人"), text: $cardQuery)
                    .font(pf(15))
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onSubmit { Task { await searchCards() } }
                if cardSearching {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Button { Task { await searchCards() } } label: {
                        Text(Tr("搜索")).font(pf(14)).foregroundColor(C.green)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).frame(height: 52)

            if cardUsers.isEmpty {
                HairLine(inset: 16)
                hint(Tr("搜一个人，进去给他发券 / 会员卡 / 礼品卡 / 票"))
            } else {
                ForEach(cardUsers) { u in
                    HairLine(inset: 70)
                    Button { cardUser = u } label: {
                        HStack(spacing: 12) {
                            Avatar(path: u.avatar ?? "", size: 46, radius: 23)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(u.nickname ?? u.username ?? "").font(pf(15.5))
                                    .foregroundColor(C.label).lineLimit(1)
                                Text(cardUserSub(u))
                                    .font(pf(12)).foregroundColor(C.subLabel).lineLimit(1)
                            }
                            Spacer(minLength: 6)
                            Text(Tr("发卡 / 管理")).font(pf(13)).foregroundColor(C.green)
                            Chevron(size: 9, line: 1.6)
                        }
                        .padding(.horizontal, 14).frame(height: 62)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if !cardMsg.isEmpty {
                Text(cardMsg).font(pf(12.5)).foregroundColor(C.subLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.bottom, 8)
            }
        }
    }

    private func searchCards() async {
        cardSearching = true
        cardMsg = ""
        do {
            cardUsers = try await API.shared.opsCardFind(cardQuery)
            if cardUsers.isEmpty { cardMsg = Tr("没找到这个人") }
        } catch {
            cardMsg = (error as? APIError)?.errorDescription ?? "搜索失败"
        }
        cardSearching = false
    }

    private func cardUserSub(_ u: API.OpsUserRow) -> String {
        let name = u.username ?? ""
        let n = Tr("名下 ") + String(u.cards ?? 0) + Tr(" 张卡")
        return name + " · " + n
    }

    private var logsSection: some View {
        card(Tr("App 日志 / 崩溃（汇入）")) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(logTotalText).font(pf(15.5)).foregroundColor(C.label)
                    Text(logSubText)
                        .font(pf(12)).foregroundColor(C.subLabel)
                }
                Spacer(minLength: 6)
                if logLoading { ProgressView().scaleEffect(0.7) }
                Button { Task { await loadLogs() } } label: {
                    Text(Tr("刷新")).font(pf(13.5)).foregroundColor(C.green)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).frame(height: 58)

            if !logKinds.isEmpty {
                HairLine(inset: 16)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        kindChip("", Tr("全部") + " " + String(logTotal))
                        ForEach(logKinds.prefix(12), id: \.kind) { k in
                            kindChip(k.kind, k.kind + " " + String(k.n))
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                }
            }

            if logRows.isEmpty {
                HairLine(inset: 16)
                hint(logLoading ? Tr("正在加载…") : Tr("还没有汇入的日志"))
            } else {
                ForEach(logRows) { r in
                    HairLine(inset: 16)
                    Button { logDetail = r } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(r.kind ?? "").font(pf(14.5)).foregroundColor(C.label).lineLimit(1)
                                Spacer(minLength: 0)
                                Text(logTime(r.at ?? "")).font(pf(11.5)).foregroundColor(C.subLabel)
                            }
                            Text(logOneLine(r)).font(pf(12)).foregroundColor(C.subLabel).lineLimit(2)
                            Text(logMeta(r)).font(pf(11)).foregroundColor(C.subLabel).lineLimit(1)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var logTotalText: String {
        Tr("汇入 ") + String(logTotal) + Tr(" 条日志")
    }

    private var logSubText: String {
        let a = Tr("类型 ") + String(logKinds.count) + Tr(" 种")
        let b = Tr("最近 ") + String(logRows.count) + Tr(" 条")
        return a + " · " + b
    }

    private func kindChip(_ kind: String, _ label: String) -> some View {
        Button {
            logKind = kind
            Task { await loadLogs() }
        } label: {
            Text(label)
                .font(pf(12.5))
                .foregroundColor(logKind == kind ? .white : C.label)
                .padding(.horizontal, 10).frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(logKind == kind ? C.green : C.pageBg))
        }
        .buttonStyle(.plain)
    }

    private func logOneLine(_ r: API.AppLogRow) -> String {
        (r.text ?? "").replacingOccurrences(of: "\n", with: " ")
    }

    private func logMeta(_ r: API.AppLogRow) -> String {
        var parts: [String] = []
        if let a = r.app, !a.isEmpty { parts.append(a) }
        if let u = r.user, !u.isEmpty { parts.append(u) }
        if let i = r.ip, !i.isEmpty { parts.append(i) }
        return parts.joined(separator: " · ")
    }

    private func logTime(_ s: String) -> String {
        if let n = Double(s), n > 1_000_000_000 {
            let d = Date(timeIntervalSince1970: n > 10_000_000_000 ? n / 1000 : n)
            let f = DateFormatter()
            f.dateFormat = "MM-dd HH:mm"
            return f.string(from: d)
        }
        return TimeFmt.bill(s)
    }

    private func loadLogs() async {
        logLoading = true
        if let r = try? await API.shared.opsLogs(kind: logKind, limit: 30) {
            logTotal = r.total ?? 0
            logKinds = r.kinds ?? []
            logRows = r.rows ?? []
        }
        logLoading = false
    }

    private var switchSection: some View {
        card(Tr("开关")) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Tr("实名认证先刷脸")).font(pf(16)).foregroundColor(C.label)
                    Text(Tr("关掉后只填姓名+身份证号就能提交")).font(pf(12)).foregroundColor(C.subLabel)
                }
                Spacer(minLength: 6)
                Toggle("", isOn: Binding(
                    get: { faceForRealName },
                    set: { v in
                        faceForRealName = v
                        Task {
                            let ok = await API.shared.opsSetUIKey("realnameFace", v ? 1 : 0)

                            if ok {
                                let cfg = await API.shared.uiConfig()
                                UIConfig.apply(cfg.ui)
                            }
                            msg = ok ? Tr("已") + (v ? Tr("开启") : Tr("关闭")) + Tr("实名前刷脸")
                                     : Tr("保存失败")
                        }
                    }))
                    .labelsHidden().tint(C.green)
            }
            .padding(.horizontal, 16).frame(height: 62)

            HairLine(inset: 16)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Tr("圆形头像")).font(pf(16)).foregroundColor(C.label)
                    Text(Tr("开 = 会话、通讯录和个人资料全部用圆形；关 = 星言默认圆角方形"))
                        .font(pf(12)).foregroundColor(C.subLabel)
                        .lineLimit(2)
                }
                Spacer(minLength: 6)
                Toggle("", isOn: Binding(
                    get: { roundAvatars },
                    set: { v in
                        roundAvatars = v
                        app.setAvatarCircle(v)
                        Task {
                            let ok = await API.shared.opsSetUIKey("avatarShape", v ? 1 : 0)
                            if ok {
                                await app.refreshUI(force: true)
                            }
                            msg = ok ? (v ? Tr("已切换为圆形头像") : Tr("已切换为圆角方形头像"))
                                     : Tr("已在本机切换，服务器暂未保存")
                        }
                    }))
                    .labelsHidden().tint(C.green)
            }
            .padding(.horizontal, 16).frame(height: 66)

            HairLine(inset: 16)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Tr("会话页分类横条")).font(pf(16)).foregroundColor(C.label)
                    Text(Tr("关闭后「全部 / 未读 / 群聊 / 公众号 / 置顶」整条隐藏，不再占高度"))
                        .font(pf(12)).foregroundColor(C.subLabel)
                        .lineLimit(2)
                }
                Spacer(minLength: 6)
                Toggle("", isOn: Binding(
                    get: { chatFilterBar },
                    set: { v in
                        chatFilterBar = v
                        Task {
                            let ok = await API.shared.opsSetUIKey("chatFilterBar", v ? 1 : 0)
                            if ok {
                                let cfg = await API.shared.uiConfig()
                                UIConfig.apply(cfg.ui)
                            }
                            msg = ok ? (v ? Tr("已开启会话页分类横条") : Tr("已关闭会话页分类横条"))
                                     : Tr("保存失败")
                        }
                    }))
                    .labelsHidden().tint(C.green)
            }
            .padding(.horizontal, 16).frame(height: 66)

            HairLine(inset: 16)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Tr("会话页分组卡片")).font(pf(16)).foregroundColor(C.label)
                    Text(Tr("开 = 会话列表包在一块圆角卡片里；关 = 恢复原来的整页列表"))
                        .font(pf(12)).foregroundColor(C.subLabel)
                        .lineLimit(2)
                }
                Spacer(minLength: 6)
                Toggle("", isOn: Binding(
                    get: { chatsCardStyle },
                    set: { v in
                        chatsCardStyle = v
                        Task {
                            let ok = await API.shared.opsSetUIKey("chatsCardStyle", v ? 1 : 0)
                            if ok {
                                await app.refreshUI(force: true)
                            }
                            msg = ok ? (v ? Tr("已开启会话页分组卡片") : Tr("已恢复原会话列表"))
                                     : Tr("保存失败")
                        }
                    }))
                    .labelsHidden().tint(C.green)
            }
            .padding(.horizontal, 16).frame(height: 66)

            HairLine(inset: 16)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Tr("「我」页排版")).font(pf(16)).foregroundColor(C.label)
                    Text(Tr("卡片版 = 头像压在卡片上沿 / 微信版 = 一行放下头像·名字·星言号"))
                        .font(pf(12)).foregroundColor(C.subLabel)
                        .lineLimit(2)
                }
                Spacer(minLength: 6)
                Picker("", selection: Binding(
                    get: { meLayout },
                    set: { v in
                        meLayout = v
                        Task {
                            let ok = await API.shared.opsSetUIKey("meLayout", Double(v))
                            if ok {
                                let cfg = await API.shared.uiConfig()
                                UIConfig.apply(cfg.ui)
                            }
                            msg = ok ? (Tr("我页排版已切成") + (v == 1 ? Tr("微信版") : Tr("卡片版"))
                                        + Tr("，重开 App 生效"))
                                     : Tr("保存失败")
                        }
                    })) {
                    Text(Tr("卡片版")).tag(0)
                    Text(Tr("微信版")).tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }
            .padding(.horizontal, 16).frame(height: 62)

            HairLine(inset: 16)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Tr("多设备同时在线")).font(pf(16)).foregroundColor(C.label)
                    Text(Tr("开 = 同一个账号几台手机都在线、消息互相同步；关 = 新手机一登就把旧手机顶下线"))
                        .font(pf(12)).foregroundColor(C.subLabel)
                        .lineLimit(2)
                }
                Spacer(minLength: 6)
                Toggle("", isOn: Binding(
                    get: { multiDevice },
                    set: { v in
                        multiDevice = v
                        Task {
                            let ok = await API.shared.opsSetUIKey("multiDevice", v ? 1 : 0)
                            if ok {
                                let cfg = await API.shared.uiConfig()
                                UIConfig.apply(cfg.ui)
                            }
                            msg = ok ? (v ? Tr("已开启多设备同时在线") : Tr("已关闭，回到单点登录"))
                                     : Tr("保存失败")
                        }
                    }))
                    .labelsHidden().tint(C.green)
            }
            .padding(.horizontal, 16).frame(height: 62)

            HairLine(inset: 16)
            darkPageColorSection
        }
    }

    private var darkPageColorSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Tr("四个主页深色底色"))
                    .font(pf(16))
                    .foregroundColor(C.label)
                Text(Tr("聊天、通讯录、世界、我的同步换色；浅色模式仍保持白色"))
                    .font(pf(12))
                    .foregroundColor(C.subLabel)
            }

            VStack(spacing: 0) {
                ForEach(Array(darkPagePresets.enumerated()), id: \.element.id) { index, preset in
                    Button {
                        Task { await applyDarkPagePreset(preset) }
                    } label: {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color(hex: preset.hex))
                                .frame(width: 42, height: 42)
                                .overlay(alignment: .bottomLeading) {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(Color(hex: preset.surface))
                                        .frame(width: 25, height: 12)
                                        .padding(5)
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .stroke(C.hairline, lineWidth: 0.6)
                                }

                            Text(Tr(preset.name))
                                .font(pf(15.5, .medium))
                                .foregroundColor(C.label)

                            Spacer(minLength: 0)

                            if activeDarkPagePreset == preset.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(C.green)
                            } else {
                                Circle()
                                    .stroke(C.hairline, lineWidth: 0.8)
                                    .frame(width: 20, height: 20)
                            }
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 58)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if index < darkPagePresets.count - 1 { HairLine(inset: 68) }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .onAppear { syncActiveDarkPagePreset() }
    }

    private func applyDarkPagePreset(_ preset: DarkPagePreset) async {
        let values = darkPageThemeValues(preset)
        activeDarkPagePreset = preset.id
        UIConfig.setDarkPageTheme(values)
        app.previewUIConfig(values)
        UISelectionFeedbackGenerator().selectionChanged()

        let direct = await API.shared.opsApplyDarkTheme(preset.id)
        let allOK: Bool
        if direct {
            allOK = true
        } else {
            allOK = await API.shared.opsSetUIValues(values)
        }
        if allOK {
            await app.refreshUI(force: true)
            msg = Tr("四个主页颜色已切换为") + preset.name
        } else {
            await app.refreshUI(force: true)
            syncActiveDarkPagePreset()
            msg = Tr("深色页面配色保存失败")
        }
    }

    private func syncActiveDarkPagePreset() {
        let savedId = UIConfig.text("darkThemeId", "")
        if darkPagePresets.contains(where: { $0.id == savedId }) {
            activeDarkPagePreset = savedId
            return
        }
        guard let current = UIConfig.darkHex("chatsPageBg") else {
            activeDarkPagePreset = ""
            return
        }
        activeDarkPagePreset = darkPagePresets.first(where: { $0.hex == current })?.id ?? ""
    }

    private func darkPageThemeValues(_ preset: DarkPagePreset) -> [String: String] {
        func dark(_ value: UInt32) -> String {
            String(format: "#%06X", value)
        }
        func value(_ key: String, light: UInt32, darkHex: UInt32) -> String {
            let currentLight: String? = {
                guard let raw = UIConfig.stringValue(key) else { return nil }
                return raw.split(separator: "|", omittingEmptySubsequences: false)
                    .first
                    .map(String.init)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }()
            let preservedLight = (currentLight?.isEmpty == false)
                ? currentLight!
                : String(format: "#%06X", light)
            return preservedLight + "|" + dark(darkHex)
        }

        var values: [String: String] = [:]
        values["darkThemeId"] = preset.id

        let canvasKeys: [(String, UInt32)] = [
            ("navBg", 0xEDEDED),
            ("tabBg", 0xF7F7F8),
            ("tabBarColor", 0xF7F7F8),
            ("chatsTopBg", 0xFFFFFF),
            ("chatsPageBg", 0xFFFFFF),
            ("chatsNavMaskColor", 0xEDEDED),
            ("chatsBottomMaskColor", 0xF7F7F7),
            ("hbChatsBottomMaskColor", 0xFFFFFF),
            ("hbChatsTabBg", 0xFFFFFF),
            ("hbChatsListBg", 0xFFFFFF),
            ("contactsBg", 0xFFFFFF),
            ("discoverBg", 0xEDEDED),
            ("discoverPageBg", 0xEDEDED),
            ("pageBg", 0xEDEDED),
            ("payPageBg", 0xF2F2F7),
            ("payInsetBg", 0xF2F2F7)
        ]
        for (key, light) in canvasKeys {
            values[key] = value(key, light: light, darkHex: preset.hex)
        }

        let surfaceKeys: [(String, UInt32)] = [
            ("cardBg", 0xFFFFFF),
            ("chatsRowBg", 0xFFFFFF),
            ("chatRowBg", 0xFFFFFF),
            ("hbChatsRowBg", 0xFFFFFF),
            ("discoverCardBg", 0xFFFFFF),
            ("meCardBg", 0xFFFFFF),
            ("pinnedBg", 0xFFFFFF),
            ("chatTimeBg", 0xE5E5E5),
            ("searchBg", 0xF2F2F2),
            ("fieldBg", 0xF2F2F2),
            ("payCardBg", 0xFFFFFF),
            ("payRaisedBg", 0xFFFFFF)
        ]
        for (key, light) in surfaceKeys {
            values[key] = value(key, light: light, darkHex: preset.surface)
        }

        values["lineColor"] = value("lineColor", light: 0xE5E5E5, darkHex: preset.line)
        values["navLineColor"] = value("navLineColor", light: 0xE8E8E8, darkHex: preset.line)
        values["payLineColor"] = value("payLineColor", light: 0xE5E5EA, darkHex: preset.line)
        return values
    }

    private var rpCoversSection: some View {
        card(Tr("红包封面（发红包时能挑的那几张）")) {
            if rpCovers.isEmpty {
                hint(Tr("还没有封面，下面点「新增一张封面」"))
            } else {
                ForEach(Array(rpCovers.enumerated()), id: \.element.id) { i, c in
                    if i > 0 { HairLine(inset: 70) }
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(hexString: c.color ?? "#B3241C", fallback: 0xB3241C))
                            if let img = (c.thumb?.isEmpty == false ? c.thumb : c.image), !img.isEmpty {
                                RemoteImage(path: img).frame(width: 46, height: 46)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                        .frame(width: 46, height: 46)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(c.name ?? "").font(pf(15.5)).foregroundColor(C.label).lineLimit(1)
                                if rpDefault == c.id {
                                    Text(Tr("默认"))
                                        .font(pf(10.5)).foregroundColor(.white)
                                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                                        .background(RoundedRectangle(cornerRadius: 4).fill(C.green))
                                }
                            }
                            Text((c.enabled == false ? Tr("已停用") : Tr("在用")) + " · " + (c.color ?? ""))
                                .font(pf(11.5)).foregroundColor(C.subLabel).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Button { rpEdit = c } label: {
                            Text(Tr("编辑")).font(pf(13)).foregroundColor(C.green)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14).frame(height: 62)
                }
            }
            HairLine(inset: 16)
            row(Tr("新增一张封面"), Tr("点这里")) { rpNew = true }
        }
    }

    private func loadRpCovers() async {
        if let r = try? await API.shared.opsRPCovers() {
            rpCovers = r.covers
            rpDefault = r.defaultId
        }
    }

    private func saveRpCovers(_ list: [API.RPCover], defaultId: String) async -> Bool {
        let arr: [[String: Any]] = list.map { c in
            var d: [String: Any] = [
                "id": c.id,
                "name": c.name ?? "",
                "image": c.image ?? "",
                "thumb": c.thumb ?? c.image ?? "",
                "color": c.color ?? "#B3241C",
                "enabled": c.enabled != false
            ]
            d["id"] = c.id
            return d
        }
        do {
            let saved = try await API.shared.opsRPSave(covers: arr, defaultId: defaultId)
            rpCovers = saved
            rpDefault = defaultId
            return true
        } catch {
            msg = (error as? APIError)?.errorDescription ?? "保存封面失败"
            return false
        }
    }

    private func applyRpEdit(_ r: RPCoverEditResult, editing: API.RPCover?) {
        var list = rpCovers
        var def = rpDefault
        if r.deleted, let id = editing?.id {
            list.removeAll { $0.id == id }
            if def == id { def = list.first?.id ?? "" }
        } else if let c = r.cover {
            if let old = editing, let i = list.firstIndex(where: { $0.id == old.id }) {
                list[i] = API.RPCover(id: old.id, name: c.name, image: c.image,
                                      thumb: c.thumb, color: c.color, enabled: c.enabled)
                if r.makeDefault { def = old.id }
            } else {
                let tmp = "cv" + String(Int(Date().timeIntervalSince1970 * 1000) % 100000)
                list.append(API.RPCover(id: tmp, name: c.name, image: c.image,
                                        thumb: c.thumb, color: c.color, enabled: c.enabled))
                if r.makeDefault || def.isEmpty { def = tmp }
            }
        }
        Task {
            if await saveRpCovers(list, defaultId: def) {
                msg = Tr("红包封面已保存（发红包页立刻能看到）")
            }
        }
    }

    private var addSection: some View {
        card(Tr("上线新音乐")) {
            row(Tr("音频文件"), audioName.isEmpty ? Tr("未选择") : audioName) { showAudioPick = true }
            Text(Tr("mp3 / m4a / flac / wma …什么格式都行，服务器会自动转成 mp3"))
                .font(pf(11.5)).foregroundColor(C.subLabel)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.bottom, 8)
            HairLine(inset: 16)
            row(Tr("批量导入"), batchTotal > 0 ? (Tr("已导入 ") + "\(batchDone)/\(batchTotal)") : Tr("一次选好几首")) { showBatchPick = true }
            HairLine(inset: 16)
            row(Tr("导入整个文件夹"), Tr("文件夹里的歌全进来（歌名=文件名）")) { showFolderPick = true }
            HairLine(inset: 16)
            HStack {
                Text(Tr("歌名")).font(pf(16)).foregroundColor(C.label)
                Spacer(minLength: 8)
                TextField(Tr("必填"), text: $title)
                    .font(pf(16)).multilineTextAlignment(.trailing)
            }
            .frame(height: 52).padding(.horizontal, 16)
            HairLine(inset: 16)
            HStack {
                Text(Tr("歌手")).font(pf(16)).foregroundColor(C.label)
                Spacer(minLength: 8)
                TextField(Tr("选填"), text: $artist)
                    .font(pf(16)).multilineTextAlignment(.trailing)
            }
            .frame(height: 52).padding(.horizontal, 16)
            HairLine(inset: 16)
            ZStack(alignment: .topLeading) {
                if lyrics.isEmpty {
                    Text(Tr("歌词（选填，一行一句或贴 LRC）"))
                        .font(pf(14)).foregroundColor(C.subLabel)
                        .padding(.top, 10).padding(.leading, 5)
                }
                TextEditor(text: $lyrics)
                    .font(pf(14))
                    .frame(height: 90)
                    .scrollContentBackground(.hidden)
            }
            .padding(.horizontal, 12)
            HairLine(inset: 16)
            row(Tr("封面"), newCoverURL.isEmpty ? Tr("未选择") : Tr("已选")) { startPick("") }
            HairLine(inset: 16)
            HStack {
                Button { Task { await addMusic() } } label: {
                    Text(busy == "add" ? Tr("上传中…") : Tr("加进曲库"))
                        .font(pf(15.5, .medium)).foregroundColor(.white)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(Capsule().fill(C.green))
                }
                .buttonStyle(.plain)
                .disabled(busy == "add" || title.isEmpty || audioURL.isEmpty)
                .opacity((title.isEmpty || audioURL.isEmpty) ? 0.5 : 1)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
    }

    private var musicIcons: some View {
        card(Tr("音乐图标")) {
            if let list = data?.music, !list.isEmpty {
                HStack {
                    Text(pickingMusic ? (Tr("已选 ") + "\(pickedMusic.count)" + Tr(" 首")) : Tr("点每首右边的图换封面"))
                        .font(pf(12)).foregroundColor(C.subLabel)
                    Spacer(minLength: 0)
                    Button {
                        if pickingMusic { Task { await deletePicked() } }
                        else { pickingMusic = true }
                    } label: {
                        Text(pickingMusic ? Tr("删除选中") : Tr("批量删除"))
                            .font(pf(13, .medium))
                            .foregroundColor(pickingMusic ? C.red : C.green)
                    }
                    .buttonStyle(.plain)
                    if pickingMusic {
                        Button { pickingMusic = false; pickedMusic = [] } label: {
                            Text(Tr("取消")).font(pf(13)).foregroundColor(C.subLabel)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 10)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                HairLine(inset: 16)
                ForEach(Array(list.enumerated()), id: \.element.id) { i, t in
                    if i > 0 { HairLine(inset: 70) }
                    iconRow(cover: t.cover ?? "", title: t.title, sub: t.artistText,
                            busyKey: t.id, id: t.id,
                            picking: pickingMusic, picked: pickedMusic.contains(t.id)) {
                        if pickingMusic {
                            if pickedMusic.contains(t.id) { pickedMusic.remove(t.id) }
                            else { pickedMusic.insert(t.id) }
                        } else {
                            startPick(t.id)
                        }
                    }
                }
            } else {
                hint(loading ? Tr("正在加载…") : Tr("曲库还是空的"))
            }
        }
    }

    private var sysNoticeSection: some View {
        card(Tr("系统通知（星言团队）")) {
            tipRow(Tr("总开关"), Binding(
                get: { snOn },
                set: { v in
                    snOn = v
                    Task { try? await API.shared.saveSysNotice(enabled: snOn, types: snTypes) }
                }
            ))
            ForEach(snKeys, id: \.key) { k in
                HairLine(inset: 16)
                tipRow(Tr(k.name), Binding(
                    get: { snTypes[k.key] ?? true },
                    set: { v in
                        snTypes[k.key] = v
                        Task { try? await API.shared.saveSysNotice(enabled: snOn, types: snTypes) }
                    }
                ))
            }
            HairLine(inset: 16)
            Text(Tr("开着的时候：新设备登录 / 改密码 / 改手机号 / 收到转账 / 后台公告，都会用那个号给用户发一张卡片（会话列表有红点）"))
                .font(pf(11.5)).foregroundColor(C.subLabel)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 10)
        }
    }

    private var snKeys: [(key: String, name: String)] {
        [("login", "登录提醒"), ("security", "安全提醒"), ("pay", "支付通知"), ("notice", "官方公告")]
    }

    private func tipRow(_ title: String, _ on: Binding<Bool>) -> some View {
        HStack {
            Text(title).font(pf(15.5)).foregroundColor(C.label)
            Spacer(minLength: 8)
            Toggle("", isOn: on).labelsHidden().tint(C.green)
        }
        .padding(.horizontal, 16).frame(height: 52)
    }

    private var officialSection: some View {
        card(Tr("官方号（名字 / 头像）")) {
            if officials.isEmpty {
                hint(loading ? Tr("正在加载…") : Tr("还没有官方号"))
            } else {
                ForEach(Array(officials.enumerated()), id: \.element.key) { i, o in
                    if i > 0 { HairLine(inset: 72) }
                    Button { editingOfficial = o } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(C.pageBg)
                                Text(o.name.isEmpty ? "★" : String(o.name.prefix(1)))
                                    .font(pf(20)).foregroundColor(C.subLabel)
                                if let av = o.avatar, !av.isEmpty {
                                    RemoteImage(path: av).frame(width: 48, height: 48)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                            }
                            .frame(width: 48, height: 48)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(o.name).font(pf(15.5)).foregroundColor(C.label).lineLimit(1)
                                Text((o.desc ?? "").isEmpty ? Tr("点一下换名字 / 头像") : o.desc!)
                                    .font(pf(12)).foregroundColor(C.subLabel).lineLimit(1)
                            }
                            Spacer(minLength: 6)
                            Text(Tr("编辑")).font(pf(13)).foregroundColor(C.green)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold)).foregroundColor(C.subLabel)
                        }
                        .padding(.horizontal, 14).frame(height: 64)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            HairLine(inset: 16)
            Text(Tr("「星言团队」和「星联世界」这些官方号的名字、头像都在这儿换：头像点一下选张图，名字点一下改字。改完所有人那边立刻变，不用出包。"))
                .font(pf(11.5)).foregroundColor(C.subLabel)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 10)
        }
    }

    private var miniappsSection: some View {
        card(Tr("小程序（图标 / 名字 / 说明）")) {
            if let list = data?.apps, !list.isEmpty {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, a in
                    if i > 0 { HairLine(inset: 70) }
                    Button { editing = a } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(C.pageBg)
                                Text(a.iconText).font(pfStyled(size: 22))
                                if let cv = a.cover, !cv.isEmpty {
                                    RemoteImage(path: cv).frame(width: 46, height: 46)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                            }
                            .frame(width: 46, height: 46)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(a.name).font(pf(15.5)).foregroundColor(C.label).lineLimit(1)
                                Text((a.desc ?? "").isEmpty ? a.url : a.desc!)
                                    .font(pf(12)).foregroundColor(C.subLabel).lineLimit(1)
                            }
                            Spacer(minLength: 6)
                            Text(Tr("编辑")).font(pf(13)).foregroundColor(C.green)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold)).foregroundColor(C.subLabel)
                        }
                        .padding(.horizontal, 14).frame(height: 62)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } else {
                hint(loading ? Tr("正在加载…") : Tr("还没有小程序"))
            }
        }
    }

    private var gameIcons: some View {
        card(Tr("游戏图标")) {
            if let list = data?.games, !list.isEmpty {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, g in
                    if i > 0 { HairLine(inset: 70) }
                    iconRow(cover: g.cover ?? "", title: g.name,
                            sub: g.groupText, busyKey: g.id) { startPick(g.id) }
                }
            } else {
                hint(loading ? Tr("正在加载…") : Tr("还没有小游戏"))
            }
        }
    }

    private func iconRow(cover: String, title: String, sub: String,
                         busyKey: String, id: String = "",
                         picking: Bool = false, picked: Bool = false,
                         tap: @escaping () -> Void) -> some View {
        Button { tap() } label: {
            HStack(spacing: 12) {
                if picking {
                    Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 21))
                        .foregroundColor(picked ? C.green : C.subLabel)
                }
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(C.pageBg)
                    Text("🖼").font(pf(18))
                    if !cover.isEmpty {
                        RemoteImage(path: cover).frame(width: 46, height: 46)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(pf(15.5)).foregroundColor(C.label).lineLimit(1)
                    Text(sub).font(pf(12)).foregroundColor(C.subLabel).lineLimit(1)
                }
                Spacer(minLength: 6)
                if !picking {
                    Text(busy == busyKey ? Tr("上传中…") : Tr("换图标"))
                        .font(pf(13)).foregroundColor(C.green)
                }
            }
            .padding(.horizontal, 14).frame(height: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(pf(13)).foregroundColor(C.subLabel)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 6)
            VStack(spacing: 0) { content() }
                .background(C.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 12)
        }
    }

    private func groupTitle(_ t: String) -> some View {
        Text(t)
            .font(pf(13, .medium))
            .foregroundColor(C.subLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 8)
    }

    private func row(_ k: String, _ v: String, tap: @escaping () -> Void) -> some View {
        Button { tap() } label: {
            HStack {
                Text(k).font(pf(16)).foregroundColor(C.label)
                Spacer(minLength: 8)
                Text(v).font(pf(15)).foregroundColor(C.subLabel).lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(C.subLabel)
            }
            .padding(.horizontal, 16).frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func hint(_ t: String) -> some View {
        Text(t).font(pf(13.5)).foregroundColor(C.subLabel)
            .frame(maxWidth: .infinity).padding(.vertical, 20)
    }

    private func startPick(_ id: String) {
        pickFor = id
        showCoverPick = true
    }

    private func load() async {
        data = await API.shared.manageData()

        if let list = try? await API.shared.officialAccounts() { officials = list }

        let cfg = await API.shared.sysNoticeCfg()
        snOn = cfg.enabled
        snTypes = cfg.types
        await loadShop()
        await loadLogs()
        await loadRpCovers()
        loading = false
    }

    private func uploadAudio(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        let name = url.lastPathComponent
        guard let raw = try? Data(contentsOf: url), !raw.isEmpty else {
            msg = Tr("读不到这个文件"); return
        }
        if raw.count > 60 * 1024 * 1024 { msg = Tr("这个音频超过 60MB，先压一下"); return }
        busy = "audio"
        msg = Tr("正在上传音频…")
        Task {
            do {
                let b64 = raw.base64EncodedString()
                let payload: [String: Any] = ["dataUrl": "data:" + mimeFor(name) + ";base64," + b64,
                                              "filename": name]
                let r = try await API.shared.rawUpload(payload)
                audioURL = r.url
                audioName = name
                msg = Tr("音频已上传")
            } catch {
                msg = (error as? APIError)?.errorDescription ?? "音频上传失败"
            }
            busy = ""
        }
    }

    private let audioExts: Set<String> = ["mp3", "m4a", "flac", "wav", "aac", "ogg", "oga",
                                          "opus", "ape", "wma", "aiff", "aif", "amr", "mka", "mp4"]

    private func importFolder(_ dir: URL) {
        let ok = dir.startAccessingSecurityScopedResource()
        if !ok { msg = Tr("读不到这个文件夹") ; return }
        var files: [URL] = []
        if let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) {
            for case let u as URL in e where audioExts.contains(u.pathExtension.lowercased()) {
                files.append(u)
            }
        }
        guard !files.isEmpty else {
            dir.stopAccessingSecurityScopedResource()
            msg = Tr("这个文件夹里没找到音频文件")
            return
        }

        importFiles(files, holding: dir)
    }

    private func importFiles(_ urls: [URL], holding: URL? = nil) {
        let list = urls.filter { audioExts.contains($0.pathExtension.lowercased()) }
        guard !list.isEmpty else {
            holding?.stopAccessingSecurityScopedResource()
            msg = Tr("没找到能导入的音频文件")
            return
        }
        batchTotal = list.count
        batchDone = 0
        Task {
            defer { holding?.stopAccessingSecurityScopedResource() }
            for u in list {
                let scoped = u.startAccessingSecurityScopedResource()
                defer { if scoped { u.stopAccessingSecurityScopedResource() } }
                do {
                    let raw = try Data(contentsOf: u)
                    if raw.count > 60 * 1024 * 1024 { batchDone += 1; continue }
                    let payload: [String: Any] = [
                        "dataUrl": "data:" + mimeFor(u.lastPathComponent) + ";base64," + raw.base64EncodedString(),
                        "filename": u.lastPathComponent
                    ]
                    let r = try await API.shared.rawUpload(payload)
                    try await API.shared.manageSaveMusic(id: "",
                                                         title: u.deletingPathExtension().lastPathComponent,
                                                         artist: "", cover: "", url: r.url, lyrics: "")
                } catch {

                }
                batchDone += 1
                msg = Tr("正在导入 ") + "\(batchDone)/\(batchTotal)"
            }
            msg = Tr("导入完成 ") + "\(batchDone)/\(batchTotal)"
            await load()
        }
    }

    private func mimeFor(_ name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "mp3": return "audio/mpeg"
        case "m4a", "m4r", "mp4", "aac": return "audio/mp4"
        case "wav": return "audio/wav"
        case "flac": return "audio/flac"
        case "ogg", "oga", "opus": return "audio/ogg"
        case "aiff", "aif": return "audio/aiff"
        case "webm": return "audio/webm"
        default: return "application/octet-stream"
        }
    }

    private func uploadPic(_ img: UIImage) {
        let key = pickFor
        busy = key.isEmpty ? "newcover" : key
        Task {
            do {
                let url = try await API.shared.upload(image: img)
                if key.isEmpty {
                    newCoverURL = url
                    msg = Tr("封面已上传")
                } else if key.hasPrefix("mus_") {
                    try await API.shared.manageSetIcon(kind: "music", id: key, cover: url)
                    msg = Tr("音乐图标已换好")
                } else {
                    try await API.shared.manageSetIcon(kind: "miniapp", id: key, cover: url)
                    msg = Tr("游戏图标已换好")
                }
                if !key.isEmpty { await load() }
            } catch {
                msg = (error as? APIError)?.errorDescription ?? "换图标失败"
            }
            busy = ""
        }
    }

    private func addMusic() async {
        busy = "add"
        do {
            try await API.shared.manageSaveMusic(id: "", title: title, artist: artist,
                                                 cover: newCoverURL, url: audioURL, lyrics: lyrics)
            msg = Tr("已加进曲库：") + title
            title = ""; artist = ""; lyrics = ""; audioURL = ""; audioName = ""; newCoverURL = ""
            await load()
        } catch {
            msg = (error as? APIError)?.errorDescription ?? "保存失败"
        }
        busy = ""
    }

    private func deletePicked() async {
        let ids = Array(pickedMusic)
        guard !ids.isEmpty else { msg = Tr("先勾几首再删"); return }
        busy = "del"
        do {
            try await API.shared.manageRemoveMusic(ids: ids)
            msg = Tr("已删除 ") + "\(ids.count)" + Tr(" 首")
            pickedMusic = []
            pickingMusic = false
            await load()
        } catch {
            msg = (error as? APIError)?.errorDescription ?? "删除失败"
        }
        busy = ""
    }
}

struct MiniAppEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: MiniApp

    var onSaved: () async -> Void

    @State private var name = ""
    @State private var desc = ""
    @State private var icon = ""
    @State private var group = ""
    @State private var url = ""
    @State private var cover = ""
    @State private var showPic = false
    @State private var busy = false
    @State private var msg = ""

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("编辑小程序"), back: { dismiss() }) {
                Button { Task { await save() } } label: {
                    Text(busy ? Tr("保存中…") : Tr("保存"))
                        .font(pf(15, .medium))
                        .foregroundColor(busy ? C.subLabel : C.green)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                }
                .buttonStyle(.plain)
                .disabled(busy)
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {

                    Button { showPic = true } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(C.pageBg)
                                Text(icon.isEmpty ? "🧩" : icon).font(pfStyled(size: 26))
                                if !cover.isEmpty {
                                    RemoteImage(path: cover).frame(width: 56, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                            .frame(width: 56, height: 56)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(Tr("图标图片")).font(pf(16)).foregroundColor(C.label)
                                Text(cover.isEmpty ? Tr("点一下选张图") : Tr("已设置，点一下换一张"))
                                    .font(pf(12)).foregroundColor(C.subLabel)
                            }
                            Spacer(minLength: 6)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold)).foregroundColor(C.subLabel)
                        }
                        .padding(.horizontal, 16).frame(height: 76)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(C.cardBg)

                    textRow(Tr("名字"), $name)
                    textRow(Tr("说明"), $desc)
                    textRow(Tr("图标（emoji）"), $icon)
                    textRow(Tr("分组"), $group)
                    textRow(Tr("入口地址"), $url)

                    if !msg.isEmpty {
                        Text(msg).font(pf(12.5)).foregroundColor(C.subLabel)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 18).padding(.top, 12)
                    }
                    Spacer().frame(height: 30)
                }
                .padding(.top, 8)
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea(edges: .top))
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .onAppear {
            name = item.name
            desc = item.desc ?? ""
            icon = item.icon ?? ""
            group = item.group ?? ""
            url = item.url
            cover = item.cover ?? ""
        }
        .sheet(isPresented: $showPic) {
            PhotoPicker { img in
                busy = true
                Task {
                    if let u = try? await API.shared.upload(image: img) {
                        cover = u
                        msg = Tr("图标图片已上传，别忘了保存")
                    } else {
                        msg = Tr("图片上传失败")
                    }
                    busy = false
                }
            }
        }
    }

    private func textRow(_ k: String, _ v: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Text(k).font(pf(16)).foregroundColor(C.label)
                .frame(width: 92, alignment: .leading)
            TextField("", text: v)
                .font(pf(16))
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(C.cardBg)
        .overlay(alignment: .bottom) { HairLine(inset: 16) }
    }

    private func save() async {
        busy = true
        do {
            try await API.shared.manageSaveMiniApp(id: item.id, name: name, desc: desc,
                                                   icon: icon, group: group, url: url)
            if cover != (item.cover ?? "") {
                try await API.shared.manageSetIcon(kind: "miniapp", id: item.id, cover: cover)
            }
            await onSaved()
            dismiss()
        } catch {
            msg = (error as? APIError)?.errorDescription ?? "保存失败"
        }
        busy = false
    }
}

struct OfficialEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: API.OfficialAccount

    var onSaved: () async -> Void

    @State private var name = ""
    @State private var avatar = ""
    @State private var busy = false
    @State private var msg = ""

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("官方号"), back: { dismiss() }) {
                Button { Task { await save() } } label: {
                    Text(busy ? Tr("保存中…") : Tr("保存"))
                        .font(pf(15, .medium))
                        .foregroundColor(busy ? C.subLabel : C.green)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                }
                .buttonStyle(.plain)
                .disabled(busy)
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {

                    Button { pickAvatar() } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(C.pageBg)
                                Text(name.isEmpty ? "★" : String(name.prefix(1)))
                                    .font(pf(24)).foregroundColor(C.subLabel)
                                if !avatar.isEmpty {
                                    RemoteImage(path: avatar).frame(width: 64, height: 64)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                            .frame(width: 64, height: 64)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(Tr("头像")).font(pf(16)).foregroundColor(C.label)
                                Text(busy ? Tr("上传中…") : Tr("点一下选张图片"))
                                    .font(pf(12)).foregroundColor(C.subLabel)
                            }
                            Spacer(minLength: 6)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold)).foregroundColor(C.subLabel)
                        }
                        .padding(.horizontal, 16).frame(height: 84)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(C.cardBg)

                    textRow(Tr("名字"), $name)

                    HStack(spacing: 10) {
                        Text(Tr("标识")).font(pf(16)).foregroundColor(C.label)
                            .frame(width: 92, alignment: .leading)
                        Text(item.key).font(pf(15)).foregroundColor(C.subLabel)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 54)
                    .background(C.cardBg)
                    .overlay(alignment: .bottom) { HairLine(inset: 16) }

                    if !msg.isEmpty {
                        Text(msg).font(pf(12.5)).foregroundColor(C.subLabel)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 18).padding(.top, 12)
                    }
                    Spacer().frame(height: 30)
                }
                .padding(.top, 8)
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea(edges: .top))
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .onAppear {
            name = item.name
            avatar = item.avatar ?? ""
        }
    }

    private func pickAvatar() {
        CrashCatcher.note("官方号", "点头像 key=" + item.key)
        AlbumPicker.present { img in
            CrashCatcher.note("官方号", "选到图 \(Int(img.size.width))x\(Int(img.size.height)) key=" + item.key)
            uploadAvatar(img)
        }
    }

    private func uploadAvatar(_ img: UIImage) {
        busy = true
        Task {
            do {
                let u = try await API.shared.upload(image: img)
                avatar = u
                msg = Tr("头像已上传，点右上角保存")
                CrashCatcher.note("官方号", "头像上传完 key=" + item.key)
            } catch {
                msg = (error as? APIError)?.errorDescription ?? Tr("图片上传失败")
                CrashCatcher.note("官方号", "头像上传失败 key=" + item.key + "：" + msg)
            }
            busy = false
        }
    }

    private func textRow(_ k: String, _ v: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Text(k).font(pf(16)).foregroundColor(C.label)
                .frame(width: 92, alignment: .leading)
            TextField("", text: v)
                .font(pf(16))
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(C.cardBg)
        .overlay(alignment: .bottom) { HairLine(inset: 16) }
    }

    private func save() async {
        let nm = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if nm.isEmpty { msg = Tr("名字不能为空"); return }
        busy = true
        do {
            try await API.shared.saveOfficial(key: item.key, name: nm, avatar: avatar)
            CrashCatcher.note("官方号", "保存完 key=" + item.key + " name=" + nm)
            await onSaved()
            dismiss()
        } catch {
            msg = (error as? APIError)?.errorDescription ?? "保存失败"
            CrashCatcher.note("官方号", "保存失败 key=" + item.key + "：" + msg)
        }
        busy = false
    }
}

struct ShopItemEditSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    let item: API.ShopItem?
    let onSaved: () -> Void

    @State private var name = ""
    @State private var price = ""
    @State private var stock = ""
    @State private var img = ""
    @State private var kind = "physical"
    @State private var desc = ""
    @State private var on = true
    @State private var sort = "0"
    @State private var busy = false
    @State private var msg = ""
    @State private var showPic = false

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: item == nil ? Tr("上架新商品") : Tr("改商品"), back: { dismiss() }) {
                Button { Task { await save() } } label: {
                    Text(busy ? Tr("保存中…") : Tr("保存"))
                        .font(pf(15, .medium))
                        .foregroundColor(busy ? C.subLabel : C.green)
                        .padding(.horizontal, 14).frame(height: 32)
                }
                .buttonStyle(.plain)
                .disabled(busy)
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    GroupCard {

                        Button { showPic = true } label: {
                            HStack(spacing: 12) {
                                Text(Tr("商品图")).font(pf(16)).foregroundColor(C.label)
                                Spacer(minLength: 0)
                                if busy && msg == Tr("图片上传中…") {
                                    ProgressView().scaleEffect(0.7)
                                }
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(C.pageBg)
                                    if img.isEmpty {
                                        Image(systemName: "photo")
                                            .font(.system(size: 16)).foregroundColor(C.subLabel)
                                    } else {
                                        RemoteImage(path: img).frame(width: 44, height: 44)
                                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    }
                                }
                                .frame(width: 44, height: 44)
                                Chevron(size: 9, line: 1.6)
                            }
                            .padding(.horizontal, 16).frame(height: 60)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        HairLine(inset: 16)
                        textRow(Tr("名字"), $name, Tr("抽纸 3 包"))
                        HairLine(inset: 16)
                        textRow(Tr("价格"), $price, "25")
                        HairLine(inset: 16)
                        textRow(Tr("库存"), $stock, "999")
                        HairLine(inset: 16)
                        textRow(Tr("排序"), $sort, "0")
                        HairLine(inset: 16)
                        textRow(Tr("说明"), $desc, Tr("选填"))
                    }
                    .padding(.top, 10)

                    GroupCard {
                        HStack(spacing: 12) {
                            Text(Tr("实物 / 虚拟")).font(pf(16)).foregroundColor(C.label)
                            Spacer(minLength: 0)
                            kindButton("physical", Tr("实物"))
                            kindButton("virtual", Tr("虚拟"))
                        }
                        .padding(.horizontal, 16).frame(height: 56)
                        HairLine(inset: 16)
                        HStack(spacing: 12) {
                            Text(Tr("上架")).font(pf(16)).foregroundColor(C.label)
                            Spacer(minLength: 0)
                            Toggle("", isOn: $on).labelsHidden().tint(C.green)
                        }
                        .padding(.horizontal, 16).frame(height: 56)
                    }

                    if let it = item {
                        Button {
                            Task { await remove(it) }
                        } label: {
                            Text(Tr("删除这件商品"))
                                .font(pf(16)).foregroundColor(C.red)
                                .frame(maxWidth: .infinity).frame(height: 48)
                        }
                        .buttonStyle(.plain)
                        .background(C.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.horizontal, 12)
                    }

                    if !msg.isEmpty {
                        Text(msg).font(pf(12.5)).foregroundColor(C.subLabel)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 18)
                    }
                    Spacer().frame(height: 30)
                }
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .sheet(isPresented: $showPic) {
            PhotoPicker { image in upload(image) }
        }
        .task {
            if let it = item {
                name = it.name
                price = moneyFmt(it.price)
                stock = "\(it.stock ?? 999)"
                img = it.img ?? ""
                kind = it.kind ?? "physical"
                desc = it.desc ?? ""
                on = it.on != false
                sort = "\(it.sort ?? 0)"
            }
        }
    }

    private func kindButton(_ id: String, _ label: String) -> some View {
        Button { kind = id } label: {
            Text(label)
                .font(pf(13.5))
                .foregroundColor(kind == id ? .white : C.label)
                .padding(.horizontal, 12).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(kind == id ? C.green : C.pageBg))
        }
        .buttonStyle(.plain)
    }

    private func textRow(_ k: String, _ v: Binding<String>, _ ph: String) -> some View {
        HStack(spacing: 12) {
            Text(k).font(pf(16)).foregroundColor(C.label).frame(width: 72, alignment: .leading)
            TextField(ph, text: v)
                .font(pf(15.5))
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16).frame(height: 52)
    }

    private func upload(_ image: UIImage) {
        msg = Tr("图片上传中…")
        Task {
            do {
                img = try await API.shared.upload(image: image)
                msg = Tr("图片已上传")
            } catch {
                msg = (error as? APIError)?.errorDescription ?? "图片上传失败"
            }
        }
    }

    private func save() async {
        let nm = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if nm.isEmpty { msg = Tr("名字不能为空"); return }
        busy = true
        msg = ""
        var b: [String: Any] = [
            "name": nm,
            "price": Double(price.replacingOccurrences(of: "¥", with: "")) ?? 0,
            "stock": Int(stock) ?? 0,
            "img": img,
            "kind": kind,
            "desc": desc,
            "on": on,
            "sort": Int(sort) ?? 0
        ]
        do {
            if let it = item {
                b["id"] = it.id
                _ = try await API.shared.opsShopSave(item: b, newItem: nil)
            } else {
                _ = try await API.shared.opsShopSave(item: nil, newItem: b)
            }
            DiagLog.shared.note("管理：保存商品 \(nm)")
            onSaved()
            dismiss()
        } catch {
            msg = (error as? APIError)?.errorDescription ?? "保存失败"
        }
        busy = false
    }

    private func remove(_ it: API.ShopItem) async {
        busy = true
        do {
            _ = try await API.shared.opsShopSave(item: nil, newItem: nil, removeId: it.id)
            DiagLog.shared.note("管理：删除商品 \(it.name)")
            onSaved()
            dismiss()
        } catch {
            msg = (error as? APIError)?.errorDescription ?? "删除失败"
        }
        busy = false
    }
}

struct CardAdminSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    let user: API.OpsUserRow

    @State private var cards: [WalletCard] = []
    @State private var busy = false
    @State private var msg = ""
    @State private var kind = "coupon"
    @State private var title = ""
    @State private var sub = ""
    @State private var amount = ""
    @State private var validTo = ""
    @State private var note = ""

    private let kinds: [(String, String)] = [("coupon", "优惠券"), ("member", "会员卡"),
                                             ("gift", "礼品卡"), ("ticket", "票")]

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("发卡 / 管理"), back: { dismiss() })
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    GroupCard {
                        HStack(spacing: 12) {
                            Avatar(path: user.avatar ?? "", size: 48, radius: 24)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(user.nickname ?? user.username ?? "").font(pf(16.5))
                                    .foregroundColor(C.label).lineLimit(1)
                                Text(user.username ?? "").font(pf(13)).foregroundColor(C.subLabel)
                            }
                            Spacer(minLength: 0)
                            Text(Tr("名下 ") + "\(cards.count)" + Tr(" 张"))
                                .font(pf(13)).foregroundColor(C.subLabel)
                        }
                        .padding(.horizontal, 16).frame(height: 68)
                    }
                    .padding(.top, 10)

                    if !cards.isEmpty {
                        card(Tr("他名下的卡（点右边删）")) {
                            ForEach(Array(cards.enumerated()), id: \.element.id) { i, c in
                                if i > 0 { HairLine(inset: 16) }
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(c.title ?? "").font(pf(15.5)).foregroundColor(C.label)
                                            .lineLimit(1)
                                        Text((c.kindName) + (c.used == true ? " · 已用" : "")
                                             + " · " + (c.code ?? ""))
                                            .font(pf(12)).foregroundColor(C.subLabel).lineLimit(1)
                                    }
                                    Spacer(minLength: 6)
                                    Button { Task { await del(c) } } label: {
                                        Text(Tr("删除")).font(pf(13)).foregroundColor(C.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 16).frame(height: 60)
                            }
                        }
                    }

                    card(Tr("发一张新卡")) {
                        HStack(spacing: 8) {
                            ForEach(kinds, id: \.0) { k in
                                Button { kind = k.0; if title.isEmpty { title = k.1 } } label: {
                                    Text(Tr(k.1))
                                        .font(pf(13))
                                        .foregroundColor(kind == k.0 ? .white : C.label)
                                        .padding(.horizontal, 10).frame(height: 30)
                                        .background(RoundedRectangle(cornerRadius: 15, style: .continuous)
                                            .fill(kind == k.0 ? C.green : C.pageBg))
                                }
                                .buttonStyle(.plain)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        HairLine(inset: 16)
                        textRow(Tr("标题"), $title, Tr("新人优惠券 ¥20"))
                        HairLine(inset: 16)
                        textRow(Tr("副标题"), $sub, Tr("满 100 可用"))
                        HairLine(inset: 16)
                        textRow(Tr("金额"), $amount, "20")
                        HairLine(inset: 16)
                        textRow(Tr("有效期"), $validTo, "2026-12-31")
                        HairLine(inset: 16)
                        textRow(Tr("说明"), $note, Tr("选填"))
                        HairLine(inset: 16)
                        Button { Task { await issue() } } label: {
                            Text(busy ? Tr("发送中…") : Tr("发卡"))
                                .font(pf(16, .medium)).foregroundColor(.white)
                                .frame(maxWidth: .infinity).frame(height: 46)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(C.green))
                        }
                        .buttonStyle(.plain)
                        .disabled(busy)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                    }

                    if !msg.isEmpty {
                        Text(msg).font(pf(12.5)).foregroundColor(C.subLabel)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 18)
                    }
                    Spacer().frame(height: 30)
                }
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .task { await reload() }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(pf(13)).foregroundColor(C.subLabel)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 6)
            VStack(spacing: 0) { content() }
                .background(C.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 12)
        }
    }

    private func textRow(_ k: String, _ v: Binding<String>, _ ph: String) -> some View {
        HStack(spacing: 12) {
            Text(k).font(pf(16)).foregroundColor(C.label).frame(width: 72, alignment: .leading)
            TextField(ph, text: v)
                .font(pf(15.5))
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16).frame(height: 52)
    }

    private func reload() async {
        if let list = try? await API.shared.opsCardList(userId: user.id) { cards = list }
    }

    private func issue() async {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { msg = Tr("标题不能为空"); return }
        busy = true
        do {
            cards = try await API.shared.opsCardIssue(userId: user.id, kind: kind, title: t,
                                                      sub: sub, amount: Double(amount) ?? 0,
                                                      validTo: validTo, note: note)
            msg = Tr("已发卡：") + t
            title = ""; sub = ""; amount = ""; validTo = ""; note = ""
            DiagLog.shared.note("管理：给 \(user.username ?? user.id) 发了一张「\(t)」")
        } catch {
            msg = (error as? APIError)?.errorDescription ?? "发卡失败"
        }
        busy = false
    }

    private func del(_ c: WalletCard) async {
        do {
            cards = try await API.shared.opsCardDelete(id: c.id, userId: user.id)
            msg = Tr("已删除：") + (c.title ?? "")
        } catch {
            msg = (error as? APIError)?.errorDescription ?? "删除失败"
        }
    }
}

struct AppLogDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let row: API.AppLogRow

    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("日志详情"), back: { dismiss() }) {
                Button {
                    UIPasteboard.general.string = fullText()
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                } label: {
                    Text(copied ? Tr("已复制") : Tr("复制"))
                        .font(pf(15, .medium))
                        .foregroundColor(C.green)
                        .padding(.horizontal, 14).frame(height: 32)
                }
                .buttonStyle(.plain)
            }
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    GroupCard {
                        kv(Tr("类型"), row.kind ?? "-")
                        HairLine(inset: 16)
                        kv(Tr("时间"), row.at ?? "-")
                        HairLine(inset: 16)
                        kv(Tr("版本"), row.app ?? "-")
                        HairLine(inset: 16)
                        kv(Tr("账号"), row.user ?? "-")
                        HairLine(inset: 16)
                        kv(Tr("来源 IP"), row.ip ?? "-")
                    }
                    .padding(.top, 10)

                    block(Tr("正文"), row.text ?? "")
                    if let s = row.stack, !s.isEmpty {
                        block(Tr("调用栈"), s)
                    }
                    Spacer().frame(height: 30)
                }
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
    }

    private func kv(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(k).font(pf(15)).foregroundColor(C.label).frame(width: 74, alignment: .leading)
            Text(v).font(pf(13.5)).foregroundColor(C.subLabel)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func block(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(pf(13)).foregroundColor(C.subLabel)
            Text(body)
                .font(pfStyled(size: 11.5, design: .monospaced))
                .foregroundColor(C.label.opacity(0.9))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(C.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 12)
    }

    private func fullText() -> String {
        var s = "类型：" + (row.kind ?? "-") + "\n"
        s += "时间：" + (row.at ?? "-") + "\n"
        s += "版本：" + (row.app ?? "-") + "\n"
        s += "账号：" + (row.user ?? "-") + "\n"
        s += "IP：" + (row.ip ?? "-") + "\n\n"
        s += (row.text ?? "")
        if let st = row.stack, !st.isEmpty { s += "\n\n--- 调用栈 ---\n" + st }
        return s
    }
}

struct ManageSubPage<V: View>: View {
    let title: String
    let content: () -> V
    @Environment(\.dismiss) private var dismiss

    init(title: String, @ViewBuilder content: @escaping () -> V) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: title, back: { dismiss() })
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) { content() }
                    .padding(.top, 10)
                    .padding(.bottom, 30)
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea(edges: .top))
        .toolbar(.hidden, for: .navigationBar)
        .hidesTabBar()

        .swipeBack { dismiss() }
    }
}
