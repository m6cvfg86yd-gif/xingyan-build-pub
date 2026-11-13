import SwiftUI
import UIKit

private final class BrandTabBadgeView: UIView {
    enum Kind {
        case count
        case dot
        case world
    }

    private let gradient = CAGradientLayer()
    private let highlight = CAShapeLayer()
    private let label = UILabel()
    private var kind: Kind = .dot
    private var ringColor = UIColor.black

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = false
        gradient.startPoint = CGPoint(x: 0.18, y: 0.08)
        gradient.endPoint = CGPoint(x: 0.82, y: 1)
        layer.insertSublayer(gradient, at: 0)

        label.textAlignment = .center
        label.textColor = .white
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.72
        addSubview(label)

        highlight.fillColor = UIColor.white.withAlphaComponent(0.24).cgColor
        layer.addSublayer(highlight)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(kind: Kind, count: Int = 0, ringColor: UIColor) {
        self.kind = kind
        self.ringColor = ringColor
        switch kind {
        case .count:
            label.isHidden = false
            label.text = count > 99 ? "99+" : "\(count)"
            label.font = .systemFont(ofSize: 9.5, weight: .bold)
            gradient.colors = [
                UIColor(red: 1.00, green: 0.23, blue: 0.19, alpha: 1).cgColor,
                UIColor(red: 0.95, green: 0.16, blue: 0.12, alpha: 1).cgColor
            ]
            layer.cornerRadius = 9
            layer.borderWidth = 1.2
            layer.borderColor = ringColor.cgColor
            layer.shadowOpacity = 0
        case .dot:
            label.isHidden = true
            gradient.colors = [
                UIColor(red: 1.00, green: 0.23, blue: 0.19, alpha: 1).cgColor,
                UIColor(red: 0.95, green: 0.16, blue: 0.12, alpha: 1).cgColor
            ]
            layer.cornerRadius = 4.25
            layer.borderWidth = 1.2
            layer.borderColor = ringColor.cgColor
            layer.shadowOpacity = 0
        case .world:
            label.isHidden = true
            gradient.colors = [
                UIColor(red: 1.00, green: 0.48, blue: 0.51, alpha: 1).cgColor,
                UIColor(red: 0.90, green: 0.13, blue: 0.24, alpha: 1).cgColor,
                UIColor(red: 0.66, green: 0.03, blue: 0.15, alpha: 1).cgColor
            ]
            layer.cornerRadius = 5.75
            layer.borderWidth = 1.3
            layer.borderColor = ringColor.cgColor
            layer.shadowColor = UIColor(red: 0.90, green: 0.13, blue: 0.24, alpha: 1).cgColor
            layer.shadowOpacity = 0.34
            layer.shadowRadius = 5
            layer.shadowOffset = CGSize(width: 0, height: 1.5)
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
        gradient.cornerRadius = layer.cornerRadius
        label.frame = bounds.insetBy(dx: 2, dy: 0)
        let highlightFrame = CGRect(
            x: max(1.5, bounds.width * 0.16),
            y: max(1.2, bounds.height * 0.12),
            width: max(2, bounds.width * 0.22),
            height: max(1.4, bounds.height * 0.14)
        )
        highlight.path = UIBezierPath(ovalIn: highlightFrame).cgPath
        highlight.isHidden = kind != .world
    }
}

private final class CompactDotTabBar: UITabBar {
    var dotIndexes: Set<Int> = [] {
        didSet { setNeedsLayout() }
    }

    var clearsNativeBackdrop = false {
        didSet { updateNativeBackdropVisibility() }
    }

