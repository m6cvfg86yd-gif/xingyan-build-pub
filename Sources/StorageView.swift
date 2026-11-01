import SwiftUI

struct StorageView: View {
    @ObservedObject private var lang = LangStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var info: API.StorageInfo?
    @State private var cacheBytes = 0
    @State private var loading = true
    @State private var clearing = false
    @State private var confirmChat: API.StorageChat?

    private func mb(_ b: Int) -> String {
        let v = Double(b) / 1024 / 1024
        if v < 0.1 { return String(format: "%.0f KB", v * 1024) }
        if v < 1024 { return String(format: "%.1f MB", v) }
        return String(format: "%.2f GB", v / 1024)
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Text(loading ? "…" : mb((info?.total ?? 0) + cacheBytes))
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(Tr("已用空间（聊天记录 + 缓存）"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    storageBar
                    legend
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }

            Section {
                Button {
                    clearCache()
                } label: {
                    HStack {
                        Label(Tr("缓存"), systemImage: "internaldrive")
                        Spacer()
                        Text(clearing ? Tr("清理中…") : mb(cacheBytes))
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(clearing || cacheBytes == 0)
            } header: {
                Text(Tr("存储管理"))
            } footer: {
                Text(Tr("清理缓存只删手机上的图片缓存，不会删除聊天记录，也不影响服务器上的任何东西。"))
            }

            Section {
                let chats = info?.chats ?? []
                ForEach(chats.indices, id: \.self) { i in
                    let chat = chats[i]
                    Button {
                        confirmChat = chat
                    } label: {
                        HStack(spacing: 12) {
                            Avatar(path: chat.avatar ?? "", size: 42, radius: 12)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(chat.title)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text("\(chat.messages) " + Tr("条消息"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(mb(chat.bytes))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text(Tr("聊天记录占用"))
            } footer: {
                Text(Tr("点一个会话可以清空它的本机记录。"))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Tr("存储空间"))
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

    private func row(_ title: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(title).font(pf(16)).foregroundColor(C.label)
            Spacer(minLength: 8)
            Text(value).font(pf(15)).foregroundColor(C.subLabel)
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
    }

    private func storageIcon(_ symbol: String, color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(color)
            .frame(width: 38, height: 38)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    struct Seg {
        var title: String
        var bytes: Int
        var color: Color
    }

    private var segs: [Seg] {
        let k = info?.kinds
        let img = k?.image ?? 0, vid = k?.video ?? 0, fil = k?.file ?? 0, aud = k?.audio ?? 0
        let total = info?.total ?? 0
        let other = max(0, total - (img + vid + fil + aud))
        return [
            Seg(title: Tr("图片"), bytes: img, color: Color(hex: 0x4A90D9)),
            Seg(title: Tr("视频"), bytes: vid, color: Color(hex: 0x8E6BE8)),
            Seg(title: Tr("文件"), bytes: fil, color: Color(hex: 0xE8A33D)),
            Seg(title: Tr("语音"), bytes: aud, color: Color(hex: 0x3ED37F)),
            Seg(title: Tr("其他记录"), bytes: other, color: Color(hex: 0x9AA4B2)),
            Seg(title: Tr("手机缓存"), bytes: cacheBytes, color: Color(hex: 0xC9CDD4))
        ].filter { $0.bytes > 0 }
    }

    private var storageBar: some View {
        let list = segs
        let total = max(1, list.reduce(0) { $0 + $1.bytes })
        return GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(list.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(list[i].color)
                        .frame(width: max(4, geo.size.width * CGFloat(list[i].bytes) / CGFloat(total)))
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 12)
        .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color.dyn(0xEDEDF0, 0x2C2C31)))
    }

    private var legend: some View {
        let list = segs
        return LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                                  GridItem(.flexible(), alignment: .leading)],
                         spacing: 10) {
            ForEach(list.indices, id: \.self) { i in
                HStack(spacing: 6) {
                    Circle().fill(list[i].color).frame(width: 8, height: 8)
                    Text(list[i].title).font(pf(13)).foregroundColor(C.label).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(mb(list[i].bytes)).font(pf(13)).foregroundColor(C.subLabel)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private func load() async {
        loading = true
        if let d = try? await API.shared.storage() { info = d }
        cacheBytes = Int(URLCache.shared.currentDiskUsage) + ImageStore.shared.diskUsage
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

    private func clearChat(_ c: API.StorageChat) {
        Task {
            if let err = await API.shared.clearChat(chatId: c.chatId) {
                app.show(err)
            } else {
                app.forgetChatHistory(c.chatId)
                app.show(Tr("这个会话的记录已清空"))
            }
            await load()
            await app.loadChats()
        }
    }
}
