import UIKit

enum NativeChatRowMetrics {
    private static var cachedDynamicScale: CGFloat?
    private static var cachedCombinedScale: CGFloat?

    static var dynamicScale: CGFloat {
        if let cachedDynamicScale { return cachedDynamicScale }
        let base: CGFloat = 17
        let scaled = UIFontMetrics(forTextStyle: .body).scaledValue(for: base)
        let resolved = min(1.35, max(1, scaled / base))
        cachedDynamicScale = resolved
        return resolved
    }

    static var combinedScale: CGFloat {
        if let cachedCombinedScale { return cachedCombinedScale }
        let resolved = dynamicScale * CareMode.scale
        cachedCombinedScale = resolved
        return resolved
    }

    static var rowHeight: CGFloat {
        max(72, (72 + (combinedScale - 1) * 34).rounded())
    }

    static func invalidateScaleCache() {
        cachedDynamicScale = nil
        cachedCombinedScale = nil
    }

    static func font(_ size: CGFloat,
                     weight: UIFont.Weight,
                     textStyle: UIFont.TextStyle) -> UIFont {
        let preferred = size * CareMode.scale
        let scaled = UIFontMetrics(forTextStyle: textStyle).scaledValue(for: preferred)
        return .systemFont(ofSize: min(size * combinedScale, scaled), weight: weight)
    }
}

struct NativeChatRowConfiguration {
    var title: String
    var titleColor: UIColor
    var isLight: Bool
    var preview: String
    var mentionPrefix: String
    var previewKind: String
    var highlightMention: Bool
    var previewColor: UIColor
    var time: String
    var timeColor: UIColor
    var rowBackground: UIColor
    var dividerColor: UIColor
    var showsDivider: Bool = true
    var badgeRing: UIColor
    var chatId: String
    var avatarPaths: [String]
    var groupMemberIds: [String]
    var avatarIsGroup: Bool
    var showOnline: Bool
    var moodIcon: String
    var unread: Int
    var unreadMuted: Bool
    var levelText: String
    var memberText: String
    var memberColor: UIColor?
    var onOpen: () -> Void
    var onAvatar: (() -> Void)?
    var onUnread: () -> Void
    var onHide: () -> Void
    var onDelete: () -> Void
    var onPin: (Bool) -> Void
    var isPinned: Bool
}

final class NativeChatRowCell: UICollectionViewCell, UIGestureRecognizerDelegate {
    private let foreground = UIView()
    private let avatarView = NativeChatAvatarView()
    private let titleLabel = UILabel()
    private let levelLabel = PaddingLabel(insets: UIEdgeInsets(top: 1, left: 4, bottom: 1, right: 4))
    private let memberLabel = PaddingLabel(insets: UIEdgeInsets(top: 1, left: 4, bottom: 1, right: 4))
    private let previewLabel = UILabel()
    private let timeLabel = UILabel()
    private let unreadLabel = PaddingLabel(insets: .zero)
    private let divider = UIView()
    private let pressOverlay = UIView()
    private let pinActions = UIStackView()
    private let leftActions = UIStackView()
    private var configuration: NativeChatRowConfiguration?
    private var offset: CGFloat = 0
    private var startOffset: CGFloat = 0
    private var latestRawOffset: CGFloat = 0
    private var dragDirection: CGFloat = 0
    private var actionsSignature = ""
    private var avatarSignature = ""
    private var accessibilitySignature = ""
    private var cachedTimeSignature = ""
    private var cachedTimeWidth: CGFloat = 0
    private var avatarTap: UITapGestureRecognizer?
    private weak var frozenScrollPan: UIPanGestureRecognizer?

