import SwiftUI

struct StarRouteBackdrop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            ZStack {
                OrbitTheme.canvas

                RadialGradient(
                    colors: [
                        OrbitTheme.jade.opacity(scheme == .dark ? 0.13 : 0.10),
                        Color.clear
                    ],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: max(260, geo.size.width * 0.92)
                )

                Circle()
                    .stroke(OrbitTheme.jade.opacity(scheme == .dark ? 0.13 : 0.09),
                            style: StrokeStyle(lineWidth: 0.8, dash: [2, 7]))
                    .frame(width: 310, height: 310)
                    .offset(x: geo.size.width * 0.42, y: -geo.size.height * 0.28)

                Circle()
                    .stroke(OrbitTheme.gold.opacity(scheme == .dark ? 0.10 : 0.08),
                            lineWidth: 0.8)
                    .frame(width: 220, height: 220)
                    .offset(x: -geo.size.width * 0.44, y: geo.size.height * 0.25)

                Circle()
                    .fill(OrbitTheme.jade.opacity(0.55))
                    .frame(width: 4, height: 4)
                    .offset(x: geo.size.width * 0.31, y: -geo.size.height * 0.20)

                Circle()
                    .fill(OrbitTheme.gold.opacity(0.48))
                    .frame(width: 3, height: 3)
                    .offset(x: -geo.size.width * 0.30, y: geo.size.height * 0.18)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct StarForwardHero: View {
    let symbol: String
    let kicker: String
    let title: String
    let subtitle: String
    var badge: String = ""

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.dyn(0x167B55, 0x0C3D2B),
                            Color.dyn(0x2FCD86, 0x176B4A)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            GeometryReader { geo in
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.15),
                                style: StrokeStyle(lineWidth: 0.9, dash: [2, 6]))
                        .frame(width: 150, height: 150)
                        .position(x: geo.size.width - 8, y: -2)

                    Circle()
                        .stroke(Color.white.opacity(0.09), lineWidth: 1)
                        .frame(width: 102, height: 102)
                        .position(x: geo.size.width - 2, y: 10)

                    Circle()
                        .fill(Color.white.opacity(0.62))
                        .frame(width: 4, height: 4)
                        .position(x: geo.size.width - 54, y: 20)
                }
            }
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 10.5, weight: .semibold))
                    Text(kicker)
                        .font(pfStyled(size: 9.5, weight: .bold))
                        .tracking(1.15)
                    Spacer(minLength: 10)

                    if !badge.isEmpty {
                        Text(badge)
                            .font(pfStyled(size: 10, weight: .semibold))
                            .padding(.horizontal, 9)
                            .frame(height: 23)
                            .background(Capsule().fill(Color.white.opacity(0.13)))
                            .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 0.6))
                    }
                }
                .foregroundStyle(Color.white.opacity(0.78))

                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title)
                            .font(pfStyled(size: 23, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(subtitle)
                            .font(pfStyled(size: 12, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.72))
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: symbol)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(Color.white.opacity(0.13)))
                        .overlay(Circle().stroke(Color.white.opacity(0.20), lineWidth: 0.8))
                }
            }
            .padding(16)
        }
        .frame(height: 148)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.11), lineWidth: 0.8)
        }
        .shadow(color: OrbitTheme.jade.opacity(0.13), radius: 18, y: 8)
    }
}

struct StarForwardSearch: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(OrbitTheme.tertiary)
            TextField(placeholder, text: $text)
                .font(.system(size: 14.5))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(OrbitTheme.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 13)
        .frame(height: 43)
        .background(OrbitTheme.raised)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(OrbitTheme.divider, lineWidth: 0.7)
        }
    }
}

struct StarForwardQuickTarget: View {
    let name: String
    let avatar: String
    let isGroup: Bool
    let selected: Bool

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(selected ? OrbitTheme.jadeSoft : OrbitTheme.field)
                    .frame(width: 58, height: 58)
                Avatar(path: avatar,
                       size: 48,
                       radius: 15,
                       circle: true,
                       group: isGroup)
                if selected {
                    Circle()
                        .fill(OrbitTheme.jade)
                        .frame(width: 18, height: 18)
                        .overlay {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .overlay(Circle().stroke(OrbitTheme.canvas, lineWidth: 2))
                        .offset(x: 22, y: 20)
                }
            }
            .overlay {
                Circle()
                    .stroke(selected ? OrbitTheme.jade.opacity(0.42) : OrbitTheme.divider,
                            lineWidth: 0.8)
                    .frame(width: 58, height: 58)
            }

            Text(name)
                .font(pfStyled(size: 10.5, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? OrbitTheme.jade : OrbitTheme.secondary)
                .lineLimit(1)
                .frame(width: 66)
        }
        .contentShape(Rectangle())
    }
}

struct StarForwardTargetRow: View {
    let name: String
    let subtitle: String
    let avatar: String
    let isGroup: Bool
    let selected: Bool
    var selecting: Bool = true
    var loading: Bool = false
    var countBadge: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Avatar(path: avatar,
                   size: 50,
                   radius: 16,
                   group: isGroup)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(selected ? OrbitTheme.jade.opacity(0.45) : OrbitTheme.divider,
                                lineWidth: 0.8)
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(pfStyled(size: 15.5, weight: .semibold))
                        .foregroundStyle(OrbitTheme.ink)
                        .lineLimit(1)
                    if let countBadge, !countBadge.isEmpty {
                        Text(countBadge)
                            .font(pfStyled(size: 9, weight: .bold))
                            .foregroundStyle(OrbitTheme.jade)
                            .padding(.horizontal, 6)
                            .frame(height: 17)
                            .background(Capsule().fill(OrbitTheme.jadeSoft))
                    }
                }
                Text(subtitle)
                    .font(pfStyled(size: 11.5))
                    .foregroundStyle(OrbitTheme.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if loading {
                ProgressView()
                    .tint(OrbitTheme.jade)
                    .scaleEffect(0.82)
                    .frame(width: 28, height: 28)
            } else if selecting {
                ZStack {
                    Circle()
                        .fill(selected ? OrbitTheme.jade : Color.clear)
                        .frame(width: 24, height: 24)
                    Circle()
                        .stroke(selected ? OrbitTheme.jade : OrbitTheme.tertiary.opacity(0.55),
                                lineWidth: 1.2)
                        .frame(width: 24, height: 24)
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            } else {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(OrbitTheme.jade)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(OrbitTheme.jadeSoft))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 72)
        .background(selected ? OrbitTheme.jadeSoft.opacity(0.72) : OrbitTheme.raised)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(selected ? OrbitTheme.jade.opacity(0.34) : OrbitTheme.divider,
                        lineWidth: selected ? 1 : 0.7)
        }
        .shadow(color: Color.black.opacity(selected ? 0.045 : 0.025),
                radius: 9,
                y: 3)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct StarForwardEmpty: View {
    let text: String

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(OrbitTheme.jade.opacity(0.16),
                            style: StrokeStyle(lineWidth: 0.8, dash: [3, 5]))
                    .frame(width: 70, height: 70)
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 25, weight: .light))
                    .foregroundStyle(OrbitTheme.jade.opacity(0.66))
            }
            Text(text)
                .font(pfStyled(size: 12.5))
                .foregroundStyle(OrbitTheme.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }
}
