import SwiftUI
import UIKit

/// 生活圈主页的单列编辑流。只使用不透明语义底色和细分割线，
/// 不再叠加实时玻璃或阴影，避免长列表滚动时持续触发合成开销。
struct MomentFeedCard: View {
    let moment: Moment
    let availableWidth: CGFloat
    let onOpenComments: () -> Void
    let onOpenImage: (Int) -> Void
    let onOpenVideo: (URL) -> Void
    let onOpenAvatar: (User) -> Void
    let onLike: () -> Void
    let onMore: () -> Void

    @EnvironmentObject private var app: AppState
    @State private var likedOverride: Bool?
    @State private var likePulse = false
    @State private var showLikes = false
    @State private var likesSnapshot: [MomentLike] = []

    private var images: [String] { moment.images ?? [] }
    private var isVideo: Bool { !(moment.video ?? "").isEmpty }
    private var likes: [MomentLike] { moment.likes ?? [] }
    private var comments: [MomentComment] { moment.comments ?? [] }
    private var showingLiked: Bool { likedOverride ?? (moment.likedByMe == true) }

    private var showingLikeCount: Int {
        let base = likes.count
        guard let likedOverride else { return base }
        if likedOverride == (moment.likedByMe == true) { return base }
        return max(0, base + (likedOverride ? 1 : -1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            postHeader

            if let text = moment.content?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                Text(RichText.linkified(text))
                    .font(systemTextFont(15.5, .regular, relativeTo: .body))
                    .foregroundColor(C.label)
                    .lineSpacing(5)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 13)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onOpenComments)
                    .onLongPressGesture(minimumDuration: 0.45, maximumDistance: 28) {
                        if moment.mine == true { onMore() }
                    }
            }

            if !images.isEmpty || isVideo {
                media
                    .padding(.top, 13)
            }

            actionRow
                .padding(.top, 10)

