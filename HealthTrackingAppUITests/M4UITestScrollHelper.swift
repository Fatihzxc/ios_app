import XCTest

enum M4UITestScrollHelper {
    @discardableResult
    static func requireByScrolling(
        in app: XCUIApplication,
        query: () -> XCUIElement,
        missingMessage: String,
        notHittableMessage: String
    ) -> XCUIElement {
        let element = query()
        let upper = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.38))
        let lower = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.68))

        for searchesDown in [true, false] {
            for _ in 0..<40 {
                var shouldSearchDown = searchesDown
                if element.exists {
                    let frame = element.frame
                    let hasReliableFrame = !frame.isEmpty
                        && !frame.isNull
                        && !frame.isInfinite
                    let visible = hasReliableFrame
                        && frame.minY >= app.frame.minY + 44
                        && frame.maxY <= app.frame.maxY - 44
                    if element.isHittable, visible {
                        return require(element, message: missingMessage)
                    }
                    if hasReliableFrame {
                        shouldSearchDown = frame.midY >= app.frame.midY
                    }
                }
                (shouldSearchDown ? lower : upper).press(
                    forDuration: 0.05,
                    thenDragTo: shouldSearchDown ? upper : lower
                )
            }
        }

        _ = require(element, message: missingMessage)
        XCTAssertTrue(element.isHittable, notHittableMessage)
        return element
    }

    private static func require(
        _ element: XCUIElement,
        message: String
    ) -> XCUIElement {
        XCTAssertTrue(element.waitForExistence(timeout: 1), message)
        return element
    }
}
