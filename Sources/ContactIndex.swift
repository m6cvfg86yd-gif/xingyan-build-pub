import SwiftUI
import UIKit

func ctIdxWeight() -> Font.Weight { UIConfig.num("ctIdxBold", 1) > 0 ? .heavy : .regular }

struct ContactIndexBar: View {
    static let letters: [String] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ#".map { String($0) }

    var available: Set<String>
    var onPick: (String) -> Void
    var onSearch: () -> Void

    private let padV: CGFloat = 4.2

    private let searchBox: CGFloat = 26
    private let searchGap: CGFloat = 6

    @State private var active: String? = nil

    @GestureState private var touching = false

    private let haptic = UIImpactFeedbackGenerator(style: .heavy)

    private var fontSize: CGFloat { max(6.5, L.ctIdxSize - 0.5) }
    private var rowH: CGFloat { max(fontSize, L.ctIdxItemH) }
    private var pitch: CGFloat { rowH }

    private var dotSide: CGFloat { max(16, rowH + 2) }

    private var letters: [String] {
        Self.letters.filter { available.contains($0) }
    }
    private var shownLetter: String? { touching ? active : nil }

    var body: some View {
        VStack(spacing: searchGap) {
            Button(action: onSearch) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(OrbitTheme.jade)
                    .frame(width: searchBox, height: searchBox)
                    .background(Circle().fill(OrbitTheme.raised))
                    .overlay(Circle().stroke(OrbitTheme.divider, lineWidth: 0.6))
                    .shadow(color: Color.black.opacity(0.08), radius: 5, y: 2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Tr("搜索"))

            VStack(spacing: 0) {
                ForEach(letters, id: \.self) { L in
                    Text(L)
                        .font(pfStyled(size: fontSize, weight: shownLetter == L ? .bold : .medium))

                        .foregroundColor(shownLetter == L ? .white : OrbitTheme.tertiary)
                        .frame(height: rowH)
                        .frame(width: 18)
                        .background {
                            if shownLetter == L {
                                Capsule(style: .continuous)
                                    .fill(OrbitTheme.jade)
                                    .frame(width: dotSide, height: dotSide)
                            }
                        }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($touching) { _, state, _ in state = true }
                    .onChanged { value in
                        guard !letters.isEmpty else { return }
                        let i = max(0, min(letters.count - 1,
                                           Int(floor(value.location.y / pitch))))
                        pick(letters[i])
                    }
                    .onEnded { _ in
                        active = nil
                    }
            )
            .onDisappear { active = nil }
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(OrbitTheme.field.opacity(0.92))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(OrbitTheme.divider, lineWidth: 0.6)
                    )
            )
        }
        .padding(.vertical, padV)
        .frame(width: 28)
        .onAppear { haptic.prepare() }
        .onChange(of: available) { _ in haptic.prepare() }
    }

    private func pick(_ letter: String) {
        if active != letter {
            active = letter
            haptic.impactOccurred(intensity: 1.0)
            haptic.prepare()
        }
        onPick(letter)
    }
}

struct LetterBubble: View {
    let letter: String

    var body: some View {
        Text(letter)
            .font(pfStyled(size: 34, weight: .bold))
            .foregroundColor(OrbitTheme.ink)
            .frame(width: 74, height: 74)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(OrbitTheme.raised.opacity(0.96))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(OrbitTheme.jade.opacity(0.42), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.16), radius: 16, y: 7)
            )
            .allowsHitTesting(false)
    }
}
