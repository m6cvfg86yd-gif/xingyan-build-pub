import SwiftUI

enum OfficialAccountVisual {
    static let name = LinearGradient(
        colors: [
            Color(hex: 0x25D366),
            Color(hex: 0x128C7E),
            Color(hex: 0x075E54)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let edge = LinearGradient(
        colors: [
            Color.white.opacity(0.82),
            Color(hex: 0x25D366).opacity(0.76),
            Color(hex: 0x128C7E).opacity(0.62),
            Color.black.opacity(0.18)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let glow = Color(hex: 0x25D366).opacity(0.22)
}

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
                                Color(hex: 0x25D366).opacity(scheme == .dark ? 0.30 : 0.42),
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
            Color(hex: 0x25D366),
            Color(hex: 0x128C7E)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    private let bevel = LinearGradient(
        colors: [
            Color.white.opacity(0.76),
            Color(hex: 0x9BE8B8).opacity(0.42),
            Color(hex: 0x25D366).opacity(0.30),
            Color.black.opacity(0.24)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        ZStack {
            Circle()
                .fill(face)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.16), Color.clear],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: size * 0.82
                    )
                )

            Text("V")
                .font(.system(size: size * 0.59, weight: .bold, design: .rounded))
                .foregroundStyle(
                    Color.white
                )
                .shadow(color: Color.black.opacity(0.22), radius: 0.5, x: 0, y: 0.45)
                .offset(y: -0.1)

            Circle()
                .strokeBorder(bevel, lineWidth: max(0.8, size * 0.075))

            Circle()
                .strokeBorder(Color.black.opacity(0.14), lineWidth: 0.4)
                .padding(size * 0.115)
        }
        .frame(width: size, height: size)
        .shadow(color: Color.black.opacity(0.13), radius: 1.7, x: 0, y: 0.9)
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
