import SwiftUI
import UIKit
import AudioToolbox

struct PayKeypadView: View {
    var busy: Bool = false
    var keyHeight: CGFloat = 54

    var secure: Bool = true

    var dot: Bool = false
    var onKey: (String) -> Void

    @State private var digits: [String] = (0...9).map { String($0) }

    static func shuffledDigits() -> [String] {
        var d = (0...9).map { String($0) }
        d.shuffle()
        return d
    }

    private func key(_ r: Int, _ c: Int) -> String {
        if r == 3 {

            if c == 0 { return dot ? "." : "" }
            if c == 1 { return digits.count > 9 ? digits[9] : "0" }
            return "⌫"
        }
        let i = r * 3 + c
        return i < digits.count ? digits[i] : ""
    }

    var body: some View {
        VStack(spacing: 8) {
            keyRow(0)
            keyRow(1)
            keyRow(2)
            keyRow(3)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(PayVisual.canvas)
        .onAppear {
            digits = secure ? Self.shuffledDigits() : (0...9).map { String($0) }
        }
    }

    private func keyRow(_ r: Int) -> some View {
        HStack(spacing: 8) {
            keyCell(key(r, 0))
            keyCell(key(r, 1))
            keyCell(key(r, 2))
        }
    }

    @ViewBuilder
    private func keyCell(_ key: String) -> some View {
        if key.isEmpty {

            VStack(spacing: 2) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 11))
                Text(Tr("安全键盘"))
                    .font(pf(9.5))
            }
            .foregroundColor(C.subLabel.opacity(0.75))
            .frame(maxWidth: .infinity)
            .frame(height: keyHeight)
            .background(PayVisual.card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .allowsHitTesting(false)
        } else {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()

                if UIConfig.num("payKeySound", 1) > 0 { AudioServicesPlaySystemSound(1104) }
                onKey(key)
            } label: {
                Group {
                    if key == "⌫" {
                        Image(systemName: "delete.left")
                            .font(.system(size: 22, weight: .regular))
                    } else {
                        Text(key).font(pfStyled(size: 26, weight: .regular))
                    }
                }
                .foregroundColor(C.label)
                .frame(maxWidth: .infinity)
                .frame(height: keyHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(BankKeyStyle())
            .disabled(busy)
        }
    }
}

struct PayDotField: View {
    var count: Int
    var total: Int = 6
    var shake: CGFloat = 0
    var busy: Bool = false
    var height: CGFloat = 54

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<total, id: \.self) { i in
                ZStack {
                    if count > i {
                        Circle()
                            .fill(C.label)
                            .frame(width: 11, height: 11)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: height)
                if i < total - 1 {
                    Rectangle().fill(C.hairline).frame(width: 0.7, height: height)
                }
            }
        }
        .background(PayVisual.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(PayVisual.separator, lineWidth: 0.8))

        .padding(.horizontal, 20)
        .offset(x: shake)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: count)
    }
}

@MainActor
func payShake(_ shake: Binding<CGFloat>) {
    UINotificationFeedbackGenerator().notificationOccurred(.error)
    withAnimation(.easeOut(duration: 0.06)) { shake.wrappedValue = -12 }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.35)) { shake.wrappedValue = 0 }
    }
}

struct KeyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct BankKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.dyn(0xE5E5EA, 0x3A3A3C) : PayVisual.card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

struct PayDots: View {
    var color: Color = .white
    var size: CGFloat = 9
    @State private var phase = 0
    private let tick = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(color)
                    .frame(width: size, height: size)
                    .opacity(phase == i ? 1 : 0.32)
                    .scaleEffect(phase == i ? 1.12 : 0.85)
            }
        }
        .onReceive(tick) { _ in
            withAnimation(.easeInOut(duration: 0.18)) { phase = (phase + 1) % 3 }
        }
    }
}

struct PayBusyOverlay: View {
    var text: String = "正在支付"

    var body: some View {
        ZStack {
            Color.black.opacity(0.12).ignoresSafeArea()
            VStack(spacing: 14) {
                PayDots()
                Text(text)
                    .font(pf(13.5, .medium))
                    .foregroundColor(.white)
            }
            .frame(width: 118, height: 118)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.76)))
            .shadow(color: Color.black.opacity(0.22), radius: 20, y: 8)
        }
        .transition(.opacity)
    }
}
