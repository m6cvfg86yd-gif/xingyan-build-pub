import SwiftUI

struct BillsView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var realtime = Realtime.shared

    @State private var bills: [BillRecord] = []
    @State private var months: [String] = []
    @State private var summary: BillSummary?
    @State private var month = ""
    @State private var loading = true
    @State private var showMonths = false
    @State private var showStats = false

    @State private var showMoreMenu = false

    @State private var shareFile: ShareFile?

    @State private var pickYear = 2026
    @State private var pickMonth = 10

    @State private var showSearch = false
    @State private var filter = "all"
    @State private var query = ""
    @State private var openBill: BillRecord?
    @State private var showDetail = false
    @State private var style = BillsPageStyle()
    @State private var faq: [BalanceFaq] = []
    @State private var showFaq = false
    @State private var faqAnswer: String?

    @State private var showFilterMenu = false

    private let fieldBg = Color.dyn(0xF1F2F5, 0x2C2C2E)
    private let fieldEdge = Color.dyn(0xE3E4E8, 0x3A3A3C)
    private let fieldInk = Color.dyn(0x3A3A3A, 0xEDEDED)
    private let timeGray = Color.dyn(0xB2B2B2, 0x8A8A8E)
    private let sumGray = Color.dyn(0x7B7B7B, 0x8A8A8E)
    private let incomeGold = Color(hex: 0xFFC406)

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("账单"), back: { dismiss() }) {
                Button {
                    withAnimation(.easeOut(duration: 0.12)) {
                        showMoreMenu.toggle()
                        showFilterMenu = false
                    }
                } label: {
                    WeChatDots()
                        .frame(width: 44, height: L.navH)
                }
                .buttonStyle(.plain)
            }

            .overlay(alignment: .topTrailing) {
                if showMoreMenu {
                    moreMenu
                        .padding(.trailing, 12)
                        .padding(.top, L.navH + 4)
                }
            }
            .zIndex(3)

            topBar

                .overlay(alignment: .topLeading) {
                    if showFilterMenu {
                        filterMenu
                            .padding(.leading, 16)
                            .padding(.top, 52.4 + 6)
                    }
                }
                .zIndex(2)

            if showMonths {
                monthPickerInline
            }

            if UIConfig.num("billSummaryCard", 0) > 0 {
                summaryCard
            }

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    if loading {
                        ProgressView().padding(.vertical, 40)
                    } else if filtered.isEmpty {
                        Text(Tr("还没有账单"))
                            .font(pf(14))
                            .foregroundColor(C.subLabel)
                            .padding(.vertical, 60)
                    } else {
                        ForEach(groups, id: \.month) { g in
                            Section {
                                ForEach(g.days, id: \.day) { d in
                                    dayRow(d)
                                    VStack(spacing: 0) {
                                        ForEach(Array(d.rows.enumerated()), id: \.element.id) { idx, b in
                                            row(b)
                                            if idx < d.rows.count - 1 { HairLine(inset: 64) }
                                        }
                                    }
                                    .background(PayVisual.card)
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    .padding(.horizontal, 16)
                                }
                            } header: {
                                monthHeader(g)
                            }
                        }
                    }
                    Color.clear.frame(height: 24)
                }
            }
            .background(PayVisual.canvas)

            .overlay {
                if showFilterMenu || showMoreMenu {
                    Color.black.opacity(0.05)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { closeMenus() }
                }
            }
            .zIndex(0)
        }
        .background(PayVisual.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .confirmationDialog(Tr("账单常见问题"), isPresented: $showFaq, titleVisibility: .visible) {
            ForEach(faq.indices, id: \.self) { i in
                Button(faq[i].q) { faqAnswer = faq[i].a }
            }
            Button(Tr("关闭"), role: .cancel) { }
        }
        .alert("账单常见问题", isPresented: Binding(get: { faqAnswer != nil }, set: { if !$0 { faqAnswer = nil } })) {
            Button(Tr("知道了"), role: .cancel) { faqAnswer = nil }
        } message: {
            Text(faqAnswer ?? "")
        }
        .navigationDestination(isPresented: $showDetail) {
            if let b = openBill { billDetail(b) }
        }

        .navigationDestination(isPresented: $showStats) {
            BillsStatsView()
        }

        .navigationDestination(isPresented: $showSearch) {
            BillSearchView()
        }
        .sheet(item: $shareFile) { f in ShareSheet(items: [f.url]) }
        .task { await load("") }

        .onChange(of: realtime.event) { ev in
            if ev.type == "transfer" || ev.type == "balance" { Task { await load(month) } }
        }
    }

    private var summaryCard: some View {
        let out = summary?.out ?? 0
        let income = summary?.inSum ?? 0
        let net = income - out
        let title = month.isEmpty ? Tr("本月支出") : (monthLabel(month) + Tr("支出"))
        return PayGroupCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(title)
                        .font(pf(13, .semibold))
                        .foregroundColor(PayVisual.secondaryInk)
                    Spacer()
                    if let summary, summary.pendingOut + summary.pendingIn > 0 {
                        PayStatusPill(
                            text: Tr("待处理") + " \(summary.pendingOut + summary.pendingIn)",
                            tone: .warning
                        )
                    }
                }
                Text(money(out))
                    .font(pfMoney(38, .semibold))
                    .foregroundColor(C.label)
                    .monospacedDigit()
                    .padding(.top, 9)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Rectangle()
                    .fill(PayVisual.separator)
                    .frame(height: 0.6)
                    .padding(.vertical, 15)
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(Tr("收入"))
                            .font(pf(12))
                            .foregroundColor(PayVisual.secondaryInk)
                        Text(money(income))
                            .font(pfMoney(17, .semibold))
                            .foregroundColor(PayVisual.success)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 12)
                    VStack(alignment: .trailing, spacing: 5) {
                        Text(Tr("结余"))
                            .font(pf(12))
                            .foregroundColor(PayVisual.secondaryInk)
                        Text(money(net))
                            .font(pfMoney(17, .semibold))
                            .foregroundColor(net >= 0 ? C.label : PayVisual.danger)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
            .padding(18)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var topBar: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.12)) {
                    showFilterMenu.toggle()
                    showMoreMenu = false
                }
            } label: {
                HStack(spacing: 3) {
                    Text(Tr(filterName)).font(pf(13)).foregroundColor(fieldInk)
                    DownChevron(size: 9, color: fieldInk)
                }
                .frame(width: 92, height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(fieldBg))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(fieldEdge, lineWidth: 0.5))
            }
            .buttonStyle(.plain)

            Button { showSearch = true } label: {
                HStack(spacing: 6) {
                    SVGIcon(markup: I.searchSmall, size: 13.5, color: C.subLabel)
                        .frame(width: 13.5, height: 13.5)
                    Text(Tr("查找交易"))
                        .font(pf(13.5))
                        .foregroundColor(C.subLabel)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 11)
                .frame(width: 126, height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(fieldBg))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(fieldEdge, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .padding(.leading, 14)

            Spacer(minLength: 0)

            Button { showStats = true } label: {
                HStack(spacing: 5) {
                    Text(Tr("收支统计")).font(pf(13)).foregroundColor(sumGray)
                    Chevron(size: 6, line: 1.4, color: sumGray)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16.7)
        .frame(height: 52.4)
        .background(PayVisual.canvas)
        .overlay(alignment: .bottom) { HairLine() }
    }

    private var filterName: String {
        filter == "out" ? "只看支出" : (filter == "in" ? "只看收入" : "全部账单")
    }

    private func closeMenus() {
        withAnimation(.easeOut(duration: 0.12)) {
            showFilterMenu = false
            showMoreMenu = false
        }
    }

    private var filterMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            menuTitle("账单范围")
            menuRow(Tr("全部账单"), filter == "all") { filter = "all"; closeMenus() }
            menuRow(Tr("只看支出"), filter == "out") { filter = "out"; closeMenus() }
            menuRow(Tr("只看收入"), filter == "in") { filter = "in"; closeMenus() }

            if !months.isEmpty {
                HairLine()
                menuTitle("按月份看")
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        menuRow(Tr("全部月份"), month.isEmpty) {
                            Task { await load("") }
                            closeMenus()
                        }
                        ForEach(months, id: \.self) { m in
                            menuRow(monthLabel(m), month == m) {
                                Task { await load(m) }
                                closeMenus()
                            }
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
        .frame(width: 178)
        .background(C.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 20, y: 8)
    }

    private var moreMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            menuRow(Tr("账单常见问题"), false) {
                closeMenus()
                showFaq = true
            }
            HairLine(inset: 14)
            menuRow(Tr("导出账单（CSV）"), false) {
                closeMenus()
                exportCsv()
            }
            HairLine(inset: 14)
            menuRow(Tr("分享账单文件"), false) {
                closeMenus()
                shareCsv()
            }
        }
        .frame(width: 190)
        .background(C.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 20, y: 8)
    }

    private func menuTitle(_ t: String) -> some View {
        Text(Tr(t))
            .font(pf(12))
            .foregroundColor(C.subLabel)
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    private func menuRow(_ title: String, _ on: Bool, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            HStack(spacing: 8) {
                Text(title)
                    .font(pf(15))
                    .foregroundColor(C.label)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if on {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(hex: 0x07C160))
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func monthHeader(_ g: MonthGroup) -> some View {
        let s = monthSum(g.month)
        return HStack(spacing: 0) {
            Button { openMonthPicker() } label: {
                HStack(spacing: 4) {
                    Text(monthLabel(g.month)).font(pf(style.monthFont)).foregroundColor(C.label)
                    DownChevron(size: 9, color: C.label)
                }
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            Text(Lang.isEnglish ? "Spent \(money(s.out))  Received \(money(s.income))"
                                : "支出 \(money(s.out)) 收入 \(money(s.income))")
                .font(pfMoney(style.sumFont))
                .foregroundColor(sumGray)
        }
        .padding(.leading, 17)
        .padding(.trailing, 18)
        .frame(height: 46)

        .background(PayVisual.canvas)
        .overlay(alignment: .bottom) { HairLine() }
    }

    private var availableYears: [Int] {
        var s = Set<Int>()
        for m in months { if let y = Int(m.prefix(4)) { s.insert(y) } }
        if let y = Int(month.prefix(4)), y > 0 { s.insert(y) }
        if s.isEmpty { s.insert(Calendar.current.component(.year, from: Date())) }
        return s.sorted(by: >)
    }

    private func openMonthPicker() {
        let base = month.isEmpty ? (months.first ?? "") : month
        let p = base.split(separator: "-")
        let cal = Calendar.current
        pickYear = (p.count == 2 ? Int(p[0]) : nil) ?? cal.component(.year, from: Date())
        pickMonth = (p.count == 2 ? Int(p[1]) : nil) ?? cal.component(.month, from: Date())
        withAnimation(.easeOut(duration: 0.16)) { showMonths = true }
    }

    private func closeMonthPicker() {
        withAnimation(.easeOut(duration: 0.16)) { showMonths = false }
    }

    private var monthPickerInline: some View {
        let years = availableYears
        return VStack(spacing: 0) {
            Button {
                closeMonthPicker()
                Task { await load("") }
            } label: {
                HStack(spacing: 6) {
                    Text(Tr("全部月份")).font(pf(15)).foregroundColor(C.label)
                    Spacer(minLength: 0)
                    if month.isEmpty {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(C.green)
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 46)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            HairLine()

            HStack(spacing: 0) {
                Picker("", selection: $pickYear) {
                    ForEach(years, id: \.self) { y in Text("\(y)" + Tr("年")).tag(y) }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                .clipped()

                Picker("", selection: $pickMonth) {
                    ForEach(1...12, id: \.self) { m in Text("\(m)" + Tr("月")).tag(m) }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                .clipped()
            }
            .frame(height: 170)

            HStack(spacing: 10) {
                Text(Tr("滚到要看的年月，点「完成」"))
                    .font(pf(12))
                    .foregroundColor(C.subLabel)
                Spacer(minLength: 0)
                Button {
                    closeMonthPicker()
                    Task { await load(String(format: "%04d-%02d", pickYear, pickMonth)) }
                } label: {
                    Text(Tr("完成"))
                        .font(pf(14, .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .frame(height: 32)
                        .background(Capsule().fill(C.green))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(C.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func dayRow(_ d: DayGroup) -> some View {
        HStack(spacing: 0) {
            Text(TimeFmt.billDay(d.rows.first?.createdAt))
                .font(pf(13))
                .foregroundColor(sumGray)
            Spacer(minLength: 8)
            Text(dayRight(d.rows))
                .font(pfMoney(12.5))
                .foregroundColor(sumGray)
        }
        .padding(.horizontal, 17)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 2)
        .background(PayVisual.canvas)
    }

    private func dayRight(_ rows: [BillRecord]) -> String {
        let out = rows.filter { $0.mine }.reduce(0) { $0 + $1.amount }
        if out > 0 { return "支出 " + money(out) }
        let inc = rows.filter { !$0.mine && ($0.status ?? "") == "received" }.reduce(0) { $0 + $1.amount }
        if inc > 0 { return "收入 " + money(inc) }
        return ""
    }

    private func row(_ b: BillRecord) -> some View {
        Button {
            openBill = b
            showDetail = true
        } label: {
            HStack(spacing: 0) {
                Avatar(path: b.peerAvatar ?? "", size: style.icon, radius: style.icon * 0.25)
                    .padding(.leading, 16)
                VStack(alignment: .leading, spacing: 11) {
                    Text(rowTitle(b))
                        .font(pf(style.titleFont))
                        .foregroundColor(C.label)
                        .lineLimit(1)
                    Text(rowSub(b))
                        .font(pf(style.timeFont))
                        .foregroundColor(timeGray)
                        .lineLimit(1)
                }
                .padding(.leading, 17)
                Spacer(minLength: 8)

                MoneyLabel(text: (b.mine ? "-" : "") + (style.showCurV ? money(b.amount) : moneyFmt(b.amount)),
                           size: style.amountFont, curSize: style.curFontSize,
                           color: b.mine ? C.label : incomeGold,
                           weight: style.amountWeightV)
                    .padding(.trailing, 18)
            }
            .frame(height: style.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func rowTitle(_ b: BillRecord) -> String {

        let kind = b.walletKind ?? ""
        if !kind.isEmpty, let n = b.note, !n.isEmpty { return n }
        return b.mine ? ("转账给" + b.peer) : (b.peer + "转给你")
    }

    private func rowSub(_ b: BillRecord) -> String {
        let t = TimeFmt.billClock(b.createdAt)
        if (b.status ?? "pending") == "pending" { return t + " · " + b.stateText }
        return t
    }

    @ViewBuilder
    private func billDetail(_ b: BillRecord) -> some View {
        let meId = app.me?.id ?? ""
        let chat = Chat(id: (b.chatId?.isEmpty == false ? b.chatId! : (b.peerId ?? b.id)),
                        type: "direct",
                        title: b.peer,
                        avatar: b.peerAvatar)
        let json: [String: Any] = [
            "id": b.id,
            "amount": b.amount,
            "note": b.note ?? "",
            "status": b.status ?? "pending",
            "method": b.method ?? "balance",
            "fromId": b.mine ? meId : (b.peerId ?? ""),
            "toId": b.mine ? (b.peerId ?? "") : meId,
            "createdAt": b.createdAt ?? "",
            "expiresAt": b.expiresAt ?? 0,
            "receivedAt": b.receivedAt ?? "",
            "refundedAt": b.refundedAt ?? ""
        ]
        if let data = try? JSONSerialization.data(withJSONObject: json),
           let s = String(data: data, encoding: .utf8),
           let info = TransferInfo(json: s) {
            BillDetailView(chat: chat, info: info)
        } else {
            Text(Tr("这条账单读不出来")).font(pf(14)).foregroundColor(C.subLabel)
        }
    }

    private struct DayGroup: Hashable { var day: String; var rows: [BillRecord] }

    private struct MonthGroup: Hashable { var month: String; var days: [DayGroup] }

    private var filtered: [BillRecord] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return bills.filter { b in
            if filter == "out" && !b.mine { return false }
            if filter == "in" && b.mine { return false }
            if !q.isEmpty {
                let hay = (b.peer + " " + (b.note ?? "")).lowercased()
                if !hay.contains(q) { return false }
            }
            return true
        }
    }

    private var groups: [MonthGroup] {
        var out: [MonthGroup] = []
        for b in filtered {
            let m = String((b.createdAt ?? "").prefix(7))
            let d = String((b.createdAt ?? "").prefix(10))

            var g: MonthGroup
            if out.last?.month == m { g = out.removeLast() } else { g = MonthGroup(month: m, days: []) }
            if g.days.last?.day == d {
                var day = g.days.removeLast()
                day.rows.append(b)
                g.days.append(day)
            } else {
                g.days.append(DayGroup(day: d, rows: [b]))
            }
            out.append(g)
        }
        return out
    }

    private func monthSum(_ m: String) -> (out: Double, income: Double) {
        var o = 0.0
        var i = 0.0
        for b in bills where String((b.createdAt ?? "").prefix(7)) == m {
            if b.mine { o += b.amount }
            else if (b.status ?? "") == "received" { i += b.amount }
        }
        return (o, i)
    }

    private func monthLabel(_ m: String) -> String {
        let parts = m.split(separator: "-")
        guard parts.count == 2, let mm = Int(parts[1]) else { return m }
        return "\(parts[0])年\(mm)月"
    }

    private func money(_ v: Double) -> String { "¥" + moneyFmt(v) }

    private func exportCsv() {
        guard !bills.isEmpty else { app.show(Tr("还没有账单可以导出")); return }
        UIPasteboard.general.string = csvText()
        app.show("已复制 \(bills.count) 笔账单到剪贴板（CSV）")
    }

    private func shareCsv() {
        guard !bills.isEmpty else { app.show(Tr("还没有账单可以导出")); return }
        guard let url = writeTempFile(name: "星言账单.csv", text: csvText()) else {
            app.show(Tr("账单导出失败，再试一次"))
            return
        }
        shareFile = ShareFile(url: url)
    }

    private func csvText() -> String {
        var lines = ["时间,对方,方向,金额,状态,说明,支付方式,单号"]
        for b in bills {
            let fields = [
                TimeFmt.bill(b.createdAt),
                rowTitle(b),
                b.mine ? "支出" : "收入",
                (b.mine ? "-" : "+") + moneyFmt(b.amount),
                b.stateText,
                b.note ?? "",
                (b.method ?? "balance") == "card" ? "银行卡" : "零钱",
                b.id
            ]
            lines.append(fields.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private func load(_ m: String) async {
        loading = true
        if let d = try? await API.shared.bills(month: m.isEmpty ? nil : m) {
            bills = d.bills
            months = d.months ?? []
            summary = d.summary
            month = m
            if let s = d.style { style = s }
            faq = d.faq ?? []
        }
        loading = false
    }
}

struct DownChevron: View {
    var size: CGFloat = 9
    var line: CGFloat = 1.6
    var color: Color = .gray
    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: size / 2, y: size / 2))
            p.addLine(to: CGPoint(x: size, y: 0))
        }
        .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
        .frame(width: size, height: size / 2)
    }
}
