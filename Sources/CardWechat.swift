import SwiftUI

struct ContactCardWechat: View {
    let name: String
    let wxId: String
    let region: String
    let avatarPath: String
    let isEyes: Bool

    let remarkLine: String

    let permLine: String

    let moreLine: String

    let momentsHint: String
    let thumbs: [String]
    let isBot: Bool

    let relation: String
    let networkProvince: String
    let deviceModel: String

    let onClose: () -> Void
    let onAvatar: () -> Void
    let onMessage: () -> Void
    let onVoice: () -> Void
    let onVideo: () -> Void
    let onAICall: () -> Void
    let onMoments: () -> Void
    let onRemark: () -> Void
    let onPerm: () -> Void
    let onMore: () -> Void
    let onMenu: () -> Void
    let onApply: () -> Void
    let onAgree: () -> Void

    @Environment(\.colorScheme) private var scheme

    @State private var askCall = false

    @State private var appeared = false

    @State private var copied: String? = nil

    private var green: Color { OrbitTheme.jade }
    private var pageBg: Color { OrbitTheme.canvas }
    private var cardBg: Color { scheme == .dark ? Color(hex: 0x101713) : Color(hex: 0xF8FBF8) }
    private var ink: Color { scheme == .dark ? Color(hex: 0xF1F7F3) : Color(hex: 0x15201A) }
    private var gray: Color { scheme == .dark ? Color(hex: 0x91A197) : Color(hex: 0x68766D) }
    private var hair: Color { scheme == .dark ? Color(white: 1, opacity: 0.09) : Color.black.opacity(0.075) }
    private var avatarSize: CGFloat { UIConfig.num("cardWechatAvatar", 64) }
    private var nameSize: CGFloat { UIConfig.num("cardWechatNameSize", 20) }
    private var thumbSize: CGFloat { UIConfig.num("cardWechatThumb", 40) }
    private var rowH: CGFloat { UIConfig.num("cardWechatRowH", 54) }
    private var btnH: CGFloat { UIConfig.num("cardWechatBtnH", 46) }
    private var radius: CGFloat { UIConfig.num("cardWechatRadius", 8) }
    private var cardRadius: CGFloat { max(24, min(32, radius + 18)) }
    private var avatarRadius: CGFloat { max(16, min(24, radius + 10)) }

