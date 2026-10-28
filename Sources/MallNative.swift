import SwiftUI

struct DDProduct: Identifiable, Codable, Hashable {
    var id: String

    var em: String

    var img: String? = nil
    var title: String

    var price: Double

    var orig: Double
    var sold: String

    var grp: Int
    var tags: [String]
    var shop: String
    var cate: String

    var on: Bool? = nil

    var live: Bool { on ?? true }

    var subtitle: String? = nil
    var brand: String? = nil

    var rating: Double? = nil

    var sales: Int? = nil

    var variants: [DDVariant]? = nil

    var params: [[String]]? = nil

    var detailImages: [String]? = nil

    var detail: String? = nil

    var services: [String]? = nil

    var shopId: String? = nil

    var shopKey: String { (shopId?.isEmpty == false) ? shopId! : shop }

    var specList: [DDVariant] {
        if let v = variants, !v.isEmpty { return v }
        switch cate {
        case "服饰":
            return ["S", "M", "L", "XL"].map { DDVariant(name: $0, price: price, stock: 99) }
        case "运动", "母婴":
            return ["38", "40", "42", "44"].map { DDVariant(name: $0, price: price, stock: 88) }
        case "美妆", "食品":
            return [DDVariant(name: "单件装", price: price, stock: 99),
                    DDVariant(name: "3件装", price: (price * 2.7 * 100).rounded() / 100, stock: 99),
                    DDVariant(name: "整箱装", price: (price * 8.5 * 100).rounded() / 100, stock: 99)]
        default:
            return [DDVariant(name: "标准款", price: price, stock: 99),
                    DDVariant(name: "升级款", price: (price * 1.25 * 100).rounded() / 100, stock: 99)]
        }
    }

    var serviceList: [String] {
        if let s = services, !s.isEmpty { return s }
        return ["7天无理由退货", "退货包运费", "正品保障", "极速退款"]
    }

    var dict: [String: Any] {
        var d: [String: Any] = [
            "id": id, "em": em, "img": img ?? "", "title": title,
            "price": price, "orig": orig, "sold": sold, "grp": grp,
            "tags": tags, "shop": shop, "cate": cate, "on": live
        ]
        if let subtitle, !subtitle.isEmpty { d["subtitle"] = subtitle }
        if let brand, !brand.isEmpty { d["brand"] = brand }
        if let rating { d["rating"] = rating }
        if let sales { d["sales"] = sales }
        if let params, !params.isEmpty { d["params"] = params }
        if let detailImages, !detailImages.isEmpty { d["detailImages"] = detailImages }
        if let detail, !detail.isEmpty { d["detail"] = detail }
        if let services, !services.isEmpty { d["services"] = services }
        if let shopId, !shopId.isEmpty { d["shopId"] = shopId }
        if let variants, !variants.isEmpty {
            d["variants"] = variants.map {
                ["name": $0.name, "price": $0.price, "stock": $0.stock]
            }
        }
        return d
    }
}

struct DDVariant: Codable, Hashable, Identifiable {
    var name: String
    var price: Double
    var stock: Int
    var id: String { name }
}

struct DDCartLine: Identifiable, Codable, Hashable {
    var pid: String
    var count: Int
    var id: String { pid }
}

struct DDOrder: Identifiable, Codable, Hashable {
    var id: String
    var pid: String
    var em: String
    var title: String
    var shop: String
    var price: Double
    var count: Int
    var group: Bool

    var need: Int

    var have: Int
    var status: String
    var at: Date

    var spec: String = ""

    var orderNo: String = ""

    var freight: Double = 0

    var couponOff: Double = 0

    var invoice: String = ""
    var payWay: String = ""
    var remark: String = ""

    var addrName: String = ""
    var addrPhone: String = ""
    var addrText: String = ""

    var express: String = ""
    var expressNo: String = ""

    var paidAt: Date? = nil

    var reviewed: Bool = false

    var memberOff: Double = 0

    var total: Double { max(0, price * Double(count) + freight - couponOff - memberOff) }

    static func makeNo() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyyMMddHHmmss"
        return f.string(from: Date()) + String(Int.random(in: 100000...999999))
    }

    var statusText: String {
        switch status {
        case "paying":   return "待付款"
        case "grouping": return "拼团中"
        case "wait":     return "待发货"
        case "shipped":  return "待收货"
        case "done":     return "已完成"
        case "cancel":   return "已取消"
        default:         return status
        }
    }
    var canConfirm: Bool { status == "shipped" }
    var canCancel: Bool { status == "paying" || status == "grouping" || status == "wait" }
    var canPay: Bool { status == "paying" }

    var canReview: Bool { status == "done" && !reviewed }

    var payLeft: Int {
        guard status == "paying" else { return 0 }
        return max(0, 1800 - Int(Date().timeIntervalSince(at)))
    }
}

struct DDSplash: Codable, Equatable {

    var on: Bool?

    var image: String?

    var action: String?
    var link: String?

    var seconds: Double?

    var skipText: String?

    var isOn: Bool { (on ?? true) && !(image ?? "").isEmpty }
    var secs: Double { min(10, max(1, seconds ?? 3)) }
    var skip: String { ((skipText ?? "").isEmpty ? "跳过" : skipText!) }
}

struct DDAd: Decodable, Identifiable, Hashable {
    var id: String

    var kind: String?
    var emoji: String?
    var title: String
    var sub: String?
    var cta: String?

    var top: String?
    var bottom: String?

    var action: String?
    var link: String?
    var on: Bool?
    var sort: Int?

    var coupon: DDAdCoupon?

    var isGrid: Bool { (kind ?? "strip") == "grid" }
    var topColor: UInt32 { UInt32((top ?? "").replacingOccurrences(of: "#", with: ""), radix: 16) ?? 0xFFF1EA }
    var bottomColor: UInt32 { UInt32((bottom ?? "").replacingOccurrences(of: "#", with: ""), radix: 16) ?? 0xFF5F3A }

    var dict: [String: Any] {
        ["id": id,
         "kind": kind ?? "strip",
         "emoji": emoji ?? "🛍",
         "title": title,
         "sub": sub ?? "",
         "cta": cta ?? "去看看",
         "top": top ?? "",
         "bottom": bottom ?? "",
         "action": action ?? "none",
         "link": link ?? "",
         "on": on ?? true,
         "sort": sort ?? 99]
    }
}

struct DDDeliveryMode: Decodable, Identifiable, Hashable {
    var id: String
    var name: String
    var fee: Double

    var freeMin: Double
    var days: String?
    var note: String?
    var on: Bool?

    static let defaults: [DDDeliveryMode] = [
        DDDeliveryMode(id: "d1", name: "普通快递", fee: 8, freeMin: 99, days: "3~5 天送达", note: "全国大部分地区", on: true),
        DDDeliveryMode(id: "d2", name: "次日达", fee: 15, freeMin: 199, days: "次日送达", note: "限城区", on: true),
        DDDeliveryMode(id: "d3", name: "到店自提", fee: 0, freeMin: 0, days: "当天可取", note: "到店出示订单号", on: true)
    ]
}

struct DDAdCoupon: Decodable, Hashable {
    var title: String?
    var off: Double?
    var min: Double?
    var days: Double?
    var kind: String?

    var text: String {
        let o = off ?? 0
        if o > 0 { return Tr("满 ") + String(Int(min ?? 0)) + Tr(" 减 ") + String(Int(o)) }
        return title ?? Tr("权益券")
    }
}

@MainActor
final class DDStore: ObservableObject {
    static let shared = DDStore()

    @Published private(set) var products: [DDProduct] = []

    @Published private(set) var banners: [String] = []

    @Published private(set) var mallName: String = "星言商城"
    @Published private(set) var mallSlogan: String = "拼着买 才便宜"
    @Published private(set) var orders: [DDOrder] = []
    @Published private(set) var cart: [DDCartLine] = []
    @Published private(set) var history: [String] = []
    @Published private(set) var favs: [String] = []

    @Published private(set) var views: [String] = []

    @Published var address: String = ""

    @Published var wantCart = false

    @Published var wantOrders = false
    func jumpCart() { wantCart = true }
    func jumpOrders() { wantOrders = true }

    @Published private(set) var addresses: [DDAddress] = []

    @Published private(set) var reviews: [DDReview] = []

    @Published private(set) var afterSales: [DDAfterSale] = []

    @Published private(set) var followedShops: [String] = []

    @Published private(set) var coupons: [DDCoupon] = []

    @Published private(set) var notices: [DDNotice] = []

    @Published private(set) var cartSpec: [String: String] = [:]

    @Published var invoiceTitle: String = ""

    @Published var payWay: String = XYPay.name

    @Published private(set) var vipUntil: Date? = nil

    @Published var vipAutoRenew = true

    @Published private(set) var vipSaved: Double = 0

    @Published private(set) var hiddenAds: [String] = []

    @Published private(set) var disliked: [String] = []

    @Published private(set) var mutedCates: [String] = []

    @Published private(set) var ads: [DDAd] = []

    @Published private(set) var splash = DDSplash()

    @Published private(set) var channels: [DDChannelItem] = []

    @Published private(set) var channelsConfigured = false

    @Published private(set) var allAds: [DDAd] = []

    @Published private(set) var mallNewCoupons = 0
    @Published private(set) var mallClaimable = 0

    @Published private(set) var banks: [API.WalletBankCard] = []

    @Published private(set) var deliveryModes: [DDDeliveryMode] = DDDeliveryMode.defaults
    @Published var deliveryModeId: String = DDDeliveryMode.defaults.first?.id ?? ""

    var deliveryMode: DDDeliveryMode? {
        deliveryModes.first { $0.id == deliveryModeId } ?? deliveryModes.first
    }

    func deliveryFee(_ goods: Double) -> Double {
        guard let m = deliveryMode else { return 0 }
        if m.freeMin > 0 && goods >= m.freeMin { return 0 }
        return m.fee
    }
    func applyDelivery(_ list: [DDDeliveryMode]) {
        let live = list.filter { $0.on != false }
        guard !live.isEmpty else { return }
        deliveryModes = live
        if !live.contains(where: { $0.id == deliveryModeId }) { deliveryModeId = live[0].id }
    }

    static let vipRate = 0.95

    var isVip: Bool {
        guard let d = vipUntil else { return false }
        return d > Date()
    }

    var vipDaysLeft: Int {
        guard isVip, let d = vipUntil else { return 0 }
        return max(0, Int(ceil(d.timeIntervalSinceNow / 86400)))
    }

    var vipUntilText: String {
        guard let d = vipUntil else { return "" }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    func vipPrice(_ p: DDProduct) -> Double {
        isVip ? ((p.price * DDStore.vipRate * 100).rounded() / 100) : p.price
    }

    func vipOff(_ amount: Double) -> Double {
        isVip ? ((amount * (1 - DDStore.vipRate) * 100).rounded() / 100) : 0
    }

    func openVip(months: Int) {
        let base = max(Date(), vipUntil ?? Date())
        vipUntil = Calendar.current.date(byAdding: .month, value: max(1, months), to: base) ?? base
        vipAutoRenew = true
        save()
    }

    func setVipAutoRenew(_ on: Bool) {
        vipAutoRenew = on
        save()
    }

    private struct Box: Codable {
        var products: [DDProduct]
        var orders: [DDOrder]
        var cart: [DDCartLine]
        var history: [String]
        var favs: [String]
        var address: String

        var banners: [String]?

        var views: [String]?

        var addresses: [DDAddress]?
        var reviews: [DDReview]?
        var afterSales: [DDAfterSale]?
        var followedShops: [String]?
        var coupons: [DDCoupon]?
        var notices: [DDNotice]?
        var cartSpec: [String: String]?
        var invoiceTitle: String?
        var payWay: String?

        var vipUntil: Date?
        var vipAutoRenew: Bool?
        var vipSaved: Double?
        var hiddenAds: [String]?
        var disliked: [String]?
        var mutedCates: [String]?

        var splash: DDSplash?
    }

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("dd_mall.json")
    }

    private init() {
        if let d = try? Data(contentsOf: fileURL),
           let b = try? JSONDecoder().decode(Box.self, from: d) {
            products = b.products
            orders = b.orders
            cart = b.cart
            history = b.history
            favs = b.favs
            address = b.address
            banners = b.banners ?? []
            views = b.views ?? []
            addresses = b.addresses ?? []
            reviews = b.reviews ?? []
            afterSales = b.afterSales ?? []
            followedShops = b.followedShops ?? []
            coupons = b.coupons ?? []
            notices = b.notices ?? []
            cartSpec = b.cartSpec ?? [:]
            invoiceTitle = b.invoiceTitle ?? ""

            let savedWay = b.payWay ?? ""
            payWay = (savedWay.isEmpty || savedWay == "微信支付") ? XYPay.name : savedWay
            vipUntil = b.vipUntil
            vipAutoRenew = b.vipAutoRenew ?? true
            vipSaved = b.vipSaved ?? 0
            hiddenAds = b.hiddenAds ?? []
            disliked = b.disliked ?? []
            mutedCates = b.mutedCates ?? []
            splash = b.splash ?? DDSplash()
        }
        if products.isEmpty { products = DDStore.seeds }

        if addresses.isEmpty, !address.isEmpty {
            addresses = [DDAddress(id: "a" + String(Int(Date().timeIntervalSince1970 * 1000)),
                                   name: "", phone: "", region: "", detail: address, isDefault: true)]
        }
    }

    private func save() {
        let b = Box(products: products, orders: orders, cart: cart,
                    history: history, favs: favs, address: address, banners: banners,
                    views: views, addresses: addresses,
                    reviews: reviews, afterSales: afterSales, followedShops: followedShops,
                    coupons: coupons, notices: notices, cartSpec: cartSpec,
                    invoiceTitle: invoiceTitle, payWay: payWay,
                    vipUntil: vipUntil, vipAutoRenew: vipAutoRenew, vipSaved: vipSaved,
                    hiddenAds: hiddenAds, disliked: disliked, mutedCates: mutedCates,
                    splash: splash)
        if let d = try? JSONEncoder().encode(b) { try? d.write(to: fileURL) }
    }

    var live: [DDProduct] { products.filter { $0.live } }

    static var groupOn: Bool { UIConfig.num("mallGroup", 0) > 0 }

    func refresh() async {
        let r = await API.shared.mallData()

        guard r.ok else { return }
        if !r.products.isEmpty { products = r.products }
        banners = r.banners
        if !r.name.isEmpty { mallName = r.name }
        if !r.slogan.isEmpty { mallSlogan = r.slogan }
        ads = r.ads.filter { $0.on != false }.sorted { ($0.sort ?? 99) < ($1.sort ?? 99) }
        allAds = r.ads.sorted { ($0.sort ?? 99) < ($1.sort ?? 99) }
        applyDelivery(r.delivery)
        splash = r.splash ?? DDSplash()

        if let chs = r.channels {
            channels = chs.sorted { ($0.sort ?? 99) < ($1.sort ?? 99) }
            channelsConfigured = true
        }
        save()
    }

    @discardableResult
    func opsSetChannels(_ list: [DDChannelItem]) async -> Bool {
        let ok = await API.shared.opsMall(["action": "channels", "channels": list.map { c in
            ["id": c.id, "title": c.title, "icon": c.icon ?? "", "emoji": c.emoji ?? "",
             "action": c.action ?? "subsidy", "tint": c.tint ?? "",
             "on": c.on ?? true, "sort": c.sort ?? 0]
        }])
        await refresh()
        return ok
    }

    func opsSetSplash(_ s: DDSplash) async {
        _ = await API.shared.opsMall(["action": "splash", "splash": [
            "on": s.on ?? true,
            "image": s.image ?? "",
            "action": s.action ?? "none",
            "link": s.link ?? "",
            "seconds": s.seconds ?? 3,
            "skipText": s.skipText ?? "跳过"
        ]])
        await refresh()
    }

    func opsSetName(_ name: String, _ slogan: String) async {
        _ = await API.shared.opsMall(["action": "settings", "name": name, "slogan": slogan])
        await refresh()
    }

    func opsSave(_ p: DDProduct) async {
        _ = await API.shared.opsMall(["action": "product", "item": p.dict])
        await refresh()
    }

    func opsRemove(_ id: String) async {
        _ = await API.shared.opsMall(["action": "remove", "id": id])
        await refresh()
    }

    func opsBanners(_ urls: [String]) async {
        _ = await API.shared.opsMall(["action": "banners", "banners": urls])
        await refresh()
    }

    func opsAds(_ list: [DDAd]) async {
        _ = await API.shared.opsMall(["action": "ads", "ads": list.map { $0.dict }])
        await refresh()
    }

    func refreshMallBadges() async {
        guard let r = await API.shared.mallAdMine() else { return }
        mallNewCoupons = r.newCount ?? 0
        mallClaimable = r.claimableCount ?? (r.claimable?.count ?? 0)

        mergeServerCoupons(r.coupons ?? [])

        banks = (try? await API.shared.walletBanks()) ?? banks
    }

    var bankPayText: String {
        guard let b = banks.first else { return Tr("添加银行卡") }
        let tail = b.tail ?? ""
        return tail.isEmpty ? Tr("银行卡") : (Tr("银行卡（尾号 ") + tail + ")")
    }

    func markMallSeen() {
        guard mallNewCoupons > 0 else { return }
        mallNewCoupons = 0
        Task { await API.shared.mallAdSeen() }
    }

    @discardableResult
    func claimAdCoupon(_ adId: String) async -> API.MallAdClaim? {
        let r = await API.shared.mallAdClaim(adId: adId)
        await refreshMallBadges()
        return r
    }

    private func mergeServerCoupons(_ list: [API.MallCoupon]) {
        let fmt = ISO8601DateFormatter()
        for c in list where !coupons.contains(where: { $0.id == c.id }) {
            let until = fmt.date(from: c.until ?? "") ?? Date().addingTimeInterval(7 * 86400)
            coupons.append(DDCoupon(id: c.id, title: c.title, off: c.off, min: c.min,
                                    until: until, used: c.used ?? false))
        }
    }

    func product(_ id: String) -> DDProduct? { products.first { $0.id == id } }

    var cartCount: Int { cart.reduce(0) { $0 + $1.count } }
    var cartTotal: Double {
        cart.reduce(0) { sum, line in
            sum + (product(line.pid)?.price ?? 0) * Double(line.count)
        }
    }

    func addCart(_ pid: String, count: Int = 1) {
        if let i = cart.firstIndex(where: { $0.pid == pid }) {
            cart[i].count += count
        } else {
            cart.append(DDCartLine(pid: pid, count: count))
        }

        if cartSpec[pid] == nil, let p = product(pid) { cartSpec[pid] = p.specList.first?.name ?? "" }
        save()
    }

    func setCount(_ pid: String, _ n: Int) {
        guard let i = cart.firstIndex(where: { $0.pid == pid }) else { return }
        if n <= 0 { cart.remove(at: i) } else { cart[i].count = n }
        save()
    }

    func clearCart() { cart.removeAll(); save() }

    var groupingCount: Int { orders.filter { $0.status == "grouping" }.count }

