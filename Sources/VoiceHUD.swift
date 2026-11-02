import SwiftUI

enum VoiceOrbMode: Int {
    case idle = 0
    case listening = 1
    case transcribing = 2
    case cancelling = 3
    case thinking = 4
    case speaking = 5
    case failed = 6

    var palette: [Color] {
        switch self {
        case .idle:
            return [Color(hex: 0x3B7CFF), Color(hex: 0x8A5BFF),
                    Color(hex: 0xFF5AA8), Color(hex: 0x3AD6FF)]
        case .listening:
            return [Color(hex: 0x2678FF), Color(hex: 0x865CFF),
                    Color(hex: 0xFF4E9D), Color(hex: 0x2DE2FF)]
        case .transcribing:
            return [Color(hex: 0x22C979), Color(hex: 0x31CFBE),
                    Color(hex: 0x91EE75), Color(hex: 0x54DDFF)]
        case .cancelling:
            return [Color(hex: 0xFF4A3C), Color(hex: 0xFF6A3C),
                    Color(hex: 0xFF6B6B), Color(hex: 0xFFB03C)]
        case .thinking:
            return [Color(hex: 0x3C72FF), Color(hex: 0x726CFF),
                    Color(hex: 0xC56DFF), Color(hex: 0x45D8FF)]
        case .speaking:
            return [Color(hex: 0x4D9CFF), Color(hex: 0x8A6CFF),
                    Color(hex: 0xFF6AB5), Color(hex: 0x5BE7D8)]
        case .failed:
            return [Color(hex: 0xFF6B5E), Color(hex: 0xD84A68),
                    Color(hex: 0xFF8B42), Color(hex: 0xA35BFF)]
        }
    }
}

@available(iOS 17.0, *)
private struct VoiceOrbSurface: View {
    let phase: Double
    let level: CGFloat
    let mode: VoiceOrbMode
    let canvas: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var smoothLevel: Double = 0.08
    @State private var driveLow: Double = 0.08
    @State private var driveHigh: Double = 0.05
    @State private var previousLevel: Double = 0.08

