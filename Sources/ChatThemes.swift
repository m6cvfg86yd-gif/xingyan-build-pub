import SwiftUI

enum ChatAppearancePreset: String, CaseIterable, Identifiable {
    case whatsapp
    case midnight
    case rose
    case ocean
    case sage
    case lavender
    case sunset
    case graphite
    case mint
    case sand

    var id: String { rawValue }

    var title: String {
        switch self {
        case .whatsapp: return Tr("WhatsApp")
        case .midnight: return Tr("午夜蓝")
        case .rose: return Tr("玫瑰")
        case .ocean: return Tr("海洋")
        case .sage: return Tr("鼠尾草")
        case .lavender: return Tr("薰衣草")
        case .sunset: return Tr("日落")
        case .graphite: return Tr("石墨")
        case .mint: return Tr("薄荷")
        case .sand: return Tr("沙丘")
        }
    }

    var subtitle: String {
        switch self {
        case .whatsapp: return Tr("经典绿色收发气泡")
        case .midnight: return Tr("深色聊天与苹果蓝气泡")
        case .rose: return Tr("柔和暖色聊天氛围")
        case .ocean: return Tr("清爽蓝色收发层级")
        case .sage: return Tr("低饱和自然绿色")
        case .lavender: return Tr("柔和紫色聊天氛围")
        case .sunset: return Tr("暖橙与珊瑚色气泡")
        case .graphite: return Tr("专业克制的深灰层级")
        case .mint: return Tr("轻盈清凉的薄荷绿")
        case .sand: return Tr("温暖中性的大地色")
        }
    }

    var mine: Color {
        switch self {
        case .whatsapp: return Color.dyn(0x0C7A70, 0x005C4B)
        case .midnight: return Color.dyn(0x0A84FF, 0x0A84FF)
        case .rose: return Color.dyn(0xD94A6A, 0xB83A58)
        case .ocean: return Color.dyn(0x007AFF, 0x1263C7)
        case .sage: return Color.dyn(0x5B8C6E, 0x367456)
        case .lavender: return Color.dyn(0x7867C9, 0x6553B8)
        case .sunset: return Color.dyn(0xE06B42, 0xB94A2C)
        case .graphite: return Color.dyn(0x50555C, 0x3A3F45)
        case .mint: return Color.dyn(0x258F7A, 0x1D7568)
        case .sand: return Color.dyn(0xA77B4F, 0x775639)
        }
    }

    var other: Color {
        switch self {
        case .whatsapp: return Color.dyn(0xFFFFFF, 0x202C33)
        case .midnight: return Color.dyn(0xFFFFFF, 0x1C1C1E)
        case .rose: return Color.dyn(0xFFF8FA, 0x241E22)
        case .ocean: return Color.dyn(0xF5FAFF, 0x182431)
        case .sage: return Color.dyn(0xF7FAF7, 0x1D2420)
        case .lavender: return Color.dyn(0xFAF8FF, 0x211D2B)
        case .sunset: return Color.dyn(0xFFFAF6, 0x281A15)
        case .graphite: return Color.dyn(0xFFFFFF, 0x1B1D20)
        case .mint: return Color.dyn(0xF5FFFC, 0x13231F)
        case .sand: return Color.dyn(0xFFFBF4, 0x241E18)
        }
    }

    var canvas: Color {
        switch self {
        case .whatsapp: return Color.dyn(0xEFEAE2, 0x0B141A)
        case .midnight: return Color.dyn(0xF2F2F7, 0x000000)
        case .rose: return Color.dyn(0xF8F0F3, 0x090607)
        case .ocean: return Color.dyn(0xEFF6FA, 0x00131F)
        case .sage: return Color.dyn(0xEDF3ED, 0x08110C)
        case .lavender: return Color.dyn(0xF3F0FA, 0x09070D)
        case .sunset: return Color.dyn(0xFAF1EC, 0x0D0705)
        case .graphite: return Color.dyn(0xF2F2F2, 0x000000)
        case .mint: return Color.dyn(0xEBF7F3, 0x06110E)
        case .sand: return Color.dyn(0xF5EFE5, 0x0D0A07)
        }
    }

    var panel: Color {
        switch self {
        case .whatsapp: return Color.dyn(0xF0F2F5, 0x1C1C1E)
        case .midnight: return Color.dyn(0xF2F2F7, 0x121212)
        case .rose: return Color.dyn(0xF7EDF1, 0x171113)
        case .ocean: return Color.dyn(0xEAF3F9, 0x0C1B27)
        case .sage: return Color.dyn(0xEAF1EA, 0x101813)
        case .lavender: return Color.dyn(0xF0ECF8, 0x1A1721)
        case .sunset: return Color.dyn(0xF8EAE3, 0x20120D)
        case .graphite: return Color.dyn(0xEEEEEF, 0x171717)
        case .mint: return Color.dyn(0xE6F4EF, 0x101B18)
        case .sand: return Color.dyn(0xF0E8DC, 0x1A1510)
        }
    }