    @discardableResult
    func place(pid: String, count: Int, group: Bool, fromCart: Bool = false,
               spec: String = "", address: DDAddress? = nil, remark: String = "",
               freight: Double = 0, couponOff: Double = 0, invoice: String = "",
               memberOff: Double = 0,
               payWay: String = XYPay.name, paying: Bool = true) -> DDOrder {
        let p = product(pid)

        var unit = group ? (p?.price ?? 0) : (p?.orig ?? p?.price ?? 0)
        if let v = p?.specList.first(where: { $0.name == spec }) { unit = v.price }

        let vipOff = memberOff > 0 ? memberOff : self.vipOff(unit * Double(max(1, count)))
        if vipOff > 0 { vipSaved += vipOff }
        let now = Int(Date().timeIntervalSince1970 * 1000)
        let o = DDOrder(id: "dd" + String(now) + String(Int.random(in: 100...999)),
                        pid: pid,
                        em: p?.em ?? "📦",
                        title: p?.title ?? "商品",
                        shop: p?.shop ?? "",
                        price: unit,
                        count: max(1, count),
                        group: group,
                        need: max(2, p?.grp ?? 2),
                        have: group ? 1 : 0,
                        status: paying ? "paying" : (group ? "grouping" : "wait"),
                        at: Date(),
                        spec: spec,
                        orderNo: DDOrder.makeNo(),
                        freight: freight,
                        couponOff: couponOff,
                        invoice: invoice,
                        payWay: payWay,
                        remark: remark,
                        addrName: address?.name ?? "",
                        addrPhone: address?.phone ?? "",
                        addrText: address?.full ?? "",
                        memberOff: vipOff)
        orders.insert(o, at: 0)
        if fromCart { cart.removeAll { $0.pid == pid } }

        Task {
            let ref = UserDefaults.standard.string(forKey: "chris.mall.ref") ?? ""
            let total = max(0, o.price * Double(o.count) + o.freight - o.couponOff - o.memberOff)
            _ = await API.shared.mallOrderSync(
                id: o.id,
                items: [["title": o.title, "price": o.price, "count": o.count, "img": ""]],
                total: total,
                payWay: o.payWay,
                address: (o.addrName + " " + o.addrPhone + " " + o.addrText).trimmingCharacters(in: .whitespaces),
                at: ISO8601DateFormatter().string(from: o.at),
                remark: o.remark,
                ref: ref,

                paid: (o.payWay != AliPay.name))
        }
        pushNotice(DDNotice(id: "n" + String(now), title: "订单已提交",
                            body: "「" + o.title + "」等你付款，30 分钟未付会自动取消",
                            at: Date(), kind: "order"))
        save()
        return o
    }

    func pay(_ id: String) {
        guard let i = orders.firstIndex(where: { $0.id == id }) else { return }
        guard orders[i].status == "paying" else { return }
        orders[i].paidAt = Date()
        orders[i].status = orders[i].group ? "grouping" : "wait"
        pushNotice(DDNotice(id: "n" + String(Int(Date().timeIntervalSince1970 * 1000)),
                            title: "付款成功",
                            body: orders[i].group ? "拼单已发起，人满就发货" : "商家正在打包，48 小时内发货",
                            at: Date(), kind: "order"))
        save()
    }

    @discardableResult
    func placeCombined(lines: [(pid: String, count: Int)], address: DDAddress?, payWay: String) -> DDOrder? {
        let picked = lines.compactMap { l -> (DDProduct, Int)? in
            guard let p = product(l.pid) else { return nil }
            return (p, max(1, l.count))
        }
        guard let first = picked.first else { return nil }
        var sum: Double = 0
        for (p, c) in picked { sum += p.price * Double(c) }
        let now = Int(Date().timeIntervalSince1970 * 1000)
        let o = DDOrder(id: "dd" + String(now) + String(Int.random(in: 100...999)),
                        pid: first.0.id,
                        em: first.0.em,
                        title: picked.count > 1
                            ? (Tr("合并付款 ") + String(picked.count) + Tr(" 件商品"))
                            : first.0.title,
                        shop: first.0.shop,
                        price: sum,
                        count: 1,
                        group: false,
                        need: 2,
                        have: 0,
                        status: "paying",
                        at: Date(),
                        spec: "",
                        orderNo: DDOrder.makeNo(),
                        freight: 0,
                        couponOff: 0,
                        invoice: "",
                        payWay: payWay,
                        remark: "",
                        addrName: address?.name ?? "",
                        addrPhone: address?.phone ?? "",
                        addrText: address?.full ?? "",
                        memberOff: 0)
        orders.insert(o, at: 0)
        for (p, _) in picked { cart.removeAll { $0.pid == p.id } }
        pushNotice(DDNotice(id: "n" + String(now), title: "订单已提交",
                            body: "「" + o.title + "」等你付款，30 分钟未付会自动取消",
                            at: Date(), kind: "order"))
        save()
        return o
    }

    @discardableResult
    func syncToServer(_ o: DDOrder, paid: Bool) async -> Bool {
        let ref = UserDefaults.standard.string(forKey: "chris.mall.ref") ?? ""
        return await API.shared.mallOrderSync(
            id: o.id,
            items: [["title": o.title, "price": o.price, "count": o.count, "img": ""]],
            total: o.total,
            payWay: o.payWay,
            address: (o.addrName + " " + o.addrPhone + " " + o.addrText).trimmingCharacters(in: .whitespaces),
            at: ISO8601DateFormatter().string(from: o.at),
            remark: o.remark,
            ref: ref,
            paid: paid)
    }

    func invite(_ id: String) {
        guard let i = orders.firstIndex(where: { $0.id == id }) else { return }
        orders[i].have = orders[i].need
        orders[i].status = "wait"

        pushNotice(DDNotice(id: "n" + String(Int(Date().timeIntervalSince1970 * 1000)),
                            title: "拼单成功",
                            body: "「" + orders[i].title + "」已成团，商家马上打包发货",
                            at: Date(), kind: "group"))
        save()
    }

    func cancelOrder(_ id: String) {
        guard let i = orders.firstIndex(where: { $0.id == id }) else { return }
        orders[i].status = "cancel"
        save()
    }

    func ship(_ id: String) {
        guard let i = orders.firstIndex(where: { $0.id == id }) else { return }
        if orders[i].status == "wait" {
            orders[i].status = "shipped"

            let kuaidi = ["顺丰速运", "中通快递", "圆通速递", "韵达快递"]
            orders[i].express = kuaidi[Int.random(in: 0..<kuaidi.count)]
            orders[i].expressNo = "SF" + String(Int(Date().timeIntervalSince1970)) + String(Int.random(in: 100...999))
            pushNotice(DDNotice(id: "n" + String(Int(Date().timeIntervalSince1970 * 1000)),
                                title: "包裹已发出",
                                body: orders[i].express + "：" + orders[i].expressNo,
                                at: Date(), kind: "ship"))
            save()
        }
    }

    func confirm(_ id: String) {
        guard let i = orders.firstIndex(where: { $0.id == id }) else { return }
        orders[i].status = "done"
        pushNotice(DDNotice(id: "n" + String(Int(Date().timeIntervalSince1970 * 1000)),
                            title: "交易完成", body: "去给「" + orders[i].title + "」写个评价吧",
                            at: Date(), kind: "done"))
        save()
    }

    func markReviewed(_ orderId: String) {
        guard let i = orders.firstIndex(where: { $0.id == orderId }) else { return }
        orders[i].reviewed = true
        pushNotice(DDNotice(id: "n" + String(Int(Date().timeIntervalSince1970 * 1000)),
                            title: "评价成功", body: "感谢你的评价", at: Date(), kind: "review"))
        save()
    }

    func removeOrder(_ id: String) {
        orders.removeAll { $0.id == id }
        save()
    }

    func isFav(_ pid: String) -> Bool { favs.contains(pid) }

    func toggleFav(_ pid: String) {
        if let i = favs.firstIndex(of: pid) { favs.remove(at: i) } else { favs.insert(pid, at: 0) }
        save()
    }

    func pushHistory(_ q: String) {
        let s = q.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return }
        history.removeAll { $0 == s }
        history.insert(s, at: 0)
        if history.count > 12 { history = Array(history.prefix(12)) }
        save()
    }

    func clearHistory() { history.removeAll(); save() }

    func recordView(_ pid: String) {
        guard !pid.isEmpty else { return }
        views.removeAll { $0 == pid }
        views.insert(pid, at: 0)
        if views.count > 60 { views = Array(views.prefix(60)) }
        save()
    }

    var viewed: [DDProduct] { views.compactMap { product($0) } }

    func clearViews() { views.removeAll(); save() }

    func setAddress(_ s: String) { address = s; save() }

    var defaultAddress: DDAddress? {
        addresses.first { $0.isDefault } ?? addresses.first
    }

    var hasCompleteAddress: Bool {
        guard let a = defaultAddress else { return false }
        return !a.name.isEmpty && a.phone.count >= 6
    }

    var addressLine: String {
        guard let a = defaultAddress else { return "" }
        return a.region + a.detail
    }

    private func normalizeDefault(_ keep: String = "") {
        if addresses.isEmpty { return }

        if !keep.isEmpty, let i = addresses.firstIndex(where: { $0.id == keep }) {
            for k in addresses.indices { addresses[k].isDefault = (k == i) }
            return
        }
        if addresses.contains(where: { $0.isDefault }) {
            var seen = false
            for k in addresses.indices {
                if addresses[k].isDefault {
                    if seen { addresses[k].isDefault = false } else { seen = true }
                }
            }
        } else {
            addresses[0].isDefault = true
        }
    }

    func addAddress(_ a: DDAddress) {
        var x = a
        if x.id.isEmpty { x.id = "a" + String(Int(Date().timeIntervalSince1970 * 1000)) }
        if addresses.isEmpty { x.isDefault = true }
        if x.isDefault { for k in addresses.indices { addresses[k].isDefault = false } }
        addresses.append(x)
        normalizeDefault(x.isDefault ? x.id : "")
        save()
    }

    func updateAddress(_ a: DDAddress) {
        guard let i = addresses.firstIndex(where: { $0.id == a.id }) else { return }
        if a.isDefault { for k in addresses.indices { addresses[k].isDefault = false } }
        addresses[i] = a
        normalizeDefault(a.isDefault ? a.id : "")
        save()
    }

    func removeAddress(_ id: String) {
        addresses.removeAll { $0.id == id }
        normalizeDefault()
        save()
    }

    func setDefaultAddress(_ id: String) {
        normalizeDefault(id)
        save()
    }

    func reviews(of p: DDProduct) -> [DDReview] {
        let mine = reviews.filter { $0.pid == p.id }
        return (mine + DDReview.samples(for: p)).sorted { $0.at > $1.at }
    }

    func rating(of p: DDProduct) -> Double? {
        let list = reviews(of: p)
        guard !list.isEmpty else { return nil }
        return list.reduce(0.0) { $0 + Double($1.rating) } / Double(list.count)
    }

    func addReview(_ r: DDReview) {
        reviews.insert(r, at: 0)
        pushNotice(DDNotice(id: "n" + String(Int(Date().timeIntervalSince1970 * 1000)),
                            title: "评价成功", body: "你对「" + r.title + "」的评价已经发布",
                            at: Date(), kind: "review"))
        save()
    }

    func addAfterSale(_ a: DDAfterSale) {
        afterSales.insert(a, at: 0)
        pushNotice(DDNotice(id: "n" + String(Int(Date().timeIntervalSince1970 * 1000)),
                            title: "售后已提交", body: a.kind + "申请已提交，商家会在 24 小时内处理",
                            at: Date(), kind: "aftersale"))
        save()
    }

    func afterSales(of orderId: String) -> [DDAfterSale] { afterSales.filter { $0.orderId == orderId } }

    func cancelAfterSale(_ id: String) {
        afterSales.removeAll { $0.id == id }
        save()
    }

    func isFollowed(_ key: String) -> Bool { followedShops.contains(key) }

    func toggleFollow(_ key: String) {
        guard !key.isEmpty else { return }
        if let i = followedShops.firstIndex(of: key) { followedShops.remove(at: i) }
        else { followedShops.insert(key, at: 0) }
        save()
    }

    var followedProducts: [DDProduct] {
        var out: [DDProduct] = []
        for p in products where followedShops.contains(p.shopKey) && !out.contains(where: { $0.id == p.id }) {
            out.append(p)
        }
        return out
    }

    func couponUsable(_ c: DDCoupon, total: Double) -> Bool {
        !c.used && Date() < c.until && total >= c.min
    }
    func usableCoupons(_ total: Double) -> [DDCoupon] {
        coupons.filter { couponUsable($0, total: total) }.sorted { $0.off > $1.off }
    }
    func useCoupon(_ id: String) {
        guard let i = coupons.firstIndex(where: { $0.id == id }) else { return }
        coupons[i].used = true
        save()
    }

    func seedCouponsIfNeeded() {
        guard coupons.isEmpty else { return }
        let now = Date()
        coupons = [
            DDCoupon(id: "c5", title: "满 20 减 5", off: 5, min: 20, until: now.addingTimeInterval(30 * 86400), used: false),
            DDCoupon(id: "c12", title: "满 50 减 12", off: 12, min: 50, until: now.addingTimeInterval(30 * 86400), used: false)
        ]
        save()
    }

    func pushNotice(_ n: DDNotice) {
        notices.insert(n, at: 0)
        if notices.count > 60 { notices = Array(notices.prefix(60)) }
    }
    func clearNotices() { notices.removeAll(); save() }

    func removeNotice(_ id: String) {
        notices.removeAll { $0.id == id }
        save()
    }

    func hideAd(_ id: String) {
        guard !hiddenAds.contains(id) else { return }
        hiddenAds.append(id)
        save()
    }
    func adHidden(_ id: String) -> Bool { hiddenAds.contains(id) }

    func notInterested(_ p: DDProduct, muteCate: Bool) {
        if !disliked.contains(p.id) { disliked.append(p.id) }
        if muteCate, !p.cate.isEmpty, !mutedCates.contains(p.cate) { mutedCates.append(p.cate) }
        save()
    }

    func unmuteCate(_ c: String) {
        mutedCates.removeAll { $0 == c }
        save()
    }

    func restoreDisliked(_ id: String) {
        disliked.removeAll { $0 == id }
        save()
    }
    func restoreAllDisliked() {
        disliked.removeAll()
        mutedCates.removeAll()
        save()
    }
    func unhideAd(_ id: String) {
        hiddenAds.removeAll { $0 == id }
        save()
    }
    func unhideAllAds() {
        hiddenAds.removeAll()
        save()
    }

    var dislikedProducts: [DDProduct] { products.filter { disliked.contains($0.id) } }

    func feed(_ list: [DDProduct]) -> [DDProduct] {
        let kept = list.filter { !disliked.contains($0.id) }
        let sorted = kept.sorted { a, b in
            let ma = mutedCates.contains(a.cate) ? 1 : 0
            let mb = mutedCates.contains(b.cate) ? 1 : 0
            return ma < mb
        }

        if sorted.isEmpty && !list.isEmpty {
            return list.sorted { a, b in
                let ma = mutedCates.contains(a.cate) ? 1 : 0
                let mb = mutedCates.contains(b.cate) ? 1 : 0
                return ma < mb
            }
        }
        return sorted
    }

    func cartSpecOf(_ pid: String) -> String { cartSpec[pid] ?? "" }
    func setCartSpec(_ pid: String, _ spec: String) { cartSpec[pid] = spec; save() }

    var invalidCart: [DDCartLine] {
        cart.filter { l in
            guard let p = product(l.pid) else { return true }
            return !p.live
        }
    }

    var validCart: [DDCartLine] {
        cart.filter { l in (product(l.pid)?.live ?? false) }
    }

    func cartGrouped() -> [(shop: String, lines: [DDCartLine])] {
        var order: [String] = []
        var map: [String: [DDCartLine]] = [:]
        for l in validCart {
            let s = product(l.pid)?.shop ?? "店铺"
            if map[s] == nil { order.append(s) }
            map[s, default: []].append(l)
        }
        return order.map { (shop: $0, lines: map[$0] ?? []) }
    }

    func clearInvalidCart() {
        let bad = Set(invalidCart.map { $0.pid })
        cart.removeAll { bad.contains($0.pid) }
        save()
    }

    func removeCartLine(_ pid: String) {
        cart.removeAll { $0.pid == pid }
        save()
    }

    func reorder(_ o: DDOrder) {
        addCart(o.pid, count: max(1, o.count))
        setCartSpec(o.pid, o.spec)
    }

    var categories: [String] {
        var seen: [String] = []
        for p in live where !seen.contains(p.cate) { seen.append(p.cate) }
        return seen
    }

    func search(_ q: String) -> [DDProduct] {
        let s = q.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return live }
        return live.filter {
            $0.title.localizedCaseInsensitiveContains(s)
                || $0.shop.localizedCaseInsensitiveContains(s)
                || $0.cate == s
                || $0.tags.contains { $0.contains(s) }
        }
    }

    static let seeds: [DDProduct] = [
        DDProduct(id: "p01", em: "🎧", title: "【百亿补贴】无线蓝牙耳机 主动降噪 入耳式 超长续航 苹果安卓通用",
                  price: 39.9, orig: 199, sold: "10万+", grp: 2, tags: ["百亿补贴", "官方直营"], shop: "数码优选旗舰店", cate: "数码"),
        DDProduct(id: "p02", em: "👟", title: "轻便透气跑步鞋 男款夏季网面运动鞋 软底减震",
                  price: 59.9, orig: 159, sold: "3.2万", grp: 2, tags: ["限时秒杀", "退货包运费"], shop: "潮鞋工厂店", cate: "服饰"),
        DDProduct(id: "p03", em: "🍊", title: "现摘沃柑 5斤装 手剥甜橙 新鲜当季水果 产地直发",
                  price: 16.8, orig: 39.9, sold: "8.6万", grp: 2, tags: ["产地直发", "坏果包赔"], shop: "果农直供店", cate: "生鲜"),
        DDProduct(id: "p04", em: "🧴", title: "氨基酸洗面奶 深层清洁温和不紧绷 敏感肌可用 200ml",
                  price: 19.9, orig: 69, sold: "5.1万", grp: 3, tags: ["正品保障"], shop: "肌研美妆专营", cate: "美妆"),
        DDProduct(id: "p05", em: "☕", title: "保温杯 316不锈钢 大容量便携车载水杯 24小时保温",
                  price: 29.9, orig: 99, sold: "2.7万", grp: 2, tags: ["限时秒杀"], shop: "日用家居优选", cate: "家居"),
        DDProduct(id: "p06", em: "🍜", title: "螺蛳粉 广西正宗柳州风味 5包装 加臭加辣速食",
                  price: 24.9, orig: 49.9, sold: "12万", grp: 2, tags: ["百亿补贴", "爆款"], shop: "美味零食铺", cate: "食品"),
        DDProduct(id: "p07", em: "📱", title: "120W超级快充充电宝 20000毫安 大容量 自带四线",
                  price: 69, orig: 199, sold: "4.4万", grp: 2, tags: ["官方补贴"], shop: "数码优选旗舰店", cate: "数码"),
        DDProduct(id: "p08", em: "🧸", title: "儿童毛绒玩具公仔 安抚陪睡娃娃 生日礼物正版授权",
                  price: 22.8, orig: 79, sold: "1.9万", grp: 3, tags: ["母婴优选"], shop: "萌趣玩具城", cate: "母婴"),
        DDProduct(id: "p09", em: "👕", title: "纯棉短袖T恤 男款夏季宽松百搭 三件装 不易变形",
                  price: 39.9, orig: 129, sold: "6.8万", grp: 2, tags: ["退货包运费"], shop: "基础款服饰店", cate: "服饰"),
        DDProduct(id: "p10", em: "🥛", title: "纯牛奶 250ml×12盒 全脂营养早餐奶 整箱实惠装",
                  price: 33.9, orig: 69, sold: "9.3万", grp: 2, tags: ["百亿补贴", "日期新鲜"], shop: "乳品官方旗舰", cate: "食品"),
        DDProduct(id: "p11", em: "🪥", title: "电动牙刷 声波震动 智能定时 情侣款 含4个刷头",
                  price: 45.9, orig: 169, sold: "2.2万", grp: 2, tags: ["限时秒杀"], shop: "口腔护理专营", cate: "美妆"),
        DDProduct(id: "p12", em: "🍚", title: "东北五常大米 10斤装 当季新米 香糯软弹 真空包装",
                  price: 34.9, orig: 79, sold: "7.5万", grp: 2, tags: ["产地直发"], shop: "粮油旗舰店", cate: "食品"),
        DDProduct(id: "p13", em: "⌚", title: "智能运动手环 心率血氧监测 防水计步 长续航 通用腕带",
                  price: 79, orig: 299, sold: "1.6万", grp: 3, tags: ["官方补贴"], shop: "数码优选旗舰店", cate: "数码"),
        DDProduct(id: "p14", em: "🧺", title: "衣物收纳箱 大容量可折叠 防潮防尘 衣柜整理三件套",
                  price: 26.9, orig: 89, sold: "3.7万", grp: 2, tags: ["9.9元包邮"], shop: "日用家居优选", cate: "家居"),
        DDProduct(id: "p15", em: "🍰", title: "千层蛋糕 动物奶油 现做现发 网红下午茶甜品",
                  price: 29.9, orig: 88, sold: "2.5万", grp: 2, tags: ["顺丰冷链"], shop: "甜品烘焙坊", cate: "食品"),
        DDProduct(id: "p16", em: "🧢", title: "棒球帽 男女同款 遮阳防晒 显脸小 可调节",
                  price: 15.9, orig: 59, sold: "4.1万", grp: 2, tags: ["9.9元包邮"], shop: "基础款服饰店", cate: "服饰")
    ]
}

