import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum OfficeDocumentKind {
    case word
    case excel
    case powerpoint

    init?(fileName: String) {
        switch (fileName as NSString).pathExtension.lowercased() {
        case "doc", "docx", "docm", "rtf", "rtfd", "odt", "pages", "wps":
            self = .word
        case "xls", "xlsx", "xlsm", "xlsb", "csv", "tsv", "ods", "numbers", "et":
            self = .excel
        case "ppt", "pptx", "pptm", "pps", "ppsx", "odp", "key", "dps":
            self = .powerpoint
        default:
            return nil
        }
    }

    var name: String {
        switch self {
        case .word: return Tr("Word 文档")
        case .excel: return Tr("Excel 表格")
        case .powerpoint: return Tr("PowerPoint 演示文稿")
        }
    }

    var badge: String {
        switch self {
        case .word: return "W"
        case .excel: return "X"
        case .powerpoint: return "P"
        }
    }

    var symbol: String {
        switch self {
        case .word: return "doc.text.fill"
        case .excel: return "tablecells.fill"
        case .powerpoint: return "rectangle.on.rectangle.angled"
        }
    }

    var color: Color {
        switch self {
        case .word: return Color(hex: 0x2B579A)
        case .excel: return Color(hex: 0x217346)
        case .powerpoint: return Color(hex: 0xD24726)
        }
    }

    var formats: String {
        switch self {
        case .word: return "DOC · DOCX · RTF · ODT · PAGES"
        case .excel: return "XLS · XLSX · CSV · ODS · NUMBERS"
        case .powerpoint: return "PPT · PPTX · PPSX · ODP · KEY"
        }
    }
}

struct OfficeDocumentHeader: View {
    let kind: OfficeDocumentKind
    let name: String
    let local: URL

    private var subtitle: String {
        let size = (try? local.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if size > 0 {
            return kind.name + " · " + ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        }
        return kind.name
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(kind.color)
                VStack(spacing: 1) {
                    Image(systemName: kind.symbol)
                        .font(.system(size: 14, weight: .semibold))
                    Text(kind.badge)
                        .font(pfStyled(size: 8, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(pfStyled(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(pfStyled(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(kind.color)
                .accessibilityLabel(Tr("原生文档预览"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

struct OfficeDocumentActionBar: View {
    let kind: OfficeDocumentKind
    let favoriting: Bool
    let onFavorite: () -> Void
    let onPrint: () -> Void
    let onShare: () -> Void
    let onDrop: () -> Void
    let onInfo: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            action(title: Tr("收藏"),
                   symbol: favoriting ? "hourglass" : "star",
                   tint: C.green,
                   enabled: !favoriting,
                   action: onFavorite)
            action(title: Tr("打印"), symbol: "printer", tint: C.label, action: onPrint)
            action(title: Tr("分享"), symbol: "square.and.arrow.up", tint: .white,
                   filled: true, action: onShare)
            Menu {
                Button(action: onDrop) {
                    Label(Tr("面对面快传"), systemImage: "dot.radiowaves.left.and.right")
                }
                Button(action: onInfo) {
                    Label(Tr("文件信息"), systemImage: "info.circle")
                }
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                    Text(Tr("更多"))
                        .font(pfStyled(size: 10.5, weight: .medium))
                }
                .foregroundStyle(C.label)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(C.cardBg)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Tr("更多文档操作"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .top) {
            Rectangle().fill(C.hairline).frame(height: 0.5)
        }
        .accessibilityElement(children: .contain)
    }

    private func action(title: String,
                        symbol: String,
                        tint: Color,
                        enabled: Bool = true,
                        filled: Bool = false,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(pfStyled(size: 10.5, weight: .medium))
            }
            .foregroundStyle(filled ? Color.white : tint)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(filled ? C.green : C.cardBg)
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.55)
    }
}

struct OfficeDocumentInfoSheet: View {
    let kind: OfficeDocumentKind
    let name: String
    let local: URL

    @Environment(\.dismiss) private var dismiss

    private var values: URLResourceValues? {
        try? local.resourceValues(forKeys: [
            .fileSizeKey, .contentModificationDateKey, .contentTypeKey
        ])
    }

    private var sizeText: String {
        guard let size = values?.fileSize, size > 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    private var dateText: String {
        guard let date = values?.contentModificationDate else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var typeText: String {
        values?.contentType?.localizedDescription ?? kind.name
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(kind.color)
                            Text(kind.badge)
                                .font(pfStyled(size: 27, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 58, height: 58)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(name)
                                .font(pfStyled(size: 17, weight: .semibold))
                                .lineLimit(2)
                            Text(kind.name)
                                .font(pfStyled(size: 15))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section(header: Text(Tr("文件信息"))) {
                    LabeledContent(Tr("类型"), value: typeText)
                    LabeledContent(Tr("大小"), value: sizeText)
                    LabeledContent(Tr("修改时间"), value: dateText)
                    LabeledContent(Tr("文件"), value: local.lastPathComponent)
                }

                Section {
                    LabeledContent(Tr("预览方式"), value: Tr("iOS 原生文档引擎"))
                } footer: {
                    Text(Tr("支持 ") + kind.formats + Tr("。文档由 iPhone 原生渲染，不会上传到第三方网页预览服务。"))
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(Tr("文件信息"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Tr("完成")) { dismiss() }
                }
            }
        }
    }
}
