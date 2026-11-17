import SwiftUI
import UIKit

struct ShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// Shared visual language for every outbound share surface in the app.
/// The hierarchy follows Xiaohongshu: content preview, compact circular
/// actions, secondary utility row, then one explicit cancel action.
enum ShareSheetTheme {
    static let accent = Color(hex: 0xFF2442)
    static let secondaryAccent = Color(hex: 0x2AAE88)

    static func page(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x111113) : Color(hex: 0xF7F7F8)
    }

    static func card(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x1D1D20) : .white
    }

    static func ink(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xF5F5F7) : Color(hex: 0x171719)
    }

    static func secondaryInk(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x99999F) : Color(hex: 0x707077)
    }
}

struct SharePreviewCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(12)
            .background(ShareSheetTheme.card(scheme))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.primary.opacity(scheme == .dark ? 0.08 : 0.05),
                            lineWidth: 0.7)
            }
            .shadow(color: Color.black.opacity(scheme == .dark ? 0.24 : 0.055),
                    radius: 18, y: 8)
    }
}

struct ShareActionTile: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    let subtitle: String?
    let symbol: String
    let tint: Color
    let action: () -> Void

    init(title: String,
         subtitle: String? = nil,
         symbol: String,
         tint: Color,
         action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    tint.opacity(scheme == .dark ? 0.34 : 0.18),
                                    tint.opacity(scheme == .dark ? 0.17 : 0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 54, height: 54)
                        .overlay {
                            Circle()
                                .stroke(Color.white.opacity(scheme == .dark ? 0.10 : 0.46),
                                        lineWidth: 0.8)
                        }
                    Image(systemName: symbol)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(tint)
                }
                Text(Tr(title))
                    .font(pf(11.5, .medium))
                    .foregroundStyle(ShareSheetTheme.ink(scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                if let subtitle, !subtitle.isEmpty {
                    Text(Tr(subtitle))
                        .font(pf(9.5))
                        .foregroundStyle(ShareSheetTheme.secondaryInk(scheme))
                        .lineLimit(1)
                }
            }
            .frame(width: 72)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ShareSheet: View {
    let items: [Any]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var copied = false
    @State private var saved = false

    private var image: UIImage? {
        for item in items {
            if let value = item as? UIImage { return value }
            if let data = item as? Data, let value = UIImage(data: data) { return value }
            if let url = item as? URL,
               url.isFileURL,
               let value = UIImage(contentsOfFile: url.path) {
                return value
            }
        }
        return nil
    }

    private var remoteImageURL: URL? {
        for item in items {
            guard let url = item as? URL, !url.isFileURL else { continue }
            let ext = url.pathExtension.lowercased()
            if ["jpg", "jpeg", "png", "heic", "webp", "gif"].contains(ext) {
                return url
            }
        }
        return nil
    }

    private var shareURL: URL? {
        for item in items {
            if let url = item as? URL { return url }
            if let text = item as? String,
               let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
               ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                return url
            }
        }
        return nil
    }

    private var primaryText: String {
        for item in items {
            if let text = item as? String,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
            if let url = item as? URL { return url.lastPathComponent }
        }
        return Tr("来自星言的内容")
    }

    private var previewTitle: String {
        if image != nil || remoteImageURL != nil { return Tr("图片") }
        guard let url = shareURL else { return Tr("文字内容") }
        let ext = url.pathExtension.lowercased()
        if ["mp4", "mov", "m4v", "webm"].contains(ext) { return Tr("视频") }
        if !ext.isEmpty { return Tr("文件") }
        return Tr("链接")
    }

    private var previewSymbol: String {
        if image != nil || remoteImageURL != nil { return "photo.on.rectangle.angled" }
        if previewTitle == Tr("视频") { return "play.rectangle.fill" }
        if previewTitle == Tr("文件") { return "doc.fill" }
        if shareURL != nil { return "link" }
        return "text.quote"
    }

    private var copyText: String? {
        if let shareURL { return shareURL.absoluteString }
        return items.compactMap { $0 as? String }.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    preview
                    actionRail
                    moreCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            cancelButton
        }
        .background(ShareSheetTheme.page(scheme).ignoresSafeArea())
        .presentationDragIndicator(.hidden)
        .presentationDetents([.height(492), .large])
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Tr("分享到"))
                    .font(pf(20, .bold))
                    .foregroundStyle(ShareSheetTheme.ink(scheme))
                Text(Tr("把内容发送到聊天、朋友或更多应用"))
                    .font(pf(11.5))
                    .foregroundStyle(ShareSheetTheme.secondaryInk(scheme))
            }
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(ShareSheetTheme.secondaryInk(scheme))
                    .frame(width: 34, height: 34)
                    .background(ShareSheetTheme.card(scheme), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Tr("关闭"))
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var preview: some View {
        SharePreviewCard {
            HStack(spacing: 13) {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 78, height: 92)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                } else if let remoteImageURL {
                    AsyncImage(url: remoteImageURL) { phase in
                        if let value = phase.image {
                            value.resizable().scaledToFill()
                        } else {
                            previewPlaceholder
                        }
                    }
                    .frame(width: 78, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                } else {
                    previewPlaceholder
                        .frame(width: 78, height: 92)
                }

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(ShareSheetTheme.accent)
                            .frame(width: 6, height: 6)
                        Text(previewTitle.uppercased())
                            .font(pfStyled(size: 9, weight: .bold))
                            .tracking(1.15)
                            .foregroundStyle(ShareSheetTheme.accent)
                    }
                    Text(primaryText)
                        .font(pf(14.5, .semibold))
                        .foregroundStyle(ShareSheetTheme.ink(scheme))
                        .lineLimit(3)
                    Text(shareURL?.host ?? Tr("来自星言"))
                        .font(pf(10.5))
                        .foregroundStyle(ShareSheetTheme.secondaryInk(scheme))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var previewPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            ShareSheetTheme.accent.opacity(0.16),
                            ShareSheetTheme.secondaryAccent.opacity(0.13)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: previewSymbol)
                .font(.system(size: 29, weight: .medium))
                .foregroundStyle(ShareSheetTheme.accent)
        }
    }

    private var actionRail: some View {
        HStack(alignment: .top, spacing: 8) {
            if copyText != nil {
                ShareActionTile(
                    title: copied ? "已复制" : "复制链接",
                    subtitle: copied ? nil : "发送给朋友",
                    symbol: copied ? "checkmark" : "link",
                    tint: ShareSheetTheme.accent
                ) {
                    UIPasteboard.general.string = copyText
                    withAnimation(.easeOut(duration: 0.16)) { copied = true }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
            if image != nil {
                ShareActionTile(
                    title: saved ? "已保存" : "保存图片",
                    subtitle: saved ? nil : "存入相册",
                    symbol: saved ? "checkmark" : "arrow.down.to.line.compact",
                    tint: Color(hex: 0x2B8CF6)
                ) {
                    guard let image else { return }
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    withAnimation(.easeOut(duration: 0.16)) { saved = true }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
            ShareActionTile(
                title: "系统分享",
                subtitle: "更多应用",
                symbol: "square.and.arrow.up",
                tint: ShareSheetTheme.secondaryAccent
            ) {
                presentSystemShare()
            }
            ShareActionTile(
                title: "关闭",
                subtitle: "返回页面",
                symbol: "xmark",
                tint: Color(hex: 0x8B8B91)
            ) {
                dismiss()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var moreCard: some View {
        Button {
            UIPasteboard.general.string = copyText
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.easeOut(duration: 0.16)) { copied = true }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(ShareSheetTheme.accent)
                    .frame(width: 36, height: 36)
                    .background(ShareSheetTheme.accent.opacity(0.10), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(Tr("复制原始内容"))
                        .font(pf(14.5, .medium))
                        .foregroundStyle(ShareSheetTheme.ink(scheme))
                    Text(Tr("适合粘贴到聊天、备忘录或其他应用"))
                        .font(pf(10.5))
                        .foregroundStyle(ShareSheetTheme.secondaryInk(scheme))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ShareSheetTheme.secondaryInk(scheme).opacity(0.62))
            }
            .padding(.horizontal, 14)
            .frame(height: 66)
            .background(ShareSheetTheme.card(scheme),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(copyText == nil)
        .opacity(copyText == nil ? 0.45 : 1)
    }

    private var cancelButton: some View {
        Button { dismiss() } label: {
            Text(Tr("取消"))
                .font(pf(16, .semibold))
                .foregroundStyle(ShareSheetTheme.ink(scheme))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(ShareSheetTheme.card(scheme))
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }

    private func presentSystemShare() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController else {
            return
        }
        var presenter = root
        while let next = presenter.presentedViewController {
            presenter = next
        }
        let controller = UIActivityViewController(activityItems: items,
                                                  applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX,
                                        y: presenter.view.bounds.maxY - 80,
                                        width: 1, height: 1)
        }
        presenter.present(controller, animated: true)
    }
}

func writeTempFile(name: String, text: String) -> URL? {
    let dir = FileManager.default.temporaryDirectory
    let url = dir.appendingPathComponent(name)
    do {
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    } catch {
        return nil
    }
}
