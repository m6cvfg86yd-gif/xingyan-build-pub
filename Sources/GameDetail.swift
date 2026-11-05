import SwiftUI

struct GameDetailView: View {
    let game: MiniApp

    var onPlay: (MiniApp) -> Void

    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var rank: GameRank?
    @State private var loadingRank = true
    @State private var shareApp: MiniApp?

    private let pageBg = Color.dyn(0xEDEDED, 0x111114)
    private let cardBg = Color.dyn(0xFFFFFF, 0x1B1B1D)
    private let ink = C.label
    private let subInk = C.subLabel

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: game.name, back: { dismiss() })

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    cover
                    titleRow
                    rankCard
                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            bottomBar
        }
        .background(pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .hidesTabBar()
        .swipeBack { dismiss() }
        .sheet(item: $shareApp) { g in
            ForwardPickerView(items: [ForwardItem(kind: "miniapp", content: miniAppSharePayload(g))]) { shareApp = nil }
                .environmentObject(app)
        }
        .task { await loadRank() }
    }

    private var cover: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x2B2F3A), Color(hex: 0x171B22)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(game.iconText).font(pfStyled(size: 76))
            if let cv = game.cover, !cv.isEmpty {
                RemoteImage(path: cv, mode: .fill, maxSide: 1200)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
        }
        .frame(height: 196)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var titleRow: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(game.name).font(pf(19, .semibold)).foregroundColor(ink).lineLimit(1)
                Text(Tr("小游戏"))
                    .font(pf(11))
                    .foregroundColor(C.green)
                    .padding(.horizontal, 7)
                    .frame(height: 19)
                    .background(Capsule().fill(C.green.opacity(0.12)))
                Spacer(minLength: 0)
            }
            if let d = game.desc, !d.isEmpty {
                Text(d).font(pf(13.5)).foregroundColor(subInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let line = myScoreLine {
                Text(line)
                    .font(pf(12.5))
                    .foregroundColor(subInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(cardBg))
    }

    private var rankCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(Tr("好友排行")).font(pf(15, .medium)).foregroundColor(ink)
                Spacer(minLength: 0)
                if (rank?.total ?? 0) > 3 {
                    Text(playersText(rank?.total ?? 0))
                        .font(pf(11.5)).foregroundColor(subInk)
                }
            }
            .padding(.bottom, 6)

            if loadingRank {
                HStack(spacing: 8) {
                    ProgressView().tint(subInk)
                    Text(Tr("正在加载…")).font(pf(13)).foregroundColor(subInk)
                }
                .padding(.vertical, 14)
            } else if topRows.isEmpty {
                Text(Tr("还没有好友的成绩，你先玩一局上榜"))
                    .font(pf(13)).foregroundColor(subInk)
                    .padding(.vertical, 14)
            } else {
                ForEach(Array(topRows.enumerated()), id: \.offset) { i, r in
                    HStack(spacing: 12) {

                        Text(r.rank.map { "\($0)" } ?? "—")
                            .font(pf(13, .semibold))
                            .foregroundColor(i == 0 ? Color(hex: 0xE8A33D) : subInk)
                            .frame(width: 18)
                        Avatar(path: r.avatar ?? "", size: 34, radius: 9)
                        Text(r.isMe ? Tr("我") : (r.name ?? Tr("好友")))
                            .font(pf(14.5))
                            .foregroundColor(ink)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text("\(r.scoreText)")
                            .font(pfMoney(14.5))
                            .foregroundColor(ink)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 8)
                    if i < topRows.count - 1 { HairLine(inset: 64) }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(cardBg))
    }

    private var topRows: [GameRankRow] {
        Array((rank?.rows ?? []).filter { $0.scoreText > 0 }.prefix(5))
    }

    private var myScoreLine: String? {
        guard let my = rank?.myScore, my > 0 else { return nil }
        let r = rank?.myRank ?? 0
        if Lang.isEnglish { return "My best \(my)" + (r > 0 ? " · #\(r)" : "") }
        return "我的最高分 \(my)" + (r > 0 ? " · 第 \(r) 名" : "")
    }

    private func playersText(_ n: Int) -> String {
        Lang.isEnglish ? "\(n) players" : "共 \(n) 人在玩"
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button { shareApp = game } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(ink)
                    .frame(width: 48, height: 46)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(cardBg))
            }
            .buttonStyle(.plain)

            Button { onPlay(game); dismiss() } label: {
                Text(Tr("开始游戏"))
                    .font(pf(16, .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(colors: [C.green, C.green.opacity(0.78)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, max(10, L.safeBottom + 6))
        .background(pageBg)
    }

    private func loadRank() async {
        loadingRank = true
        rank = await API.shared.gameRank(game.id)
        loadingRank = false
    }
}

struct GameRankBoardView: View {
    let games: [MiniApp]

    @Environment(\.dismiss) private var dismiss
    @State private var ranks: [String: GameRank] = [:]
    @State private var loading = true

    private let pageBg = Color.dyn(0xEDEDED, 0x111114)
    private let cardBg = Color.dyn(0xFFFFFF, 0x1B1B1D)
    private let ink = C.label
    private let subInk = C.subLabel

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("游戏排行榜"), back: { dismiss() })

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    if loading {
                        ProgressView().padding(.vertical, 50)
                    } else if games.isEmpty {
                        Text(Tr("还没有游戏")).font(pf(14)).foregroundColor(subInk)
                            .padding(.vertical, 50)
                    } else {
                        rankingHero

                        if rankedScored.count > 3 {
                            HStack {
                                Text(Tr("全部排行")).font(pf(14.5, .medium)).foregroundColor(ink)
                                Spacer(minLength: 0)
                                Text(Lang.isEnglish ? "\(rankedScored.count)" : "\(rankedScored.count) 款")
                                    .font(pf(11)).foregroundColor(subInk)
                            }
                            .padding(.horizontal, 2)

                            VStack(spacing: 0) {
                                ForEach(Array(rankedScored.dropFirst(3).enumerated()), id: \.element.app.id) { i, item in
                                    if i > 0 { HairLine(inset: 60) }
                                    rankedRow(item.app, rank: item.rank)
                                }
                            }
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(cardBg))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(C.hairline, lineWidth: 0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }

                        if !waitingScored.isEmpty {
                            HStack {
                                Text(Tr("待挑战")).font(pf(14.5, .medium)).foregroundColor(ink)
                                Spacer(minLength: 0)
                                Text(Tr("还没有好友成绩")).font(pf(11)).foregroundColor(subInk)
                            }
                            .padding(.horizontal, 2)

                            VStack(spacing: 0) {
                                ForEach(Array(waitingScored.enumerated()), id: \.element.app.id) { i, item in
                                    if i > 0 { HairLine(inset: 60) }
                                    waitingRow(item.app)
                                }
                            }
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(cardBg))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(C.hairline, lineWidth: 0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                    Color.clear.frame(height: 20)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }
        }
        .background(pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .hidesTabBar()
        .swipeBack { dismiss() }
        .task { await loadAll() }
    }

    private var rankedGames: [(app: MiniApp, rank: Int)] {
        func metric(_ g: MiniApp) -> (Int, Int) {
            let r = ranks[g.id]
            let players = r?.total ?? 0
            let best = (r?.rows ?? []).map { $0.scoreText }.max() ?? 0
            return (players, best)
        }
        let sorted = games.sorted { a, b in
            let ma = metric(a), mb = metric(b)
            if ma.0 != mb.0 { return ma.0 > mb.0 }
            if ma.1 != mb.1 { return ma.1 > mb.1 }
            return a.name < b.name
        }

        var out: [(app: MiniApp, rank: Int)] = []
        var last: (Int, Int)? = nil
        var lastRank = 0
        for (i, g) in sorted.enumerated() {
            let m = metric(g)
            if let l = last, l == m {
                out.append((g, lastRank))
            } else {
                lastRank = i + 1
                out.append((g, lastRank))
                last = m
            }
        }
        return out
    }

    private var rankedScored: [(app: MiniApp, rank: Int)] {
        rankedGames.filter { scoreOf($0.app) > 0 }
    }

    private var waitingScored: [(app: MiniApp, rank: Int)] {
        rankedGames.filter { scoreOf($0.app) <= 0 }
    }

    private func scoreOf(_ g: MiniApp) -> Int {
        (ranks[g.id]?.rows ?? []).map { $0.scoreText }.max() ?? 0
    }

    private func playersOf(_ g: MiniApp) -> Int {
        ranks[g.id]?.total ?? 0
    }

    private var podiumItems: [(app: MiniApp, rank: Int, place: Int)] {
        let top = Array(rankedScored.prefix(3))
        var out: [(app: MiniApp, rank: Int, place: Int)] = []
        if top.count > 1 { out.append((top[1].app, top[1].rank, 2)) }
        if !top.isEmpty { out.append((top[0].app, top[0].rank, 1)) }
        if top.count > 2 { out.append((top[2].app, top[2].rank, 3)) }
        return out
    }

    private var rankingHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Tr("好友游戏榜")).font(pf(21, .bold)).foregroundColor(.white)
                    Text(Tr("按好友真实最高分排列")).font(pf(11.5)).foregroundColor(.white.opacity(0.75))
                }
                Spacer(minLength: 0)
                Text(Lang.isEnglish ? "\(rankedScored.count) scored"
                                    : "\(rankedScored.count) 款有成绩")
                    .font(pf(10.5))
                    .foregroundColor(.white.opacity(0.86))
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
            }

            if podiumItems.isEmpty {
                VStack(spacing: 6) {
                    Text("🏁").font(pfStyled(size: 30))
                    Text(Tr("还没有真实游戏成绩")).font(pf(14)).foregroundColor(.white)
                    Text(Tr("先玩一局，成绩会自动进入好友排行"))
                        .font(pf(11.5)).foregroundColor(.white.opacity(0.70))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 112)
            } else {
                HStack(alignment: .bottom, spacing: 9) {
                    ForEach(podiumItems, id: \.app.id) { item in
                        podiumCard(item.app, place: item.place)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x171B2C),
                                              Color(hex: 0x242B40),
                                              Color(hex: 0x30394F)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .shadow(color: .black.opacity(0.14), radius: 12, y: 5)
    }

    private func podiumCard(_ g: MiniApp, place: Int) -> some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color(hex: 0x2B2F3A), Color(hex: 0x171B22)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text(g.iconText).font(pfStyled(size: place == 1 ? 28 : 24))
                    if let cv = g.cover, !cv.isEmpty {
                        RemoteImage(path: cv, mode: .fill)
                            .frame(width: place == 1 ? 58 : 50,
                                   height: place == 1 ? 58 : 50)
                            .clipShape(Circle())
                    }
                }
                .frame(width: place == 1 ? 58 : 50,
                       height: place == 1 ? 58 : 50)

                Text("\(place)")
                    .font(pf(10, .bold))
                    .foregroundColor(Color(hex: 0x17191D))
                    .frame(width: 19, height: 19)
                    .background(Circle().fill(rankColor(place)))
                    .overlay(Circle().stroke(Color.white.opacity(0.24), lineWidth: 1))
                    .offset(x: 4, y: -4)
            }

            Text(g.name)
                .font(pf(place == 1 ? 14.5 : 12.5, .medium))
                .foregroundColor(.white)
                .lineLimit(1)

            Text("\(scoreOf(g))")
                .font(pf(place == 1 ? 18 : 15, .bold))
                .foregroundColor(rankColor(place))
                .monospacedDigit()

            Text(Lang.isEnglish ? "\(playersOf(g)) players" : "\(playersOf(g)) 人参与")
                .font(pf(10)).foregroundColor(.white.opacity(0.72))
        }
        .frame(maxWidth: .infinity)
        .frame(height: place == 1 ? 148 : 134)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(Color.white.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
            .stroke(Color.white.opacity(0.15), lineWidth: 0.5))
    }

    private func rankedRow(_ g: MiniApp, rank: Int) -> some View {
        HStack(spacing: 11) {
            Text("\(rank)")
                .font(pf(13.5, .medium))
                .foregroundColor(rank <= 3 ? rankColor(rank) : subInk)
                .frame(width: 24)
            gameRankCircle(g, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(g.name).font(pf(14.5, .medium)).foregroundColor(ink).lineLimit(1)
                Text(Lang.isEnglish ? "\(playersOf(g)) friends"
                                    : "\(playersOf(g)) 位好友参与")
                    .font(pf(10.5)).foregroundColor(subInk)
            }
            Spacer(minLength: 0)
            Text("\(scoreOf(g))")
                .font(pf(16, .medium))
                .foregroundColor(Color(hex: 0x576B95))
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .frame(height: 64)
    }

    private func waitingRow(_ g: MiniApp) -> some View {
        HStack(spacing: 11) {
            gameRankCircle(g, size: 36)
            Text(g.name).font(pf(13.5)).foregroundColor(ink).lineLimit(1)
            Spacer(minLength: 0)
            Text(Tr("暂无成绩")).font(pf(11.5)).foregroundColor(subInk)
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
    }

    private func gameRankCircle(_ g: MiniApp, size: CGFloat) -> some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(hex: 0x2B2F3A), Color(hex: 0x171B22)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(g.iconText).font(pfStyled(size: size * 0.42))
            if let cv = g.cover, !cv.isEmpty {
                RemoteImage(path: cv, mode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            }
        }
        .frame(width: size, height: size)
    }

    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return Color(hex: 0xE8A33D)
        case 2: return Color(hex: 0xA7A7AD)
        case 3: return Color(hex: 0xC98A5B)
        default: return C.subLabel
        }
    }

    private func boardRow(_ g: MiniApp, rank: Int) -> some View {
        let r = ranks[g.id]
        let players = r?.total ?? 0
        let best = (r?.rows ?? []).map { $0.scoreText }.max() ?? 0
        let medal = rankColor(rank)
        return HStack(spacing: 12) {
            Text("\(rank)")
                .font(pf(15, .semibold))
                .foregroundColor(rank <= 3 ? medal : C.subLabel)
                .frame(width: 22)
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color(hex: 0x2B2F3A), Color(hex: 0x171B22)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Text(g.iconText).font(pfStyled(size: 22))
                if let cv = g.cover, !cv.isEmpty {
                    RemoteImage(path: cv)
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                }
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(g.name).font(pf(15.5, .medium)).foregroundColor(ink).lineLimit(1)
                Text(players > 0 ? (Lang.isEnglish ? "\(players) players" : "\(players) 人在玩")
                                 : Tr("还没有人玩过"))
                    .font(pf(12))
                    .foregroundColor(subInk)
            }
            Spacer(minLength: 8)
            if best > 0 {
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(best)").font(pfMoney(15)).foregroundColor(ink).monospacedDigit()
                    Text(Tr("最高分")).font(pf(11.5)).foregroundColor(subInk)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(cardBg))
    }

    private func boardCard(_ g: MiniApp) -> some View {
        let r = ranks[g.id]
        let rows = Array((r?.rows ?? []).filter { $0.scoreText > 0 }.prefix(3))
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(LinearGradient(colors: [Color(hex: 0x2B2F3A), Color(hex: 0x171B22)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text(g.iconText).font(pfStyled(size: 22))
                    if let cv = g.cover, !cv.isEmpty {
                        RemoteImage(path: cv).frame(width: 42, height: 42)
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                }
                .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(g.name).font(pf(15, .medium)).foregroundColor(ink).lineLimit(1)
                    Text(myScoreText(r))
                        .font(pf(12)).foregroundColor(subInk)
                }
                Spacer(minLength: 6)
            }
            .padding(.bottom, rows.isEmpty ? 0 : 6)

            if rows.isEmpty {
                Text(Tr("还没有好友的成绩"))
                    .font(pf(12.5)).foregroundColor(subInk)
                    .padding(.top, 6)
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    HStack(spacing: 10) {

                        Text(row.rank.map { "\($0)" } ?? "—")
                            .font(pf(12.5, .semibold))
                            .foregroundColor(i == 0 ? Color(hex: 0xE8A33D) : subInk)
                            .frame(width: 16)
                        Avatar(path: row.avatar ?? "", size: 28, radius: 8)
                        Text(row.isMe ? Tr("我") : (row.name ?? Tr("好友")))
                            .font(pf(14)).foregroundColor(ink).lineLimit(1)
                        Spacer(minLength: 6)
                        Text("\(row.scoreText)").font(pfMoney(14)).foregroundColor(ink)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(cardBg))
    }

    private func loadAll() async {
        loading = true
        var out: [String: GameRank] = [:]
        await withTaskGroup(of: Optional<GameRank>.self) { grp in
            for g in games {
                grp.addTask { await API.shared.gameRank(g.id) }
            }
            for await r in grp {

                if let r, let id = r.game, !id.isEmpty { out[id] = r }
            }
        }
        ranks = out
        loading = false
    }

    private func myScoreText(_ r: GameRank?) -> String {
        let mine = r?.myScore ?? 0
        guard mine > 0 else { return Tr("我还没玩过") }
        return Lang.isEnglish ? "My best \(mine)" : "我的最高分 \(mine)"
    }
}
