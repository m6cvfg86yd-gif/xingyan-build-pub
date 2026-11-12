import SwiftUI
import Foundation

struct MyFilesPickerView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    var onPick: (API.MyFileItem) -> Void

    var onSystemPicker: (() -> Void)? = nil

    @State private var files: [API.MyFileItem] = []
    @State private var loading = true
    @State private var q = ""

    @State private var preview: FilePreviewData?
    @State private var openingId = ""

    private var shown: [API.MyFileItem] {
        let key = q.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return files }
        return files.filter {
            $0.fileName.localizedCaseInsensitiveContains(key)
                || ($0.chatName ?? "").localizedCaseInsensitiveContains(key)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("选择文件"), back: { dismiss() })

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(C.searchIcon)
                TextField(Tr("搜索文件名"), text: $q)
                    .font(pf(14.5))
                if !q.isEmpty {
                    Button { q = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15)).foregroundColor(C.searchIcon)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(C.searchBg))
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 6)

            if loading {
                Spacer(minLength: 0)
                ProgressView()
                Spacer(minLength: 0)
            } else if shown.isEmpty {
                Spacer(minLength: 0)
                VStack(spacing: 10) {
                    Image(systemName: "folder")
                        .font(.system(size: 34)).foregroundColor(C.time)
                    Text(q.isEmpty ? Tr("还没有发过文件。在聊天里发一个，这里就有了。")
                                   : Tr("没有找到这个文件"))
                        .font(pf(14)).foregroundColor(C.subLabel)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 40)
                Spacer(minLength: 0)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(shown) { f in
                            Button {
                                onPick(f)
                                dismiss()
                            } label: {
                                row(f)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .padding(.bottom, 16)
                }
            }

            if onSystemPicker != nil {
                Button {
                    onSystemPicker?()
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.badge.plus").font(.system(size: 15))
                        Text(Tr("从「文件」App 里挑")).font(pf(15))
                    }
                    .foregroundColor(C.link)
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(C.cardBg))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }
                .buttonStyle(.plain)
            }
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }

        .sheet(item: $preview) { f in
            FilePreviewSheet(name: f.name, local: f.local)
        }
        .task { await load() }
    }

    private func row(_ f: API.MyFileItem) -> some View {
        HStack(spacing: 12) {
            Text(f.ext.isEmpty ? "FILE" : f.ext.uppercased())
                .font(pfExact(11, .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(fileColor(f.ext)))
            VStack(alignment: .leading, spacing: 3) {
                Text(f.fileName)
                    .font(pf(15.5)).foregroundColor(C.label)
                    .lineLimit(2).multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Text(sizeText(f.bytes ?? 0)).font(pf(12)).foregroundColor(C.subLabel)
                    if let c = f.chatName, !c.isEmpty {
                        Text("·").font(pf(12)).foregroundColor(C.subLabel)
                        Text((f.mine == true ? Tr("发到 ") : Tr("来自 ")) + c)
                            .font(pf(12)).foregroundColor(C.subLabel).lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 6)

            Button { openPreview(f) } label: {
                if openingId == f.id {
                    ProgressView().scaleEffect(0.72).frame(width: 34, height: 34)
                } else {
                    Image(systemName: "eye")
                        .font(.system(size: 15.5, weight: .medium))
                        .foregroundColor(C.subLabel)
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
            }
            .buttonStyle(.plain)
            Image(systemName: "paperplane")
                .font(.system(size: 15)).foregroundColor(C.green)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(C.cardBg))
        .contentShape(Rectangle())
    }

    private func openPreview(_ f: API.MyFileItem) {
        guard let p = f.url, !p.isEmpty else {
            app.show(Tr("这个文件找不到了"))
            return
        }
        let name = MyFilesPickerView.previewName(f.fileName, path: p)
        if let local = RemoteFileCache.localFile(path: p, preferredName: name) {
            preview = FilePreviewData(name: local.name, local: local.local)
            return
        }
        openingId = f.id
        Task {
            defer { openingId = "" }
            do {
                let file = try await RemoteFileCache.shared.file(path: p,
                                                                 preferredName: name)
                preview = FilePreviewData(name: file.name, local: file.local)
            } catch {
                app.show(Tr("文件下载失败，检查一下网络"))
            }
        }
    }

    static func previewName(_ name: String, path: String) -> String {
        var n = name.replacingOccurrences(of: "/", with: "_")
        if n.contains(".") { return n }
        let clean = path.split(separator: "?").first.map(String.init) ?? path
        if let last = clean.split(separator: "/").last, last.contains(".") {
            let ext = last.split(separator: ".").last.map(String.init) ?? ""
            if !ext.isEmpty, ext.count <= 5 { n += "." + ext }
        }
        return n
    }

    static func previewName(_ name: String, path: String, data: Data) -> String {
        var n = previewName(name, path: path)
        if n.contains(".") { return n }
        let ext = extensionFromData(data)
        return ext.isEmpty ? n : n + "." + ext
    }

    private static func extensionFromData(_ d: Data) -> String {
        let b = [UInt8](d.prefix(4096))
        func has(_ bytes: [UInt8], at: Int = 0) -> Bool {
            guard b.count >= at + bytes.count else { return false }
            return Array(b[at..<(at + bytes.count)]) == bytes
        }
        if has([0x25, 0x50, 0x44, 0x46]) { return "pdf" }
        if has([0x50, 0x4B, 0x03, 0x04]) {
            let s = String(data: d.prefix(2 * 1024 * 1024), encoding: .isoLatin1) ?? ""
            if s.contains("word/") { return "docx" }
            if s.contains("xl/") { return "xlsx" }
            if s.contains("ppt/") { return "pptx" }
            return "zip"
        }
        if has([0xFF, 0xD8, 0xFF]) { return "jpg" }
        if has([0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if has([0x47, 0x49, 0x46]) { return "gif" }
        if has([0x52, 0x49, 0x46, 0x46]) && has([0x57, 0x41, 0x56, 0x45], at: 8) { return "wav" }
        if has([0x66, 0x4C, 0x61, 0x43]) { return "flac" }
        if has([0x4F, 0x67, 0x67, 0x53]) { return "ogg" }
        if has([0x49, 0x44, 0x33]) || has([0xFF, 0xFB]) { return "mp3" }
        if b.count >= 12 && String(bytes: b[4..<8], encoding: .ascii) == "ftyp" {
            let brand = String(bytes: b[8..<12], encoding: .ascii) ?? ""
            if brand.contains("M4A") { return "m4a" }
            if brand.contains("qt") { return "mov" }
            return "mp4"
        }
        if has([0x52, 0x61, 0x72, 0x21]) { return "rar" }
        if has([0x37, 0x7A, 0xBC, 0xAF]) { return "7z" }
        if let text = String(data: d.prefix(4096), encoding: .utf8),
           !text.unicodeScalars.contains(where: { $0.value < 9 }) {
            return "txt"
        }
        return ""
    }

    private func fileColor(_ ext: String) -> Color {
        switch ext.lowercased() {
        case "pdf": return Color(hex: 0xE0533D)
        case "doc", "docx", "docm", "rtf", "rtfd", "odt", "pages", "wps":
            return Color(hex: 0x2B579A)
        case "xls", "xlsx", "xlsm", "xlsb", "csv", "tsv", "ods", "numbers", "et":
            return Color(hex: 0x217346)
        case "ppt", "pptx", "pptm", "pps", "ppsx", "odp", "key", "dps":
            return Color(hex: 0xD24726)
        case "zip", "rar", "7z": return Color(hex: 0xB8860B)
        case "mp3", "m4a", "wav": return Color(hex: 0x8E44AD)
        case "mp4", "mov", "avi": return Color(hex: 0x1F6FB2)
        case "jpg", "jpeg", "png", "gif", "heic", "webp": return Color(hex: 0x2E9B5B)
        case "txt", "md", "log": return Color(hex: 0x6C7A89)
        default: return Color(hex: 0x8A8A8E)
        }
    }

    private func sizeText(_ b: Int) -> String {
        if b <= 0 { return "" }
        if b < 1024 { return "\(b) B" }
        if b < 1024 * 1024 { return String(format: "%.1f KB", Double(b) / 1024) }
        return String(format: "%.1f MB", Double(b) / 1024 / 1024)
    }

    private func load() async {
        files = await API.shared.myFiles()
        loading = false
    }
}
