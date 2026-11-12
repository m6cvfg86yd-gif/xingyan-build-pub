import SwiftUI
import UIKit

struct VirtualCardView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var info: VirtualCardInfo?
    @State private var revealed = false
    @State private var busy = false
    @State private var error = ""
    @State private var confirmRotate = false

    private var frozen: Bool { info?.status == "frozen" }
    private var exists: Bool { info?.exists == true }

    var body: some View {
        screen
    }

    private var screen: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("虚拟卡号"), back: { dismiss() })

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    cardFace
                    noticeBlock
                    if exists {
                        details
                        actions
                    } else {
                        issueBlock
                    }
                    errorBlock
                    Color.clear.frame(height: max(24, L.safeBottom + 12))
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .background(PayVisual.canvas)
        }
        .background(PayVisual.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .task { await load() }
        .task(id: revealed) {
            guard revealed else { return }
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            guard !Task.isCancelled else { return }
            await hideCard()
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active, revealed {
                Task { await hideCard() }
            }
        }
        .confirmationDialog(Tr("更换虚拟卡号？"),
                            isPresented: $confirmRotate,
                            titleVisibility: .visible) {
            Button(Tr("更换卡号"), role: .destructive) { run("rotate") }
            Button(Tr("取消"), role: .cancel) {}
        } message: {
            Text(Tr("旧卡号会立即失效，已保存旧卡号的商户将无法继续使用。"))
        }
    }

    private var noticeBlock: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(PayVisual.warning)
            Text(Tr(info?.notice ?? "星言内部虚拟卡号，不是 Visa / Mastercard，不能在外部商户使用"))
                .font(pf(12.5))
                .foregroundStyle(PayVisual.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(PayVisual.warning.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var issueBlock: some View {
        VStack(spacing: 12) {
            Text(Tr("生成一张仅在星言支付系统内使用的设备虚拟卡号"))
                .font(pf(14))
                .foregroundStyle(PayVisual.secondaryInk)
                .multilineTextAlignment(.center)
            Button {
                run("issue")
            } label: {
                Text(busy ? Tr("正在生成…") : Tr("生成虚拟卡号"))
            }
            .buttonStyle(PayPrimaryButtonStyle(tint: PayVisual.tint, enabled: !busy))
            .disabled(busy)
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var errorBlock: some View {
        if !error.isEmpty {
            Text(error)
                .font(pf(12.5))
                .foregroundStyle(PayVisual.danger)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
    }

    private var cardFace: some View {
        ZStack(alignment: .topLeading) {
            cardBackground
            VStack(alignment: .leading, spacing: 0) {
                cardHeader
                Spacer(minLength: 24)
                cardNumber
                Spacer(minLength: 20)
                cardFooter
            }
            .padding(22)
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            CardLightSweep(cornerRadius: 26)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.25), .white.opacity(0.04), .white.opacity(0.13)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.9
                )
        }
        .shadow(color: .black.opacity(0.26), radius: 20, y: 10)
        .overlay(alignment: .topTrailing) {
            if frozen {
                Label(Tr("已冻结"), systemImage: "snowflake")
                    .font(pf(10.5, .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(.red.opacity(0.76), in: Capsule())
                    .padding(16)
            }
        }
    }

    @ViewBuilder
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(LinearGradient(
                colors: [Color(hex: 0x050506), Color(hex: 0x1A1B1F), Color(hex: 0x080809)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.06),
                    .init(color: .white.opacity(0.10), location: 0.47),
                    .init(color: .clear, location: 0.66)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            .blendMode(.screen)
        Circle()
            .fill(.white.opacity(0.04))
            .frame(width: 240, height: 240)
            .blur(radius: 54)
            .offset(x: 170, y: -135)
    }

    private var cardHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Tr("星言虚拟卡"))
                    .font(pf(15, .semibold))
                    .foregroundStyle(.white)
                Text("STAR PAY · DEVICE CARD")
                    .font(pfExact(8.5, .bold))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer()
            Image(systemName: "wave.3.right.circle.fill")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.white.opacity(0.42))
        }
    }

    private var cardNumber: some View {
        Text(numberText)
            .font(Font(UIFont.monospacedDigitSystemFont(ofSize: 18, weight: .semibold)))
            .tracking(1.1)
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }

    private var cardFooter: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Tr("持卡人"))
                    .font(pfExact(8.5, .medium))
                    .foregroundStyle(.white.opacity(0.38))
                Text(cardholder)
                    .font(pfExact(10.5, .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if exists {
                cardMetric(Tr("有效期"), expiryText)
                if revealed {
                    cardMetric(Tr("安全码"), info?.cvv ?? "•••")
                }
            }
        }
    }

    private var cardholder: String {
        (app.me?.nickname ?? app.me?.username ?? "STAR PAY").uppercased()
    }

    private var numberText: String {
        if exists, revealed, let number = info?.number, !number.isEmpty {
            return groupedVirtualCardNumber(number)
        }
        return "••••  ••••  ••••  " + (info?.last4 ?? "••••")
    }

    private var expiryText: String {
        String(format: "%02d/%02d",
               info?.expMonth ?? 0,
               (info?.expYear ?? 2000) % 100)
    }

    private func cardMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(pfExact(8.5, .medium))
                .foregroundStyle(.white.opacity(0.38))
            Text(value)
                .font(pfMoney(10.5, .semibold))
                .foregroundStyle(.white.opacity(0.82))
        }
    }

    private var details: some View {
        PayGroupCard {
            VStack(spacing: 0) {
                PayDetailRow(title: Tr("卡片状态"), value: frozen ? Tr("已冻结") : Tr("正常"),
                             valueColor: frozen ? PayVisual.warning : PayVisual.success)
                HairLine(inset: 18)
                PayDetailRow(title: Tr("卡号版本"), value: "\(info?.generation ?? 1)")
                HairLine(inset: 18)
                PayDetailRow(title: Tr("发卡网络"), value: Tr("星言内部测试，不接外部卡组织"))
                if revealed, let number = info?.number {
                    HairLine(inset: 18)
                    PayDetailRow(title: Tr("复制卡号"), value: number, copyValue: number)
                }
                if revealed, let cvv = info?.cvv {
                    HairLine(inset: 18)
                    PayDetailRow(title: Tr("复制安全码"), value: cvv, copyValue: cvv)
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                if revealed { Task { await hideCard() } }
                else { run("reveal") }
            } label: {
                Label(revealed ? Tr("隐藏卡号") : Tr("显示卡号"),
                      systemImage: revealed ? "eye.slash.fill" : "faceid")
            }
            .buttonStyle(PayPrimaryButtonStyle(tint: PayVisual.tint, enabled: !busy))
            .disabled(busy)

            HStack(spacing: 10) {
                Button {
                    run(frozen ? "unfreeze" : "freeze")
                } label: {
                    Label(frozen ? Tr("解冻卡片") : Tr("冻结卡片"),
                          systemImage: frozen ? "lock.open.fill" : "snowflake")
                }
                .buttonStyle(PaySecondaryButtonStyle(tint: frozen ? PayVisual.success : PayVisual.warning))
                .disabled(busy)

                Button {
                    confirmRotate = true
                } label: {
                    Label(Tr("更换卡号"), systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(PaySecondaryButtonStyle(tint: PayVisual.tint))
                .disabled(busy)
            }
        }
    }

    private func load() async {
        do {
            info = try await API.shared.virtualCard()
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? Tr("虚拟卡加载失败")
        }
    }

    private func run(_ action: String) {
        guard !busy else { return }
        busy = true
        error = ""
        Task {
            let reason = action == "reveal"
                ? Tr("验证身份，查看虚拟卡号")
                : Tr("验证身份，管理虚拟卡")
            let auth = await Biometrics.authenticate(reason: reason)
            guard auth.ok else {
                busy = false
                if !auth.message.isEmpty { error = auth.message }
                return
            }
            do {
                let result = try await API.shared.virtualCardAction(action, verified: true)
                info = result
                revealed = action == "reveal"
                if action == "reveal" { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                if action == "rotate" { app.show(Tr("虚拟卡号已更换")) }
                if action == "issue" { app.show(Tr("虚拟卡号已生成")) }
            } catch {
                self.error = (error as? APIError)?.errorDescription ?? Tr("操作失败，请重试")
            }
            busy = false
        }
    }

    private func hideCard() async {
        revealed = false
        info = try? await API.shared.virtualCard()
    }
}

private func groupedVirtualCardNumber(_ number: String) -> String {
    var parts: [String] = []
    var index = number.startIndex
    while index < number.endIndex {
        let end = number.index(index, offsetBy: 4, limitedBy: number.endIndex) ?? number.endIndex
        parts.append(String(number[index..<end]))
        index = end
    }
    return parts.joined(separator: "  ")
}
