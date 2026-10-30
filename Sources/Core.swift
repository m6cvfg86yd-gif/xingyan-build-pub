import SwiftUI
import UIKit
import ImageIO

enum MomentsPref {
    private static let key = "chris.momentsOn"

    static var isOn: Bool {
        if UserDefaults.standard.object(forKey: key) == nil { return true }
        return UserDefaults.standard.bool(forKey: key)
    }
    static func set(_ v: Bool) {
        UserDefaults.standard.set(v, forKey: key)

        NotificationCenter.default.post(name: .chrisUIPrefsChanged, object: nil)
    }
}

extension Notification.Name {

    static let chrisUIPrefsChanged = Notification.Name("chrisUIPrefsChanged")
    static let chrisChatRead = Notification.Name("chris.chatRead")
}

extension View {

    func copyOnLongPress(_ text: String, toast: ((String) -> Void)? = nil) -> some View {
        self.onLongPressGesture(minimumDuration: 0.4) {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return }
            UIPasteboard.general.string = t
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            toast?(Tr("已复制"))
        }
    }
}

enum AppInfo {

    static let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    static let displayVersion = "7.0 Max"
    static let build: String = {
        let n = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "1"
        let d = (Bundle.main.infoDictionary?["BuildDate"] as? String) ?? ""
        return d.isEmpty ? ("B" + n) : ("B" + n + " · " + d)
    }()

    static let deviceId: String = {
        let key = "chris.device.id"
        if let v = Keychain.get(key), !v.isEmpty { return v }
        let v = UUID().uuidString
        Keychain.set(v, for: key)
        return v
    }()

    static let deviceName: String =
        UIDevice.current.name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""

    static let deviceMachine: String = {
        var sys = utsname()
        uname(&sys)
        let id = withUnsafePointer(to: &sys.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        return id.isEmpty ? UIDevice.current.model : id
    }()

    static let deviceModel: String = friendlyModel(deviceMachine)
    private static func friendlyModel(_ id: String) -> String {
        let map: [String: String] = [
            "iPhone8,1": "iPhone 6s", "iPhone8,2": "iPhone 6s Plus",
            "iPhone8,4": "iPhone SE",
            "iPhone9,1": "iPhone 7", "iPhone9,3": "iPhone 7",
            "iPhone9,2": "iPhone 7 Plus", "iPhone9,4": "iPhone 7 Plus",
            "iPhone10,1": "iPhone 8", "iPhone10,4": "iPhone 8",
            "iPhone10,2": "iPhone 8 Plus", "iPhone10,5": "iPhone 8 Plus",
            "iPhone10,3": "iPhone X", "iPhone10,6": "iPhone X",
            "iPhone11,2": "iPhone XS", "iPhone11,4": "iPhone XS Max",
            "iPhone11,6": "iPhone XS Max", "iPhone11,8": "iPhone XR",
            "iPhone12,1": "iPhone 11", "iPhone12,3": "iPhone 11 Pro",
            "iPhone12,5": "iPhone 11 Pro Max", "iPhone12,8": "iPhone SE2",
            "iPhone13,1": "iPhone 12 mini", "iPhone13,2": "iPhone 12",
            "iPhone13,3": "iPhone 12 Pro", "iPhone13,4": "iPhone 12 Pro Max",
            "iPhone14,2": "iPhone 13 Pro", "iPhone14,3": "iPhone 13 Pro Max",
            "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13",
            "iPhone14,6": "iPhone SE3", "iPhone14,7": "iPhone 14", "iPhone14,8": "iPhone 14 Plus",
            "iPhone15,2": "iPhone 14 Pro", "iPhone15,3": "iPhone 14 Pro Max",
            "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus",
            "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max",
            "iPhone17,3": "iPhone 16", "iPhone17,4": "iPhone 16 Plus",
            "iPhone17,1": "iPhone 16 Pro", "iPhone17,2": "iPhone 16 Pro Max",
            "iPhone17,5": "iPhone 16e",
            "iPhone18,3": "iPhone 17", "iPhone18,4": "iPhone Air",
            "iPhone18,1": "iPhone 17 Pro", "iPhone18,2": "iPhone 17 Pro Max",
            "iPhone18,5": "iPhone 17e",
            "iPad13,1": "iPad Air 4", "iPad13,2": "iPad Air 4",
            "iPad13,4": "iPad Pro 11 M1", "iPad13,5": "iPad Pro 11 M1",
            "iPad13,6": "iPad Pro 12.9 M1", "iPad13,7": "iPad Pro 12.9 M1",
            "iPad13,8": "iPad mini 6", "iPad13,9": "iPad mini 6",
            "iPad13,10": "iPad 10", "iPad13,11": "iPad 10",
            "iPad13,16": "iPad Air 5", "iPad13,17": "iPad Air 5",
            "iPad14,3": "iPad Pro 11 M2", "iPad14,4": "iPad Pro 11 M2",
            "iPad14,5": "iPad Pro 12.9 M2", "iPad14,6": "iPad Pro 12.9 M2",
            "iPad14,8": "iPad Air 11 M2", "iPad14,9": "iPad Air 13 M2",
            "iPad14,10": "iPad mini 7", "iPad14,11": "iPad mini 7",
            "iPad16,3": "iPad Pro 11 M4", "iPad16,4": "iPad Pro 11 M4",
            "iPad16,5": "iPad Pro 13 M4", "iPad16,6": "iPad Pro 13 M4"
        ]
        if let v = map[id] { return v }
        if id.lowercased().hasPrefix("ipad") { return "iPad · \(id)" }
        if id.lowercased().hasPrefix("iphone") { return "iPhone · \(id)" }
        return id.isEmpty ? UIDevice.current.model : id
    }

    static let deviceOs: String = "iOS " + UIDevice.current.systemVersion

    static let deviceKind: String = {
        switch UIDevice.current.userInterfaceIdiom {
        case .pad: return "tablet"
        case .mac: return "desktop"
        default:   return "phone"
        }
    }()

    static let deviceKindName: String = {
        switch deviceKind {
        case "tablet":  return "平板"
        case "desktop": return "电脑"
        default:        return "手机"
        }
    }()
}

enum UIConfig {
    private static var numbers: [String: CGFloat] = [:]
    private static var strings: [String: String] = [:]
    static var scale: CGFloat = 0.94

    static func num(_ key: String, _ def: CGFloat) -> CGFloat { numbers[key] ?? def }

    static func text(_ key: String, _ def: String) -> String {
        if let v = strings[key], !v.trimmingCharacters(in: .whitespaces).isEmpty { return v }
        return def
    }

    static func color(_ key: String, _ light: UInt32, _ dark: UInt32) -> Color {
        guard let raw = strings[key] else { return Color.dyn(light, dark) }
        let parts = raw.split(separator: "|").map { String($0).trimmingCharacters(in: .whitespaces) }
        func hex(_ s: String) -> UInt32? { UInt32(s.replacingOccurrences(of: "#", with: ""), radix: 16) }
        let l = parts.count > 0 ? (hex(parts[0]) ?? light) : light
        let d = parts.count > 1 ? (hex(parts[1]) ?? l) : l
        return Color.dyn(l, d)
    }

    static func colorIfSet(_ key: String) -> Color? {
        guard let raw = strings[key], !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let parts = raw.split(separator: "|").map { String($0).trimmingCharacters(in: .whitespaces) }
        func hex(_ s: String) -> UInt32? { UInt32(s.replacingOccurrences(of: "#", with: ""), radix: 16) }
        guard let first = parts.first, let l = hex(first) else { return nil }
        let d = parts.count > 1 ? (hex(parts[1]) ?? l) : l
        return Color.dyn(l, d)
    }

    static func apply(_ json: [String: Any]) {
        var n: [String: CGFloat] = [:]
        var s: [String: String] = [:]
        for (k, v) in json {
            if let d = v as? Double { n[k] = CGFloat(d) }
            else if let i = v as? Int { n[k] = CGFloat(i) }
            else if let b = v as? Bool { n[k] = b ? 1 : 0 }
            else if let t = v as? String { s[k] = t }
        }
        numbers = n
        strings = s
        if let sc = n["fontScale"], sc > 0.5, sc < 1.6 { scale = sc }
    }
}

enum L {

    static var width: CGFloat = {
        if let w = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
            .windows.first?.bounds.width, w > 0 { return w }
        return UIScreen.main.bounds.width
    }()

    static var height: CGFloat {
        if let h = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
            .windows.first?.bounds.height, h > 0 { return h }
        return UIScreen.main.bounds.height
    }

    static var compactPhone: Bool { width <= 375 || height <= 700 }

