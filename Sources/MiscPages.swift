import SwiftUI

struct FavoritesView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var items: [[String: Any]] = []
    @State private var pendingNotes: [[String: Any]] = []
    @State private var loading = true
    @State private var viewerPaths: [String] = []
    @State private var viewerIndex: Int?

    @State private var q = ""
    @State private var kindFilter = "all"

    @State private var showCompose = false

    @State private var noteDetail: [String: Any]? = nil

    @State private var showAddMenu = false
    @State private var showTakePhoto = false
    @State private var showPickPhoto = false
    @State private var savingImage = false

    @State private var forward: [ForwardItem] = []
    @State private var showForward = false
    @State private var favoriteFilePreview: FilePreviewData?

    private var shown: [[String: Any]] {
        let key = q.trimmingCharacters(in: .whitespaces)
        return (pendingNotes + items).filter { it in
            let kind = (it["kind"] as? String) ?? "text"

            let isPic = ["image", "images", "video", "livephoto"].contains(kind)
            if kindFilter == "image" && !isPic { return false }
            if kindFilter == "text" && isPic { return false }
            if key.isEmpty { return true }

            let content = (it["content"] as? String) ?? ""
            let title = (it["title"] as? String) ?? ""
            let from = (it["fromName"] as? String) ?? ""
            if content.localizedCaseInsensitiveContains(key) { return true }
            if title.localizedCaseInsensitiveContains(key) { return true }
            if from.localizedCaseInsensitiveContains(key) { return true }
            let typeWords: [String] = isPic ? [Tr("图片"), Tr("视频"), Tr("照片")]
                                        : (kind == "transfer" ? [Tr("转账")] : [Tr("文字"), Tr("笔记")])
            return typeWords.contains { $0.localizedCaseInsensitiveContains(key) }
        }
    }

    private func favoriteRow(_ item: [String: Any]) -> some View {
        let kind = (item["kind"] as? String) ?? "text"
        let content = (item["content"] as? String) ?? ""
        let title = ((item["title"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let heading: String = {
            if kind == "images" { return Tr("图片") + " " + String(countImages(item)) }
            if kind == "file", let f = fileInfo(item) { return f.name }
            if !title.isEmpty { return title }
            let first = content.components(separatedBy: "\n").first ?? content
            return first.isEmpty ? Tr("收藏") : String(first.prefix(40))
        }()
        let preview: String = {
            if kind == "file", let f = fileInfo(item), f.bytes > 0 {
                return ByteCountFormatter.string(fromByteCount: Int64(f.bytes), countStyle: .file)
            }
            if kind == "images" { return Tr("图片与视频") }
            return previewText(content, excluding: title)
        }()

        return HStack(alignment: .top, spacing: 11) {
            if let thumb = thumbOf(item) {
                RemoteImage(path: thumb)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            } else {
                Image(systemName: iconName(kind))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 38, height: 38)
                    .background(Color.accentColor.opacity(0.10),
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    if (item["pinned"] as? Bool) == true {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(heading)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                if !preview.isEmpty {
                    Text(preview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let from = item["fromName"] as? String, !from.isEmpty {
                    Text(from)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { openFavorite(item) }
    }

    @ViewBuilder private var favoriteListContent: some View {
        if loading {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .padding(.vertical, 28)
        } else if shown.isEmpty {
            VStack(spacing: 9) {
                Image(systemName: "tray")
                    .font(.system(size: 30))
                    .foregroundStyle(.secondary)
                Text(Tr("暂无收藏"))
                    .font(.headline)
                Text(Tr("聊天中的收藏和你写的笔记会出现在这里"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
        } else {
            let pinned = shown.filter { ($0["pinned"] as? Bool) == true }
            let regular = shown.filter { ($0["pinned"] as? Bool) != true }
            if !pinned.isEmpty {
                Section {
                    ForEach(Array(pinned.enumerated()), id: \.offset) { _, item in
                        favoriteListRow(item)
                    }
                } header: {
                    Text(Tr("已置顶"))
                }
            }
            if !regular.isEmpty {
                Section {
                    ForEach(Array(regular.enumerated()), id: \.offset) { _, item in
                        favoriteListRow(item)
                    }
                } header: {
                    if !pinned.isEmpty {
                        Text(Tr("收藏"))
                    }
                }
            }
        }
    }

    private func favoriteListRow(_ item: [String: Any]) -> some View {
        favoriteRow(item)
            .favoriteActions(item,
                             remove: removeFavorite,
                             pin: togglePinned,
                             forward: { selected in
                                 forward = forwardItems(of: selected)
                                 showForward = true
                             })
    }

    var body: some View {
        List {
            favoriteListContent
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Tr("收藏"))
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $q, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text(Tr("搜索")))
        .refreshable { await load() }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Picker(Tr("筛选"), selection: $kindFilter) {
                        Text(Tr("全部")).tag("all")
                        Text(Tr("图片与视频")).tag("image")
                        Text(Tr("文字与笔记")).tag("text")
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showAddMenu = true } label: {
                    if savingImage {
                        ProgressView()
                    } else {
                        Image(systemName: "square.and.pencil")
                    }
                }
                .disabled(savingImage)
            }
        }
        .hidesTabBar()
        .task { await load() }

        .sheet(isPresented: $showCompose) {
            FavoriteNoteComposeSheet { body, title, editing in
                if !editing {
                    pendingNotes.insert([
                        "id": "local-" + UUID().uuidString,
                        "kind": "text",
                        "content": body,
                        "title": title,
                        "fromName": "",
                        "pinned": false
                    ], at: 0)
                }
                Task {
                    if !editing { try? await Task.sleep(nanoseconds: 350_000_000) }
                    await load()
                }
            }
                .environmentObject(app)
        }

        .confirmationDialog(Tr("添加收藏"), isPresented: $showAddMenu, titleVisibility: .hidden) {
            Button(Tr("写笔记")) { showCompose = true }
            Button(Tr("拍照")) { showTakePhoto = true }
            Button(Tr("从相册选择")) { showPickPhoto = true }
            Button(Tr("取消"), role: .cancel) { }
        }
        .fullScreenCover(isPresented: $showTakePhoto) {
            CameraPicker { img in saveImage(img) }
        }
        .sheet(isPresented: $showPickPhoto) {
            PhotoPicker { img in saveImage(img) }
        }

        .sheet(isPresented: Binding(get: { noteDetail != nil },
                                    set: { if !$0 { noteDetail = nil } })) {
            if let it = noteDetail {
                FavoriteNoteDetailSheet(id: (it["id"] as? String) ?? "",
                                        content: (it["content"] as? String) ?? "",
                                        pinned: (it["pinned"] as? Bool) == true) {
                    Task { await load() }
                }
                .environmentObject(app)
            }
        }

        .sheet(isPresented: $showForward) {
            ForwardPickerView(items: forward) { }
                .environmentObject(app)
        }
        .sheet(item: $favoriteFilePreview) { f in
            FilePreviewSheet(name: f.name, local: f.local)
        }
        .overlay {
            if let i = viewerIndex, !viewerPaths.isEmpty {

                PhotoPager(paths: viewerPaths, startIndex: i, showActions: true) { viewerIndex = nil }
            }
        }
    }

    private func openPhoto(_ path: String) {
        let all = items.filter { (($0["kind"] as? String) ?? "") == "image" }
            .compactMap { $0["content"] as? String }
        guard !all.isEmpty else { return }
        viewerPaths = all
        viewerIndex = all.firstIndex(of: path) ?? 0
    }

    private func openFavorite(_ item: [String: Any]) {
        let kind = (item["kind"] as? String) ?? "text"
        if kind == "text" || kind == "transfer" {
            noteDetail = item
        } else if kind == "file" {
            openFavoriteFile(item)
        } else if let thumb = thumbOf(item) {
            openPhoto(thumb)
        }
    }

    private func iconName(_ kind: String) -> String {
        switch kind {
        case "file": return "doc.fill"
        case "image", "images", "video", "livephoto": return "photo.on.rectangle.angled"
        case "transfer": return "yensign.circle.fill"
        default: return "note.text"
        }
    }

    private func togglePinned(_ item: [String: Any]) {
        guard let id = item["id"] as? String else { return }
        let on = (item["pinned"] as? Bool) != true
        if let index = items.firstIndex(where: { ($0["id"] as? String) == id }) {
            items[index]["pinned"] = on
        }
        Task {
            _ = await API.shared.updateFavorite(id: id, pinned: on)
            await load()
        }
    }

    private func forwardItems(of item: [String: Any]) -> [ForwardItem] {
        let kind = (item["kind"] as? String) ?? "text"
        let content = (item["content"] as? String) ?? ""
        switch kind {
        case "image":
            return [ForwardItem(kind: "image", content: content)]
        case "images":
            return [ForwardItem(kind: "images", content: content)]
        case "video":
            return [ForwardItem(kind: "video", content: content)]
        case "livephoto":
            return [ForwardItem(kind: "livephoto", content: content)]
        case "transfer":
            return [ForwardItem(kind: "text", content: content)]
        case "file":
            return [ForwardItem(kind: "file", content: content)]
        default:

            let hasPic = content.components(separatedBy: "\n").contains { $0.hasPrefix("[图]") }
            return [ForwardItem(kind: hasPic ? "note" : "text", content: content)]
        }
    }

    private func thumbOf(_ item: [String: Any]) -> String? {
        let kind = (item["kind"] as? String) ?? "text"
        let content = (item["content"] as? String) ?? ""
        if kind == "image" { return content.isEmpty ? nil : content }
        if kind == "images" {
            guard let d = content.data(using: .utf8),
                  let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let paths = o["paths"] as? [String],
                  let first = paths.first, !first.isEmpty else { return nil }
            return first
        }
        return nil
    }

    private func countImages(_ item: [String: Any]) -> Int {
        let content = (item["content"] as? String) ?? ""
        guard let d = content.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let paths = o["paths"] as? [String] else { return 0 }
        return paths.count
    }

    private func fileInfo(_ item: [String: Any]) -> (name: String, url: String, bytes: Int)? {
        let content = (item["content"] as? String) ?? ""
        guard let d = content.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let url = o["url"] as? String, !url.isEmpty else { return nil }
        let title = (item["title"] as? String) ?? ""
        let name = (o["name"] as? String) ?? (title.isEmpty ? "文件" : title)
        let bytes = (o["bytes"] as? Int) ?? 0
        return (name, url, bytes)
    }

    private func openFavoriteFile(_ item: [String: Any]) {
        guard let f = fileInfo(item) else {
            app.show(Tr("这个文件找不到了"))
            return
        }
        let name = MyFilesPickerView.previewName(f.name, path: f.url)
        app.show(Tr("正在打开…"))
        Task {
            do {
                let file = try await RemoteFileCache.shared.file(path: f.url,
                                                                 preferredName: name)
                favoriteFilePreview = FilePreviewData(name: file.name, local: file.local)
            } catch {
                app.show(Tr("文件下载失败，检查一下网络"))
            }
        }
    }

    private func load() async {
        let fresh: [[String: Any]] = await API.shared.favorites()
        pendingNotes.removeAll { pending in
            let content = (pending["content"] as? String) ?? ""
            return fresh.contains { item in
                ((item["kind"] as? String) ?? "") == ((pending["kind"] as? String) ?? "")
                    && ((item["content"] as? String) ?? "") == content
            }
        }
        items = fresh
        loading = false
    }

    private func removeFavorite(_ id: String) {
        items.removeAll { (($0["id"] as? String) ?? "") == id }
        Task {
            await API.shared.deleteFavorite(id)
            await load()
        }
    }

    private func saveImage(_ img: UIImage) {
        savingImage = true
        Task {
            do {
                let url = try await API.shared.upload(image: img)
                let ok = await API.shared.addFavorite(kind: "image", content: url,
                                                      title: Tr("图片"), from: "")
                await MainActor.run { app.show(ok ? Tr("已收藏这张图片") : Tr("收藏失败")) }
                if ok { await load() }
            } catch {
                await MainActor.run { app.show((error as? APIError)?.errorDescription ?? "上传失败") }
            }
            savingImage = false
        }
    }

    private func previewText(_ s: String, excluding heading: String = "") -> String {
        var out: [String] = []
        for line in s.components(separatedBy: "\n") {
            if line.hasPrefix("[图]") { out.append(Tr("［图片］")); continue }
            if out.isEmpty, line.trimmingCharacters(in: .whitespacesAndNewlines) == heading {
                continue
            }
            out.append(line)
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension View {
    func favoriteActions(_ item: [String: Any],
                         remove: @escaping (String) -> Void,
                         pin: @escaping ([String: Any]) -> Void,
                         forward: @escaping ([String: Any]) -> Void) -> some View {
        swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if let id = item["id"] as? String, !id.hasPrefix("local-") {
                Button(role: .destructive) {
                    remove(id)
                } label: {
                    Label(Tr("删除"), systemImage: "trash")
                }
                Button {
                    pin(item)
                } label: {
                    Label((item["pinned"] as? Bool) == true ? Tr("取消置顶") : Tr("置顶"),
                          systemImage: (item["pinned"] as? Bool) == true ? "pin.slash" : "pin")
                }
                .tint(.orange)
            }
        }
        .contextMenu {
            if let id = item["id"] as? String, !id.hasPrefix("local-") {
                Button {
                    forward(item)
                } label: {
                    Label(Tr("转发给朋友"), systemImage: "arrowshape.turn.up.right")
                }
                Button {
                    pin(item)
                } label: {
                    Label((item["pinned"] as? Bool) == true ? Tr("取消置顶") : Tr("置顶"),
                          systemImage: (item["pinned"] as? Bool) == true ? "pin.slash" : "pin")
                }
                Button(role: .destructive) {
                    remove(id)
                } label: {
                    Label(Tr("删除"), systemImage: "trash")
                }
            }
        }
    }
}

struct StickerViewOld: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var shop: [StickerPack] = []
    @State private var mine = StickerMine()

    @State private var installedIds: [String] = StickerLib.ids
    @State private var openPackId: String?
    @State private var confirmRemove: String?
    @State private var addingPhoto = false
    @State private var loading = true

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("表情"), back: { dismiss() })

            ScrollView {
                VStack(spacing: 0) {

                    sectionTitle(Tr("我的表情"))

                    if !mine.recentList.isEmpty {
                        packRow(icon: "🕘", name: Tr("最近使用"), count: mine.recentList.count)
                            .opacity(0.9)
                        HairLine(inset: 56)
                    }

                    if mine.packList.isEmpty && mine.singleList.isEmpty {
                        Text(Tr("还没有添加表情，去下面的「表情商店」加几个"))
                            .font(pf(13.5))
                            .foregroundColor(C.subLabel)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 18)
                            .background(C.cardBg)
                    }

                    ForEach(mine.packList, id: \.self) { p in
                        Button { openPackId = p.id } label: {
                            packRow(icon: p.icon ?? "😀", name: p.name ?? "表情包",
                                    count: (p.stickers ?? []).count)
                        }
                        .buttonStyle(.plain)
                        HairLine(inset: 56)
                    }

                    ForEach(mineBuiltin, id: \.id) { p in
                        builtinRow(p, added: true)
                        HairLine(inset: 56)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(Tr("添加的单个表情"))
                                .font(pf(15)).foregroundColor(C.label)
                            Spacer()
                            Button { addingPhoto = true } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus")
                                    Text(Tr("添加"))
                                }
                                .font(pf(14)).foregroundColor(C.green)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 44)

                        if !mine.singleList.isEmpty {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                                ForEach(mine.singleList, id: \.self) { s in
                                    Button { confirmRemove = s } label: {
                                        Group {
                                            if s.hasPrefix("http") || s.hasPrefix("/uploads") {
                                                RemoteImage(path: s, maxSide: 400)
                                            } else {
                                                Text(s).font(pf(28))
                                            }
                                        }
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 62)
                                        .background(RoundedRectangle(cornerRadius: 8).fill(C.searchBg))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 14)
                        }
                    }
                    .background(C.cardBg)

                    Spacer().frame(height: 14)

                    sectionTitle(Tr("表情商店"))
                    ForEach(shop, id: \.self) { p in
                        VStack(spacing: 0) {
                            HStack(spacing: 12) {
                                Text(p.icon ?? "😀").font(pf(26))
                                    .frame(width: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name ?? "表情包").font(pf(16)).foregroundColor(C.label)
                                    Text(Lang.isEnglish ? "\((p.stickers ?? []).count) stickers"
                                                       : "\((p.stickers ?? []).count) 个表情")
                                        .font(pf(12.5)).foregroundColor(C.subLabel)
                                }
                                Spacer(minLength: 8)
                                if isAdded(p) {
                                    Button { removePack(p) } label: {
                                        Text(Tr("移除"))
                                            .font(pf(14)).foregroundColor(C.subLabel)
                                            .padding(.horizontal, 12).frame(height: 28)
                                            .background(RoundedRectangle(cornerRadius: 5).fill(C.searchBg))
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    Button { addPack(p) } label: {
                                        Text(Tr("添加"))
                                            .font(pf(14, .medium)).foregroundColor(.white)
                                            .padding(.horizontal, 12).frame(height: 28)
                                            .background(RoundedRectangle(cornerRadius: 5).fill(C.green))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 62)
                            HairLine(inset: 56)
                        }
                        .background(C.cardBg)
                    }

                    ForEach(shopBuiltin, id: \.id) { p in
                        builtinRow(p, added: false)
                    }

                    Spacer().frame(height: 30)
                }
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea(edges: .bottom))
        .background(C.pageBg.ignoresSafeArea(edges: .top))
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .task { await load() }
        .sheet(isPresented: Binding(get: { openPackId != nil },
                                    set: { if !$0 { openPackId = nil } })) {
            if let p = (mine.packList + shop).first(where: { $0.id == openPackId }) {
                packDetail(p)
            }
        }
        .sheet(isPresented: $addingPhoto) {
            PhotoPicker { image in addSingle(image) }
        }
        .confirmationDialog(Tr("删除这个表情？"), isPresented: Binding(
            get: { confirmRemove != nil },
            set: { if !$0 { confirmRemove = nil } }
        ), titleVisibility: .visible) {
            Button(Tr("删除"), role: .destructive) {
                if let s = confirmRemove { removeSingle(s) }
                confirmRemove = nil
            }
            Button(Tr("取消"), role: .cancel) { confirmRemove = nil }
        }
    }

    private func sectionTitle(_ t: String) -> some View {
        HStack {
            Text(t).font(pf(13)).foregroundColor(C.subLabel)
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 30)
        .background(C.pageBg)
    }

    private var mineBuiltin: [BuiltinPack] {
        installedIds.compactMap { id in BuiltinPacks.all.first(where: { $0.id == id }) }
    }

    private var shopBuiltin: [BuiltinPack] {
        BuiltinPacks.all.filter { !installedIds.contains($0.id) }
    }

    private func builtinRow(_ p: BuiltinPack, added: Bool) -> some View {
        HStack(spacing: 12) {
            Text(p.icon).font(pf(26)).frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.name).font(pf(16)).foregroundColor(C.label)
                Text(Lang.isEnglish ? "\(p.stickers.count) stickers" : "\(p.stickers.count) 个表情")
                    .font(pf(12.5)).foregroundColor(C.subLabel)
            }
            Spacer(minLength: 8)
            Button {
                if added { StickerLib.remove(p.id) } else { StickerLib.add(p.id) }
                installedIds = StickerLib.ids
            } label: {
                Text(added ? Tr("移除") : Tr("添加"))
                    .font(pf(14, added ? .regular : .medium))
                    .foregroundColor(added ? C.subLabel : .white)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 5).fill(added ? C.searchBg : C.green))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: 62)
        .background(C.cardBg)
    }

    private func packRow(icon: String, name: String, count: Int) -> some View {
        HStack(spacing: 12) {
            Text(icon).font(pf(24)).frame(width: 40)
            Text(name).font(pf(16)).foregroundColor(C.label)
            Spacer(minLength: 8)
            Text(Lang.isEnglish ? "\(count) items" : "\(count) 个").font(pf(13)).foregroundColor(C.subLabel)
            Chevron(size: 9, line: 1.6)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(C.cardBg)
        .contentShape(Rectangle())
    }

    private func packDetail(_ p: StickerPack) -> some View {
        VStack(spacing: 0) {
            NavBar(title: p.name ?? "表情包", back: { openPackId = nil })
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                    ForEach((p.stickers ?? []).indices, id: \.self) { i in
                        let s = (p.stickers ?? [])[i]
                        Group {
                            if s.hasPrefix("http") || s.hasPrefix("/uploads") {
                                RemoteImage(path: s, maxSide: 400)
                            } else {
                                Text(s).font(pf(34))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 72)
                        .background { CardGlassBox(radius: 8) }
                    }
                }
                .padding(16)
            }
            Button {
                removePack(p)
                openPackId = nil
            } label: {
                Text(Tr("移除这个表情包"))
                    .font(pf(16)).foregroundColor(C.red)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(C.cardBg)
            }
            .buttonStyle(.plain)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .hidesTabBar()
    }

    private func load() async {
        if let r = try? await API.shared.stickerShop() {
            shop = r.shop
            mine = r.mine
        }
        loading = false
    }

    private func isAdded(_ p: StickerPack) -> Bool {
        guard let id = p.id else { return false }
        return mine.packList.contains { $0.id == id }
    }

    private func addPack(_ p: StickerPack) {
        guard let id = p.id else { return }
        Task {
            await API.shared.addStickerPack(id)
            await load()
            app.show(Tr("已添加"))
        }
    }

    private func removePack(_ p: StickerPack) {
        guard let id = p.id else { return }
        Task {
            await API.shared.removeStickerPack(id)
            await load()
            app.show(Tr("已移除"))
        }
    }

    private func addSingle(_ image: UIImage) {
        Task {
            guard let url = try? await API.shared.upload(image: image) else { return }
            await API.shared.addSingleSticker(url)
            await load()
            app.show(Tr("已添加到我的表情"))
        }
    }

    private func removeSingle(_ s: String) {
        Task {
            await API.shared.removeSingleSticker(s)
            await load()
            app.show(Tr("已删除"))
        }
    }
}

struct StatusView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var cats: [StatusCategory] = []
    @State private var picked: StatusItem? = nil
    @State private var pickedColor = ""
    @State private var caption = ""
    @State private var saving = false
    @FocusState private var typing: Bool

    @State private var myStatus: MyStatus? = nil

    private var hasMood: Bool {
        !((app.me?.moodText ?? "").isEmpty && (app.me?.moodIcon ?? "").isEmpty)
    }

    private let cols = [GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("状态"), back: { dismiss() }) {
                Button { save() } label: {
                    Text(Tr("就这样"))
                        .font(pf(15, .medium))
                        .foregroundColor(picked == nil ? C.subLabel : C.green)
                        .padding(.horizontal, 16)
                        .frame(height: L.navH)
                }
                .buttonStyle(.plain)
                .disabled(picked == nil || saving)
            }

            ScrollView {
                VStack(spacing: 10) {
                    composeRow
                    if hasMood, let ms = myStatus { myStatusCard(ms) }
                    ForEach(cats.indices, id: \.self) { i in
                        section(cats[i])
                    }
                    if hasMood { endRow }
                    Spacer().frame(height: 30)
                }
                .padding(.top, 10)
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea(edges: .top))
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .task {
            await load()
            myStatus = try? await API.shared.myStatus()
        }
    }

    private func myStatusCard(_ ms: MyStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(ms.moodIcon ?? "").font(pf(18))
                Text(ms.moodText ?? "").font(pf(15, .medium)).foregroundColor(C.label)
                Spacer(minLength: 6)
                if let h = ms.hoursLeft {
                    Text(h <= 0 ? Tr("马上过期") : (Tr("还剩 ") + "\(h)" + Tr(" 小时")))
                        .font(pf(12.5)).foregroundColor(C.subLabel)
                }
            }
            if let views = ms.views, !views.isEmpty {
                Text(Tr("谁看过我的状态") + "（\(views.count)）")
                    .font(pf(12.5)).foregroundColor(C.subLabel)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(views, id: \.self) { v in
                            VStack(spacing: 4) {
                                Avatar(path: v.avatar ?? "", size: 36, radius: 18)
                                Text(v.name ?? "").font(pf(11)).foregroundColor(C.subLabel).lineLimit(1)
                            }
                            .frame(width: 46)
                        }
                    }
                }
            } else {
                Text(Tr("还没有人看过")).font(pf(12.5)).foregroundColor(C.subLabel)
            }
        }
        .padding(14)

        .background(
            ZStack {
                C.cardBg
                if !statusTint.isEmpty {
                    Color(hexString: statusTint).opacity(0.10)
                }
            }
        )
        .overlay(alignment: .leading) {
            if !statusTint.isEmpty {
                Capsule().fill(Color(hexString: statusTint)).frame(width: 3).padding(.vertical, 12)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
        .padding(.horizontal, 12)
    }

    private var statusTint: String {
        let c = MoodColor.clean(app.me?.moodColor)
        if !c.isEmpty { return c }
        return MoodColor.clean(myStatus?.moodColor)
    }

    private var composeRow: some View {
        HStack(spacing: 10) {
            moodBox
            TextField("", text: $caption, prompt: Text(Tr("说点什么…")).foregroundColor(C.subLabel))
                .font(pf(14.5))
                .foregroundColor(C.label)
                .focused($typing)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Capsule().fill(C.fieldBg))
                .onChange(of: caption) { v in
                    if v.count > 30 { caption = String(v.prefix(30)) }
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)

        .background(C.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
        .padding(.horizontal, 12)
    }

    private var moodBox: some View {
        let icon = picked?.icon ?? ""
        let on = picked != nil
        return ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(on ? AnyShapeStyle(tileGradient(picked?.color ?? pickedColor))
                         : AnyShapeStyle(C.cardBg))
                .frame(width: 44, height: 44)
            if on {
                Text(icon.isEmpty ? "🙂" : icon).font(pf(22))
            } else {
                Text("＋").font(pf(20)).foregroundColor(C.subLabel)
            }
        }
    }

    private func section(_ c: StatusCategory) -> some View {
        let title = c.name ?? ""
        let items = c.items ?? []
        let catColor = MoodColor.clean(c.color)
        return VStack(alignment: .leading, spacing: 12) {

            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hexString: catColor.isEmpty ? "#8A8F99" : catColor))
                    .frame(width: 6, height: 6)
                Text(Tr(title))
                    .font(pf(13, .medium))
                    .foregroundColor(C.subLabel)
                Spacer(minLength: 0)
            }
            .padding(.leading, 16)
            LazyVGrid(columns: cols, spacing: 10) {
                ForEach(items, id: \.self) { it in
                    tile(it, fallback: catColor)
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.top, 14)
        .padding(.bottom, 16)
        .background(C.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 12)
    }

    private func tile(_ it: StatusItem, fallback: String) -> some View {
        let own = MoodColor.clean(it.color)
        let base = own.isEmpty ? (fallback.isEmpty ? "#6F8A38" : fallback) : own
        let on = (picked?.id ?? "-") == (it.id ?? "?")
        return Button { pick(it, base: base) } label: {
            VStack(spacing: 7) {

                ZStack {
                    Circle().fill(Color.white.opacity(0.22)).frame(width: 34, height: 34)
                    Text(it.icon ?? "🙂").font(pf(19))
                }
                Text(Tr(it.label ?? "状态"))
                    .font(pf(12.5, .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 86)
            .background(tileGradient(base))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white, lineWidth: on ? 2 : 0))
            .overlay(alignment: .topTrailing) {
                if on {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                        .background(Circle().fill(Color.black.opacity(0.18)).frame(width: 15, height: 15))
                        .padding(6)
                }
            }
            .shadow(color: Color.black.opacity(0.10), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }

    private func tileGradient(_ raw: String) -> LinearGradient {
        let c1 = MoodColor.clean(raw)
        let base = c1.isEmpty ? "#6F8A38" : c1
        let c2 = MoodColor.shift(base, to: true)
        let c3 = MoodColor.shift(base, to: false)

        return LinearGradient(colors: [Color(hexString: c3.isEmpty ? base : c3),
                                       Color(hexString: base),
                                       Color(hexString: c2.isEmpty ? base : c2)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var endRow: some View {
        Button { endMood() } label: {
            Text(Tr("结束状态"))
                .font(pf(15.5))
                .foregroundColor(C.red)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(C.cardBg)
        }
        .buttonStyle(.plain)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 12)
    }

    private func load() async {
        cats = (try? await API.shared.statusCategories()) ?? []
        if hasMood {
            pickedColor = MoodColor.clean(app.me?.moodColor)
            caption = app.me?.moodCaption ?? ""
        }
    }

    private func pick(_ it: StatusItem, base: String) {
        picked = it
        pickedColor = base
        typing = true
    }

    private func save() {
        guard let it = picked, !saving else { return }
        saving = true
        Task {
            await API.shared.setMood(it, caption: caption, fallbackColor: pickedColor)
            app.me = try? await API.shared.me()
            app.show(Tr("状态更新了"))
            saving = false
            dismiss()
        }
    }

    private func endMood() {
        Task {
            await API.shared.setMood(nil)
            app.me = try? await API.shared.me()
            app.show(Tr("状态已取消"))
            dismiss()
        }
    }
}

struct StatusDetailView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var info: MyStatus? = nil
    @State private var editing = false

    private var icon: String { info?.moodIcon ?? app.me?.moodIcon ?? "" }
    private var label: String { info?.moodLabel ?? app.me?.moodLabel ?? app.me?.moodText ?? "" }
    private var note: String { info?.moodCaption ?? app.me?.moodCaption ?? "" }
    private var c1: String {
        let mine = MoodColor.clean(info?.moodColor)
        return mine.isEmpty ? MoodColor.clean(app.me?.moodColor) : mine
    }
    private var c2: String {
        let mine = MoodColor.clean(info?.moodColor2)
        return mine.isEmpty ? MoodColor.clean(app.me?.moodColor2) : mine
    }
    private var viewers: [StatusViewer] { info?.views ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("我的状态"), back: { dismiss() }) {
                Button { editing = true } label: {
                    Text(Tr("更改状态"))
                        .font(pf(15))
                        .foregroundColor(C.green)
                        .padding(.horizontal, 16)
                        .frame(height: L.navH)
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                VStack(spacing: 12) {
                    bigCard
                    viewersCard
                    Spacer().frame(height: 20)
                }
                .padding(.top, 12)
            }
            .background(C.pageBg)

            endButton
        }
        .background(C.pageBg.ignoresSafeArea(edges: .top))
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .sheet(isPresented: $editing) { StatusView() }
        .task { await reload() }
        .onChange(of: editing) { on in
            if !on { Task { await reload() } }
        }
    }

    private var bigCard: some View {
        let base = c1.isEmpty ? "#5B7F42" : c1
        let second = c2.isEmpty ? MoodColor.shift(base, to: true) : c2
        return VStack(spacing: 10) {
            Text(icon.isEmpty ? "🙂" : icon).font(pf(44))
            if !label.isEmpty {
                Text(Tr(label)).font(pf(17, .medium)).foregroundColor(.white).lineLimit(1)
            }
            if !note.isEmpty {
                Text(note).font(pf(13.5)).foregroundColor(.white.opacity(0.92))
                    .multilineTextAlignment(.center).lineLimit(3)
            }
            Text(leftText).font(pf(11.5)).foregroundColor(.white.opacity(0.82))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 18)
        .background(LinearGradient(colors: [Color(hexString: base),
                                            Color(hexString: second.isEmpty ? base : second)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 12)
    }

    private var leftText: String {
        let h = info?.hoursLeft ?? 0
        if h <= 0 { return Tr("24 小时后自动结束（不到 1 小时）") }
        return "24 小时后自动结束 · 还剩 \(h) 小时"
    }

    private var viewersCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(Tr("谁看过我"))
                    .font(pf(14, .medium))
                    .foregroundColor(C.label)
                Spacer(minLength: 0)
                Text(Lang.isEnglish ? "\(info?.viewerCount ?? viewers.count) viewers"
                                    : "\(info?.viewerCount ?? viewers.count) 人")
                    .font(pf(13))
                    .foregroundColor(C.subLabel)
            }
            .padding(.horizontal, 15)
            .frame(height: 46)
            HairLine(inset: 15)
            if viewers.isEmpty {
                Text(Tr("还没有人看过你的状态"))
                    .font(pf(13))
                    .foregroundColor(C.subLabel)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 18)
            } else {
                ForEach(viewers, id: \.self) { v in
                    viewerRow(v)
                }
            }
        }
        .background(C.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 12)
    }

    private func viewerRow(_ v: StatusViewer) -> some View {
        HStack(spacing: 10) {
            Avatar(path: v.avatar ?? "", size: 34, radius: 17, circle: true)
            Text(v.name ?? "好友")
                .font(pf(15))
                .foregroundColor(C.label)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(TimeFmt.list(v.at))
                .font(pf(12))
                .foregroundColor(C.subLabel)
                .fixedSize()
        }
        .padding(.horizontal, 15)
        .frame(height: 54)
    }

    private var endButton: some View {
        Button { endIt() } label: {
            Text(Tr("结束状态"))
                .font(pf(15.5))
                .foregroundColor(C.red)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(C.cardBg)
        }
        .buttonStyle(.plain)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, max(10, L.safeBottom))
    }

    private func reload() async {
        info = try? await API.shared.myStatus()
        app.me = try? await API.shared.me()
    }

    private func endIt() {
        Task {
            await API.shared.endMyStatus()
            app.me = try? await API.shared.me()
            app.show(Tr("状态已取消"))
            dismiss()
        }
    }
}

