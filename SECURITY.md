# Security policy

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting for this repository
(Security → Report a vulnerability) instead of opening a public issue. Include
the affected file or endpoint and a way to reproduce it. You can expect an
acknowledgement within a few days.

## The community APNs key is public on purpose

`Server/community-apns/AuthKey_4M53447M36.p8` is an Apple Push Notification
service key that this project publishes deliberately, so that people without
an Apple developer account can run their own push relay for the stock Drel
app. Apple limits it to one topic (`com.webbridgekit.superapp`) and to the
production environment, and it can be revoked on its own. A report that only
points at this file is not a vulnerability.

Using the key for any other topic or for sandbox devices would be one, and so
would anything in [the key's description](Server/community-apns/README.md)
that turns out to be wrong.

## What is worth reporting

- Sending a push through the official channel (`api.drel.app`) without being a
  registered gateway, or naming an HTML app that the official gateway does not
  serve.
- Reading, altering, or replaying another device's notifications, history, or
  approvals.
- Opening an HTML app, a route, or a native action that the user did not
  authorize, or escaping the isolation between apps.
- Getting the iOS or macOS app to load an app package or manifest that is not
  correctly signed.
- Anything in the self-hosted server (`Server/`) that lets an unauthenticated
  caller register devices, publish apps, or read stored data.

Problems in an individual self-hosted deployment also need to be reported to
its operator: the project cannot see or fix other people's instances.
