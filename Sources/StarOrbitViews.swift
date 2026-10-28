import SwiftUI

struct StarOrbitMetric: Identifiable {
    let id = UUID()
    let value: String
    let label: String
}

struct StarOrbitHero: View {
    let kicker: String
    let title: String
    let subtitle: String
    let symbol: String
    var accent: Color = OrbitTheme.jade
    var metrics: [StarOrbitMetric] = []

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(
                    colors: [
                        accent.opacity(0.86),
                        Color.dyn(0x18312A, 0x07100D)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))

            orbitDecoration

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 7) {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .font(.system(size: 11, weight: .semibold))
                        Text(kicker)
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.25)
                    }
                    .foregroundStyle(Color.white.opacity(0.76))

                    Spacer(minLength: 10)

                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white.opacity(0.13)))
                        .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 0.7))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.74))
                        .lineLimit(2)
                }

                if !metrics.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(metrics) { metric in
                            HStack(spacing: 5) {
                                Text(metric.value)
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                Text(metric.label)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(Color.white.opacity(0.64))
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 25)
                            .background(Capsule().fill(Color.white.opacity(0.11)))
                            .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 0.6))
                        }
                    }
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 170)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
        }
    }

    private var orbitDecoration: some View {
        GeometryReader { geo in
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.11), lineWidth: 1)
                    .frame(width: 174, height: 174)
                    .position(x: geo.size.width - 12, y: 8)
                Circle()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 4, height: 4)
                    .position(x: geo.size.width - 86, y: 26)
            }
        }
        .allowsHitTesting(false)
    }
}

struct StarOrbitIconBadge: View {
    let symbol: String
    var accent: Color = OrbitTheme.jade
    var size: CGFloat = 46

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                .fill(accent.opacity(0.14))
            RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                .stroke(accent.opacity(0.28), lineWidth: 0.8)
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .medium))
                .foregroundStyle(accent)
        }
        .frame(width: size, height: size)
    }
}

struct StarOrbitTrailingPill: View {
    let text: String
    var accent: Color = OrbitTheme.jade

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(accent)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(Capsule().fill(accent.opacity(0.12)))
            .overlay(Capsule().stroke(accent.opacity(0.20), lineWidth: 0.6))
    }
}

enum StarOrbitContactKind: String {
    case newFriends
    case groups
    case tags
    case official = "officialAccounts"
    case service

    var accent: Color {
        switch self {
        case .newFriends: return OrbitTheme.jade
        case .groups: return Color.dyn(0x315E78, 0x78AFC8)
        case .tags: return OrbitTheme.gold
        case .official, .service: return Color.dyn(0x5E6579, 0xAAB4D0)
        }
    }
}

struct StarOrbitContactIcon: View {
    let kind: StarOrbitContactKind
    var size: CGFloat = 45

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .fill(kind.accent.opacity(0.16))
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .stroke(kind.accent.opacity(0.34), lineWidth: 0.8)

