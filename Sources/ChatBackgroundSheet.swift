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
    Color.dyn(0xEFEAE2, 0x000000)
}

func worldAndMeCanvasColor() -> Color {
    Color.dyn(0xFFFFFF, 0x0B141A)
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

func renderedChatBackgroundSolidColor(_ path: String, dark: Bool) -> Color? {
    switch normalizedChatBackground(path) {
    case "solid:white":
        return dark ? Color(hex: 0x101110) : Color(hex: 0xF2F3EF)
    case "solid:black":
        return .black
    default:
        return nil
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

    private var wallpaperCardFill: Color {
        scheme == .dark ? C.cardBg : C.meCardBg
    }

    private var wallpaperCardLine: Color {
        scheme == .dark ? C.hairline : Color.primary.opacity(0.055)
    }

    private var wallpaperCardLineWidth: CGFloat {
        scheme == .dark ? 0.8 : 0.6
    }

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
        standardBody
    }

    private var standardBody: some View {
        ScrollView {
            VStack(spacing: 18) {
                backgroundPreview

                VStack(spacing: 0) {
                    wallpaperChoiceRow(
                        symbol: "photo.on.rectangle.angled",
                        tint: Color(hex: 0x128C7E),
                        title: Tr("默认壁纸"),
                        subtitle: Tr("星言全景壁纸，上下连续"),
                        selected: usingDefaultWallpaper
                    ) {
                        pick(defaultWallpaperPath.isEmpty
                             ? "auto"
                             : defaultWallpaperPath)
                    }

                    if inChat {
                        wallpaperDivider
                        wallpaperChoiceRow(
                            symbol: "arrow.triangle.2.circlepath",
                            tint: Color(hex: 0x667781),
                            title: Tr("使用全局背景"),
                            subtitle: Tr("跟随聊天背景设置自动变化"),
                            selected: current == "auto"
                        ) {
                            pick("auto")
                        }
                    }
                }
                .background(wallpaperCardFill)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(wallpaperCardLine, lineWidth: wallpaperCardLineWidth)
                }

                VStack(alignment: .leading, spacing: 10) {
                    wallpaperSectionHeader(Tr("纯色"), detail: Tr("始终可用"))

                    HStack(spacing: 12) {
                        ForEach(shownPresets, id: \.path) { item in
                            wallpaperSwatch(item)
                        }
                    }
                }

                VStack(spacing: 0) {
                    wallpaperChoiceRow(
                        symbol: "photo.badge.plus",
                        tint: Color(hex: 0x0A84FF),
                        title: Tr("从相册选择"),
                        subtitle: Tr("选择一张照片作为聊天壁纸"),
                        selected: false,
                        showsChevron: true
                    ) {
                        picking = true
                    }
                }
                .background(wallpaperCardFill)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(wallpaperCardLine, lineWidth: wallpaperCardLineWidth)
                }

                Text(Tr("相册壁纸会保留完整全景；深色模式使用同一张壁纸的自然黑模糊。"))
                    .font(pfStyled(size: 11.5))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 2)

                if busy {
                    HStack(spacing: 9) {
                        ProgressView()
                        Text(Tr("正在更新壁纸…"))
                            .font(pfStyled(size: 12.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, max(28, L.safeBottom + 20))
        }
        .scrollIndicators(.hidden)
        .background(C.pageBg.ignoresSafeArea())
        .navigationTitle(Tr(inChat ? "选择背景图" : "聊天背景"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if modal {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .accessibilityLabel(Tr("关闭"))
                }
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

    private var wallpaperDivider: some View {
        Rectangle()
            .fill(scheme == .dark ? C.hairline : Color.primary.opacity(0.075))
            .frame(height: 0.5)
            .padding(.leading, 60)
    }

    private func wallpaperSectionHeader(_ title: String,
                                        detail: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(pfStyled(size: 13.5, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            if let detail {
                Text(detail)
                    .font(pfStyled(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 2)
    }

    private func wallpaperChoiceRow(symbol: String,
                                    tint: Color,
                                    title: String,
                                    subtitle: String,
                                    selected: Bool,
                                    showsChevron: Bool = false,
                                    action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(tint)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(pfStyled(size: 15.5, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(pfStyled(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x128C7E))
                } else if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    private func wallpaperSwatch(_ item: (path: String, name: String)) -> some View {
        let selected = normalizedChatBackground(current) == item.path
        return Button {
            pick(item.path)
        } label: {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let solid = chatBackgroundSolidColor(item.path) {
                        solid
                    } else {
                        C.pageBg
                    }
                }
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 5) {
                        Capsule()
                            .fill(Color.black.opacity(item.path == "solid:black" ? 0.38 : 0.10))
                            .frame(width: 48, height: 9)
                        Capsule()
                            .fill(Color.black.opacity(item.path == "solid:black" ? 0.24 : 0.07))
                            .frame(width: 32, height: 9)
                    }
                    .padding(12)
                }

                HStack(spacing: 6) {
                    Text(Tr(item.name))
                        .font(pfStyled(size: 12.5, weight: .semibold))
                    Spacer(minLength: 4)
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                    }
                }
                .foregroundStyle(item.path == "solid:black"
                                 ? Color.white : Color(hex: 0x202C33))
                .padding(.horizontal, 11)
                .frame(height: 34)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 112)
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(selected
                            ? Color(hex: 0x128C7E)
                            : Color.primary.opacity(0.10),
                            lineWidth: selected ? 2.2 : 0.7)
            }
        }
        .buttonStyle(.plain)
        .disabled(busy)
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

            if let solid = renderedChatBackgroundSolidColor(
                immersivePath,
                dark: scheme == .dark
            ) {
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
            } else {
                ChatDefaultWallpaper()
            }

            if effect == .blackBlur {
                Color(hex: 0x090A09).opacity(0.075)
            } else if effect == .whiteBlur {
                Color.white.opacity(0.055)
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
            if let solid = renderedChatBackgroundSolidColor(
                path,
                dark: scheme == .dark
            ) {
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
                ChatDefaultWallpaper()
            }

            if effect == .blackBlur {
                Color(hex: 0x090A09).opacity(0.075)
            } else if effect == .whiteBlur {
                Color.white.opacity(0.055)
            }

            VStack(spacing: 12) {
                HStack {
                    Text(Tr("今天"))
                        .font(pfStyled(size: 10.5, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .frame(height: 23)
                        .background(Color.black.opacity(0.22), in: Capsule())
                    Spacer()
                    Label(Tr("实时预览"), systemImage: "eye.fill")
                        .font(pfStyled(size: 10.5, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .frame(height: 23)
                        .background(Color.black.opacity(0.22), in: Capsule())
                }

                HStack(alignment: .bottom, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Tr("你好，看看这张壁纸。"))
                            .font(pfStyled(size: 13.5))
                            .foregroundStyle(Color(hex: 0x111B21))
                        Text("09:41")
                            .font(pfStyled(size: 9.5))
                            .foregroundStyle(Color(hex: 0x667781))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.97),
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                    Spacer(minLength: 54)
                }

                HStack(alignment: .bottom, spacing: 8) {
                    Spacer(minLength: 70)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Tr("上下遮罩会保持同一张壁纸。"))
                            .font(pfStyled(size: 13.5))
                            .foregroundStyle(Color(hex: 0x111B21))
                        HStack(spacing: 3) {
                            Spacer(minLength: 0)
                            Text("09:42")
                                .font(pfStyled(size: 9.5))
                            Image(systemName: "checkmark")
                                .font(.system(size: 8.5, weight: .bold))
                        }
                        .foregroundStyle(Color(hex: 0x667781))
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(Color(hex: 0x0C7A70),
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }

                Spacer(minLength: 0)
                    .frame(height: 12)
            }
            .padding(14)
        }
        .frame(height: 250)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 0.7)
        }
        .shadow(color: Color.black.opacity(scheme == .dark ? 0.30 : 0.08),
                radius: 16, y: 8)
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
        let localPath = "local-bg-" + UUID().uuidString
        primeBackgroundCache(path: localPath, image: image)
        if inChat {
            applyChatBackground(localPath)
        } else {
            ChatBgStore.shared.setGlobal(localPath)
            if var me = app.me {
                me.chatBackground = localPath
                app.me = me
                app.rememberLastUser()
            }
        }

        busy = true
        Task {
            if let url = try? await API.shared.uploadOriginal(image: image) {
                primeBackgroundCache(path: url, image: image)
                if inChat {
                    if let saved = await API.shared.changeChatBackground(chatId: chatId, path: url) {
                        applyChatBackground(url)
                        applySyncedChatBackgrounds(saved)
                        app.show(Tr("这个聊天的背景换好了"))
                    } else {
                        applyChatBackground(localPath)
                        app.show(Tr("已在本机换好，联网后自动同步"))
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
                app.show(Tr("已在本机换好，联网后自动同步"))
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
            Task.detached(priority: .utility) {
                if let data = image.jpegData(compressionQuality: 0.86) {
                    ImageStore.shared.diskWrite(path, data)
                }
            }
            return
        }
        guard !cacheKey.isEmpty, cacheKey != path else { return }
        if let cached = ImageStore.shared.get(cacheKey) {
            ImageStore.shared.put(path, cached)
            return
        }
        Task.detached(priority: .utility) {
            if let data = ImageStore.shared.diskRead(cacheKey),
               let image = RemoteImage.downsampled(data, maxSide: chatWallpaperDecodeSide()) {
                ImageStore.shared.put(path, image)
                ImageStore.shared.diskWrite(path, data)
            }
        }
    }
}
