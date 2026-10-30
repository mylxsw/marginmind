import XCTest
@MainActor final class iPadAcceptance: XCTestCase {
 let app = XCUIApplication(bundleIdentifier: "io.github.mylxsw.marginmind")
 let labels: [String: String] = ["Show Sidebar":"显示侧栏", "Hide Sidebar":"隐藏侧栏", "Source Only":"只看原文", "Split":"分栏", "Map Only":"只看脑图", "Assistant":"助手", "Close":"关闭", "Main Map":"主脑图", "Select":"选择", "Area Select":"框选", "Pen":"画笔", "More":"更多", "Copy":"拷贝", "Style":"样式", "Actual Size":"实际大小", "Settings":"设置", "General":"通用", "Models":"模型", "Default Model":"默认模型", "Appearance":"外观", "Language":"语言", "System":"跟随系统", "Light":"浅色", "Dark":"深色", "Icons":"图标", "List":"列表", "Add Child Topic":"添加子主题", "Margin Notes":"页边批注"]
 func button(_ prefix: String) -> XCUIElement { app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@ OR label BEGINSWITH[c] %@", prefix, labels[prefix] ?? prefix)).firstMatch }
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
  let close = button("Close")
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
  XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "Margin Notes", "页边批注")).firstMatch.waitForExistence(timeout: 5))
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
  let begin = app.otherElements["pdf-selection-start"]
  XCTAssertTrue(begin.exists)
  XCTAssertLessThan(abs(handle.frame.midX - begin.frame.midX), line.frame.width * 0.3)
  let endBeforeDrag = handle.frame.midX
  handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.1, thenDragTo: handle.coordinate(withNormalizedOffset: CGVector(dx: 1.7, dy: 0.5)))
  XCTAssertTrue(button("Copy").waitForExistence(timeout: 5))
  XCTAssertGreaterThan(handle.frame.midX, endBeforeDrag + 10)
  shot("02b-selection-landscape")
  reading.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.6)).tap()
  companion("03-assistant-landscape")
  button("Map Only").tap()
  let zoom = button("Actual Size")
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
 func testTabletLibraryAndSidebar() throws {
  start(); orient(.landscapeLeft)
  let wasList = button("List").isSelected
  button("Icons").tap()
  let sample = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Sample:")).allElementsBoundByIndex.filter { $0.isHittable && $0.frame.width < 300 && $0.frame.width > 100 }.first
  XCTAssertNotNil(sample); sample!.tap()
  XCTAssertTrue(button("Map Only").waitForExistence(timeout: 10))
  button("Show Sidebar").tap()
  XCTAssertTrue(button("Main Map").waitForExistence(timeout: 5))
  XCTAssertTrue(button("Main Map").isSelected)
  XCTAssertTrue(button("Sample chapter:").isSelected)
  shot("30-workspace-sidebar")
  start(); button("List").tap()
  let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Sample:")).allElementsBoundByIndex.filter { $0.isHittable && $0.frame.width > 500 }.first
  XCTAssertNotNil(row); XCTAssertGreaterThanOrEqual(row!.frame.height, 44); row!.tap()
  XCTAssertTrue(button("Map Only").waitForExistence(timeout: 10))
  start(); button(wasList ? "List" : "Icons").tap()
 }
 func testTabletSettingsMenus() throws {
  start(); orient(.landscapeLeft)
  button("Show Sidebar").tap(); button("Settings").tap(); button("General").tap()
  let appearance = button("Appearance"), language = button("Language")
  XCTAssertGreaterThanOrEqual(appearance.frame.height, 44)
  XCTAssertEqual(appearance.frame.height, language.frame.height, accuracy: 1)
  shot("31-settings-general")
  let original = appearance.value as? String ?? "System"
  appearance.tap(); shot("32-settings-appearance-menu"); button(original).tap()
  button("Models").tap()
  XCTAssertTrue(button("Default Model").waitForExistence(timeout: 5))
  XCTAssertEqual(button("Default Model").frame.height, 44, accuracy: 1)
  shot("33-settings-models")
  button("Close").tap()
 }
 func testSettingsKeyboard() throws {
  start(); orient(.landscapeLeft)
  button("Show Sidebar").tap()
  let settings = button("Settings")
  XCTAssertTrue(settings.waitForExistence(timeout: 5)); settings.tap()
  XCTAssertTrue(button("Models").waitForExistence(timeout: 5)); button("Models").tap()
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
  orient(.portrait); if !settings.isHittable { button("Show Sidebar").tap() }; settings.tap(); button("Models").tap(); service.tap(); field.tap()
  XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 8)); shot("10-settings-keyboard-portrait")
  XCTAssertLessThan(close.frame.maxY, app.keyboards.firstMatch.frame.minY)
  close.tap()
  orient(.landscapeLeft)
 }
 func setAppearance(_ choice: String?) -> String {
  start(); orient(.landscapeLeft)
  button("Show Sidebar").tap(); button("Settings").tap(); button("General").tap()
  let appearance = button("Appearance")
  XCTAssertTrue(appearance.waitForExistence(timeout: 5))
  let old = appearance.value as? String ?? "System"
  if let choice, choice != old {
   appearance.tap(); button(choice).tap()
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
   button("Map Only").tap(); button("Actual Size").tap()
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

 func testZZPreparePencil() throws {
  start(); orient(.landscapeLeft); openSample(); button("Source Only").tap(); button("Pen").tap()
  XCTAssertTrue(button("Pen").isSelected)
  shot("34-pencil-ready")
 }

 func testSelectionColorEntryIsSeparateFromMarkerActions() throws {
  start(); orient(.landscapeLeft); openSample(); button("Source Only").tap()
  let document = button("Sample chapter:")
  if !document.isHittable { button("Show Sidebar").tap() }
  XCTAssertTrue(document.waitForExistence(timeout: 5)); document.tap()
  let hideSidebar = button("Hide Sidebar")
  if hideSidebar.exists && hideSidebar.isHittable { hideSidebar.tap() }
  button("Select").tap()
  let line = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "人在学习新知识之后", "在这一页上拖选任意一句话")).firstMatch
  XCTAssertTrue(line.waitForExistence(timeout: 8))
  line.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).press(forDuration: 1.0, thenDragTo: line.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5)))
  let copy = button("Copy")
  XCTAssertTrue(copy.waitForExistence(timeout: 6))
  let rowY = copy.frame.midY
  let color = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "Colors:", "颜色:")).firstMatch
  let highlight = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Highlight", "高亮")).allElementsBoundByIndex.first { $0.isHittable && abs($0.frame.midY - rowY) < 2 }
  let underline = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Underline", "下划线")).allElementsBoundByIndex.first { $0.isHittable && abs($0.frame.midY - rowY) < 2 }
  XCTAssertTrue(color.exists); XCTAssertNotNil(highlight); XCTAssertNotNil(underline)
  XCTAssertLessThan(color.frame.midX, highlight!.frame.midX)
  XCTAssertLessThan(highlight!.frame.midX, underline!.frame.midX)
  let more = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "More Colors", "更多颜色")).firstMatch
  XCTAssertFalse(more.exists)
  color.tap(); XCTAssertTrue(more.waitForExistence(timeout: 5))
  let colors = app.buttons.allElementsBoundByIndex.filter { $0.isHittable && abs($0.frame.midY - more.frame.midY) < 2 }
  XCTAssertEqual(colors.count, 5)
  shot("35-selection-color-entry")
  app.otherElements["tablet-workspace-content"].coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.7)).tap()
  XCTAssertFalse(more.exists)
 }

}
