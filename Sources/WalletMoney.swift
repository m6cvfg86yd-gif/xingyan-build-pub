import SwiftUI

struct RechargeView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var amountText = ""
    @State private var banks: [API.WalletBankCard] = []
    @State private var bankId = ""
    @State private var busy = false
    @State private var showAddBank = false
    @State private var showPay = false
    @State private var done = false

    private var amount: Double { Double(amountText) ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("充值"), back: { dismiss() })

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    PayGroupCard {
                        VStack(spacing: 10) {
                            Text(Tr("充值金额"))
                                .font(pf(12.5, .medium))
                                .foregroundColor(PayVisual.secondaryInk)
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                Text("¥").font(pf(24, .semibold)).foregroundColor(C.label)
                                TextField("0.00", text: $amountText)
                                    .font(pfMoney(40, .semibold))
                                    .keyboardType(.decimalPad)
                                    .foregroundColor(C.label)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }

                    HStack(spacing: 10) {
                        ForEach([50, 100, 200, 500], id: \.self) { v in
                            Button {
                                amountText = "\(v)"
                            } label: {
                                Text("¥\(v)")
                                    .font(pf(14.5, .semibold))
                                    .foregroundColor(amount == Double(v) ? .white : C.label)
                                    .frame(maxWidth: .infinity).frame(height: 42)
                                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(amount == Double(v) ? PayVisual.tint : PayVisual.card))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    PayGroupCard {
                        Button {
                            if banks.isEmpty { showAddBank = true }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "creditcard.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(PayVisual.tint)
                                    .frame(width: 34, height: 34)
                                    .background(PayVisual.tint.opacity(0.12),
                                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                Text(Tr("到账银行卡")).font(pf(16)).foregroundColor(C.label)
                                Spacer(minLength: 8)
                                Text(bankLabel).font(pf(14)).foregroundColor(PayVisual.secondaryInk).lineLimit(1)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundColor(PayVisual.secondaryInk.opacity(0.55))
                            }
                            .padding(.horizontal, 16).frame(height: 60)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    Text(Tr("充值是从银行卡转入零钱（本 App 内记账），到账立刻可用。"))
                        .font(pf(12.5)).foregroundColor(PayVisual.secondaryInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)

                    Button { showPay = true } label: {
                        Text(busy ? Tr("处理中…") : Tr("充值"))
                    }
                    .buttonStyle(PayPrimaryButtonStyle(tint: PayVisual.tint, enabled: amount > 0))
                    .disabled(busy || amount <= 0)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, max(28, L.safeBottom))
            }
            .background(PayVisual.canvas)
        }
        .background(PayVisual.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .task { await loadBanks() }
        .sheet(isPresented: $showAddBank) {
            BankAddSheet { list in banks = list; bankId = list.first(where: { $0.isDefault == true })?.id ?? list.first?.id ?? "" }
                .environmentObject(app)
        }
        .sheet(isPresented: $showPay) {
            PayConfirmSheet(title: Tr("充值") + " ¥" + money(amount)) { pwd, face in
                doRecharge(password: pwd, face: face)
            }
            .environmentObject(app)
        }

        .overlay {
            if busy { PayBusyOverlay(text: "正在充值") }
        }
    }

    private var bankLabel: String {
        if let b = banks.first(where: { $0.id == bankId }) { return b.label }
        if let b = banks.first { return b.label }
        return Tr("添加银行卡")
    }

    private func loadBanks() async {
        banks = (try? await API.shared.walletBanks()) ?? []
        if bankId.isEmpty { bankId = banks.first(where: { $0.isDefault == true })?.id ?? banks.first?.id ?? "" }
    }

    private func doRecharge(password: String, face: Bool) {
        busy = true
        Task {
            do {
                let r = try await API.shared.walletRecharge(amount: amount, bankId: bankId)
                await app.refreshAll()
                busy = false
                dismiss()
                if r.pending == true {
                    if let raw = r.checkoutUrl, let url = URL(string: raw), !raw.isEmpty {
                        app.show(Tr("充值订单已创建，请在支付机构完成付款"))
                        openURL(url)
                    } else {
                        app.show(Tr("充值订单已创建，等待支付机构确认"))
                    }
                } else {
                    app.show(Tr("充值成功") + " ¥" + money(amount) + "，" + Tr("零钱") + " ¥" + money(r.balance ?? 0))
                }
            } catch {
                busy = false
                app.show((error as? APIError)?.errorDescription ?? Tr("充值失败"))
            }
        }
    }
}

struct WithdrawView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var amountText = ""
    @State private var banks: [API.WalletBankCard] = []
    @State private var bankId = ""
    @State private var busy = false
    @State private var showAddBank = false

    @State private var showPickBank = false
    @State private var showPay = false
    @State private var ops: [API.WalletOp] = []

    @State private var faq: (String, String)?
    @FocusState private var amountFocused: Bool

    private var amount: Double { Double(amountText) ?? 0 }
    private var balance: Double { app.me?.balance ?? 0 }

    private var fee: Double { amount <= 0 ? 0 : max(0.1, (amount * 0.001 * 100).rounded() / 100) }

    private var net: Double { max(0, amount - fee) }
    private var picked: API.WalletBankCard? { banks.first(where: { $0.id == bankId }) }

    var body: some View {
        VStack(spacing: 0) {

            NavBar(title: Tr("零钱提现"), back: { dismiss() })

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {

                    PayGroupCard {
                        Button {
                            if banks.isEmpty { showAddBank = true } else { showPickBank = true }
                        } label: {
                            HStack(spacing: 12) {
                                Text(Tr("提现到")).font(pf(16)).foregroundColor(C.label)
                                Spacer(minLength: 6)
                                HStack(spacing: 7) {
                                    bankBadge(picked?.bank ?? "")
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(picked.map { ($0.bank ?? Tr("银行卡")) + Tr("储蓄卡") }
                                             ?? Tr("添加银行卡"))
                                            .font(pf(15.5)).foregroundColor(C.label).lineLimit(1)
                                        Text(picked.map { Tr("尾号 ") + ($0.tail ?? "****") } ?? "")
                                            .font(pf(12.5)).foregroundColor(PayVisual.secondaryInk)
                                    }
                                }
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundColor(PayVisual.secondaryInk.opacity(0.55))
                            }
                            .padding(.horizontal, 16).frame(height: 68)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        HairLine(inset: 16)
                        HStack(spacing: 6) {
                            Image(systemName: "clock")
                                .font(.system(size: 12))
                                .foregroundColor(PayVisual.secondaryInk)
                            Text(Tr("预计 2 小时内到账（以银行处理时间为准）"))
                                .font(pf(12.5)).foregroundColor(PayVisual.secondaryInk)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 42)
                    }

                    PayGroupCard {
                        VStack(spacing: 0) {
                            VStack(spacing: 8) {
                                Text(Tr("提现金额"))
                                    .font(pf(12.5, .medium))
                                    .foregroundColor(PayVisual.secondaryInk)
                                HStack(alignment: .firstTextBaseline, spacing: 5) {
                                    Text("¥").font(pf(24, .semibold)).foregroundColor(C.label)
                                    TextField("0.00", text: $amountText)
                                        .font(pfMoney(38, .semibold))
                                        .keyboardType(.decimalPad)
                                        .foregroundColor(C.label)
                                        .focused($amountFocused)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 22)

                            HairLine(inset: 18)
                            HStack {
                                Text(Tr("可用余额"))
                                    .font(pf(13.5))
                                    .foregroundColor(PayVisual.secondaryInk)
                                Spacer()
                                Text("¥" + money(balance))
                                    .font(pf(13.5, .medium))
                                    .foregroundColor(PayVisual.secondaryInk)
                                Button {
                                    amountText = String(format: "%.2f", max(0, balance))
                                    amountFocused = false
                                } label: {
                                    Text(Tr("全部提现"))
                                        .font(pf(13.5, .semibold))
                                        .foregroundColor(PayVisual.tint)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 18)
                            .frame(height: 48)
                        }
                    }

                    PayGroupCard {
                        VStack(spacing: 0) {
                            if amount > 0 {
                                HStack {
                                    Text(Tr("服务费（0.1%，最低 ¥0.1）"))
                                    Spacer()
                                    Text("¥" + money(fee))
                                }
                                HairLine(inset: 18)
                                HStack {
                                    Text(Tr("实际到账"))
                                    Spacer()
                                    Text("¥" + money(net))
                                        .foregroundColor(PayVisual.success)
                                }
                                HairLine(inset: 18)
                            }
                            HStack {
                                Text(Tr("单笔限额"))
                                Spacer()
                                Text("¥50,000.00")
                            }
                        }
                        .font(pf(13.5))
                        .foregroundColor(PayVisual.secondaryInk)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 46)
                    }

                    Button { showPay = true } label: {
                        Text(busy ? Tr("处理中…") : Tr("提现"))
                    }
                    .buttonStyle(PayPrimaryButtonStyle(tint: PayVisual.tint, enabled: canWithdraw))
                    .disabled(busy || !canWithdraw)

                    PayGroupCard {
                        VStack(spacing: 0) {
                            faqRow(Tr("提现多久能到账？"),
                                   Tr("一般 2 小时内到账，具体以银行处理时间为准。遇到节假日可能稍慢。")) {
                                faq = (Tr("提现多久能到账？"),
                                       Tr("一般 2 小时内到账，具体以银行处理时间为准。遇到节假日可能慢一些。\n如果超过 24 小时还没到账，把提现记录截图发给管理员查。"))
                            }
                            HairLine(inset: 18)
                            faqRow(Tr("提现要手续费吗？"),
                                   Tr("按提现金额的 0.1% 收取，最低 ¥0.1。")) {
                                faq = (Tr("提现要手续费吗？"),
                                       Tr("按提现金额的 0.1% 收取，最低 ¥0.1，从提现金额里直接扣。\n（这也是微信零钱提现的规则。）"))
                            }
                        }
                    }

                    if !ops.isEmpty {
                        PaySectionLabel(text: Tr("提现记录"))
                        PayGroupCard {
                            ForEach(ops.indices, id: \.self) { i in
                                let o = ops[i]
                                if i > 0 { HairLine(inset: 16) }
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("¥" + money(o.amount ?? 0)).font(pf(16)).foregroundColor(C.label)
                                        Text((o.bankText ?? "") + " · " + (o.createdAt ?? "").prefix(16))
                                            .font(pf(12)).foregroundColor(PayVisual.secondaryInk).lineLimit(1)
                                    }
                                    Spacer(minLength: 8)
                                    Text(statusText(o.status))
                                        .font(pf(13))
                                        .foregroundColor(o.status == "pending" ? C.orange : C.green)
                                }
                                .padding(.horizontal, 16).frame(height: 60)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, max(28, L.safeBottom))
            }
            .background(PayVisual.canvas)
        }
        .background(PayVisual.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .task {
            banks = (try? await API.shared.walletBanks()) ?? []
            bankId = banks.first(where: { $0.isDefault == true })?.id ?? banks.first?.id ?? ""
            ops = (try? await API.shared.walletOps()) ?? []
        }
        .sheet(isPresented: $showAddBank) {
            BankAddSheet { list in banks = list; bankId = list.first?.id ?? "" }
                .environmentObject(app)
        }

        .sheet(isPresented: $showPickBank) { bankPicker }
        .sheet(isPresented: $showPay) {
            PayConfirmSheet(title: Tr("提现") + " ¥" + money(amount)) { pwd, face in
                doWithdraw(password: pwd, face: face)
            }
            .environmentObject(app)
        }

        .overlay {
            if busy { PayBusyOverlay(text: "正在提现") }
        }
        .alert(faq?.0 ?? "", isPresented: Binding(get: { faq != nil }, set: { if !$0 { faq = nil } })) {
            Button(Tr("知道了"), role: .cancel) { faq = nil }
        } message: {
            Text(faq?.1 ?? "")
        }
        .onAppear {

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { amountFocused = true }
        }
    }

    private func bankBadge(_ bank: String) -> some View {
        let ch = bank.isEmpty ? "卡" : String(bank.prefix(1))
        return Text(ch)
            .font(pf(14, .medium))
            .foregroundColor(.white)
            .frame(width: 28, height: 28)
            .background(Circle().fill(bankColor(bank)))
    }

    private func bankColor(_ bank: String) -> Color {
        if bank.contains("工商") { return Color(hex: 0xC0392B) }
        if bank.contains("建设") { return Color(hex: 0x1F5FBF) }
        if bank.contains("农业") { return Color(hex: 0x2E9B5B) }
        if bank.contains("中国银行") { return Color(hex: 0xB3282E) }
        if bank.contains("招商") { return Color(hex: 0xC7302C) }
        if bank.contains("交通") { return Color(hex: 0x1D4E9B) }
        if bank.contains("邮储") || bank.contains("邮政") { return Color(hex: 0x2B7A3D) }
        return Color(hex: 0x8A8A8E)
    }

    private func faqRow(_ q: String, _ a: String, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 8) {
                Text(q).font(pf(13.5)).foregroundColor(C.link)
                Spacer(minLength: 8)
                Chevron(size: 8, line: 1.4)
            }
            .padding(.horizontal, 20).frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var bankPicker: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("选择到账银行卡"), back: { showPickBank = false })
            ScrollView {
                VStack(spacing: 0) {
                    GroupCard {
                        ForEach(banks) { b in
                            Button {
                                bankId = b.id
                                showPickBank = false
                            } label: {
                                HStack(spacing: 12) {
                                    bankBadge(b.bank ?? "")
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text((b.bank ?? Tr("银行卡")) + Tr("储蓄卡"))
                                            .font(pf(16)).foregroundColor(C.label)
                                        Text(Tr("尾号 ") + (b.tail ?? "****"))
                                            .font(pf(12.5)).foregroundColor(C.subLabel)
                                    }
                                    Spacer(minLength: 8)
                                    if b.id == bankId {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(C.green)
                                    }
                                }
                                .padding(.horizontal, 16).frame(height: 64)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            HairLine(inset: 16)
                        }
                        Button {
                            showPickBank = false
                            showAddBank = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 17)).foregroundColor(C.green)
                                Text(Tr("添加银行卡")).font(pf(16)).foregroundColor(C.label)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 16).frame(height: 56)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 10)
                    Text(Tr("到账时间：预计 2 小时内（以银行处理时间为准）"))
                        .font(pf(12.5)).foregroundColor(C.subLabel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 22).padding(.top, 10)
                }
            }
            .background(PayVisual.canvas)
        }
        .background(PayVisual.canvas.ignoresSafeArea())

        .swipeBack { showPickBank = false }
    }

    private var canWithdraw: Bool { amount >= 1 && amount + fee <= balance && !bankId.isEmpty }

    private func statusText(_ s: String?) -> String {
        switch s {
        case "done": return Tr("已到账")
        case "failed": return Tr("提现失败")
        default: return Tr("处理中")
        }
    }

    private func doWithdraw(password: String, face: Bool) {
        busy = true
        Task {
            do {
                let r = try await API.shared.walletWithdraw(amount: amount, bankId: bankId,
                                                            password: password, face: face)
                await app.refreshAll()
                ops = (try? await API.shared.walletOps()) ?? ops
                amountText = ""
                busy = false
                app.show(Tr("提现申请已提交") + "：" + (r.expect ?? "") + "（" + Tr("服务费") + " ¥" + money(r.fee ?? 0) + "）")
            } catch {
                busy = false
                app.show((error as? APIError)?.errorDescription ?? Tr("提现失败"))
            }
        }
    }
}

