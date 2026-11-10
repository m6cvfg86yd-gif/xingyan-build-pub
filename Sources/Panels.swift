import SwiftUI

var panelH: CGFloat { L.v(198, 53, 240) }

struct ChatPanelGlassBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            GlassBackground(shape: Rectangle(),
                            opacity: scheme == .dark ? 0.74 : 0.94,
                            edgeAlpha: scheme == .dark ? 0.16 : 0.26,
                            shadow: false,
                            seed: 0.83,
                            native: true)
            C.tabBg.opacity(scheme == .dark ? 0.32 : 0.18)
            LinearGradient(colors: [Color.white.opacity(scheme == .dark ? 0.015 : 0.12),
                                    Color.clear],
                           startPoint: .top, endPoint: .bottom)
        }
    }
}

struct ChatEmojiPanelMaterial: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Rectangle().fill(
                scheme == .dark
                    ? Color.black.opacity(0.08)
                    : Color.white.opacity(0.07)
            )
        }
    }
}

let emojiAll: [String] = [
    "😄", "😖", "😍", "😳", "😎", "😭", "😚", "🤐",
    "😴", "😢", "😅", "😡", "😛", "😁", "😲", "😔",
    "😎", "😰", "😫", "🤢", "🤭", "😊", "🙄", "😤",
    "🤤", "😪", "😱", "😅", "😃", "🫡", "💪", "🤬",

    "🤔", "🤫", "😵", "😩", "😞", "💀", "🔨", "👋",
    "😅", "🤧", "👏", "😳", "😏", "😤", "😤", "🥱",
    "😒", "🥺", "😢", "😏", "😘", "😨", "🥺", "🔪",
    "🍉", "🍺", "🏀", "🏓", "☕", "🍚", "🐷", "🌹",

    "🥀", "😘", "❤️", "💔", "🎂", "⚡", "💣", "🗡️",
    "⚽", "🐞", "💩", "🌙", "☀️", "🎁", "🤗", "👍",
    "👎", "🤝", "✌️", "🙏", "😉", "👊", "👌", "🕺",
    "🥶", "😤", "🌀", "🙇", "🔄", "🏃", "👋", "🤩",

    "👍", "👏", "🙏", "✌️", "❤️", "🌹", "🎁", "🎉",
    "🔥", "⭐", "🌈", "🎵", "☕", "🎂", "🧧", "☀️",
    "🌙", "☁️", "🌧️", "❄️", "🐱", "🐶", "🐼", "🐰",
    "🐷", "🐵", "🐯", "🐟", "🍎", "🍓", "🍉", "🍺"
]

enum EmojiSet {
    static let names = ["smile", "grin", "laugh", "joy", "rofl", "wink", "love", "kiss",
                        "cool", "shy", "smirk", "think", "wow", "doubt", "sweat", "shh",
                        "cry", "sob", "angry", "sleep", "pray", "clap", "ok", "thumb",
                        "heart", "fire", "gift", "redpacket", "party", "money"]
    static var ours: [String] { names }
    static func url(_ i: Int) -> String { "/uploads/emj2-" + names[max(0, min(i, names.count - 1))] + ".png" }
}

@MainActor
final class StickerImageCache {
    static let shared = StickerImageCache()
    private var store: [String: UIImage] = [:]
    private var animatedStore: [String: UIImage] = [:]

    static func decode(_ data: Data, animated: Bool) -> UIImage? {
        guard animated,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }

        let count = CGImageSourceGetCount(source)
        guard count > 1 else { return UIImage(data: data) }

        var frames: [UIImage] = []
        frames.reserveCapacity(count)
        var duration = 0.0

        for index in 0..<count {
            guard let cg = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            frames.append(UIImage(cgImage: cg))

            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue
                ?? (gif?[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue
                ?? 0.08
            duration += max(0.02, delay)
        }

        guard !frames.isEmpty else { return UIImage(data: data) }
        return UIImage.animatedImage(with: frames, duration: max(0.2, duration)) ?? frames[0]
    }

    func get(_ key: String) -> UIImage? { store[key] }

    func getAnimated(_ key: String) -> UIImage? { animatedStore[key] }

    func put(_ key: String, _ image: UIImage, animated: Bool = false) {
        if store.count > 600 { store.removeAll() }
        if animatedStore.count > 36 { animatedStore.removeAll() }
        store[key] = image
        if animated {
            animatedStore[key] = image
        }
    }
}

struct AnimatedStickerView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = true
        view.backgroundColor = .clear
        apply(image, to: view)
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        apply(image, to: view)
    }

    static func dismantleUIView(_ view: UIImageView, coordinator: Void) {
        view.stopAnimating()
        view.animationImages = nil
    }

    private func apply(_ image: UIImage, to view: UIImageView) {
        guard let frames = image.images, frames.count > 1 else {
            view.stopAnimating()
            view.animationImages = nil
            view.image = image
            return
        }
        view.image = frames[0]
        if view.animationImages?.first !== frames.first {
            view.animationImages = frames
            view.animationDuration = max(0.2, image.duration)
            view.animationRepeatCount = 0
        }
        if !view.isAnimating {
            view.startAnimating()
        }
    }
}

