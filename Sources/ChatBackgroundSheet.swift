import SwiftUI
import UIKit

func normalizedChatBackground(_ path: String) -> String {
    switch path.trimmingCharacters(in: .whitespacesAndNewlines) {
    case "/bg/bw1.jpg", "solid:white": return "solid:white"
    case "/bg/bw2.jpg", "solid:black": return "solid:black"
    default: return path
    }
}

func serverChatBackgroundRef(_ path: String) -> String {
    switch normalizedChatBackground(path) {
    case "solid:white": return "/bg/bw1.jpg"
    case "solid:black": return "/bg/bw2.jpg"
    default: return path
    }
}

func chatBackgroundSolidColor(_ path: String) -> Color? {
    switch normalizedChatBackground(path) {
    case "solid:white": return .white
    case "solid:black": return .black
    default: return nil
    }
}

final class ChatBgStore: ObservableObject {
    static let shared = ChatBgStore()

    @Published private(set) var version = 0

    private func key(_ chatId: String) -> String { "chris.chatBg." + chatId }

    func get(_ chatId: String) -> String {
        guard !chatId.isEmpty else { return "" }
        return UserDefaults.standard.string(forKey: key(chatId)) ?? ""
    }

    func set(_ chatId: String, _ value: String) {
        guard !chatId.isEmpty else { return }
        if value.isEmpty || value == "auto" {
            UserDefaults.standard.removeObject(forKey: key(chatId))
        } else {
            UserDefaults.standard.set(value, forKey: key(chatId))
        }
        version += 1
    }

    func clearAll() {
        let prefix = "chris.chatBg."
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            UserDefaults.standard.removeObject(forKey: key)
        }
        version += 1
    }
}

