import SwiftUI
import UIKit

struct IndexBarTouch: UIViewRepresentable {

    var onMove: (CGFloat) -> Void
    var onEnd: () -> Void

    final class Coord: NSObject {
        var onMove: (CGFloat) -> Void = { _ in }
        var onEnd: () -> Void = { }

        @objc func handlePan(_ g: UIPanGestureRecognizer) {
            guard let v = g.view else { return }
            switch g.state {
            case .began, .changed:
                onMove(g.location(in: v).y)
            case .ended, .cancelled, .failed:
                onEnd()
            default:
                break
            }
        }

        @objc func handleTap(_ g: UITapGestureRecognizer) {
            guard g.state == .ended, let v = g.view else { return }
            onMove(g.location(in: v).y)
            onEnd()
        }
    }

    func makeCoordinator() -> Coord { Coord() }

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        v.isUserInteractionEnabled = true
        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coord.handlePan(_:)))
        v.addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coord.handleTap(_:)))
        v.addGestureRecognizer(tap)
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onMove = onMove
        context.coordinator.onEnd = onEnd
    }
}

struct ContactSection: Identifiable {
    var id: String { letter }
    let letter: String
    let users: [User]
}

struct ContactsView: View {

    @State private var navScrolled: CGFloat = 0
    @ObservedObject private var lang = LangStore.shared
    @EnvironmentObject var app: AppState

    @State private var keyword = ""
    @State private var path = NavigationPath()
    @State private var bubble: String?
    @State private var bubbleTask: Task<Void, Never>?
    @State private var plusMenu = false
    @State private var showScan = false
    @State private var showPhoneContacts = false

    @State private var showSearch = false
    @ObservedObject private var realtime = Realtime.shared

    @State private var idxLetter = ""

    private let idxHaptic = UIImpactFeedbackGenerator(style: .heavy)

    @State private var starIds: [String] = []

    private var listHeadH: CGFloat { max(0, L.navH - 7) }

private var funcs: [(String, String, Color, String)] {
    [
        (Tr("新的朋友"), I.newFriends, Color(hex: 0x2C6E5E), "newFriends"),
        (Tr("群聊"), I.groups, Color(hex: 0x315E78), "groups"),
        (Tr("仅聊天的朋友"), I.chatOnly, Color(hex: 0x8E8E99), "chatOnly"),
        (Tr("标签"), I.tag, OrbitTheme.jadeDeep, "tags"),
        (Tr("公众号"), I.service, Color(hex: 0x5E6579), "officialAccounts")
    ]
}

    private func hiddenContact(_ user: User) -> Bool {
        let username = (user.username ?? "").lowercased()
        if username == "ai" || username == "housekeeper" { return true }
        let name = user.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return name == "ai助手" || name == "ai 助手" || name == "小星"
    }

    private var filtered: [User] {
        let sorted = app.contacts.filter { !hiddenContact($0) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        guard !keyword.isEmpty else { return sorted }
        return sorted.filter { $0.name.contains(keyword) || ($0.username ?? "").contains(keyword) }
    }

    private var starUsers: [User] {
        guard !starIds.isEmpty else { return [] }
        return starIds.compactMap { id in
            app.contacts.first { $0.id == id && !hiddenContact($0) }
        }
    }

    private var sections: [ContactSection] {
        var order: [String] = []
        var map: [String: [User]] = [:]
        for u in filtered {
            let k = pinyinInitial(u.name)
            if map[k] == nil { order.append(k) }
            map[k, default: []].append(u)
        }
        return order.sorted { a, b in
            if a == "#" { return false }
            if b == "#" { return true }
            return a < b
        }.map { ContactSection(letter: $0, users: map[$0] ?? []) }
    }

    private var contactsTopHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(C.tabText1)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(OrbitTheme.ink)
                Text("\(filtered.count) 位联系人")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(OrbitTheme.secondary)
            }

