import SwiftUI
import UIKit

struct GrowthIcons: Codable, Hashable {
    var crowns: Int = 0
    var suns: Int = 0
    var moons: Int = 0
    var stars: Int = 0

    var count: Int { crowns + suns + moons + stars }
}

struct GrowthCfg: Codable, Hashable {
    var enabled: Bool?
    var fullSeconds: Int?
    var halfSeconds: Int?
    var maxPerDay: Double?
    var boost: Double?
    var showInContacts: Bool?
    var showInChats: Bool?
    var showInProfile: Bool?
    var avatarFrame: Bool?
    var tip: String?
}

struct GrowthMe: Codable, Hashable {
    var enabled: Bool?
    var total: Double?
    var level: Int?

    var levelShown: Int?
    var icons: GrowthIcons?
    var levelStartDays: Double?
    var nextDays: Double?
    var needDays: Double?
    var todaySeconds: Int?
    var todayEarned: Double?
    var cfg: GrowthCfg?
}

struct GrowthRankRow: Codable, Identifiable, Hashable {
    var id: String
    var name: String?
    var avatar: String?
    var total: Double?
    var level: Int?
    var icons: GrowthIcons?
}

enum QQLevel {

    static func days(for level: Int) -> Int { level * level + 4 * level }

    static func level(forDays d: Double) -> Int {
        max(0, Int((max(0, d) + 4).squareRoot() - 2))
    }
    static func icons(_ level: Int) -> GrowthIcons {
        var n = max(0, level)
        let crowns = n / 64; n %= 64
        let suns = n / 16; n %= 16
        let moons = n / 4; n %= 4
        return GrowthIcons(crowns: crowns, suns: suns, moons: moons, stars: n)
    }
}

enum GrowthFlags {
    static var showInContacts = true
    static var showInProfile = true
    static var showInChats = true

    static var avatarFrame = true
}

@MainActor
final class GrowthStore: ObservableObject {
    static let shared = GrowthStore()

    @Published var me: GrowthMe?
    @Published var rank: [GrowthRankRow] = []
    @Published var rankMine: GrowthRankRow?

    private var timer: Timer?
    private var lastTick = Date()
    private var running = false

    var level: Int { me?.level ?? 0 }

    var shownLevel: Int { me?.levelShown ?? max(1, level) }
    var icons: GrowthIcons { me?.icons ?? QQLevel.icons(shownLevel) }
    var cfg: GrowthCfg { me?.cfg ?? GrowthCfg() }
    var totalDays: Double { me?.total ?? 0 }

    func start() {
        guard !running else { return }
        running = true
        lastTick = Date()
        Task { await refresh() }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in await GrowthStore.shared.tick() }
        }
    }

    func stop() {
        guard running else { return }
        running = false
        timer?.invalidate()
        timer = nil
        Task { await tick() }
    }

    func tick() async {
        let now = Date()
        let secs = Int(now.timeIntervalSince(lastTick))
        lastTick = now
        guard secs > 0 else { return }
        if let g = try? await API.shared.growthPing(seconds: min(3600, secs)) { apply(g) }
    }

    func refresh() async {
        if let g = try? await API.shared.growthMe() { apply(g) }
    }

    private func apply(_ g: GrowthMe) {
        me = g
        let c = g.cfg
        GrowthFlags.showInContacts = c?.showInContacts ?? true
        GrowthFlags.showInProfile = c?.showInProfile ?? true
        GrowthFlags.showInChats = c?.showInChats ?? true
        GrowthFlags.avatarFrame = c?.avatarFrame ?? true
    }

    func loadRank() async {
        if let r = try? await API.shared.growthRank() {
            rank = r.rows
            rankMine = r.me
        }
    }
}

enum QQGlyphKind { case crown, sun, moon, star }

