import SwiftUI
import UIKit

struct TransferView: View {
    let chat: Chat

    var onPaid: () -> Void = {}

    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var digits = ""
    @State private var note = ""
    @State private var noteEditing = false
    @State private var method = "balance"
    @State private var showPay = false
    @State private var showMethod = false
    @State private var password = ""
    @State private var hasPwd = false
    @State private var busy = false
    @State private var step = 0
    @State private var doneAmount: Double = 0
    @State private var receipt: API.TransferReceipt?

    @State private var showBills = false
    @State private var showPayHelp = false
    @State private var payHint: String?
    @State private var badPwd = false

    @State private var needFaceForRisk = false
    @State private var caretOn = true

    @State private var faceOK = false

    @State private var peerRealName = ""

    private var amount: Double { Double(digits) ?? 0 }
    private var peerAvatar: String { chat.avatar ?? "" }

    private var peerTitle: String {
        let masked = peerRealName.trimmingCharacters(in: .whitespaces)
        if masked.isEmpty { return chat.name }
        return chat.name + "（" + masked + "）"
    }
    private var balance: Double { app.me?.balance ?? 0 }
    private var methodName: String {
        method == "xypay" ? XYPay.name : Tr("星言零钱")
    }
    private var methodSub: String {
        (method == "xypay" ? XYPay.cardLine + " · " : "") + Tr("可用") + " ¥" + money(balance)
    }

