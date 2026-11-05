import SwiftUI
import UIKit
import Foundation
import UniformTypeIdentifiers

struct ExternalFileItem: Identifiable {
    let id = UUID()
    let name: String
    let local: URL
    let bytes: Int
}

final class ExternalFileInbox: ObservableObject {
    static let shared = ExternalFileInbox()

    @Published var files: [ExternalFileItem] = []
    @Published var present = false
    @Published var importing = false
    private var lastAcceptKey = ""
    private var lastAcceptAt = Date.distantPast

    private init() {}

    func accept(_ urls: [URL]) {
        let valid = urls.filter { $0.isFileURL }
        guard !valid.isEmpty else { return }

        let key = valid.map(\.path).joined(separator: "|")
        if key == lastAcceptKey && Date().timeIntervalSince(lastAcceptAt) < 1.5 { return }
        lastAcceptKey = key
        lastAcceptAt = Date()
        DispatchQueue.main.async { self.importing = true }

        DispatchQueue.global(qos: .userInitiated).async {
            var copied: [ExternalFileItem] = []
            let fm = FileManager.default
            let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ExternalInbox", isDirectory: true)
            try? fm.createDirectory(at: base, withIntermediateDirectories: true)

            for source in valid {
                let scoped = source.startAccessingSecurityScopedResource()
                defer { if scoped { source.stopAccessingSecurityScopedResource() } }

                let name = Self.sourceName(source)
                var destination = base.appendingPathComponent(name)
                if fm.fileExists(atPath: destination.path) {
                    let stem = destination.deletingPathExtension().lastPathComponent
                    let ext = destination.pathExtension
                    destination = base.appendingPathComponent(
                        stem + "-" + String(Int(Date().timeIntervalSince1970)) + (ext.isEmpty ? "" : "." + ext))
                }
                do {
                    try fm.copyItem(at: source, to: destination)
                    let attrs = try? fm.attributesOfItem(atPath: destination.path)
                    let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
                    copied.append(ExternalFileItem(name: destination.lastPathComponent,
                                                   local: destination,
                                                   bytes: size))
                } catch {

                    if let data = try? Data(contentsOf: source), !data.isEmpty {
                        do {
                            try data.write(to: destination, options: .atomic)
                            copied.append(ExternalFileItem(name: destination.lastPathComponent,
                                                           local: destination,
                                                           bytes: data.count))
                        } catch {
                        }
                    }
                }
            }

            DispatchQueue.main.async {
                self.importing = false
                if copied.isEmpty { return }
                self.files.append(contentsOf: copied)
                self.present = true
            }
        }
    }

    func finish() {
        let old = files
        files = []
        present = false
        for item in old { try? FileManager.default.removeItem(at: item.local) }
    }

    private static func safeName(_ raw: String) -> String {
        let decoded = raw.removingPercentEncoding ?? raw
        let bad = CharacterSet(charactersIn: "/\\:")
        var name = decoded.components(separatedBy: bad).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = "文件" }
        if name.count > 180 { name = String(name.prefix(180)) }
        return name
    }

    private static func sourceName(_ source: URL) -> String {
        let values = try? source.resourceValues(forKeys: [.nameKey, .typeIdentifierKey, .contentTypeKey])
        var name = values?.name ?? source.lastPathComponent
        if name.isEmpty { name = "文件" }
        if !name.contains("."), let type = values?.typeIdentifier,
           let ext = UTType(type)?.preferredFilenameExtension, !ext.isEmpty {
            name += "." + ext
        } else if !name.contains("."), let type = values?.contentType,
                  let ext = type.preferredFilenameExtension, !ext.isEmpty {
            name += "." + ext
        } else if !name.contains("."), !source.pathExtension.isEmpty {
            name += "." + source.pathExtension
        }
        return safeName(name)
    }
}

