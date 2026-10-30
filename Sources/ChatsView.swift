import SwiftUI
import UIKit
import Darwin

struct RowSwipeCatcher: UIViewRepresentable {

    var onTap: (CGPoint) -> Void

    var onBegan: () -> Void

    var onChanged: (CGFloat) -> Void

    var onEnded: (CGFloat, CGFloat) -> Void

    final class Coord: NSObject, UIGestureRecognizerDelegate {
        var onTap: (CGPoint) -> Void = { _ in }
        var onBegan: () -> Void = { }
        var onChanged: (CGFloat) -> Void = { _ in }
        var onEnded: (CGFloat, CGFloat) -> Void = { _, _ in }

        private var horizontal = false
        private weak var frozenScroll: UIScrollView?

        private func freezeEnclosingScroll(_ view: UIView?) {
            var candidate = view
            while let current = candidate {
                if let scroll = current as? UIScrollView {
                    scroll.isScrollEnabled = false
                    frozenScroll = scroll
                    return
                }
                candidate = current.superview
            }
        }

        private func restoreEnclosingScroll() {
            frozenScroll?.isScrollEnabled = true
            frozenScroll = nil
        }

        @objc func handlePan(_ g: UIPanGestureRecognizer) {
            let t = g.translation(in: g.view)
            switch g.state {
            case .began:
                horizontal = false
            case .changed:
                if !horizontal {

                    guard abs(t.x) > abs(t.y) + 4 else { return }
                    horizontal = true
                    freezeEnclosingScroll(g.view)
                    onBegan()
                }
                onChanged(t.x)
            case .ended, .cancelled, .failed:
                if horizontal { onEnded(t.x, g.velocity(in: g.view).x) }
                restoreEnclosingScroll()
                horizontal = false
            default:
                break
            }
        }

        @objc func handleTap(_ g: UITapGestureRecognizer) {
            onTap(g.location(in: g.view))
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }

    func makeCoordinator() -> Coord { Coord() }

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        v.isUserInteractionEnabled = true

        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coord.handlePan(_:)))
        pan.delegate = context.coordinator
        pan.cancelsTouchesInView = false
        pan.delaysTouchesBegan = false
        v.addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coord.handleTap(_:)))
        tap.delegate = context.coordinator

        tap.cancelsTouchesInView = false
        v.addGestureRecognizer(tap)

        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onBegan = onBegan
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
    }
}

struct ChatRow: View {
    let chat: Chat
    @EnvironmentObject private var app: AppState
    @State private var fetchedPeer: User?

    var onTapAvatar: (() -> Void)? = nil

    var body: some View {

        HStack(alignment: .center, spacing: 12) {
            avatarBlock
            textColumn
            Spacer(minLength: 6)
            rightColumn
        }
        .padding(.horizontal, 14)
        .frame(height: L.rowH)
        .contentShape(Rectangle())
        .task { await loadPeerIfNeeded() }
    }

    private var avatarTop: CGFloat { max(0, (L.rowH - L.avatar) / 2) }

    private var peerId: String? {
        guard chat.type != "group" else { return nil }
        let sender = chat.lastMessage?.senderId
        return (chat.memberIds ?? []).first { $0 != app.me?.id }
            ?? (sender != app.me?.id ? sender : nil)
    }

    private var peer: User? {
        guard let peerId, !peerId.isEmpty else { return nil }
        return app.contact(for: peerId) ?? fetchedPeer
    }

