import SwiftUI
import UIKit
import Vision
import CoreImage

enum StarAvatarHairStyle: String, Codable, CaseIterable, Identifiable {
    case shortCrop
    case sidePart
    case centerPart
    case bob
    case shoulder
    case curly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shortCrop: return Tr("短寸")
        case .sidePart: return Tr("侧分")
        case .centerPart: return Tr("中分")
        case .bob: return Tr("短发波波")
        case .shoulder: return Tr("齐肩发")
        case .curly: return Tr("卷发")
        }
    }
}

enum StarAvatarGlassesStyle: String, Codable, CaseIterable, Identifiable {
    case rectangular
    case round
    case aviator

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rectangular: return Tr("方框")
        case .round: return Tr("圆框")
        case .aviator: return Tr("飞行员")
        }
    }
}

struct StarAvatarProfile: Codable, Equatable, Hashable {
    var skinHex: UInt32 = 0xD8A77F
    var hairHex: UInt32 = 0x171A20
    var eyeHex: UInt32 = 0x2E221B
    var faceWidth: Double = 1.0
    var faceLength: Double = 1.0
    var jawWidth: Double = 1.0
    var eyeSpacing: Double = 1.0
    var eyeSize: Double = 1.0
    var noseLength: Double = 1.0
    var mouthWidth: Double = 1.0
    var hairStyle: StarAvatarHairStyle = .sidePart
    var hasGlasses: Bool = false
    var glassesStyle: StarAvatarGlassesStyle = .rectangular
    var glassesHex: UInt32 = 0x17191D
    var glassesLensOpacity: Double = 0.16
    var confidence: Double = 0
    var generated: Bool = false
    var updatedAt: Date = .distantPast

    static let fallback = StarAvatarProfile()

    var skinUIColor: UIColor { UIColor(hex: skinHex) }
    var hairUIColor: UIColor { UIColor(hex: hairHex) }
    var eyeUIColor: UIColor { UIColor(hex: eyeHex) }
    var glassesUIColor: UIColor { UIColor(hex: glassesHex) }

    func clamped() -> StarAvatarProfile {
        var value = self
        value.faceWidth = min(1.16, max(0.84, faceWidth))
        value.faceLength = min(1.16, max(0.84, faceLength))
        value.jawWidth = min(1.16, max(0.84, jawWidth))
        value.eyeSpacing = min(1.18, max(0.82, eyeSpacing))
        value.eyeSize = min(1.25, max(0.76, eyeSize))
        value.noseLength = min(1.20, max(0.80, noseLength))
        value.mouthWidth = min(1.20, max(0.80, mouthWidth))
        value.glassesLensOpacity = min(0.42, max(0.04, glassesLensOpacity))
        value.confidence = min(1, max(0, confidence))
        return value
    }
}

enum StarAvatarProfileStore {
    private static let prefix = "star.avatar.profile."

    static func load(userID: String) -> StarAvatarProfile {
        let key = prefix + (userID.isEmpty ? "local" : userID)
        guard let data = UserDefaults.standard.data(forKey: key),
              let profile = try? JSONDecoder().decode(StarAvatarProfile.self, from: data) else {
            return .fallback
        }
        return profile.clamped()
    }

