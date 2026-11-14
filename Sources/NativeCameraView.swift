import AVFoundation
import SwiftUI
import UIKit

enum NativeCameraMode: String, CaseIterable, Identifiable {
    case photo
    case video

    var id: String { rawValue }
    var title: String { self == .photo ? Tr("照片") : Tr("视频") }
}

final class NativeCameraController: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published private(set) var isReady = false
    @Published private(set) var denied = false
    @Published private(set) var microphoneDenied = false
    @Published private(set) var usingFront = false
    @Published private(set) var flashMode: AVCaptureDevice.FlashMode = .auto
    @Published private(set) var torchOn = false
    @Published private(set) var zoomFactor: CGFloat = 1
    @Published private(set) var maxZoom: CGFloat = 1
    @Published private(set) var isRecording = false
    @Published private(set) var recordingSeconds = 0
    @Published var capturedPhoto: UIImage?
    @Published var capturedVideo: URL?
    @Published var errorText = ""

    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let sessionQueue = DispatchQueue(label: "xingyan.native.camera")
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var configured = false
    private var recordingTimer: Timer?

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted { self.configureAndStart() }
                    else { self.denied = true }
                }
            }
        default:
            denied = true
        }
    }

    func stop() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func flip() {
        guard !isRecording else { return }
        replaceCamera()
    }

    func cycleFlash() {
        if torchOn {
            torchOn = false
            setTorch(false)
            flashMode = .auto
            return
        }
        switch flashMode {
        case .auto: flashMode = .on
        case .on: flashMode = .off
        case .off: flashMode = .auto
        @unknown default: flashMode = .auto
        }
    }

    var flashSymbol: String {
        if torchOn { return "bolt.fill" }
        switch flashMode {
        case .on: return "bolt.fill"
        case .off: return "bolt.slash.fill"
        default: return "bolt.badge.automatic.fill"
        }
    }

    func setZoom(_ zoom: CGFloat) {
        let factor = min(max(1, zoom), maxZoom)
        guard let device = currentDevice() else { return }
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = factor
            device.unlockForConfiguration()
            zoomFactor = factor
        } catch {
            errorText = Tr("无法调整缩放")
        }
    }

    func focus(at point: CGPoint) {
        guard point.x >= 0, point.x <= 1, point.y >= 0, point.y <= 1,
              let device = currentDevice() else { return }
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
            UISelectionFeedbackGenerator().selectionChanged()
        } catch { }
    }

    func capturePhoto() {
        guard isReady, !isRecording else { return }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let settings: AVCapturePhotoSettings
            if self.photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                settings = AVCapturePhotoSettings(format: [
                    AVVideoCodecKey: AVVideoCodecType.hevc
                ])
            } else {
                settings = AVCapturePhotoSettings()
            }
            if let device = self.currentDevice(), device.hasFlash,
               self.photoOutput.supportedFlashModes.contains(self.flashMode) {
                settings.flashMode = self.flashMode
            }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func toggleRecording() {
        if isRecording {
            movieOutput.stopRecording()
            return
        }
        guard isReady else { return }
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                self.microphoneDenied = !granted
                self.beginRecording(withAudio: granted)
            }
        }
    }

    private func configureAndStart() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.configured { self.configureSession() }
            guard self.configured else { return }
            if !self.session.isRunning { self.session.startRunning() }
            Task { @MainActor in self.isReady = true }
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        if session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
        } else {
            session.sessionPreset = .high
        }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            Task { @MainActor in self.denied = true }
            return
        }
        session.addInput(input)
        videoInput = input

        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
           let audio = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audio),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
            self.audioInput = audioInput
        }

        guard session.canAddOutput(photoOutput), session.canAddOutput(movieOutput) else {
            session.commitConfiguration()
            Task { @MainActor in self.errorText = Tr("相机输出初始化失败") }
            return
        }
        session.addOutput(photoOutput)
        session.addOutput(movieOutput)
        photoOutput.isHighResolutionCaptureEnabled = true
        movieOutput.maxRecordedDuration = CMTime(seconds: 60, preferredTimescale: 600)
        configureConnections()
        session.commitConfiguration()
        configured = true

        let maxZoom = min(8, device.activeFormat.videoMaxZoomFactor)
        Task { @MainActor in
            self.maxZoom = max(1, maxZoom)
            self.usingFront = false
        }
    }

    private func replaceCamera() {
        sessionQueue.async { [weak self] in
            guard let self, !self.isRecording else { return }
            let nextPosition: AVCaptureDevice.Position = self.currentDevice()?.position == .front
                ? .back : .front
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                       for: .video,
                                                       position: nextPosition),
                  let nextInput = try? AVCaptureDeviceInput(device: device) else { return }

            self.session.beginConfiguration()
            if let old = self.videoInput { self.session.removeInput(old) }
            if self.session.canAddInput(nextInput) {
                self.session.addInput(nextInput)
                self.videoInput = nextInput
            } else if let old = self.videoInput {
                self.session.addInput(old)
            }
            self.configureConnections()
            self.session.commitConfiguration()
            let maxZoom = min(8, device.activeFormat.videoMaxZoomFactor)
            Task { @MainActor in
                self.usingFront = device.position == .front
                self.maxZoom = max(1, maxZoom)
                self.zoomFactor = 1
            }
        }
    }

    private func configureConnections() {
        for output in [photoOutput, movieOutput] {
            guard let connection = output.connection(with: .video) else { continue }
            if #available(iOS 17.0, *) {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
            } else {
                connection.videoOrientation = .portrait
            }
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = currentDevice()?.position == .front
            }
        }
    }

    private func currentDevice() -> AVCaptureDevice? {
        videoInput?.device
    }

    private func setTorch(_ on: Bool) {
        guard let device = currentDevice(), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        } catch { }
    }

    private func beginRecording(withAudio: Bool) {
        guard !isRecording else { return }
        if !withAudio {
            errorText = Tr("视频将不包含声音，请在设置中开启麦克风")
        }
        let lightOn = flashMode == .on
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if withAudio, self.audioInput == nil,
               let audio = AVCaptureDevice.default(for: .audio),
               let input = try? AVCaptureDeviceInput(device: audio) {
                self.session.beginConfiguration()
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                    self.audioInput = input
                }
                self.session.commitConfiguration()
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("xingyan-native-\(UUID().uuidString).mov")
            self.configureConnections()
            self.setTorch(lightOn)
            self.movieOutput.startRecording(to: url, recordingDelegate: self)
            Task { @MainActor in
                self.torchOn = lightOn
                self.isRecording = true
                self.recordingSeconds = 0
                self.recordingTimer?.invalidate()
                self.recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.isRecording else { return }
                        self.recordingSeconds += 1
                        if self.recordingSeconds >= 60 { self.toggleRecording() }
                    }
                }
            }
        }
    }
}

