import SwiftUI
import WebKit
import UIKit

struct MiniApp: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var desc: String?
    var icon: String?
    var kind: String?
    var url: String
    var color: String?

    var cover: String?

    var group: String?

    var action: String?

    var category: String? = nil

    var capabilities: [String]? = nil
    var provider: String? = nil
    var featured: Bool? = nil

    var isGame: Bool { (kind ?? "") == "game" }
    var iconText: String { (icon?.isEmpty == false) ? icon! : (isGame ? "🕹️" : "🧩") }
    var actionText: String { (action?.isEmpty == false) ? action! : "立即玩" }
    var groupText: String { (group?.isEmpty == false) ? group! : "推荐小游戏" }
}

struct MiniAppCapabilityCategory: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let examples: [String]

    static let all: [MiniAppCapabilityCategory] = [
        .init(id: "retail", title: "电商零售", subtitle: "商城与品牌", symbol: "bag.fill", tint: Color(hex: 0xFF6B4A),
              examples: ["综合商城", "品牌商城", "会员商城", "拼团", "二手交易"]),
        .init(id: "food", title: "餐饮服务", subtitle: "点餐外卖", symbol: "fork.knife", tint: Color(hex: 0xFF8A1F),
              examples: ["扫码点餐", "外卖", "排队取号", "订座", "团购套餐"]),
        .init(id: "life", title: "生活服务", subtitle: "到家与缴费", symbol: "house.fill", tint: Color(hex: 0x2E9E5B),
              examples: ["家政", "维修", "搬家", "洗衣", "水电燃气"]),
        .init(id: "beauty", title: "美容健康", subtitle: "到店与健身", symbol: "heart.fill", tint: Color(hex: 0xEC5B86),
              examples: ["美发", "美甲", "美容", "健身", "瑜伽"]),
        .init(id: "medical", title: "医疗医药", subtitle: "挂号问诊", symbol: "cross.case.fill", tint: Color(hex: 0xE5484D),
              examples: ["医院挂号", "在线问诊", "报告查询", "疫苗预约", "药品配送"]),
        .init(id: "travel", title: "旅游出行", subtitle: "酒店与交通", symbol: "airplane", tint: Color(hex: 0x2F73C9),
              examples: ["酒店", "民宿", "机票", "火车票", "打车"]),
        .init(id: "tickets", title: "文娱票务", subtitle: "电影与演出", symbol: "ticket.fill", tint: Color(hex: 0x8B5CF6),
              examples: ["电影票", "演出票", "展览", "KTV", "体育赛事"]),
        .init(id: "education", title: "教育培训", subtitle: "课程与校园", symbol: "graduationcap.fill", tint: Color(hex: 0x0EA5A4),
              examples: ["课程购买", "在线学习", "考试报名", "作业", "校园服务"]),
        .init(id: "property", title: "房产服务", subtitle: "租房与物业", symbol: "building.2.fill", tint: Color(hex: 0x7C8798),
              examples: ["新房", "二手房", "租房", "物业缴费", "社区报修"]),
        .init(id: "auto", title: "汽车服务", subtitle: "养车与出行", symbol: "car.fill", tint: Color(hex: 0x3978D4),
              examples: ["4S店", "洗车", "保养", "驾校", "停车"]),
        .init(id: "gov", title: "政务民生", subtitle: "办事与社保", symbol: "building.columns.fill", tint: Color(hex: 0xD64B45),
              examples: ["政务办事", "社保", "公积金", "税务", "社区登记"]),
        .init(id: "finance", title: "金融保险", subtitle: "银行与保险", symbol: "creditcard.fill", tint: Color(hex: 0xC58A21),
              examples: ["银行", "保险", "信用卡", "基金", "理财"]),
        .init(id: "delivery", title: "快递物流", subtitle: "寄件与查件", symbol: "shippingbox.fill", tint: Color(hex: 0xB27042),
              examples: ["寄件", "查件", "驿站", "同城配送", "货运"]),
        .init(id: "enterprise", title: "企业服务", subtitle: "办公与经营", symbol: "briefcase.fill", tint: Color(hex: 0x596579),
              examples: ["招聘", "打卡", "审批", "CRM", "进销存"]),
        .init(id: "content", title: "内容资讯", subtitle: "新闻与社区", symbol: "newspaper.fill", tint: Color(hex: 0x4D7CFE),
              examples: ["新闻", "视频", "社区", "论坛", "知识付费"]),
        .init(id: "tools", title: "工具效率", subtitle: "扫描与转换", symbol: "wrench.and.screwdriver.fill", tint: Color(hex: 0x64748B),
              examples: ["翻译", "OCR", "扫描", "PDF", "记账"]),
        .init(id: "social", title: "社交互动", subtitle: "报名与投票", symbol: "person.3.fill", tint: Color(hex: 0x14A38B),
              examples: ["投票", "报名", "问卷", "抽奖", "活动签到"]),
        .init(id: "games", title: "娱乐游戏", subtitle: "小游戏", symbol: "gamecontroller.fill", tint: Color(hex: 0x7A45D6),
              examples: ["休闲游戏", "答题", "互动游戏", "抽奖", "虚拟宠物"]),
        .init(id: "member", title: "会员营销", subtitle: "卡券与积分", symbol: "crown.fill", tint: Color(hex: 0xD9A326),
              examples: ["会员卡", "积分", "优惠券", "储值", "秒杀"]),
        .init(id: "local", title: "本地门店", subtitle: "到店与核销", symbol: "storefront.fill", tint: Color(hex: 0x0F9D75),
              examples: ["门店展示", "预约到店", "扫码点单", "员工核销", "附近门店"]),
        .init(id: "campus", title: "教育校园", subtitle: "校园生活", symbol: "book.closed.fill", tint: Color(hex: 0x3A7BD5),
              examples: ["校园卡", "课表", "成绩", "缴费", "社团活动"]),
        .init(id: "public", title: "公共服务", subtitle: "场馆与公告", symbol: "mappin.and.ellipse", tint: Color(hex: 0x4B7F8C),
              examples: ["停车缴费", "景区导览", "场馆预约", "图书馆", "社区公告"]),
        .init(id: "agriculture", title: "农业产业", subtitle: "农产品与供应链", symbol: "leaf.fill", tint: Color(hex: 0x4D9B43),
              examples: ["农产品商城", "认养", "溯源", "农资", "批发"]),
        .init(id: "live", title: "直播内容", subtitle: "直播与带货", symbol: "dot.radiowaves.left.and.right", tint: Color(hex: 0xE23D6D),
              examples: ["商品直播", "短视频", "内容种草", "课程直播", "互动直播"])
    ]
}

