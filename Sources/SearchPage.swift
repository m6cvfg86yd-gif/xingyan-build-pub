import SwiftUI
import UIKit

struct SearchPage: View {
    @ObservedObject private var lang = LangStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    var onOpenChat: ((Chat) -> Void)? = nil
    var onOpenUser: ((User) -> Void)? = nil

    var voiceBall: Bool = false

    @State private var q = ""
    @State private var scope = "all"

    @State private var history: [String] = []

    @State private var hot: [String] = SearchSuggest.shown
    @FocusState private var focused: Bool

    @StateObject private var dictation = Dictation()

    @State private var kbHeight: CGFloat = 0
    @State private var inputMethodChanging = false
    @State private var inputMethodChangeToken = 0
    @State private var showAI = false
    @State private var showBrowser = false
    @State private var showDrop = false

    private struct OfficialTool: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let symbol: String
        let keywords: String
    }

    private let officialTools: [OfficialTool] = [
        OfficialTool(id: "ai", title: "小星 AI",
                     subtitle: "星言助手 · 问答、创作、联网搜索",
                     symbol: "sparkles",
                     keywords: "小星 AI ai 人工智能 星言助手 小星助手 官方助手 语音 问答 创作 搜索 助手 官方工具 工具"),
        OfficialTool(id: "browser", title: "内置浏览器",
                     subtitle: "在星言里搜索和打开网页",
                     symbol: "safari",
                     keywords: "内置浏览器 浏览器 网页 网站 打开网页 搜索 官方工具 工具"),
        OfficialTool(id: "drop", title: "文件快传",
                     subtitle: "面对面传照片、视频和文件",
                     symbol: "dot.radiowaves.left.and.right",
                     keywords: "文件快传 快传 文件 传文件 文件传输 面对面 传输 官方工具 工具")
    ]

    private let scopes: [(String, String, String)] = [
        ("all", "全部", "magnifyingglass"),
        ("chat", "聊天记录", "bubble.left.and.bubble.right"),
        ("user", "联系人", "person.crop.circle"),
        ("group", "群聊", "person.2"),
        ("moments", "朋友圈", "photo.on.rectangle.angled"),
        ("feed", "视频号", "play.rectangle")
    ]

    private var key: String { q.trimmingCharacters(in: .whitespaces) }

    private var chats: [Chat] {
        let base = app.chats.filter { $0.botRank != 0 }
        if key.isEmpty { return [] }
        return base.filter { c in
            chatTitle(c).localizedCaseInsensitiveContains(key)
        }
    }

    private func chatTitle(_ c: Chat) -> String {
        if let t = c.title, !t.isEmpty { return t }
        if let peerId = (c.memberIds ?? []).first(where: { $0 != (app.me?.id ?? "") }),
           let u = app.contact(for: peerId) {
            return u.name
        }
        return Tr("聊天")
    }

    private func chatAvatar(_ c: Chat) -> String {
        if let a = c.avatar, !a.isEmpty { return a }
        if let peerId = (c.memberIds ?? []).first(where: { $0 != (app.me?.id ?? "") }),
           let u = app.contact(for: peerId) {
            return u.avatarPath
        }
        return ""
    }
    private var groups: [Chat] { scope == "all" || scope == "group" ? chats.filter { $0.type == "group" } : [] }
    private var directChats: [Chat] { scope == "group" ? [] : chats.filter { $0.type != "group" } }
    private var matchedTools: [OfficialTool] {
        guard !key.isEmpty else { return [] }
        let needle = key.lowercased()
        return officialTools.filter {
            $0.title.lowercased().contains(needle)
                || $0.subtitle.lowercased().contains(needle)
                || $0.keywords.lowercased().contains(needle)
        }
    }
    private var contacts: [User] {
        if key.isEmpty || scope == "chat" || scope == "group" { return [] }
        return app.contacts.filter { ($0.nickname ?? "").localizedCaseInsensitiveContains(key)
            || ($0.username ?? "").localizedCaseInsensitiveContains(key) }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(C.searchIcon)
                    TextField(Tr("搜索"), text: $q)
                        .font(pf(14.5))
                        .focused($focused)
                        .submitLabel(.search)
                        .onSubmit { remember(key) }
                    if !key.isEmpty {
                        Button { q = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15)).foregroundColor(C.searchIcon)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(C.searchBg))

                Button { dismiss() } label: {
                    Text(Tr("取消")).font(pf(16)).foregroundColor(C.label)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if key.isEmpty {
                        scopeRow
                        if !history.isEmpty { historyBlock }
                        if !hot.isEmpty { suggestBlock }
                        Text(Tr("输入关键词就能搜会话、联系人和群聊"))
                            .font(pf(12.5)).foregroundColor(C.subLabel)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 30)
                    } else {
                        scopeRow
                        if !matchedTools.isEmpty { toolBlock }
                        if !directChats.isEmpty { sectionBlock(Tr("聊天记录"), directChats, isGroup: false) }
                        if !groups.isEmpty { sectionBlock(Tr("群聊"), groups, isGroup: true) }
                        if !contacts.isEmpty { contactBlock }
                        if directChats.isEmpty && groups.isEmpty && contacts.isEmpty
                            && matchedTools.isEmpty {
                            Text(Tr("没有找到 ") + "「\(key)」")
                                .font(pf(14)).foregroundColor(C.subLabel)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        }
                    }
                    Color.clear.frame(height: 24)
                }
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea())

        GeometryReader { g in
            if voiceBall, kbHeight > 1, !inputMethodChanging {
                VoiceOrb(level: dictation.listening ? 0.55 : 0.16,
                         diameter: 92,
                         listening: dictation.listening,
                         metalShader: false)
                    .position(x: g.size.width / 2,
                              y: max(70, g.size.height - kbHeight - 62))
                    .transition(.opacity.combined(with: .scale(scale: 0.86)))
                    .onTapGesture {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()

                        dictation.toggle { t in q = t }
                    }
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .allowsHitTesting(voiceBall && kbHeight > 1)
        .animation(.easeOut(duration: 0.22), value: kbHeight)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            focused = true
            history = SearchHistory.all
        }

        .task { await loadHot() }

        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { n in
            guard let f = n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let h = max(0, UIScreen.main.bounds.height - f.minY)
            if abs(h - kbHeight) > 0.5 {
                if voiceBall { beginInputMethodTransition() }
                withAnimation(.easeOut(duration: 0.22)) { kbHeight = h }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            if kbHeight != 0 {
                dictation.stop()
                withAnimation(.easeOut(duration: 0.22)) { kbHeight = 0 }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UITextInputMode.currentInputModeDidChangeNotification)) { _ in
            beginInputMethodTransition()
        }
        .onDisappear { dictation.stop() }
        .fullScreenCover(isPresented: $showAI) {
            PluginsView().environmentObject(app)
        }
        .fullScreenCover(isPresented: $showBrowser) {
            InAppBrowserView()
        }
        .fullScreenCover(isPresented: $showDrop) {
            FaceToFaceFileSheet(rows: [],
                                avatar: app.me?.avatarPath ?? "",
                                name: app.me?.name ?? "")
                .environmentObject(app)
        }
    }

    private var toolBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Tr("官方工具")).font(pf(13)).foregroundColor(C.subLabel)
                .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 6)
            ForEach(matchedTools) { tool in
                Button {
                    remember(key)
                    switch tool.id {
                    case "ai": showAI = true
                    case "browser": showBrowser = true
                    default: showDrop = true
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: tool.symbol)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(C.green)
                            .frame(width: 40, height: 40)
                            .background(C.cardBg)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(tool.title).font(pf(16)).foregroundColor(C.label)
                            Text(tool.subtitle).font(pf(12.5)).foregroundColor(C.subLabel)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(C.subLabel)
                    }
                    .padding(.horizontal, 14).frame(height: 62)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                HairLine(inset: 66)
            }
        }
        .background(C.cardBg)
        .padding(.top, 10)
    }

    private func beginInputMethodTransition() {
        guard voiceBall else { return }
        // 文字/表情/手写键盘都会重建键盘视图，先卸载 Metal 球再恢复。
        dictation.stop()
        inputMethodChanging = true
        inputMethodChangeToken += 1
        let token = inputMethodChangeToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if token == inputMethodChangeToken { inputMethodChanging = false }
        }
    }

    private var scopeRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(scopes, id: \.0) { s in
                    let on = (scope == s.0)
                    Button { scope = s.0 } label: {
                        HStack(spacing: 5) {
                            Image(systemName: s.2).font(.system(size: 12, weight: .medium))
                            Text(Tr(s.1)).font(pf(13))
                        }
                        .foregroundColor(on ? .white : C.subLabel)
                        .padding(.horizontal, 12).frame(height: 30)
                        .background(Capsule().fill(on ? C.green : C.cardBg))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
    }

    private var historyBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(Tr("搜索历史")).font(pf(13)).foregroundColor(C.subLabel)
                Spacer(minLength: 0)
                Button {
                    SearchHistory.clear()
                    withAnimation(.easeOut(duration: 0.18)) { history = [] }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(C.subLabel)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 8)

            ChipFlow(spacing: 10, lineSpacing: 10) {
                ForEach(history, id: \.self) { r in
                    chip(r, icon: "clock.arrow.circlepath") {
                        remember(r)
                        q = r
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
        }
        .background(C.cardBg)
        .padding(.top, 10)
    }

    private var suggestBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Tr("猜你想搜"))
                .font(pf(13)).foregroundColor(C.subLabel)
                .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 8)
            ChipFlow(spacing: 10, lineSpacing: 10) {
                ForEach(hot, id: \.self) { w in
                    chip(w) {
                        remember(w)
                        q = w
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
        }
        .background(C.cardBg)
        .padding(.top, 10)
    }

    private func chip(_ text: String, icon: String? = nil, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 5) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(C.subLabel)
                }
                Text(Tr(text)).font(pf(14)).foregroundColor(C.label).lineLimit(1)
            }
            .padding(.horizontal, 13)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.dyn(0xEDEDF0, 0x2C2C31)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.dyn(0xD5D5DA, 0x3A3A40), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }

    private func sectionBlock(_ title: String, _ list: [Chat], isGroup: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(pf(13)).foregroundColor(C.subLabel)
                .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 6)
            ForEach(list) { c in
                Button {
                    remember(key)
                    onOpenChat?(c)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Avatar(path: chatAvatar(c), size: 40, radius: isGroup ? 6 : 4)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(chatTitle(c)).font(pf(16)).foregroundColor(C.label)
                            if let p = c.lastMessage?.preview, !p.isEmpty {
                                Text(p).font(pf(12.5)).foregroundColor(C.subLabel).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14).frame(height: 60)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                HairLine(inset: 66)
            }
        }
        .background(C.cardBg)
        .padding(.top, 10)
    }

    private var contactBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Tr("联系人")).font(pf(13)).foregroundColor(C.subLabel)
                .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 6)
            ForEach(contacts) { u in
                Button {
                    remember(key)
                    onOpenUser?(u)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Avatar(path: u.avatarPath, size: 40, radius: 4)
                        Text(u.name).font(pf(16)).foregroundColor(C.label)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14).frame(height: 60)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                HairLine(inset: 66)
            }
        }
        .background(C.cardBg)
        .padding(.top, 10)
    }

    private func remember(_ text: String) {
        SearchHistory.add(text)
        history = SearchHistory.all
    }

    private func loadHot() async {
        if let words = try? await API.shared.searchHot(), !words.isEmpty {
            SearchSuggest.remote = words
            hot = SearchSuggest.shown
        }
    }
}

struct ChipFlow: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > maxW { x = 0; y += lineH + lineSpacing; lineH = 0 }
            x += sz.width + spacing
            lineH = max(lineH, sz.height)
        }
        return CGSize(width: maxW, height: y + lineH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + sz.width > bounds.maxX {
                x = bounds.minX; y += lineH + lineSpacing; lineH = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            lineH = max(lineH, sz.height)
        }
    }
}