struct FriendStatusView: View {
    @Environment(\.dismiss) private var dismiss
    let user: User

    private var base: String {
        let c = MoodColor.clean(user.moodColor)
        return c.isEmpty ? "#5B7F42" : c
    }
    private var second: String {
        let c = MoodColor.clean(user.moodColor2)
        return c.isEmpty ? MoodColor.shift(base, to: true) : c
    }
    private var label: String {
        let l = (user.moodLabel ?? "").trimmingCharacters(in: .whitespaces)
        return l.isEmpty ? (user.moodText ?? "") : l
    }
    private var note: String { user.moodCaption ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("状态"), back: { dismiss() })
            ScrollView {
                VStack(spacing: 14) {
                    VStack(spacing: 10) {
                        Text(user.moodIcon ?? "🙂").font(pf(46))
                        if !label.isEmpty {
                            Text(Tr(label)).font(pf(17, .medium)).foregroundColor(.white)
                        }
                        if !note.isEmpty {
                            Text(note).font(pf(13.5)).foregroundColor(.white.opacity(0.92))
                                .multilineTextAlignment(.center)
                        }
                        Text(leftText).font(pf(11.5)).foregroundColor(.white.opacity(0.82))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .padding(.horizontal, 18)
                    .background(LinearGradient(colors: [Color(hexString: base),
                                                        Color(hexString: second.isEmpty ? base : second)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 12)
                    Spacer().frame(height: 20)
                }
                .padding(.top, 12)
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea(edges: .top))
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
    }

    private var leftText: String {
        let exp = Double(user.moodExpiresAt ?? 0)
        guard exp > 0 else { return Tr("24 小时内有效") }
        let left = (exp - Date().timeIntervalSince1970 * 1000) / 3600000
        if left <= 0 { return Tr("已经结束了") }
        if left < 1 { return Tr("24 小时内有效（不到 1 小时）") }
        return "24 小时内有效 · 还剩 \(Int(left.rounded())) 小时"
    }
}

struct FriendsStatusView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var picked: User? = nil

    @State private var bursting: String = ""

    @State private var localLikes: [String: Int] = [:]
    @State private var localMine: [String: Bool] = [:]

    @State private var listening: [String: FriendNowPlaying] = [:]

    private var list: [User] {
        app.contacts.filter { u in
            !((u.moodText ?? "").isEmpty && (u.moodIcon ?? "").isEmpty)
        }
    }

    var body: some View {
        VStack(spacing: 0) {

            ZStack {
                NavBar(title: UIConfig.text("friendsStatusTitle", ""), back: { dismiss() })
                if UIConfig.text("friendsStatusTitle", "").isEmpty {
                    StatusRingIcon()
                        .allowsHitTesting(false)
                }
            }

            if list.isEmpty {
                VStack(spacing: 10) {
                    Text("🙂").font(pf(30))
                    Text(Tr("朋友们现在都没挂状态")).font(pf(15)).foregroundColor(C.label)
                    Text(Tr("等好友在「我 → 状态」里挂一个，这里就会显示"))
                        .font(pf(12.5)).foregroundColor(C.subLabel)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 70)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {

                        ForEach(sections) { sec in
                            dayHeader(sec.day)
                            ForEach(sec.groups) { g in
                                groupHeader(g)
                                ForEach(g.users) { u in
                                    Button { picked = u } label: { row(u) }
                                        .buttonStyle(.plain)
                                    HairLine(inset: 72)
                                }
                            }
                        }
                    }
                    Spacer().frame(height: 30)
                }
                .background(C.pageBg)
            }
        }
        .background(C.pageBg.ignoresSafeArea(edges: .top))
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .sheet(item: $picked) { u in
            NavigationStack { FriendStatusView(user: u).environmentObject(app) }
        }
        .task {
            if let list = await API.shared.friendsNowPlaying() {
                var m: [String: FriendNowPlaying] = [:]
                for f in list { m[f.id] = f }
                listening = m
            }
        }
    }

