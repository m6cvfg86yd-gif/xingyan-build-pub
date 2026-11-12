import SwiftUI

struct BalancePageView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var realtime = Realtime.shared

    @State private var cfg: BalancePageConfig?
    @State private var showBills = false
    @State private var showRecharge = false
    @State private var rechargeAmount = ""
    @State private var showWithdraw = false
    @State private var showFaq = false

    @State private var showFaqPage = false
    @State private var showUpgrade = false
    @State private var faqAnswer: String?

    @State private var needReal = false

    private var st: BalanceStyle { cfg?.style ?? BalanceStyle() }

    var body: some View {
        VStack(spacing: 0) {

            NavBar(title: cfg?.navTitle ?? "零钱明细", back: { dismiss() })

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    top
                    bottom
                    Spacer(minLength: 20)
                }
                .padding(.top, 20)
            }
            .background(PayVisual.canvas)
        }
        .background(PayVisual.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .navigationDestination(isPresented: $showBills) { BillsView() }

        .navigationDestination(isPresented: $showRecharge) {
            RechargeView().environmentObject(app)
        }

        .navigationDestination(isPresented: $showWithdraw) {
            WithdrawView().environmentObject(app)
        }
        .confirmationDialog(Tr("常见问题"), isPresented: $showFaq, titleVisibility: .visible) {
            ForEach((cfg?.faq ?? []).indices, id: \.self) { i in
                Button(cfg!.faq![i].q) { faqAnswer = cfg!.faq![i].a }
            }
            Button(Tr("关闭"), role: .cancel) { }
        }
        .sheet(isPresented: $showFaqPage) {
            FAQView().environmentObject(app)
        }
        .sheet(isPresented: $showUpgrade) {
            WalletUpgradeView().environmentObject(app)
        }
        .alert(Tr("常见问题"), isPresented: Binding(get: { faqAnswer != nil }, set: { if !$0 { faqAnswer = nil } })) {
            Button(Tr("知道了"), role: .cancel) { faqAnswer = nil }
        } message: {
            Text(faqAnswer ?? "")
        }
        .task { await load() }
        .onChange(of: realtime.event) { ev in
            if ev.type == "balance" || ev.type == "transfer" || ev.type == "ui" { Task { await load() } }
        }

        .overlay {
            if needReal {
                NeedRealNameView { dismiss() }
                    .environmentObject(app)
            }
        }
    }

    private var top: some View {
        VStack(spacing: 12) {
            PayGroupCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label(cfg?.title ?? Tr("我的零钱"), systemImage: "wallet.bifold.fill")
                            .font(pf(15, .medium))
                            .foregroundColor(PayVisual.secondaryInk)
                        Spacer()
                        PayStatusPill(
                            text: (cfg?.isLocked ?? false) ? Tr("待实名") : Tr("可用"),
                            tone: (cfg?.isLocked ?? false) ? .warning : .success
                        )
                    }

                    MoneyLabel(text: (cfg?.isLocked ?? false)
                               ? "¥****"
                               : money(cfg?.balance ?? app.me?.balance ?? 0),
                               size: 40, curSize: 24, topAlign: true,
                               color: C.label, weight: .semibold)
                        .monospacedDigit()

                    if let note = cfg?.note, !note.isEmpty {
                        Text(note)
                            .font(pf(13))
                            .foregroundColor(PayVisual.secondaryInk)
                    }
                }
                .padding(20)
            }

            if cfg?.isLocked ?? false {
                Button {
                    app.show(Tr("请先完成实名认证"))
                    RealNameGate.shared.prompt()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.system(size: 17, weight: .semibold))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Tr("完成实名认证后使用零钱"))
                                .font(pf(14, .semibold))
                            Text(Tr("按国家规定，实名后才能查看和使用钱包金额"))
                                .font(pf(12))
                                .foregroundColor(PayVisual.secondaryInk)
                        }
                        Spacer(minLength: 6)
                        Text(Tr("去认证"))
                            .font(pf(13.5, .semibold))
                            .foregroundColor(PayVisual.warning)
                    }
                    .foregroundColor(C.label)
                    .padding(16)
                    .background(Color.dyn(0xFFF7E6, 0x2D2417))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
    }

    private var bottom: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Button {
                    run(cfg?.recharge?.action ?? "recharge", cfg?.recharge?.label ?? "充值")
                } label: {
                    Label(cfg?.recharge?.label ?? Tr("充值"), systemImage: "plus")
                }
                .buttonStyle(PayPrimaryButtonStyle(tint: PayVisual.tint))

                Button {
                    run(cfg?.withdraw?.action ?? "withdraw", cfg?.withdraw?.label ?? "提现")
                } label: {
                    Label(cfg?.withdraw?.label ?? Tr("提现"), systemImage: "arrow.up.to.line")
                }
                .buttonStyle(PaySecondaryButtonStyle(tint: PayVisual.tint))
            }

            PayGroupCard {
                VStack(spacing: 0) {
                    ForEach(Array((cfg?.links ?? []).filter { $0.enabled != false }.enumerated()),
                            id: \.element.id) { idx, l in
                        Button {
                            run(l.action ?? "soon", l.label)
                        } label: {
                            HStack {
                                Text(Tr(l.label))
                                    .font(pf(15.5))
                                    .foregroundColor(C.label)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundColor(PayVisual.secondaryInk.opacity(0.55))
                            }
                            .padding(.horizontal, 18)
                            .frame(height: 52)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if idx < ((cfg?.links ?? []).filter { $0.enabled != false }.count - 1) {
                            HairLine(inset: 18)
                        }
                    }
                }
            }

            if let f = cfg?.footer, !f.isEmpty {
                Text(f)
                    .font(pf(12))
                    .foregroundColor(PayVisual.secondaryInk)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 20)
    }

    private func run(_ action: String, _ label: String) {
        switch action {
        case "recharge": rechargeAmount = ""; showRecharge = true

        case "bills": if UIConfig.num("billsShow", 1) > 0 { showBills = true }
        case "withdraw": showWithdraw = true

        case "faq": showFaqPage = true
        case "upgrade": showUpgrade = true
        default: app.show("「\(label)」还没接后端，先把页面做出来")
        }
    }

    private func money(_ v: Double) -> String { "¥" + moneyFmt(v) }

    private func load() async {
        do {
            cfg = try await API.shared.balancePage()
        } catch let e as APIError {

            if case .needRealName = e { needReal = true; return }
        } catch { }
    }
}
