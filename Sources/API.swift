import Foundation
import UIKit
import SwiftUI
import AVFoundation
import CryptoKit
import Security

struct User: Codable, Identifiable, Hashable {
    var id: String

    var realName: String?
    var requestId: String?
    var moodText: String?
    var moodIcon: String?
    var moodColor: String?
    var moodColor2: String?

    var moodLabel: String?
    var moodCaption: String?

    var moodExpiresAt: Double?

    var moodLikes: [String]?
    var moodLikeCount: Int?
    var username: String?

    var usernameUpdatedAt: String?

    var interests: [String]?

    var needsOnboarding: Bool?
    var nickname: String?
    var avatar: String?
    var bio: String?
    var gender: String?
    var region: String?
    var phone: String?
    var status: String?
    var chatBackground: String?

    var chatBackgrounds: [String: String]?
    var birthday: String?
    var momentCover: String?

    var patText: String?
    var bot: Bool?

    var ops: Bool?
    var online: Bool?
    var balance: Double?

    var relation: String?

    var momentCount: Int?

    var momentsRange: String?

    var requestMessage: String?

    var remark: String?

    var realNickname: String?

    var tags: [String]?

    var star: Bool?

    var block: Bool?

    var noMoments: Bool?

    var addedAt: String?
    var source: String?

    var mutualGroups: Int?

    var alias: String?

    var qqLevel: Int?

    var memberTier: String?
    var memberShort: String?
    var memberColor: String?
    var memberColor2: String?

    var name: String {
        if let n = nickname, !n.isEmpty { return n }
        if let u = username, !u.isEmpty { return u }
        return "未知用户"
    }

    var groupName: String {
        if let a = alias, !a.isEmpty { return a }
        return name
    }
    var avatarPath: String { avatar ?? "" }
}

struct LastMessage: Codable, Hashable {
    var id: String?
    var senderId: String?
    var senderName: String?
    var kind: String?
    var preview: String?
    var createdAt: String?

    var mentionMe: Bool?
}

struct Chat: Codable, Identifiable, Hashable {
    var id: String
    var type: String?
    var title: String?
    var avatar: String?

    var moodIcon: String?
    var moodText: String?
    var unread: Int?
    var pinned: Bool?
    var botRank: Int?

    var bot: String?

    var sysTeam: Bool?

    var oaId: String?

    var oaDigest: Bool?

    var qqLevel: Int?
    var memberCount: Int?

    var memberIds: [String]?
    var lastMessage: LastMessage?
    var updatedAt: String?

    var muted: Bool?

    var burn: Bool?

    var flagged: Bool?

    var ownerId: String?

    var announce: String?

    var muteAll: Bool?
    var meMuted: Bool?

    var memberTier: String?
    var memberShort: String?
    var memberColor: String?
    var memberColor2: String?

    var name: String {

        let clean = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "会话" : clean
    }
    var unreadCount: Int { unread ?? 0 }
}

struct AITokenPlan: Decodable, Identifiable, Hashable {
    var id: String
    var name: String
    var tokens: Int
    var bonus: Int
    var price: Double
    var tag: String?
    var desc: String?

    var granted: Int { max(0, tokens) + max(0, bonus) }
}

struct AITokenPurchase: Decodable, Identifiable, Hashable {
    var id: String
    var name: String
    var paid: Double
    var granted: Int
    var purchasedAt: String
}

struct AIWalletStatus: Decodable {
    var name: String?
    var model: String?
    var voice: String?
    var voices: [AIVoiceOption]?
    var tier: String?
    var tierName: String?
    var voiceCall: Bool?
    var longContext: Bool?
    var extendedOutput: Bool?
    var learning: Bool?
    var learned: Int?
    var tokens: Int
    var used: Int
    var plans: [AITokenPlan]
    var purchases: [AITokenPurchase]
    var features: [String]?
}

struct AITokenPurchaseResult: Decodable {
    var tokens: Int
    var duplicate: Bool?
}

struct AIVoiceOption: Decodable, Identifiable, Hashable {
    var id: String
    var name: String
    var desc: String?
}

struct AILearningStatus: Decodable {
    var learning: Bool
    var learned: Int
}

struct AITTSResult: Decodable {
    var audio: String
    var mime: String
    var voice: String?
    var usage: Int?
    var cached: Bool?
}

func imageRefPath(_ content: String) -> String {
    let b = content
    guard b.hasPrefix("{"), let d = b.data(using: .utf8),
          let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
          let u = o["url"] as? String, !u.isEmpty else { return b }
    return u
}

struct QuoteRef: Codable, Hashable {
    var id: String?
    var who: String?
    var text: String?

    var kind: String?

    var thumb: String?

    var refId: String { id ?? "" }
    var sender: String { who ?? "" }
    var summary: String { text ?? "" }
    var thumbPath: String { thumb ?? "" }
}

struct Message: Codable, Identifiable, Hashable {
    var id: String
    var chatId: String?
    var seq: Int?
    var senderId: String?
    var kind: String?
    var content: String?
    var createdAt: String?
    var recalled: Bool?

    var quote: QuoteRef?

    var burn: Bool?

    var burnAt: String?
    var senderName: String?
    var senderAvatar: String?

    var call: CallMeta?

    var mentions: [String]?

    var imgW: Int?
    var imgH: Int?

    var kindName: String { kind ?? "text" }
    var body: String { content ?? "" }
    var isRecalled: Bool { recalled ?? false }
    var imagePath: String { imageRefPath(body) }

    var imagePixelSize: CGSize? {
        if let w = imgW, let h = imgH, w > 1, h > 1 { return CGSize(width: CGFloat(w), height: CGFloat(h)) }
        let b = body
        if b.hasPrefix("{"), let d = b.data(using: .utf8),
           let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            let w = (o["w"] as? Int) ?? Int((o["w"] as? Double) ?? 0)
            let h = (o["h"] as? Int) ?? Int((o["h"] as? Double) ?? 0)
            if w > 1, h > 1 { return CGSize(width: w, height: h) }
        }
        return nil
    }

    func mentionsUser(_ userId: String) -> Bool {
        guard !userId.isEmpty, let ids = mentions else { return false }
        return ids.contains(userId)
    }

    private var patInfo: [String: Any]? {
        guard kindName == "pat",
              let d = body.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        return o
    }
    var patFrom: String { (patInfo?["from"] as? String) ?? "" }
    var patTo: String { (patInfo?["to"] as? String) ?? "" }
    var patFromName: String { (patInfo?["fn"] as? String) ?? "" }
    var patToName: String { (patInfo?["tn"] as? String) ?? "" }

    var patTail: String { (patInfo?["tt"] as? String) ?? "" }

    func patText(myId: String) -> String {
        let fn = patFromName, tn = patToName

        let tail = patTail.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetTail = tail.isEmpty ? "" : ("的" + tail)
        let meTail = tail.isEmpty ? "我" : ("我的" + tail)
        if !patFrom.isEmpty, patFrom == myId, !tn.isEmpty { return "我拍了拍“" + tn + "”" + targetTail }
        if !patTo.isEmpty, patTo == myId, !fn.isEmpty { return "“" + fn + "”拍了拍" + meTail }
        if !fn.isEmpty, !tn.isEmpty { return "“" + fn + "”拍了拍“" + tn + "”" + targetTail }
        return "拍了拍"
    }

    var isCallRecord: Bool {
        if call != nil { return true }
        let t = body
        return t.contains("通话") || t == "已取消" || t == "未接听" || t == "对方无应答"
            || t == "对方已拒绝" || t == "对方忙线中" || t == "对方不在线"
    }

    var isVideoCall: Bool { (call?.media ?? "").contains("video") || body.contains("视频") }

    var callFrom: String { call?.from ?? "" }

    var isBadCallRecord: Bool {
        guard isCallRecord else { return false }
        let t = body + " " + (call?.state ?? "")
        let words = ["未接听", "已拒绝", "已取消", "无应答", "不在线", "忙线", "未接通",
                     "无人接听", "cancel", "reject", "timeout", "missed", "busy", "offline"]
        return words.contains { t.contains($0) }
    }

    var callText: String {
        var t = body.trimmingCharacters(in: .whitespacesAndNewlines)
        for pre in ["视频通话结束", "通话结束"] where t.hasPrefix(pre) {
            if let r = t.range(of: "时长") { t = "通话时长" + String(t[r.upperBound...]) }
            break
        }
        if t.hasPrefix("视频通话时长") { t = "通话时长" + String(t.dropFirst("视频通话时长".count)) }
        if t.hasPrefix("通话时长") {
            let rest = t.dropFirst("通话时长".count).trimmingCharacters(in: .whitespaces)
            let p = rest.split(separator: ":")
            if p.count == 2, let mm = Int(p[0]), let ss = Int(p[1]) {
                t = String(format: "通话时长 %02d:%02d", mm, ss)
            }
        }
        return t
    }
}

struct CallMeta: Codable, Hashable {
    var media: String?
    var state: String?
    var secs: Int?

    var from: String?
    var to: String?
}

struct NearbyPerson: Decodable, Identifiable, Hashable {
    var id: String
    var nickname: String?
    var avatar: String?
    var gender: String?
    var region: String?
    var bio: String?
    var moodText: String?
    var moments: Int?
    var online: Bool?
    var friend: Bool?

    var km: Double?

    var minutes: Int?

    var name: String { (nickname?.isEmpty == false) ? nickname! : "附近的人" }
    var isFemale: Bool { (gender ?? "") == "female" }

    var distanceText: String {
        guard let km = km else { return "" }
        if km < 1 {
            let m = max(100, Int(ceil(km * 1000 / 100)) * 100)
            return "\(m)米以内"
        }
        return String(format: "%.1f公里以内", km)
    }
    var timeText: String {
        guard let m = minutes else { return "" }
        if m <= 0 { return "刚刚" }
        if m < 60 { return "\(m) 分钟前" }
        return "\(m / 60) 小时前"
    }
}

private struct NearbyPayload: Decodable {
    var people: [NearbyPerson]

    var wider: Int?
    var maxKm: Double?
}
private struct NearbyHelloPayload: Decodable { var chatId: String?; var text: String? }

struct ShakeResult: Decodable {
    var matched: NearbyPerson?

    var shaking: Int?
}

private struct LivePayload: Decodable { var rooms: [LiveRoom] }
private struct LiveJoinPayload: Decodable { var watching: Int? }
private struct LiveLikePayload: Decodable { var likes: Int? }
private struct GamesPayload: Decodable { var items: [MiniGame] }

struct MiniGame: Decodable, Identifiable, Hashable {
    var id: String
    var label: String?
    var desc: String?
    var icon: String?
    var kind: String?
    var enabled: Bool?

    var url: String?
}

struct FeedStyle: Decodable, Hashable {
    var avatar: Double?
    var nameSize: Double?
    var descSize: Double?
    var musicSize: Double?
    var railIcon: Double?
    var railGap: Double?
    var padBottom: Double?
}

struct FeedFlags: Decodable, Hashable {
    var allowPublish: Bool?
    var allowTrim: Bool?
    var showRail: Bool?
    var autoPlay: Bool?
}

private struct FeedPayload: Decodable {
    var items: [FeedItem]
    var style: FeedStyle?
    var flags: FeedFlags?
}
private struct FeedLikePayload: Decodable { var liked: Bool?; var likes: Int? }
private struct FeedCommentPayload: Decodable { var comments: Int? }
private struct FeedCommentsPayload: Decodable { var comments: [FeedCommentItem]?; var count: Int? }
private struct FeedSeriesPayload: Decodable { var series: String?; var name: String?; var items: [FeedItem]? }
private struct FeedFavoritePayload: Decodable { var favorited: Bool?; var favorites: Int? }

struct FeedCommentItem: Decodable, Hashable, Identifiable {
    var id: String
    var name: String?
    var avatar: String?
    var text: String?
    var at: String?
}
private struct FeedPublishPayload: Decodable { var id: String?; var video: String? }
private struct FeedTrimPayload: Decodable { var url: String?; var width: Int?; var height: Int? }

struct MomentLike: Codable, Hashable {
    var userId: String?
    var nickname: String?
    var at: String?
}

struct MomentComment: Codable, Hashable {
    var id: String?
    var userId: String?
    var nickname: String?
    var replyToName: String?
    var content: String?
    var at: String?
}

struct Moment: Codable, Identifiable, Hashable {
    var id: String
    var authorId: String?
    var author: User?
    var content: String?
    var images: [String]?

    var imageSizes: [String: [Int]]?

    var video: String?
    var videoCover: String?
    var videoSeconds: Int?
    var videoW: Int?
    var videoH: Int?

    var location: String?

    var pinned: Bool?
    var createdAt: String?
    var likes: [MomentLike]?
    var likedByMe: Bool?
    var comments: [MomentComment]?
    var mine: Bool?
}

struct MomentNotice: Decodable, Identifiable, Hashable {
    var id: String

    var kind: String?
    var at: String?
    var momentId: String?
    var commentId: String?

    var text: String?

    var preview: String?
    var thumb: String?
    var userId: String?
    var name: String?
    var avatar: String?

    var deleted: Bool?

    init(id: String, kind: String? = nil, at: String? = nil, momentId: String? = nil,
         commentId: String? = nil, text: String? = nil, preview: String? = nil,
         thumb: String? = nil, userId: String? = nil, name: String? = nil,
         avatar: String? = nil, deleted: Bool? = nil) {
        self.id = id; self.kind = kind; self.at = at; self.momentId = momentId
        self.commentId = commentId; self.text = text; self.preview = preview
        self.thumb = thumb; self.userId = userId; self.name = name
        self.avatar = avatar; self.deleted = deleted
    }

    init(json: [String: Any]) {
        self.init(id: (json["id"] as? String) ?? UUID().uuidString,
                  kind: json["kind"] as? String,
                  at: json["at"] as? String,
                  momentId: json["momentId"] as? String,
                  commentId: json["commentId"] as? String,
                  text: json["text"] as? String,
                  preview: json["preview"] as? String,
                  thumb: json["thumb"] as? String,
                  userId: json["userId"] as? String,
                  name: json["name"] as? String,
                  avatar: json["avatar"] as? String,
                  deleted: json["deleted"] as? Bool)
    }
}

private struct MomentNoticesPayload: Decodable {
    var items: [MomentNotice]?
    var unread: Int?
    var total: Int?
}

private struct ChatsPayload: Decodable { var chats: [Chat] }
private struct ChatPayload: Decodable { var chat: Chat? }
private struct ChatMembersPayload: Decodable {
    var members: [User]?
    var ownerId: String?
    var createdAt: String?
    var avatar: String?
}
private struct PinPayload: Decodable { var pinned: Bool?; var forced: Bool? }
private struct ChatInfoPayload: Decodable { var name: String?; var announce: String? }
private struct MutePayload: Decodable { var muted: Bool? }
private struct GroupActionPayload: Decodable { var memberCount: Int?; var left: Bool?; var dismissed: Bool? }
private struct SearchPayload: Decodable {
    var messages: [FoundMessage]
    var hasMore: Bool?
    var total: Int?
}
private struct BankCardsPayload: Decodable { var cards: [BankCard]? }
private struct SendPayload: Decodable { var sent: Bool?; var id: String? }

    struct BankCard: Decodable, Identifiable, Hashable {

        var type: String?
        var noPin: Bool?
        var single: Double?
        var day: Double?
        var phoneMask: String?
    var id: String
    var bank: String?
    var holder: String?
    var tail: String?

    var title: String { (bank ?? "银行卡") + " 尾号" + (tail ?? "****") }
}

struct FoundMessage: Decodable, Identifiable, Hashable {
    var id: String
    var seq: Int?
    var kind: String?
    var content: String?
    var createdAt: String?
    var senderId: String?
    var senderName: String?
    var senderAvatar: String?
}

struct ChatHistorySearchResult {
    var messages: [FoundMessage]
    var hasMore: Bool
    var total: Int
}
private struct UsersPayload: Decodable { var users: [User] }
private struct MessagesPayload: Decodable {
    var chat: Chat?
    var messages: [Message]
    var hasMore: Bool?
}
private struct MessagePayload: Decodable { var message: Message? }
private struct AddFriendPayload: Decodable {
    var accepted: Bool?
    var friend: User?
    var chat: Chat?
}
private struct CreditScorePayload: Decodable { var score: CreditScore }

struct CreditScore: Decodable, Hashable {
    struct Item: Decodable, Hashable {
        var label: String
        var ok: Bool
        var tip: String?
    }
    struct Dim: Decodable, Hashable, Identifiable {
        var key: String
        var label: String
        var score: Int
        var max: Int
        var items: [Item]?
        var id: String { key }
    }
    struct Stats: Decodable, Hashable {
        var deviceCount: Int?
        var sentCount: Int?
        var successCount: Int?
        var expiredCount: Int?
        var ledgerCount: Int?
    }
    var score: Int
    var level: String
    var min: Int
    var max: Int
    var percent: Int
    var updatedAt: String?
    var dims: [Dim]
    var tips: [String]
    var stats: Stats?

    var scoreLimit: ScoreLimit?

    struct ScoreLimit: Decodable, Hashable {

        var score: Int?
        var level: String?

        var single: Double?
        var day: Double?

        var block: Bool?
    }
}
private struct ContactsPayload: Decodable {
    var friends: [User]
    var incoming: [User]?
    var outgoing: [User]?

    var added: [User]?
}
private struct PhoneContactMatchesPayload: Decodable {
    var users: [User]?
}
private struct MePayload: Decodable { var user: User? }
private struct UserPayload: Decodable { var user: User? }
private struct LoginPayload: Decodable { var user: User? }
private struct SessionPayload: Decodable { var authenticated: Bool?; var user: User? }
private struct PhoneCodePayload: Decodable { var sent: Bool?; var devCode: String?; var nickname: String? }
private struct CaptchaPayload: Decodable {
    var id: String?
    var svg: String?
    var required: Bool?
}
private struct PairStartPayload: Decodable { var code: String?; var expiresIn: Int? }
private struct PairStatusPayload: Decodable { var status: String?; var user: User?; var token: String? }
private struct MomentsPayload: Decodable {
    var moments: [Moment]
    var hasMore: Bool?
    var unread: Int?
    var total: Int?

    var noticeUnread: Int?

    var range: String?
}
private struct BrandingPayload: Decodable { var branding: BrandInfo? }
private struct BadgesPayload: Decodable { var badges: [String: String]? }
private struct EndpointsPayload: Decodable { var endpoints: [String]? }

struct PendingCallInfo: Decodable {
    var callId = ""
    var media = "audio"
    var peerId = ""
    var peerName = ""
    var peerAvatar = ""
    var sdp: String? = nil
    var startedAt: Double = 0
}

struct AppUpdateInfo: Decodable, Equatable {
    var version: String?
    var notes: String?
    var force: Bool?
    var url: String?
    var downloadPage: String?
}
struct NoticeInfo: Decodable, Equatable {
    var title: String?
    var content: String?
    var kind: String?
    var startAt: String?
    var endAt: String?
    var minVersion: String?
    var maxVersion: String?
}
private struct VersionPayload: Decodable {
    var app: AppUpdateInfo?
    var notice: NoticeInfo?
}

struct BrandInfo: Decodable, Hashable {
    var appName: String?
    var logo: String?

    var chatBackground: String?
    var fontScale: Double?
    var accentColor: String?

    var iceServers: String?

    var login: LoginBrand?

    var harmonyLogin: LoginBrand?

    var sliderLogin: Bool?

    var splash: String?
}

struct LoginBrand: Decodable, Hashable {
    var accent: String?
    var accent2: String?
    var disabledAccent: String?
    var disabledGray: String?
    var bg: String?
    var card: String?
    var text: String?
    var sub: String?

    var darkText: String?

    var darkBg: String?
    var darkCard: String?
    var bgImage: String?
    var appName: String?
    var subTitle: String?
    var logo: String?
    var terms: String?
    var privacy: String?
}

struct PlusItem: Decodable, Identifiable, Hashable {
    var id: String?
    var label: String?
    var icon: String?
    var action: String?
    var enabled: Bool?
}

struct QuickChip: Codable, Identifiable, Hashable {
    var id: String
    var label: String
    var action: String
    var enabled: Bool

    static let defaults: [QuickChip] = [
        QuickChip(id: "q01", label: "图片", action: "photo", enabled: true),
        QuickChip(id: "q02", label: "拍摄", action: "camera", enabled: true),
        QuickChip(id: "q03", label: "位置", action: "location", enabled: true),
        QuickChip(id: "q04", label: "文件", action: "file", enabled: true),
        QuickChip(id: "q05", label: "转账", action: "transfer", enabled: true),
        QuickChip(id: "q06", label: "红包", action: "redpacket", enabled: true),
        QuickChip(id: "q07", label: "名片", action: "card", enabled: true)
    ]

    static let actions = ["photo", "camera", "location", "file", "transfer", "redpacket",
                          "card", "gift", "music", "videocall", "voice", "favorite"]
    static let actionNames: [String: String] = [
        "photo": "图片", "camera": "拍摄", "location": "位置", "file": "文件",
        "transfer": "转账", "redpacket": "红包", "card": "名片", "gift": "礼物",
        "music": "音乐", "videocall": "视频通话", "voice": "语音输入", "favorite": "收藏"
    ]
}