            Canvas { context, canvas in
                let line = GraphicsContext.Shading.color(.white.opacity(0.92))
                let soft = GraphicsContext.Shading.color(.white.opacity(0.42))
                let stroke = max(1.15, size * 0.033)

                func dotPath(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat) -> Path {
                    let rect = CGRect(
                        x: canvas.width * x - radius,
                        y: canvas.height * y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                    return Path(ellipseIn: rect)
                }

                switch kind {
                case .newFriends:
                    var link = Path()
                    link.move(to: CGPoint(x: canvas.width * 0.31, y: canvas.height * 0.60))
                    link.addLine(to: CGPoint(x: canvas.width * 0.61, y: canvas.height * 0.39))
                    context.stroke(link, with: soft,
                                   style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                    context.fill(dotPath(0.31, 0.60, size * 0.095),
                                 with: .color(.white.opacity(0.94)))
                    context.fill(dotPath(0.61, 0.39, size * 0.085),
                                 with: .color(.white.opacity(0.94)))
                    var plus = Path()
                    plus.move(to: CGPoint(x: canvas.width * 0.73, y: canvas.height * 0.57))
                    plus.addLine(to: CGPoint(x: canvas.width * 0.73, y: canvas.height * 0.78))
                    plus.move(to: CGPoint(x: canvas.width * 0.625, y: canvas.height * 0.675))
                    plus.addLine(to: CGPoint(x: canvas.width * 0.835, y: canvas.height * 0.675))
                    context.stroke(plus, with: line,
                                   style: StrokeStyle(lineWidth: stroke * 1.2, lineCap: .round))

                case .groups:
                    let points = [
                        CGPoint(x: canvas.width * 0.50, y: canvas.height * 0.28),
                        CGPoint(x: canvas.width * 0.30, y: canvas.height * 0.70),
                        CGPoint(x: canvas.width * 0.70, y: canvas.height * 0.70)
                    ]
                    var link = Path()
                    link.move(to: points[0])
                    link.addLine(to: points[1])
                    link.addLine(to: points[2])
                    link.closeSubpath()
                    context.stroke(link, with: soft,
                                   style: StrokeStyle(lineWidth: stroke, lineJoin: .round))
                    context.fill(dotPath(0.50, 0.28, size * 0.083),
                                 with: .color(.white.opacity(0.94)))
                    context.fill(dotPath(0.30, 0.70, size * 0.073),
                                 with: .color(.white.opacity(0.94)))
                    context.fill(dotPath(0.70, 0.70, size * 0.073),
                                 with: .color(.white.opacity(0.94)))

                case .tags:
                    var tag = Path()
                    tag.move(to: CGPoint(x: canvas.width * 0.25, y: canvas.height * 0.43))
                    tag.addLine(to: CGPoint(x: canvas.width * 0.43, y: canvas.height * 0.25))
                    tag.addLine(to: CGPoint(x: canvas.width * 0.72, y: canvas.height * 0.25))
                    tag.addQuadCurve(
                        to: CGPoint(x: canvas.width * 0.79, y: canvas.height * 0.32),
                        control: CGPoint(x: canvas.width * 0.79, y: canvas.height * 0.25)
                    )
                    tag.addLine(to: CGPoint(x: canvas.width * 0.79, y: canvas.height * 0.52))
                    tag.addLine(to: CGPoint(x: canvas.width * 0.52, y: canvas.height * 0.79))
                    tag.addQuadCurve(
                        to: CGPoint(x: canvas.width * 0.43, y: canvas.height * 0.79),
                        control: CGPoint(x: canvas.width * 0.47, y: canvas.height * 0.83)
                    )
                    tag.addLine(to: CGPoint(x: canvas.width * 0.21, y: canvas.height * 0.57))
                    tag.addQuadCurve(
                        to: CGPoint(x: canvas.width * 0.21, y: canvas.height * 0.48),
                        control: CGPoint(x: canvas.width * 0.17, y: canvas.height * 0.53)
                    )
                    tag.closeSubpath()
                    context.stroke(tag, with: line,
                                   style: StrokeStyle(lineWidth: stroke, lineJoin: .round))
                    context.fill(dotPath(0.64, 0.40, size * 0.055),
                                 with: .color(.white.opacity(0.94)))

                case .official, .service:
                    context.fill(dotPath(0.50, 0.52, size * 0.055),
                                 with: .color(.white.opacity(0.94)))
                    for radius in [size * 0.18, size * 0.30] {
                        var arc = Path()
                        arc.addArc(center: CGPoint(x: canvas.width * 0.50,
                                                   y: canvas.height * 0.52),
                                   radius: radius,
                                   startAngle: .degrees(205),
                                   endAngle: .degrees(335),
                                   clockwise: false)
                        context.stroke(arc, with: radius > size * 0.2 ? soft : line,
                                       style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                    }
                    context.fill(dotPath(0.50, 0.22, size * 0.038),
                                 with: .color(.white.opacity(0.94)))
                }
            }
            .padding(size * 0.08)
        }
        .frame(width: size, height: size)
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
        }
    }
}

struct StarOrbitWorldIcon: View {
    let action: String
    let label: String
    var size: CGFloat = 40

