import SwiftUI

struct StorageView: View {
    @ObservedObject private var lang = LangStore.shared
    @EnvironmentObject var app: AppState

    @State private var info: API.StorageInfo?
    @State private var cacheBytes = 0
    @State private var loading = true
    @State private var clearing = false
    @State private var confirmChat: API.StorageChat?
    @State private var deviceFreeBytes: Int64 = 0

    private func mb(_ b: Int) -> String {
        let v = Double(b) / 1024 / 1024
        if v < 0.1 { return String(format: "%.0f KB", v * 1024) }
        if v < 1024 { return String(format: "%.1f MB", v) }
        return String(format: "%.2f GB", v / 1024)
    }

    private func deviceBytes(_ b: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
    }

    private var appBytes: Int {
        (info?.total ?? 0) + cacheBytes
    }

    private var sortedChats: [API.StorageChat] {
        (info?.chats ?? []).sorted {
            if $0.bytes == $1.bytes { return $0.title < $1.title }
            return $0.bytes > $1.bytes
        }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(loading ? "…" : mb(appBytes))
                                .font(pfStyled(size: 34, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)
                            Text(Tr("星言在本机使用的空间"))
                                .font(pfStyled(size: 15))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Tr("本 App"))
                            .font(pfStyled(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 9)
                            .frame(height: 24)
                            .background(
                                Capsule().fill(Color(uiColor: .tertiarySystemFill))
                            )
                    }

                    storageBar

                    HStack(spacing: 6) {
                        Image(systemName: "iphone")
                        Text(deviceFreeBytes > 0
                             ? Tr("iPhone 可用") + " " + deviceBytes(deviceFreeBytes)
                             : Tr("设备容量读取中"))
                        Spacer()
                        Text(Tr("本地"))
                            .foregroundStyle(.secondary)
                    }
                    .font(pfStyled(size: 12))
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
                .listRowInsets(EdgeInsets(top: 12, leading: 18, bottom: 14, trailing: 18))
            }

            Section {
                ForEach(mediaSegs, id: \.title) { seg in
                    HStack(spacing: 12) {
                        storageIcon(seg.symbol, color: seg.color)
                        Text(seg.title)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        Text(mb(seg.bytes))
                            .font(pfStyled(size: 15))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            } header: {
                Text(Tr("占用明细"))
            } footer: {
                Text(Tr("按聊天中的图片、视频、文件和语音分类统计；只统计这台设备上的数据。"))
            }

            Section {
                Button {
                    clearCache()
                } label: {
                    HStack(spacing: 12) {
                        storageIcon("internaldrive.fill",
                                    color: Color(hex: 0x64748B))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(Tr("缓存"))
                                .foregroundStyle(.primary)
                            Text(Tr("图片和网络临时文件，可安全清理"))
                                .font(pfStyled(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        if clearing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text(mb(cacheBytes))
                                .font(pfStyled(size: 15))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(clearing || cacheBytes == 0)
            } header: {
                Text(Tr("管理"))
            } footer: {
                Text(Tr("清理缓存不会删除聊天记录，也不会影响服务器上的数据。"))
            }

            Section {
                if loading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(Tr("正在计算聊天占用…"))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if sortedChats.isEmpty {
                    Label(Tr("没有聊天记录占用"), systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedChats) { chat in
                        Button {
                            confirmChat = chat
                        } label: {
                            HStack(spacing: 12) {
                                Avatar(path: chat.avatar ?? "", size: 40, radius: 12)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(chat.title)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text("\(chat.messages) " + Tr("条消息"))
                                        .font(pfStyled(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Text(mb(chat.bytes))
                                    .font(pfStyled(size: 15))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                HStack {
                    Text(Tr("聊天记录占用"))
                    Spacer()
                    if !loading {
                        Text("\(sortedChats.count) " + Tr("个会话"))
                            .textCase(nil)
                    }
                }
            } footer: {
                Text(Tr("点按一个会话可以只清空这台手机上的聊天记录。"))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Tr("存储空间"))
        .navigationBarTitleDisplayMode(.large)
        .hidesTabBar()
        .task { await load() }
        .confirmationDialog(Tr("清空这个会话的聊天记录？"),
                            isPresented: Binding(get: { confirmChat != nil },
                                                 set: { if !$0 { confirmChat = nil } }),
                            titleVisibility: .visible) {
            Button(Tr("清空"), role: .destructive) {
                if let c = confirmChat { clearChat(c) }
                confirmChat = nil
            }
            Button(Tr("取消"), role: .cancel) { confirmChat = nil }
        }
    }

    private func storageIcon(_ symbol: String, color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color)
            )
    }

    struct Seg {
        var title: String
        var bytes: Int
        var color: Color
        var symbol: String
    }

    private var mediaSegs: [Seg] {
        let kinds = info?.kinds
        let image = kinds?.image ?? 0
        let video = kinds?.video ?? 0
        let file = kinds?.file ?? 0
        let audio = kinds?.audio ?? 0
        let total = info?.total ?? 0
        let other = max(0, total - (image + video + file + audio))
        return [
            Seg(title: Tr("图片"), bytes: image, color: Color(hex: 0x3478F6), symbol: "photo.fill"),
            Seg(title: Tr("视频"), bytes: video, color: Color(hex: 0xA855F7), symbol: "play.rectangle.fill"),
            Seg(title: Tr("文件"), bytes: file, color: Color(hex: 0xF59E0B), symbol: "doc.fill"),
            Seg(title: Tr("语音"), bytes: audio, color: Color(hex: 0x22C55E), symbol: "waveform"),
            Seg(title: Tr("其他记录"), bytes: other, color: Color(hex: 0x8E8E93), symbol: "ellipsis.message.fill")
        ].filter { $0.bytes > 0 }
    }

    private var segs: [Seg] {
        mediaSegs + [
            Seg(title: Tr("手机缓存"),
                bytes: cacheBytes,
                color: Color(hex: 0x64748B),
                symbol: "internaldrive.fill")
        ].filter { $0.bytes > 0 }
    }

    private var storageBar: some View {
        let list = segs
        let total = max(1, list.reduce(0) { $0 + $1.bytes })
        return GeometryReader { geo in
            HStack(spacing: 2) {
                if list.isEmpty {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill))
                } else {
                    ForEach(list.indices, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(list[i].color)
                            .frame(width: max(4, geo.size.width * CGFloat(list[i].bytes) / CGFloat(total)))
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 14)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill))
        )
        .animation(.easeInOut(duration: 0.22), value: list.map(\.bytes))
    }

    private func load() async {
        loading = true
        if let data = try? await API.shared.storage() { info = data }
        cacheBytes = Int(URLCache.shared.currentDiskUsage) + ImageStore.shared.diskUsage
        if let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let free = attributes[.systemFreeSize] as? NSNumber {
            deviceFreeBytes = free.int64Value
        }
        loading = false
    }

    private func clearCache() {
        clearing = true
        URLCache.shared.removeAllCachedResponses()
        ImageStore.shared.clear()
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            cacheBytes = Int(URLCache.shared.currentDiskUsage) + ImageStore.shared.diskUsage
            clearing = false
            app.show(Tr("缓存已清理"))
        }
    }

    private func clearChat(_ chat: API.StorageChat) {
        Task {
            if let error = await API.shared.clearChat(chatId: chat.chatId) {
                app.show(error)
            } else {
                app.forgetChatHistory(chat.chatId)
                app.show(Tr("这个会话的记录已清空"))
            }
            await load()
            await app.loadChats()
        }
    }
}
