import SwiftUI

struct ProfileEditViewOld: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var nickname = ""
    @ObservedObject private var ring = Ringtone.shared
    @State private var showRingtone = false
    @State private var bio = ""
    @State private var region = ""
    @State private var gender = "male"
    @State private var phone = ""
    @State private var birthday = ""
    @State private var showBirthday = false
    @State private var showRegion = false
    @State private var showPhone = false
    @State private var showPhoto = false
    @State private var busy = false
    @State private var cropImage: UIImage?
    @State private var showMyQR = false

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("个人信息"), back: { dismiss() }) {
                Button {
                    save()
                } label: {
                    Text(busy ? "保存中…" : "保存")
                        .font(pf(17))
                        .foregroundColor(C.green)
                        .frame(height: L.navH)
                        .padding(.trailing, 16)
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                VStack(spacing: 0) {
                    GroupCard {
                        Button {
                            showPhoto = true
                        } label: {
                            HStack(spacing: 12) {
                                Text(Tr("头像")).font(pf(17)).foregroundColor(C.label)
                                Spacer()
                                Avatar(path: app.me?.avatarPath ?? "", size: 56, radius: 6)
                                Chevron(size: 9, line: 1.6).padding(.trailing, 3)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 72)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        HairLine(inset: 16)
                        field("昵称", $nickname)

                        HStack(spacing: 8) {
                            Text(Tr("最多 16 个字符；不能用 < > \" ' / \\ 等符号，不能冒用官方或客服"))
                                .font(pf(12)).foregroundColor(C.subLabel)
                            Spacer(minLength: 0)
                            Text("\(nickname.count)/16")
                                .font(pf(12)).foregroundColor(nickname.count > 16 ? C.red : C.subLabel)
                        }
                        .padding(.horizontal, 16).padding(.bottom, 10)
                        HairLine(inset: 16)

                        HStack(spacing: 12) {
                            Text(Tr("星言号")).font(pf(17)).foregroundColor(C.label)
                                .frame(width: 76, alignment: .leading)
                            Text(app.me?.username ?? "-")
                                .font(pf(17))
                                .foregroundColor(C.subLabel)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 56)
                    }

                    Rectangle().fill(C.pageBg).frame(height: 8)

                    GroupCard {
                        HStack(spacing: 12) {
                            Text(Tr("性别")).font(pf(17)).foregroundColor(C.label)
                            Spacer()
                            Picker("", selection: $gender) {
                                Text(Tr("男")).tag("male")
                                Text(Tr("女")).tag("female")
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 140)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 56)
                        HairLine(inset: 16)

                        Button {
                            showRegion = true
                        } label: {
                            HStack(spacing: 12) {
                                Text(Tr("地区")).font(pf(17)).foregroundColor(C.label)
                                Spacer()
                                Text(region.isEmpty ? Tr("未设置") : region)
                                    .font(pf(15)).foregroundColor(C.subLabel)
                                Chevron(size: 9, line: 1.6).padding(.trailing, 3)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 56)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        HairLine(inset: 16)

                        Button {
                            showBirthday = true
                        } label: {
                            HStack(spacing: 12) {
                                Text(Tr("生日")).font(pf(17)).foregroundColor(C.label)
                                Spacer()
                                Text(birthday.isEmpty ? "未设置" : birthday)
                                    .font(pf(15))
                                    .foregroundColor(C.subLabel)
                                Chevron(size: 9, line: 1.6).padding(.trailing, 3)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 56)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        HairLine(inset: 16)
                        field("个性签名", $bio)
                    }

                    Rectangle().fill(C.pageBg).frame(height: 8)

                    GroupCard {

                        Button {
                            showPhone = true
                        } label: {
                            HStack(spacing: 12) {
                                Text(Tr("手机号"))
                                    .font(pf(17)).foregroundColor(C.label)
                                    .frame(width: 76, alignment: .leading)
                                Spacer(minLength: 0)
                                Text(phone.isEmpty ? Tr("未绑定") : maskPhone(phone))
                                    .font(pf(17)).foregroundColor(C.subLabel)
                                Chevron(size: 9, line: 1.6).padding(.trailing, 3)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 56)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    GroupCard {
                        Button {
                            showRingtone = true
                        } label: {
                            HStack(spacing: 12) {
                                Text(Tr("来电铃声")).font(pf(17)).foregroundColor(C.label)
                                Spacer()
                                Text(ring.currentName)
                                    .font(pf(15))
                                    .foregroundColor(C.subLabel)
                                Chevron(size: 9, line: 1.6).padding(.trailing, 3)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 56)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    Text(Tr("手机号一年只能改一次；头像、昵称、地区、签名想改就改。"))
                        .font(pf(12.5))
                        .foregroundColor(C.subLabel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        .padding(.top, 10)

                    Spacer().frame(height: 30)
                }
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea(edges: .top))
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .onAppear {
            nickname = app.me?.nickname ?? ""
            bio = app.me?.bio ?? ""
            region = app.me?.region ?? ""
            gender = app.me?.gender == "female" ? "female" : "male"
            phone = app.me?.phone ?? ""
            birthday = app.me?.birthday ?? ""
        }
        .sheet(isPresented: $showPhoto) {

            PhotoPicker { image in cropImage = image }
        }
        .sheet(isPresented: Binding(get: { cropImage != nil },
                                    set: { if !$0 { cropImage = nil } })) {
            if let img = cropImage {
                AvatarCropSheet(image: img) { cropped in
                    changeAvatar(cropped)
                    cropImage = nil
                }
            }
        }
        .sheet(isPresented: $showRingtone) {
            RingtonePicker()
        }
        .sheet(isPresented: $showBirthday) {
            BirthdayPickerSheet(birthday: $birthday)
        }
        .sheet(isPresented: $showRegion) {
            RegionPickerSheet { r in region = r }
        }
        .sheet(isPresented: $showPhone) {
            PhoneChangeSheet().environmentObject(app)
        }
        .sheet(isPresented: $showMyQR) { MyQRView() }

        .onChange(of: region) { v in
            if v != (app.me?.region ?? "") { saveNow(["region": v]) }
        }
        .onChange(of: birthday) { v in
            if v != (app.me?.birthday ?? "") { saveNow(["birthday": v]) }
        }
    }

    private func field(_ title: String, _ text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Text(title).font(pf(17)).foregroundColor(C.label).frame(width: 76, alignment: .leading)
            TextField("", text: text)
                .font(pf(17))
                .foregroundColor(C.label)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }

    private func changeAvatar(_ image: UIImage) {
        busy = true
        Task {
            if let url = try? await API.shared.upload(image: image) {
                cacheUploadedImage(image, path: url)
                do {
                    try await API.shared.updateMeChecked(["avatar": url])
                    app.applyMyProfileFields(["avatar": url])
                } catch {
                    busy = false
                    app.show(Tr("头像上传失败，再试一次"))
                    return
                }
                app.show(Tr("头像换好了"))
            }
            busy = false
        }
    }

    private func saveNow(_ fields: [String: Any]) {
        Task {
            do {
                try await API.shared.updateMeChecked(fields)
                app.applyMyProfileFields(fields)
            } catch {
                app.show(error.localizedDescription)
            }
        }
    }

    private func save() {
        busy = true
        Task {
            var fields: [String: Any] = [
                "nickname": nickname,
                "bio": bio,
                "region": region,
                "gender": gender,
                "birthday": birthday
            ]
            if !phone.isEmpty && phone != (app.me?.phone ?? "") { fields["phone"] = phone }
            do {
                try await API.shared.updateMeChecked(fields)
            } catch {

                busy = false
                app.show(error.localizedDescription)
                return
            }
            app.applyMyProfileFields(fields)
            await app.loadContacts()
            busy = false
            app.show(Tr("已保存"))
            dismiss()
        }
    }
}

struct NewFriendsView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var realtime = Realtime.shared

    @State private var incoming: [User] = []
    @State private var outgoing: [User] = []
    @State private var added: [User] = []
    @State private var loading = true
    @State private var keyword = ""
    @State private var busy: Set<String> = []
    @State private var confirmClearFriends = false
    @State private var clearingFriends = false
    @State private var pendingRemoveFriend: User?

    @State private var locallyAccepted: [String: User] = [:]
    private var clearableFriends: [User] {
        app.contacts.filter { $0.bot != true && $0.relation != "self" }
    }

    private func hit(_ u: User) -> Bool {
        if keyword.isEmpty { return true }
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return u.name.localizedCaseInsensitiveContains(query)
            || (u.username ?? "").localizedCaseInsensitiveContains(query)
            || (u.requestMessage ?? "").localizedCaseInsensitiveContains(query)
    }
    private var effectiveIncoming: [User] {
        var rows = incoming
        for user in locallyAccepted.values
            where !rows.contains(where: { $0.id == user.id }) {
            rows.insert(user, at: 0)
        }
        return rows
    }
    private var shownIncoming: [User] { effectiveIncoming.filter(hit) }
    private var shownOutgoing: [User] { outgoing.filter(hit) }
    private var shownAdded: [User] { added.filter(hit) }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("新的朋友"), back: { dismiss() })

            ScrollView {
                LazyVStack(spacing: 10) {
                    orbitHeader
                        .padding(.horizontal, 12)

                    NavigationLink(value: "addFriend") { addFriendRow }
                        .buttonStyle(MenuPressStyle())
                        .padding(.horizontal, 12)

                    if !clearableFriends.isEmpty {
                        Button {
                            confirmClearFriends = true
                        } label: {
                            clearFriendsRow
                        }
                        .buttonStyle(MenuPressStyle())
                        .padding(.horizontal, 12)
                        .disabled(clearingFriends)
                    }

                    if loading && incoming.isEmpty && outgoing.isEmpty && added.isEmpty {
                        HStack { Spacer(); ProgressView(); Spacer() }
                            .frame(height: 76)
                            .background(OrbitTheme.cardBackground())
                            .padding(.horizontal, 12)
                    } else if !loading && shownIncoming.isEmpty && shownOutgoing.isEmpty && shownAdded.isEmpty {
                        Text(Tr("没有匹配的申请记录"))
                            .font(pf(15))
                            .foregroundColor(C.subLabel)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 36)
                            .background(OrbitTheme.cardBackground())
                            .padding(.horizontal, 12)
                    }

                    if !shownIncoming.isEmpty {
                        sectionHeader(Tr("好友申请"), count: shownIncoming.count)
                            .padding(.horizontal, 16)
                        ForEach(shownIncoming) { user in
                            requestRow(user)
                                .background(OrbitTheme.cardBackground())
                                .padding(.horizontal, 12)
                        }
                    }
                    if !shownAdded.isEmpty {
                        sectionHeader(Tr("已添加"), count: shownAdded.count)
                            .padding(.horizontal, 16)
                        ForEach(shownAdded) { user in
                            SwipeDeleteFriendRow(
                                user: user,
                                note: noteOf(user),
                                onOpen: { openChat(user) },
                                onDelete: { pendingRemoveFriend = user }
                            )
                                .padding(.horizontal, 12)
                        }
                    }
                    if !shownOutgoing.isEmpty {
                        sectionHeader(Tr("我添加的"), count: shownOutgoing.count)
                            .padding(.horizontal, 16)
                        ForEach(shownOutgoing) { user in
                            waitingRow(user)
                                .background(OrbitTheme.cardBackground())
                                .padding(.horizontal, 12)
                        }
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, 30)
            }
            .refreshable { await load() }
        }
        .background(OrbitTheme.canvas.ignoresSafeArea(edges: .bottom))
        .background(OrbitTheme.canvas.ignoresSafeArea(edges: .top))
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .task {
            await load()

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if Task.isCancelled { break }
                await load()
            }
        }

        .onChange(of: realtime.event) { ev in
            if ev.type == "friend" { Task { await load() } }
        }
        .onChange(of: app.localOutgoingFriendRequests) { _ in
            mergeLocalOutgoing()
        }
        .confirmationDialog(Tr("清除所有已添加好友？"),
                            isPresented: $confirmClearFriends,
                            titleVisibility: .visible) {
            Button(Tr("清除") + " \(clearableFriends.count) " + Tr("位好友"), role: .destructive) {
                clearAllAddedFriends()
            }
            Button(Tr("取消"), role: .cancel) { }
        } message: {
            Text(Tr("将解除双方好友关系，并从当前账号移除单聊入口和本机记录。机器人、系统号和群聊会保留，此操作不可撤销。"))
        }
        .alert(Tr("删除这位好友？"), isPresented: Binding(
            get: { pendingRemoveFriend != nil },
            set: { if !$0 { pendingRemoveFriend = nil } }
        )) {
            Button(Tr("取消"), role: .cancel) { pendingRemoveFriend = nil }
            Button(Tr("删除"), role: .destructive) {
                if let user = pendingRemoveFriend { removeAddedFriend(user) }
                pendingRemoveFriend = nil
            }
        } message: {
            Text(Tr("将解除双方好友关系，并从当前账号移除单聊入口和本机记录。此操作不可撤销。"))
        }
    }

    private var orbitHeader: some View {
        VStack(spacing: 10) {
            StarOrbitHero(
                kicker: "关系星轨",
                title: Tr("新的朋友"),
                subtitle: Tr("每一次连接，都是星轨上的一次靠近"),
                symbol: "person.2.fill",
                accent: OrbitTheme.jade,
                metrics: [
                    StarOrbitMetric(value: "\(incoming.count)", label: Tr("待确认")),
                    StarOrbitMetric(value: "\(outgoing.count)", label: Tr("已发出"))
                ]
            )

            StarOrbitSearchField(
                placeholder: Tr("搜索昵称、星言号或验证消息"),
                text: $keyword
            )
        }
    }

    private var addFriendRow: some View {
        HStack(spacing: L.ctGap) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(hex: 0x4C93DD))
                Image(systemName: "person.badge.plus").font(.system(size: 18)).foregroundColor(.white)
            }
            .frame(width: L.ctIcon, height: L.ctIcon)
            Text(Tr("添加朋友")).font(pf(L.ctNameSize)).foregroundColor(C.label)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 13)).foregroundColor(C.subLabel)
        }
        .padding(.leading, L.ctPadL)
        .padding(.trailing, 16)
        .frame(height: L.ctRowH)
        .background(OrbitTheme.cardBackground())
        .clipShape(OrbitTheme.card)
        .contentShape(Rectangle())
    }

    private var clearFriendsRow: some View {
        HStack(spacing: L.ctGap) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(C.red)
                Image(systemName: "person.badge.minus")
                    .font(.system(size: 18))
                    .foregroundColor(.white)
            }
            .frame(width: L.ctIcon, height: L.ctIcon)
            Text(Tr("清除已添加的好友"))
                .font(pf(L.ctNameSize))
                .foregroundColor(C.red)
            Spacer(minLength: 0)
            if clearingFriends {
                ProgressView().scaleEffect(0.72)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13))
                    .foregroundColor(C.subLabel)
            }
        }
        .padding(.leading, L.ctPadL)
        .padding(.trailing, 16)
        .frame(height: L.ctRowH)
        .background(OrbitTheme.cardBackground())
        .clipShape(OrbitTheme.card)
        .contentShape(Rectangle())
    }

    private func clearAllAddedFriends() {
        guard !clearingFriends else { return }
        clearingFriends = true
        app.show(Tr("正在清除好友…"))
        Task { @MainActor in
            let result = await API.shared.clearAddedFriends()
            await app.loadContacts()
            await app.loadChats()
            await load()
            clearingFriends = false
            if let error = result.error {
                app.show(Tr("清除失败：") + error)
            } else {
                app.show(Tr("已清除") + " \(result.removed) " + Tr("位好友"))
            }
        }
    }

    private func sectionHeader(_ t: String, count: Int? = nil) -> some View {
        OrbitSectionLabel(text: t, count: count)
        .frame(height: 30)
    }

    private func requestRow(_ user: User) -> some View {
        HStack(spacing: L.ctGap) {
            Avatar(path: user.avatarPath, size: L.ctAvatar, radius: 6)
            VStack(alignment: .leading, spacing: 3) {
                Text(user.name).font(pf(L.ctNameSize)).foregroundColor(C.label).lineLimit(1)
                Text(noteOf(user)).font(pf(13)).foregroundColor(C.subLabel).lineLimit(1)
            }
            Spacer(minLength: 8)
            if locallyAccepted[user.id] != nil {
                Text(Tr("已添加"))
                    .font(pf(14, .medium))
                    .foregroundColor(C.green)
            } else if busy.contains(user.id) {
                ProgressView().scaleEffect(0.72)
            } else {
                Button { respond(user, true) } label: {
                    Text(Tr("接受"))
                        .font(pf(14, .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 13)
                        .frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(C.green))
                }
                .buttonStyle(MenuPressStyle())

                Button { respond(user, false) } label: {
                    Text(Tr("拒绝")).font(pf(14)).foregroundColor(C.subLabel)
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)
            }
        }
        .padding(.leading, L.ctPadL)
        .padding(.trailing, 16)
        .frame(height: 68)
        .contentShape(Rectangle())
        .onTapGesture {
            if locallyAccepted[user.id] != nil { openChat(user) }
        }
    }

    private func doneRow(_ user: User) -> some View {
        HStack(spacing: L.ctGap) {
            Avatar(path: user.avatarPath, size: L.ctAvatar, radius: 6)
            VStack(alignment: .leading, spacing: 3) {
                Text(user.name).font(pf(L.ctNameSize)).foregroundColor(C.label).lineLimit(1)
                Text(noteOf(user)).font(pf(13)).foregroundColor(C.subLabel).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(Tr("已添加")).font(pf(14)).foregroundColor(C.subLabel)
        }
        .padding(.leading, L.ctPadL)
        .padding(.trailing, 16)
        .frame(height: 68)
        .contentShape(Rectangle())
    }

    private func removeAddedFriend(_ user: User) {
        guard !busy.contains(user.id) else { return }
        busy.insert(user.id)
        let removedChatIds = app.chats.filter {
            ($0.type ?? "direct") == "direct" && ($0.memberIds ?? []).contains(user.id)
        }.map(\.id)
        Task { @MainActor in
            if let error = await API.shared.removeFriend(userId: user.id) {
                busy.remove(user.id)
                app.show(Tr("删除失败：") + error)
                return
            }

            added.removeAll { $0.id == user.id }
            locallyAccepted.removeValue(forKey: user.id)
            app.applyFriendRemoved(userId: user.id)
            for chatId in removedChatIds { app.forgetChatHistory(chatId, notify: false) }
            await app.loadContacts()
            await app.loadChats()
            await load()
            busy.remove(user.id)
            app.show(Tr("已删除好友"))
        }
    }

    private func waitingRow(_ user: User) -> some View {
        HStack(spacing: L.ctGap) {
            Avatar(path: user.avatarPath, size: L.ctAvatar, radius: 6)
            VStack(alignment: .leading, spacing: 3) {
                Text(user.name).font(pf(L.ctNameSize)).foregroundColor(C.label).lineLimit(1)
                let n = (user.requestMessage ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !n.isEmpty {
                    Text(n).font(pf(13)).foregroundColor(C.subLabel).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(Tr("等待验证")).font(pf(14)).foregroundColor(C.subLabel)
        }
        .padding(.leading, L.ctPadL)
        .padding(.trailing, 16)
        .frame(height: 68)
        .contentShape(Rectangle())
    }

    private func noteOf(_ user: User) -> String {
        let n = (user.requestMessage ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? Tr("请求加你为好友") : n
    }

    private func openChat(_ user: User) {
        Task {
            guard let chat = try? await API.shared.openDirect(userId: user.id) else {
                app.show(Tr("打不开聊天"))
                return
            }
            app.revealChatLocally(chat.id)
            app.ensureChatVisible(chat)
            app.openChat = chat
            dismiss()
        }
    }

    private func load() async {
        if let d = try? await API.shared.friendRequests() {
            let localIds = Set(locallyAccepted.keys)
            incoming = d.incoming.filter {
                !localIds.contains($0.id)
            }
            outgoing = d.outgoing
            var mergedAdded = d.added
            mergedAdded.removeAll { localIds.contains($0.id) }
            added = mergedAdded
            mergeLocalOutgoing()
            app.contacts = d.friends
            app.friendRequests = incoming.count
        }
        loading = false
    }

    private func mergeLocalOutgoing() {
        let friendIds = Set(app.contacts.map(\.id))
        var merged = outgoing
        for user in app.localOutgoingFriendRequests
            where !friendIds.contains(user.id) && !merged.contains(where: { $0.id == user.id }) {
            merged.insert(user, at: 0)
        }
        outgoing = merged
    }

    private func respond(_ user: User, _ accept: Bool) {

        guard !busy.contains(user.id) else { return }

        let backup = incoming
        busy.insert(user.id)
        if accept { locallyAccepted[user.id] = user }
        if accept { app.applyFriendAccepted(user) }
        withAnimation(.easeOut(duration: 0.18)) {
            incoming.removeAll { $0.id == user.id }
        }
        app.friendRequests = incoming.count
        Task {
            let res: (ok: Bool, pending: Int?, chat: Chat?) = (user.requestId ?? "").isEmpty
                ? await API.shared.respondFriend(userId: user.id, accept: accept)
                : await API.shared.respondFriend(requestId: user.requestId ?? "", accept: accept)
            busy.remove(user.id)
            guard res.ok else {

                locallyAccepted[user.id] = nil
                incoming = backup
                app.friendRequests = incoming.count
                app.show(Tr("网络不太好，再试一次"))
                await app.loadContacts()
                await load()
                return
            }
            if let n = res.pending { app.friendRequests = n }
            app.show(accept ? Tr("已添加到通讯录") : Tr("已拒绝"))
            if accept { UINotification.lightTap() }

            await app.loadContacts()
            await app.loadChats()
            if accept {
                if let chat = res.chat {
                    app.ensureChatVisible(chat)
                    app.openChat = chat
                } else {
                    app.wantChatsTab = true
                }
                dismiss()
                return
            }

            await load()
        }
    }
}

private struct SwipeDeleteFriendRow: View {
    let user: User
    let note: String
    var onOpen: () -> Void
    var onDelete: () -> Void

    @State private var offset: CGFloat = 0
    @State private var startOffset: CGFloat = 0
    @State private var crossedOpen = false

    private let rowHeight: CGFloat = 68
    private let deleteWidth: CGFloat = 80
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    private var swipeAnimation: Animation {
        .interactiveSpring(response: 0.28, dampingFraction: 0.82, blendDuration: 0.08)
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            rowContent
                .frame(height: rowHeight)
                .background(OrbitTheme.cardBackground())
                .offset(x: offset)
                .contentShape(Rectangle())
                .zIndex(1)

            Button {
                close()
                onDelete()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 17, weight: .medium))
                    Text(Tr("删除"))
                        .font(pf(14, .medium))
                        .lineLimit(1)
                }
                .foregroundColor(.white)
                .frame(width: deleteWidth, height: rowHeight)
                .background(C.red)
            }
            .buttonStyle(.plain)
            .frame(width: max(0, -offset), height: rowHeight, alignment: .trailing)
            .clipped()
            .allowsHitTesting(offset < -1)
            .zIndex(2)
        }
        .frame(height: rowHeight)
        .background(OrbitTheme.cardBackground())
        .clipShape(OrbitTheme.card)
        .overlay(alignment: .leading) {
            GeometryReader { geo in
                RowSwipeCatcher(
                    onTap: { _ in
                        if offset != 0 {
                            close()
                        } else {
                            onOpen()
                        }
                    },
                    onBegan: {
                        startOffset = offset
                        crossedOpen = -offset > deleteWidth * 0.42
                        NotificationCenter.default.post(name: .chrisRowSwipe, object: user.id)
                    },
                    onChanged: { dx in
                        var next = startOffset + dx
                        if next > 0 {
                            next = min(8, next * 0.22)
                        } else if next < -deleteWidth {
                            next = -(deleteWidth + min(42, (-next - deleteWidth) * 0.28))
                        }
                        offset = next

                        let nowOpen = -offset > deleteWidth * 0.42
                        if nowOpen != crossedOpen {
                            crossedOpen = nowOpen
                            haptic.impactOccurred(intensity: nowOpen ? 0.55 : 0.32)
                        }
                    },
                    onEnded: { _, velocity in
                        let shouldOpen: Bool
                        if velocity <= -420 {
                            shouldOpen = true
                        } else if velocity >= 420 {
                            shouldOpen = false
                        } else {
                            shouldOpen = -offset > deleteWidth * 0.42
                        }
                        if shouldOpen { haptic.impactOccurred() }
                        withAnimation(swipeAnimation) {
                            offset = shouldOpen ? -deleteWidth : 0
                        }
                    }
                )
                .frame(width: max(0, geo.size.width + offset), height: geo.size.height)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .chrisRowSwipe)) { note in
            if let id = note.object as? String, id != user.id {
                close()
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: L.ctGap) {
            Avatar(path: user.avatarPath, size: L.ctAvatar, radius: 6)
            VStack(alignment: .leading, spacing: 3) {
                Text(user.name)
                    .font(pf(L.ctNameSize))
                    .foregroundColor(C.label)
                    .lineLimit(1)
                Text(note)
                    .font(pf(13))
                    .foregroundColor(C.subLabel)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(Tr("已添加"))
                .font(pf(14))
                .foregroundColor(C.subLabel)
        }
        .padding(.leading, L.ctPadL)
        .padding(.trailing, 16)
    }

    private func close() {
        guard offset != 0 else { return }
        withAnimation(swipeAnimation) { offset = 0 }
    }
}

struct AddFriendView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var realtime = Realtime.shared

    @State private var keyword = ""
    @State private var results: [User] = []
    @State private var searching = false
    @State private var searched = false
    @State private var errorText: String?
    @State private var target: User?
    @State private var sentTo: Set<String> = []
    @State private var showScan = false

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("添加朋友"), back: { dismiss() })

            ScrollView {
                VStack(spacing: 0) {
                    searchRow
                        .padding(L.searchPad)

                    if let errorText = errorText {
                        Text(errorText)
                            .font(pf(14))
                            .foregroundColor(C.subLabel)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    }

                    if searching {
                        HStack { Spacer(); ProgressView(); Spacer() }
                            .frame(height: 76).background(C.cardBg)
                    } else if searched && results.isEmpty {
                        Text(Tr("未找到相关用户"))
                            .font(pf(15))
                            .foregroundColor(C.subLabel)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
                            .background(C.cardBg)
                    }

                    if !results.isEmpty {
                        Text(Tr("搜索结果"))
                            .font(pf(13)).foregroundColor(C.subLabel)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 16)
                            .frame(height: 30)
                            .background(C.pageBg)
                        ForEach(results) { u in
                            VStack(spacing: 0) {
                                HairLine(inset: 72)
                                resultRow(u)
                            }
                            .background(C.cardBg)
                        }
                    }

                    VStack(spacing: 0) {
                        HairLine(inset: 56)
                        otherRow(icon: "qrcode.viewfinder", title: Tr("扫一扫")) { showScan = true }
                        HairLine(inset: 56)
                        NavigationLink(value: "myQR") {
                            otherRowLabel(icon: "qrcode", title: Tr("我的二维码"))
                        }
                        .buttonStyle(MenuPressStyle())
                    }
                    .background(C.cardBg)
                    .padding(.top, 24)
                }
                .padding(.bottom, 30)
            }
        }
        .background(C.pageBg.ignoresSafeArea(edges: .bottom))
        .background(C.pageBg.ignoresSafeArea(edges: .top))
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .fullScreenCover(isPresented: $showScan) {
            ScannerView { text in handleScanned(text, app: app) }
        }
        .sheet(item: $target) { u in
            FriendApplySheet(user: u) {
                sentTo.insert(u.id)
                Task { await app.loadContacts() }
            }
            .environmentObject(app)
        }
        .onChange(of: realtime.event) { ev in
            if ev.type == "friend" && !results.isEmpty { search() }
        }
    }

    private var searchRow: some View {
        HStack(spacing: 8) {
            SVGIcon(markup: I.searchSmall, size: 16, color: C.searchIcon)
            TextField(Tr("星言号/手机号"), text: $keyword)
                .font(pf(16))
                .foregroundColor(C.label)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .submitLabel(.search)
                .onSubmit { search() }
            if !keyword.isEmpty {
                Button {
                    keyword = ""
                    results = []
                    searched = false
                    errorText = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(C.searchIcon)
                }
                .buttonStyle(.plain)
            }
            Button { search() } label: {
                Text(searching ? Tr("搜索中…") : Tr("搜索"))
                    .font(pf(15, .medium))
                    .foregroundColor(keyword.isEmpty ? C.subLabel : .white)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(keyword.isEmpty ? Color.clear : C.green))
            }
            .buttonStyle(.plain)
            .disabled(keyword.isEmpty || searching)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(C.searchBg))
    }

    private func resultRow(_ u: User) -> some View {
        HStack(spacing: L.ctGap) {
            Avatar(path: u.avatarPath, size: 52, radius: 7)
            VStack(alignment: .leading, spacing: 4) {
                Text(u.name).font(pf(17)).foregroundColor(C.label).lineLimit(1)
                if let un = u.username, !un.isEmpty {
                    Text(Tr("星言号") + "：" + un)
                        .font(pf(13)).foregroundColor(C.subLabel).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            resultAction(u)
        }
        .padding(.horizontal, 16)
        .frame(height: 76)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func resultAction(_ u: User) -> some View {
        let rel = u.relation ?? "none"
        if sentTo.contains(u.id) || rel == "requested" {
            Text(Tr("等待验证")).font(pf(14)).foregroundColor(C.subLabel)
        } else if rel == "friend" || rel == "self" {
            Text(Tr("已添加")).font(pf(14)).foregroundColor(C.subLabel)
        } else if rel == "incoming" {
            Button { accept(u) } label: {
                greenChip(Tr("接受"))
            }
            .buttonStyle(MenuPressStyle())
        } else {
            Button { openApply(u) } label: {
                greenChip(Tr("添加到通讯录"))
            }
            .buttonStyle(MenuPressStyle())
        }
    }

    private func greenChip(_ t: String) -> some View {
        Text(t)
            .font(pf(14, .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(C.green))
    }

    private func otherRow(icon: String, title: String, tap: @escaping () -> Void) -> some View {
        Button(action: tap) { otherRowLabel(icon: icon, title: title) }
            .buttonStyle(MenuPressStyle())
    }

    private func otherRowLabel(icon: String, title: String) -> some View {
        HStack(spacing: L.ctGap) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(hex: 0x4C93DD))
                Image(systemName: icon).font(.system(size: 17)).foregroundColor(.white)
            }
            .frame(width: L.ctIcon, height: L.ctIcon)
            Text(title).font(pf(L.ctNameSize)).foregroundColor(C.label)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 13)).foregroundColor(C.subLabel)
        }
        .padding(.leading, L.ctPadL)
        .padding(.trailing, 16)
        .frame(height: L.ctRowH)
        .background(C.cardBg)
        .contentShape(Rectangle())
    }

    private func search() {
        let q = keyword.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        searching = true
        errorText = nil
        Task {
            do {
                let list = try await API.shared.searchUsers(q)
                results = list
                searched = true
            } catch {
                results = []
                searched = true
                errorText = (error as? APIError)?.errorDescription ?? Tr("未找到相关用户")
            }
            searching = false
        }
    }

    private func openApply(_ u: User) {
        target = u
    }

    private func accept(_ u: User) {
        Task {

            let res = await API.shared.respondFriend(userId: u.id, accept: true)
            guard res.ok else {
                app.show(Tr("到「通讯录 → 新的朋友」里同意"))
                return
            }
            UINotification.lightTap()
            if let n = res.pending { app.friendRequests = n }
            app.show(Tr("已添加到通讯录"))
            await app.loadContacts()
            await app.loadChats()
            if let chat = res.chat {
                app.ensureChatVisible(chat)
                app.openChat = chat
            } else {
                app.wantChatsTab = true
            }
            dismiss()
        }
    }
}

