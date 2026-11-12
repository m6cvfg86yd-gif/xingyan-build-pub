import SwiftUI
import UIKit

private final class CompactDotTabBar: UITabBar {
    var dotIndexes: Set<Int> = [] {
        didSet { setNeedsLayout() }
    }

    var clearsNativeBackdrop = false {
        didSet { updateNativeBackdropVisibility() }
    }

    private var dotViews: [Int: UIView] = [:]

    override func layoutSubviews() {
        super.layoutSubviews()
        updateNativeBackdropVisibility()
        let slot = bounds.width / 4
        for index in 0..<4 {
            let dot = dotViews[index] ?? {
                let view = UIView()
                view.isUserInteractionEnabled = false
                view.layer.cornerRadius = 4
                addSubview(view)
                dotViews[index] = view
                return view
            }()
            dot.backgroundColor = .systemRed
            dot.layer.borderColor = UIColor(C.tabBg).cgColor
            dot.layer.borderWidth = 1
            dot.isHidden = !dotIndexes.contains(index)
            guard !dot.isHidden else { continue }
            let centerX = slot * (CGFloat(index) + 0.5)
            dot.frame = CGRect(x: centerX + 9.5, y: 3.5, width: 8, height: 8)
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

/*
 底栏图标加载器：
 网络下载只负责把图片放进缓存，绝不持有或回写 UITabBarItem。

 真机崩溃栈多次落在 swift_abortRetainUnowned →
 UITabBarItem._setInternalTemplateImage。根因是异步任务完成时，
 SwiftUI 已经把旧 UITabBar 拆掉，任务却还在修改旧 item。

 现在图片加载完成后只发布 revision；NativeTabBar.updateUIView 会拿
 当前仍存活的 UIView 重新同步赋值。这样不会跨 View 生命周期碰 UIKit。
 */
@MainActor
fileprivate final class TabIconLoader: ObservableObject {
    static let shared = TabIconLoader()

    @Published private(set) var revision = 0

    private var images: [String: UIImage] = [:]
    private var inFlight: Set<String> = []
    private var failed: Set<String> = []
    private var retryTasks: [String: Task<Void, Never>] = [:]
    private var preparedVersion = -1

    private init() {}

    func image(for value: String) -> UIImage? {
        if let image = images[value] { return image }
        guard let cached = ImageStore.shared.get(value) else { return nil }
        images[value] = cached
        return cached
    }

    func prepare(_ values: [String], version: Int) {
        if version != preparedVersion {
            preparedVersion = version
            failed.subtract(values)
        }
        for value in values where Self.isRaster(value) {
            if images[value] != nil || inFlight.contains(value) || failed.contains(value) {
                continue
            }
            if let cached = ImageStore.shared.get(value) {
                images[value] = cached
                continue
            }
            if value.hasPrefix("data:") {
                if let data = Self.decodeDataURL(value), let image = UIImage(data: data) {
                    images[value] = image
                } else {
                    failed.insert(value)
                }
                continue
            }
            loadRemote(value)
        }
    }

    private func loadRemote(_ value: String) {
        guard let url = API.shared.assetURL(value) else {
            failed.insert(value)
            return
        }
        inFlight.insert(value)
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.inFlight.remove(value) }
            do {
                let data = try await API.shared.assetData(url)
                guard !Task.isCancelled, let image = UIImage(data: data) else {
                    self.failed.insert(value)
                    self.scheduleRetry(value)
                    return
                }
                ImageStore.shared.put(value, image)
                ImageStore.shared.diskWrite(value, data)
                self.images[value] = image
                self.failed.remove(value)
                self.retryTasks.removeValue(forKey: value)?.cancel()
                self.revision &+= 1
            } catch {
                self.failed.insert(value)
                self.scheduleRetry(value)
            }
        }
    }

    fileprivate static func isRaster(_ value: String) -> Bool {
        value.hasPrefix("http") || value.hasPrefix("/") || value.hasPrefix("data:")
    }

    private func scheduleRetry(_ value: String) {
        retryTasks[value]?.cancel()
        retryTasks[value] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard let self, !Task.isCancelled else { return }
            self.failed.remove(value)
            self.retryTasks.removeValue(forKey: value)
            self.revision &+= 1
        }
    }

