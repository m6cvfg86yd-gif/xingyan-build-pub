import SwiftUI
import UIKit
import CoreImage

final class ChatWallpaperEffectRenderer {
    static let shared = ChatWallpaperEffectRenderer()

    private let cache = NSCache<NSString, UIImage>()
    private let context = CIContext(options: [
        .cacheIntermediates: true,
        .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any
    ])

    private init() {
        cache.countLimit = 24
        cache.totalCostLimit = 36 * 1024 * 1024
    }

    func image(path: String,
               effect: ChatBackgroundEffect,
               target: CGSize) async -> UIImage? {
        guard effect != .original, effect != .auto,
              target.width > 1, target.height > 1 else { return nil }
        let width = max(280, min(620, target.width))
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
                  RemoteImage.downsampled(data, maxSide: 900)
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
        guard let input = CIImage(image: cropped) else { return nil }

        let radius = max(10, min(24, target.width * 0.036))
        let blurred = input
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [
                kCIInputRadiusKey: radius
            ])
            .cropped(to: input.extent)

        let black = effect == .blackBlur
        let toned = blurred.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: black ? 0.82 : 0.88,
            kCIInputContrastKey: black ? 1.045 : 1.015,
            kCIInputBrightnessKey: black ? -0.025 : 0.035
        ])
        guard let cg = context.createCGImage(toned, from: input.extent) else {
            return nil
        }
        return UIImage(cgImage: cg)
    }
}

struct ChatWallpaperEffectImage: View {
    let path: String
    let effect: ChatBackgroundEffect
    @Environment(\.colorScheme) private var scheme
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { proxy in
            let resolved = effect.resolved(for: scheme)
            let widthBucket = max(1, Int((proxy.size.width / 80).rounded()))
            ZStack {
                (resolved == .blackBlur
                 ? Color(hex: 0x101110)
                 : Color(hex: 0xF3F4F1))
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width,
                               height: proxy.size.height)
                        .clipped()
                        .transition(.opacity)
                }
            }
            .task(id: "\(path)#\(resolved.rawValue)#\(widthBucket)") {
                image = await ChatWallpaperEffectRenderer.shared.image(
                    path: path,
                    effect: resolved,
                    target: proxy.size
                )
            }
            .animation(.easeOut(duration: 0.24), value: image != nil)
        }
    }
}
