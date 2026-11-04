import SwiftUI

enum QRInk: String, CaseIterable {
    case green, blue, red, amber, purple, black

    var name: String {
        switch self {
        case .green:  return "绿"
        case .blue:   return "蓝"
        case .red:    return "红"
        case .amber:  return "黄"
        case .purple: return "紫"
        case .black:  return "黑"
        }
    }
    var color: Color {
        switch self {
        case .green:  return Color(hexString: "#12A05A")
        case .blue:   return Color(hexString: "#1B5FD0")
        case .red:    return Color(hexString: "#D6353B")
        case .amber:  return Color(hexString: "#B4770F")
        case .purple: return Color(hexString: "#6A3FD0")
        case .black:  return Color(hexString: "#111111")
        }
    }
}

private struct XingyanMark: View {
    let accent: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(accent)
            HStack(spacing: 4) {
                Capsule().fill(Color(hex: 0x07351C)).frame(width: 2.8, height: 7)
                Capsule().fill(Color(hex: 0x07351C)).frame(width: 2.8, height: 7)
            }
            .offset(y: 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.white.opacity(0.36), lineWidth: 0.6)
        }
    }
}

private struct OrbitIdentityMotif: View {
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
                    .stroke(accent.opacity(0.28),
                            style: StrokeStyle(lineWidth: 0.8, dash: [1, 5]))
                    .frame(width: side * 0.70, height: side * 0.28)
                    .rotationEffect(.degrees(16))
                    .position(x: geo.size.width * 0.70, y: geo.size.height * 0.45)

                Circle()
                    .fill(accent)
                    .frame(width: 4, height: 4)
                    .position(x: geo.size.width * 0.48, y: geo.size.height * 0.37)

                HStack(spacing: 8) {
                    Capsule().fill(accent.opacity(0.75)).frame(width: 5, height: 13)
                    Capsule().fill(accent.opacity(0.75)).frame(width: 5, height: 13)
                }
                .rotationEffect(.degrees(-16))
                .position(x: geo.size.width * 0.83, y: geo.size.height * 0.66)
            }
        }
    }
}