            socialContext
                .padding(.top, 9)
        }
        .padding(.horizontal, L.momentPadH)
        .padding(.top, 18)
        .padding(.bottom, 17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(C.pageBg)
        .overlay(alignment: .bottom) {
            HairLine(inset: L.momentPadH)
        }
        .onChange(of: moment.likedByMe) { _ in
            likedOverride = nil
        }
        .sheet(isPresented: $showLikes) {
            MomentLikesSheet(likes: likesSnapshot)
                .environmentObject(app)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
        }
    }

    private var postHeader: some View {
        HStack(alignment: .center, spacing: 11) {
            Avatar(path: moment.author?.avatarPath ?? "",
                   size: 42,
                   radius: 21,
                   circle: true)
                .contentShape(Circle())
                .onTapGesture {
                    if let user = moment.author { onOpenAvatar(user) }
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(moment.author?.name ?? "")
                        .font(systemTextFont(15.5, .semibold, relativeTo: .headline))
                        .foregroundColor(C.label)
                        .lineLimit(1)

                    if moment.pinned == true {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(C.subLabel)
                    }
                }

                HStack(spacing: 5) {
                    Text(TimeFmt.ago(moment.createdAt))
                    if let location = moment.location?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !location.isEmpty {
                        Text("·")
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 10.5, weight: .medium))
                        Text(location).lineLimit(1)
                    }
                }
                .font(systemTextFont(12, .regular, relativeTo: .caption1))
                .foregroundColor(C.subLabel)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if let user = moment.author { onOpenAvatar(user) }
            }

            Spacer(minLength: 8)

            Button(action: onMore) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(C.subLabel)
                    .frame(width: 38, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Tr("更多"))
        }
    }

    @ViewBuilder
    private var media: some View {
        if isVideo {
            videoTile
        } else {
            MomentFeedImageGrid(images: images,
                                sizes: moment.imageSizes ?? [:],
                                width: availableWidth - L.momentPadH * 2,
                                onTap: onOpenImage)
        }
    }

    private var videoTile: some View {
        let width = max(1, availableWidth - L.momentPadH * 2)
        let ratio = CGFloat(max(1, moment.videoH ?? 4)) / CGFloat(max(1, moment.videoW ?? 5))
        let height = min(430, max(width * 0.62, width * ratio))

        return Button {
            let raw = moment.video ?? ""
            let full = raw.hasPrefix("http") ? raw : API.shared.base + raw
            if let url = URL(string: full) { onOpenVideo(url) }
        } label: {
            ZStack {
                if let cover = moment.videoCover, !cover.isEmpty {
                    RemoteImage(path: cover, mode: .fill, maxSide: 1440)
                } else {
                    C.searchBg
                }

                Circle()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: 54, height: 54)
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundColor(.white)
                            .offset(x: 1.5)
                    }

                if (moment.videoSeconds ?? 0) > 0 {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text(Self.timeText(moment.videoSeconds ?? 0))
                                .font(systemTextFont(11.5, .medium, relativeTo: .caption2))
                                .foregroundColor(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.black.opacity(0.62)))
                        }
                    }
                    .padding(8)
                }

                if moment.pinned == true {
                    VStack {
                        HStack {
                            Label(Tr("置顶"), systemImage: "pin.fill")
                                .font(systemTextFont(10.5, .semibold, relativeTo: .caption2))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.black.opacity(0.62)))
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(8)
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 0.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var actionRow: some View {
        HStack(spacing: 20) {
            Button {
                if !showingLiked {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                likedOverride = !showingLiked
                withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                    likePulse = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                    likePulse = false
                }
                onLike()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: showingLiked ? "heart.fill" : "heart")
                        .font(.system(size: 19, weight: .regular))
                        .scaleEffect(likePulse ? 1.16 : 1)
                    if showingLikeCount > 0 {
                        Text("\(showingLikeCount)")
                            .font(systemTextFont(12.5, .medium, relativeTo: .caption1))
                    }
                }
                .foregroundColor(showingLiked ? Color(hex: 0xFF3B4D) : C.subLabel)
                .frame(minWidth: 34, minHeight: 32, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showingLiked ? Tr("取消赞") : Tr("赞"))

            Button(action: onOpenComments) {
                HStack(spacing: 5) {
                    Image(systemName: "bubble.right")
                        .font(.system(size: 18, weight: .regular))
                    if !comments.isEmpty {
                        Text("\(comments.count)")
                            .font(systemTextFont(12.5, .medium, relativeTo: .caption1))
                    }
                }
                .foregroundColor(C.subLabel)
                .frame(minWidth: 34, minHeight: 32, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Tr("评论"))

            Spacer(minLength: 0)

            Button(action: onMore) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(C.subLabel)
                    .frame(width: 34, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Tr("更多"))
        }
    }

    @ViewBuilder
    private var socialContext: some View {
        if !likes.isEmpty || !comments.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                if !likes.isEmpty {
                    likesSummaryButton
                }

                ForEach(Array(comments.prefix(2).enumerated()), id: \.offset) { _, comment in
                    commentLine(comment)
                }

                if comments.count > 2 {
                    Button(action: onOpenComments) {
                        Text(Lang.isEnglish
                             ? "View all \(comments.count) comments"
                             : "查看全部 \(comments.count) 条评论")
                            .font(systemTextFont(12.5, .medium, relativeTo: .caption1))
                            .foregroundColor(C.subLabel)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var likesSummaryButton: some View {
        Button {
            likesSnapshot = stableOrderedLikes
            showLikes = true
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: 0xFF6985), Color(hex: 0xF33D5E)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(width: 25, height: 25)

                HStack(spacing: 2) {
                    ForEach(Array(stableOrderedLikes.prefix(8).enumerated()), id: \.offset) { _, like in
                        likeAvatar(like, size: 21)
                            .overlay(Circle().stroke(C.pageBg, lineWidth: 1.2))
                    }
                    if stableOrderedLikes.count > 8 {
                        Text("+\(stableOrderedLikes.count - 8)")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundColor(C.subLabel)
                            .frame(width: 21, height: 21)
                            .background(Circle().fill(Color.primary.opacity(0.07)))
                            .overlay(Circle().stroke(C.pageBg, lineWidth: 1.2))
                    }
                }
                .frame(height: 21)

                Text(localizedLikeSummary)
                    .font(systemTextFont(12.5, .medium, relativeTo: .caption1))
                    .foregroundColor(C.label)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(C.subLabel)
            }
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Lang.isEnglish
                            ? "\(showingLikeCount) people like this. View all."
                            : "\(showingLikeCount) 人觉得不错，查看全部")
    }

    @ViewBuilder
    private func likeAvatar(_ like: MomentLike, size: CGFloat) -> some View {
        let path = like.userId.flatMap { app.contact(for: $0)?.avatarPath } ?? ""
        if !path.isEmpty {
            Avatar(path: path, size: size, radius: size / 2, circle: true)
        } else {
            Text(String((like.nickname ?? Tr("星")).prefix(1)))
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundColor(C.subLabel)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.dyn(0xECECF0, 0x242426)))
        }
    }

    private var stableOrderedLikes: [MomentLike] {
        var seen = Set<String>()
        let unique = likes.filter { like in
            let key = like.userId?.isEmpty == false ? like.userId! : (like.nickname ?? UUID().uuidString)
            return seen.insert(key).inserted
        }
        let friends = unique.filter { app.contact(for: $0.userId ?? "") != nil }
        let others = unique.filter { app.contact(for: $0.userId ?? "") == nil }
        return friends + others
    }

    private var localizedLikeSummary: String {
        let names = likes.compactMap(\.nickname).filter { !$0.isEmpty }
        let count = showingLikeCount

        if Lang.isEnglish {
            switch names.count {
            case 0: return count == 1 ? "1 person likes this" : "\(count) people like this"
            case 1: return count > 1 ? "\(names[0]) and \(count - 1) others" : names[0]
            case 2: return count > 2 ? "\(names[0]), \(names[1]) and \(count - 2) others"
                : "\(names[0]) and \(names[1])"
            default: return "\(names[0]), \(names[1]) and \(count - 2) others"
            }
        }

        switch names.count {
        case 0: return "\(count) 人觉得不错"
        case 1: return count > 1 ? "\(names[0])等 \(count) 人" : names[0]
        case 2: return count > 2 ? "\(names[0])、\(names[1])等 \(count) 人"
            : "\(names[0])、\(names[1])"
        default: return "\(names[0])、\(names[1])等 \(count) 人"
        }
    }

    private func commentLine(_ comment: MomentComment) -> some View {
        let name = comment.nickname ?? ""
        let text = comment.content ?? ""
        let replyName = (comment.replyToName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let line = replyName.isEmpty
            ? "\(name)：\(text)"
            : "\(name) 回复 \(replyName)：\(text)"

        return Text(line)
            .foregroundColor(C.label)
            .font(systemTextFont(13, .regular, relativeTo: .caption1))
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpenComments)
    }

    private static func timeText(_ seconds: Int) -> String {
        String(format: "%02d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
    }
}

