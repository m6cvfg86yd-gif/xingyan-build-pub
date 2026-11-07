import SwiftUI
import UIKit
import CoreImage

enum PhotoEditPreset: String, CaseIterable, Identifiable {
    case original
    case auto
    case vivid
    case warm
    case cool
    case mono

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return Tr("原图")
        case .auto: return Tr("自动美化")
        case .vivid: return Tr("鲜艳")
        case .warm: return Tr("暖色")
        case .cool: return Tr("冷色")
        case .mono: return Tr("黑白")
        }
    }

    var symbol: String {
        switch self {
        case .original: return "photo"
        case .auto: return "wand.and.stars"
        case .vivid: return "sun.max"
        case .warm: return "sun.horizon"
        case .cool: return "snowflake"
        case .mono: return "circle.lefthalf.filled"
        }
    }
}

struct PhotoEditSettings {
    var smooth: Double = 0.25
    var slimFace: Double = 0.16
    var enlargeEyes: Double = 0.10
    var smallerHead: Double = 0.10
    var brightness: Double = 0.02
    var contrast: Double = 0.04
    var saturation: Double = 0.04
    var sharpen: Double = 0.16
    var vignette: Double = 0.06

    static let neutral = PhotoEditSettings(
        smooth: 0, slimFace: 0, enlargeEyes: 0, smallerHead: 0,
        brightness: 0, contrast: 0, saturation: 0, sharpen: 0, vignette: 0
    )

    var token: String {
        [
            smooth, slimFace, enlargeEyes, brightness,
            smallerHead, contrast, saturation, sharpen, vignette
        ]
        .map { String(Int(($0 * 20).rounded())) }
        .joined(separator: ":")
    }
}

struct PhotoEditorView: View {
    let image: UIImage
    let onDone: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var preset: PhotoEditPreset = .auto
    @State private var amount = 0.65
    @State private var quarterTurns = 0
    @State private var preview: UIImage
    @State private var rendering = false
    @State private var exporting = false
    @State private var errorText = ""
    @State private var editSection = 0
    @State private var settings = PhotoEditSettings()

    init(image: UIImage, onDone: @escaping (UIImage) -> Void) {
        self.image = image
        self.onDone = onDone
        _preview = State(initialValue: image)
    }

    private var renderKey: String {
        "\(preset.rawValue)-\(Int((amount * 20).rounded()))-\(quarterTurns)-\(settings.token)"
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ZStack {
                Color.black
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 12)

                if rendering || exporting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .padding(12)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            controls
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task(id: renderKey) {
            if preset == .original, quarterTurns == 0 {
                preview = image
                rendering = false
                return
            }
            rendering = true
            let output = await Task.detached(priority: .userInitiated) {
                PhotoEditRenderer.render(
                    image,
                    preset: preset,
                    amount: amount,
                    quarterTurns: quarterTurns,
                    settings: settings,
                    maxSide: 1800
                )
            }.value
            guard !Task.isCancelled else { return }
            preview = output ?? image
            rendering = false
        }
        .alert(Tr("处理失败，再试一次"), isPresented: Binding(
            get: { !errorText.isEmpty },
            set: { if !$0 { errorText = "" } }
        )) {
            Button(Tr("好"), role: .cancel) { errorText = "" }
        }
    }

    private var header: some View {
        HStack {
            Button(Tr("取消")) { dismiss() }
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.88))

            Spacer()