struct ExternalFileSendView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var inbox: ExternalFileInbox
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var selectedId = ""
    @State private var forwardExpanded = true
    @State private var favoriteBusy = false
    @State private var sending = false
    @State private var progress = ""
    @State private var transferFraction: Double = 0
    @State private var alert = ""
    @State private var forwardScrollTick = 0
    @State private var filePreview: FilePreviewData?
    @State private var showShare = false
    @State private var showDrop = false

    private var chats: [Chat] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rows = app.chats.filter {
            ($0.oaId ?? "").isEmpty && $0.oaDigest != true
        }
        guard !q.isEmpty else { return rows }
        return rows.filter { $0.name.lowercased().contains(q) }
    }

    private var contacts: [User] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rows = app.contacts.filter {
            $0.id != app.me?.id && $0.block != true && $0.bot != true
        }
        guard !q.isEmpty else { return rows }
        return rows.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                StarRouteBackdrop()

                VStack(spacing: 0) {
                    NavBar(title: Tr("外部文件")) {
                        Button {
                            if !sending && !favoriteBusy { inbox.finish() }
                        } label: {
                            Text(Tr("取消"))
                                .font(pfStyled(size: 13.5, weight: .semibold))
                                .foregroundStyle(sending || favoriteBusy
                                                 ? OrbitTheme.tertiary
                                                 : OrbitTheme.secondary)
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                        }
                        .buttonStyle(.plain)
                        .disabled(sending || favoriteBusy)
                    }

                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            LazyVStack(alignment: .leading, spacing: 14) {
                                fileHero
                                fileStrip
                                actionRail

                                if forwardExpanded {
                                    recipientSection
                                        .id("forward-targets")
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.top, 4)
                            .padding(.bottom, 18)
                        }
                        .onChange(of: forwardScrollTick) { _ in
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                                proxy.scrollTo("forward-targets", anchor: .top)
                            }
                        }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                sendDock
            }
            .task { if app.chats.isEmpty { await app.loadChats() } }
            .alert(alert, isPresented: Binding(get: { !alert.isEmpty },
                                               set: { if !$0 { alert = "" } })) {
                Button(Tr("知道了"), role: .cancel) {}
            }
            .sheet(item: $filePreview) { f in
                FilePreviewSheet(name: f.name, local: f.local)
            }
            .sheet(isPresented: $showShare) {
                ShareSheet(items: inbox.files.map(\.local))
            }
            .fullScreenCover(isPresented: $showDrop) {
                FaceToFaceFileSheet(rows: [], avatar: app.me?.avatarPath ?? "",
                                    name: app.me?.name ?? "我", ink: C.label,
                                    mode: .host, initialFiles: inbox.files.map(\.local))
                    .environmentObject(app)
            }
        }
    }

    private var fileHero: some View {
        StarForwardHero(
            symbol: "tray.and.arrow.down.fill",
            kicker: "STAR INBOX",
            title: Tr("文件已经到达"),
            subtitle: Tr("先检查内容，再沿星轨发给朋友"),
            badge: "\(inbox.files.count) " + Tr("个文件") + " · " + fileBytes
        )
    }

    private var fileStrip: some View {
        VStack(alignment: .leading, spacing: 9) {
            OrbitSectionLabel(text: Tr("传入文件"), count: inbox.files.count)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(inbox.files) { item in
                        Button {
                            filePreview = FilePreviewData(name: item.name, local: item.local)
                        } label: {
                            fileTile(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
                .padding(.vertical, 2)
            }
        }
    }

    private func fileTile(_ item: ExternalFileItem) -> some View {
        let look = FileKind.look(item.name)
        return HStack(spacing: 10) {
            VStack(spacing: 1) {
                Image(systemName: look.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(look.color)
                Text(look.badge)
                    .font(pfExact(7.5, .bold))
                    .foregroundStyle(look.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 44, height: 44)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(look.color.opacity(0.13)))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(look.color.opacity(0.20), lineWidth: 0.7))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(pfStyled(size: 12.5, weight: .semibold))
                    .foregroundStyle(OrbitTheme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(fileSize(item.bytes))
                    .font(pfStyled(size: 10.5))
                    .foregroundStyle(OrbitTheme.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(OrbitTheme.tertiary)
        }
        .padding(.horizontal, 11)
        .frame(width: 218, height: 66)
        .background(OrbitTheme.raised)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(OrbitTheme.divider, lineWidth: 0.7)
        }
        .shadow(color: Color.black.opacity(0.035), radius: 8, y: 3)
    }

    private var actionRail: some View {
        HStack(spacing: 8) {
            fileAction(Tr("打开"), "doc.text.magnifyingglass", OrbitTheme.jade) {
                previewFirstFile()
            }
            fileAction(Tr("转发"), "paperplane.fill", Color.dyn(0x315E78, 0x78AFC8)) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    forwardExpanded = true
                }
                forwardScrollTick += 1
            }
            fileAction(Tr("收藏"), "star.fill", OrbitTheme.gold) {
                favorite()
            }
            fileAction(Tr("分享"), "square.and.arrow.up", Color.dyn(0x5E6579, 0xAAB4D0)) {
                showShare = true
            }
            fileAction(Tr("快传"), "dot.radiowaves.left.and.right", Color.dyn(0x477C68, 0x77C8A8)) {
                showDrop = true
            }
        }
        .disabled(favoriteBusy || sending)
    }

    private func fileAction(_ title: String, _ symbol: String, _ tint: Color,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(tint.opacity(0.13)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(tint.opacity(0.18), lineWidth: 0.7))
                Text(title)
                    .font(pfStyled(size: 10.5, weight: .medium))
                    .foregroundStyle(OrbitTheme.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 65)
            .background(OrbitTheme.raised)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(OrbitTheme.divider, lineWidth: 0.7)
            }
        }
        .buttonStyle(.plain)
    }

    private var recipientSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            OrbitSectionLabel(text: Tr("转发给朋友"))
            StarForwardSearch(placeholder: Tr("搜索会话或联系人"), text: $query)

            if !chats.isEmpty {
                OrbitSectionLabel(text: Tr("最近会话"), count: chats.count)
                ForEach(Array(chats.prefix(30))) { chat in
                    Button {
                        select("c:" + chat.id)
                    } label: {
                        StarForwardTargetRow(
                            name: chat.name,
                            subtitle: chatSubtitle(chat),
                            avatar: chat.avatar ?? "",
                            isGroup: chat.type == "group",
                            selected: isSelected(chat.id),
                            countBadge: chatBadge(chat)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if !contacts.isEmpty {
                OrbitSectionLabel(text: Tr("联系人"), count: contacts.count)
                    .padding(.top, chats.isEmpty ? 0 : 4)
                ForEach(Array(contacts.prefix(80))) { user in
                    Button {
                        select("u:" + user.id)
                    } label: {
                        StarForwardTargetRow(
                            name: user.name,
                            subtitle: contactSubtitle(user),
                            avatar: user.avatarPath,
                            isGroup: false,
                            selected: isSelected(user.id),
                            countBadge: user.online == true ? Tr("在线") : nil
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if chats.isEmpty && contacts.isEmpty {
                StarForwardEmpty(text: Tr("没有匹配的会话或联系人"))
            }
        }
    }

    private var sendDock: some View {
        VStack(spacing: 9) {
            if sending || favoriteBusy {
                VStack(spacing: 5) {
                    HStack(spacing: 7) {
                        ProgressView()
                            .tint(OrbitTheme.jade)
                            .scaleEffect(0.72)
                        Text(progress)
                            .font(pfStyled(size: 11.5, weight: .medium))
                            .foregroundStyle(OrbitTheme.secondary)
                        Spacer(minLength: 0)
                        Text("\(Int(min(1, max(0, transferFraction)) * 100))%")
                            .font(pfStyled(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(OrbitTheme.jade)
                    }
                    ProgressView(value: min(1, max(0, transferFraction)))
                        .tint(OrbitTheme.jade)
                }
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(selectedId.isEmpty ? Tr("选择接收人") : selectedName)
                        .font(pfStyled(size: 14, weight: .semibold))
                        .foregroundStyle(OrbitTheme.ink)
                        .lineLimit(1)
                    Text(selectedId.isEmpty ? Tr("文件会保留原格式发送") : fileBytes)
                        .font(pfStyled(size: 10.5))
                        .foregroundStyle(OrbitTheme.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Button {
                    send()
                } label: {
                    HStack(spacing: 7) {
                        if sending {
                            ProgressView().tint(.white).scaleEffect(0.72)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 12.5, weight: .semibold))
                        }
                        Text(sending ? Tr("发送中…") : Tr("发送"))
                            .font(pfStyled(size: 14.5, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 19)
                    .frame(height: 42)
                    .background(Capsule().fill(
                        LinearGradient(
                            colors: selectedId.isEmpty || sending || favoriteBusy
                                ? [OrbitTheme.tertiary.opacity(0.56), OrbitTheme.tertiary.opacity(0.40)]
                                : [OrbitTheme.jade, OrbitTheme.jadeDeep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    ))
                }
                .buttonStyle(.plain)
                .disabled(selectedId.isEmpty || sending || favoriteBusy)
            }
        }
        .padding(.horizontal, 13)
        .padding(.top, 9)
        .padding(.bottom, max(8, L.safeBottom * 0.32))
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(OrbitTheme.divider.opacity(0.72))
                .frame(height: 0.5)
        }
        .animation(.easeOut(duration: 0.18), value: sending)
        .animation(.linear(duration: 0.16), value: transferFraction)
    }

    private var selectedName: String {
        if selectedId.hasPrefix("c:"),
           let chat = app.chats.first(where: { $0.id == String(selectedId.dropFirst(2)) }) {
            return chat.name
        }
        if selectedId.hasPrefix("u:"),
           let user = app.contacts.first(where: { $0.id == String(selectedId.dropFirst(2)) }) {
            return user.name
        }
        return Tr("选择一个朋友")
    }

    private func select(_ value: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.24, dampingFraction: 0.84)) {
            selectedId = value
        }
    }

    private func chatSubtitle(_ chat: Chat) -> String {
        let preview = (chat.lastMessage?.preview ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !preview.isEmpty { return preview }
        return chat.type == "group" ? Tr("群聊会话") : Tr("最近联系")
    }

    private func chatBadge(_ chat: Chat) -> String? {
        if chat.type == "group", let count = chat.memberCount, count > 0 {
            return "\(count)" + Tr("人")
        }
        return nil
    }

    private func contactSubtitle(_ user: User) -> String {
        let username = (user.username ?? "").trimmingCharacters(in: .whitespaces)
        if !username.isEmpty { return "@" + username }
        let mood = (user.moodText ?? "").trimmingCharacters(in: .whitespaces)
        return mood.isEmpty ? Tr("星言好友") : mood
    }

    private func fileSize(_ bytes: Int) -> String {
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024.0) }
        return String(format: "%.1f MB", Double(bytes) / 1024.0 / 1024.0)
    }

    private var fileBytes: String {
        let total = inbox.files.reduce(0) { $0 + $1.bytes }
        if total <= 0 { return Tr("准备发送") }
        if total < 1024 * 1024 { return String(format: "%.1f KB", Double(total) / 1024.0) }
        return String(format: "%.1f MB", Double(total) / 1024.0 / 1024.0)
    }

    private func previewFirstFile() {
        guard let first = inbox.files.first else { return }
        filePreview = FilePreviewData(name: first.name, local: first.local)
    }

    private func isSelected(_ id: String) -> Bool {
        selectedId == "c:" + id || selectedId == "u:" + id
    }

    private func send() {
        guard !selectedId.isEmpty, !inbox.files.isEmpty else { return }
        sending = true
        transferFraction = 0.01
        Task {
            let chat: Chat?
            if selectedId.hasPrefix("u:") {
                chat = try? await API.shared.directChat(userId: String(selectedId.dropFirst(2)))
            } else {
                let id = selectedId.hasPrefix("c:") ? String(selectedId.dropFirst(2)) : selectedId
                chat = app.chats.first { $0.id == id }
            }
            guard let chat else {
                sending = false
                alert = Tr("这个朋友暂时无法创建会话")
                return
            }
            var done = 0
            let count = max(1, inbox.files.count)
            for (index, item) in inbox.files.enumerated() {
                progress = Tr("正在上传") + " \(done + 1)/\(inbox.files.count)"
                let bytes = (try? item.local.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if bytes > 100 * 1024 * 1024 {
                    alert = Tr("单个文件不能超过 100MB")
                    break
                }
                guard bytes > 0 else { continue }
                do {
                    let uploadedURL = try await uploadItem(item) { fraction in
                        DispatchQueue.main.async {
                            transferFraction = min(1, (Double(index) + fraction) / Double(count))
                        }
                    }
                    transferFraction = min(1, Double(index + 1) / Double(count))
                    let contentObject: [String: Any] = [
                        "url": uploadedURL,
                        "name": item.name,
                        "bytes": bytes,
                        "mime": UTType(filenameExtension: item.local.pathExtension)?.preferredMIMEType
                            ?? "application/octet-stream"
                    ]
                    let body = try JSONSerialization.data(withJSONObject: contentObject, options: [])
                    let content = String(data: body, encoding: .utf8) ?? "{\"url\":\"\(uploadedURL)\"}"
                    _ = try await API.shared.send(chatId: chat.id, kind: "file", content: content)
                    done += 1
                } catch {
                    alert = (error as? APIError)?.errorDescription ?? Tr("文件发送失败")
                    break
                }
            }
            sending = false
            transferFraction = 0
            if alert.isEmpty && done > 0 {
                await app.loadChats()
                inbox.finish()
                dismiss()
            }
        }
    }

    private func favorite() {
        guard !inbox.files.isEmpty else { return }
        favoriteBusy = true
        transferFraction = 0.01
        Task {
            var saved: [(name: String, content: String)] = []
            var done = 0
            let count = max(1, inbox.files.count)
            for (index, item) in inbox.files.enumerated() {
                progress = Tr("正在收藏") + " \(done + 1)/\(inbox.files.count)"
                let bytes = (try? item.local.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if bytes > 100 * 1024 * 1024 {
                    alert = Tr("单个文件不能超过 100MB")
                    break
                }
                guard bytes > 0 else { continue }
                do {
                    let uploadedURL = try await uploadItem(item) { fraction in
                        DispatchQueue.main.async {
                            transferFraction = min(1, (Double(index) + fraction) / Double(count))
                        }
                    }
                    transferFraction = min(1, Double(index + 1) / Double(count))
                    let body = try JSONSerialization.data(withJSONObject: [
                        "url": uploadedURL,
                        "name": item.name,
                        "bytes": bytes,
                        "mime": UTType(filenameExtension: item.local.pathExtension)?.preferredMIMEType
                            ?? "application/octet-stream"
                    ], options: [])
                    saved.append((name: item.name,
                                  content: String(data: body, encoding: .utf8) ?? "{\"url\":\"\(uploadedURL)\"}"))
                    done += 1
                } catch {
                    alert = (error as? APIError)?.errorDescription ?? Tr("收藏失败")
                    break
                }
            }
            if alert.isEmpty && done > 0 {
                var allOK = true
                for file in saved {
                    let ok = await API.shared.addFavorite(kind: "file",
                                                          content: file.content,
                                                          title: file.name,
                                                          from: "外部文件")
                    allOK = allOK && ok
                }
                if allOK {
                    app.show(Tr("已收藏"))
                    inbox.finish()
                    dismiss()
                } else {
                    alert = Tr("收藏失败")
                }
            }
            favoriteBusy = false
            transferFraction = 0
        }
    }

    private func uploadItem(_ item: ExternalFileItem,
                            onProgress: @escaping (Double) -> Void) async throws -> String {
        try await API.shared.uploadBinaryFile(
            item.local, mime: "application/octet-stream",
            skipTranscode: true, onProgress: onProgress)
    }
}
