import UIKit
import WebBridgeKit

final class AppRegistrationViewController: UIViewController {
    private let onAppActivated: (String) -> Void

    private lazy var addressField: UITextField = {
        let field = UITextField()
        field.placeholder = L10n.tr("app.registration.placeholder")
        field.borderStyle = .roundedRect
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.keyboardType = .URL
        field.clearButtonMode = .whileEditing
        field.accessibilityIdentifier = "appRegistration.addressField"
        return field
    }()

    private lazy var addButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.title = L10n.tr("app.registration.add")
        configuration.cornerStyle = .medium
        configuration.baseBackgroundColor = ThemeTokens.Color.primary
        configuration.baseForegroundColor = ThemeTokens.Color.onPrimary
        let button = UIButton(configuration: configuration)
        button.addTarget(self, action: #selector(addTapped), for: .touchUpInside)
        button.accessibilityIdentifier = "appRegistration.add"
        return button
    }()

    init(onAppActivated: @escaping (String) -> Void) {
        self.onAppActivated = onAppActivated
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("AppRegistrationViewController is created programmatically")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.tr("app.registration.title")
        view.backgroundColor = ThemeTokens.Color.background
        addressField.delegate = self
        installForm()
    }

    private func installForm() {
        let stack = UIStackView(arrangedSubviews: [addressField, addButton])
        stack.axis = .vertical
        stack.spacing = ThemeTokens.Spacing.lg
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: ThemeTokens.Spacing.xl),
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            addButton.heightAnchor.constraint(equalToConstant: ThemeTokens.ComponentContract.Button.height)
        ])
    }

    @objc private func addTapped() {
        let input = addressField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let url = validatedURL(from: input) {
            DrelAppOpenFallback.presentBrowserFallback(
                .openInBrowser(url, appName: url.host ?? url.absoluteString),
                from: self
            )
            return
        }

        guard let appID = validatedAppID(from: input) else {
            showInvalidInput()
            return
        }

        DrelPushAppCatalogCoordinator.shared.activateIfTrusted(appID: appID, route: "/") { [weak self] accepted in
            guard let self else { return }
            if accepted {
                self.onAppActivated(appID)
                return
            }

            self.showWebFallback(for: appID)
        }
    }

    private func validatedURL(from input: String) -> URL? {
        guard input.count <= 2_048 else { return nil }
        return DrelAppOpenFallback.trustedHTTPSURLForRegistration(from: input)
    }

    private func validatedAppID(from input: String) -> String? {
        guard input.count <= 253 else { return nil }
        let pattern = "^app\\.[A-Za-z0-9-]+(?:\\.[A-Za-z0-9-]+)+$"
        guard input.range(of: pattern, options: .regularExpression) != nil else { return nil }
        let appID = input.lowercased()
        // The same boundary the push fallback applies: reserved Drel IDs and
        // private/loopback hosts never become a launch target.
        guard DrelAppOpenFallback.deriveStartURL(fromAppID: appID) != nil else { return nil }
        return appID
    }

    private func showWebFallback(for appID: String) {
        let host = appID.hasPrefix("app.") ? String(appID.dropFirst("app.".count)) : appID
        guard let url = URL(string: "https://\(host)/") else {
            showInvalidInput()
            return
        }

        let alert = UIAlertController(
            title: L10n.tr("common.notice"),
            message: L10n.tr("app.registration.app_not_found"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.tr("common.open"), style: .default) { _ in
            WebBrowserManager.shared.openBrowser(
                url: url,
                params: DrelMessageOpenPolicy.browserParams(for: url, mode: .normal, payload: [:]),
                from: self
            )
        })
        alert.addAction(UIAlertAction(title: L10n.tr("common.cancel"), style: .cancel))
        present(alert, animated: true)
    }

    private func showInvalidInput() {
        let alert = UIAlertController(
            title: L10n.tr("common.notice"),
            message: L10n.tr("app.registration.invalid_input"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.tr("common.ok"), style: .default))
        present(alert, animated: true)
    }
}

extension AppRegistrationViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        addTapped()
        return true
    }
}
