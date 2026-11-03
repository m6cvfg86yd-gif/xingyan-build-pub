import SwiftUI
import AVKit
import Photos
import UIKit

struct MomentCommentsSheet: View {
    let initial: Moment
    let onChanged: () -> Void

    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var live: Moment
    @State private var text = ""
    @State private var replyToId = ""
    @State private var replyToName = ""
    @State private var sending = false
    @State private var deleting: MomentComment?
    @State private var previewIndex = 0
    @State private var fullViewerIndex: Int?
    @State private var videoURL: URL?
    @State private var imageActions = false
    @State private var actionPath = ""
    @State private var fullImageActions = false
    @State private var fullActionPath = ""
    @FocusState private var commentFocused: Bool
    @State private var openSwipeKey: String?
    @State private var swipeOffsets: [String: CGFloat] = [:]

    init(moment: Moment, onChanged: @escaping () -> Void) {
        self.initial = moment
        self.onChanged = onChanged
        _live = State(initialValue: moment)
    }

    private var images: [String] { live.images ?? [] }
    private var comments: [MomentComment] { live.comments ?? [] }
    private var likes: [MomentLike] { live.likes ?? [] }
    private var previewHeight: CGFloat {
        min(420, max(280, (L.width - 32) * 0.96))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                frostedBackground

                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                momentContextCard

                                commentsHeader
                                    .padding(.horizontal, 4)

                                if comments.isEmpty {
                                    VStack(spacing: 8) {
                                        Image(systemName: "bubble.left")
                                            .font(.title2)
                                            .foregroundStyle(.secondary)
                                        Text(Tr("还没有评论"))
                                            .font(.headline)
                                        Text(Tr("说点什么，成为第一个评论的人"))
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 42)
                                    .background(frostedCard)
                                    .id("moment-comment-empty")
                                } else {
                                    ForEach(Array(comments.enumerated()), id: \.offset) { index, item in
                                        commentRow(item, index: index)
                                            .id(commentKey(item, index))
                                    }
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.top, 10)
                            .padding(.bottom, 18)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .contentShape(Rectangle())
                        .simultaneousGesture(TapGesture().onEnded {
                            commentFocused = false
                        })
                        .onChange(of: comments.count) { _ in
                            if let last = comments.last {
                                withAnimation(.easeOut(duration: 0.22)) {
                                    proxy.scrollTo(commentKey(last, comments.count - 1), anchor: .bottom)
                                }
                            }
                        }
                    }

