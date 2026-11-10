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

private enum PhotoEditorMode: String, CaseIterable, Identifiable {
    case filters
    case beauty
    case adjust

    var id: String { rawValue }

    var title: String {
        switch self {
        case .filters: return Tr("滤镜")
        case .beauty: return Tr("美颜")
        case .adjust: return Tr("调整")
        }
    }

    var symbol: String {
        switch self {
        case .filters: return "camera.filters"
        case .beauty: return "face.smiling"
        case .adjust: return "slider.horizontal.3"
        }
    }
}

private enum PhotoBeautyTool: String, CaseIterable, Identifiable {
    case smooth
    case slimFace
    case enlargeEyes
    case smallerHead

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smooth: return Tr("磨皮")
        case .slimFace: return Tr("瘦脸")
        case .enlargeEyes: return Tr("大眼")
        case .smallerHead: return Tr("小头")
        }
    }

    var symbol: String {
        switch self {
        case .smooth: return "sparkles"
        case .slimFace: return "person.crop.circle"
        case .enlargeEyes: return "eye"
        case .smallerHead: return "person.crop.square"
        }
    }
}

private enum PhotoAdjustTool: String, CaseIterable, Identifiable {
    case brightness
    case contrast
    case saturation
    case sharpen
    case vignette

    var id: String { rawValue }

    var title: String {
        switch self {
        case .brightness: return Tr("亮度")
        case .contrast: return Tr("对比度")
        case .saturation: return Tr("饱和度")
        case .sharpen: return Tr("锐化")
        case .vignette: return Tr("暗角")
        }
    }

