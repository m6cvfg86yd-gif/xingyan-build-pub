import Contacts
import MessageUI
import SwiftUI
import UIKit

private enum PhoneContactLoadState {
    case idle, requesting, ready, denied
}

private struct LocalPhoneContact: Identifiable {
    let id: String
    let name: String
    let phone: String
}

private struct QRInvite: Identifiable {
    let id = UUID()
    let name: String
    let phone: String
    let image: UIImage
    let messageImage: UIImage
}

private struct PhoneContactMark: View {
    let accent: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(accent)
            HStack(spacing: 4) {
                Capsule().fill(Color(hex: 0x07351C)).frame(width: 2.8, height: 7)
                Capsule().fill(Color(hex: 0x07351C)).frame(width: 2.8, height: 7)
            }
            .offset(y: 1)
        }
    }
}

private struct PhoneOrbitMotif: View {
    let accent: Color
    let ink: Color

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height) * 0.95
            ZStack {
                Ellipse()
                    .trim(from: 0.04, to: 0.80)
                    .stroke(ink.opacity(0.16),
                            style: StrokeStyle(lineWidth: 0.8, dash: [3, 6]))
                    .frame(width: side, height: side * 0.40)
                    .rotationEffect(.degrees(-17))
                    .position(x: geo.size.width * 0.68, y: geo.size.height * 0.42)
                Ellipse()
                    .trim(from: 0.20, to: 0.92)
                    .stroke(accent.opacity(0.28),
                            style: StrokeStyle(lineWidth: 0.8, dash: [1, 5]))
                    .frame(width: side * 0.68, height: side * 0.26)
                    .rotationEffect(.degrees(15))
                    .position(x: geo.size.width * 0.70, y: geo.size.height * 0.44)
            }
        }
    }
}

