import XCTest
@testable import Drel

final class OfflinePackageUpdateLabelTests: XCTestCase {
    func testNotInstalledDownloads() {
        XCTAssertEqual(
            PWAAppCenterViewController.offlinePackageActionTitle(
                installedVersion: nil,
                targetVersion: "0.4.10.3"
            ),
            "下载离线包"
        )
    }

    func testSameVersionRedownloads() {
        XCTAssertEqual(
            PWAAppCenterViewController.offlinePackageActionTitle(
                installedVersion: "0.4.10.3",
                targetVersion: "0.4.10.3"
            ),
            "重新下载离线包"
        )
    }

    func testMissingVersionComponentsRedownload() {
        XCTAssertEqual(
            PWAAppCenterViewController.offlinePackageActionTitle(
                installedVersion: "",
                targetVersion: "0.4.10.3"
            ),
            "重新下载离线包"
        )
        XCTAssertEqual(
            PWAAppCenterViewController.offlinePackageActionTitle(
                installedVersion: "0.4.10.3",
                targetVersion: ""
            ),
            "重新下载离线包"
        )
    }

    func testStrictlyNewerVersionUpdates() {
        XCTAssertEqual(
            PWAAppCenterViewController.offlinePackageActionTitle(
                installedVersion: "0.4.10.2",
                targetVersion: "0.4.10.3"
            ),
            "更新离线包"
        )
    }

    func testNumericCompareNotStringCompare() {
        // 字符串比较会把 "10" 排在 "9" 前面，这里必须按数字比较。
        XCTAssertTrue(
            PWAAppCenterViewController.offlinePackageTargetIsNewer(
                installedVersion: "0.4.9.9",
                targetVersion: "0.4.9.10"
            )
        )
    }

    func testDowngradeDoesNotShowUpdate() {
        XCTAssertFalse(
            PWAAppCenterViewController.offlinePackageTargetIsNewer(
                installedVersion: "0.4.10.3",
                targetVersion: "0.4.10.2"
            )
        )
        XCTAssertEqual(
            PWAAppCenterViewController.offlinePackageActionTitle(
                installedVersion: "0.4.10.3",
                targetVersion: "0.4.10.2"
            ),
            "重新下载离线包"
        )
    }

    func testUncomparableVersionDoesNotShowUpdate() {
        for target in ["beta", "1.2.x", "1.2.3-rc1", "v0.4.10.3"] {
            XCTAssertFalse(
                PWAAppCenterViewController.offlinePackageTargetIsNewer(
                    installedVersion: "0.4.10.3",
                    targetVersion: target
                ),
                "target \(target) 不应判定为新版本"
            )
        }
    }

    func testWhitespaceIsIgnored() {
        XCTAssertTrue(
            PWAAppCenterViewController.offlinePackageTargetIsNewer(
                installedVersion: " 0.4.10.3 ",
                targetVersion: "\t0.4.10.4\n"
            )
        )
    }

    func testDifferentComponentCounts() {
        XCTAssertTrue(
            PWAAppCenterViewController.offlinePackageTargetIsNewer(
                installedVersion: "1.2",
                targetVersion: "1.2.1"
            )
        )
        XCTAssertFalse(
            PWAAppCenterViewController.offlinePackageTargetIsNewer(
                installedVersion: "1.2.1",
                targetVersion: "1.2"
            )
        )
        XCTAssertFalse(
            PWAAppCenterViewController.offlinePackageTargetIsNewer(
                installedVersion: "1.2",
                targetVersion: "1.2.0"
            )
        )
    }
}
