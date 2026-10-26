// Native pixel wheel events for the activated benchmark window; no viewer controller.
import AppKit
import ApplicationServices
let pid = Int32(CommandLine.arguments[1])!
let x = Double(CommandLine.arguments[2])!, y = Double(CommandLine.arguments[3])!
let app = NSRunningApplication(processIdentifier: pid)!
app.activate(options: [.activateAllWindows])
let source = CGEventSource(stateID: .hidSystemState)
let point = CGPoint(x: x, y: y)
let originalPoint = CGEvent(source: nil)!.location
defer { CGWarpMouseCursorPosition(originalPoint) }
CGWarpMouseCursorPosition(point)
CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
Thread.sleep(forTimeInterval: 0.5)
let start = Date()
for i in 0..<1800 {
    // 10s continuous down, 10s paused reading (150ms burst each second), 10s up.
    let slow = i >= 600 && i < 1200
    if !slow || i % 60 < 9 {
        let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 1,
            wheel1: i >= 1200 ? 65 : -65, wheel2: 0, wheel3: 0)!
        event.location = point
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
            app.activate(options: [.activateAllWindows])
            Thread.sleep(forTimeInterval: 0.02)
        }
        event.post(tap: .cghidEventTap)
    }
    let wait = Double(i + 1) / 60 - Date().timeIntervalSince(start)
    if wait > 0 { Thread.sleep(forTimeInterval: wait) }
}
