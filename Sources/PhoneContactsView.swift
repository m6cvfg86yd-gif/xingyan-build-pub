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
}

struct PhoneContactsView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

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
                LazyVStack(spacing: 14) {
                    VStack(spacing: 10) {
                        Image(systemName: "person.text.rectangle")
                            .font(.system(size: 34, weight: .light))
                            .foregroundColor(C.green)
                        Text(Tr("从手机通讯录添加朋友"))
                            .font(pf(17, .semibold))
                            .foregroundColor(C.label)
                        Text(Tr("星言只在你选择一个联系人后，用这个号码查询对应账号；不会批量上传其他联系人。"))
                            .font(pf(12.5))
                            .foregroundColor(C.subLabel)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity)
                    .background(C.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

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
                                .background(Capsule().fill(C.green))
                        }
                        .buttonStyle(.plain)

                    case .requesting:
                        ProgressView(Tr("正在读取手机联系人…"))
                            .padding(.vertical, 24)

                    case .ready:
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(C.subLabel)
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
                        .frame(height: 42)
                        .background(C.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

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
                            VStack(spacing: 0) {
                                ForEach(filteredContacts) { contact in
                                    Button {
                                        Task { await lookUp(contact) }
                                    } label: {
                                        HStack(spacing: 12) {
                                            ZStack {
                                                Circle().fill(C.green.opacity(0.12))
                                                Text(String(contact.name.prefix(1)))
                                                    .font(pf(17, .semibold))
                                                    .foregroundColor(C.green)
                                            }
                                            .frame(width: 44, height: 44)

                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(contact.name)
                                                    .font(pf(16, .medium))
                                                    .foregroundColor(C.label)
                                                Text(contact.phone)
                                                    .font(pf(12))
                                                    .foregroundColor(C.subLabel)
                                            }

                                            Spacer()

                                            if searchingPhone == contact.phone {
                                                ProgressView()
                                            } else {
                                                Text(Tr("查找"))
                                                    .font(pf(12.5, .medium))
                                                    .foregroundColor(C.green)
                                            }
                                        }
                                        .padding(.horizontal, 14)
                                        .frame(height: 64)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!searchingPhone.isEmpty)
                                    if contact.id != filteredContacts.last?.id {
                                        HairLine(inset: 70)
                                    }
                                }
                            }
                            .background(C.cardBg)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                .padding(14)
                .padding(.bottom, max(20, L.safeBottom))
            }
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $qrInvite) { invite in
            PhoneInviteSheet(name: invite.name, phone: invite.phone,
                             image: invite.image) {
                qrInvite = nil
            }
        }
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
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                onOpenUser(user)
            }
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? Tr("查找失败，请稍后再试")
        }
    }

    private func prepareInvite(_ contact: LocalPhoneContact) {
        guard let image = makeInviteQRCard() else {
            errorText = Tr("二维码生成失败，请稍后再试")
            return
        }
        qrInvite = QRInvite(name: contact.name, phone: contact.phone, image: image)
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
}

private struct PhoneInviteSheet: View {
    let name: String
    let phone: String
    let image: UIImage
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
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: Color.black.opacity(0.12), radius: 14, y: 6)
                        .padding(.horizontal, 12)

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
            SMSInviteComposer(phone: phone, image: image) {
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
