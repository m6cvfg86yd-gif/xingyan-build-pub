import SwiftUI
import UIKit

struct MemberTier: Decodable, Hashable, Identifiable {
    var id: String
    var name: String
    var short: String?
    var color: String?
    var color2: String?
    var boost: Double?
    var groupMax: Int?
    var price: Price?

    struct Price: Decodable, Hashable {
        var month: Double?
        var quarter: Double?
        var year: Double?
    }

    func priceOf(_ months: Int) -> Double {
        let p = price ?? Price()
        let unit: Double
        if months >= 12 { unit = (p.year ?? 0) / 12 }
        else if months >= 3 { unit = (p.quarter ?? 0) / 3 }
        else { unit = (p.month ?? 0) }
        return (unit * Double(months) * 100).rounded() / 100
    }
}

struct MemberBenefit: Decodable, Hashable {
    var icon: String?
    var title: String?
    var desc: String?
}

struct MemberMe: Decodable, Hashable {
    var tier: String?
    var name: String?
    var short: String?
    var color: String?
    var color2: String?
    var expireAt: Double?
    var active: Bool?
    var daysLeft: Int?
    var autoRenew: Bool?
    var boost: Double?
    var groupMax: Int?

    var isActive: Bool { active == true && !(tier ?? "").isEmpty }
}

struct MemberHistoryRow: Decodable, Hashable, Identifiable {
    var at: String?
    var tier: String?
    var days: Int?
    var months: Int?
    var price: Double?
    var note: String?
    var id: String { (at ?? "") + "|" + (tier ?? "") + "|" + String(price ?? 0) }
}

struct MemberInfo: Decodable {
    var enabled: Bool?
    var title: String?
    var sub: String?
    var tiers: [MemberTier]?
    var benefits: [MemberBenefit]?
    var me: MemberMe?
    var balance: Double?
    var history: [MemberHistoryRow]?
}

@MainActor
final class MemberStore: ObservableObject {
    static let shared = MemberStore()

    @Published var info: MemberInfo?
    @Published var loading = false
    @Published var lastError = ""

    var tiers: [MemberTier] { info?.tiers ?? [] }
    var benefits: [MemberBenefit] { info?.benefits ?? [] }
    var me: MemberMe? { info?.me }
    var active: Bool { info?.me?.isActive == true }
    var balance: Double { info?.balance ?? 0 }

    func refresh() async {
        if loading { return }
        loading = true
        defer { loading = false }
        if let m = try? await API.shared.memberInfo() { info = m }
    }

    @discardableResult
    func open(tierId: String, months: Int, payPassword: String) async -> String? {
        let (me, balance, err) = await API.shared.memberOpen(tierId: tierId, months: months, payPassword: payPassword)
        if let err = err { return err }
        if var cur = info {
            if let me = me { cur.me = me }
            if let balance = balance { cur.balance = balance }
            info = cur
        }
        await refresh()
        return nil
    }

    func setAuto(_ on: Bool) async {
        await API.shared.memberAuto(on)
        await refresh()
    }

    @discardableResult
    func redeem(_ code: String) async -> String {
        let (_, msg) = await API.shared.memberRedeem(code)
        await refresh()
        return msg
    }
}

struct MemberBadge: View {
    var tier: String?
    var short: String?
    var color: String?
    var color2: String?
    var height: CGFloat = 13

    private var body1: some View {
        let c1 = Color(hexString: (color?.isEmpty == false ? color! : "#E0B44A"))
        let c2 = Color(hexString: (color2?.isEmpty == false ? color2! : "#B8862A"))
        return Text((short?.isEmpty == false) ? short! : "VIP")
            .font(pf(max(7.5, height * 0.58), .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, height * 0.28)
            .frame(height: height)
            .background(Capsule().fill(LinearGradient(colors: [c1, c2],
                                                      startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 0.6))
            .shadow(color: c2.opacity(0.35), radius: 2, y: 1)
            .fixedSize()
    }

    var body: some View {
        if let t = tier, !t.isEmpty { body1 }
    }
}

struct MemberPaySheet: View {
    let amount: Double
    var purpose: String = "开通会员"
    var hasPassword: Bool = true

    let pay: (String) async -> String?
    let onDone: () -> Void

    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var pwd = ""
    @State private var busy = false
    @State private var tip = ""

    @State private var shake: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Tr("收银台"))
                        .font(pf(17, .semibold))
                        .foregroundColor(C.label)
                    Text(XYPay.name)
                        .font(pf(11.5, .medium))
                        .foregroundColor(PayVisual.secondaryInk)
                }
                Spacer(minLength: 0)
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(PayVisual.secondaryInk)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .overlay(HairLine(), alignment: .bottom)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    VStack(spacing: 7) {
                        Text(purpose)
                            .font(pf(14.5, .medium))
                            .foregroundColor(PayVisual.secondaryInk)
                        StarPayAmount(value: amount, role: .detail, color: C.label)
                    }
                    .frame(maxWidth: .infinity)

                    PayCheckoutWalletCard(
                        title: XYPay.cardLine,
                        subtitle: XYPay.sub,
                        tail: XYPay.tail(app.me?.id ?? app.me?.username ?? "xingyan"),
                        holder: app.me?.nickname ?? app.me?.username ?? ""
                    )

