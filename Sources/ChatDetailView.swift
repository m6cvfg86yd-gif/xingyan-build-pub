import SwiftUI
import UniformTypeIdentifiers
import Combine
import UIKit
import QuickLook
import QuickLookThumbnailing
import CoreImage

private struct ChatTypingDots: View {
    let color: Color
    @State private var active = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(color)
                    .frame(width: 3.6, height: 3.6)
                    .scaleEffect(active ? 1 : 0.58)
                    .opacity(active ? 1 : 0.42)
                    .animation(
                        .easeInOut(duration: 0.58)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.13),
                        value: active
                    )
            }
        }
        .frame(width: 17, height: 10)
        .onAppear { active = true }
        .accessibilityHidden(true)
    }
}

private final class ImageUploadProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double]
    private var completed = 0

    init(count: Int) {
        values = Array(repeating: 0, count: max(1, count))
    }

    func update(index: Int, value: Double) -> (progress: Double, completed: Int) {
        lock.lock()
        defer { lock.unlock() }
        if values.indices.contains(index) {
            if values[index] < 0.999, value >= 0.999 {
                completed += 1
            }
            values[index] = min(1, max(0, value))
        }
        return (values.reduce(0, +) / Double(values.count), completed)
    }
}

private enum ChatTheme {
    static var preset: ChatAppearancePreset { ChatThemeStore.shared.selected() }
    static var page: Color { preset.canvas }
    static var panel: Color { preset.panel }
    static var bubbleMine: Color {
        preset.mine
    }
    static var bubbleOther: Color { preset.other }
    static let ink = Color.dyn(0x111B21, 0xE9EDEF)
    static let mineInk = Color.dyn(0xFFFFFF, 0xE9EDEF)
    static let secondary = Color.dyn(0x667781, 0x8696A0)
    static let groupSenderNameOnLight = Color.dyn(0x111B21, 0x111B21)
    static let groupSenderNameOnDark = Color.dyn(0xE9EDEF, 0xE9EDEF)
    static let secondaryOnMine = Color.dyn(0xD4F5EF, 0xE5E5EA)
    static let timeInk = Color.dyn(0x667781, 0x8696A0)
    static var composerBg: Color { preset.panel }
    static let separator = Color.dyn(0xE9EDEF, 0x38383A)
    static let link = Color.dyn(0x0067DC, 0x7CCBFF)
    static let linkOnMine = Color.dyn(0xEFFFFC, 0xD9FFF8)
    static let mentionMe = Color.dyn(0xE53935, 0xFF9E91)
    static let mentionMeOnMine = Color.dyn(0x7A1717, 0xFFD2CA)
}

enum AlbumFold {
    private static let key = "chris.albumOpen"

    static func isOpen(_ id: String) -> Bool {
        guard !id.isEmpty else { return false }
        return Set(UserDefaults.standard.stringArray(forKey: key) ?? []).contains(id)
    }

    static func setOpen(_ id: String, _ open: Bool) {
        guard !id.isEmpty else { return }
        var list = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        if open { list.insert(id) } else { list.remove(id) }

        var arr = Array(list)
        if arr.count > 200 { arr = Array(arr.suffix(200)) }
        UserDefaults.standard.set(arr, forKey: key)
    }
}

struct PendingMsg: Identifiable, Hashable {
    var id: String
    var kind: String
    var content: String
    var mentions: [String] = []

    var quoteJSON: String?
    var sending = false
    var failed = false
    var failureReason: String? = nil
    var at = Date()

    var preview: String {
        switch kind {
        case "text": return content
        case "image", "images": return "[图片]"
        case "audio": return "[语音]"
        case "file": return "[文件]"
        case "video", "livephoto": return "[视频]"
        case "location": return "[位置]"
        case "transfer": return "[转账]"
        case "redpacket": return "[红包]"
        case "gift": return "[礼物]"
        case "link": return "[链接]"

        case "note": return "[笔记]"
        default: return "[" + kind + "]"
        }
    }
}

private struct ChatContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

func bubbleSeed(_ id: String) -> Double {
    var h = 5381
    for u in id.unicodeScalars { h = (h &* 33) &+ Int(u.value) }
    return Double(abs(h % 997)) / 997.0
}

struct BubbleShape: Shape {
    let mine: Bool
    var radius: CGFloat = 12
    var tail: Bool = true

    var pill: Bool = false

    func path(in rect: CGRect) -> Path {
        let r = min(pill ? min(rect.height / 2, 18) : radius, rect.height / 2, rect.width / 2)

        let out: CGFloat = tail ? 5 : 0
        let h: CGFloat = 9
        let y0 = rect.minY + 6
        let x0 = rect.minX, x1 = rect.maxX, yA = rect.minY, yB = rect.maxY
        var p = Path()

        if mine {
            p.move(to: CGPoint(x: x0 + r, y: yA))
            p.addLine(to: CGPoint(x: x1 - r, y: yA))
            p.addQuadCurve(to: CGPoint(x: x1, y: yA + r), control: CGPoint(x: x1, y: yA))
            if out > 0 {
                p.addLine(to: CGPoint(x: x1, y: y0))
                p.addLine(to: CGPoint(x: x1 + out, y: y0 + h / 2))
                p.addLine(to: CGPoint(x: x1, y: y0 + h))
            }
            p.addLine(to: CGPoint(x: x1, y: yB - r))
            p.addQuadCurve(to: CGPoint(x: x1 - r, y: yB), control: CGPoint(x: x1, y: yB))
            p.addLine(to: CGPoint(x: x0 + r, y: yB))
            p.addQuadCurve(to: CGPoint(x: x0, y: yB - r), control: CGPoint(x: x0, y: yB))
            p.addLine(to: CGPoint(x: x0, y: yA + r))
            p.addQuadCurve(to: CGPoint(x: x0 + r, y: yA), control: CGPoint(x: x0, y: yA))
        } else {
            p.move(to: CGPoint(x: x1 - r, y: yA))
            p.addLine(to: CGPoint(x: x0 + r, y: yA))
            p.addQuadCurve(to: CGPoint(x: x0, y: yA + r), control: CGPoint(x: x0, y: yA))
            if out > 0 {
                p.addLine(to: CGPoint(x: x0, y: y0))
                p.addLine(to: CGPoint(x: x0 - out, y: y0 + h / 2))
                p.addLine(to: CGPoint(x: x0, y: y0 + h))
            }
            p.addLine(to: CGPoint(x: x0, y: yB - r))
            p.addQuadCurve(to: CGPoint(x: x0 + r, y: yB), control: CGPoint(x: x0, y: yB))
            p.addLine(to: CGPoint(x: x1 - r, y: yB))
            p.addQuadCurve(to: CGPoint(x: x1, y: yB - r), control: CGPoint(x: x1, y: yB))
            p.addLine(to: CGPoint(x: x1, y: yA + r))
            p.addQuadCurve(to: CGPoint(x: x1 - r, y: yA), control: CGPoint(x: x1, y: yA))
        }
        p.closeSubpath()
        return p
    }
}

private struct BubbleUsesLightInkKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

private struct BubbleWallpaperTintKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

extension EnvironmentValues {
    fileprivate var bubbleUsesLightInk: Bool? {
        get { self[BubbleUsesLightInkKey.self] }
        set { self[BubbleUsesLightInkKey.self] = newValue }
    }

    fileprivate var bubbleWallpaperTint: Color? {
        get { self[BubbleWallpaperTintKey.self] }
        set { self[BubbleWallpaperTintKey.self] = newValue }
    }
}

struct BubbleFill: View {
    var mine: Bool
    var tail: Bool = true

    var pill: Bool = false

    var seed: Double = 0

    var glass: Bool = true
    @Environment(\.colorScheme) private var scheme
    @Environment(\.bubbleUsesLightInk) private var wallpaperUsesLightInk
    private var usesDarkBackdrop: Bool { wallpaperUsesLightInk ?? (scheme == .dark) }

    private var gloss: Color {
        return Color.white.opacity(UIConfig.num("bubbleGloss", 0))
    }
    private var shade: Color {
        Color.black.opacity(UIConfig.num("bubbleShade", 0))
    }

    private var edgeAlpha: CGFloat { UIConfig.num("bubbleEdge", 0) }

    private var mineFill: LinearGradient {
        LinearGradient(
            colors: [
                ChatTheme.bubbleMine,
                ChatTheme.bubbleMine.opacity(0.88)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        ZStack {
            if mine {
                BubbleShape(mine: mine, tail: tail, pill: pill)
                    .fill(mineFill)
            } else {
                BubbleShape(mine: mine, tail: tail, pill: pill)
                    .fill(ChatTheme.bubbleOther)
            }

            if UIConfig.num("bubbleGloss", 0) > 0
                || UIConfig.num("bubbleShade", 0) > 0 {
                BubbleShape(mine: mine, tail: tail, pill: pill)
                    .fill(LinearGradient(stops: [
                        .init(color: gloss, location: 0),
                        .init(color: Color.clear, location: 0.42),
                        .init(color: Color.clear, location: 0.68),
                        .init(color: shade, location: 1)
                    ], startPoint: .top, endPoint: .bottom))
            }

            if edgeAlpha > 0 {
                BubbleShape(mine: mine, tail: tail, pill: pill)
                    .stroke(Color.white.opacity(edgeAlpha), lineWidth: 0.9)
            }

            if UIConfig.num("bubbleIridescent", 0) > 0 {
                BubbleShape(mine: mine, tail: tail, pill: pill)
                    .stroke(AngularGradient(
                        colors: [
                            Color(red: 0.32, green: 0.86, blue: 1.00).opacity(0.55),
                            Color(red: 0.72, green: 0.58, blue: 1.00).opacity(0.50),
                            Color(red: 1.00, green: 0.58, blue: 0.78).opacity(0.46),
                            Color(red: 1.00, green: 0.86, blue: 0.48).opacity(0.50),
                            Color(red: 0.55, green: 1.00, blue: 0.72).opacity(0.46),
                            Color(red: 0.32, green: 0.86, blue: 1.00).opacity(0.55)
                        ],
                        center: .center,
                        angle: .degrees(seed * 360)),
                            lineWidth: 1.1)
            }
        }
        .allowsHitTesting(false)
    }
}

enum PanelKind { case none, emoji, plus, gift, mention }

private enum ChatWallpaperEdge: Equatable {
    case top
    case bottom
}

private struct ChatImmersiveEdgeMask: View {
    let path: String
    let edge: ChatWallpaperEdge
    let tint: Color?
    let dark: Bool
    let effect: ChatBackgroundEffect
    let preset: ChatAppearancePreset
    let themeVersion: Int
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { proxy in
            if path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ChatDefaultWallpaper(preset: preset)
                    .frame(width: max(1, proxy.size.width),
                           height: max(1, proxy.size.height),
                           alignment: edge == .top ? .top : .bottom)
                    .id("edge-theme-\(preset.rawValue)-\(themeVersion)-\(edge == .top ? "top" : "bottom")")
            } else if normalizedChatBackground(path) == "solid:black" {
                Rectangle()
                    .fill(Color.black)
                    .frame(width: max(1, proxy.size.width),
                           height: max(1, proxy.size.height),
                           alignment: edge == .top ? .top : .bottom)
            } else {
            let width = max(1, proxy.size.width)
            let height = max(1, proxy.size.height)
            let alignment: Alignment = edge == .top ? .top : .bottom
            let resolved = effect.resolved(for: scheme)
            let blurred = resolved != .original
            let effectiveDark = resolved == .blackBlur
                || (resolved != .whiteBlur && dark)
            let base = tint ?? (effectiveDark ? Color(hex: 0x111312)
                                              : Color(hex: 0xF3F5F2))
            let direction: (UnitPoint, UnitPoint) = edge == .top
                ? (.top, .bottom)
                : (.bottom, .top)

            ZStack(alignment: alignment) {
                Rectangle()
                    .fill(base)

                if !path.isEmpty {
                    if let solid = renderedChatBackgroundSolidColor(
                        path,
                        dark: effectiveDark
                    ) {
                        solid
                    } else if blurred {
                        ChatWallpaperEffectImage(
                            path: path,
                            effect: resolved,
                            renderSize: CGSize(width: width, height: L.height),
                            displayAlignment: alignment
                        )
                        .id(path + (edge == .top
                                    ? ":mask-top-blur"
                                    : ":mask-bottom-blur"))
                    } else {
                        RemoteImage(path: path,
                                    mode: .fill,
                                    maxSide: chatWallpaperDecodeSide())
                            .id(path + (edge == .top ? ":mask-top" : ":mask-bottom"))
                            .frame(width: width, height: L.height)
                    }
                }

                Rectangle()
                    .fill(base.opacity(blurred
                                       ? (effectiveDark ? 0.065 : 0.045)
                                       : (effectiveDark ? 0.045 : 0.025)))

                LinearGradient(
                    colors: [
                        Color.white.opacity(effectiveDark ? 0.025 : 0.055),
                        Color.clear,
                        Color.black.opacity(effectiveDark ? 0.028 : 0.008)
                    ],
                    startPoint: direction.0,
                    endPoint: direction.1
                )

                LinearGradient(
                    colors: [
                        Color.clear,
                        base.opacity(blurred
                                     ? (effectiveDark ? 0.075 : 0.035)
                                     : (effectiveDark ? 0.055 : 0.025))
                    ],
                    startPoint: direction.0,
                    endPoint: direction.1
                )

                ChatMaterialGrainOverlay()
            }
            .frame(width: width, height: height, alignment: alignment)
            .clipped()
            }
        }
        .allowsHitTesting(false)
    }
}

struct KeyboardLiftDisable: ViewModifier {
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.ignoresSafeArea(.keyboard, edges: .bottom)
        } else {
            content
        }
    }
}

private struct QuickIconButtonStyle: ButtonStyle {
    let ink: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(configuration.isPressed ? ink.opacity(0.10) : Color.clear)
            }
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct ThreeWaveMicGlyph: View {
    let ink: Color

    var body: some View {
        HStack(alignment: .center, spacing: 1.8) {
            Image(systemName: "mic.fill")
                .font(.system(size: 14.5, weight: .semibold))

            HStack(alignment: .center, spacing: 1.55) {
                Capsule(style: .continuous)
                    .frame(width: 1.65, height: 6)
                Capsule(style: .continuous)
                    .frame(width: 1.65, height: 11)
                Capsule(style: .continuous)
                    .frame(width: 1.65, height: 8)
            }
            .frame(height: 18, alignment: .center)
        }
        .foregroundStyle(ink)
        .frame(width: 24, height: 22)
    }
}

private struct StarWhisperLine: View {
    let text: String
    let ink: Color
    let surface: Color
    let border: Color
    let accent: Color
    let active: Bool
    var plain: Bool = false

    @State private var arrived = false
    @State private var bloom = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkles")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(accent)
            Text(text)
                .font(.footnote)
                .foregroundStyle(ink)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, plain ? 2 : 11)
        .padding(.vertical, plain ? 0 : 5)
        .background {
            if !plain {
                ZStack {
                    Capsule(style: .continuous).fill(.ultraThinMaterial)
                    Capsule(style: .continuous).fill(surface)
                }
            }
        }
        .overlay {
            if !plain {
                Capsule(style: .continuous).stroke(border, lineWidth: 0.6)
            }
        }
        .overlay {
            if active && !plain {
                Capsule(style: .continuous)
                    .stroke(accent.opacity(bloom ? 0 : 0.42), lineWidth: 1)
                    .scaleEffect(bloom ? 1.16 : 0.98)
                    .opacity(bloom ? 0 : 1)
            }
        }
        .scaleEffect(arrived ? 1 : 0.92)
        .opacity(arrived ? 1 : 0)
        .onAppear {
            if active {
                play()
            } else {
                arrived = true
            }
        }
        .onChange(of: active) { isActive in
            if isActive { play() }
        }
    }

    private func play() {
        arrived = false
        bloom = false
        withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) {
            arrived = true
        }
        withAnimation(.easeOut(duration: 0.82).delay(0.08)) {
            bloom = true
        }
    }
}

struct ChatDetailView: View {
    @ObservedObject private var lang = LangStore.shared

    @ObservedObject private var chatBg = ChatBgStore.shared
    @ObservedObject private var chatTheme = ChatThemeStore.shared
    @ObservedObject private var drafts = ChatDraftStore.shared
    let chat: Chat

    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var messages: [Message] = []
    @State private var senderAvatarCache: [String: String] = [:]
    @State private var groupSenderProfilesLoaded = false
    @State private var backgroundLuminance: Double? = nil
    @State private var backgroundTopLuminance: Double? = nil
    @State private var backgroundBottomLuminance: Double? = nil
    @State private var wallpaperTopTint: Color? = nil
    @State private var wallpaperBottomTint: Color? = nil
    @State private var historySyncTask: Task<Void, Never>?

    @State private var hiddenMessageIds: Set<String> = []

    @State private var persistTask: Task<Void, Never>?
    @State private var draftSaveTask: Task<Void, Never>?
    @State private var input = ""
    @State private var inputBoxHeight: CGFloat = 39
    @State private var dismissDragActive = false
    @State private var loading = true
    @State private var initialCacheReady = false
    @State private var initialRetryTask: Task<Void, Never>?
    @State private var initialScrollReady = false
    @State private var initialScrollTask: Task<Void, Never>?
    @State private var panel: PanelKind = .none
    @State private var emojiPanelExpanded = false
    @State private var plusItems: [PlusItem] = []

    @State private var showPickCard = false
    @State private var gifts: [Gift] = []

    @State private var web: WebURL?

    @State private var runningMiniApp: MiniApp?

    @State private var autoOpened: Set<String> = []

    @State private var actionMessage: Message?
    @State private var forwardItems: [ForwardItem] = []
    @State private var showForward = false
    @State private var selectMode = false
    @State private var selected: Set<String> = []
    @State private var showMultiDeleteConfirm = false
    @State private var quote: Message?
    @State private var quoteInspect: QuoteInspectItem?

    @State private var reEditDraft: String?

    @State private var lastBurnSweep = Date.distantPast
    @State private var burnedIds: Set<String> = []

    @State private var frameBox = MsgFrameBox()
    @State private var frameCaptureTick = 0

    @State private var msgIndex: [String: Int] = [:]
    @State private var menuRect: CGRect = .zero

    @State private var showPhoto = false
    @State private var showCamera = false

    @State private var showCameraVideo = false
    @State private var recordedVideo: URL?
    @State private var showLocation = false

    @State private var showLocationMenu = false
    @State private var showLiveLocation = false

    @State private var showSendLocation = false
    @State private var showTransfer = false

    @State private var kbHeight: CGFloat = 0

    @State private var showSendRedPacket = false

    @State private var rainOn = false
    @State private var openRedPacket: RedPacketInfo? = nil
    @State private var redPacketDetail: String? = nil
    @State private var showGroupInfo = false
    @State private var showSearch = false
    @State private var showChatInfo = false
    @State private var sysToolsPage: SysPage?
    @State private var showFile = false

    @State private var showMyFiles = false

    @State private var showStickerStore = false

    @State private var myStickers = StickerMine()

    @State private var showCaptureSticker = false

    @State private var showPickMusic = false

    @State private var showApply = false
    @State private var applyNote = ""
    @State private var peerRelationChecked = false
    @State private var serverPeerRelation: String?
    @State private var peerBanned = false
    @State private var peerBanReason = ""
    @State private var peerBlockedByMe = false

    @State private var announcePage = ""
    @State private var showAnnouncePage = false
    @State private var showChatFavorites = false
    @State private var showChatTheme = false
    @State private var showCall = false

    @State private var redialAsk: Message? = nil
    @State private var patAnimatingId: String?
    @State private var patAnimationTask: Task<Void, Never>?

    @State private var showCallChoice = false
    @State private var billInfo: TransferInfo?
    @State private var uploading = false

    @State private var viewer: PhotoPager.Item?

    @State private var asrCache: [String: String] = [:]
    @State private var asrBusy: Set<String> = []

    @State private var outbox: [PendingMsg] = []
    @State private var flushing = false

    @State private var filePreview: FilePreviewData?

    @State private var shareFile: FilePreviewData?

    @State private var oaArticleId = ""
    @State private var showOaArticle = false

    @State private var lastContentHeight: CGFloat = 0
    @State private var followOwnSendUntil = Date.distantPast

    @State private var cardUser: User?

    @State private var openLocation: LocationPoint?

    @State private var botCard = false

    @State private var newsMode = true

    private var isStarWorld: Bool { chat.bot == "qqnews" }

    private var redPacketDetailPresented: Binding<Bool> {
        Binding(
            get: { redPacketDetail != nil },
            set: { if !$0 { redPacketDetail = nil } }
        )
    }

