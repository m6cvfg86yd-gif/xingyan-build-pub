import SwiftUI
import UIKit

final class StatusBarStyle: ObservableObject {
    static let shared = StatusBarStyle()

    private var window: UIWindow?
    private var light = false

    func set(light want: Bool) {
        if want == light && (want == false || window != nil) { return }
        light = want
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if want {
                if self.window == nil {
                    guard let scene = UIApplication.shared.connectedScenes
                        .compactMap({ $0 as? UIWindowScene })
                        .first(where: { $0.activationState == .foregroundActive })
                        ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
                    else { return }
                    let w = UIWindow(windowScene: scene)
                    w.windowLevel = .statusBar
                    w.backgroundColor = .clear
                    w.isUserInteractionEnabled = false
                    w.rootViewController = LightStatusVC()
                    self.window = w
                }
                self.window?.isHidden = false
                self.window?.rootViewController?.setNeedsStatusBarAppearanceUpdate()
            } else {
                self.window?.isHidden = true
                self.window?.rootViewController?.setNeedsStatusBarAppearanceUpdate()
            }
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
