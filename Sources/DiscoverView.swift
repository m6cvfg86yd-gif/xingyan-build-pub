import SwiftUI
import UniformTypeIdentifiers
import CoreLocation
import UIKit

struct DiscoverView: View {

    @State private var navScrolled: CGFloat = 0
    @ObservedObject private var lang = LangStore.shared
    @EnvironmentObject var app: AppState
    @State private var path = NavigationPath()

    @State private var items: [DiscoverItem] = []
    @State private var loaded = false

    @State private var showScan = false
    @ObservedObject private var realtime = Realtime.shared

    private var latestThumb: String {
        for m in app.moments {
            if let img = m.images?.first, !img.isEmpty { return img }
            if let c = m.videoCover, !c.isEmpty { return c }
        }
        return ""
    }

    private var discoverTopHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("世界")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(OrbitTheme.ink)
                Text(app.moments.isEmpty ? Tr("去发现、聊天、生活")
                                         : "\(app.moments.count) 条新动态")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(OrbitTheme.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                path.append("search")
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundStyle(OrbitTheme.ink)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(OrbitTheme.field))
                    .overlay(Circle().stroke(OrbitTheme.divider, lineWidth: 0.6))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Tr("搜索"))

            Button {
                showScan = true
            } label: {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(
                            LinearGradient(colors: [OrbitTheme.jadeDeep, OrbitTheme.jade],
                                           startPoint: .topLeading,
                                           endPoint: .bottomTrailing)
                        )
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Tr("扫一扫"))
        }
        .padding(.horizontal, 16)
        .frame(height: L.navH)
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {

                discoverTopHeader
                    .measure("discover.nav")

                    .background { TopGlassBar(scrolled: navScrolled, fallback: OrbitTheme.canvas, always: true) }
                    .overlay(alignment: .bottom) { TopGlassLine(scrolled: navScrolled) }
                    .zIndex(1)
                ScrollView {
                    VStack(spacing: 0) {
                        TopScrollProbe(space: "discoverScroll")
                            .frame(height: 0)

                        Color.clear.frame(height: L.navH)

                        ForEach(grouped.indices, id: \.self) { gi in

                            VStack(spacing: 0) {
                                ForEach(grouped[gi].indices, id: \.self) { ri in
                                    let item = grouped[gi][ri]
                                    if ri > 0 { rowLine }
                                    MenuRow(icon: "world:" + (item.action ?? "default"),
                                            iconColor: Color(hexString: item.color ?? "#4A90D9", fallback: 0x4A90D9),
                title: Tr(item.label),
                                            badge: item.action == "moments" && app.showDot("momentsRow", auto: !latestThumb.isEmpty),
                                            thumb: item.action == "moments" ? latestThumb : "",
                                            onTap: { open(item) },

                                            clearBg: true,

                                            iconTile: true,

                                            sf: RowIcon.sf(action: item.action, label: item.label))
                                }
                            }
                            .background(OrbitTheme.cardBackground())
                            .padding(.horizontal, 12)
                            .padding(.top, 3)
                            .padding(.bottom, 9)
                        }

                        Spacer().frame(height: 20)
                    }
                    .topScrollTracking($navScrolled, space: "discoverScroll")
                }

                .padding(.top, -L.navH)
                .background(OrbitTheme.canvas)
            }
            .background(OrbitTheme.canvas.ignoresSafeArea(edges: .bottom))

            .background(OrbitTheme.canvas.ignoresSafeArea(edges: .top))
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { key in
                if key == "moments" {
                    MomentsView()
                } else if key == "nearby" {
                    NearbyPageView()
        } else if key == "shake" {

            BottlePageView()
        } else if key == "bottle" {

            BottlePageView()
                } else if key == "live" {
                    LiveListView()
                } else if key == "games" {
                    GamesPageView()
                } else if key == "channels" {
                    ChannelsView()
                } else if key == "look" {
                    LookView()
                } else if key == "search" {
                    SearchAllView()
                } else if key == "news" {
                    NewsView()
                } else if key == "music" {

                    ListenView()
                } else if key == "miniapps" {

                    MiniAppsView()
                } else if key.hasPrefix("soon:") {
                    ComingSoonView(title: String(key.dropFirst(5)))
                } else {
                    ComingSoonView(title: key)
                }
            }
        }

        .onChange(of: realtime.event) { ev in
            if ev.type == "moment" || ev.user != nil { Task { await app.loadMoments() } }
            if ev.type == "ui" { Task { await loadItems() } }
        }

        .onReceive(NotificationCenter.default.publisher(for: .chrisUIPrefsChanged)) { _ in
            Task { await loadItems() }
        }
        .task {
            if !loaded { await loadItems() }
        }
        .fullScreenCover(isPresented: $showScan) {
            ScannerView { text in handleScanned(text, app: app) }
        }
    }

    private var grouped: [[DiscoverItem]] {

        let visible = MomentsPref.isOn ? items : items.filter { $0.action != "moments" }
        var out: [[DiscoverItem]] = []
        var last: Int? = nil
        for it in visible {
            let g = it.group ?? 1
            if last == nil || g != last! { out.append([]); last = g }
            out[out.count - 1].append(it)
        }
        return out
    }

    private func loadItems() async {
        if let list = try? await API.shared.discover(), !list.isEmpty {

            items = list
            loaded = true
        } else if items.isEmpty {

            items = DiscoverItem.builtin
        }
    }

    private func open(_ item: DiscoverItem) {
        switch item.action ?? "soon" {
        case "moments": path.append("moments")
        case "news": path.append("news")
        case "nearby": path.append("nearby")
        case "shake": path.append("shake")
        case "bottle": path.append("bottle")
        case "live": path.append("live")
        case "games": path.append("games")
    case "channels": path.append("channels")
    case "look": path.append("look")
    case "search": path.append("search")

    case "music": path.append("music")
    case "miniapps": path.append("miniapps")
    case "scan": showScan = true
    default: path.append("soon:" + item.label)
        }
    }

    private var gap: some View {
        Rectangle().fill(C.pageBg).frame(height: L.groupGap)
    }

    private var rowLine: some View {
        Rectangle()
            .fill(OrbitTheme.divider)
            .frame(height: 0.5)
            .padding(.leading, L.menuLineInset)
    }
}

extension DiscoverItem {
    static var builtin: [DiscoverItem] {
        [
            DiscoverItem(id: "d01", label: "生活圈", icon: "i.moments", svg: I.moments,
                         color: "#4A90D9", action: "moments", group: 1, enabled: true),
            DiscoverItem(id: "d02", label: "视频号", icon: "i.channels", svg: I.channels,
                         color: "#F2943B", action: "soon", group: 2, enabled: true),
            DiscoverItem(id: "d03", label: "直播", icon: "i.live", svg: I.live,
                         color: "#F4525B", action: "soon", group: 2, enabled: true),
            DiscoverItem(id: "d04", label: "扫一扫", icon: "i.scan", svg: I.scan,
                         color: "#3D83E7", action: "soon", group: 3, enabled: true),

            DiscoverItem(id: "d05", label: "漂流瓶", icon: "i.shake", svg: I.shake,
                         color: "#2E7BD6", action: "bottle", group: 3, enabled: true),
            DiscoverItem(id: "d06", label: "看一看", icon: "i.look", svg: I.look,
                         color: "#7275E9", action: "look", group: 4, enabled: true),
            DiscoverItem(id: "d07", label: "搜一搜", icon: "i.searchRow", svg: I.searchRow,
                         color: "#59C47E", action: "search", group: 4, enabled: true),
            DiscoverItem(id: "d08", label: "附近", icon: "i.nearby", svg: I.nearby,
                         color: "#3D83E7", action: "soon", group: 5, enabled: true),
            DiscoverItem(id: "d10", label: "游戏", icon: "i.game", svg: I.game,
                         color: "#9A6AE8", action: "soon", group: 7, enabled: true)
        ]
    }

    static var builtinMe: [DiscoverItem] {
        [
            DiscoverItem(id: "m01", label: "服务", icon: "i.wallet", svg: I.wallet,
                         color: "#59C47E", action: "service", group: 1, enabled: true),
            DiscoverItem(id: "m02", label: "收藏", icon: "i.star", svg: I.star,
                         color: "#4489EA", action: "favorites", group: 2, enabled: true),

            DiscoverItem(id: "m07", label: "小店与卡包", icon: "i.wallet", svg: I.wallet,
                         color: "#E08A22", action: "shop", group: 2, enabled: true),
            DiscoverItem(id: "m03", label: "生活圈", icon: "i.album", svg: I.album,
                         color: "#7275E9", action: "moments", group: 2, enabled: true),
            DiscoverItem(id: "m04", label: "作品", icon: "i.works", svg: I.works,
                         color: "#3D83E7", action: "works", group: 2, enabled: true),
            DiscoverItem(id: "m05", label: "表情", icon: "i.sticker", svg: I.sticker,
                         color: "#F5C144", action: "stickers", group: 3, enabled: true),
            DiscoverItem(id: "m06", label: "设置", icon: "i.gear", svg: I.gear,
                         color: "#3D83E7", action: "settings", group: 4, enabled: true)
        ]
    }
}

struct ComingSoonView: View {
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            Text(title).font(pf(17)).foregroundColor(C.label)
            Text(Tr("这一页排在下一批")).font(pf(14)).foregroundColor(C.subLabel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(C.pageBg)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(pf(18, .medium))
                }
            }
            ToolbarItem(placement: .principal) {
                Text(title).font(pf(UIConfig.num("navTitle", 17))).foregroundColor(C.label)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .swipeBack { dismiss() }
        .hidesTabBar()
    }
}

private struct OffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct OffsetKey2: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private final class MomentCoverPullBox {
    var value: CGFloat = 0
}

