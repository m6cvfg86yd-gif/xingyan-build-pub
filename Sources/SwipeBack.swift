import SwiftUI
import UIKit

final class SwipeBackPage: ObservableObject {
    let id = UUID()
    var onBack: () -> Void = {}
    var enabled = true
    var width: CGFloat = 390

    weak var host: UIView?

    var hostSet = false

    @Published var offset: CGFloat = 0
}

final class SwipeBackCenter: NSObject, UIGestureRecognizerDelegate {
    static let shared = SwipeBackCenter()

    private var pages: [SwipeBackPage] = []
    private weak var pan: UIScreenEdgePanGestureRecognizer?

    private weak var hostWindow: UIWindow?

    private var retries = 0

    private var tracking = false
    private var tracked: SwipeBackPage?

    func push(_ p: SwipeBackPage) {
        pages.removeAll { $0 === p }
        pages.append(p)

        installIfNeeded()
    }

    func remove(_ p: SwipeBackPage) {
        pages.removeAll { $0 === p }
        if tracked === p { tracked = nil; tracking = false }
        p.offset = 0
    }

    private var top: SwipeBackPage? {

        pages.removeAll { p in
            guard p.hostSet else { return false }
            guard let h = p.host else { return true }
            return h.window == nil
        }
        for p in pages.reversed() where p.enabled { return p }
        return nil
    }

    private func installIfNeeded() {
        guard let win = Self.keyWindow() else {

            if retries < 20 {
                retries += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.installIfNeeded() }
            }
            return
        }

        if let g = pan, g.view === win { hostWindow = win; return }

        if let old = pan {
            old.view?.removeGestureRecognizer(old)
            pan = nil
        }
        retries = 0
        let g = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handle(_:)))
        g.edges = .left
        g.delegate = self

        g.cancelsTouchesInView = true
        g.delaysTouchesBegan = false
        win.addGestureRecognizer(g)
        pan = g
        hostWindow = win
    }

    static func keyWindow() -> UIWindow? {
        let all = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }

        return all.first { $0.isKeyWindow && $0.windowLevel == .normal }
            ?? all.first { $0.isKeyWindow }
            ?? all.first { $0.windowLevel == .normal && !$0.isHidden }
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        installIfNeeded()
        return top != nil
    }

    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard let p = top, let v = g.view, let pan = g as? UIPanGestureRecognizer else { return false }
        let vel = pan.velocity(in: v)
        guard vel.x > 0 else { return false }
        guard abs(vel.x) > abs(vel.y) * 1.1 else { return false }
        tracked = p
        return true
    }

    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    @objc private func handle(_ g: UIPanGestureRecognizer) {
        guard let v = g.view else { return }
        let t = g.translation(in: v)
        switch g.state {
        case .began:
            tracking = true
            tracked?.offset = max(0, t.x)
        case .changed:
            guard tracking, let p = tracked else { return }

            p.offset = max(0, t.x)
        case .ended:
            guard tracking, let p = tracked else { return }
            tracking = false
            tracked = nil
            let far = p.offset > p.width * 0.32
            let fast = g.velocity(in: v).x > 950
            if far || fast {
                withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.90)) {
                    p.offset = p.width
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                    if p.offset > 0 { p.onBack() }
                    p.offset = 0
                }
            } else {
                withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.90)) {
                    p.offset = 0
                }
            }
        default:

            tracking = false
            if let p = tracked { withAnimation(.easeOut(duration: 0.2)) { p.offset = 0 } }
            tracked = nil
        }
    }

}

struct SwipeBackModifier: ViewModifier {
    let enabled: Bool
    let onBack: () -> Void

    @StateObject private var page = SwipeBackPage()

    private var width: CGFloat { max(1, L.width) }

    func body(content: Content) -> some View {
        ZStack {
            content
                .offset(x: page.offset)
                .overlay(
                    Color.black
                        .opacity(0.16 * Double(min(1, page.offset / width)))
                        .allowsHitTesting(false)
                )

                .background(SwipeBackHost(page: page).frame(width: 0, height: 0).allowsHitTesting(false))
        }
        .background(C.pageBg)
        .onAppear {
            page.onBack = onBack
            page.width = width
            page.enabled = enabled
            SwipeBackCenter.shared.push(page)
        }
        .onDisappear { SwipeBackCenter.shared.remove(page) }
        .onChange(of: enabled) { v in page.enabled = v }
        .onChange(of: width) { w in page.width = w }
    }
}

private struct SwipeBackHost: UIViewRepresentable {
    let page: SwipeBackPage

    func makeUIView(context: Context) -> UIView {
        let v = UIView(frame: .zero)
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear

        DispatchQueue.main.async { self.page.host = v; self.page.hostSet = true }
        return v
    }

    func updateUIView(_ v: UIView, context: Context) {
        if page.host !== v { DispatchQueue.main.async { self.page.host = v; self.page.hostSet = true } }
    }
}

extension View {

    func swipeBack(_ enabled: Bool = true, onBack: @escaping () -> Void) -> some View {
        modifier(SwipeBackModifier(enabled: enabled, onBack: onBack))
    }
}