    static var iOS27OrLater: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0)
        )
    }

    static func v(_ lo: CGFloat, _ vw: CGFloat, _ hi: CGFloat) -> CGFloat {
        min(max(lo, width * vw / 100), hi)
    }

    static func o(_ key: String, _ def: CGFloat) -> CGFloat { UIConfig.num(key, def) }

    static var safeTop: CGFloat {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
            .windows.first?.safeAreaInsets.top ?? 20
    }
    static var safeBottom: CGFloat {
        max(0, (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
            .windows.first?.safeAreaInsets.bottom ?? 0)
    }

    static var navH: CGFloat {
        let def: CGFloat = compactPhone ? 42
            : ((width >= 398 && width <= 425) ? 48 : v(42, 11.4, 50))
        return o("navH", def)
    }
    static var tabH: CGFloat { o("tabH", compactPhone ? 50 : 56) }
    static var tabIcon: CGFloat { o("tabIcon", compactPhone ? 21 : 23) }
    static var tabIconBox: CGFloat { o("tabIconBox", compactPhone ? 22 : 24) }
    static var tabLabel: CGFloat { o("tabLabel", compactPhone ? 10 : 11) }

    static var rowH: CGFloat { o("chatRowH", 72) }
    static var avatar: CGFloat { o("chatAvatar", v(44, 12.3, 48)) }
    static var rowPadL: CGFloat { o("chatPadL", 16) }
    static var rowPadR: CGFloat { o("chatPadR", 16) }
    static var rowGap: CGFloat { o("chatGap", 12) }

    static var rowPadTop: CGFloat { o("chatPadTop", 15) }

    static var rowTextGap: CGFloat { o("chatTextGap", 5) }
    static var rowNameSize: CGFloat { o("chatNameSize", 17) }
    static var rowPreviewSize: CGFloat { o("chatPreviewSize", 14) }
    static var rowTimeSize: CGFloat { o("chatTimeSize", 12) }
    static var searchBoxH: CGFloat { o("searchBoxH", 36) }
    static var searchPad: CGFloat { o("searchPad", 8) }

    static var dividerLeft: CGFloat { o("dividerLeft", 76) }

    static var ctRowH: CGFloat { o("ctRowH", 56) }
    static var ctAvatar: CGFloat { o("ctAvatar", 40) }
    static var ctPadL: CGFloat { o("ctPadL", 16) }
    static var ctGap: CGFloat { o("ctGap", 12) }
    static var ctIcon: CGFloat { o("ctIcon", 40) }
    static var ctNameSize: CGFloat { o("ctNameSize", 16) }
    static var ctHeadH: CGFloat { o("ctHeadH", 28) }
    static var ctHeadSize: CGFloat { o("ctHeadSize", 15) }
    static var ctIdxSize: CGFloat { o("ctIdxSize", 12.5) }
    static var ctIdxItemH: CGFloat { o("ctIdxItemH", 16.5) }

    static var ctSearchGap: CGFloat { o("contactsSearchGap", 10) }
    static var ctSearchIcon: CGFloat { o("contactsSearchIcon", 18) }
    static var ctSearchText: CGFloat { o("contactsSearchText", 17) }
    static var ctTextX: CGFloat { ctPadL + ctAvatar + ctGap }

    static var menuH: CGFloat { o("menuH", 56) }
    static var menuPadL: CGFloat { o("menuPadL", 18) }
    static var menuPadR: CGFloat { o("menuPadR", 16) }
    static var menuGap: CGFloat { o("menuGap", 18) }
    static var menuIcon: CGFloat { o("menuIcon", 22) }
    static var menuTextSize: CGFloat { o("menuTextSize", 17) }
    static var groupGap: CGFloat { o("groupGap", 8) }
    static var menuTextX: CGFloat { menuPadL + menuIcon + menuGap }

    static var menuLineInset: CGFloat { o("menuLineInset", 56) }

    static var msgPad: CGFloat { v(12, 3.1, 14) }

    static var chatAvatar: CGFloat { o("chatAvatar2", 40) }

    static var chatGapMsg: CGFloat { o("chatMsgGap", 9) }

    static var chatGap: CGFloat { o("chatGap", 10) }
    static var bubblePadH: CGFloat { o("bubblePadH", 12) }
    static var bubblePadV: CGFloat { o("bubblePadV", 10) }

    static var bubblePadHPill: CGFloat { bubblePadH + 3 }

    static var msgLineSpacing: CGFloat { o("msgLineSpacing", 0) }

    static var bubbleMaxW: CGFloat { o("bubbleMaxW", min(310, max(240, width * 0.69))) }
    static var composerH: CGFloat { o("composerH", 56) }
    static var composerIconBox: CGFloat { o("composerIconBox", 33) }
    static var composerIcon: CGFloat { o("composerIcon", 28) }
    static var inputH: CGFloat { o("inputH", 39) }

    static var chatFontSize: CGFloat { o("chatFontSize", 16) }
    static var msgTimeSize: CGFloat { o("msgTimeSize", 12.5) }

    static var coverH: CGFloat { o("coverH", 380) }
    static var coverAvatar: CGFloat { v(52, 17.1, 72) }
    static var momentPadH: CGFloat { o("momentPadH", 22) }
    static var momentAvatar: CGFloat { o("momentAvatar", 44) }

    static var cdAvatar: CGFloat { o("cdAvatar", 64) }
    static var cdAvatarRadius: CGFloat { o("cdAvatarRadius", 6) }
    static var cdHeroPadTop: CGFloat { o("cdHeroPadTop", 27) }
    static var cdHeroPadBottom: CGFloat { o("cdHeroPadBottom", 29.5) }
    static var cdHeroPadH: CGFloat { o("cdHeroPadH", 16) }
    static var cdHeroGap: CGFloat { o("cdHeroGap", 16) }
    static var cdNameSize: CGFloat { o("cdNameSize", 20) }
    static var cdNameRowH: CGFloat { o("cdNameRowH", 22) }
    static var cdGender: CGFloat { o("cdGender", 14) }
    static var cdLineSize: CGFloat { o("cdLineSize", 15) }
    static var cdLineH: CGFloat { o("cdLineH", 22) }
    static var cdLineGap: CGFloat { o("cdLineGap", 6) }
    static var cdLabelW: CGFloat { o("cdLabelW", 80) }
    static var cdRowH: CGFloat { o("cdRowH", 22) }
    static var cdRowGap: CGFloat { o("cdRowGap", 8) }
    static var cdRowsPadV: CGFloat { o("cdRowsPadV", 13.5) }
    static var cdPadH: CGFloat { o("cdPadH", 16) }
    static var cdCardGap: CGFloat { o("cdCardGap", 8) }
    static var cdThumbRowTop: CGFloat { o("cdThumbRowTop", 15) }
    static var cdThumbRowBottom: CGFloat { o("cdThumbRowBottom", 15.5) }
    static var cdThumb: CGFloat { o("cdThumb", 48) }
    static var cdThumbGap: CGFloat { o("cdThumbGap", 8) }
    static var cdActH: CGFloat { o("cdActH", 55.6) }
    static var cdActSize: CGFloat { o("cdActSize", 17) }
    static var cdActGap: CGFloat { o("cdActGap", 6.5) }
    static var cdIcChatW: CGFloat { o("cdIcChatW", 19) }
    static var cdIcChatH: CGFloat { o("cdIcChatH", 19.7) }
    static var cdIcVideoW: CGFloat { o("cdIcVideoW", 20) }
    static var cdIcVideoH: CGFloat { o("cdIcVideoH", 21) }

    static var tfPadRowH: CGFloat { o("tfPadRowH", v(50, 13.6, 58)) }
    static var tfKeySize: CGFloat { o("tfKeySize", v(20, 6, 24)) }
    static var tfSendSize: CGFloat { o("tfSendSize", v(15, 4.3, 17)) }
    static var tfCnySize: CGFloat { o("tfCnySize", v(26, 7.6, 32)) }
    static var tfDigitSize: CGFloat { o("tfDigitSize", v(34, 10, 42)) }
    static var tfCellW: CGFloat { o("tfCellW", v(21, 6.6, 28)) }
    static var tfUnitSize: CGFloat { o("tfUnitSize", v(10.5, 3, 12.5)) }
    static var tfCaretH: CGFloat { o("tfCaretH", v(30, 9.4, 40)) }
    static var tfCaretW: CGFloat { o("tfCaretW", 2.5) }
    static var tfAvatar: CGFloat { o("tfAvatar", v(30, 9, 34)) }

    static var payHeadH: CGFloat { o("payHeadH", v(46, 12.9, 54)) }
    static var payPadH: CGFloat { o("payPadH", v(46, 13.1, 55)) }
    static var payPadFont: CGFloat { o("payPadFont", v(20, 5.7, 24)) }
    static var paySheetRadius: CGFloat { o("paySheetRadius", v(10, 3.2, 14)) }
    static var payPwdW: CGFloat { o("payPwdW", v(238, 70.8, 297)) }
    static var payPwdH: CGFloat { o("payPwdH", v(46, 12.4, 52)) }
    static var safeStripH: CGFloat { o("safeStripH", max(34, safeBottom)) }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: 1
        )
    }
    static func dyn(_ light: UInt32, _ dark: UInt32) -> UIColor {
        UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        }
    }
}

extension Color {
    init(hex: UInt32) { self = Color(UIColor(hex: hex)) }

    init(hexString: String, fallback: UInt32 = 0x6F8A38) {
        let s = hexString.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces)
        self = Color(UIColor(hex: UInt32(s, radix: 16) ?? fallback))
    }
    static func dyn(_ light: UInt32, _ dark: UInt32) -> Color { Color(UIColor.dyn(light, dark)) }
}

func colorDyn(_ raw: String?, light: UInt32, dark: UInt32) -> Color {
    let s = (raw ?? "").trimmingCharacters(in: .whitespaces)
    if s.isEmpty { return Color.dyn(light, dark) }
    let parts = s.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
    func hex(_ t: String) -> UInt32? {
        UInt32(t.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces), radix: 16)
    }
    let l = hex(parts[0]) ?? light
    if parts.count > 1, let d = hex(parts[1]) { return Color.dyn(l, d) }
    return Color.dyn(l, dark)
}

enum C {

    static var pageBg      : Color { UIConfig.color("pageBg", 0xEDEDED, 0x0B0B0D) }
    static var navBg       : Color { UIConfig.color("navBg", 0xEDEDED, 0x18181A) }
    static var tabBg       : Color { UIConfig.color("tabBg", 0xF7F7F7, 0x18181A) }
    static var cardBg      : Color { UIConfig.color("cardBg", 0xFFFFFF, 0x1C1C1E) }
    static var chatRowBg   : Color { UIConfig.color("chatRowBg", 0xFFFFFF, 0x2A2A2A) }
    static var pinnedBg    : Color { UIConfig.color("pinnedBg", 0xF2F2F2, 0x333335) }
    static var searchBg    : Color { UIConfig.color("searchBg", 0xFFFFFF, 0x2A2A2C) }

    static var fieldBg     : Color { UIConfig.color("fieldBg", 0xF2F2F2, 0x2C2C2E) }
    static var searchIcon  : Color { UIConfig.color("searchIcon", 0xB2B2B2, 0x9A9A9E) }
    static var searchIcon2 : Color { UIConfig.color("searchIcon2", 0x8C8C8C, 0x9A9A9E) }
    static let searchBorder = Color(UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.12) : UIColor(hex: 0xF0F0F0)
    })

    static let searchBorderChats = Color(UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.12) : UIColor.clear
    })
    static var name        : Color { UIConfig.color("nameColor", 0x1C1C1E, 0xF2F2F7) }
    static var label       : Color { UIConfig.color("labelColor", 0x191919, 0xF2F2F7) }
    static var preview     : Color { UIConfig.color("previewColor", 0xB2B2B2, 0xB2B2B2) }
    static var time        : Color { UIConfig.color("timeColor", 0xC7C7CC, 0xC7C7CC) }

    static var ctIdxColor  : Color { UIConfig.color("ctIdxColor", 0x555555, 0x8E8E93) }
    static var subLabel    : Color { UIConfig.color("subLabelColor", 0x999999, 0x8F8F8F) }
    static var hairline    : Color { UIConfig.color("lineColor", 0xE5E5E5, 0x333335) }
    static var navLine     : Color { UIConfig.color("navLineColor", 0xE8E8E8, 0x2C2C2E) }

    static var green       : Color { UIConfig.color("greenColor", 0x07C160, 0x07C160) }
    static var red         : Color { UIConfig.color("redColor", 0xFA5151, 0xFA5151) }
    static var orange      : Color { UIConfig.color("orangeColor", 0xB27C37, 0xE3B464) }
    static var tabInk      : Color { UIConfig.color("tabInkColor", 0x191919, 0xB5B5B5) }

    static var chatsTopBg  : Color { UIConfig.color("chatsTopBg", 0xF7F7F7, 0x18181A) }

    static var chatsPageBg : Color { UIConfig.color("chatsPageBg", 0xEDEDED, 0x0B0B0D) }
    static var chatsRowBg  : Color { UIConfig.color("chatsRowBg", 0xFFFFFF, 0x1C1C1E) }

    static var contactsBg  : Color { UIConfig.color("contactsBg", 0xFFFFFF, 0x141419) }

    static var discoverBg  : Color { UIConfig.color("discoverBg", 0xEDEDED, 0x141419) }

    static var discoverCardBg: Color { UIConfig.color("discoverCardBg", 0xFFFFFF, 0x1C1C22) }

    static var meCardBg    : Color { UIConfig.color("meCardBg", 0xFFFFFF, 0x1C1C22) }

    static var bubbleMine  : Color { UIConfig.color("bubbleMineColor", 0x95EC69, 0x1E88C7) }
    static var bubbleOther : Color { UIConfig.color("bubbleOtherColor", 0xFFFFFF, 0x2D2D30) }
    static var bubbleText  : Color { UIConfig.color("bubbleTextColor", 0x191919, 0xEDEDED) }

    static var msgTime     : Color { UIConfig.color("msgTimeColor", 0xAEAEB2, 0xAEAEB2) }

    static var chatTimeBg  : Color { UIConfig.color("chatTimeBg", 0xE5E5E5, 0x2C2C2E) }
    static var chatTimeInk : Color { UIConfig.color("chatTimeColor", 0x8A8A8E, 0x8A8A8E) }

    static var link        : Color { UIConfig.color("linkColor", 0x576B95, 0x7D90A9) }
    static let arrow       = Color.dyn(0xB2B2B2, 0x8A8A8E)
    static let ringInk     = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 1, green: 1, blue: 1, alpha: 0.78)
            : UIColor(red: 25 / 255, green: 25 / 255, blue: 26 / 255, alpha: 0.62)
    })
    static let iconGray    = Color.dyn(0x6F6F6F, 0x9A9A9A)

    static var chatBarIcon : Color { UIConfig.color("chatBarIcon", 0x6F6F6F, 0x9A9A9A) }

    static var tabTitle0: String { UIConfig.text("tabTitle0", "聊天") }
    static var tabTitle1: String { UIConfig.text("tabTitle1", "通讯录") }
    static var tabTitle2: String { UIConfig.text("tabTitleWorld", "世界") }
    static var tabTitle3: String { UIConfig.text("tabTitleMe", "我的") }

    static let loginBg     = Color(hex: 0x111111)
    static let loginCard   = Color(hex: 0x191919)
    static let loginText   = Color(hex: 0xEDEDED)
    static let loginGray   = Color(hex: 0x7F7F7F)
    static let loginLink   = Color(hex: 0x7D90A9)
    static let loginGreen  = Color(hex: 0x1DC9BD)
}

