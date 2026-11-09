import SwiftUI

struct SplashView: View {
    var remote: String = ""

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false
    @State private var breathing = false
    @State private var progress: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                StarLaunchBackdrop(remote: remote)

                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    VStack(spacing: 20) {
                        StarLaunchMark(
                            size: min(116, max(96, geo.size.width * 0.27)),
                            breathing: breathing
                        )
                        .scaleEffect(revealed ? 1 : 0.94)
                        .opacity(revealed ? 1 : 0)

                        VStack(spacing: 8) {
                            Text("星言")
                                .font(.system(size: 28, weight: .semibold, design: .rounded))
                                .tracking(1.2)
                                .foregroundStyle(.white)

                            Text("连接，自有轨道")
                                .font(.system(size: 12.5, weight: .medium))
                                .tracking(1.6)
                                .foregroundStyle(Color.white.opacity(0.50))
                        }
                        .offset(y: revealed ? 0 : 8)
                        .opacity(revealed ? 1 : 0)
                    }
                    .offset(y: -geo.size.height * 0.025)

                    Spacer(minLength: 0)

                    VStack(spacing: 14) {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.07))
                            .frame(width: 132, height: 1.5)
                            .overlay(alignment: .leading) {
                                Capsule(style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.18),
                                                Color.white.opacity(0.82),
                                                Color(hex: 0x49D79B).opacity(0.72)
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: 132 * progress, height: 1.5)
                                    .shadow(color: Color.white.opacity(0.24), radius: 4)
                            }

                        Text("XINGYAN")
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                            .tracking(4.2)
                            .foregroundStyle(Color.white.opacity(0.25))
                    }
                    .opacity(revealed ? 1 : 0)
                    .padding(.bottom, max(30, L.safeBottom + 18))
                }
                .padding(.horizontal, 28)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("星言"))
        .onAppear {
            withAnimation(.easeOut(duration: 0.52)) {
                revealed = true
            }
            withAnimation(.easeInOut(duration: 1.05).delay(0.12)) {
                progress = 1
            }
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
    }
}

struct StarLaunchBackdrop: View {
    var remote: String = ""

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(
                    stops: [
                        .init(color: Color(hex: 0x050706), location: 0),
                        .init(color: Color(hex: 0x0A110D), location: 0.48),
                        .init(color: Color(hex: 0x070A08), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                if !remote.isEmpty {
                    RemoteImage(path: remote, mode: .fill, maxSide: 1600)
                        .frame(width: geo.size.width * 1.10,
                               height: geo.size.height * 1.06)
                        .blur(radius: 58, opaque: false)
                        .saturation(0.72)
                        .opacity(0.11)
                        .blendMode(.screen)
                        .clipped()
                }

                RadialGradient(
                    stops: [
                        .init(color: Color(hex: 0x3ABE8A).opacity(0.22), location: 0),
                        .init(color: Color(hex: 0x164A35).opacity(0.10), location: 0.42),
                        .init(color: .clear, location: 1)
                    ],
                    center: UnitPoint(x: 0.28, y: 0.29),
                    startRadius: 2,
                    endRadius: max(geo.size.width, geo.size.height) * 0.63
                )

                RadialGradient(
                    stops: [
                        .init(color: Color(hex: 0xD9D0B8).opacity(0.12), location: 0),
                        .init(color: .clear, location: 1)
                    ],
                    center: UnitPoint(x: 0.88, y: 0.78),
                    startRadius: 0,
                    endRadius: max(geo.size.width, geo.size.height) * 0.44
                )

                LaunchSilkField()
                    .opacity(0.62)

                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(0.10), location: 0),
                        .init(color: .clear, location: 0.42),
                        .init(color: Color.black.opacity(0.22), location: 1)
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

private struct LaunchSilkField: View {
    var body: some View {
        Canvas { context, size in
            var fine = context
            fine.addFilter(.blur(radius: 18))

            for index in 0..<4 {
                let y = size.height * (0.20 + CGFloat(index) * 0.19)
                var path = Path()
                path.move(to: CGPoint(x: -size.width * 0.08, y: y))
                path.addCurve(
                    to: CGPoint(x: size.width * 1.08, y: y + size.height * 0.035),
                    control1: CGPoint(
                        x: size.width * 0.28,
                        y: y - size.height * (0.07 + CGFloat(index) * 0.008)
                    ),
                    control2: CGPoint(
                        x: size.width * 0.70,
                        y: y + size.height * (0.06 + CGFloat(index) * 0.006)
                    )
                )
                fine.stroke(
                    path,
                    with: .linearGradient(
                        Gradient(colors: [
                            Color.clear,
                            Color.white.opacity(0.035 + Double(index) * 0.008),
                            Color(hex: 0x9AE7C3).opacity(0.032),
                            Color.clear
                        ]),
                        startPoint: CGPoint(x: 0, y: y),
                        endPoint: CGPoint(x: size.width, y: y)
                    ),
                    lineWidth: index == 1 ? 1.1 : 0.65
                )
            }
        }
        .allowsHitTesting(false)
    }
}

struct StarLaunchMark: View {
    let size: CGFloat
    let breathing: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        stops: [
                            .init(color: Color(hex: 0x7CE7B4).opacity(0.22), location: 0),
                            .init(color: Color(hex: 0x276C51).opacity(0.08), location: 0.54),
                            .init(color: .clear, location: 1)
                        ],
                        center: .center,
                        startRadius: size * 0.18,
                        endRadius: size * 0.72
                    )
                )
                .frame(width: size * 1.48, height: size * 1.48)
                .scaleEffect(breathing ? 1.045 : 0.96)

            Ellipse()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.02),
                            Color.white.opacity(0.20),
                            Color(hex: 0x8FF0C6).opacity(0.11),
                            Color.white.opacity(0.01)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 0.7
                )
                .frame(width: size * 1.40, height: size * 0.42)
                .rotationEffect(.degrees(-16))
                .opacity(breathing ? 0.86 : 0.52)

            Group {
                if let icon = AppIconImage.image {
                    Image(uiImage: icon)
                        .resizable()
                        .scaledToFit()
                } else {
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: 0x74E8B1), Color(hex: 0x1B8A60)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay {
                            Text("星")
                                .font(.system(size: size * 0.36, weight: .bold))
                                .foregroundStyle(.white)
                        }
                }
            }
            .frame(width: size * 0.72, height: size * 0.72)
            .clipShape(
                RoundedRectangle(cornerRadius: size * 0.17, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.17, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.34),
                                Color.white.opacity(0.08),
                                Color.black.opacity(0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            }
            .shadow(color: Color.black.opacity(0.50), radius: 24, y: 14)
            .shadow(color: Color(hex: 0x52D9A0).opacity(0.16), radius: 28)
        }
        .frame(width: size * 1.48, height: size * 1.48)
        .accessibilityHidden(true)
    }
}