            Spacer(minLength: 8)

            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.62)) {
                    plusMenu = true
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background {
                        ZStack {
                            Circle().fill(.ultraThinMaterial)
                            Circle().fill(
                                LinearGradient(colors: [OrbitTheme.jadeDeep, OrbitTheme.jade],
                                               startPoint: .topLeading,
                                               endPoint: .bottomTrailing)
                            )
                            .opacity(0.76)
                        }
                    }
                    .overlay(Circle().stroke(OrbitTheme.divider, lineWidth: 0.7))
                    .shadow(color: Color.black.opacity(0.10), radius: 8, y: 4)
            }
            .buttonStyle(NavPlusPressStyle())
            .accessibilityLabel(Tr("更多"))
        }
        .padding(.horizontal, 16)
        .frame(height: L.navH)
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {

                VStack(spacing: 0) {

                    contactsTopHeader

                    .background { TopGlassBar(scrolled: navScrolled, fallback: OrbitTheme.canvas, always: true) }

                }
                .zIndex(1)

                ScrollViewReader { proxy in
                    ZStack(alignment: .trailing) {
                        ScrollView {

                            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {

                                TopScrollProbe(space: "contactsScroll")
                                    .frame(height: 0)

                                Color.clear.frame(height: listHeadH)

                                contactsSearchBar
                                    .padding(.horizontal, 16)
                                    .padding(.top, 6)
                                    .padding(.bottom, 10)

                                if keyword.isEmpty {

                                    funcStrip
                                    Color.clear.frame(height: 8)
                                }

                                if keyword.isEmpty, !starUsers.isEmpty {
                                    starStrip
                                    Color.clear.frame(height: 8)
                                }

                                ForEach(sections) { section in
                                    Section {
                                      ForEach(section.users.indices, id: \.self) { i in
                                        let user = section.users[i]
                                        VStack(spacing: 0) {
                                            NavigationLink(value: user) {
                                                contactRow(user)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 3)
                                        .id(user.id)
                                      }
                                    } header: {

                                        HStack(spacing: 6) {
                                            Text(section.letter)
                                                .font(.system(size: 10.5, weight: .bold))
                                                .foregroundStyle(OrbitTheme.secondary)
                                                .padding(.horizontal, 8)
                                                .frame(height: 20)
                                                .background(Capsule().fill(OrbitTheme.field))
                                            Spacer(minLength: 0)
                                        }
                                        .padding(.leading, 14)
                                        .frame(height: max(30, L.ctHeadH))
                                        .background(OrbitTheme.canvas)
                                        .id("letter-\(section.letter)")
                                    }
                                }

                                Group {
                                    if filtered.isEmpty {
                                        Text(Tr("还没有联系人，点右上角 ＋ 添加"))
                                            .font(pf(16))
                                            .foregroundColor(OrbitTheme.secondary)
                                            .frame(maxWidth: .infinity)
                                            .padding(.top, 40)
                                    } else {
                                        Text("\(filtered.count)位联系人")

                                            .font(.system(size: 12.5, weight: .medium))
                                            .foregroundColor(OrbitTheme.tertiary)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 20)
                                    }
                                }
                                .background(OrbitTheme.canvas)

                                Color.clear
                                    .frame(height: L.tabH + L.safeBottom + 12)
                            }
                        }
                        .background(OrbitTheme.canvas)
                        .topScrollTracking($navScrolled, space: "contactsScroll")
                        .refreshable { await app.loadContacts() }

                        if keyword.isEmpty && !sections.isEmpty {
                            ContactIndexBar(
                                available: Set(sections.map { $0.letter }),
                                onPick: { L in
                                    withAnimation(.easeOut(duration: 0.12)) {
                                        proxy.scrollTo("letter-\(L)", anchor: .top)
                                    }
                                    showBubble(L)
                                },
                                onSearch: {
                                    showSearch = true
                                }
                            )
                            .padding(.trailing, 8)
                            .frame(maxHeight: .infinity, alignment: .center)
                        }

                        if let b = bubble {
                            LetterBubble(letter: b)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                                .offset(y: -56)
                        }
                    }
                }

                .padding(.top, -listHeadH)
            }
            .background(OrbitTheme.canvas.ignoresSafeArea(edges: .bottom))

            .background(OrbitTheme.canvas.ignoresSafeArea(edges: .top))
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: User.self) { user in
                ContactCardView(user: user,
                                onOpenChat: { chat in path.append(chat) },
                                onOpenMoments: { id in path.append("moments:" + id) })
            }
            .navigationDestination(for: Chat.self) { chat in
                ChatDetailView(chat: chat)
            }
            .navigationDestination(for: String.self) { key in
                if key.hasPrefix("moments:") {
                    let uid = String(key.dropFirst(8))
                    MomentsView(target: app.contacts.first { $0.id == uid })
                } else if key == "newFriends" {
                    NewFriendsView()
                } else if key == "addFriend" {
                    AddFriendView()
                } else if key == "newGroup" {
                    GroupCreateView { chat in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { path.append(chat) }
                    }
                } else if key == "myQR" {
                    MyQRView()
                } else if key == "groupList" {
                    GroupListView(onOpenChat: { chat in path.append(chat) })
                } else if key == "starTags" {
                    StarOrbitTagsView()
                        .environmentObject(app)
                } else if key == "officialAccounts" {
                    OfficialAccountsView()
                } else {
                    ComingSoonView(title: key)
                }
            }
        }

        .navPlusOverlay($plusMenu, items: [
            NavPlusItem(title: Tr("发起群聊"), symbol: "person.2.fill",
                        colors: [C.green, C.green.opacity(0.78)]) { path.append("newGroup") },
            NavPlusItem(title: Tr("添加朋友"), symbol: "person.badge.plus",
                        colors: [Color(hex: 0x64B5F6), Color(hex: 0x2A6BC4)]) { path.append("addFriend") },
            NavPlusItem(title: Tr("手机联系人"), symbol: "person.text.rectangle",
                        colors: [Color(hex: 0x69A18F), Color(hex: 0x315E78)]) {
                showPhoneContacts = true
            },
            NavPlusItem(title: Tr("扫一扫"), symbol: "qrcode.viewfinder",
                        colors: [C.green, C.green.opacity(0.78)]) { showScan = true }
        ])
        .fullScreenCover(isPresented: $showScan) {
            ScannerView { text in handleScanned(text, app: app) }
        }
        .sheet(isPresented: $showPhoneContacts) {
            PhoneContactsView { user in
                path.append(user)
            }
            .environmentObject(app)
        }

        .fullScreenCover(isPresented: $showSearch) {
            SearchPage(onOpenChat: { c in path.append(c) },
                       onOpenUser: { u in path.append(u) })
                .environmentObject(app)
        }
        .task {
            await app.loadContacts()

            if let ids = try? await API.shared.starredFriends() { starIds = ids }

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if Task.isCancelled { break }
                await app.loadContacts()
            }
        }

        .onChange(of: realtime.event) { ev in
            if ev.type == "friend" || ev.type == "presence" || ev.type == "profile" || ev.user != nil {
                Task { await app.loadContacts() }
            }
        }
    }

    private func showBubble(_ letter: String) {
        bubble = letter
        bubbleTask?.cancel()
        bubbleTask = Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            if !Task.isCancelled { bubble = nil }
        }
    }

    private var contactsSearchBar: some View {
        Button {
            plusMenu = false
            showSearch = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(OrbitTheme.tertiary)
                Text(Tr("搜索"))
                    .font(.system(size: 14))
                    .foregroundColor(OrbitTheme.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 42)
            .background(OrbitTheme.control.fill(OrbitTheme.field))
            .overlay(OrbitTheme.control.stroke(OrbitTheme.divider, lineWidth: 0.6))
            .contentShape(OrbitTheme.control)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Tr("搜索"))
    }

    private var funcStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            OrbitSectionLabel(text: Tr("快捷入口"), count: ctFuncs.count)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                spacing: 8
            ) {
                ForEach(Array(ctFuncs.enumerated()), id: \.offset) { _, item in
                    funcCell(item)
                }
            }
        }
        .padding(13)
        .background(OrbitTheme.cardBackground())
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private func entryRow(_ item: (String, String, Color, String)) -> some View {
        let sym: String
        switch item.3 {
        case "newFriends":      sym = "person.badge.plus"
        case "groups":          sym = "person.3.fill"
        case "tags":            sym = "tag.fill"
        default:                sym = "dot.radiowaves.left.and.right"
        }
        return HStack(spacing: 13) {
            ZStack {
                if !item.1.isEmpty {
                    funcIcon(item, size: 32)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(item.2)
                        Image(systemName: sym)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .frame(width: 32, height: 32)
                }
            }
            .frame(width: 32, height: 32)

            Text(item.0)
                .font(pf(17))
                .foregroundColor(C.label)

            Spacer(minLength: 8)

            if item.3 == "newFriends" && app.showDot("newFriends", auto: app.friendRequests > 0) {
                Text(app.friendRequests > 99 ? "99+" : "\(app.friendRequests)")
                    .font(pf(12, .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, app.friendRequests > 9 ? 6 : 0)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(Capsule().fill(C.red))
            }

        }
        .padding(.leading, 16)
        .padding(.trailing, 18)
        .frame(height: 56)
        .contentShape(Rectangle())
    }

    private var ctFuncs: [(String, String, Color, String)] {
        let want = ["newFriends", "groups", "tags", "officialAccounts"]
        var out: [(String, String, Color, String)] = []
        for k in want {
            if let f = funcs.first(where: { $0.3 == k }) { out.append(f) }
        }
        return out
    }

    private var starStrip: some View {
        VStack(alignment: .leading, spacing: 13) {
            OrbitSectionLabel(text: Tr("星标朋友"), count: starUsers.count)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 15) {
                    ForEach(starUsers) { u in
                        NavigationLink(value: u) {
                            VStack(spacing: 7) {
                                Avatar(path: u.avatarPath, size: 48, radius: 15,

                                       level: (u.qqLevel ?? 0) > 1 ? (u.qqLevel ?? 0) : 0)
                                    .overlay(alignment: .bottomTrailing) {
                                        Image(systemName: "star.fill")
                                            .font(.system(size: 7.5))
                                            .foregroundStyle(.white)
                                            .frame(width: 17, height: 17)
                                            .background(Circle().fill(OrbitTheme.gold))
                                            .overlay(Circle().stroke(OrbitTheme.raised, lineWidth: 1.4))
                                            .offset(x: 3, y: 3)
                                    }
                                Text(u.name)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundColor(OrbitTheme.secondary)
                                    .lineLimit(1)
                                    .frame(width: 58)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 1)
            }
        }
        .padding(13)
        .background(OrbitTheme.cardBackground())
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private func funcCell(_ item: (String, String, Color, String)) -> some View {
        Button {
            openFunc(item.3)
        } label: {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    funcIcon(item, size: 45)

                    if item.3 == "newFriends" && app.showDot("newFriends", auto: app.friendRequests > 0) {
                        Text(app.friendRequests > 99 ? "99+" : "\(app.friendRequests)")
                            .font(pf(11, .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, app.friendRequests > 9 ? 4 : 0)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Capsule().fill(C.red))
                            .offset(x: 6, y: -5)
                    }
                }
                Text(item.0)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(OrbitTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuPressStyle())
    }

    private func openFunc(_ key: String) {
        switch key {
        case "newFriends": path.append("newFriends")
        case "groups": path.append("groupList")
        case "chatOnly": app.show(Tr("仅聊天的朋友：只有聊天记录、没加好友的人会出现在这里"))
        case "tags": path.append("starTags")
        case "officialAccounts": path.append("officialAccounts")
        case "service": path.append("officialAccounts")
        case "work": app.show(Tr("企业联系人：还没绑定企业"))
        default: app.show(Tr("我的企业：还没创建企业"))
        }
    }

    private func funcRow(_ item: (String, String, Color, String)) -> some View {
        Button {
            switch item.3 {
            case "newFriends": path.append("newFriends")
            case "groups": path.append("groupList")
            case "chatOnly": app.show(Tr("仅聊天的朋友：只有聊天记录、没加好友的人会出现在这里"))
            case "tags": path.append("starTags")

            case "officialAccounts": path.append("officialAccounts")
            case "service": path.append("officialAccounts")
            case "work": app.show(Tr("企业联系人：还没绑定企业"))
            default: app.show(Tr("我的企业：还没创建企业"))
            }
        } label: {
            HStack(spacing: L.ctGap) {
                funcIcon(item, size: L.ctIcon)
                Text(item.0)
                    .font(pf(L.ctNameSize))
                    .foregroundColor(C.label)
                Spacer(minLength: 0)

                if item.3 == "newFriends" && app.showDot("newFriends", auto: app.friendRequests > 0) {
                    Text(app.friendRequests > 99 ? "99+" : "\(app.friendRequests)")
                        .font(pf(12.5, .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, app.friendRequests > 9 ? 6 : 0)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Capsule().fill(C.red))
                        .padding(.trailing, 16)
                }
            }
            .padding(.leading, L.ctPadL)
            .frame(height: L.ctRowH)
            .background(C.contactsBg)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuPressStyle())
    }

    @ViewBuilder
    private func funcIcon(_ item: (String, String, Color, String), size: CGFloat) -> some View {
        if let custom = IconOverrides.custom("quick." + item.3) {
            FlexIcon(custom: custom, size: size, color: .white,
                     symbol: RowIcon.sf(action: item.3, label: item.0))
        } else if let kind = StarOrbitContactKind(rawValue: item.3) {
            StarOrbitContactIcon(kind: kind, size: size)
        } else {
            FuncIcon(markup: item.1, bg: item.2, size: size,
                     iconSize: size * 0.44)
        }
    }

    private func contactRow(_ user: User) -> some View {
        HStack(spacing: 11) {

            Avatar(path: user.avatarPath, size: min(L.ctAvatar, 42), radius: 14,
                   level: (user.qqLevel ?? 0) > 1 ? (user.qqLevel ?? 0) : 0)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(user.name)
                        .font(.system(size: 15.5, weight: .semibold))
                        .foregroundColor(OrbitTheme.ink)
                        .lineLimit(1)

                    if (user.qqLevel ?? 0) > 1, GrowthFlags.showInContacts != false {
                        QQLevelBadge(level: user.qqLevel ?? 0, size: L.v(14, 4, 16), maxIcons: 3)
                            .fixedSize()
                    }

                    MemberBadge(tier: user.memberTier,
                                short: user.memberShort,
                                color: user.memberColor,
                                color2: user.memberColor2,
                                height: L.v(12, 3.4, 14))
                        .fixedSize()
                }

                if let subtitle = contactSubtitle(user) {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(OrbitTheme.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
            if starIds.contains(user.id) {
                Image(systemName: "star.fill")
                    .font(.system(size: 10))
                    .foregroundColor(OrbitTheme.gold)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: max(58, L.ctRowH - 2))
        .background(OrbitTheme.control.fill(OrbitTheme.raised))
        .overlay(OrbitTheme.control.stroke(OrbitTheme.divider, lineWidth: 0.6))
        .contentShape(Rectangle())
    }

    private func contactSubtitle(_ user: User) -> String? {
        for value in [user.moodText, user.bio, user.region] {
            let text = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
        }
        return nil
    }

    private func indexBar(_ proxy: ScrollViewProxy) -> some View {
        let rowH = max(1, L.ctIdxItemH)
        return VStack(spacing: 0) {
            ForEach(sections) { section in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo("letter-\(section.letter)", anchor: .top)
                    }
                } label: {
                    Text(section.letter)

                        .font(pf(L.ctIdxSize, ctIdxWeight()))

                        .foregroundColor(idxLetter == section.letter
                                         ? .white
                                         : OrbitTheme.tertiary)
                        .frame(width: 22, height: rowH)
                        .background {
                            if idxLetter == section.letter {
                                Circle()
                                    .fill(OrbitTheme.jade)
                                    .frame(width: max(15, rowH + 1.5))
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }

        .overlay {
            IndexBarTouch(onMove: { y in
                guard !sections.isEmpty else { return }
                let i = min(sections.count - 1, max(0, Int(y / rowH)))
                let letter = sections[i].letter
                guard letter != idxLetter else { return }
                idxLetter = letter
                idxHaptic.impactOccurred(intensity: 1.0)
                proxy.scrollTo("letter-\(letter)", anchor: .top)
            }, onEnd: {
                idxLetter = ""
            })
        }
        .padding(.trailing, 5.7)
        .frame(maxHeight: .infinity, alignment: .center)

        .padding(.vertical, 6)
        .padding(.horizontal, 3)
        .background {
            Capsule(style: .continuous)
                .fill(OrbitTheme.field.opacity(0.94))
                .overlay(Capsule(style: .continuous).stroke(OrbitTheme.divider, lineWidth: 0.6))
                .shadow(color: Color.black.opacity(0.08), radius: 8, y: 3)
        }
        .padding(.trailing, 4)
    }
}

struct ContactCardView: View {
    let user: User
    var onOpenChat: (Chat) -> Void
    var onOpenMoments: (String) -> Void

    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var full: User?
    @State private var thumbs: [String] = []
    @State private var hasMoments = false
    @State private var busy = false
    @State private var showMore = false
    @State private var showInfo = false
    @State private var showPhone = false
    @State private var showApply = false

    @State private var meta: API.FriendMeta?
    @State private var showRemark = false
    @State private var showPerm = false
    @State private var confirmDelete = false

    @State private var showStatus = false

    @State private var aiCall: Chat?

    @State private var showBigAvatar = false

    @State private var showShare = false

    @State private var cardIn = false

    @State private var relationOverride: String?

    private var avatarPath: String { u.avatarPath }

    private var u: User { full ?? user }

    private var statusAlive: Bool {
        !((u.moodIcon ?? "").isEmpty && (u.moodText ?? "").isEmpty)
    }

    private var displayName: String {
        if let r = meta?.remark, !r.trimmingCharacters(in: .whitespaces).isEmpty { return r }
        if let r = u.remark, !r.trimmingCharacters(in: .whitespaces).isEmpty { return r }
        if let r = app.contact(for: u.id)?.remark, !r.trimmingCharacters(in: .whitespaces).isEmpty {
            return r
        }
        return u.name
    }
    private var phone: String { (u.phone ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    private var realNicknameText: String {
        if let name = u.realNickname?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty { return name }
        if let name = app.contact(for: u.id)?.realNickname?
            .trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
        return u.name
    }
    private var isBot: Bool { u.bot == true }

    private var isEyesBot: Bool { (u.username ?? "").lowercased() == "housekeeper" }
    private var relation: String {
        if let r = relationOverride, !r.isEmpty { return r }
        if let r = u.relation, !r.isEmpty { return r }
        return u.id == app.me?.id ? "self" : "none"
    }

    private var sheetBg: Color { scheme == .dark ? Color(hex: 0x1C1C1E) : .white }
    private var scrollBg: Color { C.pageBg }
    private var ink: Color { scheme == .dark ? Color(hex: 0xEDEDED) : Color(hex: 0x1A1A1A) }
    private var gray: Color { scheme == .dark ? Color(hex: 0x8E8E93) : Color(hex: 0x737373) }
    private var link: Color { scheme == .dark ? Color(hex: 0x7D90B8) : Color(hex: 0x576B95) }
    private var lineColor: Color { scheme == .dark ? Color(white: 1, opacity: 0.09) : Color(hex: 0xE5E5E5) }

    var body: some View {
        ZStack {
            Group {
                if UIConfig.text("cardStyle", "old") == "new" {
                    ContactCardNew(name: displayName,
                                   idLine: "账号 " + (u.username ?? ""),
                                   avatarPath: u.avatarPath,
                                   isEyes: isEyesBot,
                                   remark: meta?.remark
                                     ?? (u.remark?.isEmpty == false ? (u.remark ?? "") : ""),
                                   phone: phone,
                                   momentCount: thumbs.count,
                                   momentsRange: u.momentsRange ?? "all",
                                   onClose: { dismiss() },
                                   onMessage: { openChat() },
                                   onVoice: { startCall(video: false) },
                                   onVideo: { startCall(video: true) },
                                   onMoments: hasMoments ? { onOpenMoments(u.id) } : nil)
                } else if UIConfig.text("cardStyle", "old") == "wechat" {
                    wechatCard
                } else {
                    cardBody
                }
            }

            if showMore { morePanel.transition(.opacity) }
        }
        .animation(.easeOut(duration: 0.18), value: showMore)
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .confirmationDialog(Tr("删除好友？"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(Tr("删除"), role: .destructive) { removeFriend() }
            Button(Tr("取消"), role: .cancel) { }
        }

        .navigationDestination(isPresented: $showRemark) {
            FriendRemarkSheet(user: u, meta: meta) { await load() }
                .environmentObject(app)
        }
        .navigationDestination(isPresented: $showPerm) {
            FriendPermSheet(user: u, meta: meta) { await load() }
                .environmentObject(app)
        }

        .navigationDestination(isPresented: $showStatus) {
            FriendStatusView(user: u)
                .environmentObject(app)
        }

        .fullScreenCover(isPresented: $showBigAvatar) {
            PhotoPager(paths: [avatarPath], startIndex: 0) { showBigAvatar = false }
        }
        .confirmationDialog("", isPresented: $showInfo, titleVisibility: .hidden) {
            if isBot {
                Button("昵称：\(realNicknameText)") { }
                Button("账号：\(u.username ?? "—")") { }
                if let b = u.bio, !b.isEmpty { Button("简介：\(b)") { } }
            } else {
                Button("昵称：\(realNicknameText)") { }
                Button("账号：\(u.username ?? "—")") { }
                if let r = meta?.remark ?? u.remark, !r.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button("备注：\(r)") { }
                }

                if let b = u.bio, !b.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button("个性签名：\(b)") { }
                }
                Button("地区：\((u.region?.isEmpty == false) ? u.region! : "未知")") { }
            }
            Button(Tr("取消"), role: .cancel) { }
        }
        .confirmationDialog("", isPresented: $showPhone, titleVisibility: .hidden) {
            Button("拨打 \(phone)") { dial() }
            Button(Tr("取消"), role: .cancel) { }
        }
        .task { await load() }
        .fullScreenCover(item: $aiCall) { c in
            AICallView(chat: c).environmentObject(app)
        }

        .navigationDestination(isPresented: $showApply) {
            FriendApplySheet(user: u) {
                Task {
                    await app.loadContacts()
                    await load()
                }
            }
            .environmentObject(app)
        }

        .sheet(isPresented: $showShare) {
            CardShareView(user: u) {
                Task { await app.loadChats() }
            }
            .environmentObject(app)
        }
    }

    private var wechatCard: some View {
        ContactCardWechat(name: displayName,
                          wxId: "微信号：" + ((u.username?.isEmpty == false) ? u.username! : "—"),
                          region: regionText,
                          avatarPath: avatarPath,
                          isEyes: isEyesBot,
                          remarkLine: tagText,
                          permLine: permText,
                          moreLine: moreText,
                          momentsHint: momentsHint,
                          thumbs: thumbs,
                          isBot: isBot,
                          relation: relation,
                          onClose: { dismiss() },
                          onAvatar: { if !avatarPath.isEmpty { showBigAvatar = true } },
                          onMessage: { openChat() },
                          onVoice: { startCall(video: false) },
                          onVideo: { startCall(video: true) },
                          onAICall: { startAICall() },
                          onMoments: { onOpenMoments(u.id) },
                          onRemark: { showRemark = true },
                          onPerm: { showPerm = true },
                          onMore: { showInfo = true },
                          onMenu: {
                              CrashCatcher.markStep("三点", "联系人三点点击 \(u.id)")
                              showMore = true
                          },
                          onApply: { showApply = true },
                          onAgree: { run(CardAct(title: "同意好友申请", key: "agree")) })
    }

    private var regionText: String {
        (u.region?.isEmpty == false) ? u.region! : Tr("未知")
    }

    private var momentsHint: String {
        if !thumbs.isEmpty { return "" }
        switch u.momentsRange ?? "all" {
        case "3d": return "朋友仅展示最近三天的朋友圈"
        case "6m": return "朋友仅展示最近半年的朋友圈"
        default:   return ""
        }
    }

    private func startCall(video: Bool) {
        if CallCenter.shared.phase != .idle {
            app.show(Tr("正在通话中"))
            return
        }
        CallCenter.shared.start(peerId: u.id,
                                name: u.nickname ?? u.username ?? "对方",
                                avatar: u.avatar ?? "",
                                video: video)
    }

    private var cardBody: some View {
        ZStack {
            VStack(spacing: 0) {
                nav
                ScrollView {
                    VStack(spacing: 12) {
                        hero
                        infoCard
                        if hasMoments { momentsCard }
                        acts
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 24)

                    .opacity(cardIn ? 1 : 0)
                    .offset(y: cardIn ? 0 : 8)
                }
                .background(scrollBg)
            }
            .background(sheetBg.ignoresSafeArea())
        }
        .onAppear { withAnimation(.easeOut(duration: 0.30)) { cardIn = true } }
    }

    private var morePanel: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.36)
                .ignoresSafeArea()
                .onTapGesture { showMore = false }
                .transition(.opacity)

            VStack(spacing: 10) {

                HStack(spacing: 10) {
                    if isEyesBot {
                        JarvisEyesAvatar(size: 34)
                            .frame(width: 40, height: 40)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(sheetBg))
                    } else {
                        Avatar(path: avatarPath, size: 40, radius: 10,
                               level: (u.qqLevel ?? 0) > 1 ? (u.qqLevel ?? 0) : 0)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(displayName)
                            .font(pf(15.5, .medium))
                            .foregroundColor(C.label)
                            .lineLimit(1)
                        Text(Tr("星言号") + "：" + (u.username ?? "-"))
                            .font(pf(12))
                            .foregroundColor(C.subLabel)
                            .lineLimit(1)

                            .copyOnLongPress(u.username ?? "") { app.show($0) }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(C.cardBg))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(C.hairline, lineWidth: 0.6))

                PanelCard(solid: true) {
                    if isBot {
                        PanelRow(symbol: "message.fill", colors: PanelTint.green,
                                 title: Tr("发消息")) { closeMore { openChat() } }
                        PanelDivider()
                        PanelRow(symbol: "phone.fill", colors: PanelTint.blue,
                                 title: Tr("语音通话")) { closeMore { startAICall() } }
                    } else {

                        PanelRow(symbol: "tag.fill", colors: PanelTint.green,
                                 title: Tr("设置备注和标签")) { closeMore { showRemark = true } }
                        PanelDivider()

                        PanelRow(symbol: "square.and.arrow.up", colors: PanelTint.blue,
                                 title: Tr("推荐给朋友")) { closeMore { showShare = true } }
                        PanelDivider()
                        PanelRow(symbol: "lock.shield.fill", colors: PanelTint.blue,
                                 title: Tr("朋友权限")) { closeMore { showPerm = true } }
                        PanelDivider()
                        PanelRow(symbol: meta?.star == true ? "star.slash.fill" : "star.fill",
                                 colors: PanelTint.orange,
                                 title: meta?.star == true ? Tr("取消星标朋友") : Tr("设为星标朋友")) {
                            closeMore { toggleStar() }
                        }
                        PanelDivider()
                        PanelRow(symbol: meta?.block == true ? "hand.raised.slash.fill" : "hand.raised.fill",
                                 colors: PanelTint.purple,
                                 title: meta?.block == true ? Tr("移出黑名单") : Tr("加入黑名单")) {
                            closeMore { toggleBlock() }
                        }
                        PanelDivider()
                        PanelRow(symbol: "exclamationmark.bubble.fill", colors: PanelTint.gray,
                                 title: Tr("投诉")) {
                            closeMore { app.show(Tr("已收到你的投诉，我们会尽快处理")) }
                        }
                        PanelDivider()
                        PanelDangerRow(symbol: "person.badge.minus", title: Tr("删除好友")) {
                            closeMore { confirmDelete = true }
                        }
                    }
                }

                Button { showMore = false } label: {
                    Text(Tr("取消"))
                        .font(pf(16))
                        .foregroundColor(C.label)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background { CardGlassBox(radius: 14) }
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(C.hairline, lineWidth: 0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 14)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func closeMore(_ then: @escaping () -> Void) {
        showMore = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { then() }
    }

    private var nav: some View {
        NavBar(title: "", back: { dismiss() }) {
            Button { showMore = true } label: {
                FlexIcon(custom: IconOverrides.custom("nav.more"), size: 22,
                         color: ink, symbol: "ellipsis")
                    .frame(width: 54, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Tr("更多"))
        }
        .background(sheetBg)
    }

    private var hero: some View {

        PanelHeroCard(glow: Color(hex: 0xF0C24B)) {
            ZStack(alignment: .topTrailing) {
                StarOrbitProfileAccent()

                HStack(alignment: .top, spacing: L.cdHeroGap) {
                    avatarHead
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {

                            Text(displayName)
                                .font(pf(L.cdNameSize, .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .layoutPriority(1)

                            if (u.qqLevel ?? 0) > 0, GrowthFlags.showInProfile != false {
                                QQLevelBadge(level: u.qqLevel ?? 0, size: L.v(15, 4.2, 17), maxIcons: 4)
                                    .fixedSize()
                            }

                            GenderMark(gender: u.gender, size: max(15, L.cdGender))
                            Spacer(minLength: 0)
                        }

                        if statusAlive { statusChip }

                        VStack(alignment: .leading, spacing: 5) {
                            heroLine("昵称：" + ((u.realNickname?.isEmpty == false) ? u.realNickname! : u.name))
                            heroLine("账号：" + ((u.username?.isEmpty == false) ? u.username! : "—"))
                            if isBot {
                                heroLine("简介：" + ((u.bio?.isEmpty == false) ? u.bio! : "您的私人助理"))
                            } else {
                                heroLine("地区：" + ((u.region?.isEmpty == false) ? u.region! : "未知"))
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var avatarHead: some View {
        Group {
            if isEyesBot {
                JarvisEyesAvatar(size: L.cdAvatar * 0.84)
                    .frame(width: L.cdAvatar, height: L.cdAvatar)
                    .background(RoundedRectangle(cornerRadius: max(12, L.cdAvatarRadius), style: .continuous)
                        .fill(Color.white.opacity(0.1)))
            } else {
            Avatar(path: u.avatarPath, size: L.cdAvatar, radius: max(12, L.cdAvatarRadius),
                   level: (u.qqLevel ?? 0) > 1 ? (u.qqLevel ?? 0) : 0)
                    .contentShape(Rectangle())
                    .onTapGesture { if !avatarPath.isEmpty { showBigAvatar = true } }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: max(12, L.cdAvatarRadius), style: .continuous)

            .stroke(LinearGradient(colors: [Color.white.opacity(0.85),
                                            Color(hex: 0xF0C24B).opacity(0.75),
                                            Color.white.opacity(0.25)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1.6))
        .shadow(color: Color.black.opacity(0.38), radius: 12, y: 5)
        .shadow(color: Color(hex: 0xF0C24B).opacity(0.18), radius: 14, y: 2)
    }

    private func heroLine(_ text: String) -> some View {

        let parts = text.split(separator: "：", maxSplits: 1).map(String.init)
        return HStack(spacing: 3) {
            if parts.count == 2 {
                Text(parts[0] + "：")
                    .foregroundColor(.white.opacity(0.48))
                Text(parts[1])
                    .foregroundColor(.white.opacity(0.9))
            } else {
                Text(text).foregroundColor(.white.opacity(0.82))
            }
        }
        .font(pf(12.5))
        .lineLimit(1)
    }

    private var statusChip: some View {
        let c = MoodColor.clean(u.moodColor)
        let cap = (u.moodCaption ?? "").trimmingCharacters(in: .whitespaces)
        let lab = (u.moodLabel ?? "").trimmingCharacters(in: .whitespaces)
        let text = cap.isEmpty ? (lab.isEmpty ? (u.moodText ?? "") : lab) : cap
        return Button { showStatus = true } label: {
            HStack(spacing: 4) {
                Text(u.moodIcon ?? "🙂")
                Text(text).lineLimit(1)
            }
            .font(pf(12))
            .foregroundColor(.white)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(Capsule().fill(c.isEmpty ? Color.white.opacity(0.16) : Color(hexString: c)))
            .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 0.7))
        }
        .buttonStyle(.plain)
    }

    private var infoCard: some View {
        PanelCard(solid: true) {
            PanelRow(symbol: "person.text.rectangle.fill", colors: PanelTint.blue,
                     title: Tr("朋友资料")) { showInfo = true }

            if !phone.isEmpty {
                PanelDivider()
                PanelRow(symbol: "phone.fill", colors: PanelTint.green,
                         title: Tr("电话"), value: phone) { showPhone = true }
            }

            if !isBot && relation == "friend" {

                PanelDivider()
                PanelRow(symbol: "tag.fill", colors: PanelTint.orange,
                         title: Tr("标签"), value: tagText) { showRemark = true }

                PanelDivider()
                PanelRow(symbol: "lock.shield.fill", colors: PanelTint.purple,
                         title: Tr("朋友权限"), value: permText) { showPerm = true }

                PanelDivider()
                PanelRow(symbol: "info.circle.fill", colors: PanelTint.gray,
                         title: Tr("更多信息"), value: moreText) { showInfo = true }
            }
        }
    }

    private var momentsCard: some View {
        PanelCard(solid: true) {
            Button { onOpenMoments(u.id) } label: {
                HStack(spacing: 11) {
                    PanelIcon(symbol: "photo.on.rectangle.angled", colors: PanelTint.teal)
                    Text(Tr("朋友圈"))
                        .font(pf(16))
                        .foregroundColor(C.label)
                    Spacer(minLength: 8)

                    HStack(spacing: 6) {
                        ForEach(thumbs.prefix(3).indices, id: \.self) { i in
                            RemoteImage(path: thumbs[i])
                                .frame(width: 38, height: 38)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                    }
                    Chevron(size: 9, line: 1.6)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 62)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private struct CardAct {
        var title: String
        var key: String
    }

    private var actList: [CardAct] {

        if isBot {
            return [CardAct(title: "发消息", key: "msg"),
                    CardAct(title: "语音通话", key: "aicall")]
        }
        switch relation {
        case "friend", "self":
            return [CardAct(title: "发消息", key: "msg"),
                    CardAct(title: "音视频通话", key: "call")]
        case "incoming":
            return [CardAct(title: "同意好友申请", key: "agree"),
                    CardAct(title: "发消息", key: "msg")]
        case "requested":
            return [CardAct(title: "已发送好友申请", key: "pending")]
        default:
            return [CardAct(title: "添加到通讯录", key: "add")]
        }
    }

    private var acts: some View {
        PanelCard(solid: true) {
            ForEach(actList.indices, id: \.self) { i in
                if i > 0 { PanelDivider() }
                actRow(actList[i])
            }
        }
    }

    private func actRow(_ act: CardAct) -> some View {
        let symbol: String
        let colors: [Color]
        switch act.key {
        case "msg":     symbol = "message.fill";        colors = PanelTint.green
        case "call":    symbol = "video.fill";          colors = PanelTint.blue
        case "aicall":  symbol = "phone.fill";          colors = PanelTint.blue
        case "agree":   symbol = "person.badge.plus";   colors = PanelTint.green
        case "add":     symbol = "person.badge.plus";   colors = PanelTint.green
        default:        symbol = "clock.fill";          colors = PanelTint.gray
        }
        let pending = act.key == "pending"
        return Button { run(act) } label: {
            HStack(spacing: 11) {
                PanelIcon(symbol: symbol, colors: colors)
                Text(act.title)
                    .font(pf(16, .medium))
                    .foregroundColor(pending ? C.subLabel : C.label)
                Spacer(minLength: 0)
                if !pending { Chevron(size: 9, line: 1.6) }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(pending)
    }

    private func run(_ act: CardAct) {
        switch act.key {
        case "msg":
            openChat()
        case "aicall":
            startAICall()
        case "call":

            if CallCenter.shared.phase != .idle {
                app.show(Tr("正在通话中"))
            } else {
                CallCenter.shared.start(peerId: u.id, name: u.nickname ?? u.username ?? "对方",
                                        avatar: u.avatar ?? "", video: false)
            }
        case "add":
            showApply = true
        case "agree":
            busy = true
            relationOverride = "friend"
            app.applyFriendAccepted(u)
            Task {

                let res = await API.shared.respondFriend(userId: u.id, accept: true)
                if res.ok {
                    UINotification.lightTap()
                    app.show(Tr("已同意，现在可以聊天了"))
                    if let n = res.pending { app.friendRequests = n }
                    await app.loadContacts()
                    await app.loadChats()
                    if let chat = res.chat {
                        app.ensureChatVisible(chat)
                        app.openChat = chat
                    } else {
                        app.wantChatsTab = true
                    }
                    dismiss()
                    await load()
                } else {
                    relationOverride = nil
                    await app.loadContacts()
                    await app.loadChats()
                    app.show(Tr("到「通讯录 → 新的朋友」里同意"))
                }
                busy = false
            }
        default:
            app.show(Tr("已经发过申请了，等对方通过"))
        }
    }

    private func openChat(then after: (() -> Void)? = nil) {
        busy = true
        Task {
            if let chat = try? await API.shared.openDirect(userId: u.id) {
                app.revealChatLocally(chat.id)
                app.ensureChatVisible(chat)
                onOpenChat(chat)
                after?()
            } else {
                app.show(Tr("打不开聊天"))
            }
            busy = false
        }
    }

    private var tagText: String {
        let tags = (meta?.tags ?? []).filter { !$0.isEmpty }
        return tags.isEmpty ? Tr("未设置") : tags.joined(separator: "、")
    }

    private var permText: String {
        if meta?.block == true { return Tr("已加入黑名单") }
        if meta?.noMoments == true { return Tr("不看他的朋友圈") }
        if meta?.hideMyMoments == true { return Tr("不让他看我的朋友圈") }
        return Tr("聊天、朋友圈")
    }

    private var moreText: String {
        var bits: [String] = []
        if let g = u.mutualGroups, g > 0 { bits.append("共同群聊 \(g) 个") }
        if let s = meta?.source, !s.isEmpty { bits.append(s == "me" ? "我添加的" : "他添加的我") }
        bits.append("添加时间 " + (addedText.isEmpty ? "—" : addedText))
        return bits.joined(separator: " · ")
    }

    private var addedText: String {
        guard let s = meta?.addedAt, s.count >= 10 else { return "" }
        let y = s.prefix(4), m = s.dropFirst(5).prefix(2), d = s.dropFirst(8).prefix(2)
        return "\(Int(y) ?? 0)年\(Int(m) ?? 0)月\(Int(d) ?? 0)日"
    }

    private func startAICall() {
        busy = true
        Task {
            if let chat = try? await API.shared.openDirect(userId: u.id) {
                aiCall = chat
            } else {
                app.show(Tr("打不开对话"))
            }
            busy = false
        }
    }

    private func dial() {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty, let url = URL(string: "tel://\(digits)") else { return }
        UIApplication.shared.open(url)
    }

    private func load() async {
        if let fresh = try? await API.shared.user(id: user.id) { full = fresh }

        if relation == "friend" || relation == "self" {
            if let m = try? await API.shared.friendMeta(userId: user.id) { meta = m }
        }
        if let list = try? await API.shared.moments(limit: 6, userId: user.id) {
            var images: [String] = []
            for m in list {
                for src in (m.images ?? []) where images.count < 5 {
                    images.append(src)
                }

                if let c = m.videoCover, !c.isEmpty, images.count < 5 {
                    images.append(c)
                }
            }
            thumbs = images
            hasMoments = !list.isEmpty
        }
    }

    private func toggleStar() {
        let next = !(meta?.star == true)
        let previous = meta
        var optimistic = meta ?? API.FriendMeta()
        optimistic.star = next
        meta = optimistic
        Task {
            if await API.shared.setFriendMeta(userId: u.id, star: next) {
                app.show(next ? Tr("已设为星标朋友") : Tr("已取消星标"))
            } else {
                meta = previous
                app.show(Tr("没保存上，再试一次"))
            }
        }
    }

    private func toggleBlock() {
        let next = !(meta?.block == true)
        let previous = meta
        var optimistic = meta ?? API.FriendMeta()
        optimistic.block = next
        meta = optimistic
        Task {
            if await API.shared.setFriendMeta(userId: u.id, block: next) {
                app.show(next ? Tr("已加入黑名单，他发不了消息给你") : Tr("已移出黑名单"))
            } else {
                meta = previous
                app.show(Tr("没保存上，再试一次"))
            }
        }
    }

    private func removeFriend() {
        let userId = u.id
        let removedChatIds = app.chats.filter {
            ($0.type ?? "direct") == "direct" && ($0.memberIds ?? []).contains(userId)
        }.map(\.id)
        app.applyFriendRemoved(userId: userId)
        app.openChat = nil
        app.wantChatsTab = true
        dismiss()
        app.show(Tr("已删除好友"))
        Task {
            if let err = await API.shared.removeFriend(userId: userId) {
                app.show(Tr("删除失败，已恢复：") + err)
                for chatId in removedChatIds { app.revealChatLocally(chatId) }
                await app.loadContacts()
                await app.loadChats()
                return
            }

            for chatId in removedChatIds { app.forgetChatHistory(chatId, notify: false) }
            await app.loadContacts()
            await app.loadChats()
        }
    }
}

struct GenderMark: View {
    let gender: String?
    var size: CGFloat = 14

    var body: some View {
        Group {
            if gender == "male" {
                figure(male: true)
            } else if gender == "female" {
                figure(male: false)
            } else {
                Color.clear.frame(width: 0, height: 0)
            }
        }
    }

    private func figure(male: Bool) -> some View {
        let tint = male ? Color(hex: 0x10AEFF) : Color(hex: 0xFF7BA9)
        return ZStack {
            Path { p in
                p.addEllipse(in: CGRect(x: 8.1, y: 1.8, width: 7.8, height: 7.8))
            }
            .fill(tint)

            Path { p in
                if male {
                    p.move(to: CGPoint(x: 5.6, y: 22.2))
                    p.addLine(to: CGPoint(x: 8.1, y: 11.4))
                    p.addLine(to: CGPoint(x: 15.9, y: 11.4))
                    p.addLine(to: CGPoint(x: 18.4, y: 22.2))
                    p.addLine(to: CGPoint(x: 14.2, y: 22.2))
                    p.addLine(to: CGPoint(x: 12.0, y: 16.6))
                    p.addLine(to: CGPoint(x: 9.8, y: 22.2))
                } else {
                    p.move(to: CGPoint(x: 12.0, y: 11.0))
                    p.addLine(to: CGPoint(x: 18.8, y: 22.2))
                    p.addLine(to: CGPoint(x: 5.2, y: 22.2))
                }
                p.closeSubpath()
            }
            .fill(tint)
        }
        .frame(width: 24, height: 24)
        .scaleEffect(size / 24, anchor: .center)
        .frame(width: size, height: size)
    }
}