private final class MomentScrollMetrics {
    var topY: CGFloat = 0
    var blockY: CGFloat = 0
    var baseTop: CGFloat? = nil
    var baseBlock: CGFloat? = nil
}

struct MomentsView: View {
    @ObservedObject private var lang = LangStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var target: User? = nil

    var mineOnly: Bool = false

    private var feedUserId: String? { mineOnly ? app.me?.id : target?.id }

    private var coverEditable: Bool { target == nil || mineOnly }

    @State private var scrollMetrics = MomentScrollMetrics()

    @State private var sentinelGone = false

    @State private var solid = false
    @State private var moments: [Moment] = []

    @State private var confirmDiscard = false
    @State private var showPhoto = false
    @State private var showCamera = false

    @State private var showVideoShoot = false
    @State private var showCoverPhoto = false

    @State private var coverMenu = false
    @State private var showCoverCamera = false
    @State private var coverDraft: UIImage?

    @State private var coverLocked = false
    @State private var coverLockPull: CGFloat = 0

    @State private var coverPullBox = MomentCoverPullBox()
    @State private var composerPick = false

    @State private var composerVideoPick = false
    @State private var pickMediaMenu = false

    @State private var showMomentAlbum = false
    @State private var pickedVideo: URL?
    @State private var videoCover: UIImage?
    @State private var videoSeconds = 0
    @State private var videoWH: (w: Int, h: Int)?
    @State private var videoProgress = 0.0
    @State private var posting = false
    @State private var draft = ""
    @State private var picked: [UIImage] = []
    @State private var uploading = false
    @State private var commentsSheet: Moment?

    @State private var actionMoment: Moment?

    @State private var viewerPaths: [String] = []
    @State private var viewerIndex: Int?

    @State private var momentVideo: URL?

    @State private var cardUser: User?
    @State private var liveTarget: User?

    @State private var hasMoreMoments = false

    @State private var feedRange = "all"

    @State private var visibility = "public"
    @State private var showVisibility = false
    @State private var showPick = false
    @State private var pickMode = "partial"
    @State private var visibleTo: Set<String> = []
    @State private var hiddenFrom: Set<String> = []

    @State private var draftLocation = ""
    @State private var remindIds: Set<String> = []
    @State private var showLocation = false

    @State private var dragIndex: Int?

    @State private var tapLockUntil = Date(timeIntervalSince1970: 0)
    @State private var loadingMore = false
    @State private var momentTotal = 0

    @State private var pullY: CGFloat = 0
    @State private var pulling = false
    @State private var spin: Double = 0
    @State private var spinTask: Task<Void, Never>?

    @State private var lastDragAt = Date(timeIntervalSince1970: 0)
    @ObservedObject private var realtime = Realtime.shared

    @State private var expandedGroups: Set<String> = []

    @State private var foldRowsCache: [FoldRow] = []

    @State private var groupPage: MomentGroup?
    @State private var showGroupPage = false

    @State private var showNoticeList = false

    private var owner: User? {
        if let target {
            return liveTarget ?? app.contact(for: target.id) ?? target
        }
        return app.me
    }
    private var cover: String { owner?.momentCover ?? "" }

    private var signature: String? {
        let s = (owner?.bio ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    private func updateSolidState() {
        let a = scrollMetrics.baseTop.map { $0 - scrollMetrics.topY } ?? 0
        let b = scrollMetrics.baseBlock.map { $0 - scrollMetrics.blockY } ?? 0
        let next = max(0, max(a, b)) > (L.coverH - 52) || sentinelGone
        if next != solid { solid = next }
    }

    var body: some View {
        ZStack(alignment: .top) {

            Color.dyn(0xFFFFFF, 0x191919).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {

                    Color.clear
                        .frame(height: 1)
                        .background(
                            GeometryReader { g in
                                Color.clear.preference(key: OffsetKey.self,
                                                       value: g.frame(in: .global).minY)
                            }
                        )

                    GeometryReader { g in
                        let measured = max(0, g.frame(in: .named("momentsScroll")).minY - 1)
                        let extra = coverLocked ? coverLockPull : measured
                        coverView(extra)
                            .offset(y: coverLocked ? 0 : -extra)
                            .onAppear { coverPullBox.value = measured }
                            .onChange(of: measured) { coverPullBox.value = $0 }
                    }
                    .frame(height: L.coverH + (coverLocked ? coverLockPull : 0))
                    .zIndex(1)
                    momentList
                }
                .background(
                    GeometryReader { g in
                        Color.clear.preference(key: OffsetKey2.self,
                                               value: g.frame(in: .global).minY)
                    }
                )
            }
            .coordinateSpace(name: "momentsScroll")
            .onPreferenceChange(OffsetKey.self) { y in
                if scrollMetrics.baseTop == nil { scrollMetrics.baseTop = y }
                scrollMetrics.topY = y
                updateSolidState()
            }

            .simultaneousGesture(
                DragGesture(minimumDistance: 6).onChanged { _ in
                    tapLockUntil = Date().addingTimeInterval(0.35)

                    ScrollGate.shared.touch()
                }
            )
            .onPreferenceChange(OffsetKey2.self) { y in
                if scrollMetrics.baseBlock == nil { scrollMetrics.baseBlock = y }
                scrollMetrics.blockY = y
                updateSolidState()
            }

            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { v in
                        lastDragAt = Date()
                        guard !sentinelGone else { return }
                        let dy = v.translation.height
                        if dy > 0 {
                            pullY = min(140, dy)
                            if !pulling { spin = Double(pullY) * 3.2 }
                        } else if !pulling {
                            pullY = 0
                        }
                    }
                    .onEnded { _ in
                        lastDragAt = Date()
                        if pullY > 60 && !pulling { startPullRefresh() }
                        if !pulling { pullY = 0 }
                    }
            )
            .ignoresSafeArea(edges: .top)

            .task(id: pullY > 0 || pulling) {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    if Task.isCancelled { return }
                    if pulling {

                        if Date().timeIntervalSince(lastDragAt) > 10 {
                            CrashCatcher.note("朋友圈", "下拉刷新超过 10 秒没回来，先收球")
                            pulling = false
                            pullY = 0
                            spin = 0
                        }
                        continue
                    }
                    if pullY > 0 && Date().timeIntervalSince(lastDragAt) > 0.4 {
                        pullY = 0
                        spin = 0
                        return
                    }
                    if pullY <= 0 { return }
                }
            }

            navBar

            if pullY > 0 || pulling {
                ColorBall(size: 34, spin: spin)
                    .scaleEffect(0.72 + min(1, pullY / 90) * 0.28)
                    .offset(y: min(96, pullY * 0.8) + L.safeTop + 6)
                    .animation(.easeOut(duration: 0.12), value: pullY)
                    .allowsHitTesting(false)
                    .zIndex(30)
            }

            if let i = viewerIndex, !viewerPaths.isEmpty {

                PhotoPager(paths: viewerPaths, startIndex: i, showActions: true) {
                    viewerIndex = nil
                    tapLockUntil = Date().addingTimeInterval(0.6)
                }
                    .zIndex(40)
            }

        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()

        .navigationDestination(isPresented: $showGroupPage) {
            if let g = groupPage {
                MomentGroupPage(title: g.title, moments: g.moments)
            }
        }

        .navigationDestination(isPresented: $showNoticeList) {
            MomentNoticesView(onOpen: { n in openNotice(n) })
                .environmentObject(app)
        }
        .modifier(TapAvatarCard(cardUser: $cardUser))
        .hidesTabBar()

        .sheet(isPresented: Binding(get: { momentVideo != nil },
                                    set: { if !$0 { momentVideo = nil } })) {
            if let u = momentVideo { VideoPlayerSheet(url: u) }
        }
        .sheet(item: $commentsSheet) { moment in
            MomentCommentsSheet(moment: moment) {
                Task { await reload() }
            }
            .environmentObject(app)
        }
        .onAppear {
            scrollMetrics.baseTop = nil
            scrollMetrics.baseBlock = nil
            scrollMetrics.topY = 0
            scrollMetrics.blockY = 0
            sentinelGone = false
            solid = false
        }
        .task {

            if moments.isEmpty, target == nil, !mineOnly {
                let cached = LocalStore.cachedMoments(userId: app.me?.id ?? "")
                if !cached.isEmpty {
                    moments = cached
                    rebuildFoldRows(cached)
                }
            }
            await reload()
        }
        .onChange(of: moments) { fresh in
            rebuildFoldRows(fresh)
        }

        .onChange(of: realtime.event) { _ in
            if realtime.event.type == "profile", let user = realtime.event.user,
               user.id == target?.id {
                liveTarget = user
            }

            let t = realtime.event.type.lowercased()
            guard t.contains("moment") || t.contains("like") || t.contains("comment") else { return }
            Task { await pollNewMoments() }
        }
        .task {
            if liveTarget == nil { liveTarget = target }

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                if Task.isCancelled { break }
                await pollNewMoments()
            }
        }

        .confirmationDialog(Tr("更换相册封面"), isPresented: $coverMenu, titleVisibility: .visible) {
            Button(Tr("从手机相册选择")) { showCoverPhoto = true }
            Button(Tr("拍一张")) { showCoverCamera = true }
            Button(Tr("取消"), role: .cancel) { }
        }
        .sheet(isPresented: $showCoverCamera) {
            CameraPicker { image in coverDraft = image }
        }

        .sheet(isPresented: Binding(get: { coverDraft != nil },
                                    set: { if !$0 { coverDraft = nil } })) {
            if let img = coverDraft {
                CoverAdjustSheet(image: img,
                                 frameSize: CGSize(width: L.width, height: L.coverH)) { out in
                    changeCover(out)
                    coverDraft = nil
                }
            }
        }

