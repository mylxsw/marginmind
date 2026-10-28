import Flutter
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {
  func testKeychainRoundTripAndValidation() {
    let account = "test-" + UUID().uuidString
    func invoke(_ method: String, _ args: [String: Any]) -> Any? {
      var value: Any?
      MobileSecrets.handle(FlutterMethodCall(methodName: method, arguments: args)) { value = $0 }
      return value
    }
    defer { _ = invoke("delete", ["account": account]) }
    XCTAssertNil(invoke("read", ["account": account]))
    XCTAssertNil(invoke("write", ["account": account, "value": "secret"]))
    XCTAssertEqual(invoke("read", ["account": account]) as? String, "secret")
    XCTAssertNil(invoke("write", ["account": account, "value": "updated"]))
    XCTAssertEqual(invoke("read", ["account": account]) as? String, "updated")
    XCTAssertNil(invoke("delete", ["account": account]))
    XCTAssertNil(invoke("read", ["account": account]))
    XCTAssertTrue(invoke("write", ["account": ""]) is FlutterError)
    XCTAssertTrue(invoke("write", ["account": account]) is FlutterError)
  }
}