                    PayGroupCard {
                        VStack(spacing: 0) {
                            checkoutRow(Tr("收款方"), purpose)
                            HairLine(inset: 16)
                            checkoutRow(Tr("付款方式"), XYPay.name)
                            HairLine(inset: 16)
                            checkoutRow(Tr("安全验证"), Tr("支付密码"))
                        }
                    }

                    if hasPassword {
                        VStack(spacing: 12) {
                            PayDotField(count: pwd.count, shake: shake, busy: busy)
                            Text(Tr("输入 6 位支付密码完成付款"))
                                .font(pf(12.5))
                                .foregroundColor(PayVisual.secondaryInk)
                        }
                    } else {
                        VStack(spacing: 9) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 22))
                                .foregroundColor(PayVisual.warning)
                            Text(Tr("还没设置支付密码"))
                                .font(pf(16, .semibold))
                                .foregroundColor(C.label)
                            Text(Tr("为了安全，付款前要先设一个 6 位支付密码\n（我 → 设置 → 账号与安全 → 支付密码）"))
                                .font(pf(13.5))
                                .foregroundColor(PayVisual.secondaryInk)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 26)
                        .padding(.vertical, 14)
                    }

                    if !tip.isEmpty {
                        Text(tip)
                            .font(pf(13))
                            .foregroundColor(PayVisual.danger)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 10)
            }

            if hasPassword {
                PayKeypadView(busy: busy) { tapKey($0) }
            }
        }

        .overlay {
            if busy { PayBusyOverlay(text: "正在开通会员") }
        }
        .animation(.easeOut(duration: 0.15), value: busy)
        .background(PayVisual.canvas.ignoresSafeArea())
    }

    private func checkoutRow(_ title: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(pf(13.5))
                .foregroundColor(PayVisual.secondaryInk)
            Spacer(minLength: 8)
            Text(value)
                .font(pf(13.5, .medium))
                .foregroundColor(C.label)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    private func tapKey(_ key: String) {
        if busy { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if key == "⌫" {
            if !pwd.isEmpty { pwd.removeLast() }
            tip = ""
            return
        }
        guard !key.isEmpty, pwd.count < 6 else { return }
        pwd.append(key)
        tip = ""
        if pwd.count == 6 { submit() }
    }

    private func submit() {
        guard !busy else { return }
        busy = true

        Task { @MainActor in
            let err = await pay(pwd)
            busy = false
            if let err = err {
                tip = err
                pwd = ""

                UINotificationFeedbackGenerator().notificationOccurred(.error)
                withAnimation(.easeOut(duration: 0.06)) { shake = -12 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.35)) { shake = 0 }
                }
                return
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
            onDone()
        }
    }
}

struct MemberPayResult: Identifiable {
    let id = UUID()
    var title: String
    var amount: Double
    var expireText: String
    var isRenew: Bool
}

struct MemberPayDoneView: View {
    let result: MemberPayResult
    var onClose: () -> Void

    @State private var pop = false
    @State private var ripple = false
    @State private var showRows = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 34)
            ZStack {
                Circle()
                    .stroke(C.green.opacity(ripple ? 0 : 0.45), lineWidth: 2)
                    .frame(width: ripple ? 136 : 66, height: ripple ? 136 : 66)
                Circle()
                    .fill(LinearGradient(colors: [C.green, C.green.opacity(0.78)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 66, height: 66)
                    .scaleEffect(pop ? 1 : 0.5)
                    .shadow(color: C.green.opacity(0.35), radius: 12, y: 4)
                Image(systemName: "checkmark")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.white)
                    .scaleEffect(pop ? 1 : 0.4)
                    .opacity(pop ? 1 : 0)
            }
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.58)) { pop = true }
                withAnimation(.easeOut(duration: 1.1).delay(0.1)) { ripple = true }
                withAnimation(.easeOut(duration: 0.42).delay(0.22)) { showRows = true }
            }
            Text(Tr("支付成功"))
                .font(pf(20, .semibold))
                .foregroundColor(C.label)
                .padding(.top, 16)
                .opacity(showRows ? 1 : 0)
            Text("¥" + moneyFmt(result.amount))
                .font(pfMoney(30, .medium))
                .foregroundColor(C.label)
                .padding(.top, 6)
                .opacity(showRows ? 1 : 0)

            PanelCard {
                row(Tr("商品"), result.title)
                PanelDivider()
                row(Tr("支付方式"), Tr("零钱"))
                PanelDivider()
                row(Tr("到期时间"), result.expireText)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .opacity(showRows ? 1 : 0)
            .offset(y: showRows ? 0 : 12)

            Button { onClose() } label: {
                Text(Tr("完成"))
                    .font(pf(17, .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(colors: [C.green, C.green.opacity(0.78)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .padding(.top, 22)

            Spacer(minLength: 0)
        }
        .background(C.pageBg.ignoresSafeArea())
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(spacing: 10) {
            Text(title).font(pf(14.5)).foregroundColor(C.subLabel)
            Spacer(minLength: 8)
            Text(value).font(pf(14.5)).foregroundColor(C.label).lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
    }
}
