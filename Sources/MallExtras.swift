import SwiftUI

enum DDChannelKind: String, CaseIterable, Identifiable {
    case subsidy, rank, cheap, factory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .subsidy: return "百亿补贴"
        case .rank:    return "排行榜"
        case .cheap:   return "9.9包邮"
        case .factory: return "厂家直供"
        }
    }

    var sub: String {
        switch self {
        case .subsidy: return "平台补贴：按折扣力度排，省得最多的在前"
        case .rank:    return "按销量排（拼的人越多越靠前）"
        case .cheap:   return "9.9 元以内，包邮到家"
        case .factory: return "工厂发货：厂家直供 / 一件代发"
        }
    }

    var icon: String {
        switch self {
        case .subsidy: return "yensign.circle.fill"
        case .rank:    return "chart.bar.fill"
        case .cheap:   return "tag.fill"
        case .factory: return "shippingbox.fill"
        }
    }

    var tint: Color {
        switch self {
        case .subsidy: return DDColor.red
        case .rank:    return DDColor.orange
        case .cheap:   return Color(hex: 0x1CA36B)
        case .factory: return Color(hex: 0x2E6BFF)
        }
    }
}

struct DDChannelItem: Codable, Identifiable, Hashable {
    var id: String
    var title: String

    var icon: String?

    var emoji: String?

    var action: String?

    var tint: String?
    var on: Bool?
    var sort: Int?

    var live: Bool { on ?? true }

    var symbol: String { (icon?.isEmpty == false) ? icon! : (DDChannelKind(rawValue: action ?? "")?.icon ?? "tag.fill") }
    var emojiText: String { emoji ?? "" }
    var tintColor: Color {
        if let t = tint, t.count == 7, t.hasPrefix("#"),
           let v = UInt32(t.dropFirst(), radix: 16) { return Color(hex: v) }
        return DDChannelKind(rawValue: action ?? "")?.tint ?? DDColor.red
    }

    static let builtin: [DDChannelItem] = [
        DDChannelItem(id: "ch1", title: "百亿补贴", icon: "yensign.circle.fill", emoji: "💰",
                      action: "subsidy", tint: nil, on: true, sort: 1),
        DDChannelItem(id: "ch2", title: "排行榜", icon: "chart.bar.fill", emoji: "🏆",
                      action: "rank", tint: nil, on: true, sort: 2),
        DDChannelItem(id: "ch3", title: "9.9包邮", icon: "tag.fill", emoji: "🏷️",
                      action: "cheap", tint: nil, on: true, sort: 3),
        DDChannelItem(id: "ch4", title: "厂家直供", icon: "shippingbox.fill", emoji: "🏭",
                      action: "factory", tint: nil, on: true, sort: 4),
        DDChannelItem(id: "fn1", title: "我的订单", icon: "doc.text", emoji: "📄",
                      action: "orders", tint: nil, on: true, sort: 5),
        DDChannelItem(id: "fn2", title: "购物车", icon: "cart", emoji: "🛒",
                      action: "cart", tint: nil, on: true, sort: 6),
        DDChannelItem(id: "fn3", title: "我的收藏", icon: "heart", emoji: "❤️",
                      action: "fav", tint: nil, on: true, sort: 7),
        DDChannelItem(id: "fn4", title: "浏览足迹", icon: "clock", emoji: "👣",
                      action: "views", tint: nil, on: true, sort: 8)
    ]
}

extension DDProduct {

    var saveMoney: Double { max(0, orig - price) }

    var discountRate: Double { orig > 1 ? max(0, min(1, 1 - price / orig)) : 0 }

    var salesNum: Int {
        if let s = sales { return s }
        let t = sold.replacingOccurrences(of: "+", with: "").trimmingCharacters(in: .whitespaces)
        if t.hasSuffix("万") { return Int((Double(String(t.dropLast())) ?? 0) * 10000) }
        return Int(t) ?? 0
    }

    var inStock: Bool { specList.contains { $0.stock > 0 } }

