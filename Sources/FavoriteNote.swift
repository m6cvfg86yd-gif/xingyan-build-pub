import SwiftUI

struct FavoriteNoteComposeSheet: View {
    typealias SaveHandler = (String, String, Bool) -> Void

    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    let editingId: String
    let initial: String
    let onSaved: SaveHandler

    @State private var titleText = ""
    @State private var bodyText = ""
    @State private var busy = false
    @State private var msg = ""
    @FocusState private var focused: Bool
    @State private var showPic = false
    @State private var picBusy = false
    @State private var pics: [String] = []

    init(editingId: String = "", initial: String = "", onSaved: @escaping SaveHandler) {
        self.editingId = editingId
        self.initial = initial
        self.onSaved = onSaved

        var body: [String] = []
        var imgs: [String] = []
        for line in initial.components(separatedBy: "\n") {
            if line.hasPrefix("[图]") { imgs.append(String(line.dropFirst(3))) }
            else { body.append(line) }
        }
        while body.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            body.removeFirst()
        }
        let title = body.first ?? ""
        _titleText = State(initialValue: title.trimmingCharacters(in: .whitespacesAndNewlines))
        _bodyText = State(initialValue: body.dropFirst().joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines))
        _pics = State(initialValue: imgs)
    }

    private var canSave: Bool {
        !titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !pics.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField(Tr("标题"), text: $titleText, axis: .vertical)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1...3)
                    .padding(.horizontal, 18)
                    .padding(.top, 12)

                Divider().padding(.horizontal, 18)

                ZStack(alignment: .topLeading) {
                    if bodyText.isEmpty {
                        Text(Tr("开始输入…"))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 18)
                            .padding(.top, 12)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $bodyText)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 13)
                        .padding(.top, 4)
                        .focused($focused)
                }

                if !pics.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
                        ForEach(pics, id: \.self) { p in
                            ZStack(alignment: .topTrailing) {
                                RemoteImage(path: p, mode: .fill, maxSide: 600)
                                    .frame(height: 88)
                                    .frame(maxWidth: .infinity)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                Button { pics.removeAll { $0 == p } } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 17))
                                        .foregroundColor(.white)
                                        .shadow(color: .black.opacity(0.35), radius: 1.5)
                                        .padding(4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 12)
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle(editingId.isEmpty ? Tr("新建备忘录") : Tr("编辑备忘录"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Tr("取消")) { dismiss() }
                        .disabled(busy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if busy {
                            ProgressView()
                        } else {
                            Text(Tr("完成")).fontWeight(.semibold)
                        }
                    }
                    .disabled(busy || !canSave)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if !msg.isEmpty {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 18)
                            .padding(.bottom, 6)
                    }
                    HStack(spacing: 18) {
                        Button { showPic = true } label: {
                            Image(systemName: "photo")
                        }
                        .disabled(picBusy)
                        Button {
                            bodyText += (bodyText.isEmpty ? "" : "\n") + "————————"
                        } label: {
                            Image(systemName: "minus")
                        }
                        if picBusy { ProgressView() }
                        Spacer()
                        Text("\((titleText + bodyText).count) / 20000")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 18, weight: .medium))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                }
                .background(.bar)
            }
        }
        .task {
            if editingId.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focused = true }
            }
        }
        .sheet(isPresented: $showPic) {
            PhotoPicker { img in insertImage(img) }
        }
    }

    private func insertImage(_ img: UIImage) {
        picBusy = true
        Task {
            do {
                let url = try await API.shared.upload(image: img)
                pics.append(url)
                msg = Tr("图片已插入")
            } catch {
                msg = (error as? APIError)?.errorDescription ?? "图片上传失败"
            }
            picBusy = false
        }
    }

    private func save() async {
        let cleanTitle = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        if !cleanTitle.isEmpty { parts.append(cleanTitle) }
        if !cleanBody.isEmpty { parts.append(cleanBody) }
        if !pics.isEmpty {
            let imgs = pics.map { "[图]" + $0 }.joined(separator: "\n")
            parts.append(imgs)
        }
        let body = parts.joined(separator: "\n")
        guard !body.isEmpty else { return }
        busy = true
        msg = ""

        let firstLine = cleanTitle.isEmpty
            ? (body.split(separator: "\n").first.map(String.init) ?? body)
            : cleanTitle
        let title = String(firstLine.prefix(24))

        let ok: Bool
        if editingId.isEmpty {
            ok = await API.shared.addFavorite(kind: "text", content: body, title: title, from: "")
        } else {
            ok = await API.shared.updateFavorite(id: editingId, content: body, title: title)
        }
        busy = false
        if ok {
            DiagLog.shared.note("收藏：保存了一条笔记（" + String(body.count) + " 字）")
            onSaved(body, title, !editingId.isEmpty)
            dismiss()
        } else {
            msg = Tr("保存失败，再试一次")
        }
    }
}