struct PhoneContactsView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var scheme

    var onOpenUser: (User) -> Void

    @State private var state: PhoneContactLoadState = .idle
    @State private var contacts: [LocalPhoneContact] = []
    @State private var keyword = ""
    @State private var searchingPhone = ""
    @State private var qrInvite: QRInvite?
    @State private var errorText = ""

    private var filteredContacts: [LocalPhoneContact] {
        let q = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return contacts }
        let digits = q.filter { $0 >= "0" && $0 <= "9" }
        return contacts.filter {
            $0.name.localizedCaseInsensitiveContains(q)
                || (!digits.isEmpty && $0.phone.contains(digits))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("手机联系人"), back: { dismiss() })

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    contactsHero

                    switch state {
                    case .idle, .denied:
                        Button {
                            Task { await loadContacts() }
                        } label: {
                            Text(state == .denied ? Tr("去系统设置开启通讯录权限") : Tr("读取手机联系人"))
                                .font(pf(16, .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(
                                    Capsule().fill(
                                        LinearGradient(colors: [OrbitTheme.jadeDeep, OrbitTheme.jade],
                                                       startPoint: .leading, endPoint: .trailing)
                                    )
                                )
                                .shadow(color: OrbitTheme.jade.opacity(0.18), radius: 10, y: 5)
                        }
                        .buttonStyle(.plain)

                    case .requesting:
                        ProgressView(Tr("正在读取手机联系人…"))
                            .padding(.vertical, 24)

                    case .ready:
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(OrbitTheme.tertiary)
                            TextField(Tr("搜索姓名或号码"), text: $keyword)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            if !keyword.isEmpty {
                                Button {
                                    keyword = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(C.subLabel)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background(OrbitTheme.field)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(OrbitTheme.divider, lineWidth: 0.7)
                        }

                        if contacts.isEmpty {
                            Text(Tr("手机通讯录里没有可查询的号码"))
                                .font(pf(14))
                                .foregroundColor(C.subLabel)
                                .padding(.vertical, 30)
                        } else if filteredContacts.isEmpty {
                            Text(Tr("没有找到匹配的手机联系人"))
                                .font(pf(14))
                                .foregroundColor(C.subLabel)
                                .padding(.vertical, 30)
                        } else {
                            ForEach(filteredContacts) { contact in
                                Button {
                                    Task { await lookUp(contact) }
                                } label: {
                                    phoneContactRow(contact)
                                }
                                .buttonStyle(MenuPressStyle())
                                .disabled(!searchingPhone.isEmpty)
                            }
                        }
                    }

                    if !errorText.isEmpty {
                        Text(errorText)
                            .font(pf(12.5))
                            .foregroundColor(C.red)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, max(20, L.safeBottom))
            }
        }
        .background(phoneContactsBackdrop)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $qrInvite) { invite in
            PhoneInviteSheet(name: invite.name,
                             phone: invite.phone,
                             image: invite.image,
                             messageImage: invite.messageImage) {
                qrInvite = nil
            }
        }
    }

    private var phoneContactsBackdrop: some View {
        ZStack {
            OrbitTheme.canvas
            RadialGradient(colors: [OrbitTheme.jade.opacity(scheme == .dark ? 0.09 : 0.12), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 300)
        }
        .ignoresSafeArea()
    }

    private var contactsHero: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(colors: scheme == .dark
                                   ? [Color(hex: 0x14231A), Color(hex: 0x09100C)]
                                   : [Color(hex: 0xFCFEFC), Color(hex: 0xEAF5EE)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )

            PhoneOrbitMotif(accent: OrbitTheme.jade, ink: OrbitTheme.secondary)
                .frame(width: 170, height: 125)
                .offset(x: 24, y: -10)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 9) {
                    PhoneContactMark(accent: OrbitTheme.jade)
                        .frame(width: 28, height: 28)
                    Text("XINGYAN · CONTACT ORBIT")
                        .font(pfStyled(size: 9.5, weight: .semibold))
                        .tracking(1.3)
                        .foregroundStyle(OrbitTheme.secondary)
                }
                Text(Tr("从手机通讯录添加朋友"))
                    .font(pf(21, .semibold))
                    .foregroundStyle(OrbitTheme.ink)
                Text(Tr("星言只在你选择一个联系人后，用这个号码查询对应账号；不会批量上传其他联系人。"))
                    .font(pf(12))
                    .foregroundStyle(OrbitTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if state == .ready {
                    HStack(spacing: 7) {
                        Text("\(contacts.count)")
                            .font(pfStyled(size: 12, weight: .bold, design: .rounded))
                        Text(Tr("个本地联系人"))
                            .font(pf(10.5, .medium))
                    }
                    .foregroundStyle(OrbitTheme.jadeDeep)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Capsule().fill(OrbitTheme.jadeSoft))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(OrbitTheme.divider, lineWidth: 0.7)
        }
        .shadow(color: Color.black.opacity(scheme == .dark ? 0.30 : 0.07), radius: 16, y: 8)
    }

    private func phoneContactRow(_ contact: LocalPhoneContact) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(LinearGradient(colors: [OrbitTheme.jade.opacity(0.20),
                                                  OrbitTheme.jade.opacity(0.07)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Text(String(contact.name.prefix(1)))
                    .font(pfStyled(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(OrbitTheme.jadeDeep)
            }
            .frame(width: 46, height: 46)
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(OrbitTheme.jade.opacity(0.16), lineWidth: 0.7)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(contact.name)
                    .font(pf(15.5, .medium))
                    .foregroundStyle(OrbitTheme.ink)
                    .lineLimit(1)
                Text(contact.phone)
                    .font(pfStyled(size: 11.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(OrbitTheme.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)
            if searchingPhone == contact.phone {
                ProgressView().tint(OrbitTheme.jade)
            } else {
                HStack(spacing: 5) {
                    Text(Tr("查找"))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .bold))
                }
                .font(pf(11.5, .semibold))
                .foregroundStyle(OrbitTheme.jadeDeep)
                .padding(.horizontal, 10)
                .frame(height: 29)
                .background(Capsule().fill(OrbitTheme.jadeSoft))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 68)
        .background(OrbitTheme.raised)
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(OrbitTheme.divider, lineWidth: 0.7)
        }
        .contentShape(Rectangle())
    }

    private func loadContacts() async {
        if state == .denied {
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            return
        }

        state = .requesting
        errorText = ""
        let granted = await withCheckedContinuation { continuation in
            CNContactStore().requestAccess(for: .contacts) { allowed, _ in
                continuation.resume(returning: allowed)
            }
        }
        guard granted else {
            state = .denied
            errorText = Tr("没有通讯录权限。你可以去系统设置里开启，星言不会在后台读取。")
            return
        }

        do {
            contacts = try PhoneContactLoader.load()
            state = .ready
        } catch {
            state = .idle
            errorText = Tr("读取手机联系人失败，请稍后再试")
        }
    }

    private func lookUp(_ contact: LocalPhoneContact) async {
        guard searchingPhone.isEmpty else { return }
        searchingPhone = contact.phone
        errorText = ""
        defer { searchingPhone = "" }

        do {
            guard let user = try await API.shared.searchUsers(contact.phone).first else {
                errorText = Tr("这个手机联系人还没有注册星言，可以生成二维码邀请")
                prepareInvite(contact)
                return
            }
            onOpenUser(user)
            dismiss()
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? Tr("查找失败，请稍后再试")
        }
    }

    private func prepareInvite(_ contact: LocalPhoneContact) {
        guard let image = makeInviteQRCard(),
              let messageImage = makeMessageInviteQRCard() else {
            errorText = Tr("二维码生成失败，请稍后再试")
            return
        }
        qrInvite = QRInvite(name: contact.name,
                            phone: contact.phone,
                            image: image,
                            messageImage: messageImage)
    }

    private func makeInviteQRCard() -> UIImage? {
        guard let qr = qrImage("https://aa.x8iu.com/download.html", size: 720) else {
            return nil
        }
        let size = CGSize(width: 1080, height: 1380)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let ctx = renderer.cgContext
            let colors = [
                UIColor(red: 0.035, green: 0.20, blue: 0.17, alpha: 1).cgColor,
                UIColor(red: 0.015, green: 0.075, blue: 0.065, alpha: 1).cgColor
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors, locations: [0, 1]) {
                ctx.drawLinearGradient(gradient,
                                       start: CGPoint(x: 0, y: 0),
                                       end: CGPoint(x: size.width, y: size.height),
                                       options: [])
            }

            UIColor.white.withAlphaComponent(0.05).setStroke()
            ctx.setLineWidth(2)
            ctx.strokeEllipse(in: CGRect(x: -180, y: 80, width: 720, height: 720))
            ctx.strokeEllipse(in: CGRect(x: 670, y: 940, width: 520, height: 520))

            let card = CGRect(x: 80, y: 72, width: 920, height: 1236)
            let cardPath = UIBezierPath(roundedRect: card, cornerRadius: 48)
            UIColor.white.setFill()
            cardPath.fill()

            let titleStyle = NSMutableParagraphStyle()
            titleStyle.alignment = .center
            let title = "星言 Luchat" as NSString
            title.draw(in: CGRect(x: 130, y: 158, width: 820, height: 72),
                       withAttributes: [
                        .font: UIFont.systemFont(ofSize: 56, weight: .semibold),
                        .foregroundColor: UIColor(red: 0.035, green: 0.18, blue: 0.15, alpha: 1),
                        .paragraphStyle: titleStyle
                       ])

            let tagline = "安全、克制的即时通讯" as NSString
            tagline.draw(in: CGRect(x: 130, y: 238, width: 820, height: 48),
                         withAttributes: [
                            .font: UIFont.systemFont(ofSize: 26, weight: .regular),
                            .foregroundColor: UIColor(white: 0.38, alpha: 1),
                            .paragraphStyle: titleStyle
                         ])

            if let icon = UIImage(named: "AppIcon60x60@3x")
                ?? UIImage(named: "AppIcon60x60@2x") {
                let iconRect = CGRect(x: 480, y: 314, width: 120, height: 120)
                let iconPath = UIBezierPath(roundedRect: iconRect, cornerRadius: 28)
                ctx.saveGState()
                iconPath.addClip()
                icon.draw(in: iconRect)
                ctx.restoreGState()
            }

            let qrFrame = CGRect(x: 170, y: 474, width: 740, height: 740)
            let qrPath = UIBezierPath(roundedRect: qrFrame.insetBy(dx: -22, dy: -22),
                                      cornerRadius: 34)
            UIColor(white: 0.96, alpha: 1).setFill()
            qrPath.fill()
            qr.draw(in: qrFrame)

            let foot = "请使用微信或系统相机扫码下载" as NSString
            foot.draw(in: CGRect(x: 120, y: 1242, width: 840, height: 46),
                      withAttributes: [
                        .font: UIFont.systemFont(ofSize: 25, weight: .medium),
                        .foregroundColor: UIColor(red: 0.035, green: 0.18, blue: 0.15, alpha: 1),
                        .paragraphStyle: titleStyle
                      ])
        }
    }

    /// Messages renders attachments at roughly their real aspect ratio. Keep the
    /// SMS version compact and square so it does not dominate the composer or
    /// arrive as a large poster-sized preview.
    private func makeMessageInviteQRCard() -> UIImage? {
        guard let qr = qrImage("https://aa.x8iu.com/download.html", size: 420) else {
            return nil
        }
        let size = CGSize(width: 640, height: 640)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let ctx = renderer.cgContext
            let colors = [
                UIColor(red: 0.035, green: 0.20, blue: 0.17, alpha: 1).cgColor,
                UIColor(red: 0.015, green: 0.075, blue: 0.065, alpha: 1).cgColor
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors, locations: [0, 1]) {
                ctx.drawLinearGradient(gradient,
                                       start: CGPoint(x: 0, y: 0),
                                       end: CGPoint(x: size.width, y: size.height),
                                       options: [])
            }

            let card = CGRect(x: 28, y: 28, width: 584, height: 584)
            let cardPath = UIBezierPath(roundedRect: card, cornerRadius: 38)
            UIColor.white.setFill()
            cardPath.fill()

            let center = NSMutableParagraphStyle()
            center.alignment = .center
            ("星言 Luchat" as NSString).draw(
                in: CGRect(x: 64, y: 64, width: 512, height: 44),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 34, weight: .semibold),
                    .foregroundColor: UIColor(red: 0.035, green: 0.18, blue: 0.15, alpha: 1),
                    .paragraphStyle: center
                ]
            )

            let qrFrame = CGRect(x: 124, y: 128, width: 392, height: 392)
            UIColor(white: 0.985, alpha: 1).setFill()
            UIBezierPath(roundedRect: qrFrame.insetBy(dx: -12, dy: -12),
                         cornerRadius: 22).fill()
            qr.draw(in: qrFrame)

            ("扫码下载星言" as NSString).draw(
                in: CGRect(x: 96, y: 550, width: 448, height: 34),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 22, weight: .medium),
                    .foregroundColor: UIColor(red: 0.035, green: 0.18, blue: 0.15, alpha: 1),
                    .paragraphStyle: center
                ]
            )
        }
    }
}

