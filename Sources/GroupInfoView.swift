import SwiftUI

struct GroupInfoView: View {
    @ObservedObject private var lang = LangStore.shared
    let chat: Chat
    var onExitChat: () -> Void = {}

    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var members: [User] = []
    @State private var ownerId = ""
    @State private var createdAt = ""
    @State private var loading = true
    @State private var pinned = false
    @State private var saving = false

    @State private var muted = false

    @State private var announce = ""
    @State private var showAnnounce = false
    @State private var announceDraft = ""
    @State private var showRename = false
    @State private var nameDraft = ""
    @State private var showSearch = false
    @State private var showAllMembers = false
    @State private var showComplaint = false

    @State private var showGroupBg = false
    @State private var showGroupTheme = false
    @State private var confirmClear = false
    @State private var confirmQuit = false
    @State private var kickTarget: User?
    @State private var showQR = false
    @State private var muteAll = false
    @State private var kickMode = "kick"

    @State private var showAdd = false
    @State private var removing = false

    @State private var showAlias = false
    @State private var aliasDraft = ""
    @State private var aliasTarget: User?
    @State private var aliasTitle = "设置群昵称"

    @State private var cardUser: User?

    private var isOwner: Bool { !ownerId.isEmpty && ownerId == app.me?.id }

    private var myAlias: String {
        members.first(where: { $0.id == app.me?.id })?.alias ?? ""
    }

    private let gridColumns = Array(
        repeating: GridItem(.flexible(minimum: 0), spacing: 4, alignment: .top),
        count: 5
    )

    private var ownerName: String {
        if let u = members.first(where: { $0.id == ownerId }) { return u.name }
        return "群主"
    }

    private var createdText: String {
        guard createdAt.count >= 10 else { return "" }
        let y = createdAt.prefix(4)
        let m = createdAt.dropFirst(5).prefix(2)
        let d = createdAt.dropFirst(8).prefix(2)
        return "\(Int(y) ?? 0)年\(Int(m) ?? 0)月\(Int(d) ?? 0)日"
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("聊天信息"), back: { dismiss() })