    private var dotViews: [Int: UIView] = [:]
    var badgeCount: Int = 0 {
        didSet { setNeedsLayout() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateNativeBackdropVisibility()
        let slot = bounds.width / 4
        for index in 0..<4 {
            let dot = dotViews[index] ?? {
                let view = BrandTabBadgeView()
                view.layer.cornerRadius = 4
                addSubview(view)
                dotViews[index] = view
                return view
            }()
            let badge = dot as! BrandTabBadgeView
            let centerX = slot * (CGFloat(index) + 0.5)
            if index == 0, badgeCount > 0 {
                let title = badgeCount > 99 ? "99+" : "\(badgeCount)"
                let width: CGFloat = title.count > 2 ? 28 : (title.count > 1 ? 23 : 18)
                badge.frame = CGRect(x: centerX + 8, y: 2,
                                     width: width, height: 18)
                badge.apply(kind: .count, count: badgeCount,
                            ringColor: UIColor(C.tabBg))
                badge.isHidden = false
                bringSubviewToFront(badge)
                continue
            }
            let isWorld = index == 2 && dotIndexes.contains(index)
            let side: CGFloat = isWorld ? 11.5 : 8.5
            badge.frame = CGRect(x: centerX + (isWorld ? 9 : 10),
                                 y: isWorld ? 3.5 : 4,
                                 width: side, height: side)
            badge.apply(kind: isWorld ? .world : .dot,
                        ringColor: UIColor(C.tabBg))
            badge.isHidden = !dotIndexes.contains(index)
            guard !dot.isHidden else { continue }
            bringSubviewToFront(dot)
        }
    }

    private func updateNativeBackdropVisibility() {
        /* iOS 26/27 会保留一层原生 TabBar 背板。深色只隐藏这层，
           不覆盖图标内容；外层 TabGlassBackdrop 继续负责玻璃效果。 */
        for child in subviews {
            let typeName = String(describing: type(of: child))
            guard typeName.contains("BarBackground") else { continue }
            child.isHidden = clearsNativeBackdrop
        }
    }
}

@MainActor
fileprivate final class TabAvatarLoader: ObservableObject {
    static let shared = TabAvatarLoader()

    @Published private(set) var revision = 0

    private var images: [String: UIImage] = [:]
    private var inFlight: Set<String> = []
    private var retryTasks: [String: Task<Void, Never>] = [:]

    private init() {}

    func image(for value: String) -> UIImage? {
        if let image = images[value] { return image }
        guard let cached = ImageStore.shared.get(value) else { return nil }
        images[value] = cached
        return cached
    }

    func prepare(_ value: String) {
        guard !value.isEmpty, images[value] == nil, !inFlight.contains(value) else { return }
        if let cached = ImageStore.shared.get(value) {
            images[value] = cached
            revision &+= 1
            return
        }
        guard let url = API.shared.assetURL(value) else { return }
        inFlight.insert(value)
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.inFlight.remove(value) }
            do {
                let data = try await API.shared.assetData(url)
                guard !Task.isCancelled, let image = UIImage(data: data) else {
                    self.scheduleRetry(value)
                    return
                }
                ImageStore.shared.put(value, image)
                ImageStore.shared.diskWrite(value, data)
                self.images[value] = image
                self.revision &+= 1
            } catch {
                self.scheduleRetry(value)
            }
        }
    }

    private func scheduleRetry(_ value: String) {
        retryTasks[value]?.cancel()
        retryTasks[value] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard let self, !Task.isCancelled else { return }
            self.retryTasks.removeValue(forKey: value)
            self.prepare(value)
        }
    }
}

/// 只替换底栏；页面、顶栏、导航和键盘布局继续使用 B2103 原实现。
struct NativeTabBar: UIViewRepresentable {
    @Binding var selection: Int
    @Environment(\.colorScheme) private var scheme
    @StateObject private var avatarLoader = TabAvatarLoader.shared
    let badge: Int
    let contactsDot: Bool
    let momentsDot: Bool
    let meDot: Bool
    let avatarPath: String

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeUIView(context: Context) -> UITabBar {
        let bar = CompactDotTabBar()
        bar.delegate = context.coordinator
        bar.itemPositioning = .fill
        bar.items = [
            UITabBarItem(title: C.tabText0, image: UIImage(systemName: "message"),
                         selectedImage: Self.messageIconWithEyes()),
            UITabBarItem(title: C.tabText1, image: UIImage(systemName: "person.2"),
                         selectedImage: UIImage(systemName: "person.2.fill")),
            UITabBarItem(title: C.tabText2, image: UIImage(systemName: "safari"),
                         selectedImage: Self.worldIconWithOrbit()),
            UITabBarItem(title: C.tabText3, image: UIImage(systemName: "person.crop.circle"),
                         selectedImage: UIImage(systemName: "person.crop.circle.fill")?
                            .withTintColor(UIColor(OrbitTheme.jade),
                                           renderingMode: .alwaysOriginal))
        ]
        applyColors(bar)
        refresh(bar)
        return bar
    }