    private static func decodeDataURL(_ value: String) -> Data? {
        guard let comma = value.firstIndex(of: ","), value[..<comma].contains("base64") else {
            return nil
        }
        let encoded = String(value[value.index(after: comma)...])
        return Data(base64Encoded: encoded)
    }
}

/// 只替换底栏；页面、顶栏、导航和键盘布局继续使用 B2103 原实现。
struct NativeTabBar: UIViewRepresentable {
    @Binding var selection: Int
    @Environment(\.colorScheme) private var scheme
    @StateObject private var iconLoader = TabIconLoader.shared
    let uiVersion: Int
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
                         selectedImage: UIImage(systemName: "message.fill")),
            UITabBarItem(title: C.tabText1, image: UIImage(systemName: "person.2"),
                         selectedImage: UIImage(systemName: "person.2.fill")),
            UITabBarItem(title: C.tabText2, image: UIImage(systemName: "safari"),
                         selectedImage: UIImage(systemName: "safari")),
            UITabBarItem(title: C.tabText3, image: UIImage(systemName: "person.crop.circle"),
                         selectedImage: UIImage(systemName: "person.crop.circle.fill"))
        ]
        applyColors(bar)
        refresh(bar)
        return bar
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
        let size = UIConfig.num("tabIcon3", L.tabIconBox)
        var imagePaths = (0..<4).compactMap {
            context.coordinator.customIcon($0)
        }
        if context.coordinator.customIcon(3) == nil && !avatarPath.isEmpty {
            imagePaths.append(avatarPath)
        }
        iconLoader.prepare(imagePaths, version: uiVersion)
        context.coordinator.applyIcons(
            in: bar,
            loader: iconLoader,
            revision: iconLoader.revision,
            uiVersion: uiVersion,
            size: size,
            scheme: scheme == .dark ? "dark" : "light",
            avatarPath: context.coordinator.customIcon(3) == nil ? avatarPath : "",
            normalColor: UIColor(OrbitTheme.secondary),
            selectedColor: UIColor.systemBlue
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
        items[0].badgeValue = badge > 0 ? (badge > 99 ? "99+" : "\(badge)") : nil
        items[1].badgeValue = nil
        items[2].badgeValue = nil
        items[3].badgeValue = nil
        if let bar = bar as? CompactDotTabBar {
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
        fileprivate let customKeys = ["tab2.chat", "tab2.contacts", "tab2.world", "tab2.me"]
        private let legacyKeys = ["tab.chat", "tab.contacts", "tab.discover", "tab.me"]
        private let symbols = ["message", "person.2", "globe.americas", "person.crop.circle"]
        private let selectedSymbols = ["message.fill", "person.2.fill",
                                       "globe.americas.fill", "person.crop.circle.fill"]
        private var appliedIconKeys: [Int: String] = [:]
        private var appliedStyleKey = ""
        private let selectionFeedback = UISelectionFeedbackGenerator()

        init(selection: Binding<Int>) {
            self.selection = selection
        }

        func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
            guard let index = tabBar.items?.firstIndex(where: { $0 === item }) else { return }
            selectionFeedback.prepare()
            selectionFeedback.selectionChanged()
            selection.wrappedValue = index
        }

        fileprivate func customIcon(_ index: Int) -> String? {
            // 前三个入口固定使用系统图标，只有“我的”允许显示头像。
            if index < 3 { return nil }
            return IconOverrides.custom(customKeys[index]) ?? IconOverrides.custom(legacyKeys[index])
        }

        fileprivate func applyIcons(in bar: UITabBar, loader: TabIconLoader, revision: Int,
                                    uiVersion: Int, size: CGFloat, scheme: String,
                                    avatarPath: String,
                                    normalColor: UIColor, selectedColor: UIColor) {
            guard let items = bar.items, items.count == 4 else { return }
            let styleKey = "\(uiVersion)|\(revision)|\(size)|\(scheme)"
            if styleKey != appliedStyleKey {
                appliedStyleKey = styleKey
                appliedIconKeys.removeAll(keepingCapacity: true)
            }

            for index in 0..<4 {
                let custom = customIcon(index)
                let avatarKey = index == 3 ? avatarPath : ""
                let iconKey = "\(styleKey)|\(custom ?? "__default__")|\(avatarKey)"
                guard appliedIconKeys[index] != iconKey else { continue }

                if index < 3, custom == nil {
                    items[index].image = UIImage(systemName: symbols[index])?
                        .withRenderingMode(.alwaysTemplate)
                    items[index].selectedImage = gradientSymbol(
                        selectedSymbols[index],
                        size: size
                    )
                    appliedIconKeys[index] = iconKey
                    continue
                }

                if index == 3, custom == nil, !avatarPath.isEmpty,
                   loader.image(for: avatarPath) == nil {
                    // 图片还在缓存/网络加载中时保留上一张头像，避免底栏忽然变成占位图标。
                    continue
                }

                let rendered = renderedIcon(custom: custom, index: index, size: size,
                                            loader: loader,
                                            avatarPath: avatarPath,
                                            normalColor: normalColor,
                                            selectedColor: selectedColor)
                items[index].image = rendered.normal.withRenderingMode(.alwaysOriginal)
                items[index].selectedImage = rendered.selected.withRenderingMode(.alwaysOriginal)
                appliedIconKeys[index] = iconKey
            }
        }

        private func renderedIcon(custom: String?, index: Int, size: CGFloat,
                                  loader: TabIconLoader,
                                  avatarPath: String,
                                  normalColor: UIColor,
                                  selectedColor: UIColor) -> (normal: UIImage, selected: UIImage) {
            if let custom, TabIconLoader.isRaster(custom), let raster = loader.image(for: custom) {
                return (raster, raster)
            }
            if index == 3, custom == nil, !avatarPath.isEmpty,
               let avatar = loader.image(for: avatarPath) {
                let circled = circularAvatar(avatar)
                return (circled, circled)
            }

            let normal = render(custom: custom, index: index, selected: false, size: size,
                                color: normalColor)
            let itemSelectedColor = index == 3 ? UIColor(OrbitTheme.jade) : selectedColor
            let selected = render(custom: custom, index: index, selected: true, size: size,
                                  color: itemSelectedColor)
            return (normal, selected)
        }

        private func circularAvatar(_ image: UIImage) -> UIImage {
            let size = CGSize(width: 25, height: 25)
            return UIGraphicsImageRenderer(size: size).image { _ in
                UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).addClip()
                image.draw(in: CGRect(origin: .zero, size: size))
            }
        }

        private func gradientSymbol(_ name: String, size: CGFloat) -> UIImage? {
            let content = Image(systemName: name)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(hex: 0x20C96B),
                            Color(hex: 0xA7D96A),
                            Color(hex: 0xD9B95F)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size + 2, height: size + 2)
            let renderer = ImageRenderer(content: content)
            renderer.scale = UIScreen.main.scale
            return renderer.uiImage?.withRenderingMode(.alwaysOriginal)
        }

        private func render(custom: String?, index: Int, selected: Bool, size: CGFloat,
                            color: UIColor) -> UIImage {
            let content: AnyView
            if let custom, !TabIconLoader.isRaster(custom) {
                content = AnyView(FlexIcon(custom: custom, size: size,
                                           color: Color(uiColor: color),
                                           symbol: symbols[index])
                    .frame(width: size + 2, height: size + 2))
            } else {
                content = AnyView(OrbitTabGlyph(kind: index, selected: selected,
                                                color: Color(uiColor: color),
                                                accent: OrbitTheme.gold)
                    .frame(width: size, height: size))
            }
            let renderer = ImageRenderer(content: content)
            renderer.scale = UIScreen.main.scale
            return renderer.uiImage ?? UIImage(systemName: selected ? selectedSymbols[index] : symbols[index])
                ?? UIImage()
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
