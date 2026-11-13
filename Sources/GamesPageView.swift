import SwiftUI
import WebKit
import AVFoundation

struct GameTableSeat: Decodable {
    var id: String?
    var name: String?
    var avatar: String?
    var mine: Bool?
}

struct GameTable: Decodable, Identifiable {
    var code: String
    var id: String { code }
    var game: String?
    var host: String?
    var started: Bool?
    var seated: Int?
    var seats: [GameTableSeat?]?

    var seatNames: [String?] { (seats ?? []).map { $0?.name } }
}

func miniAppSharePayload(_ g: MiniApp) -> String {
    var d: [String: Any] = ["id": g.id, "name": g.name, "kind": g.kind ?? "game", "url": g.url]
    if let v = g.desc, !v.isEmpty { d["desc"] = v }
    if let v = g.icon, !v.isEmpty { d["icon"] = v }
    if let v = g.cover, !v.isEmpty { d["cover"] = v }
    if let v = g.action, !v.isEmpty { d["action"] = v }
    guard let data = try? JSONSerialization.data(withJSONObject: d),
          let s = String(data: data, encoding: .utf8) else { return "" }
    return s
}

struct GamesPageView: View {

    static func stableKey(_ s: String) -> String {
        var h: UInt64 = 5381
        for b in s.utf8 { h = (h &* 33) &+ UInt64(b) }
        return String(h, radix: 16)
    }

    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var games: [MiniApp] = []
    @State private var shareApp: MiniApp?

    @State private var iconPickFor = ""
    @State private var showIconPick = false

    @State private var bannerIndex = 0

    @State private var detail: MiniApp?
    @State private var showDetail = false

    @State private var showRankBoard = false

    private let tick = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    private let recentKey = "chris.games.recent"
    @State private var recentIds: [String] = []

    private let pageBg = Color.dyn(0xEDEDED, 0x111114)
    private let cardBg = Color.dyn(0xFFFFFF, 0x1B1B1D)
    private let ink = C.label
    private let subInk = C.subLabel

    @State private var loading = true
    @State private var isVisible = false
    @State private var isInteracting = false
    @State private var lastInteraction = Date.distantPast