struct FavoriteNoteDetailSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    let id: String
    let content: String

    var pinned: Bool = false

    let onChanged: () -> Void

    @State private var editing = false
    @State private var copied = false
    @State private var isPinned = false
    @State private var showForward = false

    @State private var viewerPath: String?

    private var hasPic: Bool {
        content.components(separatedBy: "\n").contains { $0.hasPrefix("[图]") }
    }

    private var lines: [String] {
        content.components(separatedBy: "\n")
    }

    private var titleText: String {
        lines.first(where: {
            !$0.hasPrefix("[图]") && !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) ?? Tr("备忘录")
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(titleText)
                        .font(.largeTitle.bold())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    let titleIndex = lines.firstIndex(of: titleText)
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        if index == titleIndex { EmptyView() }
                        else if line.hasPrefix("[图]") {
                            NoteImageBlock(path: String(line.dropFirst(3))) { p in viewerPath = p }
                        } else if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(line)
                                .font(.body)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(Tr("（空）"))
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
            .background(Color(.systemBackground))
            .navigationTitle(Tr("备忘录"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Tr("关闭")) { dismiss() }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { editing = true } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    Menu {
                        Button {
                            UIPasteboard.general.string = content
                            copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                        } label: {
                            Label(copied ? Tr("已复制") : Tr("复制"), systemImage: "doc.on.doc")
                        }
                        Button { Task { await pin(!isPinned) } } label: {
                            Label(isPinned ? Tr("取消置顶") : Tr("置顶"),
                                  systemImage: isPinned ? "pin.slash" : "pin")
                        }
                        Button { showForward = true } label: {
                            Label(Tr("转发给朋友"), systemImage: "arrowshape.turn.up.right")
                        }
                        Divider()
                        Button(role: .destructive) { Task { await remove() } } label: {
                            Label(Tr("删除"), systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .overlay {
            if let p = viewerPath, !p.isEmpty {
                PhotoPager(paths: [p], startIndex: 0, showActions: true) { viewerPath = nil }
            }
        }
        .task { isPinned = pinned }

        .sheet(isPresented: $showForward) {

            ForwardPickerView(items: [ForwardItem(kind: hasPic ? "note" : "text", content: content)]) { }
                .environmentObject(app)
        }
        .sheet(isPresented: $editing) {
            FavoriteNoteComposeSheet(editingId: id, initial: content) { _, _, _ in
                onChanged()
                dismiss()
            }
            .environmentObject(app)
        }
    }

    private func pin(_ on: Bool) async {
        if await API.shared.updateFavorite(id: id, pinned: on) {
            isPinned = on
            DiagLog.shared.note(on ? "收藏：置顶了一条" : "收藏：取消置顶")
            onChanged()
        }
    }

    private func remove() async {
        await API.shared.deleteFavorite(id)
        DiagLog.shared.note("收藏：删掉了一条笔记")
        onChanged()
        dismiss()
    }
}