struct MiniAppShare: Decodable {
    var id: String
    var name: String
    var desc: String?
    var icon: String?
    var kind: String?
    var url: String
    var cover: String?
    var action: String?

    var asApp: MiniApp {
        MiniApp(id: id, name: name, desc: desc, icon: icon, kind: kind, url: url,
                color: nil, cover: cover, group: nil, action: action)
    }
    var isGame: Bool { (kind ?? "") == "game" }

    init?(json: String) {
        guard let d = json.data(using: .utf8),
              let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return nil }
        let name = (o["name"] as? String) ?? ""
        let url = (o["url"] as? String) ?? ""
        guard !name.isEmpty, !url.isEmpty else { return nil }
        self.id = (o["id"] as? String) ?? ""
        self.name = name
        self.desc = o["desc"] as? String
        self.icon = o["icon"] as? String
        self.kind = o["kind"] as? String
        self.url = url
        self.cover = o["cover"] as? String
        self.action = o["action"] as? String
    }
}

struct MiniAppCardBubble: View {
    let info: MiniAppShare
    var onOpen: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x2B2F3A), Color(hex: 0x171B22)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Text(info.icon?.isEmpty == false ? info.icon! : (info.isGame ? "🕹️" : "🧩"))
                    .font(pfStyled(size: 26))
                if let cv = info.cover, !cv.isEmpty {
                    RemoteImage(path: cv).frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text(info.name).font(pf(15)).foregroundColor(C.label).lineLimit(1)
                Text(info.desc?.isEmpty == false ? info.desc! : Tr("点开就能玩"))
                    .font(pf(12)).foregroundColor(C.subLabel).lineLimit(2)
                Text(Tr("小游戏"))
                    .font(pf(10.5)).foregroundColor(C.subLabel)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(width: 232, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(C.cardBg))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(C.hairline, lineWidth: 0.5))
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
    }
}