    private func row(_ u: User) -> some View {
        return HStack(spacing: 12) {
            Avatar(path: u.avatarPath, size: 40, radius: 5)
            VStack(alignment: .leading, spacing: 3) {
                Text(u.name).font(pf(16)).foregroundColor(C.label).lineLimit(1)
                if let f = listening[u.id] {

                    HStack(spacing: 4) {
                        Image(systemName: "music.note").font(.system(size: 10.5))
                        Text(Tr("在听《") + f.title + "》").lineLimit(1)
                    }
                    .font(pf(12))
                    .foregroundColor(Color(hex: 0x576B95))
                }
                Text(left(u)).font(pf(12)).foregroundColor(C.subLabel).lineLimit(1)
            }
            Spacer(minLength: 6)

            Button { like(u) } label: {
                ZStack {
                    Image(systemName: liked(u) ? "heart.fill" : "heart")
                        .font(.system(size: 17))
                        .foregroundColor(liked(u) ? Color(hex: 0xFF4868) : C.subLabel)
                    if bursting == u.id { HeartBurst() }
                    if likeCount(u) > 0 {
                        Text("\(likeCount(u))")
                            .font(pf(10))
                            .foregroundColor(C.subLabel)
                            .offset(x: 13, y: 9)
                    }
                }
                .frame(width: 42, height: 42)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text(u.moodIcon ?? "").font(pf(18))
        }
        .padding(.horizontal, 16)
        .frame(height: 62)
        .contentShape(Rectangle())
    }

    private func liked(_ u: User) -> Bool {
        if let v = localMine[u.id] { return v }
        return (u.moodLikes ?? []).contains(app.me?.id ?? "")
    }

    private func likeCount(_ u: User) -> Int {
        if let n = localLikes[u.id] { return n }
        return u.moodLikeCount ?? (u.moodLikes ?? []).count
    }

    private func like(_ u: User) {
        let now = !liked(u)
        localMine[u.id] = now
        localLikes[u.id] = max(0, likeCount(u) + (now ? 1 : -1))
        if now { bursting = u.id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            if bursting == u.id { bursting = "" }
        }
        Task {
            if let r = await API.shared.statusLike(u.id) {
                localMine[u.id] = r.liked
                localLikes[u.id] = r.count
            }
            await app.loadContacts()
        }
    }

    private struct StatusGroup: Identifiable {
        var id: String { key }
        var key: String
        var icon: String
        var users: [User]
    }

    private struct DaySection: Identifiable {
        var id: String { day }
        var day: String
        var groups: [StatusGroup]
    }

    private var sections: [DaySection] {
        var order: [String] = []
        var byDay: [String: [User]] = [:]
        for u in list.sorted(by: { setAt($0) > setAt($1) }) {
            let d = dayOf(setAt(u))
            if byDay[d] == nil { byDay[d] = []; order.append(d) }
            byDay[d]?.append(u)
        }
        return order.map { d in
            let users = byDay[d] ?? []
            var gOrder: [String] = []
            var byKey: [String: StatusGroup] = [:]
            for u in users {
                let label = ((u.moodLabel ?? "").isEmpty ? (u.moodText ?? "") : (u.moodLabel ?? ""))
                let key = label.isEmpty ? Tr("状态") : label
                if byKey[key] == nil {
                    byKey[key] = StatusGroup(key: key, icon: u.moodIcon ?? "", users: [])
                    gOrder.append(key)
                }
                byKey[key]?.users.append(u)
            }
            return DaySection(day: d, groups: gOrder.compactMap { byKey[$0] })
        }
    }

    private func setAt(_ u: User) -> Double {
        let exp = Double(u.moodExpiresAt ?? 0)
        return exp > 0 ? (exp - 24 * 3600 * 1000) : 0
    }

    private func dayOf(_ ms: Double) -> String {
        guard ms > 0 else { return Tr("更早") }
        let d = Date(timeIntervalSince1970: ms / 1000)
        let cal = Calendar.current
        if cal.isDateInToday(d) { return Tr("今天") }
        if cal.isDateInYesterday(d) { return Tr("昨天") }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: d),
                                      to: cal.startOfDay(for: Date())).day ?? 99
        if days == 2 { return Tr("前天") }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = cal.isDate(d, equalTo: Date(), toGranularity: .year) ? "M月d日" : "yyyy年M月d日"
        return f.string(from: d)
    }

    private func dayHeader(_ t: String) -> some View {
        HStack {
            Text(t).font(pf(13)).foregroundColor(C.subLabel)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 6)
    }

    private func groupHeader(_ g: StatusGroup) -> some View {
        HStack(spacing: 5) {
            if !g.icon.isEmpty { Text(g.icon).font(pf(14)) }
            Text("\(g.users.count) " + Tr("个朋友在") + g.key)
                .font(pf(14))
                .foregroundColor(Color(hex: 0x576B95))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private func left(_ u: User) -> String {
        let exp = Double(u.moodExpiresAt ?? 0)
        guard exp > 0 else { return "" }
        let h = (exp - Date().timeIntervalSince1970 * 1000) / 3600000
        if h <= 0 { return "" }
        if h < 1 { return Tr("还剩不到 1 小时") }
        return Tr("还剩 ") + String(Int(h.rounded())) + Tr(" 小时")
    }
}

struct StatusRingIcon: View {
    var size: CGFloat = 26
    var color: Color = C.label

    var body: some View {
        Circle()
            .trim(from: 0.04, to: 0.96)
            .stroke(color, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .frame(width: size, height: size)
    }
}

struct HeartBurst: View {
    var intensity: CGFloat = 1.15
    @State private var t: CGFloat = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [
                            Color(hex: 0xFF315A), Color(hex: 0xFF86A2),
                            Color(hex: 0xFFC45C), Color(hex: 0xFF315A)
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 2.2 * intensity, lineCap: .round)
                )
                .frame(width: 20, height: 20)
                .scaleEffect(0.45 + t * 5.6 * intensity)
                .opacity(Double(1 - t) * 0.78)

            Circle()
                .fill(RadialGradient(
                    colors: [.white.opacity(0.72), Color(hex: 0xFF7792).opacity(0.18), .clear],
                    center: .center,
                    startRadius: 1,
                    endRadius: 28 * intensity
                ))
                .frame(width: 58 * intensity, height: 58 * intensity)
                .scaleEffect(0.25 + t * 1.35)
                .opacity(Double(1 - t) * 0.66)

            ZStack {
                Image(systemName: "heart.fill")
                    .font(.system(size: 18 * intensity, weight: .bold))
                    .foregroundStyle(LinearGradient(
                        colors: [Color(hex: 0xFF8FA6), Color(hex: 0xFF3D62), Color(hex: 0xE9204C)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .shadow(color: Color(hex: 0xFF3158).opacity(0.50),
                            radius: 9 * intensity, y: 2)

                Image(systemName: "sparkle")
                    .font(.system(size: 5.5 * intensity, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92))
                    .offset(x: -3.6 * intensity, y: -3.8 * intensity)
            }
            .scaleEffect(1 + t * 2.15)
            .opacity(Double(1 - t))

            ForEach(0..<22, id: \.self) { i in
                let angle = Double(i) / 22 * 2 * Double.pi + Double(i % 3) * 0.11
                let distance = CGFloat(15 + (i % 5) * 3)
                    + t * CGFloat(48 + (i % 4) * 10) * intensity
                Group {
                    if i % 6 == 0 {
                        Image(systemName: "sparkle")
                            .font(.system(size: 8.5 * intensity, weight: .bold))
                            .foregroundStyle(Color(hex: i % 2 == 0 ? 0xFFD36A : 0xFFFFFF))
                    } else if i % 5 == 0 {
                        Circle()
                            .fill(Color(hex: 0xFFD978))
                            .frame(width: 3.2 * intensity, height: 3.2 * intensity)
                    } else {
                        Image(systemName: "heart.fill")
                            .font(.system(size: (i % 3 == 0 ? 8 : 10) * intensity,
                                           weight: .bold))
                            .foregroundStyle(i % 2 == 0
                                             ? Color(hex: 0xFF4F72)
                                             : Color(hex: 0xFF9BB0))
                    }
                }
                    .rotationEffect(.degrees(Double(t) * Double(45 + i * 13)))
                    .scaleEffect(1.12 - t * 0.46)
                    .offset(x: CGFloat(cos(angle)) * distance,
                            y: CGFloat(sin(angle)) * distance - t * 7 * intensity)
                    .opacity(Double(1 - t))
            }

            ForEach(0..<8, id: \.self) { i in
                Capsule()
                    .fill(i % 2 == 0
                          ? Color(hex: 0xFF6F8D).opacity(0.72)
                          : Color(hex: 0xFFC65C).opacity(0.64))
                    .frame(width: 1.7 * intensity, height: 8 * intensity)
                    .offset(y: -(21 * intensity + t * 66 * intensity))
                    .rotationEffect(.degrees(Double(i) / 8 * 360))
                    .opacity(Double(1 - t) * 0.72)
            }
        }
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeOut(duration: 0.86)) { t = 1 }
        }
    }
}

