import SwiftUI

struct WeChatMessageCard<Content: View>: View {
    var width: CGFloat = 268
    var padding: CGFloat = 13
    let content: Content

    init(width: CGFloat = 268,
         padding: CGFloat = 13,
         @ViewBuilder content: () -> Content) {
        self.width = width
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(width: width, alignment: .leading)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.regularMaterial)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.dyn(0xFFFFFF, 0x242426).opacity(0.72))
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.13), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.28),
                                     Color.black.opacity(0.07)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.7
                    )
            }
            .shadow(color: Color.black.opacity(0.08), radius: 12, y: 5)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct WeChatMessageCardFooter: View {
    let symbol: String
    let title: String
    var trailing: String = ""

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(C.green)
                .frame(width: 20, height: 20)
                .background(C.green.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(title)
                .font(pfStyled(size: 11, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 5)
            if !trailing.isEmpty {
                Text(trailing)
                    .font(pfStyled(size: 10, weight: .medium))
                    .foregroundStyle(C.subLabel)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(Color.primary.opacity(0.045),
                                in: Capsule(style: .continuous))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(C.subLabel)
    }
}
