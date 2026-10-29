import SwiftUI
import UIKit

struct AppleSettingsView: View {
    @EnvironmentObject private var app: AppState
    @State private var confirmLogout = false
    @State private var busy = false
    @State private var showQR = false
    @State private var momentsOn = MomentsPref.isOn

    private var accountSubtitle: String {
        let phone = (app.me?.phone ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !phone.isEmpty { return maskPhone(phone) }
        let username = app.me?.username ?? ""
        return username.isEmpty ? Tr("管理账号与安全") : username
    }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    ProfileEditView()
                } label: {
                    HStack(spacing: 13) {
                        Avatar(path: app.me?.avatarPath ?? "", size: 54, radius: 17)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(app.me?.name ?? Tr("星言用户"))
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(accountSubtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Button {
                    showQR = true
                } label: {
                    settingsRow(Tr("我的二维码"), symbol: "qrcode",
                                color: .blue)
                }
                .buttonStyle(.plain)
            }

            Section(header: Text(Tr("账号与安全"))) {
                NavigationLink {
                    AccountSecurityView()
                } label: {
                    settingsRow(Tr("账号安全"), symbol: "lock.shield.fill",
                                color: .blue)
                }
                NavigationLink {
                    LoginDevicesView()
                } label: {
                    settingsRow(Tr("登录设备"), symbol: "laptopcomputer.and.iphone",
                                color: .indigo)
                }
                NavigationLink {
                    RealNameView()
                } label: {
                    settingsRow(Tr("实名认证"), symbol: "person.text.rectangle.fill",
                                color: .green)
                }
                NavigationLink {
                    PayPasswordView()
                } label: {
                    settingsRow(Tr("支付密码"), symbol: "key.fill",
                                color: C.green)
                }
            }

            Section(header: Text(Tr("通用"))) {
                NavigationLink {
                    AppearanceView()
                } label: {
                    settingsRow(Tr("外观与显示"), symbol: "circle.lefthalf.filled",
                                color: .gray)
                }
                NavigationLink {
                    LanguageView()
                } label: {
                    settingsRow(Tr("语言与地区"), symbol: "globe",
                                color: .blue)
                }
                NavigationLink {
                    NotifyView()
                } label: {
                    settingsRow(Tr("通知"), symbol: "bell.badge.fill",
                                color: .red)
                }
                NavigationLink {
                    GeneralView()
                } label: {
                    settingsRow(Tr("界面与显示"), symbol: "switch.2",
                                color: .indigo)
                }
                NavigationLink {
                    PrivacyView()
                } label: {
                    settingsRow(Tr("隐私与权限"), symbol: "hand.raised.fill",
                                color: .blue)
                }
            }

            Section(header: Text(Tr("聊天与通话"))) {
                Toggle(isOn: Binding(
                    get: { momentsOn },
                    set: { value in
                        momentsOn = value
                        MomentsPref.set(value)
                        app.show(value ? Tr("朋友圈已开启")
                                        : Tr("朋友圈已关闭"))
                    }
                )) {
                    Label("朋友圈", systemImage: "photo.on.rectangle.angled")
                }
                NavigationLink {
                    ChatSettingsView()
                } label: {
                    settingsRow(Tr("聊天设置"), symbol: "message.fill",
                                color: .green)
                }
                NavigationLink {
                    CallSettingsView()
                } label: {
                    settingsRow(Tr("音视频通话"), symbol: "phone.fill",
                                color: .green)
                }
                NavigationLink {
                    ChatBackgroundSheet()
                } label: {
                    settingsRow(Tr("聊天背景"), symbol: "photo.fill",
                                color: .cyan)
                }
                NavigationLink {
                    StorageView()
                } label: {
                    settingsRow(Tr("存储空间"), symbol: "internaldrive.fill",
                                color: .gray)
                }
                NavigationLink {
                    ChatHistoryView()
                } label: {
                    settingsRow(Tr("聊天记录管理"), symbol: "clock.arrow.circlepath",
                                color: C.green)
                }
            }

            Section(header: Text(Tr("健康与保护"))) {
                NavigationLink {
                    TeenModeView()
                } label: {
                    settingsRow(Tr("未成年人模式"), symbol: "umbrella.fill",
                                color: .blue)
                }
                NavigationLink {
                    CareModeView()
                } label: {
                    settingsRow(Tr("关怀模式"), symbol: "textformat.size",
                                color: C.green)
                }
                NavigationLink {
                    SelfPermView()
                } label: {
                    settingsRow(Tr("个人信息与权限"), symbol: "checkmark.shield.fill",
                                color: .gray)
                }
            }

            Section(header: Text(Tr("支持"))) {
                NavigationLink {
                    SupportView()
                } label: {
                    settingsRow(Tr("帮助与客服"), symbol: "questionmark.circle.fill",
                                color: .blue)
                }
                NavigationLink {
                    FeedbackView()
                } label: {
                    settingsRow(Tr("帮助与反馈"), symbol: "bubble.left.and.bubble.right.fill",
                                color: .blue)
                }
                NavigationLink {
                    DiagView()
                } label: {
                    settingsRow(Tr("诊断工具"), symbol: "stethoscope",
                                color: .purple)
                }
                NavigationLink {
                    AboutView()
                } label: {
                    HStack {
                        settingsRow(Tr("关于星言"), symbol: "info.circle.fill",
                                    color: .gray)
                        Spacer()
                        Text(AppInfo.build)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if app.me?.ops == true {
                Section(header: Text(Tr("管理"))) {
                    NavigationLink {
                        UserManageView()
                    } label: {
                        settingsRow(Tr("用户管理"), symbol: "person.2.badge.gearshape.fill",
                                    color: .indigo)
                    }
                    NavigationLink {
                        FaceReviewView()
                    } label: {
                        settingsRow(Tr("人脸比对"), symbol: "face.smiling",
                                    color: C.green)
                    }
                }
            }

            Section {
                NavigationLink {
                    SwitchAccountView()
                } label: {
                    settingsRow(Tr("切换账号"), symbol: "arrow.triangle.2.circlepath",
                                color: .blue)
                }

                Button(role: .destructive) {
                    confirmLogout = true
                } label: {
                    HStack {
                        Spacer()
                        if busy {
                            ProgressView()
                        } else {
                            Text(Tr("退出登录"))
                        }
                        Spacer()
                    }
                }
                .disabled(busy)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Tr("设置"))
        .navigationBarTitleDisplayMode(.large)
        .hidesTabBar()
        .onAppear { momentsOn = MomentsPref.isOn }
        .onReceive(NotificationCenter.default.publisher(for: .chrisUIPrefsChanged)) { _ in
            momentsOn = MomentsPref.isOn
        }
        .sheet(isPresented: $showQR) {
            NavigationStack {
                MyQRView()
                    .environmentObject(app)
            }
        }
        .alert(Tr("确定退出登录？"), isPresented: $confirmLogout) {
            Button(Tr("取消"), role: .cancel) { }
            Button(Tr("退出登录"), role: .destructive) {
                busy = true
                Task {
                    await app.logout()
                    busy = false
                }
            }
        }
    }

    private func settingsRow(_ title: String, symbol: String, color: Color) -> some View {
        Label {
            Text(title)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(color)
                )
        }
    }
}