        .sheet(isPresented: $showVideoShoot, onDismiss: { showVideoShoot = false }) {
            CameraVideoPicker { url in
                Task {
                    await prepareVideo(url)
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    posting = true
                }
            }
        }
        .sheet(isPresented: $showCoverPhoto) {
            PhotoPicker { image in coverDraft = image }
        }
        .sheet(isPresented: $posting) { publishSheet }

        .confirmationDialog(Tr("这条动态"), isPresented: Binding(
            get: { actionMoment != nil },
            set: { if !$0 { actionMoment = nil } }
        ), titleVisibility: .visible) {
            if let m = actionMoment {
                if m.likedByMe == true {
                    Button(Tr("取消赞")) { like(m) }
                } else {
                    Button(Tr("赞")) { like(m) }
                }
                Button(Tr("评论")) {
                    commentsSheet = m
                }
                if m.mine == true {
                    Button(m.pinned == true ? Tr("取消置顶") : Tr("置顶")) {
                        togglePin(m)
                    }
                    Button(Tr("删除"), role: .destructive) { remove(m) }
                }
            }
            Button(Tr("取消"), role: .cancel) { actionMoment = nil }
        }
    }

    private func toggleCoverLock() {
        guard coverEditable else { return }
        withAnimation(.easeOut(duration: 0.3)) {
            if coverLocked {
                coverLocked = false
                coverLockPull = 0
            } else {
                coverLockPull = min(420, max(240, coverPullBox.value))
                coverLocked = true
            }
        }
    }

    private func coverView(_ extra: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            if cover.isEmpty {

                if UIImage(named: "moments-cover") != nil {

                    Image("moments-cover")
                        .resizable()
                        .scaledToFill()
                        .frame(width: L.width, height: L.coverH + extra)
                        .clipped()
                } else {
                    LinearGradient(colors: [Color(hex: 0x0D3B66), Color(hex: 0x1D6FB8), Color(hex: 0x0099FF)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            } else {
                RemoteImage(path: cover, icon: "photo", maxSide: 2560)
                    .id(cover)
            }

            if cover.isEmpty && coverEditable {
                VStack(spacing: 10) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 46, height: 46)
                        .background {
                            ZStack {
                                GlassBackground(shape: Circle(), opacity: 0.92,
                                                edgeAlpha: 0.74, seed: 0.36)
                                Circle().fill(Color.black.opacity(0.18))
                            }
                        }

                    Text(Tr("设置生活圈封面"))
                        .font(pf(16.5, .semibold))
                        .foregroundColor(.white)

                    Text(Tr("从相册选一张图，让朋友一眼记住你"))
                        .font(pf(12.2))
                        .foregroundColor(.white.opacity(0.82))
                        .multilineTextAlignment(.center)

                    Button {
                        coverMenu = true
                    } label: {
                        Text(Tr("立即设置"))
                            .font(pf(14.5, .semibold))
                            .foregroundColor(.white)
                            .frame(width: 118, height: 38)
                            .background {
                                ZStack {
                                    GlassBackground(shape: Capsule(style: .continuous),
                                                    opacity: 0.96,
                                                    edgeAlpha: 0.82,
                                                    seed: 0.62)
                                    Capsule().fill(C.green.opacity(0.26))
                                }
                            }
                            .overlay {
                                Capsule(style: .continuous)
                                    .stroke(Color.white.opacity(0.42), lineWidth: 0.8)
                            }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .frame(maxWidth: 286)
                .background {
                    ZStack {
                        GlassBackground(shape: RoundedRectangle(cornerRadius: 22, style: .continuous),
                                        opacity: 0.82,
                                        edgeAlpha: 0.58,
                                        shadow: true,
                                        seed: 0.48)
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.black.opacity(0.24))
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.24), lineWidth: 0.7)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 24)
                .zIndex(4)
            }

            Group {
                if scheme == .dark {
                    HarmonyDarkMask(strength: 0.94)
                        .mask(
                            LinearGradient(
                                colors: [Color.black, Color.black.opacity(0.70), Color.clear],
                                startPoint: .top, endPoint: .bottom)
                        )
                } else {
                    LinearGradient(colors: [Color.black.opacity(max(0, UIConfig.num("momentTopMask", 0.20))),
                                            Color.black.opacity(0)],
                                   startPoint: .top, endPoint: .bottom)
                }
            }
                .frame(height: max(L.safeTop + 56, UIConfig.num("momentTopMaskH", 150)))
                .frame(maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)

            Group {
                if scheme == .dark {
                    HarmonyDarkMask(strength: 0.96)
                        .mask(
                            LinearGradient(
                                colors: [Color.clear, Color.black.opacity(0.78), Color.black],
                                startPoint: .top, endPoint: .bottom)
                        )
                } else {
                    LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.22),
                                            Color.black.opacity(0.36)],
                                   startPoint: .top, endPoint: .bottom)
                }
            }
                .frame(height: L.coverH * 0.62)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)

            if coverEditable {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { toggleCoverLock() }
                    .zIndex(2)
            }

            if coverEditable && !cover.isEmpty {
                HStack {
                    Button {
                        coverMenu = true
                    } label: {
                        Text(Tr("换封面"))
                            .font(pf(12.5, .medium))
                            .foregroundColor(.white)
                            .frame(width: 88, height: 32)
                            .background {
                                if coverLocked {
                                    Capsule()
                                        .fill(.ultraThinMaterial)
                                        .overlay(Capsule().fill(Color.black.opacity(0.12)))
                                } else {
                                    Capsule().fill(Color.black.opacity(0.44))
                                }
                            }
                            .overlay(Capsule().stroke(Color.white.opacity(0.24), lineWidth: 0.7))
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 12)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .zIndex(4)
            }

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(owner?.name ?? "")
                        .font(pf(17, .semibold))
                        .foregroundColor(.white)
                        .shadow(color: Color.black.opacity(0.55), radius: 4, x: 0, y: 1)
                        .lineLimit(1)
                }
                .padding(.bottom, 24)
                VStack(spacing: 4) {
                    Avatar(path: owner?.avatarPath ?? "", size: L.coverAvatar, radius: 8)
                        .shadow(color: Color.black.opacity(0.28), radius: 5, x: 0, y: 2)
                    if let sign = signature {
                        Text(sign)
                            .font(pf(12.5))
                            .foregroundColor(C.label)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.dyn(0xFFFFFF, 0x000000).opacity(0.62)))
                            .frame(width: L.coverAvatar + 56, alignment: .center)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 16)
            .offset(y: 21)
            .allowsHitTesting(false)
        }
        .frame(height: L.coverH + extra)
        .zIndex(1)

        .contentShape(Rectangle())
    }

    private func momentRow(_ moment: Moment) -> some View {
        MomentNoteCard(
            moment: moment,
            columnWidth: noteColumnWidth,
            onOpenComments: { commentsSheet = moment },
            onOpenVideo: { url in momentVideo = url },
            onOpenAvatar: { user in cardUser = user },
            onLike: { like(moment) },
            onMore: { actionMoment = moment }
        )
    }

    private var noteColumnWidth: CGFloat {
        max(138, (L.width - 16 - 10) / 2)
    }

    private func noteColumns() -> ([Moment], [Moment]) {
        let pinned = moments.filter { $0.pinned == true }
        let regular = moments.filter { $0.pinned != true }
        var left: [Moment] = []
        var right: [Moment] = []
        var leftH: CGFloat = 0
        var rightH: CGFloat = 0
        for moment in pinned + regular {
            let h = estimatedNoteHeight(moment)
            if leftH <= rightH {
                left.append(moment)
                leftH += h + 14
            } else {
                right.append(moment)
                rightH += h + 14
            }
        }
        return (left, right)
    }

    private func estimatedNoteHeight(_ moment: Moment) -> CGFloat {
        let width = noteColumnWidth
        var media: CGFloat = 0
        if !(moment.video ?? "").isEmpty {
            let w = CGFloat(max(1, moment.videoW ?? 4))
            let h = CGFloat(max(1, moment.videoH ?? 5))
            media = min(width * 1.48, max(width * 0.68, width * h / w))
        } else if let first = (moment.images ?? []).first,
                  let size = moment.imageSizes?[first], size.count >= 2,
                  size[0] > 0, size[1] > 0 {
            media = min(width * 1.50, max(width * 0.72,
                                          width * CGFloat(size[1]) / CGFloat(size[0])))
        } else if !(moment.images ?? []).isEmpty {
            media = width * 1.16
        }
        let text = moment.content?.isEmpty == false ? CGFloat(64) : 10
        return max(92, media + text + 55)
    }

    private func dayLabel(_ s: String?) -> String {
        guard let d = TimeFmt.date(s) else { return "" }
        let cal = Calendar.current
        if cal.isDateInToday(d) { return Tr("今天") }
        if cal.isDateInYesterday(d) { return Tr("昨天") }
        let days = cal.dateComponents([.day],
                                      from: cal.startOfDay(for: d),
                                      to: cal.startOfDay(for: Date())).day ?? 99
        if days == 2 { return Tr("前天") }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = cal.isDate(d, equalTo: Date(), toGranularity: .year) ? "M月d日" : "yyyy年M月d日"
        return f.string(from: d)
    }

    private func dayHeader(_ t: String) -> some View {
        HStack {
            Text(t)
                .font(pf(13))
                .foregroundColor(C.subLabel)
            Spacer(minLength: 0)
        }
        .padding(.top, 14)
        .padding(.bottom, 2)
    }

    private struct FoldRow: Identifiable {
        var id: String { first.id }
        var first: Moment
        var rest: [Moment]
    }

    private var foldRows: [FoldRow] { foldRowsCache }

    private func rebuildFoldRows(_ source: [Moment]) {
        let timeline = source.filter { $0.pinned != true }
        let win = UIConfig.num("momentFoldWindow", 10) * 60_000
        guard win > 0 else {
            foldRowsCache = timeline.map { FoldRow(first: $0, rest: []) }
            return
        }
        var out: [FoldRow] = []
        var i = 0
        while i < timeline.count {
            let head = timeline[i]
            var rest: [Moment] = []
            let headAt = TimeFmt.date(head.createdAt) ?? Date.distantPast
            var j = i + 1
            while j < timeline.count {
                let nxt = timeline[j]

                guard let aid = head.authorId, !aid.isEmpty, nxt.authorId == aid else { break }
                let nextAt = TimeFmt.date(nxt.createdAt) ?? Date.distantPast

                if abs(headAt.timeIntervalSince(nextAt)) > win / 1000 { break }
                rest.append(nxt)
                j += 1
            }
            out.append(FoldRow(first: head, rest: rest))
            i = j
        }
        foldRowsCache = out
    }

    private func packedRow(_ row: FoldRow) -> some View {
        Button {

            groupPage = MomentGroup(id: row.first.id,
                                    title: row.first.author?.name ?? Tr("朋友圈"),
                                    moments: row.rest)
            showGroupPage = true
        } label: {
            HStack(spacing: 6) {
                Text(Tr("余下") + " \(row.rest.count) " + Tr("条"))
                    .font(pf(14))
                    .foregroundColor(Color(hex: 0x576B95))
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: 0x576B95))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var momentList: some View {
        let lanes = noteColumns()
        return LazyVStack(spacing: 0) {
            Color.clear
                .frame(height: 1)
                .onAppear {
                    sentinelGone = false
                    updateSolidState()
                }
                .onDisappear {
                    sentinelGone = true
                    updateSolidState()
                }

            HStack(alignment: .top, spacing: 10) {
                LazyVStack(spacing: 14) {
                    ForEach(lanes.0) { moment in
                        momentRow(moment)
                    }
                }
                .frame(width: noteColumnWidth)

                LazyVStack(spacing: 14) {
                    ForEach(lanes.1) { moment in
                        momentRow(moment)
                    }
                }
                .frame(width: noteColumnWidth)
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.horizontal, 8)

            if hasMoreMoments {
                Text(loadingMore ? "正在加载…" : " ")
                    .font(pf(14))
                    .foregroundColor(C.subLabel)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .onAppear {
                        Task { await loadMoreMoments() }
                    }
            } else if momentTotal > 0 {
                Text(Tr("没有更多了"))
                    .font(pf(13))
                    .foregroundColor(C.subLabel)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }

            if !mineOnly, !(feedUserId ?? "").isEmpty, (feedUserId ?? "") != (app.me?.id ?? ""),
               feedRange == "3d" || feedRange == "6m" {
                Text(feedRange == "3d" ? Tr("朋友仅展示最近三天的朋友圈")
                                       : Tr("朋友仅展示最近半年的朋友圈"))
                    .font(pf(13))
                    .foregroundColor(C.subLabel)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
        }
        .padding(.top, 60)
        .padding(.bottom, max(42, L.safeBottom + 20))
        .frame(maxWidth: .infinity)
        .background(C.cardBg)
        .offset(y: 0)
        .zIndex(0)
    }

    private var navBar: some View {
        ZStack {

            if solid {
                Text(Tr("朋友圈"))
                    .font(pf(UIConfig.num("navTitle", 17)))
                    .foregroundColor(C.label)
            }

            HStack(spacing: 0) {

                Button { dismiss() } label: {
                    FlexIcon(custom: IconOverrides.custom("nav.back"),
                             size: 20, color: solid ? C.label : .white,
                             symbol: "chevron.left", weight: .medium)
                        .frame(width: 56, height: L.navH)
                        .shadow(color: solid ? .clear : Color.black.opacity(0.55), radius: 2, x: 0, y: 1)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                ZStack(alignment: .topTrailing) {
                    Button { showNoticeList = true } label: {
                        FlexIcon(custom: IconOverrides.custom("nav.momentsBell"), size: 21,
                                 color: solid ? C.label : .white, symbol: "bell", weight: .medium)
                            .frame(width: 40, height: 44)
                            .shadow(color: solid ? .clear : Color.black.opacity(0.55), radius: 2, x: 0, y: 1)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if app.momentNoticeUnread > 0 {
                        Circle().fill(C.red)
                            .frame(width: 8, height: 8)
                            .offset(x: -7, y: 9)
                    }
                }

                SVGIcon(markup: I.camera, size: 26, color: solid ? C.label : .white)
                    .frame(width: 44, height: 44)
                    .shadow(color: solid ? .clear : Color.black.opacity(0.55), radius: 2, x: 0, y: 1)
                    .contentShape(Rectangle())
                    .onTapGesture { openComposer() }
                    .onLongPressGesture(minimumDuration: 0.45, maximumDistance: 26) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showVideoShoot = true
                    }
                .padding(.trailing, 6)
                .contentShape(Rectangle())
            }
        }
        .frame(height: L.navH)

        .background { TopGlassBar(scrolled: solid ? 999 : 0,
                                  fallback: Color.dyn(0xFFFFFF, 0x191919)) }
        .zIndex(25)
        .allowsHitTesting(true)
    }

    private func openPhoto(_ path: String, in moment: Moment) {
        guard Date() >= tapLockUntil else { return }
        guard !(moment.images ?? []).isEmpty else { return }
        _ = path
        commentsSheet = moment
    }

    private func openNotice(_ n: MomentNotice) {
        let mid = n.momentId ?? ""
        guard !mid.isEmpty else { return }
        if let hit = moments.first(where: { $0.id == mid }) { openMoment(hit); return }
        Task {
            await pollNewMoments()
            if let hit = moments.first(where: { $0.id == mid }) {
                openMoment(hit)
            } else {
                app.show(Tr("那条动态在更下面的记录里，往下翻就能看到"))
            }
        }
    }

    private func openMoment(_ m: Moment) {
        if let paths = m.images, !paths.isEmpty {
            viewerPaths = paths
            viewerIndex = 0
            return
        }
        if let v = m.video, !v.isEmpty {
            let full = v.hasPrefix("http") ? v : API.shared.base + v
            if let u = URL(string: full) { momentVideo = u; return }
        }
        app.show(m.content ?? "")
    }

    private var publishSheet: some View {
        VStack(spacing: 0) {

            NavBar(title: Tr("发表"), back: { closeComposer() }) {
                Button { publish() } label: {
                    Text(uploading ? Tr("发布中…") : Tr("发表"))
                        .font(pf(17, .semibold))
                        .foregroundColor(canPublish ? C.green : C.subLabel)
                        .frame(height: L.navH)
                        .padding(.trailing, 16)
                }
                .buttonStyle(.plain)
                .disabled(!canPublish)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    ZStack(alignment: .topLeading) {
                        if draft.isEmpty {
                            Text(Tr("这一刻的想法…"))
                                .font(pf(17))
                                .foregroundColor(C.subLabel)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $draft)
                            .font(pf(17))
                            .frame(minHeight: 104)
                            .scrollContentBackground(.hidden)
                    }
                    .padding(.horizontal, 12)
                    .background(C.cardBg)

                    composerGrid
                        .padding(.horizontal, 16)
                        .padding(.top, 14)

                    VStack(spacing: 0) {
                        HairLine(inset: 16)
                        composerRow(icon: "location", title: Tr("所在位置"),
                                    value: draftLocation.isEmpty ? Tr("不显示位置") : draftLocation) {
                            showLocation = true
                        }
                        HairLine(inset: 16)
                        composerRow(icon: "eye", title: Tr("谁可以看"), value: visibilityName) {
                            showVisibility = true
                        }
                        HairLine(inset: 16)
                        composerRow(icon: "at", title: Tr("提醒谁看"),
                                    value: remindIds.isEmpty ? "" : "\(remindIds.count) 个人") {
                            pickMode = "at"
                            showPick = true
                        }
                    }
                    .background(C.cardBg)
                    .padding(.top, 18)
                }
                .padding(.bottom, 30)
            }
        }

        .background(C.pageBg.ignoresSafeArea(edges: .bottom))
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { posting = false }
        .hidesTabBar()

            .sheet(isPresented: $showMomentAlbum, onDismiss: { showMomentAlbum = false }) {
                MomentPicker(limit: max(1, 9 - picked.count)) { r in
                    switch r {
                    case .images(let imgs):
                        let room = 9 - picked.count
                        if imgs.count > room { app.show("最多 9 张图，还能再加 \(room) 张") }
                        picked.append(contentsOf: imgs.prefix(max(0, room)))
                    case .video(let url):
                        Task { await prepareVideo(url) }
                    }
                }
            }
            .confirmationDialog(Tr("谁可以看"), isPresented: $showVisibility, titleVisibility: .visible) {
                Button(Tr("公开（所有好友可见）")) { visibility = "public" }
                Button(Tr("私密（仅自己可见）")) { visibility = "private" }
                Button(Tr("部分可见…")) { visibility = "partial"; pickMode = "partial"; showPick = true }
                Button(Tr("不给谁看…")) { visibility = "exclude"; pickMode = "exclude"; showPick = true }
                Button(Tr("取消"), role: .cancel) { }
            }
            .sheet(isPresented: $showPick) { friendPickSheet }
            .sheet(isPresented: $showLocation) {
                PlacePickerSheet(text: $draftLocation)
            }

            .sheet(isPresented: $showCamera) {
                CameraPicker(onPick: { image in
                    picked = [image]
                }, onVideo: { url in
                    Task { await prepareVideo(url) }
                })
            }

            .alert(Tr("不保留这次编辑？"), isPresented: $confirmDiscard) {
                Button(Tr("继续编辑"), role: .cancel) { }
                Button(Tr("不保留"), role: .destructive) { resetComposer() }
            }
    }

    private var canPublish: Bool {
        !uploading && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                       || !picked.isEmpty || pickedVideo != nil)
    }

    private var composerGrid: some View {
        let gap: CGFloat = 6
        let side = (L.width - 32 - gap * 2) / 3
        return LazyVGrid(columns: Array(repeating: GridItem(.fixed(side), spacing: gap), count: 3),
                         alignment: .leading, spacing: gap) {

            if pickedVideo != nil {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        if let c = videoCover {
                            Image(uiImage: c)
                                .resizable()
                                .scaledToFill()
                        } else {
                            C.searchBg
                        }
                        Color.black.opacity(videoProgress > 0.01 ? 0.42 : 0.22)
                        VStack(spacing: 6) {
                            if videoProgress > 0.01 {

                                ZStack {
                                    Circle().stroke(Color.white.opacity(0.30), lineWidth: 4)
                                        .frame(width: 50, height: 50)
                                    Circle()
                                        .trim(from: 0, to: max(0.04, min(1, videoProgress)))
                                        .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                        .rotationEffect(.degrees(-90))
                                        .frame(width: 50, height: 50)
                                    Text("\(Int(min(1, videoProgress) * 100))%")
                                        .font(.system(size: 12.5, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                            } else {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(.white.opacity(0.95))
                            }
                            if videoSeconds > 0, videoProgress <= 0.01 {
                                Text(String(format: "%02d:%02d", videoSeconds / 60, videoSeconds % 60))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .frame(width: side, height: side)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    if !uploading {
                        Button {
                            pickedVideo = nil
                            videoCover = nil
                            videoSeconds = 0
                            videoWH = nil
                            videoProgress = 0
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(Color.black.opacity(0.6)))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 6, y: -6)
                    }
                }
            }
            ForEach(picked.indices, id: \.self) { i in
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: picked[i])
                        .resizable()
                        .scaledToFill()
                        .frame(width: side, height: side)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .contentShape(Rectangle())
                        .onDrag {
                            dragIndex = i
                            return NSItemProvider(object: String(i) as NSString)
                        }
                        .onDrop(of: [UTType.text],
                                delegate: MomentGridDrop(index: i, items: $picked, dragIndex: $dragIndex))
                    Button {
                        picked.remove(at: i)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color.black.opacity(0.6)))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 6, y: -6)
                }
            }
            if picked.count < 9 && pickedVideo == nil {

                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(C.searchBg)
                    Image(systemName: "plus")
                        .font(.system(size: 26, weight: .light))
                        .foregroundColor(C.subLabel)
                }
                .frame(width: side, height: side)
                .contentShape(Rectangle())
                .onTapGesture { showMomentAlbum = true }
                .onLongPressGesture(minimumDuration: 0.45, maximumDistance: 26) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showCamera = true
                }
            }
        }
    }

    private func composerRow(icon: String, title: String, value: String,
                             tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundColor(C.label)
                    .frame(width: 20)
                Text(title).font(pf(16)).foregroundColor(C.label)
                Spacer(minLength: 8)
                if !value.isEmpty {
                    Text(value).font(pf(15)).foregroundColor(C.subLabel).lineLimit(1)
                }
                Chevron(size: 9, line: 1.6)
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var visibilityName: String {
        switch visibility {
        case "private": return "仅自己"
        case "partial": return "部分可见"
        case "exclude": return "不给谁看"
        default: return "公开"
        }
    }

    private var friendPickSheet: some View {
        NavigationStack {
            List {
                ForEach(app.contacts) { u in
                    Button {
                        if pickMode == "at" {
                            if remindIds.contains(u.id) { remindIds.remove(u.id) } else { remindIds.insert(u.id) }
                        } else if pickMode == "partial" {
                            if visibleTo.contains(u.id) { visibleTo.remove(u.id) } else { visibleTo.insert(u.id) }
                        } else {
                            if hiddenFrom.contains(u.id) { hiddenFrom.remove(u.id) } else { hiddenFrom.insert(u.id) }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Avatar(path: u.avatarPath, size: 38, radius: 6)
                            Text(u.name).font(pf(16)).foregroundColor(C.label)
                            Spacer()
                            let on = pickMode == "at" ? remindIds.contains(u.id)
                                : (pickMode == "partial" ? visibleTo.contains(u.id) : hiddenFrom.contains(u.id))
                            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(on ? C.green : C.subLabel)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle(pickMode == "at" ? "提醒谁看"
                             : (pickMode == "partial" ? "选择可见的好友" : "选择不看的好友"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button(Tr("好了")) { showPick = false } } }
        }
    }

    private func startPullRefresh() {
        pulling = true
        spinTask?.cancel()
        spinTask = Task { @MainActor in
            var angle = spin
            let started = Date()
            while !Task.isCancelled {
                angle += 14
                spin = angle
                try? await Task.sleep(nanoseconds: 16_000_000)
                if Date().timeIntervalSince(started) > 1.0 { break }
            }

            let finished = await withPullTimeout(seconds: 6) {
                if self.coverEditable { self.app.me = try? await API.shared.me() }
                await self.reload()
            }
            if !finished {
                CrashCatcher.note("朋友圈", "下拉刷新的网络请求超 6 秒，先把彩球收掉")
            }
            pullY = 0
            spin = 0
            pulling = false
        }
    }

    private func withPullTimeout(seconds: Double,
                                 _ work: @escaping @MainActor () async -> Void) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask { await work(); return true }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    private func reload() async {
        if let feed = try? await API.shared.momentsFeed(limit: 30, userId: feedUserId) {
            moments = feed.moments
            hasMoreMoments = feed.hasMore
            momentTotal = feed.total
            feedRange = feed.range
            app.momentNoticeUnread = feed.noticeUnread

            if target == nil && !mineOnly {
                LocalStore.saveMoments(moments, userId: app.me?.id ?? "")
            }
        } else {

            let cached = LocalStore.cachedMoments(userId: app.me?.id ?? "")
            moments = cached.isEmpty ? app.moments : cached
            hasMoreMoments = false
        }

        if target == nil {
            await API.shared.markMomentsSeen()
            app.momentsUnread = 0
        }
    }

    private func loadMoreMoments() async {
        guard hasMoreMoments, !loadingMore, let last = moments.last else { return }
        loadingMore = true
        if let feed = try? await API.shared.momentsFeed(limit: 30, before: last.createdAt, beforeId: last.id,
                                                        userId: feedUserId) {
            let known = Set(moments.map { $0.id })
            moments.append(contentsOf: feed.moments.filter { !known.contains($0.id) })
            hasMoreMoments = feed.hasMore && !feed.moments.isEmpty
        } else {
            hasMoreMoments = false
        }
        loadingMore = false
    }

    private func pollNewMoments() async {
        guard let feed = try? await API.shared.momentsFeed(limit: 30, userId: feedUserId) else { return }
        let known = Set(moments.map { $0.id })
        let fresh = feed.moments.filter { !known.contains($0.id) }
        if !fresh.isEmpty { moments.insert(contentsOf: fresh, at: 0) }
        momentTotal = feed.total
        if moments.count <= 30 { hasMoreMoments = feed.hasMore }
    }

    private func publish() {
        uploading = true
        Task {

            if let v = pickedVideo {
                do {
                    DispatchQueue.main.async { videoProgress = 0.02 }
                    var file = v
                    var from = 0.0
                    if await MediaTool.needsCompress(v) {
                        if let small = await MediaTool.compress(v, onProgress: { p in
                            DispatchQueue.main.async { videoProgress = min(0.45, p * 0.45) }
                        }) { file = small; from = 0.45 }
                    }
                    guard let up = await MediaTool.upload(file, onProgress: { p in
                        DispatchQueue.main.async { videoProgress = from + p * (1 - from) }
                    }, skipServerTranscode: true) else {
                        throw APIError.message("视频上传失败")
                    }

                    var cp = ""
                    let coverImg: UIImage?
                    if let c = videoCover { coverImg = c } else { coverImg = await MediaTool.firstFrame(file) }
                    if let c = coverImg { cp = (try? await API.shared.uploadCover(image: c)) ?? "" }
                    let wh = videoWH
                    try await API.shared.postMoment(content: draft, images: [],
                                                    video: up, videoCover: cp,
                                                    videoSeconds: videoSeconds,
                                                    videoW: wh?.w ?? 0, videoH: wh?.h ?? 0,
                                                    visibility: visibility,
                                                    visibleTo: Array(visibleTo),
                                                    hiddenFrom: Array(hiddenFrom),
                                                    location: draftLocation)
                    await remindFriends()
                    app.show(Tr("已发表"))
                } catch {
                    app.show((error as? APIError)?.errorDescription ?? "视频发表失败")
                }
                resetComposer()
                await reload()
                await app.loadMoments()
                return
            }
            var urls: [String] = []
            var sizes: [String: [Int]] = [:]

            var mResults: [(idx: Int, url: String, w: Int, h: Int, data: Data)] = []
            await withTaskGroup(of: (Int, String, Int, Int, Data).self) { group in
                var nextIdx = 0
                func addUpload(_ i: Int) {
                    let img = picked[i]
                    let w = Int(img.size.width.rounded()), h = Int(img.size.height.rounded())
                    group.addTask {
                        let up = try? await API.shared.uploadImageForSend(img, original: false)
                        return (i, up?.url ?? "", w, h, up?.data ?? Data())
                    }
                }
                while nextIdx < min(3, picked.count) { addUpload(nextIdx); nextIdx += 1 }
                for await r in group {
                    if !r.1.isEmpty { mResults.append((idx: r.0, url: r.1, w: r.2, h: r.3, data: r.4)) }
                    if nextIdx < picked.count { addUpload(nextIdx); nextIdx += 1 }
                }
            }
            for r in mResults.sorted(by: { $0.idx < $1.idx }) {
                urls.append(r.url)

                sizes[r.url] = [r.w, r.h]
                let img = picked[r.idx]
                ImageStore.shared.put(r.url, img)
                ImageSizeCache.put(r.url, ImageBubble.thumb(img.size))
                if !r.data.isEmpty {
                    let bytes = r.data
                    Task.detached(priority: .utility) {
                        ImageStore.shared.diskWrite(r.url, bytes)
                        LocalStore.keep(r.url, data: bytes)
                    }
                }
            }
            do {
                try await API.shared.postMoment(content: draft, images: urls,
                                                imageSizes: sizes,
                                                visibility: visibility,
                                                visibleTo: Array(visibleTo),
                                                hiddenFrom: Array(hiddenFrom),
                                                location: draftLocation)
                await remindFriends()
                app.show(Tr("已发表"))
            } catch {
                app.show((error as? APIError)?.errorDescription ?? "发表失败")
            }
            resetComposer()
            await reload()
            await app.loadMoments()
        }
    }

    private func remindFriends() async {
        guard !remindIds.isEmpty else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let tip = "我在朋友圈提到了你" + (text.isEmpty ? "" : "：" + String(text.prefix(30)))
        for fid in remindIds {
            if let chat = try? await API.shared.openDirect(userId: fid) {
                _ = try? await API.shared.send(chatId: chat.id, text: tip)
            }
        }
        await app.loadChats()
    }

    private func resetComposer() {
        draft = ""
        picked = []
        pickedVideo = nil
        videoCover = nil
        videoSeconds = 0
        videoWH = nil
        videoProgress = 0
        visibility = "public"
        visibleTo = []
        hiddenFrom = []
        draftLocation = ""
        remindIds = []
        uploading = false
        posting = false
        tapLockUntil = Date().addingTimeInterval(0.6)
    }

    private func openComposer() {
        resetComposer()
        posting = true
    }

    private func closeComposer() {
        let hasStuff = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !picked.isEmpty || pickedVideo != nil
        if hasStuff { confirmDiscard = true } else { resetComposer() }
    }

    private func prepareVideo(_ url: URL) async {
        let cover = await MediaTool.firstFrame(url)
        let secs = await MediaTool.seconds(url)
        let wh = await MediaTool.aspect(url)
        await MainActor.run {
            pickedVideo = url
            videoCover = cover
            videoSeconds = secs
            videoWH = wh
            videoProgress = 0
            picked = []
        }
    }

    private func changeCover(_ image: UIImage) {
        Task {
            uploading = true
            guard let url = try? await API.shared.uploadCover(image: image) else {
                uploading = false
                app.show(Tr("封面没保存上，再试一次"))
                return
            }

            let previous = app.me?.momentCover
            if var me = app.me {
                me.momentCover = url
                app.me = me
            }
            do {
                try await API.shared.updateMeChecked(["momentCover": url])
                app.show(Tr("封面换好了"))
            } catch {
                if var me = app.me, me.momentCover == url {
                    me.momentCover = previous
                    app.me = me
                }
                app.show(Tr("封面没保存上，再试一次"))
            }
            uploading = false
        }
    }

    private func like(_ moment: Moment) {
        Task {
            if let err = await API.shared.likeMoment(id: moment.id) {
                app.show(err)
            } else {
                await reload()
            }
        }
    }

    private func togglePin(_ moment: Moment) {
        let next = !(moment.pinned == true)
        Task {
            await API.shared.pinMoment(id: moment.id, pinned: next)
            await reload()
            app.show(next ? Tr("已置顶，会固定显示在最上面") : Tr("已取消置顶"))
        }
    }

    private func deleteComment(_ momentId: String, _ commentId: String) {
        Task {
            if let err = await API.shared.deleteMomentComment(momentId: momentId, commentId: commentId) {
                app.show(err)
            } else {
                app.show(Tr("评论已删除"))
            }
            await reload()
        }
    }

    private func remove(_ moment: Moment) {
        Task {
            if let err = await API.shared.deleteMoment(id: moment.id) {
                app.show(err)
            } else {
                await reload()
                await app.loadMoments()
                app.show(Tr("已删除"))
            }
        }
    }
}

struct MomentGroup: Identifiable {
    var id: String
    var title: String
    var moments: [Moment]
}

struct MomentGroupPage: View {
    let title: String
    let moments: [Moment]
    @Environment(\.dismiss) private var dismiss
    @State private var viewerPaths: [String] = []
    @State private var viewerIndex: Int?

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                NavBar(title: title, back: { dismiss() })
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(moments.enumerated()), id: \.element.id) { i, m in
                            MomentRow(moment: m, onOpenImage: { p in open(p, in: m) })
                                .padding(.horizontal, L.momentPadH)
                            if i < moments.count - 1 {
                                HairLine(inset: L.momentPadH + L.momentAvatar + 9)
                            }
                        }
                        Spacer().frame(height: 30)
                    }
                }
                .background(Color.dyn(0xFFFFFF, 0x191919))
            }

            if let i = viewerIndex, !viewerPaths.isEmpty {
                PhotoPager(paths: viewerPaths, startIndex: i, showActions: true) {
                    viewerIndex = nil
                }
                .zIndex(40)
            }
        }
        .background(C.pageBg.ignoresSafeArea(edges: .top))
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
    }

    private func open(_ path: String, in m: Moment) {
        let all = m.images ?? []
        guard !all.isEmpty else { return }
        viewerPaths = all
        viewerIndex = all.firstIndex(of: path) ?? 0
    }
}

