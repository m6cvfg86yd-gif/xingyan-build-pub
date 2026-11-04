import SwiftUI

struct MsgAction: Identifiable, Hashable {
    var key: String
    var label: String
    var icon: String
    var danger: Bool = false
    var id: String { key }
}

struct MsgMenuBox: View {
    let actions: [MsgAction]
    var onPick: (MsgAction) -> Void

    @Environment(\.colorScheme) private var scheme
    private var bg: Color { scheme == .dark ? Color(hex: 0x3A3A3C) : .white }
    private var ink: Color { scheme == .dark ? Color(hex: 0xEDEDED) : Color(hex: 0x1A1A1A) }

    static let itemW: CGFloat = 56
    static let itemH: CGFloat = 62
    static let padH: CGFloat = 6
    static let padV: CGFloat = 8

    static func columns(_ n: Int) -> Int { min(6, max(1, n)) }

    static func size(_ n: Int) -> CGSize {
        let cols = columns(n)
        let rows = Int(ceil(Double(n) / Double(cols)))
        return CGSize(width: CGFloat(cols) * itemW + padH * 2,
                      height: CGFloat(rows) * itemH + padV * 2)
    }

    var body: some View {
        let cols = MsgMenuBox.columns(actions.count)
        let rows = Int(ceil(Double(actions.count) / Double(cols)))
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(Array(actions.enumerated()), id: \.element.id) { idx, a in
                        if idx / cols == r {
                            Button {
                                onPick(a)
                            } label: {
                                VStack(spacing: 5) {
                                    Image(systemName: a.icon)
                                        .font(.system(size: 20))
                                        .foregroundColor(a.danger ? Color(hexString: "#FA5151") : ink)
                                        .frame(height: 22)
                                    Text(Tr(a.label))
                                        .font(pf(11.5))
                                        .foregroundColor(a.danger ? Color(hexString: "#FA5151") : ink)
                                        .lineLimit(1)
                                        .fixedSize()
                                }
                                .frame(width: MsgMenuBox.itemW, height: MsgMenuBox.itemH)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, MsgMenuBox.padH)
        .padding(.vertical, MsgMenuBox.padV)

        .background {
            ZStack {
                GlassBackground(shape: RoundedRectangle(cornerRadius: 10, style: .continuous),
                                opacity: UIConfig.num("menuGlassAlpha", 0.92),
                                edgeAlpha: UIConfig.num("menuGlassEdge", 0.28),
                                shadow: false,
                                seed: 0.85,
                                native: true)
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(bg.opacity(0.55))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(Color.white.opacity(scheme == .dark ? 0.16 : 0.30), lineWidth: 0.6))
        .shadow(color: Color.black.opacity(0.18), radius: 12, y: 4)
    }
}

struct ForwardItem: Hashable {
    var kind: String
    var content: String
}

struct ForwardPickerView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    let items: [ForwardItem]
    var onSent: () -> Void

    @State private var keyword = ""
    @State private var sending = false

    @State private var picked: Set<String> = []

    private var list: [Chat] {
        let base = app.chats
        let key = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return base }
        return base.filter {
            $0.name.localizedCaseInsensitiveContains(key) ||
            ($0.lastMessage?.preview ?? "").localizedCaseInsensitiveContains(key)
        }
    }

    private var selectedChats: [Chat] {
        app.chats.filter { picked.contains($0.id) }
    }

    private var contentSummary: String {
        guard items.count > 1 else {
            return items.first.map { kindName($0.kind) } ?? Tr("内容")
        }
        return Tr("共") + " \(items.count) " + Tr("条内容")
    }

    private var recentChats: [Chat] {
        keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Array(list.prefix(6))
            : []
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("转发给朋友"), back: { dismiss() }) {
                Button {
                    if !picked.isEmpty {
                        withAnimation(.easeOut(duration: 0.18)) { picked.removeAll() }
                    } else {
                        dismiss()
                    }
                } label: {
                    Text(picked.isEmpty ? Tr("取消") : Tr("清空"))
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(picked.isEmpty ? OrbitTheme.secondary : OrbitTheme.jade)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                }
                .buttonStyle(.plain)
            }

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 14) {
                    StarForwardHero(
                        symbol: "paperplane.fill",
                        kicker: "STAR ROUTE",
                        title: Tr("把星光送到"),
                        subtitle: Tr("选择会话即可转发，原内容会完整保留"),
                        badge: contentSummary
                    )

                    StarForwardSearch(placeholder: Tr("搜索会话或消息"), text: $keyword)

                    if !recentChats.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            OrbitSectionLabel(text: Tr("常联系"), count: recentChats.count)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: 13) {
                                    ForEach(recentChats) { chat in
                                        Button {
                                            toggle(chat.id)
                                        } label: {
                                            StarForwardQuickTarget(
                                                name: chat.name,
                                                avatar: chat.avatar ?? "",
                                                isGroup: chat.type == "group",
                                                selected: picked.contains(chat.id)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 1)
                                .padding(.vertical, 2)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        OrbitSectionLabel(
                            text: keyword.isEmpty ? Tr("全部会话") : Tr("搜索结果"),
                            count: list.count
                        )

                        if list.isEmpty {
                            StarForwardEmpty(text: Tr("没有找到匹配的会话"))
                        } else {
                            ForEach(list) { chat in
                                Button {
                                    toggle(chat.id)
                                } label: {
                                    StarForwardTargetRow(
                                        name: chat.name,
                                        subtitle: subtitle(for: chat),
                                        avatar: chat.avatar ?? "",
                                        isGroup: chat.type == "group",
                                        selected: picked.contains(chat.id),
                                        countBadge: badge(for: chat)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 4)
                .padding(.bottom, 18)
            }
        }
        .background {
            StarRouteBackdrop()
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            sendDock
        }
        .swipeBack { dismiss() }
    }

    private var sendDock: some View {
        VStack(spacing: 10) {
            if !selectedChats.isEmpty {
                HStack(spacing: 8) {
                    HStack(spacing: -7) {
                        ForEach(Array(selectedChats.prefix(4))) { chat in
                            Avatar(path: chat.avatar ?? "",
                                   size: 25,
                                   radius: 8,
                                   circle: true,
                                   group: chat.type == "group")
                                .overlay(Circle().stroke(OrbitTheme.raised, lineWidth: 1.5))
                        }
                    }
                    Text(Tr("已选") + " \(selectedChats.count) " + Tr("个会话"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(OrbitTheme.secondary)
                    Spacer(minLength: 6)
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) { picked.removeAll() }
                    } label: {
                        Text(Tr("清空"))
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(OrbitTheme.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(picked.isEmpty ? Tr("选择一个会话") : Tr("准备发送"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(OrbitTheme.ink)
                    Text(contentSummary)
                        .font(.system(size: 10.5))
                        .foregroundStyle(OrbitTheme.secondary)
                }
                Spacer(minLength: 8)
                Button {
                    sendSelected()
                } label: {
                    HStack(spacing: 7) {
                        if sending {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.72)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 12.5, weight: .semibold))
                        }
                        Text(sending ? Tr("发送中…") : Tr("发送"))
                            .font(.system(size: 14.5, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 19)
                    .frame(height: 42)
                    .background {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: picked.isEmpty || sending
                                        ? [OrbitTheme.tertiary.opacity(0.55), OrbitTheme.tertiary.opacity(0.42)]
                                        : [OrbitTheme.jade, OrbitTheme.jadeDeep],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .shadow(color: picked.isEmpty ? .clear : OrbitTheme.jade.opacity(0.24),
                            radius: 9,
                            y: 4)
                }
                .buttonStyle(.plain)
                .disabled(picked.isEmpty || sending)
            }
        }
        .padding(.horizontal, 13)
        .padding(.top, 10)
        .padding(.bottom, max(8, L.safeBottom * 0.32))
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(OrbitTheme.divider.opacity(0.7))
                .frame(height: 0.5)
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: picked.count)
    }

    private func toggle(_ id: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.84)) {
            if picked.contains(id) { picked.remove(id) } else { picked.insert(id) }
        }
    }

    private func subtitle(for chat: Chat) -> String {
        let preview = (chat.lastMessage?.preview ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !preview.isEmpty { return preview }
        return chat.type == "group" ? Tr("群聊会话") : Tr("最近联系")
    }

    private func badge(for chat: Chat) -> String? {
        if chat.type == "group", let count = chat.memberCount, count > 0 {
            return "\(count)" + Tr("人")
        }
        if let unread = chat.unread, unread > 0 {
            return unread > 99 ? "99+" : "\(unread)"
        }
        return nil
    }

    private func kindName(_ kind: String) -> String {
        switch kind {
        case "image": return Tr("图片")
        case "images": return Tr("相册")
        case "video": return Tr("视频")
        case "music": return Tr("音乐")
        case "miniapp": return Tr("小程序")
        case "file": return Tr("文件")
        case "mall": return Tr("商城卡片")
        case "note": return Tr("笔记")
        default: return Tr("内容")
        }
    }

    private func sendSelected() {
        let targets = selectedChats
        guard !targets.isEmpty else { return }
        sending = true
        Task {
            for chat in targets {
                for it in items {
                    _ = try? await API.shared.send(chatId: chat.id, kind: it.kind, content: it.content)
                }
            }
            sending = false
            if targets.count == 1 {
                app.show(Tr("已转发给") + "「" + targets[0].name + "」")
            } else {
                app.show(Tr("已转发给") + " " + String(targets.count) + " " + Tr("个聊天"))
            }
            onSent()
            dismiss()
        }
    }
}

struct MultiSelectBar: View {
    let count: Int
    var onForward: () -> Void
    var onFavorite: () -> Void
    var onDelete: () -> Void

    @Environment(\.colorScheme) private var scheme
    private var ink: Color { scheme == .dark ? Color(hex: 0xEDEDED) : Color(hex: 0x1A1A1A) }

    var body: some View {
        HStack(spacing: 0) {
            item("转发", "arrowshape.turn.up.right", onForward)
            item("收藏", "star", onFavorite)
            item("删除", "trash", onDelete, danger: true)
        }
        .frame(height: 54)
        .background(C.tabBg)
        .overlay(alignment: .top) { HairLine() }
    }

    private func item(_ title: String, _ icon: String, _ tap: @escaping () -> Void, danger: Bool = false) -> some View {
        Button(action: tap) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 18))
                Text(Tr(title)).font(pf(11))
            }
            .foregroundColor(danger ? Color(hexString: "#FA5151") : ink)
            .opacity(count == 0 ? 0.45 : 1)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
    }
}
