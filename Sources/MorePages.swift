import SwiftUI

struct GroupListView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    var onOpenChat: (Chat) -> Void

    private var groups: [Chat] {
        app.chats.filter { $0.type == "group" }
            .sorted { ($0.updatedAt ?? "") > ($1.updatedAt ?? "") }
    }

    private var memberConnections: Int {
        groups.reduce(0) { $0 + ($1.memberCount ?? 0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("群聊"), back: { dismiss() })
            ScrollView {
                LazyVStack(spacing: 10) {
                    StarOrbitHero(
                        kicker: "群星轨道",
                        title: Tr("群聊"),
                        subtitle: Tr("每个群，都是同一条轨道上的共同空间"),
                        symbol: "person.3.fill",
                        accent: OrbitTheme.jade,
                        metrics: [
                            StarOrbitMetric(value: "\(groups.count)", label: Tr("个群聊")),
                            StarOrbitMetric(value: "\(memberConnections)", label: Tr("位成员连接"))
                        ]
                    )
                    .padding(.horizontal, 12)

                    if groups.isEmpty {
                        emptyState
                    } else {
                        OrbitSectionLabel(text: Tr("我的群聊"), count: groups.count)
                            .padding(.horizontal, 17)
                            .padding(.top, 2)

                        ForEach(groups) { chat in
                            Button { onOpenChat(chat) } label: {
                                groupCard(chat)
                            }
                            .buttonStyle(MenuPressStyle())
                            .padding(.horizontal, 12)
                        }
                    }
                    Spacer().frame(height: 30)
                }
                .padding(.top, 10)
            }
            .refreshable { await app.loadChats() }
        }
        .background(OrbitTheme.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .task { await app.loadChats() }
    }

    private func groupCard(_ chat: Chat) -> some View {
        StarOrbitCard {
            HStack(spacing: 13) {
                if (chat.avatar ?? "").isEmpty {
                    GroupAvatarMosaic(
                        chatId: chat.id,
                        memberIds: chat.memberIds ?? [],
                        size: 46,
                        radius: 13
                    )
                } else {
                    Avatar(path: chat.avatar ?? "", size: 46, radius: 13, group: true)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(chat.name)
                        .font(.system(size: 16.5, weight: .medium))
                        .foregroundStyle(OrbitTheme.ink)
                        .lineLimit(1)
                    Text("\(chat.memberCount ?? 0) " + Tr("位成员"))
                        .font(.system(size: 12.5))
                        .foregroundStyle(OrbitTheme.secondary)
                }
                Spacer(minLength: 8)
                StarOrbitTrailingPill(text: "\(chat.memberCount ?? 0)", accent: OrbitTheme.jade)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(OrbitTheme.tertiary)
            }
            .padding(.horizontal, 15)
            .frame(height: 72)
            .contentShape(Rectangle())
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            StarOrbitIconBadge(symbol: "person.3.fill", accent: OrbitTheme.jade, size: 54)
            Text(Tr("还没有群聊"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(OrbitTheme.ink)
            Text(Tr("在「＋ → 发起群聊」里建立第一条群轨道"))
                .font(.system(size: 13))
                .foregroundStyle(OrbitTheme.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
        .background(OrbitTheme.cardBackground())
        .clipShape(OrbitTheme.card)
        .padding(.horizontal, 12)
    }
}

private struct ChatSearchCategoryItem {
    let key: String
    let title: String
    let symbol: String
    let tint: [Color]
}

enum ChatSearchJump {
    static let didRequest = Notification.Name("CHRISChatSearchJump")

    static func request(chatId: String, messageId: String, seq: Int?) {
        var info: [String: Any] = [
            "chatId": chatId,
            "messageId": messageId
        ]
        if let seq, seq > 0 { info["seq"] = seq }
        NotificationCenter.default.post(name: didRequest, object: nil, userInfo: info)
    }

    static func destination(from note: Notification) -> (chatId: String, messageId: String, seq: Int?)? {
        guard let info = note.userInfo,
              let chatId = info["chatId"] as? String,
              let messageId = info["messageId"] as? String,
              !chatId.isEmpty, !messageId.isEmpty else { return nil }
        return (chatId, messageId, info["seq"] as? Int)
    }
}

struct ChatSearchView: View {
    let chat: Chat
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppState

    @State private var keyword = ""
    @State private var hits: [FoundMessage] = []
    @State private var busy = false
    @State private var done = false
    @State private var total = 0
    @State private var hasMore = false

    @State private var typingTask: Task<Void, Never>? = nil

    @State private var token = 0

    @State private var filter = ""
    @State private var members: [User] = []
    @State private var memberId = ""
    @State private var memberName = ""
    @State private var showMembers = false
    @State private var showDate = false
    @State private var dateOpenToken = 0
    @State private var selectedDate = Date()
    @State private var dateFrom: Date?
    @State private var dateTo: Date?
    @State private var dateLabel = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                NavBar(title: Tr("查找聊天记录"), back: { dismiss() })

                searchBar
                if trimmed.isEmpty && filter.isEmpty && memberId.isEmpty && dateFrom == nil {
                    categoryGrid
                    Spacer(minLength: 0)
                } else {
                    resultArea
                }
            }
            if showDate {
                datePicker
                    .transition(.opacity)
                    .zIndex(20)
            }
        }
        .background(C.pageBg.ignoresSafeArea())
        .animation(.easeOut(duration: 0.16), value: showDate)
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .onAppear {
            focused = true
            if chat.type == "group", members.isEmpty {
                Task {
                    if let r = try? await API.shared.chatMembers(chatId: chat.id) {
                        members = r.members
                    }
                }
            }
        }
        .onDisappear { typingTask?.cancel() }
        .sheet(isPresented: $showMembers) {
            memberPicker
        }
    }

    private var trimmed: String { keyword.trimmingCharacters(in: .whitespaces) }

    private var searchBar: some View {
        HStack(spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundColor(C.searchIcon)
                TextField(Tr("搜索聊天记录"), text: $keyword)
                    .font(pf(15))
                    .focused($focused)
                    .submitLabel(.search)
                    .onSubmit { search() }
                    .onChange(of: keyword) { _ in typingChanged() }
                if !keyword.isEmpty {
                    Button { keyword = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundColor(C.searchIcon2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(C.searchBg))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(C.hairline, lineWidth: 0.6))

            Button { dismiss() } label: {
                Text(Tr("取消"))
                    .font(pf(15, .medium))
                    .foregroundColor(C.label)
                    .frame(height: 36)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    private let categories: [ChatSearchCategoryItem] = [
        ChatSearchCategoryItem(key: "member", title: "群成员", symbol: "person.3.fill", tint: PanelTint.blue),
        ChatSearchCategoryItem(key: "date", title: "日期", symbol: "calendar", tint: PanelTint.orange),
        ChatSearchCategoryItem(key: "image", title: "图片与视频", symbol: "photo.on.rectangle", tint: PanelTint.teal),
        ChatSearchCategoryItem(key: "file", title: "文件", symbol: "folder.fill", tint: PanelTint.orange),
        ChatSearchCategoryItem(key: "link", title: "链接", symbol: "link", tint: PanelTint.blue),
        ChatSearchCategoryItem(key: "music", title: "音乐与音频", symbol: "music.note", tint: PanelTint.purple),
        ChatSearchCategoryItem(key: "trade", title: "交易", symbol: "wallet.pass.fill", tint: PanelTint.green),
        ChatSearchCategoryItem(key: "miniapp", title: "小程序", symbol: "square.grid.2x2.fill", tint: PanelTint.teal),
        ChatSearchCategoryItem(key: "channels", title: "视频号", symbol: "play.rectangle.fill", tint: PanelTint.red)
    ]

    private var visibleCategories: [ChatSearchCategoryItem] {
        chat.type == "group" ? categories : categories.filter { $0.key != "member" }
    }

    private func choose(_ c: ChatSearchCategoryItem) {
        memberId = ""
        memberName = ""
        dateFrom = nil
        dateTo = nil
        dateLabel = ""
        if c.key == "member" {
            showMembers = true
            return
        }
        if c.key == "date" {
            focused = false
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                            to: nil, from: nil, for: nil)
            selectedDate = Date()
            dateOpenToken += 1
            let token = dateOpenToken
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
                if token == dateOpenToken { showDate = true }
            }
            return
        }
        filter = c.key
        search()
    }

    private var selectedCategoryTitle: String {
        if filter == "member" { return memberName.isEmpty ? Tr("群成员") : memberName }
        if filter == "date" { return dateLabel.isEmpty ? Tr("日期") : dateLabel }
        if filter.isEmpty { return Tr("全部") }
        return Tr(categories.first(where: { $0.key == filter })?.title ?? "全部")
    }

    private var memberPicker: some View {
        NavigationStack {
            List(members) { u in
                Button {
                    memberId = u.id
                    memberName = u.name
                    filter = "member"
                    showMembers = false
                    search()
                } label: {
                    HStack(spacing: 12) {
                        Avatar(path: u.avatarPath, size: 42, radius: 8)
                        Text(u.name)
                            .font(pf(15))
                            .foregroundColor(C.label)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(C.subLabel)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .navigationTitle(Tr("选择群成员"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(Tr("取消")) { showMembers = false }
                }
            }
        }
    }

    private var datePicker: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
                .onTapGesture { showDate = false }
            VStack(spacing: 14) {
                HStack {
                    Text(Tr("按日期查找"))
                        .font(pf(17, .semibold))
                        .foregroundColor(C.label)
                    Spacer()
                    Button(Tr("取消")) { showDate = false }
                        .font(pf(15))
                        .foregroundColor(C.subLabel)
                }
                DatePicker("", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .padding(.horizontal, 10)
                Button { applyDateSearch() } label: {
                    Text(Tr("查找这一天"))
                        .font(pf(16, .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(LinearGradient(colors: PanelTint.green,
                                                 startPoint: .topLeading,
                                                 endPoint: .bottomTrailing)))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 18)
            }
            .padding(.top, 18)
            .padding(.bottom, 16)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(C.cardBg))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(C.hairline, lineWidth: 0.7))
            .padding(.horizontal, 24)
        }
    }

    private func applyDateSearch() {
        let day = selectedDate
        showDate = false
        // 先卸掉日期控件，再发起查询，避免同一布局事务内重排结果页。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            let cal = Calendar.current
            let start = cal.startOfDay(for: day)
            dateFrom = start
            dateTo = cal.date(byAdding: .day, value: 1, to: start)
            let f = DateFormatter()
            f.locale = Locale(identifier: "zh_CN")
            f.dateFormat = "yyyy年M月d日"
            dateLabel = f.string(from: day)
            filter = "date"
            search()
        }
    }

    private var categoryGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 3), spacing: 0) {
            ForEach(visibleCategories, id: \.key) { c in
                Button { choose(c) } label: {
                    VStack(spacing: 9) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(LinearGradient(colors: c.tint, startPoint: .topLeading,
                                                     endPoint: .bottomTrailing))
                                .frame(width: 48, height: 48)
                            Image(systemName: c.symbol)
                                .font(.system(size: 21, weight: .medium))
                                .foregroundColor(.white)
                        }
                        Text(Tr(c.title))
                            .font(pf(13))
                            .foregroundColor(C.label)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 92)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .background(C.cardBg)
    }

    private var rows: [FoundMessage] {
        hits
    }

    @ViewBuilder
    private var resultArea: some View {
        if busy && hits.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                Text(Tr("正在翻这个会话的全部历史…"))
                    .font(pf(13))
                    .foregroundColor(C.subLabel)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 56)
            Spacer(minLength: 0)
        } else if rows.isEmpty {

            if trimmed.isEmpty && filter.isEmpty && memberId.isEmpty && dateFrom == nil {
                Spacer(minLength: 0)
            } else {
                emptyState
            }
        } else {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    resultHeader
                    PanelCard {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { idx, m in
                            resultRow(m)
                            if idx < rows.count - 1 { PanelDivider() }
                        }
                    }
                    if hasMore {
                        Button { loadMore() } label: {
                            Text(busy ? Tr("正在加载…") : Tr("加载更多"))
                                .font(pf(13))
                                .foregroundColor(C.green)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .disabled(busy)
                    }
                    Spacer().frame(height: 30)
                }
                .padding(.horizontal, 14)
            }
        }
    }

    private var resultHeader: some View {
        HStack(spacing: 6) {
            Text(selectedCategoryTitle)
                .font(pf(12.5, .medium))
                .foregroundColor(C.green)
            Text("· \(total) 条")
                .font(pf(12.5, .medium))
                .foregroundColor(C.subLabel)
            Spacer(minLength: 0)
            if rows.count < total {
                Text(Tr("已显示 ") + "\(rows.count)")
                    .font(pf(11.5))
                    .foregroundColor(C.subLabel)
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private func resultRow(_ m: FoundMessage) -> some View {
        return Button {
            openMessage(m)
        } label: {
            HStack(alignment: .top, spacing: 11) {
                Avatar(path: avatarFor(m), size: 40, radius: 8)
                VStack(alignment: .leading, spacing: 6) {
                    highlighted(preview(m))
                        .font(pf(15))
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 6) {
                        Text((m.senderName?.isEmpty == false) ? m.senderName! : Tr("消息"))
                            .font(pf(12))
                            .foregroundColor(C.subLabel)
                            .lineLimit(1)
                        Text("·").font(pf(12)).foregroundColor(C.subLabel)
                        Text(TimeFmt.bubble(m.createdAt ?? ""))
                            .font(pf(12))
                            .foregroundColor(C.subLabel)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func openMessage(_ message: FoundMessage) {
        let chatId = chat.id
        let messageId = message.id
        let seq = message.seq
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            ChatSearchJump.request(chatId: chatId, messageId: messageId, seq: seq)
        }
    }

    private func avatarFor(_ m: FoundMessage) -> String {
        if let a = m.senderAvatar, !a.isEmpty { return a }
        if let id = m.senderId {
            if let u = members.first(where: { $0.id == id }) { return u.avatarPath }
            if let u = app.contacts.first(where: { $0.id == id }) { return u.avatarPath }
        }
        return ""
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color(hex: 0xEDF1F5), Color(hex: 0xDCE4EC)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 72, height: 72)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 27, weight: .light))
                    .foregroundColor(C.subLabel)
            }
            .shadow(color: Color.black.opacity(0.06), radius: 8, y: 3)

            Text(!filter.isEmpty
                 ? Tr("这一类还没有记录")
                 : (done ? Tr("没找到") + "「\(trimmed)」" + Tr("相关的聊天记录")
                         : Tr("输入关键字，或点上面对应的分类")))
                .font(pf(14))
                .foregroundColor(C.subLabel)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)

            if !done {
                Text(Tr("文字、图片、文件、红包…都在这份历史里，搜到什么都能对上"))
                    .font(pf(12))
                    .foregroundColor(C.subLabel.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 52)
    }

    private var hasSearchCondition: Bool {
        !trimmed.isEmpty || !filter.isEmpty || !memberId.isEmpty || dateFrom != nil
    }

    private var kindFilter: String {
        ["member", "date"].contains(filter) ? "" : filter
    }

    private func search() {
        typingTask?.cancel()
        guard hasSearchCondition else {
            hits = []
            total = 0
            hasMore = false
            done = false
            return
        }
        busy = true
        focused = false
        token += 1
        let mine = token
        Task {
            let r = await API.shared.chatHistorySearch(chatId: chat.id, query: trimmed,
                                                       filter: kindFilter,
                                                       memberId: memberId,
                                                       from: dateFrom, to: dateTo,
                                                       before: nil, limit: 100)
            guard mine == token else { return }
            hits = r.messages
            total = r.total
            hasMore = r.hasMore
            busy = false
            done = true
        }
    }

    private func loadMore() {
        guard hasMore, !busy, let before = hits.last?.seq else { return }
        busy = true
        token += 1
        let mine = token
        Task {
            let r = await API.shared.chatHistorySearch(chatId: chat.id, query: trimmed,
                                                       filter: kindFilter,
                                                       memberId: memberId,
                                                       from: dateFrom, to: dateTo,
                                                       before: before, limit: 100)
            guard mine == token else { return }
            let known = Set(hits.map(\.id))
            hits.append(contentsOf: r.messages.filter { !known.contains($0.id) })
            total = r.total
            hasMore = r.hasMore
            busy = false
        }
    }

    private func typingChanged() {
        typingTask?.cancel()
        let q = trimmed
        guard !q.isEmpty else {
            hits = []
            total = 0
            hasMore = false
            done = false
            busy = false
            return
        }
        filter = ""
        memberId = ""
        memberName = ""
        dateFrom = nil
        dateTo = nil
        dateLabel = ""
        typingTask = Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            if Task.isCancelled { return }
            busy = true
            token += 1
            let mine = token
            let r = await API.shared.chatHistorySearch(chatId: chat.id, query: q,
                                                       filter: "", memberId: "",
                                                       from: nil, to: nil, before: nil, limit: 100)
            guard mine == token else { return }
            hits = r.messages
            total = r.total
            hasMore = r.hasMore
            busy = false
            done = true
        }
    }

    private func preview(_ m: FoundMessage) -> String {
        let c = m.content ?? ""
        switch (m.kind ?? "text") {
        case "text":     return ClassicEmojiSet.expand(c)
        case "image", "images": return Tr("[图片]")
        case "video", "livephoto": return Tr("[视频]")
        case "voice", "audio": return Tr("[语音]")
        case "location": return Tr("[位置]")
        case "file":
            if let d = c.data(using: .utf8),
               let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let n = o["name"] as? String, !n.isEmpty {
                return Tr("[文件] ") + n
            }
            return Tr("[文件]")
        case "redpacket": return Tr("[红包]")
        case "transfer":  return Tr("[转账]")
        case "gift":      return Tr("[礼物]")
        case "call":      return Tr("[通话]")
        case "card":      return Tr("[名片]")
        case "sticker", "emoji": return Tr("[表情]")
        case "link", "oa":
            if let d = c.data(using: .utf8),
               let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let title = o["title"] as? String, !title.isEmpty {
                return Tr("[链接] ") + title
            }
            return Tr("[链接]")
        case "music":
            if let d = c.data(using: .utf8),
               let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let title = o["title"] as? String, !title.isEmpty {
                return Tr("[音乐] ") + title
            }
            return Tr("[音乐]")
        case "miniapp", "mini", "mall": return Tr("[小程序]")
        case "channels", "channel", "feed": return Tr("[视频号]")
        default:          return c.isEmpty ? Tr("[消息]") : ClassicEmojiSet.expand(c)
        }
    }

    private func highlighted(_ text: String) -> Text {
        let kw = trimmed
        guard !kw.isEmpty else { return Text(text) }
        var out = Text("")
        var rest = Substring(text)
        while let r = rest.range(of: kw, options: [.caseInsensitive]) {
            out = out + Text(String(rest[rest.startIndex..<r.lowerBound]))
            out = out + Text(String(rest[r])).foregroundColor(C.green).bold()
            rest = rest[r.upperBound...]
        }
        return out + Text(String(rest))
    }

    private static func look(for kind: String?) -> (symbol: String, colors: [Color]) {
        switch (kind ?? "text") {
        case "image":    return ("photo.fill", PanelTint.teal)
        case "video":    return ("video.fill", PanelTint.blue)
        case "voice", "audio": return ("mic.fill", PanelTint.purple)
        case "file":     return ("doc.fill", PanelTint.orange)
        case "location": return ("location.fill", PanelTint.green)
        case "redpacket": return ("gift.fill", PanelTint.red)
        case "transfer": return ("creditcard.fill", PanelTint.orange)
        case "call":     return ("phone.fill", PanelTint.blue)
        case "card":     return ("person.crop.square.fill", PanelTint.blue)
        case "gift":     return ("gift.fill", PanelTint.purple)
        case "sticker", "emoji": return ("face.smiling.fill", PanelTint.orange)
        default:         return ("text.bubble.fill", PanelTint.gray)
        }
    }
}