extension View {

    func ddLight() -> some View { environment(\.colorScheme, .light) }
}

enum DDColor {
    static let red      = Color(hex: 0xE02F24)
    static let redDeep  = Color(hex: 0xC81E14)
    static let redLight = Color(hex: 0xFFF1EF)
    static let orange   = Color(hex: 0x176A57)

    static let blue     = Color(hex: 0x007DFF)
    static let blueDeep = Color(hex: 0x2F6FED)
    static let blueLight = Color(hex: 0xEAF4FF)
    static let blueEdge = Color(hex: 0xD6E7FF)
    static let page     = Color(hex: 0xF4F6F9)
    static let card     = Color(hex: 0xFFFFFF)
    static let ink      = Color(hex: 0x182431)
    static let sub      = Color(hex: 0x707A8A)
    static let weak     = Color(hex: 0xA4ADBA)
    static let line     = Color(hex: 0xE9EDF2)

    static let cardGrad = LinearGradient(colors: [Color(hex: 0xFFFFFF), Color(hex: 0xFBFCFE)],
                                         startPoint: .top, endPoint: .bottom)
    static let cardEdge = Color(hex: 0xE9EDF2)
    static let cardShadow = Color(hex: 0x26354A).opacity(0.07)

    static let mineCardGrad = LinearGradient(colors: [Color(hex: 0xFFFFFF), Color(hex: 0xFBFCFE),
                                                      Color(hex: 0xFFFFFF)],
                                             startPoint: .top, endPoint: .bottom)

    static let barGrad = LinearGradient(colors: [Color(hex: 0x2F6FED), Color(hex: 0x007DFF)],
                                        startPoint: .top, endPoint: .bottom)

    static let gradHeader = LinearGradient(
        colors: [Color(hex: 0xFF5F3A), Color(hex: 0xEF3323), Color(hex: 0xD81A10)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let gradBtn = LinearGradient(
        colors: [C.green, C.green.opacity(0.78)],
        startPoint: .leading, endPoint: .trailing)

    static let gradBtnSoft = LinearGradient(
        colors: [C.green, OrbitTheme.jadeDeep],
        startPoint: .leading, endPoint: .trailing)

    static let gradThumb = LinearGradient(
        colors: [Color(hex: 0xFFF3EC), Color(hex: 0xFFFBF7)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

func ddTopGradient() -> LinearGradient {
    func col(_ s: String) -> Color? {
        let v = s.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces)
        guard let n = UInt32(v, radix: 16) else { return nil }
        return Color(hex: n)
    }
    let raw = UIConfig.text("mallTopGrad", "")
    if !raw.isEmpty {
        let cols = raw.split(separator: ",").map { col(String($0)) }.compactMap { $0 }
        if cols.count >= 2 {
            return LinearGradient(colors: cols, startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
    return LinearGradient(colors: [Color(hex: 0xFFFBF8), Color(hex: 0xFFF1EA), Color(hex: 0xFFE6DC)],
                          startPoint: .topLeading, endPoint: .bottomTrailing)
}

func ddMineTopGradient() -> LinearGradient {
    func col(_ s: String) -> Color? {
        let v = s.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces)
        guard let n = UInt32(v, radix: 16) else { return nil }
        return Color(hex: n)
    }
    let raw = UIConfig.text("mallMineGrad", "")
    if !raw.isEmpty {
        let cols = raw.split(separator: ",").map { col(String($0)) }.compactMap { $0 }
        if cols.count >= 2 { return LinearGradient(colors: cols, startPoint: .top, endPoint: .bottom) }
    }
    return LinearGradient(colors: [Color(hex: 0xE02F24), Color(hex: 0xFF6A4D),
                                   Color(hex: 0xFFC3B0), Color(hex: 0xF5F5F7)],
                          startPoint: .top, endPoint: .bottom)
}

struct DDThumb: View {
    var em: String
    var size: CGFloat
    var radius: CGFloat = 10

    var img: String? = nil

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(DDColor.gradThumb)
            if let img, !img.isEmpty {
                RemoteImage(path: img, icon: "photo")
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            } else {
                Text(em).font(.system(size: size * 0.46))
            }
        }
        .frame(width: size, height: size)
    }
}

struct DDPrice: View {
    var value: Double
    var size: CGFloat = 17
    var color: Color = DDColor.red

    var body: some View {

        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text("¥").font(pf(size * 0.62, .semibold)).foregroundColor(color)
            Text(DDPrice.split(value).0)
                .font(pf(size * 1.12, .bold)).foregroundColor(color)
            if !DDPrice.split(value).1.isEmpty {
                Text(DDPrice.split(value).1)
                    .font(pf(size * 0.72, .bold)).foregroundColor(color)
            }
        }
    }

    static func split(_ v: Double) -> (String, String) {
        let s = moneyFmt(v)
        guard s.contains(".") else { return (s, "") }
        let parts = s.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return (s, "") }
        return (String(parts[0]), "." + String(parts[1]))
    }
}

enum DDMallFloorCfg {

    static var pull: CGFloat {
        let base = max(40, UIConfig.num("chatsFloorPull", 120))
        let scale = UIConfig.num("mallFloorScale", 1.6)
        return max(40, base * max(0.5, scale))
    }

    static func heavy(_ d: CGFloat) -> CGFloat {
        let g = UIConfig.num("floorGravity", 1)
        if g <= 0 || d <= 60 { return d }
        let tail = max(0, d - 60)
        return 60 + CGFloat(pow(Double(tail), 0.82)) * 0.62 + tail * 0.38
    }
}

struct MallNativeView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = DDStore.shared

    @State private var tab = 0

    @State private var homeTopChannel = 0
    @State private var openProduct: DDProduct? = nil
    @State private var showSearch = false
    @State private var showOrders = false

    @State private var showVip = false

    @State private var showCity = false

    @State private var showMineAddress = false
    @State private var showMineService = false
    @ObservedObject private var city = DDCity.shared

    @State private var floorUp = false
    @State private var floorPull: CGFloat = 0
    @State private var floorOrders = 0
    @State private var showFloorOrders = false
    @State private var showFloorFav = false
    @State private var showFloorViews = false

    @State private var showSplash = false

    @State private var openedAt = Date()

    @State private var showScan = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            header

            content
                .background(
                    UnevenRoundedRectangle(topLeadingRadius: 18,
                                           bottomLeadingRadius: 0,
                                           bottomTrailingRadius: 0,
                                           topTrailingRadius: 18,
                                           style: .continuous)
                        .fill(DDColor.page)
                        .shadow(color: Color.black.opacity(0.07), radius: 8, y: -2)
                )
                .frame(maxWidth: .infinity)
                .clipped()
            tabBar
        }
        .frame(maxWidth: .infinity)
        .background(DDColor.page.ignoresSafeArea())

        .overlay {
            if showSplash {
                MallSplashAdView(splash: store.splash,
                                 onClose: { withAnimation(.easeOut(duration: 0.22)) { showSplash = false } },
                                 onTap: { openSplashTarget() })
                    .transition(.opacity)
            }
        }

        .overlay(alignment: .top) {
            if floorPull > 0.5 || floorUp {
                let screenH = UIScreen.main.bounds.height
                let reveal = floorUp ? screenH : min(floorPull, screenH)
                ZStack(alignment: .top) {
                    DDMallFloor(onClose: { closeMallFloor() },
                                onSearch: { showSearch = true },
                                onOrders: { i in
                                    floorOrders = i
                                    showFloorOrders = true
                                },
                                onFav: { closeMallFloor(); showFloorFav = true },
                                onViews: { closeMallFloor(); showFloorViews = true },
                                onCart: { closeMallFloor(); tab = 3 },
                                onOpen: { p in closeMallFloor(); openProduct_tap(p) },
                                onCity: { showCity = true })
                        .environmentObject(app)
                        .frame(height: screenH)
                        .offset(y: -(screenH - reveal))
                        .ignoresSafeArea()

                    VStack(spacing: 0) {
                        Spacer().frame(height: L.safeTop + 10)
                        mallPullDots
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                    .opacity(floorUp ? 0 : 1)
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
                }
            }
        }
        .sheet(isPresented: $showFloorOrders) {
            DDOrdersView(startFilter: floorOrders).environmentObject(app)
        }
        .sheet(isPresented: $showFloorFav) {
            DDFavView(onOpen: { p in
                showFloorFav = false
                openProduct_tap(p)
            })
            .environmentObject(app)
        }
        .sheet(isPresented: $showFloorViews) {
            DDViewsView(onOpen: { p in
                showFloorViews = false
                openProduct_tap(p)
            })
        }
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .fullScreenCover(item: $openProduct) { p in

            DDDetailView(product: p,
                         onCart: { tab = 3 },
                         onOpenOther: { openProduct = $0 }).environmentObject(app)
        }
        .sheet(isPresented: $showSearch) {
            DDSearchView { p in
                showSearch = false
                openProduct = p
            }
            .environmentObject(app)
        }

        .fullScreenCover(isPresented: $showScan) {
            ScannerView { text in handleScanned(text, app: app) }
        }
        .sheet(isPresented: $showOrders) {
            DDOrdersView().environmentObject(app)
        }
        .sheet(isPresented: $showVip) {
            DDVipPageView(onOpen: { p in
                showVip = false
                openProduct_tap(p)
            })
            .environmentObject(app)
        }

        .sheet(isPresented: $showCity) {
            DDCityPickerView().environmentObject(app)
        }
        .sheet(isPresented: $showMineService) {
            DDHelpCenterView().environmentObject(app)
        }
        .sheet(isPresented: $showMineAddress) {
            DDAddressListView().environmentObject(app)
        }

        .onChange(of: store.wantCart) { v in
            guard v else { return }
            store.wantCart = false
            openProduct = nil
            showOrders = false
            tab = 3
        }
        .onChange(of: store.wantOrders) { v in
            guard v else { return }
            store.wantOrders = false
            openProduct = nil
            showOrders = true
        }

        .onAppear {

            if store.splash.isOn, !showSplash { showSplash = true }
            openedAt = Date()

            CrashCatcher.note("开屏广告", "进商城：配置=\(store.splash.isOn ? "有" : "无")｜封面=\(store.splash.image ?? "-")｜秒=\(Int(store.splash.secs))｜首屏=\(store.products.count)件")
            if store.wantCart {
                store.wantCart = false
                tab = 3
            }
            if store.wantOrders {
                store.wantOrders = false
                showOrders = true
            }
        }

        .onChange(of: store.splash) { s in
            guard s.isOn, !showSplash else { return }
            guard Date().timeIntervalSince(openedAt) < 5 else { return }
            withAnimation(.easeOut(duration: 0.2)) { showSplash = true }
        }

        .task {
            await store.refresh()
            await store.refreshMallBadges()

            if store.splash.isOn, !showSplash { withAnimation(.easeOut(duration: 0.2)) { showSplash = true } }

            DDCity.shared.locateIfNeeded()
            MallWeather.shared.refresh()
        }
        .ddLight()

        .preferredColorScheme(.light)
    }

    private var titles = ["商城", "分类", "消息", "购物车", "我的"]
    private let homeChannels = ["星选", "好价", "热门", "上新"]

    private func openSplashTarget() {
        let a = store.splash.action ?? "none"
        let l = (store.splash.link ?? "").trimmingCharacters(in: .whitespaces)
        withAnimation(.easeOut(duration: 0.2)) { showSplash = false }
        guard !l.isEmpty, a != "none" else { return }
        if a == "product", let p = store.products.first(where: { $0.id == l }) {
            openProduct_tap(p)
            return
        }
        if let u = URL(string: l), u.scheme != nil { openURL(u) }
    }

