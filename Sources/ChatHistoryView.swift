import SwiftUI

struct ChatHistoryView: View {
    @ObservedObject private var lang = LangStore.shared
    @EnvironmentObject var app: AppState

    @State private var info: API.StorageInfo?
    @State private var loading = true
    @State private var busy = false
    @State private var confirmAll = false
    @State private var confirmChat: API.StorageChat?
    @State private var doneTip = ""

    @State private var shareFile: ShareFile?
    @State private var showImport = false
    @State private var exportBusy = false
    @State private var importBusy = false
    @State private var importTip = ""

    private func mb(_ bytes: Int) -> String {
        let value = Double(bytes) / 1024 / 1024
        if value < 0.1 { return String(format: "%.0f KB", value * 1024) }
        if value < 1024 { return String(format: "%.1f MB", value) }
        return String(format: "%.2f GB", value / 1024)
    }

    private func title(_ chat: API.StorageChat) -> String {
        chat.title.isEmpty ? Tr("聊天") : chat.title
    }

    private var cleanupChats: [API.StorageChat] {
        (info?.chats ?? []).filter { $0.bytes > 1024 }.sorted {
            if $0.bytes == $1.bytes { return $0.title < $1.title }
            return $0.bytes > $1.bytes
        }
    }

    private var totalMessages: Int {
        (info?.chats ?? []).reduce(0) { $0 + $1.messages }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(loading ? "…" : mb(info?.total ?? 0))
                            .font(pfStyled(size: 34, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(Tr("聊天记录"))
                            .font(pfStyled(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 9)
                            .frame(height: 24)
                            .background(
                                Capsule().fill(Color(uiColor: .tertiarySystemFill))
                            )
                    }
                    Text(Tr("你这边的聊天记录总共占用"))
                        .font(pfStyled(size: 15))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 14) {
                        Label("\(info?.chats.count ?? 0) " + Tr("个会话"),
                              systemImage: "bubble.left.and.bubble.right")
                        Label("\(totalMessages) " + Tr("条消息"),
                              systemImage: "text.bubble")
                    }
                    .font(pfStyled(size: 12))
                    .foregroundStyle(.secondary)
                    if !doneTip.isEmpty {
                        Label(doneTip, systemImage: "checkmark.circle.fill")
                            .font(pfStyled(size: 12))
                            .foregroundStyle(.green)
                    }
                }
                .padding(.vertical, 5)
            }

            Section {
                backupRow(
                    title: Tr("导出聊天记录"),
                    detail: exportBusy ? Tr("正在导出…")
                        : Tr("JSON 备份，换手机后可再导入"),
                    symbol: "square.and.arrow.up",
                    color: Color(hex: 0x3478F6)
                ) {
                    exportChats(json: true)
                }

                backupRow(
                    title: Tr("导出为文本"),
                    detail: Tr("TXT 文件，可直接阅读"),
                    symbol: "doc.text",
                    color: Color(hex: 0x64748B)
                ) {
                    exportChats(json: false)
                }

                backupRow(
                    title: Tr("从文件导入"),
                    detail: importBusy ? Tr("正在导入…")
                        : (importTip.isEmpty ? Tr("选择导出的 JSON 备份") : importTip),
                    symbol: "square.and.arrow.down",
                    color: Color(hex: 0x22C55E)
                ) {
                    showImport = true
                }
            } header: {
                Text(Tr("备份与迁移"))
            } footer: {
                Text(Tr("导出的 JSON 备份可在新手机上重新导入；重复导入不会产生重复消息。"))
            }