    @State private var showAdmin = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(Tr("游戏")).font(pf(17, .semibold)).foregroundColor(ink)
                HStack(spacing: 0) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundColor(ink)
                            .frame(width: 44, height: L.navH)
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)

                    if app.me?.ops == true {
                        Button { showAdmin = true } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundColor(ink)
                                .frame(width: 44, height: L.navH)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: L.navH)
            .background(pageBg)

            ScrollView {
                LazyVStack(spacing: 0) {

                    if !bannerGames.isEmpty { banner }

                    if !recentGames.isEmpty { recentRow }

                    if !list.isEmpty { rankEntry }

                    ForEach(groups, id: \.0) { g in
                        HStack(spacing: 6) {
                            Text(g.0).font(pf(15, .medium)).foregroundColor(ink)
                            Spacer(minLength: 0)
                            Text(Lang.isEnglish ? "\(g.1.count)" : "\(g.1.count) 款")
                                .font(pf(11)).foregroundColor(subInk)
                        }
                        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 9)

                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)
                        ], alignment: .leading, spacing: 10) {
                            ForEach(g.1) { g2 in posterCard(g2) }
                        }
                        .padding(.horizontal, 16)
                    }

                    if loading {
                        HStack(spacing: 10) {
                            ProgressView().tint(subInk)
                            Text(Tr("正在加载…")).font(pf(14)).foregroundColor(subInk)
                        }
                        .frame(maxWidth: .infinity).padding(.top, 30)
                    } else if list.isEmpty {
                        Text(Tr("游戏暂时没准备好，点一下再试"))
                            .font(pf(14)).foregroundColor(subInk)
                            .frame(maxWidth: .infinity).padding(.top, 30)
                    }
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { _ in isInteracting = true }
                    .onEnded { _ in
                        isInteracting = false
                        lastInteraction = Date()
                    }
            )
        }
        .background(pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .hidesTabBar()
        .swipeBack { dismiss() }

        .sheet(isPresented: $showIconPick) {
            PhotoPicker { img in
                let id = iconPickFor
                Task {
                    if let url = try? await API.shared.upload(image: img) {
                        try? await API.shared.manageSetIcon(kind: "miniapp", id: id, cover: url)
                        games = await API.shared.miniApps(kind: "game")
                    }
                }
            }
        }

        .sheet(item: $shareApp) { g in
            ForwardPickerView(items: [ForwardItem(kind: "miniapp", content: miniAppSharePayload(g))]) { shareApp = nil }
                .environmentObject(app)
        }
        .sheet(isPresented: $showAdmin) {
            GamesPageAdminSheet(games: list).environmentObject(app)
        }
        .task {

            recentIds = UserDefaults.standard.stringArray(forKey: recentKey) ?? []
            games = await API.shared.miniApps(kind: "game")
            loading = false
        }
        .onChange(of: games.count) { _ in bannerIndex = 0 }
        .onReceive(tick) { _ in
            let n = bannerGames.count
            guard n > 1,
                  isVisible,
                  scenePhase == .active,
                  !isInteracting,
                  Date().timeIntervalSince(lastInteraction) > 1.2 else { return }
            withAnimation(.easeInOut(duration: 0.4)) { bannerIndex = (bannerIndex + 1) % n }
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .navigationDestination(isPresented: $showDetail) {
            if let g = detail {
                GameDetailView(game: g) { pick in
                    recordPlayed(pick)
                    app.launchMiniApp(pick)
                }
            }
        }
        .navigationDestination(isPresented: $showRankBoard) {
            GameRankBoardView(games: list)
        }
    }

    private var list: [MiniApp] { games }

    private var bannerGames: [MiniApp] {

        let picked = UIConfig.text("gamesBannerIds", "")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !picked.isEmpty {
            let mapped = picked.compactMap { id in list.first { $0.id == id } }
            if !mapped.isEmpty { return Array(mapped.prefix(8)) }
        }
        let withCover = list.filter { ($0.cover?.isEmpty == false) }
        if withCover.count >= 2 { return Array(withCover.prefix(5)) }
        return Array(list.prefix(3))
    }

    @ViewBuilder private var wallpaperBg: some View {
        let wp = UIConfig.text("gamesWallpaper", "").trimmingCharacters(in: .whitespaces)
        ZStack {
            LinearGradient(colors: [Color(hex: 0x1B1E26), Color(hex: 0x0E1015)],
                           startPoint: .top, endPoint: .bottom)
            if !wp.isEmpty {
                RemoteImage(path: wp, mode: .fill, maxSide: 1000)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .overlay(Color.black.opacity(0.35))
            }
        }
        .ignoresSafeArea()
    }

    private var banner: some View {
        let items = bannerGames
        return VStack(spacing: 7) {
            TabView(selection: $bannerIndex) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, g in
                    Button { openDetail(g) } label: { bannerCard(g) }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 178)

            if items.count > 1 {
                HStack(spacing: 5) {
                    ForEach(0..<items.count, id: \.self) { i in
                        Circle()
                            .fill(i == min(bannerIndex, items.count - 1)
                                  ? C.label.opacity(0.7) : C.subLabel.opacity(0.3))
                            .frame(width: 5.5, height: 5.5)
                    }
                }
            }
        }
        .padding(.top, 12)
    }

    private func bannerCard(_ g: MiniApp) -> some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Color(hex: 0x2B2F3A), Color(hex: 0x171B22)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            if let cv = g.cover, !cv.isEmpty {
                RemoteImage(path: cv, mode: .fill, maxSide: 1200)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {

                let wp = UIConfig.text("gamesWallpaper", "").trimmingCharacters(in: .whitespaces)
                ZStack {
                    if !wp.isEmpty {
                        RemoteImage(path: wp, mode: .fill, maxSide: 1200)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                            .overlay(Color.black.opacity(0.30))
                    }
                    Text(g.iconText).font(pfStyled(size: 66))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            LinearGradient(colors: [.clear, .black.opacity(0.55)],
                           startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 3) {
                Text(g.name).font(pf(19, .semibold)).foregroundColor(.white).lineLimit(1)
                Text(g.desc ?? "").font(pf(12.5)).foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 178)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .topLeading) {
            Text(Tr("精选"))
                .font(pf(10.5, .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(Capsule().fill(Color.black.opacity(0.32)))
                .padding(12)
        }
    }

    private var recentGames: [MiniApp] {
        recentIds.compactMap { id in list.first { $0.id == id } }
    }

    private var recentRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(Tr("最近在玩")).font(pf(15.5, .semibold)).foregroundColor(ink)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(recentGames) { g in
                        Button { recordPlayed(g); app.launchMiniApp(g) } label: {
                            HStack(spacing: 8) {
                                gameCircle(g, size: 30)
                                Text(g.name).font(pf(12.5, .medium)).foregroundColor(ink)
                                    .lineLimit(1).frame(maxWidth: 112, alignment: .leading)
                            }
                            .padding(.leading, 6)
                            .padding(.trailing, 13)
                            .frame(height: 44)
                            .background(Capsule().fill(cardBg))
                            .overlay(Capsule().stroke(C.hairline, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.top, 14)
    }

    private func recordPlayed(_ g: MiniApp) {
        var ids = recentIds.filter { $0 != g.id }
        ids.insert(g.id, at: 0)
        if ids.count > 8 { ids = Array(ids.prefix(8)) }
        recentIds = ids
        UserDefaults.standard.set(ids, forKey: recentKey)
    }

    private func openDetail(_ g: MiniApp) {
        detail = g
        showDetail = true
    }

    private func play(_ g: MiniApp) {
        recordPlayed(g)
        app.launchMiniApp(g)
    }

    private var rankEntry: some View {
        Button { showRankBoard = true } label: {
            HStack(spacing: 11) {
                Text("🏆")
                    .font(pfStyled(size: 19))
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.dyn(0xFFF3D6, 0x2A2417)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(Tr("游戏排行榜")).font(pf(15, .medium)).foregroundColor(ink)
                    Text(Tr("看看好友在每款游戏里的最高分")).font(pf(12)).foregroundColor(subInk)
                }
                Spacer(minLength: 6)
                Chevron(size: 8, line: 1.6, color: subInk)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(cardBg))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private var groups: [(String, [MiniApp])] {
        var order: [String] = []
        var map: [String: [MiniApp]] = [:]
        for g in list {
            let k = g.groupText
            if map[k] == nil { map[k] = []; order.append(k) }
            map[k]?.append(g)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    private func gameCircle(_ g: MiniApp, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Color(hex: 0x2B2F3A), Color(hex: 0x171B22)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(g.iconText).font(pfStyled(size: size * 0.42))
            if let cv = g.cover, !cv.isEmpty {
                RemoteImage(path: cv, mode: .fill, maxSide: max(96, size * 3))
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            }
        }
        .frame(width: size, height: size)
    }

    private func posterCard(_ g: MiniApp) -> some View {
        Button { openDetail(g) } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(colors: [Color(hex: 0x2B2F3A), Color(hex: 0x171B22)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Text(g.iconText).font(pfStyled(size: 46))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if let cv = g.cover, !cv.isEmpty {
                        RemoteImage(path: cv, mode: .fill, maxSide: 640)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                    }
                    LinearGradient(colors: [.clear, .black.opacity(0.62)],
                                   startPoint: .center, endPoint: .bottom)
                }
                .frame(height: 112)
                .clipped()
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 5) {
                    Text(g.name).font(pf(15, .medium)).foregroundColor(ink).lineLimit(1)
                    Text((g.desc?.isEmpty == false) ? (g.desc ?? "") : Tr("小游戏"))
                        .font(pf(11.5)).foregroundColor(subInk).lineLimit(1)
                    HStack(spacing: 4) {
                        Text(g.actionText).font(pf(11.5)).foregroundColor(Color(hex: 0x576B95))
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(subInk)
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 184)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(cardBg))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(C.hairline, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func card(_ g: MiniApp) -> some View {
        HStack(spacing: 12) {

            Button { openDetail(g) } label: {
                HStack(spacing: 12) {
                    ZStack {

                        Circle()
                            .fill(LinearGradient(colors: [Color(hex: 0x2B2F3A), Color(hex: 0x171B22)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                        Text(g.iconText).font(pfStyled(size: 30))
                        if let cv = g.cover, !cv.isEmpty {
                            RemoteImage(path: cv, maxSide: 240)
                                .frame(width: 72, height: 72)
                                .clipShape(Circle())
                        }
                    }
                    .frame(width: 72, height: 72)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(g.name).font(pf(16, .medium)).foregroundColor(ink).lineLimit(1)
                        Text(g.desc ?? "").font(pf(12.5)).foregroundColor(subInk)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 6)

            if app.me?.ops == true {
                Button {
                    iconPickFor = g.id
                    showIconPick = true
                } label: {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 16))
                        .foregroundColor(C.green)
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Button { shareApp = g } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16))
                    .foregroundColor(subInk)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { play(g) } label: {
                Text(g.actionText)
                    .font(pf(13.5, .medium))

                    .foregroundColor(Color.dyn(0x111111, 0x111111))
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(Capsule().fill(Color.white))
                    .overlay(Capsule().stroke(Color.black.opacity(0.10), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(cardBg))
    }
}

struct GameWebPage: View {
    let game: MiniApp
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var localIndex: URL?
    @State private var localDir: URL?
    @State private var loading = true
    @State private var errorText = ""

    @StateObject private var box = WebBox()

    @State private var share = false

    @State private var capsuleMenu = false

    @State private var about = false
    @State private var closing = false

    private var isRoomGame: Bool { false }
    @State private var tables: [GameTable] = []
    @State private var myRoom: String = ""
    @State private var mySeat: Int = 0
    @State private var roomNames: [String?] = []
    @State private var roomStarted = false
    @State private var lobbyMsg = ""
    @State private var moveSeq = 0
    @State private var pollTask: Task<Void, Never>? = nil

    var body: some View {

        stage
            .background(Color(hex: 0x0B0E17).ignoresSafeArea())
            .statusBarHidden(false)

            .onAppear {
                Self.setGameAudio(true)
                StatusBarStyle.shared.set(light: true)
            }
            .onDisappear {
                Self.setGameAudio(false)
                StatusBarStyle.shared.set(light: false)
                box.shutdown()
            }
            .task {
                if isRoomGame { await loadTables() }
                await prepare()
            }
            .confirmationDialog(game.name, isPresented: $capsuleMenu, titleVisibility: .visible) {

                Button(Tr("转发给朋友")) { share = true }
                Button(Tr("好友排名")) { box.web?.evaluateJavaScript("window.chrisRank && chrisRank.show()") }
                if isRoomGame && !myRoom.isEmpty {
                    Button(Tr("复制桌号邀请")) {
                        UIPasteboard.general.string = Tr("四国军棋 桌号 ") + myRoom
                        lobbyMsg = Tr("桌号已复制")
                    }
                }
                Button(Tr("关于")) { about = true }
                Button(Tr("重新进入")) { Task { await prepare(force: true) } }
                Button(Tr("关闭"), role: .destructive) { closeGame() }
                Button(Tr("取消"), role: .cancel) { }
            }
            .sheet(isPresented: $share) {
                ForwardPickerView(items: [ForwardItem(kind: "miniapp", content: miniAppSharePayload(game))]) {
                    share = false
                }
                .environmentObject(app)
            }
            .alert(Tr("关于"), isPresented: $about) {
                Button(Tr("知道了"), role: .cancel) { }
            } message: {
                Text(aboutText)
            }
            .onDisappear {
                pollTask?.cancel()
                if !myRoom.isEmpty { Task { await API.shared.gameTableLeave(myRoom) } }
            }
    }

    private var aboutText: String {
        var s = game.name
        if let d = game.desc, !d.isEmpty { s += "\n" + d }
        s += "\n\n" + Tr("星言小游戏")
        if let g = game.group, !g.isEmpty { s += "\n" + g }
        return s
    }

    private var stage: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if isRoomGame && !roomStarted {
                    lobby
                } else if let localIndex {
                    GameWebView(index: localIndex, dir: localDir,
                                rankJs: chrisRankJs(game: game.id, token: API.shared.token, base: API.shared.base),
                                box: box,
                                onScore: { g, s in Task { await API.shared.gameScore(g, s) } },
                                onRank: { g, done in Task { done(await API.shared.gameRankJSONWithAvatars(g)) } },
                                roomJs: roomJs,
                                onMove: { mv in Task { await API.shared.gameTableMove(myRoom, mv) } })
                } else if loading {
                    VStack(spacing: 10) {
                        ProgressView().tint(.white)
                        Text(Tr("正在准备游戏…")).font(pf(13.5)).foregroundColor(.white.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 12) {
                        Text(errorText.isEmpty ? Tr("游戏打不开") : errorText)
                            .font(pf(14)).foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center).padding(.horizontal, 30)
                        Button { Task { await prepare(force: true) } } label: {
                            Text(Tr("重试"))
                                .font(pf(15, .medium)).foregroundColor(.white)
                                .padding(.horizontal, 22).frame(height: 40)
                                .background(Capsule().fill(C.green))
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            .ignoresSafeArea()

            miniCapsule

                .padding(.top, max(8, L.safeTop + 6))
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

                        .padding(.bottom, max(18, L.safeBottom + 14))
                    }
                }
            }
        }
    }

    private var miniCapsule: some View {
        GameWindowCapsule(
            onMenu: { capsuleMenu = true },
            onClose: { closeGame() }
        )
    }

    private func closeGame() {
        guard !closing else { return }
        closing = true
        Self.setGameAudio(false)
        box.shutdown()
        dismiss()
    }

    private var lobby: some View {
        ZStack {
            Color(hex: 0x0B0E17).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 12) {
                    Text(Tr("四国军棋 · 棋牌大厅")).font(pf(17, .semibold)).foregroundColor(.white)
                    Text(myRoom.isEmpty ? Tr("点一张桌子坐下，缺的位置由电脑顶上")
                                        : (Tr("你在 ") + myRoom + Tr(" 号桌（") + "\(mySeat + 1)" + Tr(" 号位）")))
                        .font(pf(12.5)).foregroundColor(.white.opacity(0.6))

                    if !myRoom.isEmpty {
                        roomCard
                    } else {
                        Button { Task { await createTable() } } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                Text(Tr("自己开一桌"))
                            }
                            .font(pf(15, .medium)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .background(Capsule().fill(C.green))
                        }
                        .buttonStyle(.plain)

                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                            GridItem(.flexible(), spacing: 10)], spacing: 10) {
                            ForEach(tables) { t in tableCard(t) }
                        }
                        if tables.isEmpty {
                            Text(Tr("还没有人开桌，你可以先开一桌等好友"))
                                .font(pf(13)).foregroundColor(.white.opacity(0.5))
                                .padding(.top, 20)
                        }
                    }
                    if !lobbyMsg.isEmpty {
                        Text(lobbyMsg).font(pf(12.5)).foregroundColor(.white.opacity(0.7))
                    }
                    Spacer().frame(height: 20)
                }
                .padding(16)
            }
        }
    }

    private func tableCard(_ t: GameTable) -> some View {
        Button { Task { await sit(t.code) } } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(Tr("桌 ") + t.code).font(pf(14, .semibold)).foregroundColor(.white)
                    Spacer(minLength: 0)
                    Text("\(t.seated ?? 0)/4").font(pf(11.5)).foregroundColor(.white.opacity(0.55))
                }
                let names = t.seatNames
                ForEach(0..<4, id: \.self) { i in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(i < names.count && names[i] != nil ? C.green : Color.white.opacity(0.12))
                            .frame(width: 7, height: 7)
                        Text(i < names.count ? (names[i] ?? Tr("空位")) : Tr("空位"))
                            .font(pf(12))
                            .foregroundColor(i < names.count && names[i] != nil ? .white : .white.opacity(0.45))
                            .lineLimit(1)
                    }
                }
                Text((t.started == true) ? Tr("已开局") : Tr("点一下坐下"))
                    .font(pf(11.5)).foregroundColor(C.green)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: 0x1B1B1D)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var roomCard: some View {
        VStack(spacing: 10) {
            HStack {
                Text(Tr("桌号 ") + myRoom).font(pf(19, .semibold)).foregroundColor(.white)
                Spacer(minLength: 0)

                Button {
                    UIPasteboard.general.string = Tr("来打四国军棋，桌号 ") + myRoom + Tr("（进「游戏 → 四国军棋」大厅点这张桌坐下）")
                    lobbyMsg = Tr("桌号已复制，去聊天里发给好友就行")
                } label: {
                    Text(Tr("复制桌号邀请")).font(pf(13)).foregroundColor(C.green)
                }
                .buttonStyle(.plain)
            }
            ForEach(0..<4, id: \.self) { i in
                HStack(spacing: 8) {
                    Text("\(i + 1)").font(pf(12)).foregroundColor(.white.opacity(0.5)).frame(width: 14)
                    Text(i < roomNames.count ? (roomNames[i] ?? Tr("空位（电脑）")) : Tr("空位（电脑）"))
                        .font(pf(14))
                        .foregroundColor(i == mySeat ? C.green : .white)
                    Spacer(minLength: 0)
                    if i == mySeat { Text(Tr("我")).font(pf(11.5)).foregroundColor(C.green) }
                }
                .padding(.horizontal, 12).frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(i == mySeat ? 0.10 : 0.05)))
            }
            Button { startRoom() } label: {
                Text(roomStarted ? Tr("开局啦") : Tr("开始（缺的人电脑顶上）"))
                    .font(pf(15, .medium)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(Capsule().fill(C.green))
            }
            .buttonStyle(.plain)
            Button { Task { await API.shared.gameTableLeave(myRoom); myRoom = ""; roomStarted = false; await loadTables() } } label: {
                Text(Tr("离开这桌")).font(pf(13)).foregroundColor(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0x1B1B1D)))
    }

    private func loadTables() async {
        tables = await API.shared.gameTables(game.id)
    }

    private func createTable() async {
        guard let r = await API.shared.gameTableCreate(game.id) else { lobbyMsg = Tr("开桌失败，再试一次"); return }
        myRoom = r.code
        mySeat = r.seat
        await refreshRoom()
    }

    private func sit(_ code: String) async {
        guard let r = await API.shared.gameTableSit(code) else { lobbyMsg = Tr("坐不进去，换一桌试试"); return }
        myRoom = code
        mySeat = r.seat
        roomNames = r.players
        if r.started { startRoom() }
    }

    private func refreshRoom() async {
        let list = await API.shared.gameTables(game.id)
        if let t = list.first(where: { $0.code == myRoom }) {
            roomNames = t.seatNames
            if t.started == true { roomStarted = true }
        }
    }

    private func startRoom() {
        roomStarted = true
        moveSeq = 0
        Task {
            await API.shared.gameTableStart(myRoom)
            await prepare(force: true)
        }

        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if Task.isCancelled { return }
                let r = await API.shared.gameTableMoves(myRoom, since: moveSeq)
                moveSeq = r.n
                if !r.list.isEmpty,
                   let data = try? JSONSerialization.data(withJSONObject: r.list),
                   let s = String(data: data, encoding: .utf8) {
                    DispatchQueue.main.async {
                        box.web?.evaluateJavaScript("window.chrisOnMoves && window.chrisOnMoves(\(s));")
                    }
                }
            }
        }
    }

    private var roomJs: String {
        let names = roomNames.map { $0 ?? "" }
        var arr = "[]"
        if let d = try? JSONSerialization.data(withJSONObject: names.map { ["name": $0.isEmpty ? "电脑" : $0] }),
           let s = String(data: d, encoding: .utf8) { arr = s }
        return """
        window.chrisRoom = { code: "\(myRoom)", seat: \(mySeat), players: \(arr) };
        window.chrisMove = function (mv) {
          try { window.webkit.messageHandlers.chrisRoom.postMessage({ action: 'move', move: mv }); } catch (e) {}
        };
        """
    }

    private var gameFiles: [String] {
        ["index.html", "js/adapter.js", "js/engine.js", "js/sound.js", "js/main.js"]
    }

    static func setGameAudio(_ on: Bool) {
        let s = AVAudioSession.sharedInstance()
        if on {
            try? s.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try? s.setActive(true)
        } else {
            try? s.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        }
    }

    private func prepare(force: Bool = false) async {
        loading = true
        errorText = ""
        let path = game.url
        guard !path.isEmpty, let remoteIndex = API.shared.assetURL(path) else {
            loading = false
            errorText = Tr("这款游戏还没配地址（后台「游戏」里填 url）")
            return
        }
        let remoteDir = remoteIndex.deletingLastPathComponent()
        let fm = FileManager.default
        guard let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            loading = false
            return
        }

        let rootKey = "games/\(game.id)-\(GamesPageView.stableKey(game.url))"
        let root = caches.appendingPathComponent(rootKey, isDirectory: true)
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)

            let stampFile = root.appendingPathComponent(".list")
            let oldStamp = (try? String(contentsOf: stampFile, encoding: .utf8)) ?? ""
            let cachedIndex = root.appendingPathComponent("index.html")
            if !force, !oldStamp.isEmpty,
               let size = try? cachedIndex.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               size > 0 {
                localDir = root
                localIndex = cachedIndex
                loading = false
                let previousStamp = oldStamp
                Task {
                    guard let list = await miniAppFileList(baseDir: remoteDir) else { return }
                    let stamp = GamesPageView.stableKey(list.joined(separator: "|"))
                    if stamp != previousStamp {
                        for f in list {
                            let dst = root.appendingPathComponent(f)
                            guard let data = try? await API.shared.assetData(
                                remoteDir.appendingPathComponent(f)
                            ) else { continue }
                            try? FileManager.default.createDirectory(
                                at: dst.deletingLastPathComponent(),
                                withIntermediateDirectories: true
                            )
                            try? data.write(to: dst, options: .atomic)
                        }
                        try? stamp.write(to: stampFile, atomically: true, encoding: .utf8)
                    }
                }
                return
            }

            let list = await miniAppFileList(baseDir: remoteDir)
            let stamp = GamesPageView.stableKey(list.joined(separator: "|"))
            let needAll = force || oldStamp != stamp
            for f in list {
                let dst = root.appendingPathComponent(f)
                if !needAll, let sz = try? dst.resourceValues(forKeys: [.fileSizeKey]).fileSize, sz > 0 { continue }
                try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
                let data = try await API.shared.assetData(remoteDir.appendingPathComponent(f))
                try data.write(to: dst, options: .atomic)
            }
            try? stamp.write(to: stampFile, atomically: true, encoding: .utf8)
            localDir = root
            localIndex = root.appendingPathComponent("index.html")
        } catch {
            errorText = Tr("游戏下载失败：") + error.localizedDescription
        }
        loading = false
    }
}