    private func closeMallFloor() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
            floorUp = false
            floorPull = 0
        }
    }

    private var mallPullDots: some View {
        let p: CGFloat = floorUp ? 1000 : floorPull
        let total: CGFloat = max(1, DDMallFloorCfg.pull)
        let prog: CGFloat = min(1, max(0, p / total))
        let track: CGFloat = 74
        let allLit: Bool = prog >= 0.999
        let litCount: Int = min(3, max(0, Int(prog * 3 + 0.001)))
        let label: String = allLit ? Tr("松手进入二楼")
                         : (litCount >= 1 ? Tr("继续下拉") : Tr("下拉进入二楼"))
        return HStack(spacing: 10) {

            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.34))
                    .frame(width: track, height: 2)
                Capsule()
                    .fill(LinearGradient(colors: [DDColor.orange, Color(hex: 0x0F4F41)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(2, track * prog), height: 2)
                ForEach(0..<3, id: \.self) { i in
                    let at: CGFloat = track * CGFloat(i + 1) / 3
                    let on: Bool = prog * track + 0.5 >= at
                    ZStack {
                        if on {
                            Circle().fill(DDColor.orange.opacity(0.35))
                                .frame(width: 16, height: 16).blur(radius: 4)
                        }
                        Circle()
                            .fill(on ? DDColor.orange : Color.white.opacity(0.55))
                            .frame(width: on ? 8 : 6, height: on ? 8 : 6)
                            .shadow(color: on ? DDColor.orange.opacity(0.55) : .clear, radius: 5)
                    }
                    .frame(width: 16, height: 16)
                    .offset(x: at - 8)
                }
            }
            .frame(width: track, height: 16)

            Text(label)
                .font(pf(11.5, .medium))
                .foregroundColor(allLit ? DDColor.orange : DDColor.ink.opacity(0.55))
                .fixedSize()
        }
        .padding(.leading, 13).padding(.trailing, 15)
        .frame(height: 34)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().stroke(Color.white.opacity(0.34), lineWidth: 0.6))
                .shadow(color: Color.black.opacity(0.10 + 0.10 * prog), radius: 10, y: 3)
        }
        .scaleEffect(allLit ? 1.05 : 1)

        .opacity(min(1, max(0, (p - 25) / 40)))
        .animation(.spring(response: 0.26, dampingFraction: 0.82), value: litCount)
        .animation(.easeOut(duration: 0.16), value: floorPull)
    }

    private var header: some View {

        let onRed = false

        return VStack(spacing: 6) {
            HStack(spacing: 8) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(DDColor.ink)
                        .frame(width: 34, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if tab == 0 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(homeChannels.indices, id: \.self) { i in
                                Button {
                                    withAnimation(.easeOut(duration: 0.16)) {
                                        homeTopChannel = i
                                    }
                                } label: {
                                    VStack(spacing: 3) {
                                        Text(Tr(homeChannels[i]))
                                            .font(pf(homeTopChannel == i ? 17.5 : 15.5,
                                                    homeTopChannel == i ? .bold : .medium))
                                            .foregroundColor(homeTopChannel == i
                                                             ? DDColor.blueDeep : DDColor.sub)
                                        Capsule()
                                            .fill(homeTopChannel == i ? DDColor.blueDeep : Color.clear)
                                            .frame(width: homeTopChannel == i ? 24 : 0, height: 3)
                                    }
                                    .frame(width: 72, height: 40)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    Button { tab = 3 } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "cart.fill")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(DDColor.ink)
                                .frame(width: 38, height: 40)
                            if store.cartCount > 0 {
                                Text(store.cartCount > 99 ? "99+" : String(store.cartCount))
                                    .font(pf(9, .semibold)).foregroundColor(.white)
                                    .padding(.horizontal, 4).frame(height: 14)
                                    .background(Capsule().fill(Color(hex: 0xFF6B4A)))
                                    .offset(x: 4, y: -2)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(Tr(titles[tab]))

                        .font(pf(17, .semibold))
                        .foregroundColor(onRed ? .white : DDColor.ink)
                    Spacer(minLength: 0)
                    if tab == 4 {
                        HStack(spacing: 7) {
                            mineHeaderButton("mappin.and.ellipse", Tr("收货地址")) {
                                showMineAddress = true
                            }
                            mineHeaderButton("headphones", Tr("客户服务")) {
                                showMineService = true
                            }
                        }
                    } else {
                        Color.clear.frame(width: 34, height: 40)
                    }
                }
            }
            if tab == 0 {
                searchBox
                HStack(spacing: 4) {
                    Text(store.mallName).font(pf(12.5, .semibold))
                        .foregroundColor(DDColor.ink)
                    Text(store.mallSlogan).font(pf(11))
                        .foregroundColor(DDColor.sub)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)

        .padding(.bottom, 8)

        .background { headerBg.ignoresSafeArea(edges: .top) }
    }

    @ViewBuilder private var headerBg: some View {

        ZStack {
            DDColor.card
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(UIConfig.num("mallHeaderGlass", 0.18))
        }
    }

    private func mineHeaderButton(_ icon: String, _ title: String,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11.5, weight: .semibold))
                Text(title)
                    .font(pf(11.5, .medium))
                    .lineLimit(1)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(Capsule().fill(Color.white.opacity(0.16)))
            .overlay(Capsule().stroke(Color.white.opacity(0.24), lineWidth: 0.7))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var searchBox: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(DDColor.sub)
            Text(Tr("搜索想要的商品")).font(pf(14)).foregroundColor(DDColor.sub)
            Spacer(minLength: 0)

            Button { showScan = true } label: {
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(DDColor.blue)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(height: 34)
        .background(Capsule().fill(Color.white))
        .overlay(Capsule().stroke(DDColor.blue, lineWidth: 1))
        .shadow(color: DDColor.blue.opacity(0.06), radius: 6, y: 2)
        .contentShape(Rectangle())

        .onTapGesture { showSearch = true }
    }

    @ViewBuilder private var content: some View {
        switch tab {
            case 0: DDHomeTab(topChannel: homeTopChannel,
                              onOpen: openProduct_tap, onCart: { tab = 3 },
                              floorUp: $floorUp, floorPull: $floorPull)

            case 1: DDCategoryTab(onOpen: openProduct_tap, onSearch: { showSearch = true })
            case 2: DDMsgTab(onOrders: { showOrders = true })
            case 3: DDCartTab(onOpen: openProduct_tap, onOrders: { showOrders = true })
            default: DDMineTab(onOrders: { showOrders = true }, onOpen: openProduct_tap)
        }
    }

    private func openProduct_tap(_ p: DDProduct) {
        store.recordView(p.id)
        openProduct = p
    }

    private var tabBar: some View {
        VStack(spacing: 0) {
            HairLine()
            HStack(spacing: 0) {

                tabButton(0, "首页", "house.fill", 0,
                          dot: store.mallClaimable > 0)
                tabButton(1, "分类", "square.grid.2x2", 0,
                          dot: store.mallClaimable > 0)
                tabButton(2, "消息", "bell.fill", store.mallNewCoupons,
                          dot: store.mallNewCoupons == 0 && store.groupingCount > 0)
                tabButton(3, "购物车", "cart.fill", store.cartCount,
                          dot: store.orders.contains { $0.status == "paying" })
                tabButton(4, "我的", "person.fill", 0,
                          dot: store.orders.contains { $0.status == "shipped" })
            }

            .frame(height: UIConfig.num("mallTabH", 49))
            .padding(.bottom, UIConfig.num("mallTabPad", 2))
        }

        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                    .opacity(UIConfig.num("mallTabGlass", 0.18))
                DDColor.card.opacity(0.96)
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func tabButton(_ i: Int, _ label: String, _ icon: String, _ badge: Int,
                           dot: Bool = false) -> some View {
        Button {
            tab = i
            if i == 2 { store.markMallSeen() }
            if store.mallClaimable > 0 { Task { await store.refreshMallBadges() } }
        } label: {
            VStack(spacing: 2) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: UIConfig.num("mallTabIcon", 23),
                                      weight: tab == i ? .semibold : .regular))
                        .foregroundColor(tab == i ? DDColor.blue : DDColor.sub)
                        .frame(width: 28, height: 24)
                    if badge > 0 {
                        Text(badge > 99 ? "99+" : String(badge))
                            .font(pf(9.5, .semibold)).foregroundColor(.white)
                            .padding(.horizontal, 4).frame(height: 14)
                            .background(Capsule().fill(DDColor.redDeep))
                            .offset(x: 9, y: -5)
                    } else if dot {
                        Circle().fill(DDColor.redDeep)
                            .frame(width: 8, height: 8)
                            .offset(x: 8, y: -3)
                    }
                }
                Text(Tr(label))
                    .font(pf(UIConfig.num("mallTabLabel", 10), tab == i ? .medium : .regular))
                    .foregroundColor(tab == i ? DDColor.blue : DDColor.sub)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct DDHomeTab: View {
    @EnvironmentObject private var app: AppState

    @Environment(\.openURL) private var openLink
    @ObservedObject private var store = DDStore.shared
    var topChannel: Int = 0
    var onOpen: (DDProduct) -> Void

    var onCart: () -> Void = { }

    var floorUp: Binding<Bool>? = nil
    var floorPull: Binding<CGFloat>? = nil

    @State private var floorTick = 0

    @State private var floorGestureLocked = false

    @State private var floorDragStart: Date? = nil

    @State private var channel: DDChannelKind? = nil

    @State private var showVipAd = false
    @State private var showMusicAd = false

    @State private var showAdOrders = false
    @State private var showAdFav = false
    @State private var showAdViews = false
    @State private var showAddressHome = false

    @State private var topY: CGFloat = 0
    @State private var cate: String? = nil
    @State private var secs = 2 * 3600 + 41 * 60 + 33
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var list: [DDProduct] {
        let base = cate == nil ? store.live : store.live.filter { $0.cate == cate }

        let rows = store.feed(base)
        switch topChannel {
        case 1:
            return rows.sorted {
                let d0 = ($0.orig - $0.price) / max(0.01, $0.orig)
                let d1 = ($1.orig - $1.price) / max(0.01, $1.orig)
                return d0 > d1
            }
        case 2:
            return rows.sorted { ($0.sales ?? 0) > ($1.sales ?? 0) }
        case 3:
            return Array(rows.reversed())
        default:
            return rows
        }
    }

    private var mallFloorPullValue: CGFloat { DDMallFloorCfg.pull }

    private func mallFloorImpact(_ level: Int) {
        let strength = Int(UIConfig.num("floorHaptic", 3))
        guard strength > 0 else { return }
        switch min(level, strength) {
        case 1: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case 2: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        default: UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
    }

    var body: some View {

        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {

                    Color.clear.frame(height: 0)
                        .background(GeometryReader { g in
                            Color.clear.preference(key: DDFloorOffsetKey.self,
                                                   value: g.frame(in: .named("ddhome")).minY)
                        })
                    deliveryStrip
                    carousel(proxy)
                    sectionTitle(Tr("今日精选"), subtitle: Tr("真实商品 · 官方保障"), right: Tr("更多频道"))
                    promoBoard

                    adStrip
                    sectionTitle(Tr("品牌好价"), subtitle: Tr("大牌直降 · 限时补贴"), right: Tr("全部好价"))
                    dealBoard
                    sectionTitle(Tr("为你推荐"), subtitle: Tr("按热度与优惠智能排序"), right: Tr("更多好物"))

                    cateRow
                    if !store.mutedCates.isEmpty { mutedNote }

                    if store.disliked.count >= 20 && store.dislikedProducts.count >= store.live.count {
                        HStack(spacing: 8) {
                            Image(systemName: "hand.thumbsdown").font(.system(size: 12)).foregroundColor(DDColor.sub)
                            Text(Tr("你把商品都隐藏了，先给你看全部")).font(pf(12)).foregroundColor(DDColor.sub)
                            Spacer(minLength: 0)
                            Button {
                                store.restoreAllDisliked()
                                app.show(Tr("已全部恢复"))
                            } label: {
                                Text(Tr("全部恢复")).font(pf(12.5, .medium)).foregroundColor(DDColor.red)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 6)
                    }
                    grid.id("dd-grid")
                    Spacer().frame(height: 16)
                }
                .padding(.top, 10)
            }
            .background(DDColor.page)
            .coordinateSpace(name: "ddhome")
            .onPreferenceChange(DDFloorOffsetKey.self) { topY = $0 }

            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { v in

                        guard !(floorUp?.wrappedValue ?? false), topY > -1 else { return }
                        let dy = v.translation.height

                        if dy < -8 {
                            floorGestureLocked = true
                            floorPull?.wrappedValue = 0
                            floorTick = 0
                            return
                        }
                        if floorGestureLocked { return }
                        if dy <= 0 { floorPull?.wrappedValue = 0; floorTick = 0; return }
                        if floorDragStart == nil { floorDragStart = Date() }

                        let p = min(DDMallFloorCfg.heavy(dy), UIScreen.main.bounds.height)
                        if abs(p - (floorPull?.wrappedValue ?? 0)) > 0.5 { floorPull?.wrappedValue = p }

                        let step = max(1, mallFloorPullValue / 3)
                        let lit = min(3, Int(p / step))
                        if lit != floorTick {
                            floorTick = lit
                            if lit > 0 { mallFloorImpact(lit >= 3 ? 3 : 2) }
                        }
                    }
                    .onEnded { _ in
                        floorGestureLocked = false

                        let dt = floorDragStart.map { Date().timeIntervalSince($0) } ?? 1
                        floorDragStart = nil
                        guard !(floorUp?.wrappedValue ?? false) else { return }
                        if dt < 0.35 {
                            withAnimation(.easeOut(duration: 0.18)) { floorPull?.wrappedValue = 0 }
                            floorTick = 0
                            return
                        }
                        if (floorPull?.wrappedValue ?? 0) > mallFloorPullValue {
                            withAnimation(.spring(response: 0.44, dampingFraction: 0.82)) {
                                floorUp?.wrappedValue = true
                            }
                            mallFloorImpact(3)
                        } else {
                            withAnimation(.easeOut(duration: 0.22)) { floorPull?.wrappedValue = 0 }
                        }
                        floorTick = 0
                    }
            )
            .onReceive(ticker) { _ in if secs > 0 { secs -= 1 } }

            .sheet(item: $channel) { k in
                DDChannelView(kind: k, onCart: { channel = nil; onCart() })
                    .environmentObject(app)
            }

            .sheet(isPresented: $showVipAd) {
                DDVipPageView { p in
                    showVipAd = false
                    onOpen(p)
                }
                .environmentObject(app)
            }
            .fullScreenCover(isPresented: $showMusicAd) {
                NavigationStack { ListenView().environmentObject(app) }
            }

            .sheet(isPresented: $showAdOrders) { DDOrdersView().environmentObject(app) }
            .sheet(isPresented: $showAdFav) {
                DDFavView(onOpen: { p in
                    showAdFav = false
                    onOpen(p)
                })
                .environmentObject(app)
            }
            .sheet(isPresented: $showAdViews) {
                DDViewsView(onOpen: { p in
                    showAdViews = false
                    onOpen(p)
                })
            }
            .sheet(isPresented: $showAddressHome) {
                DDAddressListView().environmentObject(app)
            }
        }
    }

    private func toGrid(_ proxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo("dd-grid", anchor: .top) }
    }

    private var deliveryStrip: some View {
        Button { showAddressHome = true } label: {
            HStack(spacing: 7) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: 0x2F6FED))
                Text(store.addressLine.isEmpty ? Tr("选择收货地址") : store.addressLine)
                    .font(pf(12, .medium))
                    .foregroundColor(DDColor.ink)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(Tr("预计明日送达"))
                    .font(pf(10.5, .medium))
                    .foregroundColor(Color(hex: 0x2E9E5B))
                Text(Tr("官方正品"))
                    .font(pf(9.5, .semibold))
                    .foregroundColor(DDColor.red)
                    .padding(.horizontal, 7)
                    .frame(height: 22)
                    .background(Capsule().fill(DDColor.red.opacity(0.09)))
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(DDColor.weak)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(DDColor.cardGrad)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DDColor.cardEdge, lineWidth: 0.6))
            .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
    }

    private var dealBoard: some View {
        let columns = [
            GridItem(.flexible(), spacing: 8, alignment: .top),
            GridItem(.flexible(), spacing: 8, alignment: .top)
        ]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(Array(store.live.prefix(4).enumerated()), id: \.element.id) { i, p in
                Button { onOpen(p) } label: { dealTile(p, index: i) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
    }

    private func dealTile(_ p: DDProduct, index: Int) -> some View {
        let title: String = index % 4 == 0 ? Tr("星选好价")
            : (index % 4 == 1 ? Tr("品牌直降")
                : (index % 4 == 2 ? Tr("新品尝鲜") : Tr("会员专享")))
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(pf(13.5, .bold))
                    .foregroundColor(index % 4 == 3 ? Color(hex: 0x8B5B00) : Color(hex: 0x17345F))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text(p.title)
                    .font(pf(10))
                    .foregroundColor(Color(hex: 0x73809A))
                    .lineLimit(1)
                Text("¥" + moneyFmt(p.price))
                    .font(pf(15.5, .bold))
                    .foregroundColor(Color(hex: 0xFF6B4A))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 10)

            if let img = p.img, !img.isEmpty {
                RemoteImage(path: img, icon: "photo", mode: .fill)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(.trailing, 8)
            } else {
                Text(p.em)
                    .font(.system(size: 38))
                    .frame(width: 56, height: 56)
                    .padding(.trailing, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 100)
        .background(LinearGradient(
            colors: index % 4 == 3 ? [Color(hex: 0xFFF8E3), .white]
                                   : [Color(hex: 0xF2F7FF), .white],
            startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var promoBoard: some View {
        GeometryReader { g in
            HStack(spacing: 8) {
                if let first = store.live.first {
                    Button { onOpen(first) } label: { featurePromoProduct(first) }
                        .buttonStyle(.plain)
                        .frame(width: (g.size.width - 20) * 0.52)
                }
                VStack(spacing: 7) {
                    ForEach(Array(store.live.dropFirst().prefix(2))) { p in
                        Button { onOpen(p) } label: { compactPromoProduct(p) }
                            .buttonStyle(.plain)
                    }
                    HStack(spacing: 4) {
                        Text(Tr("正品保障")).font(pf(9)).foregroundColor(DDColor.blueDeep)
                        Text("·").font(pf(9)).foregroundColor(Color(hex: 0xA2AAB5))
                        Text(Tr("极速退款")).font(pf(9)).foregroundColor(DDColor.blueDeep)
                        Spacer(minLength: 0)
                        Text(Tr("查看全部"))
                            .font(pf(10))
                            .foregroundColor(DDColor.sub)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(DDColor.weak)
                    }
                    .frame(height: 20)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(DDColor.cardGrad)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(DDColor.cardEdge, lineWidth: 0.7))
            .shadow(color: DDColor.cardShadow, radius: 10, y: 3)
        }
        .frame(height: 190)
        .padding(.horizontal, 10)
    }

    private func featurePromoProduct(_ p: DDProduct) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                if let img = p.img, !img.isEmpty {
                    RemoteImage(path: img, icon: "photo", mode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(height: 102)
                        .clipped()
                } else {
                    Text(p.em).font(.system(size: 46))
                        .frame(maxWidth: .infinity)
                        .frame(height: 102)
                        .background(Color(hex: 0xEEF2F7))
                }
                Text(Tr("今日主推"))
                    .font(pf(9.5, .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(DDColor.red.opacity(0.85)))
                    .padding(8)
            }
            .frame(height: 102)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(p.title)
                .font(pf(12, .medium))
                .foregroundColor(DDColor.ink)
                .lineLimit(1)
            Text(p.shop)
                .font(pf(9.5))
                .foregroundColor(DDColor.sub)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("¥").font(pf(9.5)).foregroundColor(DDColor.red)
                Text(moneyFmt(p.price)).font(pf(19, .bold)).foregroundColor(DDColor.red)
                Spacer(minLength: 0)
                if !p.sold.isEmpty {
                    Text(Tr("已售") + p.sold)
                        .font(pf(9))
                        .foregroundColor(DDColor.sub)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compactPromoProduct(_ p: DDProduct) -> some View {
        HStack(spacing: 8) {
            if let img = p.img, !img.isEmpty {
                RemoteImage(path: img, icon: "photo", mode: .fill)
                    .frame(width: 62, height: 62)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            } else {
                Text(p.em).font(.system(size: 30))
                    .frame(width: 62, height: 62)
                    .background(Color(hex: 0xF1F4F8))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(p.title)
                    .font(pf(10.5))
                    .foregroundColor(DDColor.ink)
                    .lineLimit(2)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("¥" + moneyFmt(p.price))
                        .font(pf(14.5, .bold))
                        .foregroundColor(DDColor.red)
                    Text(moneyFmt(p.orig))
                        .font(pf(9))
                        .foregroundColor(DDColor.sub)
                        .strikethrough()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 78)
        .padding(7)
        .background(DDColor.page)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    @State private var bannerPage = 0

    @ViewBuilder private func carousel(_ proxy: ScrollViewProxy) -> some View {
        let imgs = store.banners.filter { !$0.isEmpty }
        if !imgs.isEmpty {
            VStack(spacing: 8) {
                TabView(selection: $bannerPage) {
                    ForEach(imgs.indices, id: \.self) { i in
                        Button { toGrid(proxy) } label: {

                            ZStack(alignment: .bottomTrailing) {
                                RemoteImage(path: imgs[i], icon: "photo")
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 146)

                                LinearGradient(colors: [.clear, .black.opacity(0.18)],
                                               startPoint: .center, endPoint: .bottom)
                                    .allowsHitTesting(false)
                                if imgs.count > 1 {
                                    HStack(spacing: 5) {
                                        ForEach(imgs.indices, id: \.self) { k in
                                            Capsule()
                                                .fill(k == i

                                                      ? DDColor.orange
                                                      : Color.white.opacity(0.45))
                                                .frame(width: k == i ? 14 : 6, height: 6)
                                        }
                                    }
                                    .padding(.trailing, 16)
                                    .padding(.bottom, 14)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .padding(.horizontal, 12)
                        }
                        .buttonStyle(.plain)
                        .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 152)
            }

            .task(id: imgs.count) {
                guard imgs.count > 1 else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 3_500_000_000)
                    if Task.isCancelled { return }
                    withAnimation(.easeInOut(duration: 0.35)) {
                        bannerPage = (bannerPage + 1) % max(1, imgs.count)
                    }
                }
            }
        }
    }

    private func seckill(_ proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 10) {

            HStack(spacing: 0) {
                Button { toGrid(proxy) } label: {
                    VStack(spacing: 5) {
                        Text(Tr("限时")).font(pf(14, .semibold)).foregroundColor(.white)
                        Text(Tr("秒杀")).font(pf(14, .semibold)).foregroundColor(.white)
                        Text(clockText)
                            .font(pf(9.5, .semibold)).foregroundColor(.white)
                            .padding(.horizontal, 5).frame(height: 16)
                            .background(Capsule().fill(Color.black.opacity(0.22)))
                    }
                    .frame(width: 74)
                    .frame(maxHeight: .infinity)
                    .background(LinearGradient(colors: [Color(hex: 0xFF5F3A), Color(hex: 0xD81A10)],
                                               startPoint: .top, endPoint: .bottom))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(store.live.prefix(8))) { p in
                            Button { onOpen(p) } label: { seckillCell(p) }
                                .buttonStyle(.plain)
                        }
                        Button { toGrid(proxy) } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(DDColor.sub)
                                Text(Tr("更多")).font(pf(11)).foregroundColor(DDColor.sub)
                            }
                            .frame(width: 54, height: 108)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                }
            }
            .frame(height: 108)
        }
        .padding(.vertical, 10)
        .background(DDColor.cardGrad)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DDColor.cardEdge, lineWidth: 0.6))
        .shadow(color: DDColor.cardShadow, radius: 10, y: 3)
        .padding(.horizontal, 10)
    }

    private func seckillCell(_ p: DDProduct) -> some View {
        VStack(spacing: 4) {
            DDThumb(em: p.em, size: 78, radius: 6, img: p.img)
            DDPrice(value: p.price, size: 15)
            Text("¥" + moneyFmt(p.orig))
                .font(pf(10.5)).foregroundColor(DDColor.sub)
                .strikethrough()
        }
        .frame(width: 82)
    }

    private var clockText: String {
        let h = secs / 3600
        let m = (secs % 3600) / 60
        let s = secs % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    private var cateRow: some View {

        let names: [String] = ["推荐"] + store.categories
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 22) {
                ForEach(names, id: \.self) { c in
                    let on = (c == "推荐" && cate == nil) || cate == c
                    Button {
                        withAnimation(.easeOut(duration: 0.16)) {
                            cate = (c == "推荐") ? nil : (cate == c ? nil : c)
                        }
                    } label: {
                        VStack(spacing: 5) {
                            Text(Tr(c))
                                .font(pf(15, on ? .semibold : .regular))
                                .foregroundColor(on ? DDColor.blueDeep : DDColor.ink)
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(on ? DDColor.blueDeep : Color.clear)
                                .frame(width: 18, height: 2.5)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(DDColor.cardGrad)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DDColor.cardEdge, lineWidth: 0.6))
        .shadow(color: DDColor.cardShadow, radius: 10, y: 3)
        .padding(.horizontal, 10)
    }

    private func sectionTitle(_ t: String, subtitle: String = "", right: String) -> some View {

        HStack(alignment: .firstTextBaseline, spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(DDColor.blueDeep)
                .frame(width: 3, height: 17)
            Text(t).font(pf(18, .bold)).foregroundColor(DDColor.ink)
            if !subtitle.isEmpty {
                Text(subtitle).font(pf(10.5)).foregroundColor(DDColor.sub).lineLimit(1)
            }
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                Text(right).font(pf(12.5)).foregroundColor(DDColor.sub)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(DDColor.weak)
            }
            .offset(y: -1)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    private var mutedNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye.slash").font(.system(size: 12)).foregroundColor(DDColor.sub)
            Text(Tr("已少推：") + store.mutedCates.map { Tr($0) }.joined(separator: "、"))
                .font(pf(12)).foregroundColor(DDColor.sub).lineLimit(1)
            Spacer(minLength: 0)
            Button {
                if let c = store.mutedCates.first { store.unmuteCate(c) }
            } label: {
                Text(Tr("恢复")).font(pf(12.5, .medium)).foregroundColor(DDColor.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var grid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 10, alignment: .top),
            GridItem(.flexible(), spacing: 10, alignment: .top)
        ]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(list) { p in
                DDProductCard(product: p,
                              onOpen: { onOpen(p) },
                              onAddCart: {
                                  store.addCart(p.id)
                                  app.show(Tr("已加入购物车"))
                              })
                    .contextMenu {
                        Button(role: .destructive) {
                            store.notInterested(p, muteCate: false)
                            app.show(Tr("好的，这件不再推给你"))
                        } label: { Label(Tr("不感兴趣"), systemImage: "hand.thumbsdown") }
                        if !p.cate.isEmpty {
                            Button {
                                store.notInterested(p, muteCate: true)
                                app.show(Tr("好的，少推「") + Tr(p.cate) + Tr("」"))
                            } label: { Label(Tr("不感兴趣，少推这一类"), systemImage: "eye.slash") }
                        }
                    }
            }
        }
        .padding(.horizontal, 10)
    }

    @ViewBuilder private var adStrip: some View {
        let list = store.ads.filter { !$0.isGrid }
        if list.isEmpty {
            DDAdStrip(emoji: "🗂", title: "百亿补贴 · 折扣最狠的一批",
                      sub: "省得最多的排前面，点进去直接逛", cta: "去看看",
                      top: 0xFFF1EA, bottom: 0xFF5F3A) { channel = .subsidy }
                .padding(.horizontal, 12)
        } else if let a = list.first, !store.adHidden("ad:" + a.id) {
            DDAdStrip(emoji: a.emoji ?? "🛍", title: a.title, sub: a.sub ?? "",
                      cta: a.cta ?? "去看看", top: a.topColor, bottom: a.bottomColor) {
                runAd(a)
            }
            .padding(.horizontal, 12)
        }
    }

    @ViewBuilder private func adCard(_ n: Int) -> some View {
        let grid = store.ads.filter { $0.isGrid }
        if !grid.isEmpty {
            let a = grid[n % grid.count]
            if !store.adHidden("ad:" + a.id) {
                DDAdCard(emoji: a.emoji ?? "🛍", title: a.title, sub: a.sub ?? "",
                         cta: a.cta ?? "去看看", top: a.topColor, bottom: a.bottomColor,
                         adKey: "ad:" + a.id) { runAd(a) }
            }
        } else if n % 2 == 1 {
            if !store.adHidden("🎧听一听：曲库新歌随便放") {
                DDAdCard(emoji: "🎧", title: "听一听：曲库新歌随便放",
                         sub: "边逛边放，好友还能看到你在听什么", cta: "去听歌",
                         top: 0xB98CFF, bottom: 0x7A45D6) { showMusicAd = true }
            }
        } else {
            if !store.adHidden("👑星言PLUS 会员") {
                DDAdCard(emoji: "👑", title: "星言PLUS 会员",
                         sub: "下单立减 5%，退货免运费，专属客服", cta: "去开通",
                         top: 0xFFE7B0, bottom: 0xD9A94A) { showVipAd = true }
            }
        }
    }

    private func runAd(_ a: DDAd) {

        if let c = a.coupon {
            Task {
                let r = await store.claimAdCoupon(a.id)
                if let r = r {
                    if r.already == true {
                        app.show(Tr("这张券你已经领过了，在「我的 → 卡包」里"))
                    } else if r.coupon != nil {
                        app.show(Tr("已发券：") + c.text + Tr("（卡包 / 下单结算都能用）"))
                    }
                }
            }
        }
        switch a.action ?? "none" {
        case "vip":      showVipAd = true
        case "music":    showMusicAd = true
        case "subsidy":  channel = .subsidy
        default:
            if let s = a.link, !s.isEmpty, let u = URL(string: s) { openLink(u) }
        }
    }
}

private extension View {
    @ViewBuilder
    func mallOptionalTap(_ action: (() -> Void)?) -> some View {
        if let action {
            onTapGesture(perform: action)
        } else {
            self
        }
    }
}

struct DDProductCard: View {
    let product: DDProduct
    var onOpen: (() -> Void)? = nil
    var onAddCart: (() -> Void)? = nil
    @ObservedObject private var store = DDStore.shared

    var body: some View {

        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                if let img = product.img, !img.isEmpty {
                    RemoteImage(path: img, icon: "photo", mode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(height: 156)
                        .clipped()
                } else {
                    Text(product.em)
                        .font(.system(size: 62))
                        .frame(maxWidth: .infinity)
                        .frame(height: 156)
                        .background(LinearGradient(
                            colors: [Color(hex: 0xF2F7FF), Color(hex: 0xE6F1FF)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                }

                if let tag = product.tags.first {
                    Text(Tr(tag))
                        .font(pf(9, .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(DDColor.red.opacity(0.85)))
                        .padding(8)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 156)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Button {
                    store.notInterested(product, muteCate: false)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.92))
                        .frame(width: 21, height: 21)
                        .background(Circle().fill(Color.black.opacity(0.28)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(7)
            }
            .overlay(alignment: .bottomLeading) {
                if product.orig > product.price {
                    Text("\(max(1, Int(((1 - product.price / max(0.01, product.orig)) * 100).rounded())))% OFF")
                        .font(pf(9, .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .frame(height: 20)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.black.opacity(0.72)))
                        .padding(8)
                }
            }

            Text(product.title)
                .font(pf(UIConfig.num("mallCardTitle", 13.5), .medium))
                .foregroundColor(DDColor.ink)
                .lineSpacing(2)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9)
                .padding(.top, 8)

            HStack(spacing: 6) {
                Text(product.tags.count > 1 ? Tr(product.tags[1]) : Tr("包邮"))
                    .font(pf(9))
                    .foregroundColor(DDColor.red)
                    .padding(.horizontal, 5)
                    .frame(height: 18)
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color(hex: 0xF2B8AC), lineWidth: 0.6))
                Text(Tr("官方保障"))
                    .font(pf(9))
                    .foregroundColor(DDColor.blueDeep)
                    .padding(.horizontal, 5)
                    .frame(height: 18)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color(hex: 0xEAF2FF)))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.top, 6)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("¥").font(pf(11, .bold)).foregroundColor(DDColor.red)
                Text(moneyFmt(product.price))
                    .font(pf(UIConfig.num("mallCardPrice", 20), .bold))
                    .foregroundColor(DDColor.red)
                    .layoutPriority(2)
                Text("¥" + moneyFmt(product.orig))
                    .font(pf(10))
                    .foregroundColor(DDColor.sub)
                    .strikethrough()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.top, 5)

            HStack(spacing: 4) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(hex: 0x8E98A5))
                Text(product.shop.isEmpty ? Tr("星言官方旗舰店") : product.shop)
                    .font(pf(9.5))
                    .foregroundColor(DDColor.sub)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 2)
                Text(Tr("已售") + (product.sold.isEmpty ? "1000+" : product.sold))
                    .font(pf(9.5))
                    .foregroundColor(DDColor.sub)
                    .lineLimit(1)
                if let onAddCart {
                    Button(action: onAddCart) {
                        Image(systemName: "cart.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 27, height: 27)
                            .background(Circle().fill(DDColor.blueDeep))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.top, 7)
            .padding(.bottom, 10)
        }
        .background(DDColor.cardGrad)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(DDColor.cardEdge.opacity(0.7), lineWidth: 0.6))
        .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)
        .shadow(color: DDColor.cardShadow, radius: 14, y: 5)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .mallOptionalTap(onOpen)
    }
}

struct DDRecTab: View {
    @ObservedObject private var store = DDStore.shared
    var onOpen: (DDProduct) -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                ForEach(store.live) { p in
                    Button { onOpen(p) } label: { recCard(p) }
                        .buttonStyle(.plain)
                }
                Spacer().frame(height: 16)
            }
            .padding(.vertical, 10)
        }
        .background(DDColor.page)
    }

    private func recCard(_ p: DDProduct) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(Color(hex: 0xFFD9CC)).frame(width: 26, height: 26)
                    .overlay(Text("拼").font(pf(12, .semibold)).foregroundColor(DDColor.red))
                Text(p.shop).font(pf(13.5, .medium)).foregroundColor(DDColor.ink)
                Spacer(minLength: 0)
                Text(Tr("种草")).font(pf(11)).foregroundColor(.white)
                    .padding(.horizontal, 6).frame(height: 18)
                    .background(Capsule().fill(DDColor.red))
            }
            Text(p.title).font(pf(15)).foregroundColor(DDColor.ink).lineLimit(3)
            HStack(spacing: 8) {
                DDThumb(em: p.em, size: 96, radius: 10, img: p.img)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        ForEach(p.tags.prefix(2), id: \.self) { t in
                            Text(t).font(pf(10.5)).foregroundColor(DDColor.red)
                                .padding(.horizontal, 5).frame(height: 17)
                                .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(DDColor.redLight))
                        }
                    }
                    DDPrice(value: p.price, size: 18)
                    if !p.sold.isEmpty {
                        Text(Tr("已拼") + p.sold).font(pf(11.5)).foregroundColor(DDColor.sub)
                    }
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .background(DDColor.cardGrad)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DDColor.cardEdge, lineWidth: 0.6))
        .shadow(color: DDColor.cardShadow, radius: 10, y: 3)
        .padding(.horizontal, 10)
    }
}

