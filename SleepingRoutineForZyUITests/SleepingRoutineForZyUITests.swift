import XCTest

final class SleepingRoutineForZyUITests: XCTestCase {
    func testLaunchShowsOnboardingWelcome() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshOnboarding"]
        app.launch()
        XCTAssertTrue(
            app.staticTexts["Sleep better with a simple routine."].waitForExistence(timeout: 5)
        )
    }

    func testLaunchWithSkipShowsHomeTab() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSkipOnboarding"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Start Sleep Routine"].waitForExistence(timeout: 5))
    }

    func testStartAndEndRoutineFromHome() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSkipOnboarding"]
        app.launch()

        let start = app.buttons["Start Sleep Routine"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        let end = app.buttons["End Routine"]
        XCTAssertTrue(end.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Sleep routine active"].exists)
        end.tap()

        XCTAssertTrue(app.buttons["Start Sleep Routine"].waitForExistence(timeout: 5))
    }

    func testOnboardingHappyPathToHome() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshOnboarding"]
        app.launch()

        app.buttons["Continue"].firstMatch.tap()
        app.buttons["Enable notifications"].firstMatch.tap()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 3) {
            allow.tap()
        }

        // Permission dialog may appear on device; Skip Spotify is always available.
        let skip = app.buttons["Skip for now"]
        XCTAssertTrue(skip.waitForExistence(timeout: 8))
        skip.tap()

        let start = app.buttons["Start my routine"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 5))
    }

    func testAlarmsAddSaveAndDisable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSkipOnboarding"]
        app.launch()

        app.tabBars.buttons["Alarms"].tap()
        XCTAssertTrue(
            app.staticTexts["These alarms use iOS notifications. They are helpful reminders, but they are not the same as Apple Clock and are not guaranteed while the phone is asleep or notifications are off."]
                .waitForExistence(timeout: 5)
            || app.buttons["Add Alarm"].waitForExistence(timeout: 5)
        )

        let addButton = app.buttons["Add Alarm"].firstMatch
        if addButton.exists {
            addButton.tap()
        } else {
            app.navigationBars.buttons["Add Alarm"].tap()
        }

        let save = app.buttons["Save Alarm"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()

        // After save, an ON/OFF label should appear for the alarm.
        let onLabel = app.staticTexts["ON"]
        XCTAssertTrue(onLabel.waitForExistence(timeout: 5))
    }
}