    private func openActions(_ m: Message) {
        if selectMode { toggleSelect(m); return }
        let contentRect = frameBox.frames[m.id] ?? .zero
        menuRect = contentRect
        actionMessage = m
        for delay in [0.0, 0.12, 0.30] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard actionMessage?.id == m.id else { return }
                if let latest = frameBox.frames[m.id] {
                    menuRect = latest
                }
            }
        }
    }

    private var deletedMessageKey: String { "chris.deleted." + chat.id }

    private func loadDeletedMessageIds() {
        hiddenMessageIds = Set(UserDefaults.standard.stringArray(forKey: deletedMessageKey) ?? [])
    }

    private func persistDeletedMessageIds(_ newIds: [String]) {
        let valid = newIds.filter { !$0.isEmpty }
        guard !valid.isEmpty else { return }
        hiddenMessageIds.formUnion(valid)
        UserDefaults.standard.set(Array(hiddenMessageIds).sorted(), forKey: deletedMessageKey)
    }

    private func visibleMessages(_ rows: [Message]) -> [Message] {
        let sorted = rows.filter { !hiddenMessageIds.contains($0.id) }
            .sorted(by: messageSortsBefore)
        var seenClientIds = Set<String>()
        var recentProductCards: [String: Message] = [:]
        var out: [Message] = []
        out.reserveCapacity(sorted.count)

        for message in sorted {
            if let cid = message.clientId?.trimmingCharacters(in: .whitespacesAndNewlines),
               !cid.isEmpty {
                if !seenClientIds.insert(cid).inserted { continue }
            }

            if message.kindName == "mall" {
                let key = (message.senderId ?? "") + "\u{1F}" + message.body
                if let previous = recentProductCards[key],
                   duplicateProductCard(previous, message) {
                    continue
                }
                recentProductCards[key] = message
            }
            out.append(message)
        }
        return out
    }

    private func duplicateProductCard(_ first: Message, _ second: Message) -> Bool {
        guard first.senderId == second.senderId,
              first.body == second.body else { return false }
        if let a = TimeFmt.date(first.createdAt),
           let b = TimeFmt.date(second.createdAt) {
            return abs(b.timeIntervalSince(a)) <= 30
        }
        if let a = first.seq, let b = second.seq {
            return abs(b - a) <= 3
        }
        return false
    }

    private func messageSortsBefore(_ a: Message, _ b: Message) -> Bool {
        let ca = a.createdAt ?? "", cb = b.createdAt ?? ""
        if ca != cb { return ca < cb }
        let sa = a.seq ?? 0, sb = b.seq ?? 0
        if sa != sb { return sa < sb }
        return a.id < b.id
    }

    private func appendVisibleMessage(_ message: Message) {
        guard !hiddenMessageIds.contains(message.id) else { return }
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages.remove(at: index)
        }
        if let cid = message.clientId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !cid.isEmpty,
           messages.contains(where: { $0.clientId == cid }) {
            return
        }
        if message.kindName == "mall",
           messages.contains(where: {
               $0.kindName == "mall" && duplicateProductCard($0, message)
           }) {
            return
        }
        var low = 0, high = messages.count
        while low < high {
            let middle = (low + high) / 2
            if messageSortsBefore(message, messages[middle]) {
                high = middle
            } else {
                low = middle + 1
            }
        }
        messages.insert(message, at: low)
        if messages.count > maxMessageWindow {
            messages.removeFirst(messages.count - maxMessageWindow)
            hasOlder = true
        }
        rebuildIndex()
    }

    private func upsertVisibleMessage(_ message: Message) {
        appendVisibleMessage(message)
    }

    private func actionTitle(_ m: Message) -> String {
        let t = m.kindName == "text" ? m.body : "[" + ((m.kindName == "image" || m.kindName == "images") ? "图片" : m.kindName) + "]"
        return String(t.prefix(40))
    }

    private func actions(for m: Message) -> [MsgAction] {
        var list: [MsgAction] = [
            MsgAction(key: "copy", label: "复制", icon: "doc.on.doc"),
            MsgAction(key: "forward", label: "转发", icon: "arrowshape.turn.up.right")
        ]
        if m.kindName == "file", !m.isRecalled {
            list.append(MsgAction(key: "share", label: "分享", icon: "square.and.arrow.up"))
        }

        if readableText(m).isEmpty == false {
            list.append(MsgAction(key: "speak", label: "朗读", icon: "speaker.wave.2"))
        }

        if m.kindName == "audio", !m.isRecalled {
            list.insert(MsgAction(key: "asr", label: "转文字", icon: "text.bubble"), at: 0)
        }
        if !m.isRecalled {
            list.append(MsgAction(key: "fav", label: "收藏", icon: "star"))
            list.append(MsgAction(key: "quote", label: "引用", icon: "text.quote"))
        }
        if m.senderId == myId, !m.isRecalled {
            list.append(MsgAction(key: "recall", label: "撤回", icon: "arrow.uturn.backward", danger: true))
        }
        list.append(MsgAction(key: "multi", label: "多选", icon: "checkmark.circle"))
        list.append(MsgAction(key: "del", label: "删除", icon: "trash", danger: true))
        if m.senderId != myId {
            list.append(MsgAction(key: "report", label: "举报", icon: "exclamationmark.bubble"))
        }
        return list
    }

    private func readableText(_ m: Message) -> String {
        if m.isCallRecord { return m.callText }
        switch m.kindName {
        case "text", "link": return m.body
        default: return ""
        }
    }

    private func run(_ a: MsgAction, on m: Message) {
        switch a.key {
        case "asr":
            transcribeMessage(m)
        case "speak":
            Speaker.shared.speak(readableText(m))
            app.show(Tr("正在朗读…"))
        case "copy":
            UIPasteboard.general.string = m.kindName == "text" ? m.body : "[" + m.kindName + "]"
            app.show(Tr("已复制"))
        case "forward":
            forwardItems = [ForwardItem(kind: forwardedKind(m), content: m.body)]
            showForward = true
        case "share":
            prepareFileShare(m)
        case "fav":
            Task {
                let fav = favoritePayload(m)
                let ok = await API.shared.addFavorite(kind: fav.kind,
                                                      content: fav.content,
                                                      title: chat.name,
                                                      from: displayName(m))
                app.show(ok ? Tr("已收藏") : Tr("收藏失败"))
            }
        case "quote":
            quote = m
        case "recall":
            recall(m)
        case "multi":
            selectMode = true
            selected = [m.id]
        case "del":
            persistDeletedMessageIds([m.id])
            messages.removeAll { $0.id == m.id }
            rebuildIndex()
            app.show(Tr("已删除"))
        case "report":
            report(m)
        default:
            break
        }
    }

    private func toggleSelect(_ m: Message) {
        if selected.contains(m.id) { selected.remove(m.id) } else { selected.insert(m.id) }
    }

    private func exitSelectMode() {
        selectMode = false
        selected = []
        actionMessage = nil
    }

    private func mySelected() -> [Message] {
        messages.filter { selected.contains($0.id) }
    }

    private func forwardedKind(_ m: Message) -> String {
        switch m.kindName {

        case "images", "image", "file", "video", "livephoto", "location", "link":
            return m.kindName

        case "mall":
            return "mall"
        default:
            return "text"
        }
    }

    private func favoritePayload(_ m: Message) -> (kind: String, content: String) {
        let k = forwardedKind(m)
        if ["text", "image", "images", "transfer"].contains(k) { return (k, m.body) }
        var title = ""
        if let data = m.body.data(using: .utf8),
           let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            title = (o["name"] as? String) ?? (o["title"] as? String) ?? (o["text"] as? String) ?? ""
        }
        let label: String
        switch k {
        case "file": label = Tr("文件")
        case "video": label = Tr("视频")
        case "livephoto": label = Tr("实况")
        case "location": label = Tr("位置")
        case "link": label = Tr("链接")
        default: label = k
        }
        return ("text", "[" + label + "]" + (title.isEmpty ? "" : " " + title))
    }

    private func multiForward() {
        let picked = mySelected()
        guard !picked.isEmpty else { return }
        forwardItems = picked.map { ForwardItem(kind: forwardedKind($0), content: $0.body) }
        showForward = true
    }

    private func multiFavorite() {
        let picked = mySelected()
        guard !picked.isEmpty else { return }
        Task {
            var n = 0
            for m in picked {
                let fav = favoritePayload(m)
                if await API.shared.addFavorite(kind: fav.kind,
                                                content: fav.content, title: chat.name, from: displayName(m)) { n += 1 }
            }
            app.show(Tr("已收藏") + " \(n) " + Tr("条"))
            exitSelectMode()
        }
    }

    private func multiDelete() {
        let ids = Array(selected)
        guard !ids.isEmpty else { return }
        persistDeletedMessageIds(ids)
        messages.removeAll { ids.contains($0.id) }
        rebuildIndex()
        app.show(Tr("已删除") + " \(ids.count) " + Tr("条"))
        exitSelectMode()
    }

    @State private var focused = false
    @StateObject private var composerBridge = ChatComposerBridge()
    @ObservedObject private var recentPhotos = RecentPhotoStore.shared
    @ObservedObject private var realtime = Realtime.shared
    @ObservedObject private var recorder = VoiceRecorder.shared

    @State private var pressStart: Date?
    @State private var voiceStarting = false
    @State private var pushTask: Task<Void, Never>?

    @State private var unreadHere = 0

    @State private var scrollTick = 0

    @State private var pinTick = 0

    @State private var pinTask: Task<Void, Never>? = nil

    @State private var settleTask: Task<Void, Never>? = nil
    @State private var hasOlder = false
    @State private var loadingOlder = false

    @State private var loadingAllGroupHistory = false
    @State private var holdScroll = false
    @State private var allowSettledBottom = false
    @State private var atBottom = true

    @State private var wasAtBottom = true

    @State private var scroller: ScrollViewProxy?

    @State private var lastOlderLoad = Date.distantPast

    @State private var lastReadSyncAt = Date.distantPast

    @State private var pendingMedia: MediaSendSheet.Payload?

    @State private var draftImages: [UIImage] = []

    @State private var videoToPlay: URL?

    @State private var videoPayload = ""

    @State private var peerTyping = ""
    @State private var typingClear: Task<Void, Never>?

    @State private var lastTypingSent = Date.distantPast

    @State private var sendingMedia = ""

    @State private var sendingPreview: UIImage?
    @State private var sendProgress: Double = 0
    @State private var sendingFileName = ""
    @State private var sendingFileBytes = 0
    @State private var sendingFileProgress: Double? = nil
    @State private var voiceMode = false

    @State private var mentionMembers: [User] = []
    @State private var mentionQuery = ""

    @State private var mentionIds: [String] = []

    @State private var lastInputSnapshot = ""

    private var myId: String { app.me?.id ?? "" }
    private var isGroup: Bool {

        if chat.type == "group" { return true }
        if (chat.memberIds ?? []).count >= 3 { return true }
        return false
    }

    /// 群历史按需分页，不在进群时一次性合并最多 5000 条。
    private var shouldLoadCompleteGroupHistory: Bool { false }

    private let initialMessageWindow = 200
    /* 首屏只放最近 200 条，更早历史由用户继续上滑按页加载。
       这能避免进群时一次合并数千条消息造成明显掉帧。 */
    private let maxMessageWindow = 5_000

    private var navTitle: String {
        guard isGroup else {
            if let peer = peerUserId, let user = app.contact(for: peer) {
                let remark = (user.remark ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return remark.isEmpty ? user.name : remark
            }
            return liveChat.name
        }
        return liveChat.name
    }

    private var navTitleShown: String {
        if selectMode { return Tr("已选择") + " \(selected.count) " + Tr("项") }
        if loadingAllGroupHistory { return Tr("正在同步全部消息…") }
        guard !peerTyping.isEmpty else { return navTitle }
        return isGroup ? "有人正在输入…" : "对方正在输入…"
    }

    private var chatNavigationStatus: String {
        guard !selectMode else { return "" }
        if !peerTyping.isEmpty {
            return isGroup ? "有人正在输入…" : "对方正在输入…"
        }
        if isGroup {
            let count = liveChat.memberCount ?? (liveChat.memberIds?.count ?? 0)
            return count > 0 ? "\(count)人星友连接" : ""
        }
        if let peer = peerUserId, let user = app.contact(for: peer) {
            return user.online == true ? "在线" : "离线"
        }
        return ""
    }

    private var whatsAppChatSubtitle: String {
        if loadingAllGroupHistory { return navTitle }
        if !peerTyping.isEmpty {
            return isGroup ? "有人正在输入…" : "对方正在输入…"
        }
        return chatNavigationStatus.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isPeerTyping: Bool {
        !peerTyping.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var navAvatarPath: String {
        let raw = (liveChat.avatar ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty { return raw }
        guard let peer = peerUserId, let user = app.contact(for: peer) else { return "" }
        return (user.avatarPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var whatsAppChatAvatar: some View {
        Group {
            if isGroup,
               navAvatarPath.isEmpty || navAvatarPath.contains("/uploads/group-") {
                GroupAvatarMosaic(chatId: liveChat.id,
                                  memberIds: liveChat.memberIds ?? [],
                                  size: 38, radius: 19)
            } else {
                Avatar(path: navAvatarPath, size: 38, radius: 19,
                       circle: true, group: isGroup)
            }
        }
        .frame(width: 38, height: 38)
        .clipShape(Circle())
    }

    private var whatsAppChatHeader: some View {
        let hideChrome = false
        let title = loadingAllGroupHistory ? Tr("正在同步全部消息…") : navTitle

        return HStack(spacing: 0) {
            if let back = navBackAction {
                Button(action: back) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(adaptiveTopInk)
                        .frame(width: 42, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Tr("返回"))
            }

            if let badge = leftUnreadBadge {
                badge
                    .padding(.leading, 3)
                    .padding(.trailing, 5)
            }

            if !hideChrome {
                Button {
                    if isGroup { showGroupInfo = true } else { showChatInfo = true }
                } label: {
                    HStack(spacing: 10) {
                        whatsAppChatAvatar

                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(pf(17, .semibold))
                                .foregroundStyle(adaptiveTopInk)
                                .lineLimit(1)
                                .truncationMode(.tail)

                            if isPeerTyping {
                                HStack(spacing: 5) {
                                    ChatTypingDots(color: Color(hex: 0x25D366))
                                    Text(isGroup ? Tr("有人正在输入") : Tr("正在输入"))
                                        .font(pf(12.5, .regular))
                                        .foregroundStyle(adaptiveTopInk.opacity(
                                            topBarUsesLightInk ? 0.78 : 0.72
                                        ))
                                        .lineLimit(1)
                                }
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            } else if !whatsAppChatSubtitle.isEmpty {
                                Text(whatsAppChatSubtitle)
                                    .font(pf(12.5, .regular))
                                    .foregroundStyle(adaptiveTopInk.opacity(
                                        topBarUsesLightInk ? 0.78 : 0.72
                                    ))
                                    .lineLimit(1)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)

                Spacer(minLength: 6)

                Button {
                    showCallChoice = true
                } label: {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(C.red))
                        .frame(width: 42, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Tr("语音通话"))

                Menu {
                    Button {
                        showChatTheme = true
                    } label: {
                        Label(Tr("聊天主题"), systemImage: "paintpalette.fill")
                    }

                    Button {
                        if isGroup { showGroupInfo = true } else { showChatInfo = true }
                    } label: {
                        Label(Tr("会话信息"), systemImage: "info.circle")
                    }

                    if isGroup && !groupAnnouncement.isEmpty {
                        Button {
                            announcePage = groupAnnouncement
                            showAnnouncePage = true
                        } label: {
                            Label(Tr("群公告"), systemImage: "megaphone")
                        }
                    }

                    Button {
                        showChatFavorites = true
                    } label: {
                        Label(Tr("收藏"), systemImage: "bookmark")
                    }

                    if isStarWorld {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                newsMode.toggle()
                            }
                        } label: {
                            Label(Tr("世界"), systemImage: "globe.asia.australia")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(adaptiveTopInk)
                        .frame(width: 42, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Tr("更多"))
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.leading, 2)
        .padding(.trailing, 2)
        .frame(height: L.navH)
        .animation(.easeOut(duration: 0.18), value: hideChrome)
    }

    private var chatTopNavigation: AnyView {
        if selectMode {
            return AnyView(
                NavBar(title: navTitleShown, back: nil,
                       titleColor: adaptiveTopInk,
                       titleOutline: .clear,
                       backColor: adaptiveTopInk,
                       titleView: chatNavigationTitle,
                       leftExtra: nil,
                       backGlass: false,
                       floating: false,
                       titleGlass: false,
                       rightGlass: false) {
                    Button {
                        exitSelectMode()
                    } label: {
                        Text(Tr("取消"))
                            .font(pf(15.5))
                            .foregroundColor(adaptiveTopInk)
                            .frame(width: 52, height: 36)
                    }
                    .buttonStyle(.plain)
                }
            )
        }
        return AnyView(whatsAppChatHeader)
    }

    private var chatNavigationTitle: AnyView {
        let text = (selectMode || loadingAllGroupHistory) ? navTitleShown : navTitle
        return AnyView(
            VStack(spacing: 1) {
                HStack(spacing: 5) {
                    Text(text)
                        .font(pf(17, .semibold))
                        .foregroundStyle(chat.showsOfficialMark
                                         ? AnyShapeStyle(OfficialAccountVisual.name)
                                         : AnyShapeStyle(adaptiveTopInk))
                        .shadow(color: chat.showsOfficialMark
                                ? OfficialAccountVisual.glow : .clear,
                                radius: 3)
                        .lineLimit(1)
                }
                if !chatNavigationStatus.isEmpty {
                    Text(chatNavigationStatus)
                        .font(pf(10.5, .medium))
                        .foregroundColor(adaptiveTopInk.opacity(topBarUsesLightInk ? 0.84 : 0.78))
                        .lineLimit(1)
                }
            }
        )
    }

    private var chatSectionBar: some View {
        HStack(spacing: 0) {
            chatSectionButton("聊天", active: !(isStarWorld && newsMode), enabled: true) {
                if isStarWorld && newsMode {
                    withAnimation(.easeInOut(duration: 0.18)) { newsMode = false }
                }
            }
            chatSectionButton("世界", active: isStarWorld && newsMode, enabled: isStarWorld) {
                guard isStarWorld else {
                    app.show(Tr("当前会话暂无世界内容"))
                    return
                }
                withAnimation(.easeInOut(duration: 0.18)) { newsMode = true }
            }
            chatSectionButton("公告",
                              active: false,
                              enabled: isGroup && !groupAnnouncement.isEmpty) {
                announcePage = groupAnnouncement
                showAnnouncePage = true
            }
            chatSectionButton("置顶", active: false, enabled: true) {
                app.show(Tr("暂无置顶消息"))
            }
            chatSectionButton("收藏", active: false, enabled: true) {
                showChatFavorites = true
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 36)
    }

    private func chatSectionButton(_ title: String,
                                   active: Bool,
                                   enabled: Bool,
                                   action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(Tr(title))
                .font(pf(13, active ? .semibold : .medium))
                .foregroundColor(adaptiveTopInk.opacity(active ? 1 : (enabled ? 0.72 : 0.32)))
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var navBackAction: (() -> Void)? {
        selectMode ? nil : { dismiss() }
    }

    private func exitChatNow() {
        showGroupInfo = false
        showChatInfo = false
        app.pendingPushChatId = nil
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            app.openChat = nil
            app.wantChatsTab = true
        }
    }

    private func reportTyping() {
        guard Date().timeIntervalSince(lastTypingSent) > 2.0 else { return }
        lastTypingSent = Date()
        Realtime.shared.sendJSON(["type": "typing", "chatId": chat.id])
    }

    private var peerUserId: String? {
        let me = myId
        guard !me.isEmpty else { return nil }
        guard let ids = chat.memberIds, ids.count == 2, ids.contains(me) else { return nil }
        guard let other = ids.first(where: { $0 != me }), !other.isEmpty else { return nil }
        return other
    }

    private var callActiveHere: Bool {
        let c = CallCenter.shared
        guard c.phase.isBusy, let peer = peerUserId else { return false }
        return c.peerId == peer
    }

    private var callBarText: String {
        let c = CallCenter.shared
        switch c.phase {
        case .incoming:   return c.isVideo ? "邀请你视频通话" : "邀请你语音通话"
        case .outgoing:   return c.isVideo ? "正在等待对方接受视频通话" : "正在等待对方接受语音通话"
        case .connecting: return "正在接通…"
        case .active:     return c.isVideo ? "正在视频通话中" : "正在语音通话中"
        case .idle:       return ""
        }
    }

    private func startRealCall(video: Bool) {

        if !isGroup && peerBanned {
            app.show(Tr("对方账号已被管理员封禁，暂时无法通话"))
            return
        }
        if isGroup {
            if CallCenter.shared.phase != .idle { app.show(Tr("正在通话中")); return }
            CallCenter.shared.resetIfStale()
            CallCenter.shared.startGroupCall(chatId: chat.id, title: chat.name ?? "", video: video)
            return
        }
        guard let peer = peerUserId else { app.show(Tr("找不到对方账号，先刷新一下会话")); return }
       if CallCenter.shared.phase != .idle { app.show(Tr("正在通话中")); return }

        CallCenter.shared.resetIfStale()
        if CallCenter.shared.phase != .idle { app.show(Tr("正在通话中")); return }

        let peerName = app.contact(for: peer)?.name ?? chat.name
        CallCenter.shared.start(peerId: peer, name: peerName, avatar: chat.avatar ?? "", video: video)
    }

    private func displayName(_ message: Message) -> String {
        if let n = message.senderName, !n.isEmpty { return n }
        return app.contact(for: message.senderId ?? "")?.name ?? ""
    }

    private var burnOn: Bool { (app.chats.first { $0.id == chat.id }?.burn ?? chat.burn) ?? false }

    private var hasBurnMsg: Bool { messages.contains { $0.burn == true } }
    private var needBurnSweep: Bool { burnOn || hasBurnMsg }

    private var backgroundPath: String {
        // 主题是一整套外观。用户主动选过主题后，旧的自定义壁纸不再遮挡主题背景。
        if ChatThemeStore.shared.hasExplicitSelection(chatId: chat.id) {
            return ""
        }
        if let synced = app.me?.chatBackgrounds?[chat.id],
           !synced.isEmpty, synced != "auto" {
            return normalizedChatBackground(synced)
        }
        let per = ChatBgStore.shared.get(chat.id)
        if !per.isEmpty, per != "auto" { return normalizedChatBackground(per) }
        let v = effectiveGlobalChatBackground(app.me?.chatBackground)
        if !v.isEmpty, v != "auto" { return normalizedChatBackground(v) }
        // 未主动选过主题时保留旧的全局面板壁纸；选过主题后由整套主题接管背景。
        return ""
    }

    private var usesPlainDefaultChatChrome: Bool {
        backgroundPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var backgroundEffect: ChatBackgroundEffect {
        scheme == .dark ? .blackBlur : .original
    }

    private var resolvedBackgroundEffect: ChatBackgroundEffect {
        backgroundEffect.resolved(for: scheme)
    }

    private var senderNameUsesLightInk: Bool {
        switch resolvedBackgroundEffect {
        case .blackBlur: return true
        case .whiteBlur: return false
        case .original, .auto: break
        }
        let path = normalizedChatBackground(backgroundPath)
        switch path {
        case "solid:white":
            return false
        case "solid:black":
            return true
        default:
            break
        }
        if let backgroundLuminance { return backgroundLuminance < 0.46 }
        return scheme == .dark
    }

    private var adaptiveSystemInk: Color {
        senderNameUsesLightInk
            ? Color.white.opacity(0.92)
            : Color(hex: 0x3F4247)
    }

    private var composerUsesLightInk: Bool {
        switch resolvedBackgroundEffect {
        case .blackBlur: return true
        case .whiteBlur: return false
        case .original, .auto: break
        }
        let path = normalizedChatBackground(backgroundPath)
        switch path {
        case "solid:white":
            return false
        case "solid:black":
            return true
        default:
            break
        }
        if let backgroundBottomLuminance { return backgroundBottomLuminance < 0.46 }
        return senderNameUsesLightInk
    }

    private var topBarUsesLightInk: Bool {
        if isStarWorld && newsMode { return scheme == .dark }
        switch resolvedBackgroundEffect {
        case .blackBlur: return true
        case .whiteBlur: return false
        case .original, .auto: break
        }
        let path = normalizedChatBackground(backgroundPath)
        switch path {
        case "solid:white":
            return false
        case "solid:black":
            return true
        default:
            break
        }
        if let backgroundTopLuminance {
            return Self.prefersLightTopInk(for: backgroundTopLuminance)
        }
        return senderNameUsesLightInk
    }

    private var newsMaskColor: Color {
        Color(uiColor: .systemGroupedBackground)
    }

    private static func prefersLightTopInk(for luminance: Double) -> Bool {
        let lightInkLuminance = 0.86
        let darkInkLuminance = 0.018
        let lightContrast = (lightInkLuminance + 0.05) / (luminance + 0.05)
        let darkContrast = (luminance + 0.05) / (darkInkLuminance + 0.05)
        return lightContrast > darkContrast
    }

    private var adaptiveTopInk: Color {
        topBarUsesLightInk ? .white : .black
    }

    private var adaptiveTopAccent: Color {
        topBarUsesLightInk
            ? Color(hex: 0x75C4FF)
            : Color(hex: 0x0866D8)
    }

    private var adaptiveTopOutline: Color {
        topBarUsesLightInk
            ? Color.black.opacity(0.82)
            : Color.white.opacity(0.86)
    }

    private var adaptiveSystemSecondaryInk: Color {
        senderNameUsesLightInk
            ? Color.white.opacity(0.78)
            : Color(hex: 0x62666C)
    }

    private var adaptiveSystemSurface: Color {
        senderNameUsesLightInk
            ? Color.black.opacity(0.40)
            : Color.white.opacity(0.76)
    }

    private var adaptiveSystemBorder: Color {
        senderNameUsesLightInk
            ? Color.white.opacity(0.16)
            : Color.black.opacity(0.07)
    }

    private var adaptiveMicInk: Color {
        composerUsesLightInk
            ? Color(hex: 0x5BE39A)
            : Color(hex: 0x117A50)
    }

    private var adaptiveEmojiInk: Color {
        composerUsesLightInk ? .white : Color(hex: 0x111111)
    }

    private var adaptivePlusInk: Color {
        composerUsesLightInk ? .white : Color(hex: 0x111111)
    }

    private var adaptiveComposerSurface: Color {
        composerUsesLightInk
            ? Color.black.opacity(0.34)
            : Color.white.opacity(0.82)
    }

    private var composerTextInk: Color {
        composerUsesLightInk ? .white : Color(hex: 0x111111)
    }

    private var adaptiveComposerStroke: Color {
        composerUsesLightInk
            ? Color.white.opacity(0.16)
            : Color.black.opacity(0.07)
    }

    private func refreshBackgroundLuminance() async {
        let path = normalizedChatBackground(backgroundPath)
        guard !path.isEmpty else {
            backgroundLuminance = nil
            backgroundTopLuminance = nil
            backgroundBottomLuminance = nil
            wallpaperTopTint = nil
            wallpaperBottomTint = nil
            return
        }
        switch path {
        case "solid:white":
            backgroundLuminance = 1
            backgroundTopLuminance = 1
            backgroundBottomLuminance = 1
            wallpaperTopTint = .white
            wallpaperBottomTint = .white
            return
        case "solid:black":
            backgroundLuminance = 0
            backgroundTopLuminance = 0
            backgroundBottomLuminance = 0
            wallpaperTopTint = .black
            wallpaperBottomTint = .black
            return
        default:
            break
        }

        var data = await Task.detached(priority: .utility) {
            ImageStore.shared.diskRead(path)
        }.value
        if data == nil, let url = API.shared.assetURL(path) {
            data = try? await API.shared.assetData(url)
        }
        guard !Task.isCancelled, let data else { return }

        let samples = await Task.detached(priority: .utility) {
            () -> (full: [Double], top: [Double], bottom: [Double])? in
            guard let image = RemoteImage.downsampled(data, maxSide: 64)?.cgImage else {
                return nil
            }
            guard let full = Self.averageImageSample(
                image,
                normalizedRect: CGRect(x: 0, y: 0, width: 1, height: 1)
            ),
            let top = Self.averageImageSample(
                image,
                normalizedRect: CGRect(x: 0, y: 0.66, width: 1, height: 0.34)
            ),
            let bottom = Self.averageImageSample(
                image,
                normalizedRect: CGRect(x: 0, y: 0, width: 1, height: 0.34)
            ) else { return nil }
            return (full, top, bottom)
        }.value
        guard !Task.isCancelled,
              path == normalizedChatBackground(backgroundPath),
              let samples else { return }
        backgroundLuminance = samples.full[0]
        backgroundTopLuminance = samples.top[0]
        backgroundBottomLuminance = samples.bottom[0]
        wallpaperTopTint = Color(
            red: samples.top[1],
            green: samples.top[2],
            blue: samples.top[3]
        )
        wallpaperBottomTint = Color(
            red: samples.bottom[1],
            green: samples.bottom[2],
            blue: samples.bottom[3]
        )
    }

    private static func averageImageSample(_ image: CGImage,
                                           normalizedRect: CGRect) -> [Double]? {
        let source = CIImage(cgImage: image)
        let extent = source.extent
        let sampleRect = CGRect(
            x: extent.minX + normalizedRect.minX * extent.width,
            y: extent.minY + normalizedRect.minY * extent.height,
            width: normalizedRect.width * extent.width,
            height: normalizedRect.height * extent.height
        )
        let output = source.applyingFilter("CIAreaAverage", parameters: [
            kCIInputExtentKey: CIVector(cgRect: sampleRect)
        ])
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        pixel.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            context.render(output,
                           toBitmap: base,
                           rowBytes: 4,
                           bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                           format: .RGBA8,
                           colorSpace: CGColorSpaceCreateDeviceRGB())
        }
        func linear(_ value: UInt8) -> Double {
            let c = Double(value) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(pixel[0])
            + 0.7152 * linear(pixel[1])
            + 0.0722 * linear(pixel[2])
        return [
            luminance,
            Double(pixel[0]) / 255,
            Double(pixel[1]) / 255,
            Double(pixel[2]) / 255
        ]
    }

    private var groupAnnouncement: String {
        guard isGroup else { return "" }
        let live = app.chats.first(where: { $0.id == chat.id })?.announce ?? chat.announce ?? ""
        return live.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var chatDetailMain: some View {
        ZStack {
            chatBackdrop
                .ignoresSafeArea()
                .transaction { $0.animation = nil }
                .zIndex(0)

            messageList

                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded { dismissTyping() })

                .simultaneousGesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { _ in
                            guard !dismissDragActive else { return }
                            dismissDragActive = true
                            dismissTyping()
                            ScrollGate.shared.setScrolling(true)
                        }
                        .onEnded { _ in
                            dismissDragActive = false
                            ScrollGate.shared.setScrolling(false)
                        },
                    including: (focused || panel != .none) ? .all : .none
                )
                .zIndex(1)

            if isStarWorld && newsMode {
                NewsFeedView(compact: true)
                    .zIndex(12)
            }

            if UIConfig.num("chatScrollDiag", 0) > 0 {
                VStack(spacing: 0) {
                    ChatScrollDiagView()
                    Spacer(minLength: 0)
                }
                .zIndex(60)
            }

            if !atBottomNow {
                VStack {
                    Spacer(minLength: 0)
                    HStack {
                        Spacer(minLength: 0)
                        VStack(spacing: 8) {

                            if let lastMsg = messages.last?.id {
                                Button {
                                    withAnimation(.easeOut(duration: 0.26)) {
                                        scroller?.scrollTo(lastMsg, anchor: .bottom)
                                    }
                                    unreadHere = 0
                                } label: {
                                    HStack(spacing: 5) {
                                        if unreadHere > 0 {
                                            Text(Lang.isRussian
                                                 ? "\(unreadHere) новых сообщений"
                                                 : (Lang.isEnglish
                                                    ? "\(unreadHere) new messages"
                                                    : "\(unreadHere) 条新消息"))
                                                .font(pf(11.5, .medium))
                                                .foregroundColor(C.label)
                                        }
                                        Image(systemName: "chevron.down")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(C.label)
                                    }
                                    .padding(.horizontal, unreadHere > 0 ? 11 : 0)
                                    .frame(minWidth: 34, minHeight: 34)
                                    .background(Capsule().fill(.regularMaterial))
                                    .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 0.5))
                                    .shadow(color: Color.black.opacity(0.18), radius: 8, y: 3)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.trailing, 12)
                        .padding(.bottom, 10)
                    }
                }
                .zIndex(55)
            }

        }

        .onChange(of: recorder.seconds) { s in
            if recorder.recording, s >= recorder.maxSeconds { finishVoice() }
        }

        .onAppear {
            if recorder.stale {
                CrashCatcher.note("录音", "进聊天页发现孤儿录音，已清掉")
                recorder.forceStop()
            }
            if input.isEmpty {
                let savedDraft = drafts.text(for: chat.id)
                if !savedDraft.isEmpty {
                    input = savedDraft
                    lastInputSnapshot = savedDraft
                }
            }
            if applyNote.isEmpty { applyNote = "我是" + (app.me?.nickname ?? "") }
        }

        .alert(Tr("发送朋友验证"), isPresented: $showApply) {
            TextField(Tr("验证消息"), text: $applyNote)
            Button(Tr("发送")) { sendApply() }
            Button(Tr("取消"), role: .cancel) { }
        } message: {
            Text(Tr("对方通过验证后，你们就能聊天了。"))
        }

        .onChange(of: focused) { pinAfterFocusChange($0) }
        .onChange(of: panel) { _ in pinToBottomSoon() }

        .safeAreaInset(edge: .top, spacing: 0) {

            AnyView(VStack(spacing: 0) {

            VStack(spacing: 0) {
            chatTopNavigation
            }
            .background {
                Group {
                    if isStarWorld && newsMode {
                        newsMaskColor
                    } else {
                        ChatImmersiveEdgeMask(path: backgroundPath,
                                              edge: .top,
                                              tint: wallpaperTopTint,
                                              dark: topBarUsesLightInk,
                                              effect: backgroundEffect,
                                              preset: ChatTheme.preset,
                                              themeVersion: chatTheme.version)
                    }
                }
                .ignoresSafeArea(edges: .top)
            }
            if !isGroup && peerBanned {
                HStack(spacing: 11) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(C.red)
                        .frame(width: 34, height: 34)
                        .background(C.red.opacity(0.10), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Tr("该账号已被管理员封禁"))
                            .font(pf(13.5, .semibold))
                            .foregroundColor(C.label)
                        if !peerBanReason.isEmpty {
                            Text(Tr("原因：") + peerBanReason)
                                .font(pf(12))
                                .foregroundColor(C.subLabel)
                                .lineLimit(1)
                        } else {
                            Text(Tr("暂时无法发送消息或发起通话"))
                                .font(pf(12))
                                .foregroundColor(C.subLabel)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    ZStack {
                        Rectangle().fill(.regularMaterial)
                        Color.red.opacity(0.055)
                    }
                }
                .overlay(alignment: .bottom) {
                    Rectangle().fill(C.red.opacity(0.16)).frame(height: 0.5)
                }
            }

            if callActiveHere {
                Button {
                    CallCenter.shared.restore()
                } label: {
                    HStack(spacing: 8) {
                        Circle().fill(C.green).frame(width: 7, height: 7)
                        Text(callBarText)
                            .font(pf(13.5))
                            .foregroundColor(C.green)
                        Spacer(minLength: 0)
                        Text(Tr("回到通话 ›"))
                            .font(pf(13.5))
                            .foregroundColor(C.green.opacity(0.9))
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(.regularMaterial)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(C.green.opacity(0.18)).frame(height: 0.5)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            })
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AnyView(Group {
                if selectMode {
                    MultiSelectBar(count: selected.count,
                                   onForward: { multiForward() },
                                   onFavorite: { multiFavorite() },
                                   onDelete: { showMultiDeleteConfirm = true })
                } else {
                    VStack(spacing: 0) {
                        if chat.sysTeam == true, !focused, panel == .none {
                            AnyView(sysTeamToolsBar)
                        }
                        AnyView(composer)

                            .padding(.bottom, UIConfig.num("chatKeyboardManual", 1) > 0
                                     ? max(0, kbHeight - (UIConfig.num("chatKbFlush", 1) > 0 ? L.safeBottom : 0))
                                     : 0)
                    }
                }
            })
        }

        .modifier(KeyboardLiftDisable(enabled: UIConfig.num("chatKeyboardManual", 1) > 0))
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { n in
            guard UIConfig.num("chatKeyboardManual", 1) > 0 else { return }
            guard let f = n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let screenH = (UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.screen.bounds.height }.first) ?? UIScreen.main.bounds.height
            let h = max(0, screenH - f.origin.y)
            withAnimation(.easeOut(duration: 0.25)) { kbHeight = h }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.22)) { kbHeight = 0 }
        }
        .onChange(of: panel) { next in
            if next != .none { kbHeight = 0 }
            if next != .emoji { emojiPanelExpanded = false }
        }

        .overlay {
            GeometryReader { geo in
                if let m = actionMessage {
                    let g = geo.frame(in: .global)
                    let box = MsgMenuBox.size(actions(for: m).count)
                    let rect = menuRect == .zero
                        ? CGRect(x: g.midX, y: g.midY, width: 0, height: 0)
                        : menuRect
                    let above = (rect.minY - g.minY) > (box.height + 16)
                    let x = min(max(8, rect.midX - g.minX - box.width / 2),
                                max(8, geo.size.width - box.width - 8))

                    let gap = UIConfig.num("msgMenuGap", 6)
                    let y = above ? (rect.minY - g.minY - box.height - gap)
                                  : min(geo.size.height - box.height - 8, rect.maxY - g.minY + gap)
                    ZStack(alignment: .topLeading) {
                        Color.black.opacity(0.03)
                            .ignoresSafeArea()
                            .onTapGesture { actionMessage = nil }
                        MsgMenuBox(actions: actions(for: m)) { a in
                            actionMessage = nil
                            run(a, on: m)
                        }
                        .offset(x: x, y: max(8, y))
                    }
                }
            }
            .zIndex(30)
        }
    }

    private var chatDetailPanels: some View {
        chatDetailMain
        .sheet(isPresented: $showForward) {
            ForwardPickerView(items: forwardItems) { }
                .environmentObject(app)
        }
        .sheet(item: $quoteInspect) { item in
            QuoteInspectSheet(
                quote: item.quote,
                onOpenImage: { path in
                    quoteInspect = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        openImage(path)
                    }
                },
                onJump: { id in
                    quoteInspect = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        jumpToMessage(id)
                    }
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }

        .confirmationDialog(Tr("音视频通话"), isPresented: $showCallChoice, titleVisibility: .hidden) {
            Button(Tr("语音通话")) { startRealCall(video: false) }
            Button(Tr("视频通话")) { startRealCall(video: true) }
            Button(Tr("取消"), role: .cancel) { }
        }

        .confirmationDialog(Tr("删除所选消息？"), isPresented: $showMultiDeleteConfirm,
                            titleVisibility: .visible) {
            Button(Tr("删除"), role: .destructive) { multiDelete() }
            Button(Tr("取消"), role: .cancel) { }
        } message: {
            Text(Tr("删除后，将无法恢复。"))
        }

        .confirmationDialog(redialTitle, isPresented: Binding(
            get: { redialAsk != nil },
            set: { if !$0 { redialAsk = nil } }
        ), titleVisibility: .visible) {
            if redialAsk?.isVideoCall == true {
                Button(Tr("视频通话")) { startRedial(true) }
                Button(Tr("语音通话")) { startRedial(false) }
            } else {
                Button(Tr("语音通话")) { startRedial(false) }
                Button(Tr("视频通话")) { startRedial(true) }
            }
            Button(Tr("取消"), role: .cancel) { redialAsk = nil }
        }

        .fullScreenCover(isPresented: $showChatInfo, onDismiss: {
            Task { await refreshPeerRelation() }
        }) {
            NavigationStack {
                DirectChatInfoView(chat: chat, onExitChat: exitChatNow)
                    .environmentObject(app)
            }
        }
        .fullScreenCover(isPresented: $showChatTheme, onDismiss: {
            chatTheme.refresh(chat.id)
        }) {
            ChatThemePickerView(chatId: chat.id)
        }
        .sheet(item: $sysToolsPage) { page in
            sysToolsPageView(page)
                .environmentObject(app)
        }
        .swipeBack { dismiss() }
        .hidesTabBar()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showPhoto) {

            MediaPicker(onImage: { image in
                            pendingMedia = .image(image, nativeCamera: false)
                        },
                        onVideo: { url in
                            Task {
                                let cover = await MediaTool.firstFrame(url)
                                pendingMedia = .video(url, cover)
                            }
                        },
                        onLive: { image, url in pendingMedia = .live(image, url) },
                        maxImages: 9,
                        onImages: { stageDraftImages($0) },
                        onNotice: { msg in app.show(msg) })
        }
        .fullScreenCover(isPresented: $showCamera) {
            NativeCameraView(initialMode: .photo,
                             onPick: { image in
                                 pendingMedia = .image(image, nativeCamera: true)
                             },
                             onVideo: { url in sendRecordedVideo(url) })
        }

        .fullScreenCover(isPresented: $showCameraVideo, onDismiss: {
            guard let url = recordedVideo else { return }
            recordedVideo = nil
            sendRecordedVideo(url)
        }) {
            NativeCameraView(initialMode: .video,
                             onPick: { image in
                                 pendingMedia = .image(image, nativeCamera: true)
                             },
                             onVideo: { url in
                                 recordedVideo = url
                                 showCameraVideo = false
                             })
        }

        .sheet(isPresented: $showPickCard) {
            PickContactView { u in sendCard(u) }
                .environmentObject(app)
        }
        .sheet(isPresented: $showLocation) {
            LocationSheet { payload in send(kind: "location", content: payload) }
        }

        .confirmationDialog(Tr("位置"), isPresented: $showLocationMenu, titleVisibility: .visible) {
            Button(Tr("发送位置")) { showSendLocation = true }
            Button(Tr("共享实时位置")) { showLiveLocation = true }
            Button(Tr("取消"), role: .cancel) { }
        }
        .sheet(isPresented: $showSendLocation) {
            SendLocationView { payload in send(kind: "location", content: payload) }
        }
        .sheet(isPresented: $showLiveLocation) {
            LiveLocationView(chat: chat) {
                send(kind: "text", content: "📍 我发起了共享实时位置，点＋→位置→共享实时位置就能加入")
            }
            .environmentObject(app)
        }
        .sheet(isPresented: $showTransfer, onDismiss: {

            Task { await load(initial: false); await app.loadChats() }
        }) {

            TransferView(chat: chat, onPaid: {
                Task { await load(initial: false); await app.loadChats() }
            })
        }

        .sheet(isPresented: $showSendRedPacket) {
            RedPacketSendView(chat: chat) { _ in

                if UIConfig.num("redPacketRain", 1) > 0 { rainOn = true }
                Task { await load(initial: false); await app.loadChats() }
            }
            .environmentObject(app)
        }
        .overlay {
            if rainOn {
                RedPacketRain(duration: UIConfig.num("redPacketRainSec", 3.2)) { rainOn = false }
                    .zIndex(30)
            }
        }
    }

    private var chatDetailCovers: some View {
        chatDetailPanels
        .fullScreenCover(item: $openRedPacket) { info in
            RedPacketOpenView(info: info, myId: myId) { id in
                redPacketDetail = id
            }
            .environmentObject(app)
        }
        .sheet(isPresented: redPacketDetailPresented) {
            if let id = redPacketDetail {
                RedPacketDetailView(id: id, myId: myId).environmentObject(app)
            }
        }
        .fullScreenCover(isPresented: $showCall) {
            AICallView(chat: chat)
        }
        .fullScreenCover(item: $viewer) { item in

            PhotoPager(paths: item.paths, startIndex: item.index, showActions: true) { viewer = nil }
        }
        .modifier(TapAvatarCard(cardUser: $cardUser))
        .sheet(isPresented: $botCard) {
            BotCardView(chat: chat).environmentObject(app)
        }
        .fullScreenCover(item: $web) { SafariSheet(url: $0.url).ignoresSafeArea() }

        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == "http" || url.scheme == "https" {
                if ExternalLinkRouter.openIfNeeded(url) { return .handled }
                web = WebURL(url: url)
                return .handled
            }
            return .systemAction
        })

        .sheet(item: $openLocation) { p in
            LocationDetailView(point: p).environmentObject(app)
        }
        .onChange(of: messages.count) { _ in autoOpenShopCard() }

        .fullScreenCover(isPresented: $showGroupInfo) {
            NavigationStack {
                GroupInfoView(chat: chat, onExitChat: exitChatNow)
                    .environmentObject(app)
            }
        }
        .sheet(isPresented: $showSearch) { ChatSearchView(chat: chat) }
        .onReceive(NotificationCenter.default.publisher(for: ChatSearchJump.didRequest)) { note in
            guard let target = ChatSearchJump.destination(from: note),
                  target.chatId == chat.id else { return }
            showSearch = false
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 350_000_000)
                jumpToMessage(target.messageId, seq: target.seq)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .chrisChatCleared)) { note in
            guard let chatId = note.object as? String, chatId == chat.id else { return }
            messages.removeAll()
            outbox.removeAll()
            selected.removeAll()
            selectMode = false
            hasOlder = false
            hiddenMessageIds.removeAll()
            UserDefaults.standard.removeObject(forKey: deletedMessageKey)
            rebuildIndex()
            DispatchQueue.main.async { scroller?.scrollTo("__bottom", anchor: .bottom) }
        }

        .sheet(isPresented: $showStickerStore, onDismiss: { Task { await loadMyStickers() } }) {
            StickerView().environmentObject(app)
        }

        .fullScreenCover(isPresented: $showCaptureSticker) {
            StickerCamera { image in captureSticker(image) }
        }

        .sheet(isPresented: $showPickMusic) {
            ListenView(sendTo: chat) { t in sendMusic(t) }
                .environmentObject(app)
        }

        .fullScreenCover(isPresented: $showAnnouncePage) {
            GroupAnnounceView(text: announcePage, groupName: isGroup ? chat.name : "")
        }
        .sheet(isPresented: $showChatFavorites) {
            NavigationStack {
                FavoritesView()
                    .environmentObject(app)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .hidesTabBar()
        .sheet(isPresented: Binding(
            get: { billInfo != nil },
            set: { if !$0 { billInfo = nil } }
        )) {
            if let info = billInfo {
                BillDetailView(chat: chat, info: info)
            }
        }

        .fullScreenCover(isPresented: Binding(get: { pendingMedia != nil },
                                    set: { if !$0 { pendingMedia = nil } })) {
            if let p = pendingMedia {
                MediaSendSheet(payload: p) { live, original, edited in
                    let nativeCamera: Bool
                    if case .image(_, let isNativeCamera) = p {
                        nativeCamera = isNativeCamera
                    } else {
                        nativeCamera = false
                    }
                    let payload = edited.map {
                        MediaSendSheet.Payload.image($0, nativeCamera: nativeCamera)
                    } ?? p
                    pendingMedia = nil
                    sendMedia(payload, live: live, original: original)
                }
            }
        }

        .fullScreenCover(isPresented: Binding(get: { videoToPlay != nil },
                                    set: { if !$0 { videoToPlay = nil } })) {

            if let u = videoToPlay {
                VideoPlayerSheet(url: u, forwardContent: videoPayload)
                    .environmentObject(app)
            }
        }

        .fullScreenCover(item: $filePreview) { f in
            FilePreviewSheet(name: f.name, local: f.local,
                             favoriteTitle: f.favoriteTitle,
                             favoriteFrom: f.favoriteFrom)
                .environmentObject(app)
        }
        .sheet(item: $shareFile) { f in
            ShareSheet(items: [f.local])
        }

        .sheet(isPresented: $showOaArticle) {
            NavigationStack { ArticleView(articleId: oaArticleId).environmentObject(app) }
        }

        .sheet(isPresented: $showFile) {
            AnyFilePicker(
                onPick: { urls in
                    showFile = false
                    sendFiles(urls)
                },
                onCancel: { showFile = false }
            )
        }

        .sheet(isPresented: $showMyFiles) {
            MyFilesPickerView(onPick: { f in sendExistingFile(f) },
                              onSystemPicker: {

                                  DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showFile = true }
                              })
                .environmentObject(app)
        }
    }

    var body: some View {
        chatDetailCovers
        .task(id: chat.id) {
            HitchWatch.shared.start("聊天页")
            app.markChatReadLocally(chat.id)
            loadDeletedMessageIds()
            loadOutbox()
            await load(initial: true)
            historySyncTask?.cancel()
            if shouldLoadCompleteGroupHistory {
                historySyncTask = Task { @MainActor in
                    await loadAllGroupHistory()
                }
            }
            await loadGroupSenderProfilesIfNeeded()
            await refreshPeerRelation()
            await flushOutbox()
            await API.shared.markRead(chatId: chat.id)
            app.markChatReadLocally(chat.id)

            LocalNotify.clearChat(chat.id)
            await app.loadChats()
            if plusItems.isEmpty {
                let items = (try? await API.shared.plusPanel()) ?? []
                plusItems = normalizedPlusItems(items)
            }
            await loadMyStickers()

            await StickerCatalog.shared.loadIfNeeded()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                if Task.isCancelled { break }
                if !realtime.connected {
                    await load(initial: false)
                    await flushOutbox()
                }

                if needBurnSweep {
                    let gone = await API.shared.burnSweep(chatId: chat.id)
                    if !gone.isEmpty { burnAway(gone) }
                }
            }
        }

        .task(id: backgroundPath) {
            await refreshBackgroundLuminance()
        }

        .task(id: chat.id) {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if Task.isCancelled { break }
                guard hasBurnMsg else { continue }
                let gone = await API.shared.burnSweep(chatId: chat.id)
                if !gone.isEmpty { burnAway(gone) }
            }
        }

        .onChange(of: app.offline) { off in
            if !off { Task { await flushOutbox() } }
        }
        .onChange(of: realtime.event) { _ in
            let ev = realtime.event

            if !isGroup, let user = ev.user, user.id == peerId {
                peerBanned = user.banned == true
                peerBanReason = user.banReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            }

            if ev.type == "typing", ev.chatId == chat.id {
                peerTyping = "对方"
                typingClear?.cancel()
                typingClear = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    if !Task.isCancelled { peerTyping = "" }
                }
            }

            if ev.type == "message", ev.chatId == chat.id {
                typingClear?.cancel()
                peerTyping = ""
            }

            if ev.type == "pat", ev.chatId == chat.id {
                UIImpactFeedbackGenerator(style: ev.patTo == myId ? .medium : .light).impactOccurred()
            }

            if ev.type == "burn", ev.chatId == chat.id, !ev.burnIds.isEmpty {
                burnAway(ev.burnIds)
            }

            if ev.type == "recall", ev.chatId == chat.id, !ev.messageId.isEmpty {
                markMessageRecalledLocally(ev.messageId)
                pushTask?.cancel()
                pushTask = Task {
                    try? await Task.sleep(nanoseconds: 180_000_000)
                    if !Task.isCancelled { await load(initial: true) }
                }
            }

            if ev.type == "message", ev.chatId == chat.id, let message = ev.message {
                upsertVisibleMessage(message)
                if message.kindName == "pat" {
                    animateStarWhisper(message.id)
                }
                if let seq = message.seq { Realtime.shared.ackDelivery(chatId: chat.id, seq: seq) }
                markConversationReadSoon()
            } else if (ev.type == "message" || ev.type == "chat"), ev.chatId == chat.id {
                pushTask?.cancel()
                pushTask = Task {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    if Task.isCancelled { return }
                    await load(initial: false)
                }
            }
        }

        .onChange(of: messages) { _ in
            rememberSenderAvatars(messages)
            schedulePersist()
        }
        .onChange(of: chatTheme.version) { _ in
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                frameCaptureTick &+= 1
            }
        }
        .onAppear {
            chatTheme.activate(chat.id)
        }
        .onReceive(NotificationCenter.default.publisher(for: .chrisStickersChanged)) { _ in
            Task { await loadMyStickers() }
        }
        .onChange(of: realtime.connected) { connected in
            if connected { Task { await load(initial: false) } }
        }

        .onDisappear {
            if dismissDragActive {
                dismissDragActive = false
                ScrollGate.shared.setScrolling(false)
            }
            historySyncTask?.cancel()
            historySyncTask = nil
            persistTask?.cancel()
            persistTask = nil
            draftSaveTask?.cancel()
            draftSaveTask = nil
            ChatDraftStore.shared.set(input, for: chat.id)
            settleTask?.cancel()
            settleTask = nil
            initialScrollTask?.cancel()
            initialScrollTask = nil
            pinTask?.cancel()
            pinTask = nil
            patAnimationTask?.cancel()
            patAnimationTask = nil
            let snapshot = messages
            Task.detached(priority: .utility) {
                LocalStore.saveChat(chat.id, snapshot)
            }
            let latest = messages.last
            Task { @MainActor in
                await app.loadChats()
                app.ensureChatVisible(chat, latest: latest)
            }
        }
    }

    private var messageList: some View {

        let nearTopIds = hasOlder ? Set(messages.prefix(24).map { $0.id }) : Set<String>()
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {

                    if hasOlder {
                        Color.clear
                            .frame(height: 1)
                            .onAppear { autoLoadOlder() }
                    }
                    ForEach(messages) { message in
                        messageBlock(message)
                            .id(message.id)

                            .onAppear {
                                if nearTopIds.contains(message.id) { autoLoadOlder() }

                                if message.id == messages.last?.id { atBottom = true }
                            }
                    }

                    ForEach(outbox) { p in
                        pendingBubble(p)
                    }

                    if !sendingMedia.isEmpty {
                        HStack(spacing: 8) {
                            Spacer(minLength: 0)

                            SendingVideoBubble(cover: sendingPreview,
                                               progress: sendProgress)
                        }
                        .id("__sending")
                        .padding(.bottom, 12)
                        .padding(.trailing, 6)
                    }
                    if let progress = sendingFileProgress, !sendingFileName.isEmpty {
                        HStack(spacing: 8) {
                            Spacer(minLength: 0)
                            SendingFileBubble(name: sendingFileName,
                                              bytes: sendingFileBytes,
                                              progress: progress)
                        }
                        .id("__sending-file")
                        .padding(.bottom, 12)
                        .padding(.trailing, 6)
                    }
                    Color.clear
                        .frame(height: 1)
                        .onAppear { atBottom = true }
                        .onDisappear { atBottom = false }
                        .id("__bottom")

                    Spacer().frame(height: 8)
                }
                .padding(L.msgPad)

                .background(GeometryReader { geo in
                    Color.clear.preference(key: ChatContentHeightKey.self, value: geo.size.height)
                })
                .onPreferenceChange(ChatContentHeightKey.self) { h in
                    let grew = h > lastContentHeight + 0.5
                    lastContentHeight = h
                    if grew, atBottomNow {
                        scrollToEnd(proxy, animated: false)
                        scheduleSettledBottom()
                    }
                }

                .overlay(alignment: .topLeading) {
                    ScrollOffsetProbe(onChange: { _, _ in
                        if ChatScrollHandle.shared.moving, let g = ChatScrollHandle.shared.gap {
                            let next = g <= 16
                            if wasAtBottom != next { wasAtBottom = next }
                        }
                    }, onScrollStateChange: { scrolling in
                        if scrolling {
                            ScrollGate.shared.setScrolling(true)
                            followOwnSendUntil = Date.distantPast
                        } else {
                            ScrollGate.shared.setScrolling(false)
                            frameCaptureTick &+= 1
                        }
                    }, onSizeChange: {

                        guard wasAtBottom, !holdScroll else { return }
                        if ChatScrollHandle.shared.moving { return }
                        ChatScrollDiag.shared.note("内容变高 → 哨兵贴底")
                        ChatScrollHandle.shared.pinToBottom(animated: false)
                    })
                        .frame(width: 1, height: 1)
                        .allowsHitTesting(false)
                }
            }
            .coordinateSpace(name: "chatScroll")
            .scrollDismissesKeyboard(.interactively)
        .onChange(of: messages.count) { _ in

                backfillVoiceText()
                if !initialScrollReady {
                    if !loading { settleInitialScroll(proxy) }
                    return
                }
                ChatScrollDiag.shared.note("消息数变了=\(messages.count) atBottom=\(atBottomNow ? 1 : 0)")
                guard !holdScroll else { return }
                guard atBottomNow || messages.last?.senderId == myId else { return }
                scrollToEnd(proxy, animated: false)
                scheduleSettledBottom()
                markConversationReadSoon()
            }
            .onChange(of: loading) { value in
                if value {
                    allowSettledBottom = false
                } else {
                    if !initialScrollReady {
                        settleInitialScroll(proxy)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        allowSettledBottom = true
                    }
                }
            }
            .onChange(of: scrollTick) { _ in
                atBottom = true
                wasAtBottom = true
                scrollToEnd(proxy, animated: true)
                markConversationReadSoon()
            }

            .onChange(of: pinTick) { _ in
                scrollToEnd(proxy, animated: false)
            }

            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { n in
                ChatScrollDiag.shared.note("键盘位置变了")
                pinThroughKeyboardTransition(proxy, notice: n)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                ChatScrollDiag.shared.note("键盘弹起")
                pinToBottomImmediately(proxy)
            }

            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                ChatScrollDiag.shared.note("回前台 atBottom=\(atBottomNow ? 1 : 0)")
                if atBottomNow { scrollToEnd(proxy, animated: false) }
            }
            .onAppear {
                ChatScrollDiag.shared.note("onAppear 打开会话")

                CrashCatcher.note("聊天页", "9 页面出现 " + chat.id)
                scroller = proxy
                backfillVoiceText()
                wasAtBottom = true
                atBottom = true
                if initialCacheReady || !loading {
                    settleInitialScroll(proxy)
                } else {
                    initialScrollReady = false
                }
                if initialCacheReady || !loading {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        allowSettledBottom = true
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                    CrashCatcher.note("聊天页",
                        "打开 \(chat.id) 条数=\(messages.count) 内容高=\(Int(lastContentHeight))"
                        + " 离底=\(Int(ChatScrollHandle.shared.gap ?? -999))"
                        + " 哨兵=\(atBottom) 跟随=\(wasAtBottom)")
                }
            }
            .onChange(of: initialCacheReady) { ready in
                if ready {
                    settleInitialScroll(proxy)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        allowSettledBottom = true
                    }
                }
            }
        }
    }

    private func settleInitialScroll(_ proxy: ScrollViewProxy) {
        guard !initialScrollReady else { return }
        initialScrollTask?.cancel()
        ChatScrollHandle.shared.allowAutomaticPinning()
        initialScrollTask = Task { @MainActor in
            atBottom = true
            wasAtBottom = true
            for delay in [0, 24, 70, 150, 260] {
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
                }
                if Task.isCancelled { return }
                proxy.scrollTo("__bottom", anchor: .bottom)
            }
            if Task.isCancelled { return }
            initialScrollReady = true
            pinTick += 1
        }
    }

    private func autoLoadOlder() {
        guard hasOlder, !loadingOlder, !loadingAllGroupHistory, !loading else { return }
        guard Date().timeIntervalSince(lastOlderLoad) > 0.08 else { return }
        lastOlderLoad = Date()
        Task { await loadOlder() }
    }

    private func pinToBottomSoon(force: Bool = false) {

        var stick = force || atBottomNow

        if !force, let g = ChatScrollHandle.shared.gap, g > 200 { stick = false }
        ChatScrollDiag.shared.note("pinToBottomSoon force=\(force ? 1 : 0) stick=\(stick ? 1 : 0)")
        guard stick else { return }
        if force { ChatScrollHandle.shared.allowAutomaticPinning() }
        pinTask?.cancel()
        pinTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: force ? 120_000_000 : 280_000_000)
            if Task.isCancelled { return }
            atBottom = true
            if force {
                ChatScrollHandle.shared.allowAutomaticPinning()
                scroller?.scrollTo("__bottom", anchor: .bottom)
            }
            pinTick += 1
            if force {
                try? await Task.sleep(nanoseconds: 320_000_000)
                if Task.isCancelled { return }
                ChatScrollHandle.shared.allowAutomaticPinning()
                scroller?.scrollTo("__bottom", anchor: .bottom)
            }
        }
    }

    private func pinAfterFocusChange(_ focused: Bool) {
        if focused {
            pinToBottomImmediately()
        } else {
            pinToBottomSoon()
        }
    }

    private func pinToBottomImmediately() {
        guard atBottomNow else { return }
        pinTask?.cancel()
        ChatScrollHandle.shared.allowAutomaticPinning()
        atBottom = true
        wasAtBottom = true
        scroller?.scrollTo("__bottom", anchor: .bottom)
        pinTick += 1
    }

    private func pinToBottomImmediately(_ proxy: ScrollViewProxy) {
        guard atBottomNow else { return }
        ChatScrollHandle.shared.allowAutomaticPinning()
        scrollToEnd(proxy, animated: false)
    }

    private func pinThroughKeyboardTransition(_ proxy: ScrollViewProxy,
                                              notice: Notification) {
        guard atBottomNow else { return }
        let value = notice.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey]
            as? Double ?? 0.25
        pinToBottomImmediately(proxy)
        DispatchQueue.main.async {
            pinToBottomImmediately(proxy)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + value + 0.02) {
            pinToBottomImmediately(proxy)
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy, animated: Bool) {

        ChatScrollDiag.shared.note("scrollToEnd anim=\(animated ? 1 : 0)")
        if ChatScrollHandle.shared.pinToBottom(animated: animated) { return }
        let target = "__bottom"
        guard !target.isEmpty else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.22)) { proxy.scrollTo(target, anchor: .bottom) }
        } else {
            proxy.scrollTo(target, anchor: .bottom)
        }
    }

    private func repinIfAtBottom() {
        ChatScrollDiag.shared.note("repinIfAtBottom atBottom=\(atBottomNow ? 1 : 0)")
        guard atBottomNow else { return }

        if let g = ChatScrollHandle.shared.gap, g > 200 { return }
        pinTick += 1
    }

    private func markConversationReadSoon() {
        let now = Date()
        guard now.timeIntervalSince(lastReadSyncAt) > 1.5 else { return }
        lastReadSyncAt = now
        app.markChatReadLocally(chat.id)
        Task {
            await API.shared.markRead(chatId: chat.id)
            await app.loadChats()
            app.markChatReadLocally(chat.id)
        }
    }

    private func scheduleSettledBottom(delayMs: UInt64 = 120) {
        guard allowSettledBottom else { return }
        guard atBottomNow, !holdScroll, !ChatScrollHandle.shared.moving else { return }
        let followOwnSend = Date() < followOwnSendUntil
        settleTask?.cancel()
        settleTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
            if Task.isCancelled { return }
            guard atBottomNow, !holdScroll, !ChatScrollHandle.shared.moving else { return }
            if !followOwnSend, let gap = ChatScrollHandle.shared.gap, gap > 24 { return }
            pinTick += 1
        }
    }

    private var atBottomNow: Bool { wasAtBottom || atBottom }

    private func pendingBubble(_ p: PendingMsg) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            HStack(alignment: .center, spacing: 7) {
                Spacer(minLength: 0)
                if p.sending {
                    ProgressView().scaleEffect(0.72)
                } else if p.failed {
                    Button {
                        Task { await flushOutbox() }
                    } label: {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(C.red)
                    }
                    .buttonStyle(.plain)
                }
                Text(p.preview)
                    .font(pf(16))
                    .foregroundColor(ChatTheme.ink)
                    .lineLimit(6)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(BubbleFill(mine: true, tail: false))
                    .opacity(p.failed ? 0.9 : 1)
            }
            if p.failed, let reason = p.failureReason, !reason.isEmpty {
                Text(reason)
                    .font(pf(11.5))
                    .foregroundColor(C.red.opacity(0.88))
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .padding(.trailing, 3)
            }
        }
        .padding(.vertical, 4)
        .id(p.id)
    }

    private func saveOutbox() {
        let arr = outbox.map { p -> [String: Any] in
            var d: [String: Any] = ["id": p.id, "kind": p.kind, "content": p.content,
                                    "at": p.at.timeIntervalSince1970]
            if let q = p.quoteJSON { d["quote"] = q }
            if let reason = p.failureReason, !reason.isEmpty { d["failureReason"] = reason }
            return d
        }
        UserDefaults.standard.set(arr, forKey: "chris.outbox." + chat.id)
    }

    private func loadOutbox() {
        let arr = (UserDefaults.standard.array(forKey: "chris.outbox." + chat.id) as? [[String: Any]]) ?? []
        outbox = arr.compactMap { d in
            guard let id = d["id"] as? String,
                  let kind = d["kind"] as? String,
                  let content = d["content"] as? String else { return nil }
            return PendingMsg(id: id, kind: kind, content: content,
                              quoteJSON: d["quote"] as? String,
                              failed: (d["failureReason"] as? String)?.isEmpty == false,
                              failureReason: d["failureReason"] as? String)
        }
    }

    private static func quoteDict(_ json: String?) -> [String: Any]? {
        guard let json = json, let d = json.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        return o
    }

    private var chatBackdrop: some View {
        ZStack {
            if backgroundPath.isEmpty {
                ChatDefaultWallpaper(preset: ChatTheme.preset)
            } else {
                ChatTheme.page
                if let solid = renderedChatBackgroundSolidColor(
                    backgroundPath,
                    dark: scheme == .dark
                ) {
                    solid
                } else {
                    if resolvedBackgroundEffect == .original {
                        RemoteImage(path: backgroundPath,
                                    mode: .fill,
                                    maxSide: chatWallpaperDecodeSide())
                            .id(backgroundPath)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                    } else {
                        ChatWallpaperEffectImage(path: backgroundPath,
                                                 effect: resolvedBackgroundEffect)
                            .id(backgroundPath + "#" + resolvedBackgroundEffect.rawValue)
                    }
                    wallpaperEffectOverlay
                    if resolvedBackgroundEffect == .original {
                        wallpaperAtmosphere
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var wallpaperEffectOverlay: some View {
        switch resolvedBackgroundEffect {
        case .blackBlur:
            ZStack {
                Color(hex: 0x090A09).opacity(0.075)
                LinearGradient(
                    colors: [Color.white.opacity(0.008), Color.clear],
                    startPoint: .top,
                    endPoint: .center
                )
            }
            .ignoresSafeArea()
        case .whiteBlur:
            ZStack {
                Color.white.opacity(0.055)
                LinearGradient(
                    colors: [Color.white.opacity(0.03), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea()
        case .auto, .original:
            Color.clear
        }
    }

    private var wallpaperAtmosphere: Color {
        if scheme == .dark {
            let bright = (backgroundLuminance ?? 0.35) > 0.66
            return Color.black.opacity(bright ? 0.18 : 0.11)
        }
        let darkImage = (backgroundLuminance ?? 0.62) < 0.38
        return Color.white.opacity(darkImage ? 0.055 : 0.018)
    }

    private func backfillVoiceText() {
        for m in messages where m.kindName == "audio" && asrCache[m.id] == nil {
            if let t = VoiceText.get(m.id) { asrCache[m.id] = t }
        }
    }

    @ViewBuilder
    private func messageBlock(_ message: Message) -> some View {
        VStack(spacing: 0) {
            if showTime(for: message) { timeLine(message) }
            if message.kindName == "pat" {

                StarWhisperLine(
                    text: message.patText(myId: myId),
                    ink: adaptiveSystemSecondaryInk,
                    surface: adaptiveSystemSurface,
                    border: adaptiveSystemBorder,
                    accent: adaptiveMicInk,
                    active: patAnimatingId == message.id,
                    plain: usesPlainDefaultChatChrome
                )
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 40)
                    .padding(.bottom, gapAfter(message))
            } else if message.kindName == "system" {

                if message.isCallRecord && !message.callFrom.isEmpty {
                    callRow(message)
                } else {
                        SystemLine(message: message,
                                   usesLightInk: senderNameUsesLightInk,
                                   plain: usesPlainDefaultChatChrome)
                            .padding(.bottom, gapAfter(message))

                            .contentShape(Rectangle())
                            .onTapGesture { redialAsk = message }
                }
            } else if message.isRecalled {
                recallLine(message)
                    .padding(.bottom, gapAfter(message))
            } else {
                messageRow(message)

                    .overlay(alignment: (message.senderId == myId) ? .leading : .trailing) {
                        if message.burn == true {

                            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                                HStack(spacing: 3) {
                                    Image(systemName: "flame.fill")
                                        .font(.system(size: 11))
                                    if let d = TimeFmt.date(message.burnAt) {
                                        Text(burnCountText(d, now: ctx.date))
                                            .font(pfStyled(size: 10, weight: .medium))
                                            .monospacedDigit()
                                    }
                                }
                                .foregroundColor(Color(hex: 0xFF9A2E))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background {
                                    if !usesPlainDefaultChatChrome {
                                        Capsule().fill(.thinMaterial)
                                    }
                                }
                                .overlay {
                                    if !usesPlainDefaultChatChrome {
                                        Capsule().stroke(
                                            Color(hex: 0xFF9A2E).opacity(0.28),
                                            lineWidth: 0.6
                                        )
                                    }
                                }
                                .offset(x: (message.senderId == myId) ? -26 : 26)
                            }
                        }
                    }
            }
        }
        .padding(.leading, selectMode ? 34 : 0)
        .overlay(alignment: .leading) {
            if selectMode {
                Image(systemName: selected.contains(message.id)
                      ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21))
                    .foregroundColor(selected.contains(message.id) ? C.green : ChatTheme.secondary)
                    .padding(.leading, 10)
            }
        }
        .overlay {
            if selectMode {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { toggleSelect(message) }
            }
        }
    }

    @ViewBuilder
    private func timeLine(_ message: Message) -> some View {
        if usesPlainDefaultChatChrome {
            Text(TimeFmt.bubble(message.createdAt))
                .font(pf(11.5, .medium))
                .foregroundColor(adaptiveSystemSecondaryInk.opacity(0.92))
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 7)
        } else {
            Text(TimeFmt.bubble(message.createdAt))
                .font(pf(12, .medium))
                .foregroundColor(adaptiveSystemSecondaryInk)
                .padding(.horizontal, L.o("chatTimePadX", 9))
                .padding(.vertical, L.o("chatTimePadY", 4))
                .background {
                    ZStack {
                        Capsule(style: .continuous)
                            .fill(.ultraThinMaterial)
                        Capsule(style: .continuous)
                            .fill(adaptiveSystemSurface)
                    }
                }
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(adaptiveSystemBorder, lineWidth: 0.6)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, L.o("chatTimeGapTop", 10))
                .padding(.bottom, L.o("chatTimeGapBottom", 10))
        }
    }

    @ViewBuilder
    private func recallLine(_ message: Message) -> some View {
        if usesPlainDefaultChatChrome {
            Text(recallText(message))
                .font(pf(12.5))
                .foregroundColor(adaptiveSystemSecondaryInk.opacity(0.92))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 40)
        } else {
            Text(recallText(message))
                .font(pf(13))
                .foregroundColor(adaptiveSystemSecondaryInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(.ultraThinMaterial)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(adaptiveSystemSurface)
                    }
                )
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 40)
        }
    }

    private func recallText(_ message: Message) -> String {
        if message.senderId == myId { return Tr("你撤回了一条消息") }
        if isGroup { return displayName(message) + " " + Tr("撤回了一条消息") }
        return Tr("对方撤回了一条消息")
    }

    @ViewBuilder
    private func messageRow(_ message: Message) -> some View {
        EquatableView(content: MessageRow(message: message,
                   mine: mineFor(message),
                   myId: myId,
                   senderName: senderNameFor(message),
                   senderNameUsesLightInk: senderNameUsesLightInk,
                   wallpaperTint: wallpaperBottomTint,
                   senderAvatarPath: senderAvatarFor(message),
                   senderQQLevel: app.contact(for: message.senderId ?? "")?.qqLevel ?? 0,
                   currentNickname: app.me?.nickname ?? "",
                   currentUsername: app.me?.username ?? "",
                   showTail: isRunStart(message),
                   onTapTransfer: { info in billInfo = info },
                   onOpenImage: { path in openImage(path) },
                   onOpenAvatar: { id in openAvatar(id) },
                   onOpenWeb: { url in web = WebURL(url: url) },
                   onOpenLocation: { p in openLocation = p },
                   onOpenUserCard: { uid in openCardUser(uid) },
                   onOpenAnnounce: { text in announcePage = text; showAnnouncePage = true },

                   onOpenMiniApp: { g in app.launchMiniApp(g, returningTo: chat) },
                   onOpenVideo: { u in videoToPlay = u; videoPayload = message.body },
                   onPat: { uid in pat(uid) },
                   onTapRedPacket: { info in tapRedPacket(info) },
                   asrText: asrCache[message.id] ?? "",
                   asrBusy: asrBusy.contains(message.id),
                   onOpenFile: { body in openFile(body) },
                   onOpenArticle: { id in oaArticleId = id; showOaArticle = true },
                   onLayoutChanged: { scheduleSettledBottom() },

                   onOpenQuote: { ref in quoteInspect = QuoteInspectItem(quote: ref) },
                   onShowToast: { text in app.show(text) }))
            .padding(.bottom, gapAfter(message))

            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.42).onEnded { _ in openActions(message) }
            )

            .simultaneousGesture(
                TapGesture().onEnded {
                    guard CareMode.on, CareMode.speakText else { return }
                    let t = readableText(message)
                    if !t.isEmpty { Speaker.shared.speak(t) }
                }
            )
            .background(GeometryReader { g in

                let contentFrame = g.frame(in: .global)
                Color.clear
                    .onAppear { frameBox.frames[message.id] = contentFrame }
                    .onChange(of: contentFrame) { f in
                        if !ChatScrollHandle.shared.moving {
                            frameBox.frames[message.id] = f
                        }
                    }
                    .onChange(of: frameCaptureTick) { _ in
                        frameBox.frames[message.id] = contentFrame
                    }
            })
    }

    private func mineFor(_ message: Message) -> Bool {
        if message.isCallRecord && !message.callFrom.isEmpty { return message.callFrom == myId }
        return message.senderId == myId
    }

    @ViewBuilder
    private func callRow(_ message: Message) -> some View {
        let mine = mineFor(message)
        let callerAvatar = app.contact(for: message.callFrom)?.avatarPath ?? ""
        HStack(alignment: .top, spacing: 0) {
            if mine { Spacer(minLength: 0) }
            if !mine {
                Avatar(path: callerAvatar, size: L.chatAvatar, radius: L.chatAvatar / 2)
                Spacer().frame(width: L.chatGapMsg)
            }
            Button {
                redialAsk = message
            } label: {
                CallRecordBubble(message: message, mine: mine)
            }
            .buttonStyle(.plain)
            if mine {
                Spacer().frame(width: L.chatGapMsg)
                Avatar(path: callerAvatar, size: L.chatAvatar, radius: L.chatAvatar / 2)
            }
            if !mine { Spacer(minLength: 0) }
        }
        .padding(.bottom, gapAfter(message))

        .onLongPressGesture { openActions(message) }
        .background(GeometryReader { g in
            let contentFrame = g.frame(in: .global)
            Color.clear
                .onAppear { frameBox.frames[message.id] = contentFrame }
                .onChange(of: contentFrame) { f in
                    if !ChatScrollHandle.shared.moving {
                        frameBox.frames[message.id] = f
                    }
                }
                .onChange(of: frameCaptureTick) { _ in
                    frameBox.frames[message.id] = contentFrame
                }
        })
    }

    private func pat(_ userId: String) {
        guard !userId.isEmpty else { return }
        Realtime.shared.sendJSON(["type": "pat", "chatId": chat.id, "targetId": userId])
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func redialPeerId(_ message: Message) -> String {
        var peer = (message.callFrom == myId) ? (message.call?.to ?? "") : message.callFrom
        if peer.isEmpty || peer == myId {
            if let other = message.call?.to, !other.isEmpty, other != myId { peer = other }
            else if let other = message.call?.from, !other.isEmpty, other != myId { peer = other }
            else if let other = peerUserId { peer = other }
        }
        return peer == myId ? "" : peer
    }

    private func redialName(_ message: Message) -> String {
        let peer = redialPeerId(message)
        if peer.isEmpty { return chat.name }
        return app.contact(for: peer)?.name ?? chat.name
    }

    private var redialTitle: String {
        guard let m = redialAsk else { return "" }
        return Tr("给「") + redialName(m) + Tr("」打电话？")
    }

    private func startRedial(_ video: Bool) {
        guard let message = redialAsk else { return }
        redialAsk = nil
        let peer = redialPeerId(message)
        guard !peer.isEmpty else { app.show(Tr("这条记录里找不到对方账号")); return }
        if CallCenter.shared.phase != .idle { app.show(Tr("正在通话中")); return }
        CallCenter.shared.resetIfStale()
        if CallCenter.shared.phase != .idle { app.show(Tr("正在通话中")); return }
        CallCenter.shared.start(peerId: peer,
                                name: app.contact(for: peer)?.name ?? chat.name,
                                avatar: app.contact(for: peer)?.avatarPath ?? (chat.avatar ?? ""),
                                video: video)
    }

    private func indexOf(_ message: Message) -> Int? {

        if let i = msgIndex[message.id], i < messages.count, messages[i].id == message.id {
            return i
        }
        return messages.firstIndex(where: { $0.id == message.id })
    }

    private func rebuildIndex() {
        var m = [String: Int](minimumCapacity: messages.count)
        for (i, x) in messages.enumerated() { m[x.id] = i }
        msgIndex = m
    }

    private func isRunStart(_ message: Message) -> Bool {
        guard let i = indexOf(message), i > 0 else { return true }
        let prev = messages[i - 1]
        if prev.kindName == "system" || prev.kindName == "pat" || prev.isRecalled { return true }
        if (prev.senderId ?? "") != (message.senderId ?? "") { return true }
        return TimeFmt.minutesBetween(prev.createdAt, message.createdAt) >= 5
    }

    private func senderNameFor(_ message: Message) -> String {
        guard isGroup, message.senderId != myId else { return "" }
        return isRunStart(message) ? displayName(message) : ""
    }

    private func senderAvatarFor(_ message: Message) -> String {
        if let path = message.senderAvatar, !path.isEmpty { return path }
        let senderId = message.senderId ?? ""
        if let path = app.contact(for: senderId)?.avatarPath, !path.isEmpty { return path }
        return senderAvatarCache[senderId] ?? ""
    }

    private func rememberSenderAvatars(_ rows: [Message]) {
        guard isGroup else { return }
        for message in rows {
            guard let senderId = message.senderId, !senderId.isEmpty,
                  let path = message.senderAvatar, !path.isEmpty,
                  senderAvatarCache[senderId] != path else { continue }
            senderAvatarCache[senderId] = path
        }
    }

    private func loadGroupSenderProfilesIfNeeded() async {
        guard isGroup, !groupSenderProfilesLoaded else { return }
        groupSenderProfilesLoaded = true
        guard let result = try? await API.shared.chatMembers(chatId: chat.id) else {
            groupSenderProfilesLoaded = false
            return
        }
        var resolved: [String: String] = [:]
        for member in result.members where !member.id.isEmpty && !member.avatarPath.isEmpty {
            resolved[member.id] = member.avatarPath
        }
        senderAvatarCache.merge(resolved) { _, newer in newer }
        rememberSenderAvatars(messages)
    }

    private func gapAfter(_ message: Message) -> CGFloat {
        guard let i = indexOf(message) else { return 15 }
        guard i + 1 < messages.count else { return 4 }
        let next = messages[i + 1]
        if showTime(for: next) { return 0 }
        if next.kindName == "system" || next.kindName == "pat" || next.isRecalled { return 12 }
        if message.kindName == "system" || message.kindName == "pat" || message.isRecalled { return 12 }
        let same = (next.senderId ?? "") == (message.senderId ?? "")

        return same ? UIConfig.num("msgGapSame", 7) : UIConfig.num("msgGapOther", 15)
    }

    private var leftUnreadBadge: AnyView? {
        guard unreadHere > 0 else { return nil }
        return AnyView(
            Button {
                unreadHere = 0
                scrollTick += 1
            } label: {
                Text(unreadHere > 99 ? "99+" : "\(unreadHere)")
                    .font(pfStyled(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(.systemBlue))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 3, y: 1)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 2)
        )
    }

    private func showTime(for message: Message) -> Bool {

        guard let index = indexOf(message) else { return false }
        if index == 0 { return true }
        return TimeFmt.minutesBetween(messages[index - 1].createdAt, message.createdAt) >= 5
    }

    private func animateStarWhisper(_ messageId: String) {
        guard !messageId.isEmpty else { return }
        patAnimationTask?.cancel()
        patAnimatingId = messageId
        patAnimationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            guard !Task.isCancelled, patAnimatingId == messageId else { return }
            patAnimatingId = nil
        }
    }

    private var quickBar: some View {
        let chips = quickChips
        return Group {
            if chips.count <= 7 {
                HStack(spacing: 0) {
                    ForEach(chips) { c in quickChip(c) }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(chips) { c in
                            quickChip(c)
                                .frame(width: 52)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
    }

    private var quickChips: [QuickChip] {
        let list = app.quickChips.filter { $0.enabled }
        return list.isEmpty ? QuickChip.defaults : list
    }

    @ViewBuilder
    private var plusIcon: some View {
        let cfg = app.plusButton
        let side = cfg.size > 0 ? CGFloat(cfg.size) : L.composerIcon
        Group {
            if !cfg.image.isEmpty {
                RemoteImage(path: cfg.image, mode: .fit, maxSide: 200)
                    .frame(width: max(20, side - 2), height: max(20, side - 2))
            } else {
                Image(systemName: "plus")
                    .font(.system(size: max(21, side - 3), weight: .semibold))
                    .foregroundStyle(panel == .plus ? C.green : adaptivePlusInk)
            }
        }
        .frame(width: L.composerIconBox, height: L.composerIconBox)
        .contentShape(Rectangle())
    }

    private func quickChip(_ c: QuickChip) -> some View {
        let symbol = quickChipSymbol(c.action)
        let title = chatEntryLabel(c.label, action: c.action)
        return Button {
            switch c.action {
            case "photo": openPhotoPicker()
            case "camera": showCamera = true
            case "location": showSendLocation = true
            case "file": openFilePicker()
            case "transfer": showTransfer = true
            case "redpacket": showSendRedPacket = true
            case "card": showPickCard = true

            default:
                handlePlus(PlusItem(id: c.id, label: c.label, icon: c.action,
                                    action: c.action, enabled: true))
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(quickChipInk)
                .shadow(color: composerUsesLightInk
                        ? Color.black.opacity(0.40)
                        : Color.clear,
                        radius: 1.2, x: 0, y: 0.8)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(QuickIconButtonStyle(ink: quickChipInk))
        .accessibilityLabel(Text(title))
        .help(title)
    }

    private var quickChipInk: Color {
        composerUsesLightInk ? Color.white : Color(hex: 0x161616)
    }

    private func quickChipSymbol(_ action: String) -> String {
        switch action {
        case "photo":
            return "photo.fill"
        case "camera":
            return "camera.fill"
        case "location":
            return "location.fill"
        case "file":
            return "doc.fill"
        case "transfer":
            return "banknote.fill"
        case "redpacket":
            return "gift.fill"
        case "card":
            return "person.crop.rectangle.fill"
        case "gift":
            return "gift.fill"
        case "music":
            return "music.note.list"
        case "videocall":
            return "video.fill"
        case "voice":
            return "waveform.circle.fill"
        case "favorite":
            return "star.fill"
        default:
            return "plus.circle.fill"
        }
    }

    private var sysTeamToolsBar: some View {
        Button {
            focused = false
            sysToolsPage = .tools
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(C.green)
                    .frame(width: 30, height: 30)
                    .background(C.green.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(Tr("自助工具"))
                        .font(pf(13.5, .semibold))
                        .foregroundColor(C.label)
                    Text(Tr("改密码 · 登录设备 · 找回 · 安全"))
                        .font(pf(10))
                        .foregroundColor(C.subLabel)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Chevron(size: 8, line: 1.5, color: C.subLabel)
            }
            .padding(.horizontal, 12)
            .frame(height: 46)
            .background(C.cardBg.opacity(0.96))
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(ChatTheme.separator, lineWidth: 0.6))
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func sysToolsPageView(_ page: SysPage) -> some View {
        switch page {
        case .tools:
            SysToolsView { key in
                sysToolsPage = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    sysToolsPage = chatSysDestination(for: key)
                }
            }
        case .support:
            SupportView()
        case .kefu:
            KefuPage()
        case .security:
            AccountSecurityView()
        case .devices:
            LoginDevicesView()
        case .safety:
            AccountSafetyCenterView()
        case .feedback:
            FeedbackView()
        case .delete:
            DeleteAccountView()
        }
    }

    private func chatSysDestination(for key: String) -> SysPage {
        switch key {
        case "pwd": return .security
        case "devices": return .devices
        case "support": return .support
        case "safety": return .safety
        case "feedback": return .feedback
        case "delete": return .delete
        default: return .kefu
        }
    }

    private var composer: some View {
        Group {
            if !isFriendPeer {

                verifyComposer
            } else if peerBanned {
                bannedComposer
            } else if peerBlockedByMe {
                blockedComposer
            } else if mutedForMe {
                mutedComposer
            } else {
                activeComposer
            }
        }
    }

    private var peerId: String {
        (chat.memberIds ?? []).first(where: { $0 != myId }) ?? ""
    }

    private var isFriendPeer: Bool {
        guard !isGroup, !peerId.isEmpty else { return true }
        if (chat.bot ?? "").isEmpty == false || (chat.oaId ?? "").isEmpty == false { return true }
        if app.contacts.isEmpty { return true }
        if app.contacts.contains(where: { $0.id == peerId }) { return true }
        if serverPeerRelation == "friend" || serverPeerRelation == "self" { return true }
        /* 非好友也有服务端限定的陌生人消息额度（默认 5 条）。
           客户端保留输入框；第 6 条会收到服务端明确提示并引导加好友。 */
        if peerRelationChecked, serverPeerRelation == "none" { return true }
        if peerRelationChecked, serverPeerRelation == "requested" { return true }
        if peerRelationChecked, serverPeerRelation == "incoming" { return true }
        return !peerRelationChecked
    }

    private func refreshPeerRelation() async {
        guard !isGroup,
              !peerId.isEmpty,
              (chat.bot ?? "").isEmpty,
              (chat.oaId ?? "").isEmpty else {
            peerRelationChecked = true
            return
        }
        guard let user = try? await API.shared.user(id: peerId) else {
            peerRelationChecked = true
            return
        }
        serverPeerRelation = user.relation
        peerBanned = user.banned == true
        peerBanReason = user.banReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let meta = try? await API.shared.friendMeta(userId: peerId) {
            peerBlockedByMe = meta.block == true
        } else {
            peerBlockedByMe = false
        }
        if user.relation == "friend" {
            app.applyFriendAccepted(user)
        }
        peerRelationChecked = true
    }

    private var bannedComposer: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(C.red)
            VStack(alignment: .leading, spacing: 3) {
                Text(Tr("对方账号已被管理员封禁"))
                    .font(pf(14.5, .medium))
                    .foregroundColor(C.label)
                Text(peerBanReason.isEmpty
                     ? Tr("暂时无法发送消息")
                     : Tr("原因：") + peerBanReason)
                    .font(pf(12.5))
                    .foregroundColor(C.subLabel)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(ChatTheme.composerBg)
        .overlay(alignment: .top) { HairLine() }
    }

    private var blockedComposer: some View {
        Button {
            Task {
                guard await API.shared.setFriendMeta(userId: peerId, block: false) else {
                    app.show(Tr("没保存上，再试一次"))
                    return
                }
                peerBlockedByMe = false
                await app.loadContacts()
                await app.loadChats()
                app.show(Tr("已移出黑名单"))
            }
        } label: {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(C.red)
                    .frame(width: 34, height: 34)
                    .background(C.red.opacity(0.10), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(Tr("你已将对方加入黑名单"))
                        .font(pf(14.5, .semibold))
                        .foregroundColor(C.label)
                    Text(Tr("对方无法给你发消息。点按这里可移出黑名单。"))
                        .font(pf(12.5))
                        .foregroundColor(C.subLabel)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(C.subLabel.opacity(0.55))
                    .padding(.top, 9)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .background(ChatTheme.composerBg)
            .overlay(alignment: .top) { HairLine() }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Tr("你已将对方加入黑名单，点按移出黑名单"))
    }

    private var verifyComposer: some View {
        VStack(spacing: 10) {
            Text(Tr("你还不是他（她）朋友。请先发送朋友验证请求，对方验证通过后，才能聊天。"))
                .font(pf(13.5))
                .foregroundColor(C.subLabel)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button { showApply = true } label: {
                Text(Tr("发送朋友验证"))
                    .font(pf(15, .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(C.green))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
        }
        .padding(.top, 14)
        .padding(.bottom, 20)
        .background(C.cardBg)
    }

    private func sendApply() {
        let note = applyNote.trimmingCharacters(in: .whitespaces)
        Task {
            do {
                let result = try await API.shared.addFriend(
                    userId: peerId,
                    note: note.isEmpty ? ("我是" + (app.me?.nickname ?? "")) : note)
                if result.accepted {
                    if let user = result.friend ?? app.contact(for: peerId) {
                        app.applyFriendAccepted(user)
                    }
                    await app.loadChats()
                    app.show(Tr("你们已经是好友了"))
                } else {
                    app.show(Tr("已发送朋友验证"))
                }
            } catch {
                app.show((error as? APIError)?.errorDescription ?? "发送失败")
            }
        }
    }

    private var kbUp: Bool { kbHeight > 1 }

    private var mutedForMe: Bool {
        let c = liveChat
        guard c.type == "group" else { return false }
        if c.meMuted == true { return true }

        return c.muteAll == true && c.ownerId != myId
    }

    private var liveChat: Chat { app.chats.first(where: { $0.id == chat.id }) ?? chat }

    private var mutedComposerInk: Color {
        scheme == .dark ? C.subLabel : Color(hex: 0x191919)
    }

    private var mutedComposer: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.slash.fill")
                .font(.system(size: 15))
                .foregroundColor(mutedComposerInk)
            Text(liveChat.meMuted == true
                 ? Tr("你已被群主禁言，暂时不能发言")
                 : Tr("全员禁言中，只有群主可以发言"))
                .font(pf(14))
                .foregroundColor(mutedComposerInk)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .frame(height: L.inputH)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background {
            GlassBackground(shape: Rectangle(),
                            opacity: max(UIConfig.num("glassAlpha", 0.8), 0.92),
                            edgeAlpha: UIConfig.num("glassEdgeAlpha", 0.65),
                            seed: 0.31,
                            native: true)
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private var composerMaxHeight: CGFloat {
        min(156, max(112, L.height * 0.20))
    }

    private var composerInputHeight: CGFloat {
        (voiceMode || recorder.recording) ? L.inputH : max(L.inputH, inputBoxHeight)
    }

    private var composerNeedsLightLift: Bool {
        !composerUsesLightInk
            && backgroundPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var composerFieldRadius: CGFloat {
        min(19.5, composerInputHeight / 2)
    }

    private var composerFieldFill: Color {
        composerUsesLightInk
            ? Color(hex: 0x202C33).opacity(0.96)
            : Color.white.opacity(0.96)
    }

    private var composerFieldBorder: Color {
        composerUsesLightInk
            ? Color.white.opacity(0.07)
            : Color.black.opacity(0.055)
    }

    private var draftImagesBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(draftImages.indices, id: \.self) { index in
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: draftImages[index])
                            .resizable()
                            .scaledToFill()
                            .frame(width: 68, height: 68)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        Text("\(index + 1)")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color.black.opacity(0.54)))
                            .padding(4)
                    }
                    .overlay(alignment: .topTrailing) {
                        Button {
                            guard draftImages.indices.contains(index) else { return }
                            withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                                draftImages.remove(at: index)
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(Color.black.opacity(0.62)))
                        }
                        .buttonStyle(.plain)
                        .padding(3)
                        .accessibilityLabel(Tr("移除这张照片"))
                    }
                }

                Button { openPhotoPicker() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundColor(composerUsesLightInk ? .white : C.label)
                        .frame(width: 46, height: 68)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Tr("继续添加照片"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .animation(.spring(response: 0.26, dampingFraction: 0.82), value: draftImages.count)
    }

    private var activeComposer: some View {
        VStack(spacing: 0) {

            if let q = quote {
                HStack(spacing: 8) {
                    Rectangle().fill(adaptiveMicInk).frame(width: 3, height: 38)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(q.senderId == myId ? Tr("我") : displayName(q))
                            .font(pf(11.5))
                            .foregroundColor(adaptiveMicInk)
                        Text(quoteComposerSummary(q))
                            .font(pf(12.5))
                            .foregroundColor(composerUsesLightInk
                                             ? Color.white.opacity(0.84)
                                             : Color(hex: 0x4B5055))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if !quotePreviewThumb(q).isEmpty {
                        RemoteImage(path: quotePreviewThumb(q), mode: .fill, maxSide: 240)
                            .frame(width: 38, height: 38)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(Color.black.opacity(0.08), lineWidth: 0.5))
                    }
                    Button { quote = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 17))
                            .foregroundColor(composerUsesLightInk
                                             ? Color.white.opacity(0.68)
                                             : C.subLabel)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(adaptiveComposerSurface)
            }

            if let draft = reEditDraft {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundColor(C.green)
                    Text(Tr("重新编辑"))
                        .font(pf(13.5))
                        .foregroundColor(C.label)
                    Spacer(minLength: 0)
                    Button { reEditDraft = nil } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(C.subLabel)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 12)
                .padding(.trailing, 6)
                .frame(height: 36)
                .background(ChatTheme.panel)
                .contentShape(Rectangle())
                .onTapGesture {
                    input = draft
                    reEditDraft = nil
                    focused = true
                }
            }

            if !draftImages.isEmpty {
                draftImagesBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if kbUp {
                quickBar
            }

            if panel == .plus {
                ChatRecentPhotoStrip(
                    store: recentPhotos,
                    onPick: { image in
                        panel = .none
                        pendingMedia = .image(image, nativeCamera: false)
                    },
                    onOpenLibrary: {
                        openPhotoPicker()
                    })
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(3)
            }

            HStack(spacing: 6) {

                Button {
                    if recorder.recording { return }
                    if voiceMode {
                        voiceMode = false
                        focused = true
                    } else {
                        focused = false
                        panel = .none
                        showCamera = true
                    }
                } label: {
                    Group {
                        if recorder.recording {
                            Image(systemName: "waveform")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(recorder.willCancel ? C.red : C.green)
                        } else if voiceMode {
                            Image(systemName: "keyboard")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(C.green)
                        } else {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(adaptiveMicInk)
                        }
                    }
                    .frame(width: 32, height: 40)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Tr(voiceMode ? "切换到键盘" : "拍摄"))

                HStack(spacing: 0) {
                    if voiceMode {

                        HStack(spacing: 9) {
                            if recorder.recording {
                                Circle()
                                    .fill(recorder.willCancel ? C.red : C.green)
                                    .frame(width: 8, height: 8)
                                InlineVoiceWave(level: recorder.level,
                                                active: !recorder.willCancel)
                                    .frame(width: 76, height: 22)
                                Text(String(format: "%d:%02d",
                                            recorder.seconds / 60,
                                            recorder.seconds % 60))
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(composerTextInk)
                                    .monospacedDigit()
                                Spacer(minLength: 0)
                                Text(recorder.willCancel
                                     ? Tr("松手取消")
                                     : (recorder.willTranscribe ? Tr("松手转文字") : Tr("松手发送")))
                                    .font(pf(12.5, .medium))
                                    .foregroundStyle(recorder.willCancel ? C.red : C.green)
                            } else {
                                Image(systemName: voiceStarting ? "waveform" : "mic.fill")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(C.green)
                                Text(voiceStarting ? Tr("正在开始录音…") : Tr("按住 说话"))
                                    .font(pf(15.5))
                                    .foregroundColor(composerTextInk)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, recorder.recording ? 12 : 0)
                        .frame(height: composerInputHeight)
                        .background(
                            recorder.recording
                            ? (recorder.willCancel ? C.red.opacity(0.09) : Color.white.opacity(0.72))
                            : Color.clear,
                            in: RoundedRectangle(cornerRadius: 19, style: .continuous)
                        )
                        .contentShape(Rectangle())

                        .scaleEffect(pressStart != nil ? 0.965 : 1)
                        .opacity(pressStart != nil ? 0.86 : 1)
                        .animation(.spring(response: 0.20, dampingFraction: 0.68), value: pressStart)
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { v in
                                    if recorder.recording {
                                        recorder.drag(v.translation.height)
                                        return
                                    }

                                    guard pressStart == nil else { return }
                                    pressStart = Date()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                                        guard pressStart != nil, !recorder.recording else { return }
                                        voiceStarting = true
                                        focused = false
                                        panel = .none
                                        Task {
                                            _ = await recorder.begin()
                                            voiceStarting = false
                                        }
                                    }
                                }
                                .onEnded { _ in
                                    pressStart = nil
                                    voiceStarting = false
                                    guard recorder.recording else { return }

                                    if recorder.willCancel { recorder.cancel(); return }
                                    if recorder.willTranscribe {
                                        guard let got = recorder.end() else { return }
                                        transcribeToInput(got.url)
                                        return
                                    }
                                    finishVoice()
                                }
                        )
                    } else if recorder.recording {
                        HStack(spacing: 9) {
                            Circle()
                                .fill(recorder.willCancel ? C.red : C.green)
                                .frame(width: 8, height: 8)
                            InlineVoiceWave(level: recorder.level,
                                            active: !recorder.willCancel)
                                .frame(width: 76, height: 22)
                            Text(String(format: "%d:%02d",
                                        recorder.seconds / 60,
                                        recorder.seconds % 60))
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(composerTextInk)
                                .monospacedDigit()
                            Spacer(minLength: 0)
                            Text(recorder.willCancel ? Tr("松手取消") : Tr("松手发送"))
                                .font(pf(12.5, .medium))
                                .foregroundStyle(recorder.willCancel ? C.red : C.green)
                        }
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: composerInputHeight)
                        .background(
                            recorder.willCancel ? C.red.opacity(0.09)
                                                : Color.white.opacity(0.72),
                            in: RoundedRectangle(cornerRadius: 19, style: .continuous)
                        )
                    } else {
                        HStack(spacing: 4) {
                        ChatComposerTextField(text: $input,
                                              focused: $focused,
                                              bridge: composerBridge,
                                              font: chatComposerUIFont(),
                                              tintColor: UIColor(hex: 0x2F7FD8),
                                              textColor: UIColor(composerTextInk),
                                              minHeight: L.inputH,
                                              maxHeight: composerMaxHeight,
                                              onHeightChange: { height in
                                                  guard abs(inputBoxHeight - height) > 0.5 else { return }
                                                  withAnimation(.spring(response: 0.22,
                                                                        dampingFraction: 0.92,
                                                                        blendDuration: 0.08)) {
                                                      inputBoxHeight = height
                                                  }
                                              },
                                              onBeginEditing: { panel = .none })

                            .onChange(of: input) { v in
                                reportTyping()
                                scheduleDraftSave(v)

                                if isGroup, justTypedAtSign(from: lastInputSnapshot, to: v) { openMentionPicker() }
                                lastInputSnapshot = v
                            }

                            if !voiceMode,
                               input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Button {
                                    focused = false
                                    panel = .none
                                    voiceMode = true
                                } label: {
                                    Image(systemName: "mic")
                                        .font(.system(size: max(19, L.composerIcon - 3), weight: .medium))
                                        .foregroundColor(adaptiveMicInk)
                                        .frame(width: 32, height: 40)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Tr("切换到语音"))
                            }
                        }
                    }
                }
                .padding(.horizontal, 6)
                .frame(height: composerInputHeight)
                .background {
                    RoundedRectangle(cornerRadius: composerFieldRadius,
                                     style: .continuous)
                        .fill(recorder.recording
                              ? (recorder.willCancel
                                 ? Color.dyn(0xFFF1F1, 0x3A2A2A)
                                 : Color.dyn(0xF2F2F2, 0x242427))
                              : composerFieldFill)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: composerFieldRadius,
                                     style: .continuous)
                        .stroke(composerFieldBorder, lineWidth: 0.6)
                }
                if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draftImages.isEmpty {

                    HStack(spacing: 2) {
                        Button {
                            focused = false
                            panel = (panel == .emoji) ? .none : .emoji
                        } label: {
                            Image(systemName: "face.smiling")
                                .font(.system(size: max(19, L.composerIcon - 3), weight: .medium))
                                .symbolRenderingMode(.monochrome)
                                .foregroundStyle(panel == .emoji ? C.green : adaptiveEmojiInk)
                                .frame(width: 32, height: 40)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Tr("表情"))

                        Button {
                            focused = false
                            panel = (panel == .plus) ? .none : .plus
                            if panel == .plus && plusItems.isEmpty {
                                Task {
                                    await recentPhotos.loadIfNeeded(force: true,
                                                                    requestAccess: true)
                                    let items = (try? await API.shared.plusPanel()) ?? []
                                    plusItems = normalizedPlusItems(items)
                                }
                            } else if panel == .plus {
                                Task {
                                    await recentPhotos.loadIfNeeded(force: true,
                                                                    requestAccess: true)
                                }
                            }
                        } label: {
                            plusIcon
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Tr("更多功能"))
                    }
                    .padding(.horizontal, 2)
                    .frame(height: L.composerIconBox + 8)
                } else {
                    HStack(spacing: 2) {
                        if !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button {
                                focused = false
                                panel = (panel == .emoji) ? .none : .emoji
                            } label: {
                                Image(systemName: "face.smiling")
                                    .font(.system(size: max(19, L.composerIcon - 3), weight: .medium))
                                    .symbolRenderingMode(.monochrome)
                                    .foregroundStyle(panel == .emoji ? C.green : adaptiveEmojiInk)
                                    .frame(width: 32, height: 40)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Tr("表情"))
                        }

                        Button {
                            if draftImages.isEmpty {
                                sendText()
                            } else {
                                sendDraftImages()
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(
                                        colors: [Color(hex: 0x4EDC7C), C.green],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ))
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 15.5, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .offset(x: -0.5, y: 0.5)
                            }
                                .frame(width: 36, height: 36)
                                .shadow(color: C.green.opacity(0.22), radius: 7, y: 3)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Tr("发送"))
                        .transition(.scale(scale: 0.72).combined(with: .opacity))
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .animation(.spring(response: 0.24, dampingFraction: 0.82),
                       value: input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draftImages.isEmpty)

            panelView

                .background {
                    Group {
                        if panel == .emoji {
                            ChatEmojiPanelMaterial()
                        } else if panel != .none {
                            ChatPanelGlassBackground()
                        } else {
                            Color.clear
                        }
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
        }
        .background {
            if !(panel == .emoji && emojiPanelExpanded) {
                Group {
                    if isStarWorld && newsMode {
                        newsMaskColor
                    } else {
                        ChatImmersiveEdgeMask(path: backgroundPath,
                                              edge: .bottom,
                                              tint: wallpaperBottomTint,
                                              dark: composerUsesLightInk,
                                              effect: backgroundEffect,
                                              preset: ChatTheme.preset,
                                              themeVersion: chatTheme.version)
                    }
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
    }

    @ViewBuilder
    private var panelView: some View {
        switch panel {
        case .emoji:
            EmojiPanel(draft: $input,
                       onSend: { sendText(); panel = .none },
                       onDelete: { composerBridge.deleteBackward() },
                       onInsert: { composerBridge.insert($0) },
                       onSendSticker: { url in

                           send(kind: "image", content: url)
                           panel = .none
                       },

                       onOpenStore: { panel = .none; showStickerStore = true },

                       onCaptureSticker: { panel = .none; showCaptureSticker = true },
                       mine: myStickers,
                       onExpandedChange: { emojiPanelExpanded = $0 })
        case .plus:
            PlusPanel(items: plusItems,
                      onTap: { item in handlePlus(item) },
                      onLongPress: { item in handlePlusLong(item) })
        case .mention:
            MentionPanel(members: mentionMembers,
                         query: $mentionQuery,
                         canAtAll: chat.ownerId == myId,
                         title: { mentionName($0) },
                         onPick: { pickMention($0) },
                         onPickAll: { pickMentionAll() })
        case .gift:
            GiftPanel(gifts: gifts) { gift in
                let payload = "{\"id\":\"\(gift.id)\",\"name\":\"\(gift.name ?? "礼物")\",\"icon\":\"\(gift.icon ?? "🎁")\",\"price\":\(Int(gift.price ?? 0))}"
                send(kind: "gift", content: payload)
                panel = .none
            }
        case .none:
            EmptyView()
        }
    }

    private func openPhotoPicker() {
        focused = false
        panel = .none
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            showPhoto = true
        }
    }

    private func handlePlus(_ item: PlusItem) {
        switch item.action ?? "none" {
        case "photo":
            openPhotoPicker()
        case "camera":
            panel = .none
            showCamera = true
        case "screenshare":
            panel = .none
            if isGroup {
                CallCenter.shared.requestGroupScreenShare(chatId: chat.id,
                                                          title: chat.name ?? "")
            } else if let peer = peerUserId {
                let peerName = app.contact(for: peer)?.name ?? chat.name
                CallCenter.shared.requestScreenShare(peerId: peer,
                                                     name: peerName,
                                                     avatar: chat.avatar ?? "")
            } else {
                app.show(Tr("找不到对方账号，先刷新一下会话"))
            }
        case "location":
            panel = .none
            showLocationMenu = true
        case "liveshare":
            panel = .none
            showLiveLocation = true
        case "gift":
            panel = .gift
            if gifts.isEmpty { Task { gifts = (try? await API.shared.gifts()) ?? [] } }
        case "transfer":
            panel = .none
            showTransfer = true
        case "file":
            panel = .none
            openFilePicker()
        case "videocall":
            panel = .none
            if (chat.botRank ?? 9) < 9 {
                showCall = true
            } else {

                showCallChoice = true
            }
        case "voice":
            panel = .none
            app.show(Tr("按住输入框左边的麦克风说话：松开发送，上滑取消"))
        case "redpacket":
            panel = .none
            showSendRedPacket = true
        case "favorite":
            panel = .none
            app.show(Tr("收藏夹还是空的"))
        case "card":
            panel = .none
            showPickCard = true
        case "music":

            panel = .none
            showPickMusic = true
        default:
            app.show("\(chatEntryLabel(item.label, action: item.action))排在下一批")
        }
    }

    private func dismissTyping() {
        if panel != .none { panel = .none }
        if focused { focused = false }
    }

    private func loadMyStickers() async {
        if let r = try? await API.shared.stickerShop() { myStickers = r.mine }
    }

    private func captureSticker(_ image: UIImage) {
        app.show(Tr("正在添加表情…"))
        Task {
            guard let url = try? await API.shared.upload(image: image) else {
                app.show(Tr("表情上传失败，再试一次"))
                return
            }
            await API.shared.addSingleSticker(url)
            await loadMyStickers()
            app.show(Tr("已添加到我的表情"))
        }
    }

    private func sendMusic(_ t: MusicTrack) {
        let body: [String: Any] = [
            "id": t.id,
            "title": t.title,
            "artist": t.artist ?? "",
            "cover": t.cover ?? "",
            "url": t.url
        ]
        guard let d = try? JSONSerialization.data(withJSONObject: body),
              let json = String(data: d, encoding: .utf8) else { return }
        send(kind: "music", content: json)
    }

    private func sendText() {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return }

        if isStarWorld, newsMode { withAnimation(.easeInOut(duration: 0.18)) { newsMode = false } }

        let quotePayload = quoteFields(quote)
        draftSaveTask?.cancel()
        ChatDraftStore.shared.clear(chat.id)
        input = ""
        quote = nil
        reEditDraft = nil

        let ids = mentionIds.filter { id in
            guard let u = mentionMembers.first(where: { $0.id == id }) else { return true }
            return text.contains("@" + mentionName(u))
        }
        mentionIds = []

        send(kind: "text", content: ClassicEmojiSet.expand(text), mentions: ids, quote: quotePayload)
    }

    private func scheduleDraftSave(_ value: String) {
        draftSaveTask?.cancel()
        draftSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 260_000_000)
            guard !Task.isCancelled else { return }
            ChatDraftStore.shared.set(value, for: chat.id)
        }
    }

    private func quoteFields(_ q: Message?) -> [String: Any]? {
        guard let q = q, !q.id.isEmpty else { return nil }
        let who = q.senderId == myId ? Tr("我") : displayName(q)
        var d: [String: Any] = ["id": q.id, "who": who, "kind": q.kindName]
        let thumb = quotePreviewThumb(q)
        if !thumb.isEmpty { d["thumb"] = thumb }
        switch q.kindName {
        case "text":
            d["text"] = String(q.body.prefix(90))
        case "image":
            d["text"] = Tr("[图片]")
        case "images":
            d["text"] = Tr("[图片]")
        case "audio":
            d["text"] = Tr("[语音]")
        case "video":
            d["text"] = Tr("[视频]")
        case "livephoto":
            d["text"] = Tr("[实况]")
        default:
            d["text"] = "[" + q.kindName + "]"
        }
        return d
    }

    private func quoteComposerSummary(_ q: Message) -> String {
        switch q.kindName {
        case "text", "link":
            return String(q.body.prefix(40))
        case "image", "images":
            return Tr("[图片]")
        case "video":
            return Tr("[视频]")
        case "livephoto":
            return Tr("[实况]")
        case "audio":
            return Tr("[语音]")
        default:
            return "[" + q.kindName + "]"
        }
    }

    private func quotePreviewThumb(_ q: Message) -> String {
        switch q.kindName {
        case "image":
            return q.imagePath
        case "images":
            return Self.firstImagePath(q.body) ?? ""
        case "video":
            return Self.firstJSONString(q.body, key: "cover") ?? ""
        case "livephoto":
            return Self.firstJSONString(q.body, key: "image") ?? ""
        default:
            return ""
        }
    }

    private static func firstJSONString(_ body: String, key: String) -> String? {
        guard let d = body.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let value = o[key] as? String, !value.isEmpty else { return nil }
        return value
    }

    private static func firstImagePath(_ body: String) -> String? {
        guard let d = body.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let paths = o["paths"] as? [String], let first = paths.first, !first.isEmpty else { return nil }
        return first
    }

    private func justTypedAtSign(from old: String, to new: String) -> Bool {
        let a = Array(old), b = Array(new)
        guard b.count == a.count + 1 else { return false }
        for i in 0..<b.count {
            if i >= a.count { return b[i] == "@" }
            if b[i] != a[i] { return b[i] == "@" }
        }
        return false
    }

    private func openMentionPicker() {
        mentionQuery = ""
        panel = .mention
        focused = false
        guard mentionMembers.isEmpty else { return }
        Task {
            if let r = try? await API.shared.chatMembers(chatId: chat.id) {
                mentionMembers = r.members.filter { $0.id != myId }
            }
        }
    }

    private func mentionName(_ u: User) -> String {

        if let a = u.alias, !a.isEmpty { return a }
        if let r = app.contact(for: u.id)?.remark, !r.trimmingCharacters(in: .whitespaces).isEmpty { return r }
        if let n = u.nickname, !n.isEmpty { return n }
        return u.username ?? Tr("成员")
    }

    private func pickMention(_ u: User) {
        insertMention(mentionName(u))
        if !mentionIds.contains(u.id) { mentionIds.append(u.id) }
    }

    private func pickMentionAll() {
        insertMention(Tr("所有人"))
    }

    private func insertMention(_ name: String) {
        if input.hasSuffix("@") { input.removeLast() }
        if !input.isEmpty, !input.hasSuffix(" ") { input += " " }
        input += "@" + name + " "
        mentionQuery = ""
        panel = .none
        focused = true
    }

    private func openImage(_ path: String) {

        var all: [String] = []
        for m in messages where !m.isRecalled {
            if m.kindName == "image" {
                all.append(m.imagePath)
            } else if m.kindName == "images" {
                if let data = m.body.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let paths = obj["paths"] as? [String] {
                    all.append(contentsOf: paths)
                }
            }
        }
        if !path.isEmpty, !all.contains(path) { all.insert(path, at: 0) }
        guard !all.isEmpty else { return }
        viewer = PhotoPager.Item(paths: all, index: all.firstIndex(of: path) ?? 0)
    }

    private func openAvatar(_ senderId: String) {
        let id = senderId.isEmpty ? myId : senderId
        if id.isEmpty { return }

        if (chat.botRank ?? 9) < 9, senderId.isEmpty || senderId == peerUserId {
            botCard = true
            return
        }
        if id == myId, let me = app.me { cardUser = me; return }
        if let u = app.contact(for: id) { cardUser = u; return }
        Task {
            if let u = try? await API.shared.user(id: id) { cardUser = u }
            else { app.show(Tr("打不开这个人的名片")) }
        }
    }

    private func openCardUser(_ id: String) {
        guard !id.isEmpty else { return }
        if let u = app.contact(for: id) { cardUser = u; return }
        Task {
            if let u = try? await API.shared.user(id: id) { cardUser = u }
            else { app.show(Tr("打不开这个人的名片")) }
        }
    }

    private func handlePlusLong(_ item: PlusItem) -> Bool {
        guard (item.action ?? "").lowercased() == "camera" else { return false }
        panel = .none
        showCameraVideo = true
        return true
    }

    private func sendRecordedVideo(_ url: URL) {
        Task {

            var file = url
            let dst = FileManager.default.temporaryDirectory
                .appendingPathComponent("shot-\(Int(Date().timeIntervalSince1970 * 1000)).mov")
            if (try? FileManager.default.copyItem(at: url, to: dst)) != nil { file = dst }
            let cover = await MediaTool.firstFrame(file)

            try? await Task.sleep(nanoseconds: 200_000_000)
            sendMedia(.video(file, cover), live: false, original: false)
        }
    }

    private func sendCard(_ u: User) {
        Task {

            var name = u.name
            var username = u.username ?? ""
            var avatar = u.avatarPath
            if username.isEmpty || avatar.isEmpty {
                if let full = try? await API.shared.user(id: u.id) {
                    name = full.name.isEmpty ? name : full.name
                    username = (full.username ?? "").isEmpty ? username : (full.username ?? "")
                    avatar = full.avatarPath.isEmpty ? avatar : full.avatarPath
                }
            }
            let body: [String: Any] = [
                "userId": u.id,
                "name": name,
                "avatar": avatar,
                "username": username
            ]
            let json = (try? JSONSerialization.data(withJSONObject: body))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            send(kind: "card", content: json)
        }
    }

    private func send(kind: String, content: String, mentions: [String] = [],
                      quote: [String: Any]? = nil) {

        if isStarWorld, newsMode { withAnimation(.easeInOut(duration: 0.18)) { newsMode = false } }

        var qJSON: String?
        if let q = quote, !q.isEmpty,
           let d = try? JSONSerialization.data(withJSONObject: q) {
            qJSON = String(data: d, encoding: .utf8)
        }
        outbox.append(PendingMsg(id: UUID().uuidString, kind: kind, content: content,
                                 mentions: mentions, quoteJSON: qJSON))
        followOwnSendUntil = Date().addingTimeInterval(5)
        saveOutbox()

        UINotification.lightTap()
        pinToBottomSoon(force: true)
        Task { await flushOutbox() }
    }

    @MainActor
    private func flushOutbox() async {
        guard !flushing, !outbox.isEmpty else { return }
        flushing = true
        defer { flushing = false }
        for p in outbox.filter({ !$0.sending }) {
            guard let idx = outbox.firstIndex(where: { $0.id == p.id }) else { continue }
            outbox[idx].sending = true
            outbox[idx].failed = false
            outbox[idx].failureReason = nil
            do {
                if let message = try await API.shared.send(chatId: chat.id, kind: p.kind, content: p.content,
                                                           mentions: p.mentions, clientId: p.id,
                                                           quote: Self.quoteDict(p.quoteJSON)) {
                    appendVisibleMessage(message)
                    app.ensureChatVisible(chat, latest: message)
                }
                outbox.removeAll { $0.id == p.id }
            } catch {
                let reason = (error as? APIError)?.errorDescription ?? "发送失败"
                if p.kind == "text", reason.contains("敏感词") || reason.contains("稍后再试") {

                    outbox.removeAll { $0.id == p.id }
                    if input.isEmpty { input = p.content }
                    app.show(reason)
                } else if let i2 = outbox.firstIndex(where: { $0.id == p.id }) {
                    outbox[i2].sending = false
                    outbox[i2].failed = true
                    outbox[i2].failureReason = reason
                }
            }
        }
        saveOutbox()
        await app.loadChats()
    }

    private func tapRedPacket(_ info: RedPacketInfo) {
        if info.fromId != myId && info.stillOpen && !info.claimed(by: myId) {
            openRedPacket = info
        } else {
            redPacketDetail = info.id
        }
    }

    private func dataURLToImage(_ s: String) -> UIImage? {
        guard let comma = s.firstIndex(of: ","),
              let data = Data(base64Encoded: String(s[s.index(after: comma)...])) else { return nil }
        return UIImage(data: data)
    }

    private static func jsonStringArray(_ items: [String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: items),
              let s = String(data: data, encoding: .utf8) else { return "[]" }
        return s
    }

    private func stageDraftImages(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        let room = max(0, 9 - draftImages.count)
        guard room > 0 else {
            app.show(Tr("一次最多发送 9 张照片"))
            return
        }
        if images.count > room {
            app.show(Tr("一次最多发送 9 张照片，多出的已忽略"))
        }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
            draftImages.append(contentsOf: images.prefix(room))
        }
        focused = false
        panel = .none
    }

    private func sendDraftImages() {
        let images = draftImages
        guard !images.isEmpty else { return }
        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
            draftImages.removeAll()
        }
        sendMedia(.images(images), live: false, original: false)
    }

    private func sendMedia(_ p: MediaSendSheet.Payload, live: Bool, original: Bool) {
        switch p {
        case .image(let img, let nativeCamera):
            uploading = true
            sendingPreview = img
            sendingMedia = Tr("图片上传中…")
            sendProgress = 0.02
            scrollTick += 1
            let px = img.sendPixelSize
            Task {
                let t0 = Date()
                do {
                    let up = try await API.shared.uploadImageForSend(
                        img, original: original,
                        preserveResolution: nativeCamera,
                        onProgress: { p in
                            DispatchQueue.main.async {
                                sendProgress = min(0.82, 0.02 + p * 0.80)
                            }
                        })
                    let url = up.url
                    seedLocalImage(url, img, data: up.data)
                    sendingMedia = Tr("正在发送…")
                    sendProgress = 0.9
                    let tUp = Date()
                    if let m = try await API.shared.send(chatId: chat.id, kind: "image", content: url,
                                                         imgW: px.w, imgH: px.h) {
                        appendVisibleMessage(m)
                    }
                    let tSend = Date()
                    Task { await API.shared.callDiag("发图(+) 压+传=\(Int(tUp.timeIntervalSince(t0) * 1000))ms"
                        + " 发送=\(Int(tSend.timeIntervalSince(tUp) * 1000))ms"
                        + " 原图=\(original ? 1 : 0) 原始=\(Int(img.size.width))x\(Int(img.size.height))") }
                } catch { app.show((error as? APIError)?.errorDescription ?? "图片发送失败") }
                uploading = false
                sendingMedia = ""
                sendingPreview = nil
                sendProgress = 0
                await app.loadChats()
            }

        case .images(let list):

            guard !list.isEmpty else { return }
            CrashCatcher.note("发图", "多选 \(list.count) 张，开始上传")
            uploading = true
            sendingPreview = list.first
            sendingMedia = Tr("图片上传中…") + " 0/\(list.count)"
            sendProgress = 0.02
            scrollTick += 1
            let progress = ImageUploadProgress(count: list.count)
            Task {
                do {
                    var urls: [String] = []
                    var dims: [(w: Int, h: Int)] = []

                    var upResults: [(idx: Int, url: String, w: Int, h: Int, data: Data)] = []
                    var upError: String? = nil
                    await withTaskGroup(of: (Int, String, Int, Int, Data, String?).self) { group in
                        var nextIdx = 0
                        func addUpload(_ i: Int) {
                            let img = list[i]
                            let px = img.sendPixelSize
                            group.addTask {
                                do {
                                    let up = try await API.shared.uploadImageForSend(
                                        img, original: original,
                                        onProgress: { p in
                                            let state = progress.update(index: i, value: p)
                                            DispatchQueue.main.async {
                                                sendProgress = min(0.82, 0.02 + state.progress * 0.80)
                                                sendingMedia = Tr("图片上传中…") + " \(state.completed)/\(list.count)"
                                            }
                                        })
                                    return (i, up.url, px.w, px.h, up.data, nil)
                                } catch {
                                    return (i, "", 0, 0, Data(),
                                            (error as? APIError)?.errorDescription ?? "图片上传失败")
                                }
                            }
                        }
                        while nextIdx < min(3, list.count) { addUpload(nextIdx); nextIdx += 1 }
                        for await r in group {
                            if let e = r.5 {
                                if upError == nil { upError = e }
                            } else {
                                upResults.append((idx: r.0, url: r.1, w: r.2, h: r.3, data: r.4))
                            }
                            if nextIdx < list.count { addUpload(nextIdx); nextIdx += 1 }
                        }
                    }
                    if let e = upError, upResults.count != list.count { throw APIError.message(e) }
                    for r in upResults.sorted(by: { $0.idx < $1.idx }) {
                        urls.append(r.url)
                        dims.append((w: r.w, h: r.h))
                        seedLocalImage(r.url, list[r.idx], data: r.data)
                    }
                    if urls.count >= 2 {
                        sendingMedia = Tr("正在发送…")
                        sendProgress = 0.9
                        CrashCatcher.note("发图", "合成一条相册消息（\(urls.count) 张）")
                        let body = "{\"paths\":" + Self.jsonStringArray(urls) + "}"
                        if let m = try await API.shared.send(chatId: chat.id, kind: "images", content: body) {
                            appendVisibleMessage(m)
                        }
                    } else {
                        CrashCatcher.note("发图", "\(urls.count) 张，分开一条一条发")
                        for (i, u) in urls.enumerated() {
                            let d: (w: Int, h: Int) = i < dims.count ? dims[i] : (w: 0, h: 0)
                            if let m = try await API.shared.send(chatId: chat.id, kind: "image", content: u,
                                                                 imgW: d.w, imgH: d.h) {
                                appendVisibleMessage(m)
                            }
                        }
                    }
                } catch { app.show((error as? APIError)?.errorDescription ?? "图片发送失败") }
                uploading = false
                sendingMedia = ""
                sendingPreview = nil
                sendProgress = 0
                await app.loadChats()
            }

        case .video(let url, let preview):
            uploading = true
            sendProgress = 0.02
            sendingPreview = preview
            sendingMedia = Tr("视频发送中…")
            scrollTick += 1
            Task {

                let cover: UIImage?
                if let p = preview { cover = p } else { cover = await MediaTool.firstFrame(url) }
                if cover != nil { sendingPreview = cover }

                let coverTask = Task { () -> String? in
                    guard let c = cover else { return nil }
                    let up = try? await API.shared.uploadImageForSend(c, original: false)
                    if let up = up { seedLocalImage(up.url, c, data: up.data) }
                    return up?.url
                }

                var file = url

                var uploadFrom = 0.0
                if !original, await MediaTool.needsCompress(url) {
                    sendingMedia = Tr("视频压缩中…")
                    uploadFrom = 0.45
                    file = (await MediaTool.compress(url) { p in
                        DispatchQueue.main.async { sendProgress = min(0.45, p * 0.45) }
                    }) ?? url
                    sendingMedia = Tr("视频发送中…")
                }

                let secs = await MediaTool.seconds(file)

                let wh = await MediaTool.aspect(file)
                let from = uploadFrom
                guard let up = await MediaTool.upload(file, onProgress: { p in
                    DispatchQueue.main.async {
                        sendProgress = from + p * (1 - from)
                        if p >= 0.999 { sendingMedia = Tr("服务器处理中…") }
                    }
                }, skipServerTranscode: true) else {
                    uploading = false
                    sendingMedia = ""
                    sendingPreview = nil
                    app.show(Tr("视频上传失败"))
                    return
                }

                LocalStore.keepOriginal(up, from: file)
                var body: [String: Any] = ["url": up, "seconds": secs]
                if let wh = wh { body["w"] = wh.w; body["h"] = wh.h }

                if let cp = await coverTask.value {
                    body["cover"] = cp
                }
                let json = (try? JSONSerialization.data(withJSONObject: body)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                if let m = try? await API.shared.send(chatId: chat.id, kind: "video", content: json) {
                    appendVisibleMessage(m)
                }
                uploading = false
                sendingMedia = ""
                sendingPreview = nil
                await app.loadChats()
            }

        case .live(let img, let url):

            if !live { sendImage(img); return }
            uploading = true
            sendProgress = 0.02
            sendingPreview = img
            sendingMedia = Tr("实况发送中…")
            scrollTick += 1
            Task {
                do {
                    let up = try await API.shared.uploadImageForSend(img, original: original)
                    let iurl = up.url
                    seedLocalImage(iurl, img, data: up.data)
                    DispatchQueue.main.async { sendProgress = 0.25 }
                    var file = url
                    var uploadFrom = 0.25
                    if !original, await MediaTool.needsCompress(url) {
                        sendingMedia = Tr("实况压缩中…")
                        file = (await MediaTool.compress(url) { p in
                            DispatchQueue.main.async { sendProgress = 0.25 + p * 0.15 }
                        }) ?? url
                        uploadFrom = 0.4
                        sendingMedia = Tr("实况发送中…")
                    }
                    let from = uploadFrom
                    guard let vurl = await MediaTool.upload(file, onProgress: { p in
                        DispatchQueue.main.async { sendProgress = from + p * (1 - from) }
                    }, skipServerTranscode: true) else { throw APIError.message("实况上传失败") }

                    LocalStore.keepOriginal(vurl, from: file)
                    let body: [String: Any] = ["image": iurl, "video": vurl]
                    let json = (try? JSONSerialization.data(withJSONObject: body)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                    if let m = try await API.shared.send(chatId: chat.id, kind: "livephoto", content: json) {
                        appendVisibleMessage(m)
                    }
                } catch { app.show((error as? APIError)?.errorDescription ?? "实况发送失败") }
                uploading = false
                sendingMedia = ""
                sendingPreview = nil
                await app.loadChats()
            }
        }
    }

    private func seedLocalImage(_ path: String, _ image: UIImage, data: Data) {
        guard !path.isEmpty else { return }
        ImageStore.shared.put(path, image)
        ImageSizeCache.put(path, ImageBubble.thumb(image.size))
        guard !data.isEmpty else { return }
        Task.detached(priority: .utility) {
            ImageStore.shared.diskWrite(path, data)
            LocalStore.keep(path, data: data)
        }
    }

    private func sendImage(_ image: UIImage) {
        uploading = true
        let px = image.sendPixelSize
        Task {
            let t0 = Date()
            do {
                let up = try await API.shared.uploadImageForSend(image, original: false)
                let url = up.url

                seedLocalImage(url, image, data: up.data)
                let tUp = Date()
                if let message = try await API.shared.send(chatId: chat.id, kind: "image", content: url,
                                                           imgW: px.w, imgH: px.h) {
                    appendVisibleMessage(message)
                }
                let tSend = Date()

                Task { await API.shared.callDiag("发图 压+传=\(Int(tUp.timeIntervalSince(t0) * 1000))ms"
                    + " 发送=\(Int(tSend.timeIntervalSince(tUp) * 1000))ms"
                    + " 原始=\(Int(image.size.width))x\(Int(image.size.height))") }
            } catch {
                app.show((error as? APIError)?.errorDescription ?? "图片发送失败")
            }
            uploading = false
            await app.loadChats()
        }
    }

    private func finishVoice() {
        guard let got = recorder.end() else { return }
        sendVoice(url: got.url, seconds: got.seconds, waveform: got.waveform)
    }

    private func transcribeMessage(_ m: Message) {
        guard let data = m.body.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let path = o["url"] as? String,
              let url = API.shared.assetURL(path) else {
            app.show(Tr("这条语音找不到了"))
            return
        }
        asrCache.removeValue(forKey: m.id)
        asrBusy.insert(m.id)
        Task {
            defer { asrBusy.remove(m.id) }
            guard await FileSpeech.authorize() else {
                app.show(Tr("请先在 设置 → 星言 → 语音识别 里允许，才能转文字"))
                return
            }
            var text = ""
            if let d = try? await API.shared.assetData(url), !d.isEmpty {
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("asr-\(m.id).m4a")
                try? d.write(to: tmp)
                text = await FileSpeech.recognize(url: tmp)
                try? FileManager.default.removeItem(at: tmp)
            }
            if text.isEmpty {
                app.show(Tr("没听清，再说一次或者直接发语音"))
            } else {

                VoiceText.set(m.id, text)
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    asrCache[m.id] = text
                }
            }
        }
    }

    private func transcribeToInput(_ url: URL) {
        Task {
            guard await FileSpeech.authorize() else {
                app.show(Tr("请先在 设置 → 星言 → 语音识别 里允许，才能转文字"))
                return
            }
            let text = await FileSpeech.recognize(url: url)
            if text.isEmpty {
                app.show(Tr("没听清，再说一次或者直接发语音"))
            } else {
                input = text
                voiceMode = false
            }
        }
    }

    private func sendVoice(url: URL, seconds: Int, waveform: [CGFloat]) {
        Task {
            uploading = true
            defer { uploading = false }

            let effect = VoiceChangerStore.shared.current
            var file = url
            if effect.id != "origin" {
                file = await Task.detached(priority: .userInitiated) {
                    VoiceChanger.process(url, preset: effect)
                }.value
            }
            guard let data = try? Data(contentsOf: file), !data.isEmpty else {
                app.show(Tr("录音读不到，再录一次"))
                return
            }
            let payload: [String: Any] = [
                "dataUrl": "data:audio/mp4;base64," + data.base64EncodedString(),
                "filename": "voice.m4a"
            ]
            do {
                let up = try await API.shared.rawUpload(payload)
                var info: [String: Any] = [
                    "url": up.url,
                    "seconds": seconds,
                    "bytes": data.count
                ]
                if !waveform.isEmpty {
                    info["wave"] = waveform.map { Double(($0 * 1000).rounded() / 1000) }
                }
                let body = (try? JSONSerialization.data(withJSONObject: info))
                    .flatMap { String(data: $0, encoding: .utf8) }
                    ?? "{\"url\":\"\(up.url)\",\"seconds\":\(seconds)}"
                send(kind: "audio", content: body)
            } catch {
                app.show((error as? APIError)?.errorDescription ?? "语音发送失败")
            }
            try? FileManager.default.removeItem(at: url)
            if file != url { try? FileManager.default.removeItem(at: file) }
        }
    }

    private func sendFile(_ url: URL) {
        Task { await uploadAndSendFile(url) }
    }

    private func sendFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        Task {
            for u in urls { await uploadAndSendFile(u) }
        }
    }

    private func openFilePicker() {
        showFile = true
    }

    private func normalizedPlusItems(_ raw: [PlusItem]) -> [PlusItem] {
        var items = raw.filter { $0.enabled != false }
        if let i = items.firstIndex(where: { $0.action == "file" }) {
            if i >= 8 {
                let file = items.remove(at: i)
                items.insert(file, at: min(7, items.count))
            }
        } else {
            let file = PlusItem(id: "file-fallback", label: Tr("文件"),
                                icon: "file", action: "file", enabled: true)
            items.insert(file, at: min(7, items.count))
        }
        return items
    }

    private func sendExistingFile(_ f: API.MyFileItem) {
        let url = f.url ?? ""
        guard !url.isEmpty else { app.show(Tr("这个文件找不到了")); return }
        let name = f.fileName.replacingOccurrences(of: "\"", with: "")
                      .replacingOccurrences(of: "\\", with: "")
        let content = "{\"url\":\"\(url)\",\"name\":\"\(name)\",\"bytes\":\(f.bytes ?? 0)}"
        send(kind: "file", content: content)
    }

    private func uploadAndSendFile(_ url: URL) async {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }

        // AnyFilePicker 已经用 asCopy 把文件放进了 App 可读的本地副本，
        // 这里直接流式上传，避免大文件在发送前再整份复制一次。
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .nameKey])
        let sizeBytes = values?.fileSize ?? 0
        let name = values?.name ?? url.lastPathComponent
        if sizeBytes > 100 * 1024 * 1024 {
            app.show(Tr("这个文件超过 100MB，先压缩一下再发"))
            return
        }
        guard sizeBytes > 0 else {
            app.show(Tr("读不到这个文件"))
            return
        }
        uploading = true
        sendingFileName = name
        sendingFileBytes = sizeBytes
        sendingFileProgress = 0.01
        scrollTick += 1
        defer {
            uploading = false
            sendingFileName = ""
            sendingFileBytes = 0
            sendingFileProgress = nil
        }

        let sourceMime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"
        do {
            let uploadedURL = try await API.shared.uploadBinaryFile(
                url, mime: "application/octet-stream", skipTranscode: true, onProgress: { p in
                    let value = min(1, max(0.01, p))
                    DispatchQueue.main.async {
                        guard sendingFileName == name else { return }
                        sendingFileProgress = value
                    }
                })
            LocalStore.keepOriginal(uploadedURL, from: url)
            let body: [String: Any] = [
                "url": uploadedURL,
                "name": name,
                "bytes": sizeBytes,
                "mime": sourceMime
            ]
            let jsonData = try JSONSerialization.data(withJSONObject: body)
            guard let content = String(data: jsonData, encoding: .utf8) else {
                throw APIError.message("文件信息生成失败")
            }
            if let message = try await API.shared.send(chatId: chat.id, kind: "file", content: content) {
                appendVisibleMessage(message)
            }
            sendingFileProgress = nil
            sendingFileName = ""
            sendingFileBytes = 0
        } catch {
            app.show((error as? APIError)?.errorDescription ?? "文件发送失败")
        }
        await app.loadChats()
    }

    private func openFile(_ body: String) {
        guard let data = body.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let path = o["url"] as? String,
              !path.isEmpty else {
            app.show(Tr("这个文件找不到了"))
            return
        }
        let raw = (o["name"] as? String) ?? "文件"

        let name = MyFilesPickerView.previewName(raw, path: path)
        if let local = RemoteFileCache.localFile(path: path, preferredName: name) {
            filePreview = FilePreviewData(name: local.name, local: local.local,
                                          favoriteTitle: chat.name,
                                          favoriteFrom: "聊天文件")
            return
        }
        Task {
            do {
                let file = try await RemoteFileCache.shared.file(path: path,
                                                                 preferredName: name)
                filePreview = FilePreviewData(name: file.name, local: file.local,
                                              favoriteTitle: chat.name,
                                              favoriteFrom: "聊天文件")
            } catch {
                app.show(Tr("文件下载失败，检查一下网络"))
            }
        }
    }

    private func prepareFileShare(_ m: Message) {
        guard let data = m.body.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let path = o["url"] as? String,
              !path.isEmpty else {
            app.show(Tr("这个文件找不到了"))
            return
        }
        let raw = (o["name"] as? String) ?? "文件"
        let name = MyFilesPickerView.previewName(raw, path: path)
        app.show(Tr("正在准备分享…"))
        Task {
            do {
                let file = try await RemoteFileCache.shared.file(path: path,
                                                                 preferredName: name)
                shareFile = FilePreviewData(name: file.name, local: file.local)
            } catch {
                app.show(Tr("文件下载失败，检查一下网络"))
            }
        }
    }

    private func doTransfer(amount: Double, note: String, method: String, password: String) {
        Task {
            do {
                try await API.shared.transfer(chatId: chat.id, amount: amount, note: note,
                                              method: method, password: password)
                await load(initial: true)
                await app.loadChats()
                app.show("已转账 ¥\(moneyFmt(amount))")
            } catch {
                app.show((error as? APIError)?.errorDescription ?? "转账失败")
            }
        }
    }

    private func recall(_ message: Message) {
        let draft = message.kindName == "text" ? message.body : ""
        Task {
            if let error = await API.shared.recall(chatId: chat.id, messageId: message.id) {
                app.show(error)
                return
            }
            markMessageRecalledLocally(message.id)
            app.applyRecallSummaryLocally(chat.id, messageId: message.id)
            await load(initial: true)
            await app.loadChats()
            guard !draft.isEmpty else { return }
            reEditDraft = draft

            try? await Task.sleep(nanoseconds: 300 * 1_000_000_000)
            if reEditDraft == draft { reEditDraft = nil }
        }
    }

    private func markMessageRecalledLocally(_ messageId: String) {
        guard let index = messages.firstIndex(where: { $0.id == messageId }),
              messages[index].isRecalled != true else { return }
        messages[index].recalled = true
        rebuildIndex()
        schedulePersist()
    }

    private func jumpToMessage(_ id: String, seq targetSeq: Int? = nil) {
        guard !id.isEmpty else { return }
        if messages.contains(where: { $0.id == id }) {
            withAnimation(.easeInOut(duration: 0.25)) { scroller?.scrollTo(id, anchor: .center) }
            return
        }
        Task { @MainActor in
            if let targetSeq, targetSeq > 0,
               targetSeq < (messages.first?.seq ?? Int.max) {
                await loadHistory(to: id, targetSeq: targetSeq)
            } else {
                var tries = 0
                while hasOlder, tries < 12, !messages.contains(where: { $0.id == id }) {
                    await loadOlder()
                    tries += 1
                }
            }
            guard messages.contains(where: { $0.id == id }) else {
                app.show(Tr("那条消息在更早的记录里，往上翻就能看到"))
                return
            }
            try? await Task.sleep(nanoseconds: 80_000_000)
            withAnimation(.easeInOut(duration: 0.25)) { scroller?.scrollTo(id, anchor: .center) }
        }
    }

    private func loadHistory(to targetId: String, targetSeq: Int) async {
        guard !loadingOlder, let firstSeq = messages.first?.seq, firstSeq > targetSeq else { return }
        loadingOlder = true
        lastOlderLoad = Date()
        defer { loadingOlder = false }

        var cursor = firstSeq
        var pageHasMore = true
        var older: [Message] = []

        while pageHasMore, cursor > targetSeq, older.count < 20_000, !Task.isCancelled {
            do {
                let page = try await API.shared.messages(chatId: chat.id, limit: 100, before: cursor)
                if page.messages.isEmpty {
                    pageHasMore = false
                    break
                }
                older.append(contentsOf: page.messages)
                pageHasMore = page.hasMore
                if page.messages.contains(where: { $0.id == targetId }) { break }
                let next = page.messages.compactMap(\.seq).min() ?? 0
                if next <= 0 || next >= cursor { break }
                cursor = next
            } catch {
                lastOlderLoad = Date.distantPast
                ChatScrollDiag.shared.note("聊天记录加载失败，保留当前内容并等待重试")
                return
            }
        }

        guard !older.isEmpty else { return }
        let keep = messages.first?.id
        holdScroll = true
        var mergedById = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        for message in older { mergedById[message.id] = message }
        let merged = mergedById.values.sorted(by: messageSortsBefore)
        messages = visibleMessages(merged)
        hasOlder = pageHasMore
        rebuildIndex()

        if let keep, let proxy = scroller {
            DispatchQueue.main.async { proxy.scrollTo(keep, anchor: .top) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { holdScroll = false }
    }

    private func report(_ message: Message) {
        let target = message.senderId ?? ""
        guard !target.isEmpty else { return }
        Task {
            await API.shared.report(userId: target, chatId: chat.id,
                                    reason: "聊天内容举报",
                                    content: String(message.body.prefix(200)))
            app.show(Tr("已举报，管理员会处理"))
        }
    }

    private func schedulePersist() {
        persistTask?.cancel()

        persistTask = Task { @MainActor [messages, chatId = chat.id] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if Task.isCancelled { return }
            let list = messages
            Task.detached(priority: .utility) {
                LocalStore.saveChat(chatId, list)
            }
        }
    }

    private func load(initial: Bool) async {
        if initial, messages.isEmpty, let cached = app.prefetched[chat.id], !cached.isEmpty {
            let rows = visibleMessages(cached)
            messages = Array(rows.suffix(initialMessageWindow))
            hasOlder = rows.count > messages.count
            prefetchRecentFiles()
        } else if initial, messages.isEmpty {

            let chatId = chat.id
            let local = await Task.detached(priority: .userInitiated) {
                LocalStore.cachedChat(chatId)
            }.value
            if !local.isEmpty {
                let rows = visibleMessages(local)
                messages = Array(rows.suffix(initialMessageWindow))
                hasOlder = rows.count > messages.count
                prefetchRecentFiles()
            }
        }

        if initial {
            // 缓存用于立即放开聊天页；网络首屏继续在后台补齐最新消息。
            initialCacheReady = true
        }
        do {

            let cachedLastSeq = messages.compactMap { $0.seq }.max() ?? 0
            let result: (chat: Chat?, messages: [Message], hasMore: Bool)
            if initial {
                result = try await initialMessageBatch()
            } else if cachedLastSeq > 0 {
                var incoming: [Message] = []
                var latestChat: Chat? = nil
                var more = false
                var since = cachedLastSeq
                for _ in 0..<100 {
                    let page = try await API.shared.messagesSince(chatId: chat.id, since: since, limit: 200)
                    if let c = page.chat { latestChat = c }
                    incoming.append(contentsOf: page.messages)
                    more = page.hasMore
                    let next = page.messages.compactMap { $0.seq }.max() ?? since
                    if !more || page.messages.isEmpty || next <= since { break }
                    since = next
                }
                result = (latestChat, incoming, more)
            } else {
                result = try await initialMessageBatch()
            }

            var mergedById: [String: Message] = [:]
            for m in messages { mergedById[m.id] = m }
            for m in result.messages { mergedById[m.id] = m }
            let merged = mergedById.values.sorted(by: messageSortsBefore)
            let visible = visibleMessages(merged)

            let nextMessages = Array(visible.suffix(initialMessageWindow))
            let same = !initial && nextMessages.count == messages.count
                && zip(nextMessages, messages).allSatisfy { $0.id == $1.id && $0.body == $1.body }
            if initial || !same {

                if initial {
                    unreadHere = chat.unreadCount
                } else if !messages.isEmpty {

                    let oldLastSeq = messages.last?.seq ?? 0
                    let incoming = result.messages.filter {
                        ($0.seq ?? 0) > oldLastSeq && $0.senderId != myId && $0.kindName != "system"
                    }.count
                    if incoming > 0 { unreadHere += incoming }
                }
                messages = nextMessages
                if initial {
                    hasOlder = result.hasMore
                        || nextMessages.count > result.messages.count
                        || (nextMessages.first?.seq ?? 0) < (result.messages.first?.seq ?? 0)
                }

                if let last = result.messages.last, let sq = last.seq {
                    Realtime.shared.ackDelivery(chatId: chat.id, seq: sq)
                }
            }
        } catch {
            ChatScrollDiag.shared.note("聊天记录加载失败，静默重试")
            if initial, messages.isEmpty {
                initialRetryTask?.cancel()
                initialRetryTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    guard !Task.isCancelled, messages.isEmpty else { return }
                    await load(initial: true)
                }
            }
        }
        if initial, !messages.isEmpty {
            initialRetryTask?.cancel()
            initialRetryTask = nil
        }
        rebuildIndex()
        prefetchRecentFiles()
        loading = false
        autoOpenShopCard()

        if needBurnSweep {

            if Date().timeIntervalSince(lastBurnSweep) > 5 {
                lastBurnSweep = Date()
                let gone = await API.shared.burnSweep(chatId: chat.id)
                if !gone.isEmpty { burnAway(gone) }
            }
        }
    }

    private func prefetchRecentFiles() {
        var started = 0
        for message in messages.suffix(80).reversed()
        where message.kindName == "file" && started < 3 {
            guard let data = message.body.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let path = object["url"] as? String, !path.isEmpty else { continue }
            let name = (object["name"] as? String) ?? "文件"
            let bytes = (object["bytes"] as? Int) ?? 0
            guard bytes > 0, bytes <= 30 * 1024 * 1024 else { continue }
            started += 1
            Task {
                await RemoteFileCache.shared.prefetch(path: path,
                                                      preferredName: name,
                                                      bytes: bytes)
            }
        }
    }

    /// 首屏优先一次拿 300 条，避免连续三次独立网络往返。
    /// 旧服务器不认识 all=1 时只回 100 条，这里会自动续拉剩余两页。
    private func initialMessageBatch() async throws
        -> (chat: Chat?, messages: [Message], hasMore: Bool) {
        var incoming: [Message] = []
        var incomingIds = Set<String>()
        var latestChat: Chat?
        var more = false
        var before = 0
        for _ in 0..<3 {
            let page = try await API.shared.messages(
                chatId: chat.id,
                limit: initialMessageWindow,
                before: before > 0 ? before : nil,
                all: true
            )
            if let c = page.chat { latestChat = c }
            if page.messages.isEmpty {
                more = false
                break
            }
            for message in page.messages where incomingIds.insert(message.id).inserted {
                incoming.append(message)
            }
            more = page.hasMore
            if incoming.count >= initialMessageWindow { break }
            let next = page.messages.compactMap(\.seq).min() ?? 0
            if !more || next <= 0 || (before > 0 && next >= before) { break }
            before = next
        }
        return (latestChat, incoming, more)
    }

    private func burnCountText(_ deadline: Date, now: Date) -> String {
        let left = Int(deadline.timeIntervalSince(now).rounded(.up))
        if left > 0 { return "\(left)s" }
        return Tr("焚毁…")
    }

    private func burnAway(_ ids: [String]) {

        let fresh = ids.filter { !burnedIds.contains($0) }
        guard !fresh.isEmpty else { return }
        burnedIds.formUnion(fresh)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        BurnFX.shared.fire()
        app.show(Tr("🔥 消息已焚毁"))
        withAnimation(.easeOut(duration: 0.5)) {
            messages.removeAll { fresh.contains($0.id) }
        }
        rebuildIndex()
    }

    private func loadOlder() async {
        guard !loadingOlder, !loadingAllGroupHistory,
              let first = messages.first, let seq = first.seq else { return }
        loadingOlder = true
        lastOlderLoad = Date()
        defer { loadingOlder = false }
        do {
            var cursor = seq
            var older: [Message] = []
            var olderIds = Set<String>()
            var more = true
            let target = isGroup ? 300 : 200
            for _ in 0..<3 {
                let page = try await API.shared.messages(
                    chatId: chat.id,
                    limit: target,
                    before: cursor,
                    all: true
                )
                if page.messages.isEmpty {
                    more = false
                    break
                }
                for message in page.messages where olderIds.insert(message.id).inserted {
                    older.append(message)
                }
                more = page.hasMore
                let next = page.messages.compactMap(\.seq).min() ?? 0
                if !more || next <= 0 || next >= cursor { break }
                cursor = next
                if older.count >= target { break }
            }
            hasOlder = more

            guard !older.isEmpty else { hasOlder = false; return }
            let keep = first.id
            holdScroll = true
            let merged = visibleMessages(older + messages)
            messages = Array(merged.suffix(maxMessageWindow))
            if merged.count > messages.count { hasOlder = true }
            rebuildIndex()

            if let proxy = scroller {
                ChatScrollDiag.shared.note("上翻加载完 → 钉回原位置")
                DispatchQueue.main.async { proxy.scrollTo(keep, anchor: .top) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { holdScroll = false }
        } catch {

            lastOlderLoad = Date.distantPast
            ChatScrollDiag.shared.note("上翻历史加载失败，保留当前位置")
        }
    }

    private func autoOpenShopCard() {
        guard let last = messages.last, last.kindName == "link",
              last.senderId != myId, !autoOpened.contains(last.id),
              let link = ShopLink(json: last.body) else { return }
        autoOpened.insert(last.id)
        ShopOpener.open(link) { url in web = WebURL(url: url) }
    }

    private var peerAccount: String {
        if let peer = peerUserId, let u = app.contact(for: peer) {
            return u.username ?? ""
        }
        if let t = liveChat.title, let u = app.contacts.first(where: { ($0.nickname ?? "") == t || ($0.name ?? "") == t }) {
            return u.username ?? ""
        }
        return ""
    }

    private func loadAllGroupHistory() async {
        guard shouldLoadCompleteGroupHistory, hasOlder, !loadingAllGroupHistory else { return }
        loadingAllGroupHistory = true
        defer { loadingAllGroupHistory = false }

        var olderById: [String: Message] = [:]
        var reachedStart = false
        var before = messages.first?.seq ?? 0
        var pages = 0
        var consecutiveFailures = 0
        /* 每页 5000 条，并且客户端只保留最近 5000 条。这样后台同步
           只有一个完整批次，低内存机型不会继续累积到两万条。 */
        let pageSize = 5_000
        while hasOlder, pages < 64, !Task.isCancelled, before > 0,
              messages.count < maxMessageWindow,
              consecutiveFailures < 5 {
            do {
                let page = try await API.shared.messages(
                    chatId: chat.id,
                    limit: pageSize,
                    before: before,
                    all: true
                )
                consecutiveFailures = 0
                if page.messages.isEmpty {
                    reachedStart = true
                    break
                }
                for message in page.messages { olderById[message.id] = message }
                /* 每拿到一页就先并入当前会话，用户能马上看到新增的
                   更早消息，而不是等所有页拉完才一次性“跳出来”。 */
                let followBottom = atBottomNow
                let keepAnchor = messages.first?.id
                var mergedById = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
                for (id, message) in olderById { mergedById[id] = message }
                let merged = mergedById.values.sorted(by: messageSortsBefore)
                messages = Array(visibleMessages(merged).suffix(maxMessageWindow))
                hasOlder = true
                rebuildIndex()
                if followBottom, let scroller {
                    ChatScrollHandle.shared.allowAutomaticPinning()
                    DispatchQueue.main.async {
                        scroller.scrollTo("__bottom", anchor: .bottom)
                    }
                } else if let keepAnchor, let scroller {
                    holdScroll = true
                    DispatchQueue.main.async { scroller.scrollTo(keepAnchor, anchor: .top) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        holdScroll = false
                    }
                }
                let next = page.messages.compactMap(\.seq).min() ?? 0
                if !page.hasMore {
                    reachedStart = true
                    break
                }
                if next <= 0 || next >= before { break }
                before = next
                pages += 1
                await Task.yield()
            } catch {
                consecutiveFailures += 1
                if consecutiveFailures >= 5 { break }
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
        }

        guard !olderById.isEmpty, !Task.isCancelled else {
            if reachedStart { hasOlder = false }
            return
        }

        let followBottom = atBottomNow
        let keepAnchor = messages.first?.id
        var mergedById = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        for (id, message) in olderById { mergedById[id] = message }
        let merged = mergedById.values.sorted(by: messageSortsBefore)
        let visible = visibleMessages(merged)
        messages = Array(visible.suffix(maxMessageWindow))
        hasOlder = !reachedStart
        rebuildIndex()

        if !followBottom, let keepAnchor, let scroller {
            holdScroll = true
            DispatchQueue.main.async { scroller.scrollTo(keepAnchor, anchor: .top) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { holdScroll = false }
        }
    }
}

struct SystemLine: View {
    let message: Message
    var usesLightInk: Bool = false
    var plain: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            displayText
                .font(.footnote)
                .multilineTextAlignment(.center)
            if message.isCallRecord {
                callIcon(size: 13)
            }
        }

        .padding(.horizontal, plain ? 2 : 10)
        .padding(.vertical, plain ? 0 : 4)
        .background(
            Group {
                if !plain {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(.ultraThinMaterial)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(usesLightInk
                                  ? Color.black.opacity(0.40)
                                  : Color.white.opacity(0.76))
                    }
                }
            }
        )
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
    }

    @ViewBuilder
    private func callIcon(size: CGFloat) -> some View {
        CallIcon(key: callIconKey,
                 symbol: message.isVideoCall ? "video.fill" : "phone.fill",
                 builtin: callIconMarkup,
                 size: size,
                 color: ink)
    }

    private var callIconKey: String {
        if message.isBadCallRecord {
            return message.isVideoCall ? "ui.callRecordVideoMissed" : "ui.callRecordMissed"
        }
        return message.isVideoCall ? "ui.callRecordVideo" : "ui.callRecord"
    }

    private var callIconMarkup: String {
        if message.isBadCallRecord {
            return message.isVideoCall ? I.callRecordVideoMissed : I.callRecordMissed
        }
        return message.isVideoCall ? I.callRecordVideo : I.callRecord
    }

    private var displayText: Text {
        let raw = message.body
        guard let invite = raw.range(of: " 邀请 "),
              let joined = raw.range(of: " 加入了群聊", options: .backwards),
              invite.upperBound <= joined.lowerBound else {
            return Text(raw).foregroundColor(ink)
        }
        let inviter = String(raw[..<invite.lowerBound])
        let invitees = String(raw[invite.upperBound..<joined.lowerBound])
        guard !inviter.isEmpty, !invitees.isEmpty else {
            return Text(raw).foregroundColor(ink)
        }
        let pink = usesLightInk ? Color(hex: 0xFF9CC4) : Color(hex: 0xC33F78)
        return Text(inviter).foregroundColor(pink)
            + Text(Tr(" 邀请 ")).foregroundColor(ink)
            + Text(invitees).foregroundColor(pink)
            + Text(Tr(" 加入了群聊")).foregroundColor(ink)
    }

    private var ink: Color {

        let normal = usesLightInk
            ? Color.white.opacity(0.92)
            : Color(hex: 0x3F4247)
        guard message.isCallRecord else { return normal }
        return message.isBadCallRecord
            ? (usesLightInk ? Color(hex: 0xFFAAA0) : Color(hex: 0xC7352F))
            : normal
    }
}

struct CallRecordBubble: View {
    let message: Message
    let mine: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(message.callText)
                .font(pf(L.chatFontSize))
                .foregroundColor(ink)
            callIcon
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(BubbleFill(mine: mine))
        .frame(maxWidth: L.bubbleMaxW, alignment: mine ? .trailing : .leading)
        .accessibilityElement(children: .combine)
    }

    private var callIcon: some View {
        CallIcon(key: callIconKey,
                 symbol: message.isVideoCall ? "video.fill" : "phone.fill",
                 builtin: callIconMarkup,
                 size: 15,
                 color: ink)
    }

    private var callIconKey: String {
        if message.isBadCallRecord {
            return message.isVideoCall ? "ui.callRecordVideoMissed" : "ui.callRecordMissed"
        }
        return message.isVideoCall ? "ui.callRecordVideo" : "ui.callRecord"
    }

    private var callIconMarkup: String {
        if message.isBadCallRecord {
            return message.isVideoCall ? I.callRecordVideoMissed : I.callRecordMissed
        }
        return message.isVideoCall ? I.callRecordVideo : I.callRecord
    }

    private var ink: Color {
        message.isBadCallRecord ? ChatTheme.mentionMe : ChatTheme.ink
    }
}