struct DDMsgTab: View {
    @ObservedObject private var store = DDStore.shared

    var onOrders: () -> Void

    @State private var confirmClear = false

    private var grouping: [DDOrder] { store.orders.filter { $0.status == "grouping" } }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {

                if store.notices.isEmpty && grouping.isEmpty {
                    Text(Tr("还没有消息")).font(pf(14)).foregroundColor(DDColor.sub)
                        .frame(maxWidth: .infinity).padding(.top, 60)
                    Text(Tr("下单、付款、成团、发货、签收、评价之后，这里都会有服务通知"))
                        .font(pf(12)).foregroundColor(DDColor.sub)
                        .multilineTextAlignment(.center).padding(.horizontal, 30)
                } else {
                    if !store.notices.isEmpty {
                        head(Tr("服务通知"), right: Tr("清空")) { confirmClear = true }
                        ForEach(store.notices) { n in noticeRow(n) }
                    }
                    if !grouping.isEmpty {
                        head(Tr("拼单消息"), right: "")
                        ForEach(grouping) { o in row(o) }
                    }
                }
                Spacer().frame(height: 16)
            }
            .padding(.vertical, 10)
        }
        .background(DDColor.page)
        .alert(Tr("清空服务通知？"), isPresented: $confirmClear) {
            Button(Tr("取消"), role: .cancel) { }
            Button(Tr("清空"), role: .destructive) { store.clearNotices() }
        }
    }

    private func head(_ t: String, right: String, tap: @escaping () -> Void = { }) -> some View {
        HStack {
            Text(t).font(pf(13.5, .medium)).foregroundColor(DDColor.sub)
            Spacer(minLength: 0)
            if !right.isEmpty {
                Button { tap() } label: {
                    Text(right).font(pf(12.5)).foregroundColor(DDColor.sub)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private func noticeRow(_ n: DDNotice) -> some View {

        DDSwipeRow(onTap: { onOrders() }, onDelete: { store.removeNotice(n.id) }) {
            noticeCard(n)
        }
    }

    private func noticeCard(_ n: DDNotice) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(noticeColor(n.kind).opacity(0.12)).frame(width: 38, height: 38)
                Image(systemName: noticeIcon(n.kind))
                    .font(.system(size: 16))
                    .foregroundColor(noticeColor(n.kind))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(n.title).font(pf(14.5, .medium)).foregroundColor(DDColor.ink).lineLimit(2)
                Text(n.body).font(pf(12.5)).foregroundColor(DDColor.sub)
                    .fixedSize(horizontal: false, vertical: true)
                Text(timeText(n.at)).font(pf(11.5)).foregroundColor(DDColor.sub)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(DDColor.cardGrad)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DDColor.cardEdge, lineWidth: 0.6))
        .shadow(color: DDColor.cardShadow, radius: 10, y: 3)
        .contentShape(Rectangle())
    }

    private func noticeIcon(_ kind: String) -> String {
        switch kind {
        case "order":     return "doc.text.fill"
        case "group":     return "person.3.fill"
        case "ship":      return "shippingbox.fill"
        case "done":      return "checkmark.seal.fill"
        case "review":    return "star.fill"
        case "aftersale": return "arrow.uturn.backward.circle.fill"
        default:          return "bell.fill"
        }
    }

    private func noticeColor(_ kind: String) -> Color {
        switch kind {
        case "order":     return DDColor.red
        case "group":     return DDColor.redDeep
        case "ship":      return Color(hex: 0x2E6BFF)
        case "done":      return Color(hex: 0x1CA36B)
        case "review":    return DDColor.orange
        case "aftersale": return DDColor.weak
        default:          return DDColor.red
        }
    }

    private func row(_ o: DDOrder) -> some View {
        HStack(alignment: .top, spacing: 10) {
            DDThumb(em: o.em, size: 46, radius: 8)
            VStack(alignment: .leading, spacing: 4) {
                Text(msgTitle(o)).font(pf(14.5, .medium)).foregroundColor(DDColor.ink).lineLimit(2)
                Text(o.title).font(pf(12.5)).foregroundColor(DDColor.sub).lineLimit(1)
                Text(timeText(o.at)).font(pf(11.5)).foregroundColor(DDColor.sub)
            }
            Spacer(minLength: 0)
            if o.status == "grouping" {
                Button { store.invite(o.id) } label: {
                    Text(Tr("邀好友拼单"))
                        .font(pf(12.5, .medium)).foregroundColor(.white)
                        .padding(.horizontal, 10).frame(height: 28)
                        .background(Capsule().fill(DDColor.red))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(DDColor.cardGrad)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DDColor.cardEdge, lineWidth: 0.6))
        .shadow(color: DDColor.cardShadow, radius: 10, y: 3)
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
        .onTapGesture { onOrders() }
    }

    private func msgTitle(_ o: DDOrder) -> String {
        switch o.status {
        case "grouping":
            let left = max(1, o.need - o.have)
            return Tr("你参与的拼单还差 ") + String(left) + Tr(" 人成团")
        case "wait":    return Tr("拼单成功，商家正在打包")
        case "shipped": return Tr("包裹已发出，注意收货")
        case "done":    return Tr("订单已完成，去评价一下吧")
        default:        return Tr("订单已取消")
        }
    }
}

struct DDCartTab: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject private var store = DDStore.shared
    var onOpen: (DDProduct) -> Void
    var onOrders: () -> Void

    @State private var checked: Set<String> = []
    @State private var showPay = false

    @State private var showXYPayCart = false

    @State private var showAliPayCart = false
    @State private var aliPayOrder: DDOrder? = nil

    @State private var pickedAddrId = ""
    @State private var showAddrList = false
    @State private var needAddr = false
    @State private var waitAddrThenPay = false

    private var lines: [DDCartLine] { store.cart }

    private var chosenAddr: DDAddress? {
        if !pickedAddrId.isEmpty, let a = store.addresses.first(where: { $0.id == pickedAddrId }) {
            return a
        }
        return store.defaultAddress
    }
    private var addrReady: Bool {
        guard let a = chosenAddr else { return false }
        return !a.full.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !a.name.isEmpty && a.phone.count >= 6
    }
    private var total: Double {
        lines.filter { checked.contains($0.pid) }.reduce(0) { sum, l in
            sum + (store.product(l.pid)?.price ?? 0) * Double(l.count)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if lines.isEmpty {
                VStack(spacing: 10) {
                    Text("🛒").font(.system(size: 42))
                    Text(Tr("购物车还是空的")).font(pf(15)).foregroundColor(DDColor.sub)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {

                        ForEach(Array(store.cartGrouped().enumerated()), id: \.offset) { _, g in
                            shopHead(g.shop, g.lines)
                            ForEach(g.lines) { l in line(l) }
                        }

                        if !store.invalidCart.isEmpty {
                            VStack(spacing: 0) {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle").font(.system(size: 13))
                                        .foregroundColor(DDColor.sub)
                                    Text(Tr("失效商品")).font(pf(13.5, .medium)).foregroundColor(DDColor.ink)
                                    Text(String(store.invalidCart.count) + Tr(" 件")).font(pf(12)).foregroundColor(DDColor.sub)
                                    Spacer(minLength: 0)
                                    Button { store.clearInvalidCart() } label: {
                                        Text(Tr("清空失效")).font(pf(12.5)).foregroundColor(DDColor.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 12).frame(height: 40)
                                ForEach(store.invalidCart) { l in
                                    HStack(spacing: 10) {
                                        Text("📦").font(.system(size: 20))
                                            .frame(width: 46, height: 46)
                                            .background(DDColor.page)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                        Text(store.product(l.pid)?.title ?? Tr("商品已下架"))
                                            .font(pf(12.5)).foregroundColor(DDColor.sub).lineLimit(1)
                                        Spacer(minLength: 0)
                                        Button { store.removeCartLine(l.pid) } label: {
                                            Text(Tr("移除")).font(pf(12.5)).foregroundColor(DDColor.sub)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 12).frame(height: 60)
                                }
                            }
                            .background(DDColor.cardGrad)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DDColor.cardEdge, lineWidth: 0.6))
                            .shadow(color: DDColor.cardShadow, radius: 10, y: 3)
                            .padding(.horizontal, 10)
                        }
                        Spacer().frame(height: 12)
                    }
                    .padding(.vertical, 10)
                }
                bottomBar
            }
        }
        .background(DDColor.page)
    }

    private func line(_ l: DDCartLine) -> some View {
        let p = store.product(l.pid)
        return HStack(spacing: 10) {
            Button { toggle(l.pid) } label: {
                Image(systemName: checked.contains(l.pid) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(checked.contains(l.pid) ? DDColor.blue : DDColor.sub)
            }
            .buttonStyle(.plain)

            Button { if let p { onOpen(p) } } label: {
                HStack(spacing: 10) {
                    DDThumb(em: p?.em ?? "📦", size: 64, radius: 8, img: p?.img)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(p?.title ?? "").font(pf(13)).foregroundColor(DDColor.ink).lineLimit(2)
                        DDPrice(value: (p?.price ?? 0) * Double(l.count), size: 15)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            HStack(spacing: 0) {
                step("−") { store.setCount(l.pid, l.count - 1) }
                Text(String(l.count)).font(pf(13)).frame(width: 30)
                step("+") { store.setCount(l.pid, l.count + 1) }
            }
        }
        .padding(12)
        .background(DDColor.cardGrad)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DDColor.cardEdge, lineWidth: 0.6))
        .shadow(color: DDColor.cardShadow, radius: 10, y: 3)
        .padding(.horizontal, 10)

        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { store.removeCartLine(l.pid) } label: { Text(Tr("删除")) }
        }
    }

    private func shopHead(_ shop: String, _ ls: [DDCartLine]) -> some View {
        let n = ls.filter { checked.contains($0.pid) }.count
        return HStack(spacing: 8) {
            Image(systemName: "storefront").font(.system(size: 13)).foregroundColor(DDColor.ink)
            Text(shop).font(pf(13.5, .medium)).foregroundColor(DDColor.ink).lineLimit(1)
            Spacer(minLength: 0)
            Text(n > 0 ? (Tr("已选 ") + String(n) + Tr(" 件")) : Tr("未选"))
                .font(pf(11.5)).foregroundColor(DDColor.sub)
        }
        .padding(.horizontal, 14).frame(height: 34)
    }

    private func step(_ t: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(t).font(pf(15, .medium))
                .foregroundColor(t == "+" ? DDColor.blue : DDColor.ink)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(t == "+" ? DDColor.blueLight : DDColor.page))
        }
        .buttonStyle(.plain)
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            HairLine()
            HStack(spacing: 10) {
                Button { checked = (checked.count == lines.count ? [] : Set(lines.map { $0.pid })) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: checked.count == lines.count && !lines.isEmpty
                              ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 19))
                            .foregroundColor(checked.count == lines.count ? DDColor.blue : DDColor.sub)
                        Text(Tr("全选")).font(pf(13.5)).foregroundColor(DDColor.ink)
                    }
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                Text(Tr("合计 ")).font(pf(13)).foregroundColor(DDColor.sub)
                DDPrice(value: total, size: 18)
                Button { showPay = true } label: {
                    Text(Tr("去结算") + (checked.isEmpty ? "" : "(\(checked.count))"))
                        .font(pf(15, .medium)).foregroundColor(.white)
                        .padding(.horizontal, 18).frame(height: 38)
                        .background(Capsule().fill(checked.isEmpty
                                                   ? DDColor.sub : DDColor.blue))
                }
                .buttonStyle(.plain)
                .disabled(checked.isEmpty)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(DDColor.card)
        }
        .sheet(isPresented: $showPay) { paySheet }
    }

    private var paySheet: some View {
        VStack(spacing: 0) {
            DDSheetBar(title: Tr("确认下单"))
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {

                    Button { showAddrList = true } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 19)).foregroundColor(DDColor.red)
                            VStack(alignment: .leading, spacing: 4) {
                                if let a = chosenAddr {
                                    HStack(spacing: 8) {
                                        Text(a.name.isEmpty ? Tr("未填收货人") : a.name)
                                            .font(pf(15, .medium)).foregroundColor(DDColor.ink)
                                        if !a.phone.isEmpty {
                                            Text(a.phone).font(pf(13)).foregroundColor(DDColor.sub)
                                        }
                                    }
                                    Text(a.full.isEmpty ? Tr("还没填详细地址") : a.full)
                                        .font(pf(13)).foregroundColor(DDColor.sub)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                } else {
                                    Text(Tr("请先填写收货地址"))
                                        .font(pf(15)).foregroundColor(DDColor.red)
                                    Text(Tr("点这里新增一条")).font(pf(12.5)).foregroundColor(DDColor.sub)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(DDColor.sub.opacity(0.55))
                                .padding(.top, 4)
                        }
                        .padding(14)
                        .background(DDColor.cardGrad)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DDColor.cardEdge, lineWidth: 0.6))
                        .shadow(color: DDColor.cardShadow, radius: 10, y: 3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    ForEach(lines.filter { checked.contains($0.pid) }) { l in
                        HStack(spacing: 10) {
                            DDThumb(em: store.product(l.pid)?.em ?? "📦", size: 46, radius: 8, img: store.product(l.pid)?.img)
                            Text(store.product(l.pid)?.title ?? "")
                                .font(pf(13)).foregroundColor(DDColor.ink).lineLimit(2)
                            Spacer(minLength: 0)
                            Text("×" + String(l.count)).font(pf(13)).foregroundColor(DDColor.sub)
                        }
                        .padding(12)
                        .background(DDColor.cardGrad)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DDColor.cardEdge, lineWidth: 0.6))
                        .shadow(color: DDColor.cardShadow, radius: 10, y: 3)
                    }
                    Text(Tr("合计 ") + "¥" + moneyFmt(total))
                        .font(pf(16, .semibold)).foregroundColor(DDColor.red)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal, 14)

                    if store.isVip {
                        Text(Tr("PLUS会员立减 ") + "-¥" + moneyFmt(store.vipOff(total)))
                            .font(pf(12.5)).foregroundColor(DDColor.red)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.horizontal, 14)
                    }
                    Spacer().frame(height: 8)

                    DDPayWayList(payWay: $store.payWay)
                        .background(DDColor.cardGrad)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DDColor.cardEdge, lineWidth: 0.6))
                        .shadow(color: DDColor.cardShadow, radius: 10, y: 3)
                    Spacer().frame(height: 8)

                    DDDeliveryList(goods: total)
                        .background(DDColor.cardGrad)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DDColor.cardEdge, lineWidth: 0.6))
                        .shadow(color: DDColor.cardShadow, radius: 10, y: 3)
                    Spacer().frame(height: 8)
                }
                .padding(.vertical, 10)
            }
            Button {
                payAll()
            } label: {
                Text(Tr("提交订单"))
                    .font(pf(16, .medium)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: 23, style: .continuous).fill(DDColor.gradBtn))
                    .padding(.horizontal, 14)
            }
            .buttonStyle(.plain)
            .padding(.bottom, max(10, L.safeBottom))
            .padding(.top, 6)
        }
        .background(DDColor.page.ignoresSafeArea())
        .sheet(isPresented: $showXYPayCart) {
            XYPaySheet(amount: payableTotal, target: cartPayTitle, note: Tr("购物车结算"),
                       onSuccess: { realPayAll() })
                .environmentObject(app)
        }
        .sheet(isPresented: $showAliPayCart) {
            if let o = aliPayOrder {
                AliPayWaitingSheet(amount: o.total, orderId: o.id,
                                   sync: { _ = await store.syncToServer(o, paid: false) }) { paid in
                    if paid {
                        store.pay(o.id)
                        app.show(Tr("支付宝付款成功"))
                    } else {
                        app.show(Tr("还没收到这笔付款，订单在「我的订单 → 待付款」里"))
                    }
                }
                .environmentObject(app)
            }
        }
        .sheet(isPresented: $showAddrList) {
            DDAddressListView(pick: { a in pickedAddrId = a.id })
        }
        .alert(Tr("请先填写收货地址"), isPresented: $needAddr) {
            Button(Tr("去填写")) { showAddrList = true }
            Button(Tr("取消"), role: .cancel) { waitAddrThenPay = false }
        } message: {
            Text(Tr("收货人、手机号、详细地址都要填，填好就直接接着付款"))
        }
        .onChange(of: showAddrList) { v in
            guard !v, waitAddrThenPay else { return }
            if addrReady {
                waitAddrThenPay = false

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { payAll() }
            }
        }
        .ddLight()
    }

    private var cartPayTitle: String {
        let n = lines.filter { checked.contains($0.pid) }.count
        return n > 0 ? Tr("合并付款 ") + String(n) + Tr(" 件商品") : Tr("购物车结算")
    }

    private var payableTotal: Double {
        max(0, total - (store.isVip ? store.vipOff(total) : 0) + store.deliveryFee(total))
    }

    private func payAll() {

        guard addrReady else {
            waitAddrThenPay = true
            needAddr = true
            return
        }

        if store.payWay == XYPay.name {
            showXYPayCart = true
            return
        }
        realPayAll()
    }

    private func realPayAll() {
        let paid = (store.payWay == XYPay.name)

        if store.payWay == AliPay.name {
            let picked = lines.filter { checked.contains($0.pid) }
                .map { (pid: $0.pid, count: $0.count) }
            if let o = store.placeCombined(lines: picked, address: chosenAddr, payWay: store.payWay) {
                checked = []
                showPay = false
                aliPayOrder = o
                store.jumpOrders()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { showAliPayCart = true }
                return
            }
        }
        for l in lines where checked.contains(l.pid) {

            let o = store.place(pid: l.pid, count: l.count, group: false,
                                fromCart: true, address: chosenAddr)

            if paid { store.pay(o.id) }
        }
        checked = []
        showPay = false
        app.show(paid ? Tr("支付成功") : Tr("下单成功，去「我的订单」看进度"))

        store.jumpOrders()
    }

    private func toggle(_ pid: String) {
        if checked.contains(pid) { checked.remove(pid) } else { checked.insert(pid) }
    }
}

