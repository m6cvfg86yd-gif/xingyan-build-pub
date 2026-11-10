import SwiftUI
import UIKit

private struct OnboardingFeature: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let detail: String

    static let all: [OnboardingFeature] = [
        .init(id: "chat", symbol: "bubble.left.and.bubble.right.fill",
              title: "聊天与通话", detail: "单聊、群聊、语音和视频通话"),
        .init(id: "discover", symbol: "safari.fill",
              title: "动态与服务", detail: "朋友圈、视频号、小程序和常用服务"),
        .init(id: "security", symbol: "lock.shield.fill",
              title: "账号与安全", detail: "登录设备、隐私权限和安全设置可随时管理")
    ]
}

struct NewUserOnboardingView: View {
    @EnvironmentObject private var app: AppState
    @State private var step = 0
    @State private var avatar: UIImage?
    @State private var avatarPath = ""
    @State private var showPicker = false
    @State private var uploading = false
    @State private var saving = false
    @State private var error = ""
    @State private var appeared = false

    var body: some View {
        ZStack {
            onboardingBackground

            VStack(spacing: 0) {
                heading

                Group {
                    if step == 0 {
                        avatarStep
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)))
                    } else {
                        welcomeStep
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                bottomAction
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, max(16, L.safeBottom))
        }
        .sheet(isPresented: $showPicker) {
            PhotoPicker { image in
                avatar = image
                uploadAvatar(image)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.45)) { appeared = true }
        }
    }

    private var onboardingBackground: some View {
        Color.dyn(0xFFFFFF, 0x0B141A).ignoresSafeArea()
    }

    private var heading: some View {
        HStack {
            HStack(spacing: 7) {
                ZStack {
                    Circle().fill(LinearGradient(
                        colors: [Color(hex: 0x25D366), Color(hex: 0x1FAA59)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(width: 28, height: 28)
                Text("Star chat")
                    .font(pfStyled(size: 16, weight: .semibold))
                    .foregroundColor(C.label)
            }
            Spacer()
            HStack(spacing: 7) {
                ForEach(0..<2, id: \.self) { index in
                    Capsule()
                        .fill(index <= step
                              ? LinearGradient(colors: [Color(hex: 0x25D366), Color(hex: 0x1FAA59)],
                                               startPoint: .leading, endPoint: .trailing)
                              : LinearGradient(colors: [C.subLabel.opacity(0.18), C.subLabel.opacity(0.18)],
                                               startPoint: .leading, endPoint: .trailing))
                        .frame(width: index == step ? 28 : 12, height: 5)
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: step)
                }
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -10)
    }

    private var avatarStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                Text(Tr("完善个人资料"))
                    .font(pfStyled(size: 30, weight: .bold))
                    .foregroundColor(C.label)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 44)
                Text(Tr("设置一张清晰头像，方便联系人和群成员识别你。"))
                    .font(pfStyled(size: 14.5))
                    .foregroundColor(C.subLabel)
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 12)

                Button { showPicker = true } label: {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color(hex: 0x25D366), Color(hex: 0x1FAA59)],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 172, height: 172)
                            .shadow(color: Color(hex: 0x25D366).opacity(0.16), radius: 14, y: 7)

                        if let avatar {
                            Image(uiImage: avatar)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 158, height: 158)
                                .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(Color.dyn(0xFFFFFF, 0x232326))
                                .frame(width: 158, height: 158)
                            VStack(spacing: 10) {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 48, weight: .light))
                                    .foregroundColor(C.subLabel.opacity(0.62))
                                if uploading {
                                    ProgressView().tint(Color(hex: 0x25D366))
                                } else {
                                    Label(Tr("选择头像"), systemImage: "camera.fill")
                                        .font(pfStyled(size: 13, weight: .medium))
                                        .foregroundColor(Color(hex: 0x25D366))
                                }
                            }
                        }

                        if avatar != nil && !uploading {
                            VStack {
                                Spacer()
                                HStack {
                                    Spacer()
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white)
                                        .frame(width: 38, height: 38)
                                        .background(Circle().fill(Color.black.opacity(0.58)))
                                        .overlay(Circle().stroke(Color.white.opacity(0.7), lineWidth: 1))
                                        .offset(x: -5, y: -5)
                                }
                            }
                            .frame(width: 172, height: 172)
                        }
                    }
                    .padding(.top, 48)
                }
                .buttonStyle(OnboardingPressStyle())
                .disabled(uploading)

                Text(avatar == nil ? Tr("点击上传你的专属头像") : Tr("头像已就绪，可以继续了"))
                    .font(pfStyled(size: 13.5, weight: .medium))
                    .foregroundColor(avatar == nil ? C.subLabel : Color(hex: 0x18A66A))
                    .padding(.top, 22)

                if !error.isEmpty {
                    Text(error)
                        .font(pfStyled(size: 13))
                        .foregroundColor(C.red)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                }

                Text(Tr("建议使用本人照片或能代表你的头像\n之后可以在「我 → 个人资料」里更换"))
                    .font(pfStyled(size: 12.5))
                    .foregroundColor(C.subLabel.opacity(0.82))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.top, 24)
            }
        }
    }

    private var welcomeStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text(Tr("欢迎开始使用"))
                    .font(pfStyled(size: 30, weight: .bold))
                    .foregroundColor(C.label)
                    .padding(.top, 36)
                Text(Tr("账号已经创建。下面是星言的主要功能，进入后可随时在「发现」和「我」中找到。"))
                    .font(pfStyled(size: 14.5))
                    .foregroundColor(C.subLabel)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 11)

                VStack(spacing: 0) {
                    ForEach(OnboardingFeature.all) { feature in
                        featureCard(feature)
                    }
                }
                .background(Color.dyn(0xFFFFFF, 0x111B21))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(C.hairline, lineWidth: 0.5))
                .padding(.top, 26)

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color(hex: 0x25D366))
                        .padding(.top, 1)
                    Text(Tr("头像和资料之后可在「我 → 个人信息」中修改；登录设备与隐私权限在「我 → 设置」中管理。"))
                        .font(pfStyled(size: 12.5))
                        .foregroundColor(C.subLabel)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Color(hex: 0x25D366).opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(Color(hex: 0x25D366).opacity(0.16), lineWidth: 0.7)
                )
                .padding(.top, 18)
                .padding(.bottom, 18)
            }
        }
    }

    private func featureCard(_ feature: OnboardingFeature) -> some View {
        HStack(spacing: 13) {
            Image(systemName: feature.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Color(hex: 0x25D366))
                .frame(width: 42, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(hex: 0x25D366).opacity(0.10))
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(Tr(feature.title))
                    .font(pfStyled(size: 15.5, weight: .semibold))
                    .foregroundColor(C.label)
                Text(Tr(feature.detail))
                    .font(pfStyled(size: 12.5))
                    .foregroundColor(C.subLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 72)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(C.hairline)
                .frame(height: 0.5)
                .padding(.leading, 69)
        }
    }

    private var bottomAction: some View {
        VStack(spacing: 13) {
            if !error.isEmpty && step == 1 {
                Text(error)
                    .font(pfStyled(size: 13))
                    .foregroundColor(C.red)
            }

            Button {
                if step == 0 {
                    guard !avatarPath.isEmpty else {
                        error = uploading ? Tr("头像正在上传，请稍候") : Tr("请先选择一张头像")
                        return
                    }
                    error = ""
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { step = 1 }
                } else {
                    finish()
                }
            } label: {
                HStack(spacing: 8) {
                    if saving {
                        ProgressView().tint(.white)
                    }
                    Text(step == 0 ? Tr("继续") : saving ? Tr("正在完成设置…") : Tr("完成，进入星言"))
                        .font(pfStyled(size: 16, weight: .semibold))
                    if step == 0 && !saving {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .bold))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    Capsule().fill(LinearGradient(
                        colors: canContinue
                              ? [Color(hex: 0x25D366), Color(hex: 0x1FAA59)]
                              : [C.subLabel.opacity(0.28), C.subLabel.opacity(0.28)],
                        startPoint: .leading, endPoint: .trailing))
                )
                .shadow(color: canContinue ? Color(hex: 0x25D366).opacity(0.18) : .clear,
                        radius: 16, y: 8)
            }
            .buttonStyle(OnboardingPressStyle())
            .disabled(saving || uploading)

            if step == 1 {
                Button {
                    error = ""
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) { step = 0 }
                } label: {
                    Text(Tr("返回上一步"))
                        .font(pfStyled(size: 13))
                        .foregroundColor(C.subLabel)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 14)
    }

    private var canContinue: Bool {
        if step == 0 { return !avatarPath.isEmpty && !uploading && !saving }
        return !saving
    }

    private func uploadAvatar(_ image: UIImage) {
        uploading = true
        error = ""
        Task {
            do {
                let path = try await API.shared.upload(image: image)
                await MainActor.run {
                    avatarPath = path
                    uploading = false
                }
            } catch {
                await MainActor.run {
                    avatar = nil
                    avatarPath = ""
                    uploading = false
                    self.error = (error as? APIError)?.errorDescription ?? Tr("头像上传失败，请重试")
                }
            }
        }
    }

    private func finish() {
        guard !saving else { return }
        saving = true
        error = ""
        Task {
            do {
                try await app.finishNewUserOnboarding(avatar: avatarPath, interests: [])
                await MainActor.run {
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    saving = false
                }
            } catch {
                await MainActor.run {
                    saving = false
                    self.error = (error as? APIError)?.errorDescription ?? Tr("保存失败，请重试")
                }
            }
        }
    }
}

private struct OnboardingPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