            Text(Tr("编辑照片"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)

            Spacer()

            Button {
                export()
            } label: {
                Text(exporting ? Tr("照片处理中…") : Tr("完成"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(rendering || exporting)
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(.ultraThinMaterial)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            if editSection == 0 {
                if preset != .original {
                    sliderRow(Tr("滤镜强度"), value: $amount, range: 0...1)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(PhotoEditPreset.allCases) { item in
                            presetButton(item)
                        }
                    }
                    .padding(.horizontal, 12)
                }
            } else if editSection == 1 {
                sliderRow(Tr("磨皮"), value: $settings.smooth, range: 0...1)
                sliderRow(Tr("瘦脸"), value: $settings.slimFace, range: 0...1)
                sliderRow(Tr("大眼"), value: $settings.enlargeEyes, range: 0...1)
                sliderRow(Tr("小头"), value: $settings.smallerHead, range: 0...1)
            } else {
                sliderRow(Tr("亮度"), value: $settings.brightness, range: -0.2...0.2)
                sliderRow(Tr("对比度"), value: $settings.contrast, range: -0.2...0.4)
                sliderRow(Tr("饱和度"), value: $settings.saturation, range: -0.3...0.5)
                sliderRow(Tr("锐化"), value: $settings.sharpen, range: 0...1)
                sliderRow(Tr("暗角"), value: $settings.vignette, range: 0...1)
            }

            HStack(spacing: 4) {
                toolButton(0, Tr("滤镜"), "camera.filters")
                toolButton(1, Tr("美颜"), "face.smiling")
                toolButton(2, Tr("调整"), "slider.horizontal.3")
                roundToolButton(Tr("旋转"), "rotate.right") {
                    quarterTurns = (quarterTurns + 1) % 4
                }
                roundToolButton(Tr("复位"), "arrow.counterclockwise") {
                    reset()
                }
            }
            .padding(.horizontal, 10)
        }
        .padding(.top, 9)
        .padding(.bottom, 16)
        .background(.ultraThinMaterial)
    }

    private func toolButton(_ index: Int, _ title: String, _ symbol: String) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) {
                editSection = index
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .medium))
                    .frame(height: 22)
                Text(title)
                    .font(.system(size: 11.5, weight: editSection == index ? .semibold : .medium))
            }
            .foregroundStyle(editSection == index ? Color.black : Color.white.opacity(0.82))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(editSection == index ? Color.white : Color.white.opacity(0.06))
            }
        }
        .buttonStyle(.plain)
    }

    private func roundToolButton(_ title: String, _ symbol: String,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .medium))
                    .frame(height: 22)
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.82))
            .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
    }

    private func sliderRow(_ title: String, value: Binding<Double>,
                           range: ClosedRange<Double>) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.74))
                .frame(width: 52, alignment: .leading)
            Slider(value: value, in: range)
                .tint(.white)
            Text(String(format: "%.0f", normalizedPercent(value.wrappedValue, range: range)))
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.58))
                .frame(width: 30, alignment: .trailing)
        }
        .padding(.horizontal, 16)
    }

    private func normalizedPercent(_ value: Double, range: ClosedRange<Double>) -> Double {
        guard range.upperBound > range.lowerBound else { return 0 }
        return (value - range.lowerBound) / (range.upperBound - range.lowerBound) * 100
    }

    private func presetButton(_ item: PhotoEditPreset) -> some View {
        let selected = preset == item
        return Button {
            preset = item
            if item == .original { amount = 0.65 }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: item.symbol)
                    .font(.system(size: 18, weight: .medium))
                    .frame(height: 20)
                Text(item.title)
                    .font(.system(size: 11.5, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? Color.black : Color.white.opacity(0.86))
            .frame(width: 64, height: 52)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? Color.white : Color.white.opacity(0.07))
            }
        }
        .buttonStyle(.plain)
    }

    private func reset() {
        preset = .original
        amount = 0.65
        quarterTurns = 0
        settings = .neutral
        editSection = 0
    }

    private func export() {
        exporting = true
        Task {
            let output = await Task.detached(priority: .userInitiated) {
                PhotoEditRenderer.render(
                    image,
                    preset: preset,
                    amount: amount,
                    quarterTurns: quarterTurns,
                    settings: settings,
                    maxSide: nil
                )
            }.value
            exporting = false
            guard let output else {
                errorText = Tr("处理失败，再试一次")
                return
            }
            onDone(output)
            dismiss()
        }
    }
}

private enum PhotoEditRenderer {
    private static let context = CIContext(options: [
        .cacheIntermediates: false,
        .workingColorSpace: CGColorSpaceCreateDeviceRGB()
    ])
    private static let faceDetector = CIDetector(
        ofType: CIDetectorTypeFace,
        context: context,
        options: [
            CIDetectorAccuracy: CIDetectorAccuracyHigh,
            CIDetectorTracking: true
        ]
    )