struct DDMineTab: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject private var store = DDStore.shared
    var onOrders: () -> Void
    var onOpen: (DDProduct) -> Void

    @State private var showFav = false
    @State private var showViews = false
    @State private var showMyReviews = false
    @State private var showAfterSales = false
    @State private var showCoupons = false
    @State private var showFollowed = false
    @State private var showService = false

    @State private var showDist = false

    @State private var showHidden = false

    @State private var showVip = false

    var body: some View {
        ScrollView(showsIndicators: false) {

            VStack(spacing: 12) {
                profileCard
                DDVipBanner { showVip = true }
                    .padding(.horizontal, 12)
                orderCard
                toolCard
                Spacer().frame(height: 16)
            }
            .padding(.vertical, 12)
        }
        .background(DDColor.page)
        .sheet(isPresented: $showFav) {
            DDFavView(onOpen: { p in
                showFav = false
                onOpen(p)
            })
            .environmentObject(app)
        }
        .sheet(isPresented: $showViews) {
            DDViewsView(onOpen: { p in
                showViews = false
                onOpen(p)
            })
        }
        .sheet(isPresented: $showMyReviews) { DDMyReviewsView() }
        .sheet(isPresented: $showAfterSales) { DDAfterSaleListView() }
        .sheet(isPresented: $showCoupons) { DDCouponSheet(total: 0) { _ in } }
        .sheet(isPresented: $showFollowed) {
            DDShopFollowListView(onOpen: { p in
                showFollowed = false
                onOpen(p)
            })
        }
        .sheet(isPresented: $showService) { DDHelpCenterView().environmentObject(app) }

        .sheet(isPresented: $showDist) { DistMeView().environmentObject(app) }
        .sheet(isPresented: $showHidden) { MallHiddenView().environmentObject(app) }
        .sheet(isPresented: $showVip) {
            DDVipPageView(onOpen: { p in
                showVip = false
                onOpen(p)
            })
            .environmentObject(app)
        }
    }

    private var profileCard: some View {

        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                Avatar(path: app.me?.avatar ?? "", size: 64, radius: 32)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2.5))
                    .shadow(color: DDColor.blue.opacity(0.14), radius: 8, y: 3)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(app.me?.nickname ?? app.me?.username ?? Tr("我"))
                            .font(pf(18, .semibold)).foregroundColor(DDColor.ink).lineLimit(1)
                        if store.isVip {
                            Text("PLUS")
                                .font(pf(10.5, .bold))
                                .foregroundColor(Color(hex: 0x5A3E14))
                                .padding(.horizontal, 6).frame(height: 18)
                                .background(Capsule().fill(LinearGradient(
                                    colors: [Color(hex: 0xFFE7B0), Color(hex: 0xFFC861)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing)))
                        }
                    }
                    Text(Tr("星言号 ") + (app.me?.username ?? ""))
                        .font(pf(12.5)).foregroundColor(DDColor.sub).lineLimit(1)

                        .copyOnLongPress(app.me?.username ?? "") { app.show($0) }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 14)

            HairLine(inset: 16, color: DDColor.red.opacity(0.10))

            HStack(spacing: 0) {
                statCell(String(store.orders.count), Tr(DDStore.groupOn ? "我的拼单" : "我的订单")) { onOrders() }
                statDivider
                statCell(String(store.favs.count), Tr("我的收藏")) { showFav = true }
                statDivider
                statCell(String(store.viewed.count), Tr("浏览足迹")) { showViews = true }
            }
            .padding(.vertical, 14)
        }
        .background(DDColor.mineCardGrad)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(DDColor.cardEdge.opacity(0.7), lineWidth: 0.6))
        .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)
        .shadow(color: DDColor.cardShadow, radius: 14, y: 5)
        .padding(.horizontal, 12)
    }

    private func statCell(_ n: String, _ label: String, _ tap: @escaping () -> Void) -> some View {
        Button { tap() } label: {
            VStack(spacing: 4) {
                Text(n).font(pf(18.5, .semibold)).foregroundColor(DDColor.ink).monospacedDigit()
                Text(label).font(pf(11.5)).foregroundColor(DDColor.sub)
            }
            .frame(maxWidth: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var statDivider: some View {
        Rectangle().fill(DDColor.cardEdge).frame(width: 0.6, height: 24)
    }

    private var orderCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text(Tr("我的订单")).font(pf(16, .semibold)).foregroundColor(DDColor.ink)
                Spacer(minLength: 0)
                Button { onOrders() } label: {
                    HStack(spacing: 2) {
                        Text(Tr("全部订单")).font(pf(12.5)).foregroundColor(DDColor.sub)
                        Chevron(size: 8, line: 1.4)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)
            HairLine(inset: 16)
            HStack(spacing: 0) {

                if DDStore.groupOn {
                    orderEntry("拼团中", "person.2.fill", store.orders.filter { $0.status == "grouping" }.count)
                } else {
                    orderEntry("待付款", "creditcard.fill", store.orders.filter { $0.status == "paying" }.count)
                }
                orderEntry("待发货", "shippingbox.fill", store.orders.filter { $0.status == "wait" }.count)
                orderEntry("待收货", "truck.box.fill", store.orders.filter { $0.status == "shipped" }.count)
                orderEntry("已完成", "checkmark.seal.fill", store.orders.filter { $0.status == "done" }.count)
            }
            .padding(.vertical, 14)
        }
        .background(DDColor.cardGrad)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(DDColor.cardEdge.opacity(0.7), lineWidth: 0.6))
        .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)
        .shadow(color: DDColor.cardShadow, radius: 14, y: 5)
        .padding(.horizontal, 12)
    }

    private func orderEntry(_ label: String, _ icon: String, _ n: Int) -> some View {
        Button { onOrders() } label: {
            VStack(spacing: 5) {
                ZStack(alignment: .topTrailing) {

                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(LinearGradient(colors: [DDColor.red.opacity(0.16), DDColor.red.opacity(0.07)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 40, height: 40)
                        Image(systemName: icon)
                            .font(.system(size: 19))
                            .foregroundColor(DDColor.red)
                    }
                    if n > 0 {
                        Text(String(n)).font(pf(9.5, .semibold)).foregroundColor(.white)
                            .padding(.horizontal, 4).frame(height: 14)
                            .background(Capsule().fill(DDColor.redDeep))
                            .offset(x: 6, y: -4)
                    }
                }
                Text(Tr(label)).font(pf(11.5)).foregroundColor(DDColor.ink)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var toolCard: some View {
        VStack(spacing: 0) {
            toolRow("我的收藏", "heart.fill", Tr("\(store.favs.count) 件")) { showFav = true }
            HairLine(inset: 52)

            toolRow("浏览足迹", "clock.fill", Tr("\(store.viewed.count) 件")) { showViews = true }
            HairLine(inset: 52)
            toolRow("我的评价", "star.bubble", Tr("\(store.reviews.count) 条")) { showMyReviews = true }
            HairLine(inset: 52)
            toolRow("退款/售后", "arrow.uturn.backward", Tr("\(store.afterSales.count) 单")) { showAfterSales = true }
            HairLine(inset: 52)
            toolRow("我的优惠券", "ticket", Tr("\(store.usableCoupons(99999).count) 张可用")) { showCoupons = true }
            HairLine(inset: 52)
            toolRow("关注的店铺", "heart.circle", Tr("\(store.followedShops.count) 家")) { showFollowed = true }

            HairLine(inset: 52)
            toolRow("我的推广", "person.badge.plus", Tr("赚佣金 / 帮好友助力")) { showDist = true }
            HairLine(inset: 52)

            toolRow("不感兴趣与隐藏", "hand.thumbsdown",
                    Tr("\(store.disliked.count) 件商品 · \(store.hiddenAds.count) 条广告")) { showHidden = true }
            HairLine(inset: 52)
            toolRow("联系客服", "bubble.left.and.bubble.right", "") { showService = true }
        }
        .background(DDColor.cardGrad)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(DDColor.cardEdge.opacity(0.7), lineWidth: 0.6))
        .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)
        .shadow(color: DDColor.cardShadow, radius: 14, y: 5)
        .padding(.horizontal, 12)
    }

    private func toolRow(_ title: String, _ icon: String, _ right: String,
                         _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            HStack(spacing: 12) {

                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(colors: [DDColor.blue.opacity(0.15), DDColor.blue.opacity(0.06)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 15))
                        .foregroundColor(DDColor.blue)
                }
                Text(Tr(title)).font(pf(15.5)).foregroundColor(DDColor.ink)
                Spacer(minLength: 0)
                Text(right).font(pf(12.5)).foregroundColor(DDColor.sub).lineLimit(1)
                Chevron(size: 9, line: 1.5)
            }
            .padding(.horizontal, 14).frame(height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

}

struct DDDetailView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = DDStore.shared

    let product: DDProduct

    private let onCart: (() -> Void)?

    private let onOpenOther: ((DDProduct) -> Void)?

    init(product: DDProduct, onCart: (() -> Void)? = nil, onOpenOther: ((DDProduct) -> Void)? = nil) {
        self.product = product
        self.onCart = onCart
        self.onOpenOther = onOpenOther
    }

    @State private var showOrder = false
    @State private var group = true

    @State private var pickedSpec = ""
    @State private var showSpec = false
    @State private var showShare = false
    @State private var showService = false
    @State private var showShop = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    hero
                    priceCard
                    configurationCard
                    serviceRow
                    deliveryCard

                    if DDStore.groupOn { groupCard }
                    shopCard
                    DDReviewSection(product: product)
                    DDParamSection(product: product)
                    DDDetailLongSection(product: product)
                    sectionTitle(Tr("看了又看"))
                    recommendRow
                    Spacer().frame(height: 12)
                }
                .padding(.bottom, 10)
            }
            bottomBar
        }
        .background(DDColor.page.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showOrder) {
            DDOrderSheet(product: product, group: group, spec: pickedSpec)
                .environmentObject(app)
        }
        .sheet(isPresented: $showSpec) {
            DDSpecSheet(product: product) { v in pickedSpec = v.name }
                .ddLight()
        }
        .sheet(isPresented: $showShare) { DDShareSheet(product: product).environmentObject(app) }
        .sheet(isPresented: $showService) { DDHelpCenterView(product: product).environmentObject(app) }
        .sheet(isPresented: $showShop) {
            DDShopPageView(shop: product.shop, onOpen: { p in
                showShop = false
                onOpenOther?(p)
            })
        }
        .ddLight()

        .onAppear { if pickedSpec.isEmpty { pickedSpec = product.specList.first?.name ?? "" } }
    }

    private var selectedVariant: DDVariant? {
        product.specList.first { $0.name == pickedSpec } ?? product.specList.first
    }

    private var displayPrice: Double {
        selectedVariant?.price ?? product.price
    }

    private var configurationCard: some View {
        Button { showSpec = true } label: {
            HStack(spacing: 14) {
                Text(Tr("选择"))
                    .font(pf(13.5))
                    .foregroundColor(DDColor.sub)
                    .frame(width: 34, alignment: .leading)
                Text(pickedSpec.isEmpty ? (selectedVariant?.name ?? Tr("标准款")) : pickedSpec)
                    .font(pf(15, .medium))
                    .foregroundColor(DDColor.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("¥" + moneyFmt(displayPrice))
                    .font(pf(13.5))
                    .foregroundColor(DDColor.sub)
                Chevron(size: 8, line: 1.5)
            }
            .padding(.horizontal, 18)
            .frame(height: 58)
            .background(DDColor.card)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { HairLine(inset: 18) }
    }

    private var deliveryCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(C.green)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(store.deliveryMode?.name ?? Tr("普通快递"))
                    .font(pf(14, .medium))
                    .foregroundColor(DDColor.ink)
                Text(store.deliveryMode?.days ?? Tr("预计 48 小时内发货"))
                    .font(pf(12.5))
                    .foregroundColor(DDColor.sub)
            }
            Spacer(minLength: 8)
            Text(store.deliveryMode?.note ?? Tr("全国配送"))
                .font(pf(12))
                .foregroundColor(DDColor.weak)
                .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 66)
        .background(DDColor.card)
        .overlay(alignment: .top) { HairLine(inset: 18) }
    }

    private var serviceRow: some View {
        HStack(spacing: 14) {
            ForEach(product.serviceList.prefix(4), id: \.self) { s in
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 11)).foregroundColor(C.green)
                    Text(s).font(pf(11.5)).foregroundColor(DDColor.sub)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(DDColor.card)
        .overlay(alignment: .top) { HairLine(inset: 18) }
    }

    private func sectionTitle(_ t: String) -> some View {
        HStack {
            Text(t).font(pf(15, .semibold)).foregroundColor(DDColor.ink)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.top, 4)
    }

    private var recommendRow: some View {
        let others = store.live.filter { $0.id != product.id && ($0.cate == product.cate || $0.shop == product.shop) }.prefix(6)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(others)) { p in
                    Button { onOpenOther?(p) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            DDThumb(em: p.em, size: 104, radius: 10, img: p.img)
                            DDPrice(value: p.price, size: 15)
                            Text(p.title).font(pf(11.5)).foregroundColor(DDColor.sub)
                                .lineLimit(2).frame(width: 104, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(DDColor.ink)
                    .frame(width: 34, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text(Tr("商品详情")).font(pf(17, .semibold)).foregroundColor(DDColor.ink)
            Spacer(minLength: 0)
            Button { store.toggleFav(product.id) } label: {
                Image(systemName: store.isFav(product.id) ? "heart.fill" : "heart")
                    .font(.system(size: 17))
                    .foregroundColor(store.isFav(product.id) ? DDColor.redDeep : DDColor.ink)
                    .frame(width: 34, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { showShare = true } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 17))
                    .foregroundColor(DDColor.ink)
                    .frame(width: 34, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(DDColor.card)
        .overlay(HairLine(), alignment: .bottom)
    }

    private var hero: some View {
        ZStack {
            Color(hex: 0xF7F8FA)
            if let img = product.img, !img.isEmpty {
                RemoteImage(path: img, icon: "photo")
                    .frame(maxWidth: .infinity).frame(height: 330).clipped()
            } else {
                Text(product.em).font(.system(size: 170))
            }
        }
        .frame(height: 330)
    }

    private var priceCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                DDPrice(value: displayPrice, size: 27, color: DDColor.ink)
                if product.orig > displayPrice {
                    Text("¥" + moneyFmt(product.orig))
                        .font(pf(13)).foregroundColor(DDColor.weak).strikethrough()
                }
                Spacer(minLength: 8)
                if let rating = product.rating, rating > 0 {
                    Label(String(format: "%.1f", rating), systemImage: "star.fill")
                        .font(pf(11.5, .medium))
                        .foregroundColor(Color(hex: 0xA37D38))
                }
            }
            Text(product.title)
                .font(pf(21, .semibold))
                .foregroundColor(DDColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle = product.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(pf(13.5))
                    .foregroundColor(DDColor.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Text(Tr("官方正品"))
                    .font(pf(11, .medium))
                    .foregroundColor(C.green)
                    .padding(.horizontal, 7)
                    .frame(height: 21)
                    .background(Capsule().fill(C.green.opacity(0.10)))
                if !product.sold.isEmpty {
                    Text(Tr("已售") + product.sold)
                        .font(pf(12))
                        .foregroundColor(DDColor.sub)
                }
                Spacer(minLength: 0)
                if !product.tags.isEmpty {
                    Text(product.tags.prefix(2).joined(separator: " · "))
                        .font(pf(11.5))
                        .foregroundColor(DDColor.weak)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DDColor.card)
    }

    private var groupCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(Tr("正在拼单")).font(pf(15, .semibold)).foregroundColor(DDColor.ink)
                Text(Tr("\(product.grp)人团")).font(pf(11)).foregroundColor(.white)
                    .padding(.horizontal, 6).frame(height: 18)
                    .background(Capsule().fill(DDColor.red))
                Spacer(minLength: 0)
                Text(Tr("还差 1 人成团")).font(pf(12)).foregroundColor(DDColor.sub)
            }
            ForEach(0..<2, id: \.self) { i in
                HStack(spacing: 10) {
                    Circle().fill(Color(hex: 0xFFD9CC)).frame(width: 34, height: 34)
                        .overlay(Text(i == 0 ? "拼" : "友")
                            .font(pf(13, .semibold)).foregroundColor(DDColor.red))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(i == 0 ? Tr("拼友 138****6621") : Tr("拼友 186****3302"))
                            .font(pf(13.5)).foregroundColor(DDColor.ink)
                        Text(Tr("还剩 ") + String(23 - i * 7) + Tr(" 小时"))
                            .font(pf(11.5)).foregroundColor(DDColor.sub)
                    }
                    Spacer(minLength: 0)
                    Button { app.show(Tr("已加入 TA 的拼单")) } label: {
                        Text(Tr("去拼单"))
                            .font(pf(13, .medium)).foregroundColor(.white)
                            .padding(.horizontal, 12).frame(height: 30)
                            .background(Capsule().fill(DDColor.red))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(DDColor.cardGrad)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DDColor.cardEdge, lineWidth: 0.6))
        .shadow(color: DDColor.cardShadow, radius: 10, y: 3)
        .padding(.horizontal, 10)
    }

    private var shopCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(C.green.opacity(0.10))
                    .frame(width: 40, height: 40)
                    .overlay(Image(systemName: "building.2")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(C.green))
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.shop).font(pf(14.5, .medium)).foregroundColor(DDColor.ink)
                    Text(Tr("官方授权") + " · " + Tr(product.cate))
                        .font(pf(12)).foregroundColor(DDColor.sub)
                }
                Spacer(minLength: 0)

                Button { showShop = true } label: {
                    Text(Tr("进店")).font(pf(12.5)).foregroundColor(C.green)
                        .padding(.horizontal, 10).frame(height: 28)
                        .background(Capsule().stroke(C.green.opacity(0.45), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                Button { store.toggleFollow(product.shopKey) } label: {
                    Text(store.isFollowed(product.shopKey) ? Tr("已关注") : Tr("关注"))
                        .font(pf(12.5)).foregroundColor(store.isFollowed(product.shopKey) ? DDColor.sub : C.green)
                        .padding(.horizontal, 10).frame(height: 28)
                        .background(Capsule().stroke(store.isFollowed(product.shopKey)
                                                     ? DDColor.sub.opacity(0.35) : C.green.opacity(0.45),
                                                     lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                Button { showService = true } label: {
                    Text(Tr("客服")).font(pf(12.5)).foregroundColor(DDColor.ink)
                        .padding(.horizontal, 10).frame(height: 28)
                        .background(Capsule().fill(DDColor.page))
                }
                .buttonStyle(.plain)
            }
            HairLine()
            Text(Tr("商品介绍")).font(pf(14, .semibold)).foregroundColor(DDColor.ink)
            Text(product.title + Tr(DDStore.groupOn
                                    ? "。产地直发、坏果包赔、退货包运费，拼单更便宜。"
                                    : "。产地直发、坏果包赔、退货包运费，48 小时内发货。"))
                .font(pf(13.5)).foregroundColor(DDColor.sub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(DDColor.card)
        .overlay(alignment: .top) { HairLine() }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            HairLine()
            HStack(spacing: 10) {
                Button { addToCart() } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "cart.badge.plus").font(.system(size: 19))
                        Text(Tr("购物车")).font(pf(10.5))
                    }
                    .foregroundColor(DDColor.ink)
                    .frame(width: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if DDStore.groupOn {

                    Button {
                        group = false
                        showOrder = true
                    } label: {
                        buyButton(Tr("单独购买"), "¥" + moneyFmt(product.orig), nil, soft: true)
                    }
                    .buttonStyle(.plain)
                    Button {
                        group = true
                        showOrder = true
                    } label: {
                        buyButton(Tr("发起拼单"), "¥" + moneyFmt(product.price), C.green)
                    }
                    .buttonStyle(.plain)
                } else {

                    Button { addToCart() } label: {
                        buyButton(Tr("加入购物车"), "", nil, soft: true)
                    }
                    .buttonStyle(.plain)
                    Button {
                        group = false
                        showOrder = true
                    } label: {
                        buyButton(Tr("立即购买"), "¥" + moneyFmt(product.price), C.green)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.top, 8)
            .padding(.bottom, max(8, L.safeBottom))
        }
        .background(DDColor.card)
    }

    private func buyButton(_ title: String, _ price: String, _ solid: Color?,
                           soft: Bool = false) -> some View {
        VStack(spacing: 1) {
            Text(title).font(pf(15, .medium))
            if !price.isEmpty { Text(price).font(pf(11.5)) }
        }
        .foregroundColor(soft ? C.green : .white)
        .frame(maxWidth: .infinity).frame(height: 44)
        .background {
            if let solid { RoundedRectangle(cornerRadius: 22, style: .continuous).fill(solid) }
            else if soft { RoundedRectangle(cornerRadius: 22, style: .continuous).fill(C.green.opacity(0.09)) }
            else { RoundedRectangle(cornerRadius: 22, style: .continuous).fill(DDColor.gradBtn) }
        }
    }

    private func justAddToCart() {
        if !pickedSpec.isEmpty { store.setCartSpec(product.id, pickedSpec) }
        store.addCart(product.id)
        app.show(Tr("已加入购物车"))
    }

    private func addToCart() {
        if !pickedSpec.isEmpty { store.setCartSpec(product.id, pickedSpec) }
        store.addCart(product.id)
        app.show(Tr("已加入购物车"))
        store.jumpCart()
        onCart?()
        dismiss()
    }
}

struct DDOrderSheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = DDStore.shared

    let product: DDProduct

    private let spec: String
    @State private var group: Bool
    @State private var count = 1

    @State private var pickedAddrId = ""
    @State private var showAddrList = false

    @State private var couponOff: Double = 0
    @State private var couponTitle = ""
    @State private var showCoupon = false
    @State private var remark = ""
    @State private var invoice = ""
    @State private var showInvoice = false

    @State private var showVip = false

    @State private var needAddr = false

    @State private var waitAddrThenPay = false

    @State private var showXYPay = false

    @State private var showAliPay = false
    @State private var aliPayOrder: DDOrder? = nil

    init(product: DDProduct, group: Bool, spec: String = "") {
        self.product = product
        self.spec = spec
        _group = State(initialValue: group)
    }

    private var unit: Double { (DDStore.groupOn && !group) ? product.orig : product.price }
    private var total: Double { unit * Double(count) }

    var body: some View {
        VStack(spacing: 0) {
            DDSheetBar(title: Tr("确认订单"))
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        DDThumb(em: product.em, size: 68, radius: 8, img: product.img)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(product.title).font(pf(13.5)).foregroundColor(DDColor.ink).lineLimit(2)
                            DDPrice(value: unit, size: 17)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(DDColor.cardGrad)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DDColor.cardEdge, lineWidth: 0.6))
                    .shadow(color: DDColor.cardShadow, radius: 10, y: 3)

                    if DDStore.groupOn {
                        VStack(spacing: 0) {
                            pick(Tr("发起拼单") + "（\(product.grp)人团）", Tr("按拼单价，人满发货"), true)
                            HairLine(inset: 14)
                            pick(Tr("单独购买"), Tr("按单买价，不用等人"), false)
                        }
                        .background(DDColor.cardGrad)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DDColor.cardEdge, lineWidth: 0.6))
                        .shadow(color: DDColor.cardShadow, radius: 10, y: 3)
                    }

                    HStack(spacing: 0) {
                        Text(Tr("数量")).font(pf(14.5)).foregroundColor(DDColor.ink)
                        Spacer(minLength: 0)
                        Button { if count > 1 { count -= 1 } } label: {
                            Text("−").font(pf(16, .medium)).foregroundColor(DDColor.ink)
                                .frame(width: 30, height: 30)
                                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(DDColor.page))
                        }
                        .buttonStyle(.plain)
                        Text(String(count)).font(pf(14)).frame(width: 36)
                        Button { count += 1 } label: {
                            Text("+").font(pf(16, .medium)).foregroundColor(DDColor.ink)
                                .frame(width: 30, height: 30)
                                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(DDColor.page))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(14)
                    .background(DDColor.cardGrad)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DDColor.cardEdge, lineWidth: 0.6))
                    .shadow(color: DDColor.cardShadow, radius: 10, y: 3)

                    Button { showAddrList = true } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 19)).foregroundColor(DDColor.red)
                            VStack(alignment: .leading, spacing: 4) {
                                if let a = chosenAddr {
                                    HStack(spacing: 8) {
                                        Text(a.name.isEmpty ? Tr("未填收货人") : a.name)
                                            .font(pf(15, .medium)).foregroundColor(DDColor.ink)
                                        if !a.phone.isEmpty {
                                            Text(a.phone).font(pf(13)).foregroundColor(DDColor.sub)
                                        }
                                    }
                                    Text(a.full.isEmpty ? Tr("还没填详细地址") : a.full)
                                        .font(pf(13)).foregroundColor(DDColor.sub)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                } else {
                                    Text(Tr("请先填写收货地址"))
                                        .font(pf(15)).foregroundColor(DDColor.red)
                                    Text(Tr("点这里新增一条")) .font(pf(12.5)).foregroundColor(DDColor.sub)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(DDColor.sub.opacity(0.55))
                                .padding(.top, 4)
                        }
                        .padding(14)
                        .background(DDColor.cardGrad)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DDColor.cardEdge, lineWidth: 0.6))
                        .shadow(color: DDColor.cardShadow, radius: 10, y: 3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    VStack(spacing: 0) {
                        payRow(Tr("优惠券"), couponOff > 0 ? ("-¥" + moneyFmt(couponOff)) : Tr("不使用"), red: couponOff > 0) {
                            showCoupon = true
                        }
                        HairLine(inset: 14)

                        payRow(Tr("PLUS会员"),
                               memberOff > 0
                                 ? ("-¥" + moneyFmt(memberOff))
                                 : (DDStore.groupOn ? Tr("未开通") : Tr("未开通 · 立省 ¥" + moneyFmt(wouldSave))),
                               red: memberOff > 0) { showVip = true }
                        HairLine(inset: 14)
                        payRow(Tr("发票"), invoice.isEmpty ? Tr("不开发票") : invoice, red: false) { showInvoice = true }
                        HairLine(inset: 14)

                        DDDeliveryList(goods: goodsAmount)
                        HairLine(inset: 14)

                        DDPayWayList(payWay: $store.payWay)
                    }
                    .background(DDColor.cardGrad)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DDColor.cardEdge, lineWidth: 0.6))
                    .shadow(color: DDColor.cardShadow, radius: 10, y: 3)

                    HStack(spacing: 10) {
                        Text(Tr("备注")).font(pf(14)).foregroundColor(DDColor.ink)
                        TextField(Tr("给商家留言（可不填）"), text: $remark)
                            .font(pf(13.5))
                    }
                    .padding(.horizontal, 14).frame(height: 48)
                    .background(DDColor.cardGrad)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DDColor.cardEdge, lineWidth: 0.6))
                    .shadow(color: DDColor.cardShadow, radius: 10, y: 3)

                    HStack {
                        Text(Tr("合计")).font(pf(14)).foregroundColor(DDColor.sub)
                        Spacer(minLength: 0)
                        DDPrice(value: payable, size: 20)
                    }
                    .padding(.horizontal, 4)
                    Spacer().frame(height: 8)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            Button { submit() } label: {
                Text((DDStore.groupOn && group) ? Tr("发起拼单") : Tr("立即支付"))
                    .font(pf(16, .medium)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: 23, style: .continuous).fill(DDColor.gradBtn))
                    .padding(.horizontal, 14)
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            .padding(.bottom, max(10, L.safeBottom))
        }
        .background(DDColor.page.ignoresSafeArea())
        .sheet(isPresented: $showAddrList) {
            DDAddressListView(pick: { a in pickedAddrId = a.id })
        }

        .alert(Tr("请先填写收货地址"), isPresented: $needAddr) {
            Button(Tr("去填写")) { showAddrList = true }
            Button(Tr("取消"), role: .cancel) { waitAddrThenPay = false }
        } message: {
            Text(Tr("收货人、手机号、详细地址都要填，填好就直接接着付款"))
        }

        .onChange(of: showAddrList) { v in
            guard !v, waitAddrThenPay else { return }
            let a = chosenAddr
            let full = (a?.full ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let ok = a != nil && !full.isEmpty && !(a!.name.isEmpty) && (a!.phone.count >= 6)
            if ok {
                waitAddrThenPay = false

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { submit() }
            }
        }
        .sheet(isPresented: $showCoupon) {
            DDCouponSheet(total: payable) { c in
                couponOff = c?.off ?? 0
                couponTitle = c?.title ?? ""
                if let c = c { store.useCoupon(c.id) }
            }
        }
        .sheet(isPresented: $showInvoice) {
            DDInvoiceSheet(title: $invoice).ddLight()
        }
        .sheet(isPresented: $showVip) {
            DDVipPageView().environmentObject(app)
        }

        .sheet(isPresented: $showXYPay) {
            XYPaySheet(amount: payable, target: product.title,
                       note: (DDStore.groupOn && group ? Tr("发起拼单") : Tr("立即购买")) + " ×" + String(count),
                       onSuccess: { doSubmit() })
                .environmentObject(app)
        }

        .sheet(isPresented: $showAliPay) {
            if let o = aliPayOrder {
                AliPayWaitingSheet(amount: o.total, orderId: o.id,
                                   sync: { _ = await store.syncToServer(o, paid: false) }) { paid in
                    if paid {
                        store.pay(o.id)
                        app.show(Tr("支付宝付款成功"))
                    } else {
                        app.show(Tr("还没收到这笔付款，订单在「我的订单 → 待付款」里"))
                    }
                }
                .environmentObject(app)
            }
        }
        .ddLight()
    }

    private var goodsAmount: Double {
        let u = product.specList.first { $0.name == spec }?.price ?? unit
        return u * Double(count)
    }

    private var memberOff: Double { store.vipOff(goodsAmount) }

    private var wouldSave: Double { (goodsAmount * (1 - DDStore.vipRate) * 100).rounded() / 100 }

    private var payable: Double {
        max(0, goodsAmount - couponOff - memberOff + store.deliveryFee(goodsAmount))
    }

    private func payRow(_ l: String, _ r: String, red: Bool, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            HStack {
                Text(l).font(pf(14)).foregroundColor(DDColor.ink)
                Spacer(minLength: 0)
                Text(r).font(pf(13.5)).foregroundColor(red ? DDColor.red : DDColor.sub)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DDColor.sub.opacity(0.55))
            }
            .padding(.horizontal, 14).frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var chosenAddr: DDAddress? {
        if !pickedAddrId.isEmpty, let a = store.addresses.first(where: { $0.id == pickedAddrId }) {
            return a
        }
        return store.defaultAddress
    }

    private func pick(_ title: String, _ sub: String, _ isGroup: Bool) -> some View {
        Button { group = isGroup } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(pf(15, .medium)).foregroundColor(DDColor.ink)
                    Text(sub).font(pf(12)).foregroundColor(DDColor.sub)
                }
                Spacer(minLength: 0)
                Image(systemName: group == isGroup ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(group == isGroup ? DDColor.red : DDColor.sub)
            }
            .padding(.horizontal, 14).frame(height: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func submit() {

        let a = chosenAddr
        let full = (a?.full ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let incomplete = (a?.name.isEmpty ?? true) || ((a?.phone.count ?? 0) < 6)
        if a == nil || full.isEmpty || incomplete {
            waitAddrThenPay = true
            needAddr = true
            return
        }

        if store.payWay == XYPay.name {
            showXYPay = true
            return
        }
        doSubmit()
    }

    private func doSubmit() {

        let o = store.place(pid: product.id, count: count, group: DDStore.groupOn && group, spec: spec,
                            address: chosenAddr, remark: remark.trimmingCharacters(in: .whitespaces),
                            freight: 0, couponOff: couponOff, invoice: invoice, memberOff: memberOff,
                            payWay: store.payWay, paying: true)

        if store.payWay == XYPay.name { store.pay(o.id) }

        if store.payWay == AliPay.name {
            dismiss()
            aliPayOrder = o
            store.jumpOrders()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { showAliPay = true }
            return
        }
        dismiss()
        app.show(doneText)

        store.jumpOrders()
    }

    private var doneText: String {
        (store.payWay == XYPay.name) ? Tr("支付成功") : Tr("订单已提交，去付款")
    }
}

struct DDOrdersView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = DDStore.shared
    @State private var filter = 0

    init(startFilter: Int = 0) {
        _filter = State(initialValue: max(0, startFilter))
    }

    @State private var detailOrder: DDOrder?

    @State private var payWithXY: DDOrder? = nil

    @State private var payWithAli: DDOrder? = nil

    private var names: [String] {
        DDStore.groupOn ? ["全部", "拼团中", "待发货", "待收货", "已完成"]
                        : ["全部", "待付款", "待发货", "待收货", "已完成"]
    }

    private var list: [DDOrder] {
        switch filter {
        case 1: return store.orders.filter { DDStore.groupOn ? $0.status == "grouping" : $0.status == "paying" }
        case 2: return store.orders.filter { $0.status == "wait" }
        case 3: return store.orders.filter { $0.status == "shipped" }
        case 4: return store.orders.filter { $0.status == "done" }
        default: return store.orders
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            DDSheetBar(title: Tr("我的订单"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(names.indices, id: \.self) { i in
                        Button { filter = i } label: {
                            Text(Tr(names[i]))
                                .font(pf(13.5, filter == i ? .semibold : .regular))
                                .foregroundColor(filter == i ? .white : DDColor.ink)
                                .padding(.horizontal, 14).frame(height: 30)
                                .background(Capsule().fill(filter == i
                                                            ? DDColor.red : DDColor.page))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
            }
            .padding(.vertical, 8)
            .background(DDColor.page)

            if list.isEmpty {
                VStack(spacing: 8) {
                    Text("📦").font(.system(size: 38))
                    Text(Tr("这里还没有订单")).font(pf(14.5)).foregroundColor(DDColor.sub)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DDColor.page)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(list) { o in card(o) }
                        Spacer().frame(height: 14)
                    }
                    .padding(.vertical, 10)
                }
                .background(DDColor.page)
            }
        }
        .background(DDColor.page.ignoresSafeArea())
        .sheet(item: $detailOrder) { o in
            DDOrderDetailView(orderId: o.id).environmentObject(app)
        }

        .sheet(item: $payWithXY) { o in
            XYPaySheet(amount: o.total, target: o.title,
                       note: Tr("订单付款 · ") + o.statusText,
                       onSuccess: {
                           store.pay(o.id)
                           app.show(Tr("支付成功"))
                      })
                .environmentObject(app)
        }

        .sheet(item: $payWithAli) { o in
            AliPayWaitingSheet(amount: o.total, orderId: o.id,
                               sync: { _ = await store.syncToServer(o, paid: false) }) { paid in
                if paid {
                    store.pay(o.id)
                    app.show(Tr("支付宝付款成功"))
                } else {
                    app.show(Tr("还没收到这笔付款，订单还在「待付款」"))
                }
            }
            .environmentObject(app)
        }
        .ddLight()
    }

    private func card(_ o: DDOrder) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(o.shop).font(pf(13.5, .medium)).foregroundColor(DDColor.ink).lineLimit(1)
                Spacer(minLength: 0)
                Text(Tr(o.statusText))
                    .font(pf(12.5, .medium))
                    .foregroundColor(o.status == "done" || o.status == "cancel" ? DDColor.sub : DDColor.red)
            }
            if o.canPay {
                Text(Tr("还剩 ") + String(format: "%02d:%02d", o.payLeft / 60, o.payLeft % 60) + Tr(" 未付款"))
                    .font(pf(11.5)).foregroundColor(DDColor.red)
            }
            HStack(alignment: .top, spacing: 10) {
                DDThumb(em: o.em, size: 62, radius: 8)
                VStack(alignment: .leading, spacing: 4) {
                    Text(o.title).font(pf(13)).foregroundColor(DDColor.ink).lineLimit(2)
                    if o.group, DDStore.groupOn {
                        Text(Tr("拼团 ") + "\(o.have)/\(o.need)" + Tr(" 人"))
                            .font(pf(11.5)).foregroundColor(DDColor.sub)
                    }
                    Text(timeText(o.at)).font(pf(11)).foregroundColor(DDColor.sub)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    DDPrice(value: o.price, size: 15)
                    Text("×" + String(o.count)).font(pf(11.5)).foregroundColor(DDColor.sub)
                }
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                    if o.canPay {
                        Button { store.cancelOrder(o.id) } label: { smallBtn(Tr("取消订单"), false) }
                            .buttonStyle(.plain)
                        Button { payOrder(o) } label: { smallBtn(Tr("立即付款"), true) }
                            .buttonStyle(.plain)
                    }
                if o.status == "grouping", DDStore.groupOn {
                    Button { store.invite(o.id) } label: { smallBtn(Tr("邀好友拼单"), true) }
                        .buttonStyle(.plain)
                }
                if o.status == "wait" {
                    Button { store.ship(o.id) } label: { smallBtn(Tr("提醒发货"), false) }
                        .buttonStyle(.plain)
                }
                if o.canConfirm {
                    Button { store.confirm(o.id) } label: { smallBtn(Tr("确认收货"), true) }
                        .buttonStyle(.plain)
                }
                if o.canCancel {
                    Button { store.cancelOrder(o.id) } label: { smallBtn(Tr("取消订单"), false) }
                        .buttonStyle(.plain)
                }
                if o.status == "done" || o.status == "cancel" {
                    if o.status == "done" && !o.reviewed {
                        Button {
                            store.reorder(o)
                            app.show(Tr("已加入购物车"))
                            store.jumpCart()
                        } label: { smallBtn(Tr("再来一单"), false) }
                            .buttonStyle(.plain)
                    }
                    Button { store.removeOrder(o.id) } label: { smallBtn(Tr("删除"), false) }
                        .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(DDColor.cardGrad)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DDColor.cardEdge, lineWidth: 0.6))
        .shadow(color: DDColor.cardShadow, radius: 10, y: 3)
        .padding(.horizontal, 10)

        .contentShape(Rectangle())
        .onTapGesture { detailOrder = o }
    }

    private func smallBtn(_ t: String, _ filled: Bool) -> some View {
        Text(t)
            .font(pf(12.5))
            .foregroundColor(filled ? .white : DDColor.ink)
            .padding(.horizontal, 12).frame(height: 30)
            .background(Capsule().fill(filled ? DDColor.red : DDColor.page))
    }

    private func payOrder(_ o: DDOrder) {
        if store.payWay == XYPay.name {
            payWithXY = o
            return
        }

        if store.payWay == AliPay.name {
            payWithAli = o
            return
        }
        store.pay(o.id)
        app.show(Tr("支付成功"))
    }
}