    var hasSubsidy: Bool {
        tags.contains { $0.contains("补贴") } || title.contains("补贴")
    }
}

struct DDAdCard: View {
    let emoji: String
    let title: String
    let sub: String
    let cta: String
    let top: UInt32
    let bottom: UInt32

    var adKey: String = ""
    var onTap: () -> Void

    var body: some View {
        Button { onTap() } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(colors: [Color(hex: top), Color(hex: bottom)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Text(emoji).font(pfStyled(size: 64))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Text(Tr("广告"))
                        .font(pf(9.5)).foregroundColor(.white.opacity(0.92))
                        .padding(.horizontal, 5).frame(height: 15)
                        .background(Capsule().fill(Color.black.opacity(0.28)))
                        .padding(6)
                }
                .frame(height: 150)
                .clipped()
                .overlay(alignment: .topTrailing) {

                    Button { DDStore.shared.hideAd(adKey.isEmpty ? (emoji + title) : adKey) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold)).foregroundColor(.white.opacity(0.9))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.black.opacity(0.3)))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(5)
                }
                Text(Tr(title)).font(pf(14, .medium)).foregroundColor(DDColor.ink)
                    .lineLimit(2).multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(Tr(sub)).font(pf(11.5)).foregroundColor(DDColor.sub)
                    .lineLimit(2).multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(Tr(cta))
                    .font(pf(12, .medium)).foregroundColor(.white)
                    .padding(.horizontal, 12).frame(height: 28)
                    .background(Capsule().fill(Color.black.opacity(0.22)))
            }
            .padding(8)
            .background(DDColor.card)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct DDAdStrip: View {
    let emoji: String
    let title: String
    let sub: String
    let cta: String
    let top: UInt32
    let bottom: UInt32
    var onTap: () -> Void

    var body: some View {
        Button { onTap() } label: {
            HStack(spacing: 10) {
                ZStack(alignment: .bottomTrailing) {
                    LinearGradient(colors: [Color(hex: top), Color(hex: bottom)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Text(emoji).font(pfStyled(size: 26)).frame(maxWidth: .infinity, maxHeight: .infinity)
                    Text(Tr("广告")).font(pf(8.5)).foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 4).frame(height: 13)
                        .background(Capsule().fill(Color.black.opacity(0.25)))
                        .padding(3)
                }
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(Tr(title)).font(pf(14, .medium)).foregroundColor(DDColor.ink).lineLimit(1)
                    Text(Tr(sub)).font(pf(11.5)).foregroundColor(DDColor.sub).lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(Tr(cta)).font(pf(12.5, .medium)).foregroundColor(.white)
                    .padding(.horizontal, 12).frame(height: 30)
                    .background(Capsule().fill(Color(hex: bottom)))
            }
            .padding(10)
            .background(DDColor.card)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct DDChannelRow: View {
    var onOpen: (DDChannelKind) -> Void

    var onFunc: (String) -> Void = { _ in }
    @ObservedObject private var store = DDStore.shared

    private var items: [DDChannelItem] {

        guard store.channelsConfigured else { return DDChannelItem.builtin }
        return store.channels.filter { $0.live }
    }

    var body: some View {

        if items.isEmpty {
            EmptyView()
        } else {

        LazyVGrid(columns: [GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0),
                            GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0)],
                  spacing: 12) {
            ForEach(items) { it in
                cell(item: it) {
                    if let k = DDChannelKind(rawValue: it.action ?? "") { onOpen(k) }
                    else { onFunc(it.action ?? "") }
                }
            }
        }
        .padding(.vertical, 14)
        .background(DDColor.cardGrad)

        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(DDColor.cardEdge.opacity(0.7), lineWidth: 0.6))
        .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)
        .shadow(color: DDColor.cardShadow, radius: 14, y: 5)
        .padding(.horizontal, 12)
        }
    }

    private func cell(item: DDChannelItem, tap: @escaping () -> Void) -> some View {
        let tint = item.tintColor

        return Button { tap() } label: {
            VStack(spacing: 7) {
                ZStack {

                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [tint.opacity(0.17), tint.opacity(0.07)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 46, height: 46)
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.55), lineWidth: 0.7)
                        .frame(width: 46, height: 46)
                    if item.emojiText.isEmpty {
                        Image(systemName: item.symbol)
                            .font(.system(size: 20, weight: .medium)).foregroundColor(tint)
                    } else {
                        Text(item.emojiText).font(pfStyled(size: 22))
                    }
                }
                Text(Tr(item.title)).font(pf(11.5, .medium)).foregroundColor(DDColor.ink)
                    .lineLimit(1).minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct DDChannelView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = DDStore.shared

    let kind: DDChannelKind

    var onCart: () -> Void = { }

    @State private var openProduct: DDProduct? = nil

    private var list: [DDProduct] {

        let all = store.feed(store.live)
        switch kind {
        case .rank:
            return all.sorted { $0.salesNum != $1.salesNum ? $0.salesNum > $1.salesNum : $0.price < $1.price }
        case .cheap:
            return all.filter { $0.price <= 9.9 }.sorted { $0.price < $1.price }
        case .factory:
            return all.filter { p in p.tags.contains { $0.contains("厂家") || $0.contains("一件代发") } }
                .sorted { $0.salesNum > $1.salesNum }
        case .subsidy:
            let tagged = all.filter { $0.hasSubsidy }
            if !tagged.isEmpty { return tagged.sorted { $0.discountRate > $1.discountRate } }
            return all.sorted { $0.discountRate != $1.discountRate
                ? $0.discountRate > $1.discountRate : $0.saveMoney > $1.saveMoney }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            head
            ScrollView(showsIndicators: false) {
                if list.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray").font(.system(size: 28)).foregroundColor(DDColor.weak)
                        Text(Tr("这一栏暂时没有商品")).font(pf(14)).foregroundColor(DDColor.sub)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 70)
                } else if kind == .rank {
                    ranked
                } else {
                    grid
                }
            }
            .background(DDColor.page)
        }
        .background(DDColor.page.ignoresSafeArea())
        .swipeBack { dismiss() }

        .ddLight()
        .preferredColorScheme(.light)
        .sheet(item: $openProduct) { p in
            DDDetailView(product: p,
                         onCart: { openProduct = nil; onCart() },
                         onOpenOther: { openProduct = $0 },
                         onDismiss: { openProduct = nil })
                .environmentObject(app)
        }
    }

    private var head: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(DDColor.ink)
                        .frame(width: 34, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Text(Tr(kind.title)).font(pf(17, .semibold)).foregroundColor(DDColor.ink)
                Spacer(minLength: 0)
                Text("\(list.count) " + Tr("件")).font(pf(12.5)).foregroundColor(DDColor.sub)
            }
            HStack(spacing: 6) {
                Image(systemName: kind.icon).font(.system(size: 11.5))
                Text(Tr(kind.sub)).font(pf(12)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundColor(DDColor.sub)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 9)
        .background(ddTopGradient())
        .overlay(HairLine(), alignment: .bottom)
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                  spacing: 10) {
            ForEach(list) { p in
                Button { openProduct = p } label: { DDProductCard(product: p) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 16)
    }

    private var ranked: some View {
        LazyVStack(spacing: 10) {
            ForEach(Array(list.enumerated()), id: \.element.id) { i, p in
                Button { openProduct = p } label: { rankRow(i + 1, p) }
                    .buttonStyle(.plain)
            }
            Spacer().frame(height: 16)
        }
        .padding(.vertical, 10)
    }

    private func rankRow(_ n: Int, _ p: DDProduct) -> some View {
        HStack(spacing: 10) {
            Text("\(n)")
                .font(pf(12.5, .bold)).foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(rankTint(n)))
            DDThumb(em: p.em, size: 68, radius: 10, img: p.img)
            VStack(alignment: .leading, spacing: 5) {
                Text(p.title).font(pf(13.5)).foregroundColor(DDColor.ink).lineLimit(2)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    DDPrice(value: p.price, size: 16)
                    Text("¥" + moneyFmt(p.orig))
                        .font(pf(11)).foregroundColor(DDColor.sub).strikethrough()
                }
                HStack(spacing: 6) {
                    if !p.sold.isEmpty {
                        Text(Tr("已拼") + p.sold).font(pf(11)).foregroundColor(DDColor.sub)
                    }
                    Text(p.cate).font(pf(10.5)).foregroundColor(DDColor.red)
                        .padding(.horizontal, 5).frame(height: 16)
                        .background(Capsule().fill(DDColor.redLight))
                    Spacer(minLength: 0)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(DDColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 10)
    }

    private func rankTint(_ n: Int) -> Color {
        n == 1 ? DDColor.redDeep : (n == 2 ? DDColor.orange : (n == 3 ? Color(hex: 0xF7B500) : DDColor.weak))
    }
}

struct DDSearchHotBoard: View {
    var words: [String]
    var onTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill").font(.system(size: 12)).foregroundColor(DDColor.orange)
                Text(Tr("热搜榜")).font(pf(14.5, .semibold)).foregroundColor(DDColor.ink)
                Spacer(minLength: 0)
                Text(Tr("按商品热度")).font(pf(11.5)).foregroundColor(DDColor.sub)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                      spacing: 8) {
                ForEach(Array(words.enumerated()), id: \.element) { i, w in
                    Button { onTap(w) } label: {
                        HStack(spacing: 7) {
                            Text("\(i + 1)")
                                .font(pf(11.5, .bold))
                                .foregroundColor(i < 3 ? .white : DDColor.sub)
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(i < 3 ? hotTint(i) : DDColor.page))
                            Text(w).font(pf(13)).foregroundColor(DDColor.ink).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 9).fill(DDColor.card))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func hotTint(_ i: Int) -> Color {
        i == 0 ? DDColor.redDeep : (i == 1 ? DDColor.orange : Color(hex: 0xF7B500))
    }
}

struct DDSuggestList: View {
    var words: [String]
    var onTap: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(words, id: \.self) { w in
                Button { onTap(w) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 13)).foregroundColor(DDColor.weak)
                        Text(w).font(pf(14)).foregroundColor(DDColor.ink).lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.left")
                            .font(.system(size: 12)).foregroundColor(DDColor.weak)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                HairLine()
            }
        }
        .background(DDColor.card)
    }
}