    private var accent: Color {
        switch action {
        case "moments": return OrbitTheme.jade
        case "channels", "miniapps": return Color.dyn(0x486E80, 0x82B1C5)
        case "live", "scan": return Color.dyn(0x2F7D68, 0x6CC8AC)
        case "look", "bottle", "shake": return Color.dyn(0x6C6F88, 0xB6BBD8)
        case "search", "nearby": return Color.dyn(0xA07638, 0xE0B667)
        case "games": return Color.dyn(0x546A62, 0x9BB9AC)
        default: return OrbitTheme.jadeDeep
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(accent.opacity(0.14))
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .stroke(accent.opacity(0.32), lineWidth: 0.8)

            Circle()
                .trim(from: 0.04, to: 0.70)
                .stroke(Color.white.opacity(0.18),
                        style: StrokeStyle(lineWidth: 0.8, dash: [2, 4]))
                .frame(width: size * 0.74, height: size * 0.74)
                .offset(x: size * 0.16, y: -size * 0.16)

            Image(systemName: RowIcon.sf(action: action, label: label))
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(accent)
        }
        .frame(width: size, height: size)
    }
}

struct StarStatusRail: View {
    let tab: Int
    @Environment(\.colorScheme) private var scheme

    private var accent: Color {
        switch tab {
        case 0: return OrbitTheme.jade
        case 1: return Color.dyn(0x426C7D, 0x82B2C5)
        case 2: return OrbitTheme.gold
        default: return Color.dyn(0x5F6C66, 0xA4B9B0)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let inset: CGFloat = 22
            let lineWidth = max(0, geo.size.width - inset * 2)
            let x = inset + lineWidth * CGFloat(max(0, min(3, tab))) / 3

            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [
                        accent.opacity(scheme == .dark ? 0.15 : 0.08),
                        accent.opacity(0.025),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Capsule()
                    .fill(accent.opacity(scheme == .dark ? 0.24 : 0.20))
                    .frame(width: lineWidth, height: 0.7)
                    .padding(.leading, inset)
                    .padding(.bottom, 1)

                Circle()
                    .fill(accent)
                    .frame(width: 3.5, height: 3.5)
                    .shadow(color: accent.opacity(0.45), radius: 3)
                    .offset(x: x - 1.75, y: -0.0)
                    .padding(.bottom, 0)
                    .animation(.spring(response: 0.30, dampingFraction: 0.84), value: tab)
            }
        }
        .frame(height: max(30, L.safeTop))
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }
}

struct StarOrbitProfileAccent: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Circle()
                    .trim(from: 0.08, to: 0.78)
                    .stroke(
                        Color.white.opacity(0.13),
                        style: StrokeStyle(lineWidth: 0.8, dash: [3, 6])
                    )
                    .frame(width: 168, height: 168)
                    .position(x: geo.size.width - 4, y: -4)

                Circle()
                    .fill(OrbitTheme.gold.opacity(0.62))
                    .frame(width: 4, height: 4)
                    .position(x: geo.size.width - 82, y: 22)

                Circle()
                    .fill(Color.white.opacity(0.38))
                    .frame(width: 2.5, height: 2.5)
                    .position(x: geo.size.width - 16, y: 63)
            }
        }
        .allowsHitTesting(false)
    }
}

struct StarOrbitCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(OrbitTheme.cardBackground())
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct StarOrbitSearchField: View {
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
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(OrbitTheme.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 13)
        .frame(height: 42)
        .background(OrbitTheme.field)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(OrbitTheme.divider, lineWidth: 0.7)
        }
    }
}

private struct StarTagGroup: Identifiable {
    let name: String
    let users: [User]
    var id: String { name }
}