    static func render(_ image: UIImage,
                       preset: PhotoEditPreset,
                       amount: Double,
                       quarterTurns: Int,
                       settings: PhotoEditSettings,
                       maxSide: CGFloat?) -> UIImage? {
        let normalized = normalized(image, maxSide: maxSide)
        guard let source = CIImage(image: normalized) else { return normalized }
        let strength = CGFloat(max(0, min(1, amount)))
        let faces = detectFaces(source)
        var output = applyFaceShape(source, faces: faces, settings: settings)
        output = smoothFaces(output, faces: faces, amount: settings.smooth)

        switch preset {
        case .original:
            break
        case .auto:
            output = colorControls(output,
                                   saturation: 1 + 0.18 * strength,
                                   contrast: 1 + 0.10 * strength,
                                   brightness: 0.018 * strength)
            output = filter("CIExposureAdjust", output, [
                "inputEV": 0.12 * strength
            ])
            output = filter("CIVibrance", output, [
                "inputAmount": 0.30 * strength
            ])
        case .vivid:
            output = colorControls(output,
                                   saturation: 1 + 0.38 * strength,
                                   contrast: 1 + 0.08 * strength,
                                   brightness: 0.008 * strength)
            output = filter("CIVibrance", output, [
                "inputAmount": 0.38 * strength
            ])
        case .warm:
            output = colorMatrix(output,
                                 red: 1 + 0.08 * strength,
                                 green: 1 + 0.025 * strength,
                                 blue: 1 - 0.10 * strength,
                                 bias: CIVector(x: 0.025 * strength,
                                                y: 0.012 * strength,
                                                z: -0.018 * strength,
                                                w: 0))
        case .cool:
            output = colorMatrix(output,
                                 red: 1 - 0.07 * strength,
                                 green: 1 + 0.015 * strength,
                                 blue: 1 + 0.10 * strength,
                                 bias: CIVector(x: -0.012 * strength,
                                                y: 0,
                                                z: 0.025 * strength,
                                                w: 0))
        case .mono:
            output = filter("CIPhotoEffectMono", output, [:])
            output = colorControls(output,
                                   saturation: 0,
                                   contrast: 1 + 0.10 * strength,
                                   brightness: 0)
        }

        output = colorControls(
            output,
            saturation: 1 + CGFloat(settings.saturation),
            contrast: 1 + CGFloat(settings.contrast),
            brightness: CGFloat(settings.brightness)
        )
        if settings.sharpen > 0.001 {
            output = filter("CISharpenLuminance", output, [
                "inputSharpness": settings.sharpen * 0.8
            ])
        }
        if settings.vignette > 0.001 {
            output = filter("CIVignette", output, [
                "inputIntensity": settings.vignette * 1.4,
                "inputRadius": min(output.extent.width, output.extent.height) * 0.62
            ])
        }

        let turns = ((quarterTurns % 4) + 4) % 4
        if turns != 0 {
            output = output.transformed(
                by: CGAffineTransform(rotationAngle: CGFloat(turns) * .pi / 2)
            )
        }
        let extent = output.extent.integral
        let translated = output.transformed(
            by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
        )
        guard let cg = context.createCGImage(translated, from: translated.extent) else {
            return normalized
        }
        return UIImage(cgImage: cg, scale: 1, orientation: .up)
    }

    private static func detectFaces(_ image: CIImage) -> [CIFaceFeature] {
        guard let detector = faceDetector else { return [] }
        return detector.features(
            in: image,
            options: [CIDetectorImageOrientation: 1]
        ).compactMap { $0 as? CIFaceFeature }
    }

