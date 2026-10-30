import SwiftUI

enum OrbitTheme {
    static let canvas = Color.dyn(0xF5F4F0, 0x080A09)
    static let raised = Color.dyn(0xFFFFFF, 0x191919)
    static let field = Color.dyn(0xECEAE4, 0x171B19)
    static let fieldRaised = Color.dyn(0xE6E3DC, 0x1D2220)
    static let ink = Color.dyn(0x17201C, 0xEFF4F1)
    static let secondary = Color.dyn(0x626B66, 0xA8B2AD)
    static let tertiary = Color.dyn(0x929994, 0x727C77)
    static let divider = Color.dyn(0xE2DFD7, 0x232925)
    static let jade = Color.dyn(0x176A57, 0x63C6A5)
    static let jadeDeep = Color.dyn(0x0F4F41, 0x3B9C7E)
    static let jadeSoft = Color.dyn(0xDCEFE8, 0x173A31)
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
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(OrbitTheme.secondary)
                .tracking(0.6)
            if let count {
                Text("\(count)")
                    .font(.system(size: 9.5, weight: .bold))
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
            .font(.system(size: 9.5, weight: .bold))
            .foregroundStyle(muted ? OrbitTheme.tertiary : .white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, count > 9 ? 4 : 0)
            .frame(minWidth: 18, minHeight: 18)
            .background(Capsule().fill(muted ? OrbitTheme.fieldRaised : C.red))
            .overlay(Capsule().stroke(OrbitTheme.raised, lineWidth: 1.4))
    }
}