    private static func messageIconWithEyes() -> UIImage? {
        guard let bubble = UIImage(systemName: "message.fill")?
            .withTintColor(.black, renderingMode: .alwaysOriginal) else { return nil }
        let side: CGFloat = 28
        let size = CGSize(width: side, height: side)
        return UIGraphicsImageRenderer(size: size).image { renderer in
            bubble.draw(in: CGRect(origin: .zero, size: size))
            let context = renderer.cgContext
            context.setBlendMode(.clear)
            context.setFillColor(UIColor.clear.cgColor)
            context.fillEllipse(in: CGRect(x: 9.2, y: 11.3, width: 3.4, height: 3.4))
            context.fillEllipse(in: CGRect(x: 15.4, y: 11.3, width: 3.4, height: 3.4))
        }
        .withRenderingMode(.alwaysTemplate)
    }

    private static func worldIconWithOrbit() -> UIImage? {
        guard let safari = UIImage(systemName: "safari")?
            .withTintColor(.black, renderingMode: .alwaysOriginal) else { return nil }
        let side: CGFloat = 30
        let size = CGSize(width: side, height: side)
        return UIGraphicsImageRenderer(size: size).image { renderer in
            safari.draw(in: CGRect(x: 3, y: 3, width: 24, height: 24))

            let context = renderer.cgContext
            context.saveGState()
            context.translateBy(x: 15, y: 15)
            context.rotate(by: -.pi / 9)
            context.setStrokeColor(UIColor.black.cgColor)
            context.setLineWidth(0.9)
            context.strokeEllipse(in: CGRect(x: -12.5, y: -4.2, width: 25, height: 8.4))
            context.restoreGState()

            if let sparkle = UIImage(systemName: "sparkle")?
                .withTintColor(.black, renderingMode: .alwaysOriginal) {
                sparkle.draw(in: CGRect(x: 22.5, y: 2.5, width: 5.5, height: 5.5))
            }
        }
        .withRenderingMode(.alwaysTemplate)
    }

    func updateUIView(_ bar: UITabBar, context: Context) {
        context.coordinator.selection = $selection
        applyColors(bar)
        let titles = [C.tabText0, C.tabText1, C.tabText2, C.tabText3]
        if let items = bar.items, items.count == titles.count {
            for index in titles.indices where items[index].title != titles[index] {
                items[index].title = titles[index]
            }
            bar.setNeedsLayout()
        }
        if let item = bar.items?[safe: selection], bar.selectedItem !== item {
            bar.selectedItem = item
        }
        avatarLoader.prepare(avatarPath)
        context.coordinator.applyAvatar(
            in: bar,
            loader: avatarLoader,
            revision: avatarLoader.revision,
            avatarPath: avatarPath
        )
        refresh(bar)
    }

