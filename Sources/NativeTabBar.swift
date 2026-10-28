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

/// 只替换底栏；页面、顶栏、导航和键盘布局继续使用 B2103 原实现。
struct NativeTabBar: UIViewRepresentable {
    @Binding var selection: Int
    @Environment(\.colorScheme) private var scheme
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
        _ = scheme
        applyColors(bar)
        if let item = bar.items?[safe: selection], bar.selectedItem !== item {
            bar.selectedItem = item
        }
        context.coordinator.applyCustomIcons(
            in: bar,
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
        /* 深色只染玻璃，不动底栏布局：上浅下深的半透明墨绿渐变。 */
        if scheme == .dark {
            appearance.backgroundColor = .clear
            appearance.backgroundImage = glassGradientImage()
        } else {
            appearance.backgroundColor = UIColor(red: 0.955, green: 0.982,
                                                 blue: 0.970, alpha: 0.68)
            appearance.backgroundImage = nil
        }
        appearance.shadowColor = UIColor.clear
        appearance.stackedLayoutAppearance.normal.iconColor = UIColor(OrbitTheme.secondary)
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor(OrbitTheme.secondary)
        ]
        appearance.stackedLayoutAppearance.selected.iconColor = UIColor(OrbitTheme.jade)
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: UIColor(OrbitTheme.jade)
        ]
        bar.standardAppearance = appearance
        bar.scrollEdgeAppearance = appearance
        bar.isTranslucent = true
    }

    private func glassGradientImage() -> UIImage {
        let size = CGSize(width: 1, height: 128)
        return UIGraphicsImageRenderer(size: size).image { context in
            let colors = [
                UIColor(red: 0.075, green: 0.290, blue: 0.235, alpha: 0.60).cgColor,
                UIColor(red: 0.025, green: 0.135, blue: 0.105, alpha: 0.72).cgColor
            ] as CFArray
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 1]
            ) else { return }
            context.cgContext.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: 0, y: size.height),
                options: []
            )
        }.resizableImage(withCapInsets: .zero, resizingMode: .stretch)
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
        private var avatarKey = ""
        private var appliedCustomKeys: [Int: String] = [:]
        private var iconTasks: [Int: Task<Void, Never>] = [:]
        private let customKeys = ["tab2.chat", "tab2.contacts", "tab2.world", "tab2.me"]
        private let symbols = ["message", "person.2", "safari", "person.crop.circle"]
        private let selectedSymbols = ["message.fill", "person.2.fill", "safari",
                                       "person.crop.circle.fill"]

        init(selection: Binding<Int>) {
            self.selection = selection
        }

        func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
            guard let index = tabBar.items?.firstIndex(where: { $0 === item }) else { return }
            selection.wrappedValue = index
        }

        func applyCustomIcons(in bar: UITabBar, normalColor: UIColor, selectedColor: UIColor) {
            guard let items = bar.items, items.count == 4 else { return }
            let size = UIConfig.num("tabIcon3", L.tabIconBox)
            for index in 0..<4 {
                let custom = IconOverrides.custom(customKeys[index])
                let resolved = custom ?? "__default__"
                guard appliedCustomKeys[index] != resolved else { continue }
                appliedCustomKeys[index] = resolved
                iconTasks[index]?.cancel()

                guard let custom else {
                    applyDefaultIcon(index: index, item: items[index], size: size,
                                     normalColor: normalColor, selectedColor: selectedColor)
                    continue
                }

                if custom.hasPrefix("http") || custom.hasPrefix("/uploads") || custom.hasPrefix("data:") {
                    loadRemoteIcon(custom, index: index, item: items[index], in: bar)
                } else {
                    applyRenderedIcon(custom, index: index, item: items[index],
                                      size: size, normalColor: normalColor,
                                      selectedColor: selectedColor)
                }
            }
        }

        private func applyDefaultIcon(index: Int, item: UITabBarItem, size: CGFloat,
                                      normalColor: UIColor, selectedColor: UIColor) {
            let normal = renderOrbit(index: index, selected: false, size: size,
                                     color: normalColor)
            let selected = renderOrbit(index: index, selected: true, size: size,
                                       color: selectedColor)
            item.image = normal.withRenderingMode(.alwaysOriginal)
            item.selectedImage = selected.withRenderingMode(.alwaysOriginal)
        }

        private func renderOrbit(index: Int, selected: Bool, size: CGFloat,
                                 color: UIColor) -> UIImage {
            let glyph = OrbitTabGlyph(kind: index, selected: selected,
                                      color: Color(uiColor: color),
                                      accent: OrbitTheme.gold)
                .frame(width: size, height: size)
            let renderer = ImageRenderer(content: glyph)
            renderer.scale = UIScreen.main.scale
            return renderer.uiImage ?? UIImage()
        }

        private func loadRemoteIcon(_ value: String, index: Int, item: UITabBarItem, in bar: UITabBar) {
            if let cached = ImageStore.shared.get(value) {
                item.image = cached.withRenderingMode(.alwaysOriginal)
                item.selectedImage = item.image
                return
            }
            guard let url = API.shared.assetURL(value) else { return }
            iconTasks[index] = Task { @MainActor [weak self, weak bar] in
                guard let self, let bar, self.appliedCustomKeys[index] == value,
                      let data = try? await API.shared.assetData(url),
                      let image = UIImage(data: data) else { return }
                ImageStore.shared.put(value, image)
                ImageStore.shared.diskWrite(value, data)
                guard bar.window != nil, self.appliedCustomKeys[index] == value,
                      let currentItem = bar.items?[safe: index] else { return }
                currentItem.image = image.withRenderingMode(.alwaysOriginal)
                currentItem.selectedImage = currentItem.image
            }
        }

        private func applyRenderedIcon(_ value: String, index: Int, item: UITabBarItem,
                                       size: CGFloat, normalColor: UIColor, selectedColor: UIColor) {
            let normal = render(value, index: index, size: size, color: normalColor)
            let selected = render(value, index: index, size: size, color: selectedColor)
            item.image = normal?.withRenderingMode(.alwaysOriginal)
                ?? UIImage(systemName: symbols[index])
            item.selectedImage = selected?.withRenderingMode(.alwaysOriginal)
                ?? UIImage(systemName: selectedSymbols[index])
        }

        private func render(_ value: String, index: Int, size: CGFloat, color: UIColor) -> UIImage? {
            let icon = FlexIcon(custom: value, size: size, color: Color(uiColor: color),
                                symbol: symbols[index])
                .frame(width: size + 2, height: size + 2)
            let renderer = ImageRenderer(content: icon)
            renderer.scale = UIScreen.main.scale
            return renderer.uiImage
        }

        func loadAvatar(_ path: String, in bar: UITabBar) {
            guard path != avatarKey, let item = bar.items?[safe: 3] else { return }
            avatarKey = path
            guard !path.isEmpty, let url = API.shared.assetURL(path) else {
                item.image = UIImage(systemName: "person.crop.circle")
                item.selectedImage = UIImage(systemName: "person.crop.circle.fill")
                return
            }
            if let cached = ImageStore.shared.get(path) {
                applyAvatar(cached, to: item)
                return
            }
            Task { @MainActor [weak self, weak bar] in
                guard let self = self, let bar = bar, bar.window != nil,
                      self.avatarKey == path,
                      let data = try? await API.shared.assetData(url),
                      let image = UIImage(data: data) else { return }
                guard bar.window != nil, self.avatarKey == path,
                      let currentItem = bar.items?[safe: 3] else { return }
                ImageStore.shared.put(path, image)
                ImageStore.shared.diskWrite(path, data)
                self.applyAvatar(image, to: currentItem)
            }
        }

        private func applyAvatar(_ image: UIImage, to item: UITabBarItem) {
            let size = CGSize(width: 25, height: 25)
            let avatar = UIGraphicsImageRenderer(size: size).image { _ in
                UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).addClip()
                image.draw(in: CGRect(origin: .zero, size: size))
            }
            let rendered = avatar.withRenderingMode(.alwaysOriginal)
            item.image = rendered
            item.selectedImage = rendered
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
