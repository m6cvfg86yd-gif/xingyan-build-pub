import SwiftUI

struct StarWorldLoadingOverlay: View {
    let destination: StarWorldMap

    @State private var progress: CGFloat = 0.08
    @State private var orbit: Double = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: destination == .plaza
                        ? [Color(hex: 0x06151F), Color(hex: 0x153B41), Color(hex: 0x765E42)]
                        : [Color(hex: 0x07131D), Color(hex: 0x102D37), Color(hex: 0x263D3B)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                RadialGradient(
                    colors: [
                        Color(hex: 0x70E6CB).opacity(destination == .plaza ? 0.20 : 0.13),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 18,
                    endRadius: proxy.size.width * 0.72
                )

                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        worldMark
                        VStack(alignment: .leading, spacing: 2) {
                            Text("XINGYAN WORLD")
                                .font(pfStyled(size: 9, weight: .bold))
                                .tracking(1.8)
                                .foregroundStyle(.white.opacity(0.46))
                            Text(Tr("正在穿越星门"))
                                .font(pfStyled(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.78))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, max(20, L.safeTop + 12))

                    Spacer()

                    StarWorldLoadingArtwork(destination: destination)
                        .frame(width: min(proxy.size.width - 64, 360), height: 228)
                        .overlay {
                            Circle()
                                .trim(from: 0.08, to: 0.34)
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color(hex: 0x9BF1DD).opacity(0.0),
                                            Color(hex: 0x9BF1DD).opacity(0.9),
                                            Color(hex: 0xF1D08A).opacity(0.18)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    style: StrokeStyle(lineWidth: 1.1, lineCap: .round)
                                )
                                .frame(width: 176, height: 176)
                                .rotationEffect(.degrees(orbit))
                                .allowsHitTesting(false)
                        }

                    VStack(spacing: 7) {
                        Text(Tr(destination.title))
                            .font(pfStyled(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(destination == .plaza
                             ? Tr("海边广场 · 正在布置海岸与公共空间")
                             : Tr("星言房间 · 正在点亮你的私人空间"))
                            .font(pfStyled(size: 11.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.54))
                    }
                    .padding(.top, 8)

                    Spacer()

                    VStack(spacing: 11) {
                        GeometryReader { bar in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.08))
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(hex: 0x8CEBD6), Color(hex: 0xE6C47F)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(8, bar.size.width * progress))
                                    .shadow(color: Color(hex: 0x75E4CA).opacity(0.38), radius: 9)
                            }
                        }
                        .frame(width: min(proxy.size.width - 100, 290), height: 3)

                        HStack {
                            Text(Tr("连接星言世界"))
                            Spacer()
                            Text("\(Int(progress * 100))%")
                        }
                        .font(pfStyled(size: 9.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                        .frame(width: min(proxy.size.width - 100, 290))
                    }
                    .padding(.bottom, max(30, L.safeBottom + 20))
                }
            }
            .ignoresSafeArea()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.05)) {
                progress = 0.92
            }
            withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
                orbit = 360
            }
        }
    }

    private var worldMark: some View {
        ZStack {
            Circle()
                .stroke(Color(hex: 0xE9CB8A).opacity(0.65), lineWidth: 1)
                .frame(width: 30, height: 30)
                .scaleEffect(y: 0.44)
                .rotationEffect(.degrees(-25))
            Circle()
                .fill(Color(hex: 0x78E5CB))
                .frame(width: 7, height: 7)
                .shadow(color: Color(hex: 0x78E5CB).opacity(0.8), radius: 8)
        }
        .frame(width: 34, height: 34)
    }
}

private struct StarWorldLoadingArtwork: View {
    let destination: StarWorldMap

    var body: some View {
        Canvas { context, size in
            if destination == .plaza {
                drawPlaza(context: context, size: size)
            } else {
                drawRoom(context: context, size: size)
            }
        }
    }

