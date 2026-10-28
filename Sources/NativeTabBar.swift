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
        context.coordinator.loadAvatar(avatarPath, in: bar)
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
        /* 玻璃层保留透光，但压一层浅墨绿，避免深色模式看起来仍是灰黑色。 */
        appearance.backgroundColor = scheme == .dark
            ? UIColor(red: 0.035, green: 0.145, blue: 0.112, alpha: 0.64)
            : UIColor(red: 0.955, green: 0.982, blue: 0.970, alpha: 0.68)
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

        init(selection: Binding<Int>) {
            self.selection = selection
        }

        func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
            guard let index = tabBar.items?.firstIndex(where: { $0 === item }) else { return }
            selection.wrappedValue = index
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