            NativeStaticList(items: groupInfoNativeItems,
                             signature: { $0.signature }) { item in
                groupInfoNativeRow(item)
                    .environmentObject(app)
                    .environment(\.chatInfoCardTone, .group)
            }
        }
        .background(C.pageBg.ignoresSafeArea())
        .environment(\.chatInfoCardTone, .group)
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .onAppear {
            CrashCatcher.markStep("三点", "群聊信息页出现 \(chat.id)")
        }
        .onDisappear {
            CrashCatcher.clearStep()
        }
        .task {

            let live = app.chats.first { $0.id == chat.id } ?? chat
            pinned = live.pinned == true
            muted = live.muted == true
            muteAll = live.muteAll == true
            if let r = try? await API.shared.chatMembers(chatId: chat.id) {
                members = r.members
                ownerId = r.ownerId
                createdAt = r.createdAt
            }
            announce = chatAnnounceFromList()
            loading = false
        }

        .navigationDestination(isPresented: $showAnnounce) { announceEditor }
        .sheet(isPresented: $showRename) { renameEditor }
        .sheet(isPresented: $showAlias) { aliasEditor }

        .navigationDestination(isPresented: Binding(
            get: { cardUser != nil },
            set: { if !$0 { cardUser = nil } }
        )) {
            if let u = cardUser {
                ContactCardView(user: u,
                                onOpenChat: { _ in cardUser = nil },
                                onOpenMoments: { _ in cardUser = nil })
                    .environmentObject(app)
            }
        }
        .navigationDestination(isPresented: $showSearch) { ChatSearchView(chat: chat) }
        .fullScreenCover(isPresented: $showGroupBg) {
            NavigationStack {
                ChatBackgroundSheet(chatId: chat.id, modal: true)
                    .environmentObject(app)
            }
        }
        .fullScreenCover(isPresented: $showGroupTheme, onDismiss: {
            ChatThemeStore.shared.refresh(chat.id)
        }) {
            ChatThemePickerView(chatId: chat.id)
        }
        .sheet(isPresented: $showComplaint) {
            GroupComplaintView(chatId: chat.id, groupName: chat.name)
                .environmentObject(app)
        }
        .navigationDestination(isPresented: $showQR) { GroupQRView(chat: chat) }
        .navigationDestination(isPresented: $showAdd) {
            GroupAddMembersView(chat: chat, existing: members.map { $0.id }) { names in
                app.show(names.isEmpty ? Tr("没有新增成员") : (Tr("已邀请 ") + names.joined(separator: "、") + Tr(" 进群")))
                Task {
                    if let r = try? await API.shared.chatMembers(chatId: chat.id) { members = r.members }
                    await app.loadChats()
                }
            }
        }
        .navigationDestination(isPresented: $showAllMembers) {
            GroupMembersPage(chat: chat, members: members, ownerId: ownerId)
                .environmentObject(app)
        }
        .onReceive(NotificationCenter.default.publisher(for: ChatSearchJump.didRequest)) { note in
            guard let target = ChatSearchJump.destination(from: note),
                  target.chatId == chat.id else { return }
            showSearch = false
            dismiss()
        }

        .overlay {
            if confirmClear {
                PanelConfirmDialog(title: Tr("确定要清空这个聊天的记录吗？"),
                                   okText: Tr("清空"), danger: true,
                                   onOk: { confirmClear = false; clearHistory() },
                                   onCancel: { confirmClear = false })
            }
        }

        .overlay {
            if confirmQuit {
                PanelConfirmDialog(title: isOwner ? "解散并退出该群聊？" : "退出该群聊？",
                                   okText: isOwner ? Tr("解散并退出") : Tr("退出"),
                                   danger: true,
                                   onOk: { confirmQuit = false; quitGroup() },
                                   onCancel: { confirmQuit = false })
            }
        }

        .overlay {
            if let target = kickTarget {
                PanelConfirmDialog(
                    title: kickMode == "kick"
                        ? ("确定要将「" + target.name + "」移出群聊吗？")
                        : ("确定要将「" + target.name + "」禁言吗？"),
                    okText: kickMode == "kick" ? Tr("移出群聊") : Tr("禁言"),
                    danger: true,
                    onOk: { if kickMode == "kick" { kick() } else { muteMember() } },
                    onCancel: { kickTarget = nil })
            }
        }
    }

    private func muteMember() {
        guard let target = kickTarget else { return }
        Task {
            if let err = await API.shared.setMemberMuted(chatId: chat.id, userId: target.id, muted: true) {
                app.show(err)
            } else {
                app.show("已禁言 \(target.name)")
            }
            kickTarget = nil
        }
    }

    private func chatAnnounceFromList() -> String { chat.announce ?? "" }

    private var announceEditor: some View {
        GroupAnnounceView(
            text: announce,
            groupName: chat.name,
            editable: isOwner,
            onSave: { value in
                announceDraft = value
                saveAnnounce()
            },
            onDelete: {
                deleteAnnounce()
            }
        )
    }

    private var renameEditor: some View {
        editorSheet(title: "修改群名称",
                    icon: "pencil", colors: PanelTint.blue,
                    placeholder: "群名称（最多 30 字）",
                    hint: "群名会显示在所有成员的会话列表里",
                    limit: 30, singleLine: true,
                    text: $nameDraft, editable: true) {
            saveName()
        }
    }

    private var aliasEditor: some View {
        editorSheet(title: aliasTitle,
                    icon: "character.cursor.ibeam", colors: PanelTint.purple,
                    placeholder: "最多 16 个字",
                    hint: "群昵称只在这个群里显示；留空就是取消",
                    limit: 16, singleLine: true,
                    text: $aliasDraft, editable: true) {
            saveAlias()
        }
    }

    private func editAlias(_ target: User?) {
        aliasTarget = target
        aliasTitle = (target == nil || target?.id == app.me?.id)
            ? Tr("我在本群的昵称") : Tr("设置群昵称")
        aliasDraft = target?.alias ?? members.first(where: { $0.id == app.me?.id })?.alias ?? ""
        showAlias = true
    }

    private func saveAlias() {
        let target = aliasTarget?.id ?? (app.me?.id ?? "")
        let text = aliasDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            let ok = await API.shared.setGroupAlias(chatId: chat.id, userId: target, alias: text)
            showAlias = false
            guard ok else { app.show(Tr("没保存上，再试一次")); return }

            if let i = members.firstIndex(where: { $0.id == target }) { members[i].alias = text }
            app.show(text.isEmpty ? Tr("群昵称已取消") : Tr("群昵称已设置"))
        }
    }

    private func editorSheet(title: String, icon: String, colors: [Color],
                             placeholder: String, hint: String, limit: Int,
                             singleLine: Bool,
                             text: Binding<String>, editable: Bool,
                             onSave: @escaping () -> Void) -> some View {
        let count = text.wrappedValue.count
        let over = count > limit
        return VStack(spacing: 0) {
            NavBar(title: title, back: { closeEditors() }) {
                if editable {
                    Button { onSave() } label: {
                        Text(Tr("保存"))
                            .font(pf(14.5, .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 15)
                            .frame(height: 32)
                            .background(Capsule().fill(over
                                ? AnyShapeStyle(C.subLabel.opacity(0.5))
                                : AnyShapeStyle(LinearGradient(colors: PanelTint.green,
                                                                startPoint: .topLeading,
                                                                endPoint: .bottomTrailing))))
                            .padding(.trailing, 14)
                    }
                    .buttonStyle(.plain)
                    .disabled(over)
                }
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    PanelCard(solid: true) {

                        HStack(spacing: 11) {
                            PanelIcon(symbol: icon, colors: colors)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(title)
                                    .font(pf(16, .medium))
                                    .foregroundColor(C.label)
                                Text(hint)
                                    .font(pf(12))
                                    .foregroundColor(C.subLabel)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 8)
                            Text("\(count)/\(limit)")
                                .font(pf(12.5, .medium))
                                .foregroundColor(over ? C.red : C.subLabel)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)

                        PanelDivider()

                        if singleLine {
                            ZStack(alignment: .leading) {
                                if text.wrappedValue.isEmpty {
                                    Text(placeholder)
                                        .font(pf(16))
                                        .foregroundColor(C.subLabel.opacity(0.8))
                                }
                                TextField("", text: text)
                                    .font(pf(16))
                                    .foregroundColor(C.label)
                                    .disabled(!editable)
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 58)
                        } else {
                            ZStack(alignment: .topLeading) {
                                if text.wrappedValue.isEmpty {
                                    Text(placeholder)
                                        .font(pf(15))
                                        .foregroundColor(C.subLabel.opacity(0.8))
                                        .padding(.horizontal, 16)
                                        .padding(.top, 14)
                                }
                                TextEditor(text: text)
                                    .font(pf(15))
                                    .scrollContentBackground(.hidden)
                                    .padding(.horizontal, 11)
                                    .padding(.top, 6)
                                    .disabled(!editable)
                            }
                            .frame(height: 168)
                        }
                    }

                    if !editable {
                        Text(Tr("你不是群主，这里只能看。"))
                            .font(pf(12))
                            .foregroundColor(C.subLabel)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 6)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 30)
            }
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { closeEditors() }
    }

    private func closeEditors() {
        showAnnounce = false
        showRename = false
        showAlias = false
    }

    private func saveAnnounce() {
        let text = announceDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { app.show(Tr("群公告不能为空")); return }
        Task {
            if let err = await API.shared.updateChatInfo(chatId: chat.id, name: chat.name, announce: text) {
                app.show(err)
            } else {
                announce = text
                app.applyChatAnnouncementLocally(chatId: chat.id, announce: text)
                do {
                    _ = try await API.shared.send(chatId: chat.id, kind: "announce", content: text)
                    await app.loadChats()
                    app.show(Tr("群公告已发布"))
                } catch {
                    await app.loadChats()
                    app.show((error as? APIError)?.errorDescription
                             ?? Tr("群公告已保存，但群消息发送失败"))
                }
                showAnnounce = false
            }
        }
    }

    private func deleteAnnounce() {
        Task {
            if let err = await API.shared.updateChatInfo(chatId: chat.id, name: chat.name, announce: "") {
                app.show(err)
            } else {
                announce = ""
                app.applyChatAnnouncementLocally(chatId: chat.id, announce: "")
                await app.loadChats()
                app.show(Tr("群公告已删除"))
            }
        }
    }

    private func saveName() {
        let n = nameDraft.trimmingCharacters(in: .whitespaces)
        if n.isEmpty { app.show(Tr("群名称不能为空")); return }
        Task {
            if let err = await API.shared.updateChatInfo(chatId: chat.id, name: n, announce: announce) {
                app.show(err)
            } else {
                showRename = false
                await app.loadChats()
                app.show(Tr("群名称已修改"))
            }
        }
    }

    private func clearHistory() {
        Task {
            if let err = await API.shared.clearChat(chatId: chat.id) {
                app.show(err)
            } else {
                app.forgetChatHistory(chat.id)
                app.show(Tr("聊天记录已清空"))
            }
        }
    }

    private func quitGroup() {
        let wasOwner = isOwner
        let previousChat = app.openChat
        app.hideChatLocally(chat.id)
        dismiss()
        onExitChat()
        app.show(wasOwner ? Tr("正在解散群聊…") : Tr("正在退出群聊…"))
        Task {
            let err = wasOwner ? await API.shared.dismissGroup(chatId: chat.id)
                               : await API.shared.leaveGroup(chatId: chat.id)
            if let err = err {
                app.revealChatLocally(chat.id)
                await app.loadChats()
                app.openChat = previousChat
                app.show(err)
            } else {
                await app.loadChats()
                app.show(wasOwner ? "群已解散" : "已退出群聊")
            }
        }
    }

    private func deleteChat() {
        let previousChat = app.openChat
        app.hideChatLocally(chat.id)
        dismiss()
        onExitChat()
        app.show(Tr("正在删除…"))
        Task {
            if let err = await API.shared.deleteChat(chatId: chat.id) {
                app.revealChatLocally(chat.id)
                await app.loadChats()
                app.openChat = previousChat
                app.show(err)
                return
            }
            app.forgetChatHistory(chat.id)
            await app.loadChats()
            app.show(Tr("已删除该聊天"))
        }
    }

    private func kick() {
        guard let target = kickTarget else { return }
        Task {
            if let err = await API.shared.kickMember(chatId: chat.id, userId: target.id) {
                app.show(err)
            } else {
                app.show("已把 \(target.name) 移出群聊")
                kickTarget = nil
                if let r = try? await API.shared.chatMembers(chatId: chat.id) { members = r.members }
                await app.loadChats()
            }
        }
    }

    private var groupInfoNativeItems: [NativeStaticItem] {
        let memberKey = members.map {
            "\($0.id):\($0.alias ?? ""):\($0.avatarPath):\($0.qqLevel ?? 0)"
        }.joined(separator: "|")
        return [
            NativeStaticItem(
                id: "head",
                signature: "\(chat.name)|\(chat.avatar ?? "")|\(memberKey)|\(createdText)"
            ),
            NativeStaticItem(
                id: "members",
                signature: "\(loading)-\(removing)-\(isOwner)-\(ownerId)-\(memberKey)"
            ),
            NativeStaticItem(id: "settings-title", signature: Tr("群聊设置")),
            NativeStaticItem(
                id: "info",
                signature: "\(chat.name)|\(announce)|\(myAlias)|\(ownerName)"
            ),
            NativeStaticItem(
                id: "switches",
                signature: "\(pinned)-\(muteAll)-\(muted)-\(isOwner)"
            ),
            NativeStaticItem(id: "tools", signature: "\(chat.id)-\(Lang.code)"),
            NativeStaticItem(id: "actions-title", signature: Tr("操作")),
            NativeStaticItem(id: "danger", signature: "\(isOwner)")
        ]
    }

    @ViewBuilder
    private func groupInfoNativeRow(_ item: NativeStaticItem) -> some View {
        switch item.id {
        case "head":
            headCard
                .padding(.horizontal, 14)
                .padding(.top, 6)
        case "members":
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text(Tr("群成员") + "（\(members.count)）")
                        .font(pf(13, .semibold))
                        .foregroundColor(C.subLabel)
                    Spacer(minLength: 0)
                    if isOwner {
                        ChatInfoTextButton(title: Tr(removing ? "完成" : "管理"),
                                           color: removing ? C.green : C.subLabel) {
                            withAnimation(.easeOut(duration: 0.15)) { removing.toggle() }
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.top, 18)
                .padding(.bottom, 8)
                memberCard
            }
            .padding(.horizontal, 14)
        case "settings-title":
            ChatInfoSectionTitle(text: Tr("群聊设置"))
                .padding(.horizontal, 14)
        case "info":
            infoCard.padding(.horizontal, 14)
        case "switches":
            switchCard.padding(.horizontal, 14)
        case "tools":
            groupToolCard.padding(.horizontal, 14)
        case "actions-title":
            ChatInfoSectionTitle(text: Tr("操作"))
                .padding(.horizontal, 14)
        case "danger":
            VStack(spacing: 0) {
                dangerCard
                Color.clear.frame(height: 30)
            }
            .padding(.horizontal, 14)
        default:
            EmptyView()
        }
    }

    private var headCard: some View {
        GroupCard {
            VStack(spacing: 9) {
                Group {
                    if (chat.avatar ?? "").isEmpty {
                        GroupAvatarMosaic(chatId: chat.id,
                                          memberIds: chat.memberIds ?? members.map(\.id),
                                          size: 76, radius: 19)
                    } else {
                        Avatar(path: chat.avatar ?? "", size: 76, radius: 19, group: true)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 0.8))
                .shadow(color: Color.black.opacity(0.12), radius: 10, y: 4)

                Text(chat.name)
                    .font(pf(20, .semibold))
                    .foregroundColor(C.label)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.top, 3)

                Text(memberLine)
                    .font(pf(13))
                    .foregroundColor(C.subLabel)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 22)
            .padding(.vertical, 22)
        }
    }

    private var memberLine: String {
        if members.isEmpty { return Tr("群聊") }
        var s = "\(members.count) 位成员"
        if !createdText.isEmpty { s += " · " + createdText + "创建" }
        return s
    }

    private var visibleMembers: [User] {
        Array(members.prefix(20))
    }

    private var memberCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if loading && members.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 22)
            } else {
                LazyVGrid(columns: gridColumns, spacing: 14) {
                    ForEach(visibleMembers) { u in
                        VStack(spacing: 6) {
                            ZStack(alignment: .topLeading) {
                                Avatar(path: u.avatarPath, size: 52, radius: 10, level: u.qqLevel ?? 0)

                                if removing && isOwner && u.id != app.me?.id {
                                    Button {
                                        kickMode = "kick"
                                        kickTarget = u
                                    } label: {
                                        Text(Tr("移出"))
                                            .font(pf(9.5, .medium))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 7)
                                            .frame(height: 20)
                                            .background(Capsule().fill(C.red))
                                    }
                                    .buttonStyle(.plain)
                                    .offset(x: -6, y: -6)
                                }
                            }

                            HStack(spacing: 3) {
                                Text(u.groupName)

                                    .font(pf(11))
                                    .foregroundColor(Color.dyn(0x4A4A4A, 0xD8D8D8))
                                    .lineLimit(1)

                                if let lv = u.qqLevel, lv > 0, GrowthFlags.showInContacts != false {
                                    QQLevelBadge(level: lv, size: 10, maxIcons: 2).fixedSize()
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .frame(maxWidth: .infinity)

                        .contentShape(Rectangle())
                        .onTapGesture { cardUser = u }
                        .contextMenu {
                            Button { cardUser = u } label: { Label(Tr("查看资料"), systemImage: "person.crop.circle") }
                            if u.id == app.me?.id || isOwner {
                                Button {
                                    editAlias(u.id == app.me?.id ? nil : u)
                                } label: { Label(Tr(u.id == app.me?.id ? "我在本群的昵称" : "设置群昵称"),
                                                 systemImage: "character.cursor.ibeam") }
                            }
                            if isOwner && u.id != app.me?.id {

                                Button(role: .destructive) {
                                    kickMode = "kick"
                                    kickTarget = u
                                } label: { Label(Tr("移出群聊"), systemImage: "person.badge.minus") }
                                Button {
                                    kickMode = "mute"
                                    kickTarget = u
                                } label: { Label(Tr("禁言"), systemImage: "speaker.slash") }
                                Button {
                                    Task { _ = await API.shared.setMemberMuted(chatId: chat.id, userId: u.id, muted: false) }
                                } label: { Label(Tr("取消禁言"), systemImage: "speaker.wave.2") }
                            } else {
                                Button { } label: { Label(Tr("只有群主能管理成员"), systemImage: "info.circle") }
                            }
                        }
                    }

                    if members.count > 20 {
                        VStack(spacing: 6) {
                            Button {
                                showAllMembers = true
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.dyn(0xF2F2F2, 0x2C2C31))
                                        .frame(width: 52, height: 52)
                                    Text(Tr("更多"))
                                        .font(pf(11.5, .medium))
                                        .foregroundColor(C.subLabel)
                                }
                            }
                            .buttonStyle(.plain)
                            Text(Tr("更多群成员"))
                                .font(pf(10.5))
                                .foregroundColor(C.subLabel)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    VStack(spacing: 6) {
                        Button { showAdd = true } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(C.hairline, lineWidth: 1)
                                    .frame(width: 52, height: 52)
                                Text(Tr("添加"))
                                    .font(pf(11.5, .medium))
                                    .foregroundColor(C.subLabel)
                            }
                        }
                        .buttonStyle(.plain)
                        Text(Tr("成员")).font(pf(10.5)).foregroundColor(C.subLabel)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 12)
                .padding(.top, 16)
                .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(ChatInfoCardTint.group))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(C.hairline, lineWidth: 0.6))
        .shadow(color: Color.black.opacity(0.05), radius: 8, y: 2)
    }

    private var infoCard: some View {
        GroupCard {
            ChatInfoTextRow(title: Tr("群聊名称"), value: chat.name,
                            symbol: "person.3.fill",
                            symbolTint: Color(hex: 0x34C759)) {
                nameDraft = chat.name
                if isOwner { showRename = true }
                else { app.show(Tr("只有群主能改群名称")) }
            }
            ChatInfoDivider()
            ChatInfoTextRow(title: Tr("我在本群的昵称"),
                            value: myAlias.isEmpty ? Tr("未设置") : myAlias,
                            symbol: "at",
                            symbolTint: Color(hex: 0x0A84FF)) {
                editAlias(nil)
            }
            ChatInfoDivider()
            ChatInfoTextRow(title: Tr("群公告"),
                            subtitle: announce.isEmpty ? nil : announce,
                            value: announce.isEmpty ? Tr("未设置") : nil,
                            symbol: "megaphone.fill",
                            symbolTint: Color(hex: 0xFF9F0A)) {
                announceDraft = announce
                showAnnounce = true
            }
            ChatInfoDivider()
            ChatInfoTextRow(title: Tr("群主"), value: ownerName,
                            symbol: "crown.fill",
                            symbolTint: Color(hex: 0xFFD60A)) { }
        }
    }

    private var switchCard: some View {
        GroupCard {
            ChatInfoToggleRow(title: Tr("置顶聊天"),
                              subtitle: pinned ? Tr("已置顶，会排在会话列表最上面") : nil,
                              isOn: pinned,
                              symbol: "pin.fill",
                              symbolTint: Color(hex: 0x0A84FF)) { v in
                pinned = v
                app.applyPinnedLocally(chatId: chat.id, pinned: v)
                Task {
                    guard let now = await API.shared.setPinned(chatId: chat.id, pinned: v) else {
                        pinned = !v
                        app.applyPinnedLocally(chatId: chat.id, pinned: !v)
                        app.show(Tr("置顶设置失败"))
                        return
                    }
                    pinned = now
                    app.applyPinnedLocally(chatId: chat.id, pinned: now)
                    await app.loadChats()
                }
            }
            if isOwner {
                ChatInfoDivider()
                ChatInfoToggleRow(title: Tr("全员禁言"),
                                  subtitle: muteAll ? Tr("已开启，群里只有你能发言") : nil,
                                  isOn: muteAll,
                                  symbol: "speaker.slash.fill",
                                  symbolTint: Color(hex: 0xFF9F0A)) { v in
                    muteAll = v
                    Task {
                        if let err = await API.shared.setMuteAll(chatId: chat.id, on: v) {
                            app.show(err)
                            muteAll = !v
                        }
                    }
                }
            }
            ChatInfoDivider()
            ChatInfoToggleRow(title: Tr("消息免打扰"),
                              subtitle: muted ? Tr("这个群来消息不响也不弹") : nil,
                              isOn: muted,
                              symbol: "bell.slash.fill",
                              symbolTint: Color(hex: 0x8E8E93)) { v in
                muted = v
                app.applyMutedLocally(chatId: chat.id, muted: v)
                Task {
                    guard let now = await API.shared.setMuted(chatId: chat.id, muted: v) else {
                        muted = !v
                        app.applyMutedLocally(chatId: chat.id, muted: !v)
                        app.show(Tr("免打扰设置失败"))
                        return
                    }
                    muted = now
                    app.applyMutedLocally(chatId: chat.id, muted: now)
                    await app.loadChats()
                }
            }
        }
    }

    private var groupToolCard: some View {
        GroupCard {
            ChatInfoTextRow(title: Tr("群二维码"), symbol: "qrcode",
                            symbolTint: Color(hex: 0x0A84FF)) { showQR = true }
            ChatInfoDivider()
            ChatInfoTextRow(title: Tr("查找聊天记录"), symbol: "magnifyingglass",
                            symbolTint: Color(hex: 0x0A84FF)) { showSearch = true }
            ChatInfoDivider()
            ChatInfoTextRow(title: Tr("聊天主题"), symbol: "paintpalette.fill",
                            symbolTint: Color(hex: 0xAF52DE)) { showGroupTheme = true }
            ChatInfoDivider()
            ChatInfoTextRow(title: Tr("设置当前聊天背景"), symbol: "photo.fill",
                            symbolTint: Color(hex: 0x5E5CE6)) { showGroupBg = true }
            ChatInfoDivider()
            ChatInfoTextRow(title: Tr("群语音通话"),
                            subtitle: Tr("和群里的人一起语音"),
                            symbol: "phone.fill",
                            symbolTint: Color(hex: 0x34C759)) {
                CallCenter.shared.startGroupCall(chatId: chat.id, title: chat.name)
                dismiss()
            }
            ChatInfoDivider()
            ChatInfoTextRow(title: Tr("群视频通话"),
                            subtitle: Tr("和群里的人一起视频"),
                            symbol: "video.fill",
                            symbolTint: Color(hex: 0x0A84FF)) {
                CallCenter.shared.startGroupCall(chatId: chat.id, title: chat.name, video: true)
                dismiss()
            }
            ChatInfoDivider()
            ChatInfoTextRow(title: Tr("投诉群聊"),
                            subtitle: Tr("违法违规、诈骗或骚扰"),
                            symbol: "exclamationmark.shield.fill",
                            symbolTint: Color(hex: 0xFF9F0A)) {
                showComplaint = true
            }
        }
        .padding(.top, 10)
    }

    private var dangerCard: some View {
        GroupCard {
            ChatInfoTextRow(title: Tr("清空聊天记录"), destructive: true,
                            symbol: "trash.fill",
                            symbolTint: Color(hex: 0xFF3B30)) { confirmClear = true }
            ChatInfoDivider()
            ChatInfoTextRow(title: Tr("删除该聊天"), destructive: true,
                            symbol: "bubble.left.and.bubble.right.fill",
                            symbolTint: Color(hex: 0xFF3B30)) { deleteChat() }
            ChatInfoDivider()
            ChatInfoTextRow(title: isOwner ? "解散并退出群聊" : "退出群聊",
                            destructive: true,
                            symbol: "rectangle.portrait.and.arrow.right",
                            symbolTint: Color(hex: 0xFF3B30)) { confirmQuit = true }
        }
    }
}