    private func drawPlaza(context: GraphicsContext, size: CGSize) {
        let horizon = size.height * 0.61
        var farSea = Path()
        farSea.move(to: CGPoint(x: 0, y: horizon))
        farSea.addLine(to: CGPoint(x: size.width, y: horizon))
        context.stroke(
            farSea,
            with: .linearGradient(
                Gradient(colors: [
                    Color(hex: 0x73D9CE).opacity(0),
                    Color(hex: 0x91E8DA).opacity(0.62),
                    Color(hex: 0xF0D095).opacity(0.18)
                ]),
                startPoint: CGPoint(x: 0, y: horizon),
                endPoint: CGPoint(x: size.width, y: horizon)
            ),
            lineWidth: 0.8
        )

        var island = Path()
        island.move(to: CGPoint(x: 0, y: horizon + 8))
        island.addCurve(
            to: CGPoint(x: size.width, y: horizon + 8),
            control1: CGPoint(x: size.width * 0.28, y: horizon - 9),
            control2: CGPoint(x: size.width * 0.70, y: horizon + 23)
        )
        island.addLine(to: CGPoint(x: size.width, y: size.height))
        island.addLine(to: CGPoint(x: 0, y: size.height))
        island.closeSubpath()
        context.fill(
            island,
            with: .linearGradient(
                Gradient(colors: [
                    Color(hex: 0x173B40).opacity(0.95),
                    Color(hex: 0x07171E).opacity(0.98)
                ]),
                startPoint: CGPoint(x: 0, y: horizon),
                endPoint: CGPoint(x: 0, y: size.height)
            )
        )

        for index in 0..<7 {
            var wave = Path()
            let y = horizon + 17 + CGFloat(index) * 15
            wave.move(to: CGPoint(x: size.width * 0.08, y: y))
            wave.addCurve(
                to: CGPoint(x: size.width * 0.92, y: y),
                control1: CGPoint(x: size.width * 0.35, y: y - 6),
                control2: CGPoint(x: size.width * 0.67, y: y + 6)
            )
            context.stroke(
                wave,
                with: .color(Color(hex: 0x8EE4D6).opacity(0.10 - Double(index) * 0.008)),
                lineWidth: 0.8
            )
        }

        let center = CGPoint(x: size.width * 0.5, y: horizon - 20)
        var arch = Path()
        arch.move(to: CGPoint(x: center.x - 74, y: horizon + 20))
        arch.addCurve(
            to: CGPoint(x: center.x + 74, y: horizon + 20),
            control1: CGPoint(x: center.x - 58, y: horizon - 117),
            control2: CGPoint(x: center.x + 58, y: horizon - 117)
        )
        context.stroke(
            arch,
            with: .linearGradient(
                Gradient(colors: [
                    Color(hex: 0xF4F0E4),
                    Color(hex: 0x9EE8DA)
                ]),
                startPoint: CGPoint(x: center.x - 74, y: horizon),
                endPoint: CGPoint(x: center.x + 74, y: horizon - 80)
            ),
            style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
        )

        let poolRect = CGRect(
            x: center.x - 50,
            y: horizon + 5,
            width: 100,
            height: 24
        )
        context.fill(
            Path(ellipseIn: poolRect),
            with: .color(Color(hex: 0x4FC5C8).opacity(0.28))
        )
        context.stroke(
            Path(ellipseIn: poolRect),
            with: .color(Color(hex: 0xF2E7D4).opacity(0.62)),
            lineWidth: 1
        )

        drawStars(context: context, size: size, horizon: horizon)
    }