struct FriendApplySheet: View {
    let user: User
    var onSent: () -> Void = {}

    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var note = ""
    @State private var sending = false

    private var trimmed: String { note.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("发送添加朋友申请"), back: { dismiss() }) {
                Button { send() } label: {
                    Text(sending ? Tr("发送中…") : Tr("发送"))
                        .font(pf(17))
                        .foregroundColor(trimmed.isEmpty ? C.subLabel : C.green)
                        .frame(height: L.navH)
                        .padding(.trailing, 16)
                }
                .buttonStyle(.plain)
                .disabled(sending || trimmed.isEmpty)
            }

            VStack(spacing: 0) {
                HStack(spacing: L.ctGap) {
                    Avatar(path: user.avatarPath, size: 52, radius: 7)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.name).font(pf(17)).foregroundColor(C.label)
                        if let un = user.username, !un.isEmpty {
                            Text(Tr("星言号") + "：" + un).font(pf(13)).foregroundColor(C.subLabel)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .frame(height: 76)
                .background(C.cardBg)

                HStack(spacing: 12) {
                    Text(Tr("验证消息")).font(pf(15)).foregroundColor(C.subLabel)
                    TextField(Tr("验证消息"), text: $note)
                        .font(pf(16))
                        .foregroundColor(C.label)
                    if !note.isEmpty {
                        Button { note = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15)).foregroundColor(C.searchIcon)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(C.cardBg)
                .padding(.top, 12)
            }
            Spacer()
        }
        .background(C.pageBg.ignoresSafeArea(edges: .bottom))
        .background(C.pageBg.ignoresSafeArea(edges: .top))
        .onAppear {
            if note.isEmpty { note = defaultNote() }
        }
    }

