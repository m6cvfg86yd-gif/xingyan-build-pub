import Contacts
import CryptoKit
import Security
import SwiftUI
import UIKit

private enum PhoneContactMatchState {
    case idle, requesting, done, denied
}

struct PhoneContactsView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var onOpenUser: (User) -> Void

    @State private var state: PhoneContactMatchState = .idle
    @State private var users: [User] = []
    @State private var errorText = ""

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("手机联系人"), back: { dismiss() })

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    VStack(spacing: 10) {
                        Image(systemName: "person.text.rectangle")
                            .font(.system(size: 34, weight: .light))
                            .foregroundColor(C.green)
                        Text(Tr("发现已经使用星言的手机联系人"))
                            .font(pf(17, .semibold))
                            .foregroundColor(C.label)
                        Text(Tr("联系人号码不会上传原文，也不会保存。星言只在你点击后读取号码，用本次随机令牌生成不可逆匹配值。"))
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
                            Task { await beginMatch() }
                        } label: {
                            Text(state == .denied ? Tr("去系统设置开启通讯录权限") : Tr("开始匹配"))
                                .font(pf(16, .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(Capsule().fill(C.green))
                        }
                        .buttonStyle(.plain)
                    case .requesting:
                        ProgressView(Tr("正在匹配…"))
                            .padding(.vertical, 24)
                    case .done:
                        if users.isEmpty {
                            Text(Tr("暂时没有发现已使用星言的手机联系人"))
                                .font(pf(14))
                                .foregroundColor(C.subLabel)
                                .padding(.vertical, 30)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(users) { user in
                                    Button {
                                        dismiss()
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                            onOpenUser(user)
                                        }
                                    } label: {
                                        HStack(spacing: 12) {
                                            Avatar(path: user.avatarPath, size: 44, radius: 22, circle: true)
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(user.name).font(pf(16, .medium)).foregroundColor(C.label)
                                                if let username = user.username, !username.isEmpty {
                                                    Text("@" + username).font(pf(12)).foregroundColor(C.subLabel)
                                                }
                                            }
                                            Spacer()
                                            Text(user.relation == "friend" ? Tr("已添加") : Tr("添加"))
                                                .font(pf(12.5, .medium))
                                                .foregroundColor(C.green)
                                        }
                                        .padding(.horizontal, 14)
                                        .frame(height: 64)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    if user.id != users.last?.id { HairLine(inset: 70) }
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
                    }
                }
                .padding(14)
                .padding(.bottom, max(20, L.safeBottom))
            }
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func beginMatch() async {
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
            users = try await PhoneContactsMatcher.match()
            state = .done
        } catch {
            state = .idle
            errorText = (error as? LocalizedError)?.errorDescription ?? Tr("匹配失败，请稍后再试")
        }
    }
}

private enum PhoneContactsMatcher {
    static func match() async throws -> [User] {
        let store = CNContactStore()
        let keys = [
            CNContactGivenNameKey, CNContactFamilyNameKey,
            CNContactOrganizationNameKey, CNContactPhoneNumbersKey
        ] as [CNKeyDescriptor]
        let contacts = try store.unifiedContacts(
            matching: NSPredicate(value: true),
            keysToFetch: keys
        )

        var phones = Set<String>()
        for contact in contacts {
            for phone in contact.phoneNumbers {
                let normalized = normalize(phone.value.stringValue)
                if normalized.count >= 7, normalized.count <= 15 {
                    phones.insert(normalized)
                }
                if phones.count >= 2000 { break }
            }
            if phones.count >= 2000 { break }
        }
        guard !phones.isEmpty else { return [] }

        var salt = Data(count: 32)
        let status = salt.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw APIError.message(Tr("安全随机数生成失败"))
        }
        let key = SymmetricKey(data: salt)
        let hashes = phones.map { phone in
            HMAC<SHA256>.authenticationCode(for: Data(phone.utf8), using: key)
                .map { String(format: "%02x", $0) }
                .joined()
        }
        return try await API.shared.matchPhoneContacts(salt: salt, hashes: hashes)
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private static func normalize(_ value: String) -> String {
        var digits = value.filter { $0 >= "0" && $0 <= "9" }
        if digits.hasPrefix("0086") { digits.removeFirst(4) }
        else if digits.hasPrefix("86"), digits.count == 13 { digits.removeFirst(2) }
        return digits
    }
}