    private var displayTitle: String {
        let raw = (chat.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty, raw != "未知用户" { return raw }
        if let peer { return peer.name }
        let sender = (chat.lastMessage?.senderName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if chat.lastMessage?.senderId == peerId,
           !sender.isEmpty, sender != "未知用户" { return sender }
        return raw.isEmpty ? "会话" : raw
    }

    private var displayAvatar: String {
        let raw = (chat.avatar ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty { return raw }
        return peer?.avatarPath ?? ""
    }

    private func loadPeerIfNeeded() async {
        guard let peerId, !peerId.isEmpty,
              app.contact(for: peerId) == nil else { return }
        fetchedPeer = try? await API.shared.user(id: peerId)
    }

    private var avatarBlock: some View {
        Group {
            if let tap = onTapAvatar {
                avatar.contentShape(Rectangle()).onTapGesture { tap() }
            } else {
                avatar
            }
        }
    }

    private var textColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text(displayTitle)
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundStyle(OrbitTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .layoutPriority(1)

                if chat.showsOfficialMark {
                    OfficialMark()
                        .fixedSize()
                }

                if let lv = chat.qqLevel, lv > 1, GrowthFlags.showInChats == true {
                    QQLevelBadge(level: lv, size: L.v(13, 3.6, 15), maxIcons: 3)
                        .fixedSize()
                }

                MemberBadge(tier: chat.memberTier,
                            short: chat.memberShort,
                            color: chat.memberColor,
                            color2: chat.memberColor2,
                            height: L.v(11.5, 3.2, 13))
                    .fixedSize()

            }
            mentionPreview
                .font(.system(size: 12.5))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var mentionPreview: Text {
        let raw = (chat.lastMessage?.preview ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let preview = raw.isEmpty ? fallbackPreview(chat.lastMessage?.kind ?? "") : raw
        let body = Text(preview).foregroundColor(OrbitTheme.secondary)
        guard chat.lastMessage?.mentionMe == true, chat.unreadCount > 0 else { return body }
        return Text("[有人@我] ").foregroundColor(OrbitTheme.jade) + body
    }

    /// 旧服务端或实时推送偶尔只带 kind 不带 preview，列表仍按微信占位。
    private func fallbackPreview(_ kind: String) -> String {
        switch kind {
        case "image", "images": return "[图片]"
        case "video", "livephoto": return "[视频]"
        case "audio", "voice": return "[语音]"
        case "file": return "[文件]"
        case "link", "oa": return "[链接]"
        case "music": return "[音乐]"
        case "location": return "[位置]"
        case "card": return "[名片]"
        case "transfer": return "[转账]"
        case "redpacket": return "[红包]"
        case "gift": return "[礼物]"
        case "miniapp", "mini", "app", "mall": return "[小程序]"
        case "channels", "channel", "feed", "shortvideo": return "[视频号]"
        case "call", "voicecall": return "[语音通话]"
        case "videocall": return "[视频通话]"
        case "system": return "消息"
        case "": return idlePreview
        default: return "[消息]"
        }
    }

    private var idlePreview: String {
        if chat.type == "group" {
            return "群聊"
        }
        if chat.bot == "qqnews" { return "看看今天的热点" }
        if chat.showsOfficialMark { return "查看官方内容" }
        return "新的会话"
    }

    private var rightColumn: some View {
        VStack(alignment: .trailing, spacing: 7) {
            Text(TimeFmt.list(chat.lastMessage?.createdAt ?? chat.updatedAt))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(OrbitTheme.tertiary)
                .fixedSize()
        }
    }

    @ViewBuilder
    private var unreadOnAvatar: some View {
        if chat.unreadCount > 0 {

            if (chat.muted == true || chat.flagged == true), chat.bot != "qqnews" {
                Circle()
                    .fill(OrbitTheme.tertiary)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(OrbitTheme.raised, lineWidth: 1.4))
                    .offset(x: 2, y: -2)
            } else {
                OrbitUnreadBadge(count: chat.unreadCount)
                    .offset(x: 4, y: -4)
            }
        }
    }

    private var avatar: some View {
        Group {
            if (chat.avatar ?? "").isEmpty,
               chat.type == "group" || (chat.memberCount ?? 0) > 2 {
                GroupAvatarMosaic(chatId: chat.id,
                                  memberIds: chat.memberIds ?? [],
                                  size: L.avatar, radius: 16)
            } else {
                Avatar(path: displayAvatar, size: L.avatar, radius: 16,
                       group: chat.type == "group" || (chat.memberCount ?? 0) > 2,
                       level: chat.qqLevel ?? 0)
            }
        }

            .overlay(alignment: .bottomTrailing) {
                if let icon = chat.moodIcon, !icon.isEmpty {
                    Text(icon)
                        .font(.system(size: 9))
                        .frame(width: 17, height: 17)
                        .background(Circle().fill(C.cardBg))
                        .overlay(Circle().stroke(C.hairline, lineWidth: 0.5))
                        .offset(x: 5, y: 5)
                }
            }

            .overlay(alignment: .topTrailing) {
                unreadOnAvatar
            }
    }
}

extension Notification.Name {

    static let chrisRowSwipe = Notification.Name("chris.rowSwipe")
    static let chrisChatCleared = Notification.Name("chris.chatCleared")
}

struct SwipeChatRow: View {
    enum Mode { case none, hideConfirm, delConfirm }

    let chat: Chat
    var onOpen: () -> Void

    var onTapAvatar: (() -> Void)? = nil
    var onUnread: () -> Void
    var onHide: (Bool) -> Void
    var onDelete: () -> Void
    var cardStyle: Bool = false
    var horizontalInset: CGFloat = 0

    @State private var offset: CGFloat = 0
    @State private var startOffset: CGFloat = 0
    @State private var mode: Mode = .none
    @State private var dragging = false

    private var btnW: CGFloat { UIConfig.num("swipeBtnW", 80) }
    private var btnFont: CGFloat { UIConfig.num("swipeFont", 15) }
    private var fullW: CGFloat { btnW * 3 }

    private var cardInset: CGFloat { UIConfig.num("swipeInset", 0) }
    private var cardRadius: CGFloat { UIConfig.num("swipeRadius", 0) }
    private var iconSize: CGFloat { UIConfig.num("swipeIcon", 17) }
    private var cardH: CGFloat { max(20, L.rowH - cardInset * 2) }

    private var blueBg: Color { UIConfig.color("swipeBlue", 0x2E7CF6, 0x0A84FF) }

    private var yellowBg: Color { UIConfig.color("swipeYellow", 0xE0A22B, 0xD9932A) }

    private var redBg: Color { UIConfig.color("swipeRed", 0xFA5151, 0xFA5151) }

    @State private var crossedOpen = false

    @State private var dragVelocity: CGFloat = 0

    private var barReveal: CGFloat {
        min(1, max(0, -offset / max(1, fullW)))
    }

    private let haptic = UIImpactFeedbackGenerator(style: .light)

    private var swipeSpring: Animation {

        swipeSpringFor(velocity: dragVelocity)
    }

    private func swipeSpringFor(velocity vx: CGFloat) -> Animation {
        let fast = abs(vx) > 700
        return .interpolatingSpring(mass: fast ? 0.75 : 0.9,
                                    stiffness: fast ? 420 : 320,
                                    damping: fast ? 30 : 26)
    }

    private var rowWidth: CGFloat { max(1, L.width - max(0, horizontalInset) * 2) }
    private var rowBg: Color { cardStyle ? .clear : OrbitTheme.raised }

    var body: some View {
        ZStack(alignment: .trailing) {

            ChatRow(chat: chat, onTapAvatar: onTapAvatar)
                .frame(width: rowWidth, height: L.rowH, alignment: .leading)
                .background(rowBg)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(OrbitTheme.divider)
                        .frame(height: 0.5)
                        .padding(.leading, 76)
                }
                .offset(x: offset)
                .contentShape(Rectangle())
                .zIndex(1)

            actionButtons
                .allowsHitTesting(offset != 0)
                .zIndex(2)
        }
        .frame(width: rowWidth, height: L.rowH, alignment: .leading)

        .background(rowBg)
        .clipped()

        .overlay(alignment: .leading) {
            RowSwipeCatcher(
                onTap: { p in
                    if offset != 0 {
                        close()
                    } else if p.x < L.rowPadL + L.avatar + 10, let tap = onTapAvatar {
                        tap()
                    } else {
                        onOpen()
                    }
                },
                onBegan: {
                    dragging = true
                    startOffset = offset
                    dragVelocity = 0
                    crossedOpen = (-offset > fullW * 0.42)

                    NotificationCenter.default.post(name: .chrisRowSwipe, object: chat.id)
                },
                onChanged: { dx in
                    var x = startOffset + dx
                    if x > 0 {

                        x = min(10, x * 0.22)
                    } else if x < -fullW {

                        x = -(fullW + min(92, (-x - fullW) * 0.30))
                    }

                    offset = x

                    let nowCrossed = (-offset > fullW * 0.42)
                    if nowCrossed != crossedOpen {
                        crossedOpen = nowCrossed
                        haptic.impactOccurred(intensity: nowCrossed ? 0.55 : 0.35)
                    }

                },
                onEnded: { _, vx in
                    dragging = false
                    dragVelocity = vx
                    settle(velocity: vx)
                }
            )
            .frame(width: max(0, rowWidth + offset), height: L.rowH)
        }

        .onReceive(NotificationCenter.default.publisher(for: .chrisRowSwipe)) { note in
            if let id = note.object as? String {
                if id != chat.id { collapse() }
            } else {
                collapse()
            }
        }
    }

    private func collapse() {
        guard offset != 0 || mode != .none else { return }
        dragVelocity = 0
        withAnimation(swipeSpring) {
            offset = 0
            mode = .none
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 0) {
            switch mode {
            case .none:

                bar("标为未读", "envelope.badge.fill", blueBg, btnW) {
                    onUnread()
                    close()
                }
                bar("不显示", "eye.slash.fill", yellowBg, btnW, sep: true) {
                    onHide(false)
                    close()
                }
                bar("删除", "trash.fill", redBg, btnW, sep: true) {
                    onDelete()
                    close()
                }
            case .hideConfirm:

                bar("不显示该聊天", "eye.slash.fill", yellowBg, fullW) {
                    onHide(false)
                    close()
                }
            case .delConfirm:

                bar("清空记录同时不显示聊天", "trash.fill", redBg, fullW) {
                    onDelete()
                    close()
                }
            }
        }
        .frame(height: cardH)
        .clipShape(RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(cardInset > 0 ? 0.22 : 0),
                              lineWidth: cardInset > 0 ? 0.6 : 0)
        )
        .padding(.vertical, cardInset)
        .frame(width: max(0, -offset), height: L.rowH, alignment: .trailing)
        .clipped()

        .shadow(color: .black.opacity(cardInset > 0 ? 0.16 : 0),
                radius: cardInset > 0 ? 9 : 0, x: 0, y: 3)
    }

    private func settle(velocity vx: CGFloat) {
        if mode != .none {
            withAnimation(swipeSpring) { offset = -fullW }
            return
        }
        let open: Bool
        if vx <= -420 {
            open = true
        } else if vx >= 420 {
            open = false
        } else {
            open = -offset > fullW * 0.42
        }
        if open { haptic.impactOccurred() }
        withAnimation(swipeSpring) {
            offset = open ? -fullW : 0
            if !open { mode = .none }
        }
    }

    private func bar(_ title: String, _ symbol: String, _ bg: Color, _ width: CGFloat,
                     sep: Bool = false,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundColor(.white)
                Text(title)
                    .font(pfExact(btnFont, .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .scaleEffect(0.88 + 0.12 * barReveal)
            .opacity(0.62 + 0.38 * barReveal)
            .frame(width: max(0, width), height: cardH)
            .background(bg)
            .overlay(alignment: .leading) {
                if sep {
                    Rectangle()
                        .fill(Color.white.opacity(0.36))
                        .frame(width: 0.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowSwipeActionButtonStyle())
    }

    private func close() {
        dragVelocity = 0
        withAnimation(swipeSpring) {
            offset = 0
            mode = .none
        }
    }
}

private struct RowSwipeActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }
}

struct ChatsView: View {
    private enum ChatFilter: String, CaseIterable, Identifiable, Hashable {
        case all = "全部"
        case unread = "未读"
        case group = "群聊"
        case official = "公众号"
        case pinned = "置顶"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .all: return "rectangle.stack"
            case .unread: return "circle.fill"
            case .group: return "person.2"
            case .official: return "megaphone"
            case .pinned: return "pin"
            }
        }
    }

    private struct ChatFilterSnapshot {
        let list: [Chat]
        let unreadCounts: [ChatFilter: Int]
    }

    @ObservedObject private var lang = LangStore.shared

    @ObservedObject private var eyes = EyesStore.shared
    @EnvironmentObject var app: AppState

    @Environment(\.colorScheme) private var scheme

    @State private var keyword = ""
    @State private var chatFilter: ChatFilter = .all
    @Namespace private var filterSelectionNS
    private let chatFilterH: CGFloat = 46
    private var chatFilterVisible: Bool { UIConfig.num("chatsOrbitFilter", 1) > 0 }
    private var chatFilterOffset: CGFloat { chatFilterVisible ? chatFilterH : 0 }
    private var chatsCardStyle: Bool { UIConfig.num("chatsOrbitCard", 1) > 0 }
    private var chatsCardInset: CGFloat { max(8, UIConfig.num("chatsOrbitInset", 12)) }
    private var chatsCardRadius: CGFloat { max(16, UIConfig.num("chatsOrbitRadius", 22)) }
    private var chatsPageFill: Color {
        OrbitTheme.raised
    }

    @State private var scrolled: CGFloat = 0

    @State private var pullDown: CGFloat = 0
    @State private var floorDragActive = false

    @State private var floorUp = false

    private var floorOn: Bool { UIConfig.num("chatsFloor", 1) > 0 }

    private var floorPull: CGFloat { max(40, UIConfig.num("chatsFloorPull", 120)) }

    @State private var floorTick = 0

    @State private var floorApps: [MiniApp] = []

    @ObservedObject private var mallWeather = MallWeather.shared
    @ObservedObject private var floorCity = DDCity.shared

    @State private var showFloorCity = false


    @State private var showAppSearch = false

    private func heavyPull(_ d: CGFloat) -> CGFloat {
        let g = UIConfig.num("floorGravity", 1)
        if g <= 0 || d <= 60 { return d }
        let tail = max(0, d - 60)
        return 60 + CGFloat(pow(Double(tail), 0.82)) * 0.62 + tail * 0.38
    }
    @State private var path = NavigationPath()

    @State private var oaOpenId = ""
    @State private var showOA = false
    @State private var showOAList = false
    @State private var plusMenu = false
    @State private var showScan = false

    @State private var showPayCode = false
    @State private var showAccounts = false
    @State private var openRow: String?

    @State private var showSearch = false

    @State private var botCardChat: Chat?

    @State private var botChat: Chat?

    private var eyesTint: Color {
        UIConfig.colorIfSet("eyesColor") ?? UIConfig.color("navPlusBg", 0x0F5A3C, 0x0F5A3C)
    }

    private func chatSnapshot() -> ChatFilterSnapshot {
        let base = app.chats.filter { c in
            guard c.botRank != 0,
                  !c.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return false }
            let title = (c.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let avatar = (c.avatar ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return !title.isEmpty || c.lastMessage != nil || !avatar.isEmpty
        }

        var counts: [ChatFilter: Int] = [:]
        func add(_ filter: ChatFilter, _ chat: Chat) {
            counts[filter, default: 0] += max(0, chat.unreadCount)
        }
        for chat in base {
            add(.all, chat)
            add(.unread, chat)
            if chat.type == "group" || (chat.memberCount ?? 0) > 2 { add(.group, chat) }
            if !(chat.oaId ?? "").isEmpty || chat.oaDigest == true { add(.official, chat) }
            if chat.pinned == true { add(.pinned, chat) }
        }

        let filtered: [Chat]
        switch chatFilter {
        case .all: filtered = base
        case .unread: filtered = base.filter { $0.unreadCount > 0 || $0.flagged == true }
        case .group: filtered = base.filter { $0.type == "group" || ($0.memberCount ?? 0) > 2 }
        case .official: filtered = base.filter { !($0.oaId ?? "").isEmpty || $0.oaDigest == true }
        case .pinned: filtered = base.filter { $0.pinned == true }
        }
        let shown = keyword.isEmpty ? filtered : filtered.filter {
            $0.name.contains(keyword) || (($0.lastMessage?.preview ?? "").contains(keyword))
        }
        return ChatFilterSnapshot(list: shown, unreadCounts: counts)
    }

    @ViewBuilder
    private func filterReminder(_ item: ChatFilter, count: Int) -> some View {
        if count > 0 {
            Group {
                if item == .all {
                    Circle().fill(C.red).frame(width: 7, height: 7)
                } else {
                    Text(count > 99 ? "99+" : "\(count)")
                        .font(pfExact(9, .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, count > 9 ? 4 : 3)
                        .frame(minWidth: 15)
                        .frame(height: 15)
                        .background(Capsule().fill(C.red))
                }
            }
            .overlay {
                if item != .all {
                    Capsule().stroke(OrbitTheme.canvas, lineWidth: 1)
                }
            }
            .offset(x: -3, y: -3)
        }
    }

    private func chooseFilter(_ item: ChatFilter) {
        guard chatFilter != item else { return }
        NotificationCenter.default.post(name: .chrisRowSwipe, object: nil)
        scrolled = 0
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(.spring(response: 0.30, dampingFraction: 0.92)) {
            chatFilter = item
        }
    }

    private func moveFilter(_ delta: Int) {
        let all = ChatFilter.allCases
        guard let index = all.firstIndex(of: chatFilter) else { return }
        let next = index + delta
        guard next >= 0, next < all.count else { return }
        chooseFilter(all[next])
    }

    private func chatFilterBar(unreadCounts: [ChatFilter: Int]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ChatFilter.allCases) { item in
                    Button {
                        chooseFilter(item)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 10.5, weight: .semibold))
                            Text(Tr(item.rawValue))
                                .font(.system(size: 12,
                                              weight: chatFilter == item ? .semibold : .medium))
                                .lineLimit(1)
                            let count = unreadCounts[item, default: 0]
                            if count > 0 {
                                Text(count > 99 ? "99+" : "\(count)")
                                    .font(.system(size: 8.5, weight: .bold))
                                    .padding(.horizontal, count > 9 ? 4 : 3)
                                    .frame(height: 15)
                                    .background(Capsule().fill(C.red))
                                    .foregroundStyle(Color.white)
                            }
                        }
                        .foregroundStyle(chatFilter == item
                                         ? OrbitTheme.jade
                                         : OrbitTheme.secondary)
                        .padding(.horizontal, 10)
                        .frame(height: 31)
                        .background {
                            if chatFilter == item {
                                Capsule()
                                    .fill(OrbitTheme.jadeSoft)
                                    .overlay(
                                        Capsule().stroke(OrbitTheme.jade.opacity(0.24),
                                                         lineWidth: 0.7)
                                    )
                                    .matchedGeometryEffect(id: "chatFilterSelection",
                                                           in: filterSelectionNS)
                            }
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 18)
                .onEnded { g in
                    let dx = g.translation.width
                    guard abs(dx) > 36, abs(dx) > abs(g.translation.height) * 1.25 else { return }
                    moveFilter(dx < 0 ? 1 : -1)
                }
        )
        .padding(.top, 7)
        .padding(.bottom, 5)
        .frame(height: chatFilterH)
        .background(OrbitTheme.canvas)
        .overlay(alignment: .bottom) {
            Rectangle().fill(OrbitTheme.divider).frame(height: 0.5)
        }
        .zIndex(2)
    }