struct GroupMembersPage: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    let chat: Chat
    let members: [User]
    let ownerId: String

    @State private var query = ""
    @State private var selected: User? = nil

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 0), spacing: 12, alignment: .top),
        count: 5
    )

    private var filtered: [User] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return members }
        return members.filter {
            $0.name.localizedCaseInsensitiveContains(q)
                || ($0.username ?? "").localizedCaseInsensitiveContains(q)
                || ($0.remark ?? "").localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("全部群成员"), back: { dismiss() }) {
                Text("\(members.count)")
                    .font(pf(13, .semibold))
                    .foregroundColor(C.subLabel)
                    .padding(.trailing, 14)
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(C.subLabel)
                        TextField(Tr("搜索群成员"), text: $query)
                            .font(pf(15))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if !query.isEmpty {
                            Button { query = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(C.subLabel.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 13)
                    .frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(C.cardBg))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(C.hairline, lineWidth: 0.6))

                    GroupCard {
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(filtered) { u in
                                Button { selected = u } label: {
                                    VStack(spacing: 7) {
                                        Avatar(path: u.avatarPath, size: 54, radius: 11,
                                               level: u.qqLevel ?? 0)
                                        Text(u.groupName)
                                            .font(pf(11.5))
                                            .foregroundColor(C.label)
                                            .lineLimit(1)
                                        if u.id == ownerId {
                                            Text(Tr("群主"))
                                                .font(pf(9.5, .medium))
                                                .foregroundColor(C.green)
                                                .lineLimit(1)
                                        } else {
                                            Text(u.id == app.me?.id ? Tr("我") : " ")
                                                .font(pf(9.5))
                                                .foregroundColor(C.subLabel)
                                                .lineLimit(1)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 18)
                    }

                    if filtered.isEmpty {
                        Text(Tr("没有找到群成员"))
                            .font(pf(13))
                            .foregroundColor(C.subLabel)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 36)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 30)
            }
        }
        .background(C.pageBg.ignoresSafeArea())
        .environment(\.chatInfoCardTone, .group)
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .navigationDestination(isPresented: Binding(
            get: { selected != nil },
            set: { if !$0 { selected = nil } }
        )) {
            if let u = selected {
                ContactCardView(user: u,
                                onOpenChat: { _ in selected = nil },
                                onOpenMoments: { _ in selected = nil })
                    .environmentObject(app)
            }
        }
    }
}