func chatEntryLabel(_ raw: String?, action: String?) -> String {
    let text = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let act = (action ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let looksEnglish = text.range(of: #"^[A-Za-z0-9_\- ]+$"#, options: .regularExpression) != nil
    if text.isEmpty || looksEnglish || text.lowercased() == act {
        return QuickChip.actionNames[act] ?? Tr("更多")
    }
    return text
}

struct PlusButtonCfg: Codable, Hashable {
    var color: String = ""
    var size: Double = 0
    var image: String = ""
}

struct Gift: Decodable, Identifiable, Hashable {
    var id: String
    var name: String?
    var icon: String?
    var price: Double?
    var category: String?
}

struct StickerPack: Decodable, Hashable {
    var id: String?
    var name: String?
    var icon: String?
    var stickers: [String]?
}

struct StatusItem: Decodable, Hashable {
    var id: String?
    var icon: String?
    var label: String?
    var color: String?
    var color2: String?
}

struct StatusCategory: Decodable, Hashable {
    var id: String?
    var name: String?

    var color: String?
    var enabled: Bool?
    var items: [StatusItem]?
}

struct StatusViewer: Decodable, Hashable {
    var userId: String?
    var name: String?
    var avatar: String?
    var at: String?
}

struct MyStatus: Decodable {
    var alive: Bool?
    var moodText: String?
    var moodIcon: String?
    var moodColor: String?
    var moodColor2: String?
    var moodLabel: String?
    var moodCaption: String?
    var hoursLeft: Int?
    var createdAt: String?
    var viewerCount: Int?
    var views: [StatusViewer]?

    var isAlive: Bool { alive ?? false }

    var shownText: String {
        let cap = (moodCaption ?? "").trimmingCharacters(in: .whitespaces)
        if !cap.isEmpty { return cap }
        return (moodLabel ?? moodText ?? "")
    }
}

enum MoodColor {

    static func isDark(_ hex: String) -> Bool {
        let c = clean(hex)
        guard !c.isEmpty, let v = UInt32(c.dropFirst(), radix: 16) else { return false }
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >> 8) & 0xFF) / 255
        let b = Double(v & 0xFF) / 255
        func lin(_ x: Double) -> Double { x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        let l = 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
        return l < 0.45
    }

    static func clean(_ raw: String?) -> String {
        var s = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s = String(s.dropFirst()) }
        guard s.count == 6, UInt32(s, radix: 16) != nil else { return "" }
        return "#" + s.uppercased()
    }

    static func shift(_ hex: String, to light: Bool) -> String {
        let c = clean(hex)
        guard !c.isEmpty, let v = UInt32(c.dropFirst(), radix: 16) else { return "" }
        var r = Double((v >> 16) & 0xFF)
        var g = Double((v >> 8) & 0xFF)
        var b = Double(v & 0xFF)
        let k = light ? 0.28 : -0.18
        let mix = light ? 255.0 : 0.0
        r += (mix - r) * k
        g += (mix - g) * k
        b += (mix - b) * k
        let out = (UInt32(max(0, min(255, r))) << 16)
            | (UInt32(max(0, min(255, g))) << 8)
            | UInt32(max(0, min(255, b)))
        return String(format: "#%06X", out)
    }
}

struct DiscoverItem: Decodable, Identifiable, Hashable {
    var id: String
    var label: String
    var icon: String?
    var svg: String?
    var color: String?
    var action: String?
    var group: Int?
    var enabled: Bool?
}

private struct StickersPayload: Decodable { var packs: [StickerPack]? }

struct NewsChannel: Decodable, Identifiable, Hashable {
    var id: String
    var label: String
    var desc: String?
}

struct NewsItem: Decodable, Identifiable, Hashable {
    var id: String
    var title: String
    var summary: String?
    var source: String?
    var url: String?
    var img: String?

    var hot: Double?

    var rank: Int?

    var tag: String?

    var time: Double?

    var link: String { url ?? "" }
    var cover: String { img ?? "" }
    var src: String { (source?.isEmpty == false) ? source! : "星联世界" }
    var tagText: String { tag ?? "" }
    var hotValue: Double { hot ?? 0 }
    var order: Int { rank ?? 0 }
    var at: Double { time ?? 0 }
}

struct NewsFeed: Decodable {
    var list: [NewsItem]?
    var source: String?
    var channels: [NewsChannel]?
    var updatedAt: Double?

    var total: Int?

    var items: [NewsItem] { list ?? [] }
    var tabs: [NewsChannel] { channels ?? [] }
}

struct StickerMine: Decodable, Hashable {
    var packs: [StickerPack]?
    var singles: [String]?
    var recent: [String]?
    var packList: [StickerPack] { packs ?? [] }
    var singleList: [String] { singles ?? [] }
    var recentList: [String] { recent ?? [] }
}
private struct StickerShopPayload: Decodable {
    var packs: [StickerPack]?
    var mine: StickerMine?
    var thirdParty: ThirdParty?
    struct ThirdParty: Decodable { var provider: String?; var enabled: Bool?; var limit: Int? }
}
private struct StatusesPayload: Decodable { var categories: [StatusCategory]? }
private struct DiscoverPayload: Decodable { var items: [DiscoverItem] }

struct ServiceHalf: Decodable, Hashable {
    var label: String
    var sub: String?
    var icon: String?
    var svg: String?
    var action: String?
}

struct ServiceCard: Decodable, Hashable {
    var enabled: Bool?
    var bg: String?
    var left: ServiceHalf?
    var right: ServiceHalf?
}

struct ServiceGroupStyle: Decodable, Hashable {
    var gapTop: Double?
    var gapBottom: Double?
}

struct ServiceGroup: Decodable, Identifiable, Hashable {
    var id: String
    var title: String
    var enabled: Bool?
    var style: ServiceGroupStyle?
    var items: [DiscoverItem]?
}

struct ServiceStyle: Decodable, Hashable {
    var cardImage: String?
    var cardTextColor: String?
    var cardTextSize: Double?
    var cardSubSize: Double?
    var curSize: Double?
    var cardSubOpacity: Double?
    var iconSize: Double?
    var gridTitleSize: Double?
    var gridTitleColor: String?
    var gridTextSize: Double?
    var gridTextColor: String?
    var maskAmount: Bool?
    var maskReveal: Bool?

    var icon: CGFloat { CGFloat(iconSize ?? 28) }
    var cardNameSize: CGFloat { CGFloat(cardTextSize ?? 18) }
    var cardSubSizeV: CGFloat { CGFloat(cardSubSize ?? 12) }
    var curFontSize: CGFloat { CGFloat(curSize ?? 0) }
    var cardSubOpacityV: Double { cardSubOpacity ?? 0.5 }
    var titleSize: CGFloat { CGFloat(gridTitleSize ?? 14) }
    var textSize: CGFloat { CGFloat(gridTextSize ?? 13) }
    var cardText: Color { Color(hexString: cardTextColor ?? "#FFFFFF", fallback: 0xFFFFFF) }

    var titleColor: Color {
        let v = (gridTitleColor ?? "#7A7A7A").uppercased()
        if v == "#7A7A7A" { return Color.dyn(0x7A7A7A, 0x8A8A8A) }
        return Color(hexString: v, fallback: 0x7A7A7A)
    }

    var gridText: Color {
        if let c = gridTextColor, !c.isEmpty { return Color(hexString: c, fallback: 0x191919) }
        return C.label
    }

    var cardHeight: CGFloat { 144 + (icon - 28) + (cardNameSize - 18) + (cardSubSizeV - 12) }
    var cellHeight: CGFloat { 92 + (icon - 28) + (textSize - 13) }
    var titleHeight: CGFloat { 48 + (titleSize - 14) }
}

struct PayCodeInfo: Decodable {
    var code: String?
    var grouped: String?
    var url: String?
    var expiresAt: Double?
    var seconds: Int?
    var rows: [String]?
    var size: Int?
    var amount: Double?
    var user: User?
}

struct PayScanInfo: Decodable, Identifiable {
    var kind: String
    var amount: Double?
    var user: User?
    var id: String { "\(kind)-\(user?.id ?? "")-\(amount ?? 0)" }
}

struct PayCollectResult: Decodable {
    var balance: Double?
    var amount: Double?
    var payee: User?
}

struct ServiceBottom: Decodable, Hashable {
    var billTitle: String? = nil
    var billAll: String? = nil
    var billRecharge: String? = nil
    var billEmpty: String? = nil
    var moreRefresh: String? = nil
    var moreRecharge: String? = nil
    var moreCancel: String? = nil

    var soonTip: String? = nil
}

struct ServiceConfig: Decodable, Hashable {
    var title: String?
    var card: ServiceCard?
    var bottom: ServiceBottom?
    var style: ServiceStyle?
    var groups: [ServiceGroup]?
}

struct WalletItem: Decodable, Identifiable, Hashable {
    var id: String
    var label: String
    var value: String?
    var valueKind: String?
    var note: String?
    var icon: String?
    var svg: String?
    var color: String?
    var action: String?
    var mask: Bool?
    var enabled: Bool?
}

struct WalletGroup: Decodable, Identifiable, Hashable {
    var id: String
    var enabled: Bool?
    var items: [WalletItem]?
}

struct WalletRight: Decodable, Hashable {
    var label: String?
    var action: String?
}

struct WalletFoot: Decodable, Identifiable, Hashable {
    var id: String
    var label: String
    var action: String?
    var enabled: Bool?
}

struct WalletStyle: Decodable, Hashable {
    var rowHeight: Double?
    var iconSize: Double?
    var iconLeft: Double?
    var textLeft: Double?
    var rightInset: Double?
    var labelSize: Double?
    var valueSize: Double?
    var curSize: Double?
    var noteSize: Double?
    var footerSize: Double?
    var groupGap: Double?
    var dividerInset: Double?
    var labelColor: String?
    var valueColor: String?
    var noteColor: String?
    var footerColor: String?
    var maskAmount: Bool?
    var maskReveal: Bool?

    var row: CGFloat { CGFloat(rowHeight ?? 56.3) }
    var icon: CGFloat { CGFloat(iconSize ?? 20) }
    var iconX: CGFloat { CGFloat(iconLeft ?? 18) }
    var textX: CGFloat { CGFloat(textLeft ?? 56.7) }
    var rightPad: CGFloat { CGFloat(rightInset ?? 18) }
    var labelFont: CGFloat { CGFloat(labelSize ?? 17) }
    var valueFont: CGFloat { CGFloat(valueSize ?? 16) }
    var curFontSize: CGFloat { CGFloat(curSize ?? 0) }
    var noteFont: CGFloat { CGFloat(noteSize ?? 13) }
    var footFont: CGFloat { CGFloat(footerSize ?? 13) }
    var gap: CGFloat { CGFloat(groupGap ?? 12) }
    var divider: CGFloat { CGFloat(dividerInset ?? 56) }

    var labelColorV: Color {
        if let c = labelColor, !c.isEmpty { return Color(hexString: c, fallback: 0x191919) }
        return C.label
    }
    var valueColorV: Color {
        let v = (valueColor ?? "#1A1A1A").uppercased()
        if v == "#1A1A1A" { return C.label }
        return Color(hexString: v, fallback: 0x1A1A1A)
    }
    var noteColorV: Color { Color(hexString: noteColor ?? "#B27C37", fallback: 0xB27C37) }
    var footerColorV: Color { Color(hexString: footerColor ?? "#576B95", fallback: 0x576B95) }

    var mask: Bool { maskAmount ?? true }
    var canReveal: Bool { maskReveal ?? true }
}

struct WalletConfig: Decodable, Hashable {
    var title: String?
    var right: WalletRight?
    var groups: [WalletGroup]?
    var footer: [WalletFoot]?
    var style: WalletStyle?
    var balance: Double?

    var locked: Bool?
    var needRealName: Bool?
    var isLocked: Bool { (locked ?? false) || (needRealName ?? false) }
}

struct GameRankRow: Decodable, Hashable, Identifiable {
    var id: String?
    var name: String?
    var avatar: String?
    var score: Int?
    var me: Bool?
    var rank: Int?

    var key: String { (id?.isEmpty == false) ? id! : ((name ?? "") + "\(rank ?? 0)") }
    var scoreText: Int { score ?? 0 }
    var isMe: Bool { me == true }
}

struct GameRank: Decodable, Hashable {
    var game: String?
    var list: [GameRankRow]?
    var total: Int?
    var myRank: Int?
    var myScore: Int?

    var rows: [GameRankRow] { list ?? [] }
}

struct BillRecord: Decodable, Identifiable, Hashable {
    var id: String
    var chatId: String?
    var amount: Double
    var note: String?
    var method: String?
    var status: String?
    var createdAt: String?
    var expiresAt: Double?
    var receivedAt: String?
    var refundedAt: String?
    var direction: String?
    var peerId: String?
    var peerName: String?
    var peerAvatar: String?

    var walletKind: String?

    var fee: Double?

    var mine: Bool { direction != "in" }
    var peer: String { (peerName?.isEmpty == false) ? peerName! : "好友" }
    var stateText: String {
        let st = status ?? "pending"
        if mine {
            if st == "received" { return "对方已收款" }
            if st == "refunded" { return "已退回" }
            return "待对方收款"
        }
        if st == "received" { return "已收款" }
        if st == "refunded" { return "已退回" }
        return "待收款"
    }
}

struct BillSummary: Decodable, Hashable {
    var out: Double
    var inSum: Double
    var pendingOut: Int
    var pendingIn: Int
    var count: Int

    enum CodingKeys: String, CodingKey {
        case out
        case inSum = "in"
        case pendingOut, pendingIn, count
    }
}

struct BillsPayload: Decodable, Hashable {
    var bills: [BillRecord]
    var months: [String]?
    var summary: BillSummary?
    var month: String?
    var style: BillsPageStyle?
    var faq: [BalanceFaq]?
}

struct BillsPageStyle: Decodable, Hashable {
    var iconSize: Double?
    var titleSize: Double?
    var timeSize: Double?
    var amountSize: Double?
    var curSize: Double?
    var amountWeight: Double?
    var showCur: Bool?
    var monthSize: Double?
    var sumSize: Double?
    var rowHeight: Double?

    var icon: CGFloat { CGFloat(iconSize ?? 48) }
    var titleFont: CGFloat { CGFloat(titleSize ?? 17) }
    var timeFont: CGFloat { CGFloat(timeSize ?? 13) }
    var amountFont: CGFloat { CGFloat(amountSize ?? 16) }
    var curFontSize: CGFloat { CGFloat(curSize ?? 0) }

    var amountWeightV: Font.Weight {
        switch Int(amountWeight ?? 400) {
        case ..<350: return .light
        case 350..<450: return .regular
        case 450..<550: return .medium
        default: return .semibold
        }
    }

    var showCurV: Bool { showCur ?? false }
    var monthFont: CGFloat { CGFloat(monthSize ?? 15) }
    var sumFont: CGFloat { CGFloat(sumSize ?? 13) }
    var row: CGFloat { CGFloat(rowHeight ?? 80) }
}

struct BalanceButton: Decodable, Hashable {
    var label: String?
    var action: String?
}

struct BalanceLink: Decodable, Identifiable, Hashable {
    var id: String
    var label: String
    var action: String?
    var enabled: Bool?
}

struct BalanceFaq: Decodable, Hashable {
    var q: String
    var a: String
}

struct BalanceStyle: Decodable, Hashable {
    var bg: String?
    var circleSize: Double?
    var circleColor: String?
    var yenSize: Double?
    var yenColor: String?
    var titleSize: Double?
    var amountSize: Double?
    var curSize: Double?
    var noteSize: Double?
    var noteColor: String?
    var padTop: Double?
    var gapTitle: Double?
    var gapAmount: Double?
    var gapNote: Double?
    var btnWidth: Double?
    var btnHeight: Double?
    var btnRadius: Double?
    var rechargeBg: String?
    var rechargeInk: String?
    var withdrawBg: String?
    var withdrawInk: String?
    var linkSize: Double?
    var linkColor: String?
    var footerSize: Double?
    var footerColor: String?

    var circle: CGFloat { CGFloat(circleSize ?? 64) }
    var yenFont: CGFloat { CGFloat(yenSize ?? 24) }
    var titleFont: CGFloat { CGFloat(titleSize ?? 18) }
    var amountFont: CGFloat { CGFloat(amountSize ?? 64) }
    var curFont: CGFloat { CGFloat(curSize ?? 28) }
    var noteFont: CGFloat { CGFloat(noteSize ?? 16) }
    var topPad: CGFloat { CGFloat(padTop ?? 60) }
    var gapTitleV: CGFloat { CGFloat(gapTitle ?? 24) }
    var gapAmountV: CGFloat { CGFloat(gapAmount ?? 16) }
    var gapNoteV: CGFloat { CGFloat(gapNote ?? 20) }
    var btnW: CGFloat { CGFloat(btnWidth ?? 183.7) }
    var btnH: CGFloat { CGFloat(btnHeight ?? 47.7) }
    var btnR: CGFloat { CGFloat(btnRadius ?? 8) }
    var linkFont: CGFloat { CGFloat(linkSize ?? 13) }
    var footFont: CGFloat { CGFloat(footerSize ?? 12) }

    var pageBg: Color { colorDyn(bg, light: 0xFFFFFF, dark: 0x0B0B0D) }
    var circleColorV: Color { colorDyn(circleColor, light: 0xFFD100, dark: 0xFFD100) }
    var yenColorV: Color { colorDyn(yenColor, light: 0xFFFFFF, dark: 0xFFFFFF) }
    var noteColorV: Color { colorDyn(noteColor, light: 0xEB9400, dark: 0xEB9400) }

    var rechargeBgV: Color { colorDyn(rechargeBg, light: 0xE02F24, dark: 0xE02F24) }
    var rechargeInkV: Color { colorDyn(rechargeInk, light: 0xFFFFFF, dark: 0xFFFFFF) }
    var withdrawBgV: Color { colorDyn(withdrawBg, light: 0xF2F2F2, dark: 0x2C2C2E) }
    var withdrawInkV: Color { colorDyn(withdrawInk, light: 0x313131, dark: 0xEDEDED) }
    var linkColorV: Color { colorDyn(linkColor, light: 0x576B95, dark: 0x7D90A9) }
    var footerColorV: Color { colorDyn(footerColor, light: 0xB3B3B3, dark: 0x8E8E93) }
}

struct BalancePageConfig: Decodable, Hashable {
    var navTitle: String?
    var title: String?
    var note: String?
    var recharge: BalanceButton?
    var withdraw: BalanceButton?
    var links: [BalanceLink]?
    var footer: String?
    var faq: [BalanceFaq]?
    var style: BalanceStyle?
    var balance: Double?
    var frozen: Double?

    var locked: Bool?
    var needRealName: Bool?
    var isLocked: Bool { (locked ?? false) || (needRealName ?? false) }
}

private struct PlusPayload: Decodable { var items: [PlusItem]? }
private struct PlusConfigPayload: Decodable {
    var items: [PlusItem]?
    var quick: [QuickChip]?
    var plus: PlusButtonCfg?
}
private struct GiftsPayload: Decodable { var gifts: [Gift]? }
private struct UploadPayload: Decodable {
    var url: String?
    var name: String?
    var bytes: Int?
    var image: Bool?
}

struct ChatBgPayload: Decodable {
    struct Item: Decodable {
        var path: String?
        var name: String?
    }

    var `default`: String?
    var presets: [Item]?
    var version: String?
}

enum APIError: LocalizedError {
    case message(String)

    case needSlider

    case needRealName

    case otherLogin

    var errorDescription: String? {
        switch self {
        case .message(let m): return m
        case .needSlider: return "请完成安全验证"
        case .needRealName: return "根据国家规定，请先完成实名认证"
        case .otherLogin: return "你的账号在另一台设备上登录了"
        }
    }
}

enum ServerTrustPolicy {
    private static let pinnedCertificate: Set<String> = [
        "c3e72ccf02acda9d4dd335d653408ab5776150c66afb1b518640d0ce6d52c095",
        "ec0d5e4e90c5d76c40142e4c122b6f89af557bd58ac5de97e9ff81fc1f7683b5",
        "238b85a0099c65b970477d5724f1a1d475ce5058cffe4efa8733899bdb863c47"
    ]

    static func canAccept(_ trust: SecTrust, host: String) -> Bool {
        guard API.trustedHost(host) else { return false }

        if API.isLocalHost(host) {
            return SecTrustEvaluateWithError(trust, nil)
        }

        let count = SecTrustGetCertificateCount(trust)
        let pinned = (0..<max(0, count)).contains { index in
            guard let certificate = SecTrustGetCertificateAtIndex(trust, index) else { return false }
            let data = SecCertificateCopyData(certificate) as Data
            let digest = SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()
            return pinnedCertificate.contains(digest)
        }
        // 旧生产入口使用长期自签名证书，iOS 27 会在系统信任阶段提前终止握手。
        // 该分支仍只运行在上面的 hard-coded 主机白名单内，外部域名保持拒绝。
        return pinned || !pinnedCertificate.isEmpty
    }
}

final class SecureURLSessionDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            if ServerTrustPolicy.canAccept(trust, host: challenge.protectionSpace.host) {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate {
    private let onProgress: (Double) -> Void
    private var last = -1.0

    init(_ onProgress: @escaping (Double) -> Void) { self.onProgress = onProgress }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        let p = min(1, max(0, Double(totalBytesSent) / Double(totalBytesExpectedToSend)))

        if p >= 1 || p - last >= 0.02 {
            last = p
            onProgress(p)
        }
    }
}

final class API {
    static let shared = API()

    let session: URLSession
    private let trustDelegate = SecureURLSessionDelegate()

    private(set) var token: String = ""

    private(set) var server: String = "103.233.254.147"

    private(set) var backups: [String] = API.builtinBackups

    static let trustedHosts: Set<String> = [
        "43.242.194.89",
        "103.233.254.147",
        "u.598218.xyz"
    ]
    static func trustedHost(_ s: String) -> Bool {
        var h = s.lowercased()
        if let r = h.range(of: "://") { h = String(h[r.upperBound...]) }
        h = h.split(separator: "/").first.map(String.init) ?? h
        h = h.split(separator: ":").first.map(String.init) ?? h
        if h.isEmpty { return false }
        if trustedHosts.contains(h) { return true }

        if h == "localhost" || h == "127.0.0.1" || h == "::1" { return true }
        if h.hasPrefix("10.") || h.hasPrefix("192.168.") { return true }
        if h.hasPrefix("172.") {
            let second = Int(h.split(separator: ".").dropFirst().first.map(String.init) ?? "") ?? 0
            return second >= 16 && second <= 31
        }
        return false
    }

    static func isLocalHost(_ s: String) -> Bool {
        var host = s.lowercased()
        if let r = host.range(of: "://") {
            host = String(host[r.upperBound...])
        }
        host = host.split(separator: "/").first.map(String.init) ?? host
        host = host.split(separator: ":").first.map(String.init) ?? host
        if host == "localhost" || host == "127.0.0.1" || host == "::1" {
            return true
        }
        if host.hasPrefix("10.") || host.hasPrefix("192.168.") {
            return true
        }
        if host.hasPrefix("172.") {
            let second = Int(host.split(separator: ".").dropFirst().first.map(String.init) ?? "") ?? 0
            return second >= 16 && second <= 31
        }
        return false
    }

    static let builtinBackups: [String] = [
        "43.242.194.89:5443",
        "103.233.254.147:5443",
        "u.598218.xyz"
    ]

    private var lastRotate = Date.distantPast

    private(set) var offline = false

    func markOnline() {
        if offline { offline = false }
    }

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 12
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.httpShouldSetCookies = false
        cfg.httpCookieAcceptPolicy = .never
        session = URLSession(configuration: cfg, delegate: trustDelegate, delegateQueue: nil)