struct GamesPageAdminSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let games: [MiniApp]
    @State private var picked: [String] = []
    @State private var wallpaper = ""
    @State private var showPick = false
    @State private var busy = false

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("游戏页设置"), back: { dismiss() })
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(Tr("轮播（点一下加入/移出，顺序就是轮播顺序）"))
                        .font(pf(14, .semibold)).foregroundColor(C.label)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                        ForEach(games) { g in
                            Button {
                                if let i = picked.firstIndex(of: g.id) { picked.remove(at: i) } else { picked.append(g.id) }
                            } label: {
                                Text(g.name).font(pf(12.5))
                                    .foregroundColor(picked.contains(g.id) ? .white : C.label)
                                    .lineLimit(1)
                                    .padding(.horizontal, 8).frame(height: 30)
                                    .frame(maxWidth: .infinity)
                                    .background(Capsule().fill(picked.contains(g.id) ? C.green : C.cardBg))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text(Tr("默认壁纸（没封面的轮播用这张）"))
                        .font(pf(14, .semibold)).foregroundColor(C.label).padding(.top, 8)
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(C.cardBg)
                            .frame(width: 96, height: 56)
                            .overlay {
                                if !wallpaper.isEmpty {
                                    RemoteImage(path: wallpaper, mode: .fill, maxSide: 480)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                            }
                        Button(Tr("上传壁纸")) { showPick = true }.font(pf(14)).foregroundColor(C.green)
                        Button(Tr("清除")) { wallpaper = "" }.font(pf(14)).foregroundColor(DDColor.red)
                        Spacer(minLength: 0)
                    }
                    Button {
                        busy = true
                        Task {
                            _ = await API.shared.opsSetUIKey("gamesBannerIds", picked.joined(separator: ","))
                            _ = await API.shared.opsSetUIKey("gamesWallpaper", wallpaper)
                            busy = false
                            app.show(Tr("已保存"))
                            dismiss()
                        }
                    } label: {
                        Text(busy ? Tr("保存中…") : Tr("保存")).font(pf(16, .semibold)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: 46)
                            .background(RoundedRectangle(cornerRadius: 23, style: .continuous)
                                .fill(C.green.opacity(busy ? 0.5 : 1)))
                    }
                    .buttonStyle(.plain).padding(.top, 10)
                }
                .padding(16)
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea())
        .sheet(isPresented: $showPick) {
            PhotoPicker { img in
                busy = true
                Task {
                    if let url = try? await API.shared.upload(image: img) { wallpaper = url }
                    busy = false
                }
            }
        }
        .onAppear {
            picked = UIConfig.text("gamesBannerIds", "").split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            wallpaper = UIConfig.text("gamesWallpaper", "").trimmingCharacters(in: .whitespaces)
        }
    }
}

