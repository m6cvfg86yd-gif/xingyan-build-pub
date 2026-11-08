import SwiftUI
import UserNotifications
import Foundation

private struct WeatherForecastResponse: Decodable {
    struct Hourly: Decodable {
        var time: [String]?
        var temperature2m: [Double]?
        var weatherCode: [Int]?
        var precipitationProbability: [Int]?

        enum CodingKeys: String, CodingKey {
            case time
            case temperature2m = "temperature_2m"
            case weatherCode = "weather_code"
            case precipitationProbability = "precipitation_probability"
        }
    }

    struct Daily: Decodable {
        var time: [String]?
        var weatherCode: [Int]?
        var temperature2mMax: [Double]?
        var temperature2mMin: [Double]?
        var precipitationProbabilityMax: [Int]?

        enum CodingKeys: String, CodingKey {
            case time
            case weatherCode = "weather_code"
            case temperature2mMax = "temperature_2m_max"
            case temperature2mMin = "temperature_2m_min"
            case precipitationProbabilityMax = "precipitation_probability_max"
        }
    }

    var hourly: Hourly?
    var daily: Daily?
}

private struct OfficialNoticeArticle: Identifiable {
    let id: Int
    let symbol: String
    let title: String
    let summary: String
    let body: String
    let tint: Color
}

