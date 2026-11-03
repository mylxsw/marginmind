import XCTest

/// Run on a dedicated simulator with Safari opened at https://example.com.
final class IncomingSharePresentationTests: XCTestCase {
  private let app = XCUIApplication(bundleIdentifier: "io.github.mylxsw.marginmind")
  private let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")

  private func capture(_ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  private func stageSafariShare() {
    safari.activate()
    // Safari's compact toolbar puts Share inside More and shows a first-run tip.
    let tip = safari.buttons["Close"].firstMatch
    if tip.waitForExistence(timeout: 2) { tip.tap() }
    let target = safari.cells["Foliarc"].firstMatch
    if !target.exists {
      let share = safari.buttons["Share"].firstMatch
      if !share.exists {
        let more = safari.buttons["MoreMenuButton"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 10), safari.debugDescription)
        more.tap()
      }
      XCTAssertTrue(share.waitForExistence(timeout: 20), safari.debugDescription)
      share.tap()
    }
    XCTAssertTrue(target.waitForExistence(timeout: 10), safari.debugDescription)
    capture("safari-share-target")
    target.tap()
    let saved = safari.staticTexts["Saved. Open Foliarc to choose an existing study set or create a new one."]
    XCTAssertTrue(saved.waitForExistence(timeout: 20), safari.debugDescription)
    capture("share-extension-saved")
    safari.buttons["Done"].firstMatch.tap()
  }

  func testSafariShareImportsIntoNewAndExistingStudySet() {
    continueAfterFailure = false
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    app.terminate()
    stageSafariShare()
    app.launch()
    XCTAssertTrue(app.staticTexts["Import to Foliarc"].waitForExistence(timeout: 15), app.debugDescription)
    capture("incoming-target-picker")
    let create = app.buttons["Create and Import"].firstMatch
    if !create.exists { app.buttons["New Study Set"].firstMatch.tap() }
    XCTAssertTrue(create.waitForExistence(timeout: 5), app.debugDescription)
    create.tap()
    XCTAssertTrue(create.waitForNonExistence(timeout: 10), app.debugDescription)
    let opened = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      self.app.staticTexts["Example Domain"].exists ||
        self.app.textFields.matching(NSPredicate(format: "value CONTAINS[cd] %@", "example.com")).firstMatch.exists
    }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [opened], timeout: 15), .completed, app.debugDescription)
    capture("shared-page-in-workspace")

    // A second share returns to the existing process and defaults to its recent set.
    stageSafariShare()
    app.activate()
    XCTAssertTrue(app.staticTexts["Import to Foliarc"].waitForExistence(timeout: 15), app.debugDescription)
    capture("incoming-existing-target")
    let add = app.buttons["Import"].firstMatch
    XCTAssertTrue(add.waitForExistence(timeout: 5), app.debugDescription)
    add.tap()
    XCTAssertTrue(add.waitForNonExistence(timeout: 10), app.debugDescription)
    XCTAssertTrue(app.textFields.matching(NSPredicate(format: "value CONTAINS[cd] %@", "example.com")).firstMatch
      .waitForExistence(timeout: 15), app.debugDescription)
    capture("shared-page-in-existing-workspace")
  }
}
