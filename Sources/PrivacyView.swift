import SwiftUI

struct PrivacyView: View {
    @ObservedObject private var lang = LangStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var p = PrivacySettings()
    @State private var showRange = false

    var body: some View {
        List {
            Section {
                row(Tr("加我为朋友时需要验证"), $p.needVerify, "needVerify")
                row(Tr("允许陌生人查看朋友圈"), $p.strangerMoments, "strangerMoments")
                Button {
                    showRange = true
                } label: {
                    HStack {
                        Text(Tr("朋友圈可见范围"))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(rangeLabel)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
            }

            Section(header: Text(Tr("添加我的方式")),
                    footer: Text(Tr("关掉之后，别人就不能用这个方式找到你、加你好友。"))) {
                row(Tr("账号"), $p.addByWx, "addByWx")
                row(Tr("手机号"), $p.addByPhone, "addByPhone")
                row(Tr("群聊"), $p.addByGroup, "addByGroup")
                row(Tr("二维码"), $p.addByQR, "addByQR")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Tr("隐私"))
        .hidesTabBar()
        .task { p = await API.shared.privacy() }
        .confirmationDialog(Tr("朋友圈可见范围"), isPresented: $showRange, titleVisibility: .visible) {
            Button(Tr("最近三天")) { setRange("3d") }
            Button(Tr("最近半年")) { setRange("6m") }
            Button(Tr("全部")) { setRange("all") }
            Button(Tr("取消"), role: .cancel) { }
        }
    }

    private var rangeLabel: String {
        switch p.momentsRange {
        case "3d": return Tr("最近三天")
        case "6m": return Tr("最近半年")
        default: return Tr("全部")
        }
    }

    private func setRange(_ v: String) {
        p.momentsRange = v
        Task { await API.shared.setPrivacyText("momentsRange", v) }
    }

    private func row(_ title: String, _ value: Binding<Bool>, _ key: String) -> some View {
        Toggle(title, isOn: Binding(
            get: { value.wrappedValue },
            set: { v in
                value.wrappedValue = v
                Task { await API.shared.setPrivacy(key, v) }
            }
        ))
    }
}

struct NotifyView: View {
    @ObservedObject private var lang = LangStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var n = NotifySettings()
    @State private var muteOn = false
    @ObservedObject private var push = PushCenter.shared

    private var sysText: String { push.authorized ? Tr("已开启") : Tr("已关闭") }

    var body: some View {
        List {
            Section {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack {
                        Text(Tr("接收新消息通知"))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(sysText)
                            .foregroundStyle(push.authorized ? Color.secondary : Color(.systemBlue))
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
            }

            Section {
                row(Tr("App 内提醒"), $n.on, "on")
                row(Tr("声音"), $n.sound, "sound")
                row(Tr("振动"), $n.vibrate, "vibrate")
                row(Tr("通知显示消息详情"), $n.showDetail, "showDetail")
            } footer: {
                if !push.authorized {
                    Text(Tr("系统通知还没开：点上面那行去 iOS 设置里打开「允许通知」，不然 App 在后台收不到提醒。"))
                }
            }

            Section {
                Toggle(Tr("免打扰"), isOn: $muteOn)
                if muteOn {
                    DatePicker(Tr("开始"),
                               selection: Binding(
                                get: { Self.time(n.muteStart, 22, 0) },
                                set: { n.muteStart = Self.hhmm($0) }),
                               displayedComponents: .hourAndMinute)
                    DatePicker(Tr("结束"),
                               selection: Binding(
                                get: { Self.time(n.muteEnd, 7, 0) },
                                set: { n.muteEnd = Self.hhmm($0) }),
                               displayedComponents: .hourAndMinute)
                }
            } footer: {
                Text(Tr("免打扰时段里收到消息不响不震，进 App 还是能看到小红点。"))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Tr("通知"))
        .hidesTabBar()
        .task {
            n = await API.shared.notifySettings()
            muteOn = !(n.muteStart.isEmpty || n.muteEnd.isEmpty)
            if !muteOn { n.muteStart = ""; n.muteEnd = "" }
            PushCenter.shared.start()
        }
        .onChange(of: muteOn) { on in
            if on { n.muteStart = "22:00"; n.muteEnd = "07:00" }
            else { n.muteStart = ""; n.muteEnd = "" }
            Task {
                await API.shared.setNotify([
                    "muteStart": n.muteStart,
                    "muteEnd": n.muteEnd
                ])
                LocalNotify.settings = n
            }
        }
    }

    private func row(_ title: String, _ value: Binding<Bool>, _ key: String) -> some View {
        Toggle(title, isOn: Binding(
            get: { value.wrappedValue },
            set: { v in
                value.wrappedValue = v
                Task {
                    await API.shared.setNotify([key: v])
                    LocalNotify.settings = n
                }
            }
        ))
    }

    static func hhmm(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d)
    }
    static func time(_ s: String, _ h: Int, _ m: Int) -> Date {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        if let d = f.date(from: s) { return d }
        var c = DateComponents(); c.hour = h; c.minute = m
        return Calendar.current.date(from: c) ?? Date()
    }
}

struct GeneralView: View {
    @ObservedObject private var lang = LangStore.shared
    @ObservedObject private var fontStore = AppFontStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var showTheme = false
    @State private var showLang = false
    @State private var showBg = false
    @State private var showBgPick = false
    @State private var showStorage = false
    @State private var showHistory = false
    @State private var showVoice = false
    @ObservedObject private var voiceStore = VoiceChangerStore.shared

    var body: some View {
        List {
            Section {
                link(Tr("外观"),
                     app.appearance == "dark" ? Tr("深色")
                         : (app.appearance == "light" ? Tr("浅色") : Tr("跟随系统")),
                     key: "g.theme")
                link(Tr("字体与字号"),
                     fontSummary,
                     key: "g.font")
                link(Tr("界面语言"), Lang.name, key: "g.lang")
                link(Tr("聊天背景"),
                     (app.me?.chatBackground ?? "auto") == "auto" ? Tr("恢复默认") : Tr("自定义"),
                     key: "g.chatbg")
            }
            Section {
                link(Tr("存储空间"), "", key: "g.storage")
                link(Tr("聊天记录管理"), "", key: "g.history")
                link(Tr("语音变声"), voiceStore.current.name, key: "g.voice")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Tr("通用"))
        .hidesTabBar()
    }

    private func link(_ title: String, _ value: String, key: String) -> some View {
        NavigationLink {
            switch key {
            case "g.theme": AppearanceView()
            case "g.font": FontSettingsView()
            case "g.lang": LanguageView()
            case "g.chatbg": ChatBackgroundSheet()
            case "g.storage": StorageView()
            case "g.history": ChatHistoryView()
            case "g.voice": VoiceChangerView()
            default: EmptyView()
            }
        } label: {
            LabeledContent {
                Text(value)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } label: {
                Text(title)
                    .foregroundStyle(.primary)
            }
        }
    }

    private var fontSummary: String {
        let family = fontStore.family.isEmpty ? Tr("苹方 · 默认") : fontStore.family
        return family + " · \(Int(fontStore.scale * 100))%"
    }

    private func row(_ title: String, _ value: String, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            LabeledContent {
                Text(value)
                    .foregroundStyle(.secondary)
            } label: {
                Text(title)
                    .foregroundStyle(.primary)
            }
        }
    }

    private func setLang(_ code: String) {
        Lang.code = code
        app.show(code == "en" ? "Language switched to English" : "界面语言已切成中文")
        dismiss()

    }

    private func changeBg(_ image: UIImage) {
        Task {
            if let url = try? await API.shared.uploadOriginal(image: image) {
                await API.shared.changeBackground(url)
                app.me = try? await API.shared.me()
                app.show(Tr("聊天背景换好了"))
            }
        }
    }
}

struct AppearanceView: View {
    @ObservedObject private var lang = LangStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var systemColorScheme

    private var effectiveMode: String {
        if app.appearance == "auto" {
            return systemColorScheme == .dark ? "dark" : "light"
        }
        return app.appearance == "dark" ? "dark" : "light"
    }

    var body: some View {
        List {
            Section(header: Text(Tr("外观"))) {
                HStack(alignment: .top, spacing: 18) {
                    appearanceChoice(
                        mode: "light",
                        title: Tr("浅色"),
                        selected: effectiveMode == "light"
                    )
                    appearanceChoice(
                        mode: "dark",
                        title: Tr("深色"),
                        selected: effectiveMode == "dark"
                    )
                }
                .padding(.vertical, 8)
                .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 12, trailing: 20))
                .listRowBackground(Color.clear)
            }

            Section {
                Toggle(isOn: Binding(
                    get: { app.appearance == "auto" },
                    set: { automatic in
                        if automatic {
                            app.setAppearance("auto")
                        } else {
                            app.setAppearance(systemColorScheme == .dark ? "dark" : "light")
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Tr("自动"))
                        Text(Tr("根据 iPhone 的显示设置自动切换"))
                            .font(pfStyled(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text(Tr("选择浅色或深色会立即应用到整个 App；打开自动后，会跟随 iPhone 系统的外观设置。"))
            }

        }
        .listStyle(.insetGrouped)
        .navigationTitle(Tr("外观与显示"))
        .navigationBarTitleDisplayMode(.large)
        .hidesTabBar()
        .animation(.easeInOut(duration: 0.38), value: effectiveMode)
        .animation(.easeInOut(duration: 0.38), value: app.appearance)
    }

    private func appearanceChoice(mode: String, title: String, selected: Bool) -> some View {
        Button {
            app.setAppearance(mode)
        } label: {
            VStack(spacing: 9) {
                AppearanceHomePreview(dark: mode == "dark", selected: selected)
                HStack(spacing: 6) {
                    Text(title)
                        .font(pfStyled(size: 15))
                        .foregroundStyle(.primary)
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(selected ? Tr("已选择") : "")
    }
}

private struct AppearanceHomePreview: View {
    let dark: Bool
    let selected: Bool

    private var panel: Color {
        dark ? Color(white: 0.10) : Color(white: 0.97)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: 0x777A80),
                            Color(hex: 0x202126),
                            Color(hex: 0x4B4D52),
                            Color(hex: 0x111216)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color.white.opacity(0.28), lineWidth: 0.8)
                }

            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: dark
                            ? [Color(red: 0.10, green: 0.15, blue: 0.31),
                               Color(red: 0.02, green: 0.03, blue: 0.07)]
                            : [Color(red: 0.53, green: 0.74, blue: 0.98),
                               Color(red: 0.92, green: 0.96, blue: 1.00)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    LinearGradient(
                        colors: [Color.white.opacity(0.18), .clear, Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                }
                .padding(6)

            VStack(spacing: 8) {
                HStack {
                    Text("9:41")
                        .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                    Spacer()
                    HStack(spacing: 2.5) {
                        Image(systemName: "cellularbars")
                        Image(systemName: "wifi")
                        Image(systemName: "battery.75")
                    }
                    .font(.system(size: 6.5, weight: .semibold))
                }
                .foregroundStyle(dark ? Color.white : Color.black)
                .padding(.horizontal, 13)
                .padding(.top, 10)

                HStack {
                    previewWidget(icon: "clock.fill", tint: .orange)
                    previewWidget(icon: "calendar", tint: .red)
                }
                .padding(.horizontal, 10)
                HStack {
                    previewWidget(icon: "message.fill", tint: .green)
                    previewWidget(icon: "camera.fill", tint: .gray)
                }
                .padding(.horizontal, 10)

                HStack(spacing: 5) {
                    Circle().fill(Color.white.opacity(0.82))
                    Circle().fill(Color.white.opacity(0.38))
                }
                .frame(width: 17, height: 5)

                Spacer(minLength: 0)

                HStack(spacing: 9) {
                    miniAppIcon("message.fill", tint: .green)
                    miniAppIcon("person.2.fill", tint: .blue)
                    miniAppIcon("safari.fill", tint: .cyan)
                    miniAppIcon("person.crop.circle.fill", tint: .gray)
                }
                .padding(.horizontal, 10)
                .frame(height: 42)
                .background(panel.opacity(0.62),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 9)

                Capsule()
                    .fill(dark ? Color.white.opacity(0.78) : Color.black.opacity(0.68))
                    .frame(width: 39, height: 3)
                    .padding(.bottom, 6)
            }

            Capsule()
                .fill(Color.black)
                .frame(width: 35, height: 10)
                .offset(y: -105)

            VStack {
                HStack {
                    Capsule()
                        .fill(Color(hex: 0x3F4146))
                        .frame(width: 2.5, height: 19)
                        .offset(x: -1.2, y: -42)
                    Spacer()
                    Capsule()
                        .fill(Color(hex: 0x4A4C51))
                        .frame(width: 2.5, height: 30)
                        .offset(x: 1.2, y: -35)
                }
                Spacer()
            }
        }
        .frame(width: 128, height: 238)
        .overlay(alignment: .topTrailing) {
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.accentColor)
                    .padding(6)
            }
        }
        .shadow(color: Color.black.opacity(dark ? 0.30 : 0.18), radius: 11, y: 5)
    }

    private func previewWidget(icon: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(tint, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Capsule().fill(Color.primary.opacity(0.25)).frame(width: 26, height: 3)
                Capsule().fill(Color.primary.opacity(0.13)).frame(width: 18, height: 3)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .frame(height: 31)
        .background(panel.opacity(0.90), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func miniAppIcon(_ symbol: String, tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(tint.opacity(0.86))
            .frame(width: 19, height: 19)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}

struct LanguageView: View {
    @ObservedObject private var lang = LangStore.shared
    @EnvironmentObject var app: AppState

    private let options: [(code: String, name: String, detail: String)] = [
        ("zh", "简体中文", "Chinese"),
        ("en", "English", "English"),
        ("ru", "Русский", "Russian")
    ]

    var body: some View {
        List {
            Section {
                ForEach(options, id: \.code) { option in
                    Button {
                        setLanguage(option.code)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(option.name)
                                    .foregroundStyle(.primary)
                                Text(option.detail)
                                    .font(pfStyled(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if Lang.code == option.code {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                }
            } footer: {
                Text(Tr("切换后立即生效，已经打开的页面会在返回时刷新。"))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Tr("界面语言"))
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBar()
    }

    private func setLanguage(_ code: String) {
        guard Lang.code != code else { return }
        Lang.code = code
        switch code {
        case "en":
            app.show("Language switched to English")
        case "ru":
            app.show("Язык интерфейса переключён на русский")
        default:
            app.show("界面语言已切换为中文")
        }
    }
}

struct PrivacySettings: Equatable {
    var needVerify = true
    var strangerMoments = false
    var addByWx = true
    var addByPhone = true
    var addByGroup = true
    var addByQR = true

    var momentsRange = "all"
}

struct NotifySettings: Equatable {
    var on = true
    var sound = true
    var vibrate = true
    var showDetail = true
    var muteStart = ""
    var muteEnd = ""
}