struct OfficialNoticeCenterView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var latest: NoticeInfo?
    @State private var loading = true

    private let articles: [OfficialNoticeArticle] = [
        .init(id: 1, symbol: "number.square.fill", title: "验证码绝不转发",
              summary: "任何人索要验证码，都应当立即停止沟通。",
              body: "验证码是账号、支付和找回密码的钥匙。客服、警察、银行和平台工作人员都不会向你索要验证码。收到意外验证码时，先确认是否有人正在尝试登录；不要截图、不要朗读、不要转发给任何人。",
              tint: Color(hex: 0x2F80ED)),
        .init(id: 2, symbol: "person.crop.circle.badge.exclamationmark", title: "假客服退款骗局",
              summary: "退款不需要下载会议软件或共享屏幕。",
              body: "骗子常冒充电商、快递或平台客服，谎称商品有问题需要退款。凡是要求添加私人账号、下载会议软件、打开屏幕共享或先转账验证流水的，都是高风险诈骗。退款只通过原支付渠道或 App 内官方入口处理。",
              tint: Color(hex: 0xE45858)),
        .init(id: 3, symbol: "rectangle.inset.filled.and.person.filled", title: "拒绝屏幕共享与远程控制",
              summary: "共享屏幕会把验证码、余额和聊天内容暴露给对方。",
              body: "正规客服不会要求你共享整个屏幕，也不会让你安装远程控制软件。骗子可能一边指导你操作，一边偷看验证码和支付密码。发现异常时立即停止共享、关闭远程权限，并检查登录设备。",
              tint: Color(hex: 0xB45BC6)),
        .init(id: 4, symbol: "cart.badge.plus", title: "刷单返利与兼职垫付",
              summary: "先给小利，再诱导大额垫付，是典型刷单诈骗。",
              body: "刷单本身违法，声称动动手指就能高额返利的兼职基本都是骗局。前期小额返利只是为了骗取信任，后期会以任务未完成、账户冻结或保证金为由继续要钱。不要垫付、不要充值所谓任务账户。",
              tint: Color(hex: 0xD98A22)),
        .init(id: 5, symbol: "chart.line.uptrend.xyaxis", title: "虚假投资与荐股群",
              summary: "稳定高收益、内部渠道和老师带单都是危险信号。",
              body: "骗子通过社交群、恋爱关系或“投资导师”引导你下载来路不明的 App，并展示伪造收益。任何承诺稳赚不赔、内部认购或要求不断追加资金的投资都要拒绝。不要向陌生个人账户转账。",
              tint: Color(hex: 0x1B9C75)),
        .init(id: 6, symbol: "heart.slash.fill", title: "恋爱杀猪盘",
              summary: "感情快速升温后带你投资，几乎都是骗局。",
              body: "骗子会长时间陪聊、制造亲密关系，然后以共同未来、内部机会或家庭急用为由让你投资、借款或代付。没有见过面、没有实名核验的人提出大额金钱请求时，应立即停止转账并告诉家人朋友。",
              tint: Color(hex: 0xE35C86)),
        .init(id: 7, symbol: "person.2.wave.2.fill", title: "冒充亲友和领导",
              summary: "换号、视频造假、紧急借钱都需要二次核实。",
              body: "骗子可能盗用头像和昵称，伪造领导或亲友的新账号，以开会、急病、转账不方便为由要求借钱。即使收到语音或视频也要通过原有电话号码当面或实时核验，不要只凭聊天记录转账。",
              tint: Color(hex: 0x4D7FE8)),
        .init(id: 8, symbol: "gamecontroller.fill", title: "游戏账号与装备交易",
              summary: "低价代充、绕开平台交易和保证金最危险。",
              body: "游戏交易应通过可信官方平台。骗子常以低价账号、稀有装备或代练为诱饵，要求脱离平台私下转账，随后以解冻费、保证金或验证身份继续索款。不要提供账号密码、短信验证码或支付二维码。",
              tint: Color(hex: 0x7A5CD6)),
        .init(id: 9, symbol: "link.badge.plus", title: "钓鱼链接和陌生安装包",
              summary: "一条链接就可能盗走账号，一个安装包就可能控制手机。",
              body: "不要点击陌生人发来的登录页、退款页、投票链接或安装包。下载 App 只通过系统应用商店或星言官方入口。输入账号密码前先核对域名，系统提示安装未知描述文件或获取设备管理权限时应立即退出。",
              tint: Color(hex: 0xC96A2A)),
        .init(id: 10, symbol: "airplane.departure", title: "境外高薪与出境陷阱",
              summary: "包机票高薪、轻松打字和境外客服可能是诱骗出境。",
              body: "对“包吃住、包机票、月入数万、无经验即可”的境外招聘保持警惕。不要交出护照，不要按陌生人安排前往边境或境外园区。发现同行人员、路线或工作内容异常时，立即联系家人并向当地警方求助。",
              tint: Color(hex: 0x8C5A3C)),
        .init(id: 11, symbol: "yensign.circle.fill", title: "红包与转账返利",
              summary: "先收红包再返利，本质是诱导继续转账。",
              body: "陌生人发送红包、小额转账或所谓福利，通常是为了建立信任并诱导更大的转账。不要参与垫付返利，不要按照对方要求截图余额或支付页面，更不要向陌生账户转回更多钱。",
              tint: Color(hex: 0xE84B4B)),
        .init(id: 12, symbol: "shippingbox.fill", title: "快递理赔与件损骗局",
              summary: "主动联系理赔并要求屏幕共享的，多数是假客服。",
              body: "骗子掌握部分订单信息后冒充快递客服，以丢件、损坏或理赔为由引导你操作借贷、共享屏幕或转账。先通过购物 App 内物流页面核实，不要使用对方发来的理赔链接。",
              tint: Color(hex: 0xC77A2B)),
        .init(id: 13, symbol: "ticket.fill", title: "演唱会与票务转让",
              summary: "内部票、低价票和私下转账最容易钱票两空。",
              body: "购票和转票应使用可信平台。对方要求绕开平台、先付定金、发送所谓抢票软件或提供虚假订单截图的，应立即停止交易。不要向陌生二维码付款，也不要共享票务账号。",
              tint: Color(hex: 0x9A5BE0)),
        .init(id: 14, symbol: "graduationcap.fill", title: "校园贷与注销校园贷",
              summary: "要求注销额度、清空账户记录的说法都是骗局。",
              body: "平台不会要求用户转账来注销校园贷或清空征信。凡是声称不注销会影响毕业、征信或工作的，都是制造恐惧。不要下载陌生借贷 App，不要向任何人发送学信网验证码。",
              tint: Color(hex: 0x4A82E6)),
        .init(id: 15, symbol: "building.columns.fill", title: "冒充公检法",
              summary: "真正办案不会通过聊天软件要求转账或共享屏幕。",
              body: "骗子会伪造通缉令、警官证和办案视频，要求你保密并转入所谓安全账户。公检法不会通过聊天软件办案，也不存在安全账户。接到此类要求立即挂断，并通过官方电话核实。",
              tint: Color(hex: 0x3C5878)),
        .init(id: 16, symbol: "bag.badge.plus", title: "二手交易与保证金",
              summary: "未收到平台页面确认前，不要缴纳任何保证金。",
              body: "骗子常在二手交易中伪造付款失败、账户冻结或客服介入页面，要求卖家缴纳保证金。所有付款和退款都应回到官方 App 内查看，不要点击对方提供的客服链接或扫描陌生二维码。",
              tint: Color(hex: 0x2A9B88)),
        .init(id: 17, symbol: "gift.fill", title: "免费皮肤与代充陷阱",
              summary: "免费领皮肤往往以账号密码或验证码为目标。",
              body: "不要登录陌生人提供的领取网站，不要提供游戏账号、短信验证码或支付密码。所谓低价代充、内部折扣和扫码领皮肤可能盗号或造成银行卡扣款。充值只走官方渠道。",
              tint: Color(hex: 0x9A62D8)),
        .init(id: 18, symbol: "qrcode", title: "付款码和收款码要分清",
              summary: "任何人索要付款码数字时，都可能是正在盗刷。",
              body: "付款码用于扣你的钱，收款码才是收钱。不要向陌生人展示付款码、条形码数字或验证码，也不要把收款码交给别人“代收”。每次收款前核对金额和付款对象。",
              tint: Color(hex: 0x248F69)),
        .init(id: 19, symbol: "person.badge.key.fill", title: "账号租借与代实名",
              summary: "出租账号可能被用于诈骗，并牵连实名本人。",
              body: "不要出租、出售或转借账号，也不要帮陌生人实名认证。对方可能使用账号实施诈骗、洗钱或发布违法内容，实名用户需要承担相应风险。发现账号异常立即修改密码并退出陌生设备。",
              tint: Color(hex: 0xD4603A)),
        .init(id: 20, symbol: "megaphone.fill", title: "群里的“官方通知”",
              summary: "群公告和官方号名称都可以被伪造，不要只看头像。",
              body: "群管理员、头像和昵称都可能被冒充。涉及缴费、下载、登录或转账的通知，应从 App 内官方入口或已认证账号再次核对，不要依据群内截图直接操作。",
              tint: Color(hex: 0x7C6A35))
    ]

    private var activeArticles: [OfficialNoticeArticle] {
        let cycle = Int(Date().timeIntervalSince1970 / (3 * 86_400))
        let batch = ((cycle % 2) + 2) % 2
        let start = batch * 10
        return Array(articles[start..<min(start + 10, articles.count)])
    }

    var body: some View {
        List {
            Section {
                accountHeader
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                if loading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .frame(height: 72)
                } else if let latest {
                    platformMessage(latest)
                } else {
                    Text(Tr("暂无新公告"))
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(Tr("今天"))
            }

            Section {
                ForEach(activeArticles.prefix(3)) { article in
                    NavigationLink {
                        OfficialNoticeArticleView(article: article)
                    } label: {
                        articleRow(article)
                    }
                }
            } header: {
                Text(Tr("本次推送"))
            }

            Section {
                ForEach(activeArticles.dropFirst(3)) { article in
                    NavigationLink {
                        OfficialNoticeArticleView(article: article)
                    } label: {
                        articleRow(article)
                    }
                }
            } header: {
                Text(Tr("历史消息"))
            }

            Section {
                NavigationLink {
                    SecurityAcademyView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(OrbitTheme.jade)
                            .frame(width: 34, height: 34)
                            .background(OrbitTheme.jade.opacity(0.10),
                                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(Tr("安全学堂"))
                                .font(.headline)
                            Text(Tr("反诈、账号、隐私与支付安全"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 3)
                }
            } header: {
                Text(Tr("服务"))
            } footer: {
                Text(Tr("每 3 天自动更换一批，旧内容到期自动下架"))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Tr("官方公告"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .hidesTabBar()
        .task {
            let pair = await API.shared.versionInfo()
            latest = pair.notice
            loading = false
        }
    }

    private var accountHeader: some View {
        let name = UIConfig.text("officialRowName", "").trimmingCharacters(in: .whitespacesAndNewlines)
        let avatar = UIConfig.text("officialRowAvatar", "").trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = name.isEmpty ? Tr("官方公告") : name
        return HStack(spacing: 13) {
            if avatar.isEmpty {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: 0x25B779), Color(hex: 0x0E6041)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Circle()
                    )
            } else {
                Avatar(path: avatar, size: 56, radius: 28, circle: true)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text(displayName)
                        .font(.headline)
                    OfficialVerifiedV(size: 15)
                }
                Text(Tr("平台公告、安全学堂与反诈提醒"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    private func platformMessage(_ notice: NoticeInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(notice.title?.isEmpty == false ? notice.title! : Tr("平台公告"))
                .font(.headline)
                .foregroundStyle(.primary)
            Text(notice.content ?? "")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 5) {
                Image(systemName: "checkmark.seal.fill")
                Text(Tr("官方公告"))
                Spacer(minLength: 0)
                Text(Tr("平台通知"))
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 5)
    }

    private func articleRow(_ article: OfficialNoticeArticle) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(Tr(article.title))
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(Tr(article.summary))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.seal.fill")
                    Text(Tr("星言官方"))
                    Text("·")
                    Text(Tr("反诈课堂"))
                    Text("·")
                    Text("\(320 + article.id * 137) " + Tr("阅读"))
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
            Image(systemName: article.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(article.tint)
                .frame(width: 42, height: 42)
                .background(article.tint.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .padding(.vertical, 5)
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color(hex: 0x0B2F25), Color(hex: 0x176D50), Color(hex: 0x28B67C)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(.white.opacity(0.09))
                .frame(width: 210, height: 210)
                .offset(x: 210, y: -70)
            VStack(alignment: .leading, spacing: 9) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                Text(Tr("星言官方公告"))
                    .font(pfStyled(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(Tr("只发布平台公告、服务状态与重要安全提醒"))
                    .font(pfStyled(size: 13.5))
                    .foregroundStyle(.white.opacity(0.74))
            }
            .padding(20)
        }
        .frame(height: 168)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 0.7)
        }
    }

    private func latestCard(_ notice: NoticeInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(Tr("最新公告"))
                    .font(pfStyled(size: 12, weight: .semibold))
                    .foregroundStyle(OrbitTheme.jade)
                Spacer(minLength: 0)
                Circle().fill(OrbitTheme.jade).frame(width: 6, height: 6)
            }
            Text(notice.title?.isEmpty == false ? notice.title! : Tr("平台公告"))
                .font(pfStyled(size: 18, weight: .semibold))
                .foregroundStyle(OrbitTheme.ink)
            Text(notice.content ?? "")
                .font(pfStyled(size: 14))
                .foregroundStyle(OrbitTheme.secondary)
                .lineSpacing(3)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(OrbitTheme.divider, lineWidth: 0.6)
        }
    }

    private func noticeCard(_ symbol: String, _ title: String, _ text: String, _ tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(Tr(title))
                    .font(pfStyled(size: 15.5, weight: .semibold))
                    .foregroundStyle(OrbitTheme.ink)
                Text(Tr(text))
                    .font(pfStyled(size: 13))
                    .foregroundStyle(OrbitTheme.secondary)
                    .lineSpacing(2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(OrbitTheme.divider, lineWidth: 0.6)
        }
    }
}

private struct WeatherMotionIcon: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 22
    var halo: CGFloat = 30

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var active = false

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.13))
                .frame(width: halo, height: halo)
                .scaleEffect(active ? 1.12 : 0.90)
                .opacity(active ? 0.70 : 0.30)

            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .offset(y: active ? -1.6 : 1.6)
                .rotationEffect(.degrees(active ? 2.8 : -2.8))
        }
        .frame(width: max(halo, size + 10), height: max(halo, size + 10))
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                active = true
            }
        }
    }
}