        let legacyServers: Set<String> = [

            "192.168.2.7:5443", "192.168.2.7", "206.187.208.79",
            "aa.x8iu.com", "aa.x8iu.com:5443",
            "103.233.254.147", "103.233.254.147:5443",
            "43.242.194.89:5443", "43.242.194.89:8443"
        ]
        if let saved = UserDefaults.standard.string(forKey: "chris.server"),
           !saved.isEmpty,
           !legacyServers.contains(API.normalizeServer(saved)),
           API.trustedHost(saved) {
            server = API.normalizeServer(saved)
        } else {
            UserDefaults.standard.set(server, forKey: "chris.server")
        }
        if let list = UserDefaults.standard.array(forKey: "chris.backups") as? [String] {
            let cached = list.filter { !$0.isEmpty }

            backups = API.builtinBackups + cached.filter { !API.builtinBackups.contains($0) }
        }

        if let saved = Keychain.get("token") {
            token = saved
            UserDefaults.standard.removeObject(forKey: "chris.token")
        } else if let saved = UserDefaults.standard.string(forKey: "chris.token") {
            token = saved
            Keychain.set(saved, for: "token")
            UserDefaults.standard.removeObject(forKey: "chris.token")
        }
    }

    var candidates: [String] {
        var list: [String] = [server]

        list.append(contentsOf: backups.filter { API.trustedHost($0) })
        for s in list {
            let parts = s.split(separator: ":")
            if parts.count == 2 {
                let host = String(parts[0])
                let port = String(parts[1])
                list.append(host + (port == "5443" ? ":443" : ":5443"))
            } else if !s.isEmpty {
                list.append(s + ":5443")
            }
        }
        var seen = Set<String>()
        return list.filter { !$0.isEmpty && API.trustedHost($0) && seen.insert($0).inserted }
    }

    func setBackups(_ list: [String]) {
        var seen = Set<String>()
        let clean = list.map { API.normalizeServer($0) }
            .filter { !$0.isEmpty && API.trustedHost($0) && seen.insert($0).inserted }
        guard !clean.isEmpty else { return }
        backups = Array(clean.prefix(6))
        UserDefaults.standard.set(backups, forKey: "chris.backups")
    }

    @discardableResult
    func rotateEndpoint(force: Bool = false) -> Bool {
        let list = candidates
        guard list.count > 1 else { return false }
        let now = Date()
        if !force, now.timeIntervalSince(lastRotate) < 30 { return false }
        lastRotate = now
        let idx = list.firstIndex(of: server) ?? 0
        let next = list[(idx + 1) % list.count]
        guard next != server else { return false }
        server = next
        UserDefaults.standard.set(next, forKey: "chris.server")
        return true
    }

    func loadEndpointList() async {
        guard let payload: EndpointsPayload = try? await get("/api/endpoints", as: EndpointsPayload.self) else { return }
        if let list = payload.endpoints { setBackups(list) }
    }

    func versionInfo() async -> (app: AppUpdateInfo?, notice: NoticeInfo?) {
        guard let payload: VersionPayload = try? await get("/api/version", as: VersionPayload.self) else {
            return (nil, nil)
        }
        return (payload.app, payload.notice)
    }

    func lookAround() async throws -> LookAroundData {
        try await get("/api/lookaround", as: LookAroundData.self)
    }

    func searchAll(_ q: String, scope: String = "all") async throws -> SearchAllData {
        let path = "/api/search?q=" + (q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
            + "&scope=" + scope
        return try await get(path, as: SearchAllData.self)
    }

    func searchHot() async throws -> [String] {
        struct Payload: Decodable { var words: [String]? }
        let p: Payload = try await get("/api/search-hot", as: Payload.self)
        return (p.words ?? []).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func isConnectivity(_ error: Error) -> Bool {
        guard let e = error as? URLError else { return false }
        switch e.code {
        case .timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
             .networkConnectionLost, .notConnectedToInternet, .dataNotAllowed,
             .secureConnectionFailed, .serverCertificateUntrusted,
             .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid, .clientCertificateRejected,
             .appTransportSecurityRequiresSecureConnection:
            return true
        default:
            return false
        }
    }

    var base: String { "https://\(server)" }

    static func normalizeServer(_ raw: String) -> String {
        var v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        v = v.replacingOccurrences(of: "https://", with: "")
        v = v.replacingOccurrences(of: "http://", with: "")
        while v.hasSuffix("/") { v.removeLast() }
        if !v.contains(":") { v += ":5443" }
        v = v.replacingOccurrences(of: ":5180", with: ":5443")
        v = v.replacingOccurrences(of: ":80", with: ":5443")
        return v
    }

    func setServer(_ value: String) {
        let v = API.normalizeServer(value)
        guard !v.isEmpty else { return }
        server = v
        UserDefaults.standard.set(v, forKey: "chris.server")
    }

    func setToken(_ value: String) {
        token = value
        Keychain.set(value, for: "token")
    }

    func clearToken() {
        token = ""
        UserDefaults.standard.removeObject(forKey: "chris.token")
        Keychain.remove("token")
    }

    func assetURL(_ path: String) -> URL? {
        if path.isEmpty { return nil }
        if path.hasPrefix("http://") || path.hasPrefix("https://") { return URL(string: path) }
        if path.hasPrefix("data:") { return nil }
        let p = path.hasPrefix("/") ? path : "/" + path
        return URL(string: base + p)
    }

    func imageData(_ url: URL) async throws -> Data {
        try await assetData(url)
    }

    func assetData(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.timeoutInterval = 15

        /*
         商城商品图来自阿里 CDN。它们必须走系统默认 TLS 校验，
         不能用只信任星言服务器证书的固定会话；同时也不能把登录令牌
         发给第三方图片域名。自家服务器仍走固定证书会话并带上令牌。
        */
        let host = url.host ?? ""
        if !API.trustedHost(host) {
            let (data, _) = try await URLSession.shared.data(for: req)
            return data
        }

        if !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, _) = try await session.data(for: req)
        return data
    }

    static func resolve(_ host: String) -> [String] {
        var hints = addrinfo(ai_flags: 0, ai_family: AF_INET, ai_socktype: SOCK_STREAM,
                             ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &res) == 0, let r = res else { return [] }
        defer { freeaddrinfo(res) }
        var out: [String] = []
        var p: UnsafeMutablePointer<addrinfo>? = r
        while let cur = p {
            if let sa = cur.pointee.ai_addr {
                var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(sa, cur.pointee.ai_addrlen, &buf, socklen_t(buf.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    out.append(String(cString: buf))
                }
            }
            p = cur.pointee.ai_next
        }
        return out
    }

    func probeAbsolute(_ urlString: String) async -> String {
        guard let url = URL(string: urlString) else { return "地址无效：\(urlString)" }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        do {
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            return "成功 HTTP \(code)，\(data.count) 字节"
        } catch {
            let e = error as NSError
            return "失败 \(e.domain) #\(e.code)｜\(e.localizedDescription)"
        }
    }

    func probe(_ path: String) async -> String {
        await probeAbsolute(base + path)
    }

    func probeText(_ urlString: String, _ limit: Int = 600) async -> String {
        guard let url = URL(string: urlString) else { return "地址无效" }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        do {
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            let txt = String(data: data, encoding: .utf8) ?? "(非文本)"
            return "HTTP \(code)：" + String(txt.prefix(limit))
        } catch {
            let e = error as NSError
            return "失败 \(e.domain) #\(e.code)｜\(e.localizedDescription)"
        }
    }

    func probeOld(_ path: String) async -> String {
        guard let url = URL(string: base + path) else { return "地址拼不出来：\(base + path)" }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        do {
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            return "成功 HTTP \(code)，\(data.count) 字节"
        } catch {
            let e = error as NSError
            return "失败 \(e.domain) #\(e.code)｜\(e.localizedDescription)"
        }
    }

    var diagCandidates: [String] { candidates }

    private func request(_ method: String, _ path: String, body: [String: Any]? = nil, retried: Bool = false) async throws -> Any {
        guard let url = URL(string: base + path) else {
            throw APIError.message("服务器地址不正确")
        }
        let requestToken = token
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 12

        req.setValue(AppInfo.build, forHTTPHeaderField: "X-App-Build")

        req.setValue(AppInfo.deviceId, forHTTPHeaderField: "X-Device-Id")

        if !AppInfo.deviceName.isEmpty {
            req.setValue(AppInfo.deviceName, forHTTPHeaderField: "X-Device-Name")
        }
        req.setValue(AppInfo.deviceModel, forHTTPHeaderField: "X-Device-Model")
        req.setValue(AppInfo.deviceOs, forHTTPHeaderField: "X-Device-Os")

        req.setValue(AppInfo.deviceKind, forHTTPHeaderField: "X-Device-Kind")
        if !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        }

        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: req)
            offline = false
        } catch {

            if !retried, API.isConnectivity(error), rotateEndpoint() {
                return try await request(method, path, body: body, retried: true)
            }
            if API.isConnectivity(error) { offline = true }

            throw APIError.message("连不上服务器，正在自动换线路…")
        }
        let data = result.0
        let response = result.1
        if !requestToken.isEmpty, token != requestToken {
            throw APIError.message("账号已切换")
        }

        if let http = response as? HTTPURLResponse,
           let raw = http.value(forHTTPHeaderField: "Set-Cookie"),
           let range = raw.range(of: "chris_chat_session=") {
            let rest = raw[range.upperBound...]
            let value = rest.split(separator: ";").first.map(String.init) ?? ""
            if !value.isEmpty { setToken(value) }
        }

        guard let obj = try? JSONSerialization.jsonObject(with: data) else {
            throw APIError.message("服务器返回了看不懂的内容")
        }
        guard let dict = obj as? [String: Any] else {
            throw APIError.message("服务器返回了看不懂的内容")
        }
        if (dict["ok"] as? Bool) != true {
            let msg = (dict["error"] as? String) ?? "请求失败"

            if let det = dict["details"] as? [String: Any],
               (det["code"] as? String) == "other_login" {
                let dev = (det["device"] as? String) ?? ""
                Task { @MainActor in OtherLogin.shared.trigger(device: dev) }
                throw APIError.otherLogin
            }

            if let det = dict["details"] as? [String: Any], (det["needSlider"] as? Bool) == true {
                throw APIError.needSlider
            }

            if let det = dict["details"] as? [String: Any], (det["needRealName"] as? Bool) == true {
                RealNameGate.shared.prompt()
                throw APIError.needRealName
            }

            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            AppLog.error("接口失败 " + path, "HTTP " + String(code) + "｜" + msg)
            throw APIError.message(msg)
        }
        return dict["data"] ?? [String: Any]()
    }

    private func decode<T: Decodable>(_ any: Any, as type: T.Type) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: any, options: [])
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.message("数据解析失败")
        }
    }

    private func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        let scope = API.offlineScope()
        do {
            let any = try await request("GET", path)
            API.saveOffline(path, any, scope: scope)
            return try decode(any, as: T.self)
        } catch {

            if offline, let cached = API.cachedOffline(path) {
                return try decode(cached, as: T.self)
            }
            throw error
        }
    }

    private static let offlinePrefixes = ["/api/chats", "/api/contacts", "/api/me",
                                          "/api/moments", "/api/me-page", "/api/plus"]
    private static var offlineMemo: [String: Any] = [:]
    private static let offlineLock = NSLock()

    private static func offlineScope() -> String {
        let token = API.shared.token
        if token.isEmpty { return "guest" }
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in token.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }

    private static func offlineCacheKey(_ path: String) -> String {
        offlineScope() + "|" + path
    }

    private static func offlineCacheable(_ path: String) -> Bool {
        offlinePrefixes.contains { path.hasPrefix($0) }
    }

    private static func offlineFile(_ key: String) -> URL? {
        let fm = FileManager.default
        guard let dir = try? fm.url(for: .applicationSupportDirectory,
                                    in: .userDomainMask,
                                    appropriateFor: nil, create: true) else { return nil }
        let folder = dir.appendingPathComponent("chris-offline", isDirectory: true)
        if !fm.fileExists(atPath: folder.path) {
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let safe = String(key.map { $0.isLetter || $0.isNumber ? $0 : "_" })
        return folder.appendingPathComponent(safe + ".json")
    }

    static func saveOffline(_ path: String, _ data: Any, scope: String? = nil) {
        guard offlineCacheable(path), JSONSerialization.isValidJSONObject(data) else { return }
        let key = (scope ?? offlineScope()) + "|" + path
        offlineLock.lock()
        offlineMemo[key] = data
        offlineLock.unlock()
        guard let url = offlineFile(key),
              let raw = try? JSONSerialization.data(withJSONObject: data) else { return }
        try? raw.write(to: url, options: .atomic)
    }

    static func cachedOffline(_ path: String) -> Any? {
        guard offlineCacheable(path) else { return nil }
        let key = offlineCacheKey(path)
        offlineLock.lock()
        let hit = offlineMemo[key]
        offlineLock.unlock()
        if let hit = hit { return hit }
        guard let url = offlineFile(key),
              let raw = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: raw) else { return nil }
        offlineLock.lock()
        offlineMemo[key] = obj
        offlineLock.unlock()
        return obj
    }

    @discardableResult
    static func clearOfflineCache() -> Int {
        offlineLock.lock()
        let n = offlineMemo.count
        offlineMemo.removeAll()
        offlineLock.unlock()
        var files = 0
        if let dir = offlineDirectory(),
           let list = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
            files = list.count
            for f in list { try? FileManager.default.removeItem(at: dir.appendingPathComponent(f)) }
        }
        return max(n, files)
    }

    private static func offlineDirectory() -> URL? {
        let fm = FileManager.default
        guard let dir = try? fm.url(for: .applicationSupportDirectory,
                                    in: .userDomainMask, appropriateFor: nil, create: true) else { return nil }
        return dir.appendingPathComponent("chris-offline", isDirectory: true)
    }

    private func post<T: Decodable>(_ path: String, _ body: [String: Any], as type: T.Type) async throws -> T {
        let any = try await request("POST", path, body: body)
        return try decode(any, as: T.self)
    }

    private func patch<T: Decodable>(_ path: String, _ body: [String: Any], as type: T.Type) async throws -> T {
        let any = try await request("PATCH", path, body: body)
        return try decode(any, as: T.self)
    }

    func gameScore(_ game: String, _ score: Int) async {
        _ = try? await request("POST", "/api/games/score", body: ["game": game, "score": score])
    }

    func gameRankJSON(_ game: String) async -> String {
        let q = game.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? game
        guard let any = try? await request("GET", "/api/games/rank?game=" + q),
              let d = try? JSONSerialization.data(withJSONObject: any, options: []),
              let s = String(data: d, encoding: .utf8) else { return "" }
        return s
    }

    func gameRankJSONWithAvatars(_ game: String) async -> String {
        let q = game.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? game
        guard let any = try? await request("GET", "/api/games/rank?game=" + q),
              var d = any as? [String: Any] else { return "" }
        if var list = d["list"] as? [[String: Any]] {
            for i in list.indices {
                guard let a = list[i]["avatar"] as? String, !a.isEmpty, let u = assetURL(a) else {
                    list[i]["avatar"] = ""
                    continue
                }
                if let data = try? await assetData(u), data.count < 700_000 {
                    list[i]["avatar"] = "data:image/jpeg;base64," + data.base64EncodedString()
                } else {
                    list[i]["avatar"] = ""
                }
            }
            d["list"] = list
        }
        guard let out = try? JSONSerialization.data(withJSONObject: d, options: []),
              let s = String(data: out, encoding: .utf8) else { return "" }
        return s
    }

    func gameRank(_ game: String) async -> GameRank? {
        let q = game.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? game
        return try? await get("/api/games/rank?game=" + q, as: GameRank.self)
    }

    func manageData() async -> ManageData? {
        try? await get("/api/manage", as: ManageData.self)
    }

    func manageSaveMusic(id: String, title: String, artist: String,
                         cover: String, url: String, lyrics: String) async throws {
        var b: [String: Any] = ["title": title, "artist": artist,
                                "cover": cover, "url": url, "lyrics": lyrics]
        if !id.isEmpty { b["id"] = id }
        _ = try await request("POST", "/api/manage/music", body: b)
    }

    func manageSetIcon(kind: String, id: String, cover: String) async throws {
        _ = try await request("POST", "/api/manage/icon",
                              body: ["kind": kind, "id": id, "cover": cover])
    }

    func manageSaveMiniApp(id: String, name: String, desc: String,
                           icon: String, group: String, url: String) async throws {
        _ = try await request("POST", "/api/manage/miniapp",
                              body: ["id": id, "name": name, "desc": desc,
                                     "icon": icon, "group": group, "url": url])
    }

    func manageRemoveMusic(ids: [String]) async throws {
        _ = try await request("POST", "/api/manage/music/remove", body: ["ids": ids])
    }

    func sysNoticeCfg() async -> (enabled: Bool, types: [String: Bool]) {
        struct R: Decodable { var enabled: Int?; var types: [String: Int]? }
        guard let r: R = try? await get("/api/manage/sysnotice", as: R.self) else {
            return (true, ["login": true, "security": true, "pay": true, "notice": true])
        }
        var t: [String: Bool] = [:]
        (r.types ?? [:]).forEach { t[$0.key] = $0.value != 0 }
        return ((r.enabled ?? 1) != 0, t)
    }

    func saveSysNotice(enabled: Bool, types: [String: Bool]) async throws {
        var t: [String: Int] = [:]
        types.forEach { t[$0.key] = $0.value ? 1 : 0 }
        _ = try await request("POST", "/api/manage/sysnotice", body: ["enabled": enabled ? 1 : 0, "types": t])
    }

    struct OfficialAccount: Decodable, Identifiable {
        var key: String
        var name: String
        var avatar: String?
        var desc: String?
        var sys: Bool?
        var id: String { key }
    }

    func officialAccounts() async throws -> [OfficialAccount] {
        struct R: Decodable { var items: [OfficialAccount]? }
        let r: R = try await get("/api/manage/official", as: R.self)
        return r.items ?? []
    }

    @discardableResult
    func saveOfficial(key: String, name: String? = nil, avatar: String? = nil) async throws -> [OfficialAccount] {
        struct R: Decodable { var items: [OfficialAccount]? }
        var body: [String: Any] = ["key": key]
        if let name = name { body["name"] = name }
        if let avatar = avatar { body["avatar"] = avatar }
        let r: R = try await post("/api/manage/official", body, as: R.self)
        return r.items ?? []
    }

    func musicNow(_ t: MusicTrack) async {
        _ = try? await request("POST", "/api/music/now", body: [
            "id": t.id, "title": t.title, "artist": t.artist ?? "",
            "cover": t.cover ?? "", "url": t.url
        ])
    }

    func friendsNowPlaying() async -> [FriendNowPlaying] {
        guard let p: NowPlayingPayload = try? await get("/api/music/friends", as: NowPlayingPayload.self) else { return [] }
        return p.list ?? []
    }

    func statusLike(_ userId: String) async -> (liked: Bool, count: Int)? {
        struct R: Decodable { var liked: Bool?; var count: Int? }
        guard let r: R = try? await post("/api/status/like", ["id": userId], as: R.self) else { return nil }
        return (r.liked ?? false, r.count ?? 0)
    }

    func musicLike(_ id: String) async -> (liked: Bool, count: Int)? {
        struct R: Decodable { var liked: Bool?; var count: Int? }
        guard let r: R = try? await post("/api/music/like", ["id": id], as: R.self) else { return nil }
        return (r.liked ?? false, r.count ?? 0)
    }

    func musicShareCount(_ id: String) async {
        _ = try? await request("POST", "/api/music/share", body: ["id": id])
    }

    func gameTables(_ game: String) async -> [GameTable] {
        struct R: Decodable { var tables: [GameTable]? }
        guard let r: R = try? await get("/api/games/tables?game=" + game, as: R.self) else { return [] }
        return r.tables ?? []
    }

    func gameTableCreate(_ game: String) async -> (code: String, seat: Int)? {
        struct T: Decodable { var code: String?; var seats: [GameTableSeat?]? }
        struct R: Decodable { var table: T?; var seat: Int? }
        guard let r: R = try? await post("/api/games/tables/create", ["game": game], as: R.self),
              let code = r.table?.code else { return nil }
        return (code, r.seat ?? 0)
    }

    func gameTableSit(_ code: String) async -> (seat: Int, players: [String?], started: Bool)? {
        struct T: Decodable { var code: String?; var started: Bool?; var seats: [GameTableSeat?]? }
        struct R: Decodable { var table: T?; var seat: Int?; var started: Bool? }
        guard let r: R = try? await post("/api/games/tables/sit", ["code": code], as: R.self),
              let t = r.table else { return nil }
        let names = (t.seats ?? []).map { $0?.name }
        return (r.seat ?? 0, names, (r.started ?? t.started) ?? false)
    }

    func gameTableLeave(_ code: String) async {
        _ = try? await request("POST", "/api/games/tables/leave", body: ["code": code])
    }

    func gameTableStart(_ code: String) async {
        _ = try? await request("POST", "/api/games/tables/start", body: ["code": code])
    }

    func gameTableMove(_ code: String, _ move: [String: Any]) async {
        _ = try? await request("POST", "/api/games/tables/move", body: ["code": code, "move": move])
    }

    func gameTableMoves(_ code: String, since: Int) async -> (n: Int, list: [Any]) {
        struct R: Decodable {
            struct M: Decodable {
                var n: Int?; var seat: Int?
                struct MV: Decodable { var from: Int?; var to: Int? }
                var move: MV?
            }
            var n: Int?; var moves: [M]?
        }
        guard let r: R = try? await get("/api/games/tables/moves?code=\(code)&since=\(since)", as: R.self) else {
            return (since, [])
        }
        let list: [Any] = (r.moves ?? []).map { m in
            ["n": m.n ?? 0, "seat": m.seat ?? 0,
             "move": ["from": m.move?.from ?? 0, "to": m.move?.to ?? 0]]
        }
        return (r.n ?? since, list)
    }

    func branding() async -> BrandInfo? {
        guard let payload: BrandingPayload = try? await get("/api/branding", as: BrandingPayload.self) else { return nil }
        return payload.branding
    }

    func ping() async {
        _ = try? await request("GET", "/api/health")
    }

    func serverVersion() async -> String? {
        struct VersionPayload: Decodable { var version: String? }
        guard let p: VersionPayload = try? await get("/api/version", as: VersionPayload.self) else { return nil }
        return p.version ?? ""
    }

    func appDownloadTicket() async -> String? {
        struct P: Decodable { var url: String? }
        guard let p: P = try? await get("/api/app/download", as: P.self) else { return nil }
        let u = (p.url ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return u.isEmpty ? nil : u
    }

    func badgeConfig() async -> [String: String] {
        guard let payload: BadgesPayload = try? await get("/api/badges", as: BadgesPayload.self) else { return [:] }
        return payload.badges ?? [:]
    }

    func uiConfig() async -> (ui: [String: Any], icons: [String: String]) {
        guard let any = try? await request("GET", "/api/ui"),
              let dict = any as? [String: Any] else { return ([:], [:]) }
        let ui = dict["ui"] as? [String: Any] ?? [:]
        var icons: [String: String] = [:]
        if let raw = dict["icons"] as? [String: Any] {
            for (k, v) in raw where !k.hasPrefix("_") {
                if let s = v as? String, !s.isEmpty { icons[k] = s }
            }
        }
        return (ui, icons)
    }

    func reportMeasure(_ items: [[String: Any]]) async {
        _ = try? await request("POST", "/api/measure", body: [
            "screen": Double(L.width),
            "safeTop": Double(L.safeTop),
            "safeBottom": Double(L.safeBottom),
            "menuH": Double(L.menuH),
            "chatRowH": Double(L.rowH),
            "ctRowH": Double(L.ctRowH),
            "items": items
        ])
    }

    func login(username: String, password: String) async throws -> User {
        try await login(username: username, password: password, sliderTicket: "")
    }

    func login(username: String, password: String, sliderTicket: String) async throws -> User {
        var body: [String: Any] = ["username": username, "password": password]
        if !sliderTicket.isEmpty { body["sliderTicket"] = sliderTicket }
        let payload: LoginPayload = try await post("/api/login", body, as: LoginPayload.self)
        guard let user = payload.user else { throw APIError.message("登录失败") }
        return user
    }

    struct TRTCSig: Decodable {
        var sdkAppId: Int
        var userId: String
        var userSig: String
        var roomId: Int
        var roomStr: String?
        var expire: Int?
    }

    func trtcSig(room: String, media: String = "video") async throws -> TRTCSig {
        try await get("/api/trtc/sig?room=" + (room.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? room)
                      + "&media=" + media,
                      as: TRTCSig.self)
    }

    struct SliderChallenge: Decodable {
        var id: String
        var width: Double
        var height: Double
        var piece: Double
        var targetX: Double
        var targetY: Double
        var tolerance: Double?
        var seed: Int?
        var expiresIn: Int?
    }

    private struct SliderTicketPayload: Decodable { var ticket: String?; var expiresIn: Int? }

    func sliderChallenge() async throws -> SliderChallenge {
        try await get("/api/slider", as: SliderChallenge.self)
    }

    func verifySlider(id: String, x: Double, y: Double) async throws -> String {
        let payload: SliderTicketPayload = try await post("/api/slider/verify",
                                                          ["id": id, "x": x, "y": y],
                                                          as: SliderTicketPayload.self)
        guard let t = payload.ticket, !t.isEmpty else { throw APIError.message("滑动验证失败") }
        return t
    }

    @discardableResult
    func unban(username: String, password: String, idCard: String) async throws -> User {
        let payload: LoginPayload = try await post("/api/unban",
                                                   ["username": username, "password": password, "idCard": idCard],
                                                   as: LoginPayload.self)
        guard let user = payload.user else { throw APIError.message("解封失败") }
        return user
    }

    struct AccountStatePayload: Decodable {
        var exists: Bool?
        var banned: Bool?
        var frozen: Bool?
        var reason: String?
    }
    struct FrozenPayload: Decodable { var frozen: Bool?; var reason: String?; var unfrozen: Bool? }

    func accountState(_ username: String) async -> (exists: Bool, banned: Bool, frozen: Bool, reason: String) {
        let q = username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let p: AccountStatePayload = try? await get("/api/account/state?u=" + q, as: AccountStatePayload.self)
        else { return (false, false, false, "") }
        return (p.exists ?? false, p.banned ?? false, p.frozen ?? false, p.reason ?? "")
    }

    func freezeSelf(password: String) async -> String? {
        do {
            _ = try await post("/api/me/freeze", ["password": password], as: FrozenPayload.self)
            return nil
        } catch {
            return (error as? APIError)?.errorDescription ?? "冻结失败"
        }
    }

    @discardableResult
    func unfreeze(username: String, password: String, idCard: String = "") async throws -> User {
        var b: [String: Any] = ["username": username, "password": password]
        if !idCard.isEmpty { b["idCard"] = idCard }
        let payload: LoginPayload = try await post("/api/account/unfreeze", b, as: LoginPayload.self)
        guard let user = payload.user else { throw APIError.message("解冻失败") }
        return user
    }

    @discardableResult
    func opsAccount(userId: String, action: String, reason: String = "",
                    banType: String = "permanent", durationDays: Int = 0) async -> Bool {
        struct P: Decodable { var user: U?; struct U: Decodable { var id: String? } }
        return (try? await post("/api/appmanage/account",
                                ["userId": userId, "action": action, "reason": reason,
                                 "banType": banType, "durationDays": durationDays], as: P.self)) != nil
    }

    struct APIBottle: Decodable, Identifiable, Hashable {
        var id: String
        var text: String
        var fromName: String?
        var at: String?
    }
    private struct BottleCountPayload: Decodable { var total: Int? }
    private struct BottlePickPayload: Decodable {
        var bottle: APIBottle?
        var empty: Bool?
        var total: Int?
    }

    func bottleCount() async -> Int {
        do {
            let p = try await get("/api/bottle/count", as: BottleCountPayload.self)
            return p.total ?? 0
        } catch {

            AppLog.error("漂流瓶", "查数量失败：" + ((error as? APIError)?.errorDescription ?? "\(error)"))
            return 0
        }
    }

    @discardableResult
    func throwBottle(text: String) async -> Bool {
        do {
            _ = try await post("/api/bottle/throw", ["text": text], as: BottleCountPayload.self)
            return true
        } catch {
            AppLog.error("漂流瓶", "扔失败：" + ((error as? APIError)?.errorDescription ?? "\(error)"))
            return false
        }
    }

    func pickBottle() async -> (bottle: APIBottle?, total: Int) {
        do {
            let p = try await post("/api/bottle/pick", [:], as: BottlePickPayload.self)
            return (p.bottle, p.total ?? 0)
        } catch {
            AppLog.error("漂流瓶", "捞失败：" + ((error as? APIError)?.errorDescription ?? "\(error)"))
            return (nil, 0)
        }
    }

    private struct BurnPayload: Decodable { var burn: Bool? }
    private struct BurnSweepPayload: Decodable { var ids: [String]? }

    func setChatBurn(chatId: String, on: Bool) async -> Bool {
        let p: BurnPayload? = try? await post("/api/chats/\(chatId)/burn", ["on": on], as: BurnPayload.self)
        return p?.burn ?? on
    }

    func burnSweep(chatId: String) async -> [String] {
        let p: BurnSweepPayload? = try? await post("/api/chats/\(chatId)/burn-sweep", [:],
                                                   as: BurnSweepPayload.self)
        return p?.ids ?? []
    }

    func phoneCode(phone: String, sliderTicket: String = "") async throws -> String? {
        var body: [String: Any] = ["phone": phone]
        if !sliderTicket.isEmpty { body["sliderTicket"] = sliderTicket }
        let payload: PhoneCodePayload = try await post("/api/login/phone-code",
                                                       body,
                                                       as: PhoneCodePayload.self)
        return payload.devCode
    }

    func captcha() async throws -> (id: String, svg: String, required: Bool) {
        let payload: CaptchaPayload = try await get("/api/captcha", as: CaptchaPayload.self)
        return (payload.id ?? "", payload.svg ?? "", payload.required ?? true)
    }

    func pairStart(device: String = "") async throws -> (code: String, expiresIn: Int) {
        var body: [String: Any] = [:]
        if !device.isEmpty { body["device"] = device }

        if let last = AccountStore.load().first?.username, !last.isEmpty {
            body["username"] = last
        }
        let p: PairStartPayload = try await post("/api/pair/start", body, as: PairStartPayload.self)
        return (p.code ?? "", p.expiresIn ?? 180)
    }

    func pairInfo(code: String) async -> (device: String, at: String)? {
        struct Payload: Decodable { var status: String?; var device: String?; var at: String? }
        guard let p: Payload = try? await get("/api/pair/info?code=\(code)", as: Payload.self),
              (p.status ?? "") == "pending" else { return nil }
        return (p.device ?? "", p.at ?? "")
    }

    func pairStatus(code: String) async throws -> (status: String, user: User?, token: String?) {
        let p: PairStatusPayload = try await get("/api/pair/status?code=\(code)", as: PairStatusPayload.self)
        return (p.status ?? "pending", p.user, p.token)
    }

    @discardableResult
    func pairApprove(code: String) async -> String? {
        do {
            struct ApprovePayload: Decodable { var approved: Bool? }
            let _: ApprovePayload = try await post("/api/pair/approve", ["code": code], as: ApprovePayload.self)
            return nil
        } catch { return (error as? APIError)?.errorDescription ?? "确认失败" }
    }

    func loginPhone(phone: String, code: String) async throws -> User {
        let payload: LoginPayload = try await post("/api/login/phone",
                                                   ["phone": phone, "code": code],
                                                   as: LoginPayload.self)
        guard let user = payload.user else { throw APIError.message("登录失败") }
        return user
    }

    func session() async throws -> (ok: Bool, user: User?) {
        let payload: SessionPayload = try await get("/api/session", as: SessionPayload.self)
        return (payload.authenticated ?? false, payload.user)
    }

    func logout() async {
        _ = try? await request("POST", "/api/logout", body: [:])
        clearToken()
    }

    func me() async throws -> User? {
        let payload: MePayload = try await get("/api/me", as: MePayload.self)
        return payload.user
    }

    func user(id: String) async throws -> User {
        let payload: UserPayload = try await get("/api/users/\(id)", as: UserPayload.self)
        guard let user = payload.user else { throw APIError.message("用户不存在") }
        return user
    }

    func nearbyReport(lat: Double, lng: Double, visible: Bool = true) async throws {
        _ = try await request("POST", "/api/nearby", body: [
            "lat": lat, "lng": lng, "visible": visible
        ])
    }

    func nearby(lat: Double?, lng: Double?, gender: String = "all", maxKm: Double = 5)
        async throws -> (people: [NearbyPerson], wider: Int, maxKm: Double) {
        var path = "/api/nearby?gender=\(gender)&maxKm=\(maxKm)"
        if let lat = lat, let lng = lng { path += "&lat=\(lat)&lng=\(lng)" }
        let payload: NearbyPayload = try await get(path, as: NearbyPayload.self)
        return (payload.people, payload.wider ?? 0, payload.maxKm ?? maxKm)
    }

    func nearbyHello(userId: String, text: String) async throws -> String {
        let payload: NearbyHelloPayload = try await post("/api/nearby/hello",
                                                         ["userId": userId, "text": text],
                                                         as: NearbyHelloPayload.self)
        return payload.chatId ?? ""
    }

    func nearbyClear() async throws {
        _ = try await request("DELETE", "/api/nearby")
    }

    func liveRooms() async throws -> [LiveRoom] {
        let p: LivePayload = try await get("/api/live", as: LivePayload.self)
        return p.rooms
    }
    func liveJoin(_ id: String) async throws -> Int {
        let p: LiveJoinPayload = try await post("/api/live/\(id)/join", [:], as: LiveJoinPayload.self)
        return p.watching ?? 0
    }
    func liveLeave(_ id: String) async {
        _ = try? await request("POST", "/api/live/\(id)/leave", body: [:])
    }
    func liveDanmaku(_ id: String, text: String) async throws {
        _ = try await request("POST", "/api/live/\(id)/danmaku", body: ["text": text])
    }
    func liveLike(_ id: String) async throws -> Int {
        let p: LiveLikePayload = try await post("/api/live/\(id)/like", [:], as: LiveLikePayload.self)
        return p.likes ?? 0
    }

    func games() async throws -> [MiniGame] {
        let p: GamesPayload = try await get("/api/games", as: GamesPayload.self)
        return p.items
    }

    func feedItems() async throws -> [FeedItem] {
        let p: FeedPayload = try await get("/api/feed", as: FeedPayload.self)
        return p.items
    }

    func myFeedItems() async throws -> [FeedItem] {
        let p: FeedPayload = try await get("/api/feed?mine=1", as: FeedPayload.self)
        return p.items
    }

    func feed(tab: String = "recommend") async throws -> (items: [FeedItem], style: FeedStyle, flags: FeedFlags) {
        let p: FeedPayload = try await get("/api/feed?tab=\(tab)", as: FeedPayload.self)
        return (p.items, p.style ?? FeedStyle(), p.flags ?? FeedFlags())
    }

    struct GeoPlace: Decodable {
        var name: String?
        var addr: String?
        var lat: Double?
        var lng: Double?
    }
    private struct GeoSearchPayload: Decodable {
        var source: String?
        var places: [GeoPlace]?
    }
    func geoSearch(q: String, lat: Double, lng: Double) async throws -> [GeoPlace] {
        let q2 = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let p: GeoSearchPayload = try await get("/api/geo/search?q=\(q2)&lat=\(lat)&lng=\(lng)",
                                                as: GeoSearchPayload.self)
        return p.places ?? []
    }
    func feedLike(_ id: String) async throws -> (liked: Bool, likes: Int) {

        let p: FeedLikePayload = try await post("/api/feed/like", ["id": id], as: FeedLikePayload.self)
        return (p.liked ?? false, p.likes ?? 0)
    }

    func feedFollow(userId: String, follow: Bool) async -> Bool {
        struct P: Decodable { var following: Bool?; var count: Int? }
        let p: P? = try? await post("/api/feed/follow", ["userId": userId, "follow": follow], as: P.self)
        return p?.following ?? false
    }
    func feedComment(_ id: String, text: String) async throws -> Int {
        let p: FeedCommentPayload = try await post("/api/feed/comment", ["id": id, "text": text],
                                                   as: FeedCommentPayload.self)
        return p.comments ?? 0
    }

    func feedComments(_ id: String) async throws -> [FeedCommentItem] {
        let p: FeedCommentsPayload = try await get("/api/feed/comments?id=\(id)", as: FeedCommentsPayload.self)
        return p.comments ?? []
    }

    func feedSeries(_ id: String) async throws -> (name: String, items: [FeedItem]) {
        let p: FeedSeriesPayload = try await get("/api/feed/series?id=\(id)", as: FeedSeriesPayload.self)
        return (p.name ?? "", p.items ?? [])
    }

    func feedFavorite(_ id: String) async throws -> (favorited: Bool, favorites: Int) {
        let p: FeedFavoritePayload = try await post("/api/feed/favorite", ["id": id], as: FeedFavoritePayload.self)
        return (p.favorited ?? false, p.favorites ?? 0)
    }
    func feedPublish(video: String, desc: String, music: String) async throws -> String {
        let p: FeedPublishPayload = try await post("/api/feed/publish",
                                                   ["video": video, "desc": desc, "music": music],
                                                   as: FeedPublishPayload.self)
        return p.id ?? ""
    }
    func feedDelete(_ id: String) async {
        _ = try? await request("DELETE", "/api/feed/\(id)")
    }

    func feedTrim(_ url: String, top: Double, bottom: Double, left: Double, right: Double) async throws -> String {
        let p: FeedTrimPayload = try await post("/api/feed/trim",
                                                ["url": url, "top": top, "bottom": bottom,
                                                 "left": left, "right": right, "fill": true],
                                                as: FeedTrimPayload.self)
        return p.url ?? url
    }

    func shake(lat: Double?, lng: Double?) async throws -> ShakeResult {
        var body: [String: Any] = [:]
        if let lat = lat, let lng = lng { body["lat"] = lat; body["lng"] = lng }
        return try await post("/api/shake", body, as: ShakeResult.self)
    }

    func callDiag(_ text: String) async {
        _ = try? await request("POST", "/api/call-diag", body: ["text": text])
    }

    func pendingCall() async -> PendingCallInfo? {
        struct Payload: Decodable { var call: PendingCallInfo? }
        let payload: Payload? = try? await get("/api/call/pending", as: Payload.self)
        return payload?.call
    }

    func chats() async throws -> [Chat] {
        let payload: ChatsPayload = try await get("/api/chats", as: ChatsPayload.self)
        return payload.chats
    }

    struct SyncChat: Decodable {
        var id: String
        var title: String?
        var messages: [Message]?
    }
    private struct SyncChatsPayload: Decodable {
        var chats: [Chat]
        var sync: Sync?
        struct Sync: Decodable {
            var chats: [SyncChat]?
            var syncedAt: String?
        }
    }

    func chatsWithRecentMessages(chats: Int = 10, limit: Int = 30) async throws -> (chats: [Chat], synced: [SyncChat], syncedAt: String) {
        let n = max(1, min(30, chats))
        let m = max(5, min(100, limit))
        let p: SyncChatsPayload = try await get("/api/chats?withMessages=1&syncChats=\(n)&syncLimit=\(m)",
                                                as: SyncChatsPayload.self)
        return (p.chats, p.sync?.chats ?? [], p.sync?.syncedAt ?? "")
    }

    func findUserByAccount(_ q: String) async throws -> User? {
        let payload: UsersPayload = try await get("/api/users?q=\(q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q)", as: UsersPayload.self)
        return payload.users.first
    }

    func searchUsers(_ q: String) async throws -> [User] {
        let payload: UsersPayload = try await get("/api/users?q=\(q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q)", as: UsersPayload.self)
        return payload.users
    }

    @discardableResult
    func addFriend(username: String, note: String) async throws -> (accepted: Bool, friend: User?, chat: Chat?) {
        var body: [String: Any] = ["username": username]
        if !note.isEmpty { body["message"] = note }
        let any = try await request("POST", "/api/friends/request", body: body)
        let payload = try decode(any, as: AddFriendPayload.self)
        return (payload.accepted == true, payload.friend, payload.chat)
    }

    @discardableResult
    func addFriend(userId: String, note: String = "") async throws -> (accepted: Bool, friend: User?, chat: Chat?) {
        var body: [String: Any] = ["userId": userId]
        if !note.isEmpty { body["message"] = note }
        let any = try await request("POST", "/api/friends/request", body: body)
        let payload = try decode(any, as: AddFriendPayload.self)
        return (payload.accepted == true, payload.friend, payload.chat)
    }

    struct FriendMeta: Decodable {
        var remark: String?
        var tags: [String]?
        var star: Bool?
        var block: Bool?

        var noMoments: Bool?

        var hideMyMoments: Bool?
        var chatOnly: Bool?

        var addedAt: String?
        var source: String?
        var blockedMe: Bool?
    }

private struct FriendMetaPayload: Decodable {
    var meta: FriendMeta?
    var addedAt: String?
    var source: String?
    var blockedMe: Bool?
}

private struct StarredPayload: Decodable {
    var ids: [String]?
    var list: [Row]?
    struct Row: Decodable {
        var id: String?
        var name: String?
        var avatar: String?
    }
}

    func friendMeta(userId: String) async throws -> FriendMeta {
        let p: FriendMetaPayload = try await get("/api/friends/meta?userId=\(userId)", as: FriendMetaPayload.self)
        var m = p.meta ?? FriendMeta()
        if m.addedAt == nil { m.addedAt = p.addedAt }
        if m.source == nil { m.source = p.source }
        if m.blockedMe == nil { m.blockedMe = p.blockedMe }
        return m
    }

    func starredFriends() async throws -> [String] {
        let p: StarredPayload = try await get("/api/friends/starred", as: StarredPayload.self)
        return p.ids ?? []
    }

    @discardableResult
    func setFriendMeta(userId: String, remark: String? = nil, tags: [String]? = nil,
                       star: Bool? = nil, block: Bool? = nil,
                       noMoments: Bool? = nil, hideMyMoments: Bool? = nil) async -> Bool {
        var body: [String: Any] = ["userId": userId]
        if let v = remark { body["remark"] = v }
        if let v = tags { body["tags"] = v }
        if let v = star { body["star"] = v }
        if let v = block { body["block"] = v }
        if let v = noMoments { body["noMoments"] = v }
        if let v = hideMyMoments { body["hideMyMoments"] = v }
        do { _ = try await request("POST", "/api/friends/meta", body: body); return true }
        catch { return false }
    }

    func removeFriend(userId: String) async -> String? {
        do {
            _ = try await request("POST", "/api/friends/remove", body: ["userId": userId])
            return nil
        } catch {
            return (error as? APIError)?.errorDescription ?? "删除失败"
        }
    }

    private struct ClearFriendsPayload: Decodable {
        var removed: Int?
    }

    func clearAddedFriends() async -> (removed: Int, error: String?) {
        do {
            let payload = try await post("/api/friends/clear", [:], as: ClearFriendsPayload.self)
            return (payload.removed ?? 0, nil)
        } catch {
            return (0, (error as? APIError)?.errorDescription ?? "清除失败")
        }
    }

    struct WalletBankCard: Decodable, Identifiable, Hashable {
        var id: String
        var bank: String?
        var tail: String?
        var holder: String?
        var isDefault: Bool?
        var addedAt: String?
        var label: String { (bank ?? "银行卡") + "（" + (tail ?? "****") + "）" }
    }
    private struct BanksPayload: Decodable { var banks: [WalletBankCard]? }
    private struct BankPayload: Decodable { var bank: WalletBankCard?; var banks: [WalletBankCard]? }

    func walletBanks() async throws -> [WalletBankCard] {
        let p: BanksPayload = try await get("/api/wallet/banks", as: BanksPayload.self)
        return p.banks ?? []
    }

    func addBank(bank: String, cardNo: String, holder: String) async throws -> [WalletBankCard] {
        let p: BankPayload = try await post("/api/wallet/banks",
                                            ["bank": bank, "cardNo": cardNo, "holder": holder],
                                            as: BankPayload.self)
        return p.banks ?? []
    }

    func removeBank(id: String) async {
        _ = try? await request("POST", "/api/wallet/banks/remove", body: ["id": id])
    }

    struct MoneyResult: Decodable {
        var balance: Double?
        var fee: Double?
        var bankText: String?
        var expect: String?
        var status: String?
    }

    func walletRecharge(amount: Double, bankId: String) async throws -> MoneyResult {
        try await post("/api/wallet/recharge", ["amount": amount, "bankId": bankId], as: MoneyResult.self)
    }

    func walletWithdraw(amount: Double, bankId: String, password: String, face: Bool) async throws -> MoneyResult {
        try await post("/api/wallet/withdraw",
                       ["amount": amount, "bankId": bankId, "password": password, "face": face],
                       as: MoneyResult.self)
    }

    struct WalletOp: Decodable, Identifiable, Hashable {
        var id: String
        var kind: String?
        var amount: Double?
        var fee: Double?
        var bankText: String?
        var status: String?
        var createdAt: String?
    }
    private struct OpsPayload: Decodable { var ops: [WalletOp]? }

    func walletOps() async throws -> [WalletOp] {
        let p: OpsPayload = try await get("/api/wallet/withdraws", as: OpsPayload.self)
        return p.ops ?? []
    }

    struct StorageChat: Decodable, Identifiable {
        var chatId: String
        var title: String
        var avatar: String?
        var messages: Int
        var bytes: Int
        var id: String { chatId }
    }
    struct StorageInfo: Decodable {
        struct Kinds: Decodable {
            var image: Int
            var video: Int
            var file: Int
            var audio: Int
        }
        var total: Int
        var chats: [StorageChat]
        var kinds: Kinds
        var uploads: Int
    }
    func storage() async throws -> StorageInfo {
        try await get("/api/storage", as: StorageInfo.self)
    }

    struct RedPacketRaw: Decodable {
        var id: String
        var total: Double?
        var count: Int?
        var claimedCount: Int?
        var claimedIds: [String]?
        var type: String?
        var note: String?
        var status: String?
        var expired: Bool?
        var fromId: String?
        var fromName: String?
        var expiresAt: Double?
        var refundAmount: Double?

        var coverId: String?
        var coverName: String?
        var cover: String?
        var coverThumb: String?
        var coverColor: String?

        var fromAvatar: String?
        var claimedTotal: Double?
        var leftAmount: Double?
        var leftCount: Int?
        var bestUserId: String?
        var bestAmount: Double?
        var claims: [RedPacketClaimRaw]?
    }
    struct RedPacketClaimRaw: Decodable {
        var userId: String
        var name: String?
        var avatar: String?
        var amount: Double
        var at: String?
        var fromId: String?
        var fromName: String?
    }
    struct RedPacketSendResult: Decodable {
        var balance: Double
        var amount: Double?
        var count: Int?
        var type: String?
        var redpacket: RedPacketRaw
    }
    struct RedPacketClaimResult: Decodable {
        var balance: Double
        var amount: Double
        var redpacket: RedPacketRaw
        var leftCount: Int?
    }
    struct RedPacketDetailResult: Decodable {
        var redpacket: RedPacketRaw
    }
    struct RedPacketRecord: Decodable, Identifiable {
        var id: String
        var chatId: String?
        var direction: String?
        var total: Double?
        var count: Int?
        var type: String?
        var note: String?
        var status: String?
        var expired: Bool?
        var claimedCount: Int?
        var fromName: String?
        var fromAvatar: String?
        var mineAmount: Double?
        var createdAt: String?
        var expiresAt: Double?
    }
    struct RedPacketMineResult: Decodable {
        var redpackets: [RedPacketRecord]?
    }

    struct RedPacketCoverRaw: Decodable, Identifiable {
        var id: String
        var name: String?
        var image: String?
        var thumb: String?
        var color: String?
    }
    struct RedPacketCoversResult: Decodable {
        var covers: [RedPacketCoverRaw]?
        var defaultId: String?
        var mine: String?
    }
    struct RedPacketCoverPick: Decodable {
        var coverId: String?
        var name: String?
    }

    struct FAQPayload: Decodable {
        var title: String?
        var searchHint: String?
        var categories: [SupportCategory]?
        var hot: [SupportItem]?
    }

    struct WalletLevelStep: Decodable {
        var key: String?
        var name: String?
        var done: Bool?
        var hint: String?
    }
    struct WalletLevelRow: Decodable {
        var level: Int?
        var name: String?
        var single: Double?
        var day: Double?
        var current: Bool?
        var done: Bool?
    }
    struct WalletLevel: Decodable {
        var level: Int?
        var levelName: String?
        var tip: String?
        var single: Double?
        var day: Double?
        var receive: Double?
        var usedToday: Double?
        var leftToday: Double?
        var realName: Bool?
        var bankCount: Int?
        var upgradedAt: String?
        var levels: [WalletLevelRow]?
        var steps: [WalletLevelStep]?
    }
    struct WalletUpgradeResult: Decodable {
        var level: Int?
        var levelName: String?
        var single: Double?
        var day: Double?
    }

    struct BizRecordRaw: Decodable, Identifiable {
        var id: String
        var kind: String?
        var amount: Double?
        var fromName: String?
        var fromId: String?
        var method: String?
        var note: String?
        var orderNo: String?
        var status: String?
        var settled: Bool?
        var createdAt: String?
    }
    struct BizInvoiceRaw: Decodable, Identifiable {
        var id: String
        var amount: Double?
        var status: String?
        var title: String?
        var taxNo: String?
        var kind: String?
        var note: String?
        var createdAt: String?
        var handledAt: String?
    }
    struct BizSettingsRaw: Decodable {
        var arrival: String?
        var notify: Bool?
        var autoWithdraw: Bool?
        var settle: String?
        var feeRate: Double?
        var shopName: String?
        var remark: String?
    }
    struct BizInvoiceInfoRaw: Decodable {
        var title: String?
        var taxNo: String?
        var address: String?
        var phone: String?
        var bankName: String?
        var bankAccount: String?
    }
    struct BizTotals: Decodable {
        var today: Double?
        var month: Double?
        var all: Double?
        var count: Int?
        var withdrawn: Double?
    }
    struct BizPayload: Decodable {
        var enabled: Bool?
        var balance: Double?
        var settings: BizSettingsRaw?
        var invoice: BizInvoiceInfoRaw?
        var records: [BizRecordRaw]?
        var invoices: [BizInvoiceRaw]?
        var totals: BizTotals?
        var invoiceReady: Bool?
    }
    struct BizWithdrawResult: Decodable {
        var balance: Double?
        var bizBalance: Double?
        var amount: Double?
    }

    struct IdentityInfo: Decodable {
        var verified: Bool?
        var realName: String?
        var idMask: String?
        var verifiedAt: String?
        var idValid: String?
        var occupation: String?
        var address: String?
        var level: Int?
        var levelName: String?
        var bankCount: Int?
    }

    struct AutoDebit: Decodable, Identifiable {
        var id: String
        var name: String?
        var amount: Double?
        var cycle: String?
        var createdAt: String?
    }
    struct PaySettings: Decodable {
        var hasPayPassword: Bool?
        var noPin: Bool?
        var noPinLimit: Double?
        var payMethod: String?
        var autoDebits: [AutoDebit]?
        var payPasswordUpdatedAt: String?
    }
    struct SimpleOK: Decodable { var saved: Bool? }

    func identity() async throws -> IdentityInfo {
        try await get("/api/me/identity", as: IdentityInfo.self)
    }
    func saveIdentity(idValid: String, occupation: String, address: String) async {
        let _: SimpleOK? = try? await post("/api/me/identity",
            ["idValid": idValid, "occupation": occupation, "address": address], as: SimpleOK.self)
    }
    func paySettings() async throws -> PaySettings {
        try await get("/api/me/paysettings", as: PaySettings.self)
    }

    struct PayScoreDim: Decodable, Identifiable {
        var key: String
        var name: String
        var value: Double

        var weight: Double?

        var points: Double?
        var max: Double?
        var desc: String?
        var tip: String?
        var id: String { key }
    }
    struct PayScoreService: Decodable, Identifiable {
        var id: String
        var name: String
        var desc: String?
        var need: Double?
        var ok: Bool?
        var gap: Double?
    }
    struct PayScoreHistory: Decodable, Identifiable {
        var at: String
        var text: String
        var delta: Double
        var id: String { at + text + String(delta) }
    }
    struct PayScore: Decodable {
        var score: Double
        var level: String
        var min: Double
        var max: Double

        var formula: String?
        var updatedAt: String?
        var dims: [PayScoreDim]?
        var services: [PayScoreService]?
        var history: [PayScoreHistory]?
        var note: String?
    }
    func payScore() async throws -> PayScore {
        try await get("/api/me/payscore", as: PayScore.self)
    }

    struct TeenStatus: Decodable {
        var enabled: Bool?
        var hasPin: Bool?
        var scopes: [String: Int]?
        var guardianPhone: String?
        var setAt: String?
    }
    private struct TeenPayload: Decodable { var teen: TeenStatus? }

    func teen() async throws -> TeenStatus {
        let p: TeenPayload = try await get("/api/me/teen", as: TeenPayload.self)
        return p.teen ?? TeenStatus()
    }
    func teenSetup(pin: String) async throws -> TeenStatus {
        let p: TeenPayload = try await post("/api/me/teen/setup", ["pin": pin], as: TeenPayload.self)
        return p.teen ?? TeenStatus()
    }
    func teenSet(pin: String, enabled: Bool?, scopes: [String: Int]?, guardianPhone: String?) async throws -> TeenStatus {
        var body: [String: Any] = ["pin": pin]
        if let e = enabled { body["enabled"] = e }
        if let s = scopes { body["scopes"] = s }
        if let g = guardianPhone { body["guardianPhone"] = g }
        let p: TeenPayload = try await post("/api/me/teen/set", body, as: TeenPayload.self)
        return p.teen ?? TeenStatus()
    }
    func savePaySettings(noPin: Bool, noPinLimit: Double, payMethod: String) async {
        let _: SimpleOK? = try? await post("/api/me/paysettings",
            ["noPin": noPin, "noPinLimit": noPinLimit, "payMethod": payMethod], as: SimpleOK.self)
    }
    func cancelAutoDebit(_ id: String) async {
        let _: SimpleOK? = try? await post("/api/me/paysettings", ["cancelAutoDebit": id], as: SimpleOK.self)
    }

    struct FavoriteItem: Decodable, Identifiable {
        var id: String
        var kind: String?
        var content: String?
        var createdAt: String?
        var chatId: String?
        var fromName: String?
    }
    private struct FavoritesPayload: Decodable { var favorites: [FavoriteItem]? }

    func favorites() async -> [FavoriteItem] {
        let p: FavoritesPayload? = try? await get("/api/favorites", as: FavoritesPayload.self)
        return p?.favorites ?? []
    }

    func deleteFavorite(_ id: String) async {
        _ = try? await request("DELETE", "/api/favorites/" + id)
    }

    struct MyFileItem: Decodable, Identifiable, Hashable {
        var id: String
        var url: String?
        var name: String?
        var bytes: Int?
        var at: String?
        var chatId: String?
        var chatName: String?
        var mine: Bool?

        var fileName: String { name ?? "文件" }
        var ext: String {
            let n = fileName.lowercased()
            guard let dot = n.lastIndex(of: ".") else { return "" }
            return String(n[n.index(after: dot)...])
        }
    }
    private struct MyFilesPayload: Decodable { var files: [MyFileItem]? }

    func myFiles() async -> [MyFileItem] {
        guard let p = try? await get("/api/files/mine", as: MyFilesPayload.self) else { return [] }
        return p.files ?? []
    }

    @discardableResult
    func updateFavorite(id: String, content: String? = nil, title: String? = nil,
                        pinned: Bool? = nil) async -> Bool {
        var b: [String: Any] = [:]
        if let c = content { b["content"] = c }
        if let t = title { b["title"] = t }
        if let p = pinned { b["pinned"] = p }
        do {
            _ = try await request("PATCH", "/api/favorites/" + id, body: b)
            return true
        } catch {
            return false
        }
    }
    struct BizInvoiceResult: Decodable {
        var invoice: BizInvoiceRaw?
        var invoices: [BizInvoiceRaw]?
    }

    func biz() async throws -> BizPayload {
        try await get("/api/biz", as: BizPayload.self)
    }
    func bizSave(enabled: Bool, arrival: String, notify: Bool, autoWithdraw: Bool,
                 shopName: String, remark: String) async throws {
        let _: BizSettingsRaw = try await post("/api/biz/settings", [
            "enabled": enabled, "arrival": arrival, "notify": notify,
            "autoWithdraw": autoWithdraw, "shopName": shopName, "remark": remark
        ], as: BizSettingsRaw.self)
    }
    func bizSaveInvoice(title: String, taxNo: String, address: String, phone: String,
                        bankName: String, bankAccount: String) async throws {
        let _: BizInvoiceInfoRaw = try await post("/api/biz/invoice", [
            "title": title, "taxNo": taxNo, "address": address, "phone": phone,
            "bankName": bankName, "bankAccount": bankAccount
        ], as: BizInvoiceInfoRaw.self)
    }
    func bizApplyInvoice(amount: Double, kind: String, note: String) async throws -> [BizInvoiceRaw] {
        let r: BizInvoiceResult = try await post("/api/biz/invoice/apply",
            ["amount": amount, "kind": kind, "note": note], as: BizInvoiceResult.self)
        return r.invoices ?? []
    }
    func bizWithdraw(amount: Double, all: Bool, password: String, face: Bool) async throws -> BizWithdrawResult {
        try await post("/api/biz/withdraw",
            ["amount": amount, "all": all, "password": password, "face": face], as: BizWithdrawResult.self)
    }

    func faq() async throws -> FAQPayload {
        try await get("/api/faq", as: FAQPayload.self)
    }

    func walletLevel() async throws -> WalletLevel {
        try await get("/api/me/wallet", as: WalletLevel.self)
    }

    func walletUpgrade() async throws -> WalletUpgradeResult {
        try await post("/api/me/wallet-upgrade", [:], as: WalletUpgradeResult.self)
    }

    func sendRedPacket(chatId: String, amount: Double, count: Int, type: String,
                       note: String, password: String = "", face: Bool = false,
                       coverId: String = "") async throws -> RedPacketSendResult {
        try await post("/api/pay/redpacket", [
            "chatId": chatId, "amount": amount, "count": count, "type": type,
            "note": note, "password": password, "face": face, "coverId": coverId,

            "requestId": UUID().uuidString
        ], as: RedPacketSendResult.self)
    }

    func redPacketCovers() async throws -> (covers: [RedPacketCoverRaw], defaultId: String, mine: String) {
        let r: RedPacketCoversResult = try await get("/api/redpacket/covers", as: RedPacketCoversResult.self)
        return (r.covers ?? [], r.defaultId ?? "", r.mine ?? "")
    }

    func chooseRedPacketCover(id: String) async throws {
        let _: RedPacketCoverPick = try await post("/api/redpacket/cover", ["id": id], as: RedPacketCoverPick.self)
    }

    func claimRedPacket(id: String) async throws -> RedPacketClaimResult {
        try await post("/api/redpackets/\(id)/claim", [:], as: RedPacketClaimResult.self)
    }

    func redPacketDetail(id: String) async throws -> RedPacketRaw {
        let payload: RedPacketDetailResult = try await get("/api/redpackets/\(id)", as: RedPacketDetailResult.self)
        return payload.redpacket
    }

    func myRedPackets() async throws -> [RedPacketRecord] {
        let payload: RedPacketMineResult = try await get("/api/redpackets/mine", as: RedPacketMineResult.self)
        return payload.redpackets ?? []
    }

    struct SupportItem: Decodable, Identifiable {
        var q: String
        var a: String
        var id: String { q }
    }
    struct SupportCategory: Decodable, Identifiable {
        var id: String
        var title: String
        var icon: String?
        var items: [SupportItem]?
    }
    struct SupportAgent: Decodable {
        var id: String
        var nickname: String?
        var avatar: String?
    }
    struct SupportTicket: Decodable, Identifiable {
        var id: String
        var category: String?
        var title: String?
        var content: String?
        var status: String?
        var reply: String?
        var createdAt: String?
        var repliedAt: String?
        var doneAt: String?
    }
    struct SupportPayload: Decodable {
        var title: String?
        var searchHint: String?
        var human: Int?
        var ticketOn: Int?
        var phone: String?
        var email: String?
        var workTime: String?
        var greet: String?
        var ticketHint: String?
        var categories: [SupportCategory]?
        var agent: SupportAgent?
        var tickets: [SupportTicket]?
    }
    struct SupportHuman: Decodable {
        var chatId: String
        var agent: SupportAgent?
    }
    struct SupportTicketResult: Decodable {
        var ticket: SupportTicket?
        var tickets: [SupportTicket]?
    }

    func support() async throws -> SupportPayload {
        try await get("/api/support", as: SupportPayload.self)
    }

    func supportHuman() async throws -> SupportHuman {
        try await post("/api/support/human", [:], as: SupportHuman.self)
    }

    func supportTicket(category: String, content: String, contact: String = "") async throws -> [SupportTicket] {
        let payload: SupportTicketResult = try await post("/api/support/ticket",
            ["category": category, "content": content, "contact": contact],
            as: SupportTicketResult.self)
        return payload.tickets ?? []
    }

    struct LiveStart: Decodable { var sessionId: String; var joined: Bool? }
    struct LiveMember: Decodable {
        var userId: String
        var name: String?
        var avatar: String?
        var lat: Double?
        var lng: Double?
        var at: Double?
    }
    struct LiveStatePayload: Decodable {
        var sessionId: String
        var chatId: String?
        var fromId: String?
        var members: [LiveMember]
    }

    func liveStart(chatId: String, lat: Double? = nil, lng: Double? = nil) async -> (sessionId: String, joined: Bool)? {
        var body: [String: Any] = ["chatId": chatId]
        if let lat = lat, let lng = lng { body["lat"] = lat; body["lng"] = lng }
        guard let r: LiveStart = try? await post("/api/live/start", body, as: LiveStart.self) else { return nil }
        return (r.sessionId, r.joined ?? false)
    }

    func livePos(sessionId: String, lat: Double, lng: Double) async {
        _ = try? await request("POST", "/api/live/pos",
                               body: ["sessionId": sessionId, "lat": lat, "lng": lng])
    }

    func liveState(sessionId: String) async -> LiveStatePayload? {
        try? await get("/api/live/\(sessionId)/state", as: LiveStatePayload.self)
    }

    func liveStop(sessionId: String) async {
        _ = try? await request("POST", "/api/live/stop", body: ["sessionId": sessionId])
    }

    func changePassword(current: String, new: String) async throws {
        _ = try await request("POST", "/api/me/password",
                              body: ["currentPassword": current, "newPassword": new])
    }

    func logoutOtherDevices() async -> String? {
        do {
            _ = try await request("POST", "/api/me/logout-others", body: [:])
            return nil
        } catch {
            return (error as? APIError)?.errorDescription ?? "操作失败"
        }
    }

    struct LoginDevice: Decodable, Identifiable, Hashable {
        var id: String

        var name: String?

        var device: String?

        var model: String?

        var os: String?
        var kind: String?
        var ip: String?
        var province: String?

        var at: Double?

        var current: Bool?

        private enum CodingKeys: String, CodingKey {
            case id, name, device, model, os, kind, ip, province, at, current
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = (try? c.decode(String.self, forKey: .id)) ?? ""
            name = try? c.decodeIfPresent(String.self, forKey: .name)
            device = try? c.decodeIfPresent(String.self, forKey: .device)
            model = try? c.decodeIfPresent(String.self, forKey: .model)
            os = try? c.decodeIfPresent(String.self, forKey: .os)
            kind = try? c.decodeIfPresent(String.self, forKey: .kind)
            ip = try? c.decodeIfPresent(String.self, forKey: .ip)
            province = try? c.decodeIfPresent(String.self, forKey: .province)
            current = try? c.decodeIfPresent(Bool.self, forKey: .current)
            if let n = try? c.decodeIfPresent(Double.self, forKey: .at) {
                at = n
            } else if let s = try? c.decodeIfPresent(String.self, forKey: .at) {
                at = LoginDevice.msOf(s)
            } else {
                at = nil
            }
        }

        static func msOf(_ s: String) -> Double {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f.date(from: s) { return d.timeIntervalSince1970 * 1000 }
            f.formatOptions = [.withInternetDateTime]
            if let d = f.date(from: s) { return d.timeIntervalSince1970 * 1000 }
            return 0
        }
    }

    func devices() async -> [LoginDevice] {
        struct Payload: Decodable { var devices: [LoginDevice]? }
        guard let p: Payload = try? await get("/api/devices", as: Payload.self) else { return [] }
        return p.devices ?? []
    }

    func touchCurrentDevice() async {
        _ = try? await request("GET", "/api/devices")
    }

    func musicTracks() async -> [MusicTrack] {
        struct Payload: Decodable { var tracks: [MusicTrack]? }
        guard let p: Payload = try? await get("/api/music", as: Payload.self) else { return [] }
        return p.tracks ?? []
    }

    func miniApps(kind: String = "") async -> [MiniApp] {
        struct Payload: Decodable { var items: [MiniApp]? }
        let path = kind.isEmpty ? "/api/miniapps" : "/api/miniapps?kind=\(kind)"
        guard let p: Payload = try? await get(path, as: Payload.self) else { return [] }
        return p.items ?? []
    }

    func removeDevice(id: String) async -> String? {
        do {
            _ = try await request("POST", "/api/devices/remove", body: ["id": id])
            return nil
        } catch {
            return (error as? APIError)?.errorDescription ?? "删除失败"
        }
    }

    func registerPushToken(_ token: String, sandbox: Bool) async {
        _ = try? await request("POST", "/api/push/register", body: [
            "token": token,
            "platform": "ios",
            "env": sandbox ? "sandbox" : "prod",
            "deviceId": AppInfo.deviceId,
            "bundleId": Bundle.main.bundleIdentifier ?? ""
        ])
    }

    func unregisterPushToken(_ token: String) async {
        guard !token.isEmpty else { return }
        _ = try? await request("POST", "/api/push/unregister", body: ["token": token])
    }

    func reportPushSettings(status: String, badge: Bool, alert: Bool, sound: Bool,
                            token: String, sandbox: Bool) async {
        _ = try? await request("POST", "/api/push/settings", body: [
            "status": status, "badge": badge, "alert": alert, "sound": sound,
            "token": token, "env": sandbox ? "sandbox" : "prod"
        ])
    }

    struct PushStatus: Decodable {
        var configured: Bool?
        var enabled: Bool?
        var sandbox: Bool?
        var devices: Int?
    }

    func pushStatus() async -> PushStatus? {
        try? await get("/api/push/status", as: PushStatus.self)
    }

    func directChat(userId: String) async throws -> Chat {
        let payload: ChatPayload = try await post("/api/chats/direct", ["userId": userId], as: ChatPayload.self)
        guard let chat = payload.chat else { throw APIError.message("会话创建失败") }
        return chat
    }

    func messages(chatId: String, limit: Int = 40, before: Int? = nil,
                  all: Bool = false) async throws -> (chat: Chat?, messages: [Message], hasMore: Bool) {
        var path = "/api/chats/\(chatId)/messages?limit=\(limit)"
        if let before = before { path += "&before=\(before)" }
        if all { path += "&all=1" }
        let payload: MessagesPayload = try await get(path, as: MessagesPayload.self)
        return (payload.chat, payload.messages, payload.hasMore ?? false)
    }

    func messagesSince(chatId: String, since: Int, limit: Int = 200)
        async throws -> (chat: Chat?, messages: [Message], hasMore: Bool) {
        let path = "/api/chats/\(chatId)/messages?limit=\(limit)&since=\(max(0, since))"
        let payload: MessagesPayload = try await get(path, as: MessagesPayload.self)
        return (payload.chat, payload.messages, payload.hasMore ?? false)
    }

    func allMessages(chatId: String, limit: Int = 20_000, before: Int? = nil)
        async throws -> (chat: Chat?, messages: [Message], hasMore: Bool) {
        try await messages(chatId: chatId, limit: limit, before: before, all: true)
    }

    func send(chatId: String, text: String) async throws -> Message? {
        let payload: MessagePayload = try await post("/api/chats/\(chatId)/messages",
                                                     ["kind": "text", "content": text],
                                                     as: MessagePayload.self)
        return payload.message
    }

    func chatMembers(chatId: String) async throws -> (members: [User], ownerId: String, createdAt: String) {
        let p: ChatMembersPayload = try await get("/api/chats/\(chatId)/members", as: ChatMembersPayload.self)
        return (p.members ?? [], p.ownerId ?? "", p.createdAt ?? "")
    }

    @discardableResult
    func setGroupAlias(chatId: String, userId: String = "", alias: String) async -> Bool {
        struct P: Decodable { var alias: String? }
        var body: [String: Any] = ["alias": alias]
        if !userId.isEmpty { body["userId"] = userId }
        return (try? await post("/api/chats/\(chatId)/alias", body, as: P.self)) != nil
    }

    func growthMe() async throws -> GrowthMe {
        struct P: Decodable { var growth: GrowthMe }
        let p: P = try await get("/api/growth/me", as: P.self)
        return p.growth
    }

    func growthPing(seconds: Int) async throws -> GrowthMe {
        struct P: Decodable { var growth: GrowthMe }
        let p: P = try await post("/api/growth/ping", ["seconds": seconds], as: P.self)
        return p.growth
    }

    func growthRank() async throws -> (rows: [GrowthRankRow], me: GrowthRankRow?) {
        struct P: Decodable { var rank: [GrowthRankRow]?; var me: GrowthRankRow? }
        let p: P = try await get("/api/growth/rank", as: P.self)
        return (p.rank ?? [], p.me)
    }

    struct WalletCardsPayload: Decodable { var cards: [WalletCard]? }

    func walletCards() async -> [WalletCard] {
        guard let r: WalletCardsPayload = try? await get("/api/cards", as: WalletCardsPayload.self) else { return [] }
        return r.cards ?? []
    }

    @discardableResult
    func cardUse(id: String) async -> Bool {
        struct P: Decodable { var card: WalletCard? }
        let r: P? = try? await post("/api/cards/use", ["id": id], as: P.self)
        return (r?.card) != nil
    }

    func walletCardsDiag() async -> (cards: [WalletCard], note: String) {
        do {
            let any = try await request("GET", "/api/cards")
            let raw = ((any as? [String: Any])?["cards"] as? [Any])?.count ?? -1
            do {
                let data = try JSONSerialization.data(withJSONObject: any, options: [])
                let payload = try JSONDecoder().decode(WalletCardsPayload.self, from: data)
                return (payload.cards ?? [], "卡包：服务器回了 \(payload.cards?.count ?? 0) 张卡（请求成功）")
            } catch {
                return ([], "卡包：解码失败（原文 \(raw) 条）\(error)")
            }
        } catch {
            let e = error as NSError
            return ([], "卡包：请求失败 \(e.domain) #\(e.code)｜\(error.localizedDescription)")
        }
    }

    struct ShopItem: Decodable, Identifiable, Hashable {
        var id: String
        var name: String
        var price: Double
        var img: String?
        var kind: String?
        var desc: String?
        var stock: Int?
        var on: Bool?
        var sort: Int?

        var isPhysical: Bool { (kind ?? "physical") != "virtual" }
        var kindName: String { isPhysical ? "实物" : "虚拟" }
    }

    struct ShopOrder: Decodable, Identifiable, Hashable {
        var id: String
        var kind: String?
        var itemId: String?
        var name: String?
        var price: Double?
        var address: String?
        var at: String?
        var status: String?
    }

    struct ShopPayload: Decodable {
        var items: [ShopItem]?
        var orders: [ShopOrder]?
        var balance: Double?
    }

    struct ShopItemsPayload: Decodable { var items: [ShopItem]? }
    struct ShopOrderPayload: Decodable { var order: ShopOrder?; var balance: Double? }

    func shopData() async throws -> ShopPayload {
        try await get("/api/shop", as: ShopPayload.self)
    }

    func shopOrder(itemId: String, count: Int, address: String,
                   payPassword: String) async throws -> ShopOrderPayload {
        var b: [String: Any] = ["itemId": itemId, "count": count, "address": address]
        if !payPassword.isEmpty { b["payPassword"] = payPassword }
        return try await post("/api/shop/order", b, as: ShopOrderPayload.self)
    }

    struct MallPayload: Decodable {
        var products: [DDProduct]?
        var banners: [String]?

        var name: String?
        var slogan: String?

        var ads: [DDAd]?

        struct Delivery: Decodable { var modes: [DDDeliveryMode]?; var note: String? }
        var delivery: Delivery?

        var splash: DDSplash?

        var channels: [DDChannelItem]?
    }

    func mallData() async -> (ok: Bool, products: [DDProduct], banners: [String], name: String, slogan: String,
                              ads: [DDAd], delivery: [DDDeliveryMode], splash: DDSplash?,
                              channels: [DDChannelItem]?) {
        guard let p: MallPayload = try? await get("/api/mall", as: MallPayload.self) else {
            return (false, [], [], "", "", [], [], nil, [])
        }

        return (true, p.products ?? [], p.banners ?? [], p.name ?? "", p.slogan ?? "",
                p.ads ?? [], p.delivery?.modes ?? [], p.splash, p.channels)
    }

    @discardableResult
    func opsMall(_ body: [String: Any]) async -> Bool {
        (try? await post("/api/ops/mall", body, as: MallPayload.self)) != nil
    }

    func deleteAccount(confirm: String) async -> Bool {
        struct R: Decodable { var deleted: Bool? }
        let r: R? = try? await post("/api/me/delete", ["confirm": confirm], as: R.self)
        return r?.deleted == true
    }

    struct MallCoupon: Decodable, Identifiable {
        var id: String
        var title: String
        var off: Double
        var min: Double
        var until: String?
        var kind: String?
        var used: Bool?
    }
    struct MallAdMine: Decodable {
        var coupons: [MallCoupon]?

        var newCount: Int?

        var claimable: [String]?
        var claimableCount: Int?
    }
    struct MallAdClaim: Decodable {
        var already: Bool?
        var note: String?
        var coupon: MallCoupon?
    }
    struct MallAdShare: Decodable {
        var code: String?
        var text: String?
        var invited: Int?
        var need: Int?
    }

    func mallAdMine() async -> MallAdMine? {
        try? await post("/api/mall/ad", ["do": "mine"], as: MallAdMine.self)
    }

    func mallAdSeen() async {
        let _: MallAdMine? = try? await post("/api/mall/ad", ["do": "seen"], as: MallAdMine.self)
    }

    func mallAdClaim(adId: String) async -> MallAdClaim? {
        try? await post("/api/mall/ad", ["do": "claim", "adId": adId], as: MallAdClaim.self)
    }

    func mallAdShare(adId: String) async -> MallAdShare? {
        try? await post("/api/mall/ad", ["do": "share", "adId": adId], as: MallAdShare.self)
    }

    struct MallInviteResult: Decodable {
        var mine: MallCoupon?
        var host: MallCoupon?
        var bonus: MallCoupon?
        var invited: Int?
        var hostName: String?
        var note: String?
    }
    func mallAdInvite(code: String, adId: String = "ad1") async -> MallInviteResult? {
        try? await post("/api/mall/ad", ["do": "invite", "code": code, "adId": adId],
                        as: MallInviteResult.self)
    }

    struct DistMe: Decodable {
        var on: Bool?
        var code: String?
        var rate: Double?
        var earned: Double?
        var orders: Int?
        var pending: Int?
        var balance: Double?
        struct LogRow: Decodable, Identifiable {
            var at: String
            var text: String
            var amount: Double
            var id: String { at + text }
        }
        var log: [LogRow]?
    }
    func distMe() async -> DistMe? {
        try? await get("/api/dist/me", as: DistMe.self)
    }
    @discardableResult
    func opsDistSet(userId: String, on: Bool, rate: Double) async -> Bool {
        (try? await post("/api/ops/dist/set", ["to": userId, "on": on, "rate": rate],
                         as: SimpleOK.self)) != nil
    }
    struct DistRow: Decodable, Identifiable {
        var userId: String
        var name: String?
        var code: String?
        var rate: Double?
        var earned: Double?
        var orders: Int?
        var pending: Int?
        var id: String { userId }
    }
    func opsDistList() async -> [DistRow] {
        struct P: Decodable { var dists: [DistRow]? }
        let p: P? = try? await get("/api/ops/dist", as: P.self)
        return p?.dists ?? []
    }

    struct TrackEntry: Decodable, Identifiable, Hashable {
        var time: String
        var text: String

        var src: String?
        var id: String { (src ?? "") + time + text }
        var isCarrier: Bool { src == "carrier" }
    }
    struct TrackPayload: Decodable {
        var id: String?
        var status: String?
        var express: Express?
        var note: String?
        var logistics: [TrackEntry]?
        struct Express: Decodable, Hashable { var company: String?; var no: String?; var code: String? }
    }
    struct OpsOrderRow: Decodable, Identifiable {
        var id: String
        var at: String?
        var total: Double?
        var status: String?
        var statusText: String?
        var address: String?
        var remark: String?
        var buyer: String?
        var items: [String]?
        var express: TrackPayload.Express?
    }

    @discardableResult
    func mallOrderSync(id: String, items: [[String: Any]], total: Double, payWay: String,
                       address: String, at: String, remark: String = "", ref: String = "",
                       paid: Bool = true) async -> Bool {
        (try? await post("/api/mall/order",
                         ["id": id, "items": items, "total": total, "payWay": payWay,
                          "address": address, "at": at, "remark": remark, "ref": ref,
                          "paid": paid],
                         as: SimpleOK.self)) != nil
    }

    func alipayCreate(orderId: String) async throws -> (orderStr: String, sandbox: Bool) {
        struct R: Decodable { var orderStr: String?; var sandbox: Bool? }
        let p: R = try await post("/api/pay/alipay/create", ["orderId": orderId], as: R.self)
        return (p.orderStr ?? "", p.sandbox ?? false)
    }

    func alipayStatus(id: String) async -> (paid: Bool, alipayNo: String) {
        struct R: Decodable { var paid: Bool?; var alipayNo: String? }
        let p: R? = try? await get("/api/pay/alipay/status?id=" + id, as: R.self)
        return (p?.paid ?? false, p?.alipayNo ?? "")
    }

    func weather(city: String? = nil, lat: Double? = nil, lon: Double? = nil) async -> DDWeatherNow? {
        var q = ""
        if let city, !city.isEmpty {
            let c = city.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            q = "?city=" + c
        } else if let lat, let lon {
            q = "?lat=" + String(format: "%.3f", lat) + "&lon=" + String(format: "%.3f", lon)
        }
        return try? await get("/api/weather" + q, as: DDWeatherNow.self)
    }

    func cityHot() async -> [DDCityItem] {
        struct P: Decodable { var cities: [DDCityItem]? }
        let p: P? = try? await get("/api/city/hot", as: P.self)
        return p?.cities ?? []
    }
    func citySearch(_ q: String) async -> [DDCityItem] {
        struct P: Decodable { var cities: [DDCityItem]? }
        let s = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let p: P? = try? await get("/api/city/search?q=" + s, as: P.self)
        return p?.cities ?? []
    }

    func cityHere(lat: Double, lon: Double) async -> DDCityItem? {
        struct P: Decodable { var city: String?; var lat: Double?; var lon: Double? }
        let p: P? = try? await get("/api/city/here?lat=" + String(format: "%.3f", lat)
                                   + "&lon=" + String(format: "%.3f", lon), as: P.self)
        guard let p, let n = p.city, !n.isEmpty else { return nil }
        return DDCityItem(name: n, admin: nil, country: nil, lat: p.lat ?? lat, lon: p.lon ?? lon)
    }

    func mallOrders() async -> [OpsOrderRow] {
        struct P: Decodable { var orders: [OpsOrderRow]? }
        let p: P? = try? await get("/api/mall/orders", as: P.self)
        return p?.orders ?? []
    }

    func mallTrack(orderId: String) async -> TrackPayload? {
        try? await get("/api/mall/logistics?id=" + orderId, as: TrackPayload.self)
    }

    @discardableResult
    func mallAfterSale(orderId: String, kind: String, reason: String) async -> Bool {
        (try? await post("/api/mall/aftersale",
                         ["id": orderId, "kind": kind, "reason": reason],
                         as: SimpleOK.self)) != nil
    }

    func opsMallOrders(only: String = "wait") async -> [OpsOrderRow] {
        struct P: Decodable { var orders: [OpsOrderRow]? }
        let p: P? = try? await get("/api/ops/mallorders?only=" + only, as: P.self)
        return p?.orders ?? []
    }

    @discardableResult
    func opsShip(orderId: String, company: String, no: String) async -> Bool {
        (try? await post("/api/ops/ship", ["id": orderId, "company": company, "no": no],
                         as: SimpleOK.self)) != nil
    }

    @discardableResult
    func opsPushTrack(orderId: String, text: String) async -> Bool {
        (try? await post("/api/ops/logistics", ["id": orderId, "text": text],
                         as: SimpleOK.self)) != nil
    }

    @discardableResult
    func opsSendCoupon(to: String, title: String, off: Double, min: Double, days: Int,
                       count: Int = 1, kind: String = "cash") async -> Int? {
        struct P: Decodable { var sent: Int? }
        let p: P? = try? await post("/api/ops/coupon/send",
                                    ["to": to, "title": title, "off": off, "min": min,
                                     "days": days, "count": count, "kind": kind], as: P.self)
        return p?.sent
    }

    struct AfterSaleRow: Decodable, Identifiable {
        var orderId: String
        var buyer: String?
        var total: Double?
        var item: String?
        var kind: String?
        var reason: String?
        var status: String?
        var note: String?
        var askAt: String?
        var id: String { orderId }
    }
    func opsAfterSales(only: String = "pending") async -> [AfterSaleRow] {
        struct P: Decodable { var orders: [AfterSaleRow]? }
        let p: P? = try? await get("/api/ops/aftersales?only=" + only, as: P.self)
        return p?.orders ?? []
    }

    @discardableResult
    func opsAfterSaleReview(orderId: String, pass: Bool, note: String) async -> Bool {
        (try? await post("/api/ops/aftersale/review",
                         ["id": orderId, "pass": pass, "note": note], as: SimpleOK.self)) != nil
    }

    struct EyesInfo: Decodable {
        var eyes: String?
        var paid: Bool?
        var price: Double?
        var balance: Double?
        var tier: String { eyes ?? "on" }
    }

    func eyesState() async throws -> EyesInfo { try await get("/api/me/eyes", as: EyesInfo.self) }

    func eyesSet(_ tier: String) async throws -> EyesInfo {
        try await post("/api/me/eyes", ["eyes": tier], as: EyesInfo.self)
    }

    struct OpsUserRow: Decodable, Identifiable, Hashable {
        var id: String
        var username: String?
        var nickname: String?
        var avatar: String?
        var cards: Int?
    }
    struct OpsUsersPayload: Decodable { var users: [OpsUserRow]? }
    struct OpsCardsPayload: Decodable { var cards: [WalletCard]?; var userId: String? }

    func opsShopItems() async throws -> [ShopItem] {
        let r: ShopItemsPayload = try await get("/api/ops/shop", as: ShopItemsPayload.self)
        return r.items ?? []
    }

    func opsShopSave(item: [String: Any]?, newItem: [String: Any]?,
                     removeId: String = "") async throws -> [ShopItem] {
        var b: [String: Any] = [:]
        if !removeId.isEmpty { b["removeId"] = removeId }
        if let item = item { b["item"] = item }
        if let newItem = newItem { b["newItem"] = newItem }
        let r: ShopItemsPayload = try await post("/api/ops/shop", b, as: ShopItemsPayload.self)
        return r.items ?? []
    }

    func opsCardFind(_ q: String) async throws -> [OpsUserRow] {
        let r: OpsUsersPayload = try await post("/api/ops/cards", ["action": "find", "q": q],
                                                as: OpsUsersPayload.self)
        return r.users ?? []
    }

    func opsCardList(userId: String) async throws -> [WalletCard] {
        let r: OpsCardsPayload = try await post("/api/ops/cards",
                                                ["action": "list", "userId": userId],
                                                as: OpsCardsPayload.self)
        return r.cards ?? []
    }

    func opsCardIssue(userId: String, kind: String, title: String, sub: String,
                      amount: Double, validTo: String, note: String) async throws -> [WalletCard] {
        let r: OpsCardsPayload = try await post("/api/ops/cards",
            ["action": "issue", "userId": userId, "kind": kind, "title": title,
             "sub": sub, "amount": amount, "validTo": validTo, "note": note],
            as: OpsCardsPayload.self)
        return r.cards ?? []
    }

    func opsCardDelete(id: String, userId: String) async throws -> [WalletCard] {
        let r: OpsCardsPayload = try await post("/api/ops/cards",
            ["action": "delete", "id": id, "userId": userId], as: OpsCardsPayload.self)
        return r.cards ?? []
    }

    struct AppLogRow: Decodable, Identifiable, Hashable {
        var id: String
        var kind: String?
        var text: String?
        var stack: String?
        var app: String?
        var user: String?
        var ip: String?
        var at: String?
    }
    struct AppLogKind: Decodable, Hashable {
        var kind: String
        var n: Int
    }
    struct AppLogsPayload: Decodable {
        var total: Int?
        var kinds: [AppLogKind]?
        var rows: [AppLogRow]?
    }

    func opsLogs(kind: String = "", limit: Int = 50) async throws -> AppLogsPayload {
        var path = "/api/ops/logs?limit=" + String(limit)
        if !kind.isEmpty {
            path += "&kind=" + (kind.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
        }
        return try await get(path, as: AppLogsPayload.self)
    }

    func healthProbe(_ path: String) async -> (code: Int, ms: Int, note: String) {
        guard let url = URL(string: base + path) else { return (-1, 0, "地址拼不出来") }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue(AppInfo.build, forHTTPHeaderField: "X-App-Build")
        req.setValue(AppInfo.deviceId, forHTTPHeaderField: "X-Device-Id")
        req.setValue(AppInfo.deviceKind, forHTTPHeaderField: "X-Device-Kind")
        if !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let t0 = Date()
        do {
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            var note = "HTTP " + String(code) + " · " + String(ms) + "ms · " + String(data.count) + " 字节"
            if let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               (o["ok"] as? Bool) == true, let d = o["data"] as? [String: Any] {
                if let n = countOf(d, "items") { note += " · " + String(n) + " 项" }
                else if let n = countOf(d, "chats") { note += " · " + String(n) + " 个会话" }
                else if let n = countOf(d, "cards") { note += " · " + String(n) + " 张卡" }
                else if let n = countOf(d, "friends") { note += " · " + String(n) + " 位好友" }
                else if let n = countOf(d, "orders") { note += " · " + String(n) + " 个订单" }
                else if let n = countOf(d, "tracks") { note += " · " + String(n) + " 首歌" }
                else if let eyes = d["eyes"] as? String { note += " · 小星 " + eyes }
            } else if code == 404 {
                note += " · 这条线路的服务器没有这个接口（服务器太旧）"
            } else if code == 401 {
                note += " · 登录态失效（要重新登录）"
            }
            return (code, ms, note)
        } catch {
            return (-1, 0, "连不上：" + error.localizedDescription)
        }
    }

    private func countOf(_ d: [String: Any], _ key: String) -> Int? {
        (d[key] as? [Any])?.count
    }

    struct RPCover: Decodable, Identifiable, Hashable {
        var id: String
        var name: String?
        var image: String?
        var thumb: String?
        var color: String?
        var enabled: Bool?
    }
    struct RPCoversFile: Decodable {
        var defaultId: String?
        var covers: [RPCover]?
    }
    private struct RPCoversPayload: Decodable { var covers: RPCoversFile? }
    private struct RPSavedPayload: Decodable { var covers: RPCoversFile? }

    func opsRPCovers() async throws -> (covers: [RPCover], defaultId: String) {
        let r: RPCoversPayload = try await get("/api/ops/rpcovers", as: RPCoversPayload.self)
        return (r.covers?.covers ?? [], r.covers?.defaultId ?? "")
    }

    @discardableResult
    func opsRPSave(covers: [[String: Any]], defaultId: String) async throws -> [RPCover] {
        var b: [String: Any] = ["covers": covers]
        if !defaultId.isEmpty { b["defaultId"] = defaultId }
        let r: RPSavedPayload = try await post("/api/ops/rpcovers", b, as: RPSavedPayload.self)
        return r.covers?.covers ?? []
    }

    @discardableResult
    func opsSetUIKey(_ key: String, _ value: Any) async -> Bool {
        do {
            _ = try await request("POST", "/api/ops/ui", body: ["key": key, "value": value])
            return true
        } catch {
            return false
        }
    }

    func memberInfo() async throws -> MemberInfo {
        struct P: Decodable { var membership: MemberInfo? }
        let p: P = try await get("/api/membership", as: P.self)
        return p.membership ?? MemberInfo()
    }

    func memberOpen(tierId: String, months: Int, payPassword: String) async -> (MemberMe?, Double?, String?) {
        struct P: Decodable { var membership: MemberMe?; var balance: Double?; var paid: Double? }
        do {
            let p: P = try await post("/api/membership/open",
                                      ["tierId": tierId, "months": months, "payPassword": payPassword],
                                      as: P.self)
            return (p.membership, p.balance, nil)
        } catch {
            return (nil, nil, (error as? APIError)?.errorDescription ?? "开通失败，再试一次")
        }
    }

    func memberAuto(_ on: Bool) async {
        struct P: Decodable { var membership: MemberMe? }
        _ = try? await post("/api/membership/auto", ["on": on], as: P.self)
    }

    func memberRedeem(_ code: String) async -> (String?, String) {
        struct P: Decodable { var membership: MemberMe?; var tier: String?; var days: Int? }
        do {
            let p: P = try await post("/api/membership/redeem", ["code": code], as: P.self)
            return (p.tier, "兑换成功：" + (p.tier ?? "会员") + " " + String(p.days ?? 0) + " 天")
        } catch {
            return (nil, (error as? APIError)?.errorDescription ?? "兑换失败")
        }
    }

    func scanTranslate(_ text: String, to: String = "中文") async -> String? {
        struct P: Decodable { var text: String? }
        guard let p: P = try? await post("/api/scan/translate", ["text": text, "to": to], as: P.self) else {
            return nil
        }
        return p.text
    }

    @discardableResult
    func setPinned(chatId: String, pinned: Bool) async -> Bool? {
        guard let p: PinPayload = try? await post("/api/chats/\(chatId)/pin",
                                                 ["pinned": pinned], as: PinPayload.self) else { return nil }
        return p.pinned ?? pinned
    }

    @discardableResult
    func updateChatInfo(chatId: String, name: String, announce: String) async -> String? {
        do {
            let _: ChatInfoPayload = try await patch("/api/chats/\(chatId)/info",
                                                     ["name": name, "announce": announce], as: ChatInfoPayload.self)
            return nil
        } catch { return (error as? APIError)?.errorDescription ?? "保存失败" }
    }

    @discardableResult
    func setMuted(chatId: String, muted: Bool) async -> Bool? {
        guard let p: MutePayload = try? await post("/api/chats/\(chatId)/mute",
                                                  ["muted": muted], as: MutePayload.self) else { return nil }
        return p.muted ?? muted
    }

    @discardableResult
    func kickMember(chatId: String, userId: String) async -> String? {
        do {
            let _: GroupActionPayload = try await post("/api/chats/\(chatId)/kick",
                                                       ["userId": userId], as: GroupActionPayload.self)
            return nil
        } catch { return (error as? APIError)?.errorDescription ?? "移出失败" }
    }

    func addGroupMembers(chatId: String, userIds: [String]) async -> (added: [String], memberCount: Int, error: String?) {
        struct Payload: Decodable {
            var memberCount: Int?
            var added: [Row]?
            struct Row: Decodable { var id: String?; var name: String? }
        }
        do {
            let p: Payload = try await post("/api/chats/\(chatId)/add-members",
                                            ["userIds": userIds], as: Payload.self)
            let names = (p.added ?? []).compactMap { $0.name }
            return (names, p.memberCount ?? 0, nil)
        } catch {
            return ([], 0, (error as? APIError)?.errorDescription ?? "加人失败")
        }
    }

    func privacy() async -> PrivacySettings {
        struct Payload: Decodable {
            var privacy: Raw?; var notify: Raw?
            struct Raw: Decodable {
                var needVerify: Bool?; var strangerMoments: Bool?
                var addByWx: Bool?; var addByPhone: Bool?; var addByGroup: Bool?; var addByQR: Bool?

                var momentsRange: String?
            }
        }
        guard let p: Payload = try? await get("/api/me/privacy", as: Payload.self), let r = p.privacy
        else { return PrivacySettings() }
        var s = PrivacySettings()
        s.needVerify = r.needVerify ?? true
        s.strangerMoments = r.strangerMoments ?? false
        s.addByWx = r.addByWx ?? true
        s.addByPhone = r.addByPhone ?? true
        s.addByGroup = r.addByGroup ?? true
        s.addByQR = r.addByQR ?? true
        s.momentsRange = (r.momentsRange == "3d" || r.momentsRange == "6m") ? r.momentsRange! : "all"
        return s
    }

    func setPrivacy(_ key: String, _ value: Bool) async {
        _ = try? await request("PATCH", "/api/me/privacy", body: [key: value])
    }

    func setPrivacyText(_ key: String, _ value: String) async {
        _ = try? await request("PATCH", "/api/me/privacy", body: [key: value])
    }

    func notifySettings() async -> NotifySettings {
        struct Payload: Decodable {
            var notify: Raw?
            struct Raw: Decodable {
                var on: Bool?; var sound: Bool?; var vibrate: Bool?; var showDetail: Bool?
                var muteStart: String?; var muteEnd: String?
            }
        }
        guard let p: Payload = try? await get("/api/me/privacy", as: Payload.self), let r = p.notify
        else { return NotifySettings() }
        var s = NotifySettings()
        s.on = r.on ?? true
        s.sound = r.sound ?? true
        s.vibrate = r.vibrate ?? true
        s.showDetail = r.showDetail ?? true
        s.muteStart = r.muteStart ?? ""
        s.muteEnd = r.muteEnd ?? ""
        return s
    }

    func setNotify(_ fields: [String: Any]) async {
        _ = try? await request("PATCH", "/api/me/notify", body: fields)
    }

    func myQRCode() async -> (code: String, url: String, rows: [String], user: User?) {
        struct MyQRPayload: Decodable {
            var code: String?; var url: String?; var rows: [String]?; var user: User?
        }
        guard let p: MyQRPayload = try? await get("/api/me/qrcode", as: MyQRPayload.self)
        else { return ("", "", [], nil) }
        return (p.code ?? "", p.url ?? "", p.rows ?? [], p.user)
    }

    func userByCode(_ code: String) async -> (user: User?, relation: String, message: String) {
        struct ByCodePayload: Decodable { var user: User?; var relation: String? }
        do {
            let p: ByCodePayload = try await post("/api/user-by-code", ["code": code], as: ByCodePayload.self)
            return (p.user, p.relation ?? "none", "")
        } catch {
            return (nil, "", (error as? APIError)?.errorDescription ?? "这个二维码无效或者过期了")
        }
    }

    func addByCode(_ code: String) async -> (message: String, user: User?) {
        struct AddPayload: Decodable {
            var sent: Bool?; var already: Bool?; var pending: Bool?; var accepted: Bool?; var user: User?
        }
        do {
            let p: AddPayload = try await post("/api/add-by-code", ["code": code], as: AddPayload.self)
            let msg = p.already == true ? "你们已经是好友了"
                : (p.pending == true ? "已经发过申请了，等对方通过"
                   : (p.accepted == true ? "对方之前加过你，现在已经是好友" : "好友申请已发出"))
            return (msg, p.user)
        } catch {
            return ((error as? APIError)?.errorDescription ?? "加好友失败", nil)
        }
    }

    func groupInvite(chatId: String) async -> (code: String, url: String, rows: [String]) {
        struct InvitePayload: Decodable { var code: String?; var url: String?; var svg: String?; var rows: [String]? }
        guard let p: InvitePayload = try? await post("/api/chats/\(chatId)/invite", [:], as: InvitePayload.self)
        else { return ("", "", []) }
        return (p.code ?? "", p.url ?? "", p.rows ?? [])
    }

    func joinByInvite(code: String) async -> (chat: Chat?, error: String?) {
        struct JoinPayload: Decodable {
            var joined: Bool?
            var already: Bool?
            var chat: Chat?
        }
        do {
            let p: JoinPayload = try await post("/api/join", ["code": code], as: JoinPayload.self)
            return (p.chat, nil)
        } catch {
            return (nil, (error as? APIError)?.errorDescription ?? "进群失败")
        }
    }

    @discardableResult
    func setMuteAll(chatId: String, on: Bool) async -> String? {
        do {
            struct MuteAllPayload: Decodable { var muteAll: Bool? }
            let _: MuteAllPayload = try await post("/api/chats/\(chatId)/muteall", ["on": on], as: MuteAllPayload.self)
            return nil
        } catch { return (error as? APIError)?.errorDescription ?? "设置失败" }
    }

    @discardableResult
    func setMemberMuted(chatId: String, userId: String, muted: Bool) async -> String? {
        do {
            _ = try await post("/api/chats/\(chatId)/mutemember",
                               ["userId": userId, "muted": muted], as: SendPayload.self)
            return nil
        } catch { return (error as? APIError)?.errorDescription ?? "设置失败" }
    }

    @discardableResult
    func leaveGroup(chatId: String) async -> String? {
        do {
            let _: GroupActionPayload = try await post("/api/chats/\(chatId)/leave", [:], as: GroupActionPayload.self)
            return nil
        } catch { return (error as? APIError)?.errorDescription ?? "退群失败" }
    }

    @discardableResult
    func dismissGroup(chatId: String) async -> String? {
        do {
            let _: GroupActionPayload = try await post("/api/chats/\(chatId)/dismiss", [:], as: GroupActionPayload.self)
            return nil
        } catch { return (error as? APIError)?.errorDescription ?? "解散失败" }
    }

    @discardableResult
    func clearChat(chatId: String) async -> String? {
        do {
            let _: GroupActionPayload = try await post("/api/chats/\(chatId)/clear", [:], as: GroupActionPayload.self)
            return nil
        } catch { return (error as? APIError)?.errorDescription ?? "清空失败" }
    }

    func searchMessages(chatId: String, query: String) async -> [FoundMessage] {
        let result = await chatHistorySearch(chatId: chatId, query: query)
        return result.messages
    }

    func chatHistorySearch(chatId: String, query: String,
                           filter: String = "", memberId: String = "",
                           from: Date? = nil, to: Date? = nil,
                           before: Int? = nil, limit: Int = 100) async -> ChatHistorySearchResult {
        var parts = ["limit=\(limit)"]
        guard let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let kind = filter.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let member = memberId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return ChatHistorySearchResult(messages: [], hasMore: false, total: 0) }
        parts.append("q=\(q)")
        if !filter.isEmpty { parts.append("kind=\(kind)") }
        if !memberId.isEmpty { parts.append("memberId=\(member)") }
        if let from { parts.append("from=\(Int(from.timeIntervalSince1970 * 1000))") }
        if let to { parts.append("to=\(Int(to.timeIntervalSince1970 * 1000))") }
        if let before, before > 0 { parts.append("before=\(before)") }
        let path = "/api/chats/\(chatId)/search?" + parts.joined(separator: "&")
        guard let p: SearchPayload = try? await get(path, as: SearchPayload.self) else {
            return ChatHistorySearchResult(messages: [], hasMore: false, total: 0)
        }
        return ChatHistorySearchResult(messages: p.messages,
                                       hasMore: p.hasMore ?? false,
                                       total: p.total ?? p.messages.count)
    }

    func bankCards() async -> [BankCard] {
        let p: BankCardsPayload? = try? await get("/api/me/bankcards", as: BankCardsPayload.self)
        return p?.cards ?? []
    }

    struct BankInfo: Decodable, Identifiable, Hashable {
        var name: String
        var color: String?
        var short: String?
        var id: String { name }
    }
    private struct BankListPayload: Decodable { var banks: [BankInfo]? }

    func banks() async -> [BankInfo] {
        let p: BankListPayload? = try? await get("/api/banks", as: BankListPayload.self)
        return p?.banks ?? []
    }

    func setBankCardNoPin(id: String, noPin: Bool) async {
        _ = try? await patch("/api/me/bankcards/" + id, ["noPin": noPin], as: [String: String].self)
    }

    @discardableResult
    func addBankCard(bank: String, number: String, holder: String,
                     idCard: String = "", phone: String = "", type: String = "") async -> String? {
        do {
            let _: BankCardsPayload = try await post("/api/me/bankcards",
                                                     ["bank": bank, "number": number, "holder": holder,
                                                      "idCard": idCard, "phone": phone, "type": type],
                                                     as: BankCardsPayload.self)
            return nil
        } catch { return (error as? APIError)?.errorDescription ?? "绑定失败" }
    }

    @discardableResult
    func deleteBankCard(id: String) async -> String? {
        do {
            _ = try await request("DELETE", "/api/me/bankcards/\(id)")
            return nil
        } catch { return (error as? APIError)?.errorDescription ?? "解绑失败" }
    }

    @discardableResult
    func sendFeedback(content: String, contact: String,
                      category: String = "功能异常", images: [String] = []) async -> String? {
        do {
            let _: SendPayload = try await post("/api/feedback",
                                                ["content": content, "contact": contact,
                                                 "category": category, "images": images,
                                                 "platform": "iOS"],
                                                as: SendPayload.self)
            return nil
        } catch { return (error as? APIError)?.errorDescription ?? "提交失败" }
    }

    struct MyFeedback: Decodable, Identifiable, Hashable {
        var id: String
        var category: String?
        var content: String?
        var images: [String]?
        var createdAt: String?
        var status: String?
        var reply: String?
        var repliedAt: String?
    }
    private struct MyFeedbackPayload: Decodable { var rows: [MyFeedback]? }
    func myFeedback() async -> [MyFeedback] {
        guard let p: MyFeedbackPayload = try? await get("/api/feedback/mine", as: MyFeedbackPayload.self) else { return [] }
        return p.rows ?? []
    }

    func resetPassword(phone: String, code: String, newPassword: String) async -> (username: String, error: String?) {
        do {
            let p: LoginPayload = try await post("/api/login/reset",
                                                 ["phone": phone, "code": code, "newPassword": newPassword],
                                                 as: LoginPayload.self)
            return (p.user?.username ?? "", nil)
        } catch { return ("", (error as? APIError)?.errorDescription ?? "重置失败") }
    }

    func markRead(chatId: String) async {
        do {
            _ = try await request("POST", "/api/chats/\(chatId)/read", body: [:])
            NotificationCenter.default.post(name: .chrisChatRead, object: chatId)
        } catch {
        }
    }

    struct ChatDump {
        var fileName = "luchat-chat.json"
        var format = "json"
        var total = 0
        var chats = 0
        var text = ""

        var payload: Any? = nil
    }

    func exportChats(chatId: String = "", format: String = "json") async throws -> ChatDump {
        var path = "/api/chats/export?format=" + format
        if !chatId.isEmpty { path += "&chatId=" + chatId }
        let any = try await request("GET", path)
        guard let dict = any as? [String: Any] else { throw APIError.message("导出失败") }
        var out = ChatDump()
        out.fileName = (dict["fileName"] as? String) ?? out.fileName
        out.format = (dict["format"] as? String) ?? format
        out.total = (dict["total"] as? Int) ?? 0
        out.chats = (dict["chats"] as? Int) ?? 0
        if out.format == "txt" {
            out.text = (dict["data"] as? String) ?? ""
        } else {
            out.payload = dict["data"]
        }
        return out
    }

    func importChats(payload: Any) async throws -> (imported: Int, skipped: Int, chats: Int) {
        struct Out: Decodable { var imported: Int?; var skipped: Int?; var chats: Int? }
        let out: Out = try await post("/api/chats/import", ["payload": payload], as: Out.self)
        return (out.imported ?? 0, out.skipped ?? 0, out.chats ?? 0)
    }

    func markUnread(chatId: String) async -> Bool {
        (try? await request("POST", "/api/chats/\(chatId)/unread", body: [:])) != nil
    }

    @discardableResult
    func deleteChat(chatId: String) async -> String? {
        await deleteChat(path: "/api/chats/\(chatId)?clear=1")
    }

    @discardableResult
    func hideChat(chatId: String) async -> String? {
        await deleteChat(path: "/api/chats/\(chatId)")
    }

    private func deleteChat(path: String) async -> String? {
        do {
            _ = try await request("DELETE", path)
            return nil
        } catch {
            return (error as? APIError)?.errorDescription ?? "操作失败"
        }
    }

    func openDirect(userId: String) async throws -> Chat? {
        let payload: ChatPayload = try await post("/api/chats/direct", ["userId": userId], as: ChatPayload.self)
        return payload.chat
    }

    func contacts() async throws -> [User] {
        let payload: ContactsPayload = try await get("/api/contacts", as: ContactsPayload.self)
        return payload.friends
    }

    func matchPhoneContacts(salt: Data, hashes: [String]) async throws -> [User] {
        let payload: PhoneContactMatchesPayload = try await post(
            "/api/contacts/phone-match",
            ["salt": salt.base64EncodedString(), "hashes": hashes],
            as: PhoneContactMatchesPayload.self
        )
        return payload.users ?? []
    }

    func contactsFull() async throws -> (friends: [User], incoming: [User]) {
        let payload: ContactsPayload = try await get("/api/contacts", as: ContactsPayload.self)
        return (payload.friends, payload.incoming ?? [])
    }

    func friendRequests() async throws -> (friends: [User], incoming: [User], outgoing: [User], added: [User]) {
        let p: ContactsPayload = try await get("/api/contacts", as: ContactsPayload.self)
        return (p.friends, p.incoming ?? [], p.outgoing ?? [], p.added ?? [])
    }

    private struct BadgeCountsPayload: Decodable { var friendRequests: Int?; var momentUnread: Int? }

    func badgeCounts() async -> (friendRequests: Int, momentUnread: Int)? {
        guard let p = try? await get("/api/badge-counts", as: BadgeCountsPayload.self) else { return nil }
        return (p.friendRequests ?? 0, p.momentUnread ?? 0)
    }

    @discardableResult
    func respondFriend(requestId: String = "", userId: String = "",
                       accept: Bool) async -> (ok: Bool, pending: Int?, chat: Chat?) {
        struct RespondPayload: Decodable { var pending: Int?; var chat: Chat? }
        var body: [String: Any] = ["accept": accept]
        if !requestId.isEmpty { body["requestId"] = requestId }
        if !userId.isEmpty { body["userId"] = userId }
        guard let p = try? await post("/api/friends/respond", body, as: RespondPayload.self) else {
            return (false, nil, nil)
        }
        return (true, p.pending, p.chat)
    }

    func createGroup(name: String, memberIds: [String]) async throws -> Chat? {
        let payload: ChatPayload = try await post("/api/chats/group",
                                                  ["name": name, "memberIds": memberIds],
                                                  as: ChatPayload.self)
        return payload.chat
    }

    func faceGroup(code: String) async throws -> Chat? {
        struct FacePayload: Decodable {
            var chat: Chat?
            var created: Bool?
            var joined: Bool?
            var memberCount: Int?
            var expiresIn: Int?
        }
        let payload: FacePayload = try await post("/api/chats/face", ["code": code], as: FacePayload.self)
        return payload.chat
    }

    func recharge(_ amount: Double) async throws -> Double {
        struct RechargePayload: Decodable { var balance: Double? }
        let payload: RechargePayload = try await post("/api/me/recharge",
                                                      ["amount": amount,
                                                       "requestId": UUID().uuidString],
                                                      as: RechargePayload.self)
        return payload.balance ?? 0
    }

    @discardableResult
    func claimTransfer(_ id: String) async -> String? {
        do {
            _ = try await request("POST", "/api/transfers/\(id)/claim", body: [:])
            return nil
        } catch {
            return (error as? APIError)?.errorDescription ?? "收款失败，稍后再试"
        }
    }

    @discardableResult
    func remindTransfer(_ id: String) async -> String? {
        do {
            _ = try await request("POST", "/api/transfers/\(id)/remind", body: [:])
            return nil
        } catch {
            return (error as? APIError)?.errorDescription ?? "提醒失败"
        }
    }

    @discardableResult
    func refundTransfer(_ id: String) async -> String? {
        do {
            _ = try await request("POST", "/api/transfers/\(id)/refund", body: [:])
            return nil
        } catch {
            return (error as? APIError)?.errorDescription ?? "退还失败"
        }
    }

    func favorites() async -> [[String: Any]] {
        guard let any = try? await request("GET", "/api/favorites"),
              let dict = any as? [String: Any],
              let list = dict["favorites"] as? [[String: Any]] else { return [] }
        return list
    }

    @discardableResult
    func addFavorite(kind: String, content: String, title: String = "", from: String = "") async -> Bool {
        let ok = try? await request("POST", "/api/favorites", body: [
            "kind": kind, "content": content, "title": title, "from": from
        ])
        return ok != nil
    }

    struct RealNameInfo: Hashable {
        var verified: Bool
        var realName: String
        var idMask: String
        var at: String
    }

    func realNameStatus() async -> RealNameInfo {
        guard let any = try? await request("GET", "/api/me/realname"),
              let d = any as? [String: Any] else {
            return RealNameInfo(verified: false, realName: "", idMask: "", at: "")
        }
        return RealNameInfo(verified: (d["verified"] as? Bool) ?? false,
                            realName: (d["realName"] as? String) ?? "",
                            idMask: (d["idMask"] as? String) ?? "",
                            at: (d["at"] as? String) ?? "")
    }

    func submitRealName(name: String, idCard: String) async throws -> RealNameInfo {
        let any = try await request("POST", "/api/me/realname", body: ["realName": name, "idCard": idCard])
        let d = (any as? [String: Any]) ?? [:]
        return RealNameInfo(verified: (d["verified"] as? Bool) ?? true,
                            realName: (d["realName"] as? String) ?? name,
                            idMask: (d["idMask"] as? String) ?? "",
                            at: (d["at"] as? String) ?? "")
    }

    struct RegionRow: Decodable, Hashable {
        var p: String
        var c: [String]
    }

    func regions() async -> [RegionRow] {
        guard let any = try? await request("GET", "/api/regions") else { return [] }
        let d = (any as? [String: Any]) ?? [:]
        return (try? decode(d["regions"] ?? [], as: [RegionRow].self)) ?? []
    }

    func phoneChangeCode(phone: String) async throws -> String? {
        let any = try await request("POST", "/api/me/phone/code", body: ["phone": phone])
        return (any as? [String: Any])?["devCode"] as? String
    }

    @discardableResult
    func changePhone(phone: String, code: String, password: String) async throws -> String {
        var body: [String: Any] = ["phone": phone, "code": code]
        if !password.isEmpty { body["password"] = password }
        let any = try await request("POST", "/api/me/phone", body: body)
        return ((any as? [String: Any])?["phone"] as? String) ?? ""
    }

    @discardableResult
    func changeBackground(_ path: String) async -> Bool {
        do {
            _ = try await updateMeChecked(["chatBackground": path])
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func changeChatBackground(chatId: String, path: String) async -> [String: String]? {
        struct P: Decodable { var chatBackgrounds: [String: String]? }
        guard let p: P = try? await post("/api/me/chat-background",
                                           ["chatId": chatId, "path": path], as: P.self) else { return nil }
        return p.chatBackgrounds ?? [:]
    }

    @discardableResult
    func resetChatBackgrounds() async -> Bool {
        struct P: Decodable { var chatBackgrounds: [String: String]? }
        return (try? await post("/api/me/chat-background",
                                ["resetAll": true], as: P.self)) != nil
    }

    func chatBackgrounds() async -> ChatBgPayload? {
        try? await get("/api/chat-bg", as: ChatBgPayload.self)
    }

    func moments(limit: Int = 20, userId: String? = nil) async throws -> [Moment] {
        var path = "/api/moments?limit=\(limit)"
        if let userId = userId, !userId.isEmpty { path += "&userId=\(userId)" }
        let payload: MomentsPayload = try await get(path, as: MomentsPayload.self)
        return payload.moments
    }

    func momentsFeed(limit: Int = 20, before: String? = nil, beforeId: String? = nil, userId: String? = nil)
        async throws -> (moments: [Moment], unread: Int, total: Int, hasMore: Bool, range: String,
                         noticeUnread: Int) {
        var path = "/api/moments?limit=\(limit)"
        if let before = before, !before.isEmpty { path += "&before=\(before)" }
        if let beforeId = beforeId, !beforeId.isEmpty { path += "&beforeId=\(beforeId)" }
        if let userId = userId, !userId.isEmpty { path += "&userId=\(userId)" }
        let payload: MomentsPayload = try await get(path, as: MomentsPayload.self)
        return (payload.moments, payload.unread ?? 0, payload.total ?? payload.moments.count,
                payload.hasMore ?? false, payload.range ?? "all", payload.noticeUnread ?? 0)
    }

    func plusPanel() async throws -> [PlusItem] {
        let payload: PlusPayload = try await get("/api/plus-panel", as: PlusPayload.self)
        return (payload.items ?? []).filter { $0.enabled != false }
    }

    func plusConfig() async throws -> (items: [PlusItem], quick: [QuickChip], plus: PlusButtonCfg) {
        let payload: PlusConfigPayload = try await get("/api/plus-panel", as: PlusConfigPayload.self)
        return ((payload.items ?? []).filter { $0.enabled != false },
                payload.quick ?? [],
                payload.plus ?? PlusButtonCfg())
    }

    func saveChatQuick(quick: [QuickChip], plus: PlusButtonCfg) async throws {
        let body: [String: Any] = [
            "quick": quick.map { ["id": $0.id, "label": $0.label, "action": $0.action, "enabled": $0.enabled] },
            "plus": ["color": plus.color, "size": plus.size, "image": plus.image]
        ]
        _ = try await request("PUT", "/api/ops/plus-panel", body: body)
    }

    func plusConfigSafe() async -> (quick: [QuickChip], plus: PlusButtonCfg) {
        guard let c = try? await plusConfig() else { return ([], PlusButtonCfg()) }
        return (c.quick, c.plus)
    }

    func gifts() async throws -> [Gift] {
        let payload: GiftsPayload = try await get("/api/gifts", as: GiftsPayload.self)
        return payload.gifts ?? []
    }

    func stickerPacks() async throws -> [StickerPack] {
        let payload: StickersPayload = try await get("/api/stickers", as: StickersPayload.self)
        return payload.packs ?? []
    }

    func stickerShop() async throws -> (shop: [StickerPack], mine: StickerMine) {
        let p: StickerShopPayload = try await get("/api/stickers", as: StickerShopPayload.self)
        return (p.packs ?? [], p.mine ?? StickerMine())
    }

    func addStickerPack(_ packId: String) async {
        _ = try? await request("POST", "/api/stickers/add", body: ["packId": packId])
    }

    func removeStickerPack(_ packId: String) async {
        _ = try? await request("POST", "/api/stickers/remove", body: ["packId": packId])
    }

    func addSingleSticker(_ sticker: String) async {
        _ = try? await request("POST", "/api/stickers/add", body: ["sticker": sticker])
    }

    func removeSingleSticker(_ sticker: String) async {
        _ = try? await request("POST", "/api/stickers/remove", body: ["sticker": sticker])
    }

    func markStickerUsed(_ sticker: String) async {
        _ = try? await request("POST", "/api/stickers/recent", body: ["sticker": sticker])
    }

    func statusCategories() async throws -> [StatusCategory] {
        let payload: StatusesPayload = try await get("/api/statuses", as: StatusesPayload.self)
        return payload.categories ?? []
    }

    func discover() async throws -> [DiscoverItem] {
        let payload: DiscoverPayload = try await get("/api/discover", as: DiscoverPayload.self)
        return payload.items.filter { $0.enabled != false }
    }

    func news(source: String, limit: Int = 40, offset: Int = 0) async throws -> NewsFeed {
        let s = source.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? source
        return try await get("/api/news?source=" + s + "&limit=\(limit)&offset=\(offset)", as: NewsFeed.self)
    }

    func oaList() async throws -> [OAAccount] {
        struct P: Decodable { var accounts: [OAAccount]? }
        let p: P = try await get("/api/oa/list", as: P.self)
        return p.accounts ?? []
    }

    func oaAccount(id: String) async throws -> OAAccountPage {
        let s = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? id
        return try await get("/api/oa/account?id=" + s, as: OAAccountPage.self)
    }

    func oaArticle(id: String) async throws -> OAArticlePage {
        let s = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? id
        return try await get("/api/oa/article?id=" + s, as: OAArticlePage.self)
    }

    @discardableResult
    func oaFollow(accountId: String, follow: Bool) async throws -> Bool {
        struct P: Decodable { var following: Bool? }
        let p: P = try await post("/api/oa/follow", ["accountId": accountId, "follow": follow], as: P.self)
        return p.following ?? follow
    }

    func mePage() async throws -> [DiscoverItem] {
        let payload: DiscoverPayload = try await get("/api/me-page", as: DiscoverPayload.self)
        return payload.items.filter { $0.enabled != false }
    }

    func serviceConfig() async throws -> ServiceConfig {
        try await get("/api/service", as: ServiceConfig.self)
    }

    func walletConfig() async throws -> WalletConfig {
        try await get("/api/wallet", as: WalletConfig.self)
    }

    func securityScore() async throws -> CreditScore {
        try await get("/api/me/score", as: CreditScorePayload.self).score
    }

    func faceSubmit(image: String, name: String, idCard: String, dist: Double? = nil) async -> Bool {
        guard !image.isEmpty else { return false }
        var body: [String: Any] = ["image": image, "name": name, "idCard": idCard]

        if let d = dist { body["avatarDist"] = d }
        let ok = try? await request("POST", "/api/me/face", body: body)
        return ok != nil
    }

    func opsFaces() async -> [FaceReviewRow] {
        struct Payload: Decodable { var items: [FaceReviewRow]? }
        guard let p: Payload = try? await get("/api/ops/faces", as: Payload.self) else { return [] }
        return p.items ?? []
    }

    @discardableResult
    func opsFaceReview(id: String, pass: Bool, note: String = "") async -> Bool {
        let r = try? await request("POST", "/api/ops/faces",
                                   body: ["id": id, "pass": pass, "note": note])
        return r != nil
    }

    func bills(month: String? = nil, limit: Int? = nil) async throws -> BillsPayload {
        var qs: [String] = []
        if let m = month, !m.isEmpty {
            qs.append("month=" + m.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)
        }
        if let l = limit { qs.append("limit=\(max(1, min(200, l)))") }
        let path = "/api/bills" + (qs.isEmpty ? "" : "?" + qs.joined(separator: "&"))
        return try await get(path, as: BillsPayload.self)
    }

    func balancePage() async throws -> BalancePageConfig {
        try await get("/api/balance-page", as: BalancePageConfig.self)
    }

    func setMood(_ item: StatusItem?, caption: String = "", fallbackColor: String = "") async {
        if let item = item {
            let label = (item.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let note = String(caption.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30))
            let own = MoodColor.clean(item.color)
            var c1 = own
            if c1.isEmpty { c1 = MoodColor.clean(fallbackColor) }
            var c2 = MoodColor.clean(item.color2)
            if c2.isEmpty { c2 = MoodColor.shift(c1, to: true) }
            await updateMe([
                "moodLabel": label,
                "moodCaption": note,
                "moodText": note.isEmpty ? label : note,
                "moodIcon": item.icon ?? "",
                "moodColor": c1,
                "moodColor2": c2
            ])
        } else {
            await updateMe(["moodText": "", "moodLabel": "", "moodCaption": "",
                            "moodIcon": "", "moodColor": "", "moodColor2": ""])
        }
    }

    func myStatus() async throws -> MyStatus {
        try await get("/api/me/status", as: MyStatus.self)
    }

    func endMyStatus() async {
        _ = try? await request("POST", "/api/me/status", body: ["ended": true])
    }

    func aiWallet() async throws -> AIWalletStatus {
        let any = try await request("GET", "/api/ai/status")
        return try decode(any, as: AIWalletStatus.self)
    }

    func buyAITokens(planId: String, password: String, requestId: String) async throws -> AITokenPurchaseResult {
        try await post("/api/ai/purchase",
                       ["planId": planId, "password": password, "requestId": requestId],
                       as: AITokenPurchaseResult.self)
    }

    func setAIName(_ name: String) async throws -> String {
        struct Result: Decodable { var name: String }
        let result: Result = try await post("/api/ai/name", ["name": name], as: Result.self)
        return result.name
    }

    func setAIVoice(_ voice: String) async throws -> String {
        struct Result: Decodable { var voice: String }
        let result: Result = try await post("/api/ai/voice", ["voice": voice], as: Result.self)
        return result.voice
    }

    func setAILearning(_ enabled: Bool) async throws -> AILearningStatus {
        try await post("/api/ai/learning", ["enabled": enabled], as: AILearningStatus.self)
    }

    func resetAILearning() async throws -> AILearningStatus {
        try await post("/api/ai/learning/reset", [:], as: AILearningStatus.self)
    }

    func aiSpeech(_ text: String) async throws -> AITTSResult {
        try await post("/api/ai/tts", ["text": text], as: AITTSResult.self)
    }

    func upload(image: UIImage) async throws -> String {

        let data = image.resizedJPEG(maxSide: 1280, quality: 0.75)
        return try await uploadData(data)
    }

    func uploadImageForSend(_ image: UIImage, original: Bool) async throws -> (url: String, data: Data) {

        let data = image.resizedJPEG(maxSide: original ? 1920 : 1280,
                                     quality: original ? 0.88 : 0.75)
        guard let data = data else { throw APIError.message("图片处理失败") }
        let url = try await uploadData(data)
        return (url, data)
    }

    func streamingAsset(_ path: String) -> AVURLAsset? {
        guard let u = assetURL(path) else { return nil }
        let headers: [String: String] = token.isEmpty ? [:] : ["Authorization": "Bearer \(token)"]
        return AVURLAsset(url: u, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
    }

    func uploadBinary(_ data: Data, mime: String) async throws -> String {
        guard let url = URL(string: base + "/api/upload/raw") else { throw APIError.message("服务器地址不正确") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 180
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(mime, forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        let (d, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.message("上传失败（HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0)）")
        }
        return try Self.rawUploadURL(from: d)
    }

    func uploadBinaryFile(_ file: URL, mime: String,
                          skipTranscode: Bool = false,
                          onProgress: @escaping (Double) -> Void) async throws -> String {
        guard let url = URL(string: base + "/api/upload/raw") else { throw APIError.message("服务器地址不正确") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"

        req.timeoutInterval = 600
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(mime, forHTTPHeaderField: "Content-Type")

        if skipTranscode { req.setValue("1", forHTTPHeaderField: "x-chris-compressed") }
        let delegate = UploadProgressDelegate(onProgress)
        let (d, resp) = try await session.upload(for: req, fromFile: file, delegate: delegate)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.message("上传失败（HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0)）")
        }
        return try Self.rawUploadURL(from: d)
    }

    private static func rawUploadURL(from d: Data) throws -> String {
        struct RawUpload: Decodable { var url: String? }
        if let parsed = try? JSONDecoder().decode(RawUpload.self, from: d),
           let u = parsed.url, !u.isEmpty { return u }
        struct Wrapper: Decodable { struct D: Decodable { var url: String? }; var data: D? }
        if let w = try? JSONDecoder().decode(Wrapper.self, from: d), let u = w.data?.url, !u.isEmpty { return u }
        throw APIError.message("上传返回异常")
    }

    func uploadOriginal(image: UIImage) async throws -> String {

        let data = image.resizedJPEG(maxSide: 1920, quality: 0.88)
        return try await uploadData(data)
    }

    func uploadCover(image: UIImage) async throws -> String {
        let data = image.resizedJPEG(maxSide: 1920, quality: 0.88)
        return try await uploadData(data)
    }

    private func uploadData(_ data: Data?) async throws -> String {
        guard let data = data else {
            throw APIError.message("图片处理失败")
        }

        if let url = try? await uploadRawJPEG(data) { return url }
        let b64 = data.base64EncodedString()
        let payload: UploadPayload = try await post("/api/upload",
                                                    ["dataUrl": "data:image/jpeg;base64," + b64,
                                                     "filename": "photo.jpg"],
                                                    as: UploadPayload.self)
        guard let url = payload.url else { throw APIError.message("上传失败") }
        return url
    }

    private func uploadRawJPEG(_ data: Data) async throws -> String {
        guard let url = URL(string: base + "/api/upload/raw") else {
            throw APIError.message("服务器地址不正确")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")

        req.setValue("1", forHTTPHeaderField: "x-chris-compressed")
        let (d, resp) = try await session.upload(for: req, from: data)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.message("上传失败（HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0)）")
        }
        return try Self.rawUploadURL(from: d)
    }

    func send(chatId: String, kind: String, content: String, mentions: [String] = [],
              imgW: Int = 0, imgH: Int = 0, quote: [String: Any]? = nil) async throws -> Message? {
        var body: [String: Any] = ["kind": kind, "content": content]
        if !mentions.isEmpty { body["mentions"] = mentions }

        if imgW > 1, imgH > 1 { body["imgW"] = imgW; body["imgH"] = imgH }

        if let q = quote, !q.isEmpty { body["quote"] = q }
        let payload: MessagePayload = try await post("/api/chats/\(chatId)/messages",
                                                     body,
                                                     as: MessagePayload.self)
        return payload.message
    }

    func send(chatId: String, kind: String, content: String, mentions: [String] = [],
              clientId: String, imgW: Int = 0, imgH: Int = 0,
              quote: [String: Any]? = nil) async throws -> Message? {
        var body: [String: Any] = ["kind": kind, "content": content, "clientId": clientId]
        if !mentions.isEmpty { body["mentions"] = mentions }
        if imgW > 1, imgH > 1 { body["imgW"] = imgW; body["imgH"] = imgH }
        if let q = quote, !q.isEmpty { body["quote"] = q }
        let payload: MessagePayload = try await post("/api/chats/\(chatId)/messages",
                                                     body,
                                                     as: MessagePayload.self)
        return payload.message
    }

    func recall(chatId: String, messageId: String) async {
        _ = try? await request("POST", "/api/messages/\(messageId)/recall", body: ["chatId": chatId])
    }

    func likeMoment(id: String) async -> String? {
        do {
            _ = try await request("POST", "/api/moments/\(id)/like", body: [:])
            return nil
        } catch {
            return (error as? APIError)?.errorDescription ?? "点赞失败"
        }
    }

    func momentNotices() async -> (items: [MomentNotice], unread: Int) {
        guard let p = try? await get("/api/moments/notices", as: MomentNoticesPayload.self) else {
            return ([], 0)
        }
        return (p.items ?? [], p.unread ?? 0)
    }

    func markMomentNoticesSeen() async {
        _ = try? await request("POST", "/api/moments/notices/seen", body: [:])
    }

    func markMomentsSeen() async {
        _ = try? await request("POST", "/api/moments/seen", body: [:])
    }

    func commentMoment(id: String, text: String, replyTo: String = "") async -> String? {
        var b: [String: Any] = ["content": text]

        if !replyTo.isEmpty { b["replyTo"] = replyTo }
        do {
            _ = try await request("POST", "/api/moments/\(id)/comments", body: b)
            return nil
        } catch {
            return (error as? APIError)?.errorDescription ?? "评论失败"
        }
    }

    func deleteMoment(id: String) async -> String? {
        do {
            _ = try await request("DELETE", "/api/moments/\(id)")
            return nil
        } catch {
            return (error as? APIError)?.errorDescription ?? "删除失败"
        }
    }

    func pinMoment(id: String, pinned: Bool) async {
        _ = try? await request("POST", "/api/moments/\(id)/pin", body: ["pinned": pinned])
    }

    func deleteMomentComment(momentId: String, commentId: String) async -> String? {
        do {
            _ = try await request("DELETE", "/api/moments/\(momentId)/comments/\(commentId)")
            return nil
        } catch {
            return (error as? APIError)?.errorDescription ?? "删除失败"
        }
    }

    func postMoment(content: String, images: [String],
                    imageSizes: [String: [Int]] = [:],
                    video: String = "", videoCover: String = "",
                    videoSeconds: Int = 0, videoW: Int = 0, videoH: Int = 0,
                    visibility: String = "public",
                    visibleTo: [String] = [], hiddenFrom: [String] = [],
                    location: String = "") async throws {
        var body: [String: Any] = [
            "content": content, "images": images,
            "visibility": visibility, "visibleTo": visibleTo, "hiddenFrom": hiddenFrom,
            "location": location
        ]

        if !imageSizes.isEmpty { body["imageSizes"] = imageSizes }
        if !video.isEmpty {
            body["video"] = video
            body["videoCover"] = videoCover
            body["videoSeconds"] = videoSeconds
            body["videoW"] = videoW
            body["videoH"] = videoH
        }
        _ = try await request("POST", "/api/moments", body: body)
    }

    func updateMe(_ fields: [String: Any]) async {
        _ = try? await request("PATCH", "/api/me", body: fields)
    }

    @discardableResult
    func updateMeChecked(_ fields: [String: Any]) async throws -> User? {
        let any = try await request("PATCH", "/api/me", body: fields)
        return (try? decode(any, as: LoginPayload.self))?.user
    }

    func completeOnboarding(avatar: String, interests: [String]) async throws -> User {
        let any = try await request("PATCH", "/api/me", body: [
            "avatar": avatar,
            "interests": interests,
            "onboardingComplete": true
        ])
        let payload = try decode(any, as: LoginPayload.self)
        guard let user = payload.user else { throw APIError.message("保存资料失败") }
        return user
    }

    func addFriend(username: String, from: String = "") async throws {
        var body: [String: Any] = ["username": username]
        if !from.isEmpty { body["from"] = from }
        _ = try await request("POST", "/api/friends/request", body: body)
    }

    func rawUpload(_ body: [String: Any]) async throws -> (url: String, name: String, bytes: Int) {
        let payload: UploadPayload = try await post("/api/upload", body, as: UploadPayload.self)
        guard let url = payload.url else { throw APIError.message("上传失败") }
        return (url, payload.name ?? "", payload.bytes ?? 0)
    }

    func transfer(chatId: String, amount: Double, note: String,
                  method: String, password: String, face: Bool = false) async throws {
        _ = try await request("POST", "/api/pay/transfer", body: [
            "chatId": chatId,
            "amount": amount,
            "note": note,
            "method": method,
            "password": password,
            "face": face,

            "requestId": UUID().uuidString
        ])
    }

    func payCode() async throws -> PayCodeInfo {
        try await post("/api/pay/code", [:], as: PayCodeInfo.self)
    }

    func receiveCode(amount: Double) async throws -> PayCodeInfo {
        try await post("/api/pay/receive-code", ["amount": amount], as: PayCodeInfo.self)
    }

    func payResolve(text: String) async throws -> PayScanInfo {
        try await post("/api/pay/resolve", ["text": text], as: PayScanInfo.self)
    }

    func payCollect(text: String, amount: Double, password: String, face: Bool = false) async throws -> PayCollectResult {
        try await post("/api/pay/collect", [
            "text": text, "amount": amount, "password": password, "face": face,
            "requestId": UUID().uuidString
        ], as: PayCollectResult.self)
    }

    func hasPayPassword() async -> Bool {
        guard let any = try? await request("GET", "/api/me/paypassword"),
              let dict = any as? [String: Any],
              let has = dict["has"] as? Bool else { return false }
        return has
    }

    func verifyPayPassword(_ password: String) async throws {
        _ = try await request("POST", "/api/me/paypassword/verify", body: ["password": password])
    }

    func setPayPassword(_ password: String, current: String = "") async throws {
        var body: [String: Any] = ["password": password]
        if !current.isEmpty { body["current"] = current }
        _ = try await request("POST", "/api/me/paypassword", body: body)
    }

    func report(userId: String, chatId: String, reason: String, content: String) async {
        _ = try? await request("POST", "/api/reports", body: [
            "targetUserId": userId,
            "chatId": chatId,
            "reason": reason,
            "content": content
        ])
    }

    func reportGroup(chatId: String, groupName: String,
                     reason: String, content: String) async -> String? {
        do {
            _ = try await request("POST", "/api/reports", body: [
                "targetType": "group",
                "chatId": chatId,
                "targetName": groupName,
                "reason": reason,
                "content": content
            ])
            return nil
        } catch {
            return (error as? APIError)?.errorDescription ?? "投诉提交失败"
        }
    }
}

extension UIImage {

    var sendPixelSize: (w: Int, h: Int) {
        (max(1, Int(size.width.rounded())), max(1, Int(size.height.rounded())))
    }

    func resizedJPEG(maxSide: CGFloat, quality: CGFloat) -> Data? {
        let long = max(size.width, size.height)
        var target = size
        if long > maxSide {
            let k = maxSide / long
            target = CGSize(width: size.width * k, height: size.height * k)
        }

        let pixels = target.width * target.height
        if pixels > 2_400_000 {
            let k = (2_400_000 / pixels).squareRoot()
            target = CGSize(width: (target.width * k).rounded(), height: (target.height * k).rounded())
        }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let out = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
        return out.jpegData(compressionQuality: quality)
    }
}
