import XCTest

final class BootstrapUITests: XCTestCase {
    func testLaunchShowsLocalizedBootstrapContent() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)["bootstrap.root"].waitForExistence(timeout: 5),
            "The bootstrap root should be available after launch."
        )
        XCTAssertTrue(
            app.staticTexts["Kurulum hazır"].waitForExistence(timeout: 5),
            "The localized bootstrap-ready text should be visible after launch."
        )

        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Bootstrap screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