    private let rowLeading: CGFloat = 16
    private let avatarSize: CGFloat = 50
    private let avatarGap: CGFloat = 11
    private let rowTrailing: CGFloat = 16
    private let dividerLeading: CGFloat = 77
    private let actionWidth: CGFloat = 50
    private let actionGap: CGFloat = 10
    private let actionInset: CGFloat = 12

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        setupGestures()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleSwipeElsewhere(_:)),
                                               name: .chrisRowSwipe,
                                               object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        frozenScrollPan?.isEnabled = true
        NotificationCenter.default.removeObserver(self)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        configuration = nil
        foreground.transform = .identity
        offset = 0
        startOffset = 0
        latestRawOffset = 0
        dragDirection = 0
        pinActions.alpha = 1
        pinActions.transform = .identity
        pinActions.isHidden = true
        leftActions.alpha = 1
        leftActions.transform = .identity
        leftActions.isHidden = true
        pressOverlay.backgroundColor = .clear
        avatarView.reset()
        avatarSignature = ""
        accessibilitySignature = ""
        cachedTimeSignature = ""
        cachedTimeWidth = 0
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        foreground.frame = bounds
        pressOverlay.frame = foreground.bounds
        avatarView.frame = CGRect(x: rowLeading, y: (bounds.height - avatarSize) / 2,
                                  width: avatarSize, height: avatarSize)
        let textX = rowLeading + avatarSize + avatarGap
        let timeText = configuration?.time ?? ""
        let timeSignature = "\(timeText)|\(timeLabel.font.pointSize)"
        if timeSignature != cachedTimeSignature {
            let measuredTime = ceil((timeText as NSString).size(
                withAttributes: [.font: timeLabel.font as Any]
            ).width)
            let timeScale = min(1.35, timeLabel.font.pointSize / 13)
            cachedTimeWidth = min(96, max(34 * timeScale, measuredTime + 2))
            cachedTimeSignature = timeSignature
        }
        let timeWidth = cachedTimeWidth
        let titleWidth = max(1, bounds.width - textX - rowTrailing - timeWidth - 8)
        let titleHeight: CGFloat = 22
        titleLabel.frame = CGRect(x: 0, y: 0, width: titleWidth, height: titleHeight)
        levelLabel.sizeToFit()
        memberLabel.sizeToFit()
        let resolvedTitleHeight = max(titleHeight, ceil(titleLabel.font.lineHeight))
        let previewHeight = max(19, ceil(previewLabel.font.lineHeight))
        let timeHeight = max(18, ceil(timeLabel.font.lineHeight))
        let titlePreviewGap: CGFloat = 3
        let contentHeight = resolvedTitleHeight + titlePreviewGap + previewHeight
        let contentTop = max(5, (bounds.height - contentHeight) / 2)
        let unread = configuration?.unread ?? 0
        let badgeScale = min(1.4, max(1, unreadLabel.font.pointSize / 10))
        let unreadWidth: CGFloat = configuration?.unreadMuted == true
            ? 8
            : (unread > 99 ? 28 : (unread > 9 ? 23 : 18)) * badgeScale
        let previewReserve = unread > 0 ? unreadWidth + 10 : 0
        let unreadHeight = max(18, ceil(unreadLabel.font.lineHeight) + 6)
        titleLabel.frame = CGRect(x: textX,
                                  y: contentTop,
                                  width: titleWidth,
                                  height: resolvedTitleHeight)
        previewLabel.frame = CGRect(x: textX,
                                    y: contentTop + resolvedTitleHeight + titlePreviewGap,
                                    width: max(1, bounds.width - textX - rowTrailing - previewReserve),
                                    height: previewHeight)
        timeLabel.frame = CGRect(x: bounds.width - rowTrailing - timeWidth,
                                 y: contentTop + (resolvedTitleHeight - timeHeight) / 2 - 3,
                                 width: timeWidth, height: timeHeight)
        unreadLabel.sizeToFit()
        unreadLabel.frame = CGRect(x: bounds.width - rowTrailing - unreadWidth,
                                   y: previewLabel.frame.midY - unreadHeight / 2,
                                   width: unreadWidth,
                                   height: unreadHeight)
        unreadLabel.layer.cornerRadius = configuration?.unreadMuted == true
            ? min(4, unreadHeight / 2)
            : unreadHeight / 2
        layoutTitleBadges()
        divider.frame = CGRect(x: dividerLeading, y: bounds.height - 0.5,
                               width: bounds.width - dividerLeading, height: 0.5)
        pinActions.frame = CGRect(x: actionInset, y: 0,
                                  width: actionWidth + actionInset * 2,
                                  height: bounds.height)
        leftActions.frame = CGRect(x: bounds.width - (actionWidth * 3 + actionGap * 2 + actionInset),
                                   y: 0,
                                   width: actionWidth * 3 + actionGap * 2 + actionInset,
                                   height: bounds.height)
    }

    func configure(_ configuration: NativeChatRowConfiguration) {
        self.configuration = configuration
        backgroundColor = configuration.rowBackground
        foreground.backgroundColor = configuration.rowBackground
        titleLabel.text = configuration.title
        titleLabel.textColor = configuration.titleColor
        titleLabel.font = NativeChatRowMetrics.font(17, weight: .semibold, textStyle: .headline)
        previewLabel.font = NativeChatRowMetrics.font(15,
                                                     weight: .regular,
                                                     textStyle: .body)
        timeLabel.font = NativeChatRowMetrics.font(12,
                                                  weight: .regular,
                                                  textStyle: .footnote)
        previewLabel.attributedText = styledPreview(configuration)
        timeLabel.text = configuration.time
        timeLabel.textColor = configuration.timeColor
        divider.backgroundColor = configuration.dividerColor
        divider.isHidden = !configuration.showsDivider
        unreadLabel.isHidden = configuration.unread <= 0
        if configuration.unread > 0 {
            if configuration.unreadMuted {
                unreadLabel.text = "●"
                unreadLabel.font = NativeChatRowMetrics.font(7, weight: .bold,
                                                             textStyle: .caption2)
                unreadLabel.backgroundColor = configuration.timeColor
                unreadLabel.textColor = configuration.timeColor
                unreadLabel.layer.cornerRadius = 4
                unreadLabel.frame.size.width = 8
            } else {
                unreadLabel.text = configuration.unread > 99 ? "99+" : "\(configuration.unread)"
                unreadLabel.font = NativeChatRowMetrics.font(10, weight: .bold,
                                                             textStyle: .caption2)
                unreadLabel.backgroundColor = .systemBlue
                unreadLabel.textColor = .white
                unreadLabel.layer.cornerRadius = 9
            }
            unreadLabel.layer.borderWidth = 1.5
            unreadLabel.layer.borderColor = configuration.badgeRing.cgColor
            unreadLabel.clipsToBounds = true
            unreadLabel.textAlignment = .center
        }

        levelLabel.isHidden = configuration.levelText.isEmpty
        levelLabel.font = NativeChatRowMetrics.font(8.5, weight: .semibold,
                                                    textStyle: .caption2)
        levelLabel.text = configuration.levelText
        memberLabel.isHidden = configuration.memberText.isEmpty
        memberLabel.font = NativeChatRowMetrics.font(8.5, weight: .semibold,
                                                     textStyle: .caption2)
        memberLabel.text = configuration.memberText
        memberLabel.backgroundColor = configuration.memberColor
        let nextAvatarSignature = [
            configuration.avatarPaths.joined(separator: "\u{1F}"),
            configuration.groupMemberIds.joined(separator: "\u{1F}"),
            configuration.chatId,
            configuration.avatarIsGroup ? "1" : "0",
            configuration.showOnline ? "1" : "0",
            configuration.moodIcon
        ].joined(separator: "\u{1E}")
        if avatarSignature != nextAvatarSignature || !avatarView.hasVisibleImage {
            avatarSignature = nextAvatarSignature
            avatarView.configure(paths: configuration.avatarPaths,
                                 chatId: configuration.chatId,
                                 memberIds: configuration.groupMemberIds,
                                 group: configuration.avatarIsGroup,
                                 online: configuration.showOnline,
                                 mood: configuration.moodIcon)
        }
        avatarTap?.isEnabled = configuration.onAvatar != nil
        let nextActionsSignature = "\(configuration.isPinned)|\(Lang.code)"
        if actionsSignature != nextActionsSignature {
            actionsSignature = nextActionsSignature
            rebuildActions()
        }
        configureAccessibility(configuration)
        setNeedsLayout()
    }

    private func styledPreview(_ configuration: NativeChatRowConfiguration) -> NSAttributedString {
        let text = configuration.mentionPrefix + configuration.preview
        let prefixLength = (configuration.mentionPrefix as NSString).length
        let bodyLength = (configuration.preview as NSString).length
        let result = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: previewLabel.font as Any,
                .foregroundColor: configuration.previewColor
            ]
        )
        if prefixLength > 0 {
            result.addAttributes([
                .font: UIFont.systemFont(ofSize: 15, weight: .medium),
                .foregroundColor: UIColor.systemRed
            ], range: NSRange(location: 0, length: prefixLength))
        }

        let bodyRange = NSRange(location: prefixLength, length: bodyLength)
        guard bodyLength > 0 else { return result }
        let body = configuration.preview
        let bodyText = body as NSString
        let kind = configuration.previewKind

        let wholeColor: UIColor?
        if kind == "draft"
            || body.contains("草稿")
            || body.localizedCaseInsensitiveContains("draft") {
            wholeColor = .systemRed
        } else if body.contains("已添加")
            || body.contains("已成为好友")
            || body.contains("添加了好友")
            || body.contains("好友验证通过")
            || body.contains("解冻") {
            wholeColor = .systemGreen
        } else if body.contains("删除好友")
            || body.contains("已删除")
            || body.contains("解除好友")
            || body.contains("不再是好友")
            || body.contains("关系已解除")
            || body.contains("拉黑")
            || body.contains("黑名单")
            || body.contains("拒收") {
            wholeColor = .systemRed
        } else if body.contains("封号")
            || body.contains("封禁")
            || body.contains("账号")
            || body.contains("冻结")
            || body.contains("其他地方登录")
            || body.contains("已下线") {
            wholeColor = .systemOrange
        } else if body.contains("撤回") {
            wholeColor = .systemRed
        } else {
            wholeColor = nil
        }
        if let wholeColor {
            result.addAttribute(.foregroundColor, value: wholeColor, range: bodyRange)
            return result
        }

        if let tag = Self.tokenRegex.firstMatch(
               in: body,
               range: NSRange(location: 0, length: bodyText.length)
           ) {
            let token = bodyText.substring(with: tag.range)
            if let color = Self.previewTokenColor(token) {
                result.addAttributes([
                    .font: UIFont.systemFont(ofSize: 15, weight: .medium),
                    .foregroundColor: color
                ], range: NSRange(location: prefixLength + tag.range.location,
                                  length: tag.range.length))
            }
        } else if let color = Self.previewKindColor(kind) {
            result.addAttribute(.foregroundColor, value: color, range: bodyRange)
        } else if kind == "pat" || kind == "system" {
            result.addAttribute(
                .foregroundColor,
                value: configuration.isLight
                    ? UIColor(hex: 0x5C6B73)
                    : UIColor(hex: 0xA8B5BC),
                range: bodyRange
            )
        }

        if configuration.highlightMention {
            let range = NSRange(location: 0, length: bodyText.length)
            for match in Self.mentionRegex.matches(in: body, range: range) {
                result.addAttributes([
                    .font: UIFont.systemFont(ofSize: 15, weight: .medium),
                    .foregroundColor: UIColor.systemRed
                ], range: NSRange(location: prefixLength + match.range.location,
                                  length: match.range.length))
            }
        }
        return result
    }

    private static let mentionRegex = try! NSRegularExpression(
        pattern: "@[^\\s，。！？、；：:,!?;()\\[\\]{}<>]+"
    )

    private static let tokenRegex = try! NSRegularExpression(pattern: "\\[[^\\]]+\\]")

    private static func previewTokenColor(_ token: String) -> UIColor? {
        let value = token.replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
        if value.isEmpty { return nil }
        if value.contains("转账") || value.contains("红包") || value.contains("礼物")
            || value.contains("余额") || value.contains("经营账户") {
            return .systemRed
        }
        if value.contains("通话") {
            return .systemGreen
        }
        if value.contains("文件") || value.contains("笔记") {
            return .systemOrange
        }
        if value.contains("位置") || value.contains("名片") || value.contains("链接")
            || value.contains("文章") || value.contains("群公告") || value.contains("小程序") {
            return .systemBlue
        }
        if value.contains("图片") || value.contains("实况") || value.contains("视频")
            || value.contains("骰子") || value.contains("转盘")
            || value.contains("运势") || value.contains("猜拳") {
            return .systemPurple
        }
        if value.contains("语音") || value.contains("音频")
            || value.contains("音乐") || value.contains("表情") {
            return .systemGreen
        }
        return nil
    }

    private static func previewKindColor(_ kind: String) -> UIColor? {
        switch kind {
        case "transfer", "redpacket", "gift", "balance", "company":
            return .systemRed
        case "call", "voicecall", "videocall", "audio", "voice", "sticker":
            return .systemGreen
        case "file", "note":
            return .systemOrange
        case "location", "card", "link", "oa", "article", "miniapp", "mini", "app", "mall", "announce":
            return .systemBlue
        case "image", "images", "livephoto", "video", "channels", "channel", "feed", "shortvideo",
             "dice", "wheel", "fortune", "rps":
            return .systemPurple
        case "music":
            return .systemPink
        default:
            return nil
        }
    }

    private func setupViews() {
        backgroundConfiguration = .clear()
        contentView.clipsToBounds = true
        backgroundColor = .clear

        pinActions.axis = .horizontal
        pinActions.alignment = .center
        pinActions.spacing = 0
        pinActions.isHidden = true
        leftActions.axis = .horizontal
        leftActions.alignment = .center
        leftActions.spacing = actionGap
        leftActions.isHidden = true
        contentView.addSubview(pinActions)
        contentView.addSubview(leftActions)

        foreground.clipsToBounds = true
        contentView.addSubview(foreground)
        foreground.addSubview(avatarView)
        foreground.addSubview(titleLabel)
        foreground.addSubview(previewLabel)
        foreground.addSubview(timeLabel)
        foreground.addSubview(unreadLabel)
        foreground.addSubview(divider)
        pressOverlay.isUserInteractionEnabled = false
        pressOverlay.backgroundColor = .clear
        foreground.addSubview(pressOverlay)

        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        previewLabel.font = .systemFont(ofSize: 15, weight: .regular)
        previewLabel.lineBreakMode = .byTruncatingTail
        timeLabel.font = .systemFont(ofSize: 13, weight: .regular)
        timeLabel.textAlignment = .right
        timeLabel.adjustsFontSizeToFitWidth = true
        timeLabel.minimumScaleFactor = 0.75
        unreadLabel.textAlignment = .center
        unreadLabel.font = .systemFont(ofSize: 10, weight: .bold)
        unreadLabel.adjustsFontSizeToFitWidth = true
        unreadLabel.minimumScaleFactor = 0.9
        levelLabel.font = .monospacedDigitSystemFont(ofSize: 8.5, weight: .semibold)
        levelLabel.textColor = .secondaryLabel
        levelLabel.backgroundColor = UIColor.secondarySystemFill
        levelLabel.layer.cornerRadius = 4
        levelLabel.clipsToBounds = true
        memberLabel.font = .systemFont(ofSize: 8.5, weight: .semibold)
        memberLabel.textColor = .white
        memberLabel.layer.cornerRadius = 4
        memberLabel.clipsToBounds = true
    }

    private func layoutTitleBadges() {
        let baseWidth = min(titleLabel.intrinsicContentSize.width,
                            max(1, titleLabel.bounds.width))
        var x = titleLabel.frame.maxX - titleLabel.bounds.width + baseWidth + 5
        if !levelLabel.isHidden {
            levelLabel.sizeToFit()
            levelLabel.frame.origin = CGPoint(x: x, y: titleLabel.frame.midY - levelLabel.bounds.height / 2)
            foreground.addSubview(levelLabel)
            x = levelLabel.frame.maxX + 4
        }
        if !memberLabel.isHidden {
            memberLabel.sizeToFit()
            memberLabel.frame.origin = CGPoint(x: x, y: titleLabel.frame.midY - memberLabel.bounds.height / 2)
            foreground.addSubview(memberLabel)
        }
    }

    private func rebuildActions() {
        pinActions.arrangedSubviews.forEach { $0.removeFromSuperview() }
        leftActions.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let configuration else { return }

        let pinTitle = configuration.isPinned ? localized("取消置顶", "Unpin", "Открепить")
            : localized("置顶", "Pin", "Закрепить")
        pinActions.addArrangedSubview(makeAction(symbol: "pin.fill",
                                                 title: pinTitle,
                                                 background: UIColor(hex: 0x0A84FF)) { [weak self] in
            guard let self, let configuration = self.configuration else { return }
            configuration.onPin(!configuration.isPinned)
            self.closeActions()
        })
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        pinActions.addArrangedSubview(spacer)

        leftActions.addArrangedSubview(makeAction(symbol: "envelope.badge.fill",
                                                  title: localized("标为未读", "Unread", "Непрочитано"),
                                                  background: UIColor(hex: 0x28986C)) { [weak self] in
            self?.configuration?.onUnread()
            self?.closeActions()
        })
        leftActions.addArrangedSubview(makeAction(symbol: "eye.slash.fill",
                                                  title: localized("不显示", "Hide", "Скрыть"),
                                                  background: UIColor(hex: 0x7B8087)) { [weak self] in
            self?.configuration?.onHide()
            self?.closeActions()
        })
        leftActions.addArrangedSubview(makeAction(symbol: "trash.fill",
                                                  title: localized("删除", "Delete", "Удалить"),
                                                  background: .systemRed) { [weak self] in
            self?.configuration?.onDelete()
            self?.closeActions()
        })
    }

    private func makeAction(symbol: String,
                            title: String,
                            background: UIColor,
                            action: @escaping () -> Void) -> UIView {
        let container = UIView()
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.filled()
        config.image = UIImage(systemName: symbol)
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        config.baseBackgroundColor = background
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 13, leading: 13, bottom: 13, trailing: 13)
        button.configuration = config
        button.accessibilityLabel = title
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(button)
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 9, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: actionWidth),
            container.heightAnchor.constraint(equalToConstant: 64),
            button.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -7),
            button.widthAnchor.constraint(equalToConstant: actionWidth),
            button.heightAnchor.constraint(equalToConstant: actionWidth),
            label.topAnchor.constraint(equalTo: button.bottomAnchor, constant: 1),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
        return container
    }

    private func setupGestures() {
        // Row taps use UICollectionView's native selection path. The swipe is
        // owned by this UIKit cell so a custom Collection Cell cannot silently
        // swallow UISwipeActionsConfiguration on newer iOS builds.
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleAvatarTap(_:)))
        tap.cancelsTouchesInView = true
        tap.delaysTouchesBegan = false
        avatarView.isUserInteractionEnabled = true
        avatarView.addGestureRecognizer(tap)
        avatarTap = tap

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        pan.cancelsTouchesInView = false
        pan.delaysTouchesBegan = false
        foreground.addGestureRecognizer(pan)
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let translation = pan.translation(in: foreground)
        let velocity = pan.velocity(in: foreground)
        let byTranslation = abs(translation.x) >= 4
            && abs(translation.x) >= abs(translation.y) * 1.15
        let byVelocity = abs(velocity.x) >= 32
            && abs(velocity.x) >= abs(velocity.y) * 1.10
        return byTranslation || byVelocity
    }

    private func freezeEnclosingScroll() {
        var candidate: UIView? = superview
        while let view = candidate {
            if let scroll = view as? UIScrollView {
                frozenScrollPan = scroll.panGestureRecognizer
                scroll.panGestureRecognizer.isEnabled = false
                return
            }
            candidate = view.superview
        }
    }

    private func restoreEnclosingScroll() {
        frozenScrollPan?.isEnabled = true
        frozenScrollPan = nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        setPressed(true)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        setPressed(false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        setPressed(false)
    }

    private func setPressed(_ pressed: Bool) {
        let color: UIColor
        if configuration?.isLight == true {
            color = pressed ? UIColor.black.withAlphaComponent(0.045) : .clear
        } else {
            color = pressed ? UIColor.white.withAlphaComponent(0.07) : .clear
        }
        let duration = UIAccessibility.isReduceMotionEnabled ? 0 : 0.12
        UIView.animate(withDuration: duration,
                       delay: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.pressOverlay.backgroundColor = color
        }
    }

    @objc private func handleAvatarTap(_ gesture: UITapGestureRecognizer) {
        configuration?.onAvatar?()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let configuration else {
            restoreEnclosingScroll()
            return
        }
        let translation = gesture.translation(in: foreground).x
        let velocity = gesture.velocity(in: foreground).x
        switch gesture.state {
        case .began:
            freezeEnclosingScroll()
            startOffset = offset
            latestRawOffset = offset
            if dragDirection == 0 {
                dragDirection = translation < 0 ? -1 : (translation > 0 ? 1 : 0)
            }
            NotificationCenter.default.post(name: .chrisRowSwipe,
                                            object: configuration.chatId)
        case .changed:
            var raw = startOffset + translation
            if dragDirection == 0, abs(translation) >= 2 {
                dragDirection = translation < 0 ? -1 : 1
            }
            if dragDirection < 0, startOffset <= 0 {
                raw = min(0, raw)
            } else if dragDirection > 0, startOffset >= 0 {
                raw = max(0, raw)
            }
            latestRawOffset = raw
            offset = resisted(raw)
            foreground.transform = CGAffineTransform(translationX: offset, y: 0)
            pinActions.isHidden = offset <= 0
            leftActions.isHidden = offset >= 0
            let base = offset < 0
                ? actionInset + actionWidth * 3 + actionGap * 2
                : actionInset + actionWidth
            let progress = min(1, abs(offset) / max(1, base))
            let actions = offset < 0 ? leftActions : pinActions
            let direction: CGFloat = offset < 0 ? 1 : -1
            actions.alpha = 0.45 + progress * 0.55
            actions.transform = CGAffineTransform(
                translationX: direction * (1 - progress) * 10,
                y: 0
            )
        case .ended, .cancelled, .failed:
            restoreEnclosingScroll()
            let raw = latestRawOffset
            let projected = raw + velocity * 0.14
            let pinBase = actionInset + actionWidth
            let leftBase = actionInset + actionWidth * 3 + actionGap * 2
            let pinCommit = max(32, pinBase * 0.44)
            let leftCommit = max(46, min(leftBase * 0.34, bounds.width * 0.18))
            if dragDirection > 0, projected >= pinCommit {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                open(offset: pinBase, animated: true)
            } else if dragDirection < 0, projected <= -leftCommit {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                open(offset: -leftBase, animated: true)
            } else {
                closeActions()
            }
            if gesture.state == .ended, dragDirection < 0, -raw > bounds.width * 0.72 {
                configuration.onDelete()
            } else if gesture.state == .ended, dragDirection > 0, raw > bounds.width * 0.72 {
                configuration.onPin(!configuration.isPinned)
            }
        default:
            break
        }
    }

    private func resisted(_ raw: CGFloat) -> CGFloat {
        let limit = max(90, bounds.width * 0.24)
        if raw > 0, raw > actionInset + actionWidth {
            let extra = raw - (actionInset + actionWidth)
            return actionInset + actionWidth + limit * extra / (extra + 90)
        }
        let leftBase = actionInset + actionWidth * 3 + actionGap * 2
        if raw < 0, -raw > leftBase {
            let extra = -raw - leftBase
            return -(leftBase + limit * extra / (extra + 90))
        }
        return raw
    }

    private func open(offset target: CGFloat, animated: Bool) {
        let velocity = target - offset
        offset = target
        pinActions.isHidden = target <= 0
        leftActions.isHidden = target >= 0
        let updates = {
            self.foreground.transform = CGAffineTransform(translationX: target, y: 0)
            self.pinActions.alpha = target > 0 ? 1 : 0
            self.pinActions.transform = .identity
            self.leftActions.alpha = target < 0 ? 1 : 0
            self.leftActions.transform = .identity
        }
        if animated && !UIAccessibility.isReduceMotionEnabled {
            let velocityVector = CGVector(
                dx: max(-1, min(1, velocity / 900)),
                dy: 0
            )
            let timing = UISpringTimingParameters(
                dampingRatio: 0.86,
                initialVelocity: velocityVector
            )
            let animator = UIViewPropertyAnimator(duration: 0.32, timingParameters: timing)
            animator.addAnimations(updates)
            animator.startAnimation()
        } else {
            updates()
        }
    }

    private func closeActions() {
        open(offset: 0, animated: true)
    }

    @discardableResult
    func dismissOpenSwipeActions() -> Bool {
        guard offset != 0 else { return false }
        closeActions()
        return true
    }

    @objc private func handleSwipeElsewhere(_ note: Notification) {
        if let chatId = note.object as? String, chatId == configuration?.chatId {
            return
        }
        guard offset != 0 else { return }
        closeActions()
    }

    private func localized(_ zh: String, _ en: String, _ ru: String) -> String {
        if Lang.isRussian { return ru }
        if Lang.isEnglish { return en }
        return zh
    }

    private func configureAccessibility(_ configuration: NativeChatRowConfiguration) {
        let signature = [
            configuration.title,
            configuration.preview,
            configuration.mentionPrefix,
            configuration.time,
            String(configuration.unread),
            configuration.isPinned ? "1" : "0",
            Lang.code
        ].joined(separator: "\u{1E}")
        guard accessibilitySignature != signature else { return }
        accessibilitySignature = signature
        isAccessibilityElement = true
        accessibilityTraits = .button
        let unread = configuration.unread > 0
            ? localized("\(configuration.unread) 条未读",
                        "\(configuration.unread) unread",
                        "\(configuration.unread) непрочитанных")
            : ""
        accessibilityLabel = [
            configuration.title,
            unread,
            configuration.time,
            configuration.mentionPrefix + configuration.preview
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "，")
        accessibilityHint = localized("打开聊天，向左或向右滑动可查看更多操作",
                                      "Open chat. Swipe left or right for more actions",
                                      "Открыть чат. Смахните влево или вправо для дополнительных действий")

        let pinTitle = configuration.isPinned
            ? localized("取消置顶", "Unpin", "Открепить")
            : localized("置顶", "Pin", "Закрепить")
        let unreadTitle = localized("标为未读", "Mark unread", "Отметить непрочитанным")
        let hideTitle = localized("不显示", "Hide", "Скрыть")
        let deleteTitle = localized("删除", "Delete", "Удалить")

        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: pinTitle) { [weak self] _ in
                guard let self, let current = self.configuration else { return false }
                current.onPin(!current.isPinned)
                return true
            },
            UIAccessibilityCustomAction(name: unreadTitle) { [weak self] _ in
                guard let action = self?.configuration?.onUnread else { return false }
                action()
                return true
            },
            UIAccessibilityCustomAction(name: hideTitle) { [weak self] _ in
                guard let action = self?.configuration?.onHide else { return false }
                action()
                return true
            },
            UIAccessibilityCustomAction(name: deleteTitle) { [weak self] _ in
                guard let action = self?.configuration?.onDelete else { return false }
                action()
                return true
            }
        ]
    }

    override func accessibilityActivate() -> Bool {
        guard let configuration else { return false }
        if offset != 0 {
            closeActions()
        } else {
            configuration.onOpen()
        }
        return true
    }

}

