import XCTest

/// Attaches to the running Flutter fixture. Never relaunches it: that would
/// discard the controller state whose UIKit integration we are verifying.
final class IntegrationNativePresentationTests: XCTestCase {
  let app = XCUIApplication(bundleIdentifier: "io.github.mylxsw.marginmind")
  override func setUpWithError() throws { continueAfterFailure = false; app.activate() }
  func capture(_ name: String) {
    // Flutter can request landscape independently of XCUIDevice orientation.
    // App-frame screenshots then crop to stale portrait bounds; capture the
    // screen so keyboard and sheet evidence always includes the whole display.
    let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = name
    shot.lifetime = .keepAlways; add(shot)
  }
  func testSettingsDiscard() {
    let discard = app.buttons["不保存"]
    XCTAssertTrue(discard.waitForExistence(timeout: 8), app.debugDescription)
    capture("settings-native-confirmation")
    discard.tap()
    XCTAssertTrue(discard.waitForNonExistence(timeout: 5))
  }
  func testReaderNavigation() {
    let section = app.buttons["native-reader-section"]
    XCTAssertTrue(section.waitForExistence(timeout: 8), app.debugDescription)
    XCTAssertTrue(app.staticTexts["暂无目录"].exists, app.debugDescription)
    capture("pdf-native-outline-medium")
    let mediumTop = app.navigationBars.firstMatch.frame.minY
    app.swipeUp()
    XCTAssertLessThan(app.navigationBars.firstMatch.frame.minY, mediumTop - 100)
    capture("pdf-native-outline-expanded")
    section.tap()
    let bookmarks = app.buttons["书签"]
    XCTAssertTrue(bookmarks.waitForExistence(timeout: 5), app.debugDescription)
    bookmarks.tap()
    capture("pdf-native-bookmarks")
    let entry = app.staticTexts["记忆与主动提取"].firstMatch
    XCTAssertTrue(entry.waitForExistence(timeout: 5), app.debugDescription)
    entry.tap()
    XCTAssertTrue(section.waitForNonExistence(timeout: 5))
  }
  func testReflowNavigation() {
    let section = app.buttons["native-reader-section"]
    XCTAssertTrue(section.waitForExistence(timeout: 8), app.debugDescription)
    capture("reflow-native-outline")
    let entry = app.staticTexts["间隔复习"].firstMatch
    XCTAssertTrue(entry.waitForExistence(timeout: 5), app.debugDescription)
    entry.tap()
    XCTAssertTrue(section.waitForNonExistence(timeout: 5))
  }
  func testWebForm() {
    let field = app.textFields["native-field-url"]
    XCTAssertTrue(field.waitForExistence(timeout: 8), app.debugDescription)
    field.tap()
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
    field.typeText("javascript:alert(1)")
    capture("web-native-input")
    app.buttons["native-form-submit"].tap()
    XCTAssertTrue(field.exists)
    XCTAssertEqual(field.value as? String, "javascript:alert(1)")
    capture("web-native-validation")
    app.navigationBars.buttons["取消"].tap()
    capture("web-native-unsaved")
    let discard = app.buttons["放弃更改"]
    XCTAssertTrue(discard.waitForExistence(timeout: 5), app.debugDescription)
    discard.tap()
    XCTAssertTrue(field.waitForNonExistence(timeout: 5))
  }
  func testPdfCanvas() {
    let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
    let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
    from.press(forDuration: 0.05, thenDragTo: to)
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    capture("pdf-system-touch-scroll")
  }
  func testLandscapeWebForm() {
    let field = app.textFields["native-field-url"]
    XCTAssertTrue(field.waitForExistence(timeout: 8), app.debugDescription)
    capture("landscape-native-form")
    field.tap()
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
    field.typeText("https://example.com")
    capture("landscape-native-keyboard")
    app.navigationBars.buttons["取消"].tap()
    let discard = app.buttons["放弃更改"]
    XCTAssertTrue(discard.waitForExistence(timeout: 5), app.debugDescription)
    capture("landscape-native-discard")
    discard.tap()
    XCTAssertTrue(field.waitForNonExistence(timeout: 5))
  }

  func testColorPicker() {
    let picker = app.otherElements["native-color-picker"]
    XCTAssertTrue(picker.waitForExistence(timeout: 8), app.debugDescription)
    capture("system-color-picker")
    let sliders = app.buttons["Sliders"].firstMatch
    XCTAssertTrue(sliders.waitForExistence(timeout: 5), app.debugDescription)
    sliders.tap()
    let component = app.sliders.firstMatch
    XCTAssertTrue(component.waitForExistence(timeout: 5), app.debugDescription)
    component.adjust(toNormalizedSliderPosition: 0.35)
    capture("system-color-selected")
    let close = app.buttons.matching(NSPredicate(format: "label ==[c] %@", "close")).firstMatch
    XCTAssertTrue(close.waitForExistence(timeout: 5), app.debugDescription)
    close.tap()
    XCTAssertTrue(picker.waitForNonExistence(timeout: 5))
  }

  func testReaderManage() {
    let section = app.buttons["native-reader-section"]
    XCTAssertTrue(section.waitForExistence(timeout: 8), app.debugDescription)
    app.buttons["管理"].tap()
    XCTAssertTrue(section.waitForNonExistence(timeout: 5))
    capture("reader-management-opened")
  }
  func testBookmarkEditor() {
    let title = app.textFields["native-field-title"]
    XCTAssertTrue(title.waitForExistence(timeout: 8), app.debugDescription)
    title.tap()
    title.typeText("Native Bookmark QA")
    let page = app.textFields["native-field-page"]
    page.tap()
    page.buttons.firstMatch.tap()
    page.typeText("2")
    capture("native-bookmark-editor")
    app.buttons["native-form-submit"].tap()
    XCTAssertTrue(title.waitForNonExistence(timeout: 5))
  }

}
