import SwiftUI
import SafariServices
import UIKit

struct ShopLinkPrice: Hashable {
    var price: String
    var off: String
    var tag: String
}

struct ShopLink: Hashable {
    var title: String
    var sub: String
    var url: String
    var scheme: String

    var image: String

    var meta: String
    var reviews: String
    var prices: [ShopLinkPrice]

    var rich: Bool { !meta.isEmpty || !prices.isEmpty }

    init?(json: String) {
        guard let d = json.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        title = (o["title"] as? String) ?? "打开"
        sub = (o["sub"] as? String) ?? ""
        url = (o["url"] as? String) ?? ""
        scheme = (o["scheme"] as? String) ?? ""
        image = (o["image"] as? String) ?? ""
        meta = (o["meta"] as? String) ?? ""
        reviews = (o["reviews"] as? String) ?? ""
        prices = ((o["prices"] as? [[String: Any]]) ?? []).prefix(3).map { p in
            ShopLinkPrice(price: String(describing: p["price"] ?? ""),
                          off: (p["off"] as? String) ?? "",
                          tag: (p["tag"] as? String) ?? "")
        }
        if url.isEmpty && scheme.isEmpty { return nil }
    }
}

enum ExternalLinkRouter {
    private static let systemHosts = [
        "meituan.com", "meituan.net", "dianping.com", "dpurl.cn",
        "taobao.com", "tmall.com", "tb.cn",
        "jd.com", "jingdong.com",
        "pinduoduo.com", "yangkeduo.com",
        "ele.me", "alipay.com", "xiaohongshu.com", "douyin.com"
    ]

    static func prefersSystem(_ url: URL) -> Bool {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host?.lowercased(), !host.isEmpty else { return false }
        return systemHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    @MainActor
    static func openIfNeeded(_ url: URL) -> Bool {
        guard prefersSystem(url) else { return false }
        UIApplication.shared.open(url)
        return true
    }
}

@MainActor
enum ShopOpener {
    static func open(_ link: ShopLink, inApp: @escaping (URL) -> Void) {
        if !link.scheme.isEmpty, let u = URL(string: link.scheme), UIApplication.shared.canOpenURL(u) {
            UIApplication.shared.open(u)
            return
        }
        if let u = URL(string: link.url) {
            if !ExternalLinkRouter.openIfNeeded(u) { inApp(u) }
        }
    }
}

struct SafariSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let cfg = SFSafariViewController.Configuration()
        cfg.entersReaderIfAvailable = false
        let vc = SFSafariViewController(url: url, configuration: cfg)
        vc.preferredControlTintColor = UIColor(red: 0.34, green: 0.42, blue: 0.58, alpha: 1)
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) { }
}

struct WebURL: Identifiable {
    let id = UUID()
    var url: URL
}

struct ShopLinkCard: View {
    let link: ShopLink
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            if link.rich { richBody } else { simpleBody }
        }
        .buttonStyle(.plain)
    }

    private var richBody: some View {
        WeChatMessageCard {
            HStack(alignment: .top, spacing: 10) {
                RemoteImage(path: link.image, mode: .fill, maxSide: 360)
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(link.title)
                        .font(pfStyled(size: 15.5, weight: .medium))
                        .foregroundColor(C.bubbleText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if !link.meta.isEmpty {
                        Text(link.meta)
                            .font(pfStyled(size: 12.5))
                            .foregroundColor(C.subLabel)
                            .lineLimit(1)
                    }
                    if !link.reviews.isEmpty {
                        Text(link.reviews)
                            .font(pfStyled(size: 12.5))
                            .foregroundColor(C.subLabel)
                            .lineLimit(1)
                    }
                    ForEach(link.prices.indices, id: \.self) { i in
                        let p = link.prices[i]
                        HStack(spacing: 4) {
                            Text("团")
                                .font(pf(10, .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(C.red))
                            Text("¥" + p.price)
                                .font(pf(15, .semibold))
                                .foregroundColor(C.red)
                            if !p.off.isEmpty {
                                Text(p.off).font(pf(11.5)).foregroundColor(C.subLabel)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }

            Rectangle()
                .fill(C.hairline)
                .frame(height: 0.5)
                .padding(.vertical, 9)

            WeChatMessageCardFooter(symbol: "link", title: Tr("网页链接"), trailing: Tr("打开"))
        }
    }

    private var simpleBody: some View {
        WeChatMessageCard {
            HStack(spacing: 10) {

                if !link.image.isEmpty {
                    RemoteImage(path: link.image, mode: .fill, maxSide: 240)
                        .frame(width: 50, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color(hexString: "#FF5000"))
                        Text("淘")
                            .font(pf(16, .semibold))
                            .foregroundColor(.white)
                    }
                    .frame(width: 50, height: 50)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(link.title)
                        .font(pfStyled(size: 15.5, weight: .medium))
                        .foregroundColor(C.bubbleText)
                        .lineLimit(2)
                    Text(link.sub)
                        .font(pfStyled(size: 12.5))
                        .foregroundColor(C.subLabel)
                        .lineLimit(2)
                }
                Spacer(minLength: 6)
            }

            Rectangle()
                .fill(C.hairline)
                .frame(height: 0.5)
                .padding(.vertical, 9)

            WeChatMessageCardFooter(symbol: "link", title: Tr("网页链接"), trailing: Tr("打开"))
        }
    }
}