    static func save(_ profile: StarAvatarProfile, userID: String) {
        var value = profile.clamped()
        value.generated = true
        value.updatedAt = Date()
        let key = prefix + (userID.isEmpty ? "local" : userID)
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

enum StarAvatarPhotoError: LocalizedError {
    case invalidImage
    case noFace
    case multipleFaces
    case faceTooSmall
    case faceNotFrontal

    var errorDescription: String? {
        switch self {
        case .invalidImage: return Tr("照片无法读取，请换一张")
        case .noFace: return Tr("没有识别到清晰的人脸")
        case .multipleFaces: return Tr("请只保留一个人的照片")
        case .faceTooSmall: return Tr("离镜头近一点，让脸占画面更多")
        case .faceNotFrontal: return Tr("请使用正面照片，不要侧脸或遮挡")
        }
    }
}

private struct StarFaceAnalysis {
    let profile: StarAvatarProfile
}

enum StarAvatarPhotoAnalyzer {
    static func analyze(_ image: UIImage,
                        completion: @escaping (Result<StarAvatarProfile, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try analyzeSync(image)
                DispatchQueue.main.async { completion(.success(result)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private static func analyzeSync(_ image: UIImage) throws -> StarAvatarProfile {
        let upright = normalizedImage(image, maxSide: 720)
        guard let cg = upright.cgImage else { throw StarAvatarPhotoError.invalidImage }
        let width = CGFloat(cg.width)
        let height = CGFloat(cg.height)
        let request = VNDetectFaceLandmarksRequest()
        try VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
            .perform([request])
        let faces = (request.results ?? []).filter { $0.confidence > 0.35 }
        guard let face = faces.max(by: {
            $0.boundingBox.width * $0.boundingBox.height
                < $1.boundingBox.width * $1.boundingBox.height
        }) else {
            throw StarAvatarPhotoError.noFace
        }
        if faces.count > 1 { throw StarAvatarPhotoError.multipleFaces }
        let box = face.boundingBox
        if box.width < 0.18 || box.height < 0.24 {
            throw StarAvatarPhotoError.faceTooSmall
        }

        var profile = StarAvatarProfile.fallback
        profile.generated = true
        profile.updatedAt = Date()
        profile.confidence = Double(face.confidence)

        let faceAspect = box.height / max(0.001, box.width)
        profile.faceLength = clamp(Double(faceAspect / 1.27), 0.88, 1.14)
        profile.faceWidth = clamp(Double(1.27 / max(0.2, faceAspect)), 0.86, 1.14)

        if let landmarks = face.landmarks {
            if let left = center(landmarks.leftEye?.normalizedPoints, in: box),
               let right = center(landmarks.rightEye?.normalizedPoints, in: box) {
                let spacing = abs(right.x - left.x) / max(0.001, box.width)
                profile.eyeSpacing = clamp(Double(spacing / 0.39), 0.84, 1.16)
                let eyeY = (left.y + right.y) / 2
                let eyeSample = CGRect(
                    x: box.minX + box.width * 0.28,
                    y: box.minY + box.height * max(0.30, eyeY - 0.035),
                    width: box.width * 0.44,
                    height: box.height * 0.13
                )
                if let eye = averageColor(upright, normalizedRect: eyeSample),
                   let hex = eye.rgbHex {
                    profile.eyeHex = hex
                }
            }

            if let contour = landmarks.faceContour?.normalizedPoints, !contour.isEmpty {
                let lower = contour.filter { $0.y < 0.42 }
                if let minX = lower.map(\.x).min(), let maxX = lower.map(\.x).max() {
                    profile.jawWidth = clamp(Double((maxX - minX) / 0.82), 0.86, 1.14)
                }
            }

            if let nosePoints = landmarks.nose?.normalizedPoints, !nosePoints.isEmpty {
                let ys = nosePoints.map(\.y)
                if let lo = ys.min(), let hi = ys.max() {
                    profile.noseLength = clamp(Double((hi - lo) / 0.22), 0.84, 1.18)
                }
            }

            if let lips = landmarks.outerLips?.normalizedPoints, !lips.isEmpty {
                let xs = lips.map(\.x)
                if let lo = xs.min(), let hi = xs.max() {
                    profile.mouthWidth = clamp(Double((hi - lo) / 0.32), 0.84, 1.18)
                }
            }

            if let leftEye = landmarks.leftEye?.normalizedPoints, !leftEye.isEmpty {
                let ys = leftEye.map(\.y)
                if let lo = ys.min(), let hi = ys.max() {
                    profile.eyeSize = clamp(Double((hi - lo) / 0.08), 0.82, 1.20)
                }
            }
        }

        let cheekRect = CGRect(
            x: box.minX + box.width * 0.14,
            y: box.minY + box.height * 0.28,
            width: box.width * 0.72,
            height: box.height * 0.27
        )
        if let skin = averageColor(upright, normalizedRect: cheekRect),
           let hex = skin.rgbHex {
            profile.skinHex = hex
        }

        let hairCandidates = [
            CGRect(x: box.midX - box.width * 0.34,
                   y: box.maxY - box.height * 0.10,
                   width: box.width * 0.68,
                   height: box.height * 0.16),
            CGRect(x: box.minX,
                   y: box.maxY - box.height * 0.16,
                   width: box.width * 0.30,
                   height: box.height * 0.20),
            CGRect(x: box.maxX - box.width * 0.30,
                   y: box.maxY - box.height * 0.16,
                   width: box.width * 0.30,
                   height: box.height * 0.20),
        ]
        let sampledHair = hairCandidates.compactMap {
            averageColor(upright, normalizedRect: $0)
        }.min {
            $0.luminance < $1.luminance
        }
        if let hair = sampledHair, let hex = hair.rgbHex {
            profile.hairHex = hex
        }

        let classifications = classify(cg: cg, faceBox: box)
        let labels = classifications.map { $0.identifier.lowercased() }
        let hasGlassesLabel = labels.contains {
            $0.contains("eyeglass") || $0.contains("spectacle")
                || $0.contains("glasses") || $0.contains("sunglass")
                || $0.contains("eyewear")
        }
        profile.hasGlasses = hasGlassesLabel
        if labels.contains(where: { $0.contains("sunglass") }) {
            profile.glassesHex = 0x0B0D10
            profile.glassesLensOpacity = 0.30
        }

        if labels.contains(where: { $0.contains("long hair") || $0.contains("shoulder") }) {
            profile.hairStyle = .shoulder
        } else if labels.contains(where: { $0.contains("bob") }) {
            profile.hairStyle = .bob
        } else if labels.contains(where: { $0.contains("curly") || $0.contains("wavy") }) {
            profile.hairStyle = .curly
        } else if labels.contains(where: { $0.contains("bangs") || $0.contains("fringe") }) {
            profile.hairStyle = .centerPart
        } else if labels.contains(where: { $0.contains("short hair") || $0.contains("buzz") }) {
            profile.hairStyle = .shortCrop
        } else {
            profile.hairStyle = inferHairStyle(
                image: upright,
                faceBox: box,
                hair: sampledHair ?? UIColor(hex: profile.hairHex)
            )
        }

        return profile.clamped()
    }

    private static func normalizedImage(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, maxSide / max(1, longest))
        let size = CGSize(width: max(1, image.size.width * scale),
                          height: max(1, image.size.height * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private static func center(_ points: [CGPoint]?, in box: CGRect) -> CGPoint? {
        guard let points, !points.isEmpty else { return nil }
        let x = points.reduce(CGFloat.zero) { $0 + $1.x } / CGFloat(points.count)
        let y = points.reduce(CGFloat.zero) { $0 + $1.y } / CGFloat(points.count)
        return CGPoint(x: box.minX + x * box.width, y: box.minY + y * box.height)
    }

    private static func averageColor(_ image: UIImage,
                                     normalizedRect: CGRect) -> UIColor? {
        guard let ci = CIImage(image: image) else { return nil }
        let extent = ci.extent
        var rect = CGRect(
            x: normalizedRect.minX * extent.width,
            y: normalizedRect.minY * extent.height,
            width: normalizedRect.width * extent.width,
            height: normalizedRect.height * extent.height
        ).intersection(extent)
        guard rect.width > 2, rect.height > 2,
              let filter = CIFilter(name: "CIAreaAverage") else { return nil }
        filter.setValue(ci, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: rect), forKey: kCIInputExtentKey)
        guard let output = filter.outputImage else { return nil }
        var rgba = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])
            .render(output,
                    toBitmap: &rgba,
                    rowBytes: 4,
                    bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                    format: .RGBA8,
                    colorSpace: CGColorSpaceCreateDeviceRGB())
        return UIColor(
            red: CGFloat(rgba[0]) / 255,
            green: CGFloat(rgba[1]) / 255,
            blue: CGFloat(rgba[2]) / 255,
            alpha: 1
        )
    }

    private static func classify(cg: CGImage,
                                 faceBox: CGRect) -> [VNClassificationObservation] {
        let crop = CGRect(
            x: faceBox.minX - faceBox.width * 0.16,
            y: faceBox.minY - faceBox.height * 0.05,
            width: faceBox.width * 1.32,
            height: faceBox.height * 1.20
        ).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard crop.width > 0.02, crop.height > 0.02,
              let cropped = cg.cropping(to: CGRect(
                x: crop.minX * CGFloat(cg.width),
                y: (1 - crop.maxY) * CGFloat(cg.height),
                width: crop.width * CGFloat(cg.width),
                height: crop.height * CGFloat(cg.height)
              )) else { return [] }
        let request = VNClassifyImageRequest()
        try? VNImageRequestHandler(cgImage: cropped, orientation: .up, options: [:])
            .perform([request])
        return (request.results ?? []).filter { $0.confidence > 0.18 }
    }

    private static func inferHairStyle(image: UIImage,
                                       faceBox: CGRect,
                                       hair: UIColor) -> StarAvatarHairStyle {
        let sideRect = CGRect(
            x: max(0, faceBox.minX - faceBox.width * 0.24),
            y: faceBox.minY + faceBox.height * 0.18,
            width: faceBox.width * 0.20,
            height: faceBox.height * 0.54
        )
        let shoulderRect = CGRect(
            x: faceBox.minX + faceBox.width * 0.20,
            y: max(0, faceBox.minY - faceBox.height * 0.34),
            width: faceBox.width * 0.60,
            height: faceBox.height * 0.28
        )
        if let shoulder = averageColor(image, normalizedRect: shoulderRect),
           colorDistance(shoulder, hair) < 0.20 {
            return .shoulder
        }
        if let side = averageColor(image, normalizedRect: sideRect),
           colorDistance(side, hair) < 0.17 {
            return .bob
        }
        return faceBox.width / max(0.001, faceBox.height) > 0.80
            ? .sidePart
            : .shortCrop
    }

    private static func colorDistance(_ a: UIColor, _ b: UIColor) -> Double {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        let dr = Double(ar - br)
        let dg = Double(ag - bg)
        let db = Double(ab - bb)
        return sqrt(dr * dr + dg * dg + db * db)
    }

    private static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        min(high, max(low, value))
    }
}

private extension UIColor {
    var luminance: CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    var rgbHex: UInt32? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return (UInt32(max(0, min(1, r)) * 255) << 16)
            | (UInt32(max(0, min(1, g)) * 255) << 8)
            | UInt32(max(0, min(1, b)) * 255)
    }
}

struct StarAvatarPhotoStudioView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var profile: StarAvatarProfile
    let userID: String

    @State private var photo: UIImage?
    @State private var draft = StarAvatarProfile.fallback
    @State private var analyzing = false
    @State private var showCamera = false
    @State private var error: String?

    private let skinPalette: [UInt32] = [
        0xF3D5C3, 0xE8BE9F, 0xD8A77F, 0xBD825E, 0x8D593E, 0x57392C
    ]
    private let hairPalette: [UInt32] = [
        0x11151A, 0x2A201A, 0x4A3426, 0x765535, 0xA6783F, 0xC8B99D, 0x7D3D31
    ]
    private let glassesPalette: [UInt32] = [
        0x111214, 0x4C4943, 0xB99757, 0x765847, 0xC6CBD1
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    photoPanel
                    if analyzing { analysisPanel }
                    if draft.generated { editor }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, max(26, L.safeBottom + 16))
            }
            .background(C.pageBg.ignoresSafeArea())
            .navigationTitle(Tr("拍照生成形象"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(Tr("取消")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(Tr("保存")) { save() }
                        .fontWeight(.semibold)
                        .disabled(!draft.generated || analyzing)
                }
            }
        }
        .interactiveDismissDisabled(analyzing)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                showCamera = false
                runAnalysis(image)
            }
            .ignoresSafeArea()
        }
        .onAppear {
            draft = profile
            if !draft.generated {
                draft.generated = false
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Tr("只在本机分析"))
                .font(pfStyled(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: 0x75E1CC))
            Text(Tr("拍一张正面照，自动生成脸型、肤色、发型和眼镜"))
                .font(pfStyled(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(C.label)
            Text(Tr("照片只在内存中用于分析，不保存、不上传。戴眼镜时默认保留。"))
                .font(pfStyled(size: 13.5))
                .foregroundStyle(C.subLabel)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var photoPanel: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: 0x09242A),
                                Color(hex: 0x102E3A),
                                Color(hex: 0x12201D)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                if let photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .saturation(0.84)
                        .overlay(
                            LinearGradient(
                                colors: [.clear, Color.black.opacity(0.28)],
                                startPoint: .center,
                                endPoint: .bottom
                            )
                        )
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "faceid")
                            .font(.system(size: 52, weight: .light))
                            .foregroundStyle(Color(hex: 0x8FE8D7))
                        Text(Tr("脸部完整进入取景框"))
                            .font(pfStyled(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.82))
                    }
                }

                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.28),
                                Color(hex: 0x75E1CC).opacity(0.80),
                                Color.white.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )

                if analyzing {
                    ZStack {
                        Color.black.opacity(0.26)
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.2)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

            HStack(spacing: 10) {
                actionButton(Tr("拍照"), icon: "camera.fill") {
                    showCamera = true
                }
                actionButton(Tr("从相册选择"), icon: "photo.on.rectangle") {
                    AlbumPicker.present { runAnalysis($0) }
                }
            }

            if let error {
                Text(error)
                    .font(pfStyled(size: 12.5, weight: .medium))
                    .foregroundStyle(Color(hex: 0xE16F68))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(C.cardBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(C.hairline, lineWidth: 0.6)
                )
        )
    }

    private var analysisPanel: some View {
        HStack(spacing: 12) {
            ProgressView().tint(C.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(Tr("正在分析面部"))
                    .font(pfStyled(size: 14, weight: .semibold))
                    .foregroundStyle(C.label)
                Text(Tr("识别比例、肤色、发型与眼镜"))
                    .font(pfStyled(size: 11.5))
                    .foregroundStyle(C.subLabel)
            }
            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(C.cardBg))
    }

    private var editor: some View {
        VStack(spacing: 18) {
            sectionTitle(Tr("自动生成结果"), subtitle: String(format: Tr("识别可信度 %.0f%%"), draft.confidence * 100))

            VStack(spacing: 15) {
                sliderRow(Tr("脸宽"), value: $draft.faceWidth, range: 0.86...1.14)
                sliderRow(Tr("脸长"), value: $draft.faceLength, range: 0.86...1.14)
                sliderRow(Tr("下颌宽"), value: $draft.jawWidth, range: 0.86...1.14)
                sliderRow(Tr("眼距"), value: $draft.eyeSpacing, range: 0.84...1.16)
                sliderRow(Tr("眼睛大小"), value: $draft.eyeSize, range: 0.82...1.20)
                sliderRow(Tr("鼻长"), value: $draft.noseLength, range: 0.84...1.18)
                sliderRow(Tr("嘴宽"), value: $draft.mouthWidth, range: 0.84...1.18)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(C.cardBg))

            sectionTitle(Tr("肤色与发型"), subtitle: Tr("自动取样，可随时重新捏"))

            VStack(spacing: 15) {
                swatchRow(Tr("肤色"), colors: skinPalette, selection: $draft.skinHex)
                swatchRow(Tr("发色"), colors: hairPalette, selection: $draft.hairHex)
                HStack {
                    Text(Tr("发型"))
                        .font(pfStyled(size: 14))
                        .foregroundStyle(C.label)
                    Spacer()
                    Picker(Tr("发型"), selection: $draft.hairStyle) {
                        ForEach(StarAvatarHairStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(C.green)
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(C.cardBg))

            sectionTitle(Tr("眼镜"), subtitle: Tr("照片里检测到眼镜时会默认保留"))

            VStack(spacing: 15) {
                Toggle(isOn: $draft.hasGlasses) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Tr("保留眼镜"))
                            .font(pfStyled(size: 14, weight: .medium))
                            .foregroundStyle(C.label)
                        Text(Tr("镜片和镜框会随人物一起生成"))
                            .font(pfStyled(size: 11.5))
                            .foregroundStyle(C.subLabel)
                    }
                }
                .tint(C.green)

                if draft.hasGlasses {
                    HStack {
                        Text(Tr("镜框"))
                            .font(pfStyled(size: 14))
                            .foregroundStyle(C.label)
                        Spacer()
                        Picker(Tr("镜框"), selection: $draft.glassesStyle) {
                            ForEach(StarAvatarGlassesStyle.allCases) { style in
                                Text(style.title).tag(style)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(C.green)
                    }
                    swatchRow(Tr("镜框颜色"), colors: glassesPalette, selection: $draft.glassesHex)
                    sliderRow(Tr("镜片深浅"), value: $draft.glassesLensOpacity, range: 0.04...0.42)
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(C.cardBg))

            Button {
                save()
            } label: {
                Text(Tr("保存形象"))
                    .font(pfStyled(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: 0x1C8E7A), Color(hex: 0x55C6A4)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(pfStyled(size: 16, weight: .semibold))
                .foregroundStyle(C.label)
            Spacer()
            Text(subtitle)
                .font(pfStyled(size: 11.5))
                .foregroundStyle(C.subLabel)
                .lineLimit(1)
        }
    }

    private func sliderRow(_ title: String,
                           value: Binding<Double>,
                           range: ClosedRange<Double>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(pfStyled(size: 13.5))
                .foregroundStyle(C.label)
                .frame(width: 64, alignment: .leading)
            Slider(value: value, in: range)
                .tint(C.green)
            Text(String(format: "%.2f", value.wrappedValue))
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(C.subLabel)
                .frame(width: 34, alignment: .trailing)
        }
    }

    private func swatchRow(_ title: String,
                           colors: [UInt32],
                           selection: Binding<UInt32>) -> some View {
        HStack(spacing: 9) {
            Text(title)
                .font(pfStyled(size: 13.5))
                .foregroundStyle(C.label)
                .frame(width: 64, alignment: .leading)
            ForEach(colors, id: \.self) { hex in
                Button {
                    selection.wrappedValue = hex
                } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle()
                                .stroke(
                                    selection.wrappedValue == hex ? Color.white : Color.black.opacity(0.10),
                                    lineWidth: selection.wrappedValue == hex ? 2.5 : 0.7
                                )
                                .padding(selection.wrappedValue == hex ? -3 : 0)
                        )
                        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private func actionButton(_ title: String,
                              icon: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(pfStyled(size: 14, weight: .semibold))
                .foregroundStyle(C.label)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(C.fieldBg)
                )
        }
        .buttonStyle(.plain)
    }

    private func runAnalysis(_ image: UIImage) {
        photo = image
        error = nil
        analyzing = true
        StarAvatarPhotoAnalyzer.analyze(image) { result in
            analyzing = false
            switch result {
            case .success(let value):
                draft = value
            case .failure(let err):
                error = (err as? LocalizedError)?.errorDescription ?? err.localizedDescription
            }
        }
    }

    private func save() {
        let value = draft.clamped()
        profile = value
        StarAvatarProfileStore.save(value, userID: userID)
        photo = nil
        dismiss()
    }
}
