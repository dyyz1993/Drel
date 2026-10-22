# Drel 1.4.1 App Review Notes

Status: the 1.4.1 record inherits the 1.4.0 review narrative. The 1.4.0
version is already `READY_FOR_SALE`; only the patch notes change.

## Summary

Drel is a developer push-notification utility and a container for HTML apps
that the user has explicitly trusted. Version 1.4.1 is a patch release of the
1.4 line. It adds no new native capability, no new permission surface and no
new data collection.

## What changed relative to 1.4.0

- Display and routing fixes in Favorites, the Inbox and notification deep
  links.
- No change to the trust model: remote pages still receive no
  JavaScript-to-native Bridge, and the signed-manifest rules are unchanged.

## Reviewer walkthrough

No account, login, purchase, subscription, or credentials are required.

1. Launch Drel and allow notifications if you want to test push delivery.
2. Use the built-in test-send controls to deliver a harmless test message.
3. Open Settings and confirm the push channel wording and the Favorites list
   render correctly.
4. Open a saved trusted app from the app list and confirm it still launches.

## Permissions and privacy

1.4.1 introduces no new permission prompt and no new privacy usage
description. The privacy policy and terms are unchanged.

## Service and contact facts

- Official service: `https://api.drel.app`
- Support: `https://drel.app/support/`
- Privacy Policy: `https://drel.app/privacy/`
- Terms of Use: `https://drel.app/terms/`
- No login, account, purchase, subscription, advertising, or analytics is
  required for review.