struct BankAddSheet: View {
    var onAdded: ([API.WalletBankCard]) -> Void

    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var bank = ""
    @State private var cardNo = ""
    @State private var holder = ""
    @State private var busy = false

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("添加银行卡"), back: { dismiss() }) {
                Button { save() } label: {
                    Text(busy ? Tr("保存中…") : Tr("完成"))
                        .font(pf(17)).foregroundColor(cardNo.count >= 12 ? C.green : C.subLabel)
                        .frame(height: L.navH).padding(.trailing, 16)
                }
                .buttonStyle(.plain)
                .disabled(busy || cardNo.count < 12)
            }
            GroupCard {
                field(Tr("开户银行"), $bank, "招商银行")
                HairLine(inset: 16)
                field(Tr("卡号"), $cardNo, "6225 8801 2345 6789")
                HairLine(inset: 16)
                field(Tr("姓名"), $holder, "")
            }
            .padding(.top, 12)
            Text(Tr("出于安全考虑，服务器只保存银行名和卡号后四位，完整卡号不落盘。"))
                .font(pf(12.5)).foregroundColor(C.subLabel)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22).padding(.top, 10)
            Spacer()
        }
        .background(PayVisual.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .hidesTabBar()

        .swipeBack { dismiss() }
    }

    private func field(_ title: String, _ text: Binding<String>, _ ph: String) -> some View {
        HStack(spacing: 12) {
            Text(title).font(pf(16)).foregroundColor(C.label).frame(width: 84, alignment: .leading)
            TextField(ph, text: text)
                .font(pf(16)).foregroundColor(C.label)
                .keyboardType(title == Tr("卡号") ? .numberPad : .default)
        }
        .padding(.horizontal, 16).frame(height: 54)
    }

    private func save() {
        busy = true
        Task {
            do {
                let list = try await API.shared.addBank(bank: bank, cardNo: cardNo, holder: holder)
                onAdded(list)
                busy = false
                dismiss()
                app.show(Tr("银行卡已添加"))
            } catch {
                busy = false
                app.show((error as? APIError)?.errorDescription ?? Tr("添加失败"))
            }
        }
    }
}