    private func defaultNote() -> String {
        let me = (app.me?.name ?? "").trimmingCharacters(in: .whitespaces)
        let u = (app.me?.username ?? "").trimmingCharacters(in: .whitespaces)
        let who = me.isEmpty ? u : me
        return who.isEmpty ? Tr("我是") : Tr("我是") + who
    }

    private func send() {
        sending = true
        Task {
            do {
                let result: (accepted: Bool, friend: User?, chat: Chat?)
                if let un = user.username, !un.isEmpty {
                    result = try await API.shared.addFriend(username: un, note: trimmed)
                } else {
                    result = try await API.shared.addFriend(userId: user.id, note: trimmed)
                }
                if result.accepted {
                    app.applyFriendAccepted(result.friend ?? user)
                    await app.loadChats()
                    app.show(Tr("你们已经是好友了"))
                    if let chat = result.chat {
                        app.ensureChatVisible(chat)
                        app.openChat = chat
                    } else {
                        app.wantChatsTab = true
                    }
                    dismiss()
                } else {
                    app.noteFriendRequestSent(user, note: trimmed)
                    app.show(Tr("好友申请已发出"))
                }
                onSent()
                dismiss()
            } catch {
                app.show((error as? APIError)?.errorDescription ?? Tr("发送失败"))
            }
            sending = false
        }
    }
}

