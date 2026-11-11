import SwiftUI
import UIKit

struct MainTabView: View {
    @EnvironmentObject var app: AppState
    @State private var tab = 0
    @State private var mountedTabs: Set<Int> = [0]
    @State private var shownCrash = false
    @AppStorage("xingyan.topGreenGlow") private var topGreenGlow = true

    @ObservedObject private var lang = LangStore.shared
    @Environment(\.colorScheme) private var scheme

    @ObservedObject private var musicSheet = MusicSheet.shared
    @ObservedObject private var musicDock = MusicDockState.shared

    @ObservedObject private var mallSheet = MallSheet.shared

    @ObservedObject private var realNameGate = RealNameGate.shared

    private var unreadTotal: Int {

        app.chats.reduce(0) { $0 + (($1.muted == true) ? 0 : ($1.unread ?? 0)) }
    }

    private var mutedOnlyUnread: Bool {
        unreadTotal == 0 && app.chats.contains { $0.muted == true && ($0.unread ?? 0) > 0 }
    }

    private var tabAvatarPath: String {
        let current = app.me?.avatarPath ?? ""
        return current.isEmpty ? app.lastAvatar : current
    }

    private var rootTabBarVisible: Bool {
        !app.tabBarHidden && app.openChat == nil && app.openMiniApp == nil
    }