struct GroupComplaintView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    let chatId: String
    let groupName: String

    @State private var reason = "违法违规"
    @State private var detail = ""
    @State private var busy = false

    private let reasons = ["违法违规", "诈骗或欺诈", "色情低俗", "骚扰或辱骂", "侵权或冒充", "其他问题"]

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("投诉群聊"), back: { dismiss() }) {
                Button { submit() } label: {
                    Text(busy ? Tr("提交中…") : Tr("提交"))
                        .font(pf(14.5, .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 15)
                        .frame(height: 32)
                        .background(Capsule().fill(busy ? C.subLabel : C.green))
                        .padding(.trailing, 14)
                }
                .buttonStyle(.plain)
                .disabled(busy)
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    GroupCard {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(Tr("投诉对象"))
                                .font(pf(12.5, .medium))
                                .foregroundColor(C.subLabel)
                            Text(groupName)
                                .font(pf(17, .semibold))
                                .foregroundColor(C.label)
                                .lineLimit(2)
                            Text(Tr("投诉信息仅用于安全审核，群成员不会看到。"))
                                .font(pf(12.5))
                                .foregroundColor(C.subLabel)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(Tr("问题类型"))
                            .font(pf(13, .medium))
                            .foregroundColor(C.subLabel)
                            .padding(.leading, 4)
                        GroupCard {
                            ForEach(reasons.indices, id: \.self) { index in
                                if index > 0 { HairLine(inset: 16) }
                                Button {
                                    reason = reasons[index]
                                } label: {
                                    HStack(spacing: 10) {
                                        Text(Tr(reasons[index]))
                                            .font(pf(15.5))
                                            .foregroundColor(C.label)
                                        Spacer(minLength: 0)
                                        Text(reason == reasons[index] ? Tr("已选择") : Tr("选择"))
                                            .font(pf(12.5, reason == reasons[index] ? .medium : .regular))
                                            .foregroundColor(reason == reasons[index] ? C.green : C.subLabel)
                                    }
                                    .padding(.horizontal, 16)
                                    .frame(height: 48)
                                    .background(reason == reasons[index]
                                        ? C.green.opacity(0.06)
                                        : Color.clear)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(Tr("事实说明"))
                            .font(pf(13, .medium))
                            .foregroundColor(C.subLabel)
                            .padding(.leading, 4)
                        GroupCard {
                            ZStack(alignment: .topLeading) {
                                if detail.isEmpty {
                                    Text(Tr("请说明发生时间、具体行为和相关聊天内容，选填"))
                                        .font(pf(14))
                                        .foregroundColor(C.subLabel.opacity(0.75))
                                        .padding(.horizontal, 15)
                                        .padding(.top, 13)
                                }
                                TextEditor(text: $detail)
                                    .font(pf(14.5))
                                    .foregroundColor(C.label)
                                    .scrollContentBackground(.hidden)
                                    .padding(.horizontal, 10)
                                    .padding(.top, 5)
                            }
                            .frame(height: 130)
                            .overlay(alignment: .bottomTrailing) {
                                Text("\(detail.count)/200")
                                    .font(pf(10.5))
                                    .foregroundColor(C.subLabel)
                                    .padding(.trailing, 12)
                                    .padding(.bottom, 9)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(Tr("提交须知"))
                            .font(pf(13, .semibold))
                            .foregroundColor(C.label)
                        Text(Tr("· 请如实提供可核实的信息，安全团队会结合聊天记录审核。"))
                        Text(Tr("· 审核期间可能需要补充说明，请留意系统通知。"))
                        Text(Tr("· 恶意投诉或重复提交不实信息会被记录。"))
                        Text(Tr("· 除执法或安全审核需要外，不会向被投诉方披露投诉人身份。"))
                    }
                    .font(pf(12.5))
                    .foregroundColor(C.subLabel)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 30)
            }
        }
        .background(C.pageBg.ignoresSafeArea())
        .onChange(of: detail) { value in
            if value.count > 200 { detail = String(value.prefix(200)) }
        }
    }

    private func submit() {
        guard !busy else { return }
        busy = true
        Task {
            let note = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            let err = await API.shared.reportGroup(
                chatId: chatId,
                groupName: groupName,
                reason: reason,
                content: note
            )
            busy = false
            if let err {
                app.show(err)
            } else {
                dismiss()
                app.show(Tr("投诉已提交，安全团队会尽快审核"))
            }
        }
    }
}

struct GroupAnnounceEditor: View {
    @Binding var text: String
    var editable = true
    var onClose: () -> Void
    var onPublish: () -> Void

    @FocusState private var focused: Bool
    private let limit = 500
    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var over: Bool { text.count > limit }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("编辑群公告"), back: { onClose() }) {
                EmptyView()
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    HStack(alignment: .top, spacing: 13) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(C.green.opacity(0.13))
                            Image(systemName: "megaphone.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(C.green)
                        }
                        .frame(width: 42, height: 42)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(Tr(editable ? "写公告给全群成员" : "群公告"))
                                .font(pf(16, .semibold))
                                .foregroundColor(C.label)
                            Text(Tr(editable
                                    ? "发布后所有群成员会收到提示"
                                    : "群公告仅群成员可见"))
                                .font(pf(12.5))
                                .foregroundColor(C.subLabel)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(C.cardBg)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(C.hairline.opacity(0.7), lineWidth: 0.6)
                    }

                    VStack(spacing: 0) {
                        HStack(spacing: 8) {
                            Text(Tr("正文"))
                                .font(pf(13, .semibold))
                                .foregroundColor(C.subLabel)
                            Spacer(minLength: 0)
                            Text("\(text.count)/\(limit)")
                                .font(pf(12, .medium))
                                .foregroundColor(over ? C.red : C.subLabel)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 44)

                        HairLine(inset: 16)

                        if editable {
                            ZStack(alignment: .topLeading) {
                                if text.isEmpty {
                                    Text(Tr("写点什么，群里所有人都能看到"))
                                        .font(pf(16))
                                        .foregroundColor(C.subLabel.opacity(0.62))
                                        .padding(.horizontal, 15)
                                        .padding(.vertical, 15)
                                        .allowsHitTesting(false)
                                }
                                TextEditor(text: $text)
                                    .font(pf(16))
                                    .foregroundColor(C.label)
                                    .scrollContentBackground(.hidden)
                                    .focused($focused)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .frame(minHeight: 280, maxHeight: 380)
                                    .onChange(of: text) { value in
                                        if value.count > limit {
                                            text = String(value.prefix(limit))
                                        }
                                    }
                            }
                        } else {
                            Text(text.isEmpty ? Tr("群主还没发公告") : text)
                                .font(pf(16))
                                .foregroundColor(C.label)
                                .lineSpacing(7)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(C.cardBg)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(C.hairline.opacity(0.7), lineWidth: 0.6)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, editable ? 112 : 30)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(C.pageBg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if editable {
                VStack(spacing: 10) {
                    HStack(spacing: 7) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9.5, weight: .semibold))
                        Text(Tr("仅群成员可见"))
                        Spacer(minLength: 0)
                        Text(Tr("发布后立即生效"))
                    }
                    .font(pf(11.5))
                    .foregroundColor(C.subLabel)

                    Button {
                        focused = false
                        onPublish()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 14, weight: .semibold))
                            Text(Tr("发布群公告"))
                                .font(pf(16, .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            LinearGradient(colors: PanelTint.green,
                                           startPoint: .topLeading,
                                           endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(trimmed.isEmpty || over)
                    .opacity(trimmed.isEmpty || over ? 0.45 : 1)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, max(10, L.safeBottom))
                .background(C.pageBg)
                .overlay(alignment: .top) { HairLine() }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { onClose() }
        .hidesTabBar()
        .onAppear {
            guard editable else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                focused = true
            }
        }
    }
}

struct GroupAnnounceView: View {
    let text: String
    var groupName: String = ""
    var editable: Bool = false
    var onSave: ((String) -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var draft = ""
    @State private var confirmDelete = false

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("群公告"), back: { dismiss() }) {
                if editable {
                    Button {
                        draft = text
                        editing = true
                    } label: {
                        Text(Tr("编辑"))
                            .font(pf(15, .medium))
                            .foregroundColor(C.green)
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                    }
                    .buttonStyle(.plain)
                    .disabled(editing)
                }
            }
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(
                                    LinearGradient(colors: PanelTint.green,
                                                   startPoint: .topLeading,
                                                   endPoint: .bottomTrailing)
                                )
                            Image(systemName: "megaphone.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .frame(width: 58, height: 58)
                        .shadow(color: C.green.opacity(0.22), radius: 9, y: 4)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(trimmed.isEmpty ? Tr("暂无群公告") : Tr("群公告"))
                                .font(pf(19, .semibold))
                                .foregroundColor(C.label)
                            if !groupName.isEmpty {
                                Text(groupName)
                                    .font(pf(13))
                                    .foregroundColor(C.subLabel)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)

                        Text(Tr("全员可见"))
                            .font(pf(11.5, .semibold))
                            .foregroundColor(C.green)
                            .padding(.horizontal, 9)
                            .frame(height: 26)
                            .background(Capsule().fill(C.green.opacity(0.11)))
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(C.cardBg)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(C.hairline.opacity(0.7), lineWidth: 0.6)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(Tr("公告内容"))
                                .font(pf(13, .semibold))
                                .foregroundColor(C.subLabel)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 18)
                        .frame(height: 46)

                        HairLine(inset: 18)
                        if trimmed.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "text.alignleft")
                                    .font(.system(size: 28, weight: .light))
                                    .foregroundColor(C.subLabel.opacity(0.62))
                                Text(Tr("暂时没有群公告"))
                                    .font(pf(16, .medium))
                                    .foregroundColor(C.label)
                                Text(editable ? Tr("点右上角“编辑”添加公告") : Tr("群主发布后会显示在这里"))
                                    .font(pf(12.5))
                                    .foregroundColor(C.subLabel)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 46)
                        } else {
                            Text(text)
                                .font(pf(16))
                                .foregroundColor(C.label)
                                .lineSpacing(8)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 22)
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(C.cardBg))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(C.hairline.opacity(0.72), lineWidth: 0.6))

                    if editable, !trimmed.isEmpty, onDelete != nil {
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "trash")
                                    .font(.system(size: 15, weight: .semibold))
                                Text(Tr("删除公告"))
                                    .font(pf(16, .medium))
                                Spacer(minLength: 0)
                            }
                            .foregroundColor(C.red)
                            .padding(.horizontal, 18)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(C.cardBg)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(C.hairline.opacity(0.72), lineWidth: 0.6)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9.5, weight: .semibold))
                        Text(Tr("群公告仅群成员可见"))
                    }
                        .font(pf(11.5))
                        .foregroundColor(C.subLabel)
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 30)
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .confirmationDialog(
            Tr("删除群公告？"),
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button(Tr("删除公告"), role: .destructive) {
                onDelete?()
                dismiss()
            }
            Button(Tr("取消"), role: .cancel) {}
        } message: {
            Text(Tr("删除后群成员将看不到这条公告"))
        }
        .fullScreenCover(isPresented: $editing) {
            GroupAnnounceEditor(
                text: $draft,
                editable: true,
                onClose: { editing = false },
                onPublish: {
                    let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty else { return }
                    onSave?(value)
                    editing = false
                }
            )
        }
    }
}

