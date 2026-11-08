import SwiftUI

/// 官方账号名称后的玻璃胶囊标识。
struct OfficialMark: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(Tr("官方"))
            .font(pf(10.5, .semibold))
            .foregroundColor(C.label.opacity(0.90))
            .padding(.horizontal, 7)
            .frame(height: 19)
            .background {
                ZStack {
                    Capsule(style: .continuous)
                        .fill(C.cardBg.opacity(scheme == .dark ? 0.30 : 0.44))
                    GlassBackground(shape: Capsule(style: .continuous),
                                    opacity: scheme == .dark ? 0.78 : 0.92,
                                    edgeAlpha: scheme == .dark ? 0.52 : 0.68,
                                    shadow: false,
                                    seed: 0.74,
                                    native: true)
                }
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(scheme == .dark ? 0.22 : 0.82),
                                C.green.opacity(scheme == .dark ? 0.22 : 0.30),
                                Color.white.opacity(scheme == .dark ? 0.12 : 0.58)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            }
            .shadow(color: Color.black.opacity(scheme == .dark ? 0.18 : 0.06),
                    radius: 2.5, x: 0, y: 1)
            .accessibilityLabel(Tr("官方账号"))
    }
}

/// 会话列表中官方号昵称后的渐变 V 认证标识。
struct OfficialVerifiedV: View {
    var size: CGFloat = 17

    private let face = LinearGradient(
        colors: [
            Color(hex: 0x07583C),
            Color(hex: 0x16A862),
            Color(hex: 0x38C978)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private let bevel = LinearGradient(
        colors: [
            Color.white.opacity(0.92),
            Color(hex: 0xB9F1CC).opacity(0.78),
            Color(hex: 0xE5C36D).opacity(0.62),
            Color.black.opacity(0.20)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.14))
                .offset(y: size * 0.055)

            Circle()
                .fill(face)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.25), Color.clear],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: size * 0.92
                    )
                )

            Ellipse()
                .fill(Color.white.opacity(0.20))
                .frame(width: size * 0.56, height: size * 0.23)
                .blur(radius: 0.55)
                .offset(x: -size * 0.06, y: -size * 0.27)

            Text("V")
                .font(.system(size: size * 0.62, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.white, Color(hex: 0xD8FFE7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: Color.black.opacity(0.30), radius: 0.7, x: 0, y: 0.55)
                .offset(y: -0.2)

            Circle()
                .strokeBorder(bevel, lineWidth: max(0.8, size * 0.075))

            Circle()
                .strokeBorder(Color.black.opacity(0.20), lineWidth: 0.45)
                .padding(size * 0.10)
        }
        .frame(width: size, height: size)
        .shadow(color: Color.black.opacity(0.16), radius: 2.2, x: 0, y: 1.2)
        .shadow(color: OrbitTheme.jade.opacity(0.18), radius: 3.4, x: 0, y: 1)
        .accessibilityLabel(Tr("官方账号"))
    }
}

extension Chat {
    var showsOfficialMark: Bool {
        !(oaId ?? "").isEmpty
            || oaDigest == true
            || !(bot ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
