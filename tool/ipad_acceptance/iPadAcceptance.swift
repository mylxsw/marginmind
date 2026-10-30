import XCTest
@MainActor final class iPadAcceptance: XCTestCase {
 let app = XCUIApplication(bundleIdentifier: "io.github.mylxsw.marginmind")
 func button(_ prefix: String) -> XCUIElement { app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", prefix)).firstMatch }
 func shot(_ name: String) {
  let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
  print("IPAD_SHOT:" + name)
  Thread.sleep(forTimeInterval: 2)
 }
 func orient(_ value: UIDeviceOrientation) {
  XCUIDevice.shared.orientation = value
  let landscape = value == .landscapeLeft || value == .landscapeRight
  let predicate = NSPredicate { _, _ in landscape ? self.app.frame.width > self.app.frame.height : self.app.frame.height > self.app.frame.width }
  XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: app)], timeout: 15), .completed)
 }
 func start() {
  continueAfterFailure = false
  app.launch()
  XCTAssertTrue(button("Show Sidebar").waitForExistence(timeout: 20))
 }
 func openSample() {
  let sample = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Sample:")).firstMatch
  if sample.waitForExistence(timeout: 3) { sample.tap() } else { button("Open Sample Study Set").tap() }
  XCTAssertTrue(button("Map Only").waitForExistence(timeout: 15))
 }
 func companion(_ name: String) {
  button("Assistant").tap()
  let close = app.buttons["Close"]
  XCTAssertTrue(close.waitForExistence(timeout: 8))
  XCTAssertGreaterThanOrEqual(close.frame.height, 44)
  let content = app.otherElements["tablet-workspace-content"]
  let panel = app.otherElements["tablet-workspace-panel"]
  XCTAssertTrue(panel.exists)
  XCTAssertFalse(content.frame.intersects(panel.frame))
  let start = content.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.6))
  start.press(forDuration: 0.05, thenDragTo: content.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.35)))
  XCTAssertTrue(close.exists)
  shot(name)
  if app.frame.height > app.frame.width {
   let grip = app.descendants(matching: .any).matching(identifier: "tablet-panel-resize").firstMatch
   XCTAssertTrue(grip.waitForExistence(timeout: 5))
   XCTAssertEqual(grip.frame.width, 44, accuracy: 1); XCTAssertEqual(grip.frame.height, 44, accuracy: 1)
   let before = panel.frame.height
   grip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.1, thenDragTo: grip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: -0.7)))
   XCTAssertGreaterThan(panel.frame.height, before + 20)
   shot("12-companion-resized")
  }
  close.tap()
  XCTAssertFalse(panel.exists)
 }
 func testWorkspace() throws {
  start(); orient(.landscapeLeft); shot("01-library-landscape")
  openSample(); button("Source Only").tap()
  for label in ["Source Only", "Split", "Map Only", "Assistant", "Select", "Area Select", "Pen", "More"] {
   XCTAssertGreaterThanOrEqual(button(label).frame.height, 44)
   XCTAssertGreaterThanOrEqual(button(label).frame.width, 44)
  }
  shot("02-reader-landscape")
  button("More").tap()
  XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", "Margin Notes")).firstMatch.waitForExistence(timeout: 5))
  shot("02c-reader-more")
  app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.6)).tap()
  button("Select").tap()
  let reading = app.otherElements["tablet-workspace-content"]
  let line = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "人在学习新知识之后")).firstMatch
  XCTAssertTrue(line.waitForExistence(timeout: 6))
  line.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).press(forDuration: 1.0, thenDragTo: line.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5)))
  XCTAssertTrue(button("Copy").waitForExistence(timeout: 6))
  XCTAssertGreaterThanOrEqual(button("Copy").frame.height, 44)
  let handle = app.otherElements["pdf-selection-end"]
  XCTAssertTrue(handle.waitForExistence(timeout: 5))
  XCTAssertEqual(handle.frame.width, 44, accuracy: 1)
  XCTAssertEqual(handle.frame.height, 44, accuracy: 1)
  let endBeforeDrag = handle.frame.midX
  handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.1, thenDragTo: handle.coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.5)))
  XCTAssertTrue(button("Copy").waitForExistence(timeout: 5))
  XCTAssertLessThan(handle.frame.midX, endBeforeDrag - 1)
  shot("02b-selection-landscape")
  reading.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.6)).tap()
  companion("03-assistant-landscape")
  button("Map Only").tap()
  let zoom = app.buttons["Actual Size"]
  XCTAssertTrue(zoom.waitForExistence(timeout: 5)); zoom.tap()
  shot("04-map-before-style")
  button("Style").tap(); shot("05-map-style")
  button("Style").tap(); shot("05b-map-style-closed")
 }
 func testRotationCompanion() throws {
  start(); orient(.landscapeLeft); openSample(); button("Source Only").tap()
  orient(.portrait); button("Source Only").tap()
  companion("13-assistant-after-rotation")
 }
 func testPortraitCompanion() throws {
  start(); orient(.portrait); openSample(); button("Source Only").tap(); shot("06-reader-portrait")
  companion("07-assistant-portrait")
  button("Split").tap(); shot("08-split-portrait")
 }
 func testSettingsKeyboard() throws {
  start(); orient(.landscapeLeft)
  button("Show Sidebar").tap()
  let settings = button("Settings")
  XCTAssertTrue(settings.waitForExistence(timeout: 5)); settings.tap()
  XCTAssertTrue(app.buttons["Models"].waitForExistence(timeout: 5)); app.buttons["Models"].tap()
  let service = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "claude")).firstMatch
  XCTAssertTrue(service.waitForExistence(timeout: 5)); service.tap()
  let field = app.textFields["API Key"]
  XCTAssertTrue(field.waitForExistence(timeout: 5)); XCTAssertGreaterThanOrEqual(field.frame.height, 44); field.tap()
  XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 8))
  shot("09-settings-keyboard-landscape")
  let close = button("Close")
  XCTAssertGreaterThanOrEqual(close.frame.height, 44)
  XCTAssertLessThan(close.frame.maxY, app.keyboards.firstMatch.frame.minY)
  close.tap()
  orient(.portrait); if !settings.isHittable { button("Show Sidebar").tap() }; settings.tap(); app.buttons["Models"].tap(); service.tap(); field.tap()
  XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 8)); shot("10-settings-keyboard-portrait")
  XCTAssertLessThan(close.frame.maxY, app.keyboards.firstMatch.frame.minY)
  close.tap()
  orient(.landscapeLeft)
 }
 func setAppearance(_ choice: String?) -> String {
  start(); orient(.landscapeLeft)
  button("Show Sidebar").tap(); button("Settings").tap(); app.buttons["General"].tap()
  let appearance = app.buttons["Appearance"]
  XCTAssertTrue(appearance.waitForExistence(timeout: 5))
  let old = appearance.value as? String ?? "System"
  if let choice, choice != old {
   appearance.tap(); app.buttons[choice].tap()
  }
  button("Close").tap()
  if button("Hide Sidebar").exists && button("Hide Sidebar").isHittable { button("Hide Sidebar").tap() }
  return old
 }
 func testZVisualThemes() throws {
  let original = setAppearance(nil)
  for mode in ["Light", "Dark"] {
   _ = setAppearance(mode)
   openSample(); button("Source Only").tap(); shot("20-reader-" + mode.lowercased())
   button("Map Only").tap(); app.buttons["Actual Size"].tap()
   let root = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Sample: Forgetting")).firstMatch
   XCTAssertTrue(root.waitForExistence(timeout: 5)); root.tap()
   XCTAssertTrue(button("Add Child Topic").waitForExistence(timeout: 5))
   XCTAssertGreaterThanOrEqual(button("Add Child Topic").frame.height, 44)
   shot("21-node-toolbar-" + mode.lowercased())
   button("Style").tap(); shot("22-map-style-" + mode.lowercased()); button("Style").tap()
   orient(.portrait); button("Split").tap(); shot("23-split-" + mode.lowercased())
  }
  _ = setAppearance(original)
 }

}
