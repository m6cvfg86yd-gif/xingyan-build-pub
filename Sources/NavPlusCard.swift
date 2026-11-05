import SwiftUI

struct NavPlusItem {
    var title: String
    var symbol: String
    var colors: [Color]
    var action: () -> Void
}

struct NavPlusCard: View {
    var items: [NavPlusItem]

    var onPick: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                if idx > 0 {
                    Rectangle()
                        .fill(OrbitTheme.divider)
                        .frame(height: 0.5)
                        .padding(.leading, 54)
                }
                Button {
                    onPick()
                    item.action()
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(OrbitTheme.field)
                            Image(systemName: item.symbol)
                                .font(.system(size: 14.5, weight: .semibold))
                                .foregroundColor(OrbitTheme.jade)
                        }
                        .frame(width: 34, height: 34)
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(OrbitTheme.divider, lineWidth: 0.6)
                        )

                        Text(item.title)
                            .font(pfStyled(size: 14.5, weight: .medium))
                            .foregroundColor(OrbitTheme.ink)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(NavPlusRowPressStyle())
            }
        }
        .frame(width: 194)

        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(OrbitTheme.raised)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(OrbitTheme.divider, lineWidth: 0.7)
        )
        .shadow(color: Color.black.opacity(0.16), radius: 18, y: 9)
    }
}

private struct NavPlusRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .background(configuration.isPressed ? OrbitTheme.jadeSoft.opacity(0.72) : Color.clear)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension View {

    @ViewBuilder
    func navPlusOverlay(_ show: Binding<Bool>, items: [NavPlusItem]) -> some View {
        overlay {
            if show.wrappedValue {

                GeometryReader { g in
                    let overlayTop = g.frame(in: .global).minY
                    let want = L.safeTop + L.navH + UIConfig.num("plusCardTopGap", -2)
                    let padTop = max(0, want - overlayTop)
                    ZStack(alignment: .topTrailing) {

                        Color.black.opacity(0.001)
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation(.easeOut(duration: 0.14)) { show.wrappedValue = false }
                            }
                        NavPlusCard(items: items) {
                            withAnimation(.easeOut(duration: 0.12)) { show.wrappedValue = false }
                        }
                        .padding(.top, padTop)
                        .padding(.trailing, UIConfig.num("plusCardRightGap", 10))

                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.42, anchor: .topTrailing)
                                .combined(with: .opacity)
                                .combined(with: .offset(y: -10)),
                            removal: .scale(scale: 0.92, anchor: .topTrailing)
                                .combined(with: .opacity)
                        ))
                    }
                }
            }
        }
    }
}