struct MomentRow: View {
    let moment: Moment
    var onMore: (() -> Void)? = nil

    var onOpenImage: ((String) -> Void)? = nil

    var onOpenVideo: ((URL) -> Void)? = nil

    var onOpenAvatar: ((User) -> Void)? = nil

    var onDeleteComment: ((String) -> Void)? = nil

    var myId: String = ""

    var onLike: (() -> Void)? = nil
    var onComment: (() -> Void)? = nil
    var onDeleteMoment: (() -> Void)? = nil

    var onReplyComment: ((String, String) -> Void)? = nil

    var onTogglePin: (() -> Void)? = nil

    @State private var deletingComment: String?

    @State private var heartBurst = false

    @State private var showActions = false

    private var images: [String] { moment.images ?? [] }
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Avatar(path: moment.author?.avatarPath ?? "", size: L.momentAvatar, radius: 5)
                .contentShape(Rectangle())
                .onTapGesture { if let u = moment.author { onOpenAvatar?(u) } }

            VStack(alignment: .leading, spacing: 0) {
                Text(moment.author?.name ?? "")

                    .font(pf(17.3, .medium))
                    .foregroundColor(C.link)

                if let content = moment.content, !content.isEmpty {

                    Text(RichText.linkified(content))

                        .font(pf(17.3))
                        .foregroundColor(C.label)
                        .lineSpacing(1)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }

                if moment.pinned == true {
                    HStack(spacing: 3) {
                        Image(systemName: "pin.fill").font(.system(size: 10))
                        Text(Tr("置顶")).font(pf(12.5))
                    }
                    .foregroundColor(C.subLabel)
                    .padding(.top, 6)
                }

                if !images.isEmpty || !(moment.video ?? "").isEmpty {
                    grid
                        .padding(.top, 13)
                }

                HStack(spacing: 14) {
                    Text(TimeFmt.ago(moment.createdAt))
                        .font(pf(14.5))

                        .foregroundColor(Color.dyn(0xB2B2B2, 0x8A8A8E))

                    Spacer()

                    Button {
                        withAnimation(.easeOut(duration: 0.14)) { showActions.toggle() }
                    } label: {
                        HStack(spacing: 2.6) {
                            ForEach(0..<3, id: \.self) { _ in
                                Circle()
                                    .fill((moment.likedByMe == true) ? Color(hex: 0xFF6B6B) : Color.dyn(0x7F7F7F, 0xD8D8D8))
                                    .frame(width: 3.4, height: 3.4)
                            }
                        }
                        .frame(width: 28, height: 19)

                        .background {
                            ZStack {
                                GlassBackground(shape: RoundedRectangle(cornerRadius: 4, style: .continuous),
                                                opacity: UIConfig.num("momentBtnGlass", 0.85),
                                                edgeAlpha: UIConfig.num("momentBtnEdge", 0.40),
                                                shadow: false,
                                                seed: 0.70)
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(C.cardBg.opacity(0.32))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 10)

                let likes = moment.likes ?? []
                let comments = moment.comments ?? []
                if !likes.isEmpty || !comments.isEmpty {

                    VStack(alignment: .leading, spacing: 0) {
                        if !likes.isEmpty {
                            HStack(alignment: .top, spacing: 4) {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 11.5))
                                    .foregroundColor(Color(hex: 0x9A9A9A))
                                    .padding(.top, 3)
                                    .overlay {
                                        if heartBurst { HeartBurst() }
                                    }
                                Text(likes.compactMap { $0.nickname }.joined(separator: "，"))
                                    .font(pf(16))
                                    .foregroundColor(C.link)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 5)
                        }
                        if !likes.isEmpty && !comments.isEmpty {
                            HairLine(inset: 0)
                        }
                        ForEach(comments.indices, id: \.self) { i in
                            let c = comments[i]
                            if i > 0 { HairLine(inset: 0) }

                            (Text(c.nickname ?? "")
                                .foregroundColor(C.link)

                             + Text((c.replyToName ?? "").isEmpty
                                    ? ("：" + (c.content ?? ""))
                                    : (" 回复 " + (c.replyToName ?? "") + "：" + (c.content ?? "")))
                                .foregroundColor(C.label))
                                .font(pf(16))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.vertical, 5)
                                .contentShape(Rectangle())

                               .onTapGesture {
                                    if !myId.isEmpty, c.userId == myId {

                                        if onDeleteComment != nil { deletingComment = c.id }
                                    } else if let reply = onReplyComment {

                                        reply(c.userId ?? "", c.nickname ?? "")
                                    }
                               }
                        }
                    }
                    .padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.dyn(0xF7F7F7, 0x2A2A2C)))
                    .padding(.top, 8)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 15)
        .padding(.bottom, 12)

        .onChange(of: (moment.likes ?? []).count) { n in
            if n > 0 { burstHeart() }
        }

        .overlay(alignment: .bottomTrailing) {
            if showActions {
                actionBar
                    .offset(x: -34, y: -6)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }

        .simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .onChanged { _ in
                    if showActions {
                        withAnimation(.easeOut(duration: 0.12)) { showActions = false }
                    }
                }
        )

        .confirmationDialog(Tr("删除这条评论？"), isPresented: Binding(
            get: { deletingComment != nil },
            set: { if !$0 { deletingComment = nil } }
        ), titleVisibility: .visible) {
            Button(Tr("删除"), role: .destructive) {
                if let id = deletingComment { onDeleteComment?(id) }
                deletingComment = nil
            }
            Button(Tr("取消"), role: .cancel) { deletingComment = nil }
        }
    }

    private var grid: some View {
        Group {

            if let v = moment.video, !v.isEmpty {
                videoTile(v)
            } else {
                MomentImageGrid(images: images,
                                avail: L.width - L.momentPadH * 2 - L.momentAvatar - 9,
                                sizes: moment.imageSizes ?? [:],
                                foldKey: moment.id,
                                onTap: { i in if i < images.count { onOpenImage?(images[i]) } })
            }
        }
    }

    private func videoTile(_ path: String) -> some View {
        let size = videoBubbleSize(w: moment.videoW ?? 0, h: moment.videoH ?? 0)
        let cover = moment.videoCover ?? ""
        let secs = moment.videoSeconds ?? 0
        return Button {
            let full = path.hasPrefix("http") ? path : API.shared.base + path
            if let u = URL(string: full) { onOpenVideo?(u) }
        } label: {
            ZStack {
                if !cover.isEmpty {
                    RemoteImage(path: cover, mode: .fill, maxSide: 1280)
                } else {
                    C.searchBg
                }
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 42))
                    .foregroundColor(.white.opacity(0.92))
                    .shadow(color: .black.opacity(0.32), radius: 6)
                if secs > 0 {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text(String(format: "%02d:%02d", secs / 60, secs % 60))
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Color.black.opacity(0.45)))
                        }
                    }
                    .padding(7)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func burstHeart() {
        heartBurst = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { heartBurst = false }
    }

    private var actionBar: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.12)) { showActions = false }
                burstHeart()
                onLike?()
            } label: {
                HStack(spacing: 5) {
                    ZStack {
                        Image(systemName: moment.likedByMe == true ? "heart.fill" : "heart")
                            .font(.system(size: 13))
                        if heartBurst { HeartBurst() }
                    }
                    Text(moment.likedByMe == true ? Tr("取消赞") : Tr("赞"))
                        .font(pf(14.5))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 13)
                .frame(height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Rectangle().fill(Color.white.opacity(0.22)).frame(width: 0.5, height: 18)

            Button {
                withAnimation(.easeOut(duration: 0.12)) { showActions = false }
                onComment?()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "bubble.right")
                        .font(.system(size: 12.5))
                    Text(Tr("评论")).font(pf(14.5))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 13)
                .frame(height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if moment.mine == true, onDeleteMoment != nil {
                Rectangle().fill(Color.white.opacity(0.22)).frame(width: 0.5, height: 18)
                Button {
                    withAnimation(.easeOut(duration: 0.12)) { showActions = false }
                    onTogglePin?()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: moment.pinned == true ? "pin.slash" : "pin")
                            .font(.system(size: 12.5))
                        Text(moment.pinned == true ? Tr("取消置顶") : Tr("置顶")).font(pf(14.5))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 13)
                    .frame(height: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Rectangle().fill(Color.white.opacity(0.22)).frame(width: 0.5, height: 18)
                Button {
                    withAnimation(.easeOut(duration: 0.12)) { showActions = false }
                    onDeleteMoment?()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .padding(.horizontal, 13)
                        .frame(height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }

        .background {
            ZStack {
                GlassBackground(shape: RoundedRectangle(cornerRadius: 5, style: .continuous),
                                opacity: UIConfig.num("momentBarGlass", 0.9),
                                edgeAlpha: UIConfig.num("momentBarEdge", 0.35),
                                shadow: false,
                                seed: 0.60)
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.black.opacity(0.58))
            }
        }
        .shadow(color: Color.black.opacity(0.18), radius: 6, y: 2)
    }
}

struct ColorBall: View {
    var size: CGFloat = 34
    var spin: Double = 0

    var body: some View {
        ZStack {
            Circle().fill(AngularGradient(
                gradient: Gradient(colors: [
                    Color(hex: 0xFF6B6B), Color(hex: 0xFFD166), Color(hex: 0x5FD07A),
                    Color(hex: 0x4AB6FF), Color(hex: 0xA06DE0), Color(hex: 0xFF6BD6),
                    Color(hex: 0xFF6B6B)
                ]),
                center: .center))
            Circle().fill(RadialGradient(
                gradient: Gradient(colors: [.white.opacity(0.95), .white.opacity(0)]),
                center: UnitPoint(x: 0.37, y: 0.3), startRadius: 0.5, endRadius: size * 0.36))
                .padding(size * 0.14)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(spin))
        .shadow(color: Color.black.opacity(0.28), radius: 7, y: 4)
    }
}

struct MomentImageGrid: View {
    let images: [String]
    var avail: CGFloat

    var sizes: [String: [Int]] = [:]
    var foldKey: String? = nil
    var onTap: (Int) -> Void

    @State private var expanded = false
    @State private var restoredFold = false

    private let gap: CGFloat = 6
    private let radius: CGFloat = 7

    private var foldsLongAlbum: Bool { images.count > 4 }
    private var shownCount: Int {
        foldsLongAlbum && !expanded ? min(3, images.count) : images.count
    }
    private var moreCount: Int { max(0, images.count - shownCount) }
    private var collageWidth: CGFloat { min(avail, 304) }

    var body: some View {
        if images.count == 1 {
            let sz = sizes[images[0]]
            MomentSingleImage(path: images[0], avail: avail, radius: radius,
                              knownSize: (sz != nil && sz!.count == 2 && sz![1] > 0)
                                  ? CGSize(width: CGFloat(sz![0]), height: CGFloat(sz![1])) : nil) { onTap(0) }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                collage(count: shownCount)
                    .frame(width: collageWidth, alignment: .leading)

                if foldsLongAlbum {
                    Button {
                        toggleExpanded()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: expanded ? "chevron.up" : "square.grid.2x2")
                                .font(.system(size: 10.5, weight: .semibold))
                            Text(expanded ? Tr("收起照片") : Tr("查看全部") + " \(images.count) " + Tr("张"))
                                .font(pf(12.5, .medium))
                        }
                        .foregroundColor(C.link)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .onAppear {
                guard !restoredFold else { return }
                restoredFold = true
                expanded = storedFold
            }
            .animation(.easeInOut(duration: 0.18), value: shownCount)
        }
    }

    @ViewBuilder
    private func collage(count: Int) -> some View {
        switch count {
        case 2:
            let side = (collageWidth - gap) / 2
            HStack(spacing: gap) {
                tile(0, width: side, height: side)
                tile(1, width: side, height: side)
            }

        case 3:
            let mainW = (collageWidth - gap) * 0.64
            let mainH = collageWidth * 0.44
            let smallW = collageWidth - mainW - gap
            HStack(spacing: gap) {
                tile(0, width: mainW, height: mainH)
                VStack(spacing: gap) {
                    tile(1, width: smallW, height: (mainH - gap) / 2)
                    tile(2, width: smallW, height: (mainH - gap) / 2, more: moreCount)
                }
            }

        case 4:
            let side = (min(collageWidth, 286) - gap) / 2
            VStack(alignment: .leading, spacing: gap) {
                HStack(spacing: gap) {
                    tile(0, width: side, height: side)
                    tile(1, width: side, height: side)
                }
                HStack(spacing: gap) {
                    tile(2, width: side, height: side)
                    tile(3, width: side, height: side, more: moreCount)
                }
            }

        case 5:
            let mainH = collageWidth * 0.43
            let rightW = collageWidth * 0.29
            let bottomH = collageWidth * 0.24
            let leftW = collageWidth - rightW - gap
            let bottomW = (leftW - gap * 2) / 3
            HStack(spacing: gap) {
                VStack(spacing: gap) {
                    tile(0, width: leftW, height: mainH)
                    HStack(spacing: gap) {
                        tile(2, width: bottomW, height: bottomH)
                        tile(3, width: bottomW, height: bottomH)
                        tile(4, width: bottomW, height: bottomH)
                    }
                }
                tile(1, width: rightW, height: mainH + gap + bottomH)
            }

        default:
            let cell = (collageWidth - gap * 2) / 3
            let rows = stride(from: 0, to: count, by: 3).map { start in
                Array(start..<min(start + 3, count))
            }
            VStack(alignment: .leading, spacing: gap) {
                ForEach(rows.indices, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(rows[row], id: \.self) { index in
                            tile(index, width: cell, height: cell,
                                 more: index == count - 1 ? moreCount : 0)
                        }
                        if rows[row].count < 3 { Spacer(minLength: 0) }
                    }
                }
            }
        }
    }

    private func tile(_ index: Int, width: CGFloat, height: CGFloat, more: Int = 0) -> some View {
        Button {
            if more > 0 {
                toggleExpanded()
            } else {
                onTap(index)
            }
        } label: {
            RemoteImage(path: images[index], icon: "photo", maxSide: 900)
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if more > 0 {
                        Text("+\(more)")
                            .font(pf(16, .semibold))
                            .foregroundColor(.white)
                            .frame(minWidth: 29, minHeight: 29)
                            .padding(.horizontal, 3)
                            .background(Circle().fill(Color.black.opacity(0.48)))
                            .padding(7)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var storedFold: Bool {
        guard let foldKey, !foldKey.isEmpty else { return false }
        return AlbumFold.isOpen("moment:" + foldKey)
    }

    private func persistFold() {
        guard let foldKey, !foldKey.isEmpty else { return }
        AlbumFold.setOpen("moment:" + foldKey, expanded)
    }

    private func toggleExpanded() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            expanded.toggle()
        }
        persistFold()
    }
}

struct CoverAdjustSheet: View {
    let image: UIImage
    let frameSize: CGSize
    var onDone: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("拖动调整"), back: { dismiss() }) {
                Button {
                    render()
                } label: {
                    Text(Tr("完成"))
                        .font(pf(17, .semibold))
                        .foregroundColor(C.green)
                        .frame(height: L.navH)
                        .padding(.trailing, 16)
                }
                .buttonStyle(.plain)
            }

            ZStack {
                Color.black
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: frameSize.width, height: frameSize.height)
                    .scaleEffect(scale)
                    .offset(offset)
            }
            .frame(width: frameSize.width, height: frameSize.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { v in
                        offset = CGSize(width: baseOffset.width + v.translation.width,
                                        height: baseOffset.height + v.translation.height)
                    }
                    .onEnded { _ in baseOffset = offset }
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { m in scale = max(1, min(3, baseScale * m)) }
                    .onEnded { _ in baseScale = scale }
            )

            Text(Tr("拖动挪位置，双指缩放，点「完成」保存"))
                .font(pf(12.5))
                .foregroundColor(C.subLabel)
                .padding(.top, 14)
            Spacer()
        }
        .background(C.pageBg.ignoresSafeArea(edges: .bottom))
        .background(C.pageBg.ignoresSafeArea(edges: .top))
        .toolbar(.hidden, for: .navigationBar)
        .hidesTabBar()
    }

    @MainActor
    private func render() {

        let targetW: CGFloat = 2048
        let targetH = (targetW * frameSize.height / max(1, frameSize.width)).rounded()
        let k = targetW / max(1, frameSize.width)
        let view = Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: targetW, height: targetH)
            .scaleEffect(scale)
            .offset(x: offset.width * k, y: offset.height * k)
            .frame(width: targetW, height: targetH)
            .clipped()
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        if let out = renderer.uiImage { onDone(out) }
        dismiss()
    }
}

