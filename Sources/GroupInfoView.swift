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

    @State private var burn = false

    @State private var faceForBurn = false
    @State private var announce = ""
    @State private var showAnnounce = false
    @State private var announceDraft = ""
    @State private var showRename = false
    @State private var nameDraft = ""
    @State private var showSearch = false
    @State private var membersExpanded = false
    @State private var visibleMemberLimit = 20
    @State private var expandingMembers = false
    @State private var showComplaint = false

    @State private var showGroupBg = false
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

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    headCard

                    VStack(spacing: 0) {
                        HStack(spacing: 8) {
                            Text(Tr("群成员") + "（\(members.count)）")
                                .font(pf(12.5, .medium))
                                .foregroundColor(C.subLabel)
                            Spacer(minLength: 0)

                            ChatInfoTextButton(title: Tr("添加")) { showAdd = true }
                            if isOwner {
                                ChatInfoTextButton(title: Tr(removing ? "完成" : "管理"),
                                                   color: removing ? C.green : C.subLabel) {
                                    withAnimation(.easeOut(duration: 0.15)) { removing.toggle() }
                                }
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.top, 14)
                        .padding(.bottom, 6)
                        memberCard
                    }
                    ChatInfoSectionTitle(text: Tr("群聊设置"))
                    infoCard
                    switchCard
                    groupToolCard
                    ChatInfoSectionTitle(text: Tr("操作"))
                    dangerCard
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 30)
            }
        }
        .background(C.pageBg.ignoresSafeArea())
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
            burn = live.burn == true
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
        .sheet(isPresented: $showGroupBg) {
            ChatBackgroundSheet(chatId: chat.id).environmentObject(app)
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

        GroupAnnounceEditor(text: $announceDraft, editable: isOwner,
                            onClose: { closeEditors() },
                            onPublish: { saveAnnounce() })
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

                _ = try? await API.shared.send(chatId: chat.id, kind: "announce", content: text)
                await app.loadChats()
                showAnnounce = false
                app.show(Tr("群公告已发布"))
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

    private var headCard: some View {
        GroupCard {
            HStack(spacing: 14) {
                Group {
                    if (chat.avatar ?? "").isEmpty {
                        GroupAvatarMosaic(chatId: chat.id,
                                          memberIds: chat.memberIds ?? members.map(\.id),
                                          size: 64, radius: 14)
                    } else {
                        Avatar(path: chat.avatar ?? "", size: 64, radius: 14, group: true)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 0.8))
                VStack(alignment: .leading, spacing: 6) {
                    Text(chat.name)
                        .font(pf(17, .semibold))
                        .foregroundColor(C.label)
                        .lineLimit(1)
                    Text(memberLine)
                        .font(pf(12.5))
                        .foregroundColor(C.subLabel)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
        }
    }

    private var memberLine: String {
        if members.isEmpty { return Tr("群聊") }
        var s = "\(members.count) 位成员"
        if !createdText.isEmpty { s += " · " + createdText + "创建" }
        return s
    }

    private var visibleMembers: [User] {
        let limit = membersExpanded ? visibleMemberLimit : min(20, members.count)
        return Array(members.prefix(min(limit, members.count)))
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

                    if members.count > 20 && !membersExpanded {
                        VStack(spacing: 6) {
                            Button {
                                membersExpanded = true
                                visibleMemberLimit = min(60, members.count)
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
            if membersExpanded && visibleMemberLimit < members.count {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .onAppear { loadNextMemberBatch() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(C.cardBg))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(C.hairline, lineWidth: 0.6))
        .shadow(color: Color.black.opacity(0.05), radius: 8, y: 2)
    }

    private var infoCard: some View {
        GroupCard {
            ChatInfoTextRow(title: Tr("群聊名称"), value: chat.name) {
                nameDraft = chat.name
                if isOwner { showRename = true }
                else { app.show(Tr("只有群主能改群名称")) }
            }
            ChatInfoDivider()
            ChatInfoTextRow(title: Tr("我在本群的昵称"),
                            value: myAlias.isEmpty ? Tr("未设置") : myAlias) {
                editAlias(nil)
            }
            ChatInfoDivider()
            ChatInfoTextRow(title: Tr("群公告"),
                            subtitle: announce.isEmpty ? nil : announce,
                            value: announce.isEmpty ? Tr("未设置") : nil) {
                announceDraft = announce
                showAnnounce = true
            }
            ChatInfoDivider()
            ChatInfoTextRow(title: Tr("群主"), value: ownerName) { }
        }
    }

    private var switchCard: some View {
        GroupCard {
            ChatInfoToggleRow(title: Tr("置顶聊天"),
                              subtitle: pinned ? Tr("已置顶，会排在会话列表最上面") : nil,
                              isOn: pinned) { v in
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
                                  isOn: muteAll) { v in
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
                              isOn: muted) { v in
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
            ChatInfoDivider()
            ChatInfoToggleRow(title: Tr("阅后即焚"),
                              subtitle: burn ? Tr("群里发的消息，看过 20 秒后自动消失") : nil,
                              isOn: burn) { v in
                if v {
                    faceForBurn = true
                } else {
                    burn = false
                    Task {
                        _ = await API.shared.setChatBurn(chatId: chat.id, on: false)
                        await app.loadChats()
                    }
                }
            }
            .sheet(isPresented: $faceForBurn) {
                FaceVerifyFlowView { ok in
                    faceForBurn = false
                    if ok {
                        burn = true
                        Task {
                            burn = await API.shared.setChatBurn(chatId: chat.id, on: true)
                            await app.loadChats()
                            app.show(Tr("人脸验证通过，阅后即焚已打开"))
                        }
                    } else {
                        app.show(Tr("人脸验证没通过，阅后即焚先保持关闭"))
                    }
                }
                .environmentObject(app)
            }
        }
    }

    private var groupToolCard: some View {
        GroupCard {
            ChatInfoTextRow(title: Tr("群二维码")) { showQR = true }
            ChatInfoDivider()
            ChatInfoTextRow(title: Tr("查找聊天记录")) { showSearch = true }
            ChatInfoDivider()
            ChatInfoTextRow(title: Tr("设置当前聊天背景")) { showGroupBg = true }
            ChatInfoDivider()
            ChatInfoTextRow(title: Tr("群语音通话"),
                            subtitle: Tr("和群里的人一起语音")) {
                CallCenter.shared.startGroupCall(chatId: chat.id, title: chat.name)
                dismiss()
            }
            ChatInfoDivider()
            ChatInfoTextRow(title: Tr("群视频通话"),
                            subtitle: Tr("和群里的人一起视频")) {
                CallCenter.shared.startGroupCall(chatId: chat.id, title: chat.name, video: true)
                dismiss()
            }
            ChatInfoDivider()
            ChatInfoTextRow(title: Tr("投诉群聊"),
                            subtitle: Tr("违法违规、诈骗或骚扰")) {
                showComplaint = true
            }
        }
        .padding(.top, 10)
    }

    private func loadNextMemberBatch() {
        guard membersExpanded, !expandingMembers, visibleMemberLimit < members.count else { return }
        expandingMembers = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 40_000_000)
            guard membersExpanded else {
                expandingMembers = false
                return
            }
            visibleMemberLimit = min(members.count, visibleMemberLimit + 60)
            expandingMembers = false
        }
    }

    private var dangerCard: some View {
        GroupCard {
            ChatInfoTextRow(title: Tr("清空聊天记录"), destructive: true) { confirmClear = true }
            ChatInfoDivider()
            ChatInfoTextRow(title: Tr("删除该聊天"), destructive: true) { deleteChat() }
            ChatInfoDivider()
            ChatInfoTextRow(title: isOwner ? "解散并退出群聊" : "退出群聊",
                            destructive: true) { confirmQuit = true }
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

    private let limit = 500
    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var over: Bool { text.count > limit }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("群公告"), back: { onClose() }) {
                if editable {
                    Button { onPublish() } label: {
                        Text(Tr("发布"))
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
                    .disabled(trimmed.isEmpty || over)
                }
            }

            ZStack(alignment: .topLeading) {
                if editable {
                    TextEditor(text: $text)
                        .font(pf(16.5))
                        .foregroundColor(C.label)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                        .onChange(of: text) { v in
                            if v.count > limit { text = String(v.prefix(limit)) }
                        }
                    if text.isEmpty {
                        Text(Tr("写点什么，群里所有人都能看到"))
                            .font(pf(16.5))
                            .foregroundColor(C.subLabel.opacity(0.7))
                            .padding(.horizontal, 17)
                            .padding(.top, 18)
                            .allowsHitTesting(false)
                    }
                } else {

                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(text.isEmpty ? Tr("群主还没发公告") : text)
                                .font(pf(16.5))
                                .foregroundColor(C.label)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                            Spacer().frame(height: 30)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(C.cardBg)

            HStack(spacing: 8) {
                Text(editable ? Tr("发布后群里会收到一条公告") : Tr("群公告只有群主能改"))
                    .font(pf(12)).foregroundColor(C.subLabel)
                Spacer(minLength: 0)
                Text("\(text.count)/\(limit)")
                    .font(pf(12)).foregroundColor(over ? C.red : C.subLabel)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(C.cardBg)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { onClose() }
        .hidesTabBar()
    }
}

struct GroupAnnounceView: View {
    let text: String
    var groupName: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("群公告"), back: { dismiss() })
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 10) {
                            Image(systemName: "megaphone.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(C.green)
                                .frame(width: 38, height: 38)
                                .background(C.green.opacity(0.10))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(Tr("群公告"))
                                    .font(pf(16.5, .semibold))
                                    .foregroundColor(C.label)
                                if !groupName.isEmpty {
                                    Text(groupName)
                                        .font(pf(12.5))
                                        .foregroundColor(C.subLabel)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)

                        HairLine(inset: 18)

                        Text(text)
                            .font(pf(16))
                            .foregroundColor(C.label)
                            .lineSpacing(6)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 18)
                    }
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(C.cardBg))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(C.hairline.opacity(0.72), lineWidth: 0.6))

                    Text(Tr("群公告仅群成员可见"))
                        .font(pf(11.5))
                        .foregroundColor(C.subLabel)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 30)
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
    }
}

struct DirectChatInfoView: View {
    @ObservedObject private var lang = LangStore.shared
    let chat: Chat
    var onExitChat: () -> Void = {}

    @State private var faceForBurn = false

    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var peer: User?
    @State private var pinned = false
    @State private var muted = false

    @State private var burn = false
    @State private var showSearch = false
    @State private var showCard = false

    @State private var showChatBg = false
    @State private var confirmClear = false
    @State private var confirmDelete = false

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
            burn = live.burn == true
            if let r = try? await API.shared.chatMembers(chatId: chat.id) {
                peer = r.members.first { $0.id != app.me?.id }
            }

            if peer == nil, let other = chat.memberIds?.first(where: { $0 != app.me?.id }) {
                peer = try? await API.shared.user(id: other)
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
        .sheet(isPresented: $showChatBg) {
            ChatBackgroundSheet(chatId: chat.id).environmentObject(app)
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
    }

    private var peerCard: some View {
        GroupCard {
            HStack(spacing: 12) {
                Avatar(path: peer?.avatarPath ?? "", size: 60, radius: 14, level: peer?.qqLevel ?? 0)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.35), lineWidth: 0.8))
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(peer?.name ?? chat.name)
                            .font(pf(17, .semibold))
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
            }
            .contentShape(Rectangle())
            .onTapGesture { if peer != nil { showCard = true } }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
        }
    }

    private var switchCard: some View {
        GroupCard {
            ChatInfoToggleRow(title: Tr("置顶聊天"),
                              subtitle: pinned ? Tr("已置顶，会排在会话列表最上面") : nil,
                              isOn: pinned) { v in
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
                              isOn: muted) { v in
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
            ChatInfoDivider()
            ChatInfoToggleRow(title: Tr("阅后即焚"),
                              subtitle: burn ? Tr("这个人发的消息，看过 20 秒后自动消失") : nil,
                              isOn: burn) { v in
                if v {
                    faceForBurn = true
                } else {
                    burn = false
                    Task {
                        _ = await API.shared.setChatBurn(chatId: chat.id, on: false)
                        await app.loadChats()
                    }
                }
            }
        }
        .sheet(isPresented: $faceForBurn) {
            FaceVerifyFlowView { ok in
                faceForBurn = false
                if ok {
                    burn = true
                    Task {
                        burn = await API.shared.setChatBurn(chatId: chat.id, on: true)
                        await app.loadChats()
                        app.show(Tr("人脸验证通过，阅后即焚已打开"))
                    }
                } else {
                    app.show(Tr("人脸验证没通过，阅后即焚先保持关闭"))
                }
            }
            .environmentObject(app)
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
        .background(C.cardBg)
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
            .background(C.cardBg)
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
            ChatInfoTextRow(title: Tr("语音通话")) { start(video: false) }
            ChatInfoDivider()
            ChatInfoTextRow(title: Tr("视频通话")) { start(video: true) }
            ChatInfoDivider()
            ChatInfoTextRow(title: Tr("查找聊天记录")) { showSearch = true }
            ChatInfoDivider()
            ChatInfoTextRow(title: Tr("设置当前聊天背景")) {
                showChatBg = true
            }
        }
    }

    private var dangerCard: some View {
        GroupCard {
            ChatInfoTextRow(title: Tr("清空聊天记录"), destructive: true) { confirmClear = true }
            ChatInfoDivider()
            ChatInfoTextRow(title: Tr("删除该聊天"), destructive: true) { confirmDelete = true }
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

    private var candidates: [User] {
        let set = Set(existing)
        let base = app.contacts.filter { !set.contains($0.id) && $0.id != app.me?.id }
        guard !keyword.isEmpty else { return base }
        return base.filter { $0.name.contains(keyword) }
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
                        ForEach(candidates) { u in
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
            .font(pf(12.5))
            .foregroundColor(C.subLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 14)
            .padding(.bottom, 7)
    }
}

private struct ChatInfoTextRow: View {
    let title: String
    var subtitle: String? = nil
    var value: String? = nil
    var destructive = false
    var tap: () -> Void

    var body: some View {
        Button(action: tap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(pf(16))
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
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ChatInfoToggleRow: View {
    let title: String
    var subtitle: String? = nil
    let isOn: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(pf(16))
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
        .frame(minHeight: 52)
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