struct DDSearchFilterBar: View {
    var sort: String
    var onlyStock: Bool
    var onSort: (String) -> Void
    var onStock: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            item(Tr("综合"), on: sort.isEmpty) { onSort("") }
            item(Tr("销量"), on: sort == "sales") { onSort(sort == "sales" ? "" : "sales") }
            item(priceText, on: sort == "priceUp" || sort == "priceDown") {
                onSort(sort == "priceUp" ? "priceDown" : (sort == "priceDown" ? "" : "priceUp"))
            }
            Button { onStock() } label: {
                HStack(spacing: 4) {
                    Image(systemName: onlyStock ? "checkmark.square.fill" : "square")
                        .font(.system(size: 12))
                    Text(Tr("只看有货")).font(pf(12.5, onlyStock ? .medium : .regular))
                }
                .foregroundColor(onlyStock ? DDColor.red : DDColor.sub)
                .frame(maxWidth: .infinity).frame(height: 38)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(DDColor.card)
    }

    private var priceText: String {
        sort == "priceUp" ? Tr("价格↑") : (sort == "priceDown" ? Tr("价格↓") : Tr("价格"))
    }

    private func item(_ t: String, on: Bool, tap: @escaping () -> Void) -> some View {
        Button { tap() } label: {
            Text(t)
                .font(pf(12.5, on ? .semibold : .regular))
                .foregroundColor(on ? DDColor.red : DDColor.sub)
                .frame(maxWidth: .infinity).frame(height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
