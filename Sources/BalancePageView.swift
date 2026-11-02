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
                VStack(spacing: 0) {
                    top
                    Spacer(minLength: 40)
                    bottom
                }
                .frame(minHeight: 912 - L.safeTop - L.navH - L.safeBottom - 20, alignment: .top)
            }
            .background(st.pageBg)
        }
        .background(st.pageBg.ignoresSafeArea())
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
        VStack(spacing: 0) {

            ZStack {
                Circle().fill(st.circleColorV)
                Text("¥")
                    .font(pfMoney(st.yenFont))
                    .foregroundColor(st.yenColorV)
            }
            .frame(width: st.circle, height: st.circle)
            .padding(.top, st.topPad)

            Text(cfg?.title ?? "我的零钱")
                .font(pf(st.titleFont))
                .foregroundColor(Color.dyn(0x000000, 0xEDEDED))
                .padding(.top, st.gapTitleV)

            MoneyLabel(text: (cfg?.isLocked ?? false) ? "¥****" : money(cfg?.balance ?? app.me?.balance ?? 0),
                       size: st.amountFont, curSize: st.curFont, topAlign: true,
                       color: Color.dyn(0x000000, 0xEDEDED))
                .padding(.top, st.gapAmountV)

            if cfg?.isLocked ?? false {
                Button {
                    app.show(Tr("请先完成实名认证"))
                    RealNameGate.shared.prompt()
                } label: {
                    HStack(spacing: 4) {
                        Text(Tr("按国家规定，完成实名认证后才能查看和使用零钱"))
                            .font(pf(max(12, st.noteFont - 1)))
                            .foregroundColor(Color(hex: 0xE6A23C))
                        Text(Tr("去认证")).font(pf(max(12, st.noteFont - 1), .medium)).foregroundColor(C.green)
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, st.gapNoteV)
            }
            if let note = cfg?.note, !note.isEmpty {
                HStack(spacing: 4) {
                    Text(note).font(pf(st.noteFont)).foregroundColor(st.noteColorV)
                    Chevron(size: 6, line: 1.4, color: st.noteColorV)
                }
                .padding(.top, st.gapNoteV)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var bottom: some View {
        VStack(spacing: 0) {
            Button {
                run(cfg?.recharge?.action ?? "recharge", cfg?.recharge?.label ?? "充值")
            } label: {
                Text(cfg?.recharge?.label ?? "充值")
                    .font(pf(17))
                    .foregroundColor(st.rechargeInkV)
                    .frame(width: st.btnW, height: st.btnH)
                    .background(RoundedRectangle(cornerRadius: st.btnR, style: .continuous).fill(st.rechargeBgV))
            }
            .buttonStyle(.plain)

            Button {
                run(cfg?.withdraw?.action ?? "withdraw", cfg?.withdraw?.label ?? "提现")
            } label: {
                Text(cfg?.withdraw?.label ?? "提现")
                    .font(pf(17))
                    .foregroundColor(st.withdrawInkV)
                    .frame(width: st.btnW, height: st.btnH)
                    .background(RoundedRectangle(cornerRadius: st.btnR, style: .continuous).fill(st.withdrawBgV))
            }
            .buttonStyle(.plain)
            .padding(.top, 16)

            HStack(spacing: 15) {
                ForEach((cfg?.links ?? []).filter { $0.enabled != false }) { l in
                    Button {
                        run(l.action ?? "soon", l.label)
                    } label: {
            Text(Tr(l.label)).font(pf(st.linkFont)).foregroundColor(st.linkColorV)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 71)

            if let f = cfg?.footer, !f.isEmpty {
                Text(f)
                    .font(pf(st.footFont))
                    .foregroundColor(st.footerColorV)
                    .padding(.top, 10)
            }
            Color.clear.frame(height: 25)
        }
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
