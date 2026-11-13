import SwiftUI

struct KefuPage: View {
    @ObservedObject private var lang = LangStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var chatId = ""
    @State private var messages: [Message] = []
    @State private var input = ""
    @State private var loading = true
    @State private var sending = false
    @State private var quick: [API.SupportItem] = []
    @State private var greet = ""
    @State private var workTime = ""
    @State private var agentName = "在线客服"
    @State private var agentAvatar = ""
    @State private var showFAQ = false
    @State private var humanAsked = false
    @State private var connectTip = ""

    private var myId: String { app.me?.id ?? "" }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            header
                                .padding(.bottom, 12)

                            if loading {
                                ProgressView(Tr("正在连接星言支持…"))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 28)
                            } else if !connectTip.isEmpty {
                                reconnectBlock
                            }

                            ForEach(messages) { message in
                                kefuBubble(message)
                            }

                            Color.clear
                                .frame(height: 10)
                                .id("bottom")
                        }
                        .padding(.horizontal, 12)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: messages.count) { _ in
                        withAnimation(.easeOut(duration: 0.22)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
                .background(Color(uiColor: .systemGroupedBackground))
            }
            .navigationTitle(agentName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(Tr("关闭"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        askHuman()
                    } label: {
                        Image(systemName: "person.badge.headphones")
                    }
                    .accessibilityLabel(Tr("转人工"))
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                composer
            }
            .task { await start() }
            .sheet(isPresented: $showFAQ) {
                FAQView().environmentObject(app)
            }
        }
        .hidesTabBar()
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 13) {
                RPAvatar(path: agentAvatar, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(agentName)
                        .font(.headline)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(.green)
                            .frame(width: 7, height: 7)
                        Text(workTime.isEmpty ? Tr("在线支持") : workTime)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button { showFAQ = true } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 21))
                }
                .buttonStyle(.plain)
            }

            if !greet.isEmpty {
                Text(greet)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.background, in: RoundedRectangle(cornerRadius: 14,
                                                                  style: .continuous))
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.6)
        }
        .padding(.top, 8)
    }

    private var reconnectBlock: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.secondary)
            Text(connectTip)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(Tr("重新连接")) {
                connectTip = ""
                Task { await start() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var composer: some View {
        VStack(spacing: 0) {
            quickRow
            HStack(alignment: .bottom, spacing: 10) {
                TextField(Tr("描述你遇到的问题…"), text: $input, axis: .vertical)
                    .font(.body)
                    .lineLimit(1...5)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(Color(uiColor: .secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 19, style: .continuous)
                            .stroke(Color.primary.opacity(0.07), lineWidth: 0.6)
                    }

                Button {
                    sendMessage(input)
                } label: {
                    Group {
                        if sending {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .bold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? Color.secondary.opacity(0.45) : Color.accentColor,
                        in: Circle()
                    )
                }
                .buttonStyle(.plain)
                .disabled(sending || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.top, 7)
            .padding(.bottom, 8)
            .background(.bar)
        }
    }

    @ViewBuilder private func kefuBubble(_ m: Message) -> some View {
        let mine = (m.senderId == myId)
        VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: 7) {
                if mine { Spacer(minLength: 54) }
                if !mine {
                    RPAvatar(path: agentAvatar, size: 28)
                }
                Text(m.body)
                    .font(.body)
                    .foregroundStyle(mine ? Color.white : Color.primary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(
                        mine ? Color.accentColor : Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                    )
                    .fixedSize(horizontal: false, vertical: true)
                if !mine { Spacer(minLength: 54) }
            }
            Text(TimeFmt.bubble(m.createdAt))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.leading, mine ? 0 : 35)
        }
        .padding(.bottom, 12)
    }

    @ViewBuilder private var quickRow: some View {
        if !quick.isEmpty && messages.count <= 3 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(quick.enumerated()), id: \.offset) { _, it in
                        Button { sendMessage(it.q) } label: {
                            Text(it.q)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .frame(height: 30)
                                .background(Color(uiColor: .secondarySystemGroupedBackground),
                                            in: Capsule())
                                .overlay {
                                    Capsule()
                                        .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.top, 7)
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField(Tr("说说你遇到的问题…"), text: $input, axis: .vertical)
                .font(pf(15))
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background { CardGlassBox(radius: 8) }
            Button {
                sendMessage(input)
            } label: {
                Text(sending ? "…" : Tr("发送"))
                    .font(pf(15, .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .background(Capsule().fill(input.trimmingCharacters(in: .whitespaces).isEmpty ? C.subLabel : C.green))
            }
            .buttonStyle(.plain)
            .disabled(sending || input.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(C.pageBg)
    }

    private func start() async {

        if let cfg = try? await API.shared.support() {
            greet = cfg.greet ?? ""
            workTime = cfg.workTime ?? ""
            agentName = cfg.agent?.nickname ?? "在线客服"
            agentAvatar = cfg.agent?.avatar ?? ""
            var seen = Set<String>()
            quick = (cfg.categories ?? []).compactMap { c in
                (c.items ?? []).first.flatMap { seen.insert($0.q).inserted ? $0 : nil }
            }
        }
        if let r = try? await API.shared.supportHuman() {
            chatId = r.chatId
        }
        await loadMessages()

        if chatId.isEmpty { connectTip = "客服暂时接不上，点下面重试一次" }
        loading = false
    }

    private func loadMessages() async {
        guard !chatId.isEmpty else { return }
        if let r = try? await API.shared.messages(chatId: chatId, limit: 50) {
            messages = r.messages.filter { $0.kindName != "system" }
        }
    }

    private func sendMessage(_ text: String) {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !chatId.isEmpty, !sending else { return }
        sending = true
        input = ""
        Task {
            if let m = try? await API.shared.send(chatId: chatId, kind: "text", content: body) {
                messages.append(m)
            }
            sending = false

            for _ in 0..<6 {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await loadMessages()
                if let last = messages.last, last.senderId != myId { break }
            }
        }
    }

    private func askHuman() {
        if humanAsked {
            app.show(Tr("已经帮你转人工了，客服看到会在这里回复"))
            return
        }
        humanAsked = true
        sendMessage("人工")
    }
}
