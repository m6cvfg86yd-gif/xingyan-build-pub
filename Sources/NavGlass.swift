import SwiftUI

struct TopScrollKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct TopGlassBar: View {
    var scrolled: CGFloat

    var fallback: Color

    var offset: CGFloat = 80

    var always: Bool = false
    var matchFallback: Bool = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let blur = UIConfig.num("chatsNavGlassAlpha", 1)

        let mask = UIConfig.num("chatsNavMaskAlpha", 0)

        let raw = min(1, max(0, scrolled / max(1, offset)))

        let t = always ? 1 : pow(raw, 0.8)
        if t > 0.01 {

            Group {
                if matchFallback {
                    fallback
                } else if scheme == .dark {

                    HarmonyDarkMask(strength: 0.98)
                } else {
                    ZStack {
                        Rectangle().fill(.bar)
                            .opacity(max(0, min(1, blur)) * t)
                        (UIConfig.colorIfSet("chatsNavMaskColor") ?? fallback)
                            .opacity(max(0, min(1, mask)) * t)

                        if UIConfig.num("navRimLight", 1) > 0 {
                            RadialGradient(colors: [Color.white.opacity(0.30 * t), Color.clear],
                                           center: UnitPoint(x: 0.14, y: 0.18),
                                           startRadius: 1, endRadius: 170)
                            VStack { Spacer()
                                Rectangle()
                                    .fill(LinearGradient(colors: [Color.clear,
                                                                  Color.white.opacity(0.22 * t),
                                                                  Color.clear],
                                                         startPoint: .leading, endPoint: .trailing))
                                    .frame(height: 0.5)
                            }
                        }
                    }
                }
            }
            .ignoresSafeArea(edges: .top)

            .allowsHitTesting(false)
        }
    }
}

struct TopGlassLine: View {
    var scrolled: CGFloat
    var body: some View {
        Rectangle()
            .fill(C.navLine)
            .frame(height: 0.5)
            .opacity(scrolled > 6 ? 1 : 0)
    }
}

struct NavPlusGlassBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let base = UIConfig.color("navPlusBg", 0x51A969, 0x51A969)
        ZStack {
            Circle().fill(base)
            Circle().fill(
                LinearGradient(colors: [
                    Color.white.opacity(scheme == .dark ? 0.13 : 0.18),
                    Color.clear,
                    Color.black.opacity(scheme == .dark ? 0.10 : 0.07)
                ], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            Circle()
                .stroke(Color.white.opacity(scheme == .dark ? 0.16 : 0.24),
                        lineWidth: 0.7)
        }
        .shadow(color: Color.black.opacity(scheme == .dark ? 0.30 : 0.16),
                radius: 8, y: 4)
    }
}

struct NativeGlassCircleBackground: View {
    private let shape = Circle()

    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(.regular, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.20), lineWidth: 0.7))
                .shadow(color: Color.black.opacity(0.10), radius: 7, y: 3)
                .allowsHitTesting(false)
        } else {
            fallback
        }
        #else
        fallback
        #endif
    }

    private var fallback: some View {
        shape
            .fill(.ultraThinMaterial)
            .overlay(shape.stroke(Color.white.opacity(0.32), lineWidth: 0.7))
            .shadow(color: Color.black.opacity(0.10), radius: 7, y: 3)
            .allowsHitTesting(false)
    }
}

struct NativeGlassPlusButton: View {
    let action: () -> Void

    var body: some View {
        NativeGlassIconButton(symbol: "plus", label: Tr("更多"), action: action)
    }
}

struct NativeGlassIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16.5, weight: .semibold))
                .foregroundStyle(Color(hex: 0x34C759))
                .frame(width: 38, height: 38)
                .contentShape(Circle())
        }
        .buttonStyle(NavPlusPressStyle())
        .background { NativeGlassCircleBackground() }
        .accessibilityLabel(label)
    }
}

struct TopScrollProbe: View {
    var space: String
    var body: some View {
        GeometryReader { g in
            Color.clear.preference(key: TopScrollKey.self,
                                   value: -g.frame(in: .named(space)).minY)
        }
    }
}

extension View {
    func topScrollTracking(_ scrolled: Binding<CGFloat>, space: String) -> some View {
        self
            .coordinateSpace(name: space)
            .onPreferenceChange(TopScrollKey.self) { v in
                let s = max(0, v)
                if s > scrolled.wrappedValue || s < 1 {
                    if abs(s - scrolled.wrappedValue) > 0.5 { scrolled.wrappedValue = s }
                }
            }
    }
}