    var body: some View {

        ZStack(alignment: .bottom) {

            TabView(selection: $tab) {
                Group {
                    if mountedTabs.contains(0) { ChatsView() } else { Color.clear }
                }
                .tag(0)

                Group {
                    if mountedTabs.contains(1) { ContactsView() } else { Color.clear }
                }
                .tag(1)

                Group {
                    if mountedTabs.contains(2) { DiscoverView() } else { Color.clear }
                }
                .tag(2)

                Group {
                    if mountedTabs.contains(3) { MeView() } else { Color.clear }
                }
                .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .toolbar(.hidden, for: .tabBar)
            .toolbarBackground(.hidden, for: .tabBar)
            .background {
                SystemTabBarHider()
                    .frame(width: 0, height: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            .ignoresSafeArea(edges: rootTabBarVisible ? [] : .bottom)

            .safeAreaInset(edge: .bottom, spacing: 0) {
                if rootTabBarVisible {
                    NativeTabBar(selection: $tab,
                                 uiVersion: app.uiVersion,
                                 badge: app.showDot("chats", auto: unreadTotal > 0) ? unreadTotal : 0,
                                 contactsDot: app.showDot("contacts", auto: app.friendRequests > 0),
                                 momentsDot: app.showDot("discover", auto: app.momentsUnread > 0),
                                 meDot: app.showDot("me", auto: false),
                                 avatarPath: tabAvatarPath)
                        .frame(height: 49 + L.safeBottom)
                        .offset(y: L.safeBottom)
                        .ignoresSafeArea(edges: .bottom)
                        .transition(.move(edge: .bottom))
                }
            }

            .overlay(alignment: .top) {
                if tab == 0 && rootTabBarVisible &&
                   (app.syncing || !app.syncText.isEmpty) {
                    HStack(spacing: 7) {
                        if app.syncing {
                            ProgressView().scaleEffect(0.68)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(C.green)
                        }
                        Text(app.syncing ? "正在同步…" : "同步完成")
                            .font(pf(12.5, .medium))
                            .foregroundColor(C.label)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(Capsule().fill(C.cardBg.opacity(0.96)))
                    .overlay(Capsule().stroke(C.hairline, lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
                    .padding(.top, 6)
                    .transition(.opacity)
                    .allowsHitTesting(false)
                }
            }

        }

        .background(C.pageBg.ignoresSafeArea())
        .overlay(alignment: .top) {
            if topGreenGlow, scheme != .dark {
                StarStatusRail(tab: tab)
                    .zIndex(100)
            }
        }

        .overlay(CallOverlay())

        .sheet(isPresented: Binding(
            get: { CrashCatcher.hasUnseenCrash() && !shownCrash },
            set: { v in
                if !v {
                    shownCrash = true
                    CrashCatcher.acknowledgeCrashNotice()
                }
            })) {
                CrashLogView()
        }

        .overlay(CallDialogOverlay())

        .overlay(OtherLoginCard().environmentObject(app))

        .sheet(item: $app.payScan) { info in
            PayConfirmPage(target: info, scanText: app.payScanText)
                .environmentObject(app)
        }

        .sheet(isPresented: Binding(get: { app.scanCardUser != nil },
                                    set: { if !$0 { app.scanCardUser = nil } })) {
            if let u = app.scanCardUser {
                NavigationStack {
                    ContactCardView(user: u,
                                    onOpenChat: { chat in
                                        app.scanCardUser = nil
                                        app.openChatViaList(chat)
                                    },
                                    onOpenMoments: { _ in app.scanCardUser = nil })
                        .environmentObject(app)
                }
            }
        }

        .fullScreenCover(isPresented: Binding(
            get: { app.scanWebURL != nil },
            set: { if !$0 { app.scanWebURL = nil } })) {
                if let raw = app.scanWebURL,
                   let url = URL(string: raw),
                   let scheme = url.scheme?.lowercased(),
                   scheme == "http" || scheme == "https" {
                    ScannedWebBrowserView(url: url) {
                        app.scanWebURL = nil
                    }
                    .ignoresSafeArea()
                }
            }

        .sheet(isPresented: Binding(
            get: { app.scanTextResult != nil },
            set: { if !$0 { app.scanTextResult = nil } })) {
                if let text = app.scanTextResult {
                    ScannedTextResultView(text: text)
                }
            }

        .fullScreenCover(item: $app.nearbyDropInvite) { invite in
            FaceToFaceFileSheet(rows: [], avatar: "", name: invite.name, mode: .join(invite))
                .environmentObject(app)
        }

        .alert(Tr("根据国家规定"), isPresented: $realNameGate.alert) {
            Button(Tr("去实名认证")) { realNameGate.openPage = true }
            Button(Tr("取消"), role: .cancel) { }
        } message: {
            Text(Tr("请先完成实名认证，之后才能使用转账、红包、收付款、零钱等功能。聊天不受影响。"))
        }
        .sheet(isPresented: $realNameGate.openPage) {
            RealNameView().environmentObject(app)
        }

        .overlay {
            if musicSheet.open && !musicDock.active {
                MusicPlayingView()
                    .transition(.move(edge: .bottom))
                    .zIndex(60)
            }
        }
        .animation(.easeOut(duration: 0.22), value: musicSheet.open)

        .fullScreenCover(item: Binding(
            get: { mallSheet.open ? mallSheet.product : nil },
            set: { if $0 == nil { mallSheet.close() } }
        )) { p in
            DDDetailView(product: p,
                         onCart: { mallSheet.close() },
                         onOpenOther: { mallSheet.product = $0 },
                         onDismiss: { mallSheet.close() })
                .environmentObject(app)
        }

        .overlay(MiniPlayerBall(hidden: app.openMiniApp != nil
                                || app.openChat != nil || musicSheet.open
                                || musicDock.foregroundActive))

        .fullScreenCover(item: $app.openChat) { c in

            NavigationStack {
                ChatDetailView(chat: c).environmentObject(app)
            }

            .overlay(MiniPlayerBall())

            .overlay {
                if musicSheet.open {
                    MusicPlayingView()
                        .transition(.move(edge: .bottom))
                        .zIndex(60)
                }
            }
            .animation(.easeOut(duration: 0.22), value: musicSheet.open)
        }

        .fullScreenCover(item: $app.openMiniApp, onDismiss: { app.miniAppDidClose() }) { g in
            GameWebPage(game: g).environmentObject(app)
        }
        .onReceive(NotificationCenter.default.publisher(for: .chrisOpenChat)) { note in
            guard let chatId = note.userInfo?["chatId"] as? String, !chatId.isEmpty else { return }
            CrashCatcher.note("推送", "点通知 chatId=" + chatId)
            Task { @MainActor in

                for _ in 0..<40 {
                    if UIApplication.shared.applicationState == .active { break }
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
                await app.loadChats()
                CrashCatcher.note("推送", "会话已加载 " + String(app.chats.count) + " 个")

                tab = 0
                app.pendingPushChatId = chatId
            }
        }

        .onChange(of: app.wantChatsTab) { v in
            if v { tab = 0; app.wantChatsTab = false }
        }
        .onChange(of: tab) { value in
            mountedTabs.insert(value)
            musicDock.setForegroundTab(value)
        }

        .onReceive(NotificationCenter.default.publisher(for: .chrisOpenPair)) { note in
            guard let code = note.userInfo?["code"] as? String, !code.isEmpty else { return }
            app.pairApproveCode = code
        }

        .task {
            while !Task.isCancelled {
                await app.checkReachability()
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }

        .onAppear { CrashCatcher.note("启动", "7 主界面出现") }
    }
}

private struct SystemTabBarHider: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            var responder: UIResponder? = uiView
            while let current = responder {
                if let tabs = current as? UITabBarController {
                    tabs.tabBar.isHidden = true
                    tabs.tabBar.alpha = 0
                    tabs.tabBar.isUserInteractionEnabled = false
                    return
                }
                responder = current.next
            }
        }
    }
}

struct TabBarTouchLayer: UIViewRepresentable {

    var onTap: (CGFloat) -> Void
    var onLongPressBegan: (CGFloat) -> Void
    var onLongPressChanged: (CGFloat) -> Void
    var onLongPressEnded: (CGFloat) -> Void

    var onSlide: (CGFloat) -> Void

    var onSlideEnded: (CGFloat) -> Void

    final class Coord: NSObject, UIGestureRecognizerDelegate {
        var onTap: (CGFloat) -> Void = { _ in }
        var onBegan: (CGFloat) -> Void = { _ in }
        var onChanged: (CGFloat) -> Void = { _ in }
        var onEnded: (CGFloat) -> Void = { _ in }
        var onSlide: (CGFloat) -> Void = { _ in }
        var onSlideEnded: (CGFloat) -> Void = { _ in }

        private var lastPressEnd = Date.distantPast

        @objc func handleTap(_ g: UITapGestureRecognizer) {
            guard g.state == .ended, let v = g.view else { return }
            if Date().timeIntervalSince(lastPressEnd) < 0.35 { return }
            onTap(g.location(in: v).x)
        }

        @objc func handlePan(_ g: UIPanGestureRecognizer) {
            guard let v = g.view else { return }
            let x = g.location(in: v).x
            switch g.state {
            case .began, .changed:
                onSlide(x)
            case .ended, .cancelled, .failed:
                onSlideEnded(x)
            default:
                break
            }
        }

        @objc func handlePress(_ g: UILongPressGestureRecognizer) {
            guard let v = g.view else { return }
            let x = g.location(in: v).x
            switch g.state {
            case .began:
                onBegan(x)
            case .changed:
                onChanged(x)
            case .ended, .cancelled, .failed:
                lastPressEnd = Date()
                onEnded(x)
            default:
                break
            }
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            let pair = [g, other]
            let panAndPress = pair.contains { $0 is UIPanGestureRecognizer }
                && pair.contains { $0 is UILongPressGestureRecognizer }
            return panAndPress
        }
    }

    func makeCoordinator() -> Coord { Coord() }

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        v.isUserInteractionEnabled = true

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coord.handleTap(_:)))
        v.addGestureRecognizer(tap)

        let press = UILongPressGestureRecognizer(target: context.coordinator,
                                                 action: #selector(Coord.handlePress(_:)))

        press.minimumPressDuration = min(0.18, max(0.12, UIConfig.num("tabLoupePress", 0.12)))

        press.allowableMovement = 10000
        press.delegate = context.coordinator
        v.addGestureRecognizer(press)

        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coord.handlePan(_:)))
        pan.delegate = context.coordinator
        v.addGestureRecognizer(pan)

        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onBegan = onLongPressBegan
        context.coordinator.onChanged = onLongPressChanged
        context.coordinator.onEnded = onLongPressEnded
        context.coordinator.onSlide = onSlide
        context.coordinator.onSlideEnded = onSlideEnded
    }
}

struct TabBar: View {
    @ObservedObject private var lang = LangStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Binding var selection: Int
    var badge: Int