extension NativeCameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }
        let marked = NativeCameraWatermark.apply(to: image)
        Task { @MainActor in
            self.capturedPhoto = marked
        }
    }
}

extension NativeCameraController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        Task { @MainActor in
            self.isRecording = false
            self.recordingTimer?.invalidate()
            self.recordingTimer = nil
            self.setTorch(false)
            self.torchOn = false
            if error == nil || FileManager.default.fileExists(atPath: outputFileURL.path) {
                self.capturedVideo = outputFileURL
            } else {
                self.errorText = Tr("视频保存失败")
            }
        }
    }
}

private enum NativeCameraWatermark {
    private static let timeFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy.MM.dd  HH:mm"
        return formatter
    }()

    static func apply(to image: UIImage) -> UIImage {
        guard image.size.width > 1, image.size.height > 1 else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: image.size))

            let shortSide = min(image.size.width, image.size.height)
            let unit = max(0.72, min(1.65, shortSide / 1080))
            let margin = 26 * unit
            let cardHeight = 54 * unit
            let cardRadius = cardHeight / 2
            let logoSize = 36 * unit
            let brandSize = 13.2 * unit
            let detailSize = 9.8 * unit
            let rounded = UIFont.systemFont(ofSize: brandSize, weight: .semibold)
                .fontDescriptor.withDesign(.rounded) ?? UIFont.systemFont(ofSize: brandSize,
                                                                          weight: .semibold)
            let brandFont = UIFont(descriptor: rounded, size: brandSize)
            let detailFont = UIFont.monospacedDigitSystemFont(ofSize: detailSize,
                                                              weight: .medium)
            let brand = "Star Chat" as NSString
            let time = timeFormat.string(from: Date()) as NSString
            let brandAttributes: [NSAttributedString.Key: Any] = [
                .font: brandFont,
                .foregroundColor: UIColor.white.withAlphaComponent(0.94),
                .kern: 0.1 * unit
            ]
            let timeAttributes: [NSAttributedString.Key: Any] = [
                .font: detailFont,
                .foregroundColor: UIColor.white.withAlphaComponent(0.60),
                .kern: 0.3 * unit
            ]
            let brandBox = brand.size(withAttributes: brandAttributes)
            let timeBox = time.size(withAttributes: timeAttributes)
            let textGap = 2.2 * unit
            let horizontalPad = 10 * unit
            let logoGap = 10 * unit
            let cardWidth = horizontalPad + logoSize + logoGap
                + max(brandBox.width, timeBox.width) + horizontalPad
            let cardRect = CGRect(
                x: margin,
                y: image.size.height - margin - cardHeight,
                width: cardWidth,
                height: cardHeight
            )

            context.cgContext.saveGState()
            context.cgContext.setShadow(
                offset: CGSize(width: 0, height: 4 * unit),
                blur: 14 * unit,
                color: UIColor.black.withAlphaComponent(0.24).cgColor
            )
            let card = UIBezierPath(roundedRect: cardRect, cornerRadius: cardRadius)
            UIColor.black.withAlphaComponent(0.30).setFill()
            card.fill()
            context.cgContext.restoreGState()

            let glass = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor.white.withAlphaComponent(0.14).cgColor,
                    UIColor.white.withAlphaComponent(0.025).cgColor
                ] as CFArray,
                locations: [0, 1]
            )
            if let glass {
                context.cgContext.saveGState()
                card.addClip()
                context.cgContext.drawLinearGradient(
                    glass,
                    start: CGPoint(x: cardRect.midX, y: cardRect.minY),
                    end: CGPoint(x: cardRect.midX, y: cardRect.maxY),
                    options: []
                )
                context.cgContext.restoreGState()
            }
            UIColor.white.withAlphaComponent(0.18).setStroke()
            card.lineWidth = 0.8 * unit
            card.stroke()

            let logoRect = CGRect(
                x: cardRect.minX + horizontalPad,
                y: cardRect.midY - logoSize / 2,
                width: logoSize,
                height: logoSize
            )
            let logoPath = UIBezierPath(
                roundedRect: logoRect,
                cornerRadius: logoSize * 0.30
            )
            context.cgContext.saveGState()
            logoPath.addClip()
            let brandGradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor(red: 0.22, green: 0.86, blue: 0.52, alpha: 1).cgColor,
                    UIColor(red: 0.02, green: 0.52, blue: 0.98, alpha: 1).cgColor
                ] as CFArray,
                locations: [0, 1]
            )
            if let brandGradient {
                context.cgContext.drawLinearGradient(
                    brandGradient,
                    start: CGPoint(x: logoRect.minX, y: logoRect.minY),
                    end: CGPoint(x: logoRect.maxX, y: logoRect.maxY),
                    options: []
                )
            }
            context.cgContext.restoreGState()

            if let star = UIImage(systemName: "star.fill")?
                .withTintColor(.white.withAlphaComponent(0.96),
                               renderingMode: .alwaysOriginal) {
                let starSide = logoSize * 0.58
                star.draw(in: CGRect(
                    x: logoRect.midX - starSide / 2,
                    y: logoRect.midY - starSide / 2,
                    width: starSide,
                    height: starSide
                ))
            }

            let textX = logoRect.maxX + logoGap
            let brandY = cardRect.midY - textGap / 2 - brandBox.height
            brand.draw(at: CGPoint(x: textX, y: brandY),
                       withAttributes: brandAttributes)
            time.draw(at: CGPoint(x: textX, y: cardRect.midY + textGap / 2),
                      withAttributes: timeAttributes)

            let cameraAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 8.2 * unit, weight: .semibold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.48),
                .kern: 1.6 * unit
            ]
            let camera = "XINGYAN CAMERA" as NSString
            let cameraBox = camera.size(withAttributes: cameraAttributes)
            camera.draw(
                at: CGPoint(
                    x: image.size.width - margin - cameraBox.width,
                    y: image.size.height - margin - cameraBox.height
                ),
                withAttributes: cameraAttributes
            )
        }
    }
}