private struct QuoteInspectItem: Identifiable {
    let id = UUID()
    let quote: QuoteRef
}

struct QuoteInspectSheet: View {
    let quote: QuoteRef
    let onOpenImage: (String) -> Void
    let onJump: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(OrbitTheme.jade)
                        .frame(width: 32, height: 32)
                        .background(OrbitTheme.jadeSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Tr("引用内容"))
                            .font(pfStyled(size: 17, weight: .semibold))
                            .foregroundStyle(C.label)
                        if !quote.sender.isEmpty {
                            Text(quote.sender)
                                .font(pfStyled(size: 12))
                                .foregroundStyle(C.subLabel)
                        }
                    }
                    Spacer(minLength: 8)
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(C.subLabel)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(OrbitTheme.field))
                    }
                    .buttonStyle(.plain)
                }

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        if !quote.thumbPath.isEmpty {
                            RemoteImage(path: quote.thumbPath, mode: .fit, maxSide: 900)
                                .frame(maxWidth: .infinity)
                                .frame(maxHeight: 190)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(C.hairline, lineWidth: 0.7)
                                }
                                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .onTapGesture {
                                    onOpenImage(quote.thumbPath)
                                }
                                .accessibilityAddTraits(.isButton)
                        }

                        Text(quote.summary.isEmpty ? Tr("[引用]") : quote.summary)
                            .font(pfStyled(size: 16))
                            .foregroundStyle(C.label)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.bottom, 8)
                }

                if !quote.refId.isEmpty {
                    Button {
                        onJump(quote.refId)
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "arrow.down.message.fill")
                                .font(.system(size: 13, weight: .semibold))
                            Text(Tr("定位到原消息"))
                                .font(pfStyled(size: 14, weight: .semibold))
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(OrbitTheme.jade)
                        .padding(.horizontal, 14)
                        .frame(height: 46)
                        .background(Capsule().fill(OrbitTheme.jadeSoft))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, max(18, L.safeBottom))
        }
    }
}