struct DirectChatInfoView: View {
    @ObservedObject private var lang = LangStore.shared
    let chat: Chat
    var onExitChat: () -> Void = {}

    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var peer: User?
    @State private var pinned = false
    @State private var muted = false

    @State private var showSearch = false
    @State private var showCard = false

    @State private var showChatBg = false
    @State private var showChatTheme = false
    @State private var confirmClear = false
    @State private var confirmDelete = false
    @State private var confirmBlock = false
    @State private var confirmDeleteFriend = false
    @State private var friendMeta: API.FriendMeta?

    @State private var sysPage: SysPage? = nil

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("聊天信息"), back: { dismiss() })
            if chat.sysTeam == true {
                sysQuickBar
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 2)
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    peerCard
                    if chat.sysTeam != true, peer?.banned == true || friendMeta?.block == true {
                        relationshipStatusCard
                    }
                    if chat.sysTeam == true {
                        teamSimpleIntro
                    } else {
                        ChatInfoSectionTitle(text: Tr("聊天设置"))
                        switchCard
                        ChatInfoSectionTitle(text: Tr("常用"))
                        toolCard
                        ChatInfoSectionTitle(text: Tr("操作"))
                        dangerCard
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 30)
            }
        }
        .background(C.pageBg.ignoresSafeArea())
        .environment(\.chatInfoCardTone, .direct)
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .onAppear {
            CrashCatcher.markStep("三点", "单聊信息页出现 \(chat.id)")
        }
        .onDisappear {
            CrashCatcher.clearStep()
        }
        .task {

            let live = app.chats.first { $0.id == chat.id } ?? chat
            pinned = live.pinned == true
            muted = live.muted == true
            if let r = try? await API.shared.chatMembers(chatId: chat.id) {
                peer = r.members.first { $0.id != app.me?.id }
            }

            if peer == nil, let other = chat.memberIds?.first(where: { $0 != app.me?.id }) {
                peer = try? await API.shared.user(id: other)
            }
            if let id = peer?.id {
                friendMeta = try? await API.shared.friendMeta(userId: id)
            }
        }

        .navigationDestination(isPresented: $showSearch) { ChatSearchView(chat: chat) }
        .onReceive(NotificationCenter.default.publisher(for: ChatSearchJump.didRequest)) { note in
            guard let target = ChatSearchJump.destination(from: note),
                  target.chatId == chat.id else { return }
            showSearch = false
            dismiss()
        }

        .sheet(item: $sysPage) { p in
            switch p {
            case .tools:
                SysToolsView { key in
                    sysPage = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        sysPage = sysDestination(for: key)
                    }
                }
            case .support:
                SupportView().environmentObject(app)
            case .kefu:
                KefuPage().environmentObject(app)
            case .security:
                AccountSecurityView().environmentObject(app)
            case .devices:
                LoginDevicesView().environmentObject(app)
            case .safety:
                AccountSafetyCenterView().environmentObject(app)
            case .feedback:
                FeedbackView().environmentObject(app)
            case .delete:
                DeleteAccountView().environmentObject(app)
            }
        }
        .fullScreenCover(isPresented: $showChatBg) {
            NavigationStack {
                ChatBackgroundSheet(chatId: chat.id, modal: true)
                    .environmentObject(app)
            }
        }
        .fullScreenCover(isPresented: $showChatTheme, onDismiss: {
            ChatThemeStore.shared.refresh(chat.id)
        }) {
            ChatThemePickerView(chatId: chat.id)
        }
        .navigationDestination(isPresented: $showCard) {
            if let p = peer {
                ContactCardView(user: p,
                                onOpenChat: { _ in showCard = false },
                                onOpenMoments: { _ in showCard = false })
                    .environmentObject(app)
            }
        }

        .overlay {
            if confirmClear {
                PanelConfirmDialog(title: Tr("确定要清空这个聊天的记录吗？"),
                                   okText: Tr("清空"), danger: true,
                                   onOk: { confirmClear = false; clearHistory() },
                                   onCancel: { confirmClear = false })
            }
        }
        .overlay {
            if confirmDelete {
                PanelConfirmDialog(title: Tr("确定要删除这个聊天吗？"),
                                   okText: Tr("删除"), danger: true,
                                   onOk: { confirmDelete = false; deleteChat() },
                                   onCancel: { confirmDelete = false })
            }
        }
        .overlay {
            if confirmBlock {
                PanelConfirmDialog(
                    title: Tr("加入黑名单？"),
                    okText: Tr("加入黑名单"),
                    danger: true,
                    message: Tr("对方将无法给你发消息，也看不到你的朋友圈。聊天记录会保留。"),
                    symbol: "hand.raised.fill",
                    onOk: {
                        confirmBlock = false
                        setBlocked(true)
                    },
                    onCancel: { confirmBlock = false }
                )
            }
        }
        .overlay {
            if confirmDeleteFriend {
                PanelConfirmDialog(
                    title: Tr("删除好友？"),
                    okText: Tr("删除好友"),
                    danger: true,
                    message: Tr("删除后将解除好友关系并从通讯录移除。聊天记录不会被自动删除。"),
                    symbol: "person.badge.minus",
                    onOk: {
                        confirmDeleteFriend = false
                        removeFriend()
                    },
                    onCancel: { confirmDeleteFriend = false }
                )
            }
        }
    }

    private var relationshipStatusCard: some View {
        GroupCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: friendMeta?.block == true
                      ? "hand.raised.fill"
                      : "exclamationmark.shield.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(C.red)
                    .frame(width: 34, height: 34)
                    .background(C.red.opacity(0.10), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(friendMeta?.block == true ? Tr("已加入黑名单") : Tr("账号已被封禁"))
                        .font(pf(15.5, .semibold))
                        .foregroundColor(C.label)
                    Text(relationshipStatusDetail)
                        .font(pf(12.5))
                        .foregroundColor(C.subLabel)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .padding(.top, 14)
    }

    private var relationshipStatusDetail: String {
        if friendMeta?.block == true {
            return Tr("你已阻止对方发消息并隐藏朋友圈。可在下方移出黑名单。")
        }
        let reason = peer?.banReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return reason.isEmpty ? Tr("该账号已被管理员封禁，暂时无法正常聊天。")
                             : Tr("原因：") + reason
    }

    private var peerCard: some View {
        GroupCard {
            HStack(spacing: 12) {
                Avatar(path: peer?.avatarPath ?? "", size: 68, radius: 16, level: peer?.qqLevel ?? 0)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.35), lineWidth: 0.8))
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(peer?.name ?? chat.name)
                            .font(pf(18, .semibold))
                            .foregroundColor(C.label)
                            .lineLimit(1)
                        if let lv = peer?.qqLevel, lv > 0 {
                            QQLevelBadge(level: lv, size: 13, maxIcons: 2).fixedSize()
                        }
                    }
                    if let un = peer?.username, !un.isEmpty {
                        Text(Tr("星言号") + "：" + un)
                            .font(pf(12.5))
                            .foregroundColor(C.subLabel)
                            .lineLimit(1)

                            .copyOnLongPress(un) { app.show($0) }
                    }
                }
                Spacer(minLength: 0)
                if peer != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(C.subLabel.opacity(0.65))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { if peer != nil { showCard = true } }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
    }

    private var switchCard: some View {
        GroupCard {
            ChatInfoToggleRow(title: Tr("置顶聊天"),
                              subtitle: pinned ? Tr("已置顶，会排在会话列表最上面") : nil,
                              isOn: pinned,
                              symbol: "pin.fill",
                              symbolTint: Color(hex: 0x0A84FF)) { v in
                pinned = v
                app.applyPinnedLocally(chatId: chat.id, pinned: v)
                Task {
                    guard let now = await API.shared.setPinned(chatId: chat.id, pinned: v) else {
                        pinned = !v
                        app.applyPinnedLocally(chatId: chat.id, pinned: !v)
                        app.show(Tr("置顶设置失败"))
                        return
                    }
                    pinned = now
                    app.applyPinnedLocally(chatId: chat.id, pinned: now)
                    await app.loadChats()
                }
            }
            ChatInfoDivider()
            ChatInfoToggleRow(title: Tr("消息免打扰"),
                              subtitle: muted ? Tr("这个人来消息不响也不弹") : nil,
                              isOn: muted,
                              symbol: "bell.slash.fill",
                              symbolTint: Color(hex: 0x8E8E93)) { v in
                muted = v
                app.applyMutedLocally(chatId: chat.id, muted: v)
                Task {
                    guard let now = await API.shared.setMuted(chatId: chat.id, muted: v) else {
                        muted = !v
                        app.applyMutedLocally(chatId: chat.id, muted: !v)
                        app.show(Tr("免打扰设置失败"))
                        return
                    }
                    muted = now
                    app.applyMutedLocally(chatId: chat.id, muted: now)
                    await app.loadChats()
                }
            }
        }
    }

    private var teamSimpleIntro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Tr("星言团队"))
                .font(pf(15, .semibold))
                .foregroundColor(C.label)
            Text(Tr("为你处理账号安全、登录设备、密码找回、投诉申诉和产品反馈。需要帮助时，直接使用上方的自助工具或联系客服。"))
                .font(pf(13))
                .foregroundColor(C.subLabel)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(ChatInfoCardTint.direct)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.top, 14)
    }

    private var sysQuickBar: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)], spacing: 10) {
            sysQuickButton(title: Tr("自助工具"),
                           sub: Tr("改密码 · 登录设备")
                           ) { sysPage = .tools }
            sysQuickButton(title: Tr("帮助中心"),
                           sub: Tr("常见问题 · 工单")
                           ) { sysPage = .support }
            sysQuickButton(title: Tr("安全中心"),
                           sub: Tr("冻结 · 解冻 · 解封")
                           ) { sysPage = .safety }
            sysQuickButton(title: Tr("意见反馈"),
                           sub: Tr("提交问题 · 看回复")
                           ) { sysPage = .feedback }
        }
    }

    private func sysQuickButton(title: String, sub: String,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(pf(14, .semibold))
                    .foregroundColor(C.label)
                    .lineLimit(1)
                Text(sub)
                    .font(pf(10.5))
                    .foregroundColor(C.subLabel)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(ChatInfoCardTint.direct)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sysDestination(for key: String) -> SysPage {
        switch key {
        case "pwd": return .security
        case "devices": return .devices
        case "support": return .support
        case "safety": return .safety
        case "feedback": return .feedback
        case "delete": return .delete
        default: return .kefu
        }
    }

    private var sysCard: some View {
        PanelCard(solid: true) {
            PanelRow(symbol: "wrench.and.screwdriver.fill", colors: PanelTint.green,
                     title: Tr("自助工具"),
                     value: Tr("改密码 / 登录设备 / 找回密码")) { sysPage = .tools }
            PanelDivider()
            PanelRow(symbol: "headphones", colors: PanelTint.blue,
                     title: Tr("联系客服"),
                     value: Tr("常见问题 / 转人工")) { sysPage = .kefu }
        }
    }

    private var toolCard: some View {
        GroupCard {
            ChatInfoTextRow(title: Tr("语音通话"), symbol: "phone.fill",
                            symbolTint: Color(hex: 0x34C759)) { start(video: false) }
            ChatInfoDivider()
            ChatInfoTextRow(title: Tr("视频通话"), symbol: "video.fill",
                            symbolTint: Color(hex: 0x0A84FF)) { start(video: true) }
            ChatInfoDivider()
            ChatInfoTextRow(title: Tr("查找聊天记录"), symbol: "magnifyingglass",
                            symbolTint: Color(hex: 0x0A84FF)) { showSearch = true }
            ChatInfoDivider()
            ChatInfoTextRow(title: Tr("聊天主题"), symbol: "paintpalette.fill",
                            symbolTint: Color(hex: 0xAF52DE)) { showChatTheme = true }
            ChatInfoDivider()
            ChatInfoTextRow(title: Tr("设置当前聊天背景"), symbol: "photo.fill",
                            symbolTint: Color(hex: 0x5E5CE6)) {
                showChatBg = true
            }
        }
    }

    private var dangerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupCard {
                if peer != nil {
                    if friendMeta?.block == true {
                        safetyActionRow(
                            symbol: "hand.raised.slash.fill",
                            title: Tr("移出黑名单"),
                            subtitle: Tr("恢复接收消息和查看朋友圈"),
                            destructive: false
                        ) { setBlocked(false) }
                    } else {
                        safetyActionRow(
                            symbol: "hand.raised.fill",
                            title: Tr("加入黑名单"),
                            subtitle: Tr("阻止对方发消息并隐藏你的朋友圈"),
                            destructive: true
                        ) { confirmBlock = true }
                    }
                    if peer?.relation == "friend" {
                        ChatInfoDivider()
                        safetyActionRow(
                            symbol: "person.badge.minus",
                            title: Tr("删除好友"),
                            subtitle: Tr("解除好友关系并从通讯录移除"),
                            destructive: true
                        ) { confirmDeleteFriend = true }
                    }
                    ChatInfoDivider()
                }
                ChatInfoTextRow(title: Tr("清空聊天记录"), destructive: true,
                                symbol: "trash.fill",
                                symbolTint: Color(hex: 0xFF3B30)) { confirmClear = true }
                ChatInfoDivider()
                ChatInfoTextRow(title: Tr("删除该聊天"), destructive: true,
                                symbol: "bubble.left.and.bubble.right.fill",
                                symbolTint: Color(hex: 0xFF3B30)) { confirmDelete = true }
            }
            Text(Tr("危险操作会立即影响你和对方的联系。删除聊天只会移除本地会话，不会删除对方的好友关系。"))
                .font(pf(12))
                .foregroundColor(C.subLabel)
                .lineSpacing(2)
                .padding(.horizontal, 4)
        }
    }

    private func safetyActionRow(symbol: String, title: String, subtitle: String,
                                 destructive: Bool,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(destructive ? C.red : C.subLabel)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(pf(15.5, .medium))
                        .foregroundColor(destructive ? C.red : C.label)
                    Text(subtitle)
                        .font(pf(12.5))
                        .foregroundColor(C.subLabel)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func setBlocked(_ value: Bool) {
        guard let id = peer?.id else { return }
        let previous = friendMeta
        var optimistic = friendMeta ?? API.FriendMeta()
        optimistic.block = value
        friendMeta = optimistic
        Task {
            if await API.shared.setFriendMeta(userId: id, block: value) {
                app.show(value ? Tr("已加入黑名单") : Tr("已移出黑名单"))
                await app.loadContacts()
                await app.loadChats()
            } else {
                friendMeta = previous
                app.show(Tr("没保存上，再试一次"))
            }
        }
    }

    private func removeFriend() {
        guard let id = peer?.id else { return }
        Task {
            if let err = await API.shared.removeFriend(userId: id) {
                app.show(err)
                return
            }
            app.applyFriendRemoved(userId: id)
            await app.loadContacts()
            await app.loadChats()
            app.returnToChatsList()
            dismiss()
            onExitChat()
            app.show(Tr("已删除好友"))
        }
    }

    private func start(video: Bool) {
        let p = peer
        CallCenter.shared.start(peerId: p?.id ?? "",
                                name: p?.name ?? chat.name,
                                avatar: p?.avatarPath ?? "",
                                video: video)
        dismiss()
    }

    private func clearHistory() {
        Task {
            if let err = await API.shared.clearChat(chatId: chat.id) {
                app.show(err)
            } else {
                app.forgetChatHistory(chat.id)
                app.show(Tr("聊天记录已清空"))
            }
        }
    }

    private func deleteChat() {
        let previousChat = app.openChat
        app.hideChatLocally(chat.id)
        dismiss()
        onExitChat()
        app.show(Tr("正在删除…"))
        Task {
            if let err = await API.shared.deleteChat(chatId: chat.id) {
                app.revealChatLocally(chat.id)
                await app.loadChats()
                app.openChat = previousChat
                app.show(err)
                return
            }
            app.forgetChatHistory(chat.id)
            await app.loadChats()
            app.show(Tr("已删除该聊天"))
        }
    }
}