    var contactsDot: Bool = false

    var momentsDot: Bool = false

    var meDot: Bool = false

    private var items: [(String, String, String)] {
        [
            ("message", "message.fill", C.tabText0),
            ("person.2", "person.2.fill", C.tabText1),
            ("safari", "safari", C.tabText2),
            ("person.crop.circle", "person.crop.circle.fill", C.tabText3)
        ]
    }

    private func iconFont(_ i: Int) -> Font {
        let def = (i == 0 || i == 1) ? L.tabIcon - 2 : L.tabIcon
        return pf(UIConfig.num("tabIcon\(i)", def))
    }

    private let customKeys = ["tab.chat", "tab.contacts", "tab.discover", "tab.me"]

    private func customSize(_ i: Int) -> CGFloat {
        UIConfig.num("tabIcon\(i)", L.tabIconBox)
    }

    private var selColor: Color { UIConfig.color("tabOrbitSelColor", 0x17201C, 0xDDF7ED) }
    private var unselColor: Color { UIConfig.color("tabOrbitUnselColor", 0x626B66, 0x8AA79C) }

    private func activeColor(_ index: Int) -> Color {
        index < 3 ? (scheme == .dark ? .white : .black) : selColor
    }

    private func tabIconFont(_ i: Int, on: Bool) -> Font {
        let base = UIConfig.num("tabIcon\(i)", (i == 0 || i == 1) ? L.tabIcon - 2 : L.tabIcon)
        return pf(on ? base + 1.5 : base)
    }

    @State private var barWidth: CGFloat = 0
    @State private var dragX: CGFloat? = nil
    @State private var dragIndex: Int? = nil
    @State private var dragOriginX: CGFloat? = nil
    @Namespace private var tabLoupeNS

    @State private var slideX: CGFloat? = nil
    @State private var slideIndex: Int? = nil
    private let dragHaptic = UIImpactFeedbackGenerator(style: .light)

