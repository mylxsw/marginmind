import XCTest

final class PhonePresentationTests: XCTestCase {
  let app = XCUIApplication(bundleIdentifier: "io.github.mylxsw.marginmind")
  override func setUpWithError() throws {
    continueAfterFailure = false
    app.launch()
  }
  func capture(_ name: String) {
    let image = XCTAttachment(screenshot: app.screenshot())
    image.name = name
    image.lifetime = .keepAlways
    add(image)
  }
  func testNativeNewStudySetForm() throws {
    capture("01-library-native-material")
    let new = app.buttons["New Study Set"].firstMatch
    XCTAssertTrue(new.waitForExistence(timeout: 10), app.debugDescription)
    new.tap()
    capture("02-new-source-actions")
    let blank = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Blank")).firstMatch
    XCTAssertTrue(blank.waitForExistence(timeout: 5), app.debugDescription)
    blank.tap()
    let field = app.textFields["native-field-title"]
    XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
    capture("03-native-form-medium")
    // Actual XCTest drag: this exercises UIKit's gesture recognizer.
    app.swipeUp()
    capture("04-native-form-expanded")
    field.tap()
    field.typeText("Phone QA")
    capture("05-native-keyboard-and-draft")
    app.navigationBars.buttons["Cancel"].tap()
    capture("06-native-unsaved-confirmation")
    let keep = app.buttons["Cancel"].firstMatch
    XCTAssertTrue(keep.waitForExistence(timeout: 5), app.debugDescription)
    keep.tap()
    XCTAssertEqual(field.value as? String, "Phone QA")
    app.buttons["native-form-submit"].tap()
    XCTAssertTrue(field.waitForNonExistence(timeout: 5))
    capture("07-created-workspace")
  }
}
