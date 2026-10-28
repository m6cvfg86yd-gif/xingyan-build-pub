import SwiftUI
import UIKit

final class StatusBarStyle: ObservableObject {
    static let shared = StatusBarStyle()

    private var window: UIWindow?
    private var light = false

    func set(light want: Bool) {
        if Thread.isMainThread {
            apply(light: want)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.apply(light: want)
            }
        }
    }

    private func apply(light want: Bool) {
        if want == light && (want == false || window != nil) { return }
        light = want
        if want {
            if window == nil {
                guard let scene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first(where: { $0.activationState == .foregroundActive })
                    ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
                else { return }
                let next = UIWindow(windowScene: scene)
                next.windowLevel = .statusBar
                next.backgroundColor = .clear
                next.isUserInteractionEnabled = false
                next.rootViewController = LightStatusVC()
                window = next
            }
            window?.isHidden = false
            window?.rootViewController?.setNeedsStatusBarAppearanceUpdate()
        } else {
            window?.isHidden = true
            window?.rootViewController?.setNeedsStatusBarAppearanceUpdate()
        }
    }

    private final class LightStatusVC: UIViewController {
        override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
        }
    }
}