private final class PaddingLabel: UILabel {
    private let insets: UIEdgeInsets

    init(insets: UIEdgeInsets) {
        self.insets = insets
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right,
                      height: size.height + insets.top + insets.bottom)
    }
}

private final class NativeChatAvatarView: UIView {
    private let tileContainer = UIView()
    private let tileViews = (0..<4).map { _ in UIImageView() }
    private let moodLabel = UILabel()
    private let onlineDot = UIView()
    private var token = UUID()

    var hasVisibleImage: Bool {
        tileViews.contains { !$0.isHidden && $0.image != nil }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false
        tileContainer.clipsToBounds = true
        tileContainer.layer.cornerRadius = 25
        tileContainer.layer.cornerCurve = .continuous
        tileContainer.backgroundColor = UIColor.secondarySystemFill
        addSubview(tileContainer)
        tileViews.forEach {
            $0.contentMode = .scaleAspectFill
            $0.clipsToBounds = true
            $0.backgroundColor = UIColor.tertiarySystemFill
            tileContainer.addSubview($0)
        }
        moodLabel.font = .systemFont(ofSize: 9)
        moodLabel.textAlignment = .center
        moodLabel.backgroundColor = .systemBackground
        moodLabel.layer.cornerRadius = 8.5
        moodLabel.clipsToBounds = true
        addSubview(moodLabel)
        onlineDot.backgroundColor = UIColor(hex: 0x4FD229)
        onlineDot.layer.cornerRadius = 7
        addSubview(onlineDot)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        tileContainer.frame = bounds
        tileContainer.layer.cornerRadius = min(bounds.width, bounds.height) / 2
        let gap: CGFloat = 1.2
        let visibleCount = tileViews.filter { !$0.isHidden }.count
        if visibleCount <= 1 {
            tileViews[0].frame = bounds
        } else if visibleCount == 2 {
            tileViews[0].frame = CGRect(x: 0, y: 0, width: (bounds.width - gap) / 2, height: bounds.height)
            tileViews[1].frame = CGRect(x: tileViews[0].frame.maxX + gap, y: 0,
                                        width: (bounds.width - gap) / 2, height: bounds.height)
        } else {
            let halfW = (bounds.width - gap) / 2
            let halfH = (bounds.height - gap) / 2
            tileViews[0].frame = CGRect(x: 0, y: 0, width: halfW, height: halfH)
            tileViews[1].frame = CGRect(x: halfW + gap, y: 0, width: halfW, height: halfH)
            tileViews[2].frame = CGRect(x: 0, y: halfH + gap, width: halfW, height: halfH)
            tileViews[3].frame = CGRect(x: halfW + gap, y: halfH + gap, width: halfW, height: halfH)
        }
        moodLabel.frame = CGRect(x: bounds.width - 16, y: bounds.height - 16, width: 17, height: 17)
        onlineDot.frame = CGRect(x: bounds.width - 14, y: bounds.height - 14, width: 14, height: 14)
    }

