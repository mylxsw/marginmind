// Activate only the benchmark's PID and return its screen rectangle for capture.
import AppKit
import ApplicationServices
let pid = Int32(CommandLine.arguments[1])!
for _ in 0..<30 {
    NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateAllWindows])
    let app = AXUIElementCreateApplication(pid)
    var value: CFTypeRef?
    AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
    if let windows = value as? [AXUIElement], let window = windows.first {
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }
    let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as! [[String: Any]]
    for window in windows where window[kCGWindowOwnerPID as String] as? Int32 == pid {
        if let bounds = window[kCGWindowBounds as String] as? [String: Any],
           let width = bounds["Width"] as? Int, let height = bounds["Height"] as? Int,
           let x = bounds["X"] as? Int, let y = bounds["Y"] as? Int,
           width >= 400 && height >= 300 {
            let scale = Int(NSScreen.main?.backingScaleFactor ?? 1)
            print("\(x * scale),\(y * scale),\(width * scale),\(height * scale)")
            exit(0)
        }
    }
    Thread.sleep(forTimeInterval: 0.5)
}
exit(1)
