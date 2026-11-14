import SwiftUI
import UIKit
import CoreImage

struct ChatDefaultWallpaper: View {
    var preset: ChatAppearancePreset? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            if let preset {
                ChatThemeBackdrop(preset: preset)
            } else if scheme == .light {
                LinearGradient(
                    colors: [
                        Color(hex: 0xF8F5EF),
                        Color(hex: 0xF0ECE4),
                        Color(hex: 0xE7E2D8)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [
                        Color(hex: 0xFFFCF5).opacity(0.92),
                        Color(hex: 0xFFFCF5).opacity(0.32),
                        Color.clear
                    ],
                    center: UnitPoint(x: 0.18, y: 0.09),
                    startRadius: 2,
                    endRadius: 470
                )

                RadialGradient(
                    colors: [
                        Color(hex: 0xDCE7E5).opacity(0.48),
                        Color.clear
                    ],
                    center: UnitPoint(x: 0.90, y: 0.80),
                    startRadius: 4,
                    endRadius: 390
                )

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.10),
                        Color.clear,
                        Color(hex: 0x665D50).opacity(0.035)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                LinearGradient(
                    colors: [
                        Color(hex: 0x050505),
                        Color.black,
                        Color.black
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [
                        Color.white.opacity(0.022),
                        Color.white.opacity(0.008),
                        Color.clear
                    ],
                    center: UnitPoint(x: 0.15, y: 0.06),
                    startRadius: 2,
                    endRadius: 520
                )

                RadialGradient(
                    colors: [
                        Color(hex: 0x8E8E93).opacity(0.020),
                        Color.clear
                    ],
                    center: UnitPoint(x: 0.92, y: 0.84),
                    startRadius: 4,
                    endRadius: 430
                )

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.012),
                        Color.clear,
                        Color.black.opacity(0.10)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            ChatMaterialGrainOverlay()
        }
        .ignoresSafeArea()
    }
}

/// 每个聊天主题都有独立场景，不是只把消息底色换成一个纯色。
/// 所有图形都是静态 SwiftUI 绘制，不启动动画或额外 CADisplayLink。
struct ChatThemeBackdrop: View {
    let preset: ChatAppearancePreset
    @Environment(\.colorScheme) private var scheme

