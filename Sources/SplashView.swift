import SwiftUI

struct SplashView: View {
    var remote: String = ""

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reveal = false
    @State private var orbiting = false
    @State private var breathing = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                StarLaunchBackdrop(remote: remote)

                Text("星")
                    .font(.system(size: min(270, geo.size.width * 0.72),
                                  weight: .black, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.018))
                    .rotationEffect(.degrees(-8))
                    .offset(x: geo.size.width * 0.34, y: -geo.size.height * 0.05)
                    .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(hex: 0x6CE65A))
                            .frame(width: 5, height: 5)
                            .shadow(color: Color(hex: 0x6CE65A).opacity(0.7), radius: 4)
                        Text("XINGYAN  /  ORBIT SYSTEM")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .tracking(1.7)
                            .foregroundStyle(Color.white.opacity(0.48))
                        Spacer(minLength: 0)
                        Text("01")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.24))
                    }
                    .opacity(reveal ? 1 : 0)
                    .offset(y: reveal ? 0 : -8)

                    Spacer(minLength: 0)

                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("星言")
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .tracking(1.5)
                                .foregroundStyle(.white)

                            HStack(spacing: 9) {
                                Capsule()
                                    .fill(Color(hex: 0x6CE65A).opacity(0.72))
                                    .frame(width: 28, height: 1.2)
                                Text("XINGYAN")
                                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                    .tracking(4.6)
                                    .foregroundStyle(Color.white.opacity(0.55))
                            }

                            Text("让连接有自己的轨道")
                                .font(.system(size: 13, weight: .medium))
                                .tracking(0.7)
                                .foregroundStyle(Color.white.opacity(0.70))
                        }
                        .offset(x: reveal ? 0 : -18)
                        .opacity(reveal ? 1 : 0)

                        Spacer(minLength: 0)

                        StarLaunchMark(
                            size: min(112, max(90, geo.size.width * 0.26)),
                            orbiting: orbiting,
                            breathing: breathing
                        )
                        .scaleEffect(reveal ? 1 : 0.88)
                        .opacity(reveal ? 1 : 0)
                    }

                    Spacer(minLength: 46)

                    HStack(spacing: 8) {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(Color(hex: 0x6CE65A))
                                .frame(width: 5, height: 5)
                                .shadow(color: Color(hex: 0x6CE65A).opacity(0.65), radius: 4)
                            Text("正在连接星轨")
                                .font(.system(size: 10.5, weight: .medium))
                                .tracking(0.45)
                                .foregroundStyle(Color.white.opacity(0.66))
                        }
                        .padding(.horizontal, 13)
                        .frame(height: 32)
                        .background(Capsule().fill(.ultraThinMaterial))
                        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.6))

                        Spacer(minLength: 0)
                        Text("PRIVATE · SECURE · PRESENT")
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                            .tracking(1.15)
                            .foregroundStyle(Color.white.opacity(0.26))
                    }
                    .opacity(reveal ? 1 : 0)
                }
                .padding(.horizontal, 28)
                .padding(.top, max(22, L.safeTop + 10))
                .padding(.bottom, max(26, L.safeBottom + 18))
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("星言"))
        .onAppear {
            withAnimation(.easeOut(duration: 0.58)) {
                reveal = true
            }
            guard !reduceMotion else { return }
            orbiting = true
            breathing = true
        }
    }
}

struct StarLaunchBackdrop: View {
    var remote: String = ""

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(hex: 0x040806)

                if !remote.isEmpty {
                    RemoteImage(path: remote, mode: .fill, maxSide: 1600)
                        .frame(width: geo.size.width * 1.18,
                               height: geo.size.height * 1.10)
                        .blur(radius: 72, opaque: false)
                        .saturation(1.16)
                        .opacity(0.22)
                        .blendMode(.screen)
                        .clipped()
                }

                RadialGradient(
                    colors: [
                        Color(hex: 0x2F9B5E).opacity(0.25),
                        Color(hex: 0x0C3B27).opacity(0.12),
                        Color.clear
                    ],
                    center: UnitPoint(x: 0.52, y: 0.40),
                    startRadius: 6,
                    endRadius: max(geo.size.width, geo.size.height) * 0.68
                )

                Ellipse()
                    .stroke(
                        Color(hex: 0xB8FFD2).opacity(0.09),
                        style: StrokeStyle(lineWidth: 0.8, dash: [3, 8])
                    )
                    .frame(width: geo.size.width * 1.42,
                           height: geo.size.width * 0.54)
                    .rotationEffect(.degrees(-19))
                    .offset(x: geo.size.width * 0.05,
                            y: -geo.size.height * 0.15)

                Ellipse()
                    .stroke(Color(hex: 0x6CE65A).opacity(0.10), lineWidth: 0.7)
                    .frame(width: geo.size.width * 0.92,
                           height: geo.size.width * 0.34)
                    .rotationEffect(.degrees(18))
                    .offset(x: -geo.size.width * 0.20,
                            y: geo.size.height * 0.18)

