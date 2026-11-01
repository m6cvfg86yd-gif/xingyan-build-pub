import SwiftUI

struct SysNoticeInfo {
    var title = ""
    var text = ""

    init?(json: String) {
        guard let d = json.data(using: .utf8),
              let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return nil }
        let t = (o["title"] as? String) ?? ""
        let b = (o["text"] as? String) ?? ""
        guard !t.isEmpty || !b.isEmpty else { return nil }
        title = t.isEmpty ? Tr("通知") : t
        text = b
    }

    var fullText: String {
        text.isEmpty ? title : (title + "\n\n" + text)
    }

    var preview: String { text.isEmpty ? title : text }
}

struct SysNoticeBubble: View {
    let info: SysNoticeInfo
    var onOpen: () -> Void
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    expanded.toggle()
                }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(C.green)
                        Text(info.title)
                            .font(pf(15.5, .medium))
                            .foregroundColor(C.label)
                            .lineLimit(expanded ? 3 : 1)
                        Spacer(minLength: 0)
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(C.subLabel)
                    }
                    if !expanded, !info.text.isEmpty, info.preview != info.title {
                        Text(info.preview)
                            .font(pf(13))
                            .foregroundColor(C.subLabel)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                HairLine(inset: 0)
                if !info.text.isEmpty {
                    Text(info.text)
                        .font(pf(15))
                        .foregroundColor(C.label.opacity(0.9))
                        .lineLimit(12)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 13).padding(.vertical, 11)
                }
                HairLine(inset: 0)
                Button(action: onOpen) {
                    HStack(spacing: 4) {
                        Text(Tr("查看详情")).font(pf(14.5))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                        Spacer(minLength: 0)
                    }
                    .foregroundColor(Color(hex: 0x576B95))
                    .padding(.horizontal, 13).padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 252, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(C.cardBg))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(C.hairline, lineWidth: 0.5))
    }
}