            Section {
                if loading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(Tr("正在读取聊天记录…"))
                            .foregroundStyle(.secondary)
                    }
                } else if cleanupChats.isEmpty {
                    Label(Tr("没有可清理的会话"), systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(cleanupChats) { chat in
                        chatRow(chat)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    confirmChat = chat
                                } label: {
                                    Label(Tr("清空"), systemImage: "trash")
                                }
                                .disabled(busy)
                            }
                    }
                }
            } header: {
                HStack {
                    Text(Tr("按会话清理"))
                    Spacer()
                    if !loading {
                        Text("\(cleanupChats.count) " + Tr("个会话"))
                            .textCase(nil)
                    }
                }
            } footer: {
                Text(Tr("左滑会话可以清空记录；只清空你这台手机上的内容，对方仍会保留。"))
            }

            Section {
                Button(role: .destructive) {
                    confirmAll = true
                } label: {
                    HStack {
                        Label(Tr("清空全部聊天记录"), systemImage: "trash")
                        Spacer()
                        if busy {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(busy || cleanupChats.isEmpty)
            } footer: {
                Text(Tr("清空后这台手机上的聊天记录不能恢复，建议先导出备份。"))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Tr("聊天记录管理"))
        .navigationBarTitleDisplayMode(.large)
        .hidesTabBar()
        .task { await load() }
        .sheet(item: $shareFile) { file in
            ShareSheet(items: [file.url])
        }
        .fileImporter(isPresented: $showImport,
                      allowedContentTypes: [.json, .item],
                      allowsMultipleSelection: false) { result in
            handleImport(result)
        }
        .confirmationDialog(Tr("清空这个会话的聊天记录？"),
                            isPresented: Binding(
                                get: { confirmChat != nil },
                                set: { if !$0 { confirmChat = nil } }
                            ),
                            titleVisibility: .visible) {
            Button(Tr("清空"), role: .destructive) {
                if let chat = confirmChat { clear(chat.id) }
                confirmChat = nil
            }
            Button(Tr("取消"), role: .cancel) { confirmChat = nil }
        }
        .confirmationDialog(Tr("清空全部聊天记录？"),
                            isPresented: $confirmAll,
                            titleVisibility: .visible) {
            Button(Tr("清空"), role: .destructive) { clearAll() }
            Button(Tr("取消"), role: .cancel) { }
        } message: {
            Text(Tr("只清你自己这边，对方那边的记录不受影响。清掉以后不能恢复。"))
        }
    }

    private func chatRow(_ chat: API.StorageChat) -> some View {
        HStack(spacing: 12) {
            Avatar(path: chat.avatar ?? "", size: 40, radius: 12)
            VStack(alignment: .leading, spacing: 3) {
                Text(title(chat))
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

    private func backupRow(title: String,
                           detail: String,
                           symbol: String,
                           color: Color,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(color)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(detail)
                        .font(pfStyled(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 6)
                if exportBusy || importBusy {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(exportBusy || importBusy)
    }

    private func load() async {
        info = try? await API.shared.storage()
        loading = false
    }

    private func exportChats(json: Bool) {
        guard !exportBusy else { return }
        exportBusy = true
        doneTip = ""
        Task {
            do {
                let dump = try await API.shared.exportChats(format: json ? "json" : "txt")
                let text: String
                if json {
                    let object = dump.payload ?? [:]
                    let data = try JSONSerialization.data(withJSONObject: object,
                                                          options: [.prettyPrinted, .sortedKeys])
                    text = String(data: data, encoding: .utf8) ?? "{}"
                } else {
                    text = dump.text
                }
                if let url = writeTempFile(name: dump.fileName, text: text) {
                    shareFile = ShareFile(url: url)
                    doneTip = Tr("已导出 ") + "\(dump.chats)" + Tr(" 个会话 / ")
                        + "\(dump.total)" + Tr(" 条消息")
                } else {
                    app.show(Tr("写文件失败"))
                }
            } catch {
                app.show((error as? APIError)?.errorDescription ?? Tr("导出失败"))
            }
            exportBusy = false
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            importTip = Tr("读不到这个文件")
            app.show(importTip)
            return
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            importTip = Tr("这不是聊天记录备份文件")
            app.show(importTip)
            return
        }
        importBusy = true
        Task {
            do {
                let result = try await API.shared.importChats(payload: object)
                importTip = Tr("导入完成：新增 ") + "\(result.imported)"
                    + Tr(" 条，跳过（已存在）") + "\(result.skipped)" + Tr(" 条")
                doneTip = importTip
                await load()
                await app.loadChats()
            } catch {
                let message = (error as? APIError)?.errorDescription ?? Tr("导入失败")
                importTip = message
                app.show(message)
            }
            importBusy = false
        }
    }

    private func clear(_ chatId: String) {
        busy = true
        Task {
            if let error = await API.shared.clearChat(chatId: chatId) {
                app.show(error)
            } else {
                app.forgetChatHistory(chatId, notify: false)
                doneTip = Tr("已清空一个会话")
            }
            await load()
            await app.loadChats()
            busy = false
        }
    }

    private func clearAll() {
        busy = true
        Task {
            let ids = (info?.chats ?? []).map(\.id)
            var failed = 0
            for id in ids {
                if await API.shared.clearChat(chatId: id) == nil {
                    app.forgetChatHistory(id, notify: false)
                } else {
                    failed += 1
                }
                await Task.yield()
            }
            doneTip = failed == 0
                ? Tr("已清空全部聊天记录（已清 ") + "\(ids.count)" + Tr(" 个会话）")
                : Tr("部分会话清空失败，请稍后重试")
            await load()
            await app.loadChats()
            busy = false
        }
    }
}