    private var dark: Bool { scheme == .dark }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                preset.canvas
                scene(size: geo.size)
                LinearGradient(
                    colors: [
                        Color.white.opacity(dark ? 0.018 : 0.10),
                        Color.clear,
                        Color.black.opacity(dark ? 0.14 : 0.025)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }

    @ViewBuilder
    private func scene(size: CGSize) -> some View {
        switch preset {
        case .whatsapp:
            whatsappScene(size: size)
        case .midnight:
            midnightScene(size: size)
        case .rose:
            roseScene(size: size)
        case .ocean:
            oceanScene(size: size)
        case .sage:
            sageScene(size: size)
        case .lavender:
            lavenderScene(size: size)
        case .sunset:
            sunsetScene(size: size)
        case .graphite:
            graphiteScene(size: size)
        case .mint:
            mintScene(size: size)
        case .sand:
            sandScene(size: size)
        }
    }

    private func whatsappScene(size: CGSize) -> some View {
        ZStack {
            LinearGradient(
                colors: dark
                    ? [Color(hex: 0x071512), Color(hex: 0x0B141A), Color(hex: 0x111A18)]
                    : [Color(hex: 0xF8F3EA), Color(hex: 0xEFEAE2), Color(hex: 0xE8E5DA)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [Color(hex: 0x25D366).opacity(dark ? 0.09 : 0.13), Color.clear],
                center: UnitPoint(x: 0.86, y: 0.10),
                startRadius: 2,
                endRadius: max(size.width, size.height) * 0.72
            )

            Canvas { context, canvas in
                let ink = Color(hex: dark ? 0xB8C5BE : 0x5E6B60)
                    .opacity(dark ? 0.045 : 0.055)
                for row in 0..<8 {
                    for column in 0..<5 {
                        let x = CGFloat(column) * canvas.width / 4.4
                            + CGFloat((row % 2) * 28)
                        let y = CGFloat(row) * canvas.height / 7.5
                            + CGFloat(column % 2) * 16
                        var curl = Path()
                        curl.move(to: CGPoint(x: x - 18, y: y + 4))
                        curl.addCurve(
                            to: CGPoint(x: x + 7, y: y - 7),
                            control1: CGPoint(x: x - 7, y: y - 17),
                            control2: CGPoint(x: x + 17, y: y + 14)
                        )
                        context.stroke(curl, with: .color(ink), lineWidth: 0.72)

                        var loop = Path()
                        loop.addEllipse(in: CGRect(x: x + 12, y: y + 14,
                                                  width: 13, height: 8))
                        context.stroke(loop, with: .color(ink.opacity(0.72)),
                                       lineWidth: 0.62)
                    }
                }
            }
            .opacity(0.95)
        }
    }

    private func midnightScene(size: CGSize) -> some View {
        ZStack {
            LinearGradient(
                colors: dark
                    ? [Color(hex: 0x000105), Color(hex: 0x020711), Color(hex: 0x000000)]
                    : [Color(hex: 0xF7F8FC), Color(hex: 0xEDF2FA), Color(hex: 0xE9EDF6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [Color(hex: 0x0A84FF).opacity(dark ? 0.19 : 0.15), Color.clear],
                center: UnitPoint(x: 0.84, y: 0.10),
                startRadius: 2,
                endRadius: max(size.width, size.height) * 0.78
            )

            RadialGradient(
                colors: [Color(hex: 0x4C4FA8).opacity(dark ? 0.12 : 0.07), Color.clear],
                center: UnitPoint(x: 0.08, y: 0.92),
                startRadius: 2,
                endRadius: max(size.width, size.height) * 0.65
            )

            ForEach(0..<44, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(dark
                        ? Double(0.16 + (index % 5) * 0.07)
                        : Double(0.22 + (index % 4) * 0.08)))
                    .frame(width: CGFloat(index % 3 == 0 ? 1.7 : 1.1))
                    .position(
                        x: CGFloat((index * 47 + 11) % 101) / 100 * size.width,
                        y: CGFloat((index * 71 + 19) % 97) / 96 * size.height
                    )
            }
        }
    }

    private func roseScene(size: CGSize) -> some View {
        ZStack {
            LinearGradient(
                colors: dark
                    ? [Color(hex: 0x080405), Color(hex: 0x12090D), Color(hex: 0x090607)]
                    : [Color(hex: 0xFCF7F8), Color(hex: 0xF7E9EE), Color(hex: 0xF2E3E8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(RadialGradient(
                    colors: [Color(hex: 0xD94A6A).opacity(dark ? 0.21 : 0.18), Color.clear],
                    center: .center,
                    startRadius: 2,
                    endRadius: size.width * 0.58
                ))
                .frame(width: size.width * 1.18, height: size.width * 1.18)
                .position(x: size.width * 0.86, y: size.height * 0.16)

            Circle()
                .fill(RadialGradient(
                    colors: [Color(hex: 0xF0A7B7).opacity(dark ? 0.08 : 0.24), Color.clear],
                    center: .center,
                    startRadius: 2,
                    endRadius: size.width * 0.52
                ))
                .frame(width: size.width, height: size.width)
                .position(x: size.width * 0.14, y: size.height * 0.82)

            Ellipse()
                .stroke(Color.white.opacity(dark ? 0.035 : 0.32), lineWidth: 0.8)
                .frame(width: size.width * 0.82, height: size.width * 0.42)
                .rotationEffect(.degrees(-24))
                .position(x: size.width * 0.62, y: size.height * 0.62)
        }
    }

    private func oceanScene(size: CGSize) -> some View {
        ZStack {
            LinearGradient(
                colors: dark
                    ? [Color(hex: 0x001521), Color(hex: 0x002A38), Color(hex: 0x001018)]
                    : [Color(hex: 0xF2FAFF), Color(hex: 0xE3F3FB), Color(hex: 0xD7EDF7)],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [Color(hex: 0x40C7F4).opacity(dark ? 0.15 : 0.20), Color.clear],
                center: UnitPoint(x: 0.15, y: 0.08),
                startRadius: 2,
                endRadius: max(size.width, size.height) * 0.60
            )

            Canvas { context, canvas in
                let ink = Color(hex: dark ? 0x8DDCF1 : 0x2D9FC0)
                    .opacity(dark ? 0.075 : 0.12)
                for line in 0..<6 {
                    let baseline = canvas.height * (0.34 + CGFloat(line) * 0.105)
                    var path = Path()
                    path.move(to: CGPoint(x: -20, y: baseline))
                    for x in stride(from: CGFloat(-20), through: canvas.width + 20, by: 14) {
                        let y = baseline
                            + sin((x + CGFloat(line) * 31) / 54) * 8
                            + sin((x - CGFloat(line) * 17) / 27) * 3
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                    context.stroke(path, with: .color(ink), lineWidth: line == 0 ? 1 : 0.7)
                }
            }
        }
    }

    private func sageScene(size: CGSize) -> some View {
        ZStack {
            LinearGradient(
                colors: dark
                    ? [Color(hex: 0x061009), Color(hex: 0x0B1810), Color(hex: 0x07100A)]
                    : [Color(hex: 0xF8FBF6), Color(hex: 0xECF3EA), Color(hex: 0xE1EBDD)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [Color(hex: 0x7FAE86).opacity(dark ? 0.12 : 0.16), Color.clear],
                center: UnitPoint(x: 0.86, y: 0.16),
                startRadius: 2,
                endRadius: max(size.width, size.height) * 0.70
            )

            ForEach(0..<7, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(Color(hex: index % 2 == 0 ? 0x5B8C6E : 0xA7C6A0)
                        .opacity(dark ? 0.055 : 0.09))
                    .frame(width: CGFloat(22 + index % 3 * 8),
                           height: CGFloat(86 + index * 7))
                    .rotationEffect(.degrees(Double(index * 37 - 82)))
                    .position(
                        x: CGFloat((index * 29 + 8) % 91) / 100 * size.width,
                        y: CGFloat((index * 23 + 12) % 87) / 100 * size.height
                    )
            }
        }
    }

    private func lavenderScene(size: CGSize) -> some View {
        ZStack {
            LinearGradient(
                colors: dark
                    ? [Color(hex: 0x07050B), Color(hex: 0x100A18), Color(hex: 0x08060C)]
                    : [Color(hex: 0xFBF9FF), Color(hex: 0xF1ECFA), Color(hex: 0xEAE5F6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [Color(hex: 0x9B88EA).opacity(dark ? 0.18 : 0.20), Color.clear],
                center: UnitPoint(x: 0.80, y: 0.18),
                startRadius: 2,
                endRadius: max(size.width, size.height) * 0.72
            )

            Canvas { context, canvas in
                let ink = Color(hex: dark ? 0xD9CFFF : 0x7867C9)
                    .opacity(dark ? 0.16 : 0.14)
                for index in 0..<22 {
                    let x = CGFloat((index * 43 + 9) % 97) / 96 * canvas.width
                    let y = CGFloat((index * 67 + 21) % 93) / 92 * canvas.height
                    let radius = CGFloat(index % 3 == 0 ? 4.2 : 2.4)
                    var star = Path()
                    star.move(to: CGPoint(x: x, y: y - radius))
                    star.addLine(to: CGPoint(x: x + radius * 0.32, y: y - radius * 0.32))
                    star.addLine(to: CGPoint(x: x + radius, y: y))
                    star.addLine(to: CGPoint(x: x + radius * 0.32, y: y + radius * 0.32))
                    star.addLine(to: CGPoint(x: x, y: y + radius))
                    star.addLine(to: CGPoint(x: x - radius * 0.32, y: y + radius * 0.32))
                    star.addLine(to: CGPoint(x: x - radius, y: y))
                    star.addLine(to: CGPoint(x: x - radius * 0.32, y: y - radius * 0.32))
                    star.closeSubpath()
                    context.fill(star, with: .color(ink))
                }
            }
        }
    }

    private func sunsetScene(size: CGSize) -> some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: dark ? Color(hex: 0x130705) : Color(hex: 0xFFF8EE), location: 0),
                    .init(color: dark ? Color(hex: 0x2A1008) : Color(hex: 0xF8DFC9), location: 0.46),
                    .init(color: dark ? Color(hex: 0x0A0504) : Color(hex: 0xE9C8B5), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Circle()
                .fill(RadialGradient(
                    colors: [
                        Color(hex: 0xFFB35C).opacity(dark ? 0.38 : 0.46),
                        Color(hex: 0xE06B42).opacity(dark ? 0.13 : 0.15),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 3,
                    endRadius: size.width * 0.34
                ))
                .frame(width: size.width * 0.82, height: size.width * 0.82)
                .position(x: size.width * 0.74, y: size.height * 0.34)

            LinearGradient(
                colors: [
                    Color.clear,
                    Color(hex: 0xC75B45).opacity(dark ? 0.09 : 0.10),
                    Color(hex: 0x5B2A20).opacity(dark ? 0.17 : 0.045)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: size.height * 0.52)
            .position(x: size.width * 0.5, y: size.height * 0.78)
        }
    }

    private func graphiteScene(size: CGSize) -> some View {
        ZStack {
            LinearGradient(
                colors: dark
                    ? [Color(hex: 0x050505), Color(hex: 0x111214), Color(hex: 0x000000)]
                    : [Color(hex: 0xF9F9F8), Color(hex: 0xECEEEE), Color(hex: 0xE2E4E4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [Color.white.opacity(dark ? 0.065 : 0.30), Color.clear],
                center: UnitPoint(x: 0.80, y: 0.08),
                startRadius: 2,
                endRadius: max(size.width, size.height) * 0.65
            )

            Canvas { context, canvas in
                let ink = Color(hex: dark ? 0xFFFFFF : 0x50555C)
                    .opacity(dark ? 0.025 : 0.035)
                for index in 0..<18 {
                    let x = CGFloat(index) * 34 - canvas.height * 0.35
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x + canvas.height * 0.54, y: canvas.height))
                    context.stroke(path, with: .color(ink), lineWidth: 0.7)
                }
            }
            .blendMode(.softLight)
        }
    }

    private func mintScene(size: CGSize) -> some View {
        ZStack {
            LinearGradient(
                colors: dark
                    ? [Color(hex: 0x03100D), Color(hex: 0x071A16), Color(hex: 0x03100D)]
                    : [Color(hex: 0xF8FFFC), Color(hex: 0xE6F7F1), Color(hex: 0xDDF1EA)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [Color(hex: 0x61E1C0).opacity(dark ? 0.13 : 0.20), Color.clear],
                center: UnitPoint(x: 0.82, y: 0.14),
                startRadius: 2,
                endRadius: max(size.width, size.height) * 0.72
            )

            ForEach(0..<5, id: \.self) { index in
                Circle()
                    .stroke(Color.white.opacity(dark
                        ? Double(0.025 + (index % 2) * 0.012)
                        : Double(0.22 + (index % 2) * 0.08)),
                            lineWidth: 0.8)
                    .frame(width: CGFloat(94 + index * 54),
                           height: CGFloat(94 + index * 54))
                    .position(
                        x: size.width * (index % 2 == 0 ? 0.18 : 0.82),
                        y: size.height * (0.24 + CGFloat(index) * 0.15)
                    )
            }
        }
    }

    private func sandScene(size: CGSize) -> some View {
        ZStack {
            LinearGradient(
                colors: dark
                    ? [Color(hex: 0x100B06), Color(hex: 0x21170E), Color(hex: 0x100B06)]
                    : [Color(hex: 0xFFFBF2), Color(hex: 0xF4EBDD), Color(hex: 0xE9DDCD)],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [Color(hex: 0xE5B878).opacity(dark ? 0.16 : 0.24), Color.clear],
                center: UnitPoint(x: 0.82, y: 0.16),
                startRadius: 2,
                endRadius: max(size.width, size.height) * 0.62
            )

            Ellipse()
                .fill(Color(hex: dark ? 0x5A3A20 : 0xD6B28A)
                    .opacity(dark ? 0.10 : 0.20))
                .frame(width: size.width * 1.65, height: size.height * 0.62)
                .position(x: size.width * 0.12, y: size.height * 0.92)

            Ellipse()
                .fill(Color(hex: dark ? 0x8A5B2F : 0xE7CAA7)
                    .opacity(dark ? 0.07 : 0.22))
                .frame(width: size.width * 1.55, height: size.height * 0.50)
                .position(x: size.width * 0.90, y: size.height * 1.04)
        }
    }
}

final class ChatWallpaperEffectRenderer {
    static let shared = ChatWallpaperEffectRenderer()

    private let cache = NSCache<NSString, UIImage>()
    private let context = CIContext(options: [
        .cacheIntermediates: true,
        .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any
    ])

    private init() {
        cache.countLimit = 24
        cache.totalCostLimit = 128 * 1024 * 1024
    }

    func image(path: String,
               effect: ChatBackgroundEffect,
               target: CGSize) async -> UIImage? {
        guard effect != .original, effect != .auto,
              target.width > 1, target.height > 1 else { return nil }
        let nativeWidth = target.width * UIScreen.main.scale
        let width = max(960, min(2048, nativeWidth))
        let height = max(1, width * target.height / target.width)
        let key = [
            path,
            effect.rawValue,
            String(Int(width.rounded())),
            String(Int(height.rounded()))
        ].joined(separator: "#") as NSString

        if let hit = cache.object(forKey: key) { return hit }
        guard let data = await sourceData(path),
              let source = await Task.detached(priority: .userInitiated, operation: {
                  RemoteImage.downsampled(
                      data,
                      maxSide: max(2400, chatWallpaperDecodeSide())
                  )
              }).value else { return nil }
        guard !Task.isCancelled else { return nil }

        let output = await Task.detached(priority: .userInitiated) { [context] in
            Self.render(source: source,
                        effect: effect,
                        target: CGSize(width: width, height: height),
                        context: context)
        }.value
        if let output {
            cache.setObject(output,
                            forKey: key,
                            cost: Int(output.size.width * output.size.height * 4))
        }
        return output
    }

    private func sourceData(_ path: String) async -> Data? {
        if path.hasPrefix("data:"),
           let comma = path.firstIndex(of: ","),
           let data = Data(base64Encoded: String(path[path.index(after: comma)...]),
                           options: .ignoreUnknownCharacters) {
            return data
        }
        if let direct = ImageStore.shared.get(path),
           let data = await Task.detached(priority: .userInitiated, operation: {
               direct.jpegData(compressionQuality: 0.92)
           }).value {
            return data
        }
        if let data = await Task.detached(priority: .userInitiated, operation: {
            ImageStore.shared.diskRead(path)
        }).value {
            return data
        }
        if let url = API.shared.assetURL(path) {
            return try? await API.shared.assetData(url)
        }
        return nil
    }

    private static func render(source: UIImage,
                               effect: ChatBackgroundEffect,
                               target: CGSize,
                               context: CIContext) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let cropped = renderer.image { _ in
            let scale = max(target.width / source.size.width,
                            target.height / source.size.height)
            let drawSize = CGSize(width: source.size.width * scale,
                                  height: source.size.height * scale)
            let origin = CGPoint(x: (target.width - drawSize.width) * 0.5,
                                 y: (target.height - drawSize.height) * 0.5)
            source.draw(in: CGRect(origin: origin, size: drawSize))
        }
        guard let input = CIImage(image: cropped)?
            .applyingFilter("CINoiseReduction", parameters: [
                "inputNoiseLevel": 0.018,
                "inputSharpness": 0.36
            ]) else { return nil }

        let radius = max(22, min(48, target.width * 0.033))
        let blurred = input
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [
                kCIInputRadiusKey: radius
            ])
            .cropped(to: input.extent)

        let black = effect == .blackBlur
        let toned = blurred.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: black ? 0.93 : 0.96,
            kCIInputContrastKey: black ? 1.025 : 1.012,
            kCIInputBrightnessKey: black ? -0.006 : 0.012
        ])
        let exposed = toned.applyingFilter("CIExposureAdjust", parameters: [
            kCIInputEVKey: black ? -0.12 : 0.09
        ])
        let vibrant = exposed.applyingFilter("CIVibrance", parameters: [
            "inputAmount": black ? 0.015 : 0.042
        ])
        let vignetted = vibrant.applyingFilter("CIVignette", parameters: [
            kCIInputIntensityKey: black ? 0.16 : 0.065,
            kCIInputRadiusKey: 1.65
        ])
        guard let cg = context.createCGImage(vignetted, from: input.extent) else {
            return nil
        }
        return UIImage(cgImage: cg)
    }
}

struct ChatWallpaperEffectImage: View {
    let path: String
    let effect: ChatBackgroundEffect
    var renderSize: CGSize? = nil
    var displayAlignment: Alignment = .center
    @Environment(\.colorScheme) private var scheme
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { proxy in
            let resolved = effect.resolved(for: scheme)
            let target = renderSize ?? proxy.size
            let widthBucket = max(1, Int((target.width / 80).rounded()))
            ZStack(alignment: displayAlignment) {
                (resolved == .blackBlur
                 ? Color(hex: 0x101110)
                 : Color(hex: 0xF3F4F1))
                    .frame(width: target.width, height: target.height)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: target.width, height: target.height)
                        .transition(.opacity)
                }
                ChatWallpaperToneOverlay(dark: resolved == .blackBlur)
                ChatMaterialGrainOverlay()
            }
            .frame(width: proxy.size.width,
                   height: proxy.size.height,
                   alignment: displayAlignment)
            .clipped()
            .task(id: "\(path)#\(resolved.rawValue)#\(widthBucket)") {
                image = await ChatWallpaperEffectRenderer.shared.image(
                    path: path,
                    effect: resolved,
                    target: target
                )
            }
            .animation(.easeOut(duration: 0.24), value: image != nil)
        }
    }
}

private struct ChatWallpaperToneOverlay: View {
    let dark: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: dark
                    ? [Color.white.opacity(0.018),
                       Color.clear,
                       Color.black.opacity(0.10)]
                    : [Color.white.opacity(0.10),
                       Color.clear,
                       Color(hex: 0x5D5548).opacity(0.035)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: dark
                    ? [Color.white.opacity(0.018), Color.clear]
                    : [Color.white.opacity(0.075), Color.clear],
                center: UnitPoint(x: 0.22, y: 0.08),
                startRadius: 1,
                endRadius: 360
            )
        }
        .blendMode(.softLight)
        .allowsHitTesting(false)
    }
}

private enum ChatMaterialGrain {
    static let texture: UIImage? = {
        let side = 128
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(
            size: CGSize(width: side, height: side),
            format: format
        ).image { context in
            var state: UInt64 = 0x9E3779B97F4A7C15
            func next() -> UInt64 {
                state ^= state << 13
                state ^= state >> 7
                state ^= state << 17
                return state
            }
            for y in 0..<side {
                for x in 0..<side {
                    let value = Double(next() & 0xFF) / 255
                    let tone = 0.34 + value * 0.32
                    context.cgContext.setFillColor(
                        UIColor(white: tone, alpha: 0.085).cgColor
                    )
                    context.cgContext.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
    }()
}

struct ChatMaterialGrainOverlay: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let texture = ChatMaterialGrain.texture {
            Image(uiImage: texture)
                .resizable(resizingMode: .tile)
                .opacity(scheme == .dark ? 0.045 : 0.032)
                .blendMode(.overlay)
                .allowsHitTesting(false)
        }
    }
}