    private func updateDrag(_ x: CGFloat) {
        guard barWidth > 1, !items.isEmpty else { return }
        let seg = barWidth / CGFloat(items.count)
        if dragOriginX == nil { dragOriginX = x }
        let first = seg * 0.5
        let last = barWidth - seg * 0.5
        let bounded: CGFloat
        if x < first {
            bounded = first - (first - x) * 0.4
        } else if x > last {
            bounded = last + (x - last) * 0.4
        } else {
            bounded = x
        }
        let origin = dragOriginX ?? bounded
        let damped = origin + (bounded - origin) * 0.92
        let nearest = min(items.count - 1, max(0, Int(((damped - seg * 0.5) / seg).rounded())))
        let center = seg * (CGFloat(nearest) + 0.5)
        let magnetized = abs(damped - center) <= 18 ? center : damped
        let i = min(items.count - 1, max(0, Int(((magnetized - seg * 0.5) / seg).rounded())))
        if i != dragIndex { dragHaptic.impactOccurred() }
        dragX = magnetized
        dragIndex = i
    }

    private func selectTab(at x: CGFloat) {
        guard barWidth > 1, !items.isEmpty else { return }
        let seg = barWidth / CGFloat(items.count)
        selection = min(items.count - 1, max(0, Int(x / seg)))
    }

    private var tabMaskLayer: some View {

        if scheme == .dark {
            return AnyView(ZStack {
                Rectangle().fill(.ultraThinMaterial)
                    .opacity(0.84)
                Color(hex: 0x0C0C0D)
                    .opacity(0.52)
            })
        }
        let fill = UIConfig.colorIfSet("tabBarColor")
            ?? UIConfig.colorIfSet("tabBg")
            ?? C.tabBg

        let glassOn = UIConfig.num("tabGlass", 1) > 0
        if glassOn {
            return AnyView(ZStack {

                let blurA = UIConfig.num("tabBarBlur", 0.9)
                if blurA > 0 {
                    Rectangle()
                        .fill(.bar)
                        .opacity(max(0, min(1, blurA)))
                }
                GlassBackground(shape: Rectangle(),
                                opacity: UIConfig.num("tabBarGlass", 0.9),

                                edgeAlpha: UIConfig.num("tabEdgeAlpha", 0.5),
                                shadow: false,
                                seed: 0.55,
                                native: true)

                fill.opacity(UIConfig.num("tabBarOpaque", 0.10))
            })
        }
        let glass = UIConfig.num("tabGlass", 1) > 0 ? UIConfig.num("tabGlassAlpha", 0.5) : 0
        return AnyView(ZStack {
            fill
                .opacity(UIConfig.num("tabBarOpaque", 0.32))
            Rectangle().fill(.bar)
                .opacity(glass)
        })
    }

    private var dropH: CGFloat { max(0, UIConfig.num("tabBarDrop", 0)) }