private struct WeatherAnimatedBackdrop: View {
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drifting = false

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)

            LinearGradient(
                colors: [tint.opacity(0.22), tint.opacity(0.05), .clear],
                startPoint: .top,
                endPoint: .bottom
            )

            Circle()
                .fill(tint.opacity(0.16))
                .frame(width: 330, height: 330)
                .blur(radius: 34)
                .offset(x: drifting ? -86 : 78, y: drifting ? -96 : -48)

            Circle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 230, height: 230)
                .blur(radius: 42)
                .offset(x: drifting ? 110 : -72, y: drifting ? -18 : 48)

            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.18)
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 6.4).repeatForever(autoreverses: true)) {
                drifting = true
            }
        }
    }
}

private struct WeatherRainImpactOverlay: View {
    let active: Bool
    let seed: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if active && !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
                Canvas { context, size in
                    guard size.width > 20 else { return }
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    for index in 0..<5 {
                        let indexValue = Double(index)
                        let raw = sin((indexValue + seed * 17) * 12.9898) * 43758.5453
                        let fraction = abs(raw.truncatingRemainder(dividingBy: 1))
                        let x = 8 + CGFloat(fraction) * max(1, size.width - 16)
                        let cycle = 1.8 + Double(index % 3) * 0.42
                        let phase = (time / cycle + seed + indexValue * 0.19)
                            .truncatingRemainder(dividingBy: 1)

                        if phase < 0.24 {
                            let fall = phase / 0.24
                            let drop = CGRect(
                                x: x - 0.9,
                                y: -4 + fall * 8,
                                width: 1.8,
                                height: 4.5
                            )
                            context.fill(
                                Path(ellipseIn: drop),
                                with: .color(Color.white.opacity(0.88))
                            )
                        } else if phase < 0.50 {
                            let splash = (phase - 0.24) / 0.26
                            let alpha = 1 - splash
                            let spread = CGFloat(2.5 + splash * 4.5)
                            for direction in [-1.0, 0.0, 1.0] {
                                var path = Path()
                                path.move(to: CGPoint(x: x, y: 4))
                                path.addQuadCurve(
                                    to: CGPoint(
                                        x: x + CGFloat(direction) * spread,
                                        y: 4 - CGFloat(direction == 0 ? 4.8 : 3.4)
                                    ),
                                    control: CGPoint(
                                        x: x + CGFloat(direction) * spread * 0.55,
                                        y: 0.5 - splash * 1.2
                                    )
                                )
                                context.stroke(
                                    path,
                                    with: .color(Color.white.opacity(alpha * 0.72)),
                                    style: StrokeStyle(lineWidth: 0.8, lineCap: .round)
                                )
                            }
                            let ripple = CGRect(
                                x: x - spread,
                                y: 2.8,
                                width: spread * 2,
                                height: 2.4
                            )
                            context.stroke(
                                Path(ellipseIn: ripple),
                                with: .color(Color.white.opacity(alpha * 0.34)),
                                lineWidth: 0.55
                            )
                        }
                    }
                }
            }
            .frame(height: 19)
            .allowsHitTesting(false)
        }
    }
}

