import XCTest

final class ComponentCatalogTests: XCTestCase {

    private static let sectionIDs = [
        "CatalogSection_Colors",
        "CatalogSection_Typography",
        "CatalogSection_Spacing",
        "CatalogSection_CornerRadius",
        "CatalogSection_Shadows",
        "CatalogSection_Buttons",
        "CatalogSection_Badges",
        "CatalogSection_Cards",
        "CatalogSection_EmptyStates",
        "CatalogSection_GradientViews",
        "CatalogSection_SectionHeaders",
        "CatalogSection_MessageCells",
        "CatalogSection_TokenCard",
        "CatalogSection_QuickActions",
        "CatalogSection_FilterPills",
        "CatalogSection_FAB",
        "CatalogSection_MenuItems"
    ]

    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = [
            "--ui-testing",
            "--show-component-catalog",
            "-UITesting"
        ]
        app.launch()
    }

    func testCatalogLoadsTitleAndAllSectionsInSingleScrollPass() throws {
        let scrollView = app.scrollViews["ComponentCatalogScrollView"]
        XCTAssertTrue(
            scrollView.waitForExistence(timeout: 30),
            "Component Catalog scroll view should appear"
        )

        let navigationBar = app.navigationBars["UI Component Catalog"]
        XCTAssertTrue(
            navigationBar.waitForExistence(timeout: 10),
            "Navigation title should be 'UI Component Catalog'"
        )

        // Lazy sections enter the accessibility tree only after materialization.
        // Keep one ordered list and scan downward once; do not relaunch or reset
        // scrolling for each section.
        var visibleSections = Set<String>()
        let expectedSections = Set(Self.sectionIDs)
        let maximumSwipes = 40

        func collectVisibleSections() {
            for identifier in Self.sectionIDs where scrollView.otherElements[identifier].exists {
                visibleSections.insert(identifier)
            }
        }

        collectVisibleSections()
        for _ in 0..<maximumSwipes where visibleSections != expectedSections {
            scrollView.swipeUp(velocity: .fast)
            collectVisibleSections()
        }

        let missingSections = expectedSections.subtracting(visibleSections).sorted()
        XCTAssertTrue(
            missingSections.isEmpty,
            "All catalog sections should render during one scroll pass; missing: \(missingSections)"
        )
    }
}
