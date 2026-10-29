import SwiftUI

struct SettingRowLink: View {
    let title: String
    var value: String = ""
    let key: String

    var body: some View {
        NavigationLink(value: key) {
            SettingRowLabel(title: title, value: value)
        }
        .buttonStyle(MenuPressStyle())
    }
}

struct SettingRowButton: View {
    let title: String
    var value: String = ""
    let tap: () -> Void

    var body: some View {
        Button(action: tap) {
            SettingRowLabel(title: title, value: value)
        }
        .buttonStyle(MenuPressStyle())
    }
}

struct SettingRowLabel: View {
    let title: String
    var value: String = ""

    var body: some View {
        HStack(spacing: 12) {
            Text(title).font(pf(17)).foregroundColor(C.label)
            Spacer(minLength: 0)
            if !value.isEmpty {
                Text(value).font(pf(15)).foregroundColor(C.subLabel).lineLimit(1)
            }
            Chevron(size: 9, line: 1.6).padding(.trailing, 3)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(C.meCardBg)
        .contentShape(Rectangle())
    }
}

struct SelfPermView: View {
    @ObservedObject private var lang = LangStore.shared

    @ObservedObject private var mallAuth = MallAuthStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showMallAuth = false

    var body: some View {
        List {
            Section {
                NavigationLink(value: "profile") {
                    Text(Tr("个人资料"))
                }
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    LabeledContent(Tr("系统权限管理"),
                                   value: Tr("相册 / 相机 / 麦克风"))
                }
                Button {
                    showMallAuth = true
                } label: {
                    LabeledContent(Tr("授权管理"),
                                   value: mallAuth.grantedTo.isEmpty ? Tr("无") : Tr("商城"))
                }
                NavigationLink(value: "privacy") {
                    Text(Tr("隐私"))
                }
            } footer: {
                Text(Tr("App 只在你同意之后才会用相册、相机、麦克风、位置这些权限，随时可以在 iOS 设置里改。"))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Tr("个人信息与权限"))
        .hidesTabBar()
        .sheet(isPresented: $showMallAuth) { MallAuthManageSheet() }
    }
}

struct MallAuthManageSheet: View {
    @ObservedObject private var auth = MallAuthStore.shared
    @ObservedObject private var store = DDStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if auth.grantedTo.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.shield")
                            .font(.system(size: 30))
                            .foregroundStyle(.secondary)
                        Text(Tr("还没有授权任何应用"))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
                        .listRowBackground(Color.clear)
                } else {
                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: "bag.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 42, height: 42)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(DDColor.gradBtn)
                                )
                            VStack(alignment: .leading, spacing: 3) {
                                Text(store.mallName)
                                Text(Tr("获取你的公开信息（昵称、头像、星言号）"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        Button(role: .destructive) {
                            auth.revoke()
                        } label: {
                            Text(Tr("解除授权"))
                        }
                    } footer: {
                        Text(Tr("解除授权后，下次进商城会重新问一次。"))
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(Tr("授权管理"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Tr("完成")) { dismiss() }
                }
            }
        }
        .hidesTabBar()
    }
}

struct MoreSettingsView: View {
    @ObservedObject private var lang = LangStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showDiag = false
    @State private var careOn = CareMode.on

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("更多"), back: { dismiss() })
            ScrollView {
                VStack(spacing: 0) {
                    GroupCard {
                        SettingRowLink(title: Tr("未成年人模式"), key: "teen")
                        HairLine(inset: 16)
                        SettingRowLink(title: Tr("关怀模式"),
                                       value: careOn ? Tr("已开启") : Tr("未开启"),
                                       key: "care")
                        HairLine(inset: 16)
                        SettingRowLink(title: Tr("我的等级"), key: "level")
                        HairLine(inset: 16)
                        SettingRowLink(title: Tr("安全分"), key: "score")
                        HairLine(inset: 16)
                        SettingRowLink(title: Tr("登录设备管理"), key: "devices")
                        HairLine(inset: 16)

                        SettingRowLink(title: Tr("故障修复"), key: "health")
                        HairLine(inset: 16)

                        SettingRowButton(title: Tr("诊断工具")) { showDiag = true }
                    }
                    .padding(.top, 8)
                    Spacer().frame(height: 30)
                }
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .sheet(isPresented: $showDiag) {
            DiagView().environmentObject(app)
        }
        .onAppear { careOn = CareMode.on }
        .onReceive(NotificationCenter.default.publisher(for: .chrisUIPrefsChanged)) { _ in
            careOn = CareMode.on
        }
    }
}

struct ChatSettingsView: View {
    @ObservedObject private var lang = LangStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                NavigationLink(value: "g.chatbg") { Text(Tr("聊天背景")) }
                NavigationLink(value: "g.voice") { Text(Tr("语音变声")) }
                NavigationLink(value: "g.history") { Text(Tr("聊天记录管理")) }
                NavigationLink(value: "g.storage") { Text(Tr("存储空间")) }
            } footer: {
                Text(Tr("聊天记录只存在这台手机上，也能在「存储空间」里按会话清理。"))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Tr("聊天"))
        .hidesTabBar()
    }
}

struct CallSettingsView: View {
    @ObservedObject private var lang = LangStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var quality = CallPrefs.quality
    @State private var mirror = CallPrefs.mirror
    @State private var beauty = CallPrefs.beauty
    @State private var pickQuality = false
    @State private var pickBeauty = false

    var body: some View {
        List {
            Section {
                NavigationLink(value: "notify") { Text(Tr("新消息通知")) }
                NavigationLink(value: "g.voice") { Text(Tr("语音变声")) }
                Button {
                    pickQuality = true
                } label: {
                    LabeledContent(Tr("视频清晰度"),
                                   value: Tr(CallPrefs.qualityName))
                }
                Toggle(Tr("本地画面镜像"), isOn: Binding(
                    get: { mirror },
                    set: { v in mirror = v; CallPrefs.mirror = v }
                ))
                Button {
                    pickBeauty = true
                } label: {
                    LabeledContent(Tr("视频美颜"),
                                   value: Tr(CallPrefs.beautyName))
                }
                NavigationLink(value: "devices") { Text(Tr("登录设备管理")) }
            } footer: {
                Text(Tr("语音通话默认走听筒，通话中点一下扬声器就外放；视频通话默认外放。清晰度、镜像、美颜改完，正在进行的通话会立刻生效。"))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Tr("音视频通话"))
        .hidesTabBar()
        .confirmationDialog(Tr("视频清晰度"), isPresented: $pickQuality, titleVisibility: .visible) {
            Button(Tr("标清（省流量）")) { quality = 0; CallPrefs.quality = 0 }
            Button(Tr("高清（推荐）")) { quality = 1; CallPrefs.quality = 1 }
            Button(Tr("超清（最清晰）")) { quality = 2; CallPrefs.quality = 2 }
            Button(Tr("取消"), role: .cancel) { }
        } message: {
            Text(Tr("清晰度越高越吃流量：标清约 0.6Mbps、高清约 1.5Mbps、超清约 2.6Mbps。"))
        }
        .confirmationDialog(Tr("视频美颜"), isPresented: $pickBeauty, titleVisibility: .visible) {
            Button(Tr("关")) { beauty = 0; CallPrefs.beauty = 0 }
            Button(Tr("低")) { beauty = 1; CallPrefs.beauty = 1 }
            Button(Tr("中")) { beauty = 2; CallPrefs.beauty = 2 }
            Button(Tr("高")) { beauty = 3; CallPrefs.beauty = 3 }
            Button(Tr("取消"), role: .cancel) { }
        }
    }
}