struct StarOrbitTagsView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var keyword = ""

    private var groups: [StarTagGroup] {
        var grouped: [String: [User]] = [:]
        for user in app.contacts {
            for raw in user.tags ?? [] {
                let tag = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if tag.isEmpty { continue }
                grouped[tag, default: []].append(user)
            }
        }
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        return grouped.map { StarTagGroup(name: $0.key, users: $0.value) }
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("标签"), back: { dismiss() })
            ScrollView {
                LazyVStack(spacing: 12) {
                    StarOrbitHero(
                        kicker: "联系人星图",
                        title: Tr("标签"),
                        subtitle: Tr("把重要的人放进你的星轨，关系会更清晰"),
                        symbol: "tag.fill",
                        accent: OrbitTheme.gold,
                        metrics: [
                            StarOrbitMetric(value: "\(groups.count)", label: Tr("个标签")),
                            StarOrbitMetric(value: "\(groups.reduce(0) { $0 + $1.users.count })", label: Tr("次标注"))
                        ]
                    )
                    .padding(.horizontal, 12)

                    StarOrbitSearchField(placeholder: Tr("搜索标签"), text: $keyword)
                        .padding(.horizontal, 12)

                    if groups.isEmpty {
                        emptyState
                    } else {
                        OrbitSectionLabel(text: Tr("我的标签"), count: groups.count)
                            .padding(.horizontal, 17)
                            .padding(.top, 2)

                        ForEach(groups) { group in
                            NavigationLink {
                                StarOrbitTagDetailView(tag: group.name, users: group.users)
                                    .environmentObject(app)
                            } label: {
                                tagCard(group)
                            }
                            .buttonStyle(MenuPressStyle())
                            .padding(.horizontal, 12)
                        }
                    }
                    Spacer().frame(height: 30)
                }
                .padding(.top, 10)
            }
            .refreshable { await app.loadContacts() }
        }
        .background(OrbitTheme.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .task { await app.loadContacts() }
    }

    private func tagCard(_ group: StarTagGroup) -> some View {
        StarOrbitCard {
            HStack(spacing: 13) {
                StarOrbitIconBadge(symbol: "tag.fill", accent: OrbitTheme.gold)
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name)
                        .font(.system(size: 16.5, weight: .semibold))
                        .foregroundStyle(OrbitTheme.ink)
                        .lineLimit(1)
                    Text(group.users.prefix(3).map(\.name).joined(separator: " · "))
                        .font(.system(size: 12.5))
                        .foregroundStyle(OrbitTheme.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                StarOrbitTrailingPill(text: "\(group.users.count)", accent: OrbitTheme.gold)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(OrbitTheme.tertiary)
            }
            .padding(.horizontal, 15)
            .frame(height: 72)
            .contentShape(Rectangle())
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            StarOrbitIconBadge(symbol: "sparkles", accent: OrbitTheme.gold, size: 54)
            Text(Tr("还没有标签"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(OrbitTheme.ink)
            Text(Tr("在联系人资料里设置标签，这里会自动形成你的关系星图"))
                .font(.system(size: 13))
                .foregroundStyle(OrbitTheme.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
        .padding(.horizontal, 26)
        .background(OrbitTheme.cardBackground())
        .clipShape(OrbitTheme.card)
        .padding(.horizontal, 12)
    }
}

struct StarOrbitTagDetailView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    let tag: String
    let users: [User]

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: tag, back: { dismiss() })
            ScrollView {
                LazyVStack(spacing: 10) {
                    StarOrbitHero(
                        kicker: "星轨成员",
                        title: tag,
                        subtitle: Tr("同一星轨上的联系人"),
                        symbol: "point.3.connected.trianglepath.dotted",
                        accent: OrbitTheme.gold,
                        metrics: [StarOrbitMetric(value: "\(users.count)", label: Tr("位联系人"))]
                    )
                    .padding(.horizontal, 12)

                    ForEach(users) { user in
                        NavigationLink {
                            ContactCardView(
                                user: user,
                                onOpenChat: { chat in app.openChat = chat },
                                onOpenMoments: { _ in }
                            )
                            .environmentObject(app)
                        } label: {
                            StarOrbitCard {
                                HStack(spacing: 13) {
                                    Avatar(path: user.avatarPath, size: 44, radius: 12)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(user.name)
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundStyle(OrbitTheme.ink)
                                        Text("@" + (user.username ?? ""))
                                            .font(.system(size: 12))
                                            .foregroundStyle(OrbitTheme.secondary)
                                    }
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(OrbitTheme.tertiary)
                                }
                                .padding(.horizontal, 15)
                                .frame(height: 68)
                                .contentShape(Rectangle())
                            }
                        }
                        .buttonStyle(MenuPressStyle())
                        .padding(.horizontal, 12)
                    }
                    Spacer().frame(height: 30)
                }
                .padding(.top, 10)
            }
        }
        .background(OrbitTheme.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
    }
}