                    composer
                }
            }
            .navigationTitle(Tr("全部评论"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(Tr("关闭"))
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .confirmationDialog(Tr("删除这条评论？"),
                            isPresented: Binding(get: { deleting != nil },
                                                 set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button(Tr("删除"), role: .destructive) {
                if let item = deleting, let id = item.id {
                    deleteComment(id)
                }
                deleting = nil
            }
            Button(Tr("取消"), role: .cancel) { deleting = nil }
        }
        .sheet(isPresented: $imageActions) {
            if !actionPath.isEmpty {
                MomentImageActions(path: actionPath)
                    .environmentObject(app)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
        }
        .fullScreenCover(isPresented: Binding(get: { videoURL != nil },
                                              set: { if !$0 { videoURL = nil } })) {
            if let url = videoURL {
                VideoPlayerSheet(url: url)
                    .environmentObject(app)
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { fullViewerIndex != nil },
            set: { if !$0 { fullViewerIndex = nil } }
        )) {
            if let start = fullViewerIndex {
                PhotoPager(
                    paths: images,
                    startIndex: start,
                    showActions: false,
                    onLongPress: {
                        if images.indices.contains(start) {
                            fullActionPath = images[start]
                        } else {
                            fullActionPath = images.first ?? ""
                        }
                        fullImageActions = true
                    }
                ) {
                    fullViewerIndex = nil
                }
                .environmentObject(app)
                .sheet(isPresented: $fullImageActions) {
                    if !fullActionPath.isEmpty {
                        MomentImageActions(path: fullActionPath)
                            .environmentObject(app)
                            .presentationDetents([.medium])
                            .presentationDragIndicator(.visible)
                    }
                }
            }
        }
        .onDisappear { onChanged() }
    }

    private var frostedBackground: some View {
        Color(uiColor: .systemGroupedBackground)
            .ignoresSafeArea()
    }

    private var frostedCard: some View {
        RoundedRectangle(cornerRadius: 17, style: .continuous)
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(Color.primary.opacity(0.055), lineWidth: 0.6)
            }
            .shadow(color: .black.opacity(0.035), radius: 8, y: 3)
    }

    private var momentContextCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            momentPreview
            authorLine

            if let content = live.content?.trimmingCharacters(in: .whitespacesAndNewlines),
               !content.isEmpty {
                Text(RichText.linkified(content))
                    .font(systemTextFont(15.2, .regular, relativeTo: .body))
                    .foregroundColor(C.label)
                    .lineSpacing(5.5)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 9)
            }

            if !likes.isEmpty {
                likeLine
                    .padding(.top, 4)
            }
        }
        .padding(12)
        .background(frostedCard)
    }

    @ViewBuilder
    private var momentPreview: some View {
        if !images.isEmpty {
            TabView(selection: Binding(
                get: { previewIndex },
                set: { previewIndex = $0 }
            )) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, path in
                    ZStack(alignment: .topLeading) {
                        RemoteImage(path: path, icon: "photo", maxSide: 1280)
                        if images.count > 1 {
                            Text("\(index + 1)/\(images.count)")
                                .font(pf(10, .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.black.opacity(0.42)))
                                .padding(9)
                        }
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: previewHeight)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                    if images.indices.contains(previewIndex) {
                        actionPath = images[previewIndex]
                    } else {
                        actionPath = images.first ?? ""
                    }
                    imageActions = true
                }
            )
            .onTapGesture {
                fullViewerIndex = previewIndex
            }
            .padding(.top, 12)
        } else if let raw = live.video, !raw.isEmpty {
            ZStack {
                if let cover = live.videoCover, !cover.isEmpty {
                    RemoteImage(path: cover, icon: "photo", maxSide: 1280)
                } else {
                    C.searchBg
                }
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 50, height: 50)
                        .overlay(Circle().fill(Color.black.opacity(0.15)))
                    Image(systemName: "play.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundColor(.white)
                        .offset(x: 1.5)
                }
                if (live.videoSeconds ?? 0) > 0 {
                    VStack {
                        HStack {
                            Text(Self.timeText(live.videoSeconds ?? 0))
                                .font(pf(10, .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.black.opacity(0.42)))
                            Spacer(minLength: 0)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(9)
                    .allowsHitTesting(false)
                }
            }
            .frame(height: previewHeight)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.top, 12)
            .onTapGesture {
                let full = raw.hasPrefix("http") ? raw : API.shared.base + raw
                videoURL = URL(string: full)
            }
        }
    }

    private var authorLine: some View {
        HStack(spacing: 8) {
            Avatar(path: live.author?.avatarPath ?? "", size: 32, radius: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(live.author?.name ?? "")
                    .font(pf(12.5, .medium))
                    .foregroundColor(C.label)
                    .lineLimit(1)
                Text((live.location?.isEmpty == false ? ((live.location ?? "") + "  ·  ") : "")
                     + TimeFmt.ago(live.createdAt))
                    .font(pf(10.5))
                    .foregroundColor(C.subLabel)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: toggleLike) {
                HStack(spacing: 4) {
                    Image(systemName: live.likedByMe == true ? "heart.fill" : "heart")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(live.likedByMe == true ? Color(hex: 0xFA5151) : C.subLabel)
                    if likes.count > 0 {
                        Text("\(likes.count)")
                            .font(pf(11.5))
                            .foregroundColor(C.subLabel)
                    }
                }
                .frame(height: 32)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 10)
    }

    private var likeLine: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "heart.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(hex: 0xFA5151))
                .padding(.top, 2)
            Text(likes.compactMap { $0.nickname }.joined(separator: "，"))
                .font(pf(13))
                .foregroundColor(C.link)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.top, 2)
        .overlay(alignment: .bottom) { HairLine(inset: 0) }
    }

    private var commentsHeader: some View {
        HStack(spacing: 5) {
            Text(Tr("评论"))
                .font(.headline)
                .foregroundColor(C.label)
            Text("\(comments.count)")
                .font(.caption)
                .foregroundColor(C.subLabel)
            Spacer(minLength: 0)
            Text(Tr("最新"))
                .font(.caption)
                .foregroundColor(C.subLabel)
        }
        .padding(.top, 11)
        .padding(.bottom, 3)
    }

    private func commentRow(_ item: MomentComment, index: Int) -> some View {
        let key = commentKey(item, index)
        let canDelete = item.userId == app.me?.id
        let offset = swipeOffsets[key] ?? 0
        return ZStack(alignment: .trailing) {
            if canDelete {
                Button {
                    openSwipeKey = nil
                    swipeOffsets[key] = 0
                    deleting = item
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .medium))
                        Text(Tr("删除"))
                            .font(pf(11.5, .medium))
                    }
                    .foregroundColor(.white)
                    .frame(width: 74)
                    .frame(maxHeight: .infinity)
                    .background(Color(hex: 0xFA5151))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .top, spacing: 9) {
                commentAvatar(item)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Text(item.nickname ?? "")
                            .font(pf(12.5, .medium))
                            .foregroundColor(C.label.opacity(0.74))
                            .lineLimit(1)
                        if let target = item.replyToName, !target.isEmpty {
                            Text(Tr("回复") + " @" + target)
                                .font(pf(11.5))
                                .foregroundColor(C.green)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Text(TimeFmt.ago(item.at))
                            .font(pf(10.5))
                            .foregroundColor(C.subLabel)
                    }
                    Text(item.content ?? "")
                        .font(systemTextFont(14.5, .regular, relativeTo: .subheadline))
                        .foregroundColor(C.label)
                        .lineSpacing(4)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(frostedCard)
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .contentShape(Rectangle())
            .offset(x: offset)
            .animation(.easeOut(duration: 0.16), value: offset)
            .onTapGesture {
                if offset < -1 {
                    openSwipeKey = nil
                    swipeOffsets[key] = 0
                    return
                }
                if let openSwipeKey, openSwipeKey != key {
                    swipeOffsets[openSwipeKey] = 0
                    self.openSwipeKey = nil
                }
                guard item.userId != app.me?.id else { return }
                replyToId = item.userId ?? ""
                replyToName = item.nickname ?? ""
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                    if canDelete { deleting = item }
                }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        guard canDelete,
                              abs(value.translation.width) > abs(value.translation.height) else { return }
                        if openSwipeKey != nil, openSwipeKey != key {
                            swipeOffsets[openSwipeKey!] = 0
                        }
                        let base: CGFloat = openSwipeKey == key ? -78 : 0
                        swipeOffsets[key] = max(-78, min(0, base + value.translation.width))
                    }
                    .onEnded { value in
                        guard canDelete else { return }
                        let shouldOpen = value.translation.width < -32
                            || value.predictedEndTranslation.width < -70
                        withAnimation(.easeOut(duration: 0.16)) {
                            swipeOffsets[key] = shouldOpen ? -78 : 0
                            openSwipeKey = shouldOpen ? key : nil
                        }
                    }
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
    }

    private var composer: some View {
        VStack(spacing: 0) {
            if !replyToName.isEmpty {
                HStack(spacing: 6) {
                    Text(Tr("回复") + " @" + replyToName)
                        .font(pf(11.5))
                        .foregroundColor(C.subLabel)
                    Spacer(minLength: 0)
                    Button {
                        replyToId = ""
                        replyToName = ""
                    } label: {
                        Text(Tr("取消回复"))
                            .font(pf(11.5))
                            .foregroundColor(C.green)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 7)
            }
            HStack(spacing: 8) {
                TextField(Tr("说点什么…"), text: $text)
                    .font(pf(14.5))
                    .foregroundColor(C.label)
                    .focused($commentFocused)
                    .padding(.horizontal, 14)
                    .frame(height: 42)
                    .background(Capsule().fill(Color.dyn(0xF4F4F2, 0x292929)))
                    .submitLabel(.send)
                    .onSubmit { send() }
                Button(action: send) {
                    Text(Tr("发送"))
                        .font(pf(13.5, .medium))
                        .foregroundColor(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                         ? C.subLabel : .white)
                        .frame(width: 60, height: 38)
                        .background(Capsule().fill(
                            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Color.dyn(0xEAEAE7, 0x2E2E2E) : C.green
                        ))
                }
                .buttonStyle(.plain)
                .disabled(sending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.top, 9)
            .padding(.bottom, max(10, L.safeBottom))
        }
        .background(.bar)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(uiColor: .separator))
                .frame(height: 0.5)
        }
    }

    private func send() {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !sending else { return }
        let targetId = replyToId
        let targetName = replyToName
        sending = true
        Task {
            if let error = await API.shared.commentMoment(id: live.id, text: value, replyTo: targetId) {
                app.show(error)
            } else {
                let item = MomentComment(id: UUID().uuidString,
                                         userId: app.me?.id,
                                         nickname: app.me?.name ?? Tr("我"),
                                         replyToName: targetName.isEmpty ? nil : targetName,
                                         content: value,
                                         at: ISO8601DateFormatter().string(from: Date()))
                var next = comments
                next.append(item)
                live.comments = next
                text = ""
                replyToId = ""
                replyToName = ""
                onChanged()
            }
            sending = false
        }
    }

    private func deleteComment(_ id: String) {
        Task {
            if let error = await API.shared.deleteMomentComment(momentId: live.id, commentId: id) {
                app.show(error)
            } else {
                live.comments = comments.filter { $0.id != id }
                swipeOffsets.removeAll()
                openSwipeKey = nil
                onChanged()
            }
        }
    }

    private func toggleLike() {
        let liked = live.likedByMe == true
        var nextLikes = likes
        if liked {
            nextLikes.removeAll { $0.userId == app.me?.id }
        } else {
            nextLikes.append(MomentLike(userId: app.me?.id,
                                        nickname: app.me?.name ?? Tr("我"),
                                        at: ISO8601DateFormatter().string(from: Date())))
        }
        live.likes = nextLikes
        live.likedByMe = !liked
        Task {
            if let error = await API.shared.likeMoment(id: live.id) {
                app.show(error)
            }
            onChanged()
        }
    }

    private func avatar(for userId: String) -> String {
        if userId == app.me?.id { return app.me?.avatarPath ?? "" }
        return app.contact(for: userId)?.avatarPath ?? ""
    }

    @ViewBuilder
    private func commentAvatar(_ item: MomentComment) -> some View {
        let path = avatar(for: item.userId ?? "")
        if path.isEmpty {
            Text(String((item.nickname ?? Tr("友")).prefix(1)))
                .font(pf(12, .medium))
                .foregroundColor(Color.dyn(0x676C68, 0xD6DAD7))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.dyn(0xF0F1EE, 0x2B2B2B)))
        } else {
            Avatar(path: path, size: 30, radius: 15)
        }
    }

    private func commentKey(_ item: MomentComment, _ index: Int) -> String {
        (item.id ?? "comment") + "-" + String(index)
    }

    private static func timeText(_ seconds: Int) -> String {
        String(format: "%02d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
    }
}