var fontScale: CGFloat { UIConfig.scale }

func pfName(_ weight: Font.Weight) -> String? {
    var want = "PingFangSC-Regular"
    if weight == .medium {
        want = "PingFangSC-Medium"
    } else if weight == .semibold || weight == .bold || weight == .heavy || weight == .black {
        want = "PingFangSC-Semibold"
    } else if weight == .light || weight == .thin || weight == .ultraLight {
        want = "PingFangSC-Light"
    }
    if UIFont(name: want, size: 12) != nil { return want }
    for family in UIFont.familyNames where family.lowercased().contains("pingfang") {
        let names = UIFont.fontNames(forFamilyName: family)
        if names.contains(want) { return want }
        if let fallback = names.first { return fallback }
    }
    return nil
}

func pf(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {

    pfExact(max(9, (size * fontScale * CareMode.scale).rounded()), weight)
}

enum CareMode {
    static var on: Bool { UserDefaults.standard.bool(forKey: "chris.careMode") }
    static var scale: CGFloat { on ? 1.18 : 1.0 }
    static func set(_ v: Bool) {
        UserDefaults.standard.set(v, forKey: "chris.careMode")
        NotificationCenter.default.post(name: .chrisUIPrefsChanged, object: nil)
    }

    static var speakText: Bool { UserDefaults.standard.bool(forKey: "chris.careSpeak") }
    static func setSpeak(_ v: Bool) {
        UserDefaults.standard.set(v, forKey: "chris.careSpeak")
        NotificationCenter.default.post(name: .chrisUIPrefsChanged, object: nil)
    }
}

func pfExact(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    if let name = pfName(weight), UIFont(name: name, size: size) != nil {

        return .custom(name, fixedSize: size)
    }
    return .system(size: size, weight: weight)
}

func pfMoney(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
    let s = max(9, (size * fontScale).rounded())

    let din = s >= 20 ? ["AvenirNext-Bold", "AvenirNext-DemiBold", "DINAlternate-Bold", "DINAlternate"]
                      : ["AvenirNext-Medium", "AvenirNext-Regular", "DINAlternate", "DINAlternate-Bold"]
    for name in din {
        if let f = UIFont(name: name, size: s) { return Font(f).monospacedDigit() }
    }

    if weight == .medium {
        for name in ["SFProDisplay-Medium", "SF Pro Display", ".SFUI-Display-Medium"] {
            if let f = UIFont(name: name, size: s) { return Font(f).monospacedDigit() }
        }
    }
    return .system(size: s, weight: weight, design: .default).monospacedDigit()
}

private let moneyFmtter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.locale = Locale(identifier: "en_US_POSIX")
    f.usesGroupingSeparator = true
    f.groupingSeparator = ","
    f.groupingSize = 3
    f.minimumFractionDigits = 2
    f.maximumFractionDigits = 2
    return f
}()

func moneyFmt(_ v: Double) -> String {
    let n = v.isFinite ? v : 0
    return moneyFmtter.string(from: NSNumber(value: n)) ?? String(format: "%.2f", n)
}

func moneySymbolFont(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
    .system(size: size, weight: weight, design: .default)
}

func moneyText(_ text: String, size: CGFloat, curSize: CGFloat = 0, topAlign: Bool = false,
               weight: Font.Weight = .medium, exact: Bool = false) -> Text {
    let f: (CGFloat) -> Font = { s in exact ? pfMoneyExact(s, weight) : pfMoney(s, weight) }
    guard let r = text.range(of: "¥") else {
        return Text(text).font(f(size))
    }
    let prefix = String(text[text.startIndex..<r.lowerBound])
    let rest = String(text[r.upperBound...])

    let curFont = moneySymbolFont(curSize > 0 ? curSize : size, weight)
    var out = Text(prefix).font(f(size))
    var cur = Text("¥").font(curFont)

    if topAlign, curSize > 0, curSize < size {
        cur = cur.baselineOffset((size - curSize) * 0.72)
    }
    out = out + cur
    return out + Text(rest).font(f(size))
}

func pfMoneyExact(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
    let din = size >= 20 ? ["AvenirNext-Bold", "AvenirNext-DemiBold", "DINAlternate-Bold", "DINAlternate"]
                         : ["AvenirNext-Medium", "AvenirNext-Regular", "DINAlternate", "DINAlternate-Bold"]
    for name in din {
        if let f = UIFont(name: name, size: size) { return Font(f).monospacedDigit() }
    }
    if weight == .medium {
        for name in ["SFProDisplay-Medium", "SF Pro Display", ".SFUI-Display-Medium"] {
            if let f = UIFont(name: name, size: size) { return Font(f).monospacedDigit() }
        }
    }
    return .system(size: size, weight: weight, design: .default).monospacedDigit()
}

struct MoneyLabel: View {
    let text: String
    let size: CGFloat
    var curSize: CGFloat = 0
    var topAlign: Bool = false
    var color: Color = C.label
    var weight: Font.Weight = .medium

    var exact: Bool = false

    var body: some View {
        let parts = text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let head = String(parts.first ?? "")
        let tail = parts.count > 1 ? String(parts[1]) : ""
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            moneyText(head, size: size, curSize: curSize, topAlign: topAlign, weight: weight, exact: exact)
                .foregroundColor(color)
            if !tail.isEmpty || text.contains(".") {
                Rectangle()
                    .fill(color)
                    .frame(width: size * 0.16, height: size * 0.16)
                    .padding(.horizontal, size * 0.04)
            }
            if !tail.isEmpty {
                Text(tail).font(exact ? pfMoneyExact(size, weight) : pfMoney(size, weight))
                    .foregroundColor(color)
            }
        }
        .monospacedDigit()
    }
}

enum AppIconImage {
    static var image: UIImage? {
        for name in ["AppIcon60x60@3x", "AppIcon60x60@2x", "AppIcon60x60"] {
            if let p = Bundle.main.path(forResource: name, ofType: "png"), let img = UIImage(contentsOfFile: p) {
                return img
            }
        }
        return UIImage(named: "AppIcon60x60")
    }
}

@MainActor
final class ScrollGate {
    static let shared = ScrollGate()
    private(set) var busy = false
    private var release: Task<Void, Never>?

    func touch() {
        busy = true
        release?.cancel()
        release = Task { @MainActor in

            try? await Task.sleep(nanoseconds: 120_000_000)
            if Task.isCancelled { return }
            busy = false
        }
    }

    func waitUntilIdle() async {
        var waited = 0
        while busy && waited < 5 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            waited += 1
        }
    }
}

final class ImageStore {
    static let shared = ImageStore()
    private var cache: [String: UIImage] = [:]

    private var bytes = 0

    private let memoryCap = 96 * 1024 * 1024
    private let lock = NSLock()
    func get(_ key: String) -> UIImage? {
        lock.lock(); defer { lock.unlock() }
        return cache[key]
    }
    func put(_ key: String, _ img: UIImage) {
        lock.lock(); defer { lock.unlock() }
        if cache[key] != nil { return }
        cache[key] = img
        bytes += Int(img.size.width * img.size.height * 4)

        while bytes > memoryCap, cache.count > 8 {
            let first = cache.keys.first!
            if let old = cache[first] { bytes -= Int(old.size.width * old.size.height * 4) }
            cache.removeValue(forKey: first)
        }
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        cache.removeAll(keepingCapacity: false)
        bytes = 0
        if let d = diskDir {
            try? FileManager.default.removeItem(at: d)
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        }
    }

