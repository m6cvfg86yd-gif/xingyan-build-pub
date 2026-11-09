import SwiftUI
import UIKit

enum ChatBackgroundEffect: String, CaseIterable, Identifiable {
    case auto
    case original
    case blackBlur
    case whiteBlur

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "自动"
        case .original: return "原景"
        case .blackBlur: return "黑模糊"
        case .whiteBlur: return "白模糊"
        }
    }

    var symbol: String {
        switch self {
        case .auto: return "circle.lefthalf.filled"
        case .original: return "photo"
        case .blackBlur: return "moon.fill"
        case .whiteBlur: return "sun.max.fill"
        }
    }

    func resolved(for scheme: ColorScheme) -> ChatBackgroundEffect {
        self == .auto ? (scheme == .dark ? .blackBlur : .whiteBlur) : self
    }
}

func normalizedChatBackground(_ path: String) -> String {
    switch path.trimmingCharacters(in: .whitespacesAndNewlines) {
    case "/bg/bw1.jpg", "solid:white": return "solid:white"
    case "/bg/bw2.jpg", "solid:black": return "solid:black"
    default: return path
    }
}

func defaultChatCanvasColor() -> Color {
    Color.dyn(0xEFEFEF, 0x121212)
}

func effectiveDefaultChatBackground(_ path: String) -> String {
    let normalized = normalizedChatBackground(path)
    return normalized == "solid:white" ? "" : normalized
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

func effectiveGlobalChatBackground(_ serverValue: String?) -> String {
    let local = ChatBgStore.shared.global()
    if !local.isEmpty { return normalizedChatBackground(local) }
    let server = serverValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return server.isEmpty ? "auto" : normalizedChatBackground(server)
}

final class ChatBgStore: ObservableObject {
    static let shared = ChatBgStore()

    @Published private(set) var version = 0

    private let globalKey = "chris.chatBg.global"
    private let globalEffectKey = "chris.chatBgFx.global"

    private func key(_ chatId: String) -> String { "chris.chatBg." + chatId }
    private func effectKey(_ chatId: String) -> String {
        chatId.isEmpty ? globalEffectKey : "chris.chatBgFx." + chatId
    }

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

    func global() -> String {
        UserDefaults.standard.string(forKey: globalKey) ?? ""
    }

    func setGlobal(_ value: String) {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty {
            UserDefaults.standard.removeObject(forKey: globalKey)
        } else {
            UserDefaults.standard.set(clean, forKey: globalKey)
        }
        version += 1
    }

    func effect(chatId: String = "") -> ChatBackgroundEffect {
        let local = UserDefaults.standard.string(forKey: effectKey(chatId)) ?? ""
        if let value = ChatBackgroundEffect(rawValue: local) { return value }
        if !chatId.isEmpty {
            let global = UserDefaults.standard.string(forKey: globalEffectKey) ?? ""
            if let value = ChatBackgroundEffect(rawValue: global) { return value }
        }
        return .auto
    }

    func setEffect(_ effect: ChatBackgroundEffect, chatId: String = "") {
        UserDefaults.standard.set(effect.rawValue, forKey: effectKey(chatId))
        version += 1
    }

    func clearAll() {
        let prefix = "chris.chatBg."
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            UserDefaults.standard.removeObject(forKey: key)
        }
        for key in UserDefaults.standard.dictionaryRepresentation().keys
            where key.hasPrefix("chris.chatBgFx.") {
            UserDefaults.standard.removeObject(forKey: key)
        }
        UserDefaults.standard.removeObject(forKey: globalKey)
        UserDefaults.standard.removeObject(forKey: globalEffectKey)
        version += 1
    }
}

