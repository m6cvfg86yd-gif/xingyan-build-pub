import SwiftUI
import MapKit
import CoreLocation

final class LiveLocationStore: ObservableObject {
    static let shared = LiveLocationStore()

    struct Peer: Identifiable {
        var id: String
        var name: String
        var avatar: String
        var lat: Double
        var lng: Double
    }

    @Published var sessionId = ""
    @Published var chatId = ""
    @Published var active = false
    @Published var peers: [Peer] = []

    func reset() {
        sessionId = ""
        chatId = ""
        active = false
        peers = []
    }

    func apply(sessionId: String, members: [API.LiveMember]) {
        self.sessionId = sessionId
        active = true
        var list: [Peer] = []
        for m in members {
            guard let lat = m.lat, let lng = m.lng else { continue }
            list.append(Peer(id: m.userId, name: m.name ?? "",
                             avatar: m.avatar ?? "", lat: lat, lng: lng))
        }
        peers = list
    }

    func upsert(userId: String, name: String, avatar: String, lat: Double, lng: Double) {
        if let i = peers.firstIndex(where: { $0.id == userId }) {
            peers[i].lat = lat
            peers[i].lng = lng
            if !name.isEmpty { peers[i].name = name }
        } else {
            peers.append(Peer(id: userId, name: name, avatar: avatar, lat: lat, lng: lng))
        }
    }
}

struct SendLocationView: View {
    var onSend: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
    @State private var myLat = 0.0
    @State private var myLng = 0.0
    @State private var places: [(String, String, Double, Double)] = []
    @State private var loading = true
    @State private var picked = 0
    @State private var denied = false

    @State private var homePlaces: [(String, String, Double, Double)] = []

    @State private var centerPlace: (String, String, Double, Double)? = nil

    @State private var query = ""
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var centerTask: Task<Void, Never>? = nil
    @State private var searching = false

    @State private var suppressCenter = false

    var body: some View {
        ZStack {
            Map(coordinateRegion: $region, showsUserLocation: true,
                annotationItems: places.enumerated().map { IndexedPlace(index: $0.offset, name: $0.element.0,
                                                                       lat: $0.element.2, lng: $0.element.3) }) { p in
                MapMarker(coordinate: CLLocationCoordinate2D(latitude: p.lat, longitude: p.lng),
                          tint: p.index == picked ? C.green : .red)
            }
            .ignoresSafeArea()
            .onChange(of: region.center.latitude) { _ in centerMoved() }
            .onChange(of: region.center.longitude) { _ in centerMoved() }

            VStack(spacing: 9) {
                topControls
                searchBar
                Spacer(minLength: 0)
            }
            .padding(.top, 8)

            VStack(spacing: 9) {
                Spacer(minLength: 0)
                HStack {
                    Spacer(minLength: 0)
                    Button(action: recenter) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(C.green)
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .background { NativeGlassCircleBackground() }
                    .accessibilityLabel(Tr("回到当前位置"))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, locationPanelHeight + 12)

                mapStatus
                locationPanel
            }
        }
        .background(C.pageBg.ignoresSafeArea(edges: .bottom))
        .background(C.pageBg.ignoresSafeArea(edges: .top))
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .task { await locate() }
    }

    private var locationPanelHeight: CGFloat {
        min(330, max(238, L.height * 0.34))
    }

    private var topControls: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(C.label)
                    .frame(width: 42, height: 42)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .background { NativeGlassCircleBackground() }
            .accessibilityLabel(Tr("返回"))

            Spacer(minLength: 0)

            Text(Tr("发送位置"))
                .font(pf(15, .semibold))
                .foregroundColor(C.label)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background {
                    GlassBackground(shape: Capsule(style: .continuous), shadow: true)
                }

            Spacer(minLength: 0)