    var diskUsage: Int {
        guard let d = diskDir else { return 0 }
        var total = 0
        if let files = FileManager.default.enumerator(at: d,
                                                       includingPropertiesForKeys: [.fileSizeKey]) {
            for case let f as URL in files {
                if let n = try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    total += n
                }
            }
        }
        return total
    }

    private let diskDir: URL?
    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        let d = base?.appendingPathComponent("imgcache", isDirectory: true)
        if let d = d { try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }
        diskDir = d
    }

    func diskFile(_ key: String) -> URL? {
        guard let dir = diskDir, !key.isEmpty else { return nil }
        var h: UInt64 = 0xcbf29ce484222325
        for b in key.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return dir.appendingPathComponent(String(format: "%016llx", h) + ".img")
    }

    func diskRead(_ key: String) -> Data? {
        guard let f = diskFile(key) else { return nil }
        return try? Data(contentsOf: f, options: .mappedIfSafe)
    }

    func diskWrite(_ key: String, _ data: Data) {
        guard let f = diskFile(key), !data.isEmpty else { return }
        try? data.write(to: f, options: .atomic)

        guard let dir = diskDir else { return }
        let list = (try? FileManager.default.contentsOfDirectory(at: dir,
                    includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        if list.count > 600 {
            let sorted = list.sorted {
                let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return a < b
            }
            for f2 in sorted.prefix(200) { try? FileManager.default.removeItem(at: f2) }
        }
    }

    func diskBytes() -> Int {
        guard let dir = diskDir else { return 0 }
        let list = (try? FileManager.default.contentsOfDirectory(at: dir,
                    includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return list.reduce(0) { sum, u in
            sum + ((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }
}

func cacheUploadedImage(_ image: UIImage, path: String, maxSide: CGFloat = 640) {
    guard !path.isEmpty else { return }
    guard let data = image.resizedJPEG(maxSide: maxSide, quality: 0.88),
          let prepared = RemoteImage.downsampled(data, maxSide: maxSide) else {
        ImageStore.shared.put(path, image)
        return
    }
    ImageStore.shared.put(path, prepared)
    ImageStore.shared.diskWrite(path, data)
}

struct RemoteImage: View {
    let path: String
    var icon: String = "photo"
    var mode: ContentMode = .fill

    var template: Bool = false

    var maxSide: CGFloat = 1600

    var onLoaded: ((UIImage) -> Void)? = nil

    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geo in
            Group {
                if let image = image {
                    Image(uiImage: image)
                        .renderingMode(template ? .template : .original)
                        .resizable()
                        .aspectRatio(contentMode: mode)
                } else {
                    ZStack {
                        Color.dyn(0xE9E9E9, 0x2C2C2E)
                        Image(systemName: icon)
                            .font(pf(max(10, min(geo.size.width, geo.size.height) * 0.40)))
                            .foregroundColor(Color.dyn(0xC4C4C4, 0x636366))
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .task(id: path) {
            image = nil
            await load()
        }
    }

    private func load() async {
        if path.isEmpty { return }
        let requestedPath = path

        if let hit = ImageStore.shared.get(requestedPath) {
            guard !Task.isCancelled, path == requestedPath else { return }
            image = hit
            onLoaded?(hit)
            return
        }

        let side = max(64, maxSide)

        let diskBytes: Data? = await Task.detached(priority: .userInitiated) { () -> Data? in
            ImageStore.shared.diskRead(requestedPath)
        }.value
        guard !Task.isCancelled, path == requestedPath else { return }
        if let diskBytes = diskBytes {
            let diskImg: UIImage? = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                RemoteImage.downsampled(diskBytes, maxSide: side)
            }.value
            guard !Task.isCancelled, path == requestedPath else { return }
            if let diskImg = diskImg {
                ImageStore.shared.put(requestedPath, diskImg)
                image = diskImg
                onLoaded?(diskImg)
                return
            }
        }

        let data: Data
        if path.hasPrefix("data:") {
            guard let comma = path.firstIndex(of: ","),
                  let d = Data(base64Encoded: String(path[path.index(after: comma)...]),
                               options: .ignoreUnknownCharacters) else { return }
            data = d
        } else {
            guard let url = API.shared.assetURL(requestedPath) else { return }
            var remote: Data?
            for attempt in 0..<2 {
                do {
                    remote = try await API.shared.imageData(url)
                    break
                } catch {
                    guard attempt == 0 else { return }
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    guard !Task.isCancelled, path == requestedPath else { return }
                }
            }
            guard let remote else { return }
            data = remote
        }

        let img = await Task.detached(priority: .userInitiated) {
            RemoteImage.downsampled(data, maxSide: side)
        }.value
        guard !Task.isCancelled, path == requestedPath, let img = img else { return }
        ImageStore.shared.put(requestedPath, img)
        image = img
        onLoaded?(img)

        Task.detached(priority: .background) { ImageStore.shared.diskWrite(requestedPath, data) }

        if requestedPath.hasPrefix("/uploads/") || requestedPath.hasPrefix("/emoji/") {
            Task.detached(priority: .background) { LocalStore.keep(requestedPath, data: data) }
        }
    }

    static func downsampled(_ data: Data, maxSide: CGFloat) -> UIImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        if let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) {
            return UIImage(cgImage: cg)
        }
        return UIImage(data: data)
    }
}

struct Avatar: View {
    let path: String
    var size: CGFloat = 48
    var radius: CGFloat = 6
    var circle = false
    var group = false

    var level: Int = 0

    var body: some View {
        Group {
            if Avatar.isEyesBot(path) {

                JarvisEyesAvatar(size: size * 0.86)
                    .frame(width: size, height: size)
                    .background(shape.fill(Color.white))
            } else if path.isEmpty {

                ZStack {
                    if group {
                        shape.fill(LinearGradient(colors: [Color(hex: 0x58B94F), Color(hex: 0x2F923C)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing))
                    } else {
                        shape.fill(Color.dyn(0xEDEDED, 0x2C2C2E))
                    }
                    Image(systemName: group ? "person.3.fill" : "person.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: group ? size * 0.54 : size * 0.56,
                               height: group ? size * 0.54 : size * 0.56)
                        .foregroundColor(group ? .white : Color.dyn(0x707074, 0x8E8E93))
                        .offset(y: group ? 0 : size * 0.04)
                }
                .frame(width: size, height: size)
                .clipShape(shape)
            } else {
                RemoteImage(path: path, icon: "person.fill")
                    .id(path)
                    .frame(width: size, height: size)
                    .clipShape(shape)
            }
        }

        .overlay {
            if level >= 4, GrowthFlags.avatarFrame != false {
                QQAvatarFrame(level: level, size: size, circle: circle, radius: radius)
            }
        }
    }

    static func isEyesBot(_ p: String) -> Bool {
        p.contains("bot-ai-eyes")
    }

    private var shape: AnyShape {
        if circle { return AnyShape(Circle()) }
        return AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// 微信式群头像：没有单独上传群头像时，用前四个成员的头像拼图。
/// 群成员信息优先取本地通讯录；本地不全时只对可见会话补拉一次。
struct GroupAvatarMosaic: View {
    let chatId: String
    let memberIds: [String]
    var size: CGFloat = 48
    var radius: CGFloat = 6

    @EnvironmentObject private var app: AppState
    @State private var fetchedMembers: [User] = []
    @State private var loaded = false

    private var resolvedUsers: [String: User] {
        let local = ([app.me].compactMap { $0 } + app.contacts + fetchedMembers)
        var out: [String: User] = [:]
        for user in local where out[user.id] == nil {
            out[user.id] = user
        }
        return out
    }

    private var shownCount: Int {
        max(1, min(9, memberIds.count))
    }

    private var slots: [User?] {
        let lookup = resolvedUsers
        return Array(memberIds.prefix(shownCount)).map { lookup[$0] }
    }

    var body: some View {
        Group {
            if memberIds.isEmpty {
                Avatar(path: "", size: size, radius: radius, group: true)
            } else {
                ZStack(alignment: .topLeading) {
                    ForEach(Array(slots.enumerated()), id: \.offset) { index, user in
                        let box = tileBox(index: index, count: shownCount)
                        tile(user,
                             index: index,
                             count: shownCount)
                            .frame(width: box.width, height: box.height)
                            .position(x: box.midX, y: box.midY)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .background(Color.dyn(0xE8E8EC, 0x222528))
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .task(id: chatId) {
            guard !loaded, !memberIds.isEmpty else { return }
            loaded = true
            let known = Set(([app.me].compactMap { $0 } + app.contacts).map(\.id))
            guard memberIds.contains(where: { !known.contains($0) }) else { return }
            if let r = try? await API.shared.chatMembers(chatId: chatId) {
                fetchedMembers = r.members
            }
        }
    }

    private var gap: CGFloat {
        size >= 76 ? 3 : 1.5
    }

    private func tileBox(index: Int, count: Int)
        -> (x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat,
            midX: CGFloat, midY: CGFloat) {
        let boxes = normalizedBoxes(count)
        let box = boxes[min(max(0, index), boxes.count - 1)]
        let x = box.minX * size + (box.minX > 0 ? gap / 2 : 0)
        let y = box.minY * size + (box.minY > 0 ? gap / 2 : 0)
        let right = box.maxX * size - (box.maxX < 1 ? gap / 2 : 0)
        let bottom = box.maxY * size - (box.maxY < 1 ? gap / 2 : 0)
        let width = max(1, right - x)
        let height = max(1, bottom - y)
        return (x, y, width, height, x + width / 2, y + height / 2)
    }

    /// 与服务端群头像同一套自适应拼图：铺满画布，不在末行留下空格。
    private func normalizedBoxes(_ count: Int) -> [CGRect] {
        let n = max(1, min(9, count))
        let third = CGFloat(1) / 3
        switch n {
        case 1:
            return [CGRect(x: 0, y: 0, width: 1, height: 1)]
        case 2:
            return [
                CGRect(x: 0, y: 0, width: 0.5, height: 1),
                CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
            ]
        case 3:
            return [
                CGRect(x: 0, y: 0, width: 0.64, height: 1),
                CGRect(x: 0.64, y: 0, width: 0.36, height: 0.5),
                CGRect(x: 0.64, y: 0.5, width: 0.36, height: 0.5)
            ]
        case 4:
            return [
                CGRect(x: 0, y: 0, width: 0.5, height: 0.5),
                CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
                CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5),
                CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
            ]
        case 5:
            return [
                CGRect(x: 0, y: 0, width: 0.5, height: 0.5),
                CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
                CGRect(x: 0, y: 0.5, width: third, height: 0.5),
                CGRect(x: third, y: 0.5, width: third, height: 0.5),
                CGRect(x: third * 2, y: 0.5, width: third, height: 0.5)
            ]
        case 6:
            return (0..<6).map { index in
                CGRect(x: CGFloat(index % 3) * third,
                       y: CGFloat(index / 3) * 0.5,
                       width: third, height: 0.5)
            }
        case 7:
            return [CGRect(x: 0, y: 0, width: 1, height: 0.4)]
                + (0..<6).map { index in
                    CGRect(x: CGFloat(index % 3) * third,
                           y: 0.4 + CGFloat(index / 3) * 0.3,
                           width: third, height: 0.3)
                }
        case 8:
            return [
                CGRect(x: 0, y: 0, width: 0.5, height: 0.4),
                CGRect(x: 0.5, y: 0, width: 0.5, height: 0.4)
            ] + (0..<6).map { index in
                CGRect(x: CGFloat(index % 3) * third,
                       y: 0.4 + CGFloat(index / 3) * 0.3,
                       width: third, height: 0.3)
            }
        default:
            return (0..<9).map { index in
                CGRect(x: CGFloat(index % 3) * third,
                       y: CGFloat(index / 3) * third,
                       width: third, height: third)
            }
        }
    }

    @ViewBuilder
    private func tile(_ user: User?, index: Int, count: Int) -> some View {
        if memberIds.count > 9, index == 8 {
            Text("+\(memberIds.count - 8)")
                .font(.system(size: max(9, size * 0.105), weight: .medium))
                .foregroundColor(C.subLabel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.dyn(0xE7E7EA, 0x2B3037))
        } else if let path = user?.avatarPath, !path.isEmpty {
            RemoteImage(path: path, icon: "person.fill")
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else {
            ZStack {
                Color.dyn(0xEAEAED, 0x2A2D31)
                Image(systemName: "person.fill")
                    .font(.system(size: tileIconSize(index: index, count: count),
                                  weight: .regular))
                    .foregroundColor(Color.dyn(0xC7C7CC, 0x777C84))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func tileIconSize(index: Int, count: Int) -> CGFloat {
        if count == 2 { return size * 0.20 }
        if count == 3 || count == 4 { return size * 0.20 }
        return size * 0.13
    }
}

struct QQAvatarFrame: View {
    var level: Int
    var size: CGFloat
    var circle: Bool = true
    var radius: CGFloat = 6

    @State private var breathe = false
    @State private var sweep = false
    @State private var floaty = false
    @State private var rays = false

    private var tier: Int {
        if level >= 64 { return 3 }
        if level >= 16 { return 2 }
        if level >= 4 { return 1 }
        return 0
    }

    private var motionOn: Bool { size >= 52 }

    private var band: CGFloat {
        switch tier {
        case 1:  return max(2.0, size * 0.055)
        case 2:  return max(2.8, size * 0.078)
        case 3:  return max(3.2, size * 0.094)
        default: return 0
        }
    }

    private var ring: AvatarRing { AvatarRing(circle: circle, radius: radius) }

    private var metal: AngularGradient {
        let stops: [Gradient.Stop]
        switch tier {
        case 1:
            stops = [
                .init(color: Color(hex: 0xF7FBFF), location: 0.00),
                .init(color: Color(hex: 0xAFC7E8), location: 0.14),
                .init(color: Color(hex: 0x6D8CBE), location: 0.30),
                .init(color: Color(hex: 0xD6E4F9), location: 0.48),
                .init(color: Color(hex: 0x8BA6CE), location: 0.66),
                .init(color: Color(hex: 0x5B78A9), location: 0.84),
                .init(color: Color(hex: 0xF7FBFF), location: 1.00)
            ]
        case 2:
            stops = [
                .init(color: Color(hex: 0xFFF9DC), location: 0.00),
                .init(color: Color(hex: 0xFFD25A), location: 0.16),
                .init(color: Color(hex: 0xD98A08), location: 0.32),
                .init(color: Color(hex: 0xFFF0B4), location: 0.50),
                .init(color: Color(hex: 0xE8A61E), location: 0.68),
                .init(color: Color(hex: 0xB06F04), location: 0.86),
                .init(color: Color(hex: 0xFFF9DC), location: 1.00)
            ]
        default:
            stops = [
                .init(color: Color(hex: 0xFFFCEC), location: 0.00),
                .init(color: Color(hex: 0xFFE07A), location: 0.14),
                .init(color: Color(hex: 0xCE8B09), location: 0.30),
                .init(color: Color(hex: 0xFFF6CE), location: 0.46),
                .init(color: Color(hex: 0xF0B72B), location: 0.62),
                .init(color: Color(hex: 0xA96806), location: 0.80),
                .init(color: Color(hex: 0xFFF1B0), location: 1.00)
            ]
        }
        return AngularGradient(gradient: Gradient(stops: stops), center: .center)
    }

    private func sweepArc(_ alpha: Double) -> AngularGradient {
        AngularGradient(
            gradient: Gradient(stops: [
                .init(color: Color.white.opacity(0), location: 0.00),
                .init(color: Color.white.opacity(0), location: 0.62),
                .init(color: Color.white.opacity(alpha * 0.40), location: 0.72),
                .init(color: Color.white.opacity(alpha), location: 0.79),
                .init(color: Color.white.opacity(alpha * 0.30), location: 0.87),
                .init(color: Color.white.opacity(0), location: 0.96),
                .init(color: Color.white.opacity(0), location: 1.00)
            ]),
            center: .center
        )
    }

    private var glowColor: Color { tier >= 3 ? Color(hex: 0xFFD34B) : (tier >= 2 ? Color(hex: 0xFFC93C) : Color(hex: 0xBBD4FF)) }

    var body: some View {
        ZStack {

            if tier >= 2 {
                Circle()
                    .fill(RadialGradient(colors: [glowColor.opacity(breathe ? 0.30 : 0.14), Color.clear],
                                         center: .center,
                                         startRadius: size * 0.46,
                                         endRadius: size * 0.62))
                    .frame(width: size * 1.24, height: size * 1.24)
                    .scaleEffect(breathe ? 1.02 : 0.98)
                    .allowsHitTesting(false)
            }

            if tier >= 2, motionOn {
                SunBurstShape(rays: tier >= 3 ? 14 : 12)
                    .fill(Color.white.opacity(0.85))
                    .frame(width: size * 1.16, height: size * 1.16)
                    .rotationEffect(.degrees(rays ? 360 : 0))
                    .opacity(breathe ? 0.34 : 0.18)
                    .mask(ring.stroke(style: StrokeStyle(lineWidth: band * 1.5)).frame(width: size, height: size))
                    .allowsHitTesting(false)
            }

            if tier >= 1 {
                ring.stroke(metal, lineWidth: band)

                    .shadow(color: glowColor.opacity(tier >= 2 ? 0.45 : 0.30), radius: motionOn ? band * 0.9 : 0)
                    .allowsHitTesting(false)
            }

            if tier >= 1 {
                ring.stroke(Color.black.opacity(0.16), lineWidth: 0.7)
                    .padding(band * 0.52)
                    .allowsHitTesting(false)
                ring.stroke(Color.white.opacity(tier >= 2 ? 0.5 : 0.36), lineWidth: 0.8)
                    .padding(-band * 0.55)
                    .allowsHitTesting(false)
            }

            if tier >= 1 {
                ring.stroke(sweepArc(tier >= 3 ? 0.95 : (tier >= 2 ? 0.85 : 0.55)),
                            lineWidth: band * 1.05)
                    .rotationEffect(.degrees(sweep ? 360 : 0))
                    .shadow(color: (tier >= 2 ? Color(hex: 0xFFE9A6) : Color(hex: 0xDCEBFF)).opacity(0.9),
                            radius: motionOn ? band * 1.4 : 0)
                    .allowsHitTesting(false)
            }

            if tier >= 1 {
                ring.trim(from: 0.54, to: 0.80)
                    .stroke(Color.white.opacity(tier >= 2 ? 0.8 : 0.62),
                            style: StrokeStyle(lineWidth: band * 0.42, lineCap: .round))
                    .blur(radius: motionOn ? 0.5 : 0)
                    .allowsHitTesting(false)
            }

            if tier == 1 {
                QQGlyph(kind: .moon, size: max(10, size * 0.28))
                    .offset(x: -size * 0.33, y: size * 0.34 + (floaty ? -0.8 : 0.6))
                    .allowsHitTesting(false)
            }

            if tier >= 2, motionOn {
                TwinkleStar(side: max(5, size * 0.16), color: glowColor, duration: 0.80)
                    .offset(x: -size * 0.44, y: -size * 0.20)
                TwinkleStar(side: max(4, size * 0.12), color: glowColor, duration: 1.10)
                    .offset(x: size * 0.22, y: size * 0.44)
                TwinkleStar(side: max(4, size * 0.13), color: glowColor, duration: 0.95)
                    .offset(x: -size * 0.24, y: size * 0.46)
            }
        }

        .frame(width: size, height: size)
        .onAppear {
            guard tier >= 1 else { return }

            guard motionOn else { return }

            withAnimation(.linear(duration: 3.6).repeatForever(autoreverses: false)) { sweep = true }
            if tier >= 2 {

                withAnimation(.linear(duration: 24).repeatForever(autoreverses: false)) { rays = true }
            }
            if tier >= 2 {

                withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { breathe = true }
            }
            if tier >= 1 {

                withAnimation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true)) { floaty = true }
            }
        }
    }

}

struct TwinkleStar: View {
    var side: CGFloat
    var color: Color
    var duration: Double

    @State private var on = false

    var body: some View {
        SparkleShape()
            .fill(Color.white)
            .frame(width: side, height: side)
            .shadow(color: color.opacity(0.9), radius: 2.5)
            .opacity(on ? 0.95 : 0.10)
            .scaleEffect(on ? 1 : 0.5)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) { on = true }
            }
    }
}

struct AvatarRing: Shape {
    var circle: Bool
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        circle ? Path(ellipseIn: rect)
               : Path(roundedRect: rect, cornerRadius: radius + 1.5, style: .continuous)
    }
}

struct SunBurstShape: Shape {
    var rays: Int = 12

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let m = min(rect.width, rect.height)
        let r0 = m * 0.36
        let r1 = m * 0.56
        for i in 0..<max(3, rays) {
            let a = Double(i) * 2 * Double.pi / Double(max(3, rays))
            let half = Double.pi / Double(max(3, rays)) * 0.40
            p.move(to: CGPoint(x: c.x + CGFloat(cos(a - half)) * r0, y: c.y + CGFloat(sin(a - half)) * r0))
            p.addLine(to: CGPoint(x: c.x + CGFloat(cos(a)) * r1, y: c.y + CGFloat(sin(a)) * r1))
            p.addLine(to: CGPoint(x: c.x + CGFloat(cos(a + half)) * r0, y: c.y + CGFloat(sin(a + half)) * r0))
            p.closeSubpath()
        }
        return p
    }
}

struct SparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        let k = 0.12
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY),
                       control: CGPoint(x: rect.midX + w * k, y: rect.midY - h * k))
        p.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY),
                       control: CGPoint(x: rect.midX + w * k, y: rect.midY + h * k))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.midY),
                       control: CGPoint(x: rect.midX - w * k, y: rect.midY + h * k))
        p.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY),
                       control: CGPoint(x: rect.midX - w * k, y: rect.midY - h * k))
        p.closeSubpath()
        return p
    }
}

