import SwiftUI

struct DDCategoryTab: View {
    @ObservedObject private var store = DDStore.shared
    var onOpen: (DDProduct) -> Void
    var onSearch: () -> Void

    @State private var cate: String = ""

    @State private var tag: String = ""

    private var cats: [String] { ["全部"] + store.categories }

    private var byCate: [DDProduct] {
        let all = store.feed(store.live)
        guard !cate.isEmpty, cate != "全部" else { return all }
        return all.filter { $0.cate == cate }
    }
    private var list: [DDProduct] {
        guard !tag.isEmpty else { return byCate }
        return byCate.filter { $0.tags.contains(tag) }
    }

    private var chips: [String] {
        var out: [String] = []
        for p in byCate { for t in p.tags where !out.contains(t) { out.append(t) } }
        return Array(out.prefix(8))
    }

    var body: some View {
        HStack(spacing: 0) {

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(cats, id: \.self) { c in
                        let on = (c == "全部" && cate.isEmpty) || c == cate
                        Button {
                            withAnimation(.easeOut(duration: 0.18)) { cate = (c == "全部") ? "" : c; tag = "" }
                        } label: {
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                    .fill(on ? DDColor.red : Color.clear)
                                    .frame(width: 3, height: 15)
                                Text(Tr(c))
                                    .font(pf(13.5, on ? .semibold : .regular))
                                    .foregroundColor(on ? DDColor.red : DDColor.ink)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.leading, 6).padding(.trailing, 8)
                            .frame(height: 50)
                            .frame(maxWidth: .infinity)
                            .background(
                                Group {
                                    if on { DDColor.cardGrad } else { Color.clear }
                                }
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 20)
                }
            }

            .frame(width: 84)
            .background(DDColor.page)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {

                    Button { onSearch() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundColor(DDColor.sub)
                            Text(Tr("搜商品 / 品牌 / 分类"))
                                .font(pf(13.5)).foregroundColor(DDColor.sub)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(Capsule().fill(Color.white))
                        .overlay(Capsule().stroke(DDColor.cardEdge, lineWidth: 0.6))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 6) {
                        Text(Tr(cate.isEmpty ? "全部商品" : cate))
                            .font(pf(16, .semibold)).foregroundColor(DDColor.ink)
                        Text(String(list.count) + Tr(" 件"))
                            .font(pf(11.5)).foregroundColor(DDColor.sub)
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 2)

                    if !chips.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                chip(Tr("全部"), tag.isEmpty) { tag = "" }
                                ForEach(chips, id: \.self) { t in
                                    chip(Tr(t), tag == t) { tag = (tag == t) ? "" : t }
                                }
                            }
                        }
                    }

                    DDWaterfallGrid(cells: list.map { p -> (view: AnyView, h: CGFloat) in
                        (view: AnyView(DDProductCard(product: p, onOpen: { onOpen(p) })),
                         h: DDWaterfallGrid.estimate(p))
                    }, spacing: 10)

                    if list.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "shippingbox")
                                .font(.system(size: 30)).foregroundColor(DDColor.weak)
                            Text(Tr("这个分类下暂时没有商品"))
                                .font(pf(13)).foregroundColor(DDColor.sub)
                        }
                        .frame(maxWidth: .infinity).padding(.top, 50)
                    }

                    Spacer(minLength: 16)
                }

                .padding(.horizontal, 8)
                .padding(.top, 10)
            }
            .background(DDColor.page)
        }
    }

    private func chip(_ text: String, _ on: Bool, _ tap: @escaping () -> Void) -> some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { tap() } } label: {
            Text(text)
                .font(pf(12.5, on ? .medium : .regular))
                .foregroundColor(on ? .white : DDColor.red)
                .padding(.horizontal, 11).frame(height: 26)
                .background(Capsule().fill(on ? DDColor.red : DDColor.redLight))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