private struct MomentLikesSheet: View {
    let likes: [MomentLike]

    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var uniqueLikes: [MomentLike] {
        var seen = Set<String>()
        return likes.filter { like in
            let key = like.userId?.isEmpty == false ? like.userId! : (like.nickname ?? UUID().uuidString)
            return seen.insert(key).inserted
        }
    }

    private var filteredLikes: [MomentLike] {
        let key = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return uniqueLikes }
        return uniqueLikes.filter { ($0.nickname ?? "").localizedCaseInsensitiveContains(key) }
    }

    private var friends: [MomentLike] {
        filteredLikes.filter { app.contact(for: $0.userId ?? "") != nil }
    }

    private var others: [MomentLike] {
        filteredLikes.filter { app.contact(for: $0.userId ?? "") == nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.dyn(0xC9C9CE, 0x48484D))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            HStack(spacing: 10) {
                Text(Lang.isEnglish
                     ? "\(uniqueLikes.count) likes"
                     : "\(uniqueLikes.count) 人觉得不错")
                    .font(systemTextFont(18, .semibold, relativeTo: .headline))
                    .foregroundColor(C.label)
                Spacer(minLength: 0)
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(C.subLabel)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.dyn(0xF0F0F3, 0x1C1C1E)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Tr("关闭"))
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 10)

            if uniqueLikes.count > 24 {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundColor(C.subLabel)
                    TextField(Lang.isEnglish ? "Search people" : "搜索点赞的人", text: $query)
                        .font(systemTextFont(14.5, .regular, relativeTo: .body))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(C.subLabel)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 11)
                .frame(height: 38)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.dyn(0xF1F1F4, 0x1C1C1E)))
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !friends.isEmpty {
                        sectionHeader(Lang.isEnglish ? "Friends" : "好友", count: friends.count)
                        ForEach(Array(friends.enumerated()), id: \.offset) { index, like in
                            likeRow(like, relationship: Lang.isEnglish ? "Friend" : "好友")
                            if index < friends.count - 1 {
                                HairLine(inset: 67)
                            }
                        }
                    }

                    if !others.isEmpty {
                        sectionHeader(Lang.isEnglish ? "Star friends" : "星友", count: others.count)
                        ForEach(Array(others.enumerated()), id: \.offset) { index, like in
                            likeRow(like, relationship: Lang.isEnglish ? "Star friend" : "星友")
                            if index < others.count - 1 {
                                HairLine(inset: 67)
                            }
                        }
                    }

                    if filteredLikes.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "person.crop.circle.badge.questionmark")
                                .font(.system(size: 28, weight: .light))
                                .foregroundColor(C.subLabel)
                            Text(Lang.isEnglish ? "No matching people" : "没有找到这个人")
                                .font(systemTextFont(14, .regular, relativeTo: .body))
                                .foregroundColor(C.subLabel)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 54)
                    }

                    Color.clear.frame(height: max(24, L.safeBottom + 12))
                }
            }
        }
        .background(C.pageBg.ignoresSafeArea())
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
            Text("\(count)")
                .foregroundColor(C.subLabel)
            Spacer(minLength: 0)
        }
        .font(systemTextFont(13, .semibold, relativeTo: .caption1))
        .foregroundColor(C.label)
        .padding(.horizontal, 18)
        .padding(.top, 15)
        .padding(.bottom, 6)
    }

    private func likeRow(_ like: MomentLike, relationship: String) -> some View {
        let contact = like.userId.flatMap { app.contact(for: $0) }
        let name = contact?.name ?? like.nickname ?? Tr("星友")
        let avatar = contact?.avatarPath ?? ""

        return HStack(spacing: 12) {
            if avatar.isEmpty {
                Text(String(name.prefix(1)))
                    .font(systemTextFont(16, .semibold, relativeTo: .body))
                    .foregroundColor(C.subLabel)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.dyn(0xECECF0, 0x242426)))
            } else {
                Avatar(path: avatar, size: 44, radius: 22, circle: true)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(systemTextFont(15.5, .medium, relativeTo: .body))
                    .foregroundColor(C.label)
                    .lineLimit(1)
                Text(relationship)
                    .font(systemTextFont(12, .regular, relativeTo: .caption1))
                    .foregroundColor(C.subLabel)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 18)
        .frame(height: 60)
    }
}