struct CrownShape: Shape {
    enum Part { case body, band, both }
    var part: Part = .both

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        if part != .band {

            p.move(to: CGPoint(x: rect.minX + w * 0.06, y: rect.minY + h * 0.72))
            p.addLine(to: CGPoint(x: rect.minX + w * 0.06, y: rect.minY + h * 0.30))
            p.addQuadCurve(to: CGPoint(x: rect.minX + w * 0.27, y: rect.minY + h * 0.54),
                           control: CGPoint(x: rect.minX + w * 0.10, y: rect.minY + h * 0.13))
            p.addQuadCurve(to: CGPoint(x: rect.minX + w * 0.38, y: rect.minY + h * 0.38),
                           control: CGPoint(x: rect.minX + w * 0.31, y: rect.minY + h * 0.48))
            p.addQuadCurve(to: CGPoint(x: rect.minX + w * 0.50, y: rect.minY + h * 0.18),
                           control: CGPoint(x: rect.minX + w * 0.42, y: rect.minY + h * 0.42))
            p.addQuadCurve(to: CGPoint(x: rect.minX + w * 0.62, y: rect.minY + h * 0.38),
                           control: CGPoint(x: rect.minX + w * 0.58, y: rect.minY + h * 0.42))
            p.addQuadCurve(to: CGPoint(x: rect.minX + w * 0.73, y: rect.minY + h * 0.54),
                           control: CGPoint(x: rect.minX + w * 0.69, y: rect.minY + h * 0.48))
            p.addQuadCurve(to: CGPoint(x: rect.minX + w * 0.94, y: rect.minY + h * 0.30),
                           control: CGPoint(x: rect.minX + w * 0.90, y: rect.minY + h * 0.13))
            p.addLine(to: CGPoint(x: rect.minX + w * 0.94, y: rect.minY + h * 0.72))
            p.closeSubpath()
        }
        if part != .body {
            p.addRoundedRect(in: CGRect(x: rect.minX + w * 0.03, y: rect.minY + h * 0.68,
                                        width: w * 0.94, height: h * 0.30),
                             cornerSize: CGSize(width: w * 0.12, height: h * 0.15))
        }
        return p
    }
}

struct CrownBadge: View {
    var size: CGFloat
    @State private var glint = false
    @State private var floaty = false
    @State private var tilt = false

    private var depth: CGFloat { max(0.8, size * 0.10) }

