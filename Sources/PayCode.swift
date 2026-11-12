import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

func code128Image(_ text: String, height: CGFloat) -> UIImage? {
    let data = text.data(using: .ascii) ?? Data()
    let filter = CIFilter.code128BarcodeGenerator()
    filter.message = data
    filter.quietSpace = 2
    guard let out = filter.outputImage else { return nil }
    let scale = 6.0
    let scaled = out.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let ctx = CIContext()
    guard let cg = ctx.createCGImage(scaled, from: scaled.extent) else { return nil }

    let img = UIImage(cgImage: cg)
    let drawH = max(40, height)
    let size = CGSize(width: img.size.width, height: drawH)
    let r = UIGraphicsImageRenderer(size: size)
    return r.image { _ in
        UIColor.white.setFill()
        UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()

        img.draw(in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
    }
}

struct BarcodeView: View {
    let text: String
    var height: CGFloat = 76

    var body: some View {
        if let img = code128Image(text, height: height) {
            Image(uiImage: img)
                .resizable()
                .interpolation(.none)
                .frame(height: height)
                .frame(maxWidth: .infinity)
        } else {
            Rectangle().fill(Color(hex: 0xEDEDED)).frame(height: height)
        }
    }
}

struct PayCodePage: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var info: PayCodeInfo?
    @State private var left = 0
    @State private var loading = true
    @State private var failed = ""
    @State private var showReceive = false

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("收付款"), back: { dismiss() }) {
                Button { Task { await load(force: true) } } label: {
                    Text(Tr("刷新"))
                        .font(pf(16))
                        .foregroundColor(C.label)
                        .frame(height: L.navH)
                        .padding(.trailing, 16)
                }
                .buttonStyle(.plain)
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    identityCard
                    codeCard
                    receiveButton
                    securityNote
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, max(28, L.safeBottom))
            }
            .background(PayVisual.canvas)
        }
        .background(PayVisual.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)

        .modifier(BrightenScreen())
        .sheet(isPresented: $showReceive) { ReceiveCodePage().environmentObject(app) }
        .task { await load(force: false) }
        .onReceive(ticker) { _ in
            guard info != nil else { return }
            if left <= 1 { Task { await load(force: true) } }
            else { left -= 1 }
        }

        .onChange(of: scenePhase) { p in
            if p == .active { Task { await load(force: false) } }
        }
    }

    private var identityCard: some View {
        HStack(spacing: 12) {
            Avatar(path: info?.user?.avatar ?? app.me?.avatar ?? "", size: 44, radius: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(info?.user?.nickname ?? app.me?.nickname ?? Tr("我"))
                    .font(pf(16, .semibold))
                    .foregroundColor(C.label)
                Text(Tr("向商家出示动态付款码"))
                    .font(pf(12.5))
                    .foregroundColor(PayVisual.secondaryInk)
            }
            Spacer(minLength: 8)
            PayStatusPill(text: Tr("安全动态码"), tone: .processing)
        }
        .padding(.horizontal, 16)
        .frame(height: 70)
        .background(PayVisual.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var codeCard: some View {
        VStack(spacing: 0) {
            if let info = info {
                BarcodeView(text: info.code ?? "", height: 78)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                Text(info.grouped ?? "")
                    .font(pfStyled(size: 19, weight: .semibold, design: .monospaced))
                    .foregroundColor(C.label)
                    .padding(.top, 10)
                if !(info.rows ?? []).isEmpty {
                    QRCanvas(rows: info.rows ?? [])
                        .frame(width: 188, height: 188)
                        .padding(.top, 18)
                }
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                    Text(left > 0 ? Tr("\(left) 秒后自动更换") : Tr("正在更换…"))
                        .font(pf(12))
                }
                .foregroundColor(PayVisual.secondaryInk)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(PayVisual.inset, in: Capsule())
                .padding(.top, 16)
                .padding(.bottom, 24)
            } else if loading {
                ProgressView().padding(.vertical, 60)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 26))
                        .foregroundColor(Color(hex: 0xE5A54D))
                    Text(failed.isEmpty ? Tr("付款码暂时没准备好，点上面「刷新」再试一次") : failed)
                        .font(pf(14))
                        .foregroundColor(PayVisual.secondaryInk)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 46)
            }
        }
        .frame(maxWidth: .infinity)
        .background(PayVisual.card)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var receiveButton: some View {
        Button { showReceive = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "qrcode")
                    .font(.system(size: 17, weight: .medium))
                Text(Tr("二维码收款"))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.72))
            }
            .padding(.horizontal, 4)
        }
        .buttonStyle(PayPrimaryButtonStyle(tint: PayVisual.tint))
    }

    private var securityNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(PayVisual.success)
                .padding(.top, 1)
            Text(Tr("付款码只用于向商家付款，请勿泄露给陌生人；60 秒自动更换，付过一次就作废。"))
                .font(pf(12.5))
                .foregroundColor(PayVisual.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(15)
        .background(PayVisual.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func load(force: Bool) async {
        if info == nil { loading = true }
        do {
            let got = try await API.shared.payCode()
            info = got
            left = max(1, got.seconds ?? 60)
            failed = ""
        } catch {
            if info == nil { failed = Tr("付款码暂时没准备好，稍后再试") }
        }
        loading = false
    }
}

struct ReceiveCodePage: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var info: PayCodeInfo?
    @State private var amountText = ""
    @State private var showSetAmount = false
    @State private var busy = false

    private var amt: Double { max(0, info?.amount ?? 0) }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("二维码收款"), back: { dismiss() })

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.white)
                        if let info = info, let rows = info.rows, !rows.isEmpty {

                            QRCanvas(rows: rows).frame(width: 226, height: 226)
                        } else {
                            ProgressView()
                        }
                    }
                    .frame(width: 272, height: 272)
                    .shadow(color: Color.black.opacity(0.08), radius: 18, y: 8)

                    if let a = info?.amount, a > 0 {
                        VStack(spacing: 2) {
                            Text(money(a))
                                .font(pfMoney(26))
                                .foregroundColor(C.label)
                            Text(Tr("对方扫码后按这个金额付给你，改不了"))
                                .font(pf(12.5))
                                .foregroundColor(PayVisual.secondaryInk)
                        }
                    }

                    HStack(spacing: 12) {
                        Avatar(path: info?.user?.avatar ?? app.me?.avatar ?? "", size: 46, radius: 6)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(info?.user?.nickname ?? app.me?.nickname ?? "")
                                .font(pf(16, .medium)).foregroundColor(C.label).lineLimit(1)
                            Text(Tr("扫这张码就能给我付钱"))
                                .font(pf(12.5)).foregroundColor(PayVisual.secondaryInk)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 70)
                    .background(PayVisual.card)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    VStack(spacing: 0) {
                        row(Tr("设置金额"), amt > 0 ? Tr("改一下") : Tr("填一个数，扫码的人直接按这个付")) {
                            amountText = (info?.amount ?? 0) > 0 ? String(format: "%.2f", info?.amount ?? 0) : ""
                            showSetAmount = true
                        }
                        if amt > 0 {
                            HairLine(inset: 16)
                            row(Tr("清除金额"), Tr("回到普通收款码")) {
                                Task { await load(amount: 0) }
                            }
                        }
                    }
                    .background(PayVisual.card)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    Text(Tr("收款码长期有效；带金额的那种 24 小时后失效，重新设置一次就行。"))
                        .font(pf(12.5))
                        .foregroundColor(PayVisual.secondaryInk)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
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

        .modifier(BrightenScreen())
        .task { await load(amount: 0) }
        .alert(Tr("设置金额"), isPresented: $showSetAmount) {
            TextField(Tr("金额"), text: $amountText).keyboardType(.decimalPad)
            Button(Tr("确定")) {
                let v = Double(amountText.trimmingCharacters(in: .whitespaces)) ?? 0
                Task { await load(amount: v) }
            }
            Button(Tr("取消"), role: .cancel) { }
        } message: {
            Text(Tr("填了金额以后，对方扫这张码就直接按这个数付给你（24 小时内有效）"))
        }
    }

    private func row(_ title: String, _ sub: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(pf(16)).foregroundColor(C.label)
                    Text(sub).font(pf(12.5)).foregroundColor(C.subLabel)
                }
                Spacer(minLength: 0)
                Chevron(size: 9, line: 1.6)
            }
            .padding(.horizontal, 16)
            .frame(height: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func load(amount: Double) async {
        do {
            info = try await API.shared.receiveCode(amount: amount)
        } catch {
            app.show(Tr("收款码暂时没准备好，稍后再试"))
        }
    }
}