struct WalletCardView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("卡包"), back: { dismiss() })
            ScrollView {
                VStack(spacing: 0) {
                    GroupCard {
                        row("零钱", "¥\(moneyFmt(app.me?.balance ?? 0))")
                        HairLine(inset: 16)
                        row("建设银行储蓄卡", "尾号 2125")
                        HairLine(inset: 16)
                        row("单笔转账限额", "¥20000")
                    }
                    .padding(.top, 8)
                    Spacer().frame(height: 30)
                }
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea(edges: .top))
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(pf(17)).foregroundColor(C.label)
            Spacer()
            Text(value).font(pf(15)).foregroundColor(C.subLabel)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }
}

struct WorksView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var works: [FeedItem] = []
    @State private var playing: FeedItem?
    @State private var loading = true

    private let cols = [GridItem(.flexible(), spacing: 3), GridItem(.flexible(), spacing: 3), GridItem(.flexible(), spacing: 3)]

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("作品"), back: { dismiss() })
            if loading && works.isEmpty {
                Spacer(); ProgressView(); Spacer()
            } else if works.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "rectangle.stack").font(pf(34)).foregroundColor(C.subLabel)
                    Text(Tr("还没有作品")).font(pf(15)).foregroundColor(C.subLabel)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: cols, spacing: 3) {
                        ForEach(works) { w in
                            Button { playing = w } label: { tile(w) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 20)
                }
                .background(C.pageBg)
            }
        }
        .background(C.pageBg.ignoresSafeArea(edges: .bottom))
        .background(C.pageBg.ignoresSafeArea(edges: .top))
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .sheet(item: $playing) { w in
            FeedPlayerSheet(item: w, all: works)
        }
        .task {

            let mine = (try? await API.shared.myFeedItems()) ?? []
            works = mine.isEmpty ? ((try? await API.shared.feedItems()) ?? []).filter { $0.mine == true } : mine
            loading = false
        }
    }

    private func tile(_ w: FeedItem) -> some View {
        ZStack {
            if !(w.cover ?? "").isEmpty {
                RemoteImage(path: w.cover ?? "")
            } else {
                LinearGradient(colors: [Color(hex: 0x2A2A2E), Color(hex: 0x141416)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            if (w.cover ?? "").isEmpty {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 26))
                    .foregroundColor(.white.opacity(0.85))
            }
            VStack {
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "play.fill").font(.system(size: 10))
                    Text("\(w.likes ?? 0)").font(pf(11.5, .medium))
                    Spacer(minLength: 0)
                    if w.mine == true {
                        Text(Tr("我的")).font(pf(10.5)).padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(C.green))
                    }
                }
                .foregroundColor(.white)
                .padding(.horizontal, 6).padding(.vertical, 4)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom))
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .contentShape(Rectangle())
    }
}
