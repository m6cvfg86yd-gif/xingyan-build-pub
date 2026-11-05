import SwiftUI
import UIKit

private struct FontSizePreset: Identifiable {
    let id: String
    let title: String
    let value: CGFloat
}

struct FontSettingsView: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject private var store = AppFontStore.shared

    private let presets = [
        FontSizePreset(id: "small", title: "小", value: 0.88),
        FontSizePreset(id: "regular", title: "标准", value: 1.00),
        FontSizePreset(id: "large", title: "大", value: 1.14),
        FontSizePreset(id: "xlarge", title: "特大", value: 1.28)
    ]

    private var canChooseFont: Bool {
        app.me?.ops == true ||
        (app.me?.username ?? "").caseInsensitiveCompare("wzy245441545") == .orderedSame
    }

    private var familyTitle: String {
        store.family.isEmpty ? Tr("苹方 · 默认") : store.family
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("星言 · 让连接有自己的轨道")
                        .font(pf(20, .semibold))
                        .foregroundStyle(C.label)
                    Text("Aa  字体预览  123  Hello, Xingyan")
                        .font(pf(14))
                        .foregroundStyle(C.subLabel)

                    HStack(spacing: 8) {
                        Image(systemName: "textformat")
                            .font(.system(size: 11, weight: .semibold))
                        Text(store.family.isEmpty ? Tr("苹方 · 默认") : store.family)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text("\(Int(store.scale * 100))%")
                            .monospacedDigit()
                    }
                    .font(pfStyled(size: 11, weight: .medium))
                    .foregroundStyle(OrbitTheme.jade)
                }
                .padding(.vertical, 8)
            } header: {
                Text(Tr("字体预览"))
            }

            Section {
                HStack(spacing: 12) {
                    Text("A")
                        .font(pfStyled(size: 13, weight: .medium))
                    Slider(
                        value: Binding(
                            get: { Double(store.scale) },
                            set: { store.setScale(CGFloat($0)) }
                        ),
                        in: 0.80...1.40,
                        step: 0.02
                    )
                    .tint(OrbitTheme.jade)
                    Text("A")
                        .font(pfStyled(size: 23, weight: .semibold))
                }
                .foregroundStyle(C.label)

                Picker(
                    Tr("大小"),
                    selection: Binding(
                        get: { nearestPresetIndex },
                        set: { index in
                            guard presets.indices.contains(index) else { return }
                            UISelectionFeedbackGenerator().selectionChanged()
                            store.setScale(presets[index].value)
                        }
                    )
                ) {
                    ForEach(Array(presets.enumerated()), id: \.element.id) { index, preset in
                        Text(Tr(preset.title)).tag(index)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text(Tr("字号"))
            } footer: {
                Text(Tr("字号调整只对这台设备生效，所有页面会立即更新。"))
            }

            Section {
                if canChooseFont {
                    NavigationLink {
                        FontFamilyPickerView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "character.book.closed.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(OrbitTheme.jade)
                                .frame(width: 30, height: 30)
                                .background(OrbitTheme.jadeSoft)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(Tr("字体样式"))
                                    .foregroundStyle(C.label)
                                Text(familyTitle)
                                    .font(pfStyled(size: 12))
                                    .foregroundStyle(C.subLabel)
                                    .lineLimit(1)
                            }
                        }
                    }

                    if !store.family.isEmpty {
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            store.setFamily("", canChoose: canChooseFont)
                        } label: {
                            Text(Tr("恢复默认字体"))
                                .foregroundStyle(C.red)
                        }
                    }
                } else {
                    HStack(alignment: .top, spacing: 11) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(OrbitTheme.tertiary)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Tr("字体样式由管理员统一设置"))
                                .font(pfStyled(size: 14, weight: .medium))
                                .foregroundStyle(C.label)
                            Text(Tr("你可以调整字号；任意字体选择只对管理员开放。"))
                                .font(pfStyled(size: 12))
                                .foregroundStyle(C.subLabel)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text(Tr("字体"))
            } footer: {
                if canChooseFont {
                    Text(Tr("管理员可以选择这台设备上安装的任意字体。"))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Tr("字体与字号"))
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBar()
    }

    private var nearestPresetIndex: Int {
        presets.enumerated()
            .min { abs(store.scale - $0.element.value) < abs(store.scale - $1.element.value) }?
            .offset ?? 1
    }
}

struct FontFamilyPickerView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = AppFontStore.shared
    @State private var query = ""

    private var canChooseFont: Bool {
        app.me?.ops == true ||
        (app.me?.username ?? "").caseInsensitiveCompare("wzy245441545") == .orderedSame
    }

    private var families: [String] {
        let all = UIFont.familyNames.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        let key = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return all }
        return all.filter { $0.localizedCaseInsensitiveContains(key) }
    }

    var body: some View {
        Group {
            if canChooseFont {
                List {
                    Section {
                        fontRow(
                            title: Tr("苹方 · 默认"),
                            subtitle: "PingFang SC",
                            family: "",
                            preview: "星言 Xingyan 123"
                        )
                    } footer: {
                        Text(Tr("某些字体不包含中文字形，系统会自动回退到可显示字体。"))
                    }

                    Section(header: Text(Tr("系统字体"))) {
                        ForEach(families, id: \.self) { family in
                            fontRow(
                                title: family,
                                subtitle: UIFont.fontNames(forFamilyName: family).first ?? "",
                                family: family,
                                preview: sampleText(for: family)
                            )
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .searchable(text: $query, prompt: Text(Tr("搜索字体")))
            } else {
                VStack(spacing: 13) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(OrbitTheme.tertiary)
                    Text(Tr("仅管理员可用"))
                        .font(pfStyled(size: 18, weight: .semibold))
                        .foregroundStyle(C.label)
                    Text(Tr("字体选择只对管理员开放。"))
                        .font(pfStyled(size: 13))
                        .foregroundStyle(C.subLabel)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(C.pageBg.ignoresSafeArea())
            }
        }
        .navigationTitle(Tr("选择字体"))
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBar()
    }

    private func fontRow(title: String,
                         subtitle: String,
                         family: String,
                         preview: String) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            store.setFamily(family, canChoose: canChooseFont)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(pfStyled(size: 14.5, weight: .medium))
                        .foregroundStyle(C.label)
                        .lineLimit(1)
                    Text(preview)
                        .font(previewFont(family, size: 18))
                        .foregroundStyle(C.subLabel)
                        .lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(pfStyled(size: 10.5, design: .monospaced))
                            .foregroundStyle(C.subLabel.opacity(0.72))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if store.family == family {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(OrbitTheme.jade)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func previewFont(_ family: String, size: CGFloat) -> Font {
        guard !family.isEmpty,
              let face = appFontFaceName(in: family, weight: .regular),
              let font = UIFont(name: face, size: size) else {
            return .system(size: size)
        }
        return Font(font)
    }

    private func sampleText(for family: String) -> String {
        let lower = family.lowercased()
        if lower.contains("pingfang")
            || lower.contains("song")
            || lower.contains("hei")
            || lower.contains("kai")
            || lower.contains("yuan")
            || lower.contains("chinese") {
            return "星言 · 连接有自己的轨道"
        }
        return "Xingyan · Connect in orbit"
    }
}