struct FriendRemarkSheet: View {
    let user: User
    var meta: API.FriendMeta?
    var onSaved: () async -> Void

    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var remark = ""
    @State private var tags = ""
    @State private var saving = false

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("设置备注和标签"), back: { dismiss() }) {
                Button { save() } label: {
                    Text(saving ? Tr("保存中…") : Tr("完成"))
                        .font(pf(17))
                        .foregroundColor(C.green)
                        .frame(height: L.navH)
                        .padding(.trailing, 16)
                }
                .buttonStyle(.plain)
                .disabled(saving)
            }

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text(Tr("备注名")).font(pf(16)).foregroundColor(C.label)
                        .frame(width: 76, alignment: .leading)
                    TextField(Tr("填写备注名"), text: $remark)
                        .font(pf(16)).foregroundColor(C.label)
                    if !remark.isEmpty {
                        Button { remark = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15)).foregroundColor(C.searchIcon)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(C.cardBg)

                HairLine(inset: 16)
                HStack(spacing: 12) {
                    Text(Tr("标签")).font(pf(16)).foregroundColor(C.label)
                        .frame(width: 76, alignment: .leading)
                    TextField(Tr("多个标签用顿号隔开"), text: $tags)
                        .font(pf(16)).foregroundColor(C.label)
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(C.cardBg)
            }
            .padding(.top, 12)

            Text(Tr("备注名只你自己看得见：设了以后通讯录和会话列表都显示备注。"))
                .font(pf(12.5))
                .foregroundColor(C.subLabel)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.top, 12)
            Spacer()
        }
        .background(C.pageBg.ignoresSafeArea(edges: .bottom))
        .background(C.pageBg.ignoresSafeArea(edges: .top))
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .onAppear {
            remark = meta?.remark ?? ""
            tags = (meta?.tags ?? []).joined(separator: "、")
        }
    }

    private func save() {
        saving = true
        let list = tags.split(whereSeparator: { "、,，;； ".contains($0) })
            .map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        Task {
            let cleanRemark = remark.trimmingCharacters(in: .whitespaces)
            let saved = await API.shared.setFriendMeta(userId: user.id,
                                                       remark: cleanRemark,
                                                       tags: list)
            guard saved else {
                saving = false
                app.show(Tr("保存失败"))
                return
            }
            let fallback = user.realNickname?.trimmingCharacters(in: .whitespacesAndNewlines)
            let realName = (fallback?.isEmpty == false) ? fallback! : user.name
            app.applyFriendRemarkLocally(userId: user.id,
                                         displayName: cleanRemark.isEmpty ? realName : cleanRemark,
                                         remark: cleanRemark)
            await app.loadContacts()
            await app.loadChats()
            await onSaved()
            saving = false
            dismiss()
            app.show(Tr("已保存"))
        }
    }
}