    private var palette: [Color] { mode.palette }
    private var lowPower: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }
    private var renderScale: CGFloat {
        if lowPower { return 1.35 }
        let targetPoints = 2048 / max(UIScreen.main.scale, 1)
        return max(1.8, min(4.2, targetPoints / max(canvas, 1)))
    }
    private var tempo: Double {
        switch mode {
        case .idle: return 0.72
        case .listening: return 1.0
        case .transcribing: return 1.18
        case .cancelling: return 1.34
        case .thinking: return 1.48
        case .speaking: return 1.10
        case .failed: return 0.88
        }
    }

    var body: some View {
        let colors = palette
        let t = phase * tempo * (reduceMotion ? 0.45 : 1)
        let renderCanvas = canvas * renderScale
        let shader = Circle()
            .fill(RadialGradient(colors: [Color.black,
                                          Color.black.opacity(0.92),
                                          Color.black.opacity(0.48),
                                          Color.black.opacity(0.0)],
                                 center: .center,
                                 startRadius: 0,
                                 endRadius: renderCanvas * 0.5))
            .frame(width: renderCanvas, height: renderCanvas)
            .colorEffect(ShaderLibrary.voiceOrb(
                .float(t.truncatingRemainder(dividingBy: 1000)),
                .float(renderCanvas), .float(renderCanvas),
                .color(colors[0]), .color(colors[1]),
                .color(colors[2]), .color(colors[3]),
                .float(max(0.04, smoothLevel)),
                .float(UIConfig.num("voiceOrbGlass", 0.65)),
                .float(0.42),
                .float(driveLow),
                .float(driveHigh),
                .float(Double(mode.rawValue))))

        ZStack {
            shader

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.42), Color.clear],
                        center: UnitPoint(x: 0.30, y: 0.24),
                        startRadius: 0,
                        endRadius: renderCanvas * 0.26
                    )
                )
                .frame(width: renderCanvas * 0.84,
                       height: renderCanvas * 0.84)
                .blendMode(.screen)
                .allowsHitTesting(false)

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.50),
                                 Color.white.opacity(0.06),
                                 Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: renderCanvas * 0.22,
                       height: renderCanvas * 0.075)
                .rotationEffect(.degrees(-32))
                .offset(x: -renderCanvas * 0.15,
                        y: -renderCanvas * 0.22)
                .blur(radius: 1.4)
                .blendMode(.screen)
                .allowsHitTesting(false)

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.70),
                                 Color.white.opacity(0.08),
                                 colors[3].opacity(0.42)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.25
                )
                .frame(width: renderCanvas * 0.84,
                       height: renderCanvas * 0.84)
                .blur(radius: 0.35)
                .allowsHitTesting(false)
        }
        .frame(width: renderCanvas, height: renderCanvas)
        .scaleEffect(1 / renderScale)
        .frame(width: canvas, height: canvas)
        .clipShape(Circle())
        .onAppear { updateBands(level) }
        .onChange(of: level) { value in updateBands(value) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("语音")
        .accessibilityValue(mode.accessibilityValue)
    }

    private func updateBands(_ raw: CGFloat) {
        let value = max(0.03, min(1, Double(raw)))
        let delta = abs(value - previousLevel)
        previousLevel = value

        let attack = Double(UIConfig.num("voiceOrbAttack", 0.58))
        let release = Double(UIConfig.num("voiceOrbRelease", 0.16))
        let lowTarget = min(1, value * 0.92 + 0.05)
        let highTarget = min(1, delta * 5.2 + max(0, value - 0.46) * 0.38)

        smoothLevel += (value - smoothLevel) * (value > smoothLevel ? attack : release)
        driveLow += (lowTarget - driveLow) * (lowTarget > driveLow ? attack : release)
        driveHigh += (highTarget - driveHigh) * (highTarget > driveHigh ? 0.72 : 0.20)
    }
}

private extension VoiceOrbMode {
    var accessibilityValue: String {
        switch self {
        case .idle: return "待机"
        case .listening: return "正在聆听"
        case .transcribing: return "准备转文字"
        case .cancelling: return "准备取消"
        case .thinking: return "正在处理"
        case .speaking: return "正在回答"
        case .failed: return "处理失败"
        }
    }
}

struct VoiceHUD: View {
    let seconds: Int
    let level: CGFloat
    let willCancel: Bool
    var willTranscribe: Bool = false
    var maxSeconds: Int = 60
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var frameInterval: Double {
        if reduceMotion || ProcessInfo.processInfo.isLowPowerModeEnabled {
            return 1.0 / 30.0
        }
        let fps = max(60, min(120, UIScreen.main.maximumFramesPerSecond))
        return 1.0 / Double(fps)
    }

    private var colors: [Color] {
        if willCancel {
            return [Color(hex: 0xFF7A6B), Color(hex: 0xFF3B30), Color(hex: 0xFF9F0A)]
        }
        if willTranscribe {
            return [Color(hex: 0x2BD07A), Color(hex: 0x34C7E0), Color(hex: 0xB7F06A)]
        }
        return [Color(hex: 0x5B8CFF), Color(hex: 0xA45BFF), Color(hex: 0xFF5BA8)]
    }

    private var accent: Color {
        if willCancel { return Color(hex: 0xFF5B4D) }
        if willTranscribe { return Color(hex: 0x2BD07A) }
        return Color(hex: 0x7C8CFF)
    }

    private var progress: Double {
        guard maxSeconds > 0 else { return 0 }
        return max(0, min(1, Double(seconds) / Double(maxSeconds)))
    }

    private var nearlyDone: Bool { !willCancel && seconds >= max(1, maxSeconds - 10) }

