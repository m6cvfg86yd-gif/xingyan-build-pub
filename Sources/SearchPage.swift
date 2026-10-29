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
            searchHeader
            searchField

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if key.isEmpty {
                        scopeRow
                        if !history.isEmpty { historyBlock }
                        if !hot.isEmpty { suggestBlock }
                        idleHint
                    } else {
                        scopeRow
                        if !matchedTools.isEmpty { toolBlock }
                        if !directChats.isEmpty { sectionBlock(Tr("聊天记录"), directChats, isGroup: false) }
                        if !groups.isEmpty { sectionBlock(Tr("群聊"), groups, isGroup: true) }
                        if !contacts.isEmpty { contactBlock }
                        if directChats.isEmpty && groups.isEmpty && contacts.isEmpty
                            && matchedTools.isEmpty {
                            emptyResult
                        }
                    }
                    Color.clear.frame(height: 24)
                }
            }
            .background(Color.clear)
        }
        .background(OrbitTheme.canvas.ignoresSafeArea())
        .background(alignment: .top) {
            searchAura
                .ignoresSafeArea(edges: .top)
        }

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

    private var searchHeader: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(OrbitTheme.ink)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(OrbitTheme.field))
                    .overlay(Circle().stroke(OrbitTheme.divider, lineWidth: 0.7))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(Tr("星轨搜索"))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(OrbitTheme.ink)
                Text(Tr("人脉、消息与官方工具，一次找到"))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(OrbitTheme.secondary)
            }
            Spacer(minLength: 8)
            if !key.isEmpty {
                Text("\(resultCount)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(OrbitTheme.jade)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(Capsule().fill(OrbitTheme.jadeSoft))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, L.safeTop + 4)
        .padding(.bottom, 10)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(OrbitTheme.jade)
            TextField(Tr("搜索人、消息与官方工具"), text: $q)
                .font(.system(size: 15))
                .foregroundStyle(OrbitTheme.ink)
                .focused($focused)
                .submitLabel(.search)
                .onSubmit { remember(key) }
            if !key.isEmpty {
                Button { q = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(OrbitTheme.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background {
            GlassBackground(shape: RoundedRectangle(cornerRadius: 16, style: .continuous),
                            opacity: 0.78,
                            edgeAlpha: 0.42,
                            shadow: true,
                            seed: 0.31,
                            native: true,
                            tint: OrbitTheme.jadeSoft.opacity(0.34))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(OrbitTheme.jade.opacity(focused ? 0.58 : 0.24), lineWidth: 1)
        }
        .padding(.horizontal, 12)
        .animation(.easeOut(duration: 0.18), value: focused)
    }

    private var searchAura: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(colors: [OrbitTheme.jade.opacity(0.15), Color.clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 190)
            Circle()
                .stroke(OrbitTheme.jade.opacity(0.12), lineWidth: 0.8)
                .frame(width: 250, height: 250)
                .offset(x: 108, y: -142)
            Circle()
                .stroke(OrbitTheme.gold.opacity(0.10), lineWidth: 0.7)
                .frame(width: 168, height: 168)
                .offset(x: 148, y: -112)
            Circle()
                .fill(OrbitTheme.gold)
                .frame(width: 4, height: 4)
                .offset(x: -98, y: 94)
        }
        .allowsHitTesting(false)
    }

    private var resultCount: Int {
        matchedTools.count + directChats.count + groups.count + contacts.count
    }

    private var idleHint: some View {
        StarOrbitCard {
            VStack(spacing: 10) {
                StarOrbitIconBadge(symbol: "sparkles", accent: OrbitTheme.jade, size: 48)
                Text(Tr("从一个关键词进入你的星轨"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(OrbitTheme.ink)
                Text(Tr("可以搜会话、联系人、群聊，也能直达小星 AI、浏览器和文件快传。"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(OrbitTheme.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 26)
        }
        .padding(.horizontal, 12)
        .padding(.top, 16)
    }

    private var emptyResult: some View {
        StarOrbitCard {
            VStack(spacing: 9) {
                StarOrbitIconBadge(symbol: "moon.stars", accent: OrbitTheme.gold, size: 48)
                Text(Tr("这条星轨上暂时没有结果"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(OrbitTheme.ink)
                Text("「\(key)」")
                    .font(.system(size: 12.5))
                    .foregroundStyle(OrbitTheme.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        }
        .padding(.horizontal, 12)
        .padding(.top, 16)
    }

    private var toolBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            OrbitSectionLabel(text: Tr("官方工具"), count: matchedTools.count)
                .padding(.horizontal, 16)
            StarOrbitCard {
                VStack(spacing: 0) {
                    ForEach(Array(matchedTools.enumerated()), id: \.element.id) { index, tool in
                        Button {
                            remember(key)
                            switch tool.id {
                            case "ai": showAI = true
                            case "browser": showBrowser = true
                            default: showDrop = true
                            }
                        } label: {
                            HStack(spacing: 12) {
                                StarOrbitIconBadge(symbol: tool.symbol,
                                                   accent: OrbitTheme.jade,
                                                   size: 40)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(tool.title)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(OrbitTheme.ink)
                                    Text(tool.subtitle)
                                        .font(.system(size: 12.5))
                                        .foregroundStyle(OrbitTheme.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(OrbitTheme.tertiary)
                            }
                            .padding(.horizontal, 14).frame(height: 66)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if index < matchedTools.count - 1 {
                            Rectangle().fill(OrbitTheme.divider)
                                .frame(height: 0.7).padding(.leading, 66)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.top, 12)
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
                        HStack(spacing: 6) {
                            Image(systemName: s.2).font(.system(size: 12, weight: .medium))
                            Text(Tr(s.1)).font(.system(size: 12.5, weight: .medium))
                        }
                        .foregroundStyle(on ? AnyShapeStyle(Color.white)
                                            : AnyShapeStyle(OrbitTheme.secondary))
                        .padding(.horizontal, 13).frame(height: 33)
                        .background {
                            Capsule().fill(on
                                ? AnyShapeStyle(LinearGradient(
                                    colors: [OrbitTheme.jadeDeep, OrbitTheme.jade],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing))
                                : AnyShapeStyle(OrbitTheme.field))
                        }
                        .overlay {
                            Capsule().stroke(on ? Color.clear : OrbitTheme.divider,
                                             lineWidth: 0.7)
                        }
                        .shadow(color: on ? OrbitTheme.jade.opacity(0.18) : .clear,
                                radius: 7, y: 3)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var historyBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                OrbitSectionLabel(text: Tr("最近搜索"))
                Button {
                    SearchHistory.clear()
                    withAnimation(.easeOut(duration: 0.18)) { history = [] }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(OrbitTheme.tertiary)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            StarOrbitCard {
                ChipFlow(spacing: 9, lineSpacing: 9) {
                    ForEach(history, id: \.self) { r in
                        chip(r, icon: "clock.arrow.circlepath") {
                            remember(r)
                            q = r
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
            .padding(.horizontal, 12)
        }
        .padding(.top, 12)
    }

    private var suggestBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            OrbitSectionLabel(text: Tr("猜你想搜"), count: hot.count)
                .padding(.horizontal, 16)
            StarOrbitCard {
                ChipFlow(spacing: 9, lineSpacing: 9) {
                    ForEach(hot, id: \.self) { w in
                        chip(w) {
                            remember(w)
                            q = w
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
            .padding(.horizontal, 12)
        }
        .padding(.top, 12)
    }

    private func chip(_ text: String, icon: String? = nil, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 5) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(OrbitTheme.tertiary)
                }
                Text(Tr(text))
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(OrbitTheme.ink)
                    .lineLimit(1)
            }
            .padding(.horizontal, 13)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(OrbitTheme.fieldRaised))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(OrbitTheme.divider, lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }

    private func sectionBlock(_ title: String, _ list: [Chat], isGroup: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            OrbitSectionLabel(text: title, count: list.count)
                .padding(.horizontal, 16)
            StarOrbitCard {
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, c in
                        Button {
                            remember(key)
                            onOpenChat?(c)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Avatar(path: chatAvatar(c), size: 42, radius: isGroup ? 12 : 11)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(chatTitle(c))
                                        .font(.system(size: 15.5, weight: .semibold))
                                        .foregroundStyle(OrbitTheme.ink)
                                    if let p = c.lastMessage?.preview, !p.isEmpty {
                                        Text(p)
                                            .font(.system(size: 12.5))
                                            .foregroundStyle(OrbitTheme.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(OrbitTheme.tertiary)
                            }
                            .padding(.horizontal, 14).frame(height: 64)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if index < list.count - 1 {
                            Rectangle().fill(OrbitTheme.divider)
                                .frame(height: 0.7).padding(.leading, 68)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.top, 12)
    }

    private var contactBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            OrbitSectionLabel(text: Tr("联系人"), count: contacts.count)
                .padding(.horizontal, 16)
            StarOrbitCard {
                VStack(spacing: 0) {
                    ForEach(Array(contacts.enumerated()), id: \.element.id) { index, u in
                        Button {
                            remember(key)
                            onOpenUser?(u)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Avatar(path: u.avatarPath, size: 42, radius: 12)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(u.name)
                                        .font(.system(size: 15.5, weight: .semibold))
                                        .foregroundStyle(OrbitTheme.ink)
                                    if let username = u.username, !username.isEmpty {
                                        Text("@" + username)
                                            .font(.system(size: 12))
                                            .foregroundStyle(OrbitTheme.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(OrbitTheme.tertiary)
                            }
                            .padding(.horizontal, 14).frame(height: 64)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if index < contacts.count - 1 {
                            Rectangle().fill(OrbitTheme.divider)
                                .frame(height: 0.7).padding(.leading, 68)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.top, 12)
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