struct NativeCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
    }
}

struct NativeCameraView: View {
    let initialMode: NativeCameraMode
    let onPick: (UIImage) -> Void
    let onVideo: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = NativeCameraController()
    @State private var mode: NativeCameraMode
    @State private var selectedImage: UIImage?
    @State private var selectedVideo: URL?
    @State private var showGrid = false
    @State private var focusPoint: CGPoint?
    @State private var zoomStart: CGFloat = 1
    @State private var flashOverlay = false

    init(initialMode: NativeCameraMode = .photo,
         onPick: @escaping (UIImage) -> Void,
         onVideo: @escaping (URL) -> Void) {
        self.initialMode = initialMode
        self.onPick = onPick
        self.onVideo = onVideo
        _mode = State(initialValue: initialMode)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                if camera.denied {
                    permissionView
                } else {
                    NativeCameraPreview(session: camera.session)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                                .onEnded { value in
                                    focusPoint = value.location
                                    let point = CGPoint(
                                        x: value.location.x / max(1, geo.size.width),
                                        y: value.location.y / max(1, geo.size.height)
                                    )
                                    camera.focus(at: point)
                                    withAnimation(.easeOut(duration: 0.18)) {
                                        focusPoint = value.location
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                                        withAnimation(.easeOut(duration: 0.15)) {
                                            focusPoint = nil
                                        }
                                    }
                                }
                        )
                        .simultaneousGesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    camera.setZoom(zoomStart * value)
                                }
                                .onEnded { _ in zoomStart = camera.zoomFactor }
                        )

                    if showGrid { gridOverlay }

                    if let focusPoint {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.yellow, lineWidth: 1.4)
                            .frame(width: 62, height: 62)
                            .position(focusPoint)
                            .transition(.scale(scale: 1.35).combined(with: .opacity))
                    }

                    VStack(spacing: 0) {
                        topBar
                        Spacer()
                        if camera.isRecording { recordingBadge }
                        zoomBadge
                        bottomBar
                    }
                    .padding(.top, max(8, geo.safeAreaInsets.top + 4))
                    .padding(.bottom, max(12, geo.safeAreaInsets.bottom + 8))
                    .padding(.horizontal, 16)
                }

                if flashOverlay {
                    Color.white.opacity(0.88).ignoresSafeArea()
                }

                if let image = selectedImage {
                    reviewImage(image)
                } else if let url = selectedVideo {
                    reviewVideo(url)
                }
            }
        }
        .statusBarHidden(true)
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
        .onChange(of: camera.capturedPhoto) { image in
            guard let image else { return }
            selectedImage = image
            camera.capturedPhoto = nil
        }
        .onChange(of: camera.capturedVideo) { url in
            guard let url else { return }
            selectedVideo = url
            camera.capturedVideo = nil
        }
        .alert(Tr("相机提示"), isPresented: Binding(
            get: { !camera.errorText.isEmpty },
            set: { if !$0 { camera.errorText = "" } }
        )) {
            Button(Tr("好")) { camera.errorText = "" }
        } message: {
            Text(camera.errorText)
        }
    }

    private var topBar: some View {
        HStack {
            circleButton("xmark") { close() }
            Spacer()
            if camera.isRecording {
                EmptyView()
            } else {
                circleButton(camera.flashSymbol) { camera.cycleFlash() }
                circleButton(showGrid ? "grid" : "grid.circle") {
                    withAnimation(.easeOut(duration: 0.15)) { showGrid.toggle() }
                }
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 16) {
            HStack(spacing: 4) {
                ForEach(NativeCameraMode.allCases) { item in
                    Button {
                        guard !camera.isRecording else { return }
                        withAnimation(.easeOut(duration: 0.18)) { mode = item }
                    } label: {
                        Text(item.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(mode == item ? Color.black : Color.white)
                            .frame(width: 72, height: 30)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(mode == item ? Color.white : Color.white.opacity(0.14))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(Capsule(style: .continuous).fill(Color.black.opacity(0.26)))

            HStack {
                Button {
                    AlbumPicker.present { image in
                        camera.stop()
                        onPick(image)
                        dismiss()
                    }
                } label: {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(Color.black.opacity(0.28)))
                }
                .buttonStyle(.plain)
                .disabled(camera.isRecording)

                Spacer()

                Button {
                    if mode == .photo { takePhoto() }
                    else { camera.toggleRecording() }
                } label: {
                    ZStack {
                        Circle()
                            .stroke(Color.white, lineWidth: 4)
                            .frame(width: 78, height: 78)
                        if mode == .photo {
                            Circle().fill(Color.white).frame(width: 62, height: 62)
                        } else {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 62, height: 62)
                            RoundedRectangle(cornerRadius: camera.isRecording ? 6 : 31,
                                             style: .continuous)
                                .fill(Color.white)
                                .frame(width: camera.isRecording ? 24 : 30,
                                       height: camera.isRecording ? 24 : 30)
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Button { camera.flip() } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(Color.black.opacity(0.28)))
                }
                .buttonStyle(.plain)
                .disabled(camera.isRecording)
            }
        }
    }

    private var zoomBadge: some View {
        HStack(spacing: 6) {
            ForEach([CGFloat(1), CGFloat(2)], id: \.self) { value in
                Button {
                    zoomStart = value
                    camera.setZoom(value)
                } label: {
                    Text("\(Int(value))×")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(abs(camera.zoomFactor - value) < 0.2
                                         ? Color.black : Color.white)
                        .frame(width: 34, height: 34)
                        .background(
                            Circle().fill(abs(camera.zoomFactor - value) < 0.2
                                          ? Color.white : Color.black.opacity(0.28))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 14)
    }

    private var recordingBadge: some View {
        HStack(spacing: 7) {
            Circle().fill(Color.red).frame(width: 8, height: 8)
            Text(String(format: "%02d:%02d",
                        camera.recordingSeconds / 60,
                        camera.recordingSeconds % 60))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Capsule().fill(Color.black.opacity(0.42)))
        .padding(.bottom, 14)
    }

    private var gridOverlay: some View {
        GeometryReader { geo in
            Path { path in
                for i in 1...2 {
                    let x = geo.size.width * CGFloat(i) / 3
                    let y = geo.size.height * CGFloat(i) / 3
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geo.size.height))
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geo.size.width, y: y))
                }
            }
            .stroke(Color.white.opacity(0.28), lineWidth: 0.7)
        }
        .allowsHitTesting(false)
    }

    private var permissionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 34, weight: .medium))
            Text(Tr("需要相机权限"))
                .font(.title3.weight(.semibold))
            Text(Tr("到系统设置中允许星言使用相机后再回来"))
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button(Tr("打开设置")) {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(width: 180, height: 44)
            .background(Capsule().fill(Color.blue))
            Button(Tr("关闭")) { close() }
                .foregroundStyle(.white.opacity(0.8))
        }
        .foregroundStyle(.white)
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private func reviewImage(_ image: UIImage) -> some View {
        VStack(spacing: 0) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            reviewActions {
                selectedImage = nil
                camera.start()
            } onUse: {
                camera.stop()
                onPick(image)
                dismiss()
            }
        }
        .background(Color.black.ignoresSafeArea())
    }

    private func reviewVideo(_ url: URL) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Image(systemName: "video.fill")
                    .font(.system(size: 48))
                Text(Tr("视频已录制"))
                    .font(.title3.weight(.semibold))
                Text("\(camera.recordingSeconds)s")
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            reviewActions {
                try? FileManager.default.removeItem(at: url)
                selectedVideo = nil
                camera.start()
            } onUse: {
                camera.stop()
                onVideo(url)
                dismiss()
            }
        }
    }

    private func reviewActions(onRetake: @escaping () -> Void,
                               onUse: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Button(Tr("重拍"), action: onRetake)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Capsule().fill(Color.white.opacity(0.16)))
            Button(Tr("使用"), action: onUse)
                .font(.headline)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Capsule().fill(Color.white))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .background(Color.black)
    }

    private func circleButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.black.opacity(0.30)))
        }
        .buttonStyle(.plain)
    }

    private func takePhoto() {
        flashOverlay = true
        withAnimation(.easeOut(duration: 0.1)) { flashOverlay = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            withAnimation(.easeIn(duration: 0.14)) { flashOverlay = false }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        camera.capturePhoto()
    }

    private func close() {
        camera.stop()
        dismiss()
    }
}
