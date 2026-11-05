import SwiftUI

struct NoteCardBubble: View {

    let text: String
    var mine: Bool
    var showTail: Bool
    var seed: Double

    @State private var open = false

    private var title: String {
        let first = text.split(separator: "\n").first.map(String.init) ?? text
        let t = first.hasPrefix("[图]") ? "图片" : first
        return String(t.prefix(24))
    }
    private var preview: String {
        var lines: [String] = []
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("[图]") { lines.append("［图片］"); continue }
            if !line.trimmingCharacters(in: .whitespaces).isEmpty { lines.append(line) }
            if lines.count >= 4 { break }
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        Button { open = true } label: {
            WeChatMessageCard(width: 250) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(C.green)
                        .frame(width: 44, height: 44)
                        .background(C.green.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title.isEmpty ? Tr("笔记") : title)
                            .font(pfStyled(size: 15.5, weight: .medium))
                            .foregroundColor(C.label)
                            .lineLimit(2)
                        Text(preview)
                            .font(pfStyled(size: 12.5))
                            .foregroundColor(C.subLabel)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                }

                Rectangle()
                    .fill(C.hairline)
                    .frame(height: 0.5)
                    .padding(.vertical, 9)

                WeChatMessageCardFooter(symbol: "note.text", title: Tr("星言笔记"),
                                        trailing: Tr("打开"))
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $open) {
            NoteViewerSheet(text: text)
        }
    }
}

struct NoteViewerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let text: String
    @State private var copied = false

    @State private var viewerPath: String?

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("笔记"), back: { dismiss() }) {
                Button {
                    UIPasteboard.general.string = text
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                } label: {
                    Text(copied ? Tr("已复制") : Tr("复制"))
                        .font(pf(15, .medium)).foregroundColor(C.green)
                        .padding(.horizontal, 14).frame(height: 32)
                }
                .buttonStyle(.plain)
            }
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                        if line.hasPrefix("[图]") {

                            NoteImageBlock(path: String(line.dropFirst(3))) { p in viewerPath = p }
                        } else if !line.isEmpty {
                            Text(line)
                                .font(pf(16))
                                .foregroundColor(C.label)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(14)
                .background(C.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 12)
                .padding(.top, 12)
                Spacer().frame(height: 30)
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .overlay {
            if let p = viewerPath, !p.isEmpty {
                PhotoPager(paths: [p], startIndex: 0, showActions: true) { viewerPath = nil }
            }
        }
    }
}

struct NoteImageBlock: View {
    let path: String

    var onTap: ((String) -> Void)? = nil

    @State private var height: CGFloat = 210

    var body: some View {
        RemoteImage(path: path, mode: .fill, maxSide: 1400) { img in

            let w = max(120, L.width - 52)
            let ratio = img.size.height / max(1, img.size.width)
            height = min(360, max(120, w * ratio))
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { onTap?(path) }
    }
}
