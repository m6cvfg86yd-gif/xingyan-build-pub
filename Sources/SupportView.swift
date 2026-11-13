import SwiftUI

struct SupportView: View {
    @ObservedObject private var lang = LangStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var cfg: API.SupportPayload?
    @State private var loading = true
    @State private var q = ""
    @State private var nextChat: Chat?
    @State private var openCat: API.SupportCategory?
    @State private var showTicket = false
    @State private var busyHuman = false

    @State private var showKefu = false
    @State private var selectedTicket: API.SupportTicket?

    private var cats: [API.SupportCategory] { cfg?.categories ?? [] }
    private var tickets: [API.SupportTicket] { cfg?.tickets ?? [] }
    private var isOpenHuman: Bool { (cfg?.human ?? 1) != 0 }
    private var isTicketOn: Bool { (cfg?.ticketOn ?? 1) != 0 }

    private var hits: [(cat: String, item: API.SupportItem)] {
        let key = q.trimmingCharacters(in: .whitespaces)
        if key.isEmpty { return [] }
        var out: [(String, API.SupportItem)] = []
        for c in cats {
            for it in (c.items ?? []) {
                if it.q.localizedCaseInsensitiveContains(key) || it.a.localizedCaseInsensitiveContains(key) {
                    out.append((c.title, it))
                }
            }
        }
        return out
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    supportHero
                        .listRowInsets(EdgeInsets(top: 16, leading: 18,
                                                 bottom: 16, trailing: 18))
                        .listRowBackground(Color.clear)
                }