struct QQGlyphShape: Shape {
    var kind: QQGlyphKind

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        let cx = rect.midX, cy = rect.midY
        switch kind {
        case .star:
            let R = min(w, h) / 2
            let r = R * 0.42
            for i in 0..<10 {
                let ang = -Double.pi / 2 + Double(i) * Double.pi / 5
                let rad = (i % 2 == 0) ? R : r
                let pt = CGPoint(x: cx + CGFloat(cos(ang)) * rad, y: cy + CGFloat(sin(ang)) * rad)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()

        case .moon:

            p.addEllipse(in: rect.insetBy(dx: w * 0.04, dy: h * 0.04))
            let d = min(w, h) * 0.98
            p.addEllipse(in: CGRect(x: rect.minX + w * 0.36,
                                    y: rect.minY - h * 0.04,
                                    width: d, height: d))

        case .sun:
            let R = min(w, h) / 2
            p.addEllipse(in: CGRect(x: cx - R * 0.50, y: cy - R * 0.50, width: R, height: R))
            for i in 0..<8 {
                let a = Double(i) * Double.pi / 4
                let inner = R * 0.72, outer = R * 0.99, half = R * 0.15
                let p1 = CGPoint(x: cx + CGFloat(cos(a)) * inner, y: cy + CGFloat(sin(a)) * inner)
                let p2 = CGPoint(x: cx + CGFloat(cos(a)) * outer, y: cy + CGFloat(sin(a)) * outer)
                let pa = CGPoint(x: p1.x + CGFloat(cos(a + .pi / 2)) * half,
                                 y: p1.y + CGFloat(sin(a + .pi / 2)) * half)
                let pb = CGPoint(x: p1.x + CGFloat(cos(a - .pi / 2)) * half,
                                 y: p1.y + CGFloat(sin(a - .pi / 2)) * half)
                p.move(to: pa); p.addLine(to: p2); p.addLine(to: pb); p.closeSubpath()
            }

        case .crown:

            p.move(to: CGPoint(x: rect.minX + w * 0.07, y: rect.minY + h * 0.90))
            p.addLine(to: CGPoint(x: rect.minX + w * 0.07, y: rect.minY + h * 0.36))
            p.addQuadCurve(to: CGPoint(x: rect.minX + w * 0.26, y: rect.minY + h * 0.52),
                           control: CGPoint(x: rect.minX + w * 0.12, y: rect.minY + h * 0.24))
            p.addQuadCurve(to: CGPoint(x: rect.minX + w * 0.50, y: rect.minY + h * 0.22),
                           control: CGPoint(x: rect.minX + w * 0.35, y: rect.minY + h * 0.42))
            p.addQuadCurve(to: CGPoint(x: rect.minX + w * 0.74, y: rect.minY + h * 0.52),
                           control: CGPoint(x: rect.minX + w * 0.65, y: rect.minY + h * 0.42))
            p.addQuadCurve(to: CGPoint(x: rect.minX + w * 0.93, y: rect.minY + h * 0.36),
                           control: CGPoint(x: rect.minX + w * 0.88, y: rect.minY + h * 0.24))
            p.addLine(to: CGPoint(x: rect.minX + w * 0.93, y: rect.minY + h * 0.90))
            p.closeSubpath()
        }
        return p
    }
}

struct LevelIcon: View {
    var kind: QQGlyphKind
    var size: CGFloat

    var body: some View {

        QQGlyph(kind: kind, size: size)
    }

    static func image(_ kind: QQGlyphKind) -> UIImage? {
        nil
    }
}

struct QQGlyph: View {
    var kind: QQGlyphKind
    var size: CGFloat

    private var shines: Bool { kind == .sun || kind == .crown }
    private var glowColor: Color { kind == .sun ? Color(hex: 0xFFB01F) : Color(hex: 0xF2C64B) }

    @State private var pulse = false
    @State private var spin = false
    @State private var glint = false

    private var gradient: LinearGradient {
        switch kind {
        case .crown:
            return LinearGradient(colors: [Color(hex: 0xFFF7CF), Color(hex: 0xF2C64B), Color(hex: 0xC8890C)],
                                  startPoint: .top, endPoint: .bottom)
        case .sun:
            return LinearGradient(colors: [Color(hex: 0xFFEBAE), Color(hex: 0xFFB01F), Color(hex: 0xEE7A00)],
                                  startPoint: .top, endPoint: .bottom)
        case .moon:
            return LinearGradient(colors: [Color(hex: 0xF6FAFF), Color(hex: 0xB6CCEC), Color(hex: 0x7696C4)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        case .star:
            return LinearGradient(colors: [Color(hex: 0xFFF3C0), Color(hex: 0xFFC93C)],
                                  startPoint: .top, endPoint: .bottom)
        }
    }

    var body: some View {
        ZStack {

            if shines {
                Circle()
                    .fill(RadialGradient(colors: [glowColor.opacity(pulse ? 0.45 : 0.14), Color.clear],
                                         center: .center, startRadius: 0, endRadius: size * 0.9))
                    .frame(width: size * 1.6, height: size * 1.6)
                    .scaleEffect(pulse ? 1.05 : 0.86)
                    .allowsHitTesting(false)
            }

            ZStack {
                QQGlyphShape(kind: kind)
                    .fill(gradient, style: FillStyle(eoFill: true))
                QQGlyphShape(kind: kind)
                    .fill(LinearGradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0.0)],
                                         startPoint: .top, endPoint: .center),
                          style: FillStyle(eoFill: true))
            }

            .rotationEffect(.degrees(kind == .sun && spin ? 360 : 0))

            if shines {
                QQGlyphShape(kind: .star)
                    .fill(Color.white)
                    .frame(width: size * 0.36, height: size * 0.36)
                    .offset(x: size * 0.32, y: -size * 0.32)
                    .opacity(glint ? 0.95 : 0)
                    .scaleEffect(glint ? 1 : 0.35)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: Color.black.opacity(0.18), radius: size * 0.12, y: size * 0.06)
        .onAppear { startShine() }
    }