    var symbol: String {
        switch self {
        case .brightness: return "sun.max"
        case .contrast: return "circle.lefthalf.filled"
        case .saturation: return "drop"
        case .sharpen: return "wand.and.rays"
        case .vignette: return "camera.aperture"
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .brightness: return -0.2...0.2
        case .contrast: return -0.2...0.4
        case .saturation: return -0.3...0.5
        case .sharpen, .vignette: return 0...1
        }
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
    @State private var mode: PhotoEditorMode = .beauty
    @State private var beautyTool: PhotoBeautyTool = .smooth
    @State private var adjustTool: PhotoAdjustTool = .brightness
    @State private var presetThumbs: [String: UIImage] = [:]
    @State private var showOriginal = false
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
        ZStack {
            Color.black

            Image(uiImage: showOriginal ? image : preview)
                .resizable()
                .scaledToFit()
                .padding(.horizontal, 4)

            if rendering || exporting {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .padding(12)
                    .background(.ultraThinMaterial, in: Circle())
            }

            VStack(spacing: 0) {
                header
                Spacer(minLength: 0)
                controls
            }

            .overlay(alignment: .topTrailing) {
                Button {
                    showOriginal.toggle()
                } label: {
                    Label(showOriginal ? Tr("返回效果") : Tr("对比原图"),
                          systemImage: showOriginal ? "wand.and.stars" : "eye")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 11)
                        .frame(height: 32)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, L.safeTop + 64)
                .padding(.trailing, 12)
            }
        }
        .ignoresSafeArea()
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
        .task { await buildPresetThumbs() }
        .alert(Tr("处理失败，再试一次"), isPresented: Binding(
            get: { !errorText.isEmpty },
            set: { if !$0 { errorText = "" } }
        )) {
            Button(Tr("好"), role: .cancel) { errorText = "" }
        }
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Tr("取消"))

            Spacer()

            Text(Tr("编辑照片"))
                .font(.system(size: 15.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))

            Spacer()

            Button {
                export()
            } label: {
                Text(exporting ? Tr("照片处理中…") : Tr("完成"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 15)
                    .frame(height: 36)
                    .background(C.green, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(rendering || exporting)
        }
        .padding(.horizontal, 14)
        .padding(.top, L.safeTop)
        .frame(height: 58 + L.safeTop)
        .background {
            LinearGradient(
                colors: [Color.black.opacity(0.78), Color.black.opacity(0.20), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var controls: some View {
        VStack(spacing: 0) {
            modePanel
                .frame(height: 148, alignment: .top)

            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 0.5)

            HStack(spacing: 0) {
                ForEach(PhotoEditorMode.allCases) { item in
                    modeButton(item)
                }
                roundToolButton(Tr("旋转"), "rotate.right") {
                    quarterTurns = (quarterTurns + 1) % 4
                }
                roundToolButton(Tr("复位"), "arrow.counterclockwise") {
                    reset()
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 9)
            .padding(.bottom, max(12, L.safeBottom))
        }
        .background {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.30),
                    Color.black.opacity(0.88),
                    Color(hex: 0x080809)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    @ViewBuilder
    private var modePanel: some View {
        switch mode {
        case .filters:
            VStack(spacing: 7) {
                if preset != .original {
                    focusedSlider(Tr("滤镜强度"), symbol: "camera.filters",
                                  value: $amount, range: 0...1)
                } else {
                    Spacer().frame(height: 43)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        ForEach(PhotoEditPreset.allCases) { item in
                            filterCard(item)
                        }
                    }
                    .padding(.horizontal, 14)
                }
            }
            .padding(.top, 8)
        case .beauty:
            VStack(spacing: 7) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(PhotoBeautyTool.allCases) { tool in
                            subToolButton(tool.title, symbol: tool.symbol,
                                          selected: beautyTool == tool) {
                                beautyTool = tool
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                }
                focusedSlider(beautyTool.title, symbol: beautyTool.symbol,
                              value: beautyBinding, range: 0...1)
            }
            .padding(.top, 8)
        case .adjust:
            VStack(spacing: 7) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(PhotoAdjustTool.allCases) { tool in
                            subToolButton(tool.title, symbol: tool.symbol,
                                          selected: adjustTool == tool) {
                                adjustTool = tool
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                }
                focusedSlider(adjustTool.title, symbol: adjustTool.symbol,
                              value: adjustBinding, range: adjustTool.range)
            }
            .padding(.top, 8)
        }
    }

    private func roundToolButton(_ title: String, _ symbol: String,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                Text(title)
                    .font(.system(size: 9.5, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.62))
            .frame(maxWidth: .infinity)
            .frame(height: 47)
        }
        .buttonStyle(.plain)
    }

    private func modeButton(_ item: PhotoEditorMode) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) { mode = item }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: item.symbol)
                    .font(.system(size: 18, weight: .medium))
                Text(item.title)
                    .font(.system(size: 9.5, weight: mode == item ? .semibold : .medium))
            }
            .foregroundStyle(mode == item ? C.green : Color.white.opacity(0.62))
            .frame(maxWidth: .infinity)
            .frame(height: 47)
        }
        .buttonStyle(.plain)
    }

    private func subToolButton(_ title: String, symbol: String,
                               selected: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 12.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: selected ? .semibold : .medium))
            }
            .foregroundStyle(selected ? Color.white : Color.white.opacity(0.62))
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background {
                Capsule()
                    .fill(selected ? C.green.opacity(0.30) : Color.white.opacity(0.06))
            }
            .overlay {
                Capsule()
                    .stroke(selected ? C.green.opacity(0.55) : Color.white.opacity(0.06),
                            lineWidth: 0.6)
            }
        }
        .buttonStyle(.plain)
    }

    private func focusedSlider(_ title: String, symbol: String,
                               value: Binding<Double>,
                               range: ClosedRange<Double>) -> some View {
        VStack(spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(C.green)
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                Spacer(minLength: 0)
                Text(String(format: "%.0f", normalizedPercent(value.wrappedValue, range: range)))
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.56))
            }
            .padding(.horizontal, 18)

            Slider(value: value, in: range)
                .tint(C.green)
                .padding(.horizontal, 16)
        }
        .frame(height: 42)
    }

    private func normalizedPercent(_ value: Double, range: ClosedRange<Double>) -> Double {
        guard range.upperBound > range.lowerBound else { return 0 }
        return (value - range.lowerBound) / (range.upperBound - range.lowerBound) * 100
    }

    private func filterCard(_ item: PhotoEditPreset) -> some View {
        let selected = preset == item
        let thumb = presetThumbs[item.id]
        return Button {
            preset = item
            if item == .original { amount = 0.65 }
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    Image(uiImage: thumb ?? image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 62, height: 62)
                        .clipped()
                    if thumb == nil && item != .original {
                        Color.black.opacity(0.24)
                        Image(systemName: item.symbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.88))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(selected ? C.green : Color.white.opacity(0.10),
                                lineWidth: selected ? 2 : 0.7)
                }
                Text(item.title)
                    .font(.system(size: 10.5, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? C.green : Color.white.opacity(0.76))
                    .lineLimit(1)
            }
            .frame(width: 68)
        }
        .buttonStyle(.plain)
    }

    private var beautyBinding: Binding<Double> {
        Binding(
            get: {
                switch beautyTool {
                case .smooth: return settings.smooth
                case .slimFace: return settings.slimFace
                case .enlargeEyes: return settings.enlargeEyes
                case .smallerHead: return settings.smallerHead
                }
            },
            set: { value in
                switch beautyTool {
                case .smooth: settings.smooth = value
                case .slimFace: settings.slimFace = value
                case .enlargeEyes: settings.enlargeEyes = value
                case .smallerHead: settings.smallerHead = value
                }
            }
        )
    }

    private var adjustBinding: Binding<Double> {
        Binding(
            get: {
                switch adjustTool {
                case .brightness: return settings.brightness
                case .contrast: return settings.contrast
                case .saturation: return settings.saturation
                case .sharpen: return settings.sharpen
                case .vignette: return settings.vignette
                }
            },
            set: { value in
                switch adjustTool {
                case .brightness: settings.brightness = value
                case .contrast: settings.contrast = value
                case .saturation: settings.saturation = value
                case .sharpen: settings.sharpen = value
                case .vignette: settings.vignette = value
                }
            }
        )
    }

    private func reset() {
        preset = .original
        amount = 0.65
        quarterTurns = 0
        settings = .neutral
        mode = .beauty
        beautyTool = .smooth
        adjustTool = .brightness
        showOriginal = false
    }

    private func buildPresetThumbs() async {
        for item in PhotoEditPreset.allCases where item != .original {
            if Task.isCancelled { return }
            if presetThumbs[item.id] != nil { continue }
            let output = await Task.detached(priority: .utility) {
                PhotoEditRenderer.render(
                    image,
                    preset: item,
                    amount: 0.65,
                    quarterTurns: 0,
                    settings: .neutral,
                    maxSide: 180
                )
            }.value
            if Task.isCancelled { return }
            if let output { presetThumbs[item.id] = output }
        }
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