                if !q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section(Tr("搜索结果")) {
                        if hits.isEmpty {
                            supportEmptyResult
                        } else {
                            ForEach(Array(hits.enumerated()), id: \.offset) { _, hit in
                                QAItem(category: hit.cat, item: hit.item, forceOpen: true)
                            }
                        }
                    }
                } else {
                    if isOpenHuman {
                        Section(Tr("联系支持")) {
                            Button { openHuman() } label: {
                                supportActionRow(
                                    symbol: "bubble.left.and.bubble.right.fill",
                                    color: .accentColor,
                                    title: cfg?.agent?.nickname ?? Tr("在线客服"),
                                    subtitle: (cfg?.workTime?.isEmpty == false)
                                        ? cfg!.workTime!
                                        : Tr("通常几分钟内回复")
                                )
                            }
                            .disabled(busyHuman)
                        }
                    }

                    if !cats.isEmpty {
                        Section(Tr("浏览支持主题")) {
                            ForEach(Array(cats.enumerated()), id: \.element.id) { index, category in
                                Button { openCat = category } label: {
                                    supportActionRow(
                                        symbol: catSymbol(category.title),
                                        color: catColor(index),
                                        title: category.title,
                                        subtitle: "\((category.items ?? []).count) " + Tr("个解决方案")
                                    )
                                }
                            }
                        }
                    }

                    if isTicketOn || !tickets.isEmpty {
                        Section(Tr("我的支持")) {
                            if isTicketOn {
                                Button { showTicket = true } label: {
                                    supportActionRow(
                                        symbol: "square.and.pencil",
                                        color: .orange,
                                        title: Tr("提交问题"),
                                        subtitle: Tr("写下问题，支持团队会跟进")
                                    )
                                }
                            }
                            ForEach(tickets) { ticket in
                                Button { selectedTicket = ticket } label: {
                                    ticketListRow(ticket)
                                }
                            }
                        }
                    }

                    if !(cfg?.phone ?? "").isEmpty || !(cfg?.email ?? "").isEmpty {
                        Section(Tr("更多联系方式")) {
                            contactListRows
                        }
                    }

                    Section {
                        Label {
                            Text(Tr("星言支持不会索要密码、验证码或支付密码，也不会要求你转账。"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } icon: {
                            Image(systemName: "lock.shield.fill")
                                .foregroundStyle(.green)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(cfg?.title ?? Tr("星言支持"))
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $q,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: Text(cfg?.searchHint?.isEmpty == false
                                     ? cfg!.searchHint!
                                     : Tr("搜索问题或描述故障")))
            .refreshable { await load() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(Tr("关闭"))
                }
            }
            .task { await load() }
            .navigationDestination(isPresented: Binding(
                get: { nextChat != nil },
                set: { if !$0 { nextChat = nil } }
            )) {
                if let c = nextChat { ChatDetailView(chat: c) }
            }
            .navigationDestination(isPresented: Binding(
                get: { openCat != nil },
                set: { if !$0 { openCat = nil } }
            )) {
                if let c = openCat { SupportCategoryView(cat: c, keyword: q) }
            }
            .sheet(isPresented: $showTicket) {
                SupportTicketSheet(hint: cfg?.ticketHint ?? "",
                                   categories: cats.map { $0.title }) { cat, text in
                    let list = try await API.shared.supportTicket(category: cat, content: text)
                    await MainActor.run {
                        if var c = cfg {
                            c.tickets = list
                            cfg = c
                        }
                        app.show(Tr("已经提交，客服处理完会回到这里"))
                    }
                }
                .environmentObject(app)
            }
            .sheet(item: $selectedTicket) { ticket in
                SupportTicketDetailView(ticket: ticket)
            }
            .sheet(isPresented: $showKefu) {
                KefuPage().environmentObject(app)
            }
        }
        .hidesTabBar()
    }

    private var supportHero: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x28B8F6), Color(hex: 0x087CF0)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "lifepreserver.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 64, height: 64)
            .shadow(color: Color(hex: 0x087CF0).opacity(0.24), radius: 14, y: 7)

            VStack(alignment: .leading, spacing: 5) {
                Text(Tr("需要什么帮助？"))
                    .font(.title3.weight(.semibold))
                Text(Tr("先搜索解决方案，或直接联系星言支持团队。"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func supportActionRow(symbol: String, color: Color,
                                  title: String, subtitle: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 3)
    }

    private func ticketListRow(_ ticket: API.SupportTicket) -> some View {
        let status = ticket.status ?? "pending"
        return HStack(spacing: 12) {
            Image(systemName: status == "done" ? "checkmark.circle.fill" : "clock.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(status == "done" ? .green :
                                 (status == "replied" ? .blue : .orange))
            VStack(alignment: .leading, spacing: 4) {
                Text(ticket.category ?? Tr("其它问题"))
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(ticket.content ?? ticket.title ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(status == "done" ? Tr("已处理") :
                 (status == "replied" ? Tr("已回复") : Tr("待处理")))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var contactListRows: some View {
        if let phone = cfg?.phone, !phone.isEmpty {
            Button {
                if let url = URL(string: "tel://" + phone.filter { $0.isNumber }) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label(phone, systemImage: "phone.fill")
            }
        }
        if let mail = cfg?.email, !mail.isEmpty {
            Button {
                let subject = (cfg?.title ?? Tr("星言支持")) + " " + (app.me?.username ?? "")
                let encoded = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                if let url = URL(string: "mailto:\(mail)?subject=\(encoded)") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label(mail, systemImage: "envelope.fill")
            }
        }
    }

    private var supportEmptyResult: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
            Text(Tr("没有找到相关支持内容"))
                .font(.headline)
            Text(Tr("换个关键词，或联系在线客服继续处理。"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if isOpenHuman {
                Button(Tr("联系在线客服")) { openHuman() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(C.searchIcon)
            TextField(cfg?.searchHint?.isEmpty == false ? (cfg!.searchHint!) : Tr("描述你遇到的问题"), text: $q)
                .font(pf(14.5))
                .foregroundColor(C.label)
                .submitLabel(.search)
            if !q.isEmpty {
                Button { q = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(C.searchIcon)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(C.searchBg))
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }

    private var hitList: some View {
        Group {
            if hits.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 34, weight: .light))
                        .foregroundColor(C.subLabel)
                    Text(Tr("没找到相关的，换个说法试试"))
                        .font(pf(14))
                        .foregroundColor(C.subLabel)
                    if isOpenHuman {
                        Button { openHuman() } label: {
                            Text(busyHuman ? Tr("正在接通…") : Tr("联系在线客服"))
                                .font(pf(15, .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 22)
                                .frame(height: 40)
                                .background(Capsule().fill(C.green))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            } else {
                GroupCard {
                    ForEach(Array(hits.enumerated()), id: \.offset) { idx, hit in
                        if idx > 0 { HairLine(inset: 16) }
                        QAItem(category: hit.cat, item: hit.item, forceOpen: true)
                    }
                }
                .padding(.top, 10)
            }
        }
    }

    private var humanCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                AsyncAvatar(path: cfg?.agent?.avatar ?? "", size: 46, corner: 23)
                VStack(alignment: .leading, spacing: 4) {
                    Text(cfg?.agent?.nickname ?? Tr("在线客服"))
                        .font(pf(16.5, .medium))
                        .foregroundColor(C.label)
                    Text((cfg?.workTime?.isEmpty == false) ? cfg!.workTime! : Tr("人工在线时间 09:00 - 22:00"))
                        .font(pf(12.5))
                        .foregroundColor(C.subLabel)
                }
                Spacer(minLength: 8)
                Button { openHuman() } label: {
                    Text(busyHuman ? Tr("接通中…") : Tr("联系客服"))
                        .font(pf(14.5, .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 34)
                        .background(Capsule().fill(C.green))
                }
                .buttonStyle(.plain)
                .disabled(busyHuman)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
        .background { CardGlassBox(radius: 8) }
        .padding(.horizontal, 8)
        .padding(.top, 10)
    }

    private var faqCard: some View {
        Group {
            if !cats.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text(Tr("常见问题"))
                        .font(pf(13))
                        .foregroundColor(C.subLabel)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 6)
                    GroupCard {
                        ForEach(Array(cats.enumerated()), id: \.element.id) { idx, c in
                            if idx > 0 { HairLine(inset: 58) }
                            Button { openCat = c } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: catSymbol(c.title))
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white)
                                        .frame(width: 30, height: 30)
                                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(catColor(idx)))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(c.title)
                                            .font(pf(16.5))
                                            .foregroundColor(C.label)
                                        Text(Tr("共") + " \((c.items ?? []).count) " + Tr("个问题"))
                                            .font(pf(12))
                                            .foregroundColor(C.subLabel)
                                    }
                                    Spacer(minLength: 8)
                                    Chevron(size: 9, line: 1.6)
                                }
                                .padding(.horizontal, 14)
                                .frame(height: 60)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 14)
            }
        }
    }

    private var ticketCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupCard {
                Button { showTicket = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 30, height: 30)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(hexString: "#1180E0", fallback: 0x1180E0)))
                        Text(Tr("提交问题"))
                            .font(pf(16.5))
                            .foregroundColor(C.label)
                        Spacer(minLength: 8)
                        Text(Tr("写清楚一点，我们尽快处理"))
                            .font(pf(12.5))
                            .foregroundColor(C.subLabel)
                        Chevron(size: 9, line: 1.6)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 14)
    }

    private var myTickets: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Tr("我的工单"))
                .font(pf(13))
                .foregroundColor(C.subLabel)
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
            GroupCard {
                ForEach(Array(tickets.enumerated()), id: \.element.id) { idx, t in
                    if idx > 0 { HairLine(inset: 14) }
                    ticketRow(t)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 14)
    }

    private func ticketRow(_ t: API.SupportTicket) -> some View {
        let done = (t.status ?? "") == "done"
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(t.category ?? Tr("其它问题"))
                    .font(pf(15, .medium))
                    .foregroundColor(C.label)
                Spacer(minLength: 8)
                Text(done ? Tr("已处理") : ((t.status ?? "") == "replied" ? Tr("已回复") : Tr("待处理")))
                    .font(pf(12.5))
                    .foregroundColor(done ? C.subLabel : C.green)
                Text(shortTime(t.createdAt ?? ""))
                    .font(pf(12))
                    .foregroundColor(C.subLabel)
            }
            if let c = t.content, !c.isEmpty {
                Text(c)
                    .font(pf(14))
                    .foregroundColor(C.subLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let r = t.reply, !r.isEmpty {
                Text(Tr("客服回复") + "：" + r)
                    .font(pf(14))
                    .foregroundColor(C.label)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder private var contactCard: some View {
        let phone = cfg?.phone ?? ""
        let mail = cfg?.email ?? ""
        if !phone.isEmpty || !mail.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(Tr("其他联系方式"))
                    .font(pf(13))
                    .foregroundColor(C.subLabel)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
                GroupCard {
                    if !phone.isEmpty {
                        Button {
                            if let url = URL(string: "tel://" + phone.filter { $0.isNumber }) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            contactRow(Tr("客服电话"), phone)
                        }
                        .buttonStyle(.plain)
                    }
                    if !phone.isEmpty && !mail.isEmpty { HairLine(inset: 14) }
                    if !mail.isEmpty {
                        Button {
                            let body = (cfg?.title ?? Tr("客服中心")) + " " + (app.me?.username ?? "")
                            if let url = URL(string: "mailto:" + mail + "?subject=Feedback&body="
                                             + (body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            contactRow(Tr("客服邮箱"), mail)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 14)
        }
    }

    private func contactRow(_ title: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(title).font(pf(16.5)).foregroundColor(C.label)
            Spacer(minLength: 8)
            Text(value).font(pf(14)).foregroundColor(C.subLabel)
            Chevron(size: 9, line: 1.6)
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .contentShape(Rectangle())
    }

    private var footNote: some View {
        Text(Tr("客服不会向你索要密码、验证码，也不会让你转账。遇到这种都是骗子。"))
            .font(pf(12.5))
            .foregroundColor(C.subLabel)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 22)
            .padding(.top, 16)
    }

    private func load() async {
        if let got = try? await API.shared.support() {
            cfg = got
        }
        loading = false
    }

    private func openHuman() {

        if busyHuman { return }
        showKefu = true
    }

    private func catSymbol(_ title: String) -> String {
        if title.contains("账号") || title.contains("登录") || title.contains("注册") { return "person.crop.circle" }
        if title.contains("支付") || title.contains("钱包") || title.contains("钱") || title.contains("转账") { return "creditcard" }
        if title.contains("聊天") || title.contains("通话") || title.contains("消息") || title.contains("群") { return "bubble.left.and.bubble.right" }
        if title.contains("安全") || title.contains("隐私") || title.contains("锁") || title.contains("实名") { return "lock.shield" }
        if title.contains("功能") || title.contains("使用") || title.contains("怎么") { return "hand.raised" }
        return "questionmark.circle"
    }

    private func catColor(_ idx: Int) -> Color {
        let list: [Color] = [C.green, Color(hexString: "#1180E0", fallback: 0x1180E0),
                             Color(hexString: "#FA9D3B", fallback: 0xFA9D3B), C.red]
        return list[idx % list.count]
    }
}

struct SupportTicketDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let ticket: API.SupportTicket

    private var status: String { ticket.status ?? "pending" }

    private var statusText: String {
        if status == "done" { return Tr("已处理") }
        if status == "replied" { return Tr("支持团队已回复") }
        return Tr("等待支持团队处理")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(statusText, systemImage: status == "done"
                              ? "checkmark.circle.fill"
                              : (status == "replied" ? "bubble.left.fill" : "clock.fill"))
                            .font(.headline)
                            .foregroundStyle(status == "done" ? .green :
                                             (status == "replied" ? .blue : .orange))
                        if let created = ticket.createdAt {
                            Text(TimeFmt.bill(created))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section(Tr("问题")) {
                    Text(ticket.content ?? ticket.title ?? "")
                        .font(.body)
                        .textSelection(.enabled)
                        .padding(.vertical, 6)
                    if let category = ticket.category {
                        LabeledContent(Tr("分类"), value: category)
                    }
                }

                Section(Tr("支持团队回复")) {
                    if let reply = ticket.reply, !reply.isEmpty {
                        Text(reply)
                            .font(.body)
                            .textSelection(.enabled)
                            .padding(.vertical, 6)
                        if let repliedAt = ticket.repliedAt {
                            Text(TimeFmt.bill(repliedAt))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(Tr("还没有回复"))
                                .font(.body)
                            Text(Tr("处理完成后，回复会显示在这里。"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .navigationTitle(Tr("支持请求"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Tr("完成")) { dismiss() }
                }
            }
        }
    }
}

struct SupportCategoryView: View {
    @ObservedObject private var lang = LangStore.shared
    @Environment(\.dismiss) private var dismiss

    let cat: API.SupportCategory
    var keyword: String = ""

    @State private var open: Set<String> = []
    @State private var showKefu = false

    var body: some View {
        List {
            Section {
                ForEach(cat.items ?? []) { item in
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { open.contains(item.q) || !keyword.isEmpty },
                            set: { expanded in
                                if expanded { open.insert(item.q) }
                                else { open.remove(item.q) }
                            }
                        )
                    ) {
                        Text(item.a)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .padding(.vertical, 6)
                    } label: {
                        Text(item.q)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                            .padding(.vertical, 3)
                    }
                }
            } header: {
                Text(Tr("解决方案"))
            }

            Section {
                Button {
                    showKefu = true
                } label: {
                    Label(Tr("联系在线客服"), systemImage: "bubble.left.and.bubble.right.fill")
                }
            } footer: {
                Label(Tr("支持人员不会索要密码、验证码或支付密码。"),
                      systemImage: "lock.shield.fill")
                    .font(.footnote)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(cat.title)
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showKefu) {
            KefuPage()
        }
        .hidesTabBar()
        .onAppear {
            if !keyword.isEmpty {
                for item in cat.items ?? [] where
                    item.q.localizedCaseInsensitiveContains(keyword) ||
                    item.a.localizedCaseInsensitiveContains(keyword) {
                    open.insert(item.q)
                }
                if let first = (cat.items ?? []).first { open.insert(first.q) }
            }
        }
    }
}

struct QAItem: View {
    let category: String
    let item: API.SupportItem
    var forceOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Circle().fill(C.green.opacity(0.16)).frame(width: 6, height: 6).padding(.top, 7)
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.q)
                        .font(pf(15.5, forceOpen ? .medium : .regular))
                        .foregroundColor(C.label)
                        .fixedSize(horizontal: false, vertical: true)
                    if forceOpen && !item.a.isEmpty {
                        Text(item.a)
                            .font(pf(14.5))
                            .foregroundColor(C.subLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 6)
                if !forceOpen {
                    Chevron(size: 8, line: 1.5, color: C.searchIcon)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct SupportTicketSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    var hint: String = ""
    var categories: [String] = []
    var onSubmit: (String, String) async throws -> Void

    @State private var category = ""
    @State private var text = ""
    @State private var busy = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                if !hint.isEmpty {
                    Section {
                        Text(hint)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(Tr("问题描述")) {
                    ZStack(alignment: .topLeading) {
                        if text.isEmpty {
                            Text(Tr("写清楚什么时候、在哪个页面、点了什么、出现什么"))
                                .font(.body)
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                        }
                        TextEditor(text: $text)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 170)
                            .focused($focused)
                    }
                }

                if !categories.isEmpty {
                    Section(Tr("问题分类")) {
                        Picker(Tr("分类"), selection: $category) {
                            Text(Tr("请选择")).tag("")
                            ForEach(categories, id: \.self) { value in
                                Text(value).tag(value)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                Section {
                    Label(Tr("请勿发送密码、完整银行卡号或验证码。"),
                          systemImage: "lock.shield.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(Tr("提交问题"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Tr("取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        send()
                    } label: {
                        if busy {
                            ProgressView()
                        } else {
                            Text(Tr("提交")).fontWeight(.semibold)
                        }
                    }
                    .disabled(busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task {
                try? await Task.sleep(nanoseconds: 280_000_000)
                focused = true
            }
        }
    }

    private func send() {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty { app.show(Tr("先把问题写一句")); return }
        busy = true
        Task {
            do {
                try await onSubmit(category.isEmpty ? (categories.first ?? Tr("其它问题")) : category, body)
                busy = false
                dismiss()
            } catch {
                busy = false
                app.show((error as? LocalizedError)?.errorDescription ?? Tr("提交失败，再试一次"))
            }
        }
    }
}

struct AsyncAvatar: View {
    let path: String
    let size: CGFloat
    var corner: CGFloat = 0

    var body: some View {
        Group {
            if !path.isEmpty, let url = API.shared.assetURL(path) {
                AsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner > 0 ? corner : 6, style: .continuous))
    }

    private var placeholder: some View {
        ZStack {
            C.green
            Image(systemName: "headphones")
                .font(.system(size: size * 0.45, weight: .medium))
                .foregroundColor(.white)
        }
    }
}

func shortTime(_ raw: String) -> String {
    let s = raw.replacingOccurrences(of: "T", with: " ")
    guard s.count >= 16 else { return s }
    let a = s.index(s.startIndex, offsetBy: 5)
    let b = s.index(s.startIndex, offsetBy: 16)
    return String(s[a..<b])
}