struct MiniAppsView: View {
    @EnvironmentObject var app: AppState
    @State private var items: [MiniApp] = []
    @State private var loading = true
    @State private var search = ""
    @State private var category = ""
    @State private var favoriteIds: Set<String> = []
    @State private var recentIds: [String] = []

    private let favKey = "mini.favorites"
    private let recentKey = "mini.recent"

    private var filtered: [MiniApp] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var rows = items
        if !q.isEmpty {
            rows = rows.filter {
                ($0.name + " " + ($0.desc ?? "") + " " + categoryTitle(for: $0)
                 + " " + (($0.capabilities ?? []).joined(separator: " "))).lowercased().contains(q)
            }
        } else if !category.isEmpty {
            rows = rows.filter { categoryId(for: $0) == category }
        }
        return rows.sorted {
            let f0 = $0.featured == true ? 1 : 0
            let f1 = $1.featured == true ? 1 : 0
            if f0 != f1 { return f0 > f1 }
            return $0.name.localizedCompare($1.name) == .orderedAscending
        }
    }

    private var favorites: [MiniApp] {
        let all = items.filter { favoriteIds.contains($0.id) }
        let order = items.map(\.id)
        return all.sorted {
            (order.firstIndex(of: $0.id) ?? 0) < (order.firstIndex(of: $1.id) ?? 0)
        }
    }

    private var recent: [MiniApp] {
        recentIds.compactMap { id in items.first { $0.id == id } }
    }

    var body: some View {
        List {
            if loading {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(Tr("正在加载…"))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 72)
                }
            } else {
                if search.isEmpty && category.isEmpty && !recent.isEmpty {
                    Section(header: Text(Tr("最近使用"))) {
                        ForEach(recent) { item in
                            appRow(item)
                        }
                    }
                }

                if search.isEmpty && category.isEmpty && !favorites.isEmpty {
                    Section(header: Text(Tr("我的收藏"))) {
                        ForEach(favorites) { item in
                            appRow(item)
                        }
                    }
                }

                Section(header: Text(categoryTitle)) {
                    if filtered.isEmpty {
                        emptyServiceRow
                    } else {
                        ForEach(filtered) { item in
                            appRow(item)
                        }
                    }
                }

                if search.isEmpty && category.isEmpty {
                    Section {
                        NavigationLink {
                            MiniAppCategoryListView(items: items, selection: $category)
                        } label: {
                            Label(Tr("浏览全部服务类目"), systemImage: "square.grid.2x2")
                        }
                    } footer: {
                        Text(Tr("后台新增的小程序会自动归入对应类目，不用重新出包。"))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Tr("小程序"))
        .navigationBarTitleDisplayMode(.large)
        .searchable(
            text: $search,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(Tr("搜索小程序、服务或能力"))
        )
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                categoryMenu
            }
        }
        .hidesTabBar()
        .task {
            items = await API.shared.miniApps()
            favoriteIds = Set(UserDefaults.standard.stringArray(forKey: favKey) ?? [])
            recentIds = UserDefaults.standard.stringArray(forKey: recentKey) ?? []
            loading = false
        }
    }

    private var categoryMenu: some View {
        Menu {
            Button {
                category = ""
                search = ""
            } label: {
                if category.isEmpty {
                    Label(Tr("全部服务"), systemImage: "checkmark")
                } else {
                    Text(Tr("全部服务"))
                }
            }
            Divider()
            ForEach(MiniAppCapabilityCategory.all) { item in
                Button {
                    category = item.id
                    search = ""
                } label: {
                    if category == item.id {
                        Label(Tr(item.title), systemImage: "checkmark")
                    } else {
                        Text(Tr(item.title))
                    }
                }
            }
        } label: {
            Image(systemName: category.isEmpty
                  ? "line.3.horizontal.decrease.circle"
                  : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityLabel(Tr("筛选服务类目"))
    }

    private var categoryTitle: String {
        if !category.isEmpty { return Tr(MiniAppCapabilityCategory.all.first { $0.id == category }?.title ?? "全部") }
        if !search.isEmpty { return Tr("搜索结果") }
        return Tr("全部服务")
    }

    private func appRow(_ item: MiniApp) -> some View {
        Button {
            runApp(item)
        } label: {
            HStack(spacing: 12) {
                appIcon(item)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(pfStyled(size: 17))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let desc = item.desc, !desc.isEmpty {
                        Text(desc)
                            .font(pfStyled(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Text(categoryTitle(for: item))
                        .font(pfStyled(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if favoriteIds.contains(item.id) {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                        .accessibilityLabel(Tr("已收藏"))
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                toggleFavorite(item)
            } label: {
                Label(favoriteIds.contains(item.id) ? Tr("取消收藏") : Tr("收藏"),
                      systemImage: favoriteIds.contains(item.id) ? "star.slash" : "star")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                toggleFavorite(item)
            } label: {
                Label(favoriteIds.contains(item.id) ? Tr("取消收藏") : Tr("收藏"),
                      systemImage: favoriteIds.contains(item.id) ? "star.slash" : "star")
            }
            .tint(.orange)
        }
    }

    private func appIcon(_ item: MiniApp) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill))

            Text(item.iconText)
                .font(pfStyled(size: 22))

            if let cover = item.cover, !cover.isEmpty {
                RemoteImage(path: cover)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var emptyServiceRow: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(Tr("这个能力已经预留，具体服务还没有接入"))
                .font(pfStyled(size: 17))
            Text(Tr("后台添加小程序入口后会自动出现在这里，不用重新出包"))
                .font(pfStyled(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private func runApp(_ it: MiniApp) {
        recentIds.removeAll { $0 == it.id }
        recentIds.insert(it.id, at: 0)
        recentIds = Array(recentIds.prefix(8))
        UserDefaults.standard.set(recentIds, forKey: recentKey)
        app.launchMiniApp(it)
    }

    private func toggleFavorite(_ it: MiniApp) {
        if favoriteIds.contains(it.id) { favoriteIds.remove(it.id) }
        else { favoriteIds.insert(it.id) }
        UserDefaults.standard.set(Array(favoriteIds), forKey: favKey)
    }

    private func categoryId(for app: MiniApp) -> String {
        miniAppCategoryId(for: app)
    }

    private func categoryTitle(for app: MiniApp) -> String {
        MiniAppCapabilityCategory.all.first { $0.id == categoryId(for: app) }?.title ?? "工具效率"
    }
}

private func miniAppCategoryId(for app: MiniApp) -> String {
    if let category = app.category, !category.isEmpty { return category }
    let raw = (app.name + " " + (app.group ?? "") + " " + (app.desc ?? "")).lowercased()
    for category in MiniAppCapabilityCategory.all {
        if raw.contains(category.title.lowercased()) { return category.id }
        for example in category.examples where raw.contains(example.lowercased()) {
            return category.id
        }
    }
    if app.isGame { return "games" }
    return "tools"
}

private struct MiniAppCategoryListView: View {
    @Environment(\.dismiss) private var dismiss
    let items: [MiniApp]
    @Binding var selection: String

    var body: some View {
        List {
            Section {
                categoryRow(
                    title: Tr("全部服务"),
                    subtitle: Tr("显示所有已接入的小程序与游戏"),
                    symbol: "square.grid.2x2",
                    tint: .blue,
                    count: items.count,
                    id: ""
                )
            }

            Section {
                ForEach(MiniAppCapabilityCategory.all) { category in
                    categoryRow(
                        title: Tr(category.title),
                        subtitle: Tr(category.subtitle),
                        symbol: category.symbol,
                        tint: category.tint,
                        count: items.filter { miniAppCategoryId(for: $0) == category.id }.count,
                        id: category.id
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Tr("服务类目"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func categoryRow(title: String,
                             subtitle: String,
                             symbol: String,
                             tint: Color,
                             count: Int,
                             id: String) -> some View {
        Button {
            selection = id
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(pfStyled(size: 17))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(pfStyled(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if count > 0 {
                    Text("\(count)")
                        .font(pfStyled(size: 12))
                        .foregroundStyle(.secondary)
                }

                if selection == id {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct MiniAppRuntimeView: View {
    let app: MiniApp
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var localIndex: URL?
    @State private var localDir: URL?
    @State private var loading = true
    @State private var errorText = ""

    @StateObject private var box = WebBox()

    @State private var capsuleMenu = false

    var body: some View {

        ZStack(alignment: .topTrailing) {
            if let localIndex {
                MiniAppWebView(index: localIndex, dir: localDir,
                               injectBridge: !app.isGame,
                               rankJs: chrisRankJs(game: app.id, token: API.shared.token, base: API.shared.base),
                               box: box,
                               onMessage: handle,
                               onScore: { g, s in Task { await API.shared.gameScore(g, s) } },
                               onRank: { g, done in Task { done(await API.shared.gameRankJSONWithAvatars(g)) } })
            } else if loading {
                VStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text(Tr("正在准备…")).font(pf(13.5)).foregroundColor(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    Text(errorText.isEmpty ? Tr("打不开") : errorText)
                        .font(pf(14)).foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center).padding(.horizontal, 30)
                    Button { Task { await prepare(force: true) } } label: {
                        Text(Tr("重试")).font(pf(15, .medium)).foregroundColor(.white)
                            .padding(.horizontal, 22).frame(height: 40)
                            .background(Capsule().fill(C.green))
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            GameWindowCapsule(
                onMenu: { capsuleMenu = true },
                onClose: { dismiss() }
            )
            .padding(.top, 8)
            .padding(.trailing, 10)

            if localIndex != nil {
                VStack {
                    Spacer(minLength: 0)
                    HStack {
                        Spacer(minLength: 0)
                        Button {
                            box.web?.evaluateJavaScript("window.chrisRank && chrisRank.show()")
                        } label: {
                            Text("🏆")
                                .font(pfStyled(size: 20))
                                .frame(width: 42, height: 42)
                                .background(Circle().fill(Color.black.opacity(0.35)))
                                .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 12)
                        .padding(.bottom, 18)
                    }
                }
            }
        }
        .background(Color(hex: 0x0B0E17).ignoresSafeArea())
        .statusBarHidden(false)
        .task { await prepare() }
        .onAppear { StatusBarStyle.shared.set(light: true) }
        .onDisappear { StatusBarStyle.shared.set(light: false) }
        .confirmationDialog(title.isEmpty ? app.name : title, isPresented: $capsuleMenu, titleVisibility: .visible) {
            Button(Tr("好友排名")) { box.web?.evaluateJavaScript("window.chrisRank && chrisRank.show()") }
            Button(Tr("重新进入")) { Task { await prepare(force: true) } }
            Button(Tr("关闭"), role: .destructive) { dismiss() }
            Button(Tr("取消"), role: .cancel) { }
        }
    }

    private var files: [String] {
        ["index.html", "js/adapter.js", "js/engine.js", "js/sound.js", "js/main.js"]
    }

    private func prepare(force: Bool = false) async {
        loading = true
        errorText = ""
        guard let remote = API.shared.assetURL(app.url) else {
            loading = false
            errorText = Tr("这个入口地址不对（后台「小程序」里看看）")
            return
        }
        let remoteDir = remote.deletingLastPathComponent()
        let fm = FileManager.default
        guard let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            loading = false
            return
        }
        let root = caches.appendingPathComponent("miniapps/\(app.id)", isDirectory: true)
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)

            let list = await miniAppFileList(baseDir: remoteDir)
            for f in list {
                let dst = root.appendingPathComponent(f)
                if !force, let sz = try? dst.resourceValues(forKeys: [.fileSizeKey]).fileSize, sz > 0 { continue }
                try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
                let data = try await API.shared.assetData(remoteDir.appendingPathComponent(f))
                try data.write(to: dst, options: .atomic)
            }
            localDir = root
            localIndex = root.appendingPathComponent("index.html")
        } catch {
            errorText = Tr("下载失败：") + error.localizedDescription
        }
        loading = false
    }

    private func handle(_ dict: [String: Any]) {
        let fn = (dict["fn"] as? String) ?? ""
        switch fn {
        case "title":
            title = (dict["title"] as? String) ?? ""
        case "toast":
            appState.show((dict["title"] as? String) ?? "")
        case "vibrate":
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case "clipboard":
            UIPasteboard.general.string = (dict["text"] as? String) ?? ""
            appState.show(Tr("已复制"))
        case "share":
            appState.show(Tr("已分享"))
        case "exit":
            dismiss()
        default:
            break
        }
    }
}

struct MiniAppWebView: UIViewRepresentable {
    let index: URL
    let dir: URL?
    let injectBridge: Bool

    let rankJs: String
    let box: WebBox
    let onMessage: ([String: Any]) -> Void

    var onScore: ((String, Int) -> Void)? = nil
    var onRank: ((String, @escaping (String) -> Void) -> Void)? = nil

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []

        cfg.userContentController.addUserScript(
            WKUserScript(source: WebSafeArea.js, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        if !rankJs.isEmpty {
            cfg.userContentController.addUserScript(
                WKUserScript(source: rankJs, injectionTime: .atDocumentStart, forMainFrameOnly: true))

            context.coordinator.rank.onScore = onScore
            context.coordinator.rank.onRank = onRank
            cfg.userContentController.add(context.coordinator.rank, name: "chrisRank")
        }
        if injectBridge {
            cfg.userContentController.add(context.coordinator, name: "wx")
            let js = miniAppWxBridge(token: API.shared.token, base: API.shared.base)
            cfg.userContentController.addUserScript(
                WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        let v = WKWebView(frame: .zero, configuration: cfg)
        v.isOpaque = false
        v.backgroundColor = UIColor(red: 0.043, green: 0.055, blue: 0.09, alpha: 1)
        v.scrollView.bounces = false
        v.scrollView.contentInsetAdjustmentBehavior = .never
        v.loadFileURL(index, allowingReadAccessTo: dir ?? index.deletingLastPathComponent())
        context.coordinator.web = v
        context.coordinator.rank.web = v
        box.web = v
        return v
    }

    func updateUIView(_ v: WKWebView, context: Context) { }

    func makeCoordinator() -> Coord { Coord(onMessage: onMessage) }

    final class Coord: NSObject, WKScriptMessageHandler {
        let onMessage: ([String: Any]) -> Void

        let rank = RankBridge()
        weak var web: WKWebView?
        init(onMessage: @escaping ([String: Any]) -> Void) { self.onMessage = onMessage }
        func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
            if let d = message.body as? [String: Any] { onMessage(d) }
            else if let s = message.body as? String { onMessage(["fn": s]) }
        }
    }
}

func miniAppFileList(baseDir: URL) async -> [String] {
    let fallback = ["index.html", "js/adapter.js", "js/engine.js", "js/sound.js", "js/main.js"]
    guard let data = try? await API.shared.assetData(baseDir.appendingPathComponent("files.json")),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let arr = obj["files"] as? [String], !arr.isEmpty else { return fallback }
    return arr
}

func miniAppWxBridge(token: String, base: String) -> String {
    let t = token.replacingOccurrences(of: "\"", with: "\\\"")
    let b = base.replacingOccurrences(of: "\"", with: "\\\"")
    return """
    (function () {
      if (window.wx && window.wx.__chris) return;
      var TOKEN = "\(t)", BASE = "\(b)";
      function post(o) { try { window.webkit.messageHandlers.wx.postMessage(o); } catch (e) { } }
      function abs(u) { return /^https?:/i.test(u) ? u : (BASE + (u.charAt(0) === '/' ? u : '/' + u)); }
      var api = {
        __chris: true,
        setNavigationBarTitle: function (o) { post({ fn: 'title', title: (o && o.title) || '' }); },
        setNavigationBarColor: function () { },
        showToast: function (o) { post({ fn: 'toast', title: (o && o.title) || '' }); },
        hideToast: function () { },
        showLoading: function (o) { post({ fn: 'toast', title: (o && o.title) || '加载中' }); },
        hideLoading: function () { },
        showModal: function (o) {
          o = o || {};
          var ok = window.confirm(((o.title || '') + '\\n' + (o.content || '')).trim());
          if (ok && o.success) o.success({ confirm: true, cancel: false });
          else if (!ok && o.fail) o.fail({ confirm: false, cancel: true });
        },
        vibrateShort: function () { post({ fn: 'vibrate' }); },
        vibrateLong: function () { post({ fn: 'vibrate' }); },
        setStorageSync: function (k, v) { try { localStorage.setItem('wx_' + k, JSON.stringify(v)); } catch (e) { } },
        getStorageSync: function (k) { try { var s = localStorage.getItem('wx_' + k); return s == null ? '' : JSON.parse(s); } catch (e) { return ''; } },
        removeStorageSync: function (k) { try { localStorage.removeItem('wx_' + k); } catch (e) { } },
        clearStorageSync: function () { try { Object.keys(localStorage).forEach(function (k) { if (k.indexOf('wx_') === 0) localStorage.removeItem(k); }); } catch (e) { } },
        setStorage: function (o) {
          try { api.setStorageSync(o && o.key, o && o.data); if (o && o.success) o.success({ errMsg: 'setStorage:ok' }); }
          catch (e) { if (o && o.fail) o.fail({ errMsg: String(e) }); }
        },
        getStorage: function (o) {
          try { if (o && o.success) o.success({ data: api.getStorageSync(o && o.key), errMsg: 'getStorage:ok' }); }
          catch (e) { if (o && o.fail) o.fail({ errMsg: String(e) }); }
        },
        removeStorage: function (o) {
          try { api.removeStorageSync(o && o.key); if (o && o.success) o.success({ errMsg: 'removeStorage:ok' }); }
          catch (e) { if (o && o.fail) o.fail({ errMsg: String(e) }); }
        },
        clearStorage: function (o) {
          try { api.clearStorageSync(); if (o && o.success) o.success({ errMsg: 'clearStorage:ok' }); }
          catch (e) { if (o && o.fail) o.fail({ errMsg: String(e) }); }
        },
        getStorageInfoSync: function () {
          var keys = [], size = 0;
          try {
            Object.keys(localStorage).forEach(function (k) {
              if (k.indexOf('wx_') !== 0) return;
              keys.push(k.slice(3));
              size += String(localStorage.getItem(k) || '').length;
            });
          } catch (e) { }
          return { keys: keys, currentSize: Math.ceil(size / 1024), limitSize: 10240 };
        },
        request: function (o) {
          o = o || {};
          var h = {}; var hh = o.header || {};
          for (var k in hh) h[k] = hh[k];
          if (TOKEN) h['Authorization'] = 'Bearer ' + TOKEN;
          if (o.data && (o.method || 'GET').toUpperCase() !== 'GET') h['Content-Type'] = 'application/json';
          fetch(abs(o.url), { method: o.method || 'GET', headers: h,
            body: (o.data && (o.method || 'GET').toUpperCase() !== 'GET') ? JSON.stringify(o.data) : undefined })
            .then(function (r) { return r.json(); })
            .then(function (j) { if (o.success) o.success({ statusCode: 200, data: j }); })
            .catch(function (e) { if (o.fail) o.fail({ errMsg: String(e) }); });
        },
        getSystemInfoSync: function () {
          return { platform: 'ios', brand: 'Apple', model: 'iPhone', system: 'iOS',
                   windowWidth: window.innerWidth, windowHeight: window.innerHeight,
                   pixelRatio: window.devicePixelRatio || 2, statusBarHeight: 0,
                   screenWidth: window.innerWidth, screenHeight: window.innerHeight,
                   safeArea: { top: 0, bottom: 0, left: 0, right: 0 } };
        },
        getSystemInfo: function (o) {
          setTimeout(function () { if (o && o.success) o.success(api.getSystemInfoSync()); }, 0);
        },
        getWindowInfo: function () {
          return { windowWidth: window.innerWidth, windowHeight: window.innerHeight,
                   screenWidth: window.innerWidth, screenHeight: window.innerHeight,
                   pixelRatio: window.devicePixelRatio || 2 };
        },
        getDeviceInfo: function () {
          return { brand: 'Apple', model: 'iPhone', platform: 'ios', system: 'iOS' };
        },
        getAppBaseInfo: function () {
          return { SDKVersion: '3.0.0', language: 'zh_CN', version: '1.0.0' };
        },
        getNetworkType: function (o) {
          var type = navigator.onLine ? 'wifi' : 'none';
          setTimeout(function () { if (o && o.success) o.success({ networkType: type }); }, 0);
        },
        onNetworkStatusChange: function (cb) {
          if (typeof cb !== 'function') return;
          api.__networkListeners = api.__networkListeners || [];
          api.__networkListeners.push(cb);
          cb({ isConnected: navigator.onLine, networkType: navigator.onLine ? 'wifi' : 'none' });
        },
        offNetworkStatusChange: function (cb) {
          api.__networkListeners = (api.__networkListeners || []).filter(function (x) { return x !== cb; });
        },
        canIUse: function (name) { return !!(name && api[name]); },
        nextTick: function (cb) { setTimeout(cb || function () { }, 0); },
        getMenuButtonBoundingClientRect: function () {
          return { top: 6, bottom: 38, left: window.innerWidth - 60, right: window.innerWidth - 10,
                   width: 50, height: 32 };
        },
        pageScrollTo: function (o) {
          window.scrollTo({ top: (o && o.scrollTop) || 0, behavior: 'smooth' });
        },
        setClipboardData: function (o) {
          post({ fn: 'clipboard', text: String((o && o.data) || '') });
          if (o && o.success) o.success({ errMsg: 'setClipboardData:ok' });
        },
        getAccountInfoSync: function () {
          return { miniProgram: { appId: 'chris-miniapp', envVersion: 'release' } };
        },
        reportAnalytics: function () { },
        getLaunchOptionsSync: function () { return { scene: 1001, query: {}, path: '' }; },
        getEnterOptionsSync: function () { return api.getLaunchOptionsSync(); },
        showShareMenu: function () { }, hideShareMenu: function () { },
        onShareAppMessage: function () { }, onShow: function () { }, onHide: function () { },
        onError: function () { }, onUnhandledRejection: function () { },
        shareAppMessage: function () { post({ fn: 'share' }); },
        exitMiniProgram: function () { post({ fn: 'exit' }); },
        navigateTo: function (o) {
          if (!o || !o.url) return;
          window.location.href = abs(o.url);
          if (o.success) o.success({ errMsg: 'navigateTo:ok' });
        },
        redirectTo: function (o) {
          if (!o || !o.url) return;
          window.location.replace(abs(o.url));
          if (o.success) o.success({ errMsg: 'redirectTo:ok' });
        },
        reLaunch: function (o) {
          if (!o || !o.url) return;
          window.location.replace(abs(o.url));
          if (o.success) o.success({ errMsg: 'reLaunch:ok' });
        },
        switchTab: function (o) {
          if (!o || !o.url) return;
          window.location.href = abs(o.url);
          if (o.success) o.success({ errMsg: 'switchTab:ok' });
        },
        navigateBack: function (o) {
          if (window.history.length > 1) window.history.back();
          else post({ fn: 'exit' });
          if (o && o.success) o.success({ errMsg: 'navigateBack:ok' });
        }
      };
      window.wx = api;
      window.addEventListener('online', function () {
        (api.__networkListeners || []).forEach(function (cb) {
          try { cb({ isConnected: true, networkType: 'wifi' }); } catch (e) { }
        });
      });
      window.addEventListener('offline', function () {
        (api.__networkListeners || []).forEach(function (cb) {
          try { cb({ isConnected: false, networkType: 'none' }); } catch (e) { }
        });
      });
    })();
    """
}