    private var mainHint: String {
        if willCancel { return "松开手指，取消发送" }
        if willTranscribe { return "松手 转文字" }
        return "松手 发语音"
    }

    private var orbMode: VoiceOrbMode {
        if willCancel { return .cancelling }
        if willTranscribe { return .transcribing }
        return .listening
    }

    var body: some View {
        VStack(spacing: 12) {

            Text("滑到这里 转文字")
                .font(pf(13, willTranscribe ? .semibold : .regular))
                .foregroundColor(willTranscribe ? .white : .white.opacity(0.62))
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(willTranscribe
                                   ? Color(hex: 0x2BD07A).opacity(0.95)
                                   : Color.white.opacity(0.10))
                )

            TimelineView(.animation(minimumInterval: frameInterval)) { ctx in
                orb(phase: ctx.date.timeIntervalSinceReferenceDate)
            }
            .frame(width: 258, height: 258)

            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(seconds)″")
                        .font(pfMoney(15, .medium))
                        .foregroundColor(.white)
                        .monospacedDigit()
                    Text(mainHint)
                        .font(pf(13))
                        .foregroundColor(.white.opacity(0.92))
                }
                if nearlyDone {
                    Text("还可以说 \(max(0, maxSeconds - seconds)) 秒")
                        .font(pf(11.5))
                        .foregroundColor(Color(hex: 0xFFB340))
                }
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 18)

        .background {
            RadialGradient(colors: [Color.black.opacity(UIConfig.num("voiceHudDark", 0.78)),
                                    Color.black.opacity(0.42),
                                    Color.black.opacity(0.0)],
                           center: .center, startRadius: 20, endRadius: 300)
                .frame(width: 620, height: 620)
                .allowsHitTesting(false)
        }
        .animation(.easeInOut(duration: 0.2), value: willCancel)
        .animation(.easeInOut(duration: 0.2), value: willTranscribe)
    }

    private func orbInner(_ phase: Double,
                          _ c1: Color, _ c2: Color, _ c3: Color, _ c4: Color) -> some View {
        ZStack {

            Circle()
                .fill(RadialGradient(colors: [Color(red: 0.05, green: 0.06, blue: 0.17),
                                              Color(red: 0.02, green: 0.02, blue: 0.07)],
                                     center: UnitPoint(x: 0.40, y: 0.34),
                                     startRadius: 2, endRadius: 82))

            ZStack {
                AngularGradient(colors: [c1, c2, c3, c4, c1],
                                center: .center,
                                angle: .degrees(phase * 46))
                    .blur(radius: 9)
                    .opacity(0.52)
                AngularGradient(colors: [c3, c4, c1, c2, c3], center: .center)
                    .blur(radius: 16)
                    .opacity(0.40)
                    .rotationEffect(.degrees(-phase * 92))
                AngularGradient(colors: [c4, c1, c2, c3, c4], center: .center)
                    .blur(radius: 24)
                    .opacity(0.28)
                    .rotationEffect(.degrees(phase * 138))
            }
            .rotation3DEffect(.degrees(phase * 26), axis: (x: 0, y: 1, z: 0), perspective: 0.30)
            .blendMode(.plusLighter)

            ZStack {
                Circle()
                    .trim(from: 0.02, to: 0.13)
                    .stroke(c4.opacity(0.52), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(phase * 74))
                Circle()
                    .trim(from: 0.34, to: 0.47)
                    .stroke(c3.opacity(0.46), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-phase * 56))
                Circle()
                    .trim(from: 0.68, to: 0.79)
                    .stroke(c1.opacity(0.52), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(phase * 90))
            }
            .frame(width: 122, height: 122)
            .blur(radius: 9)
            .blendMode(.plusLighter)

            Circle()
                .fill(RadialGradient(colors: [Color.white.opacity(0.26), Color.clear],
                                     center: UnitPoint(x: 0.34, y: 0.27),
                                     startRadius: 1, endRadius: 54))
                .blendMode(.plusLighter)
        }
        .frame(width: 158, height: 158)

        .mask(
            Circle().fill(RadialGradient(colors: [Color.white,
                                                  Color.white,
                                                  Color.white.opacity(0.0)],
                                         center: .center,
                                         startRadius: 34, endRadius: 79))
        )
    }

    private func orb(phase: Double) -> some View {
        let amp = max(0.05, min(1, Double(level)))
        let fit = CGFloat(1 + 0.035 * sin(phase * 1.4))
        let float = CGFloat(sin(phase * 1.0) * 3.5)

        let scale = (0.86 + CGFloat(amp) * 0.42) * fit
        let glassAmt = UIConfig.num("voiceOrbGlass", 0.65)

        let c1 = willCancel ? Color(hex: 0xFF4A3C)
                            : (willTranscribe ? Color(hex: 0x2BD07A) : Color(hex: 0x3B7CFF))
        let c2 = willCancel ? Color(hex: 0xFF6A3C)
                            : (willTranscribe ? Color(hex: 0x3FD9C0) : Color(hex: 0x8A5BFF))
        let c3 = willCancel ? Color(hex: 0xFF6B6B)
                            : (willTranscribe ? Color(hex: 0x7CF0B0) : Color(hex: 0xFF5AA8))
        let c4 = willCancel ? Color(hex: 0xFFB03C)
                            : (willTranscribe ? Color(hex: 0xB7F06A) : Color(hex: 0x3AD6FF))
        let inner = orbInner(phase, c1, c2, c3, c4)

        return ZStack {
            if #available(iOS 17.0, *) {
                VoiceOrbSurface(phase: phase,
                                level: level,
                                mode: orbMode,
                                canvas: 258)
                    .scaleEffect(scale)
                    .offset(y: reduceMotion ? 0 : float)
                    .shadow(color: c2.opacity(0.32 + amp * 0.22),
                            radius: 24, y: 10)
            } else {

                Circle()
                    .fill(RadialGradient(colors: [c1.opacity(0.26 + amp * 0.22),
                                                  c2.opacity(0.10),
                                                  Color.clear],
                                         center: .center, startRadius: 42, endRadius: 168))
                    .frame(width: 336, height: 336)
                    .scaleEffect((0.90 + CGFloat(amp) * 0.30) * fit)
                    .blur(radius: 22)
                    .blendMode(.plusLighter)

                inner
                    .scaleEffect(scale)
                    .offset(y: float)
                    .shadow(color: c3.opacity(0.42 + CGFloat(amp) * 0.30), radius: 24)
                    .shadow(color: c1.opacity(0.38 + CGFloat(amp) * 0.28), radius: 46)

                inner
                    .scaleEffect(scale * 1.03)
                    .blur(radius: 40)
                    .opacity(0.42)
                    .blendMode(.plusLighter)
                    .offset(y: float)

                Circle()
                    .stroke(c4.opacity(0.55), lineWidth: 3)
                    .frame(width: 152, height: 152)
                    .blur(radius: 5)
                    .scaleEffect(scale)
                    .offset(x: 1.8, y: float)
                    .blendMode(.plusLighter)
                Circle()
                    .stroke(c3.opacity(0.50), lineWidth: 3)
                    .frame(width: 152, height: 152)
                    .blur(radius: 5)
                    .scaleEffect(scale)
                    .offset(x: -1.8, y: float)
                    .blendMode(.plusLighter)
            }

            if #unavailable(iOS 17.0) {

            if glassAmt > 0 {

                GlassBackground(shape: Circle(),
                                opacity: glassAmt,
                                edgeAlpha: UIConfig.num("voiceOrbEdge", 0.50),
                                shadow: false,
                                seed: 0.50,
                                native: false)
                    .frame(width: 158, height: 158)
                    .scaleEffect(scale)
                    .offset(y: float)
            }

            Circle()
                .stroke(Color.black.opacity(0.38), lineWidth: 5)
                .frame(width: 146, height: 146)
                .blur(radius: 5)
                .opacity(0.65)
                .scaleEffect(scale)
                .offset(y: float)

            Circle()
                .stroke(LinearGradient(colors: [Color.white.opacity(0.22),
                                                Color.white.opacity(0.02),
                                                c1.opacity(0.16)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1)
                .frame(width: 158, height: 158)
                .blur(radius: 1.2)
                .scaleEffect(scale)
                .offset(y: float)
            }

            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(AngularGradient(colors: [c1.opacity(0.50), c4.opacity(0.50)],
                                        center: .center),
                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 224, height: 224)
                .opacity(0.70)

            Ellipse()
                .fill(RadialGradient(colors: [c3.opacity(0.15 + amp * 0.13), Color.clear],
                                     center: .center, startRadius: 2, endRadius: 84))
                .frame(width: 176, height: 30)
                .offset(y: 112 - float * 0.4)
                .blur(radius: 14)
                .blendMode(.plusLighter)
        }
        .frame(width: 258, height: 258)
        .animation(.easeOut(duration: 0.09), value: level)
    }
}