struct StickerThumb: View {
    let url: String
    @State private var image: UIImage?

    private var isAnimated: Bool {
        url.lowercased().hasSuffix(".gif")
    }

    var body: some View {
        Group {
            if let image = image {
                if isAnimated {
                    AnimatedStickerView(image: image)
                } else {
                    Image(uiImage: image).resizable().scaledToFit()
                }
            } else {
                Color.clear
            }
        }
        .task(id: url) {
            if isAnimated, let cached = StickerImageCache.shared.getAnimated(url) {
                image = cached
                return
            }
            if !isAnimated, let cached = StickerImageCache.shared.get(url) {
                image = cached
                return
            }
            guard let u = API.shared.assetURL(url) else { return }
            if let data = try? await API.shared.assetData(u),
               let img = StickerImageCache.decode(data, animated: isAnimated) {
                StickerImageCache.shared.put(url, img, animated: isAnimated)
                image = img
            }
        }
    }
}

struct EmojiPanel: View {
    @Binding var draft: String
    var onSend: () -> Void
    var onDelete: () -> Void

    var onInsert: ((String) -> Void)? = nil

    var onSendSticker: ((String) -> Void)? = nil

    var onOpenStore: (() -> Void)? = nil

    var onCaptureSticker: (() -> Void)? = nil

    var mine: StickerMine? = nil
    var onExpandedChange: ((Bool) -> Void)? = nil

    @State private var tab = 1

    @State private var recent: [String] = EmojiPanel.loadRecent()
    @State private var emojiSearch = ""
    @FocusState private var searchFocused: Bool

    @State private var installed: [PanelPack] = []

    @ObservedObject private var catalog = StickerCatalog.shared
    @State private var expanded = false

    private var packTabs: [PanelPack] {
        var seen = Set<String>()
        var list: [PanelPack] = []
        for pack in installed where seen.insert(pack.id).inserted {
            list.append(pack)
        }
        for pack in mine?.packList ?? [] {
            let id = pack.id ?? ""
            guard !id.isEmpty, seen.insert(id).inserted else { continue }
            let rawIcon = pack.icon ?? ""
            let icon = rawIcon.isEmpty ? (pack.stickers?.first ?? "✨") : rawIcon
            list.append(PanelPack(
                id: id,
                name: pack.name ?? Tr("表情包"),
                icon: icon,
                stickers: pack.stickers ?? [],
                isImage: true
            ))
        }
        return list
    }

    private var singleStickers: [String] {
        mine?.singleList ?? []
    }

    private var singleTabIndex: Int {
        4 + packTabs.count
    }

    private var maximumTabIndex: Int {
        singleStickers.isEmpty ? 3 + packTabs.count : 4 + packTabs.count
    }

    private var emojiRowH: CGFloat {
        min(46, max(40, (L.width - 20) / 7))
    }
    private var collapsedH: CGFloat {
        let tabsH: CGFloat = 44
        let deleteH = L.v(38, 10.4, 42)
        return tabsH + deleteH + emojiRowH * 5 + 10
    }
    private var expandedH: CGFloat {
        min(max(panelH * 2.15, 390), L.height * 0.68)
    }

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private static let recentKey = "emoji.recent"

    private static func loadRecent() -> [String] {
        (UserDefaults.standard.array(forKey: recentKey) as? [String]) ?? []
    }

    private func use(_ glyph: String) {
        if let onInsert {
            onInsert(glyph)
        } else {
            draft += glyph
        }
        var list = recent.filter { $0 != glyph }
        list.insert(glyph, at: 0)
        if list.count > 24 { list = Array(list.prefix(24)) }
        recent = list
        UserDefaults.standard.set(list, forKey: Self.recentKey)
    }