    private static func applyFaceShape(_ input: CIImage,
                                       faces: [CIFaceFeature],
                                       settings: PhotoEditSettings) -> CIImage {
        guard !faces.isEmpty else { return input }
        var output = input

        for face in faces {
            let bounds = face.bounds
            if settings.smallerHead > 0.001 {
                output = filter("CIBumpDistortion", output, [
                    kCIInputCenterKey: CIVector(x: bounds.midX, y: bounds.midY),
                    kCIInputRadiusKey: max(24, max(bounds.width, bounds.height) * 0.72),
                    kCIInputScaleKey: -0.16 * settings.smallerHead
                ])
            }

            if settings.slimFace > 0.001 {
                let radius = max(16, bounds.width * 0.24)
                let scale = -0.20 * settings.slimFace
                for x in [bounds.minX + bounds.width * 0.23,
                          bounds.minX + bounds.width * 0.77] {
                    output = filter("CIBumpDistortion", output, [
                        kCIInputCenterKey: CIVector(x: x, y: bounds.midY - bounds.height * 0.04),
                        kCIInputRadiusKey: radius,
                        kCIInputScaleKey: scale
                    ])
                }
            }

            if settings.enlargeEyes > 0.001 {
                let radius = max(10, bounds.width * 0.10)
                let scale = 0.24 * settings.enlargeEyes
                if face.hasLeftEyePosition {
                    output = filter("CIBumpDistortion", output, [
                        kCIInputCenterKey: CIVector(
                            x: face.leftEyePosition.x,
                            y: face.leftEyePosition.y
                        ),
                        kCIInputRadiusKey: radius,
                        kCIInputScaleKey: scale
                    ])
                }
                if face.hasRightEyePosition {
                    output = filter("CIBumpDistortion", output, [
                        kCIInputCenterKey: CIVector(
                            x: face.rightEyePosition.x,
                            y: face.rightEyePosition.y
                        ),
                        kCIInputRadiusKey: radius,
                        kCIInputScaleKey: scale
                    ])
                }
            }
        }
        return output
    }

    private static func smoothFaces(_ input: CIImage,
                                    faces: [CIFaceFeature],
                                    amount: Double) -> CIImage {
        guard amount > 0.001, !faces.isEmpty else { return input }
        let faceWidth = faces.map(\.bounds.width).reduce(0, +) / CGFloat(faces.count)
        let radius = max(2.5, min(16, faceWidth * 0.035))
        let blurred = filter("CIGaussianBlur", input, [
            kCIInputRadiusKey: radius
        ]).cropped(to: input.extent)

        var mask = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1))
            .cropped(to: input.extent)
        for face in faces {
            let bounds = face.bounds.insetBy(
                dx: -face.bounds.width * 0.04,
                dy: -face.bounds.height * 0.04
            )
            let white = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1))
                .cropped(to: bounds)
                .applyingFilter("CIGaussianBlur", parameters: [
                    kCIInputRadiusKey: max(8, bounds.width * 0.10)
                ])
                .cropped(to: input.extent)
            mask = white.composited(over: mask)
        }
        let strength = CGFloat(max(0, min(1, amount)))
        let scaledMask = filter("CIColorMatrix", mask, [
            "inputRVector": CIVector(x: strength, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: strength, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: strength, w: 0)
        ])
        return filter("CIBlendWithMask", blurred, [
            kCIInputBackgroundImageKey: input,
            kCIInputMaskImageKey: scaledMask
        ]).cropped(to: input.extent)
    }

    private static func normalized(_ image: UIImage, maxSide: CGFloat?) -> UIImage {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let longest = max(pixelWidth, pixelHeight)
        let scale = maxSide.map { min(1, $0 / max(1, longest)) } ?? 1
        let size = CGSize(width: max(1, pixelWidth * scale),
                          height: max(1, pixelHeight * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private static func colorControls(_ input: CIImage,
                                      saturation: CGFloat,
                                      contrast: CGFloat,
                                      brightness: CGFloat) -> CIImage {
        filter("CIColorControls", input, [
            kCIInputSaturationKey: saturation,
            kCIInputContrastKey: contrast,
            kCIInputBrightnessKey: brightness
        ])
    }

    private static func colorMatrix(_ input: CIImage,
                                    red: CGFloat,
                                    green: CGFloat,
                                    blue: CGFloat,
                                    bias: CIVector) -> CIImage {
        filter("CIColorMatrix", input, [
            "inputRVector": CIVector(x: red, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: green, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: blue, w: 0),
            "inputBiasVector": bias
        ])
    }

    private static func filter(_ name: String,
                               _ input: CIImage,
                               _ values: [String: Any]) -> CIImage {
        guard let filter = CIFilter(name: name) else { return input }
        filter.setValue(input, forKey: kCIInputImageKey)
        for (key, value) in values {
            filter.setValue(value, forKey: key)
        }
        return filter.outputImage ?? input
    }
}
