import SwiftUI

enum OrbitTheme {
    static var canvas: Color { C.pageBg }
    static var raised: Color { C.cardBg }
    static var field: Color { C.searchBg }
    static var fieldRaised: Color { C.fieldBg }
    static var ink: Color { C.label }
    static var secondary: Color { C.subLabel }
    static var tertiary: Color { C.time }
    static var divider: Color { C.hairline }
    static let jade = Color.dyn(0x24C77F, 0x3AD48C)
    static let jadeDeep = Color.dyn(0x177D55, 0x52E09B)
    static let jadeSoft = Color.dyn(0xDDF8EB, 0x123A2A)
    static let gold = Color.dyn(0xC18A32, 0xE3B464)

    static let card = RoundedRectangle(cornerRadius: 20, style: .continuous)
    static let control = RoundedRectangle(cornerRadius: 13, style: .continuous)

    static func cardBackground(_ fill: Color = raised) -> some View {
        card
            .fill(fill)
            .overlay(card.stroke(divider, lineWidth: 0.7))
    }
}

struct OrbitSectionLabel: View {
    let text: String
    var count: Int? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(text)
                .font(pfStyled(size: 12, weight: .semibold))
                .foregroundStyle(OrbitTheme.secondary)
                .tracking(0.6)
            if let count {
                Text("\(count)")
                    .font(pfStyled(size: 9.5, weight: .bold))
                    .foregroundStyle(OrbitTheme.jade)
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(Capsule().fill(OrbitTheme.jadeSoft))
            }
            Spacer(minLength: 0)
        }
    }
}

struct OrbitUnreadBadge: View {
    let count: Int
    var muted = false

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(pfStyled(size: 9.5, weight: .bold))
            .foregroundStyle(muted ? OrbitTheme.tertiary : .white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, count > 9 ? 4 : 0)
            .frame(minWidth: 18, minHeight: 18)
            .background(Capsule().fill(muted ? OrbitTheme.fieldRaised : Color(.systemRed)))
            .overlay(Capsule().stroke(OrbitTheme.raised, lineWidth: 1.4))
    }
}
