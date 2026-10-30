import SwiftUI
import Photos
import UIKit

struct MomentNoteCard: View {
    let moment: Moment
    let columnWidth: CGFloat
    let onOpenComments: () -> Void
    let onOpenVideo: (URL) -> Void
    let onOpenAvatar: (User) -> Void
    let onLike: () -> Void
    let onMore: () -> Void
    var onDelete: (() -> Void)? = nil

    @EnvironmentObject private var app: AppState
    @State private var heartBounce = false
    @State private var imageMenu = false
    @State private var deleteMoment = false
    @State private var likedOverride: Bool?

    private var images: [String] { moment.images ?? [] }
    private var isVideo: Bool { !(moment.video ?? "").isEmpty }
    private var showingLiked: Bool { likedOverride ?? (moment.likedByMe == true) }
    private var showingLikeCount: Int {
        let base = (moment.likes ?? []).count
        guard let likedOverride else { return base }
        let server = moment.likedByMe == true
        if likedOverride == server { return base }
        return max(0, base + (likedOverride ? 1 : -1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !images.isEmpty || isVideo {
                media
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.black.opacity(0.10), lineWidth: 0.45)
                    )
                    .shadow(color: Color.black.opacity(0.10), radius: 5, y: 2)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isVideo {
                            openVideo()
                        } else {
                            onOpenComments()
                        }
                    }
                    .onLongPressGesture(minimumDuration: 0.45, maximumDistance: 28) {
                        if moment.mine == true {
                            onMore()
                        } else if !images.isEmpty {
                            imageMenu = true
                        }
                    }
            }

            if let content = moment.content?.trimmingCharacters(in: .whitespacesAndNewlines),
               !content.isEmpty {
                Text(RichText.linkified(content))
                    .font(pf(14.2, .medium))
                    .foregroundColor(C.label)
                    .lineSpacing(2)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, (images.isEmpty && !isVideo) ? 2 : 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { onOpenComments() }
                    .onLongPressGesture(minimumDuration: 0.45, maximumDistance: 28) {
                        if moment.mine == true { onMore() }
                    }
            }

            authorRow
                .padding(.top, 9)

