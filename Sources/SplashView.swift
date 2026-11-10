import SwiftUI

struct SplashView: View {
    var remote: String = ""

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    var body: some View {
        ZStack {
            StarLaunchBackdrop(remote: remote)

            LaunchCenterIcon()
                .scaleEffect(revealed ? 1 : 0.94)
                .opacity(revealed ? 1 : 0)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("星言"))
        .onAppear {
            if reduceMotion {
                revealed = true
            } else {
                withAnimation(.spring(response: 0.52, dampingFraction: 0.84)) {
                    revealed = true
                }
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
                    colors: [
                        Color(hex: 0x38D868),
                        Color(hex: 0x34C759)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [
                        Color.white.opacity(0.13),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: max(geo.size.width, geo.size.height) * 0.62
                )

                if !remote.isEmpty {
                    RemoteImage(path: remote, mode: .fill, maxSide: 1600)
                        .frame(width: geo.size.width * 1.08,
                               height: geo.size.height * 1.04)
                        .blur(radius: 56, opaque: false)
                        .saturation(0.82)
                        .opacity(0.06)
                        .blendMode(.screen)
                        .clipped()
                }

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.035),
                        Color.clear,
                        Color.black.opacity(0.065)
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

struct LaunchCenterIcon: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 142, height: 142)
                .blur(radius: 16)

            Group {
                if let icon = AppIconImage.image {
                    Image(uiImage: icon)
                        .resizable()
                        .scaledToFit()
                } else {
                    RoundedRectangle(cornerRadius: 25, style: .continuous)
                        .fill(Color.white)
                        .overlay {
                            LaunchOrbitGlyph()
                                .stroke(
                                    Color(hex: 0x34C759),
                                    style: StrokeStyle(
                                        lineWidth: 4.2,
                                        lineCap: .round
                                    )
                                )
                                .padding(22)
                        }
                }
            }
            .frame(width: 108, height: 108)
            .clipShape(
                RoundedRectangle(cornerRadius: 25, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .stroke(Color.white.opacity(0.42), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.20), radius: 22, y: 12)
            .shadow(color: Color.white.opacity(0.10), radius: 28)
        }
        .frame(width: 150, height: 150)
        .accessibilityHidden(true)
    }
}

private struct LaunchOrbitGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let rx = rect.width * 0.50
        let ry = rect.height * 0.21

        path.addEllipse(in: CGRect(
            x: center.x - rx,
            y: center.y - ry,
            width: rx * 2,
            height: ry * 2
        ))
        path.addEllipse(in: CGRect(
            x: center.x - ry,
            y: center.y - rx,
            width: ry * 2,
            height: rx * 2
        ))
        return path
    }
}