    var body: some View {
        VStack(spacing: 0) {
            nav
            ScrollView {
                VStack(spacing: 14) {
                    VStack(spacing: 0) {
                        ZStack(alignment: .topTrailing) {
                            cardSurface
                            ContactOrbitMotif(accent: green, ink: gray)
                                .frame(width: 205, height: 155)
                                .offset(x: 22, y: -12)
                                .allowsHitTesting(false)
                            VStack(spacing: 0) {
                                header
                                premiumDivider
                                friendInfoCard
                                premiumDivider
                                momentsRow
                                premiumDivider
                                buttons
                            }
                        }

                        HStack(spacing: 7) {
                            Image(systemName: "point.3.connected.trianglepath.dotted")
                            Text("XINGYAN · CONTACT SIGNAL")
                                .tracking(1.3)
                            Spacer(minLength: 4)
                            Text(relationLabel)
                        }
                        .font(pfStyled(size: 9.5, weight: .semibold))
                        .foregroundColor(gray)
                        .padding(.horizontal, 18)
                        .frame(height: 38)
                        .background(scheme == .dark ? Color(hex: 0x0B110D) : Color(hex: 0xEDF5EF))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                            .stroke(hair, lineWidth: 0.8)
                    }
                    .shadow(color: Color.black.opacity(scheme == .dark ? 0.34 : 0.10),
                            radius: 22, y: 12)

                    Spacer(minLength: 28)
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 6)
            }
        }
        .background(contactBackdrop)
        .onAppear { withAnimation(.easeOut(duration: 0.30)) { appeared = true } }

        .overlay(alignment: .bottom) {
            if let c = copied {
                Text(c)
                    .font(pf(13))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).frame(height: 32)
                    .background(Capsule().fill(Color.black.opacity(0.72)))
                    .padding(.bottom, 64)
                    .transition(.opacity)
            }
        }
        .onChange(of: copied) { v in
            guard v != nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.easeOut(duration: 0.2)) { copied = nil }
            }
        }
        .confirmationDialog(Tr("音视频通话"), isPresented: $askCall, titleVisibility: .visible) {
            Button(Tr("语音通话")) { onVoice() }
            Button(Tr("视频通话")) { onVideo() }
            Button(Tr("取消"), role: .cancel) { }
        }
    }

    private var contactBackdrop: some View {
        ZStack {
            OrbitTheme.canvas
            RadialGradient(colors: [green.opacity(scheme == .dark ? 0.09 : 0.12), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 330)
        }
        .ignoresSafeArea()
    }

    private var cardSurface: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: scheme == .dark
                            ? [Color(hex: 0x13231A), Color(hex: 0x09100C)]
                            : [Color(hex: 0xFCFEFC), Color(hex: 0xEFF7F1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                .fill(
                    RadialGradient(colors: [green.opacity(scheme == .dark ? 0.13 : 0.09), .clear],
                                   center: .topTrailing, startRadius: 0, endRadius: 250)
                )
        }
    }

    private var relationLabel: String {
        switch relation {
        case "self": return Tr("我的名片")
        case "friend": return Tr("星言联系人")
        case "incoming": return Tr("好友申请")
        case "requested": return Tr("申请已发送")
        default: return Tr("待建立联系")
        }
    }

    private func identityChip(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8.5, weight: .semibold))
            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .font(pf(10.5, .medium))
        .foregroundColor(gray)
        .padding(.horizontal, 7)
        .frame(height: 23)
        .background(Capsule().fill(cardBg.opacity(0.78)))
        .overlay(Capsule().stroke(hair, lineWidth: 0.6))
    }

    private var nav: some View {
        NavBar(title: Tr("星言身份"), back: { onClose() }) {
            Button { onMenu() } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17))
                    .foregroundColor(ink)
                    .frame(width: 54, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Tr("更多"))
        }
        .background(Color.clear)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 15) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    ContactIdentityMark(accent: green)
                        .frame(width: 23, height: 23)
                    Text(isBot ? Tr("星言助手") : "XINGYAN · ORBIT ID")
                        .font(pf(10, .semibold))
                        .tracking(1.3)
                }
                .foregroundColor(gray)
                Text(name)
                    .font(pf(max(22, nameSize + 1), .semibold))
                    .foregroundColor(ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                HStack(spacing: 6) {
                    Text(Tr("星言号"))
                        .font(pf(11.5, .medium))
                        .foregroundColor(gray)
                    Text(wxId)
                        .font(pfStyled(size: 12.5, weight: .medium, design: .monospaced))
                        .foregroundColor(ink.opacity(0.78))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .copyOnLongPress(wxId) { msg in
                            withAnimation(.easeOut(duration: 0.15)) { copied = msg }
                        }
                }
                if !region.isEmpty {
                    identityChip(icon: "location", text: region)
                }
                HStack(spacing: 6) {
                    identityChip(icon: "network", text: networkProvince)
                    identityChip(icon: "iphone", text: deviceModel)
                }
            }
            Spacer(minLength: 0)
            ZStack {
                RoundedRectangle(cornerRadius: avatarRadius + 6, style: .continuous)
                    .fill(LinearGradient(colors: [green.opacity(scheme == .dark ? 0.15 : 0.18),
                                                  cardBg],
                                         startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
                Group {
                    if isEyes {
                        JarvisEyesAvatar(size: avatarSize)
                            .frame(width: avatarSize, height: avatarSize)
                    } else {
                        Avatar(path: avatarPath, size: avatarSize, radius: avatarRadius)
                    }
                }
                .padding(4)
            }
            .frame(width: avatarSize + 14, height: avatarSize + 14)
            .overlay(RoundedRectangle(cornerRadius: avatarRadius + 6, style: .continuous)
                .stroke(green.opacity(0.30), lineWidth: 0.8))
            .shadow(color: .black.opacity(scheme == .dark ? 0.34 : 0.10), radius: 10, y: 4)
            .contentShape(Rectangle())
            .onTapGesture { onAvatar() }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
    }

    private var friendInfoCard: some View {
        Button { onRemark() } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(Tr("关系与备注"))
                    .font(pf(15.5, .medium))
                    .foregroundColor(ink)
                Text(Tr("补充备注、电话和标签，并管理联系权限。"))
                    .font(pf(12))
                    .foregroundColor(gray)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func actionRow(_ title: String, _ icon: String,
                           enabled: Bool = true,
                           _ tap: @escaping () -> Void) -> some View {
        Button { tap() } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(enabled ? Color(hex: 0x576B95) : gray)
                    .frame(width: 22)
                Text(title).font(pf(16.5)).foregroundColor(enabled ? ink : gray)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(height: rowH)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var momentsRow: some View {
        Button { onMoments() } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(green.opacity(scheme == .dark ? 0.14 : 0.10))
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(green)
                }
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Tr("朋友圈"))
                        .font(pf(15.5, .medium))
                        .foregroundColor(ink)
                    Text(momentsHint.isEmpty ? Tr("最近动态") : Tr(momentsHint))
                        .font(pf(10.5))
                        .foregroundColor(gray)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if !thumbs.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(thumbs.prefix(3).indices, id: \.self) { i in
                            RemoteImage(path: thumbs[i])
                                .frame(width: thumbSize, height: thumbSize)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                    }
                }
                Chevron(size: 9, line: 1.6)
            }
            .padding(.horizontal, 18)
            .frame(height: max(rowH, 64))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            Button { onMessage() } label: {
                HStack(spacing: 7) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text(Tr("发消息"))
                        .font(pf(15.5, .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: btnH)
                .background(Capsule().fill(green))
                .overlay(Capsule().stroke(Color.white.opacity(0.20), lineWidth: 0.7))
            }
            .buttonStyle(.plain)

            Button { secondTap() } label: {
                HStack(spacing: 7) {
                    Image(systemName: secondIcon)
                        .font(.system(size: 14, weight: .semibold))
                    Text(secondTitle)
                        .font(pf(14.5, .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                }
                .foregroundColor(secondEnabled ? green : gray)
                .frame(maxWidth: .infinity)
                .frame(height: btnH)
                .background(Capsule().fill(C.cardBg.opacity(scheme == .dark ? 0.18 : 0.54)))
                .overlay(Capsule().stroke(secondEnabled ? green.opacity(0.30) : hair,
                                          lineWidth: 0.8))
            }
            .buttonStyle(.plain)
            .disabled(!secondEnabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    private var secondIcon: String {
        if isBot { return "waveform" }
        switch relation {
        case "friend", "self": return "phone.fill"
        case "incoming":       return "person.badge.plus"
        case "requested":      return "clock"
        default:               return "person.badge.plus"
        }
    }

    private var premiumDivider: some View {
        Rectangle()
            .fill(hair)
            .frame(height: 0.5)
            .padding(.horizontal, 18)
    }

    private var secondTitle: String {
        if isBot { return Tr("语音通话") }
        switch relation {
        case "friend", "self": return Tr("音视频")
        case "incoming":       return Tr("同意申请")
        case "requested":      return Tr("申请已发送")
        default:               return Tr("添加联系人")
        }
    }

    private var secondEnabled: Bool { relation != "requested" }

    private func secondTap() {
        if isBot { onAICall(); return }
        switch relation {
        case "friend", "self": askCall = true
        case "incoming":       onAgree()
        case "requested":      break
        default:               onApply()
        }
    }

    private func row(_ title: String, _ value: String, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 10) {
                Text(title)
                    .font(pf(16))
                    .foregroundColor(ink)
                Spacer(minLength: 8)
                if !value.isEmpty {
                    Text(value)
                        .font(pf(14))
                        .foregroundColor(gray)
                        .lineLimit(1)
                }
                Chevron(size: 9, line: 1.6)
            }
            .padding(.horizontal, 16)
            .frame(height: rowH)
            .background(cardBg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))

            .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.045), radius: 7, y: 1.5)
    }

    private var hairline: some View {
        Rectangle().fill(hair).frame(height: 0.6).padding(.leading, 16)
    }

    private var gap: some View {
        Rectangle().fill(pageBg).frame(height: 8)
    }
}