    var body: some View {
        ZStack {

            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0xFFD34B).opacity(glint ? 0.38 : 0.20), Color.clear],
                                     center: .center, startRadius: size * 0.24, endRadius: size * 0.62))
                .frame(width: size * 1.30, height: size * 1.30)

            CrownShape(part: .both)
                .fill(Color.black.opacity(0.20))
                .frame(width: size, height: size)
                .blur(radius: max(0.8, size * 0.10))
                .offset(y: depth * 1.8)
            CrownShape(part: .both)
                .fill(LinearGradient(colors: [Color(hex: 0xB87C08), Color(hex: 0x7E5204)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: size, height: size)
                .offset(y: depth)

            CrownShape(part: .body)
                .fill(LinearGradient(colors: [Color(hex: 0xFFFCE8), Color(hex: 0xFFD24A), Color(hex: 0xC8890C)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: size, height: size)

            CrownShape(part: .body)
                .fill(LinearGradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0.0)],
                                     startPoint: .top, endPoint: .center))
                .frame(width: size, height: size)

            CrownShape(part: .band)
                .fill(LinearGradient(colors: [Color(hex: 0xFFF6C4), Color(hex: 0xF0B72B), Color(hex: 0xA96806)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: size, height: size)
            Rectangle()
                .fill(Color(hex: 0x9A6400).opacity(0.45))
                .frame(width: size * 0.90, height: max(0.5, size * 0.035))
                .offset(y: -size * 0.155)

            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0xFF9A9A), Color(hex: 0xE23B3B), Color(hex: 0x8E1412)],
                                     center: UnitPoint(x: 0.35, y: 0.3),
                                     startRadius: 0, endRadius: size * 0.13))
                .frame(width: size * 0.22, height: size * 0.22)
                .offset(y: size * 0.16)
            Circle()
                .fill(Color.white.opacity(0.9))
                .frame(width: size * 0.055, height: size * 0.055)
                .offset(x: -size * 0.035, y: size * 0.125)

            CrownShape(part: .both)
                .stroke(Color(hex: 0x8E5E06).opacity(0.5), lineWidth: max(0.5, size * 0.05))
                .frame(width: size, height: size)

            SparkleShape()
                .fill(Color.white)
                .frame(width: size * 0.30, height: size * 0.30)
                .offset(x: size * 0.38, y: -size * 0.30)
                .opacity(glint ? 0.95 : 0)
                .scaleEffect(glint ? 1 : 0.4)
        }
        .frame(width: size, height: size)

        .rotation3DEffect(.degrees(tilt ? 9 : -7), axis: (x: 0.15, y: 1, z: 0), perspective: 0.55)
        .offset(y: floaty ? -1.2 : 0.6)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { glint = true }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) { floaty = true }
            withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) { tilt = true }
        }
    }
}

struct Glyph3D: View {
    var kind: QQGlyphKind
    var size: CGFloat

    private var depth: CGFloat { max(0.6, size * 0.11) }
    private var eoFill: FillStyle { FillStyle(eoFill: kind == .moon) }

    private var front: [Color] {
        switch kind {
        case .star:  return [Color(hex: 0xFFF8CC), Color(hex: 0xFFD23F), Color(hex: 0xE39A00)]
        case .sun:   return [Color(hex: 0xFFF2AE), Color(hex: 0xFFB01F), Color(hex: 0xE17000)]
        case .moon:  return [Color(hex: 0xFFFFFF), Color(hex: 0xD8E6FA), Color(hex: 0x91AACF)]
        case .crown: return [Color(hex: 0xFFFBE2), Color(hex: 0xFFD24A), Color(hex: 0xC8890C)]
        }
    }

    private var side: Color {
        switch kind {
        case .star:  return Color(hex: 0xBC7C00)
        case .sun:   return Color(hex: 0xAC5600)
        case .moon:  return Color(hex: 0x6F87A8)
        case .crown: return Color(hex: 0x8E5E06)
        }
    }

    private var edge: Color {
        kind == .moon ? Color(hex: 0x5E7699).opacity(0.40) : Color(hex: 0x6B4400).opacity(0.40)
    }

    var body: some View {
        ZStack {

            QQGlyphShape(kind: kind)
                .fill(Color.black.opacity(0.20), style: eoFill)
                .frame(width: size, height: size)
                .blur(radius: max(0.7, size * 0.10))
                .offset(y: depth * 1.6)

            QQGlyphShape(kind: kind)
                .fill(side, style: eoFill)
                .frame(width: size, height: size)
                .offset(y: depth)

            QQGlyphShape(kind: kind)
                .fill(LinearGradient(colors: front, startPoint: .top, endPoint: .bottom), style: eoFill)
                .frame(width: size, height: size)
                .overlay {
                    if kind != .moon {
                        QQGlyphShape(kind: kind)
                            .stroke(edge, lineWidth: max(0.4, size * 0.045))
                    }
                }

            QQGlyphShape(kind: kind)
                .fill(LinearGradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0.0)],
                                     startPoint: .top, endPoint: .center), style: eoFill)
                .frame(width: size, height: size)

            Ellipse()
                .fill(Color.white.opacity(0.88))
                .frame(width: size * 0.22, height: size * 0.12)
                .rotationEffect(.degrees(-25))
                .offset(x: -size * 0.15, y: -size * 0.22)
                .blur(radius: max(0.2, size * 0.02))
        }
        .frame(width: size, height: size)
    }
}

struct MoonBadge: View {
    var size: CGFloat
    @State private var glow = false

    var body: some View {
        ZStack {

            QQGlyphShape(kind: .moon)
                .fill(Color.black.opacity(0.18), style: FillStyle(eoFill: true))
                .frame(width: size, height: size)
                .blur(radius: max(0.6, size * 0.10))
                .offset(y: size * 0.16)
            QQGlyphShape(kind: .moon)
                .fill(Color(hex: 0x6F87A8), style: FillStyle(eoFill: true))
                .frame(width: size, height: size)
                .offset(y: size * 0.09)

            QQGlyphShape(kind: .moon)
                .fill(LinearGradient(colors: [Color(hex: 0xFFFFFF), Color(hex: 0xD8E6FA), Color(hex: 0x91AACF)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing),
                      style: FillStyle(eoFill: true))
                .frame(width: size, height: size)

            QQGlyphShape(kind: .moon)
                .fill(LinearGradient(colors: [Color.white.opacity(0.7), Color.white.opacity(0.0)],
                                     startPoint: .top, endPoint: .center),
                      style: FillStyle(eoFill: true))
                .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        .shadow(color: Color(hex: 0xBBD4FF).opacity(glow ? 0.7 : 0.28), radius: size * 0.30)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { glow = true }
        }
    }
}

func maskPhone(_ s: String) -> String {
    let digits = s.filter { $0.isNumber }
    guard digits.count >= 7 else { return s }
    let head = digits.prefix(3)
    let tail = digits.suffix(4)
    return "\(head)****\(tail)"
}

enum TimeFmt {
    static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static var dateMemo: [String: Date] = [:]
    private static let dateMemoLock = NSLock()

    static func date(_ s: String?) -> Date? {
        guard let s = s, !s.isEmpty else { return nil }
        dateMemoLock.lock()
        if let hit = dateMemo[s] { dateMemoLock.unlock(); return hit }
        dateMemoLock.unlock()
        guard let d = isoFrac.date(from: s) ?? isoPlain.date(from: s) else { return nil }
        dateMemoLock.lock()

        if dateMemo.count > 12_000 { dateMemo.removeAll(keepingCapacity: true) }
        dateMemo[s] = d
        dateMemoLock.unlock()
        return d
    }

    private static func make(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = format
        return f
    }
    private static let fHM24 = make("HH:mm")
    private static let fHM12 = make("h:mm")
    private static let fWeekday = make("EEEE")
    private static let fMonthDay = make("M月d日")
    private static let fYearMonthDay = make("yyyy年M月d日")

    private static let fClock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = DateFormatter.dateFormat(fromTemplate: "jm", options: 0, locale: Locale.current) ?? "HH:mm"
        return f
    }()
    private static let fBill = make("yyyy年M月d日 H:mm:ss")

    static func list(_ s: String?) -> String {
        guard let d = date(s) else { return "" }
        let cal = Calendar.current
        if cal.isDateInToday(d) {
            return fClock.string(from: d)
        }
        if cal.isDateInYesterday(d) { return "昨天" }
        let days = cal.dateComponents([.day],
                                      from: cal.startOfDay(for: d),
                                      to: cal.startOfDay(for: Date())).day ?? 99

        if days == 2 { return "前天" }
        if days < 7 { return fWeekday.string(from: d) }
        return cal.isDate(d, equalTo: Date(), toGranularity: .year)
            ? fMonthDay.string(from: d)
            : fYearMonthDay.string(from: d)
    }

    static func bubble(_ s: String?) -> String {
        guard let d = date(s) else { return "" }
        let cal = Calendar.current
        let clock = fClock.string(from: d)
        if cal.isDateInToday(d) {
            return clock
        }

        let days = cal.dateComponents([.day],
                                      from: cal.startOfDay(for: d),
                                      to: cal.startOfDay(for: Date())).day ?? 99
        if days == 1 { return "昨天 " + clock }
        if days == 2 { return "前天 " + clock }
        if days < 7 { return fWeekday.string(from: d) + " " + clock }
        let day = cal.isDate(d, equalTo: Date(), toGranularity: .year)
            ? fMonthDay.string(from: d)
            : fYearMonthDay.string(from: d)
        return day + " " + clock
    }

    static func minutesBetween(_ a: String?, _ b: String?) -> Int {
        guard let d1 = date(a), let d2 = date(b) else { return 9999 }
        return abs(Int(d2.timeIntervalSince(d1) / 60))
    }

    static func bill(_ s: String?) -> String {
        guard let d = date(s) else { return "" }
        return fBill.string(from: d)
    }

    private static let fMonthDayWeek = make("M月d日 EEEE")

    static func billDay(_ s: String?) -> String {
        guard let d = date(s) else { return "" }
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "今天" }
        if cal.isDateInYesterday(d) { return "昨天" }
        return fMonthDayWeek.string(from: d)
    }

    static func billClock(_ s: String?) -> String {
        guard let d = date(s) else { return "" }
        return fClock.string(from: d)
    }

    static func ago(_ s: String?) -> String {
        guard let d = date(s) else { return "" }

        let cal = Calendar.current
        let secs = Date().timeIntervalSince(d)
        if secs < 60 { return "刚刚" }
        if secs < 3600 { return "\(Int(secs / 60))分钟前" }
        if cal.isDateInToday(d) { return "\(max(1, Int(secs / 3600)))小时前" }
        if cal.isDateInYesterday(d) { return "昨天" }
        let days = cal.dateComponents([.day],
                                      from: cal.startOfDay(for: d),
                                      to: cal.startOfDay(for: Date())).day ?? 99
        if days == 2 { return "前天" }
        if days < 7 { return "\(days)天前" }
        let sameYear = cal.component(.year, from: d) == cal.component(.year, from: Date())
        return sameYear ? fMonthDay.string(from: d) : fYearMonthDay.string(from: d)
    }
}

private var pinyinMemo: [String: String] = [:]

func pinyinInitial(_ text: String) -> String {
    if let hit = pinyinMemo[text] { return hit }
    let value = pinyinInitialRaw(text)
    if pinyinMemo.count > 4000 { pinyinMemo.removeAll(keepingCapacity: true) }
    pinyinMemo[text] = value
    return value
}

private func pinyinInitialRaw(_ text: String) -> String {
    guard !text.isEmpty else { return "#" }
    let first = String(text[text.startIndex])
    if first.range(of: "^[A-Za-z]$", options: .regularExpression) != nil {
        return first.uppercased()
    }
    var latin = first.applyingTransform(StringTransform.toLatin, reverse: false) ?? first
    latin = latin.applyingTransform(StringTransform.stripDiacritics, reverse: false) ?? latin
    latin = latin.trimmingCharacters(in: .whitespacesAndNewlines)
    if let c = latin.first, c.isLetter { return String(c).uppercased() }
    return "#"
}

struct HairLine: View {
    var inset: CGFloat = 0
    var trailingInset: CGFloat = 0
    var color: Color = C.hairline
    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: 0.5)
            .padding(.leading, inset)
            .padding(.trailing, trailingInset)
    }
}

struct Chevron: View {
    var size: CGFloat = 9
    var line: CGFloat = 1.6
    var color: Color = C.arrow
    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: size, y: 0))
            p.addLine(to: CGPoint(x: size, y: size))
        }
        .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .square, lineJoin: .miter))
        .frame(width: size, height: size)
        .rotationEffect(.degrees(45))
        .frame(width: size * 1.4, height: size * 1.4)
    }
}