struct ChatBackgroundSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var chatId: String = ""
    var modal: Bool = false

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

    private var defaultWallpaperPath: String {
        effectiveDefaultChatBackground(app.defaultChatBackground)
    }

    private var usingDefaultWallpaper: Bool {
        guard !defaultWallpaperPath.isEmpty else { return current == "auto" }
        return normalizedChatBackground(current)
            == normalizedChatBackground(defaultWallpaperPath)
    }

    private var current: String {
        if inChat {
            let synced = app.me?.chatBackgrounds?[chatId] ?? ""
            let v = synced.isEmpty ? store.get(chatId) : synced
            return v.isEmpty ? "auto" : v
        }
        let value = effectiveGlobalChatBackground(app.me?.chatBackground)
        return value.isEmpty ? "auto" : value
    }

    private var selectedEffect: ChatBackgroundEffect {
        scheme == .dark ? .blackBlur : .original
    }

    var body: some View {
        if modal {
            immersiveBody
        } else {
            standardBody
        }
    }

    private var standardBody: some View {
        List {
                Section {
                    backgroundPreview
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                if inChat {
                    Section {
                        Button {
                            pick(defaultWallpaperPath.isEmpty
                                 ? "auto"
                                 : defaultWallpaperPath)
                        } label: {
                            HStack(spacing: 13) {
                                Group {
                                    if let solid = chatBackgroundSolidColor(defaultWallpaperPath) {
                                        solid
                                    } else if !defaultWallpaperPath.isEmpty {
                                        RemoteImage(path: defaultWallpaperPath,
                                                    mode: .fill,
                                                    maxSide: 480)
                                    } else {
                                        defaultChatCanvasColor()
                                    }
                                }
                                .frame(width: 54, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 10,
                                                            style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color.secondary.opacity(0.16),
                                                lineWidth: 0.7)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(Tr("默认壁纸"))
                                        .font(pfStyled(size: 16, weight: .medium))
                                        .foregroundStyle(.primary)
                                    Text(Tr("使用星言提供的默认聊天壁纸"))
                                        .font(pfStyled(size: 11.5))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: 8)

                                if usingDefaultWallpaper {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 19, weight: .semibold))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(busy)
                    } footer: {
                        Text(Tr("默认壁纸由星言统一维护，相册壁纸会保留完整全景。"))
                    }
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
                                        .font(pfStyled(size: 13))
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
                if modal {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(Tr("完成")) { dismiss() }
                    }
                }
            }
            .sheet(isPresented: $picking) {
                PhotoPicker { image in upload(image) }
            }
        .tint(.accentColor)
    }

    private var immersivePath: String {
        let currentPath = current == "auto"
            ? (inChat ? effectiveGlobalChatBackground(app.me?.chatBackground) : "auto")
            : current
        return currentPath == "auto"
            ? effectiveDefaultChatBackground(app.defaultChatBackground)
            : normalizedChatBackground(currentPath)
    }

    private var immersiveBody: some View {
        ZStack(alignment: .bottom) {
            immersiveBackdrop
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.black.opacity(0.03),
                    Color.clear,
                    Color.black.opacity(0.58)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            immersiveControls
                .padding(.horizontal, 14)
                .padding(.bottom, max(12, L.safeBottom + 4))

            VStack {
                HStack(spacing: 10) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background {
                                GlassBackground(
                                    shape: Circle(),
                                    opacity: 0.92,
                                    edgeAlpha: 0.42,
                                    native: true,
                                    tint: Color.black.opacity(0.16)
                                )
                            }
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(Tr("聊天背景"))
                            .font(pfStyled(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(Tr("实时预览 · 沉浸式延展"))
                            .font(pfStyled(size: 10.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.68))
                    }
                    Spacer(minLength: 0)

                    if busy {
                        ProgressView()
                            .tint(.white)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, L.safeTop + 8)
                Spacer(minLength: 0)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(scheme)
        .sheet(isPresented: $picking) {
            PhotoPicker { image in upload(image) }
        }
    }

    private var immersiveBackdrop: some View {
        let effect = selectedEffect.resolved(for: scheme)
        return ZStack {
            (effect == .blackBlur
             ? Color(hex: 0x080908)
             : Color(hex: 0xEFF1EE))

            if let solid = chatBackgroundSolidColor(immersivePath) {
                solid
            } else if !immersivePath.isEmpty {
                RemoteImage(path: immersivePath,
                            mode: .fill,
                            maxSide: chatWallpaperDecodeSide())
                    .id("immersive-" + immersivePath)
                    .scaleEffect(effect == .original ? 1 : 1.045)
                    .blur(radius: effect == .blackBlur
                          ? 23 : (effect == .whiteBlur ? 19 : 0))
                    .saturation(effect == .original ? 1 : 0.86)
                    .contrast(effect == .blackBlur ? 1.04 : 1)
                    .brightness(effect == .blackBlur
                                ? -0.035 : (effect == .whiteBlur ? 0.045 : 0))
            }

            if effect == .blackBlur {
                Color(hex: 0x090A09).opacity(0.24)
            } else if effect == .whiteBlur {
                Color.white.opacity(0.16)
            }
        }
        .animation(.easeOut(duration: 0.22), value: effect)
    }

    private var immersiveControls: some View {
        VStack(spacing: 14) {
            HStack {
                Text(Tr("背景显示"))
                    .font(pfStyled(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(Tr("跟随系统"))
                    .font(pfStyled(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Image(systemName: scheme == .dark
                      ? "moon.fill" : "sun.max.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(OrbitTheme.jade)
                Text(Tr(scheme == .dark
                        ? "深色模式自动使用黑模糊"
                        : "浅色模式保持全景上下连贯"))
                    .font(pfStyled(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 9) {
                immersiveAction("photo.on.rectangle", Tr("默认壁纸")) {
                    pick(defaultWallpaperPath.isEmpty ? "auto" : defaultWallpaperPath)
                }
                immersiveAction("photo.badge.plus", Tr("从相册")) {
                    picking = true
                }
                immersiveAction("arrow.triangle.2.circlepath", Tr("自动背景")) {
                    pick("auto")
                }
            }
            .disabled(busy)

            Text(Tr("浅色保持完整全景；深色使用同图黑模糊，遮罩只处理壁纸，不会透出聊天文字。"))
                .font(pfStyled(size: 10.5))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background {
            GlassBackground(
                shape: RoundedRectangle(cornerRadius: 24, style: .continuous),
                opacity: scheme == .dark ? 0.90 : 0.84,
                edgeAlpha: 0.44,
                shadow: true,
                seed: 0.63,
                native: true
            )
        }
    }

    private func immersiveAction(_ symbol: String,
                                 _ title: String,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(pfStyled(size: 11.5, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.primary.opacity(0.055))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color.primary.opacity(0.075), lineWidth: 0.6)
            }
        }
        .buttonStyle(.plain)
    }

    private var backgroundPreview: some View {
        let currentPath = current == "auto"
            ? (inChat ? effectiveGlobalChatBackground(app.me?.chatBackground) : "auto")
            : current
        let path = currentPath == "auto"
            ? effectiveDefaultChatBackground(app.defaultChatBackground)
            : normalizedChatBackground(currentPath)
        let effect = selectedEffect.resolved(for: scheme)
        return ZStack {
            if let solid = chatBackgroundSolidColor(path) {
                solid
            } else if !path.isEmpty {
                RemoteImage(path: path, mode: .fill)
                    .scaleEffect(effect == .original ? 1 : 1.045)
                    .blur(radius: effect == .blackBlur
                          ? 23 : (effect == .whiteBlur ? 19 : 0))
                    .saturation(effect == .original ? 1 : 0.86)
                    .contrast(effect == .blackBlur ? 1.04 : 1)
                    .brightness(effect == .blackBlur
                                ? -0.035 : (effect == .whiteBlur ? 0.045 : 0))
            } else {
                defaultChatCanvasColor()
            }

            if effect == .blackBlur {
                Color(hex: 0x090A09).opacity(0.23)
            } else if effect == .whiteBlur {
                Color.white.opacity(0.16)
            }

            VStack(spacing: 10) {
                HStack {
                    Text(Tr("今天"))
                        .font(pfStyled(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(.thinMaterial, in: Capsule())
                    Spacer()
                }
                HStack {
                    Text(Tr("默认背景预览"))
                        .font(pfStyled(size: 14))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Spacer(minLength: 60)
                }
                HStack {
                    Spacer(minLength: 78)
                    Text(Tr("黑白都保持清晰"))
                        .font(pfStyled(size: 14))
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
        store.setGlobal(storedPath)
        if var me = app.me {
            me.chatBackground = storedPath
            app.me = me
            app.rememberLastUser()
        }
        Task {
            busy = true
            if path == "auto" {
                // 全局背景和所有会话覆盖必须由同一个请求一起清除，避免旧分片回写。
                let reset = await API.shared.resetChatBackgrounds()
                var saved = reset
                if !saved {
                    saved = await API.shared.changeBackground("auto")
                }
                if saved {
                    store.setGlobal("auto")
                    if var me = app.me {
                        me.chatBackground = "auto"
                        me.chatBackgrounds = [:]
                        app.me = me
                        app.rememberLastUser()
                    }
                    app.show(Tr("已恢复默认背景"))
                } else {
                    store.setGlobal("auto")
                    app.show(Tr("已在当前设备恢复默认背景"))
                }
            } else {
                if let user = await API.shared.changeBackgroundSaved(storedPath) {
                    store.setGlobal(user.chatBackground ?? storedPath)
                    app.applyMyProfileUser(user)
                    app.show(Tr("背景换好了"))
                } else {
                    store.setGlobal(storedPath)
                    app.show(Tr("聊天背景换好了"))
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
                    ChatBgStore.shared.setGlobal(url)
                    if var me = app.me {
                        me.chatBackground = url
                        app.me = me
                        app.rememberLastUser()
                    }
                    if let user = await API.shared.changeBackgroundSaved(url) {
                        ChatBgStore.shared.setGlobal(user.chatBackground ?? url)
                        app.applyMyProfileUser(user)
                        app.show(Tr("聊天背景换好了"))
                    } else {
                        ChatBgStore.shared.setGlobal(url)
                        app.show(Tr("聊天背景换好了"))
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
           let image = RemoteImage.downsampled(data, maxSide: chatWallpaperDecodeSide()) {
            ImageStore.shared.put(path, image)
            Task.detached(priority: .userInitiated) { ImageStore.shared.diskWrite(path, data) }
        }
    }
}
