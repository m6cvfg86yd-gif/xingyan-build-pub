import SwiftUI
import UIKit

enum PayVisual {
    static let tint = Color(hex: 0x0A84FF)
    static let success = Color(hex: 0x30D158)
    static let warning = Color(hex: 0xFF9F0A)
    static let danger = Color(hex: 0xFF453A)
    static let gold = Color(hex: 0xD9A441)

    static var canvas: Color { Color.dyn(0xF2F2F7, 0x000000) }
    static var card: Color { Color.dyn(0xFFFFFF, 0x1C1C1E) }
    static var raised: Color { Color.dyn(0xFFFFFF, 0x2C2C2E) }
    static var inset: Color { Color.dyn(0xF2F2F7, 0x2C2C2E) }
    static var separator: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.10)
                : UIColor(white: 0, alpha: 0.08)
        })
    }
    static var secondaryInk: Color { Color.dyn(0x6C6C70, 0x98989F) }
}

struct PayGroupCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) { content }
            .background(PayVisual.card)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct PaySectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(pf(13, .semibold))
            .foregroundColor(PayVisual.secondaryInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

struct PayStatusPill: View {
    let text: String
    var tone: Tone = .neutral

    enum Tone {
        case neutral, processing, success, warning, danger
    }

    private var color: Color {
        switch tone {
        case .neutral: return PayVisual.secondaryInk
        case .processing: return PayVisual.tint
        case .success: return PayVisual.success
        case .warning: return PayVisual.warning
        case .danger: return PayVisual.danger
        }
    }

    var body: some View {
        Text(text)
            .font(pf(12.5, .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .frame(height: 27)
            .background(color.opacity(0.12), in: Capsule())
    }
}

struct PayDetailRow: View {
    let title: String
    let value: String
    var valueColor: Color = C.label
    var copyValue: String? = nil

    @EnvironmentObject private var app: AppState

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(title)
                .font(pf(15))
                .foregroundColor(PayVisual.secondaryInk)
            Spacer(minLength: 12)
            Text(value)
                .font(pf(15, .medium))
                .foregroundColor(valueColor)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .onTapGesture {
            guard let copyValue, !copyValue.isEmpty else { return }
            UIPasteboard.general.string = copyValue
            app.show(Tr("已复制"))
        }
    }
}

struct PayEmptyState: View {
    let symbol: String
    let title: String
    var detail: String = ""

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 32, weight: .regular))
                .foregroundColor(PayVisual.secondaryInk)
            Text(title)
                .font(pf(16, .semibold))
                .foregroundColor(C.label)
            if !detail.isEmpty {
                Text(detail)
                    .font(pf(13))
                    .foregroundColor(PayVisual.secondaryInk)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .padding(.horizontal, 28)
    }
}

struct PayPrimaryButtonStyle: ButtonStyle {
    var tint: Color = PayVisual.tint
    var enabled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(pf(17, .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(enabled ? tint : PayVisual.secondaryInk.opacity(0.34))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct PaySecondaryButtonStyle: ButtonStyle {
    var tint: Color = PayVisual.tint

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(pf(16, .semibold))
            .foregroundColor(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(PayVisual.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(tint.opacity(0.24), lineWidth: 0.8)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