struct ChatBackgroundSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var chatId: String = ""

    @State private var picking = false
    @State private var busy = false

    static let presets: [String] = ["solid:white", "solid:black"]

    static let names: [String] = ["白色", "黑色"]

    private var shownPresets: [(path: String, name: String)] {
        Self.presets.enumerated().map { idx, path in
            (path, Self.names[min(idx, Self.names.count - 1)])
        }
    }

    private var inChat: Bool { !chatId.isEmpty }
    @ObservedObject private var store = ChatBgStore.shared

    private var current: String {
        if inChat {
            let synced = app.me?.chatBackgrounds?[chatId] ?? ""
            let v = synced.isEmpty ? store.get(chatId) : synced
            return v.isEmpty ? "auto" : v
        }
        let value = app.me?.chatBackground ?? "auto"
        return value.isEmpty ? "auto" : value
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    backgroundPreview
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section {
                    HStack(spacing: 14) {
                        ForEach(shownPresets, id: \.path) { item in
                            Button { pick(item.path) } label: {
                                VStack(spacing: 8) {
                                    ZStack {
                                        if let solid = chatBackgroundSolidColor(item.path) {
                                            solid
                                        } else {
                                            C.pageBg
                                        }
                                        if normalizedChatBackground(current) == item.path {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 16, weight: .bold))
                                                .foregroundColor(item.path == "solid:white" ? .black : .white)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 128)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(normalizedChatBackground(current) == item.path
                                                ? Color.accentColor : Color.secondary.opacity(0.18),
                                                lineWidth: normalizedChatBackground(current) == item.path ? 2.5 : 0.7))
                                    Text(Tr(item.name))
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .disabled(busy)
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text(Tr("纯色壁纸"))
                } footer: {
                    Text(Tr("不依赖网络，白底和黑底始终可用。"))
                }

                Section {
                    Button { pick("auto") } label: {
                        HStack {
                            Text(inChat ? Tr("使用全局背景") : Tr("系统默认背景"))
                            Spacer()
                            if current == "auto" {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    .disabled(busy)

                    Button { picking = true } label: {
                        HStack {
                            Text(Tr("从相册选择"))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                    .disabled(busy)
                }

                if busy {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(C.pageBg)
            .navigationTitle(Tr(inChat ? "选择背景图" : "聊天背景"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Tr("完成")) { dismiss() }
                }
            }
            .sheet(isPresented: $picking) {
                PhotoPicker { image in upload(image) }
            }
        }
        .tint(.accentColor)
    }

    private var backgroundPreview: some View {
        let path = current == "auto"
            ? normalizedChatBackground(app.defaultChatBackground)
            : normalizedChatBackground(current)
        return ZStack {
            if let solid = chatBackgroundSolidColor(path) {
                solid
            } else if !path.isEmpty {
                RemoteImage(path: path, mode: .fill)
            } else {
                C.pageBg
            }

            VStack(spacing: 10) {
                HStack {
                    Text(Tr("今天"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(.thinMaterial, in: Capsule())
                    Spacer()
                }
                HStack {
                    Text(Tr("默认背景预览"))
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Spacer(minLength: 60)
                }
                HStack {
                    Spacer(minLength: 78)
                    Text(Tr("黑白都保持清晰"))
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(16)
        }
        .frame(height: 235)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Color.secondary.opacity(0.15), lineWidth: 0.7))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func pick(_ path: String, cacheKey: String = "") {

        primeBackgroundCache(path: path, cacheKey: cacheKey)
        let storedPath = serverChatBackgroundRef(path)
        if inChat {
            let oldUser = app.me
            let oldLocal = ChatBgStore.shared.get(chatId)
            applyChatBackground(storedPath)
            Task {
                busy = true
                if let saved = await API.shared.changeChatBackground(chatId: chatId, path: storedPath) {
                    applySyncedChatBackgrounds(saved)
                    app.show(path == "auto" ? Tr("已改用全局背景") : Tr("这个聊天的背景换好了"))
                } else {
                    app.me = oldUser
                    ChatBgStore.shared.set(chatId, oldLocal)
                    app.show(Tr("背景没保存上，检查网络"))
                }
                busy = false
            }
            return
        }
        let oldUser = app.me
        if var me = app.me {
            me.chatBackground = storedPath
            app.me = me
        }
        Task {
            busy = true
            if path == "auto" {
                // 全局背景和所有会话覆盖必须由同一个请求一起清除，避免旧分片回写。
                let reset = await API.shared.resetChatBackgrounds()
                let saved = reset || await API.shared.changeBackground("auto")
                if saved {
                    store.clearAll()
                    if var me = app.me {
                        me.chatBackground = "auto"
                        me.chatBackgrounds = [:]
                        app.me = me
                    }
                    app.show(Tr("已恢复默认背景"))
                } else {
                    app.me = oldUser
                    app.show(Tr("背景没保存上，检查网络"))
                }
            } else {
                if await API.shared.changeBackground(storedPath) {
                    app.show(Tr("背景换好了"))
                } else {
                    app.me = oldUser
                    app.show(Tr("背景没保存上，检查网络"))
                }
            }
            busy = false
        }
    }

    private func upload(_ image: UIImage) {
        Task {
            busy = true
            if let url = try? await API.shared.uploadOriginal(image: image) {
                primeBackgroundCache(path: url, image: image)
                if inChat {
                    if let saved = await API.shared.changeChatBackground(chatId: chatId, path: url) {
                        applyChatBackground(url)
                        applySyncedChatBackgrounds(saved)
                        app.show(Tr("这个聊天的背景换好了"))
                    } else {
                        app.show(Tr("图片上传失败，换一张再试"))
                    }
                } else {
                    let oldUser = app.me
                    if var me = app.me {
                        me.chatBackground = url
                        app.me = me
                    }
                    if await API.shared.changeBackground(url) {
                        app.show(Tr("聊天背景换好了"))
                    } else {
                        app.me = oldUser
                        app.show(Tr("背景没保存上，检查网络"))
                    }
                }
            } else {
                app.show(Tr("图片上传失败，换一张再试"))
            }
            busy = false
        }
    }

    private func applyChatBackground(_ path: String) {
        ChatBgStore.shared.set(chatId, path)
        guard var me = app.me else { return }
        var map = me.chatBackgrounds ?? [:]
        if path == "auto" {
            map.removeValue(forKey: chatId)
        } else {
            map[chatId] = path
        }
        me.chatBackgrounds = map
        app.me = me
    }

    private func applySyncedChatBackgrounds(_ map: [String: String]) {
        guard var me = app.me else { return }
        me.chatBackgrounds = map.filter { !$0.value.isEmpty && $0.value != "auto" }
        app.me = me
    }

    private func primeBackgroundCache(path: String, cacheKey: String = "", image: UIImage? = nil) {
        guard !path.isEmpty, path != "auto" else { return }
        guard chatBackgroundSolidColor(path) == nil else { return }
        if let image = image {
            ImageStore.shared.put(path, image)
            if let data = image.jpegData(compressionQuality: 0.86) {
                Task.detached(priority: .userInitiated) { ImageStore.shared.diskWrite(path, data) }
            }
            return
        }
        guard !cacheKey.isEmpty, cacheKey != path else { return }
        if let cached = ImageStore.shared.get(cacheKey) {
            ImageStore.shared.put(path, cached)
            return
        }
        if let data = ImageStore.shared.diskRead(cacheKey),
           let image = RemoteImage.downsampled(data, maxSide: 1600) {
            ImageStore.shared.put(path, image)
            Task.detached(priority: .userInitiated) { ImageStore.shared.diskWrite(path, data) }
        }
    }
}