struct PayConfirmPage: View {
    let target: PayScanInfo

    var scanText: String = ""

    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var amountText = ""
    @State private var password = ""
    @State private var hasPwd = true
    @State private var busy = false
    @State private var hint = ""
    @FocusState private var amountFocus: Bool
    @FocusState private var pwdFocus: Bool

    private var fixedAmount: Double { max(0, target.amount ?? 0) }
    private var amount: Double {
        fixedAmount > 0 ? fixedAmount : (Double(amountText.trimmingCharacters(in: .whitespaces)) ?? 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("付款"), back: { dismiss() })

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    VStack(spacing: 10) {
                        Avatar(path: target.user?.avatar ?? "", size: 68, radius: 34)
                            .overlay(Circle().stroke(PayVisual.separator, lineWidth: 0.8))
                        Text(Tr("向 ") + (target.user?.nickname ?? Tr("对方")) + Tr(" 付款"))
                            .font(pf(19, .semibold)).foregroundColor(C.label)
                        Text(target.kind == "pay" ? Tr("扫的是对方的付款码") : Tr("扫的是对方的收款码"))
                            .font(pf(13)).foregroundColor(PayVisual.secondaryInk)
                    }
                    .padding(.top, 18)

                    PayGroupCard {
                        VStack(spacing: 8) {
                            Text(Tr("付款金额"))
                                .font(pf(12.5, .medium))
                                .foregroundColor(PayVisual.secondaryInk)
                            if fixedAmount > 0 {
                                StarPayAmount(value: fixedAmount, role: .sheet, color: C.label)
                            } else {
                                HStack(alignment: .firstTextBaseline, spacing: 5) {
                                    Text("¥").font(pf(24, .semibold)).foregroundColor(C.label)
                                    TextField("0.00", text: $amountText)
                                        .keyboardType(.decimalPad)
                                        .font(pfMoney(38, .semibold))
                                        .foregroundColor(C.label)
                                        .focused($amountFocus)
                                        .multilineTextAlignment(.center)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 22)
                    }

                    if hasPwd {
                        PayGroupCard {
                            VStack(spacing: 12) {
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

                                PayDotField(count: password.count, height: 50)
                                    .contentShape(Rectangle())
                                    .onTapGesture { pwdFocus = true }
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 16)

                                TextField("", text: $password)
                                    .keyboardType(.numberPad)
                                    .focused($pwdFocus)
                                    .frame(width: 1, height: 1)
                                    .opacity(0.01)
                                    .onChange(of: password) { v in
                                        let clean = String(v.filter { $0.isNumber }.prefix(6))
                                        if clean != v { password = clean }
                                    }

                                if Biometrics.paymentReady {
                                    Divider().overlay(PayVisual.separator)
                                    Button {
                                        Task { await biometricPay() }
                                    } label: {
                                        Label(Tr("使用") + Biometrics.label + Tr("支付"),
                                              systemImage: Biometrics.paymentReady ? "faceid" : "touchid")
                                            .font(pf(15.5, .semibold))
                                            .foregroundColor(PayVisual.tint)
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 50)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    } else {

                        Text(Tr("还没设置支付密码（我 → 设置 → 账号与安全 → 支付密码）"))
                            .font(pf(12.5)).foregroundColor(C.subLabel)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    if !hint.isEmpty {
                        Text(hint)
                            .font(pf(13.5))
                            .foregroundColor(Color(hex: 0xE5484D))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    Button { Task { await pay() } } label: {
                        HStack(spacing: 6) {
                            if busy { ProgressView().tint(.white) }
                            Text(busy ? Tr("付款中…") : Tr("确认付款"))
                        }
                    }
                    .buttonStyle(PayPrimaryButtonStyle(tint: PayVisual.tint, enabled: amount > 0))
                    .disabled(busy)

                    Text(Tr("付出去的钱当时到对方账上，不能撤回。"))
                        .font(pf(12.5))
                        .foregroundColor(PayVisual.secondaryInk)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, max(28, L.safeBottom))
            }
            .background(PayVisual.canvas)
        }

        .overlay {
            if busy { PayBusyOverlay(text: "正在付款") }
        }
        .background(PayVisual.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .task {
            hasPwd = await API.shared.hasPayPassword()
            if fixedAmount <= 0 { amountFocus = true } else if hasPwd { pwdFocus = true }
        }
    }

    private func biometricPay() async {
        guard !busy else { return }
        let result = await Biometrics.authenticate(
            reason: Tr("验证身份，付款 ") + money(amount))
        if result.ok {
            await pay(face: true)
        } else if !result.message.isEmpty {
            hint = result.message
        }
    }

    private func pay(face: Bool = false) async {
        hint = ""
        guard amount > 0 else { hint = Tr("请输入金额"); return }
        if !face && hasPwd && password.count < 6 { hint = Tr("请输入 6 位支付密码"); return }
        busy = true
        defer { busy = false }
        do {
            let res = try await API.shared.payCollect(
                text: codeText, amount: amount, password: face ? "" : password, face: face)
            app.show(Tr("已付款 ") + money(res.amount ?? amount) + Tr(" 给 ") + (res.payee?.nickname ?? Tr("对方")))
            app.me = try? await API.shared.me()
            await app.loadChats()
            dismiss()
        } catch {
            hint = (error as? APIError)?.errorDescription ?? Tr("付款失败")
        }
    }

    private var codeText: String { scanText }
}
