import Foundation

/// Central definition of every fixture path the app can point at.
///
/// Fixture URLs used to be inline strings spread over the seeder, the debug
/// panels and the showcase screens. Several of them pointed at
/// `ae8fcb.../test_resources/bridge-*.html`, a path that stopped serving
/// those files months ago, so the seeded entries rendered as broken cards.
///
/// The layout follows the convention the website already uses: a fixture
/// lives under `test/<name>/`, its generation under `test/<name>/<generation>/`,
/// and the source of truth lives in `test_resources/<name>/<generation>/`.
/// A path therefore states which fixture and which generation it belongs to
/// without having to open the file.
enum FixturePaths {

    // MARK: - Published website fixtures

    /// The Drel website. Historical fixtures are published here so a link
    /// keeps working for years instead of pointing at a build machine.
    static let websiteBaseURL = "https://drel.app"

    /// Base path of the published fixtures.
    static let publishedBasePath = "/test"

    /// The Bridge test pages that shipped with Drel 1.0. They exercise the
    /// full v1 action set, not the seven actions the 1.5 store build allows.
    static let bridgeGeneration = "v1"

    /// Published path of the Drel 1.0 Bridge fixtures.
    static var publishedBridgePath: String {
        "\(publishedBasePath)/bridge/\(bridgeGeneration)"
    }

    /// URL of one published Bridge fixture page.
    static func publishedBridgePage(_ name: String) -> String {
        "\(websiteBaseURL)\(publishedBridgePath)/\(name).html"
    }

    /// URL of the published Bridge fixture index.
    static var publishedBridgeIndexURL: String {
        "\(websiteBaseURL)\(publishedBridgePath)/"
    }

    /// The live demos published under `/test/`.
    ///
    /// Each name states the fixture, and the index sits one level above the
    /// generation directory, so a link always says which fixture it opens.
    enum Published: String, CaseIterable {
        case actions
        case offline
        case offlineNetwork = "offline-network"
        case template
        case bridge

        /// URL of this fixture's landing page.
        var url: String {
            "\(FixturePaths.websiteBaseURL)\(FixturePaths.publishedBasePath)/\(rawValue)/"
        }

        /// URL of this fixture's page for the given generation.
        func url(generation: String) -> String {
            "\(url)\(generation)/"
        }
    }

    // MARK: - Local fixtures

    /// The static file server that serves the repository root during local
    /// development and UI testing (`scripts/services.sh`).
    static let localFixtureOrigin = "http://localhost:8081"

    /// Path prefix of the fixtures served from the repository root.
    static let localBasePath = "/test_resources"

    /// Path of a fixture served by the local static server.
    ///
    /// The source of truth is `test_resources/<name>/<generation>/` in the
    /// repository, which is what the local server exposes.
    static func local(_ name: String, generation: String? = nil) -> String {
        var path = "\(localBasePath)/\(name)"
        if let generation {
            path += "/\(generation)"
        }
        return path
    }

    /// Full URL of a fixture served by the local static server.
    static func localURL(_ name: String, generation: String? = nil) -> String {
        "\(localFixtureOrigin)\(local(name, generation: generation))"
    }

    // MARK: - Named fixtures

    /// The Bridge pages that shipped with Drel 1.0.
    enum Bridge: String, CaseIterable {
        case permission = "bridge-permission"
        case device = "bridge-device"
        case media = "bridge-media"
        case interaction = "bridge-interaction"
        case navigation = "bridge-navigation"
        case cache = "bridge-cache"

        /// Published URL of this fixture.
        var publishedURL: String {
            FixturePaths.publishedBridgePage(rawValue)
        }
    }

    /// Fixtures the UI test harness registers against the local server.
    ///
    /// These are development apparatus, not public examples: the app
    /// unregisters them on a normal launch, so they only matter while a UI
    /// test is running.
    enum Local: String, CaseIterable {
        case pwaPermission = "pwa-permission"
        case pwaNotification = "pwa-notification"
        case pwaAgentConsole = "pwa-agent-console"

        /// Path of this fixture on the local static server.
        var path: String {
            FixturePaths.local(rawValue)
        }

        /// Entry page of this fixture.
        var indexPath: String {
            "\(path)/index.html"
        }

        /// Approval page of this fixture.
        var approvalPath: String {
            "\(path)/approval.html"
        }

        /// Full URL of this fixture's entry page.
        var indexURL: String {
            "\(FixturePaths.localFixtureOrigin)\(indexPath)"
        }
    }

    /// The v2-action variant of the permission fixture, registered by the UI
    /// test harness with `--pwa-v2-actions`.
    static let localPermissionV2Actions = "\(localBasePath)/pwa-permission/v2-actions.html"

    /// Local fixtures that still exist on disk. The `cache-demo.html`,
    /// `cache-showcase.html`, `images/` and `cases/` paths some panels used
    /// to point at were never in the repository, so those defaults resolved
    /// to a 404.
    static let localCacheValidation = "\(localBasePath)/cache-html-validation/index.html"
    static let localPushRenderCatalog = "\(localBasePath)/push-render-catalog.html"
}
