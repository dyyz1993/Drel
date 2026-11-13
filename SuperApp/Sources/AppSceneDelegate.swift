import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    private var appDelegate: AppDelegate? {
        UIApplication.shared.delegate as? AppDelegate
    }

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = DebugWindow(windowScene: windowScene)
        window.rootViewController = TabBarController()
        let hasExplicitLaunchDestination = connectionOptions.notificationResponse != nil
            || !connectionOptions.urlContexts.isEmpty
        appDelegate?.markSceneLaunchDestination(hasExplicitLaunchDestination)
        window.makeKeyAndVisible()
        self.window = window

        appDelegate?.adoptSceneWindow(
            window,
            hasExplicitLaunchDestination: hasExplicitLaunchDestination
        )

        // Scene cold launches deliver URLs here, not in launchOptions.
        // Notification taps keep their existing UNUserNotificationCenter routing.
        if connectionOptions.notificationResponse == nil {
            DispatchQueue.main.async { [weak self] in
                self?.openURLContexts(connectionOptions.urlContexts)
            }
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        openURLContexts(URLContexts)
    }

    private func openURLContexts(_ contexts: Set<UIOpenURLContext>) {
        for context in contexts {
            _ = appDelegate?.application(UIApplication.shared, open: context.url)
        }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        appDelegate?.applicationDidBecomeActive(UIApplication.shared)
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        appDelegate?.applicationWillEnterForeground(UIApplication.shared)
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        appDelegate?.applicationDidEnterBackground(UIApplication.shared)
    }
}