    @ViewBuilder
    private func magnifier(_ i: Int, x: CGFloat) -> some View {
        /* WhatsApp 的预览是一个悬浮液体玻璃胶囊：图标和文字一起装在
           28pt 圆角胶囊里，按节点磁吸移动；切换节点时只替换泡内内容，
           旧内容向一侧滑出，新内容延迟 25ms 从另一侧滑入，形成粘连感。 */
        let h = 58.0
        if i < items.count {
            ZStack {
                GlassBackground(shape: Capsule(style: .continuous),
                                opacity: 0.96,
                                edgeAlpha: 0.82,
                                shadow: false,
                                seed: 0.74,
                                native: true)
                Capsule(style: .continuous)
                    .fill(scheme == .dark ? Color(hex: 0x1A1A1C).opacity(0.88)
                                          : Color.white.opacity(0.18))
                Capsule(style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [scheme == .dark ? Color.white.opacity(0.24)
                                                     : Color.white.opacity(0.78),
                                     Color.white.opacity(0.12)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.8
                    )
                VStack(spacing: 0) {
                    Image(systemName: items[i].1)
                        .font(.system(size: 28, weight: .regular))
                    Text(items[i].2)
                        .font(pf(15, .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .contentTransition(.interpolate)
                }
                .foregroundColor(activeColor(i))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(i)
                .transition(.asymmetric(
                    insertion: .offset(x: 10).combined(with: .opacity),
                    removal: .offset(x: -10).combined(with: .opacity)
                ))
                .animation(.easeOut(duration: 0.12), value: i)
            }
            .frame(width: 108, height: h)
            .matchedGeometryEffect(id: "tab-loupe-\(i)", in: tabLoupeNS,
                                   isSource: dragIndex == i)
            .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.76), value: i)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                Button {
                    selection = i
                } label: {
                    VStack(spacing: 3) {
                        ZStack(alignment: .topTrailing) {
                            if let custom = IconOverrides.custom(customKeys[i]) {

                                if custom.hasPrefix("http") || custom.hasPrefix("/uploads") || custom.hasPrefix("data:") {
                                    RemoteImage(path: custom, template: true)
                                        .frame(width: customSize(i), height: customSize(i))
                                        .foregroundColor(selection == i ? activeColor(i) : unselColor)
                                } else {
                                    FlexIcon(custom: custom, size: customSize(i),
                                             color: selection == i ? activeColor(i) : unselColor,
                                             symbol: items[i].0)
                                }
                            } else if i == 3, let av = app.me?.avatarPath, !av.isEmpty {

                                Avatar(path: av, size: UIConfig.num("tabAvatar", 24), radius: 0, circle: true)
                                    .overlay(Circle().stroke(selection == i ? selColor : Color.clear, lineWidth: 1.5))
                            } else {
                                Image(systemName: selection == i ? items[i].1 : items[i].0)
                                    .font(tabIconFont(i, on: selection == i))
                                    .frame(width: L.tabIconBox, height: L.tabIconBox)
                            }
                            if i == 0 && badge > 0 {
                                Text(badge > 99 ? "99+" : "\(badge)")
                                    .font(pf(11, .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 3)
                                    .frame(minWidth: 15, minHeight: 15)
                                    .background(Capsule().fill(Color(.systemRed)))
                                    .offset(x: 5, y: -3)
                            }

                            if i == 2 && momentsDot {
                                Circle()
                                    .fill(Color(.systemRed))
                                    .frame(width: 9, height: 9)
                                    .overlay(Circle().stroke(OrbitTheme.raised, lineWidth: 1.5))
                                    .offset(x: 4, y: -2)
                            }

                            if i == 1 && contactsDot {
                                Circle()
                                    .fill(Color(.systemRed))
                                    .frame(width: 9, height: 9)
                                    .overlay(Circle().stroke(OrbitTheme.raised, lineWidth: 1.5))
                                    .offset(x: 4, y: -2)
                            }

                            if i == 3 && meDot {
                                Circle()
                                    .fill(Color(.systemRed))
                                    .frame(width: 9, height: 9)
                                    .overlay(Circle().stroke(OrbitTheme.raised, lineWidth: 1.5))
                                    .offset(x: 4, y: -2)
                            }
                        }
                        .frame(width: L.tabIconBox + 10, height: L.tabIconBox + 3)
                        .matchedGeometryEffect(id: "tab-loupe-\(i)", in: tabLoupeNS,
                                               isSource: dragIndex != i)
                        .opacity(dragIndex == i ? 0.05 : 1)
                        .scaleEffect(dragIndex == i ? 1.08 : 1)
                        .opacity(dragIndex != nil && dragIndex != i ? 0.58 : 1)
                        .animation(.easeOut(duration: 0.12), value: dragIndex)
                        Text(items[i].2)
                            .font(pf(UIConfig.num("tabLabel", L.tabLabel),
                                     selection == i ? .medium : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                            .frame(height: max(12, L.tabLabel + 2))
                    }
                    .foregroundColor(selection == i ? activeColor(i) : unselColor)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: L.tabH)

        .allowsHitTesting(false)

        .background(alignment: .leading) {
            if barWidth > 1, !items.isEmpty {
                let seg = barWidth / CGFloat(items.count)
                let w = max(0, seg - UIConfig.num("tabSliderInset", 7))
                let cx = slideX ?? dragX ?? (seg * (CGFloat(selection) + 0.5))
                ZStack {
                    GlassBackground(shape: Capsule(style: .continuous),
                                    opacity: UIConfig.num("tabSliderAlpha", 0.72),
                                    edgeAlpha: 0.78,
                                    shadow: false,
                                    seed: 0.22,
                                    native: true)
                    Capsule(style: .continuous)
                        .fill(scheme == .dark ? Color(hex: 0x1A1A1C).opacity(0.80)
                                              : Color.white.opacity(0.20))
                }
                    .overlay(

                        Capsule(style: .continuous)
                            .stroke(LinearGradient(colors: [scheme == .dark
                                                            ? Color.white.opacity(0.22)
                                                            : Color.white.opacity(0.70),
                                                            Color.white.opacity(0.12)],
                                                   startPoint: .top, endPoint: .bottom),
                                    lineWidth: 0.9)
                    )
                    .frame(width: w, height: max(0, L.tabH - UIConfig.num("tabSliderVInset", 10)))
                    .scaleEffect(slideX != nil ? 1.035 : 1)
                    .offset(x: cx - w / 2)

                    .animation(.spring(response: 0.30, dampingFraction: 0.78), value: selection)
                    .animation(nil, value: dragX)
            }
        }
        .background(

            tabMaskLayer
                .ignoresSafeArea(edges: .bottom)
        )

        .background(GeometryReader { g in
            Color.clear
                .onAppear { barWidth = g.size.width }
                .onChange(of: g.size.width) { w in barWidth = w }
        })

        .overlay(alignment: .top) {
            tabMaskLayer
                .frame(height: dropH)
                .offset(y: -dropH)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())

        .overlay {
            TabBarTouchLayer(
                onTap: { x in
                    selectTab(at: x)
                },
                onLongPressBegan: { x in
                    updateDrag(x)
                    dragHaptic.impactOccurred()
                },
                onLongPressChanged: { x in
                    updateDrag(x)
                },
                onLongPressEnded: { x in
                    updateDrag(x)
                    if let i = dragIndex, i < items.count { selection = i }
                    withAnimation(.easeOut(duration: 0.16)) {
                        dragX = nil
                        dragIndex = nil
                        dragOriginX = nil
                    }
                },
                onSlide: { x in
                    updateDrag(x)
                    slideIndex = dragIndex
                    slideX = dragX
                },
                onSlideEnded: { x in
                    if let i = dragIndex, i < items.count { selection = i }
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                        slideX = nil
                        slideIndex = nil
                        dragX = nil
                        dragIndex = nil
                        dragOriginX = nil
                    }
                }
            )
        }
        .overlay(alignment: .topLeading) {
            if let i = dragIndex, let x = dragX {
                magnifier(i, x: x)
                    .position(x: x, y: 8)
                    .animation(.interactiveSpring(response: 0.20, dampingFraction: 0.82), value: i)
                    .transition(.scale.combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
    }
}

struct NavBar<Right: View>: View {
    let title: String

    let titleView: AnyView?
    let back: (() -> Void)?
    let onLongPressTitle: (() -> Void)?
    private let titleColor: Color?
    private let titleOutline: Color?
    private let backColor: Color?
    private let hideChromeExceptBack: Bool

    let leftExtra: AnyView?

    var backGlass: Bool = false
    var floating: Bool = true

    var titleGlass: Bool = true
    var leftExtraGlass: Bool = true
    var rightGlass: Bool = true
    private let right: Right

    init(title: String,
         back: (() -> Void)? = nil,
         onLongPressTitle: (() -> Void)? = nil,
         titleColor: Color? = nil,
         titleOutline: Color? = nil,
         backColor: Color? = nil,
         hideChromeExceptBack: Bool = false,
         titleView: AnyView? = nil,
         leftExtra: AnyView? = nil,
         backGlass: Bool = false,
         floating: Bool = true,
         titleGlass: Bool = true,
         leftExtraGlass: Bool = true,
         rightGlass: Bool = true,
         @ViewBuilder right: () -> Right) {
        self.title = title
        self.titleView = titleView
        self.back = back
        self.onLongPressTitle = onLongPressTitle
        self.titleColor = titleColor
        self.titleOutline = titleOutline
        self.backColor = backColor
        self.hideChromeExceptBack = hideChromeExceptBack
        self.leftExtra = leftExtra
        self.backGlass = backGlass
        self.floating = floating
        self.titleGlass = titleGlass
        self.leftExtraGlass = leftExtraGlass
        self.rightGlass = rightGlass
        self.right = right()
    }

    private var useFloating: Bool { floating && UIConfig.num("navFloating", 1) > 0 }

    var body: some View {
        ZStack {
            if useFloating {

                if !title.isEmpty {
                    Group {
                        if let titleView { titleView } else { titleText }
                    }
                    .opacity(hideChromeExceptBack ? 0 : 1)
                    .allowsHitTesting(!hideChromeExceptBack)
                    .animation(.easeOut(duration: 0.16), value: hideChromeExceptBack)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background {
                        if titleGlass {
                            GlassBackground(shape: Capsule(),
                                            shadow: true,
                                            seed: 0.30,
                                            darkEdgeOff: true)
                        }
                    }
                }
            } else {

                Group {
                    if let titleView { titleView } else { titleText }
                }
                    .opacity(hideChromeExceptBack ? 0 : 1)
                    .allowsHitTesting(!hideChromeExceptBack)

                if titleView == nil && titleStroke > 0 {
                    titleText.offset(x: titleStroke)
                        .opacity(hideChromeExceptBack ? 0 : 1)
                }
            }

            HStack(spacing: 0) {
                if let back = back {
                    Button(action: back) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(backColor ?? Color.accentColor)
                            .frame(width: 44, height: 44)
                            .background {
                                if backGlass {
                                    GlassBackground(shape: Circle(),
                                                    shadow: true,
                                                    seed: 0.18,
                                                    native: true)
                                        .frame(width: 36, height: 36)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .accessibilityLabel(Tr("返回"))
                    .padding(.leading, useFloating ? 2 : 0)
                }
                if let leftExtra = leftExtra {
                    if useFloating && leftExtraGlass {

                        leftExtra
                            .frame(height: 36)
                            .padding(.horizontal, 6)
                            .background { GlassBackground(shape: Capsule(), shadow: true, seed: 0.55) }
                            .padding(.leading, 6)
                            .opacity(hideChromeExceptBack ? 0 : 1)
                            .allowsHitTesting(!hideChromeExceptBack)
                    } else {
                        leftExtra
                            .frame(height: useFloating ? 36 : L.navH)
                            .padding(.leading, useFloating ? 6 : 0)
                            .opacity(hideChromeExceptBack ? 0 : 1)
                            .allowsHitTesting(!hideChromeExceptBack)
                    }
                }
                Spacer(minLength: 0)
                if useFloating {
                    right
                        .frame(height: 36)
                        .background {
                            if rightGlass {
                                GlassBackground(shape: Capsule(),
                                                shadow: true,
                                                seed: 0.80,
                                                darkEdgeOff: true)
                            }
                        }
                        .padding(.trailing, 10)
                        .opacity(hideChromeExceptBack ? 0 : 1)
                        .allowsHitTesting(!hideChromeExceptBack)
                } else {
                    right
                        .opacity(hideChromeExceptBack ? 0 : 1)
                        .allowsHitTesting(!hideChromeExceptBack)
                }
            }
        }
        .frame(height: L.navH)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var titleText: some View {
        Text(title)
            .font(pf(titleSize, weight))
            .foregroundColor(titleColor ?? C.label)
            .shadow(color: titleOutline ?? .clear, radius: 0.8, x: 0.6, y: 0)
            .shadow(color: titleOutline ?? .clear, radius: 0.8, x: -0.6, y: 0)
            .shadow(color: titleOutline ?? .clear, radius: 0.8, x: 0, y: 0.6)
            .onLongPressGesture { onLongPressTitle?() }
    }

    private var titleSize: CGFloat {
        let base = UIConfig.num("navTitle", 17)
        return title == "发现" ? base - 1 : base
    }

    private var weight: Font.Weight { .semibold }

    private var titleStroke: CGFloat { UIConfig.num("navTitleStroke", 0) }
}

extension NavBar where Right == EmptyView {
    init(title: String,
         back: (() -> Void)? = nil,
         onLongPressTitle: (() -> Void)? = nil,
         titleColor: Color? = nil,
         titleOutline: Color? = nil,
         hideChromeExceptBack: Bool = false,
         titleView: AnyView? = nil,
         leftExtra: AnyView? = nil,
         backGlass: Bool = false,
         floating: Bool = true) {
        self.init(title: title, back: back, onLongPressTitle: onLongPressTitle,
                  titleColor: titleColor,
                  titleOutline: titleOutline,
                  hideChromeExceptBack: hideChromeExceptBack,
                  titleView: titleView, leftExtra: leftExtra,
                  backGlass: backGlass, floating: floating) { EmptyView() }
    }
}

struct SearchBoxCenter: View {
    @Binding var text: String
    var externalFocus: FocusState<Bool>.Binding? = nil
    @FocusState private var localFocus: Bool

    private var focused: Bool { externalFocus?.wrappedValue ?? localFocus }

    private var centered: Bool { text.isEmpty && !focused }

    @ViewBuilder
    private var field: some View {
        let tf = TextField("", text: $text)
            .font(pf(16))
            .foregroundColor(C.label)
            .multilineTextAlignment(centered ? .center : .leading)
        if let externalFocus = externalFocus {
            tf.focused(externalFocus)
        } else {
            tf.focused($localFocus)
        }
    }

    var body: some View {
        HStack(spacing: centered ? 3 : 5) {
            SVGIcon(markup: I.searchSmall, size: 16, color: C.searchIcon)

            ZStack(alignment: centered ? .center : .leading) {
                if text.isEmpty {
                    Text(Tr("搜索"))
                        .font(pf(16))
                        .foregroundColor(C.searchIcon)
                }
                field
            }
            .frame(maxWidth: centered ? 46 : .infinity)
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
        .padding(.leading, centered ? 28 : 9)
        .padding(.trailing, centered ? 18 : 9)
        .frame(height: L.searchBoxH)
        .background(

            GlassBackground(shape: Capsule(style: .continuous),
                            opacity: UIConfig.num("searchGlassAlpha", 0.55),
                            edgeAlpha: UIConfig.num("searchGlassEdge", 0))
        )
    }
}

struct SearchBoxLeft: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: L.v(5, 1.8, 8)) {
            SVGIcon(markup: I.searchBig, size: 16, color: C.searchIcon2)
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(Tr("搜索"))
                        .font(pf(15))
                        .foregroundColor(C.searchIcon2)
                }
                TextField("", text: $text)
                    .font(pf(15))
                    .foregroundColor(C.label)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .frame(height: L.searchBoxH)
        .background(

            GlassBackground(shape: Capsule(style: .continuous),
                            opacity: UIConfig.num("searchGlassAlpha", 0.55),
                            edgeAlpha: UIConfig.num("searchGlassEdge", 0))
        )
    }
}

struct MenuRow: View {
    let icon: String
    var iconColor: Color = C.green

    var padLeading: CGFloat = 18
    let title: String
    var detail: String = ""
    var showArrow: Bool = true
    var badge: Bool = false
    var thumb: String = ""
    var onTap: (() -> Void)? = nil

    var clearBg: Bool = false

    var iconTile: Bool = false

    var sf: String = ""

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: L.menuGap) {

                if iconTile {
                    if icon.hasPrefix("world:") {
                        StarOrbitWorldIcon(
                            action: String(icon.dropFirst(6)),
                            label: title,
                            size: L.menuIcon
                        )
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(iconColor)
                            if !sf.isEmpty {
                                Image(systemName: sf)
                                    .font(.system(size: L.menuIcon * 0.60, weight: .semibold))
                                    .foregroundColor(.white)
                            } else {
                                SVGIcon(markup: icon, size: L.menuIcon * 0.78, color: .white)
                            }
                        }
                        .frame(width: L.menuIcon, height: L.menuIcon)
                    }
                } else if !sf.isEmpty {
                    Image(systemName: sf)
                        .font(.system(size: L.menuIcon * 0.82, weight: .regular))
                        .foregroundColor(iconColor)
                        .frame(width: L.menuIcon, height: L.menuIcon)
                } else if UIConfig.num("menuIconAnim", 0) > 0,
                          icon.hasPrefix("anim:"),
                   let kind = MenuIconKind(rawValue: String(icon.dropFirst(5))) {
                    AnimatedMenuIcon(kind: kind, size: L.menuIcon)
                        .frame(width: L.menuIcon, height: L.menuIcon)
                } else {
                    SVGIcon(markup: icon, size: L.menuIcon * 1.13, color: iconColor)
                        .frame(width: L.menuIcon, height: L.menuIcon)
                }

                Text(title)
                    .font(pf(L.menuTextSize))
                    .foregroundColor(C.label)

                Spacer(minLength: 0)

                if !detail.isEmpty {
                    Text(detail).font(pf(15)).foregroundColor(C.subLabel)
                }
                if !thumb.isEmpty {
                    ZStack(alignment: .topTrailing) {
                        RemoteImage(path: thumb)
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        if badge {
                            Circle().fill(Color(.systemRed)).frame(width: 9, height: 9).offset(x: 4.5, y: -4.5)
                        }
                    }
                    .frame(width: 32, height: 32)
                    .padding(.trailing, -8)
                }
                if showArrow {
                    Chevron(size: 9, line: 1.6)
                        .padding(.trailing, 3)
                }
            }
            .padding(.leading, padLeading)
            .padding(.trailing, L.menuPadR)
            .frame(height: L.menuH)
            .background(clearBg ? Color.clear : C.cardBg)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuPressStyle())
    }
}

struct MenuPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.gray.opacity(0.16) : Color.clear)
    }
}

enum ChatInfoCardTone {
    case standard
    case group
    case direct
}

enum ChatInfoCardTint {
    static var group: Color { C.cardBg }
    static var direct: Color { C.cardBg }
}

private struct ChatInfoCardToneKey: EnvironmentKey {
    static let defaultValue: ChatInfoCardTone = .standard
}

extension EnvironmentValues {
    var chatInfoCardTone: ChatInfoCardTone {
        get { self[ChatInfoCardToneKey.self] }
        set { self[ChatInfoCardToneKey.self] = newValue }
    }
}

struct GroupCard<Content: View>: View {
    let content: Content
    @Environment(\.colorScheme) private var scheme
    @Environment(\.chatInfoCardTone) private var tone