enum RichText {
    static func looksLikeCode(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return false }

        if t.unicodeScalars.contains(where: { $0.value >= 0x2E80 }) { return false }
        if t.hasPrefix("```") { return true }
        if line.hasPrefix("  ") || line.hasPrefix("\t") { return true }
        if t.hasSuffix(";") || t.hasSuffix("{") || t.hasSuffix("}") { return true }
        if t.contains("</") || t.contains("/>") || t.contains("()") { return true }
        return false
    }

    static func lines(_ raw: String, size: CGFloat) -> AttributedString {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let mono = Font.system(size: max(11, size - 1.5), design: .monospaced)

        let base = pf(size)
        var out = AttributedString()
        let arr = s.split(separator: "\n", omittingEmptySubsequences: false)
        for (i, sub) in arr.enumerated() {
            let line = String(sub)
            if looksLikeCode(line) {
                var seg = AttributedString(line)
                seg.font = mono
                out += seg
            } else {
                var seg = linkified(line)
                seg.font = base
                out += seg
            }
            if i < arr.count - 1 { out += AttributedString("\n") }
        }
        return out
    }

    static func linkified(_ s: String) -> AttributedString {
        var out = AttributedString()
        let src = s as NSString
        let pattern = "(?:https?://|www\\.)[^\\s，。、）)】」]+"
            + "|(?:[A-Za-z0-9-]+\\.)+(?:com|cn|net|org|io|cc|me|tv|xyz|top|vip|shop|info|edu|gov|co|app|dev)"
            + "(?:/[^\\s，。、）)】」]*)?"
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return AttributedString(s)
        }
        var cursor = 0
        re.enumerateMatches(in: s, range: NSRange(location: 0, length: src.length)) { m, _, _ in
            guard let m = m else { return }
            if m.range.location > cursor {
                out += AttributedString(src.substring(with: NSRange(location: cursor,
                                                                    length: m.range.location - cursor)))
            }
            var token = src.substring(with: m.range)

            let trailing = ".,;:!?)]}>\"'"
            var tail = ""
            while let last = token.last, trailing.contains(last) {
                tail = String(last) + tail
                token.removeLast()
            }
            let full = token.lowercased().hasPrefix("http") ? token : "http://" + token
            var seg = AttributedString(token)
            if let u = URL(string: full) {

                if !looksBadLink(u) {
                    seg.link = u
                    seg.foregroundColor = Color.dyn(0x576B95, 0x7D90B8)
                }
            }
            out += seg
            if !tail.isEmpty { out += AttributedString(tail) }
            cursor = m.range.location + m.range.length
        }
        if cursor < src.length { out += AttributedString(src.substring(from: cursor)) }
        return out
    }

    static func looksBadLink(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        let badInHost = ["casino", "poker", "baccarat", "roulette", "gambling", "lottery",
                         "jackpot", "porn", "xxx", "hentai", "onlyfans", "escort",
                         "cocaine", "heroin"]
        for w in badInHost where host.contains(w) { return true }
        for lb in host.split(separator: ".") {
            let s = String(lb)
            if ["bet", "sex", "xxx", "porn", "av", "jav", "toto", "adult"].contains(s) { return true }
            if s.range(of: #"^(18|91|av|jav)?(av|jav|porn|xxx|sex)\d*$"#,
                       options: .regularExpression) != nil { return true }
        }
        let path = (url.path + "?" + (url.query ?? "")).lowercased()
        for w in ["/casino", "/bet", "/poker", "/porn", "/xxx", "/sex", "/adult"] where path.contains(w) {
            return true
        }
        return false
    }
}

struct UnreadBadge: View {
    let count: Int

    var border: Color = C.cardBg
    var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : "\(count)")
                .font(pf(12, .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, count > 9 ? 5 : 0)
                .frame(minWidth: 18, minHeight: 18)

                .background(Capsule().fill(C.red))
                .overlay(Capsule().stroke(border, lineWidth: 1.2))
        }
    }
}

struct UnreadDot: View {
    var size: CGFloat = 10

    var border: Color = C.cardBg
    var body: some View {
        Circle()
            .fill(C.red)
            .frame(width: size, height: size)
            .overlay(Circle().stroke(border, lineWidth: 1.2))
    }
}

enum VoicePlayed {
    private static let key = "chris.voice.played"
    private static let cap = 500

    static func isPlayed(_ id: String) -> Bool {
        if id.isEmpty { return true }
        return list().contains(id)
    }

    static func markPlayed(_ id: String) {
        guard !id.isEmpty else { return }
        var arr = list()
        arr.removeAll { $0 == id }
        arr.append(id)
        if arr.count > cap { arr.removeFirst(arr.count - cap) }
        UserDefaults.standard.set(arr, forKey: key)
    }

    private static func list() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }
}

enum VoiceText {
    private static let key = "chris.voice.text"
    private static let orderKey = "chris.voice.text.order"
    private static let cap = 300

    static func get(_ id: String) -> String? {
        guard !id.isEmpty else { return nil }
        return map()[id]
    }

    static func set(_ id: String, _ text: String) {
        guard !id.isEmpty, !text.isEmpty else { return }
        var m = map()
        m[id] = text
        var order = UserDefaults.standard.stringArray(forKey: orderKey) ?? []
        order.removeAll { $0 == id }
        order.append(id)
        while order.count > cap {
            let old = order.removeFirst()
            m.removeValue(forKey: old)
        }
        UserDefaults.standard.set(m, forKey: key)
        UserDefaults.standard.set(order, forKey: orderKey)
    }

    private static func map() -> [String: String] {
        (UserDefaults.standard.dictionary(forKey: key) as? [String: String]) ?? [:]
    }
}

enum IconOverrides {
    static var map: [String: String] = [:]

    static func custom(_ key: String) -> String? {
        if let v = map[key], !v.isEmpty { return v }
        return nil
    }

    private static func keyOf(_ markup: String) -> String? {
        guard let r = markup.range(of: "data-key=\"") else { return nil }
        let rest = markup[r.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        let k = String(rest[rest.startIndex..<end])
        return k.isEmpty ? nil : k
    }

    static func markup(_ builtin: String) -> String {
        if let k = keyOf(builtin), let v = custom(k) { return v }
        return builtin
    }
}

struct FlexIcon: View {
    var custom: String?
    var size: CGFloat
    var color: Color
    var symbol: String
    var weight: Font.Weight = .regular

    var body: some View {
        if let v = custom, !v.isEmpty {
            if v.hasPrefix("<svg") {

                SVGIcon(markup: v, size: size, color: color, direct: true)
            } else if v.hasPrefix("http") || v.hasPrefix("/uploads") || v.hasPrefix("data:") {
                RemoteImage(path: v).frame(width: size, height: size)
            } else {
                Text(v)
                    .font(.system(size: size * 0.86))
                    .foregroundColor(color)
                    .frame(width: size, height: size)
            }
        } else {
            Image(systemName: symbol)
                .font(.system(size: size, weight: weight))
                .foregroundColor(color)
                .frame(width: size, height: size)
        }
    }
}

struct HidesTabBar: ViewModifier {
    @EnvironmentObject var app: AppState

    func body(content: Content) -> some View {
        content
            .onAppear { app.tabBarDepth += 1 }
            .onDisappear { app.tabBarDepth = max(0, app.tabBarDepth - 1) }
    }
}

extension View {
    func hidesTabBar() -> some View { modifier(HidesTabBar()) }
}

/// 小程序的统一悬浮控制：右侧只有一个大圆点和三个点。
/// 外层页面不画导航栏、标题栏或第二层窗口，网页/游戏内容直接铺满全屏。
struct GameWindowCapsule: View {
    var onMenu: () -> Void
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onMenu) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 46, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Tr("更多"))

            Rectangle()
                .fill(Color.white.opacity(0.24))
                .frame(width: 0.5, height: 19)

            Button(action: onClose) {
                ZStack {
                    Circle()
                        .stroke(Color.white, lineWidth: 1.7)
                        .frame(width: 20, height: 20)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 8, height: 8)
                }
                .frame(width: 48, height: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Tr("关闭"))
        }
        .background(Capsule(style: .continuous).fill(Color.black.opacity(0.38)))
        .overlay(Capsule(style: .continuous).stroke(Color.white.opacity(0.20), lineWidth: 0.6))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
    }
}

struct TapAvatarCard: ViewModifier {
    @Binding var cardUser: User?

    @State private var nextChat: Chat?
    @State private var nextMoments: User?

    func body(content: Content) -> some View {
        content
            .navigationDestination(isPresented: Binding(
                get: { cardUser != nil },
                set: { if !$0 { cardUser = nil } }
            )) {
                if let u = cardUser {
                    ContactCardView(user: u,
                                    onOpenChat: { chat in
                                        cardUser = nil
                                        nextChat = chat
                                    },
                                    onOpenMoments: { _ in
                                        nextMoments = u
                                        cardUser = nil
                                    })
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { nextChat != nil },
                set: { if !$0 { nextChat = nil } }
            )) {
                if let c = nextChat { ChatDetailView(chat: c) }
            }
            .navigationDestination(isPresented: Binding(
                get: { nextMoments != nil },
                set: { if !$0 { nextMoments = nil } }
            )) {
                if let t = nextMoments { MomentsView(target: t) }
            }
    }
}

struct ZoomableRemoteImage: View {
    var path: String

    var onDoubleTap: (() -> Void)? = nil
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero
    @State private var dragStart: CGSize = .zero

    private var magnify: some Gesture {
        MagnificationGesture()
            .onChanged { v in scale = min(4, max(1, baseScale * v)) }
            .onEnded { _ in
                baseScale = scale
                if scale <= 1.02 {
                    withAnimation(.easeOut(duration: 0.2)) {
                        scale = 1; baseScale = 1; offset = .zero; baseOffset = .zero
                    }
                }
            }
    }
    private var doubleTap: some Gesture {
        TapGesture(count: 2).onEnded {
            onDoubleTap?()
            withAnimation(.easeOut(duration: 0.22)) {
                if scale > 1.02 {
                    scale = 1; baseScale = 1; offset = .zero; baseOffset = .zero
                } else {
                    scale = 2.5; baseScale = 2.5
                }
            }
        }
    }
    private var pan: some Gesture {
        DragGesture()
            .onChanged { v in
                guard scale > 1.02 else { return }
                offset = CGSize(width: dragStart.width + v.translation.width,
                                height: dragStart.height + v.translation.height)
            }
            .onEnded { _ in
                baseOffset = offset
                dragStart = offset
            }
    }

    var body: some View {
        GeometryReader { geo in
            RemoteImage(path: path, mode: .fit)
                .frame(width: geo.size.width, height: geo.size.height)
                .scaleEffect(scale)
                .offset(offset)
        }
        .contentShape(Rectangle())
        .gesture(magnify)
        .simultaneousGesture(doubleTap)

        .simultaneousGesture(pan, including: scale > 1.02 ? .all : .none)
        .onChange(of: scale) { s in
            if s <= 1.02 { dragStart = .zero; baseOffset = .zero }
            else { dragStart = baseOffset }
        }
    }
}

struct PhotoPager: View {
    let paths: [String]
    let startIndex: Int

    struct Item: Identifiable {
        let id = UUID()
        var paths: [String]
        var index: Int
    }

    var showActions: Bool = false

    var onLongPress: (() -> Void)? = nil
    var onClose: () -> Void

    @EnvironmentObject private var app: AppState
    @State private var index = 0
    @State private var saved = false
    @State private var showForward = false

