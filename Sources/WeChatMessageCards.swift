import SwiftUI

struct WeChatMessageCard<Content: View>: View {
    var width: CGFloat = 250
    var padding: CGFloat = 11
    let content: Content

    init(width: CGFloat = 250,
         padding: CGFloat = 11,
         @ViewBuilder content: () -> Content) {
        self.width = width
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(width: width, alignment: .leading)
            .background(Color.dyn(0xFFFFFF, 0x2C2C2E))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(C.hairline.opacity(0.86), lineWidth: 0.55)
            }
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct WeChatMessageCardFooter: View {
    let symbol: String
    let title: String
    var trailing: String = ""

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 5)
            if !trailing.isEmpty {
                Text(trailing)
                    .lineLimit(1)
            }
        }
        .font(pfStyled(size: 10.5, weight: .medium))
        .foregroundStyle(C.subLabel)
    }
}