private struct ContactIdentityMark: View {
    let accent: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(accent)
            HStack(spacing: 4) {
                Capsule().fill(Color(hex: 0x07351C)).frame(width: 2.6, height: 6.5)
                Capsule().fill(Color(hex: 0x07351C)).frame(width: 2.6, height: 6.5)
            }
            .offset(y: 1)
        }
    }
}

private struct ContactOrbitMotif: View {
    let accent: Color
    let ink: Color

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height) * 0.92
            ZStack {
                Ellipse()
                    .trim(from: 0.02, to: 0.78)
                    .stroke(ink.opacity(0.18),
                            style: StrokeStyle(lineWidth: 0.8, dash: [3, 6]))
                    .frame(width: side, height: side * 0.42)
                    .rotationEffect(.degrees(-18))
                    .position(x: geo.size.width * 0.68, y: geo.size.height * 0.42)
                Ellipse()
                    .trim(from: 0.18, to: 0.92)
                    .stroke(accent.opacity(0.30),
                            style: StrokeStyle(lineWidth: 0.8, dash: [1, 5]))
                    .frame(width: side * 0.70, height: side * 0.28)
                    .rotationEffect(.degrees(16))
                    .position(x: geo.size.width * 0.70, y: geo.size.height * 0.45)
                HStack(spacing: 8) {
                    Capsule().fill(accent.opacity(0.72)).frame(width: 5, height: 13)
                    Capsule().fill(accent.opacity(0.72)).frame(width: 5, height: 13)
                }
                .rotationEffect(.degrees(-16))
                .position(x: geo.size.width * 0.83, y: geo.size.height * 0.66)
            }
        }
    }
}