    var glass: Bool = false

    var bg: Color? = nil
    init(glass: Bool = false, bg: Color? = nil, @ViewBuilder content: () -> Content) {
        self.glass = glass
        self.bg = bg
        self.content = content()
    }

    var body: some View {
        let themedCard = tone != .standard
        let radius: CGFloat = themedCard ? 16 : (scheme == .dark ? 14 : 0)
        if glass && scheme != .dark {
            VStack(spacing: 0) { content }
                .background {
                    ZStack {
                        GlassBackground(shape: RoundedRectangle(cornerRadius: 16, style: .continuous),
                                        opacity: UIConfig.num("meGlassAlpha", 0.62),
                                        edgeAlpha: UIConfig.num("meGlassEdge", 0.55),
                                        shadow: true,
                                        seed: 0.42,
                                        native: true)
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(C.cardBg.opacity(0.42))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, UIConfig.num("meGlassInset", 12))
                .padding(.bottom, 10)
        } else {
            VStack(spacing: 0) { content }
                .background(bg ?? resolvedBackground)
                .clipShape(RoundedRectangle(cornerRadius: radius,
                                            style: .continuous))
                .overlay {
                    if themedCard || scheme == .dark {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .stroke(Color.primary.opacity(scheme == .dark ? 0.10 : 0.065),
                                    lineWidth: 0.7)
                    }
                }
                .padding(.horizontal, themedCard ? 0 : (scheme == .dark ? 12 : 0))
                .padding(.bottom, themedCard ? 10 : (scheme == .dark ? 8 : 0))
        }
    }

    private var resolvedBackground: Color {
        guard scheme == .dark else { return C.cardBg }
        switch tone {
        case .group: return ChatInfoCardTint.group
        case .direct: return ChatInfoCardTint.direct
        case .standard: return C.cardBg
        }
    }
}

struct GroupGap: View {

    var bg: Color? = nil
    var body: some View {

        ZStack(alignment: .bottom) {
            HairLine()
            Rectangle().fill(bg ?? C.pageBg).frame(height: L.groupGap)
            HairLine()
        }
    }
}