struct FriendPermSheet: View {
    let user: User
    var meta: API.FriendMeta?
    var onSaved: () async -> Void

    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var noMoments = false
    @State private var hideMine = false
    @State private var blocked = false

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("朋友权限"), back: { dismiss() })

            VStack(spacing: 0) {
                toggleRow(Tr("聊天"), true, locked: true)
                HairLine(inset: 16)
                toggleRow(Tr("不看他的朋友圈"), noMoments) { noMoments = $0; save() }
                HairLine(inset: 16)
                toggleRow(Tr("不让他看我的朋友圈"), hideMine) { hideMine = $0; save() }
                HairLine(inset: 16)
                toggleRow(Tr("加入黑名单"), blocked) { blocked = $0; save() }
            }
            .padding(.top, 12)
            .background(C.cardBg)

            Text(Tr("拉黑以后他发不了消息给你，也看不到你的朋友圈；聊天里你会看到「消息已发出，但被对方拒收了」。"))
                .font(pf(12.5))
                .foregroundColor(C.subLabel)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.top, 12)
            Spacer()
        }
        .background(C.pageBg.ignoresSafeArea(edges: .bottom))
        .background(C.pageBg.ignoresSafeArea(edges: .top))
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .onAppear {
            noMoments = meta?.noMoments == true
            hideMine = meta?.hideMyMoments == true
            blocked = meta?.block == true
        }
    }

    private func toggleRow(_ title: String, _ on: Bool, locked: Bool = false,
                           set: @escaping (Bool) -> Void = { _ in }) -> some View {
        HStack(spacing: 10) {
            Text(title).font(pf(16)).foregroundColor(C.label)
            Spacer(minLength: 8)
            if locked {
                Text(Tr("已开启")).font(pf(14)).foregroundColor(C.subLabel)
            } else {
                Toggle("", isOn: Binding(get: { on }, set: { set($0) }))
                    .labelsHidden()
                    .tint(C.green)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    private func save() {
        let oldNoMoments = noMoments
        let oldHideMine = hideMine
        let oldBlocked = blocked
        Task {
            let saved = await API.shared.setFriendMeta(userId: user.id, block: blocked,
                                                       noMoments: noMoments, hideMyMoments: hideMine)
            guard saved else {
                noMoments = oldNoMoments
                hideMine = oldHideMine
                blocked = oldBlocked
                app.show(Tr("没保存上，再试一次"))
                return
            }
            await onSaved()
            app.show(Tr("已保存"))
        }
    }
}

struct GroupCreateView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    var onCreated: (Chat) -> Void

    @State private var name = ""
    @State private var picked: Set<String> = []
    @State private var busy = false

    @State private var showFace = false

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("发起群聊"), back: { dismiss() }) {
                Button {
                    create()
                } label: {
                    Text(busy ? "创建中…" : "完成")
                        .font(pf(17))
                        .foregroundColor(picked.isEmpty ? C.subLabel : C.green)
                        .frame(height: L.navH)
                        .padding(.trailing, 16)
                }
                .buttonStyle(.plain)
            }

            Button { showFace = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.3.sequence.fill")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(C.green)
                        .frame(width: 26)
                    Text(Tr("面对面建群")).font(pf(16)).foregroundColor(C.label)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(C.subLabel)
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(C.cardBg)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 8)

            HStack(spacing: 8) {
                TextField("群名称", text: $name)
                    .font(pf(16))
                    .foregroundColor(C.label)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(C.searchBg)
            .padding(12)

            List {
                ForEach(app.contacts) { user in
                    Button {
                        if picked.contains(user.id) { picked.remove(user.id) }
                        else { picked.insert(user.id) }
                    } label: {
                        HStack(spacing: 12) {
                            Avatar(path: user.avatarPath, size: 40, radius: 6)
                            Text(user.name).font(pf(17)).foregroundColor(C.label)
                            Spacer()
                            Image(systemName: picked.contains(user.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(picked.contains(user.id) ? C.green : C.subLabel)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 56)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(C.cardBg)
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 0)
            .scrollContentBackground(.hidden)
            .background(C.cardBg)
        }
        .background(C.pageBg.ignoresSafeArea(edges: .bottom))
        .background(C.pageBg.ignoresSafeArea(edges: .top))
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()

        .sheet(isPresented: $showFace) {
            FaceGroupView { chat in onCreated(chat) }
                .environmentObject(app)
        }
    }

    private func create() {
        let groupName = name.trimmingCharacters(in: .whitespaces)
        if groupName.isEmpty { app.show(Tr("先填个群名称")); return }
        if picked.isEmpty { app.show(Tr("至少选一个好友")); return }
        busy = true
        Task {
            do {
                if let chat = try await API.shared.createGroup(name: groupName, memberIds: Array(picked)) {
                    await app.loadChats()
                    onCreated(chat)
                    dismiss()
                    app.show(Tr("群建好了"))
                }
            } catch {
                app.show((error as? APIError)?.errorDescription ?? "创建失败")
            }
            busy = false
        }
    }
}

struct FaceGroupView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    var onJoined: (Chat) -> Void

    @State private var digits = ""
    @State private var busy = false
    @State private var tip = ""

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("面对面建群"), back: { dismiss() }) { EmptyView() }

            VStack(spacing: 8) {
                Text(Tr("和身边的朋友输入同样的四个数字，进入同一个群聊"))
                    .font(pf(14))
                    .foregroundColor(C.subLabel)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                Text(Tr("数字 3 分钟内有效"))
                    .font(pf(12))
                    .foregroundColor(C.subLabel.opacity(0.75))

                HStack(spacing: 10) {
                    ForEach(0..<4, id: \.self) { i in
                        let on = digits.count > i
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(C.searchBg)
                            .frame(width: 46, height: 56)
                            .overlay(
                                Text(on ? String(Array(digits)[i]) : "")
                                    .font(pf(24, .semibold))
                                    .foregroundColor(C.label)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(digits.count == i ? C.green : Color.clear, lineWidth: 1.6)
                            )
                    }
                }
                .padding(.top, 10)

                if !tip.isEmpty {
                    Text(tip).font(pf(13)).foregroundColor(C.red)
                }

                Button { enter() } label: {
                    Text(busy ? Tr("进入中…") : Tr("进入群聊"))
                        .font(pf(17, .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(digits.count == 4 ? C.green : C.green.opacity(0.35)))
                }
                .buttonStyle(.plain)
                .disabled(digits.count != 4 || busy)
                .padding(.horizontal, 24)
                .padding(.top, 6)
            }
            .padding(.top, 24)

            Spacer(minLength: 10)
            keypad
            Color.clear.frame(height: L.safeBottom)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
    }

    private var keypad: some View {
        VStack(spacing: 1) {
            ForEach(0..<4, id: \.self) { r in
                HStack(spacing: 1) {
                    ForEach(0..<3, id: \.self) { c in
                        let i = r * 3 + c
                        let label = i == 9 ? "" : (i == 10 ? "0" : (i == 11 ? "⌫" : String(i + 1)))
                        key(label)
                    }
                }
            }
        }
        .background(C.hairline)
    }

    @ViewBuilder
    private func key(_ k: String) -> some View {
        if k.isEmpty {
            Color.clear.frame(maxWidth: .infinity).frame(height: 56).background(C.cardBg)
        } else {
            Button {
                if k == "⌫" {
                    if !digits.isEmpty { digits.removeLast() }
                    return
                }
                guard digits.count < 4 else { return }
                digits += k

                if digits.count == 4 { enter() }
            } label: {
                Text(k)
                    .font(pf(k == "⌫" ? 20 : 24))
                    .foregroundColor(C.label)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(C.cardBg)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func enter() {
        guard digits.count == 4, !busy else { return }
        busy = true
        tip = ""
        Task {
            do {
                guard let chat = try await API.shared.faceGroup(code: digits) else {
                    tip = Tr("没进去，再试一次")
                    digits = ""
                    busy = false
                    return
                }
                await app.loadChats()
                onJoined(chat)
                dismiss()
            } catch {
                tip = (error as? APIError)?.errorDescription ?? Tr("没进去，再试一次")
                digits = ""
            }
            busy = false
        }
    }
}

struct ServiceView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var realtime = Realtime.shared

    @ObservedObject private var eyes = EyesStore.shared

    @State private var cfg: ServiceConfig?
    @State private var bills: [BillItem] = []
    @State private var loading = true
    @State private var rechargeAmount = ""
    @State private var showRecharge = false
    @State private var showMore = false
    @State private var showWallet = false

    @State private var showServiceSupport = false
    @State private var showBillsPage = false

    @State private var showPayCode = false
    @State private var detailChat: Chat?
    @State private var detailInfo: TransferInfo?

    @State private var showAIPage = false

    struct BillItem: Identifiable {
        let id: String
        let title: String
        let amount: Double
        let date: String
        let status: String
        var chat: Chat? = nil
        var info: TransferInfo? = nil
    }

    private struct Cell: Identifiable {
        let id: String
        let label: String
        let color: Color
        let svg: String
        let action: String
    }

    private struct Group: Identifiable {
        let id: String
        let title: String
        let cells: [Cell]
        var style: ServiceGroupStyle? = nil
    }

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 0), count: 4)

    private var st: ServiceStyle { cfg?.style ?? ServiceStyle() }

    private var bt: ServiceBottom { cfg?.bottom ?? ServiceBottom() }

    private var groups: [Group] {
        var out: [Group] = []
        if let list = cfg?.groups, !list.isEmpty {
            out = list.compactMap { g in
                let cells = (g.items ?? []).filter { $0.enabled != false }.map { it in
                    Cell(id: it.id,
                         label: it.label,
                         color: Color(hexString: it.color ?? "#1180E0", fallback: 0x1180E0),
                         svg: SvcIcon.markup(it.icon, it.svg),
                         action: it.action ?? "soon")
                }
                return cells.isEmpty ? nil : Group(id: g.id, title: g.title, cells: cells, style: g.style)
            }
        } else {
            out = ServiceFallback.groups.map { pair in
                Group(id: pair.0, title: pair.0, cells: pair.1.map { row in
                    Cell(id: row.0, label: row.0,
                         color: Color(hexString: row.2, fallback: 0x1180E0),
                         svg: SvcIcon.markup(row.1, nil), action: "soon")
                })
            }
        }

        if let last = out.last {
            let ai = Cell(id: "ai.assistant",
                          label: Tr("AI 助手"),
                          color: C.green,
                          svg: #"<svg data-key="svc.ai" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3.4l1.9 5.1 5.1 1.9-5.1 1.9-1.9 5.1-1.9-5.1L5 10.4l5.1-1.9z"/><path d="M18.6 16.4l.8 2 2 .8-2 .8-.8 2-.8-2-2-.8 2-.8z"/></svg>"#,
                          action: "ai")
            out[out.count - 1] = Group(id: last.id, title: last.title,
                                       cells: last.cells + [ai], style: last.style)
        }
        return out
    }

    private var balanceText: String { "¥" + moneyFmt(app.me?.balance ?? 0) }

    private var walletSubText: String { (st.maskAmount ?? true) ? "¥****" : balanceText }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: cfg?.title ?? "服务", back: { dismiss() }) {
                Button { showMore = true } label: {
                    WeChatDots()
                        .frame(width: 44, height: L.navH)
                }
                .buttonStyle(.plain)
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if cfg?.card?.enabled != false { greenCard.padding(.top, 13) }
                    ForEach(Array(groups.enumerated()), id: \.element.id) { idx, g in
                        groupCard(g).padding(.top, topGap(idx))
                    }
                    billsCard.padding(.top, 8)
                    Color.clear.frame(height: 24)
                }
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea(edges: .top))
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .navigationDestination(isPresented: $showWallet) { WalletView() }
        .sheet(isPresented: $showServiceSupport) { SupportView().environmentObject(app) }
        .navigationDestination(isPresented: $showBillsPage) { BillsView() }
        .navigationDestination(isPresented: $showPayCode) { PayCodePage() }

        .fullScreenCover(isPresented: $showAIPage) {
            AIWorkspaceView().environmentObject(app)
        }
        .confirmationDialog(Tr("服务"), isPresented: $showMore, titleVisibility: .hidden) {
            Button(Tr(bt.moreRefresh ?? "刷新账单")) { Task { await loadBills() } }
            Button(Tr(bt.moreRecharge ?? "充值")) { rechargeAmount = ""; showRecharge = true }
            Button(Tr(bt.moreCancel ?? "取消"), role: .cancel) { }
        }
        .sheet(isPresented: Binding(
            get: { detailInfo != nil },
            set: { if !$0 { detailInfo = nil; detailChat = nil } }
        )) {
            if let c = detailChat, let i = detailInfo {
                BillDetailView(chat: c, info: i)
            }
        }
        .alert("充值", isPresented: $showRecharge) {
            TextField("金额", text: $rechargeAmount).keyboardType(.decimalPad)
            Button(Tr("充值")) { doRecharge() }
            Button(Tr("取消"), role: .cancel) { }
        }
        .task {
            await loadConfig()
            await loadBills()

            if !eyes.loaded { await eyes.refresh() }
        }

        .onChange(of: realtime.event) { ev in
            if ev.type == "transfer" || ev.type == "balance" { Task { await loadBills() } }
            if ev.type == "ui" { Task { await loadConfig() } }
        }
    }

    private var greenCard: some View {
        let c = cfg?.card

        let bg = Color(hexString: c?.bg ?? "#E02F24", fallback: 0xE02F24)
        let s = st
        return ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(bg)

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(0.18), Color.clear, Color.black.opacity(0.07)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))

            if let img = s.cardImage, !img.isEmpty {
                RemoteImage(path: img)
                    .frame(maxWidth: .infinity)
                    .frame(height: s.cardHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            HStack(alignment: .top, spacing: 0) {
                halfView(c?.left, label: "收付款", icon: "svc.pay", action: "pay", sub: "")

                Rectangle().fill(Color.white.opacity(0.18))
                    .frame(width: 0.7, height: 46)
                    .padding(.top, 6)
                halfView(c?.right, label: "钱包", icon: "svc.wallet", action: "wallet", sub: walletSubText)
            }
            .padding(.horizontal, 25)
            .padding(.top, 33)
        }
        .frame(height: s.cardHeight)
        .padding(.horizontal, 8)
        .shadow(color: Color.black.opacity(0.12), radius: 12, y: 6)
    }

    private func halfView(_ h: ServiceHalf?, label fallbackLabel: String,
                          icon fallbackIcon: String, action fallbackAction: String, sub fallbackSub: String) -> some View {
        let rawLabel = h?.label ?? ""
        let label = rawLabel.isEmpty ? fallbackLabel : rawLabel
        let rawSub = h?.sub ?? ""
        let sub = rawSub.isEmpty ? fallbackSub : rawSub
        let s = st
        return Button {
            run(h?.action ?? fallbackAction, label)
        } label: {
            VStack(spacing: 0) {
                SVGIcon(markup: SvcIcon.markup(h?.icon ?? fallbackIcon, h?.svg), size: s.icon, color: s.cardText)
                    .frame(width: s.icon, height: s.icon)
                Text(label)
                    .font(pf(s.cardNameSize))
                    .foregroundColor(s.cardText)
                    .padding(.top, 17)
                if !sub.isEmpty {
                    MoneyLabel(text: sub, size: s.cardSubSizeV, curSize: s.curFontSize,
                               color: s.cardText.opacity(s.cardSubOpacityV))
                        .padding(.top, 10)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func groupCard(_ g: Group) -> some View {
        let s = st

        return VStack(spacing: 0) {
            Text(g.title)
                .font(pf(s.titleSize))
                .foregroundColor(s.titleColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 16.7)
                .frame(height: s.titleHeight)

            LazyVGrid(columns: cols, spacing: 0) {
                ForEach(g.cells) { c in
                    Button {
                        run(c.action, c.label)
                    } label: {
                        VStack(spacing: 0) {

                            ZStack {
                                RoundedRectangle(cornerRadius: (s.icon + 14) * 0.29, style: .continuous)
                                    .fill(LinearGradient(colors: [c.color.opacity(0.18), c.color.opacity(0.07)],
                                                         startPoint: .topLeading,
                                                         endPoint: .bottomTrailing))
                                    .frame(width: s.icon + 14, height: s.icon + 14)
                                SVGIcon(markup: c.svg, size: s.icon, color: c.color)
                                    .frame(width: s.icon, height: s.icon)
                            }
                            Text(c.label)
                                .font(pf(s.textSize))
                                .foregroundColor(s.gridText)
                                .lineLimit(1)
                                .padding(.top, 10)
                        }
                        .padding(.top, 14)
                        .frame(maxWidth: .infinity)
                        .frame(height: s.cellHeight, alignment: .top)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 20)
        }
        .background { CardGlassBox(radius: 16) }
        .padding(.horizontal, 8)
        .shadow(color: Color.black.opacity(0.055), radius: 9, y: 3)
    }

    private func topGap(_ idx: Int) -> CGFloat {
        guard idx > 0 else { return 8 }
        let prev = groups[idx - 1].style?.gapBottom ?? 8
        let cur = groups[idx].style?.gapTop ?? 0
        return CGFloat(max(8, prev + cur))
    }

    private var billsCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(Tr(bt.billTitle ?? "账单"))
                    .font(pf(14))
                    .foregroundColor(Color.dyn(0x7A7A7A, 0x8A8A8A))
                Spacer(minLength: 0)
                Text(balanceText)
                    .font(pf(13))
                    .foregroundColor(C.subLabel)

                if UIConfig.num("billsShow", 1) > 0 {
                    Button { showBillsPage = true } label: {
                        Text(Tr(bt.billAll ?? "全部账单"))
                            .font(pf(13))
                            .foregroundColor(C.green)
                            .padding(.leading, 14)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    rechargeAmount = ""
                    showRecharge = true
                } label: {
                    Text(Tr(bt.billRecharge ?? "充值"))
                        .font(pf(13))
                        .foregroundColor(C.green)
                        .padding(.leading, 14)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16.7)
            .frame(height: 48)

            if loading {
                ProgressView().padding(.vertical, 26)
            } else if bills.isEmpty {
                Text(Tr(bt.billEmpty ?? "还没有账单项"))
                    .font(pf(14))
                    .foregroundColor(C.subLabel)
                    .padding(.vertical, 26)
            } else {
                ForEach(bills) { bill in
                    Button {
                        if let chat = bill.chat, let info = bill.info {
                            detailChat = chat
                            detailInfo = info
                        }
                    } label: {
                        VStack(spacing: 0) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(bill.title).font(pf(16)).foregroundColor(C.label)
                                    Text(bill.date).font(pf(12.5)).foregroundColor(C.subLabel)
                                }
                                Spacer(minLength: 0)
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text("¥\(moneyFmt(bill.amount))")
                                        .font(pfMoney(16))
                                        .foregroundColor(C.label)
                                    Text(bill.status).font(pf(12.5)).foregroundColor(C.subLabel)
                                }
                                Chevron(size: 9, line: 1.6)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 66)
                            HairLine(inset: 16)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background { CardGlassBox(radius: 16) }
        .padding(.horizontal, 8)
        .padding(.bottom, 20)
    }

    private func run(_ action: String, _ label: String) {
        switch action {
        case "wallet":
            showWallet = true
        case "pay":
            showPayCode = true
        case "ai":
            openAI()
        default:

            if label.contains("客服") { showServiceSupport = true }
            else if label.contains("经营") { showWallet = true }
            else { app.show(soonTip(label)) }
        }
    }

    private func soonTip(_ label: String) -> String {
        Tr((bt.soonTip ?? "「{label}」还没接后端，先把页面做出来").replacingOccurrences(of: "{label}", with: label))
    }

    private func loadConfig() async {
        if let got = try? await API.shared.serviceConfig() {
            cfg = got
        }
    }

    private func openAI() {
        showAIPage = true
    }

    private func doRecharge() {
        guard let amount = Double(rechargeAmount), amount > 0 else {
            app.show(Tr("金额不对"))
            return
        }
        Task {
            if let balance = try? await API.shared.recharge(amount) {
                app.me = try? await API.shared.me()
                app.show("充值成功，余额 ¥\(moneyFmt(balance))")
            } else {
                app.show(Tr("充值失败"))
            }
        }
    }

    private func loadBills() async {
        loading = true
        var found: [BillItem] = []
        for chat in app.chats.prefix(14) {
            guard let result = try? await API.shared.messages(chatId: chat.id, limit: 40) else { continue }
            for m in result.messages where m.kindName == "transfer" {
                guard let data = m.body.data(using: .utf8),
                      let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                let mine = (o["fromId"] as? String) == app.me?.id
                let amount = (o["amount"] as? Double) ?? 0
                let status = (o["status"] as? String) ?? "pending"
                let state = status == "received" ? "已收款" :
                            (status == "refunded" ? "已退回" : "待收款")
                found.append(BillItem(id: (o["id"] as? String) ?? m.id,
                                      title: mine ? "转账给 \(chat.name)" : "\(chat.name) 转账给你",
                                      amount: amount,
                                      date: TimeFmt.bill(o["createdAt"] as? String ?? m.createdAt),
                                      status: state,
                                      chat: chat,
                                      info: TransferInfo(json: m.body)))
            }
        }
        bills = found.sorted { $0.date > $1.date }
        loading = false
    }
}
