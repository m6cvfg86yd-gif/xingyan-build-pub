import SwiftUI

enum CopyMode: String, CaseIterable, Identifiable {
    case standard
    case fresh
    case familiar

    var id: String { rawValue }

    var name: String {
        switch self {
        case .standard: return Tr("默认模式")
        case .fresh: return Tr("新鲜模式")
        case .familiar: return Tr("熟客模式")
        }
    }

    var detail: String {
        switch self {
        case .standard: return Tr("清晰、克制，保留系统原生感")
        case .fresh: return Tr("短句、轻快，多一点新鲜感")
        case .familiar: return Tr("像老朋友说话，亲近但不卖萌")
        }
    }

    var symbol: String {
        switch self {
        case .standard: return "text.alignleft"
        case .fresh: return "sparkles"
        case .familiar: return "person.2.fill"
        }
    }
}

final class CopyVoiceStore: ObservableObject {
    static let shared = CopyVoiceStore()
    private static let key = "chris.copyVoice"

    @Published var mode: CopyMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: Self.key)
            LangStore.shared.copyVersion += 1
        }
    }

    private init() {
        mode = CopyMode(rawValue: UserDefaults.standard.string(forKey: Self.key) ?? "") ?? .standard
    }

    func rewrite(_ key: String, display: String) -> String {
        guard mode != .standard else { return display }
        let table = mode == .fresh ? Self.fresh : Self.familiar
        return table[key] ?? table[display] ?? display
    }

    private static let fresh: [String: String] = [
        "把星光送到": "把这份新鲜感发出去",
        "选择会话即可转发，原内容会完整保留": "选一个聊天，原内容原样送过去",
        "搜索会话或消息": "搜聊天、搜消息，一找就到",
        "消息已读完": "全都看完啦",
        "没有找到匹配的会话": "没翻到，换个词再试试",
        "正在加载…": "马上就来…",
        "发送失败，请检查网络后重试": "没发出去，看看网络再来一次",
        "部分内容转发失败，请重试": "有几条没送到，再试一次吧",
        "这个入口还没接": "这里还在路上",
        "天气暂时拿不到": "云层有点厚，天气晚点到",
        "这首歌还没有歌词": "这首歌还没写词，先听旋律",
        "朋友圈已关闭": "生活圈先收起来了",
        "朋友圈已开启：去「发现」里就能看到": "生活圈回来了，去「发现」看看"
    ]

    private static let familiar: [String: String] = [
        "把星光送到": "把这束星光送给老朋友",
        "选择会话即可转发，原内容会完整保留": "挑个熟人发过去，内容不会变",
        "搜索会话或消息": "想找哪段？丢个关键词给我就行",
        "消息已读完": "消息都看过了，先歇会儿吧",
        "没有找到匹配的会话": "暂时没找到，换个关键词我再陪你找",
        "正在加载…": "稍等一下，马上就好",
        "发送失败，请检查网络后重试": "这次没送出去，看看网络，我们再发一遍",
        "部分内容转发失败，请重试": "有几句没送到，我们再补一次",
        "这个入口还没接": "这里先留个空，后面我来补上",
        "天气暂时拿不到": "天气这会儿没回话，过会儿再看",
        "这首歌还没有歌词": "这首歌暂时没词，咱们先听旋律",
        "朋友圈已关闭": "生活圈先帮你收好了",
        "朋友圈已开启：去「发现」里就能看到": "生活圈已经回来了，去「发现」就能看到"
    ]
}