struct DDFavView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = DDStore.shared
    var onOpen: (DDProduct) -> Void

    private var list: [DDProduct] { store.products.filter { store.isFav($0.id) } }

    var body: some View {
        VStack(spacing: 0) {
            DDSheetBar(title: Tr("我的收藏"))
            if list.isEmpty {
                Text(Tr("还没有收藏的商品")).font(pf(14.5)).foregroundColor(DDColor.sub)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                        GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(list) { p in
                            Button { onOpen(p) } label: { DDProductCard(product: p) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(10)
                }
            }
        }
        .background(DDColor.page.ignoresSafeArea())
        .ddLight()
    }
}

struct DDViewsView: View {
    @ObservedObject private var store = DDStore.shared
    var onOpen: (DDProduct) -> Void

    private var list: [DDProduct] { store.viewed }

    var body: some View {
        VStack(spacing: 0) {
            DDSheetBar(title: Tr("浏览足迹"))
            if list.isEmpty {
                Text(Tr("还没有浏览记录")).font(pf(14.5)).foregroundColor(DDColor.sub)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                        GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(list) { p in
                            Button { onOpen(p) } label: { DDProductCard(product: p) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(10)
                }
                Button {
                    store.clearViews()
                } label: {
                    Text(Tr("清空浏览足迹"))
                        .font(pf(14.5)).foregroundColor(DDColor.sub)
                        .frame(maxWidth: .infinity).frame(height: 44)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 8)
            }
        }
        .background(DDColor.page.ignoresSafeArea())
        .ddLight()
    }
}

struct DDSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = DDStore.shared
    var onOpen: (DDProduct) -> Void

