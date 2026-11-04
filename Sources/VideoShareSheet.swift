import SwiftUI

struct VideoShareSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    let item: FeedItem

    var onForward: (() -> Void)? = nil
    var onToMoments: (() -> Void)? = nil
    var onFavorite: (() -> Void)? = nil
    var onSaveLocal: (() -> Void)? = nil
    var onHide: (() -> Void)? = nil

    private var link: String { item.video ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            Text(Tr("分享到"))
                .font(pf(13))
                .foregroundColor(C.subLabel)
                .padding(.top, 16)
                .padding(.bottom, 14)

            HStack(alignment: .top, spacing: 0) {
                iconButton("转发给朋友", "paperplane.fill", Color(hex: 0x19A47A)) {
                    dismiss()
                    onForward?()
                }
                iconButton("朋友圈", "camera.fill", C.green) {
                    dismiss()
                    onToMoments?()
                }
                iconButton("收藏", "star.fill", Color(hex: 0xE2A03C)) {
                    dismiss()
                    onFavorite?()
                }
                iconButton("复制链接", "link", Color(hex: 0x1180E0)) {
                    UIPasteboard.general.string = link
                    app.show(Tr("链接已复制，可以去聊天里粘贴"))
                    dismiss()
                }
                iconButton("保存本地", "arrow.down.to.line", Color(hex: 0x8A8A8E)) {
                    dismiss()
                    onSaveLocal?()
                }
            }
            .padding(.horizontal, 8)

            Rectangle().fill(C.hairline).frame(height: 0.5)
                .padding(.top, 18)
                .padding(.horizontal, 0)

            VStack(spacing: 0) {
                textRow("举报", "exclamationmark.bubble") { dismiss(); app.show(Tr("已提交举报，我们会尽快核实")) }
                HairLine(inset: 16)
                textRow("不感兴趣", "hand.thumbsdown") {
                    dismiss()
                    onHide?()
                }
            }
            .padding(.top, 4)

            Button { dismiss() } label: {
                Text(Tr("取消"))
                    .font(pf(16))
                    .foregroundColor(C.label)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(C.cardBg)
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
            Color.clear.frame(height: 6)
        }
        .background(C.pageBg.ignoresSafeArea())
        .presentationDetents([.height(320)])
    }

    private func iconButton(_ title: String, _ symbol: String, _ color: Color, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 7) {
                ZStack {
                    Circle().fill(color.opacity(0.14)).frame(width: 50, height: 50)
                    Image(systemName: symbol)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(color)
                }
                Text(Tr(title)).font(pf(11.5)).foregroundColor(C.label).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func textRow(_ title: String, _ symbol: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 16)).foregroundColor(C.subLabel).frame(width: 24)
                Text(Tr(title)).font(pf(16)).foregroundColor(C.label)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct VideoForwardPicker: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    let link: String

    var videoContent: String = ""

    @State private var q = ""
    @State private var sending = ""

    private var list: [User] {
        let key = q.trimmingCharacters(in: .whitespaces)
        let all = app.contacts
        if key.isEmpty { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(key) ||
            ($0.username ?? "").localizedCaseInsensitiveContains(key) ||
            ($0.remark ?? "").localizedCaseInsensitiveContains(key)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("转发给朋友"), back: { dismiss() })

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 14) {
                    StarForwardHero(
                        symbol: "paperplane.fill",
                        kicker: "STAR DIRECT",
                        title: Tr("直接送到朋友"),
                        subtitle: Tr("轻触好友即可发送，不需要再选一次会话"),
                        badge: "\(app.contacts.count) " + Tr("位好友")
                    )

                    StarForwardSearch(placeholder: Tr("搜索好友"), text: $q)

                    VStack(alignment: .leading, spacing: 9) {
                        OrbitSectionLabel(
                            text: q.isEmpty ? Tr("星言好友") : Tr("搜索结果"),
                            count: list.count
                        )

                        if list.isEmpty {
                            StarForwardEmpty(text: Tr("没有找到匹配的好友"))
                        } else {
                            ForEach(list) { u in
                                Button {
                                    send(to: u)
                                } label: {
                                    StarForwardTargetRow(
                                        name: u.name,
                                        subtitle: subtitle(for: u),
                                        avatar: u.avatarPath,
                                        isGroup: false,
                                        selected: false,
                                        selecting: false,
                                        loading: sending == u.id,
                                        countBadge: u.online == true ? Tr("在线") : nil
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(!sending.isEmpty)
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
            HStack(spacing: 9) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(OrbitTheme.jade)
                Text(sending.isEmpty ? Tr("轻触好友，立即发送") : Tr("正在沿星轨发送…"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(OrbitTheme.secondary)
                Spacer(minLength: 0)
                if !sending.isEmpty {
                    ProgressView()
                        .tint(OrbitTheme.jade)
                        .scaleEffect(0.72)
                }
            }
            .padding(.horizontal, 15)
            .frame(height: 46)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(OrbitTheme.divider.opacity(0.7))
                    .frame(height: 0.5)
            }
        }
        .swipeBack { dismiss() }
    }

    private func subtitle(for u: User) -> String {
        let username = (u.username ?? "").trimmingCharacters(in: .whitespaces)
        if !username.isEmpty { return "@" + username }
        let mood = (u.moodText ?? "").trimmingCharacters(in: .whitespaces)
        return mood.isEmpty ? Tr("星言好友") : mood
    }

    private func send(to u: User) {
        if !sending.isEmpty { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        sending = u.id
        Task {
            do {
                let chat = try await API.shared.directChat(userId: u.id)

                if !videoContent.isEmpty {
                    _ = try await API.shared.send(chatId: chat.id, kind: "video", content: videoContent)
                } else {
                    _ = try await API.shared.send(chatId: chat.id, kind: "text", content: link)
                }
                app.show(Tr("已转发给 ") + u.name)
                dismiss()
            } catch {
                app.show((error as? LocalizedError)?.errorDescription ?? Tr("转发失败"))
            }
            sending = ""
        }
    }
}