struct GroupAddMembersView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    let chat: Chat

    let existing: [String]

    var onDone: ([String]) -> Void

    @State private var keyword = ""
    @State private var picked: Set<String> = []
    @State private var busy = false
    @State private var showAllCandidates = false

    private var candidates: [User] {
        let set = Set(existing)
        let base = app.contacts.filter { !set.contains($0.id) && $0.id != app.me?.id }
        guard !keyword.isEmpty else { return base }
        return base.filter { $0.name.contains(keyword) }
    }

    private var visibleCandidates: [User] {
        if showAllCandidates || !keyword.isEmpty { return candidates }
        return Array(candidates.prefix(8))
    }

    private var canExpandCandidates: Bool {
        keyword.isEmpty && candidates.count > 8
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("加人"), back: { dismiss() }) {
                Button { submit() } label: {
                    Text(busy ? Tr("加入中…") : Tr("完成"))
                        .font(pf(17))
                        .foregroundColor(picked.isEmpty ? C.subLabel : C.green)
                        .frame(height: L.navH)
                        .padding(.trailing, 16)
                }
                .buttonStyle(.plain)
                .disabled(picked.isEmpty || busy)
            }

            SearchBoxCenter(text: $keyword)
                .padding(L.searchPad)

            if candidates.isEmpty {
                Text(Tr("没有可以邀请的好友了"))
                    .font(pf(14)).foregroundColor(C.subLabel)
                    .padding(.top, 40)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visibleCandidates) { u in
                            Button {
                                if picked.contains(u.id) { picked.remove(u.id) } else { picked.insert(u.id) }
                            } label: {
                                HStack(spacing: 12) {
                                    Avatar(path: u.avatarPath, size: 40, radius: 4)
                                    Text(u.name).font(pf(17)).foregroundColor(C.label).lineLimit(1)
                                    Spacer(minLength: 0)
                                    Image(systemName: picked.contains(u.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 20))
                                        .foregroundColor(picked.contains(u.id) ? C.green : C.subLabel)
                                }
                                .padding(.horizontal, 16)
                                .frame(height: 60)
                                .background(C.cardBg)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            HairLine(inset: 68)
                        }

                        if canExpandCandidates {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showAllCandidates.toggle()
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(showAllCandidates
                                         ? Tr("收起列表")
                                         : Tr("展开全部") + "（\(candidates.count)）")
                                        .font(pf(14, .medium))
                                        .foregroundColor(OrbitTheme.gold)
                                    Image(systemName: showAllCandidates ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(OrbitTheme.gold.opacity(0.86))
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(C.cardBg)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .background(C.pageBg)
            }
        }
        .background(C.pageBg.ignoresSafeArea(edges: .bottom))
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
    }

    private func submit() {
        guard !picked.isEmpty, !busy else { return }
        busy = true
        let ids = Array(picked)
        Task {
            let r = await API.shared.addGroupMembers(chatId: chat.id, userIds: ids)
            busy = false
            if let err = r.error {
                app.show(err)
                return
            }
            onDone(r.added)
            dismiss()
        }
    }
}

