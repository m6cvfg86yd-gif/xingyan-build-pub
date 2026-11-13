import SwiftUI

struct PanelSectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(pf(12.5, .medium))
            .foregroundColor(C.subLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 6)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }
}

struct PanelCard<Content: View>: View {
    private let content: () -> Content
    private let solid: Bool

    init(solid: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.content = content
        self.solid = solid
    }

    var body: some View {
        VStack(spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if solid {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(C.cardBg)
                } else {
                    CardGlassBox(radius: 14)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(C.hairline, lineWidth: 0.6))
            .shadow(color: Color.black.opacity(0.05), radius: 8, y: 2)
    }
}

struct PanelHeroCard<Content: View>: View {
    private let glow: Color
    private let content: () -> Content

    init(glow: Color = C.green, @ViewBuilder content: @escaping () -> Content) {
        self.glow = glow
        self.content = content
    }

    var body: some View {
        VStack(spacing: 14) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                ZStack {
                    LinearGradient(colors: [Color(hex: 0x1C2130), Color(hex: 0x2A2433), Color(hex: 0x14111A)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    RadialGradient(colors: [glow.opacity(0.26), Color.clear],
                                   center: .topTrailing, startRadius: 2, endRadius: 210)

                    RadialGradient(colors: [Color.white.opacity(0.10), Color.clear],
                                   center: .topLeading, startRadius: 1, endRadius: 260)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.11), lineWidth: 1))
            .overlay(

                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(LinearGradient(colors: [Color.white.opacity(0.22), Color.clear],
                                           startPoint: .top, endPoint: .center),
                            lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(0.26), radius: 18, y: 9)
            .shadow(color: (glow).opacity(0.12), radius: 16, y: 4)
    }
}

struct PanelPill: View {
    var symbol: String
    var title: String
    var colors: [Color] = PanelTint.green
    var tap: () -> Void

    var body: some View {
        Button(action: tap) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(pf(13, .medium))
                    .lineLimit(1)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(
                Capsule().fill(LinearGradient(colors: colors.map { $0.opacity(0.9) },
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }
}

struct PanelIcon: View {
    var symbol: String
    var colors: [Color] = PanelTint.green
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.31, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size)
            Image(systemName: symbol)
                .font(.system(size: size * 0.47, weight: .semibold))
                .foregroundColor(.white)
        }
        .shadow(color: (colors.last ?? .clear).opacity(0.32), radius: 4, y: 2)
    }
}

enum PanelTint {
    static let green: [Color] = [C.green, C.green.opacity(0.78)]
    static let blue: [Color] = [Color(hex: 0x64B5F6), Color(hex: 0x2A6BC4)]
    static let purple: [Color] = [Color(hex: 0xB98CFF), Color(hex: 0x7A45D6)]
    static let orange: [Color] = [C.green, C.green.opacity(0.78)]
    static let red: [Color] = [Color(hex: 0xFF7A6B), Color(hex: 0xDE2F1F)]
    static let teal: [Color] = [Color(hex: 0x38D6C4), Color(hex: 0x0E9A8C)]
    static let gray: [Color] = [Color(hex: 0xA9B2BA), Color(hex: 0x6E7780)]
}

struct PanelRow: View {
    var symbol: String
    var colors: [Color] = PanelTint.green
    var title: String
    var subtitle: String? = nil
    var value: String? = nil
    var chevron: Bool = true
    var tap: () -> Void

    var body: some View {
        Button(action: tap) {
            HStack(spacing: 11) {
                PanelIcon(symbol: symbol, colors: colors)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(pf(16))
                        .foregroundColor(C.label)
                        .lineLimit(1)
                    if let s = subtitle, !s.isEmpty {
                        Text(s)
                            .font(pf(12.5))
                            .foregroundColor(C.subLabel)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if let v = value, !v.isEmpty {
                    Text(v)
                        .font(pf(15))
                        .foregroundColor(C.subLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if chevron { Chevron(size: 9, line: 1.6) }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct PanelToggleRow: View {
    var symbol: String
    var colors: [Color] = PanelTint.green
    var title: String
    var subtitle: String? = nil
    var isOn: Bool
    var onChange: (Bool) -> Void

    var body: some View {
        HStack(spacing: 11) {
            PanelIcon(symbol: symbol, colors: colors)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(pf(16))
                    .foregroundColor(C.label)
                if let s = subtitle, !s.isEmpty {
                    Text(s)
                        .font(pf(12.5))
                        .foregroundColor(C.subLabel)
                }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(get: { isOn }, set: { onChange($0) }))
                .labelsHidden()
                .tint(C.green)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 56)
    }
}

struct PanelDangerRow: View {
    var symbol: String
    var title: String
    var subtitle: String? = nil
    var tap: () -> Void

    private var dangerInk: Color { Color.dyn(0xE03A3A, 0xFF6B6B) }

    var body: some View {
        Button(action: tap) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(dangerInk.opacity(0.10))
                        .frame(width: 30, height: 30)
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(dangerInk)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(pf(16))
                        .foregroundColor(dangerInk)
                        .lineLimit(1)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(pf(12.5))
                            .foregroundColor(C.subLabel)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                Chevron(size: 8.5, line: 1.5)
                    .opacity(0.48)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: subtitle == nil ? 54 : 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct PanelConfirmDialog: View {
    var title: String
    var okText: String

    var danger: Bool = true
    var message: String? = nil
    var symbol: String? = nil
    var onOk: () -> Void
    var onCancel: () -> Void

    private var okColor: Color {
        danger ? Color.dyn(0xE03A3A, 0xFF6B6B) : C.green
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.46)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    if let symbol, !symbol.isEmpty {
                        ZStack {
                            Circle()
                                .fill(okColor.opacity(0.10))
                                .frame(width: 46, height: 46)
                            Image(systemName: symbol)
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundColor(okColor)
                        }
                    }
                    Text(title)
                        .font(pf(17, .semibold))
                        .foregroundColor(C.label)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    if let message, !message.isEmpty {
                        Text(message)
                            .font(pf(13.5))
                            .foregroundColor(C.subLabel)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(3)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, symbol == nil ? 24 : 20)
                .padding(.bottom, 20)

                Rectangle().fill(C.hairline).frame(height: 0.5)
                HStack(spacing: 0) {
                    Button { onCancel() } label: {
                        Text(Tr("取消"))
                            .font(pf(16.5))
                            .foregroundColor(C.label)
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Rectangle().fill(C.hairline).frame(width: 0.5, height: 52)
                    Button { onOk() } label: {
                        Text(okText)
                            .font(pf(16.5, .semibold))
                            .foregroundColor(okColor)
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(C.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 21, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.7)
            )
            .frame(width: 300)
            .shadow(color: Color.black.opacity(0.30), radius: 32, y: 12)
            .transition(.scale(scale: 0.96).combined(with: .opacity))
        }
        .animation(.easeOut(duration: 0.18), value: title)
    }
}

struct PanelCircleButton: View {
    var symbol: String
    var tint: Color = C.label
    var tap: () -> Void

    var body: some View {
        Button(action: tap) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 30, height: 30)
                .background(
                    Circle().fill(C.pageBg.opacity(0.9))
                )
                .overlay(Circle().stroke(C.hairline, lineWidth: 0.6))
        }
        .buttonStyle(.plain)
    }
}

struct PanelDivider: View {
    var body: some View { HairLine(inset: 55) }
}