    var body: some View {
        ZStack {

            PayVisual.canvas.ignoresSafeArea()

            if step == 1 {
                resultPage
            } else {
                mainPage
            }

            if busy {
                ZStack {
                    Color.black.opacity(0.15).ignoresSafeArea()
                    ProgressView().padding(18)
                        .background { CardGlassBox(radius: 10) }
                }
                .zIndex(30)
            }

            if showPay {
                payLayer.zIndex(10)
            }
            if showMethod {
                methodLayer.zIndex(20)
            }

            if busy {
                PayBusyOverlay(text: "正在转账").zIndex(30)
            }
        }

        .alert(Tr("转账说明"), isPresented: $noteEditing) {
            TextField("", text: $note)
            Button(Tr("好")) { }
            Button(Tr("取消"), role: .cancel) { note = "" }
        } message: {
            Text(Tr("收付款双方可见，最多 60 个字"))
        }

        .onChange(of: note) { v in
            if v.count > 60 { note = String(v.prefix(60)) }
        }

        .sheet(isPresented: $showBills) {
            NavigationStack { BillsView().environmentObject(app) }
        }

        .sheet(isPresented: $needFaceForRisk) {
            FaceVerifyFlowView { ok in
                needFaceForRisk = false
                if ok {
                    submit(face: true)
                } else {
                    payHint = "没有人脸验证通过，这一笔没有转出去"
                }
            }
            .environmentObject(app)
        }
        .alert(Tr("转账帮助"), isPresented: $showPayHelp) {
            Button(Tr("好"), role: .cancel) { }
        } message: {
            Text(Tr("转账后对方需要确认收款才会到账；24 小时未确认会自动退回。可以在「我 → 账单」里查这笔记录。"))
        }
        .task {
            hasPwd = await API.shared.hasPayPassword()
            faceOK = Biometrics.paymentReady

            if (chat.type ?? "direct") != "group" {
                let meId = app.me?.id ?? ""
                if let peerId = (chat.memberIds ?? []).first(where: { $0 != meId }),
                   let peer = try? await API.shared.user(id: peerId) {
                    peerRealName = peer.realName ?? ""
                }
            }

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 525_000_000)
                caretOn.toggle()
            }
        }
    }

    private var mainPage: some View {
        VStack(spacing: 0) {
            head
            bodyArea
            Spacer(minLength: 0)

            sendBar

            amountPad
        }
    }

    private var amountPad: some View {
        VStack(spacing: 0) {
            PayKeypadView(busy: false, keyHeight: L.payPadH, secure: false, dot: true) { k in
                tapAmount(k)
            }
            Rectangle()
                .fill(C.cardBg)
                .frame(height: max(0, L.safeBottom))
        }
    }

    private func tapAmount(_ k: String) {
        if k == "⌫" {
            if !digits.isEmpty { digits.removeLast() }
            return
        }
        if k == "." {
            if digits.isEmpty { digits = "0."; return }
            if !digits.contains(".") { digits += "." }
            return
        }
        if digits == "0" { digits = k; return }
        let next = digits + k
        let clean = sanitizeAmount(next)

        if clean.count > digits.count { digits = clean }
    }

    private var sendBar: some View {
        Button {
            openPay()
        } label: {
            Text(Tr("转账"))
        }
        .buttonStyle(PayPrimaryButtonStyle(tint: PayVisual.tint, enabled: amount > 0))
        .disabled(amount <= 0)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, max(14, L.safeBottom))
    }

    private var head: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("")
                HStack {
                    Button { dismiss() } label: {
                        SVGIcon(markup: I.backCover, size: 20, color: C.label)
                            .frame(width: 44, height: L.navH)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
            }
            .frame(height: L.navH)

            HStack(spacing: L.v(10, 3.2, 13)) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(Lang.isEnglish ? "Transfer to \(peerTitle)" : "转账给 \(peerTitle)")
                        .font(pf(17.5, .semibold))
                        .foregroundColor(C.label)
                    Text(Lang.isEnglish ? "Account: \(chat.name)" : "账号：\(chat.name)")
                        .font(pf(12))
                        .foregroundColor(C.subLabel)
                }
                Spacer(minLength: 0)
                Avatar(path: peerAvatar, size: L.tfAvatar, radius: 6)
            }
            .padding(.top, L.v(10, 4.8, 20))
            .padding(.horizontal, L.v(16, 5, 20))
            .padding(.bottom, L.v(12, 4.4, 18))
        }
        .background(PayVisual.canvas)
    }

    private var bodyArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Tr("转账金额"))
                .font(pf(14.5))
                .foregroundColor(C.label)
                .padding(.horizontal, L.v(16, 5, 20))
                .padding(.top, L.v(10, 4, 16))
                .padding(.bottom, L.v(4, 1.4, 6))

            HStack(alignment: .center, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("¥")
                        .font(pfMoney(L.tfCnySize))
                        .foregroundColor(C.label)
                    digitCells
                }
                if caretOn {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(C.green)
                        .frame(width: L.tfCaretW, height: L.tfCaretH)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, L.v(4, 1.4, 7))
            .padding(.horizontal, L.v(16, 5, 20))
            .padding(.bottom, L.v(10, 3.4, 15))
            .overlay(alignment: .bottom) {
                Rectangle().fill(C.hairline).frame(height: 0.5)
            }
            .contentShape(Rectangle())

            HStack(alignment: .top, spacing: 5) {
                Text("¥")
                    .font(pfMoney(L.tfCnySize))
                    .foregroundColor(.clear)
                unitCells
                Spacer(minLength: 0)
            }
            .padding(.top, L.v(2, 1, 4))
            .padding(.horizontal, L.v(16, 5, 20))

            Button {
                noteEditing = true
            } label: {
                Text(note.isEmpty ? Tr("添加转账说明") : note)
                    .font(pf(16.5))
                    .foregroundColor(Color.dyn(0x1E4FA3, 0x6F9BE0))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, L.v(10, 3.4, 16))
                    .padding(.horizontal, L.v(16, 5, 20))
                .padding(.bottom, L.v(14, 4.4, 18))
                   .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }

        .background(PayVisual.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    private var digitCells: some View {
        let chars = Array(digits)
        return HStack(spacing: 0) {
            ForEach(chars.indices, id: \.self) { i in
                Text(String(chars[i]))
                    .font(pf(L.tfDigitSize, .semibold))
                    .foregroundColor(C.label)
                    .frame(width: L.tfCellW)
            }
            if digits.isEmpty { Color.clear.frame(width: L.tfCellW, height: 1) }
        }
    }

    private var unitCells: some View {
        let chars = Array(digits)
        return HStack(spacing: 0) {
            ForEach(chars.indices, id: \.self) { i in
                Text(unit(at: i, in: chars))
                    .font(pf(L.tfUnitSize))
                    .foregroundColor(Color(hex: 0xB8B8B8))
                    .lineLimit(1)
                    .frame(width: L.tfCellW)
            }
            if chars.isEmpty { Color.clear.frame(width: L.tfCellW, height: 1) }
        }
    }

    private func unit(at i: Int, in chars: [Character]) -> String {
        guard i < chars.count else { return "" }
        if chars[i] == "." { return "" }
        if chars[0..<i].contains(where: { $0 != "." }) { return "" }
        let intLen = digits.split(separator: ".").first?.count ?? 0
        switch intLen {
        case 5: return "万"
        case 6: return "十万"
        default: return intLen >= 7 ? "百万" : "千"
        }
    }

    private func sanitizeAmount(_ raw: String) -> String {
        var out = ""
        var seenDot = false
        var decimals = 0
        for ch in raw {
            if ch >= "0" && ch <= "9" {
                if seenDot {
                    if decimals >= 2 { continue }
                    decimals += 1
                }
                out.append(ch)
            } else if ch == "." || ch == "," {
                if seenDot { continue }
                seenDot = true
                out.append(".")
            }
        }
        return out.count > 10 ? String(out.prefix(10)) : out
    }

    private func openPay() {
        guard amount > 0 else { app.show(Tr("请先输入转账金额")); return }
        password = ""
        payHint = nil
        badPwd = false
        withAnimation(.easeOut(duration: 0.26)) { showPay = true }
        Task {
            hasPwd = await API.shared.hasPayPassword()
            app.me = try? await API.shared.me()
        }
    }

    private var payLayer: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { closePay() }

            VStack(spacing: 0) {
                Capsule()
                    .fill(C.subLabel.opacity(0.30))
                    .frame(width: 38, height: 5)
                    .padding(.top, 8)

                HStack(spacing: 10) {
                    Button { closePay() } label: {
                        SVGIcon(markup: payClose, size: L.v(13, 3.6, 15), color: C.label)
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)

                    Text(Tr("确认转账"))
                        .font(pf(17, .semibold))
                        .foregroundColor(C.label)
                        .frame(maxWidth: .infinity)

                    Group {
                        if faceOK {
                            Button { facePay() } label: {
                                Image(systemName: "faceid")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(PayVisual.tint)
                                    .frame(width: 40, height: 40)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Color.clear.frame(width: 40, height: 40)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 2)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        VStack(spacing: 5) {
                            Text(Tr("转账金额"))
                                .font(pf(12.5, .medium))
                                .foregroundColor(PayVisual.secondaryInk)
                            StarPayAmount(value: amount, role: .sheet, color: C.label)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                        .padding(.bottom, 18)

                        PayGroupCard {
                            VStack(spacing: 0) {
                                HStack(spacing: 13) {
                                    Avatar(path: peerAvatar, size: 44, radius: 22)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(Tr("收款给"))
                                    .font(pf(11.5, .medium))
                                    .foregroundColor(PayVisual.secondaryInk)
                                        Text(peerTitle)
                                            .font(pf(16, .semibold))
                                    .foregroundColor(C.label)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 16)
                                .frame(minHeight: 74)

                                HairLine(inset: 16)

                                Button {
                                    showMethod = true
                                } label: {
                                    HStack(spacing: 13) {
                                        Image(systemName: method == "card"
                                              ? "creditcard.fill" : "wallet.bifold.fill")
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundStyle(.white)
                                            .frame(width: 38, height: 38)
                                            .background(
                                                method == "card" ? Color(hex: 0x1677FF)
                                                    : (method == "xypay" ? PayVisual.gold : PayVisual.success),
                                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            )

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(methodName)
                                                .font(pf(15.5, .semibold))
                                                .foregroundColor(C.label)
                                            Text(methodSub)
                                                .font(pf(12))
                                                .foregroundColor(PayVisual.secondaryInk)
                                                .lineLimit(1)
                                        }
                                        Spacer(minLength: 6)
                                        Text(Tr("更改"))
                                            .font(pf(13, .medium))
                                            .foregroundColor(PayVisual.tint)
                                        Chevron(size: 7, line: 1.4, color: PayVisual.tint)
                                    }
                                    .padding(.horizontal, 16)
                                    .frame(minHeight: 66)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                if !note.isEmpty {
                                    HairLine(inset: 16)
                                    HStack(spacing: 12) {
                                        Text(Tr("转账说明"))
                                            .font(pf(13.5))
                                            .foregroundColor(PayVisual.secondaryInk)
                                        Spacer()
                                        Text(note)
                                            .font(pf(13.5, .medium))
                                            .foregroundColor(C.label)
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 16)
                                    .frame(minHeight: 48)
                                }
                            }
                        }
                        .padding(.horizontal, 20)

                        VStack(spacing: 10) {
                            PayDotField(count: password.count, shake: badPwd ? -6 : 0, height: 48)

                            if let hint = payHint {
                                Text(hint)
                                    .font(pf(13.5))
                                    .foregroundColor(PayVisual.danger)
                            } else if !hasPwd {
                                Text(Tr("还没设置支付密码：我 → 设置 → 账号与安全 → 支付密码"))
                                    .font(pf(13.5))
                                    .foregroundColor(C.subLabel)
                                    .multilineTextAlignment(.center)
                            } else {
                                Text(amount > balance
                                     ? "余额只剩 ¥\(money(balance))，点这里去充值"
                                     : Tr("输入 6 位支付密码完成这笔转账"))
                                    .font(pfMoney(13.5))
                                    .foregroundColor(amount > balance ? C.link : C.subLabel)
                            }
                        }
                        .padding(.top, 18)
                        .padding(.bottom, 8)
                    }
                }

                PayKeypadView(busy: busy, keyHeight: L.payPadH) { k in
                    tapPay(k)
                }
                .padding(.top, 10)

                Rectangle()
                    .fill(C.cardBg)
                    .frame(height: max(34, L.safeBottom))
            }
            .background(C.cardBg)
            .clipShape(TopRounded(radius: L.paySheetRadius))
            .shadow(color: .black.opacity(0.20), radius: 22, y: -6)
        }
    }

    private func tapPay(_ k: String) {
        if k == "⌫" {
            if !password.isEmpty { password.removeLast() }
            payHint = nil
            return
        }
        guard password.count < 6 else { return }
        password += k
        payHint = nil
        badPwd = false
        if password.count == 6 && !busy { submit(face: false) }
    }

    private func closePay() {
        withAnimation(.easeOut(duration: 0.22)) {
            showPay = false
            showMethod = false
        }
        password = ""
        payHint = nil
        badPwd = false
    }

    private var methodLayer: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.22)) { showMethod = false }
                }

            VStack(spacing: 0) {
                ZStack {
                    Text(Tr("选择付款方式"))
                        .font(pf(16.5, .semibold))
                        .foregroundColor(C.label)
                    HStack {
                        Button {
                            withAnimation(.easeOut(duration: 0.22)) { showMethod = false }
                        } label: {
                            SVGIcon(markup: payClose, size: L.v(13, 3.6, 15), color: C.label)
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.leading, L.v(10, 3.4, 14))
                }
                .frame(height: L.payHeadH)

                VStack(spacing: 10) {
                        methodRow("balance", Tr("星言零钱"), "¥" + money(balance))

                        if XYPay.on { methodRow("xypay", XYPay.name, XYPay.cardLine + " · ¥" + money(balance)) }
                }
                .padding(.horizontal, L.v(12, 3.8, 16))
                .padding(.bottom, L.v(10, 3, 14))

                Button {
                    recharge()
                } label: {
                    Text(Tr("充值余额"))
                        .font(pf(14.5))
                        .foregroundColor(C.link)
                        .frame(maxWidth: .infinity)
                        .frame(height: L.v(44, 12.4, 50))
                        .background(RoundedRectangle(cornerRadius: L.v(9, 2.9, 12))
                            .fill(Color.dyn(0xEDEDED, 0x111111)))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, L.v(12, 3.8, 16))

                Rectangle()
                    .fill(Color.dyn(0xEDEDED, 0x232325))
                    .frame(height: max(34, L.safeBottom))
            }
            .background(C.cardBg)
            .clipShape(TopRounded(radius: L.paySheetRadius))
        }
    }

    private func methodRow(_ key: String, _ name: String, _ sub: String) -> some View {
        Button {
            method = key
            withAnimation(.easeOut(duration: 0.22)) { showMethod = false }
            app.show(Tr("付款方式：") + name)
        } label: {
            HStack(spacing: L.v(8, 2.6, 11)) {
                SVGIcon(markup: payBalanceIcon,
                        size: L.v(21, 5.8, 25),
                        color: key == "xypay" ? XYPay.on ? PayVisual.gold : PayVisual.tint : PayVisual.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(pf(14)).foregroundColor(C.label)
                    Text(sub).font(pf(12.8)).foregroundColor(C.subLabel)
                }
                Spacer(minLength: 0)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(PayVisual.success)
                    .opacity(method == key ? 1 : 0)
            }
            .padding(.horizontal, L.v(12, 3.8, 15))
            .frame(height: L.v(56, 16, 64))
            .background(RoundedRectangle(cornerRadius: L.v(9, 2.9, 12))
                .fill(method == key ? Color.dyn(0xEAF3FC, 0x1B2A3D) : Color.dyn(0xEDEDED, 0x111111)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func recharge() {
        Task {
            if let b = try? await API.shared.recharge(500) {
                app.me = try? await API.shared.me()
                app.show("充值成功，余额 ¥\(money(b))")
            }
        }
    }

    private var resultPage: some View {
        VStack(spacing: 0) {

            HStack {
                Spacer(minLength: 0)
                Menu {
                    Button { showBills = true } label: { Label(Tr("查看账单"), systemImage: "list.bullet.rectangle") }
                    Button { again() } label: { Label(Tr("再转一笔"), systemImage: "arrow.triangle.2.circlepath") }
                    Button { showPayHelp = true } label: { Label(Tr("转账帮助"), systemImage: "questionmark.circle") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(C.label)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 8)

            Spacer().frame(height: 44)
            ZStack {
                Circle()
                    .fill(PayVisual.tint.opacity(0.12))
                    .frame(width: 92, height: 92)
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(PayVisual.tint)
                    .offset(x: -2, y: 1)
            }
            Text(Tr("转账已发出"))
                .font(pf(22, .semibold))
                .foregroundColor(C.label)
                .padding(.top, 18)
            StarPayAmount(value: doneAmount, role: .sheet, color: C.label)
                .padding(.top, 8)
            PayStatusPill(text: Tr("等待对方确认收款"), tone: .processing)
                .padding(.top, 12)
            Text(Tr("对方确认后款项进入其零钱；24 小时未确认将自动退回。"))
                .font(pf(13))
                .foregroundColor(PayVisual.secondaryInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
                .padding(.top, 12)

            PayGroupCard {
                VStack(spacing: 0) {
                    resultRow(Tr("收款方"), chat.name)
                    HairLine(inset: 18)
                    resultRow(Tr("付款方式"), methodName)
                    HairLine(inset: 18)
                    resultRow(Tr("剩余零钱"), "¥" + money(balance))
                    if !note.isEmpty {
                        HairLine(inset: 18)
                        resultRow(Tr("转账说明"), note)
                    }
                    if let id = receipt?.transfer?.id, !id.isEmpty {
                        HairLine(inset: 18)
                        resultRow(Tr("转账单号"), id)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    showBills = true
                } label: {
                    Text(Tr("查看账单"))
                }
                .buttonStyle(PaySecondaryButtonStyle(tint: PayVisual.tint))

                Button {
                    dismiss()
                } label: {
                    Text(Tr("完成"))
                }
                .buttonStyle(PayPrimaryButtonStyle(tint: PayVisual.tint))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, max(26, L.safeBottom))
        }
        .frame(maxWidth: .infinity)
        .background(PayVisual.canvas.ignoresSafeArea())
    }

    private func resultRow(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(pf(15)).foregroundColor(C.subLabel)
            Spacer()
            Text(v).font(pf(15)).foregroundColor(C.label)
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 52)
    }

    private func again() {
        withAnimation(.easeOut(duration: 0.2)) {
            step = 0
            digits = ""
            note = ""
            password = ""
            payHint = nil
            doneAmount = 0
            receipt = nil
        }
    }

    private func facePay() {
        guard amount > 0 else { app.show(Tr("请先输入转账金额")); return }
        Task {
            let r = await Biometrics.authenticate(
                reason: "验证身份，向 \(chat.name) 转账 ¥\(money(amount))")
            if r.ok {
                payHint = nil
                submit(face: true)
            } else if !r.message.isEmpty {
                payHint = r.message
            }
        }
    }

    private func submit(face: Bool) {
        guard amount > 0 else { return }
        if !face && hasPwd && password.count < 6 {
            payHint = "请输入 6 位支付密码"
            return
        }
        busy = true
        payHint = nil
        Task {
            do {
                let result = try await API.shared.transfer(
                    chatId: chat.id, amount: amount, note: note,
                    method: method, password: password, face: face)
                receipt = result
                doneAmount = result.amount ?? amount
                app.me = try? await API.shared.me()
                password = ""
                busy = false
                withAnimation(.easeOut(duration: 0.22)) {
                    showPay = false
                    step = 1
                }

                onPaid()
                await app.loadChats()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                let msg = (error as? APIError)?.errorDescription ?? "转账失败"
                password = ""

                if msg.contains("需要人脸验证") {
                    payHint = msg
                    needFaceForRisk = true
                    busy = false
                    return
                }
                badPwd = true
                payHint = msg
                try? await Task.sleep(nanoseconds: 420_000_000)
                badPwd = false
            }
            busy = false
        }
    }
}

extension View {
    func twoLayerCard(radius: CGFloat = 18, pad: CGFloat = 12) -> some View {
        self
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(C.cardBg))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(C.hairline, lineWidth: 0.6))
            .shadow(color: Color.black.opacity(0.06), radius: 10, y: 4)
            .padding(.horizontal, pad)
    }
}

struct TopRounded: Shape {
    var radius: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        p.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY),
                       control: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius),
                       control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

let payClose = """
<svg data-key="pay.close" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.3" stroke-linecap="round"><path d="M5.8 5.8l12.4 12.4M18.2 5.8L5.8 18.2"/></svg>
"""

let payChev = """
<svg data-key="pay.chev" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9.8 5.6l6.4 6.4-6.4 6.4"/></svg>
"""

let payTick = """
<svg data-key="pay.tick" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M4.9 12.7l4.7 4.7 9.5-10.4"/></svg>
"""

let payBalanceIcon = """
<svg data-key="pay.balance" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="8.6"/><path d="M12 6.6v10.8M9.4 9.2h4.2a2.1 2.1 0 0 1 0 4.2H9.4h4.6a2.1 2.1 0 0 1 0 4.2H9.4"/></svg>
"""

let payCardIcon = """
<svg data-key="pay.card" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><rect x="3.2" y="5.6" width="17.6" height="12.8" rx="2.6"/><path d="M3.2 10.2h17.6"/><path d="M6.6 14.6h3.4"/></svg>
"""

func money(_ v: Double) -> String {
    moneyFmt(v)
}