private let gamePerformanceJS = """
(() => {
  window.addEventListener('DOMContentLoaded', () => {
    const style = document.createElement('style');
    style.textContent = 'html,body{overscroll-behavior:none;touch-action:manipulation;-webkit-tap-highlight-color:transparent;}canvas{touch-action:none;}';
    document.head && document.head.appendChild(style);
  });
})();
"""

struct GameWebView: UIViewRepresentable {
    let index: URL

    let dir: URL?

    var rankJs: String = ""
    var box: WebBox? = nil

    var onScore: ((String, Int) -> Void)? = nil

    var onRank: ((String, @escaping (String) -> Void) -> Void)? = nil

    var roomJs: String = ""

    var onMove: (([String: Any]) -> Void)? = nil

    func makeCoordinator() -> RankBridge {
        let b = RankBridge()
        return b
    }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        context.coordinator.userContentController = cfg.userContentController
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []

        cfg.userContentController.addUserScript(
            WKUserScript(source: WebSafeArea.js, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        cfg.userContentController.addUserScript(
            WKUserScript(source: gamePerformanceJS,
                         injectionTime: .atDocumentStart,
                         forMainFrameOnly: true))
        if !rankJs.isEmpty {
            cfg.userContentController.addUserScript(
                WKUserScript(source: rankJs, injectionTime: .atDocumentStart, forMainFrameOnly: true))

            let b = context.coordinator
            b.onScore = onScore
            b.onRank = onRank
            cfg.userContentController.add(b, name: "chrisRank")
        }

        if !roomJs.isEmpty {
            cfg.userContentController.addUserScript(
                WKUserScript(source: roomJs, injectionTime: .atDocumentStart, forMainFrameOnly: true))
            context.coordinator.room.onMove = onMove
            cfg.userContentController.add(context.coordinator.room, name: "chrisRoom")
        }
        let v = WKWebView(frame: .zero, configuration: cfg)
        let gameBackground = UIColor(red: 0.043, green: 0.055, blue: 0.09, alpha: 1)
        v.isOpaque = true
        v.backgroundColor = gameBackground
        v.underPageBackgroundColor = gameBackground
        v.allowsLinkPreview = false
        v.scrollView.bounces = false
        v.scrollView.isScrollEnabled = false
        v.scrollView.showsVerticalScrollIndicator = false
        v.scrollView.showsHorizontalScrollIndicator = false
        v.scrollView.backgroundColor = gameBackground
        v.scrollView.contentInsetAdjustmentBehavior = .never
        v.loadFileURL(index, allowingReadAccessTo: dir ?? index.deletingLastPathComponent())
        box?.web = v
        context.coordinator.web = v
        return v
    }

    func updateUIView(_ v: WKWebView, context: Context) { }

    static func dismantleUIView(_ v: WKWebView, coordinator: RankBridge) {
        v.stopLoading()
        v.navigationDelegate = nil
        v.uiDelegate = nil
        coordinator.shutdown()
        v.removeFromSuperview()
    }
}
