import SwiftUI

struct SliderSheet: View {

    var freshKey: Int = 0
    var onPass: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var err = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(Tr("为确认是本人操作，请拖动滑块把缺口补齐"))
                    .font(pfStyled(size: 13))
                    .foregroundColor(C.subLabel)
                SliderCaptchaView(onTicket: { t in
                    onPass(t)
                    dismiss()
                }, onFail: { msg in
                    err = msg
                })
                .id(freshKey)
                if !err.isEmpty {
                    Text(err).font(pfStyled(size: 13)).foregroundColor(C.red)
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle(Tr("安全验证"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Tr("取消")) { dismiss() }
                }
            }
        }

        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
    }
}

struct SliderCaptchaView: View {

    let onTicket: (String) -> Void

    var onFail: ((String) -> Void)? = nil

    @State private var challenge: API.SliderChallenge? = nil
    @State private var dragX: CGFloat = 0
    @State private var done = false
    @State private var busy = false
    @State private var note = "拖动滑块，把缺口补齐"
    @State private var shakeFlip = false

    private let trackH: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            puzzle
            track
            HStack(spacing: 6) {
                Image(systemName: done ? "checkmark.seal.fill" : "hand.draw.fill")
                    .font(.system(size: 11))
                Text(note).font(pfStyled(size: 11.5))
            }
            .foregroundColor(done ? C.green : C.subLabel)
        }
        .task { await load() }
    }

    private var puzzle: some View {
        let w = CGFloat(challenge?.width ?? 260)
        let h = CGFloat(challenge?.height ?? 130)
        let pw = CGFloat(challenge?.piece ?? 44)
        let tx = CGFloat(challenge?.targetX ?? 0)
        let ty = CGFloat(challenge?.targetY ?? 0)
        return ZStack(alignment: .topLeading) {
            SliderScene(seed: challenge?.seed ?? 1)
                .frame(width: w, height: h)

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.black.opacity(done ? 0.12 : 0.36))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.85), lineWidth: 1))
                .frame(width: pw, height: pw)
                .offset(x: tx, y: ty)

            piece(w: w, h: h, pw: pw, tx: tx, ty: ty)
                .offset(x: dragX, y: ty)
        }
        .frame(width: w, height: h)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(C.hairline, lineWidth: 0.5))
        .offset(x: shakeFlip ? 5 : 0)
    }

    private func piece(w: CGFloat, h: CGFloat, pw: CGFloat, tx: CGFloat, ty: CGFloat) -> some View {
        SliderScene(seed: challenge?.seed ?? 1)
            .frame(width: w, height: h)
            .offset(x: -tx, y: -ty)
            .frame(width: pw, height: pw, alignment: .topLeading)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.white.opacity(0.9), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
    }

    private var track: some View {
        let w = CGFloat(challenge?.width ?? 260)
        let pw = CGFloat(challenge?.piece ?? 44)
        let maxX = max(1, w - pw)
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.dyn(0xF2F2F3, 0x2A2A2C))
                .frame(height: trackH)

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill((done ? C.green : Color.dyn(0x19A47A, 0x1DC9BD)).opacity(0.16))
                .frame(width: dragX + pw, height: trackH)

            Text(done ? Tr("验证通过") : (busy ? Tr("正在核对…") : Tr("按住滑块，拖到缺口位置")))
                .font(pfStyled(size: 12.5))
                .foregroundColor(done ? C.green : C.subLabel)
                .frame(maxWidth: .infinity)

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.dyn(0xFFFFFF, 0x3A3A3C))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(C.hairline, lineWidth: 0.5))
                .overlay(
                    Image(systemName: done ? "checkmark" : "chevron.right.2")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(done ? C.green : C.subLabel)
                )
                .frame(width: pw, height: trackH)
                .offset(x: dragX)
        }
        .frame(width: w, height: trackH)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    guard !done, !busy else { return }
                    dragX = min(max(0, v.location.x - pw / 2), maxX)
                }
                .onEnded { _ in submit() }
        )
    }

    private func load() async {
        done = false
        busy = false
        dragX = 0
        note = "拖动滑块，把缺口补齐"
        do {
            challenge = try await API.shared.sliderChallenge()
        } catch {
            challenge = nil
            note = "验证暂时没准备好，点一下重试"
        }
    }

    private func submit() {
        guard let c = challenge, !done, !busy else { return }
        busy = true
        Task {
            do {
                let ticket = try await API.shared.verifySlider(id: c.id,
                                                              x: Double(dragX),
                                                              y: c.targetY)
                done = true

                withAnimation(.easeOut(duration: 0.15)) { dragX = CGFloat(c.targetX) }
                note = "验证通过"
                onTicket(ticket)
            } catch {
                let msg = (error as? APIError)?.errorDescription ?? "没对上，再试一次"
                note = msg
                onFail?(msg)
                withAnimation(.easeOut(duration: 0.08)) { shakeFlip = true }
                try? await Task.sleep(nanoseconds: 90_000_000)
                withAnimation(.easeOut(duration: 0.08)) { shakeFlip = false }
                await load()
            }
            busy = false
        }
    }
}

struct SliderScene: View {
    let seed: Int

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                LinearGradient(colors: [SliderScene.color(seed, 0), SliderScene.color(seed, 1)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                ForEach(0..<5, id: \.self) { i in
                    Capsule()
                        .fill(SliderScene.color(seed, i + 2).opacity(0.45))
                        .frame(width: w * SliderScene.frac(seed, i * 4 + 1) * 0.8,
                               height: max(12, h * SliderScene.frac(seed, i * 4 + 2) * 0.5))
                        .rotationEffect(.degrees(Double(SliderScene.frac(seed, i * 4 + 3)) * 180 - 90))
                        .position(x: w * SliderScene.frac(seed, i * 4 + 4),
                                  y: h * SliderScene.frac(seed, i * 4 + 1))
                }
            }
        }
    }

    static func frac(_ seed: Int, _ i: Int) -> CGFloat {
        var x = UInt64(truncatingIfNeeded: seed &* 2654435761 &+ i &* 40503)
        x ^= x >> 13
        x = x &* 1274126177
        x ^= x >> 16
        return 0.08 + CGFloat(x % 1000) / 1000 * 0.84
    }

    static func color(_ seed: Int, _ i: Int) -> Color {
        let hues: [Double] = [0.58, 0.62, 0.74, 0.48, 0.88, 0.06, 0.34]
        let s = seed < 0 ? -seed : seed
        let k = (s + i * 3) % hues.count
        return Color(hue: hues[k], saturation: 0.52, brightness: 0.60 + Double((s + i) % 3) * 0.07)
    }
}