struct BankCardsView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var cards: [BankCard] = []
    @State private var loading = true
    @State private var showAdd = false
    @State private var bank = "招商银行"
    @State private var number = ""
    @State private var holder = ""
    @State private var busy = false

    @State private var bankList: [API.BankInfo] = []
    private var banks: [String] {
        let names = bankList.map { $0.name }
        return names.isEmpty
            ? ["工商银行", "建设银行", "农业银行", "中国银行", "招商银行", "交通银行", "邮储银行", "其他银行"]
            : names
    }

    private func bankColor(_ name: String) -> Color {
        if let c = bankList.first(where: { $0.name == name })?.color,
           case let hex = c.replacingOccurrences(of: "#", with: ""),
           hex.count == 6, let v = Int(hex, radix: 16) {
            return Color(hex: UInt32(v))
        }
        let table: [String: Int] = ["工商银行": 0xC8161D, "建设银行": 0x0B4DA2, "农业银行": 0x0E8B4A,
                                    "中国银行": 0xB01F24, "招商银行": 0xC7000B, "交通银行": 0x1B4E9B,
                                    "邮储银行": 0x0E7B40, "中信银行": 0xD0202F, "民生银行": 0x0E5EA8,
                                    "浦发银行": 0x0A4C8B, "兴业银行": 0x1F4C9C, "光大银行": 0x8B1A2B,
                                    "平安银行": 0xF36F21, "广发银行": 0xC8102E, "华夏银行": 0x0E5EA8,
                                    "微众银行": 0x0E9C6B, "网商银行": 0x1F7BE0]
        return Color(hex: UInt32(table[name] ?? 0x8A8A8E))
    }

    private func bankShort(_ name: String) -> String {
        if let s = bankList.first(where: { $0.name == name })?.short, !s.isEmpty { return s }
        return String(name.prefix(1))
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("银行卡"), back: { dismiss() }) {
                Button {
                    showAdd = true
                } label: {
                    Text(Tr("绑定"))
                        .font(pf(16, .medium))
                        .foregroundColor(C.green)
                        .frame(height: L.navH)
                        .padding(.trailing, 16)
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                VStack(spacing: 0) {
                    if loading {
                        ProgressView().padding(.top, 40)
                    } else if cards.isEmpty {
                        Text("还没有绑定银行卡\n点右上角「绑定」加一张")
                            .font(pf(13.5))
                            .foregroundColor(C.subLabel)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 50)
                    } else {
                        GroupCard {
                            ForEach(Array(cards.enumerated()), id: \.element.id) { idx, c in
                                HStack(spacing: 12) {
                                    Image(systemName: "creditcard.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(C.green)
                                        .frame(width: 34, height: 34)
                                        .background(RoundedRectangle(cornerRadius: 7).fill(C.searchBg))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(c.bank ?? "银行卡")
                                            .font(pf(16))
                                            .foregroundColor(C.label)
                                        Text(((c.type ?? "储蓄卡") + " · 尾号 \(c.tail ?? "****")") + ((c.holder ?? "").isEmpty ? "" : " · \(c.holder!)"))
                                            .font(pf(12.5))
                                            .foregroundColor(C.subLabel)
                                    }
                                    Spacer(minLength: 0)
                                    Button {
                                        unbind(c.id)
                                    } label: {
                                        Text(Tr("解绑"))
                                            .font(pf(13.5))
                                            .foregroundColor(C.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 16)
                                .frame(height: 66)
                                if idx < cards.count - 1 { HairLine(inset: 62) }
                            }
                        }
                        .padding(.top, 8)
                    }
                    Text(Tr("只保存银行、尾号和持卡人，完整卡号不会留在手机上。"))
                        .font(pf(12))
                        .foregroundColor(C.subLabel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        .padding(.top, 10)
                    Spacer().frame(height: 30)
                }
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .task { await reload() }
        .task { bankList = await API.shared.banks() }
        .sheet(isPresented: $showAdd) { addSheet }
    }

    private var addSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {

                    VStack(alignment: .leading, spacing: 8) {
                        Text(Tr("选择银行")).font(pf(15)).foregroundColor(C.label)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(banks, id: \.self) { name in
                                    let on = (bank == name)
                                    Button { bank = name } label: {
                                        HStack(spacing: 6) {
                                            Text(bankShort(name))
                                                .font(pf(13, .semibold))
                                                .foregroundColor(.white)
                                                .frame(width: 22, height: 22)
                                                .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                                                    .fill(bankColor(name)))
                                            Text(name).font(pf(14)).foregroundColor(on ? C.label : C.subLabel)
                                        }
                                        .padding(.horizontal, 10)
                                        .frame(height: 36)
                                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(on ? C.searchBg : C.cardBg))
                                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(on ? C.green : C.hairline, lineWidth: on ? 1.4 : 0.5))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 2)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    HairLine(color: C.navLine)
                    HairLine(color: C.navLine)
                    field("卡号") {
                        TextField("16~19 位卡号", text: $number)
                            .keyboardType(.numberPad)
                    }
                    HairLine(color: C.navLine)
                    field("持卡人") {
                        TextField("姓名", text: $holder)
                    }
                    Button {
                        add()
                    } label: {
                        Text(busy ? "绑定中…" : "确认绑定")
                            .font(pf(16, .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(C.green)
                            .cornerRadius(12)
                    }
                    .disabled(busy)
                    .padding(.horizontal, 20)
                    .padding(.top, 22)
                }
                .padding(.top, 10)
            }
            .background(Color(.systemBackground).ignoresSafeArea())
            .navigationTitle(Tr("绑定银行卡"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button(Tr("取消")) { showAdd = false } } }
        }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder _ c: () -> Content) -> some View {
        HStack(spacing: 10) {
            Text(title).font(pf(16)).foregroundColor(C.label)
            Spacer(minLength: 8)
            c()
        }
        .font(pf(15))
        .frame(height: 54)
        .padding(.horizontal, 14)
        .background(Color.dyn(0xFFFFFF, 0x1C1C1E))
    }

    private func reload() async {
        cards = await API.shared.bankCards()
        loading = false
    }

    private func add() {
        let n = number.trimmingCharacters(in: .whitespaces)
        let h = holder.trimmingCharacters(in: .whitespaces)
        if n.count < 16 { app.show(Tr("卡号要 16~19 位")); return }
        if h.isEmpty { app.show(Tr("请填持卡人姓名")); return }
        busy = true
        Task {
            if let err = await API.shared.addBankCard(bank: bank, number: n, holder: h) {
                app.show(err)
            } else {
                app.show(Tr("绑定成功"))
                showAdd = false
                number = ""
                holder = ""
                await reload()
            }
            busy = false
        }
    }

    private func unbind(_ id: String) {
        Task {
            if let err = await API.shared.deleteBankCard(id: id) {
                app.show(err)
            } else {
                app.show(Tr("已解绑"))
                await reload()
            }
        }
    }
}

