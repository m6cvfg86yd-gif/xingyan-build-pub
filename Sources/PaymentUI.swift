import SwiftUI
import UIKit

enum PayVisual {
    static let tint = Color(hex: 0x0A84FF)
    static let success = Color(hex: 0x30D158)
    static let warning = Color(hex: 0xFF9F0A)
    static let danger = Color(hex: 0xFF453A)
    static let gold = Color(hex: 0xD9A441)

    static var canvas: Color { Color.dyn(0xF2F2F7, 0x000000) }
    static var card: Color { Color.dyn(0xFFFFFF, 0x1C1C1E) }
    static var raised: Color { Color.dyn(0xFFFFFF, 0x2C2C2E) }
    static var inset: Color { Color.dyn(0xF2F2F7, 0x2C2C2E) }
    static var separator: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.10)
                : UIColor(white: 0, alpha: 0.08)
        })
    }
    static var secondaryInk: Color { Color.dyn(0x6C6C70, 0x98989F) }
}

struct PayGroupCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) { content }
            .background(PayVisual.card)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct PaySectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(pf(13, .semibold))
            .foregroundColor(PayVisual.secondaryInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

struct PayStatusPill: View {
    let text: String
    var tone: Tone = .neutral

    enum Tone {
        case neutral, processing, success, warning, danger
    }

    private var color: Color {
        switch tone {
        case .neutral: return PayVisual.secondaryInk
        case .processing: return PayVisual.tint
        case .success: return PayVisual.success
        case .warning: return PayVisual.warning
        case .danger: return PayVisual.danger
        }
    }

    var body: some View {
        Text(text)
            .font(pf(12.5, .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .frame(height: 27)
            .background(color.opacity(0.12), in: Capsule())
    }
}

struct PayDetailRow: View {
    let title: String
    let value: String
    var valueColor: Color = C.label
    var copyValue: String? = nil

    @EnvironmentObject private var app: AppState

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(title)
                .font(pf(15))
                .foregroundColor(PayVisual.secondaryInk)
            Spacer(minLength: 12)
            Text(value)
                .font(pf(15, .medium))
                .foregroundColor(valueColor)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .onTapGesture {
            guard let copyValue, !copyValue.isEmpty else { return }
            UIPasteboard.general.string = copyValue
            app.show(Tr("已复制"))
        }
    }
}

struct PayEmptyState: View {
    let symbol: String
    let title: String
    var detail: String = ""

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 32, weight: .regular))
                .foregroundColor(PayVisual.secondaryInk)
            Text(title)
                .font(pf(16, .semibold))
                .foregroundColor(C.label)
            if !detail.isEmpty {
                Text(detail)
                    .font(pf(13))
                    .foregroundColor(PayVisual.secondaryInk)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .padding(.horizontal, 28)
    }
}