    var previewBackground: Color {
        switch self {
        case .whatsapp: return Color(hex: 0xEFEAE2)
        case .midnight: return Color(hex: 0x050505)
        case .rose: return Color(hex: 0xF8EDF1)
        case .ocean: return Color(hex: 0xE7F2F8)
        case .sage: return Color(hex: 0xE8F0E8)
        case .lavender: return Color(hex: 0xF2EFF9)
        case .sunset: return Color(hex: 0xFAF0EA)
        case .graphite: return Color(hex: 0x080808)
        case .mint: return Color(hex: 0xE8F5F0)
        case .sand: return Color(hex: 0xF4EDE2)
        }
    }
}

final class ChatThemeStore: ObservableObject {
    static let shared = ChatThemeStore()

    @Published private(set) var version = 0
    private var activeChatId = ""

    private init() {}

    private func key(_ chatId: String) -> String {
        "chris.chatTheme." + (chatId.isEmpty ? "global" : chatId)
    }

    func activate(_ chatId: String) {
        guard activeChatId != chatId else { return }
        activeChatId = chatId
        version &+= 1
    }

    func selected(chatId: String = "") -> ChatAppearancePreset {
        let id = chatId.isEmpty ? activeChatId : chatId
        let raw = UserDefaults.standard.string(forKey: key(id)) ?? ""
        return ChatAppearancePreset(rawValue: raw) ?? .whatsapp
    }

    func set(_ preset: ChatAppearancePreset, chatId: String = "") {
        let id = chatId.isEmpty ? activeChatId : chatId
        UserDefaults.standard.set(preset.rawValue, forKey: key(id))
        version &+= 1
    }
}

struct ChatThemePickerView: View {
    let chatId: String

    @ObservedObject private var store = ChatThemeStore.shared
    @Environment(\.dismiss) private var dismiss

    private var selected: ChatAppearancePreset {
        store.selected(chatId: chatId)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    themePreview(selected)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(Tr("选择主题"))
                            .font(.title3.weight(.semibold))
                        Text(Tr("主题会同时改变收发气泡、聊天底色和输入区，不会覆盖你单独设置的壁纸。"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(ChatAppearancePreset.allCases.enumerated()), id: \.element.id) { index, preset in
                            Button {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    store.set(preset, chatId: chatId)
                                }
                                UISelectionFeedbackGenerator().selectionChanged()
                            } label: {
                                themeRow(preset, isSelected: selected == preset)
                            }
                            .buttonStyle(.plain)

                            if index < ChatAppearancePreset.allCases.count - 1 {
                                Divider().padding(.leading, 72)
                            }
                        }
                    }
                    .background(Color(uiColor: .secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 0.6)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, max(24, L.safeBottom + 12))
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(Tr("聊天主题"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Tr("完成")) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func themePreview(_ preset: ChatAppearancePreset) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(preset.previewBackground)

            VStack(spacing: 11) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Tr("聊天主题预览"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(preset.title)
                            .font(.headline)
                            .foregroundStyle(preset == .midnight ? Color.white : Color.primary)
                    }
                    Spacer()
                }

                HStack {
                    Text(Tr("周末有空吗？"))
                        .font(.subheadline)
                        .foregroundStyle(Color.primary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 9)
                        .background(preset.other,
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    Spacer(minLength: 42)
                }

                HStack {
                    Spacer(minLength: 42)
                    Text(Tr("有，晚点联系你。"))
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 9)
                        .background(preset.mine,
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                HStack(spacing: 8) {
                    Image(systemName: "face.smiling")
                    Image(systemName: "plus")
                    Text(Tr("输入消息"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .font(.system(size: 17, weight: .medium))
                .padding(.horizontal, 13)
                .frame(height: 42)
                .background(preset.panel,
                            in: RoundedRectangle(cornerRadius: 21, style: .continuous))
            }
            .padding(18)
        }
        .frame(height: 254)
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 0.6)
        }
        .shadow(color: Color.black.opacity(0.10), radius: 18, y: 8)
    }

    private func themeRow(_ preset: ChatAppearancePreset,
                          isSelected: Bool) -> some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(preset.previewBackground)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(preset.other)
                            .frame(width: 27, height: 12)
                        Spacer(minLength: 16)
                    }
                    HStack {
                        Spacer(minLength: 16)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(preset.mine)
                            .frame(width: 27, height: 12)
                    }
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(preset.panel)
                        .frame(height: 12)
                }
                .padding(7)
            }
            .frame(width: 62, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(preset.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(preset.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.35))
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 62)
        .contentShape(Rectangle())
    }
}
