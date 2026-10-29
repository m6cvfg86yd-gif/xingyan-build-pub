import SwiftUI

struct AccountSecurityView: View {
    @ObservedObject private var lang = LangStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var realNameText = ""
    @State private var hasPay = false
    @State private var showChangePwd = false
    @State private var confirmLogoutOthers = false

    @State private var showSafety = false

    private var me: User? { app.me }
    private var phoneText: String {
        let p = (me?.phone ?? "").trimmingCharacters(in: .whitespaces)
        return p.isEmpty ? Tr("未绑定") : maskPhone(p)
    }
    private var usernameText: String {
        let u = (me?.username ?? "").trimmingCharacters(in: .whitespaces)
        return u.isEmpty ? "—" : u
    }

    var body: some View {
        List {
            Section {
                NavigationLink(value: "profile") {
                    LabeledContent(Tr("个人信息"), value: me?.name ?? "")
                }
                Button {
                    app.show(Tr("账号一年只能改一次，需要的话联系客服"))
                } label: {
                    LabeledContent(Tr("账号"), value: usernameText)
                }
                Button {
                    app.show(Tr("手机号在注册或找回密码时绑定，需要换号联系客服"))
                } label: {
                    LabeledContent(Tr("手机号"), value: phoneText)
                }
                Button {
                    showSafety = true
                } label: {
                    LabeledContent(Tr("安全中心"),
                                   value: Tr("冻结 / 解冻 / 自助解封"))
                }
            }

            Section {
                NavigationLink(value: "changepwd") {
                    Text(Tr("修改登录密码"))
                }
                NavigationLink(value: "realname") {
                    LabeledContent(Tr("实名认证"), value: realNameText)
                }
                NavigationLink(value: "paypwd") {
                    LabeledContent(Tr("支付密码"),
                                   value: hasPay ? Tr("已设置") : Tr("未设置"))
                }
                NavigationLink(value: "gesture") {
                    LabeledContent(Tr("安全锁（手势密码）"),
                                   value: GestureStore.enabled ? Tr("已开启") : Tr("未开启"))
                }
                NavigationLink(value: "voicelock") {
                    LabeledContent(Tr("声音锁"),
                                   value: VoiceLockStore.enabled ? Tr("已开启") : Tr("未开启"))
                }
                NavigationLink(value: "score") {
                    Text(Tr("安全分"))
                }
            }

            Section {
                NavigationLink(value: "devices") {
                    Text(Tr("登录设备管理"))
                }
                Button(role: .destructive) {
                    confirmLogoutOthers = true
                } label: {
                    Text(Tr("退出其他设备"))
                }
            } footer: {
                Text(Tr("退出其他设备以后，别的手机上登录的这个账号会被踢下线，需要重新登录。"))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Tr("账号与安全"))
        .hidesTabBar()

        .sheet(isPresented: $showSafety) {
            AccountSafetyCenterView().environmentObject(app)
        }
        .task {
            if let m = try? await API.shared.me() {
                app.me = m
            }
            let rn = await API.shared.realNameStatus()
            realNameText = rn.verified ? Tr("已实名") : Tr("未实名")
            hasPay = await API.shared.hasPayPassword()
        }
        .confirmationDialog(Tr("退出其他设备？"), isPresented: $confirmLogoutOthers, titleVisibility: .visible) {
            Button(Tr("退出"), role: .destructive) {
                Task {
                    if let err = await API.shared.logoutOtherDevices() {
                        app.show(err)
                    } else {
                        app.show(Tr("已退出其他设备"))
                    }
                }
            }
            Button(Tr("取消"), role: .cancel) { }
        }
    }

    private func row(_ title: String, _ value: String, chevron: Bool) -> some View {
        HStack(spacing: 12) {
            Text(title).font(pf(17)).foregroundColor(C.label)
            Spacer(minLength: 8)
            if !value.isEmpty {
                Text(value).font(pf(15)).foregroundColor(C.subLabel).lineLimit(1)
            }
            if chevron { Chevron(size: 9, line: 1.6).padding(.trailing, 3) }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(C.cardBg)
        .contentShape(Rectangle())
    }
}

struct ChangePasswordSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var current = ""
    @State private var next = ""
    @State private var again = ""
    @State private var busy = false
    @State private var errorText = ""

    var body: some View {
        List {
            Section {
                field(Tr("当前密码"), $current)
                field(Tr("新密码（至少 6 位）"), $next)
                field(Tr("再输一遍新密码"), $again)
            } footer: {
                if !errorText.isEmpty {
                    Text(errorText)
                        .foregroundStyle(.red)
                } else {
                    Text(Tr("改完密码以后，其他手机上登录的这个账号会被踢下线。"))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Tr("修改登录密码"))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(busy ? Tr("保存中…") : Tr("完成")) {
                    save()
                }
                .disabled(!canSave)
            }
        }
        .hidesTabBar()
    }

    private var canSave: Bool { !busy && !current.isEmpty && next.count >= 6 && next == again }

    private func field(_ title: String, _ text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(.primary)
            Spacer(minLength: 12)
            SecureField("", text: text)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func save() {
        errorText = ""
        if next != again { errorText = Tr("两次输入的新密码不一样"); return }
        if next.count < 6 { errorText = Tr("新密码至少 6 位"); return }
        busy = true
        Task {
            do {
                try await API.shared.changePassword(current: current, new: next)
                // 服务端会返回新的当前设备会话令牌；立即写回本机账号，
                // 否则切号页仍保存旧令牌，要退出页面/重开 App 才恢复正常。
                app.rememberLastUser()
                busy = false
                dismiss()
                app.show(Tr("密码已修改"))
            } catch {
                busy = false
                errorText = (error as? APIError)?.errorDescription ?? Tr("修改失败")
            }
        }
    }
}