    private func drawRoom(context: GraphicsContext, size: CGSize) {
        let inset = size.width * 0.12
        let roomRect = CGRect(
            x: inset,
            y: size.height * 0.14,
            width: size.width - inset * 2,
            height: size.height * 0.70
        )
        context.fill(
            Path(roundedRect: roomRect, cornerRadius: 24),
            with: .linearGradient(
                Gradient(colors: [
                    Color(hex: 0x18353A).opacity(0.72),
                    Color(hex: 0x07171F).opacity(0.90)
                ]),
                startPoint: CGPoint(x: roomRect.minX, y: roomRect.minY),
                endPoint: CGPoint(x: roomRect.maxX, y: roomRect.maxY)
            )
        )
        context.stroke(
            Path(roundedRect: roomRect, cornerRadius: 24),
            with: .color(Color.white.opacity(0.08)),
            lineWidth: 0.8
        )

        let windowRect = CGRect(
            x: roomRect.minX + 34,
            y: roomRect.minY + 33,
            width: 108,
            height: 84
        )
        context.fill(
            Path(roundedRect: windowRect, cornerRadius: 8),
            with: .linearGradient(
                Gradient(colors: [
                    Color(hex: 0x76B9C8).opacity(0.45),
                    Color(hex: 0xF0C27D).opacity(0.20)
                ]),
                startPoint: CGPoint(x: windowRect.minX, y: windowRect.minY),
                endPoint: CGPoint(x: windowRect.maxX, y: windowRect.maxY)
            )
        )
        var mullion = Path()
        mullion.move(to: CGPoint(x: windowRect.midX, y: windowRect.minY))
        mullion.addLine(to: CGPoint(x: windowRect.midX, y: windowRect.maxY))
        mullion.move(to: CGPoint(x: windowRect.minX, y: windowRect.midY))
        mullion.addLine(to: CGPoint(x: windowRect.maxX, y: windowRect.midY))
        context.stroke(mullion, with: .color(Color.white.opacity(0.16)), lineWidth: 0.8)

        let bed = CGRect(
            x: roomRect.maxX - 132,
            y: roomRect.maxY - 72,
            width: 104,
            height: 45
        )
        context.fill(
            Path(roundedRect: bed, cornerRadius: 12),
            with: .color(Color(hex: 0xD9D4C5).opacity(0.64))
        )
        context.fill(
            Path(roundedRect: bed.insetBy(dx: 8, dy: 7), cornerRadius: 8),
            with: .color(Color(hex: 0x6FA99B).opacity(0.42))
        )

        let rug = CGRect(
            x: roomRect.midX - 46,
            y: roomRect.maxY - 50,
            width: 92,
            height: 22
        )
        context.fill(
            Path(ellipseIn: rug),
            with: .color(Color(hex: 0x2F7B70).opacity(0.24))
        )

        let doorRect = CGRect(
            x: roomRect.maxX - 52,
            y: roomRect.minY + 42,
            width: 28,
            height: 72
        )
        context.fill(
            Path(roundedRect: doorRect, cornerRadius: 6),
            with: .linearGradient(
                Gradient(colors: [
                    Color(hex: 0xE1C37F).opacity(0.48),
                    Color(hex: 0x2AA88D).opacity(0.26)
                ]),
                startPoint: CGPoint(x: doorRect.minX, y: doorRect.minY),
                endPoint: CGPoint(x: doorRect.maxX, y: doorRect.maxY)
            )
        )
        context.stroke(
            Path(roundedRect: doorRect, cornerRadius: 6),
            with: .color(Color(hex: 0xF1D698).opacity(0.48)),
            lineWidth: 0.8
        )

        drawStars(context: context, size: size, horizon: size.height * 0.44)
    }

    private func drawStars(context: GraphicsContext, size: CGSize, horizon: CGFloat) {
        let points: [(CGFloat, CGFloat, CGFloat)] = [
            (0.10, 0.16, 1.0), (0.22, 0.24, 0.7), (0.78, 0.12, 0.8),
            (0.88, 0.30, 1.2), (0.66, 0.28, 0.55), (0.32, 0.10, 0.55),
            (0.94, 0.46, 0.65), (0.06, 0.40, 0.45)
        ]
        for point in points {
            let rect = CGRect(
                x: size.width * point.0,
                y: min(horizon, size.height * point.1),
                width: point.2,
                height: point.2
            )
            context.fill(
                Path(ellipseIn: rect),
                with: .color(Color(hex: 0xC9F4E9).opacity(0.55))
            )
        }
    }
}