struct MessageRow: View {
    let message: Message
    let mine: Bool

    var myId: String = ""
    var senderName: String = ""
    var senderNameUsesLightInk: Bool = false
    var wallpaperTint: Color? = nil

    var senderAvatarPath: String = ""
    var senderQQLevel: Int = 0
    var currentNickname: String = ""
    var currentUsername: String = ""

    var showTail: Bool = true

    var onTapTransfer: ((TransferInfo) -> Void)? = nil

    var onOpenImage: ((String) -> Void)? = nil

    var onOpenAvatar: ((String) -> Void)? = nil

    var onOpenWeb: ((URL) -> Void)? = nil

    var onOpenLocation: ((LocationPoint) -> Void)? = nil

    var onOpenUserCard: ((String) -> Void)? = nil

    var onOpenAnnounce: ((String) -> Void)? = nil

    var onOpenMiniApp: ((MiniApp) -> Void)? = nil

    var onOpenVideo: ((URL) -> Void)? = nil

    var onPat: ((String) -> Void)? = nil

    var onTapRedPacket: ((RedPacketInfo) -> Void)? = nil

    var asrText: String = ""

    var asrBusy: Bool = false

    var onOpenFile: ((String) -> Void)? = nil

    var onOpenArticle: ((String) -> Void)? = nil