    func reset() {
        token = UUID()
        tileViews.forEach {
            $0.image = nil
            $0.isHidden = false
        }
        moodLabel.isHidden = true
        onlineDot.isHidden = true
    }

    func configure(paths: [String],
                   chatId: String,
                   memberIds: [String],
                   group: Bool,
                   online: Bool,
                   mood: String) {
        token = UUID()
        let requestToken = token
        let shown = group ? Array(paths.prefix(4)) : Array(paths.prefix(1))
        apply(paths: shown)
        if group, shown.filter({ !$0.isEmpty }).count < max(1, min(4, memberIds.count)) {
            NativeGroupAvatarCache.shared.paths(chatId: chatId, memberIds: memberIds) { [weak self] resolved in
                guard let self, self.token == requestToken else { return }
                self.apply(paths: Array(resolved.prefix(4)))
                self.setNeedsLayout()
            }
        }
        onlineDot.isHidden = !online
        moodLabel.isHidden = online || mood.isEmpty
        moodLabel.text = mood
        setNeedsLayout()
    }

    private func apply(paths: [String]) {
        let requestToken = token
        let shown = Array(paths.prefix(4))
        for (index, imageView) in tileViews.enumerated() {
            imageView.isHidden = index >= max(1, shown.count)
            imageView.image = nil
            imageView.backgroundColor = UIColor.tertiarySystemFill
            let path = index < shown.count ? shown[index] : ""
            guard !path.isEmpty else { continue }
            load(path: path) { [weak self, weak imageView] image in
                guard let self, self.token == requestToken, let imageView else { return }
                imageView.image = image
            }
        }
    }