struct MyQRView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var growth = GrowthStore.shared

    @State private var rows: [String] = []
    @State private var code = ""
    @State private var name = ""
    @State private var username = ""
    @State private var avatar = ""
    @State private var loading = true
    @State private var saved = false
    @State private var showScan = false

    @State private var showStyle = false

    @State private var showFaceFile = false

    @State private var showPayCode = false
    @State private var appeared = false

    @AppStorage("qrInkStyle") private var inkID = QRInk.green.rawValue

    private var ink: QRInk { QRInk(rawValue: inkID) ?? .green }
    private var cardInk: Color {
        scheme == .dark ? Color(hex: 0xF1F8F4) : Color(hex: 0x122019)
    }
    private var cardSubInk: Color {
        scheme == .dark ? Color(hex: 0x8FA69A) : Color(hex: 0x63736A)
    }
    private var cardHairline: Color {
        scheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.075)
    }
    private var cardChipFill: Color {
        scheme == .dark ? Color.white.opacity(0.07) : Color.white.opacity(0.72)
    }
    private var cardAvatarFill: Color {
        scheme == .dark ? Color(hex: 0x17241D) : Color(hex: 0xE8F5ED)
    }
    private var cardFooterFill: Color {
        scheme == .dark ? Color(hex: 0x0B130F) : Color(hex: 0xEEF5F0)
    }
    private var levelText: String {
        Tr("星轨") + " Lv." + "\(growth.shownLevel)"
    }
    private var identityCardFill: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: scheme == .dark
                            ? [Color(hex: 0x13231A), Color(hex: 0x09100C)]
                            : [Color(hex: 0xFCFEFC), Color(hex: 0xEFF7F1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [OrbitTheme.jade.opacity(scheme == .dark ? 0.13 : 0.10), .clear],
                        center: .topTrailing,
                        startRadius: 0,
                        endRadius: 260
                    )
                )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("个人名片"), back: { dismiss() })

            ZStack {
                identityBackdrop

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        identityCard
                            .opacity(appeared ? 1 : 0)
                            .scaleEffect(appeared ? 1 : 0.985)
                            .offset(y: appeared ? 0 : 8)

                        actionDock

                        HStack(spacing: 7) {
                            Image(systemName: "lock.shield.fill")
                            Text(Tr("名片只展示星言身份，不公开手机号"))
                        }
                        .font(pf(10.5, .medium))
                        .foregroundStyle(C.subLabel)
                        .padding(.bottom, 30)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                }
            }
        }
        .background(identityBackdrop)
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                appeared = true
            }
        }

        .modifier(BrightenScreen())
        .fullScreenCover(isPresented: $showScan) {
            ScannerView { text in handleScanned(text, app: app) }
        }

        .sheet(isPresented: $showStyle) {
            QRStyleSheet(current: ink) { pick in
                inkID = pick.rawValue
                DiagLog.shared.note("二维码样式：" + pick.name)
            }
        }

        .sheet(isPresented: $showFaceFile) {
            FaceToFaceFileSheet(rows: rows, avatar: avatar, name: name, ink: ink.color)
                .environmentObject(app)
        }

        .sheet(isPresented: $showPayCode) {
            NavigationStack { PayCodePage() }
                .environmentObject(app)
        }
        .task {
            let r = await API.shared.myQRCode()
            code = r.code
            rows = r.rows
            name = r.user?.name ?? (app.me?.name ?? "")
            username = r.user?.username ?? (app.me?.username ?? "")
            avatar = r.user?.avatarPath ?? (app.me?.avatarPath ?? "")
            loading = false
        }
    }

    private var identityBackdrop: some View {
        ZStack {
            OrbitTheme.canvas
            RadialGradient(colors: [OrbitTheme.jade.opacity(scheme == .dark ? 0.10 : 0.13), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 330)
            LinearGradient(colors: [Color.white.opacity(scheme == .dark ? 0.015 : 0.32), .clear],
                           startPoint: .topLeading, endPoint: .center)
        }
        .ignoresSafeArea()
    }

    private var identityCard: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                identityCardFill
                OrbitIdentityMotif(accent: OrbitTheme.jade, ink: cardSubInk)
                    .frame(width: 190, height: 150)
                    .offset(x: 18, y: -12)
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    identityHeader
                    Rectangle()
                        .fill(cardHairline)
                        .frame(height: 0.5)
                        .padding(.top, 18)
                    qrPanel
                        .padding(.top, 17)
                }
                .padding(18)
            }

            HStack(spacing: 8) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                Text("XINGYAN · ORBIT ID")
                    .tracking(1.5)
                Spacer(minLength: 4)
                Text(String(format: "ID %04d", abs(username.hashValue % 10_000)))
                    .monospacedDigit()
            }
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(cardSubInk)
            .padding(.horizontal, 18)
            .frame(height: 38)
            .background(cardFooterFill)
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(cardHairline, lineWidth: 0.8)
        }
        .shadow(color: Color.black.opacity(scheme == .dark ? 0.34 : 0.10),
                radius: 22, y: 12)
    }

    private var identityHeader: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                HStack(spacing: 7) {
                    XingyanMark(accent: OrbitTheme.jade)
                        .frame(width: 24, height: 24)
                    Text(Tr("星言身份卡"))
                        .font(pf(10.5, .semibold))
                        .tracking(1.5)
                }
                .foregroundStyle(cardSubInk)

                Spacer(minLength: 8)

                HStack(spacing: 5) {
                    Circle().fill(OrbitTheme.jade).frame(width: 5, height: 5)
                    Text(levelText)
                        .font(pf(10, .semibold))
                }
                .foregroundStyle(cardInk)
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(Capsule().fill(cardChipFill))
                .overlay(Capsule().stroke(cardHairline, lineWidth: 0.7))
            }

            HStack(alignment: .center, spacing: 15) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(cardAvatarFill)
                    Avatar(path: avatar.isEmpty ? (app.me?.avatarPath ?? "") : avatar,
                           size: 68, radius: 21, circle: false, level: growth.shownLevel)
                        .padding(4)
                }
                .frame(width: 78, height: 78)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(OrbitTheme.jade.opacity(0.28), lineWidth: 0.8)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(name.isEmpty ? (app.me?.name ?? "") : name)
                        .font(pf(24, .semibold))
                        .foregroundStyle(cardInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                    Text(Tr("扫码建立星言连接"))
                        .font(pf(11.5))
                        .foregroundStyle(cardSubInk)
                    HStack(spacing: 6) {
                        Text(Tr("星言号"))
                            .font(pf(10.5, .medium))
                        Text(username.isEmpty ? "-" : username)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .copyOnLongPress(username) { app.show($0) }
                    }
                    .foregroundStyle(cardInk.opacity(0.80))
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var qrPanel: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(hex: 0xFCFDFC))
                if loading {
                    ProgressView()
                        .tint(C.green)
                } else if rows.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 22))
                            .foregroundColor(C.subLabel)
                        Text(Tr("二维码生成失败，稍后再试"))
                            .font(pf(13))
                            .foregroundColor(C.subLabel)
                    }
                } else {
                    QRCanvas(rows: rows, avatar: avatar, ink: ink.color)
                        .frame(width: 214, height: 214)
                }
            }
            .frame(width: 244, height: 244)
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.98), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(scheme == .dark ? 0.25 : 0.08),
                    radius: 12, y: 6)

            VStack(spacing: 3) {
                Text(Tr("扫码添加好友"))
                    .font(pf(16, .semibold))
                    .foregroundStyle(cardInk)
                Text(Tr("打开星言 · 发现 · 扫一扫"))
                    .font(pf(11.5))
                    .tracking(0.2)
                    .foregroundStyle(cardSubInk)
            }
        }
    }

    private var actionDock: some View {
        HStack(spacing: 10) {
            qrTile(icon: "square.and.arrow.down.on.square",
                   title: Tr("收照片和文件"),
                   sub: Tr("当面发送")) { showFaceFile = true }
            qrTile(icon: "yensign.circle",
                   title: Tr("收红包"),
                   sub: Tr("当场收款")) { showPayCode = true }
            qrTile(icon: "paintpalette",
                   title: Tr("名片样式"),
                   sub: ink.name + Tr("色")) { showStyle = true }
            qrTile(icon: "arrow.down.to.line",
                   title: saved ? Tr("已保存") : Tr("保存名片"),
                   sub: Tr("保存到相册")) { saveToAlbum() }
        }
    }

    private func qrTile(icon: String, title: String, sub: String,
                        tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(C.green.opacity(scheme == .dark ? 0.14 : 0.10))
                    Image(systemName: icon)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundColor(C.green)
                }
                .frame(width: 38, height: 38)

                VStack(spacing: 2) {
                    Text(title)
                        .font(pf(11.5, .medium))
                        .foregroundColor(C.label)
                        .lineLimit(1)
                        .minimumScaleFactor(0.70)
                    Text(sub)
                        .font(pf(9.5))
                        .foregroundColor(C.subLabel)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 96)
            .background(OrbitTheme.raised)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(OrbitTheme.divider, lineWidth: 0.7)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func saveToAlbum() {
        guard !rows.isEmpty else { return }
        let exportInk = Color(hex: 0x122019)
        let exportSub = Color(hex: 0x68766D)
        let exportAccent = Color(hex: 0x23C77C)
        let card = ZStack(alignment: .topTrailing) {
            LinearGradient(colors: [Color(hex: 0xFCFEFC), Color(hex: 0xEAF6EE)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)

            OrbitIdentityMotif(accent: exportAccent, ink: exportSub)
                .frame(width: 290, height: 220)
                .offset(x: 28, y: -18)

            VStack(spacing: 20) {
                HStack(spacing: 12) {
                    XingyanMark(accent: exportAccent)
                        .frame(width: 38, height: 38)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("XINGYAN · ORBIT ID")
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(2.2)
                            .foregroundColor(exportAccent)
                        Text(Tr("星言身份卡"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(exportSub)
                    }
                    Spacer()
                    Text(levelText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(exportInk)
                        .padding(.horizontal, 13)
                        .frame(height: 32)
                        .background(Capsule().fill(Color.white.opacity(0.72)))
                        .overlay(Capsule().stroke(Color.black.opacity(0.07), lineWidth: 0.7))
                }

                VStack(spacing: 5) {
                    Text(name)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundColor(exportInk)
                    Text(Tr("星言号") + "  " + username)
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .foregroundColor(exportSub)
                }
                .frame(maxWidth: .infinity)

                QRCanvas(rows: rows, avatar: avatar, ink: ink.color)
                    .frame(width: 490, height: 490)
                    .padding(26)
                    .background(RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(Color(hex: 0xFCFDFC)))
                    .overlay {
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .stroke(Color.white, lineWidth: 1.2)
                    }
                    .shadow(color: Color.black.opacity(0.07), radius: 18, y: 8)

                HStack(spacing: 8) {
                    Circle().fill(exportAccent).frame(width: 7, height: 7)
                    Text(Tr("扫码添加好友") + "  ·  " + Tr("星言 · 个人身份"))
                        .font(.system(size: 14, weight: .medium))
                        .tracking(0.6)
                        .foregroundColor(exportInk.opacity(0.82))
                }
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 30)
        }
        .frame(width: 640)
        .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        }
        let renderer = ImageRenderer(content: card)
        renderer.scale = 1
        if let img = renderer.uiImage {
            UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
            saved = true
            app.show(Tr("二维码已存到相册"))
            return
        }
        app.show(Tr("保存失败，可以截图"))
    }
}