    var onLayoutChanged: (() -> Void)? = nil

    var onOpenQuote: ((QuoteRef) -> Void)? = nil
    var onShowToast: ((String) -> Void)? = nil

    @ObservedObject private var voicePlayer = VoicePlayer.shared

    @State private var playedVoice: Set<String> = []

    @State private var voiceScrub: Double = -1

    @State private var patPulse = false

    private var avatarPath: String {
        if let p = message.senderAvatar, !p.isEmpty { return p }
        return senderAvatarPath
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if mine { Spacer(minLength: 0) }

            if !mine {
                avatarView
                Spacer().frame(width: L.chatGapMsg)
            }

            bubbleColumn

            if mine {
                Spacer().frame(width: L.chatGapMsg)
                avatarView
            }

            if !mine { Spacer(minLength: 0) }
        }

        .environment(\.bubbleUsesLightInk, senderNameUsesLightInk)
        .environment(\.bubbleWallpaperTint, wallpaperTint)
    }

    private var avatarView: some View {

        let lv = (message.senderId == myId)
            ? GrowthStore.shared.shownLevel
            : senderQQLevel
        return Avatar(path: avatarPath, size: L.chatAvatar,
                      radius: L.chatAvatar / 2, level: lv)
            .scaleEffect(patPulse ? 1.10 : 1)
            .shadow(color: C.green.opacity(patPulse ? 0.30 : 0),
                    radius: patPulse ? 9 : 0)
            .animation(.spring(response: 0.24, dampingFraction: 0.62), value: patPulse)
            .contentShape(Rectangle())

            .onTapGesture(count: 2) {
                patPulse = true
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 190_000_000)
                    patPulse = false
                }
                onPat?(message.senderId ?? "")
            }
            .onTapGesture { onOpenAvatar?(message.senderId ?? "") }
    }

    private var bubbleColumn: some View {
        VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
            if !senderName.isEmpty {

                HStack(spacing: 4) {
                    Text(senderName)
                        .font(pf(13, .semibold))
                        .foregroundColor(senderNameUsesLightInk
                                         ? ChatTheme.groupSenderNameOnDark
                                         : ChatTheme.groupSenderNameOnLight)
                        .lineLimit(1)
                    if senderQQLevel > 0,
                       GrowthFlags.showInChats == true {
                        QQLevelBadge(level: senderQQLevel, size: 11, maxIcons: 2).fixedSize()
                    }
                }
            }
            content

            if asrBusy || !asrText.isEmpty {
                asrLine
            }
        }
        .frame(maxWidth: L.bubbleMaxW, alignment: mine ? .trailing : .leading)
    }

    private var asrLine: some View {
        VStack(alignment: .leading, spacing: 7) {

            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(C.green)
                Text(Tr("语音转文字"))
                    .font(pf(11.5, .medium))
                    .foregroundColor(C.green)
                Spacer(minLength: 8)
                if !asrBusy {
                    Text(Tr("点按复制"))
                        .font(pf(10.5, .medium))
                        .foregroundColor(C.time)
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10.5))
                        .foregroundColor(C.time)
                }
            }
            if asrBusy {
                HStack(spacing: 7) {
                    ProgressView().scaleEffect(0.65)
                    Text(Tr("正在识别…"))
                        .font(pf(13))
                        .foregroundColor(C.subLabel)
                }
            } else {
                Text(asrText)
                    .font(pf(13.5, .regular))
                    .foregroundColor(C.label)
                    .lineSpacing(2.5)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(.thinMaterial)
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        LinearGradient(colors: [C.green.opacity(0.16), C.green.opacity(0.04)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(C.green.opacity(0.22), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 5, x: 0, y: 2)
        .frame(maxWidth: 240, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !asrText.isEmpty else { return }
            UIPasteboard.general.string = asrText
            onShowToast?(Tr("已复制"))
        }
        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)),
                                removal: .opacity))
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: asrText)
    }

    @ViewBuilder
    private var content: some View {
        if message.isRecalled {
            Text(mine ? "你撤回了一条消息" : "对方撤回了一条消息")
                .font(pf(12.5, .regular))
                .foregroundColor(senderNameUsesLightInk
                                 ? Color.white.opacity(0.92)
                                 : Color(hex: 0x3F4247))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.ultraThinMaterial)
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(senderNameUsesLightInk
                                  ? Color.black.opacity(0.40)
                                  : Color.white.opacity(0.76))
                    }
                )
        } else {
            bubble
        }
    }

    private var bubbleFill: Color { mine ? ChatTheme.bubbleMine : ChatTheme.bubbleOther }

    private var bubblePrimaryInk: Color {
        mine ? Color.white.opacity(0.98) : ChatTheme.ink
    }

    private var bubbleSecondaryInk: Color {
        mine ? Color(hex: 0xD4F5EF).opacity(0.92) : ChatTheme.secondary
    }

    private var bubbleMentionInk: Color {
        mine ? Color(hex: 0xFFD5D0) : ChatTheme.mentionMe
    }

    private var bubbleLinkInk: Color {
        mine ? Color(hex: 0xEFFFFC) : ChatTheme.link
    }

    private var quoteSurface: Color {
        mine
            ? Color.white.opacity(0.14)
            : Color.dyn(0xF0F1F3, 0x34383E).opacity(0.88)
    }

    private var quoteBorder: Color {
        mine
            ? Color.white.opacity(0.18)
            : Color.black.opacity(0.075)
    }

    @ViewBuilder
    private var bubble: some View {
        switch message.kindName {
        case "image":

            ImageBubble(path: message.imagePath, pixel: message.imagePixelSize,
                        onSized: { onLayoutChanged?() }) { onOpenImage?(message.imagePath) }

        case "images":

            imagesGridBubble

        case "location":

            locationBubble
                .onTapGesture {
                    if let p = LocationPoint.parse(message.body) { onOpenLocation?(p) }
                }

        case "transfer":
            transferBubble
                .onTapGesture {
                    if let info = TransferInfo(json: message.body) { onTapTransfer?(info) }
                }

        case "redpacket":
            redPacketBubble
                .onTapGesture {
                    if let info = RedPacketInfo(json: message.body) { onTapRedPacket?(info) }
                }

        case "gift":
            giftBubble

        case "link":
            if let link = ShopLink(json: message.body) {
                ShopLinkCard(link: link) {
                    ShopOpener.open(link) { url in onOpenWeb?(url) }
                }
            } else {

                Text(linkFallbackText(message.body))
                    .font(pf(L.chatFontSize))
                    .foregroundColor(bubblePrimaryInk)
                    .padding(.horizontal, L.bubblePadHPill)
                    .padding(.vertical, L.bubblePadV)
                .background(BubbleFill(mine: mine, tail: showTail, seed: bubbleSeed(message.id)))
            }

        case "file":
            fileBubble

        case "oa":

            OAArticleCard(json: message.body) {
                if let d = message.body.data(using: .utf8),
                   let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                   let aid = o["articleId"] as? String, !aid.isEmpty {
                    onOpenArticle?(aid)
                }
            }

        case "card":

            if let info = UserCardInfo(json: message.body) {
                UserCardBubble(info: info)
                    .onTapGesture { onOpenUserCard?(info.userId) }
            } else {

                Text(UIConfig.num("cardDiag", 0) > 0
                     ? "[名片] 原文：" + String(message.body.prefix(80))
                     : Tr("[名片]"))
                    .font(pf(L.chatFontSize))
                    .foregroundColor(bubblePrimaryInk)
                    .padding(.horizontal, L.bubblePadHPill)
                    .padding(.vertical, L.bubblePadV)
                    .background(BubbleFill(mine: mine, tail: showTail, seed: bubbleSeed(message.id)))
            }

        case "music":

            if let m = MusicCardInfo(json: message.body) {
                MusicBubble(info: m) {
                    let t = m.asTrack
                    MusicPlayer.shared.play(t)
                    MusicSheet.shared.open(t)
                }
            } else {
                Text(Tr("[音乐]"))
                    .font(pf(L.chatFontSize))
                    .foregroundColor(bubblePrimaryInk)
                    .padding(.horizontal, L.bubblePadHPill)
                    .padding(.vertical, L.bubblePadV)
                    .background(BubbleFill(mine: mine, tail: showTail, seed: bubbleSeed(message.id)))
            }

        case "mall":

            if let m = MallCardInfo(json: message.body) {
                MallCardBubble(info: m) {
                    MallSheet.shared.open(m.asProduct)
                }
            } else {
                Text(Tr("[商品]"))
                    .font(pf(L.chatFontSize))
                    .foregroundColor(bubblePrimaryInk)
                    .padding(.horizontal, L.bubblePadHPill)
                    .padding(.vertical, L.bubblePadV)
                    .background(BubbleFill(mine: mine, tail: showTail, seed: bubbleSeed(message.id)))
            }

        case "announce":

            AnnounceBubble(text: message.body) {
                onOpenAnnounce?(message.body)
            }

        case "note":

            NoteCardBubble(text: message.body, mine: mine,
                           showTail: showTail, seed: bubbleSeed(message.id))

        case "miniapp":

            if let m = MiniAppShare(json: message.body) {
                MiniAppCardBubble(info: m) { onOpenMiniApp?(m.asApp) }
            } else {
                Text(Tr("[小游戏]"))
                    .font(pf(L.chatFontSize))
                    .foregroundColor(bubblePrimaryInk)
                    .padding(.horizontal, L.bubblePadHPill)
                    .padding(.vertical, L.bubblePadV)
                    .background(BubbleFill(mine: mine, tail: showTail, seed: bubbleSeed(message.id)))
            }

        case "sysnotice":

            if let n = SysNoticeInfo(json: message.body) {
                SysNoticeBubble(info: n) { onOpenAnnounce?(n.fullText) }
            } else {
                Text(Tr("[通知]"))
                    .font(pf(L.chatFontSize))
                    .foregroundColor(bubblePrimaryInk)
                    .padding(.horizontal, L.bubblePadHPill)
                    .padding(.vertical, L.bubblePadV)
                    .background(BubbleFill(mine: mine, tail: showTail, seed: bubbleSeed(message.id)))
            }

        case "audio":
            audioBubble

        case "video":
            VideoBubble(message: message, mine: mine) { url, _ in onOpenVideo?(url) }

        case "livephoto":
            LivePhotoBubble(message: message) { url in onOpenVideo?(url) }

        default:

            if message.body.hasPrefix("{") {
                Text(unknownCardText(message.body))
                    .font(pf(L.chatFontSize))
                    .foregroundColor(bubblePrimaryInk)
                    .padding(.horizontal, L.bubblePadHPill)
                    .padding(.vertical, L.bubblePadV)
                    .background(BubbleFill(mine: mine, tail: showTail, seed: bubbleSeed(message.id)))
                } else if let q = message.quote {

            quotedTextBubble(q, raw: message.body)
                } else {

            Text(richBody(message.body))
                .font(pf(L.chatFontSize))

                .foregroundColor(bubblePrimaryInk)
                .lineSpacing(textLineSpacing(message.body))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, L.bubblePadHPill)
                .padding(.vertical, L.bubblePadV)
                .background(
                    BubbleFill(mine: mine, tail: showTail, glass: false)
                )
                }
        }
    }

    private func quotedTextBubble(_ q: QuoteRef, raw: String) -> some View {
        VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
            Text(richBody(raw))
                .font(pf(L.chatFontSize))
                .foregroundColor(bubblePrimaryInk)
                .lineSpacing(textLineSpacing(raw))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, L.bubblePadHPill)
                .padding(.vertical, L.bubblePadV)
                .background(BubbleFill(mine: mine, tail: showTail, glass: false))

            Button {
                if (q.kind == "image" || q.kind == "images"), !q.thumbPath.isEmpty {
                    onOpenImage?(q.thumbPath)
                } else {
                    onOpenQuote?(q)
                }
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        if !q.sender.isEmpty {
                            Text(q.sender)
                                .font(pf(12.5, .medium))
                                .foregroundColor(bubbleSecondaryInk)
                                .lineLimit(1)
                        }
                        Text(q.summary.isEmpty ? Tr("[引用]") : q.summary)
                            .font(pf(13, .regular))
                            .foregroundColor(bubbleSecondaryInk)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())

                    if !q.thumbPath.isEmpty {
                        quoteThumbnail(q)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(quoteSurface)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(quoteBorder, lineWidth: 0.5)
            }
            .frame(maxWidth: 250, alignment: mine ? .trailing : .leading)
        }
    }

    private func quoteThumbnail(_ q: QuoteRef) -> some View {
        ZStack {
            RemoteImage(path: q.thumbPath, mode: .fill, maxSide: 420)
            if q.kind == "video" || q.kind == "livephoto" {
                Circle()
                    .fill(Color.black.opacity(0.46))
                    .frame(width: 25, height: 25)
                Image(systemName: "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .offset(x: 1)
            }
        }
        .frame(width: 58, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
            .stroke(Color.black.opacity(0.10), lineWidth: 0.5))
        .accessibilityHidden(true)
    }

    private func dict(_ json: String) -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return obj
    }

    private func linkText(_ s: String) -> AttributedString {

        var linked = RichText.linkified(s)
        let linkRanges = linked.runs.compactMap { $0.link == nil ? nil : $0.range }
        for range in linkRanges {
            linked[range].foregroundColor = bubbleLinkInk
            linked[range].underlineStyle = .single
        }
        return linked
    }

    private func linkFallbackText(_ raw: String) -> String {
        if let r = raw.range(of: "\"title\":\""),
           let e = raw.range(of: "\"", range: r.upperBound..<raw.endIndex) {
            let t = String(raw[r.upperBound..<e.lowerBound])
            if !t.isEmpty { return t }
        }
        return Tr("链接")
    }

    private func unknownCardText(_ raw: String) -> String {
        guard let d = raw.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
            return Tr("[卡片消息]")
        }
        for key in ["name", "title", "text", "content", "preview", "desc", "label"] {
            if let v = o[key] as? String, !v.isEmpty { return v }
        }

        if let uid = o["userId"] as? String, !uid.isEmpty { return Tr("[名片]") }
        return Tr("[卡片消息]")
    }

    private func textLineSpacing(_ raw: String) -> CGFloat {
        let lineCount = raw.reduce(1) { count, character in
            count + (character == "\n" ? 1 : 0)
        }
        let isLong = raw.count >= 120 || lineCount >= 5
        let preferred: CGFloat = isLong ? 3.2 : 2.4
        let configured = max(2.2, min(3.2, L.msgLineSpacing))
        return min(preferred, configured)
    }

    private func richBody(_ raw: String) -> AttributedString {

        let cacheKey = message.id + "|" + raw
        if let hit = RichBodyCache.get(cacheKey) { return hit }

        let s = ClassicEmojiSet.expand(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        let atMe = message.mentionsUser(myId)
        let mineNames = atMe ? myMentionNames : []

        let preferredSize = L.chatFontSize * fontScale * CareMode.scale
        let baseSize = max(12, UIFontMetrics(forTextStyle: .body)
            .scaledValue(for: preferredSize)
            .rounded())
        let mono = Font.system(size: baseSize, weight: .regular, design: .monospaced)
        let base = pfStyled(baseSize)
        var out = AttributedString()
        let lines = s.split(separator: "\n", omittingEmptySubsequences: false)
        for (idx, sub) in lines.enumerated() {
            let line = String(sub)
            if RichText.looksLikeCode(line) {
                var seg = AttributedString(line)
                seg.font = mono
                out += seg
            } else if line.contains("@") || line.contains("http") {
                var seg = decorateLine(line, atMe: atMe, mineNames: mineNames)
                seg.font = base
                out += seg
            } else {
                var seg = AttributedString(line)
                seg.font = base
                out += seg
            }
            if idx < lines.count - 1 { out += AttributedString("\n") }
        }
        RichBodyCache.put(cacheKey, out)
        return out
    }

    private func decorateLine(_ s: String, atMe: Bool, mineNames: [String]) -> AttributedString {
        var out = AttributedString()
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "@" {
                var j = s.index(after: i)
                while j < s.endIndex, !isMentionStop(s[j]) { j = s.index(after: j) }
                let token = String(s[i..<j])
                var seg = AttributedString(token)
                let name = String(token.dropFirst())
                if atMe && mineNames.contains(name) {
                    seg.foregroundColor = bubbleMentionInk
                } else {
                    seg.foregroundColor = bubbleLinkInk
                }
                out += seg
                i = j
                continue
            }

            var j = i
            while j < s.endIndex, s[j] != "@" { j = s.index(after: j) }
            out += linkText(String(s[i..<j]))
            i = j
        }
        return out
    }

    private func isMentionStop(_ c: Character) -> Bool {
        if c.isWhitespace || c.isNewline { return true }
        return "，。！？；：、（）()[]【】{}<>《》\"'!?,;:".contains(c)
    }

    private var myMentionNames: [String] {
        var names: [String] = []
        if !currentNickname.isEmpty { names.append(currentNickname) }
        if !currentUsername.isEmpty { names.append(currentUsername) }
        return names
    }

    private var locationBubble: some View {
        let o = dict(message.body)
        let lat = (o["lat"] as? Double) ?? 0
        let lng = (o["lng"] as? Double) ?? 0
        let name = (o["name"] as? String) ?? "位置"
        let addr = (o["addr"] as? String) ?? ""
        let pt = LocationPoint(lat: lat, lng: lng, name: name, addr: addr)
        return VStack(spacing: 0) {

            MapSnapshotView(point: pt, width: 216, height: 136)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(pf(15)).foregroundColor(bubblePrimaryInk).lineLimit(1)
                Text(addr.isEmpty ? "点击查看地图" : addr)
                    .font(pf(12)).foregroundColor(bubbleSecondaryInk).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .frame(width: 216)

        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

        .background(BubbleFill(mine: false, tail: showTail))
    }

    private var transferBubble: some View {
        let o = dict(message.body)
        let amount = (o["amount"] as? Double) ?? 0
        let note = (o["note"] as? String) ?? ""
        let status = (o["status"] as? String) ?? "pending"
        let state = status == "received" ? "已收款" : (status == "refunded" ? "已退回" : "待对方确认收款")

        let card: Color
        if status == "refunded" {
            card = Color(hex: 0xC2C2C2)
        } else if status == "received" {
            card = Color(hex: 0xF0C69A)
        } else {
            card = Color(hex: 0xFA9D3C)
        }

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 9) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.22)).frame(width: 34, height: 34)
                    Image(systemName: "yensign")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("¥\(moneyFmt(amount))")
                        .font(pfMoney(19, .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(note.isEmpty ? Tr("转账") : note)
                        .font(pf(11))
                        .foregroundColor(Color.white.opacity(0.85))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .padding(.top, 11)
            .padding(.bottom, 10)

            Rectangle()
                .fill(Color.white.opacity(0.22))
                .frame(height: 0.5)

            HStack(spacing: 5) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.85))
                Text(Tr("转账"))
                    .font(pf(11))
                    .foregroundColor(Color.white.opacity(0.85))
                Spacer(minLength: 4)
                Text(state)
                    .font(pf(11.5))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 11)
            .frame(height: 28)
        }

        .frame(width: UIConfig.num("transferCardW", 240), alignment: .leading)
        .background(card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var redPacketBubble: some View {
        if let info = RedPacketInfo(json: message.body) {
            RedPacketCard(info: info, mine: mine, myId: myId)
        } else {

            Text(Tr("[红包] 这条记录是旧版本的，已经失效"))
                .font(pf(14))
                .foregroundColor(ChatTheme.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(ChatTheme.separator))
        }
    }

    private var audioBubble: some View {
        let o = dict(message.body)
        let secs = max(1, (o["seconds"] as? Int) ?? 1)
        let playing = voicePlayer.playingID == message.id
        let scrubbing = voiceScrub >= 0

        let dot: Double = scrubbing ? voiceScrub : (playing ? voicePlayer.progress : 0)
        let total = playing && voicePlayer.total > 0 ? voicePlayer.total : Double(secs)
        let elapsed: Double = {
            if scrubbing { return max(0, total * dot) }
            if playing { return max(0, min(total, voicePlayer.elapsed)) }
            return 0
        }()
        let levels = voiceLevels(o, count: 36)
        let width = min(286, 196 + CGFloat(secs) * 1.45)
        let live = playing || scrubbing

        return HStack(spacing: 10) {
            if mine { Spacer(minLength: 0) }

            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: 0x4EDC7C), C.green],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Circle()
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.7)
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 25, height: 25)
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(.white)
                        .offset(x: playing ? 0 : 1)
                }
                .frame(width: 38, height: 38)
                .shadow(color: C.green.opacity(0.20), radius: 6, y: 2)

                VStack(alignment: .leading, spacing: 4) {
                    voiceProgressTrack(levels: levels, progress: dot, live: live)
                        .frame(height: 25)

                    HStack(spacing: 5) {
                        Text(live ? voiceClock(elapsed) : voiceClock(total))
                            .foregroundStyle(live ? C.green : bubbleSecondaryInk)
                        if live {
                            Text("/")
                                .foregroundStyle(bubbleSecondaryInk.opacity(0.38))
                            Text(voiceClock(total))
                                .foregroundStyle(bubbleSecondaryInk)
                        }
                        Spacer(minLength: 0)
                        if live { speedChip }
                    }
                    .font(pfStyled(size: 10, weight: .medium, design: .monospaced))
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 12)
            .frame(width: width, height: 64, alignment: .leading)
            .background(BubbleFill(mine: mine,
                                   tail: showTail,
                                   seed: bubbleSeed(message.id)))
            .overlay(alignment: .topTrailing) {
                if !mine, !playedVoice.contains(message.id),
                   !VoicePlayed.isPlayed(message.id) {
                    Circle().fill(Color(.systemRed))
                        .frame(width: 8, height: 8)
                        .offset(x: -5, y: 5)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                playedVoice.insert(message.id)
                VoicePlayed.markPlayed(message.id)
                guard let url = voiceURL() else {
                    onShowToast?(Tr("这条语音找不到了"))
                    return
                }
                voicePlayer.toggle(id: message.id, url: url)
            }
            .animation(.easeOut(duration: 0.16), value: playing)

            if !mine { Spacer(minLength: 0) }
        }
    }

    private func voiceClock(_ seconds: Double) -> String {
        let value = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", value / 60, value % 60)
    }

    private func voiceLevels(_ info: [String: Any], count: Int) -> [CGFloat] {
        if let raw = info["wave"] as? [Double], raw.count >= 4 {
            let values = raw.prefix(count).map { CGFloat(max(0.08, min(1, $0))) }
            return values.isEmpty ? waveHeights(message.id, count) : values
        }
        if let raw = info["wave"] as? [NSNumber], raw.count >= 4 {
            return raw.prefix(count).map { CGFloat(max(0.08, min(1, $0.doubleValue))) }
        }
        return waveHeights(message.id, count)
    }

    private func voiceProgressTrack(levels: [CGFloat], progress: Double, live: Bool) -> some View {
        GeometryReader { geo in
            let width = max(24, geo.size.width)
            let height = max(12, geo.size.height)
            let count = max(4, levels.count)
            let gap: CGFloat = count > 28 ? 1.1 : 1.7
            let barWidth = max(1.2, (width - gap * CGFloat(count - 1)) / CGFloat(count))
            let clamped = min(1, max(0, progress))

            ZStack(alignment: .leading) {
                Canvas { context, size in
                    for i in 0..<count {
                        let at = (Double(i) + 0.5) / Double(count)
                        let level = levels[min(i, levels.count - 1)]
                        let barHeight = max(4, level * (size.height - 3))
                        let rect = CGRect(
                            x: CGFloat(i) * (barWidth + gap),
                            y: (size.height - barHeight) / 2,
                            width: barWidth,
                            height: barHeight
                        )
                        let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                        let color = at <= clamped && live
                            ? C.green
                            : bubblePrimaryInk.opacity(live ? 0.16 : 0.24)
                        context.fill(path, with: .color(color))
                    }
                }

                if live {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.96))
                        .frame(width: 2, height: max(12, height - 2))
                        .shadow(color: C.green.opacity(0.48),
                                radius: 3, y: 0)
                        .position(x: min(width - 2, max(2, width * clamped)),
                                  y: height / 2)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = min(1, max(0, Double(value.location.x / width)))
                        voiceScrub = fraction
                        playedVoice.insert(message.id)
                        VoicePlayed.markPlayed(message.id)
                        if voicePlayer.playingID != message.id, let url = voiceURL() {
                            voicePlayer.toggle(id: message.id, url: url)
                        }
                        voicePlayer.seek(to: fraction)
                    }
                    .onEnded { _ in voiceScrub = -1 }
            )
        }
    }

    private var speedChip: some View {
        Button {
            voicePlayer.toggleRate()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Text(voicePlayer.rate > 1.5 ? "2x" : "1x")
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundColor(C.green)
                .frame(width: 28, height: 19)
                .background(Capsule().fill(C.green.opacity(0.11)))
                .overlay(Capsule().stroke(C.green.opacity(0.16), lineWidth: 0.6))
        }
        .buttonStyle(.plain)
    }

    private func voiceURL() -> URL? {
        let o = dict(message.body)
        let path = (o["url"] as? String) ?? ""
        return API.shared.assetURL(path)
    }

    private func waveHeights(_ id: String, _ n: Int) -> [CGFloat] {

        var seed: UInt64 = 0x9E3779B97F4A7C15
        for u in id.unicodeScalars {
            seed = (seed ^ UInt64(u.value)) &* 1099511628211
        }
        seed |= 1
        var out: [CGFloat] = []
        out.reserveCapacity(n)
        for _ in 0..<n {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let v = Double((seed >> 33) & 0xFFFF) / 65535.0
            out.append(CGFloat(0.30 + v * 0.70))
        }
        return out
    }

    private var imagesGridBubble: some View {
        let o = dict(message.body)
        let paths = (o["paths"] as? [String]) ?? []
        return albumGridBubble(paths)
    }

    @ViewBuilder
    private func albumGridBubble(_ paths: [String]) -> some View {
        let total = paths.count
        let gap: CGFloat = 2.5
        let width: CGFloat = 229

        if total == 0 {
            EmptyView()
        } else if total == 1 {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onOpenImage?(paths[0])
            } label: {
                RemoteImage(path: paths[0], maxSide: 1200)
                    .frame(width: width, height: 188)
                    .clipped()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .shadow(color: Color.black.opacity(0.14), radius: 7, x: 0, y: 2)
        } else if total == 2 {
            let tileWidth = (width - gap) / 2
            HStack(spacing: gap) {
                ForEach(Array(paths.enumerated()), id: \.offset) { index, path in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onOpenImage?(path)
                    } label: {
                        RemoteImage(path: path, maxSide: 900)
                            .frame(width: tileWidth, height: 172)
                            .clipped()
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Tr("预览图片") + " \(index + 1)")
                }
            }
            .frame(width: width)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
            .padding(4)
            .background {
                GlassBackground(
                    shape: RoundedRectangle(cornerRadius: 18, style: .continuous),
                    shadow: true
                )
            }
        } else {
            let strip = Array(paths.dropFirst().prefix(3))
            let tileWidth = (width - CGFloat(strip.count - 1) * gap) / CGFloat(max(1, strip.count))

            VStack(spacing: gap) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onOpenImage?(paths[0])
                } label: {
                    RemoteImage(path: paths[0], maxSide: 1200)
                        .frame(width: width, height: 156)
                        .clipped()
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Tr("预览图片") + " 1")

                HStack(spacing: gap) {
                    ForEach(Array(strip.enumerated()), id: \.offset) { offset, path in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onOpenImage?(path)
                        } label: {
                            ZStack(alignment: .bottomTrailing) {
                                RemoteImage(path: path, maxSide: 900)
                                    .frame(width: tileWidth, height: 76)
                                    .clipped()

                                if offset == strip.count - 1 && total > strip.count + 1 {
                                    Text("+\(total - strip.count - 1)")
                                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .frame(height: 25)
                                        .background {
                                            GlassBackground(
                                                shape: Capsule(style: .continuous),
                                                opacity: 0.84,
                                                tint: Color.black.opacity(0.30)
                                            )
                                        }
                                        .padding(6)
                                }
                            }
                            .frame(width: tileWidth, height: 76)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Tr("预览图片") + " \(offset + 2)")
                    }
                }
            }
            .frame(width: width)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
            .padding(4)
            .background {
                GlassBackground(
                    shape: RoundedRectangle(cornerRadius: 18, style: .continuous),
                    shadow: true
                )
            }
        }
    }

    private var giftBubble: some View {
        let o = dict(message.body)
        let icon = (o["icon"] as? String) ?? "🎁"
        let name = (o["name"] as? String) ?? "礼物"
        let price = (o["price"] as? Double) ?? 0
        return HStack(spacing: 10) {
            Text(icon).font(pf(30))
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(pf(15, .medium)).foregroundColor(bubblePrimaryInk)
                    Text("¥\(String(format: "%.0f", price))").font(pfMoney(12)).foregroundColor(C.red)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            BubbleFill(mine: mine, tail: showTail)
        )
    }

    private var fileBubble: some View {
        let o = dict(message.body)
        let name = (o["name"] as? String) ?? "文件"
        let bytes = (o["bytes"] as? Int) ?? 0
        let path = (o["url"] as? String) ?? ""
        let look = FileKind.look(name)
        let ext = (name as NSString).pathExtension
        let typeName = UTType(filenameExtension: ext)?.localizedDescription ?? look.badge
        return HStack(spacing: 11) {
            NativeFileThumbnail(name: name, path: path)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(pf(15, .semibold))
                    .foregroundColor(ChatTheme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(typeName + " · " + byteText(bytes))
                    .font(pf(12))
                    .foregroundColor(ChatTheme.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(ChatTheme.secondary.opacity(0.7))
        }
        .padding(.horizontal, 13)
        .frame(width: 224, height: 72, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(Color.primary.opacity(0.07), lineWidth: 0.6)
                }
                .shadow(color: Color.black.opacity(mine ? 0.05 : 0.10),
                        radius: 6, x: 0, y: 3)
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpenFile?(message.body) }
    }

    private func byteText(_ n: Int) -> String {
        if n > 1024 * 1024 { return String(format: "%.1f MB", Double(n) / 1024 / 1024) }
        if n > 1024 { return "\(n / 1024) KB" }
        return "\(n) B"
    }

    private func card(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 10) {
            SVGIcon(markup: icon, size: 20, color: mine ? bubblePrimaryInk : C.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(pf(15, .medium)).foregroundColor(bubblePrimaryInk)
                if !detail.isEmpty {
                    Text(detail).font(pf(12)).foregroundColor(bubbleSecondaryInk).lineLimit(2)
                }
            }
        }
        .padding(.horizontal, L.bubblePadHPill)
        .padding(.vertical, L.bubblePadV)
        .background(
            BubbleFill(mine: mine, tail: showTail)
        )
    }
}