            Button(action: send) {
                Text(Tr("发送"))
                    .font(pf(14, .semibold))
                    .foregroundColor(places.isEmpty ? C.subLabel : .white)
                    .padding(.horizontal, 15)
                    .frame(height: 42)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .background {
                GlassBackground(
                    shape: Capsule(style: .continuous),
                    shadow: true,
                    tint: places.isEmpty ? nil : C.green.opacity(0.88)
                )
            }
            .disabled(places.isEmpty)
            .accessibilityLabel(Tr("发送位置"))
        }
        .padding(.horizontal, 14)
    }

    @ViewBuilder
    private var mapStatus: some View {
        if loading {
            statusPill(Tr("正在定位…"), symbol: "location")
        } else if denied {
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                statusPill(Tr("定位没开：点这里去设置里打开「位置」"), symbol: "location.slash")
            }
            .buttonStyle(.plain)
        } else if searching {
            statusPill(Tr("正在找这个地方…"), symbol: "magnifyingglass")
        }
    }

    private func statusPill(_ title: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
            Text(title)
                .font(pf(12.5, .medium))
                .lineLimit(1)
        }
        .foregroundColor(C.label)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background {
            GlassBackground(shape: Capsule(style: .continuous), shadow: true)
        }
    }

    private var locationPanel: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.secondary.opacity(0.26))
                .frame(width: 34, height: 4)
                .padding(.top, 8)
                .padding(.bottom, 7)

            HStack(spacing: 8) {
                Image(systemName: trimmed.isEmpty ? "mappin.and.ellipse" : "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(C.green)
                Text(trimmed.isEmpty ? Tr("附近地点") : Tr("搜索结果"))
                    .font(pf(15, .semibold))
                    .foregroundColor(C.label)
                Spacer(minLength: 0)
                Text("\(places.count)")
                    .font(pf(11.5, .medium))
                    .foregroundColor(C.subLabel)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(Capsule().fill(C.label.opacity(0.06)))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            HairLine()

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    if places.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "mappin.slash")
                                .font(.system(size: 26, weight: .light))
                                .foregroundColor(C.subLabel)
                            Text(emptyText)
                                .font(pf(13.5))
                                .foregroundColor(C.subLabel)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 30)
                        .padding(.top, 34)
                    } else {
                        ForEach(places.indices, id: \.self) { i in
                            placeRow(i)
                            HairLine(inset: 48)
                        }
                    }
                }
            }
        }
        .frame(height: locationPanelHeight)
        .background {
            GlassBackground(
                shape: RoundedRectangle(cornerRadius: 26, style: .continuous),
                shadow: true
            )
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 7)
    }

    private struct IndexedPlace: Identifiable {
        var id: Int { index }
        var index: Int
        var name: String
        var lat: Double
        var lng: Double
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14.5, weight: .medium))
                .foregroundColor(C.searchIcon)
            TextField(Tr("搜索地点：大厦 / 小区 / 商铺名"), text: $query)
                .font(pf(15))
                .foregroundColor(C.label)
                .submitLabel(.search)
                .onSubmit { searchNow() }
                .onChange(of: query) { _ in queryChanged() }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(C.searchIcon2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background {
            GlassBackground(shape: Capsule(style: .continuous), shadow: true)
        }
        .padding(.horizontal, 14)
    }

    private func placeRow(_ i: Int) -> some View {
        let p = places[i]
        return Button {
            picked = i

            suppressCenter = true
            withAnimation(.easeOut(duration: 0.22)) {
                region.center = CLLocationCoordinate2D(latitude: p.2, longitude: p.3)
                region.span = MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { suppressCenter = false }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: i == picked ? "mappin.circle.fill" : "mappin.circle")
                    .font(.system(size: 17))
                    .foregroundColor(i == picked ? C.green : C.subLabel)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.0).font(pf(16)).foregroundColor(C.label).lineLimit(1)
                    if !p.1.isEmpty {
                        Text(p.1).font(pf(12.5)).foregroundColor(C.subLabel).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if i == picked {
                    Image(systemName: "checkmark").foregroundColor(C.green)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 58)
            .background(i == picked ? C.green.opacity(0.10) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var emptyText: String {
        if !trimmed.isEmpty { return Tr("没找到") + "「\(trimmed)」\n" + Tr("换个说法试试（路名 / 楼名 / 小区名）") }
        if denied { return Tr("定位没开。可以在上面搜地点，也可以拖动地图选点") }
        return Tr("拖一下地图换个位置，或者在上面搜地点")
    }

    private func queryChanged() {
        searchTask?.cancel()
        let q = trimmed
        if q.isEmpty {
            searchTask = nil
            searching = false
            places = centerPlace.map { [$0] + homePlaces } ?? homePlaces
            picked = 0
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled { return }
            await runSearch(q)
        }
    }

    private func searchNow() {
        searchTask?.cancel()
        let q = trimmed
        guard !q.isEmpty else { queryChanged(); return }
        Task { await runSearch(q) }
    }

    private func runSearch(_ q: String) async {
        searching = true
        let res = await searchPlaces(q)

        guard trimmed == q else { return }
        places = res
        picked = 0
        searching = false
    }

    private func searchPlaces(_ q: String) async -> [(String, String, Double, Double)] {

        if !q.isEmpty,
           let rows = try? await API.shared.geoSearch(q: q,
                                                      lat: region.center.latitude,
                                                      lng: region.center.longitude),
           !rows.isEmpty {
            return rows.compactMap { p in
                guard let n = p.name, !n.isEmpty, let la = p.lat, let ln = p.lng else { return nil }
                return (n, p.addr ?? "", la, ln)
            }
        }
        return await systemSearchPlaces(q)
    }

    private func systemSearchPlaces(_ q: String) async -> [(String, String, Double, Double)] {
        await withCheckedContinuation { cont in
            let req = MKLocalSearch.Request()
            req.naturalLanguageQuery = q

            req.region = MKCoordinateRegion(center: region.center,
                                            span: MKCoordinateSpan(latitudeDelta: 0.6, longitudeDelta: 0.6))
            MKLocalSearch(request: req).start { resp, _ in
                var out: [(String, String, Double, Double)] = []
                for item in resp?.mapItems ?? [] {
                    let pm = item.placemark
                    let name = item.name ?? pm.name ?? Tr("位置")
                    let addr = [pm.locality, pm.subLocality, pm.thoroughfare, pm.subThoroughfare]
                        .compactMap { $0 }.joined(separator: " ")
                    let c = pm.coordinate
                    out.append((name, addr, c.latitude, c.longitude))
                }
                cont.resume(returning: out)
            }
        }
    }

    private func centerMoved() {
        guard !suppressCenter, !loading else { return }
        centerTask?.cancel()
        let lat = region.center.latitude
        let lng = region.center.longitude
        centerTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            if Task.isCancelled { return }
            var name = Tr("地图上的这个点")
            var addr = ""
            if let marks = try? await CLGeocoder()
                .reverseGeocodeLocation(CLLocation(latitude: lat, longitude: lng)),
               let m = marks.first {
                name = m.name ?? m.locality ?? name
                addr = [m.locality, m.subLocality, m.thoroughfare, m.subThoroughfare]
                    .compactMap { $0 }.joined(separator: " ")
            }
            let place = (name, addr, lat, lng)
            centerPlace = place

            if trimmed.isEmpty {
                places = [place] + homePlaces
                picked = 0
            }
        }
    }

    private func locate() async {
        guard let loc = await OneShotLocation.shared.current() else {

            places = []
            denied = true
            loading = false
            return
        }
        myLat = loc.coordinate.latitude
        myLng = loc.coordinate.longitude

        suppressCenter = true
        region.center = loc.coordinate
        var list: [(String, String, Double, Double)] = []
        if let marks = try? await CLGeocoder().reverseGeocodeLocation(loc) {
            for m in marks.prefix(6) {
                let name = m.name ?? m.locality ?? Tr("我的位置")
                let addr = [m.locality, m.subLocality, m.thoroughfare, m.subThoroughfare]
                    .compactMap { $0 }.joined(separator: " ")
                list.append((name, addr, loc.coordinate.latitude, loc.coordinate.longitude))
            }
        }
        if list.isEmpty { list.append((Tr("我的位置"), "", myLat, myLng)) }
        homePlaces = list
        places = list
        picked = 0
        loading = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { suppressCenter = false }
    }

    private func recenter() {
        guard myLat != 0, myLng != 0 else {
            Task { await locate() }
            return
        }
        suppressCenter = true
        withAnimation(.easeOut(duration: 0.22)) {
            region.center = CLLocationCoordinate2D(latitude: myLat, longitude: myLng)
            region.span = MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
        }
        if !homePlaces.isEmpty {
            places = homePlaces
            picked = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { suppressCenter = false }
    }

    private func send() {
        guard places.indices.contains(picked) else { return }
        let p = places[picked]

        let obj: [String: Any] = ["lat": p.2, "lng": p.3, "name": p.0, "addr": p.1]
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let payload = String(data: data, encoding: .utf8) else { return }
        onSend(payload)
        dismiss()
    }
}

struct LiveLocationView: View {
    let chat: Chat
    var onStop: (() -> Void)? = nil

    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = LiveLocationStore.shared

    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
    @State private var timer: Task<Void, Never>?
    @State private var hint = ""

    private var peers: [LiveLocationStore.Peer] { store.peers }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("共享实时位置"), back: { stopAndClose() })

            Map(coordinateRegion: $region, showsUserLocation: true,
                annotationItems: peers) { p in
                MapMarker(coordinate: CLLocationCoordinate2D(latitude: p.lat, longitude: p.lng),
                          tint: p.id == app.me?.id ? C.green : .red)
            }
            .frame(maxHeight: .infinity)

            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Circle().fill(store.active ? C.green : C.subLabel).frame(width: 8, height: 8)
                    Text(store.active ? Tr("正在共享实时位置") : Tr("共享已结束"))
                        .font(pf(15)).foregroundColor(C.label)
                    Spacer()
                    Text("\(peers.count) " + Tr("个人在共享"))
                        .font(pf(13)).foregroundColor(C.subLabel)
                }
                if !peers.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(peers) { p in
                                HStack(spacing: 6) {
                                    Avatar(path: p.avatar, size: 26, radius: 13, circle: true)
                                    Text(p.name).font(pf(13)).foregroundColor(C.label)
                                }
                                .padding(.horizontal, 8)
                                .frame(height: 34)
                                .background { CardGlassBox(radius: 17) }
                            }
                        }
                    }
                }
                if !hint.isEmpty {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "location.slash")
                            Text(hint).font(pf(13))
                            Text(Tr("去设置")).font(pf(13, .medium)).foregroundColor(C.link)
                        }
                        .foregroundColor(C.subLabel)
                    }
                    .buttonStyle(.plain)
                }
                Button { stopAndClose() } label: {
                    Text(Tr("停止共享"))
                        .font(pf(16, .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: 8).fill(C.red))
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea(edges: .top))
        .toolbar(.hidden, for: .navigationBar)
        .hidesTabBar()

        .swipeBack { stopAndClose() }
        .task { await start() }
        .onDisappear { timer?.cancel() }
    }

    private func start() async {
        guard let loc = await OneShotLocation.shared.current() else {
            hint = Tr("没给定位权限，先去 设置 → Luchat → 位置 打开")
            return
        }
        let lat = loc.coordinate.latitude
        let lng = loc.coordinate.longitude
        region.center = loc.coordinate
        if let r = await API.shared.liveStart(chatId: chat.id, lat: lat, lng: lng) {
            store.sessionId = r.sessionId
            store.chatId = chat.id
            store.active = true
            if !r.joined { onStop?() }
        }
        await pushState()

        timer?.cancel()
        timer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if Task.isCancelled { break }
                await reportMyPosition()
                await pushState()
            }
        }
    }

    private func pushState() async {
        guard !store.sessionId.isEmpty else { return }
        if let s = await API.shared.liveState(sessionId: store.sessionId) {
            store.apply(sessionId: s.sessionId, members: s.members)
            if let me = s.members.first(where: { $0.userId == app.me?.id }),
               let lat = me.lat, let lng = me.lng {
                region.center = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            }
        }
    }

    private func reportMyPosition() async {
        guard store.active, !store.sessionId.isEmpty else { return }
        guard let loc = await OneShotLocation.shared.current() else { return }
        await API.shared.livePos(sessionId: store.sessionId,
                                 lat: loc.coordinate.latitude, lng: loc.coordinate.longitude)
        store.upsert(userId: app.me?.id ?? "", name: app.me?.name ?? "",
                     avatar: app.me?.avatarPath ?? "",
                     lat: loc.coordinate.latitude, lng: loc.coordinate.longitude)
    }

    private func stopAndClose() {
        timer?.cancel()
        Task {
            if !store.sessionId.isEmpty {
                await API.shared.liveStop(sessionId: store.sessionId)
            }
            store.reset()
        }
        dismiss()
    }
}
