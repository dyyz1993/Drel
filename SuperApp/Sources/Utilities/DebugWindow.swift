//
//  DebugWindow.swift
//  Drel
//
//  摇一摇唤起调试面板的窗口（DEBUG）；Release 回退为普通 UIWindow。
//  从 AppDelegate.swift 原样迁出以控制其文件长度（开源前置清理，2026-10-30）。
//

import UIKit

#if DEBUG
class DebugWindow: UIWindow {
    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        guard motion == .motionShake else { return }

        let debugPanel = DebugPanelViewController()
        let nav = UINavigationController(rootViewController: debugPanel)
        nav.modalPresentationStyle = .fullScreen

        topViewController()?.present(nav, animated: true)
    }

    private func topViewController() -> UIViewController? {
        let root = rootViewController
        return getTopViewController(from: root)
    }

    private func getTopViewController(from vc: UIViewController?) -> UIViewController? {
        guard let vc = vc else { return nil }
        if let presented = vc.presentedViewController {
            return getTopViewController(from: presented)
        }
        if let nav = vc as? UINavigationController {
            return getTopViewController(from: nav.visibleViewController)
        }
        if let tab = vc as? UITabBarController {
            return getTopViewController(from: tab.selectedViewController)
        }
        return vc
    }
}
#else
typealias DebugWindow = UIWindow
#endif