    private func startShine() {
        guard shines else { return }
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) { pulse = true }
        if kind == .sun {
            withAnimation(.linear(duration: 24).repeatForever(autoreverses: false)) { spin = true }
        }
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true).delay(0.7)) { glint = true }
    }
}

struct QQLevelBadge: View {
    var level: Int
    var size: CGFloat = 14
    var maxIcons: Int = 4

    private func kinds() -> [QQGlyphKind] {

        let ic = QQLevel.icons(max(1, level))
        var out: [QQGlyphKind] = []
        for _ in 0..<min(3, ic.crowns) { out.append(.crown) }
        for _ in 0..<min(3, ic.suns) { out.append(.sun) }
        for _ in 0..<min(3, ic.moons) { out.append(.moon) }
        for _ in 0..<min(3, ic.stars) { out.append(.star) }
        return out
    }

    var body: some View {
        let all = kinds()
        let shown = Array(all.prefix(max(1, maxIcons)))
        let more = all.count - shown.count
        HStack(spacing: size * 0.14) {
            ForEach(shown.indices, id: \.self) { i in

                LevelIcon(kind: shown[i], size: size)
            }
            if more > 0 {
                Text("+" + String(more))
                    .font(pfStyled(size: size * 0.62, weight: .semibold))
                    .foregroundColor(C.subLabel)
            }
        }
    }
}

