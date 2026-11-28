# Third-Party Notices

Drel is released under the MIT License (see `LICENSE`). It depends on the
third-party components listed below. License identifiers were verified
against each component's own license file; the full license texts ship
inside the corresponding pod when you run `pod install`.

## CocoaPods dependencies (as locked in `Podfile.lock`)

| Component | Version | License |
|---|---|---|
| Alamofire | 5.12.0 | MIT |
| Differentiator | 5.0.0 | MIT |
| Kingfisher | 7.12.0 | MIT |
| Moya | 15.0.0 | MIT |
| Realm | 10.54.6 | Apache License 2.0 |
| RealmSwift | 10.54.6 | Apache License 2.0 |
| RxCocoa | 6.9.0 | MIT |
| RxDataSources | 5.0.0 | MIT |
| RxRelay | 6.9.0 | MIT |
| RxSwift | 6.9.0 | MIT |
| SnapKit | 5.7.1 | MIT |
| SwiftSoup | 2.11.3 | MIT |
| ZIPFoundation | 0.9.20 | MIT |
| WebBridgeKit | 1.4.1 | MIT (first-party, https://github.com/dyyz1993/WebBridgeKit-Framework) |

## Server (SwiftPM, as locked in `Server/Package.resolved`)

License identifiers were verified from each pinned repository's GitHub license
metadata; the corresponding full license text is available at each upstream tag.

| Package | Version | License |
|---|---|---|
| async-http-client | 1.33.1 | Apache-2.0 |
| hummingbird | 2.22.0 | Apache-2.0 |
| swift-algorithms | 1.2.1 | Apache-2.0 |
| swift-asn1 | 1.7.0 | Apache-2.0 |
| swift-async-algorithms | 1.1.3 | Apache-2.0 |
| swift-atomics | 1.3.0 | Apache-2.0 |
| swift-certificates | 1.19.1 | Apache-2.0 |
| swift-collections | 1.4.1 | Apache-2.0 |
| swift-configuration | 1.2.0 | Apache-2.0 |
| swift-crypto | 3.15.1 | Apache-2.0 |
| swift-distributed-tracing | 1.4.1 | Apache-2.0 |
| swift-http-structured-headers | 1.7.0 | Apache-2.0 |
| swift-http-types | 1.5.1 | Apache-2.0 |
| swift-log | 1.12.0 | Apache-2.0 |
| swift-metrics | 2.10.1 | Apache-2.0 |
| swift-nio | 2.99.0 | Apache-2.0 |
| swift-nio-extras | 1.34.0 | Apache-2.0 |
| swift-nio-http2 | 1.43.0 | Apache-2.0 |
| swift-nio-ssl | 2.37.0 | Apache-2.0 |
| swift-nio-transport-services | 1.28.0 | Apache-2.0 |
| swift-numerics | 1.1.1 | Apache-2.0 |
| swift-service-context | 1.3.0 | Apache-2.0 |
| swift-service-lifecycle | 2.11.0 | Apache-2.0 |
| swift-system | 1.6.4 | Apache-2.0 |

## Vendored source

| Component | Location | License |
|---|---|---|
| qrcode-generator 1.4.4 © Kazuhiko Arase | `Server/native/qr.min.js` | MIT |

## Design assets

- Lucide icons (https://lucide.dev, ISC License) are compiled into the
  asset catalogs.
