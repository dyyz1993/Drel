import Foundation
import WebBridgeKit

extension MessageDetailViewController {
    func presentAppOpenFallback(
        failure: DrelAppOpenFailure,
        message: MessagePayload,
        appID: String,
        route: String?
    ) {
        DrelAppOpenFallback.presentBrowserFallback(
            DrelAppOpenFallback.decide(
                failure: failure,
                message: message,
                appID: appID,
                route: route
            ),
            from: self
        )
    }
}