enum ImageSizeCache {
    private static var mem: [String: CGSize] = [:]
    private static let defaultsKey = "chris.imageSizes"
    private static var disk: [String: [CGFloat]] =
        (UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: [CGFloat]]) ?? [:]

    static func get(_ path: String) -> CGSize? {
        guard !path.isEmpty else { return nil }
        if let s = mem[path] { return s }
        if let a = disk[path], a.count == 2 {
            let s = CGSize(width: a[0], height: a[1])
            mem[path] = s
            return s
        }
        return nil
    }

    static func put(_ path: String, _ size: CGSize) {
        guard !path.isEmpty, size.width > 1, size.height > 1 else { return }

        if let old = mem[path], abs(old.width - size.width) < 0.5, abs(old.height - size.height) < 0.5 {
            return
        }
        mem[path] = size
        disk[path] = [size.width, size.height]
        if disk.count > 1200 { disk.removeAll(); disk[path] = [size.width, size.height] }
        UserDefaults.standard.set(disk, forKey: defaultsKey)
    }
}

struct ImageBubble: View {
    let path: String

    var onSized: (() -> Void)? = nil

    var pixel: CGSize? = nil
    let onTap: () -> Void

    @State private var box: CGSize? = nil

    @State private var smallSticker = false

    init(path: String, pixel: CGSize? = nil, onSized: (() -> Void)? = nil, onTap: @escaping () -> Void) {
        self.path = path
        self.pixel = pixel
        self.onSized = onSized
        self.onTap = onTap
        var seed: CGSize? = nil
        var sticker = false
        if let p = pixel, p.width > 1, p.height > 1 {
            if ImageBubble.looksLikeSticker(p) { sticker = true; seed = CGSize(width: 120, height: 120) }
            else { seed = ImageBubble.thumb(p) }
        }
        _box = State(initialValue: seed)
        _smallSticker = State(initialValue: sticker)
    }