struct PayConfirmSheet: View {
    var title: String
    var onConfirm: (String, Bool) -> Void

    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var pwd = ""
    @State private var hasPay = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundColor(PayVisual.secondaryInk.opacity(0.55))
                        .frame(width: 44, height: L.navH)
                }
                .buttonStyle(.plain)
                Spacer()
                Text(Tr("确认支付"))
                    .font(pf(16.5, .semibold))
                    .foregroundColor(C.label)
                Spacer()
                Spacer().frame(width: 44)
            }
            .frame(height: L.navH)

            VStack(spacing: 12) {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(PayVisual.tint)
                    .frame(width: 62, height: 62)
                    .background(PayVisual.tint.opacity(0.12), in: Circle())
                Text(title)
                    .font(pf(24, .semibold))
                    .foregroundColor(C.label)
                    .multilineTextAlignment(.center)
                Text(Tr("请验证支付密码完成付款"))
                    .font(pf(13.5))
                    .foregroundColor(PayVisual.secondaryInk)
            }
            .padding(.top, 24)

            PayGroupCard {
                VStack(spacing: 0) {
                    HStack {
                        Label(Tr("支付密码"), systemImage: "lock.fill")
                            .font(pf(15, .medium))
                            .foregroundColor(C.label)
                        Spacer()
                        Text(Tr("6 位安全密码"))
                            .font(pf(12.5))
                            .foregroundColor(PayVisual.secondaryInk)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 16)

                    PayDotField(count: pwd.count, height: 50)
                        .contentShape(Rectangle())
                        .onTapGesture { focused = true }
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 16)

                    TextField("", text: $pwd)
                        .keyboardType(.numberPad)
                        .focused($focused)
                        .frame(height: 1)
                        .opacity(0.01)
                        .onChange(of: pwd) { value in
                            let clean = String(value.filter(\.isNumber).prefix(6))
                            if clean != value { pwd = clean }
                        }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)

            if Biometrics.available {
                Button {
                    dismiss()
                    onConfirm("", true)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "faceid")
                        Text(Tr("使用面容"))
                    }
                    .font(pf(15.5, .semibold)).foregroundColor(PayVisual.tint)
                }
                .buttonStyle(.plain)
                .padding(.top, 22)
            }

            Button {
                dismiss()
                onConfirm(pwd, false)
            } label: {
                Text(Tr("确认支付"))
            }
            .buttonStyle(PayPrimaryButtonStyle(tint: PayVisual.tint, enabled: pwd.count >= 6))
            .disabled(pwd.count < 6)
            .padding(.horizontal, 20)
            .padding(.top, 24)
            Spacer()
        }
        .background(PayVisual.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .hidesTabBar()
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { focused = true }
        }
    }
}