struct MomentGridDrop: DropDelegate {
    let index: Int
    @Binding var items: [UIImage]
    @Binding var dragIndex: Int?

    func dropEntered(info: DropInfo) {
        guard let from = dragIndex, from != index,
              items.indices.contains(from), items.indices.contains(index) else { return }
        withAnimation(.easeInOut(duration: 0.16)) {
            items.move(fromOffsets: IndexSet(integer: from), toOffset: index > from ? index + 1 : index)
        }
        dragIndex = index
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragIndex = nil
        return true
    }
}

final class OneShotLocation: NSObject, CLLocationManagerDelegate {
    static let shared = OneShotLocation()
    private let mgr = CLLocationManager()
    private var cont: CheckedContinuation<CLLocation?, Never>?
    private var timeout: Task<Void, Never>?

    func current() async -> CLLocation? {

        if let l = mgr.location, abs(l.timestamp.timeIntervalSinceNow) < 60 { return l }
        if cont != nil { return mgr.location }
        return await withCheckedContinuation { c in
            cont = c
            mgr.delegate = self
            mgr.desiredAccuracy = kCLLocationAccuracyHundredMeters
            let st = mgr.authorizationStatus
            if st == .notDetermined {

                mgr.requestWhenInUseAuthorization()
            } else if st == .denied || st == .restricted {
                finish(mgr.location)
            } else {
                mgr.requestLocation()
            }

            timeout?.cancel()
            timeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                if Task.isCancelled { return }
                self?.finish(self?.mgr.location)
            }
        }
    }

    private func finish(_ loc: CLLocation?) {
        timeout?.cancel()
        timeout = nil
        cont?.resume(returning: loc)
        cont = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let st = manager.authorizationStatus
        if st == .notDetermined { return }
        if st == .denied || st == .restricted {
            finish(manager.location)
            return
        }
        if cont != nil { manager.requestLocation() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finish(locations.last)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(manager.location)
    }
}