struct VoiceOrb: View {

    var level: CGFloat = 0.16

    var diameter: CGFloat = 92

    var listening: Bool = false
    var mode: VoiceOrbMode? = nil
    /// 键盘场景可关闭 Metal colorEffect，避免输入法切换时重建渲染管线。
    var metalShader: Bool = true

    private let canvas: CGFloat = 258
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var frameInterval: Double {
        if reduceMotion || ProcessInfo.processInfo.isLowPowerModeEnabled {
            return 1.0 / 30.0
        }
        let fps = max(60, min(120, UIScreen.main.maximumFramesPerSecond))
        return 1.0 / Double(fps)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: frameInterval)) { ctx in
            let phase = ctx.date.timeIntervalSinceReferenceDate
            let amp = max(0.05, min(1, level))
            let fit = CGFloat(1 + 0.035 * sin(phase * 1.4))
            let float = CGFloat(sin(phase * 1.0) * 3.5)
            let scale = (0.86 + amp * 0.42) * fit
            let c1 = Color(hex: 0x3B7CFF)
            let c2 = Color(hex: 0x8A5BFF)
            let c3 = Color(hex: 0xFF5AA8)
            let c4 = Color(hex: 0x3AD6FF)

            ZStack {
                if #available(iOS 17.0, *), metalShader {
                    VoiceOrbSurface(phase: phase,
                                    level: level,
                                    mode: mode ?? (listening ? .listening : .idle),
                                    canvas: canvas)
                        .scaleEffect(scale)
                        .offset(y: reduceMotion ? 0 : float)
                        .shadow(color: c2.opacity(0.30 + Double(amp) * 0.24),
                                radius: 22, y: 9)
                } else {

                    ZStack {
                        Circle()
                            .fill(RadialGradient(colors: [c1.opacity(0.95), c2.opacity(0.85), c3.opacity(0.55)],
                                                 center: UnitPoint(x: 0.36, y: 0.30),
                                                 startRadius: 2, endRadius: 132))
                        Circle()
                            .fill(RadialGradient(colors: [Color.white.opacity(0.34), Color.clear],
                                                 center: UnitPoint(x: 0.33, y: 0.26),
                                                 startRadius: 0, endRadius: 72))
                    }
                    .frame(width: 168, height: 168)
                    .blur(radius: 6)
                    .scaleEffect(scale)
                    .shadow(color: c3.opacity(0.45), radius: 26)
                    .offset(y: float)
                }
            }
            .frame(width: canvas, height: canvas)
            .scaleEffect(diameter / canvas)
            .frame(width: diameter, height: diameter)
            .opacity(listening ? 1 : 0.94)
        }
    }
}