struct MomentImageActions: View {
    let path: String

    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var share = false

    var body: some View {
        VStack(spacing: 12) {
            Capsule()
                .fill(Color.secondary.opacity(0.25))
                .frame(width: 38, height: 4)
                .padding(.top, 4)
            HStack(spacing: 12) {
                action(Tr("保存"), "square.and.arrow.down") { save() }
                action(Tr("分享"), "square.and.arrow.up") { share = true }
                action(Tr("关闭"), "xmark") { dismiss() }
            }
            .padding(.horizontal, 16)
            Spacer(minLength: 0)
        }
        .background(C.cardBg)
        .task {
            guard let url = API.shared.assetURL(path),
                  let data = try? await API.shared.imageData(url) else { return }
            image = UIImage(data: data)
        }
        .sheet(isPresented: $share) {
            if let image {
                ShareSheet(items: [image])
            }
        }
    }

    private func action(_ title: String, _ symbol: String,
                        run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 21, weight: .medium))
                Text(title).font(pf(12.5, .medium))
            }
            .foregroundColor(C.label)
            .frame(maxWidth: .infinity)
            .frame(height: 82)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.dyn(0xF3F3F1, 0x292929)))
        }
        .buttonStyle(.plain)
    }

    private func save() {
        guard let image else {
            app.show(Tr("图片还没加载完"))
            return
        }
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                app.show(Tr("需要相册权限才能保存"))
                return
            }
            try? await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            app.show(Tr("图片已保存"))
            dismiss()
        }
    }
}