struct PlacePickerSheet: View {
    @Binding var text: String
    @Environment(\.dismiss) private var dismiss

    @State private var places: [String] = []
    @State private var locating = true

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("所在位置"), back: { dismiss() })
            if locating {
                HStack { Spacer(); ProgressView(Tr("正在定位…")); Spacer() }
                    .frame(height: 90)
                    .background(C.cardBg)
            }
            ScrollView {
                VStack(spacing: 0) {
                    Button {
                        text = ""
                        dismiss()
                    } label: {
                        HStack {
                            Text(Tr("不显示位置")).font(pf(16)).foregroundColor(C.label)
                            Spacer()
                            if text.isEmpty { Image(systemName: "checkmark").foregroundColor(C.green) }
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    ForEach(places, id: \.self) { p in
                        HairLine(inset: 16)
                        Button {
                            text = p
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "mappin.and.ellipse")
                                    .font(.system(size: 15)).foregroundColor(C.subLabel)
                                Text(p).font(pf(16)).foregroundColor(C.label)
                                Spacer()
                                if text == p { Image(systemName: "checkmark").foregroundColor(C.green) }
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 52)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(C.cardBg)
                .padding(.top, 12)
            }
            Spacer()
        }
        .background(C.pageBg.ignoresSafeArea(edges: .bottom))
        .background(C.pageBg.ignoresSafeArea(edges: .top))
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .task {
            let loc = await OneShotLocation.shared.current()
            guard let loc = loc else { locating = false; return }
            if let marks = try? await CLGeocoder().reverseGeocodeLocation(loc), let m = marks.first {
                var list: [String] = []
                if let name = m.name, !name.isEmpty { list.append(name) }
                if let city = m.locality, !city.isEmpty, !list.contains(city) { list.append(city) }
                if let sub = m.subLocality, !sub.isEmpty, !list.contains(sub) { list.append(sub) }
                if let prov = m.administrativeArea, !prov.isEmpty, !list.contains(prov) { list.append(prov) }
                places = list
            }
            locating = false
        }
    }
}