private struct ChatInfoSectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(pf(13, .semibold))
            .foregroundColor(C.subLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 22)
            .padding(.bottom, 9)
    }
}

private struct ChatInfoTextRow: View {
    let title: String
    var subtitle: String? = nil
    var value: String? = nil
    var destructive = false
    var symbol: String? = nil
    var symbolTint: Color = C.green
    var tap: () -> Void

    var body: some View {
        Button(action: tap) {
            HStack(spacing: 12) {
                if let symbol {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(symbolTint.opacity(destructive ? 0.12 : 0.13))
                        Image(systemName: symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(destructive ? C.red : symbolTint)
                    }
                    .frame(width: 31, height: 31)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(pf(15.5, .medium))
                        .foregroundColor(destructive
                            ? Color.dyn(0xE03A3A, 0xFF6B6B)
                            : C.label)
                        .lineLimit(1)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(pf(12.5))
                            .foregroundColor(C.subLabel)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 10)
                if let value, !value.isEmpty {
                    Text(value)
                        .font(pf(14.5))
                        .foregroundColor(C.subLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ChatInfoToggleRow: View {
    let title: String
    var subtitle: String? = nil
    let isOn: Bool
    var symbol: String? = nil
    var symbolTint: Color = C.green
    let onChange: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let symbol {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(symbolTint.opacity(0.13))
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(symbolTint)
                }
                .frame(width: 31, height: 31)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(pf(15.5, .medium))
                    .foregroundColor(C.label)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(pf(12.5))
                        .foregroundColor(C.subLabel)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(get: { isOn }, set: onChange))
                .labelsHidden()
                .tint(C.green)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 58)
    }
}

private struct ChatInfoDivider: View {
    var body: some View { HairLine(inset: 16) }
}

private struct ChatInfoTextButton: View {
    let title: String
    var color: Color = C.green
    let tap: () -> Void

    var body: some View {
        Button(action: tap) {
            Text(title)
                .font(pf(13.5, .medium))
                .foregroundColor(color)
                .padding(.horizontal, 12)
                .frame(height: 30)
        }
        .buttonStyle(.plain)
    }
}