    private func load(path: String, completion: @escaping (UIImage?) -> Void) {
        if let hit = ImageStore.shared.get(path + "#150") ?? ImageStore.shared.get(path) {
            completion(hit)
            return
        }
        Task {
            let diskData = await Task.detached(priority: .userInitiated) {
                ImageStore.shared.diskRead(path)
            }.value
            var data = diskData
            if let url = API.shared.assetURL(path) {
                let diskImage = data.flatMap {
                    RemoteImage.downsampled($0, maxSide: 150)
                }
                if diskImage == nil {
                    data = try? await API.shared.imageData(url)
                }
            }
            guard let data else {
                await MainActor.run { completion(nil) }
                return
            }
            let image = await Task.detached(priority: .userInitiated) {
                RemoteImage.downsampled(data, maxSide: 150) ?? UIImage(data: data)
            }.value
            if let image {
                ImageStore.shared.put(path + "#150", image)
                Task.detached(priority: .background) {
                    ImageStore.shared.diskWrite(path, data)
                }
            }
            await MainActor.run { completion(image) }
        }
    }
}

@MainActor
private final class NativeGroupAvatarCache {
    static let shared = NativeGroupAvatarCache()
    private var cached: [String: [String]] = [:]
    private var running: [String: Task<[String], Never>] = [:]

    func paths(chatId: String,
               memberIds: [String],
               completion: @escaping @MainActor ([String]) -> Void) {
        if let hit = cached[chatId] {
            completion(hit)
            return
        }
        if let task = running[chatId] {
            Task {
                let paths = await task.value
                completion(paths)
            }
            return
        }
        let ids = Array(memberIds.prefix(4))
        let task = Task { () -> [String] in
            guard let result = try? await API.shared.chatMembers(chatId: chatId) else {
                return ids.map { _ in "" }
            }
            let byId = Dictionary(uniqueKeysWithValues: result.members.map { ($0.id, $0) })
            let ordered = ids.count >= 4
                ? ids
                : Array(result.members.prefix(4)).map(\.id)
            return ordered.map { byId[$0]?.avatarPath ?? "" }
        }
        running[chatId] = task
        Task {
            let paths = await task.value
            cached[chatId] = paths
            running[chatId] = nil
            completion(paths)
        }
    }
}