    @State private var q = ""

    @State private var sort = ""

    @State private var onlyStock = false

    private var kw: String { q.trimmingCharacters(in: .whitespaces) }

    private var hot: [String] {
        var score: [String: Int] = [:]
        for p in store.live {
            for k in ([p.cate, p.shop] + p.tags) where !k.isEmpty {
                score[k, default: 0] += 1
            }
        }
        return score.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(10).map { $0.key }
    }

    private var suggest: [String] {
        let k = kw
        guard !k.isEmpty else { return [] }
        var out: [String] = []
        func add(_ s: String) {
            let t = s.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty, t != k, !out.contains(t), out.count < 6 { out.append(t) }
        }
        for p in store.live where p.cate.localizedCaseInsensitiveContains(k) { add(p.cate) }
        for p in store.live {
            for t in p.tags where t.localizedCaseInsensitiveContains(k) { add(t) }
        }
        for p in store.live where p.shop.localizedCaseInsensitiveContains(k) { add(p.shop) }
        for p in store.live where p.title.localizedCaseInsensitiveContains(k) { add(p.title) }
        return out
    }

    private var result: [DDProduct] {
        var list = store.search(kw)
        if onlyStock { list = list.filter { $0.inStock } }
        switch sort {
        case "sales":     list.sort { $0.salesNum > $1.salesNum }
        case "priceUp":   list.sort { $0.price < $1.price }
        case "priceDown": list.sort { $0.price > $1.price }
        default: break
        }
        return list
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            if kw.isEmpty { idle } else { found }
        }
        .background(DDColor.page.ignoresSafeArea())
        .ddLight()
    }

    private var searchBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(DDColor.ink)
                        .frame(width: 32, height: 38)
                }
                .buttonStyle(.plain)
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14)).foregroundColor(DDColor.weak)
                    TextField(Tr("搜索想要的商品"), text: $q)
                        .font(pf(14.5))
                        .submitLabel(.search)
                        .onSubmit { store.pushHistory(kw) }
                    if !q.isEmpty {
                        Button { q = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15)).foregroundColor(DDColor.weak)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12).frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 10).fill(DDColor.card))
            }
            .padding(.horizontal, 10)
        }
        .padding(.vertical, 8)
        .background(DDColor.page)
    }

    private var idle: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                if !store.history.isEmpty {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text(Tr("搜索历史")).font(pf(14.5, .semibold)).foregroundColor(DDColor.ink)
                            Spacer(minLength: 0)
                            Button { store.clearHistory() } label: {
                                Text(Tr("清空")).font(pf(12.5)).foregroundColor(DDColor.sub)
                            }
                            .buttonStyle(.plain)
                        }
                        chips(store.history, fill: true)
                    }
                }
                DDSearchHotBoard(words: hot) { w in pick(w) }
                Spacer().frame(height: 10)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
        }
        .background(DDColor.page)
    }

    private var found: some View {
        VStack(spacing: 0) {
            if !suggest.isEmpty {
                DDSuggestList(words: suggest) { w in pick(w) }
            }
            DDSearchFilterBar(sort: sort, onlyStock: onlyStock,
                              onSort: { sort = $0 },
                              onStock: { onlyStock.toggle() })
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(result) { p in
                        Button {
                            store.pushHistory(kw)
                            onOpen(p)
                        } label: { resultRow(p) }
                        .buttonStyle(.plain)
                    }
                    if result.isEmpty {
                        Text(Tr("没有找到相关商品")).font(pf(14)).foregroundColor(DDColor.sub)
                            .padding(.top, 50)
                    }
                    Spacer().frame(height: 14)
                }
                .padding(.vertical, 10)
            }
            .background(DDColor.page)
        }
    }

    private func pick(_ w: String) {
        q = w
        store.pushHistory(w)
    }

    private func chips(_ arr: [String], fill: Bool) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 8)], spacing: 8) {
            ForEach(arr, id: \.self) { s in
                Button { q = s } label: {
                    Text(s)
                        .font(pf(13)).foregroundColor(fill ? DDColor.ink : DDColor.red)
                        .padding(.horizontal, 10).frame(height: 30)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 8)
                            .fill(fill ? DDColor.card : DDColor.redLight))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func resultRow(_ p: DDProduct) -> some View {
        HStack(spacing: 10) {
            DDThumb(em: p.em, size: 62, radius: 8, img: p.img)
            VStack(alignment: .leading, spacing: 5) {
                Text(p.title).font(pf(13.5)).foregroundColor(DDColor.ink).lineLimit(2)
                HStack(spacing: 6) {
                    DDPrice(value: p.price, size: 16)
                    if !p.sold.isEmpty {
                        Text(Tr("已拼") + p.sold).font(pf(11.5)).foregroundColor(DDColor.sub)
                    }
                }
                Text(p.shop).font(pf(11.5)).foregroundColor(DDColor.sub).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(DDColor.cardGrad)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DDColor.cardEdge, lineWidth: 0.6))
        .shadow(color: DDColor.cardShadow, radius: 10, y: 3)
        .padding(.horizontal, 10)
    }
}

struct DDSwipeRow<Content: View>: View {
    var onTap: () -> Void
    var onDelete: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var dx: CGFloat = 0
    @State private var start: CGFloat = 0
    private var actW: CGFloat { UIConfig.num("mallSwipeW", 84) }

    var body: some View {
        ZStack(alignment: .trailing) {
            content()
                .offset(x: dx)
            Button { onDelete() } label: {
                VStack(spacing: 3) {
                    Image(systemName: "trash.fill").font(.system(size: 16))
                    Text(Tr("删除")).font(pf(12))
                }
                .foregroundColor(.white)
                .frame(width: actW)
                .frame(maxHeight: .infinity)
                .background(DDColor.red)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(dx < -4 ? 1 : 0)
            .allowsHitTesting(dx <= -actW * 0.55)
        }
        .padding(.horizontal, 10)

        .overlay(alignment: .leading) {
            RowSwipeCatcher(
                onTap: { _ in
                    if dx != 0 { close() } else { onTap() }
                },
                onBegan: { start = dx },
                onChanged: { v in
                    var x = min(0, start + v)
                    if x < -actW { x = -(actW + min(26, (-x - actW) * 0.25)) }
                    dx = x
                },
                onEnded: { _, vx in
                    let open = vx <= -260 || (-dx > actW * 0.45 && vx < 260)
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        dx = open ? -actW : 0
                    }
                }
            )
            .frame(width: max(0, L.width - 20 + dx))
        }
    }

    private func close() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) { dx = 0 }
    }
}

struct DDSheetBar: View {
    @Environment(\.dismiss) private var dismiss
    let title: String

    var body: some View {
        ZStack {
            Text(Tr(title)).font(pf(17, .semibold)).foregroundColor(DDColor.ink)
            HStack {
                Button { dismiss() } label: {
                    Text(Tr("关闭")).font(pf(16)).foregroundColor(DDColor.ink)
                        .frame(height: 44)
                        .padding(.horizontal, 14)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
        }
        .frame(height: L.navH)
        .background(DDColor.card)
        .overlay(HairLine(), alignment: .bottom)
    }
}

func ddTimeText(_ d: Date) -> String {
    let cal = Calendar.current
    if cal.isDateInToday(d) {
        let mins = Int(Date().timeIntervalSince(d) / 60)
        if mins < 1 { return "刚刚" }
        if mins < 60 { return "\(mins) 分钟前" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return "今天 " + f.string(from: d)
    }
    if cal.isDateInYesterday(d) {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return "昨天 " + f.string(from: d)
    }
    let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm"
    return f.string(from: d)
}

private func timeText(_ d: Date) -> String { ddTimeText(d) }

struct DDDeliveryList: View {

    let goods: Double
    @ObservedObject private var store = DDStore.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(Tr("配送")).font(pf(14)).foregroundColor(DDColor.ink)
                Spacer(minLength: 0)
                Text(store.deliveryMode?.days ?? "").font(pf(12)).foregroundColor(DDColor.sub)
            }
            .padding(.horizontal, 14).frame(height: 40)
            HairLine(inset: 14)
            ForEach(store.deliveryModes) { m in
                let on = (store.deliveryMode?.id == m.id)
                Button { store.deliveryModeId = m.id } label: {
                    HStack(spacing: 10) {
                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18))
                            .foregroundColor(on ? DDColor.red : DDColor.sub.opacity(0.45))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.name).font(pf(14.5)).foregroundColor(DDColor.ink)
                            Text((m.note ?? "") + (m.freeMin > 0 ? ("　满 ¥" + moneyFmt(m.freeMin) + " 免运费") : ""))
                                .font(pf(11.5)).foregroundColor(DDColor.sub).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        let fee = (m.freeMin > 0 && goods >= m.freeMin) ? 0 : m.fee
                        Text(fee <= 0 ? Tr("免运费") : ("¥" + moneyFmt(fee)))
                            .font(pf(13.5, .medium))
                            .foregroundColor(fee <= 0 ? C.green : DDColor.red)
                    }
                    .padding(.horizontal, 14).frame(height: 54)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                HairLine(inset: 14)
            }
        }
    }
}

struct DDPayWayList: View {
    @Binding var payWay: String

    var onAddCard: (() -> Void)? = nil
    @ObservedObject private var store = DDStore.shared

    private var ways: [String] {
        var out: [String] = [XYPay.name]

        if AliPay.on { out.append(AliPay.name) }
        out.append(store.bankPayText)
        return out
    }

    private func tap(_ w: String) {
        if w == store.bankPayText && store.banks.isEmpty {
            onAddCard?()
            return
        }
        payWay = w
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(Tr("支付方式")).font(pf(14)).foregroundColor(DDColor.ink)
                Spacer(minLength: 0)
                Text(Tr("点一下选中")).font(pf(12)).foregroundColor(DDColor.sub)
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            HairLine(inset: 14)
            ForEach(ways.indices, id: \.self) { i in
                let w = ways[i]
                let on = (payWay == w)
                Button { tap(w) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: w == AliPay.name ? "a.circle.fill"
                                          : (w == XYPay.name ? "wallet.pass.fill" : "creditcard.fill"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(w == AliPay.name ? Color(hex: 0x1677FF)
                                             : (w == XYPay.name ? DDColor.red : Color(hex: 0x2E6BFF)))
                            .frame(width: 22)
                        Text(w).font(pf(14.5)).foregroundColor(DDColor.ink)
                        Spacer(minLength: 0)
                        if w == store.bankPayText && store.banks.isEmpty {
                            Text(Tr("去绑卡")).font(pf(12)).foregroundColor(C.link)
                        }
                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18))
                            .foregroundColor(on ? DDColor.red : DDColor.sub.opacity(0.45))
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if i < ways.count - 1 { HairLine(inset: 14) }
            }
        }
    }
}