private struct PhoneInviteSheet: View {
    let name: String
    let phone: String
    let image: UIImage
    let messageImage: UIImage
    let onFinish: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showShare = false
    @State private var showMessages = false
    @State private var saved = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    VStack(spacing: 6) {
                        Text(Tr("邀请 ") + name)
                            .font(pf(18, .semibold))
                            .foregroundColor(C.label)
                        Text(phone)
                            .font(pf(12.5))
                            .foregroundColor(C.subLabel)
                        Text(Tr("这个号码还没有注册星言"))
                            .font(pf(13))
                            .foregroundColor(C.subLabel)
                    }

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 220, maxHeight: 282)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: Color.black.opacity(0.12), radius: 14, y: 6)
                        .padding(.horizontal, 18)

                    VStack(spacing: 10) {
                        Button { showShare = true } label: {
                            inviteButton(Tr("分享二维码图片"), "square.and.arrow.up", filled: true)
                        }
                        .buttonStyle(.plain)

                        Button {
                            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                            saved = true
                        } label: {
                            inviteButton(saved ? Tr("已提交保存到相册") : Tr("保存二维码到相册"),
                                         "square.and.arrow.down", filled: false)
                        }
                        .buttonStyle(.plain)

                        Button { showMessages = true } label: {
                            inviteButton(Tr("发短信"), "message", filled: false)
                        }
                        .buttonStyle(.plain)

                        Text(Tr("支持彩信或 iMessage 时会附带二维码；纯短信只能发送文字邀请。"))
                            .font(pf(12))
                            .foregroundColor(C.subLabel)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(C.pageBg.ignoresSafeArea())
            .navigationTitle(Tr("二维码邀请"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(Tr("完成")) {
                        dismiss()
                        onFinish()
                    }
                }
            }
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [image])
        }
        .sheet(isPresented: $showMessages) {
            SMSInviteComposer(phone: phone, image: messageImage) {
                showMessages = false
            }
        }
    }

    private func inviteButton(_ title: String, _ icon: String, filled: Bool) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).font(.system(size: 17, weight: .medium))
            Text(title).font(pf(15, .medium))
        }
        .foregroundColor(filled ? .white : C.green)
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(filled ? C.green : C.cardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(filled ? Color.clear : C.green.opacity(0.35), lineWidth: 0.8)
        )
    }
}