    private func tile(_ glyph: String) -> some View {
        Button { use(glyph) } label: {
            Text(glyph)
                .font(pf(L.v(29, 8.2, 32)))
                .frame(maxWidth: .infinity)
                .frame(height: emojiRowH)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func emojiGrid(_ list: [String]) -> some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: cols, spacing: 0) {
                ForEach(list.indices, id: \.self) { i in tile(list[i]) }
            }
            .padding(.horizontal, L.v(6, 2, 10))
            .padding(.top, L.v(6, 2, 10))
            .padding(.bottom, 4)
        }
    }

    private var classicPage: some View {
        var seen = Set<String>()
        let glyphs = ClassicEmojiSet.all.map { $0.glyph }.filter { seen.insert($0).inserted }
        return emojiGrid(glyphs)
    }

    private var systemPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(EmojiThemes.all.indices, id: \.self) { t in
                    let theme = EmojiThemes.all[t]
                    Text(theme.name)
                        .font(pf(11.5))
                        .foregroundColor(C.subLabel)
                        .padding(.horizontal, L.v(10, 3.2, 14))
                        .padding(.top, t == 0 ? 8 : 12)
                        .padding(.bottom, 2)
                    LazyVGrid(columns: cols, spacing: 0) {
                        ForEach(theme.list.indices, id: \.self) { i in tile(theme.list[i]) }
                    }
                    .padding(.horizontal, L.v(6, 2, 10))
                }
            }
            .padding(.bottom, 6)
        }
    }

    private var searchableGlyphs: [String] {
        var seen = Set<String>()
        var list: [String] = []
        for glyph in ClassicEmojiSet.all.map({ $0.glyph }) + EmojiThemes.all.flatMap({ $0.list }) {
            if seen.insert(glyph).inserted { list.append(glyph) }
        }
        return list
    }

    private var searchResults: [String] {
        let key = emojiSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return [] }
        let codeGlyphs = ClassicEmojiSet.all
            .filter { $0.code.lowercased().contains(key) }
            .map { $0.glyph }
        var seen = Set<String>()
        return (codeGlyphs + searchableGlyphs.filter { $0.contains(emojiSearch) })
            .filter { seen.insert($0).inserted }
    }

    private var likeGlyphs: [String] {
        let wanted = ["赞", "强", "给力", "加油", "鼓掌", "比心", "ok",
                      "胜利", "棒", "爱心", "抱拳", "庆祝", "666"]
        var seen = Set<String>()
        let fromClassic = ClassicEmojiSet.all
            .filter { item in
                let code = item.code.lowercased()
                return wanted.contains { code.contains($0) }
            }
            .map { $0.glyph }
        let extras = ["👍", "❤️", "💪", "👏", "🙏", "🤝", "✌️", "👌",
                      "🫶", "💯", "🎉", "🔥", "⭐️", "🫡"]
        return (fromClassic + extras).filter { seen.insert($0).inserted }
    }

    private var emojiSearchPage: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(C.subLabel)
                TextField(Tr("搜索表情"), text: $emojiSearch)
                    .font(pf(14))
                    .focused($searchFocused)
                    .submitLabel(.search)
                if !emojiSearch.isEmpty {
                    Button {
                        emojiSearch = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(C.subLabel)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(Capsule().fill(Color.dyn(0xF2F2F3, 0x2B2B2E)))
            .padding(.horizontal, 10)
            .padding(.top, 6)

            if emojiSearch.isEmpty {
                if recent.isEmpty {
                    VStack(spacing: 7) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(C.subLabel)
                        Text(Tr("搜索表情和表情包"))
                            .font(pf(12.5))
                            .foregroundStyle(C.subLabel)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(showsIndicators: false) {
                        packTitle("🕘", Tr("最近使用"))
                        emojiRow(recent)
                    }
                }
            } else if searchResults.isEmpty {
                Text(Tr("没有找到表情"))
                    .font(pf(13))
                    .foregroundStyle(C.subLabel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emojiGrid(searchResults)
            }
        }
    }

    @ViewBuilder
    private var recentPage: some View {
        if recent.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 24, weight: .light))
                    .foregroundColor(C.subLabel)
                Text(Tr("用过的表情会出现在这里"))
                    .font(pf(12.5))
                    .foregroundColor(C.subLabel)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            emojiGrid(recent)
        }
    }

    private var minePage: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {

                HStack(spacing: 8) {
                    packActionButton(Tr("表情商店"), symbol: "plus") {
                        onOpenStore?()
                    }
                    packActionButton(Tr("拍摄表情"), symbol: "camera.fill") {
                        onCaptureSticker?()
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)

                ForEach(installed.indices, id: \.self) { i in
                    let pack = installed[i]
                    packTitle(pack.icon.isEmpty ? "✨" : pack.icon, pack.name)
                    if pack.isImage {
                        stickerRow(pack.stickers)
                    } else {
                        emojiRow(pack.stickers)
                    }
                }

                if let packs = mine?.packList, !packs.isEmpty {
                    ForEach(packs.indices, id: \.self) { i in
                        packTitle(packs[i].icon ?? "😀", packs[i].name ?? Tr("表情包"))
                        stickerRow(packs[i].stickers ?? [])
                    }
                }

                if let singles = mine?.singleList, !singles.isEmpty {
                    packTitle("⭐", Tr("我添加的表情"))
                    stickerRow(singles)
                }

                packTitle("🖼", Tr("我们的表情"))
                imageStickerRow

            }
            .padding(.top, L.v(2, 0.6, 4))
            .padding(.bottom, 6)
        }
    }

    private func packActionButton(_ title: String,
                                  symbol: String,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 12.5, weight: .semibold))
                Text(title)
                    .font(pf(12.5, .medium))
            }
            .foregroundStyle(C.label)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(Capsule().fill(Color.dyn(0xF2F2F3, 0x2A2A2D)))
            .overlay(Capsule().stroke(C.hairline.opacity(0.55), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func packTitle(_ icon: String, _ name: String) -> some View {
        HStack(spacing: 6) {
            Text(icon).font(pf(13))
            Text(name).font(pf(11.5)).foregroundColor(C.subLabel)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, L.v(10, 3.2, 14))
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    private func emojiRow(_ list: [String]) -> some View {
        LazyVGrid(columns: cols, spacing: 0) {
            ForEach(list.indices, id: \.self) { i in tile(list[i]) }
        }
        .padding(.horizontal, L.v(6, 2, 10))
    }

    private func stickerRow(_ list: [String]) -> some View {
        LazyVGrid(columns: cols, spacing: 0) {
            ForEach(list.indices, id: \.self) { i in
                Button { tapSticker(list[i]) } label: {
                    Group {
                        if isImageSticker(list[i]) {
                            StickerThumb(url: list[i])
                        } else {
                            Text(list[i]).font(pf(L.v(23, 6.6, 28)))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: panelH * 0.80 / 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, L.v(6, 2, 10))
    }

    private var imageStickerRow: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 5), spacing: 0) {
            ForEach(EmojiSet.ours.indices, id: \.self) { i in
                Button { onSendSticker?(EmojiSet.url(i)) } label: {
                    StickerThumb(url: EmojiSet.url(i))
                        .frame(maxWidth: .infinity)
                        .frame(height: panelH * 0.80 / 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, L.v(6, 2, 10))
    }

    private func tapSticker(_ s: String) {
        guard isImageSticker(s) else { use(s); return }

        let path = (s.hasPrefix("http") || s.hasPrefix("/")) ? s : "/" + s
        onSendSticker?(path)
    }

    private func isImageSticker(_ s: String) -> Bool {
        s.hasPrefix("http") || s.hasPrefix("/uploads") || s.hasPrefix("/emoji") || s.hasPrefix("emoji/")
    }

    private func tabButton(_ i: Int, _ title: String, _ symbol: String) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) { tab = i }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: L.v(19, 5.3, 21), weight: .medium))
                .foregroundColor(tab == i ? C.label : C.subLabel)
                .frame(width: 46, height: 36)
                .background {
                    if tab == i {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(C.label.opacity(0.07))
                    }
                }
                .scaleEffect(tab == i ? 1.04 : 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func glyphTabButton(_ i: Int, _ title: String, _ glyph: String) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) { tab = i }
        } label: {
            Text(glyph)
                .font(.system(size: 24))
                .frame(width: 46, height: 36)
                .background {
                    if tab == i {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(C.label.opacity(0.07))
                    }
                }
                .scaleEffect(tab == i ? 1.06 : 0.94)
                .opacity(tab == i ? 1 : 0.72)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func packTabButton(_ i: Int, _ pack: PanelPack) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) { tab = i }
        } label: {
            VStack(spacing: 2) {
                Group {
                    if pack.isImage && isImageSticker(pack.icon) {
                        StickerThumb(url: pack.icon)
                    } else {
                        Text(pack.icon).font(pf(L.v(19, 5.4, 22)))
                    }
                }
                .frame(width: 32, height: 32)

                Capsule()
                    .fill(tab == i ? C.label : Color.clear)
                    .frame(width: 12, height: 2)
            }
            .frame(width: 56, height: 44)
            .scaleEffect(tab == i ? 1.04 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(pack.name)
    }

    private func singleTabButton(_ i: Int, _ title: String, _ sticker: String) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) { tab = i }
        } label: {
            VStack(spacing: 2) {
                Group {
                    if isImageSticker(sticker) {
                        StickerThumb(url: sticker)
                    } else {
                        Text(sticker).font(pf(L.v(21, 5.8, 23)))
                    }
                }
                .frame(width: 32, height: 32)

                Capsule()
                    .fill(tab == i ? C.label : Color.clear)
                    .frame(width: 12, height: 2)
            }
            .frame(width: 56, height: 44)
            .scaleEffect(tab == i ? 1.04 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func packPage(_ pack: PanelPack) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                if pack.isImage && isImageSticker(pack.icon) {
                    StickerThumb(url: pack.icon).frame(width: 18, height: 18)
                } else {
                    Text(pack.icon).font(pf(13))
                }
                Text(pack.name).font(pf(11.5)).foregroundColor(C.subLabel)
                Text("\(pack.stickers.count) 个")
                    .font(pf(11))
                    .foregroundColor(C.subLabel.opacity(0.8))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, L.v(10, 3.2, 14))
            .padding(.top, 8)
            .padding(.bottom, 2)
            if pack.isImage {

                ScrollView(showsIndicators: false) {
                    stickerRow(pack.stickers)
                }
            } else {
                emojiGrid(pack.stickers)
            }
        }
    }

    private func buildInstalled() -> [PanelPack] {
        var out: [PanelPack] = []
        for b in StickerLib.mine {
            out.append(PanelPack(id: b.id, name: b.name, icon: b.icon,
                                 stickers: b.stickers, isImage: false))
        }
        for r in catalog.packs where StickerLib.isRemoteIn(r.id) {
            out.append(PanelPack(id: r.id, name: r.name, icon: r.icon,
                                 stickers: r.paths, isImage: true))
        }
        return out
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        tabButton(0, Tr("搜索"), "magnifyingglass")
                        glyphTabButton(1, Tr("笑脸"), "😊")
                        glyphTabButton(2, Tr("赞"), "👍")
                        glyphTabButton(3, Tr("其他表情包"), "🧩")
                        ForEach(packTabs.indices, id: \.self) { offset in
                            packTabButton(4 + offset, packTabs[offset])
                        }
                        if let first = singleStickers.first {
                            singleTabButton(singleTabIndex, Tr("我添加的表情"), first)
                        }
                    }
                    .padding(.horizontal, 8)
                }

                Button {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                        expanded.toggle()
                    }
                } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(C.subLabel)
                        .frame(width: 42, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded ? Tr("收起") : Tr("展开"))
            }
            .frame(height: 44)

            TabView(selection: $tab) {
                emojiSearchPage.tag(0)
                classicPage.tag(1)
                emojiGrid(likeGlyphs).tag(2)
                minePage.tag(3)
                ForEach(packTabs.indices, id: \.self) { offset in
                    packPage(packTabs[offset]).tag(4 + offset)
                }
                if !singleStickers.isEmpty {
                    ScrollView(showsIndicators: false) {
                        packTitle("⭐", Tr("我添加的表情"))
                        stickerRow(singleStickers)
                    }
                    .tag(singleTabIndex)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onAppear {
                installed = buildInstalled()
                if tab < 0 || tab > maximumTabIndex { tab = 1 }
            }
            .task {
                await StickerCatalog.shared.loadIfNeeded()
                installed = buildInstalled()
            }
            .onChange(of: catalog.packs) { _ in
                installed = buildInstalled()
                if tab < 0 || tab > maximumTabIndex { tab = 1 }
            }
            .onChange(of: mine) { _ in
                installed = buildInstalled()
                if tab < 0 || tab > maximumTabIndex { tab = 1 }
            }
            .onChange(of: maximumTabIndex) { limit in
                if tab > limit { tab = 1 }
            }
            .onChange(of: expanded) { value in
                onExpandedChange?(value)
            }

            HStack {
                Spacer()
                Button(action: onDelete) {
                    SVGIcon(markup: I.deleteKey,
                            size: L.v(21, 6.2, 24),
                            color: C.iconGray)
                        .frame(width: L.v(32, 9.4, 36), height: 32)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, L.v(12, 3.8, 15))
            .frame(height: L.v(38, 10.4, 42))
        }
        .frame(height: expanded ? expandedH : collapsedH)
        .animation(.spring(response: 0.30, dampingFraction: 0.86), value: expanded)
    }
}

