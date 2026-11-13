import SwiftUI

struct SplashView: View {
    var remote: String = ""

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false
    @State private var breathing = false
    @State private var shimmering = false
    @State private var progress: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                StarLaunchBackdrop(remote: remote)

                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    VStack(spacing: 20) {
                        StarLaunchMark(
                            size: min(112, max(96, geo.size.width * 0.26)),
                            breathing: breathing,
                            shimmering: shimmering
                        )
                        .scaleEffect(revealed ? 1 : 0.965)
                        .opacity(revealed ? 1 : 0)

                        VStack(spacing: 7) {
                            Text("星言")
                                .font(.system(size: 29, weight: .semibold, design: .default))
                                .tracking(0.2)
                                .foregroundStyle(.white)

                            Text("STAR CHAT")
                                .font(.system(size: 9.5, weight: .semibold, design: .default))
                                .tracking(2.7)
                                .foregroundStyle(Color.white.opacity(0.38))
                        }
                        .offset(y: revealed ? 0 : 7)
                        .opacity(revealed ? 1 : 0)
                    }
                    .offset(y: -geo.size.height * 0.034)

                    Spacer(minLength: 0)

                    VStack(spacing: 0) {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.10))
                            .frame(width: 96, height: 1)
                            .overlay(alignment: .leading) {
                                Capsule(style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.25),
                                                Color.white.opacity(0.94)
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: 96 * progress, height: 1)
                                    .shadow(color: Color.white.opacity(0.28), radius: 3)
                            }
                    }
                    .opacity(revealed ? 1 : 0)
                    .padding(.bottom, max(34, L.safeBottom + 22))
                }
                .padding(.horizontal, 28)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("星言"))
        .onAppear {
            withAnimation(.easeOut(duration: 0.72)) {
                revealed = true
            }
            withAnimation(.easeInOut(duration: 1.30).delay(0.10)) {
                progress = 1
            }
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                breathing = true
            }
            withAnimation(.linear(duration: 1.9).delay(0.36).repeatForever(autoreverses: false)) {
                shimmering = true
            }
        }
    }
}

struct StarLaunchBackdrop: View {
    var remote: String = ""

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(hex: 0x030404)

                if !remote.isEmpty {
                    RemoteImage(path: remote, mode: .fill, maxSide: 1600)
                        .frame(width: geo.size.width * 1.12,
                               height: geo.size.height * 1.08)
                        .blur(radius: 42, opaque: false)
                        .saturation(0.86)
                        .opacity(0.24)
                        .clipped()

                    RadialGradient(
                        colors: [
                            Color.black.opacity(0.10),
                            Color.black.opacity(0.62),
                            Color.black.opacity(0.90)
                        ],
                        center: .center,
                        startRadius: geo.size.width * 0.12,
                        endRadius: max(geo.size.width, geo.size.height) * 0.78
                    )
                }

                RadialGradient(
                    stops: [
                        .init(color: Color(hex: 0x2DB77E).opacity(0.13), location: 0),
                        .init(color: Color(hex: 0x123D2B).opacity(0.055), location: 0.46),
                        .init(color: .clear, location: 1)
                    ],
                    center: UnitPoint(x: 0.50, y: 0.42),
                    startRadius: 2,
                    endRadius: max(geo.size.width, geo.size.height) * 0.55
                )

                RadialGradient(
                    stops: [
                        .init(color: Color.white.opacity(0.055), location: 0),
                        .init(color: .clear, location: 1)
                    ],
                    center: UnitPoint(x: 0.84, y: 0.18),
                    startRadius: 0,
                    endRadius: max(geo.size.width, geo.size.height) * 0.38
                )

                LaunchSilkField()
                    .opacity(0.22)

                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(0.18), location: 0),
                        .init(color: .clear, location: 0.36),
                        .init(color: Color.black.opacity(0.30), location: 1)
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
    var shimmering: Bool = false

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
            .overlay {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0),
                                    Color.white.opacity(0.26),
                                    Color.white.opacity(0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * 0.32)
                        .rotationEffect(.degrees(18))
                        .offset(x: shimmering ? proxy.size.width * 1.20
                                              : -proxy.size.width * 0.72)
                        .blendMode(.screen)
                }
                .clipShape(RoundedRectangle(cornerRadius: size * 0.17,
                                            style: .continuous))
                .allowsHitTesting(false)
            }
        }
        .frame(width: size * 1.48, height: size * 1.48)
        .accessibilityHidden(true)
    }
}
