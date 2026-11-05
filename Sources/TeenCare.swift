import SwiftUI

struct UmbrellaIcon: View {
    var color: Color
    var size: CGFloat = 24

    var body: some View {
        Canvas { ctx, sz in
            let w = sz.width, h = sz.height
            let domeH = h * 0.56

            var dome = Path()
            dome.move(to: CGPoint(x: 0, y: domeH))
            dome.addQuadCurve(to: CGPoint(x: w, y: domeH),
                              control: CGPoint(x: w / 2, y: -domeH * 0.75))
            dome.addQuadCurve(to: CGPoint(x: w * 0.75, y: domeH),
                              control: CGPoint(x: w * 0.875, y: domeH + h * 0.10))
            dome.addQuadCurve(to: CGPoint(x: w * 0.50, y: domeH),
                              control: CGPoint(x: w * 0.625, y: domeH + h * 0.10))
            dome.addQuadCurve(to: CGPoint(x: w * 0.25, y: domeH),
                              control: CGPoint(x: w * 0.375, y: domeH + h * 0.10))
            dome.addQuadCurve(to: CGPoint(x: 0, y: domeH),
                              control: CGPoint(x: w * 0.125, y: domeH + h * 0.10))
            dome.closeSubpath()
            ctx.fill(dome, with: .color(color))

            var stick = Path()
            stick.move(to: CGPoint(x: w / 2, y: domeH - h * 0.04))
            stick.addLine(to: CGPoint(x: w / 2, y: h * 0.84))
            stick.addQuadCurve(to: CGPoint(x: w * 0.33, y: h * 0.82),
                               control: CGPoint(x: w * 0.35, y: h * 0.99))
            ctx.stroke(stick, with: .color(color),
                       style: StrokeStyle(lineWidth: max(1.4, w * 0.075), lineCap: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct TeenModeView: View {
    @ObservedObject private var lang = LangStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var cfg: API.TeenStatus?
    @State private var loading = true

    @State private var ask: Ask?
    @State private var pin = ""
    @State private var showSetup = false
    @State private var showGuardian = false
    @State private var guardianDraft = ""

    @State private var guardianPin = ""

    private enum Ask: Equatable { case close, guardian, pay(Bool) }

    private let blocked: [(String, String)] = [
        ("feed", "视频号"), ("live", "直播"), ("games", "游戏"),
        ("nearby", "附近的人"), ("shake", "摇一摇"), ("search", "搜一搜")
    ]

    private var on: Bool { cfg?.enabled ?? false }
    private var hasPin: Bool { cfg?.hasPin ?? false }
    private var payAllowed: Bool { ((cfg?.scopes ?? [:])["pay"] ?? 0) != 0 }

    var body: some View {
        Form {
            if loading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.vertical, 36)
                }
            } else {
                if on { onPage } else { offPage }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(Tr("未成年人模式"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .hidesTabBar()
        .task { await load() }

        .fullScreenCover(isPresented: $showSetup) {
            TeenSetupWizard { await load() }
                .environmentObject(app)
        }

        .sheet(isPresented: $showGuardian) { guardianSheet }
        .alert(Tr("输入独立密码"), isPresented: Binding(
            get: { ask != nil },
            set: { if !$0 { ask = nil; pin = "" } }
        )) {
            TextField(Tr("4 位数字"), text: $pin).keyboardType(.numberPad)
            Button(Tr("取消"), role: .cancel) { ask = nil; pin = "" }
            Button(Tr("确定")) { confirm() }
        } message: {
            Text(Tr("未成年人模式的开关和设置都要这个密码"))
        }
    }

    @ViewBuilder
    private var offPage: some View {
        Section {
            VStack(spacing: 12) {
                UmbrellaIcon(color: Color(hex: 0x3E9BF0), size: 58)
                Text(Tr("未成年人模式"))
                    .font(pfStyled(size: 20, weight: .semibold))
                Text(Tr("开启后，视频号、直播、游戏、附近的人、摇一摇、搜一搜将不可访问；\n微信支付、公众号、小程序可以按需要调整。"))
                    .font(pfStyled(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }

        Section {
            LabeledContent(Tr("使用条款"), value: Tr("阅读并同意"))
            LabeledContent(Tr("独立密码"), value: Tr("4 位数字"))
            LabeledContent(Tr("监护人"), value: Tr("选填"))
        } header: {
            Text(Tr("开启流程"))
        }

        Section {
            Button {
                showSetup = true
            } label: {
                Text(Tr("开启未成年人模式"))
                    .font(pfStyled(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        } footer: {
            Text(Tr("忘了独立密码：可以让监护人在「监护人」里帮你重置。"))
        }
    }

    @ViewBuilder
    private var onPage: some View {
        Section {
            VStack(spacing: 10) {
                UmbrellaIcon(color: Color(hex: 0x3E9BF0), size: 44)
                Text(Tr("未成年人模式已开启"))
                    .font(pfStyled(size: 17, weight: .semibold))
                Text(Tr("「我」页会显示一把小雨伞"))
                    .font(pfStyled(size: 13))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }

        Section {
            Button { askPin(.guardian) } label: {
                HStack {
                    Text(Tr("监护人"))
                    Spacer()
                    Text((cfg?.guardianPhone?.isEmpty == false) ? cfg!.guardianPhone! : Tr("未设置"))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            LabeledContent(Tr("使用时长"), value: Tr("每天 40 分钟"))
            LabeledContent(Tr("宵禁"), value: Tr("22:00 - 次日 6:00"))
        }

        Section {
            ForEach(Array(blocked.enumerated()), id: \.offset) { _, it in
                HStack {
                    Text(Tr(it.1))
                    Spacer()
                    Text(Tr("已限制"))
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(Tr("不可访问"))
        }

        Section {
            Toggle(Tr("微信支付"), isOn: Binding(
                get: { payAllowed },
                set: { v in askPin(.pay(v)) }
            ))
            .tint(C.green)
        } header: {
            Text(Tr("可以按需要调整"))
        }

        Section {
            Button(role: .destructive) { askPin(.close) } label: {
                Text(Tr("关闭未成年人模式"))
                    .frame(maxWidth: .infinity)
            }
        } footer: {
            Text(Tr("关闭、改设置、换监护人都要独立密码；忘了可以让监护人在后台重置。"))
        }
    }

    private func row(_ title: String, _ value: String, chevron: Bool,
                     _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 8) {
                Text(title).font(pf(16)).foregroundColor(C.label)
                Spacer(minLength: 8)
                Text(value).font(pf(14.5)).foregroundColor(C.subLabel).lineLimit(1)
                if chevron { Chevron(size: 8, line: 1.5) }
            }
            .padding(.horizontal, 16).frame(height: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var guardianSheet: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("监护人"), back: { showGuardian = false }) {
                Button { Task { await saveGuardian() } } label: {
                    Text(Tr("保存")).font(pf(16)).foregroundColor(C.green).padding(.trailing, 16)
                }
                .buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(Tr("监护人的手机号")).font(pf(15)).foregroundColor(C.label)
                TextField(Tr("填家长手机号"), text: $guardianDraft)
                    .font(pf(16))
                    .keyboardType(.numberPad)
                    .padding(.horizontal, 12).frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(C.searchBg))
                Text(Tr("只保存脱敏后的号码（如 138****8888），不会外发。"))
                    .font(pf(12)).foregroundColor(C.subLabel)
            }
            .padding(16)
            .background { CardGlassBox(radius: 14) }
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(C.hairline, lineWidth: 0.6))
            .padding(.horizontal, 14).padding(.top, 10)
            Spacer(minLength: 0)
        }
        .background(C.pageBg.ignoresSafeArea())

        .swipeBack { showGuardian = false }
        .onAppear {

            guardianDraft = ""
        }
    }

    private func load() async {
        cfg = try? await API.shared.teen()
        loading = false
    }

    private func askPin(_ what: Ask) {
        guard hasPin else { app.show(Tr("先开启未成年人模式（会设一个独立密码）")); return }
        pin = ""
        ask = what
    }

    private func confirm() {
        let p = pin.trimmingCharacters(in: .whitespaces)
        guard p.count == 4 else { app.show(Tr("密码要 4 位数字")); ask = nil; return }
        guard let what = ask else { return }
        ask = nil
        pin = ""
        Task {
            do {
                switch what {
                case .close:
                    cfg = try await API.shared.teenSet(pin: p, enabled: false, scopes: nil, guardianPhone: nil)
                    app.show(Tr("已关闭未成年人模式"))
                case .guardian:

                    _ = try await API.shared.teenSet(pin: p, enabled: nil, scopes: nil, guardianPhone: nil)
                    guardianPin = p
                    guardianDraft = ""
                    showGuardian = true
                case .pay(let v):
                    cfg = try await API.shared.teenSet(pin: p, enabled: nil, scopes: ["pay": v ? 1 : 0],
                                                       guardianPhone: nil)
                    app.show(v ? Tr("微信支付已放开") : Tr("微信支付已限制"))
                }
            } catch {
                app.show((error as? LocalizedError)?.errorDescription ?? Tr("操作失败"))
            }
        }
    }

    private func saveGuardian() async {
        let ph = guardianDraft.trimmingCharacters(in: .whitespaces)
        do {
            cfg = try await API.shared.teenSet(pin: guardianPin, enabled: nil, scopes: nil, guardianPhone: ph)
            app.show(ph.isEmpty ? Tr("已清空监护人") : Tr("监护人已保存"))
            showGuardian = false
        } catch {
            app.show((error as? LocalizedError)?.errorDescription ?? Tr("保存失败"))
        }
    }
}

struct TeenSetupWizard: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    var onDone: () async -> Void

    @State private var step = 0
    @State private var agreed = false
    @State private var pin = ""
    @State private var pin2 = ""
    @State private var phone = ""
    @State private var busy = false
    @State private var error = ""

    private let terms = """
    未成年人模式使用条款

    1. 未成年人模式用于帮助家长管理青少年的使用范围与时长。
    2. 开启后，视频号、直播、游戏、附近的人、摇一摇、搜一搜将不可访问；
       微信支付、公众号、小程序可以按家长需要调整。
    3. 开启后需要设置一个 4 位独立密码，关闭或修改设置都要输入这个密码。
    4. 独立密码只保存在你自己的服务器上（加盐哈希，服务端也看不到原文）。
    5. 忘记密码时，可以由已绑定的监护人在「监护人」里重置。
    """

    var body: some View {
        NavigationStack {
            Form {
                switch step {
                case 0: termsStep
                case 1: pinStep
                default: guardianStep
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(Tr("未成年人模式"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Tr("取消")) { dismiss() }
                        .disabled(busy)
                }
            }
            .interactiveDismissDisabled(busy)
        }
    }

    @ViewBuilder
    private var termsStep: some View {
        Section {
            VStack(spacing: 10) {
                UmbrellaIcon(color: Color(hex: 0x3E9BF0), size: 48)
                Text(Tr("请先阅读并同意使用条款"))
                    .font(pfStyled(size: 17, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)

            Text(terms)
                .font(pfStyled(size: 13))
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        Section {
            Toggle(isOn: $agreed) {
                Text(Tr("我已阅读并同意《未成年人模式使用条款》"))
            }
            .tint(C.green)
        }

        Section {
            Button(Tr("下一步")) { step = 1 }
                .frame(maxWidth: .infinity)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!agreed)
        }
    }

    @ViewBuilder
    private var pinStep: some View {
        Section {
            LabeledContent(Tr("密码")) {
                secureField($pin)
            }
            LabeledContent(Tr("确认密码")) {
                secureField($pin2)
            }
        } header: {
            Text(Tr("设置独立密码"))
        } footer: {
            Text(Tr("之后关闭未成年人模式、改设置都要输这个密码"))
        }

        if !error.isEmpty {
            Section {
                Text(error)
                    .font(pfStyled(size: 13))
                    .foregroundStyle(.red)
            }
        }

        Section {
            Button(Tr("下一步")) {
                guard pin == pin2 else { error = Tr("两次输入的密码不一样"); return }
                error = ""
                step = 2
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(pin.count != 4 || pin2.count != 4)
        }
    }

    @ViewBuilder
    private var guardianStep: some View {
        Section {
            LabeledContent(Tr("监护人手机号")) {
                TextField(Tr("选填"), text: $phone)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numberPad)
            }
        } header: {
            Text(Tr("邀请家长作为监护人"))
        } footer: {
            Text(Tr("家长可以帮你重置独立密码。"))
        }

        if !error.isEmpty {
            Section {
                Text(error)
                    .font(pfStyled(size: 13))
                    .foregroundStyle(.red)
            }
        }

        Section {
            Button(busy ? Tr("开启中…") : Tr("完成并开启")) {
                Task { await finish() }
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(busy)

            Button(Tr("先跳过，稍后再邀请")) {
                phone = ""
                Task { await finish() }
            }
            .frame(maxWidth: .infinity)
            .disabled(busy)
        }
    }

    private func secureField(_ b: Binding<String>) -> some View {
        SecureField(Tr("4 位数字"), text: b)
            .multilineTextAlignment(.trailing)
            .keyboardType(.numberPad)
            .frame(width: 110)
    }

    private func bigButton(_ title: String, enabled: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(title)
                .font(pf(17, .medium)).foregroundColor(.white)
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(enabled ? C.green : C.green.opacity(0.4)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func finish() async {
        busy = true
        error = ""
        do {
            _ = try await API.shared.teenSetup(pin: pin)
            let ph = phone.trimmingCharacters(in: .whitespaces)
            if !ph.isEmpty {
                _ = try await API.shared.teenSet(pin: pin, enabled: nil, scopes: nil, guardianPhone: ph)
            }
            await onDone()
            app.show(Tr("未成年人模式已开启"))
            dismiss()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? Tr("开启失败，再试一次")
        }
        busy = false
    }
}

struct CareModeView: View {
    @ObservedObject private var lang = LangStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var on = CareMode.on

    @State private var speak = CareMode.speakText
    @State private var confirm = false

    var body: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "figure.wave")
                        .font(.system(size: 44))
                        .foregroundStyle(C.green)
                    Text(Tr("关怀模式"))
                        .font(pfStyled(size: 20, weight: .semibold))
                    HStack(spacing: 18) {
                        perk("textformat.size", Tr("文字更大"))
                        perk("paintpalette.fill", Tr("色彩更强"))
                        perk("hand.tap.fill", Tr("按钮更大"))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section {
                Toggle(Tr("开启关怀模式"), isOn: Binding(
                    get: { on },
                    set: { v in confirm = true; pending = v }
                ))
                .tint(C.green)
            } footer: {
                Text(Tr("只改这台手机上的显示，不影响别人；关掉就恢复原来的字号。"))
            }

            Section {
                HStack(spacing: 10) {
                    Avatar(path: app.me?.avatarPath ?? "", size: on ? 34 : 30, radius: 5)
                    Text(Tr("这条消息开了关怀模式会更大"))
                        .font(on ? .system(size: 19) : .system(size: 16))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                        )
                    Spacer(minLength: 0)
                }
                HStack {
                    Text(Tr("通讯录"))
                    Spacer()
                    Text(Tr("星标朋友"))
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(Tr("效果预览"))
            }

            Section {
                Toggle(Tr("听文字消息"), isOn: Binding(
                    get: { speak },
                    set: { v in
                        speak = v
                        CareMode.setSpeak(v)
                        if v && !on { app.show(Tr("建议把关怀模式一起打开")) }
                    }
                ))
                .tint(C.green)
            } footer: {
                Text(Tr("开启后，点一下聊天里的文字消息就会读出来。"))
            }

            Section {
                Text(Tr("关怀模式由微信首创的适老化设计：文字更大、色彩更强、按钮更大。"))
                    .font(pfStyled(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(Tr("关怀模式"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .hidesTabBar()

        .alert(on ? Tr("关闭关怀模式？") : Tr("开启关怀模式？"), isPresented: $confirm) {
            Button(Tr("取消"), role: .cancel) { pending = on }
            Button(Tr("确定")) {
                on = pending
                CareMode.set(on)
                app.show(on ? Tr("关怀模式已开启") : Tr("关怀模式已关闭"))
            }
        } message: {
            Text(on ? Tr("关闭后文字、图标、按钮会恢复原来的大小。")
                    : Tr("开启后文字更大、色彩更强、按钮更大，立刻生效。"))
        }
    }

    @State private var pending = CareMode.on

    private func perk(_ icon: String, _ title: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(C.green)
            Text(title)
                .font(pfStyled(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}
