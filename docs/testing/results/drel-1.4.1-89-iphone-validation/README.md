# Drel 1.4.1 (89) Physical iPhone Validation

Date: 2026-10-17

Device: iPhone 13, iOS 18.7.3, TestFlight build `1.4.1 (89)`.

## Result

Passed:

- TestFlight installation and version confirmation.
- Physical-device launch and home rendering.
- Push-channel terminology (`推送通道`) and official/custom channel persistence.
- Favorites continuity after upgrade.
- Inbox and message-detail rendering.
- Strong-offline app metadata and app launch.
- Production APNs delivery, Inbox persistence, banner display, and notification tap routing.
- External `drel://app` deep-link parameter routing.

The owner also confirmed lock-screen presentation, `chime.caf` sound, and badge behavior.

## Evidence

The 16 JPEG files in this directory are the validation screenshots. Key files:

- `01-testflight-version-1.4.1-build-89.jpg`
- `02-home-launch-and-push-status.jpg`
- `04-push-channel-official-and-selfhosted.jpg`
- `05-favorites-upgrade-continuity.jpg`
- `07-offline-app-details.jpg`
- `08-offline-app-launch.jpg`
- `10-real-apns-message-persisted.jpg`
- `11-real-apns-message-detail.jpg`
- `13-real-apns-banner.jpg`
- `15-notification-tap-route.jpg`
- `16-notification-tap-opened-template.jpg`

## Boundary

This is physical-device acceptance evidence for build 89. It does not replace the full simulator UI regression, archive verification, or App Review submission checks.
