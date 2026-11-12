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

struct StarPayAmount: View {
    enum Role {
        case hero, metric, row, detail, sheet

        var size: CGFloat {
            switch self {
            case .hero: return 46
            case .metric: return 16
            case .row: return 17
            case .detail: return 36
            case .sheet: return 42
            }
        }

        var symbolSize: CGFloat {
            (size * 0.48).rounded()
        }

        var fractionSize: CGFloat {
            (size * 0.72).rounded()
        }

        var weight: Font.Weight {
            switch self {
            case .hero, .detail, .sheet: return .semibold
            case .metric, .row: return .semibold
            }
        }

        var tracking: CGFloat {
            switch self {
            case .hero, .detail, .sheet: return -0.55
            default: return 0
            }
        }

        var symbolLift: CGFloat {
            ((size - symbolSize) * 0.62).rounded()
        }

        var uiWeight: UIFont.Weight {
            switch weight {
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            default: return .regular
            }
        }
    }

    let value: Double
    var role: Role = .row
    var color: Color = C.label
    var sign = ""

    var body: some View {
        let text = moneyFmt(abs(value.isFinite ? value : 0))
        let parts = text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let integer = parts.first.map(String.init) ?? "0"
        let fraction = parts.count > 1 ? String(parts[1]) : "00"
        let scale = max(0.85, fontScale)

        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(sign + "¥")
                .font(.system(size: max(9, (role.symbolSize * scale).rounded()),
                              weight: role.weight))
                .baselineOffset(role.symbolLift)
            Text(integer)
                .font(Font(UIFont.monospacedDigitSystemFont(
                    ofSize: max(9, (role.size * scale).rounded()),
                    weight: role.uiWeight
                )))
                .tracking(role.tracking)
                .layoutPriority(1)
            Text("." + fraction)
                .font(Font(UIFont.monospacedDigitSystemFont(
                    ofSize: max(9, (role.fractionSize * scale).rounded()),
                    weight: role.uiWeight
                )))
                .tracking(role.tracking * 0.5)
        }
        .foregroundStyle(color)
        .lineLimit(1)
        .minimumScaleFactor(0.62)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sign + "¥" + moneyFmt(abs(value.isFinite ? value : 0)))
    }
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
    @Environment(\.scenePhase) private var scenePhase
    @State private var ledger: LedgerBillsPayload?
    @State private var loading = true
    @State private var selectedLedger: LedgerBillEntry?
    @State private var balanceVisible = false
    @State private var faceBusy = false

    private var balance: Double { app.me?.balance ?? ledger?.balance ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: name, back: { dismiss() })

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 18) {
                    paymentHero
                    ledgerSummaryStrip
                    quickActions

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
        .onChange(of: scenePhase) { phase in
            if phase != .active {
                balanceVisible = false
            }
        }
    }

    private var paymentHero: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0x060607), Color(hex: 0x17191C), Color(hex: 0x09090A)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.08),
                            .init(color: .white.opacity(0.075), location: 0.46),
                            .init(color: .clear, location: 0.65)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blendMode(.screen)

            Circle()
                .fill(.white.opacity(0.030))
                .frame(width: 260, height: 260)
                .blur(radius: 62)
                .offset(x: 176, y: -125)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 11) {
                    Group {
                        if avatar.isEmpty {
                            Image(systemName: "star.fill")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(.black)
                        } else {
                            Avatar(path: avatar, size: 36, radius: 18, circle: true)
                        }
                    }
                    .frame(width: 36, height: 36)
                    .background(.white, in: Circle())
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(pf(15.5, .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text("STAR PAY")
                            .font(pfExact(9.5, .bold))
                            .tracking(1.8)
                            .foregroundStyle(.white.opacity(0.52))
                    }

                    Spacer(minLength: 8)

                    HStack(spacing: 5) {
                        Image(systemName: ledger?.verified == true
                              ? "checkmark.shield.fill" : "clock.badge.questionmark")
                        Text(ledger?.verified == true ? Tr("账本已核对") : Tr("账本待核对"))
                    }
                    .font(pf(11, .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(.white.opacity(0.10), in: Capsule())
                }

                Spacer(minLength: 22)

                Button {
                    toggleBalancePrivacy()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Tr("可用余额"))
                            .font(pf(12.5, .medium))
                            .foregroundStyle(.white.opacity(0.56))

                        Group {
                            if balanceVisible {
                                StarPayAmount(value: balance, role: .hero, color: .white)
                            } else {
                                HStack(alignment: .firstTextBaseline, spacing: 0) {
                                    Text("¥")
                                        .font(moneySymbolFont(17, .bold))
                                        .baselineOffset(13)
                                    Text(" ********")
                                        .font(pfMoney(39, .bold))
                                        .tracking(1.2)
                                }
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            }
                        }
                        .padding(.top, 3)

                        HStack(spacing: 5) {
                            if faceBusy {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.65)
                                    .frame(width: 14, height: 14)
                            } else {
                                Image(systemName: balanceVisible ? "checkmark.shield.fill" : "faceid")
                            }
                            Text(balanceVisible ? Tr("已在本次页面验证") : Tr("轻点使用面容 ID 查看"))
                        }
                        .font(pf(10.5, .medium))
                        .foregroundStyle(.white.opacity(0.48))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 16)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(XYPay.cardLine)
                            .font(pf(10.5, .medium))
                            .foregroundStyle(.white.opacity(0.46))
                        Text("STAR PAY")
                            .font(pfExact(8.5, .bold))
                            .tracking(1.6)
                            .foregroundStyle(.white.opacity(0.27))
                    }
                    Spacer()
                    Image(systemName: "wave.3.right.circle.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white.opacity(0.30))
                }
            }
            .padding(22)
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.22), .white.opacity(0.045),
                                 .white.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.9
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 27.2, style: .continuous)
                .stroke(.white.opacity(0.035), lineWidth: 0.6)
        }
        .shadow(color: .black.opacity(0.28), radius: 22, y: 12)
        .padding(.horizontal, 16)
    }

    private func toggleBalancePrivacy() {
        if balanceVisible {
            balanceVisible = false
            return
        }
        guard !faceBusy else { return }
        faceBusy = true
        let reason: String
        if Lang.isEnglish {
            reason = "Authenticate to view your Balance"
        } else if Lang.isRussian {
            reason = "Подтвердите личность, чтобы увидеть баланс"
        } else {
            reason = "验证身份，查看零钱余额"
        }
        Task {
            let result = await Biometrics.authenticate(reason: reason)
            faceBusy = false
            if result.ok {
                balanceVisible = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                balanceVisible = false
                if !result.message.isEmpty {
                    app.show(result.message)
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }

    private var quickActions: some View {
        PayGroupCard {
            HStack(spacing: 0) {
                NavigationLink {
                    PayCodePage()
                } label: {
                    quickAction(Tr("收付款"), "qrcode", PayVisual.tint)
                }
                actionDivider
                NavigationLink {
                    BillsView()
                } label: {
                    quickAction(Tr("账单"), "doc.text.magnifyingglass", PayVisual.success)
                }
                actionDivider
                NavigationLink {
                    AccountSecurityView()
                } label: {
                    quickAction(Tr("支付安全"), "lock.shield.fill", PayVisual.warning)
                }
                actionDivider
                NavigationLink {
                    VirtualCardView()
                } label: {
                    quickAction(Tr("虚拟卡"), "creditcard.fill", PayVisual.gold)
                }
            }
            .padding(.vertical, 16)
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var ledgerSummaryStrip: some View {
        if let ledger {
            HStack(spacing: 18) {
                summaryMetric(Tr("收入"), ledger.income, PayVisual.success)
                Rectangle()
                    .fill(PayVisual.separator)
                    .frame(width: 0.5, height: 28)
                summaryMetric(Tr("支出"), ledger.expense, C.label)
            }
            .padding(.horizontal, 22)
        }
    }

    private func summaryMetric(_ title: String, _ value: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(pf(10.5, .medium))
                .foregroundStyle(PayVisual.secondaryInk)
            if balanceVisible {
                StarPayAmount(value: value, role: .metric, color: color)
            } else {
                Text("¥ ***")
                    .font(pfMoney(13.5, .semibold))
                    .foregroundStyle(PayVisual.secondaryInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionDivider: some View {
        Rectangle()
            .fill(PayVisual.separator)
            .frame(width: 0.5, height: 48)
    }

    private func quickAction(_ title: String, _ symbol: String, _ tint: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 46, height: 46)
                .background(tint.opacity(0.12), in: Circle())
            Text(title)
                .font(pf(11.5, .medium))
                .foregroundStyle(C.label)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var transactionFeed: some View {
        if let entries = ledger?.entries, !entries.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Tr("最近交易"))
                        .font(pf(22, .bold))
                        .foregroundStyle(C.label)
                    Spacer()
                    Text("\(entries.count)")
                        .font(pfMoney(12.5, .medium))
                        .foregroundStyle(PayVisual.secondaryInk)
                        .monospacedDigit()
                }
                .padding(.horizontal, 4)

                ForEach(ledgerDays(entries)) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(dayTitle(group.day))
                            .font(pf(13, .semibold))
                            .foregroundStyle(PayVisual.secondaryInk)
                            .padding(.horizontal, 4)

                        PayGroupCard {
                            VStack(spacing: 0) {
                                ForEach(Array(group.entries.enumerated()),
                                        id: \.element.id) { index, entry in
                                    transactionRow(entry)
                                    if index < group.entries.count - 1 {
                                        HairLine(inset: 58)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
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

    private func transactionRow(_ entry: LedgerBillEntry) -> some View {
        let incoming = entry.direction == "in"
        return Button {
            selectedLedger = entry
        } label: {
            HStack(spacing: 12) {
                Image(systemName: incoming ? "arrow.down.left.circle.fill" : "arrow.up.right.circle.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, incoming ? PayVisual.success : PayVisual.tint)
                    .frame(width: 36, height: 36)
                    .background(
                        (incoming ? PayVisual.success : PayVisual.tint).opacity(0.12),
                        in: Circle()
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.reason.isEmpty ? (incoming ? Tr("收款") : Tr("付款")) : entry.reason)
                        .font(pf(15.5, .semibold))
                        .foregroundColor(C.label)
                        .lineLimit(1)
                    Text(clock(entry.at) + " · " + Tr("交易成功"))
                        .font(pf(11.5, .medium))
                        .foregroundColor(PayVisual.secondaryInk)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    StarPayAmount(value: entry.delta,
                                  role: .row,
                                  color: incoming ? PayVisual.success : C.label,
                                  sign: incoming ? "+" : "-")
                    Text(Tr("余额") + " ¥" + moneyFmt(entry.after))
                        .font(pf(10.5, .medium))
                        .foregroundColor(PayVisual.secondaryInk)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 66)
            .contentShape(Rectangle())
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
                        StarPayAmount(value: entry.delta,
                                      role: .detail,
                                      color: C.label,
                                      sign: entry.direction == "in" ? "+" : "-")
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
