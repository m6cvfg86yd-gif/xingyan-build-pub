import SwiftUI

struct MallCardInfo {
    var id = ""
    var em = "📦"
    var img = ""
    var title = ""
    var price: Double = 0
    var orig: Double = 0
    var shop = ""

    init?(json: String) {
        guard let d = json.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        id = (o["id"] as? String) ?? ""
        em = (o["em"] as? String) ?? "📦"
        img = (o["img"] as? String) ?? ""
        title = (o["title"] as? String) ?? ""
        price = (o["price"] as? Double) ?? Double(o["price"] as? Int ?? 0)
        orig = (o["orig"] as? Double) ?? Double(o["orig"] as? Int ?? 0)
        shop = (o["shop"] as? String) ?? ""
        guard !title.isEmpty else { return nil }
    }

    var asProduct: DDProduct {
        DDProduct(id: id, em: em, img: img.isEmpty ? nil : img, title: title,
                  price: price, orig: orig > 0 ? orig : price, sold: "", grp: 2,
                  tags: [], shop: shop, cate: "其它")
    }
}

@MainActor
final class MallSheet: ObservableObject {
    static let shared = MallSheet()
    @Published var open = false
    @Published var product: DDProduct?
    func open(_ p: DDProduct) { product = p; open = true }
    func close() { open = false }
}

struct MallCardBubble: View {
    let info: MallCardInfo

    var onOpen: () -> Void

    var body: some View {
        Button { onOpen() } label: {
            WeChatMessageCard {
                HStack(spacing: 10) {
                    DDThumb(em: info.em, size: 62, radius: 5,
                            img: info.img.isEmpty ? nil : info.img)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(info.title)
                            .font(pfStyled(size: 15.5, weight: .medium))
                            .foregroundColor(C.label)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("¥" + moneyFmt(info.price))
                                .font(pf(16, .semibold))
                                .foregroundColor(DDColor.red)
                            if info.orig > info.price {
                                Text("¥" + moneyFmt(info.orig))
                                    .font(pf(11.5))
                                    .foregroundColor(C.subLabel)
                                    .strikethrough()
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    Spacer(minLength: 0)
                }

                Rectangle()
                    .fill(C.hairline)
                    .frame(height: 0.5)
                    .padding(.vertical, 9)

                WeChatMessageCardFooter(
                    symbol: "bag.fill",
                    title: DDStore.shared.mallName,
                    trailing: info.shop.isEmpty ? Tr("商品") : info.shop
                )
            }
        }
        .buttonStyle(.plain)
    }
}
