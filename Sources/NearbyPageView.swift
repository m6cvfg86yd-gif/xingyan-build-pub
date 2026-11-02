import SwiftUI
import CoreLocation
import UIKit

struct RadarWedge: Shape {
    var span: Double = 60
    var lead: Double = 0
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        p.move(to: c)
        p.addArc(center: c, radius: max(rect.width, rect.height) / 2,
                 startAngle: .degrees(-span + lead), endAngle: .degrees(lead),
                 clockwise: false)
        p.closeSubpath()
        return p
    }
}

final class NearbyLocator: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var lat: Double?
    @Published var lng: Double?
    @Published var denied = false
    @Published var asking = false

    private let mgr = CLLocationManager()

    override init() {
        super.init()
        mgr.delegate = self
        mgr.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func start() {
        switch mgr.authorizationStatus {
        case .denied, .restricted:
            denied = true
        case .notDetermined:
            asking = true
            mgr.requestWhenInUseAuthorization()
        default:
            mgr.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        Task { @MainActor in
            switch m.authorizationStatus {
            case .denied, .restricted:
                self.denied = true
                self.asking = false
            case .notDetermined:
                self.asking = true
            default:
                self.asking = false
                self.denied = false
                m.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        guard let loc = locs.last else { return }
        Task { @MainActor in
            self.lat = loc.coordinate.latitude
            self.lng = loc.coordinate.longitude
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError error: Error) { }
}

struct NearbyPageView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var loc = NearbyLocator()

    @State private var people: [NearbyPerson] = []
    @State private var loading = false
    @State private var tip = ""

    @State private var filter = "all"
    @State private var showMenu = false

    @State private var maxKm: Double = 5

    @State private var wider = 0

    @State private var helloFor: NearbyPerson?
    @State private var helloText = "你好呀，我是在附近的人里看到你的"
    @State private var cardUser: User?

    @State private var mode = 0
    @State private var selected: NearbyPerson?
    @State private var sweep: Double = 0

    private let radarTick = Timer.publish(every: 0.02, on: .main, in: .common).autoconnect()

    private let radarD: CGFloat = 142

    private let pageBg = Color.dyn(0x111111, 0x141419)
    private let rowBg = Color(hex: 0x191919)
    private let nameInk = Color.white
    private let subInk = Color(hex: 0x929292)

    private var filterTitle: String {
        switch filter {
        case "female": return "只看女生"
        case "male": return "只看男生"
        default: return "全部"
        }
    }

    var body: some View {
        VStack(spacing: 0) {

            ZStack {

                Text(Tr(UIConfig.text("nearbyTitle", "附近的人")))
                    .font(pf(17, .semibold))
                    .foregroundColor(nameInk)
                HStack(spacing: 0) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundColor(nameInk)
                            .frame(width: 44, height: L.navH)
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)

                    Button { withAnimation(.easeOut(duration: 0.2)) { mode = (mode == 0 ? 1 : 0) } } label: {
                        Image(systemName: mode == 0 ? "list.bullet" : "dot.radiowaves.left.and.right")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(nameInk)
                            .frame(width: 44, height: L.navH)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button { showMenu = true } label: {
                        WeChatDots(color: nameInk)
                            .frame(width: 44, height: L.navH)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: L.navH)
            .background(pageBg)

            if mode == 0 {
                radarArea
            } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    if loc.denied {
                        hint("需要定位权限才能看到附近的人\n去「设置 → CHRIS聊天 → 位置」打开", showSetting: true)
                    } else if loading && people.isEmpty {
                        ProgressView().tint(.white).padding(.top, 70)
                    } else if people.isEmpty {
                        VStack(spacing: 12) {
                            hint(tip.isEmpty
                                 ? "\(Int(maxKm)) 公里内还没有其他人\n（对方也要打开「附近的人」，并且就在你附近）"
                                 : tip, showSetting: false)
                            if tip.isEmpty && maxKm < 20 {
                                if wider > 0 {
                                    Button("扩大到 20 公里（有 \(wider) 人）") {
                                        maxKm = 20
                                        Task { await reload(force: true) }
                                    }
                                    .font(pf(15))
                                    .foregroundColor(C.green)
                                } else {
                                    Text(Tr("20 公里内也没有人"))
                                        .font(pf(13))
                                        .foregroundColor(subInk.opacity(0.7))
                                }
                            }
                        }
                    } else {
                        ForEach(people) { p in
                            personRow(p)
                        }
                    }
                }
                .padding(.bottom, 20)
            }
            .background(pageBg)
            }
        }
        .background(pageBg.ignoresSafeArea(edges: .bottom))
        .background(pageBg.ignoresSafeArea(edges: .top))
        .toolbar(.hidden, for: .navigationBar)
        .hidesTabBar()

        .swipeBack { dismiss() }
        .navigationDestination(isPresented: Binding(
            get: { cardUser != nil },
            set: { if !$0 { cardUser = nil } }
        )) {
            if let u = cardUser {
                ContactCardView(user: u, onOpenChat: { _ in cardUser = nil }, onOpenMoments: { _ in cardUser = nil })
            }
        }
        .confirmationDialog("", isPresented: $showMenu, titleVisibility: .hidden) {
            Button(Tr("全部")) { setFilter("all") }
            Button(Tr("只看女生")) { setFilter("female") }
            Button(Tr("只看男生")) { setFilter("male") }
            Button(Tr("刷新")) { Task { await reload(force: true) } }
            Button(Tr("清除位置信息并退出"), role: .destructive) { clearLocation() }
            Button(Tr("取消"), role: .cancel) { }
        }
        .alert(Tr("打招呼"), isPresented: Binding(
            get: { helloFor != nil },
            set: { if !$0 { helloFor = nil } }
        )) {
            TextField("说点什么…", text: $helloText)
            Button(Tr("发送")) { sendHello() }
            Button(Tr("取消"), role: .cancel) { helloFor = nil }
        } message: {
            Text(Lang.isEnglish ? "Send a message to \(helloFor?.name ?? "")"
                                : "给 \(helloFor?.name ?? "") 发一条消息")
        }
        .task {
            loc.start()
            await reload(force: true)
        }
        .onChange(of: loc.lat) { _ in Task { await reload(force: true) } }
        .onReceive(radarTick) { _ in
            guard mode == 0 else { return }
            sweep = (sweep + 0.96).truncatingRemainder(dividingBy: 360)
        }
    }

    private var radarArea: some View {
        VStack(spacing: 0) {
            if loc.denied {
                hint("需要定位权限才能看到附近的人\n去「设置 → CHRIS聊天 → 位置」打开", showSetting: true)
                Spacer(minLength: 0)
            } else {
                ZStack {

                    Circle()
                        .fill(RadialGradient(colors: [Color(hex: 0x0F1D16), Color(hex: 0x07110C)],
                                             center: UnitPoint(x: 0.5, y: 0.42),
                                             startRadius: 6, endRadius: radarD * 1.02))
                        .frame(width: radarD * 2 + 18, height: radarD * 2 + 18)
                        .overlay(Circle().stroke(Color(hex: 0x2E6B52).opacity(0.55), lineWidth: 1))
                        .shadow(color: .black.opacity(0.35), radius: 16, y: 7)
                        .shadow(color: C.green.opacity(0.10), radius: 22)

                    Rectangle().fill(Color(hex: 0x2E6B52).opacity(0.30))
                        .frame(width: radarD * 2, height: 1)
                    Rectangle().fill(Color(hex: 0x2E6B52).opacity(0.30))
                        .frame(width: 1, height: radarD * 2)
                    ForEach(0..<12, id: \.self) { i in
                        Rectangle()
                            .fill(Color(hex: 0x2E6B52).opacity(0.45))
                            .frame(width: 1, height: i % 3 == 0 ? 9 : 5)
                            .offset(y: -radarD + 5)
                            .rotationEffect(.degrees(Double(i) * 30))
                    }

                    ForEach(1..<4, id: \.self) { i in
                        Circle()
                            .stroke(C.green.opacity(0.30 - Double(i) * 0.07), lineWidth: 1)
                            .frame(width: radarD * 2 * CGFloat(i) / 3,
                                   height: radarD * 2 * CGFloat(i) / 3)
                    }

                    ZStack {
                        RadarWedge(span: 92)
                            .fill(LinearGradient(colors: [C.green.opacity(0.16), .clear],
                                                 startPoint: .leading, endPoint: .trailing))
                        RadarWedge(span: 52)
                            .fill(LinearGradient(colors: [C.green.opacity(0.42), .clear],
                                                 startPoint: .leading, endPoint: .trailing))

                        Rectangle()
                            .fill(LinearGradient(colors: [C.green.opacity(0.95), C.green.opacity(0.25)],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: radarD, height: 1.8)
                            .offset(x: radarD / 2)
                            .shadow(color: C.green.opacity(0.85), radius: 7)
                            .frame(width: radarD * 2, height: radarD * 2)
                    }
                    .frame(width: radarD * 2, height: radarD * 2)
                    .rotationEffect(.degrees(sweep))
                    .clipShape(Circle())
                    .frame(width: radarD * 2, height: radarD * 2)

                    Circle()
                        .stroke(C.green.opacity(0.35), lineWidth: 1.4)
                        .frame(width: 54, height: 54)
                        .scaleEffect(0.9 + 0.5 * CGFloat((sin(sweep * .pi / 90) + 1) / 2))
                        .opacity(0.9 - 0.6 * CGFloat((sin(sweep * .pi / 90) + 1) / 2))
                    Circle()
                        .fill(C.green.opacity(0.18))
                        .frame(width: 44, height: 44)
                        .scaleEffect(1 + 0.22 * CGFloat(sin(sweep * .pi / 180)))
                    Circle().fill(C.green).frame(width: 10, height: 10)
                        .shadow(color: C.green.opacity(0.9), radius: 8)

                    ForEach(Array(people.prefix(14))) { p in blip(p) }
                }
                .frame(height: radarD * 2 + 40)
                .padding(.top, 6)
                if people.isEmpty {
                    Text(loading ? Tr("正在扫描附近的人…")
                                 : (tip.isEmpty
                                    ? Tr("\(Int(maxKm)) 公里内还没有其他人\n（对方也要打开「附近的人」，并且就在你附近）")
                                    : tip))
                        .font(pf(13.5)).foregroundColor(subInk)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                        .padding(.top, 8)
                } else {
                    Text(Tr("已扫到 ") + String(people.count) + Tr(" 个人 · 点亮着的点看资料"))
                        .font(pf(13)).foregroundColor(subInk)
                        .padding(.top, 8)
                }
                Spacer(minLength: 0)
            }
            bottomCard
        }
    }

    private func blip(_ p: NearbyPerson) -> some View {
        let s = spot(p)
        let lit = isLit(s.ang)
        let picked = selected?.id == p.id
        let d = radarD * s.r
        let size: CGFloat = picked ? 46 : 38
        return Button {
            withAnimation(.easeOut(duration: 0.18)) { selected = p }
        } label: {
            ZStack {
                Circle().fill(lit || picked ? C.green.opacity(0.9) : Color(hex: 0x2A2A2A))
                    .frame(width: size, height: size)
                Avatar(path: p.avatar ?? "", size: size - 8, radius: (size - 8) / 2)
            }
            .overlay(Circle().stroke(picked ? C.green : Color.white.opacity(lit ? 0.5 : 0.14),
                                     lineWidth: picked ? 2 : 1))
            .shadow(color: lit ? C.green.opacity(0.45) : .clear, radius: 8)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .offset(x: sin(s.ang * .pi / 180) * d, y: -cos(s.ang * .pi / 180) * d)
        .opacity(lit || picked ? 1 : 0.5)
        .animation(.easeOut(duration: 0.25), value: lit)
    }

    private func spot(_ p: NearbyPerson) -> (ang: Double, r: Double) {
        var h = 5381
        for b in p.id.utf8 { h = (h &* 33) &+ Int(b) }
        let ang = Double(abs(h) % 360)
        let km = max(0.05, p.km ?? 1)
        let near = max(0.25, min(1.0, 1 - (km / max(1, maxKm))))
        return (ang, 0.30 + 0.66 * near)
    }

    private func isLit(_ ang: Double) -> Bool {
        let d = abs(((ang - sweep + 540).truncatingRemainder(dividingBy: 360)) - 180)
        return d < 26
    }

    private var bottomCard: some View {
        VStack(spacing: 8) {
            if let p = selected {
                HStack(spacing: 12) {
                    Avatar(path: p.avatar ?? "", size: 44, radius: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(p.name).font(pf(16, .medium)).foregroundColor(nameInk).lineLimit(1)
                        Text(signature(p).isEmpty ? p.distanceText
                                                  : p.distanceText + " · " + signature(p))
                            .font(pf(12.5)).foregroundColor(subInk).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Button { openCard(p) } label: {
                        Image(systemName: "person.text.rectangle")
                            .font(.system(size: 16)).foregroundColor(subInk)
                            .frame(width: 36, height: 32).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button { helloFor = p } label: {
                        Text(Tr("打招呼")).font(pf(13.5, .medium)).foregroundColor(.white)
                            .padding(.horizontal, 12).frame(height: 32)
                            .background(Capsule().fill(C.green))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 14)).foregroundColor(C.green)
                    Text(loading ? Tr("正在扫描…") : Tr("点上面亮着的头看看是谁"))
                        .font(pf(13.5)).foregroundColor(subInk)
                    Spacer(minLength: 0)
                    Button { Task { await reload(force: true) } } label: {
                        Text(Tr("重新扫描")).font(pf(13, .medium)).foregroundColor(C.green)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(rowBg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 14)
        .padding(.bottom, 18)
    }

    private func personRow(_ p: NearbyPerson) -> some View {
        Button {
            helloFor = p
        } label: {
            HStack(alignment: .top, spacing: 13) {
                Avatar(path: p.avatar ?? "", size: 46, radius: 5)
                    .padding(.leading, 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name)
                        .font(pf(17))
                        .foregroundColor(nameInk)
                        .lineLimit(1)
                    Text(p.distanceText)
                        .font(pf(14))
                        .foregroundColor(subInk)
                        .lineLimit(1)
                }
                .padding(.top, 1)

                Spacer(minLength: 8)

                if !signature(p).isEmpty {
                    Text(signature(p))
                        .font(pf(13.5))
                        .foregroundColor(subInk)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                        .frame(maxWidth: 150, alignment: .trailing)
                        .padding(.top, 3)
                }
            }
            .padding(.trailing, 16)
            .frame(height: 65, alignment: .top)
            .background(rowBg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { openCard(p) } label: {
                Label(Tr("查看资料"), systemImage: "person.text.rectangle")
            }
        }
    }

    private func signature(_ p: NearbyPerson) -> String {
        if let m = p.moodText, !m.isEmpty { return m }
        if let b = p.bio, !b.isEmpty { return b }
        if p.friend == true { return "已经是好友" }
        return ""
    }

    private func hint(_ text: String, showSetting: Bool) -> some View {
        VStack(spacing: 10) {
            Text(text)
                .font(pf(14))
                .foregroundColor(subInk)
                .multilineTextAlignment(.center)
            if showSetting {
                Button(Tr("去设置里打开")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(pf(15))
                .foregroundColor(C.green)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private func setFilter(_ f: String) {
        filter = f
        Task { await reload(force: true) }
    }

    private func reload(force: Bool) async {
        if loading && !force { return }
        loading = true
        defer { loading = false }
        do {

            if let la = loc.lat, let ln = loc.lng {
                try? await API.shared.nearbyReport(lat: la, lng: ln)
            }
            let r = try await API.shared.nearby(lat: loc.lat, lng: loc.lng, gender: filter, maxKm: maxKm)
            people = r.people
            wider = r.wider
            tip = ""
        } catch {
            tip = "网络有点忙，稍后再试"
        }
    }

    private func clearLocation() {
        Task {
            try? await API.shared.nearbyClear()
            people = []
            app.show(Tr("已清除位置信息"))
            dismiss()
        }
    }

    private func sendHello() {
        guard let p = helloFor else { return }
        let text = helloText.trimmingCharacters(in: .whitespacesAndNewlines)
        let say = text.isEmpty ? "你好呀，我是在附近的人里看到你的" : text
        helloFor = nil
        Task {
            do {
                _ = try await API.shared.nearbyHello(userId: p.id, text: say)
                app.show(Tr("已打招呼"))
                await app.loadChats()
            } catch {
                app.show((error as? APIError)?.errorDescription ?? "发送失败")
            }
        }
    }

    private func openCard(_ p: NearbyPerson) {
        Task {
            if let u = try? await API.shared.user(id: p.id) { cardUser = u }
        }
    }
}