    private func openRow(_ chat: Chat) {
        if let oa = chat.oaId, !oa.isEmpty {
            oaOpenId = oa
            showOA = true
        } else if chat.oaDigest == true {
            showOAList = true
        } else {
            path.append(chat)
        }
    }

    private var navTitle: String {

        if app.offline {
            return Lang.isEnglish ? "\(C.tabText0) (No Connection)" : "\(C.tabText0)（未连接）"
        }

        return unreadTotal > 0 ? "\(C.tabText0)(\(unreadTotal))" : C.tabText0
    }

    private var unreadTotal: Int { app.chats.reduce(0) { $0 + ($1.unread ?? 0) } }

    private var chatTopHeader: some View {
        HStack(spacing: 11) {
            Button {
                showAccounts = true
            } label: {
                Avatar(path: app.me?.avatarPath ?? "", size: 38, radius: 13)
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(OrbitTheme.jade.opacity(0.42), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Tr("切换账号"))

            VStack(alignment: .leading, spacing: 2) {
                Text(app.me?.name ?? "星言")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(OrbitTheme.ink)
                    .lineLimit(1)
                Text(app.offline ? Tr("离线")
                     : (unreadTotal > 0 ? "\(unreadTotal) 条未读消息" : Tr("消息已读完")))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(OrbitTheme.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if UIConfig.num("navEyesVisible", 0) > 0, eyes.navEyesOn {
                Button {
                    if let bot = app.chats.first(where: { $0.botRank == 0 }) {
                        botChat = bot
                    } else {
                        Task {
                            await app.loadChats()
                            if let b = app.chats.first(where: { $0.botRank == 0 }) {
                                botChat = b
                            }
                        }
                    }
                } label: {
                    JarvisEyesAvatar(size: 26, tint: eyesTint)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
            }

            Button {
                showSearch = true
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

    private var pullDots: some View {
        let p = floorUp ? 100 : pullDown
        return HStack(spacing: 7) {
            ForEach(0..<3, id: \.self) { i in

                let step = floorPull * CGFloat(i + 1) / 3
                let lit = min(1, max(0, p / step))
                Circle()
                    .fill(C.label.opacity(0.18 + 0.72 * lit))
                    .frame(width: 7, height: 7)
                    .scaleEffect(0.72 + 0.28 * lit)
                    .animation(.easeOut(duration: 0.14), value: pullDown)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var floorBounce: Bool { UIConfig.num("floorPopBounce", 1) > 0 }

    private var floorAnimDur: Double { max(0.08, Double(UIConfig.num("floorAnim", 0.42))) }

    private var floorHaptic: Int { Int(UIConfig.num("floorHaptic", 3)) }

    private func floorImpact(_ level: Int) {
        guard floorHaptic > 0 else { return }
        switch min(level, floorHaptic) {
        case 1: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case 2: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        default: UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
    }

    private var floorInset: CGFloat { floorUp ? 0 : L.safeTop + L.navH }

    private var floorBottomHNow: CGFloat {
        let v = UIConfig.num("floorBottomH", 0)
        if v > 0 { return v }
        return 54 + L.safeBottom
    }

    private var floorIconProg: CGFloat {
        min(1, max(0, pullDown - floorPull) / 60)
    }

    private var floorAnim: Animation {
        floorBounce
            ? .spring(response: floorAnimDur, dampingFraction: 0.76)
            : .easeOut(duration: floorAnimDur)
    }

    private var skyStatusLight: Bool {
        guard floorUp || pullDown > 8 else { return false }
        let look = MallWeatherLook.current(mallWeather)
        return look.phase.isNight || look.isThunder
    }

    private var navFadeForFloor: Double {
        if floorUp { return 0 }
        let p: CGFloat = pullDown / max(1, floorPull)
        let v: CGFloat = max(0, 1 - p)
        return Double(min(1, v))
    }

    private var floorReveal: CGFloat {

        let full = UIScreen.main.bounds.height

        let top = max(240, full)
        if floorUp { return top }

        if pullDown > 0.5 { return min(pullDown, top) }
        return 0
    }

    @ViewBuilder private var miniFloor: some View {

        let t: CGFloat = floorUp ? 1 : min(1, pullDown / max(1, floorPull))

        let look = MallWeatherLook.current(mallWeather)
        VStack(spacing: 10) {

            Color.clear.frame(height: floorUp ? (L.safeTop + 8) : 0)

            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(floorGreeting).font(pf(17, .medium)).foregroundColor(look.ink)
                    HStack(spacing: 4) {
                        Image(systemName: look.icon).font(.system(size: 11.5, weight: .semibold))
                        Text(floorWeatherLine(look)).font(pf(12.5))
                    }
                    .foregroundColor(look.inkSoft)
                }
                Spacer(minLength: 0)
                Button { showFloorCity = true } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "location.fill").font(.system(size: 11, weight: .semibold))
                        Text(floorCity.display).font(pf(13)).lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(look.ink)
                    .padding(.horizontal, 11).frame(height: 30)
                    .background(Capsule().fill(look.cardFill))
                    .overlay(Capsule().stroke(look.cardStroke, lineWidth: 0.6))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            .modifier(FloorPop(up: floorUp, t: t, delay: 0.02))

            Color.clear.frame(height: 12)

            HStack(spacing: 6) {
                Spacer(minLength: 0)
                Image(systemName: "magnifyingglass").font(.system(size: 13.5, weight: .medium))
                Text(Tr("搜索小程序")).font(pf(14.5))
                Spacer(minLength: 0)
            }
            .foregroundColor(look.inkSoft)
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(look.cardFill))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(look.cardStroke, lineWidth: 0.6))
            .padding(.horizontal, 22)
            .contentShape(Rectangle())

            .onTapGesture { showAppSearch = true }
            .modifier(FloorPop(up: floorUp, t: t, delay: 0.04))

            Color.clear.frame(height: 18)

            if !floorRecentApps.isEmpty {
                floorCard(look: look) {
                    floorGroup(title: Tr("最近使用的小程序"), more: true,
                               apps: floorRecentApps, look: look, t: t, delay: 0.06)
                }
            }

            if !floorActions.isEmpty {
                Color.clear.frame(height: 12)

                floorCard(look: look) {
                    floorGroup(title: Tr("快捷入口"), more: false,
                               apps: [], actions: floorActions, look: look, t: t, delay: 0.28)
                }
            }

            Spacer(minLength: 0)

            Button {
                withAnimation(floorAnim) { floorUp = false }
            } label: {
                HStack(spacing: 0) {

                    Text(navTitle)

                        .font(pf(17, .medium))
                        .foregroundColor(look.ink)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 16)

                .frame(height: max(44, floorBottomHNow))
                .frame(maxWidth: .infinity)
                .background(

                    look.darkInk ? Color.white.opacity(0.34) : Color.black.opacity(0.18)
                )
                .clipShape(RoundedRectangle(cornerRadius: max(0, UIConfig.num("floorBottomRadius", 14)),
                                            style: .continuous))
                .padding(.horizontal, 10)
                .shadow(color: .black.opacity(0.25), radius: 8, y: -3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .modifier(FloorPop(up: floorUp, t: t, delay: 0.24))
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity)

    }

    private func floorItem(_ title: String, _ symbol: String, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(C.label)
                Text(Tr(title))
                    .font(pf(12))
                    .foregroundColor(C.subLabel)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func floorCard<V: View>(look: MallWeatherLook,
                                                 @ViewBuilder _ content: () -> V) -> some View {
        VStack(spacing: 0) { content() }
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(look.cardFill))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(look.cardStroke, lineWidth: 0.6))
            .padding(.horizontal, 14)
    }

    private var floorGreeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<11:  return Tr("早上好")
        case 11..<14: return Tr("中午好")
        case 14..<18: return Tr("下午好")
        case 18..<23: return Tr("晚上好")
        default:      return Tr("夜深了")
        }
    }

    private func floorWeatherLine(_ l: MallWeatherLook) -> String {
        if mallWeather.failed { return Tr("天气暂时拿不到") }
        let name: String
        switch l.cond {
        case "clear":    name = "晴"
        case "partly":   name = "少云"
        case "cloudy":   name = "多云"
        case "overcast": name = "阴"
        case "fog":      name = "雾"
        case "drizzle":  name = "小雨"
        case "rain":     name = "雨"
        case "snow":     name = "雪"
        case "thunder":  name = "雷雨"
        default:         name = "多云"
        }
        return name + " " + String(Int(round(mallWeather.temp))) + "°"
    }

    private func floorGroup(title: String, more: Bool, apps: [MiniApp],
                            actions: [(String, String, String)] = [],
                            look: MallWeatherLook,
                            t: CGFloat, delay: Double) -> some View {

        let cells: [AnyView] = apps.isEmpty
            ? actions.map { AnyView(floorActionCell($0, look: look, t: t, delay: delay)) }
            : apps.map { AnyView(floorAppCell($0, look: look, t: t, delay: delay)) }
        let rows = stride(from: 0, to: cells.count, by: 4).map {
            Array(cells[$0..<min($0 + 4, cells.count)])
        }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text(title).font(pf(12.5)).foregroundColor(look.inkSoft)
                Spacer(minLength: 0)
                if more {
                    Text(Tr("更多") + " ›")
                        .font(pf(12.5))
                        .foregroundColor(look.inkSoft)
                        .contentShape(Rectangle())
                        .onTapGesture { path.append("miniapps") }
                }
            }
            .padding(.horizontal, 33)
            .modifier(FloorPop(up: floorUp, t: t, delay: delay))

            Color.clear.frame(height: 14)
            VStack(spacing: 14) {
                ForEach(rows.indices, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(0..<4, id: \.self) { c in
                            if c < rows[r].count {
                                rows[r][c]
                            } else {
                                Color.clear.frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 21)
        }
    }

    private func floorAppCell(_ mini: MiniApp, look: MallWeatherLook,
                              t: CGFloat, delay: Double) -> some View {
        Button { app.launchMiniApp(mini) } label: {
            VStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(colors: [Color(hex: 0x2B2F3A), Color(hex: 0x171B22)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text(mini.iconText).font(.system(size: 24))
                    if let cv = mini.cover, !cv.isEmpty {
                        RemoteImage(path: cv)
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .frame(width: 48, height: 48)
                Text(mini.name)
                    .font(pf(12))
                    .foregroundColor(look.inkSoft)
                    .lineLimit(1)
                    .frame(width: 78)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(FloorPop(up: floorUp, t: t, delay: delay))
        .scaleEffect(floorIconScaleNow, anchor: .center)
    }

    private func floorActionCell(_ it: (String, String, String), look: MallWeatherLook,
                                 t: CGFloat, delay: Double) -> some View {
        Button { runMiniApp(it.0) } label: {
            VStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(look.darkInk ? Color.white.opacity(0.72) : Color.white.opacity(0.14))
                    Image(systemName: it.2)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(look.ink)
                }
                .frame(width: 48, height: 48)
                Text(Tr(it.1))
                    .font(pf(12))
                    .foregroundColor(look.inkSoft)
                    .lineLimit(1)
                    .frame(width: 78)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(FloorPop(up: floorUp, t: t, delay: delay))
        .scaleEffect(floorIconScaleNow, anchor: .center)
    }

    private var floorIconScaleNow: CGFloat {
        let s0 = UIConfig.num("floorIconScale", 0.45)
        return floorUp ? 1 : (s0 + (1 - s0) * floorIconProg)
    }

    private var floorRecentApps: [MiniApp] {
        guard !floorApps.isEmpty else { return [] }

        return Array(floorApps.filter { $0.id != "office" }.prefix(8))
    }

    private var miniApps: [(String, String, String)] {
        let raw = UIConfig.text("miniApps", "")
        var out: [(String, String, String)] = []
        for line in raw.split(separator: "\n") {
            let parts = line.split(separator: "|").map { String($0).trimmingCharacters(in: .whitespaces) }
            if parts.count >= 3, !parts[0].isEmpty {
                out.append((parts[0], parts[1], parts[2]))
            }
        }
        if out.isEmpty {
            return [("scan", "扫一扫", "qrcode.viewfinder"),
                    ("pay", "收付款", "creditcard"),
                    ("search", "搜一搜", "magnifyingglass"),
                    ("group", "发起群聊", "person.2.fill")]
        }
        return Array(out.prefix(4))
    }

    private var floorActions: [(String, String, String)] { miniApps }

    private func runMiniApp(_ action: String) {
        switch action {
        case "scan": showScan = true
        case "pay": showPayCode = true
        case "search": showSearch = true
        case "group": path.append("newGroup")
        default: app.show(Tr("这个入口还没接"))
        }
    }

    @ViewBuilder private func chatsNavGlass(_ scrolled: CGFloat) -> some View {
        let blur = UIConfig.num("chatsNavGlassAlpha", 1)
        let mask = UIConfig.num("chatsNavMaskAlpha", 0.25)

        Group {
            if scheme == .dark {

                HarmonyDarkMask(strength: 0.98)
            } else {
                ZStack {
                    Rectangle().fill(.bar)
                        .opacity(max(0, min(1, blur)))
                    (UIConfig.colorIfSet("chatsNavMaskColor") ?? OrbitTheme.canvas)
                        .opacity(max(0.72, min(1, mask + 0.5)))
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }

    @ViewBuilder private var chatsCardBackground: some View {
        RoundedRectangle(cornerRadius: chatsCardRadius, style: .continuous)
            .fill(OrbitTheme.raised)
            .shadow(color: Color.black.opacity(scheme == .dark ? 0.22 : 0.07),
                    radius: 16, x: 0, y: 7)
    }

    @ViewBuilder private func chatListRows(_ chats: [Chat]) -> some View {
        ForEach(chats) { chat in
            SwipeChatRow(
                chat: chat,
                onOpen: { openRow(chat) },
                onTapAvatar: ((chat.botRank ?? 9) < 9) ? { botCardChat = chat } : nil,
                onUnread: { markUnread(chat) },
                onHide: { clear in hide(chat, clear: clear) },
                onDelete: { remove(chat) },
                cardStyle: chatsCardStyle,
                horizontalInset: chatsCardStyle ? chatsCardInset : 0
            )
        }
    }

    var body: some View {
        let snapshot = chatSnapshot()
        return NavigationStack(path: $path) {

            ZStack(alignment: .top) {
                if app.chats.isEmpty {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: L.safeTop + L.navH + chatFilterOffset)
                        emptyView
                        Spacer(minLength: 0)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {

                            Color.clear.frame(height: L.safeTop + L.navH + chatFilterOffset)
                            if snapshot.list.isEmpty {
                                Text(Tr("这个分类暂时没有会话"))
                                    .font(pf(14))
                                    .foregroundColor(C.subLabel)
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 54)
                            }
                            if chatsCardStyle {
                                LazyVStack(spacing: 0) {
                                    chatListRows(snapshot.list)
                                }
                                .background { chatsCardBackground }
                                .clipShape(RoundedRectangle(cornerRadius: chatsCardRadius,
                                                            style: .continuous))
                                .padding(.horizontal, chatsCardInset)
                                .padding(.top, 6)
                                .padding(.bottom, 10)
                            } else {
                                chatListRows(snapshot.list)
                            }

                            Color.clear.frame(height: L.tabH + L.safeBottom + 10)
                        }

                        .background(
                            GeometryReader { g in
                                Color.clear.preference(
                                    key: ChatsScrollKey.self,
                                    value: -g.frame(in: .named("chatsScroll")).minY)
                            }
                        )
                    }
                    .id(chatFilter)
                    .coordinateSpace(name: "chatsScroll")

                    .simultaneousGesture(
                        DragGesture(minimumDistance: 8)
                            .onChanged { g in
                                guard scrolled < 8 else { return }
                                let dy = g.translation.height
                                let dx = abs(g.translation.width)
                                if !floorDragActive {
                                    if dx > max(10, abs(dy) * 1.15) {
                                        if pullDown != 0 { pullDown = 0 }
                                        floorTick = 0
                                        return
                                    }
                                    guard dy > 10, dy > dx * 1.15 else { return }
                                    floorDragActive = true
                                }
                                if floorOn, dy > 0 {
                                    pullDown = heavyPull(dy)

                                    let step = max(1, floorPull / 3)
                                    let lit = min(3, Int(dy / step))
                                    if lit != floorTick {
                                        floorTick = lit
                                        if lit > 0 {

                                            floorImpact(lit >= 3 ? 3 : 2)
                                        }
                                    }
                                } else if !floorUp {
                                    pullDown = 0
                                    floorTick = 0
                                }
                            }
                            .onEnded { g in

                                let fling = abs(g.predictedEndTranslation.height - g.translation.height)
                                let open = floorDragActive && floorOn && pullDown > floorPull && fling < 220
                                floorDragActive = false

                                if open {
                                    floorImpact(3)
                                    if floorHaptic >= 2 {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                                            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                                        }
                                    }
                                }
                                floorTick = 0
                                withAnimation(floorAnim) {
                                    floorUp = open
                                    pullDown = 0
                                }
                            }
                    )
                    .onPreferenceChange(ChatsScrollKey.self) { v in
                        let s = max(0, v)

                        if s > 8 { NotificationCenter.default.post(name: .chrisRowSwipe, object: nil) }

                        if s > scrolled || s < 1 {
                            if abs(s - scrolled) > 0.5 { scrolled = s }
                        }

                        let p = heavyPull(max(0, -v))
                        if abs(p - pullDown) > 0.5 { pullDown = p }

                        if s > 14, floorUp { floorUp = false }
                    }

                    .ignoresSafeArea(edges: .top)
                    .background(Color.clear)
                    .refreshable { await app.loadChats() }
                }

                if pullDown > 0.5 || floorUp {
                    ZStack(alignment: .top) {

                        if floorUp || pullDown >= floorPull {
                            miniFloor
                                .frame(maxWidth: .infinity, alignment: .top)
                        }

                        VStack(spacing: 0) {
                            Spacer().frame(height: floorUp ? L.safeTop + 10 : 8)
                            pullDots
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .opacity(floorUp ? 0 : 1)
                    }
                        .frame(height: floorReveal)
                        .frame(maxWidth: .infinity, alignment: .top)

                        .padding(.top, floorInset)

                        .frame(maxWidth: .infinity, alignment: .top)
                        .clipped()

                        .background {
                            MallSkyBackground(look: MallWeatherLook.current(mallWeather))
                                .padding(.top, -(L.safeTop + L.navH))
                                .ignoresSafeArea()
                        }
                        .allowsHitTesting(floorOn && (pullDown > floorPull * 0.6 || floorUp))

                        .animation(floorBounce
                                   ? .spring(response: floorAnimDur, dampingFraction: 1.0)
                                   : .easeOut(duration: floorAnimDur),
                                   value: floorUp)
                }

                VStack(spacing: 0) {
                    chatTopHeader

                    .background {
                        ZStack {
                            if UIConfig.num("navBarSwallowTouch", 1) > 0 {
                                Color.clear
                                    .frame(height: L.navH)
                                    .contentShape(Rectangle())
                            }
                            chatsNavGlass(scrolled)
                        }
                    }

                    .overlay(alignment: .bottom) {
                        Rectangle().fill(OrbitTheme.divider).frame(height: 0.5)
                            .opacity(scrolled > 6 ? 1 : 0)
                    }

                    .opacity(navFadeForFloor)
                    .allowsHitTesting(!floorUp)
                    Spacer(minLength: 0)
                }

                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: L.safeTop + L.navH)
                        .allowsHitTesting(false)
                    if chatFilterVisible {
                        chatFilterBar(unreadCounts: snapshot.unreadCounts)
                    }
                    Spacer(minLength: 0)
                        .allowsHitTesting(false)
                }
                .ignoresSafeArea(edges: .top)
                .opacity(navFadeForFloor)
                .allowsHitTesting(!floorUp)
                .zIndex(3)
            }

            .background(chatsPageFill.ignoresSafeArea(edges: .bottom))
            .fullScreenCover(isPresented: $showSearch) {
                SearchPage(onOpenChat: { c in path.append(c) })
                    .environmentObject(app)
            }
            .background(chatsPageFill.ignoresSafeArea(edges: .top))
            .toolbar(.hidden, for: .navigationBar)

            .onChange(of: path.count) { n in
                if n == 0 { app.tabBarDepth = 0 }
            }

            .onChange(of: floorUp) { v in
                withAnimation(.easeOut(duration: 0.2)) { app.floorFull = v }
            }

            .navigationDestination(for: Chat.self) { chat in
                chatDest(chat)
            }

            .onAppear { openPendingPushChat(app.pendingPushChatId) }
            .onChange(of: app.pendingPushChatId) { v in openPendingPushChat(v) }

            .navigationDestination(isPresented: $showOA) {
                OfficialAccountPage(accountId: oaOpenId)
            }
            .navigationDestination(isPresented: $showOAList) {
                OfficialAccountsView()
            }
            .navigationDestination(for: String.self) { key in
                if key == "newGroup" {
                    GroupCreateView { chat in

                        app.openChatViaList(chat)
                    }
                } else if key == "addFriend" {
                    AddFriendView()
                } else if key == "myQR" {
                    MyQRView()
                } else if key == "miniapps" {

                    MiniAppsView()
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
            NavPlusItem(title: Tr("扫一扫"), symbol: "qrcode.viewfinder",
                        colors: [C.green, C.green.opacity(0.78)]) { showScan = true },
            NavPlusItem(title: Tr("收付款"), symbol: "creditcard.fill",
                        colors: [Color(hex: 0xB98CFF), Color(hex: 0x7A45D6)]) { showPayCode = true }
        ])

        .fullScreenCover(item: $botChat) { c in
            BotChatView(chat: c).environmentObject(app)
        }
        .fullScreenCover(isPresented: $showScan) {
            ScannerView { text in handleScanned(text, app: app) }
        }

        .sheet(isPresented: $showAppSearch) {
            MiniAppSearchView(apps: floorApps) { m in
                showAppSearch = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                    app.launchMiniApp(m)
                }
            }
            .environmentObject(app)
        }

        .sheet(isPresented: $showAccounts) {
            NavigationStack {
                SwitchAccountView()
                    .environmentObject(app)
            }
        }

        .sheet(isPresented: $showFloorCity) {
            DDCityPickerView().environmentObject(app)
        }

        .onChange(of: floorUp) { up in
            if up { MallWeather.shared.refresh() }
        }
        .sheet(item: $botCardChat) { c in
            BotCardView(chat: c).environmentObject(app)
        }
        .sheet(isPresented: $showPayCode) {
            NavigationStack { PayCodePage() }
                .environmentObject(app)
        }
        .task {
            HitchWatch.shared.start("会话列表")

            let got = await API.shared.miniApps()
            if !got.isEmpty {
                floorApps = got
                if let d = try? JSONEncoder().encode(got) {
                    UserDefaults.standard.set(d, forKey: "chris.floorApps")
                }
            } else if floorApps.isEmpty,
                      let d = UserDefaults.standard.data(forKey: "chris.floorApps"),
                      let cached = try? JSONDecoder().decode([MiniApp].self, from: d) {
                floorApps = cached
            }

            MallWeather.shared.refresh()

            while !Task.isCancelled {
                await app.loadChats()
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }

    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            Spacer()
            Text(app.loadError ?? "正在加载会话…")
                .font(pf(14))
                .foregroundColor(C.subLabel)
            if app.loadError != nil {
                Button(Tr("重试")) { Task { await app.loadChats() } }
                    .font(pf(15))
                    .foregroundColor(C.green)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(OrbitTheme.canvas)
    }

    private func markUnread(_ chat: Chat) {
        let oldUnread = chat.unread
        let oldFlagged = chat.flagged
        app.setChatUnreadLocally(chat.id, unread: max(1, chat.unreadCount), flagged: true)
        Task {
            guard await API.shared.markUnread(chatId: chat.id) else {
                app.setChatUnreadLocally(chat.id, unread: oldUnread, flagged: oldFlagged)
                app.show(Tr("标为未读失败"))
                return
            }
            await app.loadChats()
        }
    }

    private func hide(_ chat: Chat, clear: Bool) {
        withAnimation(.easeOut(duration: 0.18)) {
            app.hideChatLocally(chat.id)
        }
        Task {
            let err = clear
                ? await API.shared.deleteChat(chatId: chat.id)
                : await API.shared.hideChat(chatId: chat.id)
            if let err {
                app.revealChatLocally(chat.id)
                await app.loadChats()
                app.show(err)
                return
            }
            if clear { app.forgetChatHistory(chat.id) }
            app.dropOptimisticSummary(chat.id)
            await app.loadChats()
        }
    }

    private func remove(_ chat: Chat) {
        withAnimation(.easeOut(duration: 0.18)) {
            app.hideChatLocally(chat.id)
        }
        Task {
            let err = await API.shared.deleteChat(chatId: chat.id)
            if let err {
                app.revealChatLocally(chat.id)
                await app.loadChats()
                app.show(err)
                return
            }
            LocalStore.clearChat(chat.id)
            app.dropOptimisticSummary(chat.id)
            await app.loadChats()
        }
    }

    private func openPendingPushChat(_ id: String?) {
        guard let id, !id.isEmpty else { return }
        Task { @MainActor in
            for _ in 0..<40 {
                if app.chats.contains(where: { $0.id == id }) { break }
                await app.loadChats()
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            guard let c = app.chats.first(where: { $0.id == id }) else {
                app.pendingPushChatId = nil
                app.show(Tr("找不到这个会话"))
                CrashCatcher.note("推送", "列表里没有这个会话 " + id)
                return
            }
            app.pendingPushChatId = nil
            CrashCatcher.note("推送", "交给会话列表打开 " + id)

            try? await Task.sleep(nanoseconds: 350_000_000)
            path.append(c)
        }
    }
}

private struct ChatsScrollKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct NavPlusPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)

            .overlay {
                ZStack {
                    RadialGradient(colors: [Color.white.opacity(0.95),
                                            Color.white.opacity(0.30),
                                            Color.white.opacity(0)],
                                   center: .center, startRadius: 0, endRadius: 34)
                    Circle()
                        .fill(Color.white.opacity(0.55))
                        .frame(width: 16, height: 16)
                        .blur(radius: 7)
                }
                .blendMode(.plusLighter)
                .opacity(configuration.isPressed ? 1 : 0)
                .clipShape(Capsule(style: .continuous))
                .allowsHitTesting(false)
            }
            .brightness(configuration.isPressed ? 0.10 : 0)
            .shadow(color: Color.white.opacity(configuration.isPressed ? 0.5 : 0), radius: 10)
            .animation(.easeOut(duration: 0.13), value: configuration.isPressed)
    }
}

private struct FloorPop: ViewModifier {
    var up: Bool
    var t: CGFloat
    var delay: Double

    func body(content: Content) -> some View {
        content
    }
}

    private func chatDest(_ chat: Chat) -> some View {

        CrashCatcher.note("聊天页", "8 准备打开 " + chat.id + memNote())

        return DeferredChatView(chat: chat)
    }

    private func memNote() -> String {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return " 内存读不到" }
        let used = Int(Double(info.phys_footprint) / 1_048_576.0)
        let left = Int(Double(info.limit_bytes_remaining) / 1_048_576.0)
        return " 内存\(used)MB(剩\(left)MB)"
    }

struct MiniAppSearchView: View {
    let apps: [MiniApp]
    var onOpen: (MiniApp) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var q = ""

    private var hits: [MiniApp] {
        let key = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return apps }
        return apps.filter { $0.name.contains(key) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundColor(C.subLabel)
                    TextField(Tr("搜索小程序"), text: $q)
                        .font(pf(14.5))
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                        .submitLabel(.search)
                    if !q.isEmpty {
                        Button { q = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundColor(C.subLabel)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.dyn(0xEDEDED, 0x2C2C2E)))

                Button(Tr("取消")) { dismiss() }
                    .font(pf(15))
                    .foregroundColor(C.label)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(hits) { m in
                        Button {
                            dismiss()
                            onOpen(m)
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(LinearGradient(colors: [Color(hex: 0x2B2F3A), Color(hex: 0x171B22)],
                                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                                    Text(m.iconText).font(.system(size: 18))
                                    if let cv = m.cover, !cv.isEmpty {
                                        RemoteImage(path: cv)
                                            .frame(width: 36, height: 36)
                                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    }
                                }
                                .frame(width: 36, height: 36)
                                Text(m.name)
                                    .font(pf(16))
                                    .foregroundColor(C.label)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Chevron(size: 9, line: 1.6)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 56)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        HairLine(inset: 64)
                    }
                    if hits.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 26))
                                .foregroundColor(C.subLabel.opacity(0.6))
                            Text(Tr("没有找到这个小程序"))
                                .font(pf(14))
                                .foregroundColor(C.subLabel)
                        }
                        .padding(.top, 60)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .background(C.pageBg.ignoresSafeArea())
    }
}