struct PayPrimaryButtonStyle: ButtonStyle {
    var tint: Color = PayVisual.tint
    var enabled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(pf(17, .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(enabled ? tint : PayVisual.secondaryInk.opacity(0.34))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct PaySecondaryButtonStyle: ButtonStyle {
    var tint: Color = PayVisual.tint

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(pf(16, .semibold))
            .foregroundColor(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(PayVisual.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(tint.opacity(0.24), lineWidth: 0.8)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct PayOfficialView: View {
    private struct LedgerDayGroup: Identifiable {
        let day: String
        let entries: [LedgerBillEntry]
        var id: String { day }
    }

    let name: String
    let subtitle: String
    let avatar: String

    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var ledger: LedgerBillsPayload?
    @State private var loading = true
    @State private var selectedLedger: LedgerBillEntry?

    private var balance: Double { app.me?.balance ?? ledger?.balance ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: name, back: { dismiss() })

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    identity

                    PayGroupCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(Tr("零钱余额"))
                                        .font(pf(13, .medium))
                                        .foregroundColor(PayVisual.secondaryInk)
                                    Text("¥" + moneyFmt(balance))
                                        .font(pfMoney(30, .semibold))
                                        .foregroundColor(C.label)
                                        .monospacedDigit()
                                }
                                Spacer()
                                if let ledger {
                                    PayStatusPill(
                                        text: ledger.verified ? Tr("账本已核对") : Tr("账本待核对"),
                                        tone: ledger.verified ? .success : .warning
                                    )
                                }
                            }

                            if let ledger {
                                HStack(spacing: 0) {
                                    stat(Tr("收入"), ledger.income, PayVisual.success)
                                    Rectangle().fill(PayVisual.separator).frame(width: 0.5, height: 30)
                                    stat(Tr("支出"), ledger.expense, C.label)
                                    Rectangle().fill(PayVisual.separator).frame(width: 0.5, height: 30)
                                    stat(Tr("净额"), ledger.net, ledger.net >= 0 ? C.label : PayVisual.danger)
                                }
                            }
                        }
                        .padding(18)
                    }
                    .padding(.horizontal, 16)

                    PayGroupCard {
                        VStack(spacing: 0) {
                            NavigationLink {
                                PayCodePage()
                            } label: {
                                serviceRow(Tr("收付款"), Tr("出示付款码或收款码"), "qrcode", PayVisual.tint)
                            }
                            HairLine(inset: 56)
                            NavigationLink {
                                BillsView()
                            } label: {
                                serviceRow(Tr("我的账单"), Tr("收支明细、月度账单与导出"), "doc.text.magnifyingglass", Color(hex: 0x34C759))
                            }
                            HairLine(inset: 56)
                            NavigationLink {
                                AccountSecurityView()
                            } label: {
                                serviceRow(Tr("支付安全"), Tr("支付密码与安全设置"), "lock.shield.fill", Color(hex: 0xFF9F0A))
                            }
                        }
                    }
                    .padding(.horizontal, 16)

                    transactionFeed

                    if loading {
                        ProgressView().padding(.vertical, 20)
                    }

                    Color.clear.frame(height: max(20, L.safeBottom + 12))
                }
                .padding(.top, 8)
            }
        }
        .background(PayVisual.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .sheet(item: $selectedLedger) { entry in
            ledgerDetail(entry)
        }
        .task {
            async let account = API.shared.me()
            async let ledgerValue = API.shared.ledgerBills(limit: 200)
            app.me = try? await account
            ledger = try? await ledgerValue
            loading = false
        }
    }

    private var identity: some View {
        HStack(spacing: 14) {
            if avatar.isEmpty {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 62, height: 62)
                    .background(
                        LinearGradient(colors: [Color(hex: 0x23C878), Color(hex: 0x0A84FF)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
            } else {
                Avatar(path: avatar, size: 62, radius: 18, circle: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(pf(20, .semibold))
                        .foregroundColor(C.label)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(PayVisual.tint)
                }
                Text(subtitle)
                    .font(pf(13))
                    .foregroundColor(PayVisual.secondaryInk)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(PayVisual.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(PayVisual.separator, lineWidth: 0.8)
        }
        .padding(.horizontal, 16)
    }

    private func stat(_ title: String, _ value: Double, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title).font(pf(12)).foregroundColor(PayVisual.secondaryInk)
            Text("¥" + moneyFmt(abs(value)))
                .font(pfMoney(15, .semibold))
                .foregroundColor(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private func serviceRow(_ title: String, _ detail: String, _ symbol: String, _ tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(pf(16, .medium)).foregroundColor(C.label)
                Text(detail).font(pf(12.5)).foregroundColor(PayVisual.secondaryInk)
            }
            Spacer()
            Chevron(size: 8, line: 1.5, color: PayVisual.secondaryInk)
        }
        .padding(.horizontal, 16)
        .frame(height: 66)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var transactionFeed: some View {
        if let entries = ledger?.entries, !entries.isEmpty {
            LazyVStack(spacing: 12, pinnedViews: [.sectionHeaders]) {
                ForEach(ledgerDays(entries)) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            transactionCard(entry)
                                .padding(.horizontal, 16)
                        }
                    } header: {
                        HStack {
                            Text(dayTitle(group.day))
                                .font(pf(12, .medium))
                                .foregroundColor(PayVisual.secondaryInk)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 5)
                        .background(PayVisual.canvas)
                    }
                }
            }
        } else if !loading {
            VStack(spacing: 10) {
                Image(systemName: "list.bullet.rectangle.portrait")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundColor(PayVisual.secondaryInk)
                Text(Tr("还没有支付消息"))
                    .font(pf(15, .semibold))
                    .foregroundColor(C.label)
                Text(Tr("每一笔收付款、转账、红包和退款都会出现在这里"))
                    .font(pf(12.5))
                    .foregroundColor(PayVisual.secondaryInk)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
        }
    }

    private func transactionCard(_ entry: LedgerBillEntry) -> some View {
        let incoming = entry.direction == "in"
        return Button {
            selectedLedger = entry
        } label: {
            HStack(spacing: 13) {
                Image(systemName: incoming ? "arrow.down.left.circle.fill" : "arrow.up.right.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, incoming ? PayVisual.success : PayVisual.tint)
                    .frame(width: 38, height: 38)
                    .background(
                        (incoming ? PayVisual.success : PayVisual.tint).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.reason.isEmpty ? (incoming ? Tr("收款") : Tr("付款")) : entry.reason)
                        .font(pf(15.5, .medium))
                        .foregroundColor(C.label)
                        .lineLimit(1)
                    Text(clock(entry.at) + " · " + Tr("交易成功"))
                        .font(pf(11.5))
                        .foregroundColor(PayVisual.secondaryInk)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    Text((incoming ? "+" : "-") + "¥" + moneyFmt(abs(entry.delta)))
                        .font(pfMoney(16, .semibold))
                        .foregroundColor(incoming ? PayVisual.success : C.label)
                        .monospacedDigit()
                    Text(Tr("余额") + " ¥" + moneyFmt(entry.after))
                        .font(pf(10.5))
                        .foregroundColor(PayVisual.secondaryInk)
                        .monospacedDigit()
                }

                Chevron(size: 7, line: 1.4, color: PayVisual.secondaryInk)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(PayVisual.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(PayVisual.separator, lineWidth: 0.7)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func ledgerDetail(_ entry: LedgerBillEntry) -> some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("支付消息详情"), back: { selectedLedger = nil })
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        Image(systemName: entry.direction == "in"
                              ? "arrow.down.left.circle.fill" : "arrow.up.right.circle.fill")
                            .font(.system(size: 30, weight: .semibold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, entry.direction == "in"
                                             ? PayVisual.success : PayVisual.tint)
                        Text((entry.direction == "in" ? "+" : "-") + "¥" + moneyFmt(abs(entry.delta)))
                            .font(pfMoney(32, .semibold))
                            .foregroundColor(C.label)
                        Text(entry.reason.isEmpty ? Tr("支付交易") : entry.reason)
                            .font(pf(15))
                            .foregroundColor(PayVisual.secondaryInk)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)

                    PayGroupCard {
                        VStack(spacing: 0) {
                            PayDetailRow(title: Tr("交易时间"), value: TimeFmt.bill(entry.at))
                            HairLine(inset: 18)
                            PayDetailRow(title: Tr("方向"), value: entry.direction == "in" ? Tr("收入") : Tr("支出"))
                            HairLine(inset: 18)
                            PayDetailRow(title: Tr("交易前余额"), value: "¥" + moneyFmt(entry.before))
                            HairLine(inset: 18)
                            PayDetailRow(title: Tr("交易后余额"), value: "¥" + moneyFmt(entry.after))
                            HairLine(inset: 18)
                            PayDetailRow(title: Tr("交易单号"), value: entry.id, copyValue: entry.id)
                            if !entry.ref.isEmpty {
                                HairLine(inset: 18)
                                PayDetailRow(title: Tr("关联单号"), value: entry.ref, copyValue: entry.ref)
                            }
                        }
                    }
                    .padding(.horizontal, 16)

                    Text(Tr("此消息由星言支付自动生成，可作为账本核对凭证。"))
                        .font(pf(11.5))
                        .foregroundColor(PayVisual.secondaryInk)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }
                .padding(.bottom, max(24, L.safeBottom + 12))
            }
        }
        .background(PayVisual.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func ledgerDays(_ entries: [LedgerBillEntry]) -> [LedgerDayGroup] {
        var order: [String] = []
        var map: [String: [LedgerBillEntry]] = [:]
        for entry in entries {
            let day = String(entry.at.prefix(10))
            if map[day] == nil { order.append(day) }
            map[day, default: []].append(entry)
        }
        return order.map { LedgerDayGroup(day: $0, entries: map[$0] ?? []) }
    }

    private func dayTitle(_ day: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: day + "T00:00:00Z") else { return day }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: Lang.isEnglish ? "en_US" : (Lang.isRussian ? "ru_RU" : "zh_CN"))
        formatter.dateFormat = Lang.isEnglish ? "MMM d" : (Lang.isRussian ? "d MMM" : "M月d日")
        return formatter.string(from: date)
    }

    private func clock(_ value: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: value) else { return value }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
