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
  func testReaderActionsClose() {
    let panel = app.tables["native-reader-actions"]
    XCTAssertTrue(panel.waitForExistence(timeout: 8), app.debugDescription)
    XCTAssertFalse(app.buttons["native-actions-close"].exists)
    dismissNativePanel("native-reader-actions")
  }
  func testExportCopyRow() {
    let panel = app.tables["native-reader-actions"]
    XCTAssertTrue(panel.waitForExistence(timeout: 8), app.debugDescription)
    let row = app.cells["native-actions-export-copy"]
    for _ in 0..<4 where !row.isHittable { panel.swipeUp() }
    XCTAssertTrue(row.isHittable, app.debugDescription)
    capture("reader-actions-export-copy")
    row.tap()
    XCTAssertFalse(panel.waitForExistence(timeout: 1) && panel.isHittable)
  }
  func testReaderActionsDark() { testReaderActions() }
  func testReaderActions() {
    let panel = app.tables["native-reader-actions"]
    XCTAssertTrue(panel.waitForExistence(timeout: 8), app.debugDescription)
    capture("reader-actions-medium")
    let mediumTop = app.navigationBars.firstMatch.frame.minY
    let appearance = app.buttons["native-actions-appearance"]
    XCTAssertTrue(appearance.exists)
    appearance.tap()
    let dark = app.cells["native-actions-style-dark"]
    XCTAssertTrue(dark.waitForExistence(timeout: 5), app.debugDescription)
    dark.tap()
    expectation(for: NSPredicate { _, _ in dark.isSelected }, evaluatedWith: dark)
    waitForExpectations(timeout: 5)
    capture("reader-actions-appearance")
    app.buttons["native-actions-back"].tap()
    XCTAssertTrue(appearance.waitForExistence(timeout: 5))
    let margin = app.buttons["native-actions-margin"]
    if margin.isEnabled {
      let wasSelected = margin.isSelected
      margin.tap()
      expectation(for: NSPredicate { _, _ in margin.isSelected != wasSelected }, evaluatedWith: margin)
      waitForExpectations(timeout: 5)
      margin.tap()
      expectation(for: NSPredicate { _, _ in margin.isSelected == wasSelected }, evaluatedWith: margin)
      waitForExpectations(timeout: 5)
    }
    let vocab = app.buttons["native-actions-vocabulary-hints"]
    let wasSelected = vocab.isSelected
    vocab.tap()
    expectation(for: NSPredicate { _, _ in vocab.isSelected != wasSelected }, evaluatedWith: vocab)
    waitForExpectations(timeout: 5)
    vocab.tap()
    expectation(for: NSPredicate { _, _ in vocab.isSelected == wasSelected }, evaluatedWith: vocab)
    waitForExpectations(timeout: 5)
    // Drag the native header; actual UIKit detents must change height.
    let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: mediumTop / app.frame.height - 0.01))
    from.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)))
    XCTAssertLessThan(app.navigationBars.firstMatch.frame.minY, mediumTop - 100)
    capture("reader-actions-expanded")
    let outline = app.cells["native-actions-outline"]
    XCTAssertTrue(outline.isHittable)
    outline.tap()
    XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
    let section = readerTab("outline")
    XCTAssertTrue(section.waitForExistence(timeout: 8), app.debugDescription)
    capture("reader-actions-to-outline")
    dismissReaderList()
  }

  func testModalConfirm() {
    let cancel = app.buttons["取消"]
    XCTAssertTrue(cancel.waitForExistence(timeout: 8), app.debugDescription)
    capture("modal-system-confirmation")
    cancel.tap()
    XCTAssertTrue(cancel.waitForNonExistence(timeout: 5))
  }
  func testModalConfirmDark() { testModalConfirm() }
  func testModalRenameDark() { testModalRename() }
  func testModalRenameSave() {
    let field = app.textFields["native-field-title"]
    XCTAssertTrue(field.waitForExistence(timeout: 8), app.debugDescription)
    let save = app.buttons["native-form-submit"]
    XCTAssertTrue(save.isHittable)
    capture("modal-save-visible")
    field.tap()
    field.typeText(" QA")
    save.tap()
    XCTAssertTrue(field.waitForNonExistence(timeout: 5))
  }
  func testModalRename() {
    let field = app.textFields["native-field-title"]
    XCTAssertTrue(field.waitForExistence(timeout: 8), app.debugDescription)
    capture("modal-system-form-medium")
    field.tap()
    field.typeText(" QA")
    capture("modal-system-form-keyboard")
    app.navigationBars.buttons["取消"].tap()
    let discard = app.buttons["放弃更改"]
    XCTAssertTrue(discard.waitForExistence(timeout: 5), app.debugDescription)
    capture("modal-system-form-discard")
    app.buttons["继续编辑"].tap()
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    XCTAssertTrue((field.value as? String)?.contains("QA") == true)
    app.navigationBars.buttons["取消"].tap()
    XCTAssertTrue(discard.waitForExistence(timeout: 5))
    discard.tap()
    XCTAssertTrue(field.waitForNonExistence(timeout: 5))
  }

  func testSettingsDiscard() {
    let discard = app.buttons["不保存"]
    XCTAssertTrue(discard.waitForExistence(timeout: 8), app.debugDescription)
    capture("settings-native-confirmation")
    discard.tap()
    XCTAssertTrue(discard.waitForNonExistence(timeout: 5))
  }
  func testPortrait() {
    XCUIDevice.shared.orientation = .portrait
    expectation(for: NSPredicate { _, _ in self.app.frame.height > self.app.frame.width }, evaluatedWith: app)
    waitForExpectations(timeout: 8)
  }
  func testLandscape() {
    XCUIDevice.shared.orientation = .landscapeLeft
    expectation(for: NSPredicate { _, _ in self.app.frame.width > self.app.frame.height }, evaluatedWith: app)
    waitForExpectations(timeout: 8)
  }
  func testReaderNavigation() {
    let section = readerTab("outline")
    XCTAssertTrue(section.waitForExistence(timeout: 8), app.debugDescription)
    XCTAssertTrue(app.staticTexts["暂无目录"].exists, app.debugDescription)
    XCTAssertLessThan(section.frame.minY, app.frame.height * 0.2)
    capture("pdf-native-outline-expanded")
    let bookmarks = readerTab("bookmarks")
    XCTAssertTrue(bookmarks.waitForExistence(timeout: 5), app.debugDescription)
    bookmarks.tap()
    capture("pdf-native-bookmarks")
    let entry = app.staticTexts["记忆与主动提取"].firstMatch
    XCTAssertTrue(entry.waitForExistence(timeout: 5), app.debugDescription)
    entry.tap()
    XCTAssertTrue(section.waitForNonExistence(timeout: 5))
  }
  func testReflowNavigation() {
    let section = readerTab("outline")
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

  private func readerTab(_ id: String) -> XCUIElement {
    app.otherElements["native-reader-tabs"].firstMatch.buttons["native-reader-tab-" + id].firstMatch
  }
  private func dismissReaderList() { dismissNativePanel("native-reader-list") }
  private func dismissNativePanel(_ identifier: String) {
    let panel = app.tables[identifier]
    for _ in 0..<2 {
      if !panel.exists { break }
      let top = identifier == "native-reader-list"
        ? app.otherElements["native-reader-tabs"].firstMatch.frame.minY
        : app.navigationBars.firstMatch.frame.minY
      app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: max(0.03, top / app.frame.height - 0.01)))
        .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.97)))
    }
    XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
  }
  func testReaderHierarchyDark() { readerHierarchy("dark") }
  func testReaderHierarchyLight() { readerHierarchy("light") }
  private func readerHierarchy(_ theme: String) {
    let panel = app.tables["native-reader-list"]
    let outline = readerTab("outline")
    XCTAssertTrue(outline.waitForExistence(timeout: 8), app.debugDescription)
    XCTAssertLessThan(outline.frame.minY, app.frame.height * 0.2)
    XCTAssertFalse(app.navigationBars.firstMatch.exists)
    let manage = app.otherElements["native-reader-tabs"].firstMatch.buttons["native-reader-manage"].firstMatch
    XCTAssertEqual(outline.frame.midY, manage.frame.midY, accuracy: 1)
    XCTAssertFalse(app.navigationBars.buttons["关闭"].exists)
    let first = app.cells["native-reader-row-outline-0"]
    XCTAssertTrue(first.label.contains("Super-agent"))
    XCTAssertFalse(panel.cells.containing(NSPredicate(format: "label CONTAINS %@", "文档开头")).firstMatch.exists)
    for cell in panel.cells.allElementsBoundByIndex { XCTAssertFalse(cell.isSelected) }
    XCTAssertGreaterThanOrEqual(first.frame.height, 48)
    let longTitle = app.cells["native-reader-row-outline-1"]
    XCTAssertTrue(longTitle.label.contains("五个模块构成了支撑上述四个特征的双层架构。"))
    XCTAssertEqual(longTitle.frame.height, 48, accuracy: 1)
    let bookmarksTab = readerTab("bookmarks")
    let annotationsTab = readerTab("annotations")
    XCTAssertEqual(outline.frame.width, bookmarksTab.frame.width, accuracy: 1)
    XCTAssertEqual(outline.frame.width, annotationsTab.frame.width, accuracy: 1)
    capture(theme + "-01-native-outline")
    let bookmarks = readerTab("bookmarks")
    bookmarks.tap()
    XCTAssertTrue(bookmarks.isSelected)
    capture(theme + "-02-native-bookmarks")
    let annotations = readerTab("annotations")
    annotations.tap()
    XCTAssertTrue(annotations.isSelected)
    capture(theme + "-03-native-annotations")
    outline.tap()
    app.otherElements["native-reader-tabs"].firstMatch.buttons["native-reader-manage"].firstMatch.tap()
    XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
  }

  func testReaderManageDark() { testReaderManage() }
  func testReaderManage() {
    let section = readerTab("outline")
    XCTAssertTrue(section.waitForExistence(timeout: 8), app.debugDescription)
    app.otherElements["native-reader-tabs"].firstMatch.buttons["native-reader-manage"].firstMatch.tap()
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
