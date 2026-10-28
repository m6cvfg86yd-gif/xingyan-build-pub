import SwiftUI

struct NewsFeedView: View {

    var compact: Bool = false

    var refreshToken: Int = 0

    var initialSource: String = "qq"

    var onlyTabs: [NewsChannel]? = nil

    @State private var channels: [NewsChannel] = NewsFeedView.builtinChannels
    @State private var tab = "qq"
    @State private var items: [NewsItem] = []
    @State private var loading = false
    @State private var failed = false

    @State private var loadingTab = ""

    @State private var offset = 0
    @State private var total = 0
    @State private var updatedAt: Double = 0
    @State private var web: WebURL?

    static let builtinChannels: [NewsChannel] = [
        NewsChannel(id: "qq", label: "热点", desc: "热点榜"),
        NewsChannel(id: "toutiao", label: "头条", desc: "今日头条热榜"),
        NewsChannel(id: "sina", label: "要闻", desc: "新浪滚动新闻"),
        NewsChannel(id: "weibo", label: "热搜", desc: "微博热搜榜"),
        NewsChannel(id: "baidu", label: "百度", desc: "百度热搜榜")
    ]

    private var accent: Color { C.green }

    var body: some View {
        premiumFeed
        .task {
            if tab.isEmpty { tab = initialSource }
            if let only = onlyTabs { channels = only }
            if items.isEmpty { await load(tab) }
        }
        .onChange(of: refreshToken) { _ in Task { await load(tab) } }
        .fullScreenCover(item: $web) { w in
            SafariSheet(url: w.url).ignoresSafeArea()
        }
    }

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 24) {
                ForEach(channels) { ch in
                    Button { select(ch.id) } label: {
                        VStack(spacing: 5) {
                            Text(Tr(ch.label))
                                .font(pf(16, tab == ch.id ? .semibold : .regular))
                                .foregroundColor(tab == ch.id ? C.label : C.subLabel)
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(tab == ch.id ? accent : Color.clear)
                                .frame(width: 20, height: 2.5)
                        }
                        .padding(.top, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .background(C.navBg)
        .overlay(alignment: .bottom) { HairLine() }
    }

    private var premiumFeed: some View {
        ScrollView {
            LazyVStack(spacing: 16, pinnedViews: [.sectionHeaders]) {
                Section {
                    if items.isEmpty && loading {
                        premiumLoading
                    } else if items.isEmpty {
                        premiumEmpty
                    } else if isBoard {
                        premiumBoard
                    } else {
                        premiumEditorial
                    }
                } header: {
                    premiumChannelBar
                }
            }
            .padding(.bottom, 34)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .refreshable { await load(tab) }
    }

    private var premiumChannelBar: some View {
        VStack(spacing: 7) {
            if channels.count > 1 {
                Picker("", selection: Binding(
                    get: { tab },
                    set: { select($0) }
                )) {
                    ForEach(channels) { channel in
                        Text(Tr(channel.label)).tag(channel.id)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 16)
            }
            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .font(.caption2.weight(.semibold))
                Text(updatedAt > 0
                     ? Tr("更新于") + " " + timeText(updatedAt)
                     : Tr("实时热点"))
                Spacer(minLength: 0)
                Text(Tr("下拉刷新"))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
        }
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { HairLine() }
    }

    private var premiumLoading: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(accent)
            Text(Tr("正在整理最新内容…"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 74)
    }

    private var premiumEmpty: some View {
        VStack(spacing: 14) {
            Image(systemName: failed ? "wifi.exclamationmark" : "newspaper")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
            Text(failed ? Tr("暂时没有取到内容") : Tr("这里还没有新闻"))
                .font(.headline)
            Text(failed ? Tr("检查网络后再试一次") : Tr("稍后下拉刷新"))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button(Tr("重新加载")) { Task { await load(tab) } }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 64)
    }

    private var premiumEditorial: some View {
        let rows = Array(items)
        return VStack(spacing: 15) {
            if let first = rows.first {
                premiumSectionTitle(Tr("今日焦点"), trailing: first.src)
                premiumHero(first)
            }
            if rows.count > 1 {
                premiumSectionTitle(Tr("最新"), trailing: "\(rows.count - 1) " + Tr("条"))
                VStack(spacing: 0) {
                    ForEach(Array(rows.dropFirst())) { item in
                        Button { open(item) } label: {
                            premiumArticleRow(item)
                        }
                        .buttonStyle(.plain)
                        if item.id != rows.last?.id {
                            HairLine(inset: 15)
                        }
                    }
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(C.hairline, lineWidth: 0.5)
                }
            }
            premiumFooter
        }
        .padding(.horizontal, 16)
    }

    private func premiumSectionTitle(_ title: String, trailing: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            Text(trailing)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.top, 4)
    }

    private func premiumHero(_ item: NewsItem) -> some View {
        Button { open(item) } label: {
            Group {
                if item.cover.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        premiumTag(item)
                        Text(item.title)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                        if let summary = item.summary, !summary.isEmpty {
                            Text(summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        premiumMeta(item, onDark: false)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                } else {
                    ZStack(alignment: .bottomLeading) {
                        RemoteImage(path: item.cover, mode: .fill, maxSide: 1600)
                            .frame(maxWidth: .infinity)
                            .frame(height: 226)
                            .clipped()
                        LinearGradient(colors: [.clear, .black.opacity(0.20),
                                                .black.opacity(0.86)],
                                       startPoint: .top, endPoint: .bottom)
                        VStack(alignment: .leading, spacing: 9) {
                            premiumTag(item, dark: true)
                            Text(item.title)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.leading)
                                .lineLimit(3)
                            premiumMeta(item, onDark: true)
                        }
                        .padding(17)
                    }
                    .frame(height: 226)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(C.hairline, lineWidth: 0.5)
            }
            .shadow(color: Color.black.opacity(0.08), radius: 14, y: 5)
        }
        .buttonStyle(.plain)
    }

    private func premiumArticleRow(_ item: NewsItem) -> some View {
        HStack(alignment: .top, spacing: 13) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    if !item.tagText.isEmpty { tagChip(item.tagText) }
                }
                if let summary = item.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 13.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                premiumMeta(item, onDark: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !item.cover.isEmpty {
                RemoteImage(path: item.cover, mode: .fill, maxSide: 700)
                    .frame(width: 104, height: 78)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func premiumTag(_ item: NewsItem, dark: Bool = false) -> some View {
        if !item.tagText.isEmpty {
            Text(item.tagText)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(dark ? .white : C.red)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(dark ? Color.white.opacity(0.18)
                                       : C.red.opacity(0.10))
                )
        }
    }

    private func premiumMeta(_ item: NewsItem, onDark: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "newspaper.fill")
                .font(.system(size: 10, weight: .semibold))
            Text(item.src)
            let t = timeText(item.at)
            if !t.isEmpty {
                Text("·")
                Text(t)
            }
            if item.hotValue > 0 {
                Text("·")
                Image(systemName: "flame.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text(hotText(item.hotValue))
            }
        }
        .font(.caption)
        .foregroundStyle(onDark ? Color.white.opacity(0.78) : C.subLabel)
        .lineLimit(1)
    }

    private var premiumBoard: some View {
        let rows = Array(items.enumerated())
        return VStack(spacing: 15) {
            premiumSectionTitle(Tr("实时热榜"), trailing: "\(items.count) " + Tr("条"))
            VStack(spacing: 0) {
                ForEach(rows, id: \.element.id) { row in
                    Button { open(row.element) } label: {
                        premiumBoardRow(row.element, index: row.offset)
                    }
                    .buttonStyle(.plain)
                    if row.offset < rows.count - 1 {
                        HairLine(inset: 54)
                    }
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(C.hairline, lineWidth: 0.5)
            }
            premiumFooter
        }
        .padding(.horizontal, 16)
    }

    private func premiumBoardRow(_ item: NewsItem, index: Int) -> some View {
        let number = item.order > 0 ? item.order : index + 1
        return HStack(alignment: .top, spacing: 13) {
            Text("\(number)")
                .font(.system(size: number <= 3 ? 18 : 16,
                              weight: number <= 3 ? .bold : .semibold))
                .monospacedDigit()
                .foregroundStyle(number <= 3 ? C.red : C.subLabel)
                .frame(width: 28, alignment: .leading)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    if !item.tagText.isEmpty { tagChip(item.tagText) }
                }
                premiumMeta(item, onDark: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private var premiumFooter: some View {
        HStack {
            Spacer()
            Button { nextBatch() } label: {
                Label(Tr("换一批"), systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.bordered)
            .disabled(loading)
            Spacer()
        }
        .padding(.top, 2)
    }

    private func nextBatch() {
        let step = 20
        offset += step
        if total > 0, offset >= total { offset = 0 }
        Task { await load(tab) }
    }

    private var isBoard: Bool { tab == "weibo" || tab == "baidu" }

    @ViewBuilder private var content: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if items.isEmpty && loading {
                    ProgressView()
                        .tint(accent)
                        .padding(.top, compact ? 40 : 80)
                        .frame(maxWidth: .infinity)
                } else if items.isEmpty {
                    emptyView
                } else {
                    let rows = Array(items.enumerated())
                    ForEach(rows, id: \.element.id) { row in
                        Button { open(row.element) } label: {
                            cell(row.element, index: row.offset)
                        }
                        .buttonStyle(.plain)
                        HairLine(inset: 16)
                    }
                    footer
                }
            }
            .padding(.bottom, 28)
        }
        .background(C.cardBg)
        .refreshable { await load(tab) }
    }

    private var emptyView: some View {
        VStack(spacing: 14) {
            Text(failed ? Tr("稍后再看看") : Tr("正在加载…"))
                .font(pf(14))
                .foregroundColor(C.subLabel)
            Button { Task { await load(tab) } } label: {
                Text(Tr("重试"))
                    .font(pf(15, .medium))
                    .foregroundColor(accent)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, compact ? 50 : 90)
    }

    private var footer: some View {
        VStack(spacing: 16) {

            Button { nextBatch() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12, weight: .semibold))
                    Text(Tr("换一批")).font(pf(14))
                }
                .foregroundColor(C.green)
                .padding(.horizontal, 18)
                .frame(height: 34)
                .background(Capsule().stroke(C.hairline, lineWidth: 0.5))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(loading)
            Text(Tr("已经到底了"))
                .font(pf(12))
                .foregroundColor(C.time)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }

    @ViewBuilder private func cell(_ it: NewsItem, index: Int) -> some View {
        if isBoard {
            boardCell(it, index: index)
        } else if !it.cover.isEmpty {

            if index == 0 && !compact { heroCell(it) } else { thumbCell(it) }
        } else {
            textCell(it)
        }
    }

    private func heroCell(_ it: NewsItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(it.title)
                .font(pf(compact ? 16.5 : 17, .semibold))
                .foregroundColor(C.label)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            RemoteImage(path: it.cover, maxSide: 1400)
                .frame(height: compact ? 168 : 200)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .padding(.top, 10)
            meta(it)
                .padding(.top, 9)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func thumbCell(_ it: NewsItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(it.title)
                    .font(pf(compact ? 15.5 : 17))
                    .foregroundColor(C.label)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                meta(it)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            RemoteImage(path: it.cover, maxSide: 800)
                .frame(width: compact ? 76 : 96, height: compact ? 57 : 72)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .padding(.horizontal, compact ? 14 : 16)
        .padding(.vertical, compact ? 11 : 14)
    }

    private func textCell(_ it: NewsItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(it.title)
                .font(pf(compact ? 15.5 : 17))
                .foregroundColor(C.label)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if let s = it.summary, !s.isEmpty {
                Text(s)
                    .font(pf(14))
                    .foregroundColor(C.subLabel)
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            meta(it)
                .padding(.top, 2)
        }
        .padding(.horizontal, compact ? 14 : 16)
        .padding(.vertical, compact ? 11 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func boardCell(_ it: NewsItem, index: Int) -> some View {
        let no = it.order > 0 ? it.order : (index + 1)
        return HStack(alignment: .top, spacing: 12) {
            Text("\(no)")
                .font(pf(16, .semibold))
                .foregroundColor(rankColor(no))
                .frame(width: 24, alignment: .leading)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 6) {
                    Text(it.title)
                        .font(pf(compact ? 16 : 17))
                        .foregroundColor(C.label)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if !it.tagText.isEmpty { tagChip(it.tagText) }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    if it.hotValue > 0 {
                        Text(Tr("热度") + " " + hotText(it.hotValue))
                            .font(pf(12))
                            .foregroundColor(C.time)
                    }
                    Text(it.src)
                        .font(pf(12))
                        .foregroundColor(C.time)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func meta(_ it: NewsItem) -> some View {
        HStack(spacing: 6) {
            Text(it.src)
            let t = timeText(it.at)
            if !t.isEmpty {
                Text("·")
                Text(t)
            }
        }
        .font(pf(12))
        .foregroundColor(C.time)
        .lineLimit(1)
    }

    private func tagChip(_ text: String) -> some View {
        Text(text)
            .font(pf(10, .medium))
            .foregroundColor(C.red)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(C.red.opacity(0.12))
            )
    }

    private func rankColor(_ no: Int) -> Color {

        return no <= 3 ? C.label : C.time
    }

    private func select(_ id: String) {
        guard id != tab else { return }
        tab = id
        offset = 0
        items = []
        failed = false
        Task { await load(id) }
    }

    private func load(_ source: String) async {
        if loadingTab == source { return }
        loadingTab = source
        loading = true
        do {
            let feed = try await API.shared.news(source: source, limit: 20, offset: offset)
            guard source == tab else { loadingTab = ""; return }
            if onlyTabs == nil, !feed.tabs.isEmpty { channels = feed.tabs }
            if let t = feed.total, t > 0 { total = t }
            updatedAt = feed.updatedAt ?? 0
            var seen = Set<String>()
            items = feed.items.filter { seen.insert($0.id).inserted }
            failed = items.isEmpty
        } catch {
            guard source == tab else { loadingTab = ""; return }
            if items.isEmpty { failed = true }
        }
        loading = false
        loadingTab = ""
    }

    private func open(_ it: NewsItem) {
        guard !it.link.isEmpty, let u = URL(string: it.link) else { return }
        web = WebURL(url: u)
    }

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "MM-dd"
        return f
    }()

    private func timeText(_ ms: Double) -> String {
        guard ms > 0 else { return "" }
        let d = Date(timeIntervalSince1970: ms / 1000)
        let mins = Int(Date().timeIntervalSince(d) / 60)
        if mins < 0 { return "" }
        if mins < 1 { return Tr("刚刚") }
        if mins < 60 { return "\(mins)\(Tr("分钟前"))" }
        if mins < 60 * 24 { return "\(mins / 60)\(Tr("小时前"))" }
        if mins < 60 * 24 * 2 { return Tr("昨天") }
        return NewsFeedView.dayFmt.string(from: d)
    }

    private func hotText(_ v: Double) -> String {
        if v >= 10000 {
            let w = v / 10000
            return String(format: "%.1f万", w)
        }
        return String(format: "%.0f", v)
    }
}

struct NewsView: View {
    @State private var refreshToken = 0

    var body: some View {
        NewsFeedView(refreshToken: refreshToken)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(Tr("时刻新闻"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { refreshToken += 1 } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel(Tr("刷新"))
            }
        }
        .hidesTabBar()
    }
}