struct PlusPanel: View {
    let items: [PlusItem]
    var onTap: (PlusItem) -> Void

    var onLongPress: ((PlusItem) -> Bool)? = nil
    var onRecentImage: ((UIImage) -> Void)? = nil

    @State private var page = 0
    @ObservedObject private var recentPhotos = RecentPhotoStore.shared

    @State private var pressed: String? = nil
    private let perPage = 8

    private var pages: [[PlusItem]] {
        stride(from: 0, to: max(1, items.count), by: perPage).map { start in
            Array(items[start..<min(start + perPage, items.count)])
        }
    }

    private func tileColors(_ action: String?) -> [Color] {
        switch (action ?? "").lowercased() {
        case "photo":                    return [C.green, C.green.opacity(0.78)]
        case "camera":                   return [C.green, C.green.opacity(0.78)]
        case "video", "videocall":       return [Color(hex: 0xFF8A73), Color(hex: 0xE2432E)]
        case "voice", "voicecall":       return [Color(hex: 0x64B5F6), Color(hex: 0x2A6BC4)]
        case "location", "liveshare":    return [Color(hex: 0x4ECDC4), Color(hex: 0x1F8C86)]
        case "redpacket":                return [Color(hex: 0xF4634A), Color(hex: 0xC22A18)]
        case "gift":                     return [Color(hex: 0xFFC85C), Color(hex: 0xE09A18)]
        case "transfer":                 return [Color(hex: 0xFFC24B), Color(hex: 0xE08A0C)]
        case "file":                     return [Color(hex: 0x8A93FF), Color(hex: 0x4A55D6)]
        case "card":                     return [Color(hex: 0xA0A4AE), Color(hex: 0x6E7280)]
        case "favorite", "star":         return [Color(hex: 0xFFD34B), Color(hex: 0xE09A10)]
        case "coupon":                   return [Color(hex: 0xFF9F6B), Color(hex: 0xE0692A)]
        case "music":                    return [Color(hex: 0xB98CFF), Color(hex: 0x7A45D6)]
        case "screen":                   return [Color(hex: 0x7FA6E8), Color(hex: 0x3F66B8)]
        case "chain", "link":            return [Color(hex: 0x74C0FC), Color(hex: 0x2F7FD1)]
        case "vote":                     return [Color(hex: 0x6FD3A8), Color(hex: 0x1E9B6B)]
        default:                         return [Color(hex: 0xA8ACB6), Color(hex: 0x74788A)]
        }
    }

