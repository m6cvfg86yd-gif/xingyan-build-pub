import Foundation
import UIKit
import SwiftUI

enum LocalStore {
    static let root: URL = {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Local", isDirectory: true)
        for sub in ["Media/video", "Media/image", "Media/voice", "Media/file", "Chats"] {
            try? FileManager.default.createDirectory(at: dir.appendingPathComponent(sub),
                                                     withIntermediateDirectories: true)
        }
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: dir.path
        )
        return dir
    }()

    static func kindOf(_ path: String) -> String {
        let p = path.lowercased()
        if p.hasSuffix(".mp4") || p.hasSuffix(".mov") || p.hasSuffix(".m4v") || p.hasSuffix(".webm") { return "video" }
        if p.hasSuffix(".m4a") || p.hasSuffix(".mp3") || p.hasSuffix(".wav") || p.hasSuffix(".aac") { return "voice" }
        if p.hasSuffix(".png") || p.hasSuffix(".jpg") || p.hasSuffix(".jpeg") || p.hasSuffix(".gif")
            || p.hasSuffix(".webp") || p.hasSuffix(".heic") { return "image" }
        return "file"
    }

    static func localURL(_ path: String) -> URL? {
        guard !path.isEmpty else { return nil }
        let name = (path as NSString).lastPathComponent
        guard !name.isEmpty else { return nil }
        return root.appendingPathComponent("Media").appendingPathComponent(kindOf(path)).appendingPathComponent(name)
    }

    static func has(_ path: String) -> Bool {
        guard let u = localURL(path) else { return false }
        return FileManager.default.fileExists(atPath: u.path)
    }

    static func read(_ path: String) -> Data? {
        guard let u = localURL(path) else { return nil }
        return try? Data(contentsOf: u)
    }

    static func keep(_ path: String, data: Data) {
        guard !data.isEmpty, let u = localURL(path) else { return }
        if FileManager.default.fileExists(atPath: u.path) { return }
        try? data.write(to: u, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func keepOriginal(_ path: String, from: URL, name: String? = nil) {
        guard let u = localURL(name.map { "/uploads/" + $0 } ?? path) else { return }
        if FileManager.default.fileExists(atPath: u.path) { return }
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if (try? FileManager.default.copyItem(at: from, to: u)) != nil {
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: u.path
            )
        }
    }

    static func chatFile(_ chatId: String) -> URL {
        root.appendingPathComponent("Chats").appendingPathComponent(sanitize(chatId) + ".json")
    }

    static func saveChat(_ chatId: String, _ messages: [Message]) {
        guard !messages.isEmpty else { return }
        let tail = messages.count > 20000 ? Array(messages.suffix(20000)) : messages
        guard !tail.isEmpty else { return }
        guard let d = try? JSONEncoder().encode(tail) else { return }
        try? d.write(to: chatFile(chatId),
                     options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func cachedChat(_ chatId: String) -> [Message] {
        guard let d = try? Data(contentsOf: chatFile(chatId)) else { return [] }
        return (try? JSONDecoder().decode([Message].self, from: d)) ?? []
    }

    private static func chatListFile(_ userId: String) -> URL? {
        guard !userId.isEmpty,
              let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return dir.appendingPathComponent("chat-list-" + sanitize(userId) + ".json")
    }

    static func saveChatList(_ chats: [Chat], userId: String) {
        guard !chats.isEmpty, let file = chatListFile(userId),
              let data = try? JSONEncoder().encode(Array(chats.prefix(300))) else { return }
        try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func cachedChatList(userId: String) -> [Chat] {
        guard let file = chatListFile(userId),
              let data = try? Data(contentsOf: file) else { return [] }
        return (try? JSONDecoder().decode([Chat].self, from: data)) ?? []
    }

    static func clearChat(_ chatId: String) {
        try? FileManager.default.removeItem(at: chatFile(chatId))
    }

    private static func momentCacheFile(_ userId: String) -> URL? {
        guard !userId.isEmpty,
              let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return dir.appendingPathComponent("moments-cache-" + sanitize(userId) + ".json")
    }

    static func saveMoments(_ list: [Moment], userId: String) {
        guard !list.isEmpty, let f = momentCacheFile(userId) else { return }
        let tail = Array(list.prefix(60))
        guard let d = try? JSONEncoder().encode(tail) else { return }
        try? d.write(to: f, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func cachedMoments(userId: String) -> [Moment] {
        guard let f = momentCacheFile(userId), let d = try? Data(contentsOf: f) else { return [] }
        return (try? JSONDecoder().decode([Moment].self, from: d)) ?? []
    }

    static func usage() -> [(String, Int)] {
        var out: [(String, Int)] = []
        for k in ["video", "image", "voice", "file"] {
            out.append((k, dirSize(root.appendingPathComponent("Media").appendingPathComponent(k))))
        }
        out.append(("chat", dirSize(root.appendingPathComponent("Chats"))))
        return out
    }

    static func totalUsage() -> Int { usage().reduce(0) { $0 + $1.1 } }

    static func clear(_ kind: String) {
        let dir = kind == "chat" ? root.appendingPathComponent("Chats")
                                 : root.appendingPathComponent("Media").appendingPathComponent(kind)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: dir.path
        )
    }

    static func purgeUserArtifacts(userId: String) {
        clear("chat")
        ["video", "image", "voice", "file"].forEach { clear($0) }
        if let file = chatListFile(userId) { try? FileManager.default.removeItem(at: file) }
        if let file = momentCacheFile(userId) { try? FileManager.default.removeItem(at: file) }
    }

    private static func dirSize(_ dir: URL) -> Int {
        guard let en = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var n = 0
        for case let f as URL in en {
            n += (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return n
    }

    private static func sanitize(_ s: String) -> String {
        String(s.map { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" ? $0 : "_" })
    }

    static func text(_ bytes: Int) -> String {
        if bytes >= 1024 * 1024 * 1024 { return String(format: "%.2f GB", Double(bytes) / 1073741824) }
        if bytes >= 1024 * 1024 { return String(format: "%.1f MB", Double(bytes) / 1048576) }
        if bytes >= 1024 { return "\(bytes / 1024) KB" }
        return "\(bytes) B"
    }
}

struct StorageSpaceView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [(String, Int)] = []
    @State private var showClearAll = false
    @State private var showClearCache = false
    @State private var showClearChat = false
    @State private var showManageChats = false

    private let chatColor = Color(hex: 0x4A90D9)
    private let cacheColor = C.green
    private var cacheBytes: Int {
        rows.filter { ["image", "video", "voice", "file"].contains($0.0) }
            .reduce(0) { $0 + $1.1 }
    }

    @State private var info: API.StorageInfo?
    private var chatBytes: Int { info?.total ?? 0 }

    private var usageBar: some View {
        let total = max(1, chatBytes + cacheBytes)
        return GeometryReader { geo in
            HStack(spacing: 2) {
                if chatBytes > 0 {
                    RoundedRectangle(cornerRadius: 3, style: .continuous).fill(chatColor)
                        .frame(width: max(4, geo.size.width * CGFloat(chatBytes) / CGFloat(total)))
                }
                if cacheBytes > 0 {
                    RoundedRectangle(cornerRadius: 3, style: .continuous).fill(cacheColor)
                        .frame(width: max(4, geo.size.width * CGFloat(cacheBytes) / CGFloat(total)))
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 12)
        .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color.dyn(0xEDEDF0, 0x2C2C31)))
    }

    private func legendDot(_ title: String, _ bytes: Int, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(pf(12.5)).foregroundColor(C.subLabel)
            Text(LocalStore.text(bytes)).font(pf(12.5)).foregroundColor(C.subLabel)
        }
    }

    private func label(_ k: String) -> String {
        switch k {
        case "video": return Tr("视频")
        case "image": return Tr("图片")
        case "voice": return Tr("语音")
        case "file": return Tr("文件")
        case "chat": return Tr("聊天记录")
        default: return k
        }
    }

    private func icon(_ k: String) -> String {
        switch k {
        case "video": return "film"
        case "image": return "photo"
        case "voice": return "waveform"
        case "file": return "doc"
        case "chat": return "bubble.left.and.bubble.right"
        default: return "folder"
        }
    }

    var body: some View {

        VStack(spacing: 0) {
            NavBar(title: Tr("存储空间"), back: { dismiss() })
            VStack(spacing: 0) {
                List {
                    Section {
                        VStack(spacing: 8) {
                            Text(LocalStore.text(chatBytes + cacheBytes))
                                .font(pf(30, .semibold))
                                .foregroundColor(C.label)
                            Text(Tr("已用空间（聊天记录 + 缓存）"))
                                .font(pf(12.5))
                                .foregroundColor(C.subLabel)
                                .multilineTextAlignment(.center)

                            usageBar
                                .padding(.top, 6)
                            HStack(spacing: 18) {
                                legendDot(Tr("聊天记录"), chatBytes, chatColor)
                                legendDot(Tr("缓存"), cacheBytes, cacheColor)
                                Spacer(minLength: 0)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .listRowBackground(C.cardBg)
                    }

                    Section {
                        HStack(spacing: 12) {
                            Text(Tr("缓存")).font(pf(16)).foregroundColor(C.label)
                            Spacer(minLength: 8)
                            Text(LocalStore.text(cacheBytes)).font(pf(14)).foregroundColor(C.subLabel)
                            Button { showClearCache = true } label: {
                                Text(Tr("前往清理")).font(pf(14)).foregroundColor(C.green)
                            }
                            .buttonStyle(.plain)
                            .disabled(cacheBytes == 0)
                        }
                        .listRowBackground(C.cardBg)
                        HStack(spacing: 12) {
                            Text(Tr("聊天记录")).font(pf(16)).foregroundColor(C.label)
                            Spacer(minLength: 8)
                            Text(LocalStore.text(chatBytes)).font(pf(14)).foregroundColor(C.subLabel)

                            NavigationLink(value: "storage.manage") {
                                Text(Tr("管理")).font(pf(14)).foregroundColor(C.green)
                            }
                            .buttonStyle(.plain)
                            .disabled(chatBytes == 0)
                        }
                        .listRowBackground(C.cardBg)
                    }

                    Section {
                        ForEach(rows.indices, id: \.self) { i in
                            HStack(spacing: 12) {
                                Image(systemName: icon(rows[i].0))
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundColor(C.green)
                                    .frame(width: 26)
                                Text(label(rows[i].0)).font(pf(16)).foregroundColor(C.label)
                                Spacer(minLength: 8)
                                Text(LocalStore.text(rows[i].1))
                                    .font(pf(14)).foregroundColor(C.subLabel)
                                Button {
                                    LocalStore.clear(rows[i].0)
                                    rows = LocalStore.usage()
                                } label: {
                                    Text(Tr("清理"))
                                        .font(pf(14))
                                        .foregroundColor(rows[i].1 > 0 ? C.red : C.time)
                                }
                                .buttonStyle(.plain)
                                .disabled(rows[i].1 == 0)
                            }
                            .listRowBackground(C.cardBg)
                        }
                    } header: {
                        Text(Tr("按类型"))
                    } footer: {
                        Text(Tr("清理只删本机留的这一份，服务器上的聊天记录和别人收到的内容不受影响；以后再看会重新下回来。"))
                    }

                    Section {
                        Button(role: .destructive) { showClearAll = true } label: {
                            Text(Tr("全部清理（本机媒体 + 聊天底稿）"))
                        }
                        .listRowBackground(C.cardBg)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(C.pageBg)
            }
            .background(C.pageBg.ignoresSafeArea())
            .confirmationDialog(Tr("确定清理本机留的媒体和聊天底稿？"), isPresented: $showClearAll, titleVisibility: .visible) {
                Button(Tr("全部清理"), role: .destructive) {
                    for k in ["video", "image", "voice", "file", "chat"] { LocalStore.clear(k) }
                    rows = LocalStore.usage()
                }
                Button(Tr("取消"), role: .cancel) { }
            }

            .confirmationDialog(Tr("确定清理缓存？"), isPresented: $showClearCache, titleVisibility: .visible) {
                Button(Tr("前往清理"), role: .destructive) {
                    for k in ["image", "video", "voice", "file"] { LocalStore.clear(k) }
                    rows = LocalStore.usage()
                }
                Button(Tr("取消"), role: .cancel) { }
            }

            .confirmationDialog(Tr("确定清空本机的聊天记录底稿？"), isPresented: $showClearChat, titleVisibility: .visible) {
                Button(Tr("清空"), role: .destructive) {
                    LocalStore.clear("chat")
                    rows = LocalStore.usage()
                }
                Button(Tr("取消"), role: .cancel) { }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .onAppear {
            rows = LocalStore.usage()
            Task { info = try? await API.shared.storage() }
        }
    }
}

struct ChatStorageManageView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var chats: [API.StorageChat] = []
    @State private var loading = true
    @State private var selected: Set<String> = []
    @State private var bySize = true
    @State private var confirm = false
    @State private var busy = false

    private var list: [API.StorageChat] {
        bySize ? chats.sorted { $0.bytes > $1.bytes } : chats
    }
    private var allSelected: Bool { !list.isEmpty && selected.count == list.count }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("聊天记录管理"), back: { dismiss() }) {
                Button { withAnimation(.easeOut(duration: 0.15)) { bySize.toggle() } } label: {
                    Text(bySize ? Tr("按大小") : Tr("按时间"))
                        .font(pf(14.5)).foregroundColor(C.green).padding(.trailing, 16)
                }
                .buttonStyle(.plain)
            }
            if loading {
                ProgressView().padding(.top, 60)
                Spacer(minLength: 0)
            } else if list.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 40)).foregroundColor(C.subLabel)
                    Text(Tr("还没有可以清理的聊天记录"))
                        .font(pf(14)).foregroundColor(C.subLabel)
                }
                .padding(.top, 70)
                Spacer(minLength: 0)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(list) { c in
                            row(c)
                            HairLine(inset: 62)
                        }
                        Text(Tr("删除只是清掉你这边这个会话的历史记录，对方那边不受影响。"))
                            .font(pf(12.5)).foregroundColor(C.subLabel)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24).padding(.top, 14)
                        Color.clear.frame(height: 20)
                    }
                    .background(C.cardBg)
                }
                .background(C.pageBg)
                bottomBar
            }
        }
        .background(C.pageBg.ignoresSafeArea(edges: .bottom))
        .background(C.pageBg.ignoresSafeArea(edges: .top))
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .task { await load() }
        .confirmationDialog(Tr("删除选中的 \(selected.count) 个会话记录？"),
                            isPresented: $confirm, titleVisibility: .visible) {
            Button(Tr("删除"), role: .destructive) { Task { await removeSelected() } }
            Button(Tr("取消"), role: .cancel) { }
        }
    }

    private func row(_ c: API.StorageChat) -> some View {
        Button {
            if selected.contains(c.id) { selected.remove(c.id) } else { selected.insert(c.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected.contains(c.id) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundColor(selected.contains(c.id) ? C.green : C.subLabel)
                Avatar(path: c.avatar ?? "", size: 42, radius: 6)
                VStack(alignment: .leading, spacing: 3) {
                    Text(c.title).font(pf(16)).foregroundColor(C.label).lineLimit(1)
                    Text("\(c.messages) " + Tr("条消息"))
                        .font(pf(12.5)).foregroundColor(C.subLabel)
                }
                Spacer(minLength: 8)
                Text(LocalStore.text(c.bytes)).font(pf(14)).foregroundColor(C.subLabel)
            }
            .padding(.horizontal, 16)
            .frame(height: 66)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button {
                if allSelected { selected.removeAll() } else { selected = Set(list.map { $0.id }) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: allSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 19))
                        .foregroundColor(allSelected ? C.green : C.subLabel)
                    Text(Tr("全选")).font(pf(15)).foregroundColor(C.label)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            Button { confirm = true } label: {
                Text(busy ? Tr("删除中…") : (selected.isEmpty ? Tr("删除") : Tr("删除") + "（\(selected.count)）"))
                    .font(pf(15, .medium))
                    .foregroundColor(selected.isEmpty ? C.subLabel : .white)
                    .padding(.horizontal, 22)
                    .frame(height: 38)
                    .background(Capsule().fill(selected.isEmpty ? Color.dyn(0xEDEDF0, 0x2C2C31) : C.red))
            }
            .buttonStyle(.plain)
            .disabled(selected.isEmpty || busy)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(C.tabBg)
        .overlay(alignment: .top) { HairLine() }
    }

    private func load() async {
        if let d = try? await API.shared.storage() { chats = d.chats }
        loading = false
    }

    private func removeSelected() async {
        busy = true
        for id in selected {
            _ = await API.shared.clearChat(chatId: id)
        }
        selected.removeAll()
        await load()
        await app.loadChats()
        busy = false
        app.show(Tr("已删除"))
    }
}
