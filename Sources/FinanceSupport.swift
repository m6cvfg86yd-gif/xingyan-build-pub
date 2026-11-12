import SwiftUI
import UIKit

struct FinanceSupportView: View {
    @ObservedObject private var lang = LangStore.shared
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    var transactionId: String = ""
    var transactionLabel: String = ""

    @State private var cfg: API.FinanceSupportPayload?
    @State private var mode: Mode = .home
    @State private var chatId = ""
    @State private var messages: [Message] = []
    @State private var input = ""
    @State private var busy = false
    @State private var sending = false
    @State private var errorText = ""
    @State private var selectedReference = ""
    @State private var pendingIssue = ""

    private enum Mode { case home, chat }

    private var me: String { app.me?.id ?? "" }
    private var agentName: String { cfg?.agent?.nickname ?? Tr("星言金融客服") }
    private var latestCase: API.SupportTicket? {
        (cfg?.tickets ?? []).first(where: { ($0.status ?? "") != "done" })
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: mode == .chat ? agentName : Tr("金融客服"),
                   back: {
                       if mode == .chat {
                           mode = .home
                           Task { await reload() }
                       } else {
                           dismiss()
                       }
                   }) {
                if mode == .home {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(cfg?.queue?.offDuty == true ? PayVisual.warning : PayVisual.success)
                            .frame(width: 7, height: 7)
                        Text(cfg?.queue?.offDuty == true ? Tr("留言中") : Tr("人工在线"))
                            .font(pf(13, .medium))
                            .foregroundColor(PayVisual.secondaryInk)
                    }
                    .frame(height: L.navH)
                    .padding(.trailing, 16)
                }
            }

            if mode == .home {
                homeBody
            } else {
                chatBody
            }
        }
        .background(PayVisual.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack {
            if mode == .chat { mode = .home } else { dismiss() }
        }
        .hidesTabBar()
        .task { await boot() }
        .task(id: chatId) {
            guard !chatId.isEmpty else { return }
            while !Task.isCancelled {
                await loadMessages()
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                await reload(silent: true)
            }
        }
    }

    private var homeBody: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                hero
                safety
                quickIssues

                if !transactionId.isEmpty || !transactionLabel.isEmpty {
                    linkedTransaction
                }
                if let ticket = latestCase {
                    activeCase(ticket)
                }
                if let rows = cfg?.recentTransactions, !rows.isEmpty {
                    recentTransactions(rows)
                }
                serviceFoot
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, max(28, L.safeBottom))
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Color.white.opacity(0.18))
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 5) {
                    Text(Tr("星言金融客服"))
                        .font(pf(20, .semibold))
                        .foregroundStyle(.white)
                    Text(Tr("资金问题专属服务 · 全程加密留痕"))
                        .font(pf(12.5, .medium))
                        .foregroundStyle(Color.white.opacity(0.78))
                }
                Spacer(minLength: 4)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.white.opacity(0.9))
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(cfg?.queue?.offDuty == true ? PayVisual.warning : PayVisual.success)
                        .frame(width: 8, height: 8)
                    Text(cfg?.queue?.offDuty == true ? Tr("非值班时段 · 留言照常受理") : Tr("金融专员在线"))
                        .font(pf(13, .semibold))
                        .foregroundStyle(.white)
                }
                Text(cfg?.workTime ?? Tr("金融客服 09:00 - 22:00"))
                    .font(pf(12.5))
                    .foregroundStyle(Color.white.opacity(0.72))
            }

            Button {
                pendingIssue = ""
                Task { await connectAndOpen("") }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    Text(busy ? Tr("正在接入…") : Tr("联系金融专员"))
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                }
                .font(pf(15.5, .semibold))
                .foregroundStyle(PayVisual.tint)
                .padding(.horizontal, 16)
                .frame(height: 50)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(busy)
        }
        .padding(20)
        .background {
            LinearGradient(
                colors: [Color(hex: 0x0A84FF), Color(hex: 0x0066D6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var safety: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(PayVisual.success)
                .frame(width: 34, height: 34)
                .background(PayVisual.success.opacity(0.11), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(Tr("资金安全提醒"))
                    .font(pf(15, .semibold))
                    .foregroundStyle(C.label)
                Text(Tr("金融客服不会索要验证码、支付密码、完整银行卡号，也不会要求你转账或共享屏幕。"))
                    .font(pf(13))
                    .foregroundStyle(PayVisual.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(PayVisual.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var quickIssues: some View {
        VStack(alignment: .leading, spacing: 11) {
            PaySectionLabel(text: Tr("哪里出了问题？"))
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                issueButton("tray.and.arrow.down", Tr("转账未到账"),
                            Tr("核查到账与退回状态"), PayVisual.tint,
                            Tr("转账一直没到账，请帮我核查。"), "资金未到账")
                issueButton("exclamationmark.magnifyingglass", Tr("扣款有疑问"),
                            Tr("核对金额与交易单号"), PayVisual.danger,
                            Tr("我对一笔扣款有疑问，请帮我核查。"), "扣款与账单")
                issueButton("arrow.uturn.backward.circle", Tr("退款与退回"),
                            Tr("查看退款进度"), PayVisual.success,
                            Tr("我想查询退款进度。"), "红包与退款")
                issueButton("person.badge.shield.checkmark", Tr("账户受限"),
                            Tr("风控与实名核查"), PayVisual.warning,
                            Tr("我的支付或账户被限制了，需要人工核查。"), "账户限制")
                issueButton("creditcard", Tr("支付设置"),
                            Tr("密码与支付方式"), PayVisual.tint,
                            Tr("我想咨询支付密码或支付方式问题。"), "支付咨询")
                issueButton("ellipsis.bubble", Tr("其他资金问题"),
                            Tr("交给金融专员处理"), PayVisual.secondaryInk,
                            Tr("我有其他资金问题需要人工协助。"), "支付咨询")
            }
        }
    }

    private func issueButton(_ symbol: String, _ title: String, _ subtitle: String,
                             _ tint: Color, _ issue: String, _ category: String) -> some View {
        Button {
            pendingIssue = issue
            Task { await connectAndOpen(issue, category: category) }
        } label: {
            VStack(alignment: .leading, spacing: 11) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(pf(15, .semibold))
                        .foregroundStyle(C.label)
                    Text(subtitle)
                        .font(pf(11.8))
                        .foregroundStyle(PayVisual.secondaryInk)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .padding(14)
            .background(PayVisual.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(PayVisual.separator, lineWidth: 0.7)
            }
        }
        .buttonStyle(.plain)
    }

    private var linkedTransaction: some View {
        VStack(alignment: .leading, spacing: 10) {
            PaySectionLabel(text: Tr("本次咨询"))
            PayGroupCard {
                Button {
                    let issue = Tr("我想咨询这笔交易：") + transactionLabel
                    pendingIssue = issue
                    Task { await connectAndOpen(issue, category: "交易争议") }
                } label: {
                    HStack(spacing: 13) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(PayVisual.tint)
                            .frame(width: 38, height: 38)
                            .background(PayVisual.tint.opacity(0.11), in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(transactionLabel.isEmpty ? Tr("关联交易") : transactionLabel)
                                .font(pf(15.5, .semibold))
                                .foregroundStyle(C.label)
                            if !transactionId.isEmpty {
                                Text(transactionId)
                                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                                    .foregroundStyle(PayVisual.secondaryInk)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 6)
                        Text(Tr("核查"))
                            .font(pf(13.5, .semibold))
                            .foregroundStyle(PayVisual.tint)
                        Chevron(size: 8, line: 1.5, color: PayVisual.secondaryInk)
                    }
                    .padding(15)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func activeCase(_ ticket: API.SupportTicket) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PaySectionLabel(text: Tr("正在处理的工单"))
            Button {
                selectedReference = ticket.reference ?? ""
                Task { await connectAndOpen("") }
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 9) {
                        Image(systemName: caseSymbol(ticket))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(caseTone(ticket))
                        Text(caseTitle(ticket))
                            .font(pf(15.5, .semibold))
                            .foregroundStyle(C.label)
                        Spacer(minLength: 6)
                        PayStatusPill(text: caseTitle(ticket), tone: casePillTone(ticket))
                    }
                    Text(ticket.content ?? "")
                        .font(pf(13.2))
                        .foregroundStyle(PayVisual.secondaryInk)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        Text(ticket.id)
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        Spacer(minLength: 4)
                        Text(Tr("继续沟通"))
                            .font(pf(12.8, .semibold))
                            .foregroundStyle(PayVisual.tint)
                        Chevron(size: 7, line: 1.4, color: PayVisual.secondaryInk)
                    }
                    .foregroundStyle(PayVisual.secondaryInk)
                }
                .padding(16)
                .background(PayVisual.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(caseTone(ticket).opacity(0.22), lineWidth: 0.8)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func recentTransactions(_ rows: [API.FinanceSupportTransaction]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PaySectionLabel(text: Tr("最近交易"))
            PayGroupCard {
                ForEach(Array(rows.prefix(5).enumerated()), id: \.element.id) { index, row in
                    if index > 0 { HairLine(inset: 16) }
                    Button {
                        selectedReference = row.ref?.isEmpty == false ? row.ref! : row.id
                        let sign = (row.delta ?? 0) < 0 ? "-" : "+"
                        let label = sign + "¥" + abs(row.delta ?? 0).formatted(.number.precision(.fractionLength(2)))
                        pendingIssue = Tr("我想咨询这笔交易：") + label
                        Task { await connectAndOpen(pendingIssue, category: "交易争议") }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: (row.delta ?? 0) < 0 ? "arrow.up.right" : "arrow.down.left")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle((row.delta ?? 0) < 0 ? PayVisual.danger : PayVisual.success)
                                .frame(width: 34, height: 34)
                                .background((row.delta ?? 0) < 0
                                            ? PayVisual.danger.opacity(0.10)
                                            : PayVisual.success.opacity(0.10),
                                            in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.reason?.isEmpty == false ? row.reason! : Tr("资金变动"))
                                    .font(pf(14.5, .medium))
                                    .foregroundStyle(C.label)
                                    .lineLimit(1)
                                Text(shortFinanceTime(row.at ?? ""))
                                    .font(pf(11.8))
                                    .foregroundStyle(PayVisual.secondaryInk)
                            }
                            Spacer(minLength: 8)
                            Text(((row.delta ?? 0) < 0 ? "-" : "+") + "¥"
                                 + abs(row.delta ?? 0).formatted(.number.precision(.fractionLength(2))))
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle((row.delta ?? 0) < 0 ? C.label : PayVisual.success)
                        }
                        .padding(.horizontal, 15)
                        .frame(height: 60)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var serviceFoot: some View {
        Text(Tr("金融工单会加密留痕并记录处理人；如遇紧急诈骗，请先停止转账并联系银行冻结账户。"))
            .font(pf(11.8))
            .foregroundStyle(PayVisual.secondaryInk)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.top, 4)
    }

    private var chatBody: some View {
        VStack(spacing: 0) {
            chatTrustBar
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 13) {
                        agentIntro
                        ForEach(messages) { message in
                            financeBubble(message)
                        }
                        if !quickPrompts.isEmpty, messages.count < 5 {
                            quickPromptRow
                        }
                        Color.clear.frame(height: 10).id("finance-bottom")
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                }
                .onChange(of: messages.count) { _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("finance-bottom", anchor: .bottom)
                    }
                }
            }
            chatInput
        }
        .background(PayVisual.canvas)
    }

    private var chatTrustBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10.5, weight: .semibold))
            Text(Tr("金融会话加密保护 · 不会索要密码或验证码"))
                .font(pf(11.8, .medium))
            Spacer(minLength: 0)
            if let ticket = latestCase {
                Text(caseTitle(ticket))
                    .font(pf(11.5, .semibold))
                    .foregroundStyle(caseTone(ticket))
            }
        }
        .foregroundStyle(PayVisual.secondaryInk)
        .padding(.horizontal, 15)
        .frame(height: 38)
        .background(PayVisual.card)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PayVisual.separator).frame(height: 0.5)
        }
    }

    private var agentIntro: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(PayVisual.tint.opacity(0.12))
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(PayVisual.tint)
            }
            .frame(width: 54, height: 54)
            Text(agentName)
                .font(pf(15.5, .semibold))
                .foregroundStyle(C.label)
            Text(cfg?.greet ?? Tr("请说明交易时间、金额和问题。"))
                .font(pf(12.5))
                .foregroundStyle(PayVisual.secondaryInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private func financeBubble(_ message: Message) -> some View {
        let mine = message.senderId == me
        return HStack(alignment: .bottom, spacing: 8) {
            if mine { Spacer(minLength: 58) }
            if !mine {
                ZStack {
                    Circle().fill(PayVisual.tint.opacity(0.12))
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(PayVisual.tint)
                }
                .frame(width: 30, height: 30)
            }
            VStack(alignment: mine ? .trailing : .leading, spacing: 5) {
                if !mine {
                    Text(Tr("星言金融客服 · 官方"))
                        .font(pf(10.8, .medium))
                        .foregroundStyle(PayVisual.secondaryInk)
                        .padding(.leading, 4)
                }
                Text(message.body)
                    .font(pf(15))
                    .foregroundStyle(mine ? .white : C.label)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .fill(mine ? PayVisual.tint : PayVisual.card)
                    )
                    .overlay {
                        if !mine {
                            RoundedRectangle(cornerRadius: 17, style: .continuous)
                                .stroke(PayVisual.separator, lineWidth: 0.6)
                        }
                    }
                if let id = financeTicketID(in: message.body), !mine {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.seal.fill")
                        Text(id)
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(PayVisual.secondaryInk)
                    .padding(.leading, 4)
                }
            }
            if !mine { Spacer(minLength: 42) }
        }
    }

    private var quickPrompts: [String] {
        if latestCase?.priority == "critical" {
            return [Tr("我已经停止转账"), Tr("这笔不是我操作的"), Tr("我要补充交易单号")]
        }
        return [Tr("转账一直没到账"), Tr("我要转人工"), Tr("查询退款进度")]
    }

    private var quickPromptRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(quickPrompts, id: \.self) { prompt in
                    Button {
                        send(prompt)
                    } label: {
                        Text(prompt)
                            .font(pf(12.5, .medium))
                            .foregroundStyle(PayVisual.tint)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(PayVisual.card, in: Capsule())
                            .overlay { Capsule().stroke(PayVisual.tint.opacity(0.22), lineWidth: 0.8) }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var chatInput: some View {
        VStack(spacing: 7) {
            if !errorText.isEmpty {
                Text(errorText)
                    .font(pf(12))
                    .foregroundStyle(PayVisual.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
            }
            HStack(alignment: .bottom, spacing: 8) {
                Button {
                    send(Tr("人工"))
                } label: {
                    Image(systemName: "person.wave.2.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(PayVisual.tint)
                        .frame(width: 38, height: 38)
                        .background(PayVisual.inset, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(sending)

                TextField(Tr("描述资金问题…"), text: $input, axis: .vertical)
                    .font(pf(15))
                    .lineLimit(1...4)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
                    .background(PayVisual.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(PayVisual.separator, lineWidth: 0.7)
                    }

                Button {
                    send(input)
                } label: {
                    Image(systemName: sending ? "ellipsis" : "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? PayVisual.secondaryInk.opacity(0.35) : PayVisual.tint,
                                    in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(sending || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, max(8, L.safeBottom))
        }
        .background(PayVisual.canvas)
    }

    private func boot() async {
        if cfg == nil { await reload() }
    }

    private func reload(silent: Bool = false) async {
        if !silent { busy = true }
        if let payload = try? await API.shared.financeSupport() {
            cfg = payload
        }
        if !silent { busy = false }
    }

    private func connectAndOpen(_ issue: String, category: String = "支付咨询") async {
        guard !busy else { return }
        busy = true
        errorText = ""
        do {
            let human = try await API.shared.financeSupportHuman()
            chatId = human.chatId
            mode = .chat
            await loadMessages()
            if !issue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                send(issue)
            }
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? Tr("金融客服暂时接不上，请稍后重试")
            app.show(errorText)
        }
        busy = false
    }

    private func loadMessages() async {
        guard !chatId.isEmpty else { return }
        if let payload = try? await API.shared.messages(chatId: chatId, limit: 80) {
            messages = payload.messages.filter { $0.kindName != "system" }
        }
    }

    private func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !chatId.isEmpty, !sending else { return }
        input = ""
        sending = true
        errorText = ""
        Task {
            do {
                let sent = try await API.shared.send(chatId: chatId, kind: "text", content: text)
                if let message = sent, !messages.contains(where: { $0.id == message.id }) {
                    messages.append(message)
                }
                try? await Task.sleep(nanoseconds: 450_000_000)
                await loadMessages()
                await reload(silent: true)
            } catch {
                errorText = (error as? LocalizedError)?.errorDescription ?? Tr("发送失败，请重试")
            }
            sending = false
        }
    }

    private func financeTicketID(in text: String) -> String? {
        guard let range = text.range(of: #"ftk[A-Za-z0-9_-]+"#, options: .regularExpression) else { return nil }
        return String(text[range])
    }

    private func caseTitle(_ ticket: API.SupportTicket) -> String {
        if (ticket.status ?? "") == "done" { return Tr("已完成") }
        if (ticket.status ?? "") == "replied" { return Tr("已回复") }
        if ticket.priority == "critical" { return Tr("安全事件核查中") }
        if ticket.priority == "high" { return Tr("人工核查中") }
        return Tr("已进入人工队列")
    }

    private func caseTone(_ ticket: API.SupportTicket) -> Color {
        if ticket.priority == "critical" { return PayVisual.danger }
        if ticket.priority == "high" { return PayVisual.warning }
        if (ticket.status ?? "") == "replied" { return PayVisual.success }
        return PayVisual.tint
    }

    private func casePillTone(_ ticket: API.SupportTicket) -> PayStatusPill.Tone {
        if ticket.priority == "critical" { return .danger }
        if ticket.priority == "high" { return .warning }
        if (ticket.status ?? "") == "replied" { return .success }
        return .processing
    }

    private func caseSymbol(_ ticket: API.SupportTicket) -> String {
        if ticket.priority == "critical" { return "exclamationmark.shield.fill" }
        if ticket.priority == "high" { return "person.badge.clock.fill" }
        return "checkmark.bubble.fill"
    }

    private func shortFinanceTime(_ raw: String) -> String {
        if let date = TimeFmt.date(raw) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "MM-dd HH:mm"
            return formatter.string(from: date)
        }
        return raw.replacingOccurrences(of: "T", with: " ").prefix(16).description
    }
}