    private func applyColors(_ bar: UITabBar) {
        bar.tintColor = UIColor.systemBlue
        bar.unselectedItemTintColor = UIColor(OrbitTheme.secondary)

        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        bar.isOpaque = false
        if scheme == .dark {
            // 深色玻璃跟随管理端整套主题，不再固定成一个脱离页面的黑阶。
            appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
            let themed = UIConfig.colorIfSet("tabBarColor")
                ?? UIConfig.colorIfSet("tabBg")
                ?? C.pageBg
            appearance.backgroundColor = UIColor(themed).withAlphaComponent(0.72)
        }
        let normalTitle: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor(OrbitTheme.secondary),
            .font: pfUIFont(10.5, .medium)
        ]
        let selectedTitle: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor(OrbitTheme.secondary),
            .font: pfUIFont(10.5, .semibold)
        ]
        let selectedMyTitle: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor(OrbitTheme.jade),
            .font: pfUIFont(10.5, .semibold)
        ]
        appearance.stackedLayoutAppearance.normal.iconColor = UIColor(OrbitTheme.secondary)
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = normalTitle
        appearance.stackedLayoutAppearance.selected.iconColor = UIColor.systemBlue
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = selectedTitle
        if let items = bar.items, items.count == 4 {
            // “我的”保持原来的品牌绿，只统一前三个入口的苹果蓝选中色。
            items[3].setTitleTextAttributes(normalTitle, for: .normal)
            items[3].setTitleTextAttributes(selectedMyTitle, for: .selected)
        }
        if scheme == .dark {
            appearance.selectionIndicatorImage = UIImage()
            bar.selectionIndicatorImage = UIImage()
        }
        if #available(iOS 26.0, *) {
            if #unavailable(iOS 27.0) {
                let offset = UIOffset(horizontal: 0, vertical: 8)
                appearance.stackedLayoutAppearance.selected.titlePositionAdjustment = offset
                appearance.inlineLayoutAppearance.selected.titlePositionAdjustment = offset
                appearance.compactInlineLayoutAppearance.selected.titlePositionAdjustment = offset
            }
        }
        bar.standardAppearance = appearance
        bar.scrollEdgeAppearance = appearance
        bar.isTranslucent = true
        (bar as? CompactDotTabBar)?.clearsNativeBackdrop = false
    }

    private func refresh(_ bar: UITabBar) {
        guard let items = bar.items, items.count == 4 else { return }
        items[0].badgeValue = nil
        items[1].badgeValue = nil
        items[2].badgeValue = nil
        items[3].badgeValue = nil
        if let bar = bar as? CompactDotTabBar {
            bar.badgeCount = badge
            var dots: Set<Int> = []
            if contactsDot { dots.insert(1) }
            if momentsDot { dots.insert(2) }
            if meDot { dots.insert(3) }
            guard bar.dotIndexes != dots else { return }
            bar.dotIndexes = dots
            bar.setNeedsLayout()
        }
    }

    final class Coordinator: NSObject, UITabBarDelegate {
        var selection: Binding<Int>
        private let selectionFeedback = UISelectionFeedbackGenerator()
        private var appliedAvatarKey = ""
        private let systemMyImage = UIImage(systemName: "person.crop.circle")?
            .withRenderingMode(.alwaysTemplate)
        private let systemMySelected = UIImage(systemName: "person.crop.circle.fill")?
            .withTintColor(UIColor(OrbitTheme.jade), renderingMode: .alwaysOriginal)

        init(selection: Binding<Int>) {
            self.selection = selection
        }

        func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
            guard let index = tabBar.items?.firstIndex(where: { $0 === item }) else { return }
            selectionFeedback.prepare()
            selectionFeedback.selectionChanged()
            selection.wrappedValue = index
        }

        fileprivate func applyAvatar(in bar: UITabBar, loader: TabAvatarLoader,
                                     revision: Int, avatarPath: String) {
            guard let items = bar.items, items.count == 4 else { return }
            let key = "\(revision)|\(avatarPath)"
            guard key != appliedAvatarKey else { return }

            guard !avatarPath.isEmpty, let avatar = loader.image(for: avatarPath) else {
                if avatarPath.isEmpty {
                    items[3].image = systemMyImage
                    items[3].selectedImage = systemMySelected
                    appliedAvatarKey = key
                }
                return
            }

            let circled = circularAvatar(avatar)
            items[3].image = circled.withRenderingMode(.alwaysOriginal)
            items[3].selectedImage = circled.withRenderingMode(.alwaysOriginal)
            appliedAvatarKey = key
        }

        private func circularAvatar(_ image: UIImage) -> UIImage {
            let side: CGFloat = 25
            let size = CGSize(width: side, height: side)
            return UIGraphicsImageRenderer(size: size).image { _ in
                UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).addClip()
                let scale = max(size.width / max(1, image.size.width),
                                size.height / max(1, image.size.height))
                let drawSize = CGSize(width: image.size.width * scale,
                                      height: image.size.height * scale)
                image.draw(in: CGRect(x: (side - drawSize.width) / 2,
                                      y: (side - drawSize.height) / 2,
                                      width: drawSize.width,
                                      height: drawSize.height))
            }
        }
    }
}

struct TabGlassBackdrop: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        TabGlassBackdropView()
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    private final class TabGlassBackdropView: UIView {
        private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        private let tint = CAGradientLayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
            clipsToBounds = true
            blur.isUserInteractionEnabled = false
            addSubview(blur)

            tint.colors = [
                UIColor(red: 25 / 255, green: 25 / 255, blue: 25 / 255, alpha: 0.72).cgColor,
                UIColor(red: 25 / 255, green: 25 / 255, blue: 25 / 255, alpha: 0.72).cgColor
            ]
            tint.startPoint = CGPoint(x: 0.5, y: 0)
            tint.endPoint = CGPoint(x: 0.5, y: 1)
            layer.addSublayer(tint)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            blur.frame = bounds
            tint.frame = bounds
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