private extension View {
    func weatherRainImpacts(_ active: Bool, seed: Double) -> some View {
        overlay(alignment: .top) {
            WeatherRainImpactOverlay(active: active, seed: seed)
        }
    }
}

struct WeatherOfficialView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var weather = MallWeather.shared
    @ObservedObject private var city = DDCity.shared

    let name: String
    let subtitle: String
    let avatar: String

    @State private var showCityPicker = false
    @State private var forecast: WeatherForecastResponse?
    @State private var forecastLoading = false
    @State private var appeared = false
    @AppStorage("weatherFahrenheit") private var fahrenheit = false

    private var look: MallWeatherLook {
        MallWeatherLook.current(weather)
    }

    private var displayTemp: String {
        let value = fahrenheit ? weather.temp * 9 / 5 + 32 : weather.temp
        return weather.failed ? "—" : "\(Int(value.rounded()))°"
    }

    private var advice: (symbol: String, title: String, text: String) {
        if weather.failed {
            return ("wifi.exclamationmark", Tr("天气暂时拿不到"), Tr("检查网络后再试一次"))
        }
        if look.isThunder {
            return ("cloud.bolt.rain.fill", Tr("雷雨提醒"), Tr("尽量减少户外活动，远离高处和空旷区域"))
        }
        if look.isRain || look.isDrizzle {
            return ("umbrella.fill", Tr("出门带伞"), Tr("路面湿滑，通勤和骑行注意安全"))
        }
        if look.isSnow {
            return ("snowflake", Tr("防寒防滑"), Tr("注意保暖，步行和驾驶都要放慢速度"))
        }
        if look.isFog {
            return ("cloud.fog.fill", Tr("能见度较低"), Tr("驾车打开雾灯，并与前车保持距离"))
        }
        if weather.temp >= 30 {
            return ("sun.max.fill", Tr("注意防晒补水"), Tr("午间减少暴晒，及时补充水分"))
        }
        if weather.temp <= 5 {
            return ("thermometer.snowflake", Tr("天气偏冷"), Tr("外出注意保暖，早晚温差可能较大"))
        }
        if look.isClear {
            return ("sun.max.fill", Tr("适合出行"), Tr("天气不错，注意防晒和及时补水"))
        }
        return ("cloud.sun.fill", Tr("天气平稳"), Tr("出门前再确认一次实时天气"))
    }

    var body: some View {
        let current = look
        ZStack {
            nativeWeatherBackdrop(current)

            VStack(spacing: 0) {
                NavBar(title: Tr("天气账号"), back: { dismiss() }) {
                    Button {
                        showCityPicker = true
                    } label: {
                        Image(systemName: "location")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 38, height: 38)
                            .background(.thinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        accountHeader(current)
                        temperatureHero(current)
                        metricRow(current)
                        if let forecast {
                            hourlyForecast(forecast, current)
                            dailyForecast(forecast, current)
                        } else if forecastLoading {
                            ProgressView(Tr("正在加载预报…"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 12)
                        }
                        adviceCard(current)
                        Color.clear.frame(height: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 9)
                    .animation(.easeOut(duration: 0.42), value: appeared)
                }
                .refreshable {
                    MallWeather.shared.refresh(force: true)
                    try? await Task.sleep(nanoseconds: 650_000_000)
                    await loadForecast()
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .hidesTabBar()
        .onAppear {
            MallWeather.shared.refresh()
            appeared = true
        }
        .task(id: "\(city.lat),\(city.lon),\(city.name)") {
            await loadForecast()
        }
        .sheet(isPresented: $showCityPicker) {
            DDCityPickerView()
        }
    }

    private func nativeWeatherBackdrop(_ current: MallWeatherLook) -> some View {
        let tint: Color
        switch current.phase {
        case .dawn: tint = Color(hex: 0xFF8A5C)
        case .day: tint = Color(hex: 0x4FA8F5)
        case .dusk: tint = Color(hex: 0xFF9B5C)
        case .night: tint = Color(hex: 0x41548F)
        }
        return ZStack {
            MallSkyBackground(look: current)
            LinearGradient(
                stops: [
                    .init(color: tint.opacity(scheme == .dark ? 0.24 : 0.14), location: 0),
                    .init(color: .clear, location: 0.24),
                    .init(color: .clear, location: 0.68),
                    .init(color: Color.black.opacity(scheme == .dark ? 0.22 : 0.07),
                          location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.9), value: current.cond)
    }

    private func accountHeader(_ current: MallWeatherLook) -> some View {
        HStack(spacing: 12) {
            if avatar.isEmpty {
                Image(systemName: "cloud.sun.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color(hex: 0xFFD35C))
                    .frame(width: 50, height: 50)
                    .background(
                        LinearGradient(colors: [Color(hex: 0x4C9DFF), Color(hex: 0x1558B8)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Circle()
                    )
            } else {
                Avatar(path: avatar, size: 50, radius: 25, circle: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(name)
                        .font(.headline)
                    OfficialVerifiedV(size: 15)
                }
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.primary)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.7)
        }
        .weatherRainImpacts(current.isWet, seed: 0.11)
    }

    private func temperatureHero(_ current: MallWeatherLook) -> some View {
        VStack(spacing: 4) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) { fahrenheit.toggle() }
            } label: {
                Text(displayTemp)
                    .font(.system(size: 94, weight: .ultraLight, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(current.ink)
                    .shadow(
                        color: current.darkInk
                            ? Color.white.opacity(0.24)
                            : Color.black.opacity(0.24),
                        radius: 2.2,
                        x: 0,
                        y: 1
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(fahrenheit ? Tr("华氏温度") : Tr("摄氏温度"))

            HStack(spacing: 7) {
                WeatherMotionIcon(symbol: current.icon,
                                  tint: current.accent,
                                  size: 21,
                                  halo: 28)
                Text(weather.failed ? Tr("天气暂时拿不到") : current.conditionName)
                Text("·")
                Text(city.display)
            }
            .font(.headline)
            .foregroundStyle(current.ink)

            Text(Date.now, format: .dateTime.month(.wide).day().weekday(.wide))
                .font(.subheadline)
                .foregroundStyle(current.inkSoft)

            Text(weather.failed ? Tr("下拉刷新") : current.dayPartName + " · " + Tr("实时天气"))
                .font(.subheadline)
                .foregroundStyle(current.inkSoft)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }

    private func metricRow(_ current: MallWeatherLook) -> some View {
        HStack(spacing: 10) {
            metric("cloud.fill", Tr("云量"), "\(weather.cloud)%", current)
            metric("wind", Tr("风速"), String(format: "%.1f km/h", weather.wind), current)
            metric("clock.fill", Tr("更新"),
                   weather.updatedAt.map { timeText($0) } ?? "—", current)
        }
        .weatherRainImpacts(current.isWet, seed: 0.29)
    }

    private func metric(_ symbol: String, _ title: String,
                        _ value: String, _ current: MallWeatherLook) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(current.accent)
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.primary)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.6)
        }
    }

    private func adviceCard(_ current: MallWeatherLook) -> some View {
        let info = advice
        return HStack(spacing: 13) {
            Image(systemName: info.symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(current.accent)
                .frame(width: 44, height: 44)
                .background(.thinMaterial,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(info.title)
                    .font(.headline)
                Text(info.text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.primary)
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.7)
        }
        .weatherRainImpacts(current.isWet, seed: 0.81)
    }

    private func hourlyForecast(_ data: WeatherForecastResponse,
                                _ current: MallWeatherLook) -> some View {
        let items = hourlyItems(data)
        return VStack(alignment: .leading, spacing: 12) {
            Label(Tr("逐小时预报"), systemImage: "clock")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        VStack(spacing: 9) {
                            Text(item.time)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Image(systemName: weatherIcon(item.code, isDay: true))
                                .font(.system(size: 22, weight: .medium))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.primary)
                            Text(forecastTemp(item.temp))
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                            if item.precip > 0 {
                                Text("\(item.precip)%")
                                    .font(.caption2)
                                    .foregroundStyle(Color(hex: 0x3A8DFF))
                            }
                        }
                        .frame(width: 48)
                    }
                }
            }
        }
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.7)
        }
        .foregroundStyle(.primary)
        .weatherRainImpacts(current.isWet, seed: 0.43)
    }

    private func dailyForecast(_ data: WeatherForecastResponse,
                               _ current: MallWeatherLook) -> some View {
        let items = dailyItems(data)
        return VStack(alignment: .leading, spacing: 0) {
            Label(Tr("未来 7 天"), systemImage: "calendar")
                .font(.headline)
                .padding(.bottom, 10)
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Divider().opacity(0.55)
                }
                HStack(spacing: 10) {
                    Text(item.day)
                        .font(.body.weight(index == 0 ? .semibold : .regular))
                        .frame(width: 66, alignment: .leading)
                    Image(systemName: weatherIcon(item.code, isDay: true))
                        .font(.system(size: 20, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 30)
                    if item.precip > 0 {
                        Text("\(item.precip)%")
                            .font(.caption)
                            .foregroundStyle(Color(hex: 0x3A8DFF))
                            .frame(width: 38, alignment: .leading)
                    } else {
                        Color.clear.frame(width: 38, height: 1)
                    }
                    Spacer(minLength: 4)
                    Text(forecastTemp(item.low))
                        .foregroundStyle(.secondary)
                    Text(forecastTemp(item.high))
                        .fontWeight(.semibold)
                }
                .frame(height: 43)
            }
        }
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.7)
        }
        .foregroundStyle(.primary)
        .weatherRainImpacts(current.isWet, seed: 0.67)
    }

    private func loadForecast() async {
        guard city.lat != 0, city.lon != 0 else { return }
        forecastLoading = true
        defer { forecastLoading = false }
        guard let url = URL(string:
            "https://api.open-meteo.com/v1/forecast?latitude=\(city.lat)&longitude=\(city.lon)" +
            "&hourly=temperature_2m,weather_code,precipitation_probability" +
            "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max" +
            "&timezone=auto&forecast_days=7") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(WeatherForecastResponse.self, from: data) else {
            return
        }
        forecast = decoded
    }

    private func hourlyItems(_ data: WeatherForecastResponse)
        -> [(time: String, temp: Double, code: Int, precip: Int)] {
        guard let times = data.hourly?.time,
              let temps = data.hourly?.temperature2m,
              let codes = data.hourly?.weatherCode,
              let precips = data.hourly?.precipitationProbability else { return [] }
        let hourFormatter = DateFormatter()
        hourFormatter.locale = Locale(identifier: "en_US_POSIX")
        hourFormatter.dateFormat = "yyyy-MM-dd'T'HH:00"
        let now = hourFormatter.string(from: Date())
        var start = times.firstIndex(where: { $0 >= now }) ?? 0
        if start >= times.count { start = 0 }
        let count = min(min(times.count, temps.count), min(codes.count, precips.count))
        guard count > start else { return [] }
        return (start..<min(count, start + 12)).map { index in
            let label = String(times[index].suffix(5))
            return (label, temps[index], codes[index], precips[index])
        }
    }

    private func dailyItems(_ data: WeatherForecastResponse)
        -> [(day: String, high: Double, low: Double, code: Int, precip: Int)] {
        guard let times = data.daily?.time,
              let codes = data.daily?.weatherCode,
              let highs = data.daily?.temperature2mMax,
              let lows = data.daily?.temperature2mMin,
              let precips = data.daily?.precipitationProbabilityMax else { return [] }
        let count = min(min(times.count, codes.count),
                        min(highs.count, min(lows.count, precips.count)))
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        return (0..<count).map { index in
            let date = parser.date(from: times[index])
            let label: String
            if index == 0 {
                label = Tr("今天")
            } else {
                label = date?.formatted(.dateTime.weekday(.abbreviated)) ?? times[index]
            }
            return (label, highs[index], lows[index], codes[index], precips[index])
        }
    }

    private func forecastTemp(_ value: Double) -> String {
        let shown = fahrenheit ? value * 9 / 5 + 32 : value
        return "\(Int(shown.rounded()))°"
    }

    private func weatherIcon(_ code: Int, isDay: Bool) -> String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    private func timeText(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

private struct SecurityLessonDetailView: View {
    let lesson: SecurityLesson

    var body: some View {
        List {
            Section {
                HStack(spacing: 13) {
                    Image(systemName: lesson.symbol)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(lesson.tint)
                        .frame(width: 46, height: 46)
                        .background(lesson.tint.opacity(0.10),
                                    in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Tr(lesson.title))
                            .font(.headline)
                        Text(Tr(lesson.summary))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                ForEach(Array(lesson.points.enumerated()), id: \.offset) { index, point in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.bold())
                            .foregroundStyle(lesson.tint)
                            .frame(width: 22, height: 22)
                            .background(lesson.tint.opacity(0.10), in: Circle())
                        Text(Tr(point))
                            .font(.body)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text(Tr("处理步骤"))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Tr("安全课程"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .hidesTabBar()
    }
}

enum SecurityAcademyNotifier {
    private static let requestId = "security-academy-reminder"
    private static let copies: [(String, String)] = [
        ("验证码绝不转发", "验证码是账号钥匙，任何人索要都应立即拒绝。"),
        ("警惕假客服退款", "退款不需要共享屏幕、下载会议软件或先转账。"),
        ("拒绝屏幕共享", "共享屏幕可能暴露验证码、余额和聊天内容。"),
        ("刷单返利是骗局", "先给小利再要求大额垫付，应立即停止。"),
        ("谨防虚假投资", "稳定高收益、内部渠道和老师带单都是危险信号。"),
        ("恋爱转账先核实", "感情升温后带你投资或借款，要保持警惕。"),
        ("亲友借钱二次确认", "换号、急事和视频造假都可能用来骗钱。"),
        ("游戏交易走官方", "低价代充、保证金和绕开平台交易风险最高。"),
        ("陌生链接不要点", "登录页、退款页和安装包可能是钓鱼陷阱。"),
        ("境外高薪要当心", "包机票高薪和无经验高收入可能诱骗出境。")
    ]

    static func scheduleIfNeeded() {
        guard LocalNotify.settings.on else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                scheduleNext(center)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    if granted { scheduleNext(center) }
                }
            default:
                break
            }
        }
    }

    private static func scheduleNext(_ center: UNUserNotificationCenter) {
        center.getPendingNotificationRequests { pending in
            guard !pending.contains(where: { $0.identifier == requestId }) else { return }

            let now = Date()
            let cal = Calendar.current
            let epochDay = Int(now.timeIntervalSince1970 / 86_400)
            let delayDays = 3 + abs(epochDay) % 5
            guard let day = cal.date(byAdding: .day, value: delayDays, to: now) else { return }
            var parts = cal.dateComponents([.year, .month, .day], from: day)
            parts.hour = 9 + abs(epochDay) % 2
            parts.minute = (abs(epochDay * 7) % 6) * 10

            let copy = copies[abs(epochDay) % copies.count]
            let content = UNMutableNotificationContent()
            content.title = Tr("安全学院") + " · " + Tr(copy.0)
            content.body = Tr(copy.1)
            content.sound = .default
            content.threadIdentifier = "xingyan-security-academy"
            content.userInfo = ["kind": "securityAcademy"]
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            center.add(UNNotificationRequest(identifier: requestId,
                                             content: content,
                                             trigger: trigger),
                       withCompletionHandler: nil)
        }
    }
}

private struct OfficialNoticeArticleView: View {
    let article: OfficialNoticeArticle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: article.symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(article.tint)
                    .frame(width: 52, height: 52)
                    .background(article.tint.opacity(0.10),
                                in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                Text(Tr(article.title))
                    .font(.title2.bold())
                Text(Tr(article.summary))
                    .font(.headline)
                    .foregroundStyle(article.tint)
                Text(Tr(article.body))
                    .font(.body)
                    .lineSpacing(5)
                Divider()
                Text(Tr("遇到可疑情况，请停止转账与共享屏幕，并通过 App 内安全中心核实。"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(Tr("反诈文章"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .hidesTabBar()
    }
}

private struct SecurityLesson: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let summary: String
    let points: [String]
    let tint: Color
}

struct SecurityAcademyView: View {
    @Environment(\.dismiss) private var dismiss

    private let quickRules = [
        "凡是索要验证码、支付密码或登录二维码的，立即拒绝。",
        "凡是要求共享屏幕、安装远程控制软件的，立即退出。",
        "凡是要你转入“安全账户”或先交保证金的，都是诈骗。",
        "凡是小额返利后要求继续垫付的，立刻停止。",
        "凡是陌生链接、安装包或要求关闭安全保护的，不要点击。"
    ]

    private let lessons: [SecurityLesson] = [
        SecurityLesson(
            id: "code",
            symbol: "number.square.fill",
            title: "验证码不转发",
            summary: "验证码等于账号钥匙，任何人索要都不能给。",
            points: [
                "客服不会索要验证码、支付密码或登录二维码",
                "收到陌生验证码先检查是否有人正在登录你的账号",
                "发现异常立即修改密码并检查登录设备"
            ],
            tint: Color(hex: 0x2F80ED)
        ),
        SecurityLesson(
            id: "screen",
            symbol: "rectangle.inset.filled.and.person.filled",
            title: "拒绝屏幕共享",
            summary: "共享屏幕可能暴露验证码、余额和聊天内容。",
            points: [
                "退款、解封、注销账号不需要屏幕共享",
                "不要把远程控制权限交给陌生人",
                "发现共享后立刻停止并关闭相关权限"
            ],
            tint: Color(hex: 0xE45858)
        ),
        SecurityLesson(
            id: "fake",
            symbol: "person.crop.circle.badge.exclamationmark",
            title: "识别假客服",
            summary: "官方通知只会在认证官方号内出现。",
            points: [
                "核对官方认证标识和账号资料",
                "不点击陌生人发来的安装包或网页",
                "通过 App 内安全中心重新进入官方页面"
            ],
            tint: Color(hex: 0xD98A22)
        ),
        SecurityLesson(
            id: "money",
            symbol: "banknote.fill",
            title: "警惕投资与恋爱诈骗",
            summary: "稳定高收益、内部渠道和先转账再返利都是高风险信号。",
            points: [
                "不要向未实名见过面的人大额转账",
                "不要相信截图收益和代操作账户",
                "转账前先与家人或朋友核实"
            ],
            tint: Color(hex: 0x8B5CD6)
        ),
        SecurityLesson(
            id: "privacy",
            symbol: "hand.raised.square.fill",
            title: "检查隐私权限",
            summary: "只打开当前功能真正需要的系统权限。",
            points: [
                "定期查看定位、麦克风、相机和通讯录权限",
                "群聊和陌生人不要发送家庭住址与证件照片",
                "重要账号启用登录保护和安全提醒"
            ],
            tint: Color(hex: 0x1B9C75)
        )
    ]

    var body: some View {
        List {
            Section {
                hero
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                ForEach(Array(quickRules.enumerated()), id: \.offset) { index, rule in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x2A9B6F))
                            .padding(.top, 1)
                        Text(Tr(rule))
                            .font(.body)
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(index + 1). " + Tr(rule))
                }
            } header: {
                Text(Tr("五个凡是"))
            } footer: {
                Text(Tr("先停一下，再通过官方入口核实；无法确认时不要转账。"))
            }

            Section {
                ForEach(lessons) { lesson in
                    NavigationLink {
                        SecurityLessonDetailView(lesson: lesson)
                    } label: {
                        lessonRow(lesson)
                    }
                }
            } header: {
                Text(Tr("安全课程"))
            } footer: {
                Text(Tr("遇到可疑情况，请停止转账与共享屏幕，并通过 App 内安全中心核实。"))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Tr("安全学院"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .hidesTabBar()
    }

    private var hero: some View {
        HStack(spacing: 16) {
            Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(.white.opacity(0.11),
                            in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(Tr("先停一下，再核实"))
                    .font(pfStyled(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(Tr("学会识别诈骗，保护账号、资金和隐私"))
                    .font(pfStyled(size: 13))
                    .foregroundStyle(.white.opacity(0.72))
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background {
            LinearGradient(
                colors: [Color(hex: 0x102D24), Color(hex: 0x1D6F54)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 0.7)
        }
    }

    private func lessonRow(_ lesson: SecurityLesson) -> some View {
        HStack(spacing: 12) {
            Image(systemName: lesson.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(lesson.tint)
                .frame(width: 34, height: 34)
                .background(lesson.tint.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(Tr(lesson.title))
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(Tr(lesson.summary))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private func lessonSheet(_ lesson: SecurityLesson) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: lesson.symbol)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(lesson.tint)
                        .frame(width: 52, height: 52)
                        .background(lesson.tint.opacity(0.10),
                                    in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Tr(lesson.title))
                            .font(pfStyled(size: 22, weight: .bold, design: .rounded))
                        Text(Tr(lesson.summary))
                            .font(pfStyled(size: 13))
                            .foregroundStyle(OrbitTheme.secondary)
                    }
                }
                ForEach(Array(lesson.points.enumerated()), id: \.offset) { index, point in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(lesson.tint)
                            .frame(width: 24, height: 24)
                            .background(lesson.tint.opacity(0.11), in: Circle())
                        Text(Tr(point))
                            .font(pfStyled(size: 14.5))
                            .foregroundStyle(OrbitTheme.ink)
                            .lineSpacing(3)
                    }
                }
            }
            .padding(20)
        }
        .background(OrbitTheme.canvas.ignoresSafeArea())
    }
}
