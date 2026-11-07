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

    private let gradient = LinearGradient(
        colors: [
            Color(hex: 0x20C96B),
            Color(hex: 0xA7D96A),
            Color(hex: 0xD9B95F)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.dyn(0xF7FFF9, 0x101A15).opacity(0.96))

            Text("V")
                .font(.system(size: size * 0.61, weight: .black, design: .rounded))
                .foregroundStyle(gradient)
                .offset(y: -0.15)

            Circle()
                .strokeBorder(gradient, lineWidth: 0.9)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.30), Color.clear],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: size * 0.75
                    )
                )
                .allowsHitTesting(false)
        }
        .frame(width: size, height: size)
        .shadow(color: OrbitTheme.jade.opacity(0.20), radius: 2.5, x: 0, y: 1)
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