    private var isSticker: Bool {
        path.hasPrefix("/emoji/") || path.contains("/emj")
    }

    private var stickerLook: Bool { isSticker || smallSticker }
    private let stickerSide: CGFloat = 120

    var body: some View {
        let size = stickerLook
            ? CGSize(width: stickerSide, height: stickerSide)
            : (box ?? CGSize(width: 150, height: 150))

        Button(action: onTap) {
            Group {
                if path.lowercased().hasSuffix(".gif") {
                    StickerThumb(url: path)
                } else {
                    RemoteImage(path: path, icon: "photo",
                                mode: stickerLook ? .fit : .fill,
                                onLoaded: { img in
                        guard !isSticker else { return }
                        if ImageBubble.looksLikeSticker(img.size) {
                            smallSticker = true
                        } else if box == nil {
                            box = ImageBubble.thumb(img.size)
                            ImageSizeCache.put(path, box ?? ImageBubble.thumb(img.size))
                        }
                        onSized?()
                    })
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: stickerLook ? 8 : 5,
                                        style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: stickerLook ? 8 : 5,
                                 style: .continuous)
                    .stroke(Color.black.opacity(stickerLook ? 0 : 0.10),
                            lineWidth: 0.6)
            )
            .shadow(color: stickerLook ? .clear : Color.black.opacity(0.16),
                    radius: 7, x: 0, y: 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Tr(stickerLook ? "查看表情" : "查看图片"))

        .onAppear {
            if box == nil, let cached = ImageSizeCache.get(path) { box = cached }

            if let p = pixel, p.width > 1, p.height > 1, !stickerLook {
                ImageSizeCache.put(path, ImageBubble.looksLikeSticker(p) ? CGSize(width: 120, height: 120) : ImageBubble.thumb(p))
            }
        }
    }

    static func looksLikeSticker(_ size: CGSize) -> Bool {
        let w = max(1, size.width)
        let h = max(1, size.height)
        let m = max(w, h)
        return m <= 400 && abs(w - h) / m < 0.25
    }

    static func thumb(_ size: CGSize) -> CGSize {
        let w = max(1, size.width)
        let h = max(1, size.height)
        let scale = min(1, 200 / max(w, h))
        var tw = (w * scale).rounded()
        var th = (h * scale).rounded()
        if max(tw, th) < 60 {
            let k = 60 / max(tw, th)
            tw = (tw * k).rounded()
            th = (th * k).rounded()
        }
        return CGSize(width: min(200, tw), height: min(200, th))
    }
}

enum Tiles {
    static func url(lat: Double, lng: Double, z: Int = 15) -> String {
        let n = pow(2.0, Double(z))
        let x = Int(floor((lng + 180) / 360 * n))
        let rad = lat * .pi / 180
        let y = Int(floor((1 - log(tan(rad) + 1 / cos(rad)) / .pi) / 2 * n))
        return "https://tile.openstreetmap.org/\(z)/\(x)/\(y).png"
    }
}

enum FileKind {

