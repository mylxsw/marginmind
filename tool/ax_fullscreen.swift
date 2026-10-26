import AppKit
import ApplicationServices

// Keep an AX object reference: System Events can re-resolve a fullscreen
// window by application name, which is ambiguous with multiple app builds.
func attribute(_ element: AXUIElement, _ name: String) throws -> CFTypeRef {
  var value: CFTypeRef?
  let result = AXUIElementCopyAttributeValue(element, name as CFString, &value)
  guard result == .success, let value else {
    throw NSError(domain: "AX read \(name)", code: Int(result.rawValue))
  }
  return value
}

do {
  guard CommandLine.arguments.count == 2, let pid = Int32(CommandLine.arguments[1]), pid > 0 else {
    throw NSError(domain: "Positive PID required", code: 1)
  }
  guard let app = NSRunningApplication(processIdentifier: pid) else {
    throw NSError(domain: "Process exited", code: 1)
  }
  app.activate()
  let process = AXUIElementCreateApplication(pid)
  let windows = try attribute(process, kAXWindowsAttribute) as! [AXUIElement]
  guard let window = windows.first else { throw NSError(domain: "No AX window", code: 1) }
  guard !(try attribute(window, "AXFullScreen") as! Bool) else {
    throw NSError(domain: "Start windowed", code: 1)
  }
  for target in [true, false] {
    let error = AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, target ? kCFBooleanTrue : kCFBooleanFalse)
    guard error == .success else { throw NSError(domain: "AX fullscreen write", code: Int(error.rawValue)) }
    var reached = false
    for _ in 0..<100 {
      Thread.sleep(forTimeInterval: 0.05)
      if try attribute(window, "AXFullScreen") as! Bool == target { reached = true; break }
    }
    guard reached else { throw NSError(domain: "Fullscreen timeout", code: 1) }
    Thread.sleep(forTimeInterval: 1.2)
    guard try attribute(window, "AXFullScreen") as! Bool == target else {
      throw NSError(domain: "Fullscreen state changed during animation", code: 1)
    }
  }
  print("true, false")
} catch {
  fputs("\(error)\n", stderr)
  exit(1)
}