            actionRow
                .padding(.top, 6)
        }
        .padding(.bottom, 12)
        .frame(width: columnWidth, alignment: .leading)
        .background(C.cardBg)
        .contentShape(Rectangle())
        .confirmationDialog(Tr("图片"), isPresented: $imageMenu, titleVisibility: .visible) {
            Button(Tr("保存图片")) { saveFirstImage() }
            Button(Tr("查看评论")) { onOpenComments() }
            Button(Tr("取消"), role: .cancel) { }
        }
        .alert(Tr("删除这条朋友圈？"), isPresented: $deleteMoment) {
            Button(Tr("取消"), role: .cancel) { }
            Button(Tr("删除"), role: .destructive) { onDelete?() }
        } message: {
            Text(Tr("删除后无法恢复。"))
        }
        .onChange(of: moment.likedByMe) { _ in likedOverride = nil }
    }

    private var media: some View {
        ZStack {
            if isVideo {
                videoCover
            } else if let first = images.first {
                RemoteImage(path: first, icon: "photo", maxSide: 900)
            } else {
                C.searchBg
            }

            if isVideo {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 54, height: 54)
                        .overlay(Circle().fill(Color.black.opacity(0.18)))
                        .overlay(Circle().stroke(Color.white.opacity(0.55), lineWidth: 0.8))
                    Image(systemName: "play.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                        .offset(x: 1.5)
                        .shadow(color: .black.opacity(0.38), radius: 4, y: 1)
                }
            }

            VStack {
                HStack(alignment: .top, spacing: 5) {
                    if moment.pinned == true {
                        capsule(Tr("置顶"))
                    }
                    Spacer(minLength: 0)
                    if images.count > 1 {
                        capsule("1/\(images.count)")
                    }
                }
                Spacer(minLength: 0)
                if isVideo, (moment.videoSeconds ?? 0) > 0 {
                    HStack {
                        Spacer(minLength: 0)
                        capsule(Self.timeText(moment.videoSeconds ?? 0))
                    }
                }
            }
            .padding(7)
            .allowsHitTesting(false)
        }
        .frame(width: columnWidth, height: mediaHeight)
        .clipped()
    }

    private var videoCover: some View {
        Group {
            if let cover = moment.videoCover, !cover.isEmpty {
                RemoteImage(path: cover, icon: "photo", maxSide: 1080)
            } else {
                C.searchBg
            }
        }
    }

    private var authorRow: some View {
        HStack(spacing: 5) {
            authorAvatar
                .contentShape(Rectangle())
                .onTapGesture {
                    if let user = moment.author { onOpenAvatar(user) }
                }
            Text(moment.author?.name ?? "")
                .font(pf(11.2))
                .foregroundColor(C.subLabel)
                .lineLimit(1)
                .contentShape(Rectangle())
                .onTapGesture {
                    if let user = moment.author { onOpenAvatar(user) }
                }
            Spacer(minLength: 2)
            Text(TimeFmt.ago(moment.createdAt))
                .font(pf(10.5))
                .foregroundColor(C.subLabel)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var authorAvatar: some View {
        let path = moment.author?.avatarPath ?? ""
        if path.isEmpty {
            Text(String((moment.author?.name ?? Tr("友")).prefix(1)))
                .font(pf(9.5, .medium))
                .foregroundColor(C.subLabel)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.dyn(0xEFEFEE, 0x2B2B2B)))
        } else {
            Avatar(path: path, size: 22, radius: 7)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button {
                likedOverride = !showingLiked
                withAnimation(.spring(response: 0.22, dampingFraction: 0.58)) {
                    heartBounce = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                    heartBounce = false
                }
                onLike()
            } label: {
                HStack(spacing: 3) {
                    ZStack {
                        Image(systemName: showingLiked ? "heart.fill" : "heart")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(showingLiked ? Color(hex: 0xFA5151) : C.subLabel)
                            .scaleEffect(heartBounce ? 1.28 : 1)
                        if heartBounce { HeartBurst() }
                    }
                    if showingLikeCount > 0 {
                        Text("\(showingLikeCount)")
                            .font(pf(10.5))
                            .foregroundColor(C.subLabel)
                    }
                }
                .frame(height: 28)
            }
            .buttonStyle(.plain)

            Button(action: onOpenComments) {
                HStack(spacing: 3) {
                    Image(systemName: "bubble.right")
                        .font(.system(size: 13.5, weight: .medium))
                    if !(moment.comments ?? []).isEmpty {
                        Text("\((moment.comments ?? []).count)")
                            .font(pf(10.5))
                    }
                }
                .foregroundColor(C.subLabel)
                .frame(height: 28)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            if moment.mine == true {
                Button {
                    if onDelete != nil {
                        deleteMoment = true
                    } else {
                        onMore()
                    }
                } label: {
                    HStack(spacing: 2.2) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle()
                                .fill(Color(hex: 0x8A8F8B))
                                .frame(width: 3, height: 3)
                        }
                    }
                    .frame(width: 28, height: 28)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Tr("更多"))
            }
        }
    }

    private var mediaHeight: CGFloat {
        if isVideo {
            let w = CGFloat(max(1, moment.videoW ?? 4))
            let h = CGFloat(max(1, moment.videoH ?? 5))
            return min(columnWidth * 1.48, max(columnWidth * 0.68, columnWidth * h / w))
        }
        guard let first = images.first, let size = moment.imageSizes?[first],
              size.count >= 2, size[0] > 0, size[1] > 0 else {
            return columnWidth * 1.16
        }
        return min(columnWidth * 1.50, max(columnWidth * 0.72,
                                         columnWidth * CGFloat(size[1]) / CGFloat(size[0])))
    }

    private func capsule(_ text: String) -> some View {
        Text(text)
            .font(pf(9.3, .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(Color.black.opacity(0.48)))
    }

    private func openVideo() {
        let raw = moment.video ?? ""
        guard !raw.isEmpty else { return }
        let full = raw.hasPrefix("http") ? raw : API.shared.base + raw
        if let url = URL(string: full) { onOpenVideo(url) }
    }

    private func saveFirstImage() {
        guard let first = images.first else { return }
        Task {
            if let data = try? await API.shared.imageData(API.shared.assetURL(first) ?? URL(fileURLWithPath: "")),
               let image = UIImage(data: data) {
                let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                guard status == .authorized || status == .limited else {
                    app.show(Tr("需要相册权限才能保存"))
                    return
                }
                try? await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
                app.show(Tr("图片已保存"))
            } else {
                app.show(Tr("图片保存失败"))
            }
        }
    }

    private static func timeText(_ seconds: Int) -> String {
        String(format: "%02d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
    }
}
