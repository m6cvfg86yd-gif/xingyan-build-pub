import SwiftUI
import UIKit

struct HarmonyLoginView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @FocusState private var focus: Field?

    private enum Field: Hashable { case phone, code, user, pass }
    private enum Mode { case phone, password }

    @State private var mode: Mode = .phone
    @State private var phone = UserDefaults.standard.string(forKey: "chris.lastPhone") ?? ""
    @State private var code = ""
    @State private var user = ""
    @State private var pass = ""
    @State private var busy = false
    @State private var codeSent = false
    @State private var countdown = 0
    @State private var agreed = false
    @State private var message = ""
    @State private var hint = ""
    @State private var brandName = "星言"
    @State private var brandSubtitle = "让每一句真心，都有回应"
    @State private var logoPath = ""
    @State private var showPassword = false
    @State private var sliderTicket = ""
    @State private var sliderSeed = 0
    @State private var showSlider = false
    @State private var showReset = false
    @State private var showUnban = false
    @State private var showRegister = false
    @State private var showTerms = false
    @State private var termsKind = 0
    @State private var countdownTask: Task<Void, Never>?

    private var validPhone: Bool {
        phone.range(of: #"^1[3-9]\d{9}$"#, options: .regularExpression) != nil
    }

    private var canPrimary: Bool {
        guard agreed, !busy else { return false }
        switch mode {
        case .password:
            return !user.trimmingCharacters(in: .whitespaces).isEmpty && !pass.isEmpty
        case .phone:
            if !validPhone { return false }
            return !codeSent || code.count == 6
        }
    }

    private var primaryTitle: String {
        if busy { return "请稍候…" }
        if mode == .password || codeSent { return "登录" }
        return "获取验证码"
    }

    private var ink: Color { LoginTheme.ink(scheme) }
    private var subInk: Color { LoginTheme.inkSub(scheme) }
    private var accent: Color { Color(hex: 0x25D366) }
    private var fieldFill: Color {
        scheme == .dark ? Color(hex: 0x202C33) : Color(hex: 0xF0F2F5)
    }
    private var fieldStroke: Color {
        scheme == .dark ? Color(hex: 0x2A3942) : Color.clear
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.dyn(0xFFFFFF, 0x0B141A)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    brandArea
                    Spacer().frame(height: 30)

                    if mode == .phone {
                        phoneFields
                    } else {
                        passwordFields
                    }

                    Spacer().frame(height: 16)
                    actionArea
                    Spacer().frame(height: 22)
                    termsArea
                    Spacer(minLength: 28)
                }
                .padding(.horizontal, 24)
                .padding(.top, 54)
                .padding(.bottom, max(24, L.safeBottom))
            }
        }
        .background(LoginTheme.bg(scheme).ignoresSafeArea())
        .overlay {
            if busy {
                ZStack {
                    Color.black.opacity(0.08)
                        .ignoresSafeArea()
                    VStack(spacing: 10) {
                        ProgressView()
                            .tint(accent)
                        Text(Tr("正在进入星言…"))
                            .font(pfStyled(size: 13, weight: .medium))
                            .foregroundColor(ink)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .allowsHitTesting(true)
                .transition(.opacity)
            }
        }
        .onAppear { loadBranding() }
        .onDisappear { countdownTask?.cancel() }
        .sheet(isPresented: $showSlider) {
            SliderSheet(freshKey: sliderSeed) { ticket in
                sliderTicket = ticket
                showSlider = false
                primaryAction()
            }
        }
        .sheet(isPresented: $showReset) { ResetPasswordSheet() }
        .sheet(isPresented: $showUnban) {
            UnbanSheet(preUser: user, prePass: pass)
        }
        .sheet(isPresented: $showRegister) {
            RegisterSheet().environmentObject(app)
        }
        .sheet(isPresented: $showTerms) { TermsSheet(kind: termsKind) }
    }

    private var brandArea: some View {
        VStack(spacing: 9) {
            if let icon = AppIconImage.image {
                Image(uiImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 66, height: 66)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: Color.black.opacity(0.08), radius: 10, y: 5)
            } else {
                Image(systemName: "message.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 66, height: 66)
                    .background(accent)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            Text(brandName)
                .font(pfStyled(size: 27, weight: .semibold))
                .foregroundColor(ink)

            Text(brandSubtitle)
                .font(pfStyled(size: 13.5))
                .foregroundColor(subInk)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity)
    }

    private var phoneFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Tr("手机号"))
                .font(pfStyled(size: 13.5, weight: .medium))
                .foregroundColor(ink)

            HStack(spacing: 12) {
                Text("+86")
                    .font(pfStyled(size: 16.5, weight: .medium))
                    .foregroundColor(ink)
                Rectangle().fill(fieldStroke).frame(width: 0.7, height: 20)
                        TextField(Tr("请输入手机号"), text: $phone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .focused($focus, equals: .phone)
                    .font(pfStyled(size: 16.5))
                    .foregroundColor(ink)
                    .tint(accent)
                    .onChange(of: phone) { value in
                        phone = String(value.filter(\.isNumber).prefix(11))
                        message = ""
                    }
            }
            .frame(height: 54)
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(fieldFill))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(fieldStroke, lineWidth: 0.6))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if codeSent {
                HStack(spacing: 12) {
                        TextField(Tr("请输入 6 位验证码"), text: $code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .focused($focus, equals: .code)
                        .font(pfStyled(16.5))
                        .foregroundColor(ink)
                        .tint(accent)
                        .onChange(of: code) { value in
                            code = String(value.filter(\.isNumber).prefix(6))
                            message = ""
                        }
                    Button(countdown > 0 ? "\(countdown) 秒" : "重新获取") {
                        if countdown == 0 { requestCode() }
                    }
                    .font(pfStyled(13.5, .medium))
                    .foregroundColor(countdown > 0 ? subInk : accent)
                    .disabled(countdown > 0)
                }
                .frame(height: 54)
                .padding(.horizontal, 14)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(fieldFill))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(fieldStroke, lineWidth: 0.6))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
            .frame(maxWidth: 360)
    }

    private var passwordFields: some View {
        VStack(spacing: 10) {
            TextField(Tr("账号 / 星言号"), text: $user)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focus, equals: .user)
                .font(pfStyled(16.5))
                .foregroundColor(ink)
                .tint(accent)
                .padding(.horizontal, 14)
                .frame(height: 54)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(fieldFill))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(fieldStroke, lineWidth: 0.6))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack {
                Group {
                    if showPassword {
                        TextField(Tr("请输入密码"), text: $pass)
                    } else {
                        SecureField(Tr("请输入密码"), text: $pass)
                    }
                }
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .privacySensitive()
                .focused($focus, equals: .pass)
                .font(pfStyled(16.5))
                .foregroundColor(ink)
                .tint(accent)

                Button { showPassword.toggle() } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .foregroundColor(subInk)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .frame(height: 54)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(fieldFill))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(fieldStroke, lineWidth: 0.6))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .frame(maxWidth: 360)
    }

    private var actionArea: some View {
        VStack(spacing: 12) {
            Button { primaryAction() } label: {
                HStack(spacing: 8) {
                    if busy {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.82)
                    }
                    Text(primaryTitle)
                        .font(pfStyled(size: 17, weight: .medium))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(canPrimary ? accent : accent.opacity(0.34))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: 360)
            .disabled(busy)

            if !message.isEmpty {
                Text(message)
                    .font(pfStyled(size: 12.5))
                    .foregroundColor(C.red)
                    .frame(maxWidth: 360, alignment: .leading)
            } else if !hint.isEmpty {
                Text(hint)
                    .font(pfStyled(size: 12.5))
                    .foregroundColor(subInk)
                    .frame(maxWidth: 360, alignment: .leading)
            }

            Button { showRegister = true } label: {
                HStack(spacing: 7) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 15, weight: .medium))
                    Text(Tr("注册星言账号"))
                        .font(pfStyled(size: 14.5, weight: .medium))
                }
                .foregroundColor(accent)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(accent.opacity(0.72), lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: 360)

            HStack(spacing: 0) {
                Button(mode == .phone ? Tr("账号密码登录") : Tr("手机号登录")) {
                    mode = mode == .phone ? .password : .phone
                    sliderTicket = ""
                    message = ""
                    hint = ""
                    focus = nil
                }
                Spacer(minLength: 12)
                Button(Tr("找回密码")) { showReset = true }
                Text("·")
                    .foregroundColor(subInk.opacity(0.55))
                    .padding(.horizontal, 8)
                Button(Tr("自助解封")) { showUnban = true }
            }
            .font(pfStyled(13))
            .foregroundColor(subInk)
            .buttonStyle(.plain)
            .frame(maxWidth: 360)
        }
    }

    private var termsArea: some View {
        HStack(alignment: .center, spacing: 8) {
            Button { agreed.toggle() } label: {
                ZStack {
                    Circle()
                        .fill(agreed ? accent : fieldFill)
                        .overlay(Circle().stroke(agreed ? accent : fieldStroke, lineWidth: 1.3))
                    if agreed {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 18, height: 18)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(.init("我已阅读并同意 [《用户协议》](terms://0) 和 [《隐私政策》](terms://1)"))
                .font(pfStyled(size: 12.2))
                .foregroundColor(subInk)
                .tint(accent)
                .environment(\.openURL, OpenURLAction { url in
                    if url.scheme == "terms" {
                        termsKind = Int(url.host ?? "0") ?? 0
                        showTerms = true
                    }
                    return .handled
                })
        }
        .frame(maxWidth: 360, alignment: .leading)
    }

    private func loadBranding() {
        Task {
            guard let b = await API.shared.branding() else { return }

            let shared = b.harmonyLogin
            if let n = shared?.appName ?? b.login?.appName ?? b.appName, !n.isEmpty { brandName = n }
            if let s = shared?.subTitle ?? b.login?.subTitle, !s.isEmpty { brandSubtitle = s }
            if let l = shared?.logo ?? b.login?.logo ?? b.logo, !l.isEmpty { logoPath = l }
        }
    }

    private func requestCode() {
        guard agreed else {
            message = "请先阅读并同意用户协议和隐私政策"
            return
        }
        guard validPhone else {
            message = "请输入正确的 11 位手机号"
            return
        }
        busy = true
        message = ""
        hint = ""
        Task {
            do {
                let dev = try await API.shared.phoneCode(phone: phone,
                                                          sliderTicket: sliderTicket)
                sliderTicket = ""
                codeSent = true
                startCountdown()
                if let dev, !dev.isEmpty {
                    code = dev
                    hint = "开发环境验证码已自动填入"
                } else {
                    hint = "验证码已发送，5 分钟内有效"
                }
            } catch APIError.needSlider {
                sliderTicket = ""
                sliderSeed += 1
                showSlider = true
            } catch {
                message = (error as? APIError)?.errorDescription ?? "验证码没发出去"
            }
            busy = false
        }
    }

    private func primaryAction() {
        guard agreed else {
            message = "请先阅读并同意用户协议和隐私政策"
            return
        }
        if mode == .phone && !codeSent {
            requestCode()
        } else {
            login()
        }
    }

    private func login() {
        guard canPrimary, !busy else { return }
        busy = true
        message = ""
        focus = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
        Task { @MainActor in
            var entered = false
            do {
                if mode == .phone {
                    guard validPhone, code.count == 6 else {
                        throw APIError.message("请输入手机号和 6 位验证码")
                    }
                    try await app.login(phone: phone, code: code)
                    UserDefaults.standard.set(phone, forKey: "chris.lastPhone")
                } else {
                    let account = user.trimmingCharacters(in: .whitespaces)
                    guard !account.isEmpty, !pass.isEmpty else {
                        throw APIError.message("账号和密码都要填")
                    }
                    try await app.login(username: account, password: pass, sliderTicket: sliderTicket)
                }
                entered = true
            } catch APIError.needSlider {
                sliderTicket = ""
                sliderSeed += 1
                showSlider = true
            } catch {
                message = (error as? APIError)?.errorDescription ?? "登录失败"
            }
            /* 成功后保持遮罩，直到 RootView 已经切到主页；避免切页前还能重复点击。 */
            if !entered { busy = false }
        }
    }

    private func startCountdown() {
        countdownTask?.cancel()
        countdown = 60
        countdownTask = Task { @MainActor in
            while countdown > 0, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                countdown -= 1
            }
        }
    }
}
