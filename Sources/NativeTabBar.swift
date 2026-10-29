import SwiftUI
import UIKit

private final class CompactDotTabBar: UITabBar {
    var dotIndexes: Set<Int> = [] {
        didSet { setNeedsLayout() }
    }

    private var dotViews: [Int: UIView] = [:]

    override func layoutSubviews() {
        super.layoutSubviews()
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
            dot.backgroundColor = UIColor(C.red)
            dot.layer.borderColor = UIColor(C.tabBg).cgColor
            dot.layer.borderWidth = 1
            dot.isHidden = !dotIndexes.contains(index)
            guard !dot.isHidden else { continue }
            let centerX = slot * (CGFloat(index) + 0.5)
            dot.frame = CGRect(x: centerX + 9.5, y: 3.5, width: 8, height: 8)
            bringSubviewToFront(dot)
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
                    return
                }
                ImageStore.shared.put(value, image)
                ImageStore.shared.diskWrite(value, data)
                self.images[value] = image
                self.revision &+= 1
            } catch {
                self.failed.insert(value)
            }
        }
    }

    fileprivate static func isRaster(_ value: String) -> Bool {
        value.hasPrefix("http") || value.hasPrefix("/uploads") || value.hasPrefix("data:")
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
            selectedColor: UIColor(OrbitTheme.jade)
        )
        refresh(bar)
    }

    private func applyColors(_ bar: UITabBar) {
        bar.tintColor = UIColor(OrbitTheme.jade)
        bar.unselectedItemTintColor = UIColor(OrbitTheme.secondary)

        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(
            style: scheme == .dark ? .systemUltraThinMaterialDark : .systemThinMaterialLight
        )
        if scheme == .dark {
            appearance.backgroundEffect = nil
            appearance.backgroundColor = .clear
            appearance.backgroundImage = nil
        } else {
            appearance.backgroundColor = UIColor(red: 0.955, green: 0.982,
                                                 blue: 0.970, alpha: 0.68)
            appearance.backgroundImage = nil
        }
        appearance.shadowColor = UIColor.clear
        let normalTitle: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor(OrbitTheme.secondary),
            .font: UIFont.systemFont(ofSize: 10.5, weight: .medium)
        ]
        let selectedTitle: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor(OrbitTheme.jade),
            .font: UIFont.systemFont(ofSize: 10.5, weight: .semibold)
        ]
        appearance.stackedLayoutAppearance.normal.iconColor = UIColor(OrbitTheme.secondary)
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = normalTitle
        appearance.stackedLayoutAppearance.selected.iconColor = UIColor(OrbitTheme.jade)
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = selectedTitle
        bar.standardAppearance = appearance
        bar.scrollEdgeAppearance = appearance
        bar.isTranslucent = true
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
            bar.dotIndexes = dots
            bar.setNeedsLayout()
        }
    }

    final class Coordinator: NSObject, UITabBarDelegate {
        var selection: Binding<Int>
        fileprivate let customKeys = ["tab2.chat", "tab2.contacts", "tab2.world", "tab2.me"]
        private let legacyKeys = ["tab.chat", "tab.contacts", "tab.discover", "tab.me"]
        private let symbols = ["message", "person.2", "safari", "person.crop.circle"]
        private let selectedSymbols = ["message.fill", "person.2.fill", "safari",
                                       "person.crop.circle.fill"]
        private var appliedIconKeys: [Int: String] = [:]
        private var appliedStyleKey = ""

        init(selection: Binding<Int>) {
            self.selection = selection
        }

        func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
            guard let index = tabBar.items?.firstIndex(where: { $0 === item }) else { return }
            selection.wrappedValue = index
        }

        fileprivate func customIcon(_ index: Int) -> String? {
            IconOverrides.custom(customKeys[index]) ?? IconOverrides.custom(legacyKeys[index])
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
            let selected = render(custom: custom, index: index, selected: true, size: size,
                                  color: selectedColor)
            return (normal, selected)
        }

        private func circularAvatar(_ image: UIImage) -> UIImage {
            let size = CGSize(width: 25, height: 25)
            return UIGraphicsImageRenderer(size: size).image { _ in
                UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).addClip()
                image.draw(in: CGRect(origin: .zero, size: size))
            }
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
                UIColor(red: 0.110, green: 0.110, blue: 0.110, alpha: 0.64).cgColor,
                UIColor(red: 0.075, green: 0.075, blue: 0.075, alpha: 0.82).cgColor
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