struct AboutView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var checking = false
    @State private var latest = ""
    @State private var appName = "CHRIS 聊天"
    @ObservedObject private var push = PushCenter.shared

    @State private var pushServerReady = false

    private var pushText: String {
        if !push.authorized { return Tr("通知权限没开") }
        if push.token.isEmpty { return push.lastError.isEmpty ? Tr("登记中…") : push.lastError }
        if pushServerReady { return Tr("已开启") }
        return Tr("等服务器配置")
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("关于我们"), back: { dismiss() })
            ScrollView {
                VStack(spacing: 12) {

                    hero

                    GroupCard {

                        aboutRow("doc.text", Tr("用户协议")) { showTerms = true }
                        HairLine(inset: 54)
                        aboutRow("hand.raised", Tr("隐私政策"), sub: Tr("更新于 ") + privacyUpdated) { showPrivacyDoc = true }
                        HairLine(inset: 54)
                        aboutRow("list.bullet.rectangle", Tr("个人信息收集清单")) { showCollect = true }
                        HairLine(inset: 54)
                        aboutRow("checkmark.shield", Tr("权限使用说明")) { showPerm = true }
                        HairLine(inset: 54)
                        aboutRow("sparkles", Tr("功能介绍"), sub: Tr("聊天 / 通话 / 朋友圈 / 视界…")) { showFeature = true }
                        HairLine(inset: 54)
                        Button {
                            checkVersion()
                        } label: {
                            HStack {
                                Text(Tr("版本更新")).font(pf(16)).foregroundColor(C.label)
                                Spacer()
                                Text(checking ? "检查中…" : (latest.isEmpty ? "检查更新" : latest))
                                    .font(pf(14))
                                    .foregroundColor(C.subLabel)
                                Chevron(size: 9, line: 1.6).padding(.trailing, 3)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 52)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        HairLine(inset: 54)

                        aboutRow("person.crop.circle.badge.xmark", Tr("注销账号"),
                                 sub: Tr("App 内直接注销，7 天内可联系客服恢复"), tint: DDColor.red) { showDelete = true }
                        HairLine(inset: 54)
                        aboutRow("trash", Tr("数据删除与导出"), sub: Tr("注销后数据怎么处理")) { showDataDel = true }
                        HairLine(inset: 54)
                        aboutRow("lock.shield", Tr("账号安全"), sub: Tr("登录设备 / 实名 / 支付密码")) { showAccountSafe = true }
                        HairLine(inset: 54)
                        aboutRow("envelope", Tr("客服邮箱"),
                                 sub: supportEmail.isEmpty ? Tr("（后台未配置 supportEmail）") : supportEmail) {
                            guard !supportEmail.isEmpty else { return }
                            UIPasteboard.general.string = supportEmail
                            app.show(Tr("已复制"))
                        }
                        HairLine(inset: 54)
                        aboutRow("clock", Tr("服务时间"), sub: supportHours) { }
                        HairLine(inset: 16)

                        HStack {
                            Text(Tr("推送通知")).font(pf(16)).foregroundColor(C.label)
                            Spacer()
                            Text(pushText)
                                .font(pf(13))
                                .foregroundColor(C.subLabel)
                                .multilineTextAlignment(.trailing)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                    }

                    Text(Tr("星言为通信功能处理账号、内容和设备信息；音视频、AI、推送和支付会使用明确披露的服务商。"))
                        .font(pf(12.5))
                        .foregroundColor(C.subLabel)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, 30)
                        .padding(.top, 18)

                    Text("© 2026 " + appName + Tr(" · 保留所有权利"))
                        .font(pf(11.5))
                        .foregroundColor(C.subLabel.opacity(0.75))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
                    Spacer().frame(height: 30)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .task {
            if let b = await API.shared.branding(), let n = b.appName, !n.isEmpty { appName = n }
            if let s = await API.shared.pushStatus() { pushServerReady = (s.configured == true && s.enabled == true) }
        }
        .sheet(isPresented: $showFeature) { aboutText(Tr("功能介绍"), featureText) }
        .sheet(isPresented: $showPrivacy) { aboutText(Tr("隐私保护指引"), privacyText) }

        .sheet(isPresented: $showTerms) { TermsSheet(kind: 0) }
        .sheet(isPresented: $showPrivacyDoc) { TermsSheet(kind: 1) }
        .sheet(isPresented: $showCollect) { aboutText(Tr("个人信息收集清单"), collectText) }
        .sheet(isPresented: $showDataDel) { aboutText(Tr("数据删除与导出"), dataDelText) }
        .sheet(isPresented: $showPerm) { SelfPermView() }
        .sheet(isPresented: $showAccountSafe) { AccountSecurityView().environmentObject(app) }
        .sheet(isPresented: $showDelete) { DeleteAccountView().environmentObject(app) }
    }

    @State private var showTerms = false
    @State private var showPrivacyDoc = false
    @State private var showCollect = false
    @State private var showDataDel = false
    @State private var showPerm = false
    @State private var showAccountSafe = false
    @State private var showDelete = false

    private var company: String { UIConfig.text("appCompany", "").trimmingCharacters(in: .whitespaces) }
    private var icp: String { UIConfig.text("appIcp", "").trimmingCharacters(in: .whitespaces) }
    private var supportEmail: String { UIConfig.text("supportEmail", "").trimmingCharacters(in: .whitespaces) }
    private var supportHours: String { UIConfig.text("supportHours", "10:00–22:00") }
    private var privacyUpdated: String { UIConfig.text("privacyUpdated", "2026-10-30") }

    private var hero: some View {
        VStack(spacing: 9) {
            Group {
                if let img = AppIconImage.image {
                    Image(uiImage: img).resizable()
                } else {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(LinearGradient(colors: [C.green, C.green.opacity(0.72)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                }
            }
            .frame(width: 84, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.85), lineWidth: 2))
            .shadow(color: C.green.opacity(0.20), radius: 16, y: 6)
            Text(appName).font(pf(21, .semibold)).foregroundColor(C.label)
            Text(Tr("安全、稳定、面向团队的即时通信平台"))
                .font(pf(12.5))
                .foregroundColor(C.subLabel)
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                Text("v" + AppInfo.displayVersion)
                    .font(pf(11.5, .semibold)).foregroundColor(C.green)
                    .padding(.horizontal, 8).frame(height: 20)
                    .background(Capsule().fill(C.green.opacity(0.12)))
                Text(AppInfo.build).font(pf(11.5)).monospacedDigit().foregroundColor(C.subLabel)
                    .copyOnLongPress(AppInfo.build) { app.show($0) }
            }
            if !company.isEmpty {
                Text(company).font(pf(12.5)).foregroundColor(C.subLabel).multilineTextAlignment(.center)
            }
            if !icp.isEmpty {
                Text(Tr("APP 备案号 ") + icp).font(pf(11.5)).foregroundColor(C.subLabel)
                    .copyOnLongPress(icp) { app.show($0) }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(C.cardBg))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(C.hairline.opacity(0.7), lineWidth: 0.6))
    }

    private func aboutRow(_ icon: String, _ title: String, sub: String? = nil,
                          tint: Color = C.green, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(tint.opacity(0.10)).frame(width: 30, height: 30)
                    Image(systemName: icon).font(.system(size: 14.5)).foregroundColor(tint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(pf(15.5)).foregroundColor(C.label)
                    if let sub, !sub.isEmpty {
                        Text(sub).font(pf(11.5)).foregroundColor(C.subLabel).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold)).foregroundColor(C.subLabel.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .frame(height: (sub?.isEmpty == false) ? 60 : 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var collectText: String {
        Tr("星言仅在提供服务所必需的范围内处理以下信息：")
        + Tr("\n\n1. 账号：手机号 / 星言号 —— 登录、找回密码、安全验证")
        + Tr("\n2. 资料：昵称、头像、性别、地区、签名 —— 展示给好友和服务内可见对象")
        + Tr("\n3. 内容：聊天、图片、视频、语音、文件、朋友圈、收藏 —— 消息同步和内容展示")
        + Tr("\n4. 设备与安全：设备型号、系统版本、设备标识、IP、推送令牌、登录记录 —— 设备管理、风控和通知")
        + Tr("\n5. 位置：仅在使用附近、位置消息或实时共享时获取")
        + Tr("\n6. 实名与交易：实名姓名、证件哈希/掩码、银行卡后四位、订单、账单 —— 钱包、支付、售后和依法留存")
        + Tr("\n7. 诊断：崩溃、性能和必要的操作日志 —— 稳定性和故障排查")
        + Tr("\n\n第三方处理：腾讯云 TRTC（音视频）、DeepSeek（启用 AI 时）、Apple APNs（推送）、支付宝及后台配置的支付/短信服务。我们不会出售个人信息或用于跨 App 广告追踪。")
    }

    private var dataDelText: String {
        Tr("注销与数据删除规则：")
        + Tr("\n\n1. 在「关于我们 → 注销账号」输入「注销」即可注销，不需要联系客服。")
        + Tr("\n2. 注销后账号立即无法登录，所有设备登录状态失效。")
        + Tr("\n3. 账号资料、聊天、媒体、朋友圈、收藏和关系数据会立即清理，无法恢复。")
        + Tr("\n4. 订单、支付、发票和安全审计等依法必须留存的信息，只在法定期限内保留并限制访问。")
        + Tr("\n5. 如需在注销前导出聊天记录，请先使用「聊天记录迁移与备份」功能。")
    }

    @State private var showFeature = false
    @State private var showPrivacy = false

    private var featureText: String {
        Tr("星言是一体化即时通信与协作平台，面向个人沟通、团队协同和日常服务场景，提供安全、稳定的消息与内容能力。")
            + Tr("\n\n消息与沟通：支持单聊、群聊、多方会话、消息引用、撤回、@提醒和群公告，覆盖文字、图片、语音、视频、文件、位置、名片、红包与转账。")
            + Tr("\n\n音视频协作：提供一对一及群组语音、视频通话，支持低延迟通信与多端消息同步。")
            + Tr("\n\n内容与服务：整合朋友圈、视频号、直播、收藏、笔记、小程序、商城与生活服务入口。")
            + Tr("\n\n安全与效率：提供账号安全、登录设备管理、隐私控制、聊天记录迁移备份，以及 AI 工作台和智能助手能力。")
            + Tr("\n\n数据由自有服务统一管理，面向个人和团队提供可配置、可持续扩展的通信体验。")
    }

    private var privacyText: String {
        Tr("星言仅在提供功能所需的范围内处理账号、资料、聊天和媒体、设备与安全、位置、实名交易和诊断信息。")
            + Tr("\n\n相机、麦克风和相册仅在你拍照、发语音、视频通话或选图时使用；位置仅在使用附近、位置消息或实时共享时使用。人脸活体检测在本机完成，不上传人脸照片。")
            + Tr("\n\n音视频使用腾讯云 TRTC，AI 功能启用时使用 DeepSeek，推送使用 Apple APNs，支付使用支付宝或后台配置的支付服务。我们不会出售个人信息或用于跨 App 广告追踪。")
            + Tr("\n\n账号注销后，可删除数据会立即清理；依法必须保留的交易和安全审计记录会在法定期限内保存。")
    }

    private func aboutRow(_ title: String) -> some View {
        HStack {
            Text(title).font(pf(16)).foregroundColor(C.label)
            Spacer(minLength: 0)
            Chevron(size: 9, line: 1.6).padding(.trailing, 3)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .contentShape(Rectangle())
    }

    private func aboutText(_ title: String, _ body: String) -> some View {
        VStack(spacing: 0) {
            NavBar(title: title, back: { showFeature = false; showPrivacy = false })
            ScrollView(showsIndicators: false) {
                Text(body)
                    .font(pf(15))
                    .foregroundColor(C.label)
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 18)
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func checkVersion() {
        checking = true
        Task {
            if let v = await API.shared.serverVersion() {
                latest = v.isEmpty ? "已是最新" : "服务器版本 \(v)"
            } else {
                latest = "连不上服务器"
            }
            checking = false
        }
    }
}

struct DeleteAccountView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var busy = false

    private let lines: [String] = [
        "账号立即无法登录，所有设备的登录状态失效",
        "聊天记录、朋友圈、收藏、关系和媒体数据立即清理，无法恢复",
        "订单 / 支付 / 发票等依法需留存的记录按法定期限保存",
        "如需保留聊天记录，请先使用聊天记录迁移与备份"
    ]

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("注销账号"), back: { dismiss() })
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(Tr("注销后会发生什么")).font(pf(16, .semibold)).foregroundColor(C.label)
                    ForEach(lines, id: \.self) { line in
                        HStack(alignment: .top, spacing: 8) {
                            Circle().fill(C.subLabel.opacity(0.5))
                                .frame(width: 4, height: 4).padding(.top, 7)
                            Text(Tr(line)).font(pf(13.5)).foregroundColor(C.subLabel)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text(Tr("确认请在下面输入「注销」两个字："))
                        .font(pf(13.5, .medium)).foregroundColor(C.label)
                        .padding(.top, 8)
                    TextField(Tr("注销"), text: $input)
                        .font(pf(15))
                        .padding(.horizontal, 14).frame(height: 46)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(C.cardBg))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(C.hairline, lineWidth: 0.6))
                    Button {
                        guard input.trimmingCharacters(in: .whitespacesAndNewlines) == "注销", !busy else { return }
                        busy = true
                        Task {
                            let ok = await API.shared.deleteAccount(confirm: "注销")
                            busy = false
                            if ok {
                                if let userId = app.me?.id,
                                   let username = app.me?.username, !userId.isEmpty {
                                    app.purgeDeletedAccountLocally(userId: userId, username: username)
                                }
                                app.show(Tr("账号已注销"))
                                await app.logout(keepSavedAccount: false)
                                dismiss()
                            } else {
                                app.show(Tr("注销失败，检查网络后再试"))
                            }
                        }
                    } label: {
                        Text(busy ? Tr("正在注销…") : Tr("永久注销账号"))
                            .font(pf(16, .semibold)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(DDColor.red.opacity(input == "注销" ? 1 : 0.35)))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                    Spacer(minLength: 20)
                }
                .padding(16)
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct BirthdayPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var birthday: String

    @State private var date = Date()

    var body: some View {

        VStack(spacing: 0) {
            NavBar(title: Tr("选择生日"), back: { dismiss() }) {
                Button {
                    let f = DateFormatter()
                    f.dateFormat = "yyyy-MM-dd"
                    birthday = f.string(from: date)
                    dismiss()
                } label: {
                    Text(Tr("确定")).font(pf(15.5, .medium)).foregroundColor(C.green)
                        .padding(.horizontal, 14).frame(height: 32)
                }
                .buttonStyle(.plain)
            }
            VStack(spacing: 0) {
                DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .padding(.top, 10)
                Spacer()
            }
            .background(C.pageBg)
            .onAppear {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd"
                if let d = f.date(from: birthday) { date = d }
                else {
                    var c = DateComponents()
                    c.year = 2000; c.month = 1; c.day = 1
                    date = Calendar.current.date(from: c) ?? Date()
                }
            }
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
    }
}

struct ResetPasswordSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var phone = ""
    @State private var code = ""
    @State private var newPassword = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    field {
                        TextField("手机号", text: $phone).keyboardType(.numberPad)
                    }
                    HairLine(color: C.navLine)
                    field {
                        TextField("验证码", text: $code).keyboardType(.numberPad)
                        Button(Tr("获取验证码")) { sendCode() }
                            .font(.system(size: 14))
                            .foregroundColor(C.loginGreen)
                    }
                    HairLine(color: C.navLine)
                    field {
                        SecureField("新密码（至少 6 位）", text: $newPassword)
                    }

                    if let e = error {
                        Text(e).font(.system(size: 13)).foregroundColor(C.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 12)
                    }

                    Button { submit() } label: {
                        Text(busy ? "请稍候…" : "重置密码并登录")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(LoginTheme.accent)
                            .cornerRadius(16)
                    }
                    .disabled(busy)
                    .padding(.top, 20)

                    Text(Tr("验证码和「手机号登录」共用，5 分钟内有效。重置后其他设备会自动退出登录。"))
                        .font(.system(size: 12.5))
                        .foregroundColor(C.subLabel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 14)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
            }
            .background(Color(.systemBackground).ignoresSafeArea())
            .navigationTitle(Tr("密码找回"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button(Tr("取消")) { dismiss() } } }
        }
    }

    private func field<Content: View>(@ViewBuilder _ c: () -> Content) -> some View {
        HStack(spacing: 8) { c() }
            .font(.system(size: 15))
            .frame(height: 54)
            .padding(.horizontal, 14)
            .background(Color.dyn(0xFFFFFF, 0x1C1C1E))
    }

    private func sendCode() {
        let p = phone.trimmingCharacters(in: .whitespaces)
        if p.count < 5 { error = "请填写手机号"; return }
        error = nil
        Task {
            do {
                if let dev = try await API.shared.phoneCode(phone: p) {
                    code = dev
                    app.show("验证码：\(dev)")
                } else { app.show(Tr("验证码已发送")) }
            } catch { self.error = (error as? APIError)?.errorDescription ?? "发送失败" }
        }
    }

    private func submit() {
        let p = phone.trimmingCharacters(in: .whitespaces)
        if p.isEmpty || code.isEmpty { error = "请填手机号和验证码"; return }
        if newPassword.count < 6 { error = "新密码至少 6 位"; return }
        busy = true
        error = nil
        Task {
            let r = await API.shared.resetPassword(phone: p, code: code, newPassword: newPassword)
            if let err = r.error {
                error = err
                busy = false
                return
            }
            do {

                app.me = try? await API.shared.me()
                dismiss()
            } catch {
                self.error = (error as? APIError)?.errorDescription ?? "重置成功，但自动登录失败，请用新密码登录"
                busy = false
            }
        }
    }
}