                StarLaunchField()

                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(0.04), location: 0),
                        .init(color: Color.black.opacity(0.08), location: 0.56),
                        .init(color: Color.black.opacity(0.46), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
    }
}

private struct StarLaunchField: View {
    private let stars: [(x: CGFloat, y: CGFloat, radius: CGFloat, alpha: Double)] = [
        (0.08, 0.12, 1.1, 0.48),
        (0.19, 0.28, 0.8, 0.28),
        (0.31, 0.09, 1.4, 0.56),
        (0.47, 0.21, 0.7, 0.26),
        (0.61, 0.13, 1.0, 0.40),
        (0.78, 0.24, 1.7, 0.54),
        (0.91, 0.11, 0.8, 0.30),
        (0.12, 0.57, 0.8, 0.24),
        (0.27, 0.70, 1.2, 0.32),
        (0.44, 0.52, 0.7, 0.22),
        (0.68, 0.62, 1.4, 0.35),
        (0.84, 0.48, 0.8, 0.26),
        (0.92, 0.73, 1.1, 0.30),
        (0.18, 0.88, 0.7, 0.22),
        (0.52, 0.84, 1.0, 0.28),
        (0.76, 0.91, 0.8, 0.24)
    ]

    var body: some View {
        Canvas { context, size in
            for star in stars {
                let rect = CGRect(
                    x: size.width * star.x - star.radius,
                    y: size.height * star.y - star.radius,
                    width: star.radius * 2,
                    height: star.radius * 2
                )
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(Color.white.opacity(star.alpha))
                )
            }
        }
        .allowsHitTesting(false)
    }
}

struct StarLaunchMark: View {
    let size: CGFloat
    let orbiting: Bool
    let breathing: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: 0x66EA58).opacity(0.30),
                            Color(hex: 0x2EBE78).opacity(0.08),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 4,
                        endRadius: size * 0.70
                    )
                )
                .frame(width: size * 1.42, height: size * 1.42)
                .scaleEffect(breathing ? 1.05 : 0.95)
                .animation(
                    .easeInOut(duration: 1.9).repeatForever(autoreverses: true),
                    value: breathing
                )

            Ellipse()
                .trim(from: 0.03, to: 0.76)
                .stroke(
                    Color(hex: 0xC8FFD2).opacity(0.50),
                    style: StrokeStyle(lineWidth: 1.05, lineCap: .round, dash: [3, 7])
                )
                .frame(width: size * 1.44, height: size * 0.52)
                .rotationEffect(.degrees(orbiting ? 338 : -22))
                .animation(
                    .linear(duration: 7.5).repeatForever(autoreverses: false),
                    value: orbiting
                )

            Ellipse()
                .trim(from: 0.45, to: 0.94)
                .stroke(
                    Color(hex: 0x7CECA1).opacity(0.35),
                    style: StrokeStyle(lineWidth: 0.85, lineCap: .round)
                )
                .frame(width: size * 1.10, height: size * 0.38)
                .rotationEffect(.degrees(orbiting ? 386 : 26))
                .animation(
                    .linear(duration: 9.5).repeatForever(autoreverses: false),
                    value: orbiting
                )

            if let icon = AppIconImage.image {
                Image(uiImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * 0.70, height: size * 0.70)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: size * 0.70 * 0.23,
                            style: .continuous
                        )
                    )
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: size * 0.70 * 0.23,
                            style: .continuous
                        )
                        .stroke(Color.white.opacity(0.22), lineWidth: 0.9)
                    }
                    .shadow(color: Color(hex: 0x62E65A).opacity(0.30),
                            radius: size * 0.20,
                            y: size * 0.06)
            } else {
                RoundedRectangle(cornerRadius: size * 0.20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x9BFF74), Color(hex: 0x29A64D)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size * 0.70, height: size * 0.70)
                    .overlay {
                        HStack(spacing: size * 0.075) {
                            Capsule().fill(Color(hex: 0x07150D))
                                .frame(width: size * 0.055, height: size * 0.15)
                            Capsule().fill(Color(hex: 0x07150D))
                                .frame(width: size * 0.055, height: size * 0.15)
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: size * 0.20, style: .continuous)
                            .stroke(Color.white.opacity(0.20), lineWidth: 0.9)
                    }
            }

            Circle()
                .fill(Color(hex: 0xE8FFE5))
                .frame(width: 4.5, height: 4.5)
                .shadow(color: Color(hex: 0x8FFF8C).opacity(0.8), radius: 4)
                .offset(x: size * 0.62, y: -size * 0.09)
        }
        .frame(width: size * 1.55, height: size * 1.55)
        .accessibilityHidden(true)
    }
}
