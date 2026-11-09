import SwiftUI
import UIKit

struct ThemedScrollIndicators: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .onAppear { apply() }
            .onChange(of: scheme) { _ in apply() }
    }

    private func apply() {
        let style: UIScrollView.IndicatorStyle = scheme == .dark ? .white : .black
        UIScrollView.appearance().indicatorStyle = style

        DispatchQueue.main.async {
            let windows = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
            for window in windows {
                Self.updateScrollViews(in: window, style: style)
            }
        }
    }

    private static func updateScrollViews(in view: UIView,
                                          style: UIScrollView.IndicatorStyle) {
        if let scrollView = view as? UIScrollView {
            scrollView.indicatorStyle = style
        }
        for child in view.subviews {
            updateScrollViews(in: child, style: style)
        }
    }
}