    private var tileH: CGFloat { L.v(54, 15, 58) }
    private var tileGap: CGFloat { L.v(7, 2.4, 9) }
    private var gridPad: CGFloat { L.v(14, 4.2, 18) }
    private var gridGap: CGFloat { L.v(10, 3.2, 14) }
    private var dotsH: CGFloat { L.v(22, 6, 26) }

    private var neededH: CGFloat {
        let rows = CGFloat(max(1, Int(ceil(Double(min(items.count, perPage)) / 4.0))))
        return gridPad * 2 + rows * (tileH + tileGap + 16) + max(0, rows - 1) * gridGap + dotsH
    }

    private var recentRailExtra: CGFloat {
        (onRecentImage != nil && !recentPhotos.assets.isEmpty) ? 90 : 0
    }

    var body: some View {
        VStack(spacing: 0) {
            if let onRecentImage, !recentPhotos.assets.isEmpty {
                RecentPhotoRail(store: recentPhotos, onPick: onRecentImage)
            }

            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { p in
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: L.v(10, 3.2, 14)), count: 4),
                              spacing: L.v(10, 3.2, 14)) {
                        ForEach(pages[p].indices, id: \.self) { i in
                            tile(pages[p][i])
                        }
                    }
                    .padding(.horizontal, gridPad)
                    .padding(.top, gridPad)
                    .padding(.bottom, gridPad * 0.5)
                    .tag(p)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            if pages.count > 1 {
                HStack(spacing: L.v(5, 1.6, 7)) {
                    ForEach(pages.indices, id: \.self) { i in
                        Capsule()
                            .fill(i == page ? C.green : Color.dyn(0xD6D6D6, 0x4A4A4C))
                            .frame(width: i == page ? L.v(14, 4, 16) : L.v(6, 1.8, 7),
                                   height: L.v(6, 1.8, 7))
                            .animation(.easeOut(duration: 0.18), value: page)
                    }
                }
                .frame(height: dotsH)
            } else {
                Color.clear.frame(height: L.v(10, 3, 12))
            }
        }
        .frame(height: max(panelH, neededH) + recentRailExtra)
        .overlay(alignment: .top) { Rectangle().fill(C.hairline).frame(height: 0.5) }
        .task { await recentPhotos.loadIfNeeded() }
    }

    private func tile(_ item: PlusItem) -> some View {
        return VStack(spacing: tileGap) {
            ZStack {
                Circle()
                    .fill(C.green.opacity(0.12))
                    .frame(width: tileH, height: tileH)
                Circle()
                    .stroke(C.green.opacity(0.18), lineWidth: 0.8)
                    .frame(width: tileH, height: tileH)
                Image(systemName: whatsAppPlusSymbol(item))
                    .font(.system(size: L.v(23, 7, 26), weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(C.green)
            }
            Text(chatEntryLabel(item.label, action: item.action))
                .font(pf(L.v(11.5, 3.2, 12.5)))
                .foregroundColor(C.subLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .opacity(item.enabled == false ? 0.45 : 1)

        .scaleEffect(pressed == item.id ? 0.92 : 1)
        .animation(.easeOut(duration: 0.12), value: pressed)
        .contentShape(Rectangle())
        .onTapGesture { onTap(item) }

        .onLongPressGesture(minimumDuration: 0.35, maximumDistance: 40,
                            pressing: { p in pressed = p ? item.id : nil }) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()

            if let lp = onLongPress, lp(item) { return }
            onTap(item)
        }
    }

    private func whatsAppPlusSymbol(_ item: PlusItem) -> String {
        switch (item.action ?? "").lowercased() {
        case "photo": return "photo.on.rectangle.angled"
        case "camera": return "camera.fill"
        case "video", "videocall": return "video.fill"
        case "voice", "voicecall": return "phone.fill"
        case "location": return "location.fill"
        case "liveshare": return "location.circle.fill"
        case "file": return "doc.fill"
        case "card", "contact": return "person.crop.rectangle"
        case "redpacket": return "envelope.fill"
        case "transfer": return "arrow.left.arrow.right"
        case "gift": return "gift.fill"
        case "music": return "music.note"
        case "screenshare", "screen": return "rectangle.on.rectangle"
        case "favorite", "star": return "star.fill"
        case "coupon": return "ticket.fill"
        case "vote": return "chart.bar.fill"
        case "chain", "link": return "link"
        case "feedback": return "bubble.left.and.bubble.right.fill"
        default: return "plus.circle.fill"
        }
    }
}

private struct PlusTileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct GiftPanel: View {
    let gifts: [Gift]
    var onTap: (Gift) -> Void

    @State private var page = 0
    private let perPage = 8

    private var pages: [[Gift]] {
        stride(from: 0, to: max(1, gifts.count), by: perPage).map { start in
            Array(gifts[start..<min(start + perPage, gifts.count)])
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if gifts.isEmpty {
                Text(Tr("礼物还没配"))
                    .font(pf(14))
                    .foregroundColor(C.subLabel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { p in
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: L.v(8, 2.8, 13)), count: 4),
                                  spacing: L.v(8, 2.8, 13)) {
                            ForEach(pages[p].indices, id: \.self) { i in
                                let g = pages[p][i]
                                Button {
                                    onTap(g)
                                } label: {
                                    VStack(spacing: L.v(3, 1.2, 5)) {
                                        Text(g.icon ?? "🎁").font(pf(L.v(22, 6.4, 27)))
                                        Text(g.name ?? "礼物")
                                            .font(pf(L.v(10.5, 3, 12)))
                                            .foregroundColor(C.subLabel)
                                            .lineLimit(1)
                    Text("¥\(Int(g.price ?? 0))")
                        .font(pfMoney(L.v(10, 2.8, 11.5)))
                                            .foregroundColor(C.red)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: (panelH - L.v(22, 6, 26) - L.v(24, 7.6, 32)) / 2)
                                    .background { CardGlassBox(radius: L.v(6, 2, 9)) }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, L.v(10, 3.2, 14))
                        .padding(.top, L.v(10, 3.2, 14))
                        .tag(p)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: L.v(5, 1.6, 7)) {
                    ForEach(pages.indices, id: \.self) { i in
                        Circle()
                            .fill(i == page ? Color.dyn(0xBFBFBF, 0xB8B8B8) : Color.dyn(0xCFCFCF, 0x4A4A4A))
                            .frame(width: L.v(5, 1.5, 7), height: L.v(5, 1.5, 7))
                    }
                }
                .frame(height: L.v(22, 6, 26))
            }
        }
        .frame(height: panelH)
        .background(C.tabBg)
    }
}

struct MentionPanel: View {

    let members: [User]
    @Binding var query: String

    let canAtAll: Bool

    let title: (User) -> String
    let onPick: (User) -> Void
    let onPickAll: () -> Void
    @State private var activeLetter = ""

    private var filtered: [User] {
        let k = query.trimmingCharacters(in: .whitespaces)
        guard !k.isEmpty else { return members }
        return members.filter {
            title($0).contains(k)
                || ($0.nickname ?? "").contains(k)
                || ($0.username ?? "").contains(k)
        }
    }

    private var grouped: [(letter: String, users: [User])] {
        Dictionary(grouping: filtered) { pinyinInitial(title($0)) }
            .map { (letter: $0.key, users: $0.value.sorted {
                title($0).localizedCompare(title($1)) == .orderedAscending
            }) }
            .sorted { $0.letter < $1.letter }
    }

    var body: some View {
        VStack(spacing: 0) {

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundColor(C.subLabel)
                TextField(Tr("搜索"), text: $query)
                    .font(pf(14))
                    .foregroundColor(C.label)
                    .frame(height: 30)
            }
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.dyn(0xF2F2F2, 0x2C2C2E)))
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)

            if !grouped.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(grouped, id: \.letter) { group in
                            Button {
                                activeLetter = group.letter
                            } label: {
                                Text(group.letter)
                                    .font(pf(11.5, activeLetter == group.letter ? .bold : .semibold))
                                    .foregroundColor(activeLetter == group.letter ? .white : C.subLabel)
                                    .frame(width: 26, height: 26)
                                    .background {
                                        Circle().fill(activeLetter == group.letter
                                                      ? C.green
                                                      : Color.primary.opacity(0.045))
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Tr("跳到 ") + group.letter)
                        }
                    }
                    .padding(.horizontal, 14)
                }
                .padding(.bottom, 6)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        if canAtAll && query.trimmingCharacters(in: .whitespaces).isEmpty {
                            row(icon: "person.3.fill", user: nil, name: Tr("所有人")) { onPickAll() }
                        }
                        ForEach(grouped, id: \.letter) { group in
                            Section {
                                ForEach(group.users) { u in
                                    row(icon: nil, user: u, name: title(u)) { onPick(u) }
                                }
                            } header: {
                                Text(group.letter)
                                    .font(pf(11, .semibold))
                                    .foregroundColor(C.subLabel)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 14)
                                    .frame(height: 24)
                                    .background(C.tabBg)
                                    .id(group.letter)
                            }
                        }
                        if filtered.isEmpty && !query.trimmingCharacters(in: .whitespaces).isEmpty {
                            Text(Tr("没有找到这个人"))
                                .font(pf(13))
                                .foregroundColor(C.subLabel)
                                .padding(.top, 26)
                        }
                    }
                    .onChange(of: activeLetter) { letter in
                        guard !letter.isEmpty else { return }
                        withAnimation(.easeOut(duration: 0.18)) {
                            proxy.scrollTo(letter, anchor: .top)
                        }
                    }
                }
            }
            .frame(height: L.v(210, 60, 250))
        }
        .background(C.tabBg)
    }

    @ViewBuilder
    private func row(icon: String?, user: User?, name: String, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 10) {
                if let u = user {
                    Avatar(path: u.avatarPath, size: 36, radius: 4)
                } else {
                    Image(systemName: icon ?? "person.fill")
                        .font(.system(size: 15))
                        .foregroundColor(C.green)
                        .frame(width: 36, height: 36)
                }
                Text(name)
                    .font(pf(15))
                    .foregroundColor(C.label)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct LocationSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onSend: (String) -> Void

    @State private var name = "我的位置"
    @State private var lat = "31.491200"
    @State private var lng = "120.311900"
    @State private var addr = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text(Tr("位置名称"))) {
                    TextField("我的位置", text: $name)
                }
                Section(header: Text(Tr("经纬度（北纬 / 东经）"))) {
                    HStack {
                        Text(Tr("纬度")).foregroundColor(.secondary)
                        TextField("31.4912", text: $lat).keyboardType(.numbersAndPunctuation)
                    }
                    HStack {
                        Text(Tr("经度")).foregroundColor(.secondary)
                        TextField("120.3119", text: $lng).keyboardType(.numbersAndPunctuation)
                    }
                    if !addr.isEmpty {
                        Text(addr).font(pf(13)).foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle(Tr("发送位置"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button(Tr("取消")) { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(Tr("发送")) {
                        let payload = "{\"lat\":\(Double(lat) ?? 0),\"lng\":\(Double(lng) ?? 0),\"name\":\"\(name)\",\"addr\":\"\(addr)\"}"
                        onSend(payload)
                        dismiss()
                    }
                }
            }
        }
    }
}