    static func look(_ name: String) -> (symbol: String, color: Color, badge: String) {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf":
            return ("doc.richtext", Color(hex: 0xE5433B), "PDF")
        case "doc", "docx", "docm", "rtf", "rtfd", "odt", "pages", "wps":
            return ("doc.text", Color(hex: 0x2A6BC4), "WORD")
        case "xls", "xlsx", "xlsm", "xlsb", "csv", "tsv", "ods", "numbers", "et":
            return ("tablecells", Color(hex: 0x1E9E5A), "EXCEL")
        case "ppt", "pptx", "pptm", "pps", "ppsx", "odp", "key", "dps":
            return ("chart.bar.doc.horizontal", Color(hex: 0xE07B1F), "PPT")
        case "zip", "rar", "7z", "tar", "gz":
            return ("doc.zipper", Color(hex: 0xC79A2A), "压缩包")
        case "txt", "md", "log", "json", "xml":
            return ("doc.plaintext", Color(hex: 0x8A8A8E), "文本")
        case "mp3", "m4a", "wav", "aac", "flac":
            return ("music.note", Color(hex: 0x8A6FE8), "音频")
        case "mp4", "mov", "m4v", "avi", "mkv", "webm":
            return ("film", Color(hex: 0x5B6B7C), "视频")
        case "jpg", "jpeg", "png", "gif", "heic", "webp":
            return ("photo", Color(hex: 0x1180E0), "图片")
        default:
            let label = ext.isEmpty ? "文件" : ext.uppercased()
            return ("doc", Color(hex: 0x8A93FF), label)
        }
    }
}

private struct NativeFileThumbnail: View {
    let name: String
    let path: String

    @State private var thumbnail: UIImage?

    private static let cache = NSCache<NSString, UIImage>()

    private var look: (symbol: String, color: Color, badge: String) {
        FileKind.look(name)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))

            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .padding(3)
            } else {
                VStack(spacing: 2) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundColor(look.color)
                    Text(look.badge)
                        .font(pfExact(7.5, .bold))
                        .foregroundColor(look.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
            }
        }
        .frame(width: 48, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
        .task(id: path) { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        guard let local = LocalStore.localURL(path),
              FileManager.default.fileExists(atPath: local.path) else { return }

        let key = (path + "#file-thumbnail") as NSString
        if let hit = Self.cache.object(forKey: key) {
            thumbnail = hit
            return
        }
        let request = QLThumbnailGenerator.Request(
            fileAt: local,
            size: CGSize(width: 144, height: 168),
            scale: UIScreen.main.scale,
            representationTypes: .thumbnail
        )
        guard let representation = try? await QLThumbnailGenerator.shared
            .generateBestRepresentation(for: request) else { return }
        let image = representation.uiImage
        Self.cache.setObject(image, forKey: key)
        thumbnail = image
    }
}

extension MessageRow: Equatable {
    static func == (lhs: MessageRow, rhs: MessageRow) -> Bool {
        lhs.message == rhs.message
            && lhs.mine == rhs.mine
            && lhs.myId == rhs.myId
            && lhs.senderName == rhs.senderName
            && lhs.senderNameUsesLightInk == rhs.senderNameUsesLightInk
            && lhs.wallpaperTint == rhs.wallpaperTint
            && lhs.senderAvatarPath == rhs.senderAvatarPath
            && lhs.senderQQLevel == rhs.senderQQLevel
            && lhs.currentNickname == rhs.currentNickname
            && lhs.currentUsername == rhs.currentUsername
            && lhs.showTail == rhs.showTail
            && lhs.asrText == rhs.asrText
            && lhs.asrBusy == rhs.asrBusy
    }

}

struct FilePreviewData: Identifiable {
    let id = UUID()
    var name: String
    var local: URL
    var favoriteTitle: String = ""
    var favoriteFrom: String = ""
}

struct FilePreviewSheet: View {
    let name: String
    let local: URL
    var favoriteTitle: String = ""
    var favoriteFrom: String = ""

    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showShare = false
    @State private var favoriting = false
    @State private var showDrop = false
    @State private var showOfficeInfo = false

    private var officeKind: OfficeDocumentKind? {
        OfficeDocumentKind(fileName: name)
    }

    private var fileExtension: String {
        let ext = local.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        return ext.isEmpty ? Tr("文件") : ext.uppercased()
    }

    private var fileSizeText: String {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: local.path)[.size]) as? NSNumber
        else { return Tr("本地文件") }
        return ByteCountFormatter.string(fromByteCount: size.int64Value, countStyle: .file)
    }

    private var fileDateText: String {
        guard let date = (try? FileManager.default.attributesOfItem(atPath: local.path)[.modificationDate]) as? Date
        else { return "" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private var fileAccent: Color {
        switch local.pathExtension.lowercased() {
        case "pdf": return Color(hex: 0xF04444)
        case "doc", "docx", "pages": return Color(hex: 0x3B82F6)
        case "xls", "xlsx", "numbers", "csv": return Color(hex: 0x20B26B)
        case "ppt", "pptx", "key": return Color(hex: 0xF59E0B)
        case "zip", "rar", "7z": return Color(hex: 0x8B5CF6)
        case "txt", "md", "rtf": return Color(hex: 0x6B7280)
        default: return Color(hex: 0x0A84FF)
        }
    }

    private var fileSymbol: String {
        switch local.pathExtension.lowercased() {
        case "pdf": return "doc.richtext.fill"
        case "doc", "docx", "pages", "txt", "md", "rtf":
            return "doc.text.fill"
        case "xls", "xlsx", "numbers", "csv":
            return "tablecells.fill"
        case "ppt", "pptx", "key":
            return "rectangle.on.rectangle.fill"
        case "zip", "rar", "7z":
            return "archivebox.fill"
        default: return "doc.fill"
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                VStack(spacing: 10) {
                    if let kind = officeKind {
                        OfficeDocumentHeader(kind: kind, name: name, local: local)
                    } else {
                        fileHero
                    }

                    QuickLookView(url: local)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.primary.opacity(0.075), lineWidth: 0.7)
                        }
                        .shadow(color: Color.black.opacity(0.055), radius: 12, y: 5)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
            }
            .navigationTitle(Tr("文件预览"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.primary.opacity(0.72))
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Color.primary.opacity(0.065)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Tr("关闭"))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if officeKind != nil {
                        Button { showOfficeInfo = true } label: {
                            Image(systemName: "info.circle")
                        }
                        .accessibilityLabel(Tr("文件信息"))
                    } else {
                        Button { showShare = true } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let kind = officeKind {
                    OfficeDocumentActionBar(
                        kind: kind,
                        favoriting: favoriting,
                        onFavorite: favorite,
                        onPrint: { printDocument() },
                        onShare: { showShare = true },
                        onDrop: { showDrop = true },
                        onInfo: { showOfficeInfo = true }
                    )
                } else {
                    defaultActionBar
                }
            }
            .sheet(isPresented: $showShare) { ShareSheet(items: [local]) }
            .sheet(isPresented: $showOfficeInfo) {
                if let kind = officeKind {
                    OfficeDocumentInfoSheet(kind: kind, name: name, local: local)
                }
            }
            .fullScreenCover(isPresented: $showDrop) {
                FaceToFaceFileSheet(rows: [], avatar: app.me?.avatarPath ?? "",
                                    name: app.me?.name ?? "我", ink: C.label,
                                    mode: .host, initialFiles: [local])
                    .environmentObject(app)
            }
        }
    }

    private var fileHero: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [fileAccent, fileAccent.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: fileSymbol)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 52, height: 52)
            .shadow(color: fileAccent.opacity(0.22), radius: 8, y: 4)

            VStack(alignment: .leading, spacing: 5) {
                Text(name)
                    .font(pf(15.5, .semibold))
                    .foregroundStyle(C.label)
                    .lineLimit(2)
                HStack(spacing: 7) {
                    Text(fileExtension)
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(fileAccent)
                        .padding(.horizontal, 6)
                        .frame(height: 18)
                        .background(Capsule().fill(fileAccent.opacity(0.11)))
                    Text(fileSizeText)
                    if !fileDateText.isEmpty {
                        Text("·")
                        Text(fileDateText)
                    }
                }
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(C.subLabel)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 0.7)
        }
        .padding(.horizontal, 12)
    }

    private var defaultActionBar: some View {
        HStack(spacing: 10) {
            Button {
                favorite()
            } label: {
                VStack(spacing: 4) {
                    if favoriting {
                        ProgressView().scaleEffect(0.62).frame(height: 21)
                    } else {
                        Image(systemName: "star.fill")
                            .font(.system(size: 18, weight: .medium))
                            .frame(height: 21)
                    }
                    Text(Tr("收藏")).font(.system(size: 10.5, weight: .medium))
                }
                .foregroundColor(C.green)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(Color.primary.opacity(0.045)))
            }
            .buttonStyle(.plain)
            .disabled(favoriting)

            Button { showDrop = true } label: {
                VStack(spacing: 4) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 18, weight: .medium))
                        .frame(height: 21)
                    Text(Tr("快传")).font(.system(size: 10.5, weight: .medium))
                }
                .foregroundColor(C.label)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(Color.primary.opacity(0.045)))
            }
            .buttonStyle(.plain)

            Button { showShare = true } label: {
                VStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(height: 21)
                    Text(Tr("分享")).font(.system(size: 10.5, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    LinearGradient(
                        colors: [Color(hex: 0x4EDC7C), C.green],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                )
                .shadow(color: C.green.opacity(0.18), radius: 7, y: 3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial)
    }

    private func printDocument() {
        guard UIPrintInteractionController.canPrint(local) else {
            app.show(Tr("这个文档暂时无法打印"))
            return
        }
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo.printInfo()
        info.jobName = name
        info.outputType = .general
        controller.printInfo = info
        controller.printingItem = local
        _ = controller.present(animated: true, completionHandler: nil)
    }

    private func favorite() {
        favoriting = true
        Task {
            let ok = await API.shared.addFavorite(kind: "text",
                                                  content: "[文件] " + name,
                                                  title: favoriteTitle,
                                                  from: favoriteFrom)
            favoriting = false
            app.show(ok ? Tr("已收藏") : Tr("收藏失败"))
        }
    }
}

struct QuickLookView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let vc = QLPreviewController()
        vc.dataSource = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: QLPreviewController, context: Context) { }

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController,
                               previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

private struct InlineVoiceWave: View {
    let level: CGFloat
    let active: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(0..<18, id: \.self) { index in
                let phase = abs(sin(Double(index) * 1.37 + Double(level) * 7.5))
                let intensity = 0.24 + phase * 0.76
                Capsule(style: .continuous)
                    .fill(active ? OrbitTheme.jade : Color.red)
                    .frame(width: 2.4,
                           height: 4 + (18 * max(0.06, level) * CGFloat(intensity)))
            }
        }
        .animation(.easeOut(duration: 0.08), value: level)
        .accessibilityHidden(true)
    }
}
