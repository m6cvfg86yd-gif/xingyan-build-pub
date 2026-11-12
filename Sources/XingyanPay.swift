import SwiftUI

enum XYPay {

    static var name: String { UIConfig.text("payName", "星言支付") }
    static var sub: String { UIConfig.text("paySub", "指纹 / 面容 · 安全支付") }
    static var cardLine: String { UIConfig.text("payCard", "星言钱包") }

    static var on: Bool { UIConfig.num("payOn", 1) > 0 }

    static func tail(_ seed: String) -> String {
        var h = 5381
        for b in seed.utf8 { h = (h &* 33) &+ Int(b) }
        return String(format: "%04d", abs(h) % 10000)
    }
}

struct XYPaySheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    let amount: Double

    var target: String = ""

    var note: String = ""

    var onSuccess: () -> Void

    @State private var stage = 0
    @State private var pwd = ""
    @State private var hint = ""
    @State private var busy = false
    @State private var shake = false
    @State private var noPwd = false
    @FocusState private var focusPwd: Bool

    private var tail: String { XYPay.tail(app.me?.id ?? app.me?.username ?? "xingyan") }

    var body: some View {
        VStack(spacing: 0) {
            bar
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    cardFace
                    amountBlock
                    if stage == 2 { successBlock }
                    else if stage == 1 { pwdBlock }
                    else { verifyBlock }
                    Spacer().frame(height: 4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
        .background(PayVisual.canvas.ignoresSafeArea())
        .task {

            noPwd = !(await API.shared.hasPayPassword())
        }
    }

    private var bar: some View {
        HStack(spacing: 8) {
            Text(XYPay.name).font(pf(17, .semibold)).foregroundColor(C.label)
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(C.subLabel)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .overlay(HairLine(), alignment: .bottom)
    }

    private var cardFace: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x1C1E26), Color(hex: 0x30354A)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {

                    if let brand = IconOverrides.custom("pay.xy"), !brand.isEmpty {
                        FlexIcon(custom: brand, size: 26,
                                 color: Color(hex: 0xFFE7B0), symbol: "creditcard.fill")
                            .frame(width: 26, height: 26)
                    } else {
                        Text("星")
                            .font(pf(13, .bold)).foregroundColor(Color(hex: 0x3A2B12))
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(LinearGradient(
                                colors: [Color(hex: 0xFFE7B0), Color(hex: 0xD9A94A)],
                                startPoint: .top, endPoint: .bottom)))
                    }
                    Text(XYPay.cardLine).font(pf(13.5, .medium)).foregroundColor(.white)
                    Spacer(minLength: 0)
                    Image(systemName: "wave.3.right").font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.65))
                }
                Spacer(minLength: 0)
                Text("••••  ••••  ••••  " + tail)
                    .font(pf(15.5, .medium)).foregroundColor(.white.opacity(0.94))
                HStack(spacing: 6) {
                    Text(app.me?.nickname ?? app.me?.username ?? "")
                        .font(pf(11.5)).foregroundColor(.white.opacity(0.7)).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(XYPay.sub).font(pf(11)).foregroundColor(.white.opacity(0.55)).lineLimit(1)
                }
                .padding(.top, 6)
            }
            .padding(14)
        }
        .frame(height: 138)
        .shadow(color: .black.opacity(0.16), radius: 12, y: 6)
    }

    private var amountBlock: some View {
        VStack(spacing: 6) {
            Text(Tr("付款金额")).font(pf(12.5)).foregroundColor(C.subLabel)
            StarPayAmount(value: amount, role: .sheet, color: C.label)
            if !target.isEmpty {
                Text(target).font(pf(13)).foregroundColor(C.subLabel)
                    .multilineTextAlignment(.center).lineLimit(2)
                    .padding(.horizontal, 20)
            }
            if !note.isEmpty {
                Text(note).font(pf(11.5)).foregroundColor(C.subLabel.opacity(0.85))
            }
        }
        .padding(.top, 4)
    }

    private var verifyBlock: some View {
        VStack(spacing: 10) {
            Button { facePay() } label: {
                HStack(spacing: 8) {
                    Image(systemName: Biometrics.available ? "faceid" : "lock.shield.fill")
                        .font(.system(size: 17))
                    Text(busy ? Tr("正在验证…") : Tr(Biometrics.label + "支付"))
                }
            }
            .buttonStyle(PayPrimaryButtonStyle(tint: PayVisual.tint))
            .disabled(busy)

            Button {
                if noPwd { hint = Tr("你还没设支付密码：我 → 设置 → 账号与安全 → 支付密码") ; return }
                withAnimation(.easeOut(duration: 0.18)) { stage = 1 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { focusPwd = true }
            } label: {
                Text(Tr("用支付密码支付")).font(pf(14.5)).foregroundColor(C.label)
            }
            .buttonStyle(PaySecondaryButtonStyle(tint: PayVisual.tint))

            if !hint.isEmpty {
                Text(hint).font(pf(12.5)).foregroundColor(C.red)
                    .multilineTextAlignment(.center).padding(.horizontal, 12)
            }
            Label(Tr("支付过程由设备安全验证保护"), systemImage: "lock.shield.fill")
                .font(pf(11.5))
                .foregroundColor(PayVisual.secondaryInk)
        }
    }

    private var pwdBlock: some View {
        VStack(spacing: 12) {
            HStack(spacing: 9) {
                ForEach(0..<6, id: \.self) { i in
                    Circle()
                        .fill(i < pwd.count ? C.label : C.subLabel.opacity(0.35))
                        .frame(width: 11, height: 11)
                        .frame(width: 42, height: 46)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(C.cardBg))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(bad ? C.red : C.hairline, lineWidth: 0.6))
                }
            }
            .offset(x: shake ? -8 : 0)
            .animation(.default, value: shake)

            TextField("", text: $pwd)
                .keyboardType(.numberPad)
                .focused($focusPwd)
                .opacity(0.01)
                .frame(height: 1)
                .onChange(of: pwd) { v in
                    let t = String(v.filter { $0.isNumber }.prefix(6))
                    if t != v { pwd = t }
                    hint = ""
                    if t.count == 6 { checkPwd(t) }
                }
            if !hint.isEmpty {
                Text(hint).font(pf(12.5)).foregroundColor(C.red)
            }
            Button { pwd = ""; withAnimation { stage = 0 } } label: {
                Text(Tr("换指纹/面容支付")).font(pf(13.5)).foregroundColor(C.subLabel)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 2)
    }

    private var bad: Bool { hint.contains("不对") || hint.contains("不正确") }

    private var successBlock: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(Color(hex: 0x1CA36B)).frame(width: 62, height: 62)
                Image(systemName: "checkmark")
                    .font(.system(size: 26, weight: .bold)).foregroundColor(.white)
            }
            Text(Tr("支付成功")).font(pf(17, .semibold)).foregroundColor(C.label)
            StarPayAmount(value: amount, role: .row, color: C.subLabel)
        }
        .padding(.top, 8)
    }

    private func facePay() {
        guard !busy else { return }
        busy = true
        hint = ""
        Task {
            let r = await Biometrics.authenticate(reason: "验证身份，支付 ¥" + moneyFmt(amount))
            busy = false
            if r.ok { success() }
            else if !r.message.isEmpty { hint = r.message }
        }
    }

    private func checkPwd(_ code: String) {
        guard !busy else { return }
        busy = true
        Task {
            do {
                try await API.shared.verifyPayPassword(code)
                busy = false
                success()
            } catch {
                busy = false
                shake.toggle()
                hint = (error as? APIError)?.errorDescription ?? Tr("支付密码不正确")
                pwd = ""
            }
        }
    }

    private func success() {
        withAnimation(.easeOut(duration: 0.2)) { stage = 2 }
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            onSuccess()
            dismiss()
        }
    }
}