struct PickedGrid: View {
    let images: [UIImage]
    var onTap: (Int) -> Void

    private let gap: CGFloat = 6
    private let radius: CGFloat = 4

    var body: some View {
        if images.count == 1 {
            let img = images[0]
            let a = min(max(img.size.width / max(1, img.size.height), 0.75), 2.0)
            let limit = a >= 1 ? (L.width - 32) : (L.width - 32) * 0.62
            let w = min(limit, img.size.width)
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: w, height: min(w / a, 300))
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture { onTap(0) }
        } else {
            let cols = (images.count == 2 || images.count == 4) ? 2 : 3
            let maxW = L.width - 32
            let cell = (maxW - gap * CGFloat(cols - 1)) / CGFloat(cols)
            let rows = stride(from: 0, to: images.count, by: cols).map { start in
                Array(start..<min(start + cols, images.count))
            }
            VStack(alignment: .leading, spacing: gap) {
                ForEach(rows.indices, id: \.self) { r in
                    HStack(spacing: gap) {
                        ForEach(rows[r], id: \.self) { i in
                            Image(uiImage: images[i])
                                .resizable()
                                .scaledToFill()
                                .frame(width: cell, height: cell)
                                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                                .contentShape(Rectangle())
                                .onTapGesture { onTap(i) }
                        }
                        if rows[r].count < cols { Spacer(minLength: 0) }
                    }
                }
            }
        }
    }
}