private struct SMSInviteComposer: UIViewControllerRepresentable {
    let phone: String
    let image: UIImage
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let composer = MFMessageComposeViewController()
        composer.recipients = [phone]
        if MFMessageComposeViewController.canSendAttachments(),
           let data = image.pngData() {
            composer.body = Tr("我正在使用星言，扫描二维码即可下载：")
            composer.addAttachmentData(data, typeIdentifier: "public.png",
                                       filename: "xingyan-invite-qr.png")
        } else {
            composer.body = Tr("我正在使用星言，下载后可以通过手机号找到我。")
        }
        composer.messageComposeDelegate = context.coordinator
        return composer
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController,
                                context: Context) { }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        private let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            controller.dismiss(animated: true) { self.onFinish() }
        }
    }
}

private enum PhoneContactLoader {
    static func load() throws -> [LocalPhoneContact] {
        let keys = [
            CNContactGivenNameKey, CNContactFamilyNameKey,
            CNContactOrganizationNameKey, CNContactPhoneNumbersKey
        ] as [CNKeyDescriptor]
        let contacts = try CNContactStore().unifiedContacts(
            matching: NSPredicate(value: true),
            keysToFetch: keys
        )

        var seen = Set<String>()
        var rows: [LocalPhoneContact] = []
        for contact in contacts {
            let baseName = [contact.familyName, contact.givenName]
                .filter { !$0.isEmpty }
                .joined()
            let name = baseName.isEmpty ? contact.organizationName : baseName
            for phone in contact.phoneNumbers {
                let normalized = normalize(phone.value.stringValue)
                guard normalized.count >= 7, normalized.count <= 15,
                      seen.insert(normalized).inserted else { continue }
                rows.append(LocalPhoneContact(
                    id: normalized,
                    name: name.isEmpty ? normalized : name,
                    phone: normalized
                ))
            }
        }
        return rows.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private static func normalize(_ value: String) -> String {
        var digits = value.filter { $0 >= "0" && $0 <= "9" }
        if digits.hasPrefix("0086") { digits.removeFirst(4) }
        else if digits.hasPrefix("86"), digits.count == 13 { digits.removeFirst(2) }
        return digits
    }
}