private struct MomentFeedImageGrid: View {
    let images: [String]
    let sizes: [String: [Int]]
    let width: CGFloat
    let onTap: (Int) -> Void

    private let gap: CGFloat = 4

    var body: some View {
        if images.count == 1 {
            singleImage
        } else {
            grid
        }
    }

    private var singleImage: some View {
        let path = images[0]
        let size = sizes[path]
        let ratio = (size?.count ?? 0) >= 2 && (size?[1] ?? 0) > 0
            ? CGFloat(size![0]) / CGFloat(size![1])
            : 4.0 / 3.0
        let height = min(430, max(width * 0.62, width / max(0.55, ratio)))

        return Button {
            onTap(0)
        } label: {
            RemoteImage(path: path, icon: "photo", maxSide: 1440)
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var grid: some View {
        let columns = (images.count == 2 || images.count == 4) ? 2 : 3
        let cell = (width - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let rows = stride(from: 0, to: images.count, by: columns).map { start in
            Array(start..<min(start + columns, images.count))
        }

        return VStack(spacing: gap) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(spacing: gap) {
                    ForEach(rows[rowIndex], id: \.self) { index in
                        Button {
                            onTap(index)
                        } label: {
                            RemoteImage(path: images[index], icon: "photo", maxSide: 960)
                                .frame(width: cell, height: cell)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if rows[rowIndex].count < columns {
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }
}