struct MomentSingleImage: View {
    let path: String
    var avail: CGFloat
    var radius: CGFloat = 4

    var knownSize: CGSize? = nil
    var onTap: () -> Void

    @State private var aspect: CGFloat = 4.0 / 3.0
    @State private var naturalW: CGFloat = 0
    @State private var started = false

    var body: some View {

        let rawAspect = (knownSize?.height ?? 0) > 0 ? (knownSize!.width / knownSize!.height) : aspect
        let a = min(max(rawAspect, 0.75), 2.0)

        let limit = a >= 1 ? avail : avail * 0.62
        let rawW = (knownSize?.width ?? 0) > 0 ? knownSize!.width : naturalW
        let w = rawW > 0 ? min(limit, rawW) : limit
        let h = min(w / a, 300)

        Button { onTap() } label: {

            RemoteImage(path: path, icon: "photo", maxSide: 1080)
                .frame(width: w, height: h)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear { if !started { started = true; Task { await measure() } } }
    }

    private func measure() async {
        if let hit = ImageStore.shared.get(path), hit.size.height > 0 {
            aspect = hit.size.width / hit.size.height
            naturalW = hit.size.width
            return
        }
        guard let url = API.shared.assetURL(path) else { return }
        guard let data = try? await API.shared.imageData(url),
              let img = RemoteImage.downsampled(data, maxSide: 2048), img.size.height > 0 else { return }
        ImageStore.shared.put(path, img)
        aspect = img.size.width / img.size.height
        naturalW = img.size.width
    }
}