    @State private var shareItems: [Any] = []
    @State private var showShare = false

    @State private var tapCloseTask: Task<Void, Never>? = nil

    private var currentPath: String? {
        (index >= 0 && index < paths.count) ? paths[index] : nil
    }

    var body: some View {
        GeometryReader { geo in
        ZStack {

            Color.black.ignoresSafeArea()
            if let p = currentPath {
                RemoteImage(path: p, mode: .fill, maxSide: 600)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .blur(radius: 34)
                    .opacity(0.55)
                    .overlay(Color.black.opacity(0.18))
                    .ignoresSafeArea()
                    .animation(.easeOut(duration: 0.2), value: index)
            }

            TabView(selection: $index) {
                ForEach(paths.indices, id: \.self) { i in
                    ZStack {
                        Color.black
                        if abs(i - index) <= 1 {
                            ZoomableRemoteImage(path: paths[i], onDoubleTap: {
                                tapCloseTask?.cancel()
                            })
                        }
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            .onTapGesture {
                tapCloseTask?.cancel()
                tapCloseTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    if !Task.isCancelled { onClose() }
                }
            }

            VStack(spacing: 0) {

                if showActions { topBar }
                Spacer(minLength: 0)
                Text(saved ? Tr("已保存到相册") : (paths.count > 1 ? "\(index + 1) / \(paths.count)" : ""))
                    .font(pfExact(showActions ? 13 : 14))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.bottom, showActions ? 10 : 26)
                if showActions { actionBar }
            }
        }
        .contentShape(Rectangle())

        .onTapGesture { if !showActions { onClose() } }
        .onLongPressGesture {
            if let cb = onLongPress { cb(); return }
            save(index)
        }
        .onAppear { index = min(max(0, startIndex), max(0, paths.count - 1)) }

        .sheet(isPresented: $showForward) {
            if let p = currentPath {
                ForwardPickerView(items: [ForwardItem(kind: "image", content: p)]) { }
                    .environmentObject(app)
            }
        }
        .sheet(isPresented: $showShare) { ShareSheet(items: shareItems) }
        }
    }

    private var topBar: some View {
        HStack {
            Button { onClose() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.black.opacity(0.35)))
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }

    private var actionBar: some View {
        HStack(spacing: 0) {
            barButton(Tr("转发"), "arrowshape.turn.up.right") { showForward = true }
            barButton(Tr("分享"), "square.and.arrow.up") { shareCurrent() }
            barButton(saved ? Tr("已保存") : Tr("保存"),
                      saved ? "checkmark.circle" : "square.and.arrow.down") { save(index) }
        }
        .padding(.bottom, L.safeBottom)
        .background(
            LinearGradient(colors: [Color.black.opacity(0.0), Color.black.opacity(0.62)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func barButton(_ title: String, _ icon: String, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                Text(title).font(pfExact(11.5))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func save(_ i: Int) {
        guard i >= 0, i < paths.count else { return }
        let path = paths[i]
        Task {
            var image: UIImage? = ImageStore.shared.get(path)
            if image == nil, let url = API.shared.assetURL(path) {
                if let data = try? await API.shared.imageData(url) {
                    image = RemoteImage.downsampled(data, maxSide: 1600)
                }
            }
            guard let img = image else { return }
            UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
            saved = true
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            saved = false
        }
    }

    private func shareCurrent() {
        guard let path = currentPath else { return }
        Task {
            var items: [Any] = []

            var data = LocalStore.read(path)
            if data == nil, let url = API.shared.assetURL(path) {
                data = try? await API.shared.imageData(url)
            }
            if let d = data, !d.isEmpty {
                let ext = (path as NSString).pathExtension.isEmpty ? "jpg" : (path as NSString).pathExtension
                let f = FileManager.default.temporaryDirectory
                    .appendingPathComponent("share-\(UUID().uuidString).\(ext)")
                if (try? d.write(to: f)) != nil { items = [f] }
            }
            if items.isEmpty, let img = ImageStore.shared.get(path) { items = [img] }
            if items.isEmpty, let url = API.shared.assetURL(path) { items = [url] }
            guard !items.isEmpty else {
                app.show(Tr("这张图暂时分享不了，先保存到相册再发"))
                return
            }
            shareItems = items
            showShare = true
        }
    }
}

enum LoginTheme {
    static var accent = Color(hexString: "#19A47A")
    static var accent2 = Color(hexString: "#007AFF")
    static var disabledAccent = Color(hexString: "#B2E4C8")
    static var disabledGray = Color(hexString: "#C7C7CC")
    static var text: Color? = nil
    static var sub: Color? = nil

    static var darkText: Color? = nil
    static var pageBg: Color? = nil

    static var card: Color? = nil

    static var darkBg: Color? = nil
    static var darkCard: Color? = nil

    static func ink(_ scheme: ColorScheme) -> Color {
        if scheme == .dark, let d = darkText { return d }
        if let t = text { return t }
        return Color.primary
    }

    static func bg(_ scheme: ColorScheme) -> Color {
        if scheme == .dark, let d = darkBg { return d }
        if let b = pageBg { return b }
        return Color(.systemBackground)
    }

    static func cardBg(_ scheme: ColorScheme) -> Color {
        if scheme == .dark, let d = darkCard { return d }
        if let c = card { return c }
        return scheme == .dark ? Color(hex: 0x1C1C1E) : Color.white
    }

    static func onBg(_ scheme: ColorScheme) -> Color {
        if scheme == .dark && darkBg != nil { return inkSub(scheme) }
        if pageBg != nil { return .white }
        return ink(scheme)
    }

    static func onBgSub(_ scheme: ColorScheme) -> Color {
        if scheme == .dark && darkBg != nil { return inkSub(scheme) }
        if pageBg != nil { return Color.white.opacity(0.82) }
        return inkSub(scheme)
    }

    static func inkSub(_ scheme: ColorScheme) -> Color {
        if let s = sub { return s }
        if text != nil || darkText != nil { return ink(scheme).opacity(0.62) }
        return Color.secondary
    }

    static var bgImage = ""

    static var terms = ""
    static var privacy = ""

    static func text(kind: Int) -> String {
        let custom = (kind == 0 ? terms : privacy).trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { return custom }
        return kind == 0
            ? "1. 星言用于个人和团队即时通信，请勿传播违法、侵权或骚扰内容。\n2. 你对发送的内容和上传的文件负责；管理员可依法处理举报并限制违规账号。\n3. 为提供音视频、AI、推送和支付功能，必要信息会由相应服务商处理，具体见隐私政策。\n4. 修改密码或注销账号后，相关登录令牌会立即失效。"
            : "星言仅在提供功能所需范围内处理：账号与安全信息（手机号、星言号、设备型号、系统版本、设备标识、IP 和推送令牌）；资料与内容（昵称、头像、地区、签名、聊天、朋友圈、收藏及主动上传的媒体）；位置信息（使用附近或共享位置时）；实名、支付与交易信息（姓名、证件哈希与掩码、银行卡后四位、订单和账单）；以及必要的崩溃和性能诊断。\n\n音视频通话使用腾讯云 TRTC，AI 功能启用时使用 DeepSeek，通知使用 Apple APNs，支付使用支付宝或后台配置的支付/短信服务；仅在对应功能启用或使用时处理必要信息。\n\n我们不会出售个人信息，也不会用于跨 App 广告追踪。账号注销后，账号资料、聊天、媒体、朋友圈和收藏会立即清理；依法必须保留的交易、财务和安全审计记录会在法定期限内保留。"
    }

    static func apply(_ b: BrandInfo?) {
        guard let l = b?.login else { return }
        if let v = l.accent, !v.isEmpty { accent = Color(hexString: v) }
        if let v = l.accent2, !v.isEmpty { accent2 = Color(hexString: v) }
        if let v = l.disabledAccent, !v.isEmpty { disabledAccent = Color(hexString: v) }
        if let v = l.disabledGray, !v.isEmpty { disabledGray = Color(hexString: v) }
        if let v = l.text, !v.isEmpty { text = Color(hexString: v) }
        if let v = l.sub, !v.isEmpty { sub = Color(hexString: v) }
        if let v = l.darkText, !v.isEmpty { darkText = Color(hexString: v) }
        if let v = l.bg, !v.isEmpty { pageBg = Color(hexString: v) }
        if let v = l.card, !v.isEmpty { card = Color(hexString: v) }
        if let v = l.darkBg, !v.isEmpty { darkBg = Color(hexString: v) }
        if let v = l.darkCard, !v.isEmpty { darkCard = Color(hexString: v) }
        bgImage = l.bgImage ?? ""
        terms = l.terms ?? ""
        privacy = l.privacy ?? ""
    }
}

enum TransferTheme {
    static var accent: Color { LoginTheme.accent2 }
    static var success: Color { Color(hexString: "#34C759") }
}

struct SavedAccount: Codable, Identifiable, Hashable {
    var username: String
    var nickname: String
    var avatar: String
    var id: String { username }
}

enum AccountStore {
    private static let listKey = "chris.accounts"
    static let maxCount = 3

    static func load() -> [SavedAccount] {
        guard let raw = UserDefaults.standard.string(forKey: listKey),
              let data = raw.data(using: .utf8),
              let list = try? JSONDecoder().decode([SavedAccount].self, from: data) else { return [] }
        return Array(list.prefix(maxCount))
    }

    static func saveList(_ list: [SavedAccount]) {
        let trimmed = Array(list.prefix(maxCount))
        if let data = try? JSONEncoder().encode(trimmed), let s = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(s, forKey: listKey)
        }
    }

    @discardableResult
    static func upsert(username: String, nickname: String, avatar: String, token: String) -> [SavedAccount] {
        var list = load().filter { $0.username != username }
        list.insert(SavedAccount(username: username, nickname: nickname, avatar: avatar), at: 0)
        saveList(list)
        if !token.isEmpty { Keychain.set(token, for: "token." + username) }
        return Array(list.prefix(maxCount))
    }

    static func token(for username: String) -> String {
        return Keychain.get("token." + username) ?? ""
    }

    /// 用户修改星言号后，本机账号列表和钥匙串必须一起迁移；
    /// 否则旧星言号会留在切号页，新星言号又可能找不到原登录态。
    @discardableResult
    static func rename(from oldUsername: String, to newUsername: String,
                       nickname: String, avatar: String, token: String) -> [SavedAccount] {
        let old = oldUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let new = newUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !new.isEmpty else { return load() }

        let previousToken = old.isEmpty ? "" : tokenFor(old)
        var list = load().filter {
            $0.username.caseInsensitiveCompare(old) != .orderedSame &&
            $0.username.caseInsensitiveCompare(new) != .orderedSame
        }
        list.insert(SavedAccount(username: new, nickname: nickname, avatar: avatar), at: 0)
        saveList(list)

        if !old.isEmpty, old.caseInsensitiveCompare(new) != .orderedSame {
            Keychain.remove("token." + old)
            UserDefaults.standard.removeObject(forKey: "chris.lastUserJSON." + old.lowercased())
        }
        let migratedToken = token.isEmpty ? previousToken : token
        if !migratedToken.isEmpty {
            Keychain.set(migratedToken, for: "token." + new)
        }
        return Array(list.prefix(maxCount))
    }

    private static func tokenFor(_ username: String) -> String {
        Keychain.get("token." + username) ?? ""
    }

    static func remove(username: String) {
        saveList(load().filter { $0.username != username })
        Keychain.remove("token." + username)
    }
}