struct MyLevelView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = GrowthStore.shared
    @State private var loadingRank = true

    private func num(_ v: Double) -> String {
        let r = (v * 10).rounded() / 10
        return abs(r - r.rounded()) < 0.001 ? String(Int(r)) : String(format: "%.1f", r)
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("我的等级"), back: { dismiss() })
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    heroCard
                    todayCard
                    ruleCard
                    rankCard
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 30)
            }
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .task {
            await store.refresh()
            await store.loadRank()
            loadingRank = false
        }
    }

    private var heroCard: some View {
        let total = store.totalDays
        let level = store.shownLevel
        let start = Double(store.me?.levelStartDays ?? Double(QQLevel.days(for: level)))
        let next = Double(store.me?.nextDays ?? Double(QQLevel.days(for: level + 1)))
        let prog = next > start ? max(0, min(1, (total - start) / (next - start))) : 0
        let need = max(0, next - total)

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                QQLevelBadge(level: level, size: 26, maxIcons: 6)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 3) {
                    Text("Lv." + String(level))
                        .font(pfStyled(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: [Color(hex: 0xFFF6D2), Color(hex: 0xF0C24B)],
                                                        startPoint: .top, endPoint: .bottom))
                    Text(Tr("活跃天") + " " + num(total))
                        .font(pf(12.5))
                        .foregroundColor(.white.opacity(0.72))
                }
            }

            VStack(spacing: 7) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15))
                        Capsule()
                            .fill(LinearGradient(colors: [Color(hex: 0xFFE9A6), Color(hex: 0xF3B529)],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(8, g.size.width * prog))
                    }
                }
                .frame(height: 8)
                HStack {
                    Text("Lv." + String(level)).font(pf(11.5)).foregroundColor(.white.opacity(0.55))
                    Spacer(minLength: 6)
                    Text(Tr("距 Lv.") + String(level + 1) + Tr(" 还需 ") + num(need) + Tr(" 个活跃天"))
                        .font(pf(11.5))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
        }
        .padding(16)
        .background(
            ZStack {
                LinearGradient(colors: [Color(hex: 0x1C2130), Color(hex: 0x2B2233), Color(hex: 0x14111A)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [Color(hex: 0xF3C74B).opacity(0.22), Color.clear],
                               center: .topTrailing, startRadius: 2, endRadius: 230)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var todayCard: some View {
        let secs = store.me?.todaySeconds ?? 0
        let mins = secs / 60
        let full = store.cfg.fullSeconds ?? 7200
        let half = store.cfg.halfSeconds ?? 1800
        let tip: String = {
            if secs >= full { return Tr("今天的活跃天已经记满（1 个）") }
            if secs >= half { return Tr("再坚持 ") + String(max(1, (full - secs) / 60)) + Tr(" 分钟，今天能记满 1 个活跃天") }
            return Tr("再活跃 ") + String(max(1, (half - secs) / 60)) + Tr(" 分钟，今天记 0.5 个活跃天")
        }()
        return VStack(alignment: .leading, spacing: 10) {
            Text(Tr("今日活跃")).font(pf(15, .medium)).foregroundColor(C.label)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(mins)).font(pfStyled(size: 26, weight: .semibold, design: .rounded))
                    .foregroundColor(C.label)
                Text(Tr("分钟")).font(pf(13)).foregroundColor(C.subLabel)
                Spacer(minLength: 0)
                Text(Tr("今日已记 ") + num(store.me?.todayEarned ?? 0) + Tr(" 个活跃天"))
                    .font(pf(12.5)).foregroundColor(C.subLabel)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(C.hairline)
                    Capsule().fill(LinearGradient(colors: [Color(hex: 0xFFD98A), Color(hex: 0xF3B529)],
                                                  startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, g.size.width * min(1, Double(secs) / Double(max(1, full)))))
                }
            }
            .frame(height: 6)
            Text(tip).font(pf(12)).foregroundColor(C.subLabel)
        }
        .padding(14)
        .background { CardGlassBox(radius: 12) }
    }

    private var ruleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Tr("等级怎么算")).font(pf(15, .medium)).foregroundColor(C.label)
            Text(store.cfg.tip ?? Tr("每天使用满 2 小时记 1 个活跃天，满 30 分钟记 0.5 个。"))
                .font(pf(13)).foregroundColor(C.subLabel).lineSpacing(4)
            HairLine(inset: 0)
            HStack(spacing: 14) {
                HStack(spacing: 5) {
                    LevelIcon(kind: .star, size: 16)
                    Text(Tr("1 星 = 1 级")).font(pf(12)).foregroundColor(C.subLabel)
                }
                HStack(spacing: 5) {
                    LevelIcon(kind: .moon, size: 16)
                    Text(Tr("1 月亮 = 4 级")).font(pf(12)).foregroundColor(C.subLabel)
                }
            }
            HStack(spacing: 14) {
                HStack(spacing: 5) {
                    LevelIcon(kind: .sun, size: 16)
                    Text(Tr("1 太阳 = 16 级")).font(pf(12)).foregroundColor(C.subLabel)
                }
                HStack(spacing: 5) {
                    LevelIcon(kind: .crown, size: 16)
                    Text(Tr("1 皇冠 = 64 级")).font(pf(12)).foregroundColor(C.subLabel)
                }
            }
            Text(Tr("升到 L 级需要 L²+4L 个活跃天：Lv.4 = 32 天 · Lv.16 = 320 天 · Lv.64 = 4352 天"))
                .font(pf(11.5)).foregroundColor(C.subLabel)
        }
        .padding(14)
        .background { CardGlassBox(radius: 12) }
    }

    private var rankCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Tr("活跃榜")).font(pf(15, .medium)).foregroundColor(C.label)
                .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 8)
            if let mine = store.rankMine {
                HStack(spacing: 10) {
                    Avatar(path: mine.avatar ?? "", size: 34, radius: 17, circle: true)
                    Text(Tr("我")).font(pf(14, .medium)).foregroundColor(C.label)
                    QQLevelBadge(level: max(1, mine.level ?? 0), size: 13, maxIcons: 4)
                    Spacer(minLength: 0)
                    Text("Lv." + String(max(1, mine.level ?? 0))).font(pf(13, .semibold)).foregroundColor(C.subLabel)
                    Text(num(mine.total ?? 0) + Tr(" 天")).font(pf(13)).foregroundColor(C.subLabel)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            HairLine(inset: 14)
            if loadingRank && store.rank.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }.padding(.vertical, 18)
            } else if store.rank.isEmpty {
                Text(Tr("还没有人上榜，多用几天就有了"))
                    .font(pf(13)).foregroundColor(C.subLabel)
                    .padding(.horizontal, 14).padding(.vertical, 16)
            } else {
                ForEach(Array(store.rank.prefix(20).enumerated()), id: \.element.id) { idx, row in
                    HStack(spacing: 10) {
                        Text(String(idx + 1))
                            .font(pf(13, .semibold))
                            .foregroundColor(idx < 3 ? Color(hex: 0xE0A21B) : C.subLabel)
                            .frame(width: 22, alignment: .center)
                        Avatar(path: row.avatar ?? "", size: 32, radius: 16, circle: true)
                        Text(row.name ?? "")
                            .font(pf(14)).foregroundColor(C.label).lineLimit(1)
                        QQLevelBadge(level: max(1, row.level ?? 0), size: 12, maxIcons: 3)
                        Spacer(minLength: 0)
                        Text("Lv." + String(max(1, row.level ?? 0))).font(pf(12.5)).foregroundColor(C.subLabel)
                        Text(num(row.total ?? 0) + Tr(" 天")).font(pf(12.5)).foregroundColor(C.subLabel)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                    if idx < min(19, store.rank.count - 1) { HairLine(inset: 60) }
                }
            }
        }
        .background { CardGlassBox(radius: 12) }
    }
}
